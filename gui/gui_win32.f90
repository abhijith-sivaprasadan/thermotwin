!> @file gui_win32.f90
!> @brief Native Win32 real-time grid dashboard for ThermoTwin-F.
!>
!> The GUI is written in Fortran and links directly to the ThermoTwin-F solver.
!> It exposes a small electric-grid balancing sandbox around the gas-turbine
!> model: demand, renewable supply, storage and gas dispatch are manipulated in
!> real time, while `solve_cycle` supplies the gas-turbine power figure.
module thermotwin_win32_gui
    use, intrinsic :: iso_c_binding, only: c_associated, c_char, c_float, c_funloc, &
        c_funptr, c_int, c_intptr_t, c_loc, c_long, c_null_char, c_null_ptr, &
        c_ptr, c_sizeof
    use precision_kinds, only: dp
    use constants, only: KELVIN_OFFSET
    use types, only: InputCase, CycleResult
    use cycle_solver, only: solve_cycle
    implicit none
    private

    public :: run_gui

    integer(c_int), parameter :: CW_USEDEFAULT = int(Z'80000000', c_int)
    integer(c_int), parameter :: SW_SHOW = 5_c_int
    integer(c_int), parameter :: WM_CREATE = 1_c_int
    integer(c_int), parameter :: WM_DESTROY = 2_c_int
    integer(c_int), parameter :: WM_ERASEBKGND = 20_c_int
    integer(c_int), parameter :: WM_PAINT = 15_c_int
    integer(c_int), parameter :: WM_KEYDOWN = 256_c_int
    integer(c_int), parameter :: WM_SETFONT = 48_c_int
    integer(c_int), parameter :: WM_COMMAND = 273_c_int
    integer(c_int), parameter :: WM_TIMER = 275_c_int
    integer(c_int), parameter :: WM_HSCROLL = 276_c_int
    integer(c_int), parameter :: WM_MOUSEMOVE = 512_c_int
    integer(c_int), parameter :: WM_LBUTTONDOWN = 513_c_int
    integer(c_int), parameter :: WM_LBUTTONUP = 514_c_int
    integer(c_int), parameter :: WM_USER = 1024_c_int

    integer(c_int), parameter :: WS_OVERLAPPEDWINDOW = int(Z'00CF0000', c_int)
    integer(c_int), parameter :: WS_POPUP = int(Z'80000000', c_int)
    integer(c_int), parameter :: WS_VISIBLE = int(Z'10000000', c_int)
    integer(c_int), parameter :: WS_CHILD = int(Z'40000000', c_int)
    integer(c_int), parameter :: WS_BORDER = int(Z'00800000', c_int)
    integer(c_int), parameter :: BS_PUSHBUTTON = 0_c_int
    integer(c_int), parameter :: TBS_AUTOTICKS = 1_c_int
    integer(c_int), parameter :: COLOR_WINDOW = 5_c_int
    integer(c_int), parameter :: IDC_ARROW = 32512_c_int
    integer(c_int), parameter :: VK_ESCAPE = 27_c_int
    integer(c_int), parameter :: SM_CXSCREEN = 0_c_int
    integer(c_int), parameter :: SM_CYSCREEN = 1_c_int
    integer(c_int), parameter :: SPI_GETWORKAREA = 48_c_int
    integer(c_int), parameter :: TRANSPARENT = 1_c_int
    integer(c_int), parameter :: PS_SOLID = 0_c_int
    integer(c_int), parameter :: SRCCOPY = int(Z'00CC0020', c_int)
    integer(c_int), parameter :: FW_NORMAL = 400_c_int
    integer(c_int), parameter :: FW_SEMIBOLD = 600_c_int
    integer(c_int), parameter :: DEFAULT_CHARSET = 1_c_int
    integer(c_int), parameter :: CLEARTYPE_QUALITY = 5_c_int

    integer(c_int), parameter :: TBM_GETPOS = WM_USER
    integer(c_int), parameter :: TBM_SETPOS = WM_USER + 5_c_int
    integer(c_int), parameter :: TBM_SETRANGE = WM_USER + 6_c_int
    integer(c_int), parameter :: TBM_SETTICFREQ = WM_USER + 20_c_int

    integer(c_int), parameter :: ID_DEMAND = 101_c_int
    integer(c_int), parameter :: ID_RENEWABLE = 102_c_int
    integer(c_int), parameter :: ID_STORAGE = 103_c_int
    integer(c_int), parameter :: ID_GAS = 104_c_int
    integer(c_int), parameter :: ID_AMBIENT = 105_c_int
    integer(c_int), parameter :: ID_TIT = 106_c_int
    integer(c_int), parameter :: ID_AUTO = 201_c_int
    integer(c_int), parameter :: ID_BALANCE = 202_c_int
    integer(c_int), parameter :: ID_RESET = 203_c_int
    integer(c_int), parameter :: ID_NONE = 0_c_int
    integer(c_int), parameter :: TIMER_ID = 1_c_int
    integer(c_int), parameter :: TIMER_MS = 250_c_int
    character(len=*), parameter :: DEBUG_LOG = "gui_debug.log"

    integer(c_int), parameter :: CANVAS_W = 1280_c_int
    integer(c_int), parameter :: CANVAS_H = 940_c_int

    ! OLED-black dark-cockpit palette — COLORREF = 0x00BBGGRR
    integer(c_int), parameter :: COL_BG         = int(Z'00000000', c_int) ! OLED black
    integer(c_int), parameter :: COL_BG_GRID    = int(Z'000C0C0C', c_int) ! barely visible grid
    integer(c_int), parameter :: COL_PANEL      = int(Z'000B0B0B', c_int) ! raised black surface
    integer(c_int), parameter :: COL_PANEL_ALT  = int(Z'00131313', c_int) ! inset instrument face
    integer(c_int), parameter :: COL_PANEL_DEEP = int(Z'00030303', c_int) ! deep black well
    integer(c_int), parameter :: COL_BORDER     = int(Z'00303030', c_int) ! hard border
    integer(c_int), parameter :: COL_BORDER_SOFT= int(Z'001C1C1C', c_int) ! soft divider
    integer(c_int), parameter :: COL_INK        = int(Z'00E8E8E8', c_int) ! primary text
    integer(c_int), parameter :: COL_MUTED      = int(Z'00909090', c_int) ! secondary text
    integer(c_int), parameter :: COL_DIM        = int(Z'00484848', c_int) ! disabled text
    ! Status colours (high-saturation for OLED pop)
    integer(c_int), parameter :: COL_GREEN      = int(Z'0064E800', c_int) ! #00E864
    integer(c_int), parameter :: COL_AMBER      = int(Z'000095FF', c_int) ! #FF9500
    integer(c_int), parameter :: COL_RED        = int(Z'00303BFF', c_int) ! #FF3B30
    ! Informational accents
    integer(c_int), parameter :: COL_BLUE       = int(Z'00FF840A', c_int) ! #0A84FF
    integer(c_int), parameter :: COL_CYAN       = int(Z'00E6AD32', c_int) ! #32ADE6
    integer(c_int), parameter :: COL_LIME       = int(Z'0058D130', c_int) ! #30D158
    ! Gauge anatomy
    integer(c_int), parameter :: COL_BEZEL_RING = int(Z'00323232', c_int) ! outer bezel
    integer(c_int), parameter :: COL_BEZEL_HI   = int(Z'004A4A4A', c_int) ! bezel highlight
    integer(c_int), parameter :: COL_GAUGE_FACE = int(Z'00000000', c_int) ! gauge face (void)
    integer(c_int), parameter :: COL_GAUGE_TRACK= int(Z'000F0F0F', c_int) ! unlit track band
    ! 3-D button shading
    integer(c_int), parameter :: COL_BTN_HI     = int(Z'00545454', c_int) ! top-left highlight
    integer(c_int), parameter :: COL_BTN_SH     = int(Z'00000000', c_int) ! bottom-right shadow
    integer(c_int), parameter :: COL_BTN_BODY   = int(Z'000D0D0D', c_int) ! inactive button body

    real(dp), parameter :: DEMAND_MIN_MW = 10.0_dp
    real(dp), parameter :: DEMAND_MAX_MW = 100.0_dp
    real(dp), parameter :: RENEWABLE_MAX_MW = 60.0_dp
    real(dp), parameter :: STORAGE_MIN_MW = -20.0_dp
    real(dp), parameter :: STORAGE_MAX_MW = 20.0_dp
    real(dp), parameter :: BATTERY_CAPACITY_MWH = 30.0_dp
    real(dp), parameter :: BATTERY_INITIAL_SOC_PCT = 50.0_dp
    real(dp), parameter :: BATTERY_EFFICIENCY = 0.92_dp
    real(dp), parameter :: POWER_PRICE_USD_MWH = 95.0_dp
    real(dp), parameter :: FUEL_PRICE_USD_GJ = 7.5_dp
    real(dp), parameter :: STORAGE_CYCLE_COST_USD_MWH = 8.0_dp
    real(dp), parameter :: IMBALANCE_PENALTY_USD_MWH = 250.0_dp
    real(dp), parameter :: BATTERY_CAPEX_USD_MWH = 180000.0_dp
    real(dp), parameter :: ROI_EQUIVALENT_HOURS_PER_YEAR = 2200.0_dp
    real(dp), parameter :: CO2_KG_PER_KG_FUEL = 2.75_dp
    ! Grid frequency physics — ENTSO-E 50 Hz
    real(dp), parameter :: FREQ_NOMINAL_HZ   = 50.0_dp
    real(dp), parameter :: INERTIA_MWs       = 25.0_dp   ! swing-equation M_eff
    real(dp), parameter :: GOVERNOR_DROOP_R  = 0.05_dp   ! 5 % droop
    real(dp), parameter :: BESS_PRIMARY_GAIN = 5.0_dp    ! MW/Hz primary response
    real(dp), parameter :: BESS_PRIMARY_DB   = 0.02_dp   ! Hz dead-band
    real(dp), parameter :: UFLS_THRESH_1     = 49.0_dp   ! ENTSO-E stage 1
    real(dp), parameter :: UFLS_THRESH_2     = 48.7_dp   ! stage 2
    real(dp), parameter :: UFLS_THRESH_3     = 48.4_dp   ! stage 3
    real(dp), parameter :: UFLS_RESET        = 49.5_dp   ! latch reset
    real(dp), parameter :: UFLS_SHED_PCT     = 0.10_dp   ! 10 % per stage
    real(dp), parameter :: PI_DP             = 3.14159265358979323846_dp
    real(dp), parameter :: GAS_MIN_PCT = 20.0_dp
    real(dp), parameter :: GAS_MAX_PCT = 100.0_dp
    real(dp), parameter :: GAS_RAMP_PCT_PER_S = 18.0_dp
    real(dp), parameter :: BESS_RAMP_MW_PER_S = 4.0_dp
    real(dp), parameter :: CURTAIL_RAMP_MW_PER_S = 10.0_dp  ! inverter-fast
    real(dp), parameter :: LFSM_O_THRESH_HZ = 50.2_dp       ! ENTSO-E RfG
    real(dp), parameter :: LFSM_O_DROOP = 0.05_dp
    integer, parameter :: HISTORY_N = 240

    type, bind(C) :: Point
        integer(c_long) :: x
        integer(c_long) :: y
    end type Point

    type, bind(C) :: Rect
        integer(c_long) :: left
        integer(c_long) :: top
        integer(c_long) :: right
        integer(c_long) :: bottom
    end type Rect

    type, bind(C) :: Msg
        type(c_ptr) :: hwnd
        integer(c_int) :: message
        integer(c_intptr_t) :: wParam
        integer(c_intptr_t) :: lParam
        integer(c_int) :: time
        type(Point) :: pt
    end type Msg

    type, bind(C) :: PaintStruct
        type(c_ptr) :: hdc
        integer(c_int) :: fErase
        type(Rect) :: rcPaint
        integer(c_int) :: fRestore
        integer(c_int) :: fIncUpdate
        character(kind=c_char) :: rgbReserved(32)
    end type PaintStruct

    type, bind(C) :: WndClassExA
        integer(c_int) :: cbSize
        integer(c_int) :: style
        type(c_funptr) :: lpfnWndProc
        integer(c_int) :: cbClsExtra
        integer(c_int) :: cbWndExtra
        type(c_ptr) :: hInstance
        type(c_ptr) :: hIcon
        type(c_ptr) :: hCursor
        type(c_ptr) :: hbrBackground
        type(c_ptr) :: lpszMenuName
        type(c_ptr) :: lpszClassName
        type(c_ptr) :: hIconSm
    end type WndClassExA

    type :: GridState
        real(dp) :: demand_MW = 35.0_dp
        real(dp) :: renewable_MW = 12.0_dp
        real(dp) :: storage_request_MW = 0.0_dp
        real(dp) :: storage_MW = 0.0_dp
        real(dp) :: battery_energy_MWh = BATTERY_CAPACITY_MWH * BATTERY_INITIAL_SOC_PCT / 100.0_dp
        real(dp) :: battery_soc_pct = BATTERY_INITIAL_SOC_PCT
        real(dp) :: gas_dispatch_pct = 82.0_dp
        real(dp) :: ambient_C = 15.0_dp
        real(dp) :: TIT_K = 1400.0_dp
        real(dp) :: gas_power_MW = 0.0_dp
        real(dp) :: gas_capacity_MW = 0.0_dp
        real(dp) :: supply_MW = 0.0_dp
        real(dp) :: imbalance_MW = 0.0_dp
        real(dp) :: reserve_MW = 0.0_dp
        real(dp) :: frequency_Hz = 50.0_dp
        real(dp) :: heat_rate_kJ_kWh = 0.0_dp
        real(dp) :: exhaust_K = 0.0_dp
        real(dp) :: fuel_flow_kg_s = 0.0_dp
        real(dp) :: heat_input_MW = 0.0_dp
        real(dp) :: revenue_usd_h = 0.0_dp
        real(dp) :: fuel_cost_usd_h = 0.0_dp
        real(dp) :: storage_cost_usd_h = 0.0_dp
        real(dp) :: imbalance_penalty_usd_h = 0.0_dp
        real(dp) :: margin_usd_h = 0.0_dp
        real(dp) :: battery_value_usd_h = 0.0_dp
        real(dp) :: battery_payback_years = 0.0_dp
        real(dp) :: elapsed_s = 0.0_dp
        real(dp) :: CO2_rate_kg_s = 0.0_dp
        real(dp) :: CO2_intensity_g_kWh = 0.0_dp
        real(dp) :: CO2_cumulative_t = 0.0_dp
        ! Dynamic frequency model fields
        real(dp) :: ROCOF_Hz_s = 0.0_dp
        real(dp) :: governor_delta_MW = 0.0_dp
        real(dp) :: BESS_primary_MW = 0.0_dp
        real(dp) :: UFLS_shed_fraction = 0.0_dp
        integer  :: UFLS_stage = 0
        ! Renewable dispatch: slider sets the AVAILABLE (weather) ceiling;
        ! AGC may curtail below it, LFSM-O trims it during over-frequency
        real(dp) :: renewable_curtail_MW = 0.0_dp
        real(dp) :: renewable_lfsmo_MW = 0.0_dp
        ! Alarm state flags (drives annunciator tiles)
        logical  :: alarm_underfreq    = .false.
        logical  :: alarm_overfreq     = .false.
        logical  :: alarm_low_reserve  = .false.
        logical  :: alarm_low_soc      = .false.
        logical  :: alarm_ufls_active  = .false.
        logical  :: alarm_turbine_max  = .false.
        integer :: history_count = 0
        integer :: history_head = 0
        real(dp) :: hist_frequency_Hz(HISTORY_N) = 50.0_dp
        real(dp) :: hist_demand_MW(HISTORY_N) = 35.0_dp
        real(dp) :: hist_gas_dispatch_pct(HISTORY_N) = 82.0_dp
        logical :: auto_balance = .true.
    end type GridState

    interface
        subroutine InitCommonControls() bind(C, name="InitCommonControls")
        end subroutine InitCommonControls

        function GetModuleHandleA(lpModuleName) bind(C, name="GetModuleHandleA") result(hModule)
            import :: c_ptr
            type(c_ptr), value :: lpModuleName
            type(c_ptr) :: hModule
        end function GetModuleHandleA

        function LoadCursorA(hInstance, lpCursorName) bind(C, name="LoadCursorA") result(hCursor)
            import :: c_ptr
            type(c_ptr), value :: hInstance
            type(c_ptr), value :: lpCursorName
            type(c_ptr) :: hCursor
        end function LoadCursorA

        function GetSysColorBrush(nIndex) bind(C, name="GetSysColorBrush") result(hBrush)
            import :: c_int, c_ptr
            integer(c_int), value :: nIndex
            type(c_ptr) :: hBrush
        end function GetSysColorBrush

        function SetProcessDPIAware() bind(C, name="SetProcessDPIAware") result(ok)
            import :: c_int
            integer(c_int) :: ok
        end function SetProcessDPIAware

        function GetSystemMetrics(nIndex) bind(C, name="GetSystemMetrics") result(value)
            import :: c_int
            integer(c_int), value :: nIndex
            integer(c_int) :: value
        end function GetSystemMetrics

        function SystemParametersInfoA(uiAction, uiParam, pvParam, fWinIni) &
                bind(C, name="SystemParametersInfoA") result(ok)
            import :: c_int, c_ptr
            integer(c_int), value :: uiAction
            integer(c_int), value :: uiParam
            type(c_ptr), value :: pvParam
            integer(c_int), value :: fWinIni
            integer(c_int) :: ok
        end function SystemParametersInfoA

        function RegisterClassExA(lpwcx) bind(C, name="RegisterClassExA") result(atom)
            import :: c_int, WndClassExA
            type(WndClassExA), intent(in) :: lpwcx
            integer(c_int) :: atom
        end function RegisterClassExA

        function CreateWindowExA(dwExStyle, lpClassName, lpWindowName, dwStyle, &
                x, y, nWidth, nHeight, hWndParent, hMenu, hInstance, lpParam) &
                bind(C, name="CreateWindowExA") result(hwnd)
            import :: c_int, c_ptr
            integer(c_int), value :: dwExStyle
            type(c_ptr), value :: lpClassName
            type(c_ptr), value :: lpWindowName
            integer(c_int), value :: dwStyle
            integer(c_int), value :: x
            integer(c_int), value :: y
            integer(c_int), value :: nWidth
            integer(c_int), value :: nHeight
            type(c_ptr), value :: hWndParent
            type(c_ptr), value :: hMenu
            type(c_ptr), value :: hInstance
            type(c_ptr), value :: lpParam
            type(c_ptr) :: hwnd
        end function CreateWindowExA

        function DefWindowProcA(hwnd, msg, wParam, lParam) bind(C, name="DefWindowProcA") result(lres)
            import :: c_int, c_intptr_t, c_ptr
            type(c_ptr), value :: hwnd
            integer(c_int), value :: msg
            integer(c_intptr_t), value :: wParam
            integer(c_intptr_t), value :: lParam
            integer(c_intptr_t) :: lres
        end function DefWindowProcA

        function DestroyWindow(hwnd) bind(C, name="DestroyWindow") result(ok)
            import :: c_int, c_ptr
            type(c_ptr), value :: hwnd
            integer(c_int) :: ok
        end function DestroyWindow

        function ShowWindow(hwnd, nCmdShow) bind(C, name="ShowWindow") result(ok)
            import :: c_int, c_ptr
            type(c_ptr), value :: hwnd
            integer(c_int), value :: nCmdShow
            integer(c_int) :: ok
        end function ShowWindow

        function SetForegroundWindow(hwnd) bind(C, name="SetForegroundWindow") result(ok)
            import :: c_int, c_ptr
            type(c_ptr), value :: hwnd
            integer(c_int) :: ok
        end function SetForegroundWindow

        function UpdateWindow(hwnd) bind(C, name="UpdateWindow") result(ok)
            import :: c_int, c_ptr
            type(c_ptr), value :: hwnd
            integer(c_int) :: ok
        end function UpdateWindow

        function GetClientRect(hwnd, lpRect) bind(C, name="GetClientRect") result(ok)
            import :: c_int, c_ptr, Rect
            type(c_ptr), value :: hwnd
            type(Rect), intent(out) :: lpRect
            integer(c_int) :: ok
        end function GetClientRect

        function GetMessageA(lpMsg, hWnd, wMsgFilterMin, wMsgFilterMax) bind(C, name="GetMessageA") result(ok)
            import :: c_int, c_ptr, Msg
            type(Msg), intent(out) :: lpMsg
            type(c_ptr), value :: hWnd
            integer(c_int), value :: wMsgFilterMin
            integer(c_int), value :: wMsgFilterMax
            integer(c_int) :: ok
        end function GetMessageA

        function TranslateMessage(lpMsg) bind(C, name="TranslateMessage") result(ok)
            import :: c_int, Msg
            type(Msg), intent(in) :: lpMsg
            integer(c_int) :: ok
        end function TranslateMessage

        function DispatchMessageA(lpMsg) bind(C, name="DispatchMessageA") result(lres)
            import :: c_intptr_t, Msg
            type(Msg), intent(in) :: lpMsg
            integer(c_intptr_t) :: lres
        end function DispatchMessageA

        subroutine PostQuitMessage(nExitCode) bind(C, name="PostQuitMessage")
            import :: c_int
            integer(c_int), value :: nExitCode
        end subroutine PostQuitMessage

        function SetWindowTextA(hwnd, lpString) bind(C, name="SetWindowTextA") result(ok)
            import :: c_int, c_ptr
            type(c_ptr), value :: hwnd
            type(c_ptr), value :: lpString
            integer(c_int) :: ok
        end function SetWindowTextA

        function SetCapture(hwnd) bind(C, name="SetCapture") result(previous)
            import :: c_ptr
            type(c_ptr), value :: hwnd
            type(c_ptr) :: previous
        end function SetCapture

        function ReleaseCapture() bind(C, name="ReleaseCapture") result(ok)
            import :: c_int
            integer(c_int) :: ok
        end function ReleaseCapture

        function MessageBoxA(hWnd, lpText, lpCaption, uType) bind(C, name="MessageBoxA") result(choice)
            import :: c_int, c_ptr
            type(c_ptr), value :: hWnd
            type(c_ptr), value :: lpText
            type(c_ptr), value :: lpCaption
            integer(c_int), value :: uType
            integer(c_int) :: choice
        end function MessageBoxA

        function SendMessageA(hwnd, msg, wParam, lParam) bind(C, name="SendMessageA") result(lres)
            import :: c_int, c_intptr_t, c_ptr
            type(c_ptr), value :: hwnd
            integer(c_int), value :: msg
            integer(c_intptr_t), value :: wParam
            integer(c_intptr_t), value :: lParam
            integer(c_intptr_t) :: lres
        end function SendMessageA

        function SetTimer(hwnd, nIDEvent, uElapse, lpTimerFunc) bind(C, name="SetTimer") result(timer_id)
            import :: c_int, c_intptr_t, c_ptr
            type(c_ptr), value :: hwnd
            integer(c_intptr_t), value :: nIDEvent
            integer(c_int), value :: uElapse
            type(c_ptr), value :: lpTimerFunc
            integer(c_intptr_t) :: timer_id
        end function SetTimer

        function KillTimer(hwnd, uIDEvent) bind(C, name="KillTimer") result(ok)
            import :: c_int, c_intptr_t, c_ptr
            type(c_ptr), value :: hwnd
            integer(c_intptr_t), value :: uIDEvent
            integer(c_int) :: ok
        end function KillTimer

        function InvalidateRect(hwnd, lpRect, bErase) bind(C, name="InvalidateRect") result(ok)
            import :: c_int, c_ptr
            type(c_ptr), value :: hwnd
            type(c_ptr), value :: lpRect
            integer(c_int), value :: bErase
            integer(c_int) :: ok
        end function InvalidateRect

        function BeginPaint(hwnd, lpPaint) bind(C, name="BeginPaint") result(hdc)
            import :: c_ptr, PaintStruct
            type(c_ptr), value :: hwnd
            type(PaintStruct), intent(out) :: lpPaint
            type(c_ptr) :: hdc
        end function BeginPaint

        function EndPaint(hwnd, lpPaint) bind(C, name="EndPaint") result(ok)
            import :: c_int, c_ptr, PaintStruct
            type(c_ptr), value :: hwnd
            type(PaintStruct), intent(in) :: lpPaint
            integer(c_int) :: ok
        end function EndPaint

        function CreateSolidBrush(color) bind(C, name="CreateSolidBrush") result(hBrush)
            import :: c_int, c_ptr
            integer(c_int), value :: color
            type(c_ptr) :: hBrush
        end function CreateSolidBrush

        function FillRect(hdc, lprc, hbr) bind(C, name="FillRect") result(ok)
            import :: c_int, c_ptr, Rect
            type(c_ptr), value :: hdc
            type(Rect), intent(in) :: lprc
            type(c_ptr), value :: hbr
            integer(c_int) :: ok
        end function FillRect

        function DeleteObject(hObject) bind(C, name="DeleteObject") result(ok)
            import :: c_int, c_ptr
            type(c_ptr), value :: hObject
            integer(c_int) :: ok
        end function DeleteObject

        function DeleteDC(hdc) bind(C, name="DeleteDC") result(ok)
            import :: c_int, c_ptr
            type(c_ptr), value :: hdc
            integer(c_int) :: ok
        end function DeleteDC

        function CreateCompatibleDC(hdc) bind(C, name="CreateCompatibleDC") result(memdc)
            import :: c_ptr
            type(c_ptr), value :: hdc
            type(c_ptr) :: memdc
        end function CreateCompatibleDC

        function CreateCompatibleBitmap(hdc, cx, cy) bind(C, name="CreateCompatibleBitmap") result(bitmap)
            import :: c_int, c_ptr
            type(c_ptr), value :: hdc
            integer(c_int), value :: cx
            integer(c_int), value :: cy
            type(c_ptr) :: bitmap
        end function CreateCompatibleBitmap

        function BitBlt(hdc, x, y, cx, cy, hdcSrc, x1, y1, rop) bind(C, name="BitBlt") result(ok)
            import :: c_int, c_ptr
            type(c_ptr), value :: hdc
            integer(c_int), value :: x
            integer(c_int), value :: y
            integer(c_int), value :: cx
            integer(c_int), value :: cy
            type(c_ptr), value :: hdcSrc
            integer(c_int), value :: x1
            integer(c_int), value :: y1
            integer(c_int), value :: rop
            integer(c_int) :: ok
        end function BitBlt

        function CreatePen(fnPenStyle, nWidth, crColor) bind(C, name="CreatePen") result(hPen)
            import :: c_int, c_ptr
            integer(c_int), value :: fnPenStyle
            integer(c_int), value :: nWidth
            integer(c_int), value :: crColor
            type(c_ptr) :: hPen
        end function CreatePen

        function SelectObject(hdc, hObject) bind(C, name="SelectObject") result(oldObject)
            import :: c_ptr
            type(c_ptr), value :: hdc
            type(c_ptr), value :: hObject
            type(c_ptr) :: oldObject
        end function SelectObject

        function MoveToEx(hdc, x, y, lppt) bind(C, name="MoveToEx") result(ok)
            import :: c_int, c_ptr
            type(c_ptr), value :: hdc
            integer(c_int), value :: x
            integer(c_int), value :: y
            type(c_ptr), value :: lppt
            integer(c_int) :: ok
        end function MoveToEx

        function LineTo(hdc, x, y) bind(C, name="LineTo") result(ok)
            import :: c_int, c_ptr
            type(c_ptr), value :: hdc
            integer(c_int), value :: x
            integer(c_int), value :: y
            integer(c_int) :: ok
        end function LineTo

        function SetTextColor(hdc, color) bind(C, name="SetTextColor") result(old)
            import :: c_int, c_ptr
            type(c_ptr), value :: hdc
            integer(c_int), value :: color
            integer(c_int) :: old
        end function SetTextColor

        function SetBkMode(hdc, mode) bind(C, name="SetBkMode") result(old)
            import :: c_int, c_ptr
            type(c_ptr), value :: hdc
            integer(c_int), value :: mode
            integer(c_int) :: old
        end function SetBkMode

        function TextOutA(hdc, x, y, lpString, cch) bind(C, name="TextOutA") result(ok)
            import :: c_int, c_ptr
            type(c_ptr), value :: hdc
            integer(c_int), value :: x
            integer(c_int), value :: y
            type(c_ptr), value :: lpString
            integer(c_int), value :: cch
            integer(c_int) :: ok
        end function TextOutA

        function CreateFontA(cHeight, cWidth, cEscapement, cOrientation, cWeight, &
                bItalic, bUnderline, bStrikeOut, iCharSet, iOutPrecision, &
                iClipPrecision, iQuality, iPitchAndFamily, pszFaceName) &
                bind(C, name="CreateFontA") result(hFont)
            import :: c_int, c_ptr
            integer(c_int), value :: cHeight
            integer(c_int), value :: cWidth
            integer(c_int), value :: cEscapement
            integer(c_int), value :: cOrientation
            integer(c_int), value :: cWeight
            integer(c_int), value :: bItalic
            integer(c_int), value :: bUnderline
            integer(c_int), value :: bStrikeOut
            integer(c_int), value :: iCharSet
            integer(c_int), value :: iOutPrecision
            integer(c_int), value :: iClipPrecision
            integer(c_int), value :: iQuality
            integer(c_int), value :: iPitchAndFamily
            type(c_ptr), value :: pszFaceName
            type(c_ptr) :: hFont
        end function CreateFontA

        function hmi_native_init() bind(C, name="hmi_native_init") result(ok)
            import :: c_int
            integer(c_int) :: ok
        end function hmi_native_init

        subroutine hmi_native_shutdown() bind(C, name="hmi_native_shutdown")
        end subroutine hmi_native_shutdown

        subroutine hmi_fill_rect(hdc, left, top, right, bottom, color) bind(C, name="hmi_fill_rect")
            import :: c_int, c_ptr
            type(c_ptr), value :: hdc
            integer(c_int), value :: left, top, right, bottom, color
        end subroutine hmi_fill_rect

        subroutine hmi_fill_round_rect(hdc, left, top, right, bottom, radius, color) &
                bind(C, name="hmi_fill_round_rect")
            import :: c_int, c_ptr
            type(c_ptr), value :: hdc
            integer(c_int), value :: left, top, right, bottom, radius, color
        end subroutine hmi_fill_round_rect

        subroutine hmi_stroke_rect(hdc, left, top, right, bottom, color, width) bind(C, name="hmi_stroke_rect")
            import :: c_int, c_ptr
            type(c_ptr), value :: hdc
            integer(c_int), value :: left, top, right, bottom, color, width
        end subroutine hmi_stroke_rect

        subroutine hmi_stroke_round_rect(hdc, left, top, right, bottom, radius, color, width) &
                bind(C, name="hmi_stroke_round_rect")
            import :: c_int, c_ptr
            type(c_ptr), value :: hdc
            integer(c_int), value :: left, top, right, bottom, radius, color, width
        end subroutine hmi_stroke_round_rect

        subroutine hmi_draw_line(hdc, x1, y1, x2, y2, color, width) bind(C, name="hmi_draw_line")
            import :: c_int, c_ptr
            type(c_ptr), value :: hdc
            integer(c_int), value :: x1, y1, x2, y2, color, width
        end subroutine hmi_draw_line

        subroutine hmi_draw_text_native(hdc, x, y, lpString, pixel_size, weight, color) &
                bind(C, name="hmi_draw_text")
            import :: c_int, c_ptr
            type(c_ptr), value :: hdc
            integer(c_int), value :: x, y
            type(c_ptr), value :: lpString
            integer(c_int), value :: pixel_size, weight, color
        end subroutine hmi_draw_text_native

        subroutine hmi_fill_pie(hdc, cx, cy, radius, start_deg, sweep_deg, color) &
                bind(C, name="hmi_fill_pie")
            import :: c_int, c_float, c_ptr
            type(c_ptr), value :: hdc
            integer(c_int), value :: cx, cy, radius, color
            real(c_float), value :: start_deg, sweep_deg
        end subroutine hmi_fill_pie

        subroutine hmi_draw_arc(hdc, cx, cy, radius, start_deg, sweep_deg, color, width) &
                bind(C, name="hmi_draw_arc")
            import :: c_int, c_float, c_ptr
            type(c_ptr), value :: hdc
            integer(c_int), value :: cx, cy, radius, color, width
            real(c_float), value :: start_deg, sweep_deg
        end subroutine hmi_draw_arc

        subroutine hmi_draw_polygon(hdc, xs, ys, n_pts, fill_color, stroke_color, stroke_width) &
                bind(C, name="hmi_draw_polygon")
            import :: c_int, c_ptr
            type(c_ptr), value :: hdc
            type(c_ptr), value :: xs, ys
            integer(c_int), value :: n_pts, fill_color, stroke_color, stroke_width
        end subroutine hmi_draw_polygon
    end interface

    type(c_ptr) :: h_instance = c_null_ptr
    type(c_ptr) :: h_main = c_null_ptr
    type(c_ptr) :: h_font_ui = c_null_ptr
    type(c_ptr) :: h_font_title = c_null_ptr
    integer(c_int) :: active_control = ID_NONE
    type(GridState) :: grid
    integer :: layout_canvas_w = int(CANVAS_W)
    integer :: layout_canvas_h = int(CANVAS_H)
    integer :: layout_margin = 20
    integer :: layout_gap = 18
    integer :: layout_control_left = 20
    integer :: layout_control_top = 20
    integer :: layout_control_w = 330
    integer :: layout_control_bottom = 878
    integer :: layout_slider_x = 46
    integer :: layout_slider_w = 270
    integer :: layout_slider_y(6) = [132, 218, 304, 390, 476, 562]
    integer :: layout_button_y = 682
    integer :: layout_footer_y = 820
    integer :: layout_main_left = 374
    integer :: layout_main_top = 20
    integer :: layout_main_w = 862
    integer :: layout_main_h = 858
    logical :: native_renderer_ready = .false.

