! =============================================================================
! dnn_surrogate.f90  --  Lightweight DNN inference for ThermoTwin-F MINLP
!
! Two feedforward networks (weights loaded from dnn_weights.txt at startup):
!
!   HR surrogate   4->32->16->1  ReLU activations, linear output
!     inputs : [load_frac, tamb_C, TIT_K, fouling_pct]
!     output : heat_rate_kJ_kWh  (more accurate than the quadratic polynomial)
!
!   Commit policy  5->32->16->3  Tanh activations, linear output + caller softmax
!     inputs : [hour/24, price/150, demand/120, soc_frac, prev_cs/2]
!     output : logits for [low, mid, high dispatch]
!     use    : dnn_commit_prune() returns a keep_mask to skip DP branches
!
! Call dnn_init("dnn_weights.txt") once at startup (engine_init).
! DNN_ACTIVE remains .false. if the file is missing -- the MINLP then uses
! the original quadratic polynomial as fallback.
!
! Architecture constants and normalization parameters must stay in sync with
! the matching values in train_dnn.py.
! =============================================================================
module dnn_surrogate
    use precision_kinds, only: dp
    implicit none
    private

    ! ─ Public API ─────────────────────────────────────────────────────────────
    public :: dnn_init, dnn_heat_rate, dnn_commit_prune, dnn_commit_probs
    public :: DNN_ACTIVE, DNN_POLICY_ACTIVE, DNN_HR_MAE
    public :: dnn_online_update, dnn_heat_rate_mc

    integer, parameter :: MC_N = 20     ! number of MC-dropout forward passes
    real(dp), parameter :: DROPOUT_KEEP = 0.9_dp  ! keep probability

    ! ─ Architecture (must match train_dnn.py) ─────────────────────────────────
    integer, parameter :: HR_NI  = 4    ! load_frac, tamb_C, TIT_K, fouling_pct
    integer, parameter :: HR_NH1 = 32
    integer, parameter :: HR_NH2 = 16
    integer, parameter :: PL_NI  = 5    ! hour, price, demand, soc, prev_cs
    integer, parameter :: PL_NH1 = 32
    integer, parameter :: PL_NH2 = 16
    integer, parameter :: PL_NO  = 3    ! low / mid / high dispatch

    ! ─ Weights ────────────────────────────────────────────────────────────────
    real(dp) :: hr_W1(HR_NH1, HR_NI),  hr_b1(HR_NH1)
    real(dp) :: hr_W2(HR_NH2, HR_NH1), hr_b2(HR_NH2)
    real(dp) :: hr_W3(HR_NH2),         hr_b3

    real(dp) :: pl_W1(PL_NH1, PL_NI),  pl_b1(PL_NH1)
    real(dp) :: pl_W2(PL_NH2, PL_NH1), pl_b2(PL_NH2)
    real(dp) :: pl_W3(PL_NO,  PL_NH2), pl_b3(PL_NO)

    ! ─ Input/output normalization (must match train_dnn.py) ───────────────────
    real(dp), parameter :: HR_IN_MEAN(HR_NI) = &
        [0.65_dp, 15.0_dp, 1400.0_dp, 3.0_dp]
    real(dp), parameter :: HR_IN_STD(HR_NI)  = &
        [0.25_dp, 20.0_dp, 100.0_dp,  4.0_dp]
    real(dp), parameter :: HR_OUT_MEAN = 11500.0_dp
    real(dp), parameter :: HR_OUT_STD  = 2500.0_dp

    ! ─ Status ─────────────────────────────────────────────────────────────────
    ! DNN_ACTIVE       = HR surrogate loaded; safe to call dnn_heat_rate()
    ! DNN_POLICY_ACTIVE = policy weights also loaded; safe to call dnn_commit_prune()
    ! Keeping them separate prevents dnn_commit_prune() running on zero-initialised
    ! weights if the weight file is truncated after the HR section.
    logical  :: DNN_ACTIVE        = .false.
    logical  :: DNN_POLICY_ACTIVE = .false.
    real(dp) :: DNN_HR_MAE        = 0.0_dp

contains

    ! ─── Activation helpers ───────────────────────────────────────────────────
    elemental function relu(x) result(y)
        real(dp), intent(in) :: x
        real(dp) :: y
        y = max(0.0_dp, x)
    end function relu

    ! ─── HR surrogate forward pass ────────────────────────────────────────────
    ! Returns heat_rate_kJ_kWh for the given operating conditions.
    ! Input fouling_pct is the HR gap % relative to clean (from compute_wash_roi).
    function dnn_heat_rate(load_frac, tamb_c, tit_k, fouling_pct) result(hr)
        real(dp), intent(in) :: load_frac, tamb_c, tit_k, fouling_pct
        real(dp) :: hr
        real(dp) :: x(HR_NI), h1(HR_NH1), h2(HR_NH2)
        integer  :: j

        ! Standardise inputs
        x(1) = (load_frac   - HR_IN_MEAN(1)) / HR_IN_STD(1)
        x(2) = (tamb_c      - HR_IN_MEAN(2)) / HR_IN_STD(2)
        x(3) = (tit_k       - HR_IN_MEAN(3)) / HR_IN_STD(3)
        x(4) = (fouling_pct - HR_IN_MEAN(4)) / HR_IN_STD(4)

        ! Layer 1: HR_NI -> HR_NH1, ReLU
        do j = 1, HR_NH1
            h1(j) = relu(dot_product(hr_W1(j,:), x) + hr_b1(j))
        end do

        ! Layer 2: HR_NH1 -> HR_NH2, ReLU
        do j = 1, HR_NH2
            h2(j) = relu(dot_product(hr_W2(j,:), h1) + hr_b2(j))
        end do

        ! Output layer: HR_NH2 -> 1, linear
        hr = dot_product(hr_W3, h2) + hr_b3

        ! Denormalise and apply physical bounds
        hr = hr * HR_OUT_STD + HR_OUT_MEAN
        hr = max(7000.0_dp, min(30000.0_dp, hr))
    end function dnn_heat_rate

    ! ─── Policy forward pass + branch-pruning mask ───────────────────────────
    ! Returns keep_mask(n_pgt): .false. entries are DP branches the policy
    ! deems negligible (P < THRESH).  Only a thin band is ever pruned;
    ! the DP remains exact on all kept branches.
    subroutine dnn_commit_prune(hour_f, price_n, demand_n, soc_f, prev_n, &
                                n_pgt, keep_mask)
        real(dp), intent(in)  :: hour_f, price_n, demand_n, soc_f, prev_n
        integer,  intent(in)  :: n_pgt
        logical,  intent(out) :: keep_mask(n_pgt)

        real(dp) :: x(PL_NI), h1(PL_NH1), h2(PL_NH2), logits(PL_NO)
        real(dp) :: ex(PL_NO), probs(PL_NO), pf
        integer  :: j, k
        real(dp), parameter :: THRESH = 0.05_dp   ! prune if P < 5%

        x = [hour_f, price_n, demand_n, soc_f, prev_n]

        ! Layer 1: PL_NI -> PL_NH1, tanh
        do j = 1, PL_NH1
            h1(j) = tanh(dot_product(pl_W1(j,:), x) + pl_b1(j))
        end do

        ! Layer 2: PL_NH1 -> PL_NH2, tanh
        do j = 1, PL_NH2
            h2(j) = tanh(dot_product(pl_W2(j,:), h1) + pl_b2(j))
        end do

        ! Output: PL_NH2 -> PL_NO, linear
        do j = 1, PL_NO
            logits(j) = dot_product(pl_W3(j,:), h2) + pl_b3(j)
        end do

        ! Stable softmax
        ex    = exp(logits - maxval(logits))
        probs = ex / sum(ex)

        ! Pruning: probs(1)=low, probs(2)=mid, probs(3)=high
        keep_mask = .true.
        do k = 1, n_pgt
            pf = real(k, dp) / real(n_pgt, dp)
            ! Policy strongly prefers full load -> skip bottom-third dispatch
            if (pf < 0.35_dp .and. probs(1) < THRESH .and. probs(2) < THRESH) then
                keep_mask(k) = .false.
            end if
            ! Policy strongly prefers low/off -> skip top-fifth dispatch
            if (pf > 0.80_dp .and. probs(3) < THRESH) then
                keep_mask(k) = .false.
            end if
        end do
    end subroutine dnn_commit_prune

    ! ─── Policy softmax probabilities (for diagnostics display) ─────────────
    ! Returns raw P(low/off), P(mid), P(high) for the GUI policy confidence bars.
    subroutine dnn_commit_probs(hour_f, price_n, demand_n, soc_f, prev_n, probs)
        real(dp), intent(in)  :: hour_f, price_n, demand_n, soc_f, prev_n
        real(dp), intent(out) :: probs(PL_NO)
        real(dp) :: x(PL_NI), h1(PL_NH1), h2(PL_NH2), logits(PL_NO), ex(PL_NO)
        integer  :: j

        x = [hour_f, price_n, demand_n, soc_f, prev_n]
        do j = 1, PL_NH1
            h1(j) = tanh(dot_product(pl_W1(j,:), x) + pl_b1(j))
        end do
        do j = 1, PL_NH2
            h2(j) = tanh(dot_product(pl_W2(j,:), h1) + pl_b2(j))
        end do
        do j = 1, PL_NO
            logits(j) = dot_product(pl_W3(j,:), h2) + pl_b3(j)
        end do
        ex    = exp(logits - maxval(logits))
        probs = ex / sum(ex)
    end subroutine dnn_commit_probs

    ! ─── Weight file loader ───────────────────────────────────────────────────
    ! Reads dnn_weights.txt (written by train_dnn.py).
    ! Sets DNN_ACTIVE = .true. on success; leaves it .false. on any error
    ! so the caller falls back to the polynomial model transparently.
    subroutine dnn_init(filename)
        character(len=*), intent(in) :: filename
        integer  :: iunit, ios, j
        real(dp) :: mae_tmp
        character(len=256) :: line

        DNN_ACTIVE        = .false.
        DNN_POLICY_ACTIVE = .false.
        DNN_HR_MAE        = 0.0_dp

        open(newunit=iunit, file=trim(filename), status='old', &
             action='read', iostat=ios)
        if (ios /= 0) return   ! file not found -- silent fallback

        ! Skip header comment lines; extract MAE if present
        do
            read(iunit, '(a)', iostat=ios) line
            if (ios /= 0) then; close(iunit); return; end if
            if (line(1:1) /= '#') then; backspace(iunit); exit; end if
            if (index(line, 'HR_MAE_kJkWh:') > 0) then
                read(line(index(line, ':')+1:), *, iostat=ios) mae_tmp
                if (ios == 0) DNN_HR_MAE = mae_tmp
            end if
        end do

        ! ── HR surrogate weights  (4->32->16->1) ─────────────────────────────
        do j = 1, HR_NH1
            read(iunit, *, iostat=ios) hr_W1(j, 1:HR_NI)
            if (ios /= 0) then; close(iunit); return; end if
        end do
        read(iunit, *, iostat=ios) hr_b1(1:HR_NH1)
        if (ios /= 0) then; close(iunit); return; end if

        do j = 1, HR_NH2
            read(iunit, *, iostat=ios) hr_W2(j, 1:HR_NH1)
            if (ios /= 0) then; close(iunit); return; end if
        end do
        read(iunit, *, iostat=ios) hr_b2(1:HR_NH2)
        if (ios /= 0) then; close(iunit); return; end if

        read(iunit, *, iostat=ios) hr_W3(1:HR_NH2)   ! single output row
        if (ios /= 0) then; close(iunit); return; end if
        read(iunit, *, iostat=ios) hr_b3
        if (ios /= 0) then; close(iunit); return; end if

        ! HR loaded -- mark active even if policy is missing
        DNN_ACTIVE = .true.

        ! Skip policy separator comment(s)
        do
            read(iunit, '(a)', iostat=ios) line
            if (ios /= 0) then; close(iunit); return; end if  ! EOF -- HR only
            if (line(1:1) /= '#') then; backspace(iunit); exit; end if
        end do

        ! ── Policy weights  (5->32->16->3) ───────────────────────────────────
        do j = 1, PL_NH1
            read(iunit, *, iostat=ios) pl_W1(j, 1:PL_NI)
            if (ios /= 0) then; close(iunit); return; end if
        end do
        read(iunit, *, iostat=ios) pl_b1(1:PL_NH1)
        if (ios /= 0) then; close(iunit); return; end if

        do j = 1, PL_NH2
            read(iunit, *, iostat=ios) pl_W2(j, 1:PL_NH1)
            if (ios /= 0) then; close(iunit); return; end if
        end do
        read(iunit, *, iostat=ios) pl_b2(1:PL_NH2)
        if (ios /= 0) then; close(iunit); return; end if

        do j = 1, PL_NO
            read(iunit, *, iostat=ios) pl_W3(j, 1:PL_NH2)
            if (ios /= 0) then; close(iunit); return; end if
        end do
        read(iunit, *, iostat=ios) pl_b3(1:PL_NO)
        if (ios /= 0) then; close(iunit); return; end if

        close(iunit)
        DNN_POLICY_ACTIVE = .true.   ! all policy weights loaded
    end subroutine dnn_init

    ! Online adaptation: single gradient step on the output-layer bias (hr_b3).
    ! Corrects for systematic prediction offset using exponential moving average.
    ! GridState fields used: dnn_online_bias, dnn_online_rmse, dnn_online_n,
    !   gt_heat_rate_kJ_kWh (actual), plant_power_MW, fouling_factor, TIT_K, ambient_T_K
    subroutine dnn_online_update(load_frac, tamb_c, tit_k, fouling_pct, actual_hr, &
                                  online_bias, online_rmse, online_n)
        real(dp), intent(in)    :: load_frac, tamb_c, tit_k, fouling_pct, actual_hr
        real(dp), intent(inout) :: online_bias, online_rmse
        integer,  intent(inout) :: online_n
        real(dp), parameter :: LR     = 0.01_dp
        real(dp), parameter :: RMSE_A = 0.05_dp
        real(dp) :: predicted, error

        if (.not. DNN_ACTIVE) return
        predicted = dnn_heat_rate(load_frac, tamb_c, tit_k, fouling_pct) + online_bias
        error     = actual_hr - predicted
        online_bias = online_bias + LR * error
        online_rmse = (1.0_dp - RMSE_A) * online_rmse + RMSE_A * error**2
        online_n    = online_n + 1
        hr_b3 = hr_b3 + LR * error / HR_OUT_STD
    end subroutine dnn_online_update

    ! MC-dropout uncertainty: run MC_N forward passes with 10% dropout on both
    ! hidden layers to obtain a mean and std estimate of heat_rate.
    ! Falls back to zero sigma if DNN not loaded.
    subroutine dnn_heat_rate_mc(load_frac, tamb_c, tit_k, fouling_pct, hr_mean, hr_sigma)
        real(dp), intent(in)  :: load_frac, tamb_c, tit_k, fouling_pct
        real(dp), intent(out) :: hr_mean, hr_sigma

        real(dp) :: samples(MC_N)
        real(dp) :: x(HR_NI), h1(HR_NH1), h2(HR_NH2), hr_out
        real(dp) :: rnd1(HR_NH1), rnd2(HR_NH2), mask1(HR_NH1), mask2(HR_NH2)
        real(dp) :: scale
        real(dp) :: sum_sq
        integer  :: pass, j

        if (.not. DNN_ACTIVE) then
            hr_mean  = dnn_heat_rate(load_frac, tamb_c, tit_k, fouling_pct)
            hr_sigma = 0.0_dp
            return
        end if

        scale = 1.0_dp / DROPOUT_KEEP   ! inverted dropout scaling

        x(1) = (load_frac   - HR_IN_MEAN(1)) / HR_IN_STD(1)
        x(2) = (tamb_c      - HR_IN_MEAN(2)) / HR_IN_STD(2)
        x(3) = (tit_k       - HR_IN_MEAN(3)) / HR_IN_STD(3)
        x(4) = (fouling_pct - HR_IN_MEAN(4)) / HR_IN_STD(4)

        do pass = 1, MC_N
            call random_number(rnd1)
            call random_number(rnd2)
            mask1 = merge(scale, 0.0_dp, rnd1 >= (1.0_dp - DROPOUT_KEEP))
            mask2 = merge(scale, 0.0_dp, rnd2 >= (1.0_dp - DROPOUT_KEEP))

            do j = 1, HR_NH1
                h1(j) = relu(dot_product(hr_W1(j,:), x) + hr_b1(j)) * mask1(j)
            end do
            do j = 1, HR_NH2
                h2(j) = relu(dot_product(hr_W2(j,:), h1) + hr_b2(j)) * mask2(j)
            end do

            hr_out = dot_product(hr_W3, h2) + hr_b3
            hr_out = hr_out * HR_OUT_STD + HR_OUT_MEAN
            hr_out = max(7000.0_dp, min(30000.0_dp, hr_out))
            samples(pass) = hr_out
        end do

        hr_mean = sum(samples) / real(MC_N, dp)
        sum_sq  = sum((samples - hr_mean)**2)
        hr_sigma = sqrt(sum_sq / real(MC_N - 1, dp))
    end subroutine dnn_heat_rate_mc

end module dnn_surrogate