contains

    subroutine run_gui()
        type(WndClassExA) :: wc
        type(Msg) :: message
        type(c_ptr) :: hwnd
        type(Rect), target :: work_area
        character(kind=c_char), allocatable, target :: class_name(:)
        character(kind=c_char), allocatable, target :: title(:)
        character(len=128) :: logline
        integer(c_int) :: atom, ok, screen_x, screen_y, screen_w, screen_h
        integer(c_intptr_t) :: lres

        call reset_debug_log()
        call log_debug("startup: entering run_gui")
        ok = SetProcessDPIAware()
        call log_debug("startup: requested DPI-aware drawing")
        call InitCommonControls()
        call log_debug("startup: InitCommonControls returned")
        native_renderer_ready = hmi_native_init() /= 0_c_int
        if (native_renderer_ready) then
            call log_debug("startup: native C++ renderer initialized")
        else
            call log_debug("startup: native C++ renderer unavailable; using GDI fallback")
        end if
        call make_c_string("ThermoTwinFGridDashboard", class_name)
        call make_c_string("ThermoTwin-F Grid Balancer", title)

        h_instance = GetModuleHandleA(c_null_ptr)
        call log_debug("startup: acquired module handle")

        wc%cbSize = int(c_sizeof(wc), c_int)
        wc%style = 0_c_int
        wc%lpfnWndProc = c_funloc(window_proc)
        wc%cbClsExtra = 0_c_int
        wc%cbWndExtra = 0_c_int
        wc%hInstance = h_instance
        wc%hIcon = c_null_ptr
        wc%hCursor = LoadCursorA(c_null_ptr, int_to_cptr(IDC_ARROW))
        wc%hbrBackground = GetSysColorBrush(COLOR_WINDOW)
        wc%lpszMenuName = c_null_ptr
        wc%lpszClassName = c_loc(class_name)
        wc%hIconSm = c_null_ptr

        atom = RegisterClassExA(wc)
        if (atom == 0_c_int) then
            call fatal_gui("Could not register ThermoTwin-F GUI window class.")
            stop
        end if
        call log_debug("startup: registered window class")

        screen_x = 0_c_int
        screen_y = 0_c_int
        ok = SystemParametersInfoA(SPI_GETWORKAREA, 0_c_int, c_loc(work_area), 0_c_int)
        if (ok /= 0_c_int) then
            screen_x = int(work_area%left, c_int)
            screen_y = int(work_area%top, c_int)
            screen_w = int(work_area%right - work_area%left, c_int)
            screen_h = int(work_area%bottom - work_area%top, c_int)
        else
            screen_w = GetSystemMetrics(SM_CXSCREEN)
            screen_h = GetSystemMetrics(SM_CYSCREEN)
        end if
        if (screen_w < 1024_c_int) screen_w = CANVAS_W
        if (screen_h < 720_c_int) screen_h = CANVAS_H
        write(logline, '("startup: work-area client target ",I0,",",I0," ",I0,"x",I0," ENTSO-E 50Hz")') &
            screen_x, screen_y, screen_w, screen_h
        call log_debug(trim(logline))

        hwnd = CreateWindowExA(0_c_int, c_loc(class_name), c_loc(title), &
            WS_POPUP + WS_VISIBLE, screen_x, screen_y, &
            screen_w, screen_h, c_null_ptr, c_null_ptr, h_instance, c_null_ptr)
        if (.not. c_associated(hwnd)) then
            call fatal_gui("Could not create ThermoTwin-F GUI window.")
            stop
        end if
        call log_debug("startup: created main window")

        ok = ShowWindow(hwnd, SW_SHOW)
        ok = SetForegroundWindow(hwnd)
        ok = UpdateWindow(hwnd)
        call log_debug("startup: entering message loop")

        do while (GetMessageA(message, c_null_ptr, 0_c_int, 0_c_int) > 0_c_int)
            ok = TranslateMessage(message)
            lres = DispatchMessageA(message)
        end do

        if (ok < 0_c_int .and. lres == -1_c_intptr_t) then
            call fatal_gui("ThermoTwin-F GUI message loop failed.")
            stop
        end if
        call log_debug("shutdown: message loop exited")
    end subroutine run_gui

    recursive function window_proc(hwnd, msg, wParam, lParam) bind(C) result(lres)
        type(c_ptr), value :: hwnd
        integer(c_int), value :: msg
        integer(c_intptr_t), value :: wParam
        integer(c_intptr_t), value :: lParam
        integer(c_intptr_t) :: lres
        type(PaintStruct) :: ps
        type(c_ptr) :: hdc
        integer(c_int) :: ok

        select case (msg)
        case (WM_CREATE)
            call log_debug("message: WM_CREATE")
            h_main = hwnd
            call init_fonts()
            call create_controls(hwnd)
            call refresh_model()
            call append_history()
            lres = SetTimer(hwnd, int(TIMER_ID, c_intptr_t), TIMER_MS, c_null_ptr)
            call log_debug("message: WM_CREATE complete")
            lres = 0_c_intptr_t
            return

        case (WM_HSCROLL)
            call refresh_model()
            call invalidate_dashboard(hwnd)
            lres = 0_c_intptr_t
            return

        case (WM_COMMAND)
            call handle_command(loword(wParam))
            call invalidate_dashboard(hwnd)
            lres = 0_c_intptr_t
            return

        case (WM_TIMER)
            block
                real(dp) :: dt_s
                dt_s = real(TIMER_MS, dp) / 1000.0_dp
                grid%elapsed_s = grid%elapsed_s + dt_s
                call tick_auto_balance(dt_s)         ! AGC secondary ramp
                call refresh_model()                  ! recompute gas power, imbalance, economics
                call update_battery_soc(dt_s)         ! SOC tracking
                call tick_frequency_dynamics(dt_s)    ! swing eq + governor + BESS primary + UFLS
                grid%CO2_cumulative_t = grid%CO2_cumulative_t + &
                    grid%CO2_rate_kg_s * dt_s / 1000.0_dp
                call append_history()
                call invalidate_dashboard(hwnd)
            end block
            lres = 0_c_intptr_t
            return

        case (WM_LBUTTONDOWN)
            call handle_mouse_down(hwnd, mouse_x(lParam), mouse_y(lParam))
            call invalidate_dashboard(hwnd)
            lres = 0_c_intptr_t
            return

        case (WM_MOUSEMOVE)
            if (active_control /= ID_NONE) then
                call update_active_slider(mouse_x(lParam))
                call refresh_model()
                call invalidate_dashboard(hwnd)
            end if
            lres = 0_c_intptr_t
            return

        case (WM_LBUTTONUP)
            call handle_mouse_up()
            call invalidate_dashboard(hwnd)
            lres = 0_c_intptr_t
            return

        case (WM_KEYDOWN)
            if (wParam == int(VK_ESCAPE, c_intptr_t)) then
                ok = DestroyWindow(hwnd)
                lres = 0_c_intptr_t
                return
            end if

        case (WM_ERASEBKGND)
            lres = 1_c_intptr_t
            return

        case (WM_PAINT)
            hdc = BeginPaint(hwnd, ps)
            call draw_dashboard_buffered(hwnd, hdc)
            ok = EndPaint(hwnd, ps)
            lres = 0_c_intptr_t
            return

        case (WM_DESTROY)
            call log_debug("message: WM_DESTROY")
            ok = KillTimer(hwnd, int(TIMER_ID, c_intptr_t))
            call destroy_fonts()
            if (native_renderer_ready) call hmi_native_shutdown()
            native_renderer_ready = .false.
            call PostQuitMessage(0_c_int)
            lres = 0_c_intptr_t
            return
        end select

        lres = DefWindowProcA(hwnd, msg, wParam, lParam)
    end function window_proc

    subroutine create_controls(parent)
        type(c_ptr), value :: parent
        if (.not. c_associated(parent)) return
        call log_debug("controls: custom-drawn UI active")
    end subroutine create_controls

    subroutine init_fonts()
        character(kind=c_char), allocatable, target :: face(:)

        call make_c_string("Segoe UI", face)
        h_font_ui = CreateFontA(-17_c_int, 0_c_int, 0_c_int, 0_c_int, FW_NORMAL, &
            0_c_int, 0_c_int, 0_c_int, DEFAULT_CHARSET, 0_c_int, 0_c_int, &
            CLEARTYPE_QUALITY, 0_c_int, c_loc(face))
        h_font_title = CreateFontA(-22_c_int, 0_c_int, 0_c_int, 0_c_int, FW_SEMIBOLD, &
            0_c_int, 0_c_int, 0_c_int, DEFAULT_CHARSET, 0_c_int, 0_c_int, &
            CLEARTYPE_QUALITY, 0_c_int, c_loc(face))
    end subroutine init_fonts

    subroutine destroy_fonts()
        integer(c_int) :: ok

        if (c_associated(h_font_ui)) ok = DeleteObject(h_font_ui)
        if (c_associated(h_font_title)) ok = DeleteObject(h_font_title)
        h_font_ui = c_null_ptr
        h_font_title = c_null_ptr
    end subroutine destroy_fonts

    subroutine compute_layout(canvas_w, canvas_h)
        integer, intent(in) :: canvas_w, canvas_h
        integer :: available_control, slider_gap, first_slider_y

        layout_canvas_w = max(canvas_w, 1024)
        layout_canvas_h = max(canvas_h, 720)
        layout_margin = max(14, min(28, layout_canvas_w / 70))
        layout_gap = max(16, min(30, layout_canvas_w / 90))

        layout_control_left = layout_margin
        layout_control_top = layout_margin
        layout_control_w = min(max(320, layout_canvas_w / 5), 400)
        layout_control_bottom = layout_canvas_h - layout_margin
        layout_slider_x = layout_control_left + 26
        layout_slider_w = layout_control_w - 58

        first_slider_y = layout_control_top + 116
        available_control = max(480, layout_control_bottom - layout_control_top - 310)
        slider_gap = min(max(78, available_control / 6), 130)
        layout_slider_y(1) = first_slider_y
        layout_slider_y(2) = first_slider_y + slider_gap
        layout_slider_y(3) = first_slider_y + 2 * slider_gap
        layout_slider_y(4) = first_slider_y + 3 * slider_gap
        layout_slider_y(5) = first_slider_y + 4 * slider_gap
        layout_slider_y(6) = first_slider_y + 5 * slider_gap

        layout_button_y = min(layout_control_bottom - 176, layout_slider_y(6) + 88)
        layout_footer_y = layout_control_bottom - 58

        layout_main_left = layout_control_left + layout_control_w + layout_gap
        layout_main_top = layout_margin
        layout_main_w = max(620, layout_canvas_w - layout_margin - layout_main_left)
        layout_main_h = layout_canvas_h - 2 * layout_margin
    end subroutine compute_layout

    subroutine compute_layout_from_window(hwnd)
        type(c_ptr), value :: hwnd
        type(Rect) :: client
        integer(c_int) :: ok, cw, ch

        ok = GetClientRect(hwnd, client)
        if (ok == 0_c_int) then
            call compute_layout(int(CANVAS_W), int(CANVAS_H))
        else
            cw = int(client%right - client%left, c_int)
            ch = int(client%bottom - client%top, c_int)
            call compute_layout(int(cw), int(ch))
        end if
    end subroutine compute_layout_from_window

    subroutine invalidate_dashboard(hwnd)
        type(c_ptr), value :: hwnd
        integer(c_int) :: ok

        ok = InvalidateRect(hwnd, c_null_ptr, 0_c_int)
    end subroutine invalidate_dashboard

    subroutine handle_command(control_id)
        integer(c_int), intent(in) :: control_id

        select case (control_id)
        case (ID_AUTO)
            grid%auto_balance = .not. grid%auto_balance
        case (ID_BALANCE)
            call balance_now()
        case (ID_RESET)
            call reset_controls()
        end select

        call refresh_model()
    end subroutine handle_command

    subroutine handle_mouse_down(hwnd, x, y)
        type(c_ptr), value :: hwnd
        integer, intent(in) :: x, y
        type(c_ptr) :: previous

        call compute_layout_from_window(hwnd)
        active_control = hit_test_control(x, y)
        select case (active_control)
        case (ID_AUTO)
            grid%auto_balance = .not. grid%auto_balance
            active_control = ID_NONE
        case (ID_BALANCE)
            call balance_now()
            active_control = ID_NONE
        case (ID_RESET)
            call reset_controls()
            active_control = ID_NONE
        case (ID_DEMAND, ID_RENEWABLE, ID_STORAGE, ID_GAS, ID_AMBIENT, ID_TIT)
            previous = SetCapture(hwnd)
            call update_active_slider(x)
        end select
        call refresh_model()
    end subroutine handle_mouse_down

    subroutine handle_mouse_up()
        integer(c_int) :: ok

        if (active_control /= ID_NONE) ok = ReleaseCapture()
        active_control = ID_NONE
    end subroutine handle_mouse_up

    subroutine update_active_slider(x)
        integer, intent(in) :: x
        real(dp) :: f

        if (active_control == ID_NONE) return
        f = clamp_real(real(x - layout_slider_x, dp) / real(max(layout_slider_w, 1), dp), 0.0_dp, 1.0_dp)
        select case (active_control)
        case (ID_DEMAND)
            grid%demand_MW = DEMAND_MIN_MW + f * (DEMAND_MAX_MW - DEMAND_MIN_MW)
        case (ID_RENEWABLE)
            grid%renewable_MW = f * RENEWABLE_MAX_MW
        case (ID_STORAGE)
            grid%storage_request_MW = STORAGE_MIN_MW + f * (STORAGE_MAX_MW - STORAGE_MIN_MW)
        case (ID_GAS)
            grid%gas_dispatch_pct = GAS_MIN_PCT + f * (GAS_MAX_PCT - GAS_MIN_PCT)
            grid%auto_balance = .false.
        case (ID_AMBIENT)
            grid%ambient_C = -20.0_dp + f * 65.0_dp
        case (ID_TIT)
            grid%TIT_K = 1200.0_dp + f * 400.0_dp
        end select
    end subroutine update_active_slider

    function hit_test_control(x, y) result(control_id)
        integer, intent(in) :: x, y
        integer(c_int) :: control_id

        control_id = ID_NONE
        if (point_in_rect(x, y, layout_slider_x - 14, layout_slider_y(1) - 38, &
                layout_slider_x + layout_slider_w + 14, layout_slider_y(1) + 38)) control_id = ID_DEMAND
        if (point_in_rect(x, y, layout_slider_x - 14, layout_slider_y(2) - 38, &
                layout_slider_x + layout_slider_w + 14, layout_slider_y(2) + 38)) control_id = ID_RENEWABLE
        if (point_in_rect(x, y, layout_slider_x - 14, layout_slider_y(3) - 38, &
                layout_slider_x + layout_slider_w + 14, layout_slider_y(3) + 38)) control_id = ID_STORAGE
        if (point_in_rect(x, y, layout_slider_x - 14, layout_slider_y(4) - 38, &
                layout_slider_x + layout_slider_w + 14, layout_slider_y(4) + 38)) control_id = ID_GAS
        if (point_in_rect(x, y, layout_slider_x - 14, layout_slider_y(5) - 38, &
                layout_slider_x + layout_slider_w + 14, layout_slider_y(5) + 38)) control_id = ID_AMBIENT
        if (point_in_rect(x, y, layout_slider_x - 14, layout_slider_y(6) - 38, &
                layout_slider_x + layout_slider_w + 14, layout_slider_y(6) + 38)) control_id = ID_TIT
        if (point_in_rect(x, y, layout_control_left + 16, layout_button_y, &
                layout_control_left + 158, layout_button_y + 42)) control_id = ID_AUTO
        if (point_in_rect(x, y, layout_control_left + 172, layout_button_y, &
                layout_control_left + layout_control_w - 16, layout_button_y + 42)) control_id = ID_BALANCE
        if (point_in_rect(x, y, layout_control_left + 16, layout_button_y + 56, &
                layout_control_left + 124, layout_button_y + 98)) control_id = ID_RESET
    end function hit_test_control

    pure function point_in_rect(x, y, left, top, right, bottom) result(inside)
        integer, intent(in) :: x, y, left, top, right, bottom
        logical :: inside

        inside = (x >= left .and. x <= right .and. y >= top .and. y <= bottom)
    end function point_in_rect

    subroutine refresh_model()
        type(InputCase) :: ic
        type(CycleResult) :: res
        real(dp) :: load_fraction

        ic = baseline_case()
        ic%ambient_T_K = grid%ambient_C + KELVIN_OFFSET
        ic%T_turbine_inlet_K = grid%TIT_K

        ic%mdot_air_kg_s = 100.0_dp
        res = solve_cycle(ic)
        grid%gas_capacity_MW = max(0.0_dp, res%net_power_MW)

        load_fraction = clamp_real(grid%gas_dispatch_pct / 100.0_dp, 0.0_dp, 1.0_dp)
        ic%mdot_air_kg_s = 100.0_dp * load_fraction
        res = solve_cycle(ic)

        grid%gas_power_MW = max(0.0_dp, res%net_power_MW)
        grid%heat_rate_kJ_kWh = res%heat_rate_kJ_kWh
        grid%exhaust_K = res%exhaust_temperature_K
        grid%fuel_flow_kg_s = res%fuel_flow_kg_s
        grid%heat_input_MW = res%heat_input_MW
        grid%storage_MW = limited_storage_power(grid%storage_request_MW)
        grid%supply_MW = grid%gas_power_MW + effective_renewable_MW() + grid%storage_MW
        grid%imbalance_MW = grid%supply_MW - grid%demand_MW
        grid%reserve_MW = max(0.0_dp, grid%gas_capacity_MW - grid%gas_power_MW)
        ! frequency_Hz is integrated dynamically by tick_frequency_dynamics; not recomputed here
        call refresh_economics()
    end subroutine refresh_model

    subroutine refresh_economics()
        real(dp) :: served_MW, battery_capex_usd, annual_value_usd

        served_MW = min(grid%demand_MW, max(0.0_dp, grid%supply_MW))
        grid%revenue_usd_h = served_MW * POWER_PRICE_USD_MWH
        grid%fuel_cost_usd_h = grid%heat_input_MW * 3.6_dp * FUEL_PRICE_USD_GJ
        grid%storage_cost_usd_h = abs(grid%storage_MW) * STORAGE_CYCLE_COST_USD_MWH
        grid%imbalance_penalty_usd_h = abs(grid%imbalance_MW) * IMBALANCE_PENALTY_USD_MWH
        grid%margin_usd_h = grid%revenue_usd_h - grid%fuel_cost_usd_h - &
            grid%storage_cost_usd_h - grid%imbalance_penalty_usd_h

        grid%battery_value_usd_h = max(0.0_dp, abs(grid%storage_MW) * &
            (IMBALANCE_PENALTY_USD_MWH - STORAGE_CYCLE_COST_USD_MWH))
        battery_capex_usd = BATTERY_CAPACITY_MWH * BATTERY_CAPEX_USD_MWH
        annual_value_usd = grid%battery_value_usd_h * ROI_EQUIVALENT_HOURS_PER_YEAR
        if (annual_value_usd > 1.0e-6_dp) then
            grid%battery_payback_years = battery_capex_usd / annual_value_usd
        else
            grid%battery_payback_years = 99.0_dp
        end if

        grid%CO2_rate_kg_s = grid%fuel_flow_kg_s * CO2_KG_PER_KG_FUEL
        if (grid%gas_power_MW > 0.1_dp) then
            grid%CO2_intensity_g_kWh = grid%CO2_rate_kg_s * 3600.0_dp / grid%gas_power_MW
        else
            grid%CO2_intensity_g_kWh = 0.0_dp
        end if
    end subroutine refresh_economics

    function effective_renewable_MW() result(mw)
        ! Actual grid injection = available (slider) minus AGC curtailment
        real(dp) :: mw
        mw = max(0.0_dp, grid%renewable_MW - grid%renewable_curtail_MW)
    end function effective_renewable_MW

    function limited_storage_power(request_MW) result(actual_MW)
        real(dp), intent(in) :: request_MW
        real(dp) :: actual_MW

        actual_MW = clamp_real(request_MW, STORAGE_MIN_MW, STORAGE_MAX_MW)
        if (actual_MW > 0.0_dp .and. grid%battery_energy_MWh <= 1.0e-6_dp) then
            actual_MW = 0.0_dp
        else if (actual_MW < 0.0_dp .and. grid%battery_energy_MWh >= BATTERY_CAPACITY_MWH - 1.0e-6_dp) then
            actual_MW = 0.0_dp
        end if
    end function limited_storage_power

    subroutine update_battery_soc(dt_s)
        real(dp), intent(in) :: dt_s
        real(dp) :: delta_MWh

        if (grid%storage_MW > 0.0_dp) then
            delta_MWh = -grid%storage_MW * dt_s / 3600.0_dp / BATTERY_EFFICIENCY
        else
            delta_MWh = -grid%storage_MW * dt_s / 3600.0_dp * BATTERY_EFFICIENCY
        end if

        grid%battery_energy_MWh = clamp_real(grid%battery_energy_MWh + delta_MWh, 0.0_dp, BATTERY_CAPACITY_MWH)
        grid%battery_soc_pct = 100.0_dp * grid%battery_energy_MWh / BATTERY_CAPACITY_MWH
    end subroutine update_battery_soc

    subroutine append_history()
        integer :: idx

        idx = mod(grid%history_head, HISTORY_N) + 1
        grid%hist_frequency_Hz(idx) = grid%frequency_Hz
        grid%hist_demand_MW(idx) = grid%demand_MW
        grid%hist_gas_dispatch_pct(idx) = grid%gas_dispatch_pct
        grid%history_head = idx
        grid%history_count = min(grid%history_count + 1, HISTORY_N)
    end subroutine append_history

    function baseline_case() result(ic)
        type(InputCase) :: ic

        ic%case_name = "gui_live_case"
        ic%ambient_T_K = 288.15_dp
        ic%ambient_P_Pa = 101325.0_dp
        ic%relative_humidity = 0.60_dp
        ic%inlet_pressure_loss = 0.010_dp
        ic%mdot_air_kg_s = 100.0_dp
        ic%pressure_ratio = 15.0_dp
        ic%eta_compressor = 0.86_dp
        ic%T_turbine_inlet_K = 1400.0_dp
        ic%eta_combustor = 0.98_dp
        ic%combustor_pressure_loss = 0.030_dp
        ic%LHV_J_kg = 50.0e6_dp
        ic%eta_turbine = 0.89_dp
        ic%exhaust_pressure_loss = 0.020_dp
        ic%eta_mechanical = 0.990_dp
        ic%eta_generator = 0.985_dp
        ic%auxiliary_load_fraction = 0.020_dp
        ic%degradation_mode = "clean"
    end function baseline_case

    subroutine tick_auto_balance(dt_s)
        ! Secondary AGC with real merit order (sign convention:
        ! storage_MW > 0 = discharge, adds to supply).
        !   Shortage: restore curtailment (free) -> BESS discharge -> gas up
        !   Surplus:  BESS charge -> gas down to min -> curtail renewables (last)
        real(dp), intent(in) :: dt_s
        real(dp) :: eff_renew, gap_MW, bess_target_MW, bess_step_MW
        real(dp) :: needed_gas_MW, gas_target_pct, gas_step_pct
        real(dp) :: gas_min_MW, surplus_MW, curtail_step_MW

        if (.not. grid%auto_balance) return

        curtail_step_MW = CURTAIL_RAMP_MW_PER_S * dt_s
        ! Curtailment can never exceed the available resource
        grid%renewable_curtail_MW = clamp_real(grid%renewable_curtail_MW, 0.0_dp, grid%renewable_MW)

        ! --- Stage 1 (shortage only): restore curtailed renewables first ---
        eff_renew = effective_renewable_MW()
        gap_MW = grid%demand_MW - eff_renew - grid%gas_power_MW &
                 - limited_storage_power(grid%storage_request_MW)
        if (gap_MW > 0.0_dp .and. grid%renewable_curtail_MW > 0.0_dp) then
            grid%renewable_curtail_MW = max(0.0_dp, &
                grid%renewable_curtail_MW - min(curtail_step_MW, gap_MW))
            eff_renew = effective_renewable_MW()
        end if

        ! --- Stage 2: BESS covers the residual (fast, +-4 MW/s) ---
        ! residual > 0 -> shortage -> discharge (positive)
        bess_target_MW = clamp_real(grid%demand_MW - eff_renew - grid%gas_power_MW, &
                                    STORAGE_MIN_MW, STORAGE_MAX_MW)
        if (bess_target_MW > 0.0_dp .and. grid%battery_soc_pct < 5.0_dp) &
            bess_target_MW = 0.0_dp   ! no discharge when nearly empty
        if (bess_target_MW < 0.0_dp .and. grid%battery_soc_pct > 95.0_dp) &
            bess_target_MW = 0.0_dp   ! no charge when nearly full
        bess_step_MW = BESS_RAMP_MW_PER_S * dt_s
        grid%storage_request_MW = grid%storage_request_MW + &
            clamp_real(bess_target_MW - grid%storage_request_MW, -bess_step_MW, bess_step_MW)

        ! --- Stage 3: turbine covers what BESS cannot (slow, 18 %/s) ---
        needed_gas_MW = grid%demand_MW - eff_renew &
                        - limited_storage_power(grid%storage_request_MW)
        if (grid%gas_capacity_MW > 1.0e-6_dp) then
            gas_target_pct = 100.0_dp * needed_gas_MW / grid%gas_capacity_MW
        else
            gas_target_pct = GAS_MAX_PCT
        end if
        gas_target_pct = clamp_real(gas_target_pct, GAS_MIN_PCT, GAS_MAX_PCT)
        gas_step_pct = GAS_RAMP_PCT_PER_S * dt_s
        grid%gas_dispatch_pct = grid%gas_dispatch_pct + &
            clamp_real(gas_target_pct - grid%gas_dispatch_pct, -gas_step_pct, gas_step_pct)

        ! --- Stage 4 (surplus only): curtail renewables as last resort ---
        ! Only when gas is already at minimum stable load and BESS charge
        ! is saturated does spilling zero-cost energy make sense.
        gas_min_MW = grid%gas_capacity_MW * GAS_MIN_PCT / 100.0_dp
        surplus_MW = grid%gas_power_MW + eff_renew &
                     + limited_storage_power(grid%storage_request_MW) - grid%demand_MW
        if (surplus_MW > 0.5_dp .and. &
            grid%gas_dispatch_pct <= GAS_MIN_PCT + 0.5_dp .and. &
            (grid%storage_request_MW <= STORAGE_MIN_MW + 0.1_dp .or. &
             grid%battery_soc_pct > 95.0_dp)) then
            grid%renewable_curtail_MW = clamp_real( &
                grid%renewable_curtail_MW + min(curtail_step_MW, surplus_MW), &
                0.0_dp, grid%renewable_MW)
        end if
    end subroutine tick_auto_balance

    subroutine balance_now()
        ! GOTO SP: snap BESS and turbine to their balance setpoints instantly;
        ! drop any curtailment (operator-commanded re-dispatch).
        real(dp) :: bess_snap_MW, needed_gas_MW

        if (grid%gas_capacity_MW <= 1.0e-6_dp) return
        grid%renewable_curtail_MW = 0.0_dp
        bess_snap_MW = clamp_real(grid%demand_MW - grid%renewable_MW - grid%gas_power_MW, &
                                  STORAGE_MIN_MW, STORAGE_MAX_MW)
        if (bess_snap_MW > 0.0_dp .and. grid%battery_soc_pct < 5.0_dp)  bess_snap_MW = 0.0_dp
        if (bess_snap_MW < 0.0_dp .and. grid%battery_soc_pct > 95.0_dp) bess_snap_MW = 0.0_dp
        grid%storage_request_MW = bess_snap_MW
        needed_gas_MW = grid%demand_MW - grid%renewable_MW &
                        - limited_storage_power(grid%storage_request_MW)
        grid%gas_dispatch_pct = clamp_real(100.0_dp * needed_gas_MW / grid%gas_capacity_MW, &
                                           GAS_MIN_PCT, GAS_MAX_PCT)
        grid%auto_balance = .true.
    end subroutine balance_now

    subroutine tick_frequency_dynamics(dt_s)
        real(dp), intent(in) :: dt_s
        real(dp) :: delta_f, P_gen_eff, P_load_eff, df_dt
        real(dp) :: gov_max_up, gov_max_dn

        delta_f = grid%frequency_Hz - FREQ_NOMINAL_HZ

        ! Governor primary droop: ΔP_gov = -(Δf/f0)/R * P_rated (clamped to available headroom)
        grid%governor_delta_MW = -(delta_f / FREQ_NOMINAL_HZ) / GOVERNOR_DROOP_R * grid%gas_capacity_MW
        gov_max_up = grid%gas_capacity_MW - grid%gas_power_MW
        gov_max_dn = grid%gas_power_MW - grid%gas_capacity_MW * (GAS_MIN_PCT / 100.0_dp)
        grid%governor_delta_MW = clamp_real(grid%governor_delta_MW, -gov_max_dn, gov_max_up)

        ! BESS primary frequency response (dead-band 0.02 Hz)
        if (abs(delta_f) > BESS_PRIMARY_DB) then
            grid%BESS_primary_MW = clamp_real(-delta_f * BESS_PRIMARY_GAIN, -5.0_dp, 5.0_dp)
            if (grid%BESS_primary_MW > 0.0_dp .and. grid%battery_energy_MWh <= 1.0e-6_dp) &
                grid%BESS_primary_MW = 0.0_dp
            if (grid%BESS_primary_MW < 0.0_dp .and. &
                    grid%battery_energy_MWh >= BATTERY_CAPACITY_MWH - 1.0e-6_dp) &
                grid%BESS_primary_MW = 0.0_dp
        else
            grid%BESS_primary_MW = 0.0_dp
        end if

        ! UFLS (ENTSO-E): latching stages, reset above 49.5 Hz
        if (grid%frequency_Hz >= UFLS_RESET) then
            grid%UFLS_stage = 0
            grid%UFLS_shed_fraction = 0.0_dp
        else if (grid%frequency_Hz < UFLS_THRESH_3 .and. grid%UFLS_stage < 3) then
            grid%UFLS_stage = 3
            grid%UFLS_shed_fraction = 3.0_dp * UFLS_SHED_PCT
        else if (grid%frequency_Hz < UFLS_THRESH_2 .and. grid%UFLS_stage < 2) then
            grid%UFLS_stage = 2
            grid%UFLS_shed_fraction = 2.0_dp * UFLS_SHED_PCT
        else if (grid%frequency_Hz < UFLS_THRESH_1 .and. grid%UFLS_stage < 1) then
            grid%UFLS_stage = 1
            grid%UFLS_shed_fraction = UFLS_SHED_PCT
        end if

        ! LFSM-O (ENTSO-E RfG): above 50.2 Hz renewables shed output with 5% droop
        if (grid%frequency_Hz > LFSM_O_THRESH_HZ) then
            grid%renewable_lfsmo_MW = min(effective_renewable_MW(), &
                effective_renewable_MW() * (grid%frequency_Hz - LFSM_O_THRESH_HZ) / &
                FREQ_NOMINAL_HZ / LFSM_O_DROOP)
        else
            grid%renewable_lfsmo_MW = 0.0_dp
        end if

        ! Swing equation: df/dt = (P_gen - P_load) / M_eff
        P_gen_eff  = grid%gas_power_MW + grid%governor_delta_MW + &
                     effective_renewable_MW() - grid%renewable_lfsmo_MW + &
                     grid%storage_MW + grid%BESS_primary_MW
        P_load_eff = grid%demand_MW * (1.0_dp - grid%UFLS_shed_fraction)
        df_dt = (P_gen_eff - P_load_eff) / INERTIA_MWs
        grid%ROCOF_Hz_s = df_dt
        grid%frequency_Hz = clamp_real(grid%frequency_Hz + df_dt * dt_s, 47.0_dp, 53.0_dp)

        ! Update alarm flags
        grid%alarm_underfreq   = grid%frequency_Hz < (FREQ_NOMINAL_HZ - 0.5_dp)
        grid%alarm_overfreq    = grid%frequency_Hz > (FREQ_NOMINAL_HZ + 0.5_dp)
        grid%alarm_low_reserve = grid%reserve_MW < 2.0_dp
        grid%alarm_low_soc     = grid%battery_soc_pct < 15.0_dp
        grid%alarm_ufls_active = grid%UFLS_stage > 0
        grid%alarm_turbine_max = grid%gas_dispatch_pct >= (GAS_MAX_PCT - 0.5_dp)
    end subroutine tick_frequency_dynamics

    subroutine reset_controls()
        grid%auto_balance = .true.
        grid%battery_energy_MWh = BATTERY_CAPACITY_MWH * BATTERY_INITIAL_SOC_PCT / 100.0_dp
        grid%battery_soc_pct = BATTERY_INITIAL_SOC_PCT
        grid%elapsed_s = 0.0_dp
        grid%CO2_cumulative_t = 0.0_dp
        grid%history_count = 0
        grid%history_head = 0
        grid%demand_MW = 35.0_dp
        grid%renewable_MW = 12.0_dp
        grid%storage_request_MW = 0.0_dp
        grid%storage_MW = 0.0_dp
        grid%gas_dispatch_pct = 82.0_dp
        grid%ambient_C = 15.0_dp
        grid%TIT_K = 1400.0_dp
        grid%frequency_Hz = FREQ_NOMINAL_HZ
        grid%ROCOF_Hz_s = 0.0_dp
        grid%governor_delta_MW = 0.0_dp
        grid%BESS_primary_MW = 0.0_dp
        grid%UFLS_shed_fraction = 0.0_dp
        grid%UFLS_stage = 0
        grid%renewable_curtail_MW = 0.0_dp
        grid%renewable_lfsmo_MW = 0.0_dp
        grid%alarm_underfreq = .false.
        grid%alarm_overfreq  = .false.
        grid%alarm_low_reserve = .false.
        grid%alarm_low_soc = .false.
        grid%alarm_ufls_active = .false.
        grid%alarm_turbine_max = .false.
    end subroutine reset_controls

    subroutine draw_dashboard_buffered(hwnd, hdc)
        type(c_ptr), value :: hwnd
        type(c_ptr), value :: hdc
        type(c_ptr) :: memdc, bitmap, old_bitmap
        type(Rect) :: client
        integer(c_int) :: ok, cw, ch

        ok = GetClientRect(hwnd, client)
        if (ok == 0_c_int) then
            cw = CANVAS_W
            ch = CANVAS_H
        else
            cw = int(client%right - client%left, c_int)
            ch = int(client%bottom - client%top, c_int)
            if (cw <= 0_c_int) cw = CANVAS_W
            if (ch <= 0_c_int) ch = CANVAS_H
        end if

        memdc = CreateCompatibleDC(hdc)
        bitmap = CreateCompatibleBitmap(hdc, cw, ch)
        if (.not. c_associated(memdc) .or. .not. c_associated(bitmap)) then
            call draw_dashboard(hdc, int(cw), int(ch))
            return
        end if

        old_bitmap = SelectObject(memdc, bitmap)
        call draw_dashboard(memdc, int(cw), int(ch))
        ok = BitBlt(hdc, 0_c_int, 0_c_int, cw, ch, memdc, 0_c_int, 0_c_int, SRCCOPY)
        old_bitmap = SelectObject(memdc, old_bitmap)
        ok = DeleteObject(bitmap)
        ok = DeleteDC(memdc)
    end subroutine draw_dashboard_buffered

    subroutine draw_dashboard(hdc, canvas_w, canvas_h)
        type(c_ptr), value :: hdc
        integer, intent(in) :: canvas_w, canvas_h
        integer :: x0, y0, w, h
        integer :: inner_x, inner_w
        real(dp) :: scale_MW
        character(len=96) :: status, subtitle
        integer(c_int) :: status_color
        integer :: gx, gy

        call compute_layout(canvas_w, canvas_h)
        call fill_box(hdc, 0, 0, canvas_w, canvas_h, COL_BG)
        do gx = 0, canvas_w, 80
            call draw_line(hdc, gx, 0, gx, canvas_h, COL_BG_GRID, 1)
        end do
        do gy = 0, canvas_h, 80
            call draw_line(hdc, 0, gy, canvas_w, gy, COL_BG_GRID, 1)
        end do
        call draw_control_panel(hdc)

        x0 = layout_main_left
        y0 = layout_main_top
        w = layout_main_w
        h = layout_main_h
        inner_x = x0 + 16
        inner_w = max(500, w - 32)

        ! --- Header bar ---
        call fill_box(hdc, x0, y0, x0 + w, y0 + 44, COL_PANEL_DEEP)
        call fill_box(hdc, x0, y0, x0 + 5, y0 + 44, COL_CYAN)
        call draw_line(hdc, x0, y0 + 44, x0 + w, y0 + 44, COL_BORDER, 1)
        call draw_title_text(hdc, inner_x + 8, y0 + 10, &
            "ThermoTwin-F  |  Plant Control Console  |  50 Hz ENTSO-E", COL_INK)
        write(subtitle, '("t=",F6.1,"s  Mode: ",A)') &
            grid%elapsed_s, merge("AUTO   ", "MANUAL ", grid%auto_balance)
        call draw_text(hdc, x0 + w - 200, y0 + 14, trim(subtitle), &
            merge(COL_LIME, COL_AMBER, grid%auto_balance))

        ! --- Status banner ---
        call grid_status(status, status_color)
        call fill_box(hdc, x0, y0 + 44, x0 + w, y0 + 68, COL_PANEL_ALT)
        call fill_box(hdc, x0, y0 + 44, x0 + 6, y0 + 68, status_color)
        call draw_line(hdc, x0, y0 + 68, x0 + w, y0 + 68, COL_BORDER_SOFT, 1)
        call draw_text(hdc, inner_x + 10, y0 + 50, trim(status), status_color)

        ! --- Annunciator strip ---
        call draw_annunciator_panel(hdc, x0, y0 + 72, w, 38)

        ! --- Arc gauges + power balance ---
        block
            integer :: gy0, gh, gr, gcy, gcx1, gcx2, bar_x, bar_w
            character(len=28) :: vt

            gy0 = y0 + 114
            gh  = min(320, int(0.30_dp * real(h, dp)))
            gr  = (gh - 40) / 2
            gcy = gy0 + gh / 2 + 8
            gcx1 = inner_x + gr + 16
            gcx2 = inner_x + 2 * gr + 80 + gr + 16

            call fill_box(hdc, x0, gy0, x0 + w, gy0 + gh, COL_PANEL)
            call draw_line(hdc, x0, gy0 + gh, x0 + w, gy0 + gh, COL_BORDER_SOFT, 1)
            call draw_arc_gauge_freq(hdc, gcx1, gcy, gr)
            call draw_arc_gauge_mw(hdc, gcx2, gcy, gr, grid%gas_power_MW, grid%gas_capacity_MW, "TURBINE MW")

            scale_MW = max(max(DEMAND_MAX_MW, grid%demand_MW), max(grid%supply_MW, grid%gas_capacity_MW))
            bar_x = gcx2 + gr + 32
            bar_w = inner_w - (bar_x - inner_x)
            call draw_section_title_width(hdc, bar_x, gy0 + 10, "Power balance", bar_w)
            call draw_bar(hdc, bar_x, gy0 + 32, bar_w, 26, "Demand", grid%demand_MW, scale_MW, COL_RED)
            call draw_bar(hdc, bar_x, gy0 + 68, bar_w, 26, "Supply", grid%supply_MW, scale_MW, COL_GREEN)
            call draw_stacked_supply(hdc, bar_x, gy0 + 106, bar_w, 28, scale_MW, &
                COL_LIME, COL_GREEN, COL_BLUE, COL_AMBER)
            if (grid%UFLS_stage > 0) then
                write(vt, '("UFLS S",I1,"  ",F4.0,"% shed")') grid%UFLS_stage, grid%UFLS_shed_fraction*100.0_dp
                call draw_text(hdc, bar_x, gy0 + 144, trim(adjustl(vt)), COL_RED)
            end if
            call draw_bar(hdc, bar_x, gy0 + 162, bar_w, 22, "Reserve", grid%reserve_MW, &
                max(1.0_dp, grid%gas_capacity_MW), COL_CYAN)

            ! vertical SOC bar at right margin
            call draw_vertical_soc_bar(hdc, x0 + w - 72, gy0 + 8, 64, gh - 16)

            ! --- Faceplate KPI row (6 tiles) ---
            block
                integer :: fy, fw, fg, fp1, fp2, fp3, fp4, fp5, fp6

                fy = gy0 + gh + 12
                fg = 8
                fw = (inner_w - 5 * fg) / 6
                fp1 = inner_x
                fp2 = fp1 + fw + fg
                fp3 = fp2 + fw + fg
                fp4 = fp3 + fw + fg
                fp5 = fp4 + fw + fg
                fp6 = fp5 + fw + fg

                write(vt, '(F7.3," Hz")') grid%frequency_Hz
                call draw_faceplate(hdc, fp1, fy, fw, 68, "FREQUENCY", trim(adjustl(vt)), frequency_color())
                write(vt, '(F6.1," MW  ",F5.0,"%")') grid%gas_power_MW, &
                    100.0_dp * grid%gas_power_MW / max(grid%gas_capacity_MW, 1.0e-9_dp)
                call draw_faceplate(hdc, fp2, fy, fw, 68, "TURBINE", trim(adjustl(vt)), COL_LIME)
                write(vt, '(SP,F6.1," MW")') grid%imbalance_MW
                call draw_faceplate(hdc, fp3, fy, fw, 68, "IMBALANCE", trim(adjustl(vt)), &
                    merge(COL_GREEN, COL_RED, abs(grid%imbalance_MW) <= 0.5_dp))
                write(vt, '("$",F7.0,"/h")') grid%margin_usd_h
                call draw_faceplate(hdc, fp4, fy, fw, 68, "NET MARGIN", trim(adjustl(vt)), &
                    merge(COL_GREEN, merge(COL_AMBER, COL_RED, grid%margin_usd_h > -1000.0_dp), &
                    grid%margin_usd_h >= 0.0_dp))
                write(vt, '(F5.1,"%  ",F4.1,"/",F4.0)') &
                    grid%battery_soc_pct, grid%battery_energy_MWh, BATTERY_CAPACITY_MWH
                call draw_faceplate(hdc, fp5, fy, fw, 68, "BESS SOC", trim(adjustl(vt)), &
                    merge(COL_RED, COL_BLUE, grid%alarm_low_soc))
                ! 6th tile: Governor + BESS primary response
                write(vt, '("G",SP,F5.1," B",SP,F4.1)') &
                    grid%governor_delta_MW, grid%BESS_primary_MW
                call draw_faceplate(hdc, fp6, fy, fw, 68, "GOV / BESS", trim(adjustl(vt)), &
                    merge(COL_CYAN, COL_DIM, &
                    abs(grid%governor_delta_MW) > 0.05_dp .or. abs(grid%BESS_primary_MW) > 0.05_dp))

                ! --- ROI panel ---
                call draw_section_title_width(hdc, inner_x, fy + 80, "Economics", inner_w)
                call draw_roi_panel(hdc, inner_x, fy + 102, inner_w, 108)

                ! --- Live traces + power flow ---
                block
                    integer :: ly, lh, lg, tw, fx2, fw2
                    ly = fy + 80 + 122
                    if (ly > y0 + h - 170) ly = y0 + h - 170
                    lh = y0 + h - ly - 18
                    lh = min(max(150, lh), 340)
                    if (ly + lh > y0 + h - 12) lh = max(120, y0 + h - ly - 12)
                    lg = 20
                    tw = max(360, int(0.60_dp * real(inner_w, dp)))
                    if (inner_w - tw - lg < 240) tw = max(300, inner_w - 240 - lg)
                    fx2 = inner_x + tw + lg
                    fw2 = max(220, inner_w - tw - lg)
                    call draw_section_title_width(hdc, inner_x, ly, &
                        "Live traces  (48.5-51.5 Hz | demand MW | turbine %)", tw)
                    call draw_history_traces(hdc, inner_x, ly + 26, tw, lh)
                    call draw_section_title_width(hdc, fx2, ly, "Power flow", fw2)
                    call draw_power_flow(hdc, fx2, ly + 26, fw2, lh)
                end block
            end block
        end block
    end subroutine draw_dashboard

    subroutine draw_control_panel(hdc)
        type(c_ptr), value :: hdc
        character(len=40) :: value
        character(len=64) :: line
        integer :: left, top, right, bottom, title_x, panel_top, panel_bottom, row_gap

        left = layout_control_left
        top = layout_control_top
        right = layout_control_left + layout_control_w
        bottom = layout_control_bottom
        title_x = left + 24

        ! Panel outer shell (bezel)
        call fill_box(hdc, left, top, right, bottom, COL_BTN_SH)
        call fill_box(hdc, left+1, top+1, right-1, bottom-1, COL_PANEL_DEEP)
        ! Top highlight (3D raised edge)
        call draw_line(hdc, left+1, top+1, right-2, top+1, COL_BORDER, 1)
        call draw_line(hdc, left+1, top+1, left+1, bottom-2, COL_BORDER, 1)
        call stroke_box(hdc, left, top, right, bottom, COL_BORDER_SOFT, 1)
        ! Title area
        call fill_box(hdc, left+1, top+1, right-1, top+66, COL_PANEL)
        call draw_line(hdc, left+1, top+66, right-1, top+66, COL_BORDER, 1)
        call draw_title_text(hdc, title_x, top + 14, "Plant Controls", COL_INK)
        call draw_text(hdc, title_x, top + 44, "Dispatch console", COL_MUTED)
        call fill_box(hdc, title_x, top + 66, right - 24, top + 67, COL_BORDER_SOFT)

        write(value, '(F5.1," MW")') grid%demand_MW
        call draw_custom_slider(hdc, ID_DEMAND, layout_slider_x, layout_slider_y(1), layout_slider_w, &
            "Load demand", trim(adjustl(value)), &
            grid%demand_MW, DEMAND_MIN_MW, DEMAND_MAX_MW, COL_RED)

        if (grid%renewable_curtail_MW > 0.05_dp) then
            write(value, '(F4.1,"/",F4.1," MW")') effective_renewable_MW(), grid%renewable_MW
        else
            write(value, '(F5.1," MW")') grid%renewable_MW
        end if
        call draw_custom_slider(hdc, ID_RENEWABLE, layout_slider_x, layout_slider_y(2), layout_slider_w, &
            "Renewable available", trim(adjustl(value)), &
            grid%renewable_MW, 0.0_dp, RENEWABLE_MAX_MW, &
            merge(COL_AMBER, COL_GREEN, grid%renewable_curtail_MW > 0.05_dp))

        write(value, '(SP,F5.1," MW")') grid%storage_request_MW
        call draw_custom_slider(hdc, ID_STORAGE, layout_slider_x, layout_slider_y(3), layout_slider_w, &
            "Battery command", trim(adjustl(value)), &
            grid%storage_request_MW, STORAGE_MIN_MW, STORAGE_MAX_MW, COL_BLUE)

        write(value, '(F5.0," %")') grid%gas_dispatch_pct
        call draw_custom_slider(hdc, ID_GAS, layout_slider_x, layout_slider_y(4), layout_slider_w, &
            "Turbine dispatch", trim(adjustl(value)), &
            grid%gas_dispatch_pct, GAS_MIN_PCT, GAS_MAX_PCT, COL_LIME)

        write(value, '(F5.0," C")') grid%ambient_C
        call draw_custom_slider(hdc, ID_AMBIENT, layout_slider_x, layout_slider_y(5), layout_slider_w, &
            "Ambient air", trim(adjustl(value)), &
            grid%ambient_C, -20.0_dp, 45.0_dp, COL_AMBER)

        write(value, '(F5.0," K")') grid%TIT_K
        call draw_custom_slider(hdc, ID_TIT, layout_slider_x, layout_slider_y(6), layout_slider_w, &
            "Turbine inlet temp", trim(adjustl(value)), &
            grid%TIT_K, 1200.0_dp, 1600.0_dp, COL_RED)

        ! AUTO/MAN latching mode button
        if (grid%auto_balance) then
            call draw_industrial_button(hdc, left + 16, layout_button_y, left + 158, layout_button_y + 42, &
                "AUTO  ON", COL_GREEN, .true.)
        else
            call draw_industrial_button(hdc, left + 16, layout_button_y, left + 158, layout_button_y + 42, &
                "MANUAL  ", COL_PANEL_ALT, .false.)
        end if
        ! GOTO-SP momentary — executes instant balance
        call draw_industrial_button(hdc, left + 172, layout_button_y, right - 16, layout_button_y + 42, &
            "GOTO SP ", COL_PANEL, .false.)
        ! RESET momentary
        call draw_industrial_button(hdc, left + 16, layout_button_y + 56, left + 124, layout_button_y + 98, &
            "RESET   ", COL_PANEL, .false.)

        panel_top = layout_button_y + 124
        panel_bottom = layout_footer_y - 28
        if (panel_bottom - panel_top > 118) then
            row_gap = max(24, (panel_bottom - panel_top - 44) / 4)
            call fill_soft_box(hdc, title_x, panel_top, right - 24, panel_bottom, COL_PANEL_ALT)
            call stroke_soft_box(hdc, title_x, panel_top, right - 24, panel_bottom, COL_BORDER_SOFT, 1)
            call draw_text(hdc, title_x + 10, panel_top + 10, "Plant telemetry", COL_MUTED)
            write(line, '("Freq  ",F7.3," Hz")') grid%frequency_Hz
            call draw_text(hdc, title_x + 10, panel_top + 34, adjustl(line), frequency_color())
            write(line, '("ROCOF ",SP,F5.3," Hz/s")') grid%ROCOF_Hz_s
            call draw_text(hdc, title_x + 10, panel_top + 34 + row_gap, adjustl(line), COL_MUTED)
            write(line, '("Rsv  ",F6.1," MW  S",I1)') grid%reserve_MW, grid%UFLS_stage
            call draw_text(hdc, title_x + 10, panel_top + 34 + 2 * row_gap, adjustl(line), &
                merge(COL_RED, COL_CYAN, grid%alarm_ufls_active))
            write(line, '("SOC  ",F5.1,"%  Gov",SP,F5.1)') &
                grid%battery_soc_pct, grid%governor_delta_MW
            call draw_text(hdc, title_x + 10, panel_top + 34 + 3 * row_gap, adjustl(line), COL_BLUE)
        end if

        call fill_box(hdc, title_x, layout_footer_y - 12, right - 24, layout_footer_y - 11, COL_BORDER_SOFT)
        call draw_text(hdc, title_x, layout_footer_y, "Loop 250 ms | Fortran solver", COL_MUTED)
        call draw_text(hdc, title_x, layout_footer_y + 20, "MW  Hz  MWh  USD/h", COL_DIM)
    end subroutine draw_control_panel

    subroutine draw_custom_slider(hdc, control_id, x, y, width, label, value_text, value, lo, hi, color)
        type(c_ptr), value :: hdc
        integer(c_int), intent(in) :: control_id
        integer, intent(in) :: x, y, width
        character(len=*), intent(in) :: label, value_text
        real(dp), intent(in) :: value, lo, hi
        integer(c_int), intent(in) :: color
        integer :: knob_x
        real(dp) :: f
        character(len=20) :: lo_text, hi_text

        call draw_text(hdc, x, y - 34, label, COL_INK)
        call draw_text(hdc, x + width - 78, y - 34, value_text, color)
        f = clamp_real((value - lo) / max(hi - lo, 1.0e-9_dp), 0.0_dp, 1.0_dp)
        knob_x = x + int(f * real(width, dp))
        ! Track groove (recessed)
        call fill_box(hdc, x, y + 1, x + width, y + 6, COL_BTN_SH)
        call fill_box(hdc, x + 1, y + 2, x + width - 1, y + 5, COL_GAUGE_FACE)
        call fill_box(hdc, x + 1, y + 2, knob_x, y + 5, color)
        call stroke_box(hdc, x, y + 1, x + width, y + 6, COL_BORDER_SOFT, 1)
        ! Knob — raised 3D
        call fill_box(hdc, knob_x - 7, y - 8, knob_x + 7, y + 17, COL_BTN_SH)
        call fill_box(hdc, knob_x - 6, y - 7, knob_x + 6, y + 16, COL_PANEL_ALT)
        call draw_line(hdc, knob_x - 5, y - 6, knob_x + 5, y - 6, COL_BTN_HI, 1)
        call draw_line(hdc, knob_x - 5, y - 6, knob_x - 5, y + 15, COL_BTN_HI, 1)
        ! Centre grip lines (3 horizontal notches — skeuomorphic serrations)
        call draw_line(hdc, knob_x - 4, y - 2, knob_x + 3, y - 2, COL_BTN_SH, 1)
        call draw_line(hdc, knob_x - 4, y + 3, knob_x + 3, y + 3, COL_BTN_SH, 1)
        call draw_line(hdc, knob_x - 4, y + 8, knob_x + 3, y + 8, COL_BTN_SH, 1)
        call draw_line(hdc, knob_x - 3, y - 3, knob_x + 2, y - 3, COL_BTN_HI, 1)
        call draw_line(hdc, knob_x - 3, y + 2, knob_x + 2, y + 2, COL_BTN_HI, 1)
        call draw_line(hdc, knob_x - 3, y + 7, knob_x + 2, y + 7, COL_BTN_HI, 1)
        call stroke_box(hdc, knob_x - 6, y - 7, knob_x + 6, y + 16, color, merge(2, 1, active_control == control_id))
        write(lo_text, '(F0.0)') lo
        write(hi_text, '(F0.0)') hi
        call draw_text(hdc, x, y + 20, trim(adjustl(lo_text)), COL_DIM)
        call draw_text(hdc, x + width - 34, y + 20, trim(adjustl(hi_text)), COL_DIM)
    end subroutine draw_custom_slider

    subroutine draw_button(hdc, left, top, right, bottom, label, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: left, top, right, bottom
        character(len=*), intent(in) :: label
        integer(c_int), intent(in) :: color

        call draw_industrial_button(hdc, left, top, right, bottom, label, color, .false.)
    end subroutine draw_button

    subroutine draw_industrial_button(hdc, left, top, right, bottom, label, body_color, pressed)
        type(c_ptr), value :: hdc
        integer, intent(in) :: left, top, right, bottom
        character(len=*), intent(in) :: label
        integer(c_int), intent(in) :: body_color
        logical, intent(in) :: pressed
        integer :: bw, bh, tx, ty

        bw = right - left
        bh = bottom - top
        ! Outer shadow frame (gives depth on black bg)
        call fill_box(hdc, left, top, right, bottom, COL_BTN_SH)
        ! Main body inset by 1 px border
        if (pressed) then
            call fill_box(hdc, left+2, top+2, right-1, bottom-1, body_color)
            ! Inset top-left shadow when pressed
            call draw_line(hdc, left+2, top+2, right-2, top+2, COL_BTN_SH, 1)
            call draw_line(hdc, left+2, top+2, left+2, bottom-2, COL_BTN_SH, 1)
        else
            call fill_box(hdc, left+1, top+1, right-2, bottom-2, body_color)
            ! 3D highlight: top edge + left edge
            call draw_line(hdc, left+1, top+1,  right-3, top+1,  COL_BTN_HI, 2)
            call draw_line(hdc, left+1, top+1,  left+1, bottom-3, COL_BTN_HI, 2)
            ! 3D shadow: bottom edge + right edge
            call draw_line(hdc, left+2, bottom-2, right-2, bottom-2, COL_BTN_SH, 1)
            call draw_line(hdc, right-2, top+2,  right-2, bottom-2, COL_BTN_SH, 1)
        end if
        ! Outer border rim
        call stroke_box(hdc, left, top, right, bottom, COL_BORDER, 1)
        ! Active indicator stripe at bottom (4 px colored bar)
        if (pressed) then
            call fill_box(hdc, left+3, bottom-5, right-3, bottom-2, body_color)
        end if
        ! Label centred
        tx = left + bw / 2 - len_trim(label) * 4
        ty = top  + bh / 2 - 8
        call draw_text(hdc, tx, ty, trim(label), COL_INK)
    end subroutine draw_industrial_button

    subroutine draw_faceplate(hdc, x, y, width, height, label, value_text, value_color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        character(len=*), intent(in) :: label, value_text
        integer(c_int), intent(in) :: value_color

        ! Raised outer frame
        call fill_box(hdc, x, y, x + width, y + height, COL_BTN_SH)
        ! Inset body
        call fill_box(hdc, x + 1, y + 1, x + width - 1, y + height - 1, COL_PANEL_DEEP)
        ! Top highlight (3D raised illusion)
        call draw_line(hdc, x+1, y+1, x+width-2, y+1, COL_BORDER, 1)
        ! Label bar
        call fill_box(hdc, x + 1, y + 1, x + width - 1, y + 22, COL_PANEL_ALT)
        call draw_text(hdc, x + 8, y + 4, label, COL_MUTED)
        ! Divider
        call draw_line(hdc, x + 1, y + 22, x + width - 1, y + 22, COL_BORDER_SOFT, 1)
        ! Color accent strip on left edge
        call fill_box(hdc, x + 1, y + 22, x + 4, y + height - 1, value_color)
        ! Value text
        call draw_title_text(hdc, x + 10, y + 28, value_text, value_color)
        ! Outer glow border at value_color (1px, only on right+bottom)
        call draw_line(hdc, x, y + height - 1, x + width, y + height - 1, COL_BORDER, 1)
        call draw_line(hdc, x + width - 1, y, x + width - 1, y + height, COL_BORDER, 1)
    end subroutine draw_faceplate

    subroutine draw_annunciator_panel(hdc, x, y, w, h)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, w, h
        integer :: tile_w, gap, tx, i
        character(len=20) :: labels(6)
        logical :: states(6)
        integer(c_int) :: colors(6)

        labels(1) = "UNDER-FREQ"
        labels(2) = "OVER-FREQ"
        labels(3) = "LOW RESERVE"
        labels(4) = "LOW BESS SOC"
        labels(5) = "UFLS ACTIVE"
        labels(6) = "TURBINE MAX"
        states(1) = grid%alarm_underfreq
        states(2) = grid%alarm_overfreq
        states(3) = grid%alarm_low_reserve
        states(4) = grid%alarm_low_soc
        states(5) = grid%alarm_ufls_active
        states(6) = grid%alarm_turbine_max
        colors(1) = COL_RED
        colors(2) = COL_AMBER
        colors(3) = COL_AMBER
        colors(4) = COL_AMBER
        colors(5) = COL_RED
        colors(6) = COL_AMBER

        gap = 4
        tile_w = (w - 7 * gap) / 6

        call fill_box(hdc, x, y, x + w, y + h, COL_PANEL_DEEP)
        call stroke_box(hdc, x, y, x + w, y + h, COL_BORDER, 1)

        do i = 1, 6
            tx = x + gap + (i - 1) * (tile_w + gap)
            if (states(i)) then
                ! Active alarm tile: colored with dark body
                call fill_box(hdc, tx, y + 4, tx + tile_w, y + h - 4, COL_PANEL)
                call fill_box(hdc, tx, y + 4, tx + 4, y + h - 4, colors(i))  ! left accent
                call stroke_box(hdc, tx, y + 4, tx + tile_w, y + h - 4, colors(i), 1)
                ! Lamp circle (filled)
                call hmi_fill_pie(hdc, int(tx + tile_w - 14, c_int), int(y + h/2, c_int), &
                    6_c_int, 0.0_c_float, 360.0_c_float, colors(i))
                call draw_text(hdc, tx + 8, y + (h - 17) / 2, trim(labels(i)), colors(i))
            else
                ! Inactive: dim tile
                call fill_box(hdc, tx, y + 4, tx + tile_w, y + h - 4, COL_PANEL_DEEP)
                call fill_box(hdc, tx, y + 4, tx + 4, y + h - 4, COL_BORDER_SOFT)
                call stroke_box(hdc, tx, y + 4, tx + tile_w, y + h - 4, COL_BORDER_SOFT, 1)
                ! Dim lamp circle
                call hmi_fill_pie(hdc, int(tx + tile_w - 14, c_int), int(y + h/2, c_int), &
                    5_c_int, 0.0_c_float, 360.0_c_float, COL_DIM)
                call draw_text(hdc, tx + 8, y + (h - 17) / 2, trim(labels(i)), COL_DIM)
            end if
        end do
    end subroutine draw_annunciator_panel

    subroutine draw_gauge_bezel(hdc, cx, cy, radius)
        type(c_ptr), value :: hdc
        integer, intent(in) :: cx, cy, radius
        ! Concentric rings simulate a machined bezel on black background
        call hmi_fill_pie(hdc, int(cx,c_int), int(cy,c_int), int(radius+10,c_int), &
            0.0_c_float, 360.0_c_float, COL_BEZEL_RING)
        call hmi_fill_pie(hdc, int(cx,c_int), int(cy,c_int), int(radius+7,c_int), &
            0.0_c_float, 360.0_c_float, COL_BEZEL_HI)
        call hmi_fill_pie(hdc, int(cx,c_int), int(cy,c_int), int(radius+4,c_int), &
            0.0_c_float, 360.0_c_float, COL_BEZEL_RING)
        call hmi_fill_pie(hdc, int(cx,c_int), int(cy,c_int), int(radius+1,c_int), &
            0.0_c_float, 360.0_c_float, COL_BTN_SH)
    end subroutine draw_gauge_bezel

    subroutine draw_gauge_hub(hdc, cx, cy, hub_r, needle_color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: cx, cy, hub_r
        integer(c_int), intent(in) :: needle_color
        call hmi_fill_pie(hdc, int(cx,c_int), int(cy,c_int), int(hub_r+5,c_int), &
            0.0_c_float, 360.0_c_float, COL_BEZEL_RING)
        call hmi_fill_pie(hdc, int(cx,c_int), int(cy,c_int), int(hub_r+3,c_int), &
            0.0_c_float, 360.0_c_float, COL_BTN_SH)
        call hmi_fill_pie(hdc, int(cx,c_int), int(cy,c_int), int(hub_r,c_int), &
            0.0_c_float, 360.0_c_float, needle_color)
    end subroutine draw_gauge_hub

    subroutine draw_arc_gauge_freq(hdc, cx, cy, radius)
        type(c_ptr), value :: hdc
        integer, intent(in) :: cx, cy, radius
        real(c_float), parameter :: GSTART     = 135.0_c_float
        real(c_float), parameter :: DEG_PER_HZ = 45.0_c_float
        integer :: inner_r, hub_r, track_r, tw
        real(c_float) :: start_f
        real(dp) :: frac, ang_rad
        integer :: nx, ny, nx2, ny2
        character(len=24) :: vtext
        integer(c_int) :: ncol

        inner_r = radius - 28
        hub_r   = 10
        track_r = radius - 7
        tw      = 18

        ! Bezel ring
        call draw_gauge_bezel(hdc, cx, cy, radius)
        ! Full gauge face (deep black circle)
        call hmi_fill_pie(hdc, int(cx,c_int), int(cy,c_int), int(radius,c_int), &
            0.0_c_float, 360.0_c_float, COL_GAUGE_FACE)
        ! Unlit track
        call hmi_draw_arc(hdc, int(cx,c_int), int(cy,c_int), int(track_r,c_int), &
            GSTART, 270.0_c_float, COL_GAUGE_TRACK, int(tw,c_int))
        ! Red lo: 47–49 Hz (2 Hz = 90°)
        call hmi_draw_arc(hdc, int(cx,c_int), int(cy,c_int), int(track_r,c_int), &
            GSTART, 2.0_c_float*DEG_PER_HZ, COL_RED, int(tw,c_int))
        ! Amber lo: 49–49.5 Hz
        start_f = GSTART + 2.0_c_float*DEG_PER_HZ
        call hmi_draw_arc(hdc, int(cx,c_int), int(cy,c_int), int(track_r,c_int), &
            start_f, 0.5_c_float*DEG_PER_HZ, COL_AMBER, int(tw,c_int))
        ! Green: 49.5–50.5 Hz
        start_f = GSTART + 2.5_c_float*DEG_PER_HZ
        call hmi_draw_arc(hdc, int(cx,c_int), int(cy,c_int), int(track_r,c_int), &
            start_f, 1.0_c_float*DEG_PER_HZ, COL_GREEN, int(tw,c_int))
        ! Amber hi: 50.5–51 Hz
        start_f = GSTART + 3.5_c_float*DEG_PER_HZ
        call hmi_draw_arc(hdc, int(cx,c_int), int(cy,c_int), int(track_r,c_int), &
            start_f, 0.5_c_float*DEG_PER_HZ, COL_AMBER, int(tw,c_int))
        ! Red hi: 51–53 Hz
        start_f = GSTART + 4.0_c_float*DEG_PER_HZ
        call hmi_draw_arc(hdc, int(cx,c_int), int(cy,c_int), int(track_r,c_int), &
            start_f, 2.0_c_float*DEG_PER_HZ, COL_RED, int(tw,c_int))
        ! Thin inner trim ring
        call hmi_draw_arc(hdc, int(cx,c_int), int(cy,c_int), int(track_r - tw/2,c_int), &
            GSTART, 270.0_c_float, COL_BORDER, 1_c_int)
        ! Tick marks: major at each Hz (12 px long), minor at 0.5 Hz (5 px long)
        block
            integer :: ti
            real(dp) :: ta, tc, ts, tr_outer, tr_inner, tick_len
            character(len=4) :: hz_lbl
            integer :: lhz
            do ti = 0, 12  ! 0.5 Hz steps over 6 Hz range
                ta = (135.0_dp + ti * 22.5_dp) * PI_DP / 180.0_dp
                tc = cos(ta); ts = sin(ta)
                tr_outer = real(track_r - tw/2 + 2, dp)
                if (mod(ti, 2) == 0) then
                    tick_len = 12.0_dp  ! major Hz tick
                else
                    tick_len = 5.0_dp   ! minor 0.5 Hz tick
                end if
                tr_inner = tr_outer - tick_len
                call draw_line(hdc, cx + int(tc*tr_outer), cy + int(ts*tr_outer), &
                    cx + int(tc*tr_inner), cy + int(ts*tr_inner), COL_BORDER, 1)
                ! Label at major ticks (skip cluttered edges at 47 and 53)
                if (mod(ti, 2) == 0) then
                    lhz = 47 + ti / 2
                    if (lhz == 47 .or. lhz == 49 .or. lhz == 50 .or. &
                        lhz == 51 .or. lhz == 53) then
                        write(hz_lbl, '(I2)') lhz
                        call draw_text(hdc, cx + int(tc*(tr_inner - 14.0_dp)) - 6, &
                            cy + int(ts*(tr_inner - 14.0_dp)) - 6, trim(adjustl(hz_lbl)), COL_DIM)
                    end if
                end if
            end do
        end block

        ! Tapered polygon needle (wide at hub, sharp at tip)
        ncol = frequency_color()
        frac = clamp_real((grid%frequency_Hz - 47.0_dp) / 6.0_dp, 0.0_dp, 1.0_dp)
        ang_rad = (135.0_dp + frac * 270.0_dp) * PI_DP / 180.0_dp
        block
            integer(c_int), target :: poly_x(4), poly_y(4)
            real(dp) :: px, py, hw
            hw = 4.5_dp  ! half-width at hub base
            px = -sin(ang_rad); py = cos(ang_rad)  ! perpendicular
            ! tip
            poly_x(1) = int(cx + real(inner_r, dp) * cos(ang_rad), c_int)
            poly_y(1) = int(cy + real(inner_r, dp) * sin(ang_rad), c_int)
            ! right base
            poly_x(2) = int(cx + px * hw + cos(ang_rad) * real(hub_r, dp), c_int)
            poly_y(2) = int(cy + py * hw + sin(ang_rad) * real(hub_r, dp), c_int)
            ! counter-tail
            poly_x(3) = int(cx - cos(ang_rad) * real(hub_r + 10, dp), c_int)
            poly_y(3) = int(cy - sin(ang_rad) * real(hub_r + 10, dp), c_int)
            ! left base
            poly_x(4) = int(cx - px * hw + cos(ang_rad) * real(hub_r, dp), c_int)
            poly_y(4) = int(cy - py * hw + sin(ang_rad) * real(hub_r, dp), c_int)
            call hmi_draw_polygon(hdc, c_loc(poly_x), c_loc(poly_y), 4_c_int, &
                ncol, COL_BTN_SH, 1_c_int)
        end block
        call draw_gauge_hub(hdc, cx, cy, hub_r, ncol)

        call draw_text(hdc, cx - 26, cy - radius - 22, "FREQUENCY", COL_MUTED)

        ! Digital value below needle centre
        write(vtext, '(F7.3," Hz")') grid%frequency_Hz
        call draw_title_text(hdc, cx - 44, cy + 16, trim(adjustl(vtext)), ncol)
        write(vtext, '(SP,F5.3," Hz/s")') grid%ROCOF_Hz_s
        call draw_text(hdc, cx - 36, cy + 44, trim(adjustl(vtext)), COL_MUTED)
    end subroutine draw_arc_gauge_freq

    subroutine draw_arc_gauge_mw(hdc, cx, cy, radius, value, rated_mw, label)
        type(c_ptr), value :: hdc
        integer, intent(in) :: cx, cy, radius
        real(dp), intent(in) :: value, rated_mw
        character(len=*), intent(in) :: label
        real(c_float), parameter :: GSTART = 135.0_c_float
        integer :: inner_r, hub_r, track_r, tw
        real(c_float) :: thresh80, thresh95
        real(dp) :: frac, ang_rad
        integer :: nx, ny, nx2, ny2
        character(len=24) :: vtext
        integer(c_int) :: val_color

        inner_r = radius - 28
        hub_r   = 10
        track_r = radius - 7
        tw      = 18
        thresh80 = GSTART + 0.80_c_float * 270.0_c_float
        thresh95 = GSTART + 0.95_c_float * 270.0_c_float

        call draw_gauge_bezel(hdc, cx, cy, radius)
        call hmi_fill_pie(hdc, int(cx,c_int), int(cy,c_int), int(radius,c_int), &
            0.0_c_float, 360.0_c_float, COL_GAUGE_FACE)
        ! Unlit track
        call hmi_draw_arc(hdc, int(cx,c_int), int(cy,c_int), int(track_r,c_int), &
            GSTART, 270.0_c_float, COL_GAUGE_TRACK, int(tw,c_int))
        ! Green 0–80%
        call hmi_draw_arc(hdc, int(cx,c_int), int(cy,c_int), int(track_r,c_int), &
            GSTART, 0.80_c_float*270.0_c_float, COL_GREEN, int(tw,c_int))
        ! Amber 80–95%
        call hmi_draw_arc(hdc, int(cx,c_int), int(cy,c_int), int(track_r,c_int), &
            thresh80, 0.15_c_float*270.0_c_float, COL_AMBER, int(tw,c_int))
        ! Red 95–100%
        call hmi_draw_arc(hdc, int(cx,c_int), int(cy,c_int), int(track_r,c_int), &
            thresh95, 0.05_c_float*270.0_c_float, COL_RED, int(tw,c_int))
        call hmi_draw_arc(hdc, int(cx,c_int), int(cy,c_int), int(track_r - tw/2,c_int), &
            GSTART, 270.0_c_float, COL_BORDER, 1_c_int)

        frac = clamp_real(value / max(rated_mw, 1.0e-9_dp), 0.0_dp, 1.0_dp)
        if (frac < 0.80_dp) then
            val_color = COL_GREEN
        else if (frac < 0.95_dp) then
            val_color = COL_AMBER
        else
            val_color = COL_RED
        end if
        ang_rad = (135.0_dp + frac * 270.0_dp) * PI_DP / 180.0_dp
        ! Major ticks at 0%, 20%, 40%, 60%, 80%, 100% (6 positions)
        block
            integer :: ti
            real(dp) :: ta, tc, ts, tr_outer, tr_inner
            do ti = 0, 10
                ta = (135.0_dp + ti * 27.0_dp) * PI_DP / 180.0_dp
                tc = cos(ta); ts = sin(ta)
                tr_outer = real(track_r - tw/2 + 2, dp)
                tr_inner = tr_outer - merge(10.0_dp, 4.0_dp, mod(ti, 2) == 0)
                call draw_line(hdc, cx + int(tc*tr_outer), cy + int(ts*tr_outer), &
                    cx + int(tc*tr_inner), cy + int(ts*tr_inner), COL_BORDER, 1)
            end do
        end block
        ! Tapered polygon needle
        block
            integer(c_int), target :: poly_x(4), poly_y(4)
            real(dp) :: px, py, hw
            hw = 4.5_dp
            px = -sin(ang_rad); py = cos(ang_rad)
            poly_x(1) = int(cx + real(inner_r, dp) * cos(ang_rad), c_int)
            poly_y(1) = int(cy + real(inner_r, dp) * sin(ang_rad), c_int)
            poly_x(2) = int(cx + px * hw + cos(ang_rad) * real(hub_r, dp), c_int)
            poly_y(2) = int(cy + py * hw + sin(ang_rad) * real(hub_r, dp), c_int)
            poly_x(3) = int(cx - cos(ang_rad) * real(hub_r + 10, dp), c_int)
            poly_y(3) = int(cy - sin(ang_rad) * real(hub_r + 10, dp), c_int)
            poly_x(4) = int(cx - px * hw + cos(ang_rad) * real(hub_r, dp), c_int)
            poly_y(4) = int(cy - py * hw + sin(ang_rad) * real(hub_r, dp), c_int)
            call hmi_draw_polygon(hdc, c_loc(poly_x), c_loc(poly_y), 4_c_int, &
                val_color, COL_BTN_SH, 1_c_int)
        end block
        call draw_gauge_hub(hdc, cx, cy, hub_r, val_color)

        call draw_text(hdc, cx - radius - 4, cy + 6, "0", COL_DIM)
        write(vtext, '(I0)') int(rated_mw)
        call draw_text(hdc, cx + radius - 16, cy + 6, trim(vtext), COL_DIM)
        call draw_text(hdc, cx - len_trim(label)*5, cy - radius - 22, label, COL_MUTED)

        write(vtext, '(F6.1," MW")') value
        call draw_title_text(hdc, cx - 36, cy + 16, trim(adjustl(vtext)), val_color)
        write(vtext, '(F5.1,"%")') frac * 100.0_dp
        call draw_text(hdc, cx - 16, cy + 44, trim(adjustl(vtext)), COL_MUTED)
    end subroutine draw_arc_gauge_mw

    subroutine draw_vertical_soc_bar(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: fill_h, bar_top, bar_h, bx, bw, seg_h, seg_top
        integer(c_int) :: bar_color, seg_col
        character(len=24) :: line
        integer :: qi
        real(dp) :: seg_frac

        bx    = x + 16
        bw    = width - 32
        bar_h = height - 56
        bar_top = y + 28

        if (grid%battery_soc_pct < 15.0_dp) then
            bar_color = COL_RED
        else if (grid%battery_soc_pct < 30.0_dp) then
            bar_color = COL_AMBER
        else
            bar_color = COL_BLUE
        end if

        ! Outer bezel frame
        call fill_box(hdc, bx - 3, bar_top - 3, bx + bw + 3, bar_top + bar_h + 3, COL_BEZEL_RING)
        ! Inner well
        call fill_box(hdc, bx, bar_top, bx + bw, bar_top + bar_h, COL_GAUGE_FACE)

        ! Draw segmented fill (10 segments = 10% each)
        fill_h = int(real(bar_h, dp) * clamp_real(grid%battery_soc_pct / 100.0_dp, 0.0_dp, 1.0_dp))
        seg_h = bar_h / 10
        do qi = 0, 9
            seg_frac = real(qi, dp) / 10.0_dp + 0.05_dp
            seg_top = bar_top + bar_h - (qi + 1) * seg_h
            if (seg_frac * 100.0_dp <= grid%battery_soc_pct) then
                if (seg_frac < 0.20_dp) then
                    seg_col = COL_RED
                else if (seg_frac < 0.35_dp) then
                    seg_col = COL_AMBER
                else
                    seg_col = COL_BLUE
                end if
                call fill_box(hdc, bx + 1, seg_top + 1, bx + bw - 1, seg_top + seg_h - 1, seg_col)
            end if
        end do
        ! Gap lines between segments
        do qi = 1, 9
            call draw_line(hdc, bx, bar_top + bar_h - qi * seg_h, &
                bx + bw, bar_top + bar_h - qi * seg_h, COL_GAUGE_FACE, 2)
        end do
        ! Outer border
        call stroke_box(hdc, bx - 3, bar_top - 3, bx + bw + 3, bar_top + bar_h + 3, COL_BORDER, 1)
        ! Tick marks: 25/50/75%
        call draw_line(hdc, bx - 8, bar_top + bar_h * 3 / 4, bx - 4, bar_top + bar_h * 3 / 4, COL_MUTED, 1)
        call draw_line(hdc, bx - 8, bar_top + bar_h / 2,     bx - 4, bar_top + bar_h / 2,     COL_MUTED, 1)
        call draw_line(hdc, bx - 8, bar_top + bar_h / 4,     bx - 4, bar_top + bar_h / 4,     COL_MUTED, 1)

        ! Label above
        call draw_text(hdc, bx, y + 6,  "BESS", COL_MUTED)
        call draw_text(hdc, bx, y + 18, "SOC",  COL_DIM)
        ! Value below
        write(line, '(F5.1,"%")') grid%battery_soc_pct
        call draw_text(hdc, bx, bar_top + bar_h + 6, trim(adjustl(line)), bar_color)
        ! BESS active indicator
        if (abs(grid%storage_MW) > 0.1_dp) then
            if (grid%storage_MW > 0.0_dp) then
                write(line, '("+",F4.1)') grid%storage_MW
                call draw_text(hdc, bx, bar_top + bar_h + 24, trim(line), COL_GREEN)
            else
                write(line, '(F5.1)') grid%storage_MW
                call draw_text(hdc, bx, bar_top + bar_h + 24, trim(line), COL_AMBER)
            end if
        end if
    end subroutine draw_vertical_soc_bar

    subroutine draw_kpi_tiles(hdc, x, y, width)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width
        integer :: i, tx, ty, tile_w, gap
        character(len=64) :: value

        gap = 16
        tile_w = max(130, (width - 3 * gap) / 4)
        do i = 0, 3
            tx = x + i * (tile_w + gap)
            call fill_soft_box(hdc, tx, y, tx + tile_w, y + 72, COL_PANEL_ALT)
            call stroke_soft_box(hdc, tx, y, tx + tile_w, y + 72, COL_BORDER_SOFT, 1)
            call fill_box(hdc, tx, y, tx + tile_w, y + 2, COL_BORDER)
        end do

        write(value, '(F6.1," MW")') grid%gas_power_MW
        call draw_text(hdc, x + 12, y + 14, "Turbine MW", COL_MUTED)
        call draw_text(hdc, x + 12, y + 40, adjustl(value), COL_INK)

        write(value, '(F7.2," Hz")') grid%frequency_Hz
        call draw_text(hdc, x + tile_w + gap + 12, y + 14, "Grid frequency", COL_MUTED)
        call draw_text(hdc, x + tile_w + gap + 12, y + 40, adjustl(value), frequency_color())

        write(value, '(SP,F6.1," MW")') grid%imbalance_MW
        ty = y + 40
        call draw_text(hdc, x + 2 * (tile_w + gap) + 12, y + 14, "Net imbalance", COL_MUTED)
        if (abs(grid%imbalance_MW) <= 0.5_dp) then
            call draw_text(hdc, x + 2 * (tile_w + gap) + 12, ty, adjustl(value), COL_GREEN)
        else
            call draw_text(hdc, x + 2 * (tile_w + gap) + 12, ty, adjustl(value), COL_RED)
        end if

        write(value, '("$",F7.0,"/h")') grid%margin_usd_h
        call draw_text(hdc, x + 3 * (tile_w + gap) + 12, y + 14, "Net margin", COL_MUTED)
        if (grid%margin_usd_h >= 0.0_dp) then
            call draw_text(hdc, x + 3 * (tile_w + gap) + 12, y + 40, adjustl(value), COL_GREEN)
        else if (grid%margin_usd_h > -1000.0_dp) then
            call draw_text(hdc, x + 3 * (tile_w + gap) + 12, y + 40, adjustl(value), COL_AMBER)
        else
            call draw_text(hdc, x + 3 * (tile_w + gap) + 12, y + 40, adjustl(value), COL_RED)
        end if
    end subroutine draw_kpi_tiles

    subroutine draw_section_title_width(hdc, x, y, text, width)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width
        character(len=*), intent(in) :: text

        call draw_text(hdc, x, y, text, COL_INK)
        call draw_line(hdc, x, y + 21, x + width, y + 21, COL_BORDER_SOFT, 1)
    end subroutine draw_section_title_width

    subroutine draw_bar(hdc, x, y, width, height, label, value, maximum, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        character(len=*), intent(in) :: label
        real(dp), intent(in) :: value, maximum
        integer(c_int), intent(in) :: color
        integer :: fill_w
        character(len=96) :: text

        fill_w = int(real(width, dp) * clamp_real(value / max(maximum, 1.0e-9_dp), 0.0_dp, 1.0_dp))
        call fill_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
        call fill_box(hdc, x, y, x + fill_w, y + height, color)
        call stroke_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)
        write(text, '(A,": ",F6.1," MW")') trim(label), value
        call draw_text(hdc, x + 10, y + 5, adjustl(text), COL_PANEL_DEEP)
    end subroutine draw_bar

    subroutine draw_stacked_supply(hdc, x, y, width, height, maximum, gas_color, renewable_color, storage_color, sink_color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        real(dp), intent(in) :: maximum
        integer(c_int), intent(in) :: gas_color, renewable_color, storage_color, sink_color
        integer :: cursor, seg_w
        character(len=128) :: text

        call fill_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
        cursor = x
        seg_w = scaled_width(grid%gas_power_MW, maximum, width)
        call fill_box(hdc, cursor, y, cursor + seg_w, y + height, gas_color)
        cursor = cursor + seg_w
        seg_w = scaled_width(effective_renewable_MW(), maximum, width)
        call fill_box(hdc, cursor, y, cursor + seg_w, y + height, renewable_color)
        cursor = cursor + seg_w
        ! Curtailed renewable energy shown as hatched dim segment
        if (grid%renewable_curtail_MW > 0.05_dp) then
            seg_w = scaled_width(grid%renewable_curtail_MW, maximum, width)
            call fill_box(hdc, cursor, y, cursor + seg_w, y + height, COL_PANEL_ALT)
            call stroke_box(hdc, cursor, y, cursor + seg_w, y + height, COL_AMBER, 1)
            cursor = cursor + seg_w
        end if
        if (grid%storage_MW >= 0.0_dp) then
            seg_w = scaled_width(grid%storage_MW, maximum, width)
            call fill_box(hdc, cursor, y, cursor + seg_w, y + height, storage_color)
        else
            seg_w = scaled_width(abs(grid%storage_MW), maximum, width)
            call fill_box(hdc, x + width - seg_w, y, x + width, y + height, sink_color)
        end if
        call stroke_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)
        write(text, '("Gas ",F5.1,"  Renew ",F5.1,"  BESS ",SP,F5.1," MW")') &
            grid%gas_power_MW, effective_renewable_MW(), grid%storage_MW
        call draw_text(hdc, x + 10, y + 8, adjustl(text), COL_PANEL_DEEP)
    end subroutine draw_stacked_supply

    subroutine draw_battery_panel(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: fill_w
        integer(c_int) :: color
        character(len=128) :: line1, line2

        if (height < 1) return
        if (grid%battery_soc_pct < 15.0_dp .or. grid%battery_soc_pct > 95.0_dp) then
            color = COL_RED
        else
            color = COL_BLUE
        end if

        fill_w = int(real(width - 190, dp) * clamp_real(grid%battery_soc_pct / 100.0_dp, 0.0_dp, 1.0_dp))
        call fill_box(hdc, x, y, x + width - 190, y + 24, COL_PANEL_ALT)
        call fill_box(hdc, x, y, x + fill_w, y + 24, color)
        call stroke_box(hdc, x, y, x + width - 190, y + 24, COL_BORDER_SOFT, 1)

        write(line1, '("SOC ",F5.1,"%   ",F5.1,"/",F4.0," MWh")') &
            grid%battery_soc_pct, grid%battery_energy_MWh, BATTERY_CAPACITY_MWH
        call draw_text(hdc, x + width - 176, y + 5, adjustl(line1), COL_INK)

        write(line2, '("Command ",SP,F5.1," MW   Actual ",SP,F5.1," MW")') &
            grid%storage_request_MW, grid%storage_MW
        call draw_text(hdc, x, y + 36, adjustl(line2), COL_MUTED)
    end subroutine draw_battery_panel

    subroutine draw_roi_panel(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        character(len=96) :: line
        real(dp) :: net_usd_mwh, capacity_pct
        integer(c_int) :: margin_color

        if (height < 1) return
        net_usd_mwh = grid%margin_usd_h / max(grid%demand_MW, 1.0_dp)
        capacity_pct = 100.0_dp * grid%gas_power_MW / max(grid%gas_capacity_MW, 1.0e-9_dp)
        margin_color = merge(COL_GREEN, COL_RED, grid%margin_usd_h >= 0.0_dp)

        call fill_soft_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
        call stroke_soft_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)
        call draw_line(hdc, x + width / 4, y + 8, x + width / 4, y + height - 8, COL_BORDER_SOFT, 1)
        call draw_line(hdc, x + width / 2, y + 8, x + width / 2, y + height - 8, COL_BORDER_SOFT, 1)
        call draw_line(hdc, x + 3 * width / 4, y + 8, x + 3 * width / 4, y + height - 8, COL_BORDER_SOFT, 1)

        call draw_text(hdc, x + 12, y + 10, "Revenue", COL_MUTED)
        write(line, '("$",F7.0,"/h")') grid%revenue_usd_h
        call draw_text(hdc, x + 12, y + 34, adjustl(line), COL_INK)

        call draw_text(hdc, x + width / 4 + 12, y + 10, "Fuel + penalty", COL_MUTED)
        write(line, '("$",F7.0,"/h")') grid%fuel_cost_usd_h + grid%imbalance_penalty_usd_h
        call draw_text(hdc, x + width / 4 + 12, y + 34, adjustl(line), COL_AMBER)

        call draw_text(hdc, x + width / 2 + 12, y + 10, "Net value", COL_MUTED)
        write(line, '("$",F6.1,"/MWh")') net_usd_mwh
        call draw_text(hdc, x + width / 2 + 12, y + 34, adjustl(line), margin_color)

        call draw_text(hdc, x + 3 * width / 4 + 12, y + 10, "Heat rate", COL_MUTED)
        write(line, '(F7.0," kJ/kWh")') grid%heat_rate_kJ_kWh
        call draw_text(hdc, x + 3 * width / 4 + 12, y + 34, adjustl(line), COL_INK)

        write(line, '("Heat ",F5.1," MWth   Fuel ",F4.2," kg/s   Capacity ",F5.1,"%")') &
            grid%heat_input_MW, grid%fuel_flow_kg_s, capacity_pct
        call draw_text(hdc, x + 12, y + 60, adjustl(line), COL_MUTED)

        if (grid%battery_payback_years < 98.0_dp) then
            write(line, '("BESS value $",F5.0,"/h   payback ",F4.1," yr @ ",F4.0," h/yr")') &
                grid%battery_value_usd_h, grid%battery_payback_years, ROI_EQUIVALENT_HOURS_PER_YEAR
        else
            write(line, '("BESS value $",F5.0,"/h   payback: standby/no arbitrage")') &
                grid%battery_value_usd_h
        end if
        call draw_text(hdc, x + 408, y + 60, adjustl(line), COL_MUTED)

        write(line, '("CO2  ",F5.2," kg/s   ",F6.1," g/kWh   ",F7.3," t session")') &
            grid%CO2_rate_kg_s, grid%CO2_intensity_g_kWh, grid%CO2_cumulative_t
        call draw_text(hdc, x + 12, y + 84, adjustl(line), COL_MUTED)
    end subroutine draw_roi_panel

    subroutine draw_history_traces(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: gx, gy, gw, gh, gi
        character(len=20) :: lbl

        ! Panel shell: left accent strip + dark body
        call fill_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
        call fill_box(hdc, x, y, x + 5, y + height, COL_AMBER)
        call draw_line(hdc, x, y, x + width, y, COL_BORDER, 1)
        call draw_line(hdc, x, y + height, x + width, y + height, COL_BORDER, 1)

        ! Plot area layout: left margin for Y-axis labels
        gx = x + 44
        gy = y + 26
        gw = width - 52
        gh = height - 36

        ! Plot area background
        call fill_box(hdc, gx, gy, gx + gw, gy + gh, COL_BG)

        ! Horizontal grid lines at 25 / 50 / 75 %
        do gi = 1, 3
            call draw_line(hdc, gx, gy + gi * gh / 4, gx + gw, gy + gi * gh / 4, COL_BG_GRID, 1)
        end do
        ! Vertical grid lines at 25 / 50 / 75 %
        do gi = 1, 3
            call draw_line(hdc, gx + gi * gw / 4, gy, gx + gi * gw / 4, gy + gh, COL_BG_GRID, 1)
        end do
        ! Nominal 50 Hz centre line — slightly brighter
        call draw_line(hdc, gx, gy + gh / 2, gx + gw, gy + gh / 2, COL_BORDER, 1)

        ! Y-axis labels (left, in Hz units of the frequency range)
        call draw_text(hdc, x + 6, gy - 7,       "51.5", COL_DIM)
        call draw_text(hdc, x + 6, gy + gh/2 - 7,"50.0", COL_AMBER)
        call draw_text(hdc, x + 6, gy + gh - 7,  "48.5", COL_DIM)

        ! Plot area border
        call stroke_box(hdc, gx, gy, gx + gw, gy + gh, COL_BORDER_SOFT, 1)

        if (grid%history_count < 2) then
            call draw_text(hdc, gx + 40, gy + gh / 2 - 8, "Waiting for samples...", COL_MUTED)
        else
            call draw_trace(hdc, gx, gy, gw, gh, 1, 48.5_dp, 51.5_dp, COL_AMBER)
            call draw_trace(hdc, gx, gy, gw, gh, 2, 0.0_dp, DEMAND_MAX_MW, COL_RED)
            call draw_trace(hdc, gx, gy, gw, gh, 3, 0.0_dp, 100.0_dp, COL_LIME)
        end if

        ! Live legend with current values
        write(lbl, '(F7.3," Hz")') grid%frequency_Hz
        call draw_text(hdc, gx + 4,  y + 8, trim(adjustl(lbl)), COL_AMBER)
        write(lbl, '(F5.1," MW")') grid%demand_MW
        call draw_text(hdc, gx + 106, y + 8, trim(adjustl(lbl)), COL_RED)
        write(lbl, '(F5.1,"%")') grid%gas_dispatch_pct
        call draw_text(hdc, gx + 210, y + 8, trim(adjustl(lbl)), COL_LIME)
    end subroutine draw_history_traces

    subroutine draw_trace(hdc, x, y, width, height, series, lo, hi, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height, series
        real(dp), intent(in) :: lo, hi
        integer(c_int), intent(in) :: color
        integer :: i, idx, px, py, prev_x, prev_y
        real(dp) :: value, norm

        prev_x = x
        prev_y = y + height
        do i = 1, grid%history_count
            idx = history_index(i)
            select case (series)
            case (1)
                value = grid%hist_frequency_Hz(idx)
            case (2)
                value = grid%hist_demand_MW(idx)
            case default
                value = grid%hist_gas_dispatch_pct(idx)
            end select
            norm = clamp_real((value - lo) / max(hi - lo, 1.0e-9_dp), 0.0_dp, 1.0_dp)
            if (grid%history_count > 1) then
                px = x + int(real(width, dp) * real(i - 1, dp) / real(grid%history_count - 1, dp))
            else
                px = x
            end if
            py = y + height - int(real(height, dp) * norm)
            if (i > 1) call draw_line(hdc, prev_x, prev_y, px, py, color, 2)
            prev_x = px
            prev_y = py
        end do
    end subroutine draw_trace

    function history_index(position) result(idx)
        integer, intent(in) :: position
        integer :: idx

        idx = mod(grid%history_head - grid%history_count + position - 1 + HISTORY_N, HISTORY_N) + 1
    end function history_index

    subroutine draw_frequency_meter(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: center_x, marker_x
        real(dp) :: frac

        if (height < 1) return
        call fill_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
        center_x = x + width / 2
        call fill_box(hdc, center_x - 34, y, center_x + 34, y + height, int(Z'00406040', c_int))
        call stroke_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)
        call draw_line(hdc, center_x, y, center_x, y + height, COL_GREEN, 1)
        frac = clamp_real((grid%frequency_Hz - 48.5_dp) / 3.0_dp, 0.0_dp, 1.0_dp)
        marker_x = x + int(frac * real(width, dp))
        call draw_line(hdc, marker_x, y - 4, marker_x, y + height + 4, frequency_color(), 4)
        call draw_text(hdc, x, y + height + 8, "48.5 Hz", COL_DIM)
        call draw_text(hdc, center_x - 30, y + height + 8, "50.0 Hz", COL_DIM)
        call draw_text(hdc, x + width - 62, y + height + 8, "51.5 Hz", COL_DIM)
    end subroutine draw_frequency_meter

    subroutine draw_power_flow(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        character(len=64) :: text
        integer :: node_w, node_h, row_gap, row1, row2, row3
        integer :: grid_x, grid_y, grid_w, grid_h, load_x, center_y
        integer :: diagram_y, diagram_h

        diagram_h = min(height, 230)
        diagram_y = y + max(0, (height - diagram_h) / 2)
        node_w = min(max(88, width / 4), 120)
        node_h = max(30, min(38, (diagram_h - 16) / 3))
        row_gap = max(6, (diagram_h - 3 * node_h) / 2)
        row1 = diagram_y + max(0, (diagram_h - 3 * node_h - 2 * row_gap) / 2)
        row2 = row1 + node_h + row_gap
        row3 = row2 + node_h + row_gap
        grid_w = min(max(78, width / 5), 120)
        grid_h = max(48, min(62, diagram_h / 2))
        grid_x = x + width / 2 - grid_w / 2
        grid_y = diagram_y + diagram_h / 2 - grid_h / 2
        load_x = x + width - node_w
        center_y = grid_y + grid_h / 2

        call draw_node(hdc, x, row1, node_w, node_h, "Gas", grid%gas_power_MW, COL_LIME)
        call draw_node(hdc, x, row2, node_w, node_h, "Renew", effective_renewable_MW(), &
            merge(COL_AMBER, COL_GREEN, grid%renewable_curtail_MW > 0.05_dp))
        call draw_node(hdc, x, row3, node_w, node_h, "BESS", grid%storage_MW, COL_BLUE)

        ! GRID central node — larger, 2px colour border, imbalance readout
        call fill_box(hdc, grid_x, grid_y, grid_x + grid_w, grid_y + grid_h, COL_BTN_SH)
        call fill_box(hdc, grid_x+1, grid_y+1, grid_x+grid_w-1, grid_y+grid_h-1, COL_PANEL)
        call fill_box(hdc, grid_x+1, grid_y+1, grid_x+5, grid_y+grid_h-1, frequency_color())
        call draw_line(hdc, grid_x+1, grid_y+1, grid_x+grid_w-2, grid_y+1, COL_BORDER, 1)
        call stroke_box(hdc, grid_x, grid_y, grid_x+grid_w, grid_y+grid_h, frequency_color(), 2)
        call draw_text(hdc, grid_x + 9, grid_y + 6, "GRID", COL_MUTED)
        write(text, '(F7.3," Hz")') grid%frequency_Hz
        call draw_text(hdc, grid_x + 9, grid_y + 22, trim(adjustl(text)), frequency_color())
        write(text, '(SP,F5.1," MW")') grid%imbalance_MW
        call draw_text(hdc, grid_x + 9, grid_y + 38, trim(adjustl(text)), &
            merge(COL_GREEN, COL_RED, abs(grid%imbalance_MW) <= 0.5_dp))

        call draw_node(hdc, load_x, row2, node_w, node_h, "Load", grid%demand_MW, COL_RED)
        call draw_line(hdc, x + node_w, row1 + node_h / 2, grid_x, grid_y + 14, COL_LIME, 2)
        call draw_line(hdc, x + node_w, row2 + node_h / 2, grid_x, center_y, COL_GREEN, 2)
        call draw_line(hdc, x + node_w, row3 + node_h / 2, grid_x, grid_y + grid_h - 14, COL_BLUE, 2)
        call draw_line(hdc, grid_x + grid_w, center_y, load_x, row2 + node_h / 2, COL_RED, 2)
    end subroutine draw_power_flow

    subroutine draw_node(hdc, x, y, width, height, label, value, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        character(len=*), intent(in) :: label
        real(dp), intent(in) :: value
        integer(c_int), intent(in) :: color
        character(len=64) :: text

        ! Outer shadow frame
        call fill_box(hdc, x, y, x + width, y + height, COL_BTN_SH)
        ! Inset body
        call fill_box(hdc, x+1, y+1, x+width-1, y+height-1, COL_PANEL_DEEP)
        ! Left colour accent stripe
        call fill_box(hdc, x+1, y+1, x+4, y+height-1, color)
        ! Top highlight
        call draw_line(hdc, x+1, y+1, x+width-2, y+1, COL_BORDER, 1)
        ! Colour border
        call stroke_box(hdc, x, y, x+width, y+height, color, 1)
        ! Text
        call draw_text(hdc, x + 8, y + 5, label, COL_MUTED)
        write(text, '(SP,F6.1," MW")') value
        call draw_text(hdc, x + 8, y + height/2, trim(adjustl(text)), color)
    end subroutine draw_node

    subroutine grid_status(text, color)
        character(len=*), intent(out) :: text
        integer(c_int), intent(out) :: color

        if (abs(grid%imbalance_MW) <= 0.5_dp) then
            text = "Grid balanced | supply matches demand within 0.5 MW"
            color = COL_GREEN
        else if (grid%imbalance_MW < 0.0_dp) then
            text = "Grid shortage | raise turbine, discharge BESS, add renewables, or lower demand"
            color = COL_RED
        else
            text = "Grid surplus | lower turbine, charge BESS, curtail renewables, or raise demand"
            color = COL_AMBER
        end if
    end subroutine grid_status

    function frequency_color() result(color)
        integer(c_int) :: color
        real(dp) :: dev

        dev = abs(grid%frequency_Hz - FREQ_NOMINAL_HZ)
        if (dev <= 0.05_dp) then
            color = COL_GREEN
        else if (dev <= 0.5_dp) then
            color = COL_AMBER
        else
            color = COL_RED
        end if
    end function frequency_color

    function scaled_width(value, maximum, width) result(fill_w)
        real(dp), intent(in) :: value, maximum
        integer, intent(in) :: width
        integer :: fill_w

        fill_w = int(real(width, dp) * clamp_real(value / max(maximum, 1.0e-9_dp), 0.0_dp, 1.0_dp))
    end function scaled_width

    subroutine fill_box(hdc, left, top, right, bottom, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: left, top, right, bottom
        integer(c_int), intent(in) :: color
        type(Rect) :: r
        type(c_ptr) :: brush
        integer(c_int) :: ok

        if (native_renderer_ready) then
            call hmi_fill_rect(hdc, int(left, c_int), int(top, c_int), int(right, c_int), &
                int(bottom, c_int), color)
            return
        end if
        r%left = left
        r%top = top
        r%right = right
        r%bottom = bottom
        brush = CreateSolidBrush(color)
        ok = FillRect(hdc, r, brush)
        ok = DeleteObject(brush)
    end subroutine fill_box

    subroutine fill_soft_box(hdc, left, top, right, bottom, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: left, top, right, bottom
        integer(c_int), intent(in) :: color

        if (native_renderer_ready) then
            call hmi_fill_round_rect(hdc, int(left, c_int), int(top, c_int), int(right, c_int), &
                int(bottom, c_int), 3_c_int, color)
        else
            call fill_box(hdc, left, top, right, bottom, color)
        end if
    end subroutine fill_soft_box

    subroutine stroke_box(hdc, left, top, right, bottom, color, width)
        type(c_ptr), value :: hdc
        integer, intent(in) :: left, top, right, bottom, width
        integer(c_int), intent(in) :: color

        if (native_renderer_ready) then
            call hmi_stroke_rect(hdc, int(left, c_int), int(top, c_int), int(right, c_int), &
                int(bottom, c_int), color, int(width, c_int))
            return
        end if
        call draw_line(hdc, left, top, right, top, color, width)
        call draw_line(hdc, right, top, right, bottom, color, width)
        call draw_line(hdc, right, bottom, left, bottom, color, width)
        call draw_line(hdc, left, bottom, left, top, color, width)
    end subroutine stroke_box

    subroutine stroke_soft_box(hdc, left, top, right, bottom, color, width)
        type(c_ptr), value :: hdc
        integer, intent(in) :: left, top, right, bottom, width
        integer(c_int), intent(in) :: color

        if (native_renderer_ready) then
            call hmi_stroke_round_rect(hdc, int(left, c_int), int(top, c_int), int(right, c_int), &
                int(bottom, c_int), 3_c_int, color, int(width, c_int))
        else
            call stroke_box(hdc, left, top, right, bottom, color, width)
        end if
    end subroutine stroke_soft_box

    subroutine draw_line(hdc, x1, y1, x2, y2, color, width)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x1, y1, x2, y2, width
        integer(c_int), intent(in) :: color
        type(c_ptr) :: pen, old_pen
        integer(c_int) :: ok

        if (native_renderer_ready) then
            call hmi_draw_line(hdc, int(x1, c_int), int(y1, c_int), int(x2, c_int), &
                int(y2, c_int), color, int(width, c_int))
            return
        end if
        pen = CreatePen(PS_SOLID, int(width, c_int), color)
        old_pen = SelectObject(hdc, pen)
        ok = MoveToEx(hdc, int(x1, c_int), int(y1, c_int), c_null_ptr)
        ok = LineTo(hdc, int(x2, c_int), int(y2, c_int))
        old_pen = SelectObject(hdc, old_pen)
        ok = DeleteObject(pen)
    end subroutine draw_line

    subroutine draw_text(hdc, x, y, text, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y
        character(len=*), intent(in) :: text
        integer(c_int), intent(in) :: color
        character(kind=c_char), allocatable, target :: c_text(:)
        type(c_ptr) :: old_font
        integer(c_int) :: ignored, ok
        integer :: n

        n = len_trim(text)
        if (n <= 0) return
        call make_c_string(text(1:n), c_text)
        if (native_renderer_ready) then
            call hmi_draw_text_native(hdc, int(x, c_int), int(y, c_int), c_loc(c_text), &
                17_c_int, FW_NORMAL, color)
            return
        end if
        if (c_associated(h_font_ui)) old_font = SelectObject(hdc, h_font_ui)
        ignored = SetTextColor(hdc, color)
        ignored = SetBkMode(hdc, TRANSPARENT)
        ok = TextOutA(hdc, int(x, c_int), int(y, c_int), c_loc(c_text), int(n, c_int))
        if (c_associated(h_font_ui)) old_font = SelectObject(hdc, old_font)
    end subroutine draw_text

    subroutine draw_title_text(hdc, x, y, text, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y
        character(len=*), intent(in) :: text
        integer(c_int), intent(in) :: color
        character(kind=c_char), allocatable, target :: c_text(:)
        type(c_ptr) :: old_font
        integer(c_int) :: ignored, ok
        integer :: n

        n = len_trim(text)
        if (n <= 0) return
        call make_c_string(text(1:n), c_text)
        if (native_renderer_ready) then
            call hmi_draw_text_native(hdc, int(x, c_int), int(y, c_int), c_loc(c_text), &
                24_c_int, FW_SEMIBOLD, color)
            return
        end if
        if (c_associated(h_font_title)) old_font = SelectObject(hdc, h_font_title)
        ignored = SetTextColor(hdc, color)
        ignored = SetBkMode(hdc, TRANSPARENT)
        ok = TextOutA(hdc, int(x, c_int), int(y, c_int), c_loc(c_text), int(n, c_int))
        if (c_associated(h_font_title)) old_font = SelectObject(hdc, old_font)
    end subroutine draw_title_text

    subroutine reset_debug_log()
        integer :: unit, ios

        open(newunit=unit, file=DEBUG_LOG, status="replace", action="write", iostat=ios)
        if (ios == 0) then
            write(unit, "(A)") "ThermoTwin-F GUI debug log"
            close(unit)
        end if
    end subroutine reset_debug_log

    subroutine log_debug(message)
        character(len=*), intent(in) :: message
        integer :: unit, ios

        open(newunit=unit, file=DEBUG_LOG, status="old", position="append", action="write", iostat=ios)
        if (ios /= 0) return
        write(unit, "(A)") trim(message)
        close(unit)
    end subroutine log_debug

    subroutine fatal_gui(message)
        character(len=*), intent(in) :: message
        character(kind=c_char), allocatable, target :: c_text(:), c_caption(:)
        integer(c_int) :: ignored

        call log_debug("fatal: " // trim(message))
        call make_c_string(message, c_text)
        call make_c_string("ThermoTwin-F GUI", c_caption)
        ignored = MessageBoxA(c_null_ptr, c_loc(c_text), c_loc(c_caption), 0_c_int)
    end subroutine fatal_gui

    subroutine make_c_string(text, c_text)
        character(len=*), intent(in) :: text
        character(kind=c_char), allocatable, target, intent(out) :: c_text(:)
        integer :: i, n

        n = len_trim(text)
        allocate(c_text(n + 1))
        do i = 1, n
            c_text(i) = text(i:i)
        end do
        c_text(n + 1) = c_null_char
    end subroutine make_c_string

    pure function clamp_real(value, lo, hi) result(clamped)
        real(dp), intent(in) :: value, lo, hi
        real(dp) :: clamped

        clamped = min(max(value, lo), hi)
    end function clamp_real

    pure function loword(value) result(word)
        integer(c_intptr_t), intent(in) :: value
        integer(c_int) :: word

        word = int(iand(value, int(Z'FFFF', c_intptr_t)), c_int)
    end function loword

    pure function mouse_x(value) result(x)
        integer(c_intptr_t), intent(in) :: value
        integer :: x

        x = signed_word(iand(value, int(Z'FFFF', c_intptr_t)))
    end function mouse_x

    pure function mouse_y(value) result(y)
        integer(c_intptr_t), intent(in) :: value
        integer :: y

        y = signed_word(iand(ishft(value, -16), int(Z'FFFF', c_intptr_t)))
    end function mouse_y

    pure function signed_word(value) result(word)
        integer(c_intptr_t), intent(in) :: value
        integer :: word

        word = int(value)
        if (word >= 32768) word = word - 65536
    end function signed_word

    function int_to_cptr(value) result(ptr)
        integer(c_int), intent(in) :: value
        type(c_ptr) :: ptr
        integer(c_intptr_t) :: raw

        raw = int(value, c_intptr_t)
        ptr = transfer(raw, ptr)
    end function int_to_cptr

end module thermotwin_win32_gui

program thermotwin_gui
    use thermotwin_win32_gui, only: run_gui
    implicit none

    call run_gui()
end program thermotwin_gui
