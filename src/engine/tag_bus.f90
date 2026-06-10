!> @file tag_bus.f90
!> @brief Flat process-tag registry — the data spine of the revamp.
!>
!> Every consumer (HMI, future OPC UA server, CSV logger, scenario assertions)
!> reads the same named tags. Tags carry value, engineering units, a quality
!> flag, and the simulation timestamp of the last write.
module tag_bus
    use precision_kinds, only: dp
    implicit none
    private

    public :: tag_set, tag_get, tag_count, tag_name_at, tag_value_at
    public :: tag_units_at, tag_clear_all
    public :: TAG_QUALITY_GOOD, TAG_QUALITY_BAD, TAG_NAME_LEN, TAG_UNITS_LEN

    integer, parameter :: TAG_CAPACITY = 192
    integer, parameter :: TAG_NAME_LEN = 64
    integer, parameter :: TAG_UNITS_LEN = 16
    integer, parameter :: TAG_QUALITY_GOOD = 0
    integer, parameter :: TAG_QUALITY_BAD = 1

    type :: Tag
        character(len=TAG_NAME_LEN) :: name = ""
        character(len=TAG_UNITS_LEN) :: units = ""
        real(dp) :: value = 0.0_dp
        integer :: quality = TAG_QUALITY_BAD
        real(dp) :: timestamp_s = 0.0_dp
    end type Tag

    type(Tag) :: registry(TAG_CAPACITY)
    integer :: n_tags = 0

contains

    !> Create or update a tag (upsert by name).
    subroutine tag_set(name, value, units, t_s)
        character(len=*), intent(in) :: name
        real(dp), intent(in) :: value
        character(len=*), intent(in) :: units
        real(dp), intent(in) :: t_s
        integer :: i

        i = find_tag(name)
        if (i == 0) then
            if (n_tags >= TAG_CAPACITY) return   ! silently full; capacity is a build-time choice
            n_tags = n_tags + 1
            i = n_tags
            registry(i)%name = name
            registry(i)%units = units
        end if
        registry(i)%value = value
        registry(i)%quality = TAG_QUALITY_GOOD
        registry(i)%timestamp_s = t_s
    end subroutine tag_set

    !> Read a tag by name. found=.false. (and value=0) when absent.
    subroutine tag_get(name, value, found)
        character(len=*), intent(in) :: name
        real(dp), intent(out) :: value
        logical, intent(out) :: found
        integer :: i

        i = find_tag(name)
        found = i > 0
        if (found) then
            value = registry(i)%value
        else
            value = 0.0_dp
        end if
    end subroutine tag_get

    pure function tag_count() result(n)
        integer :: n
        n = n_tags
    end function tag_count

    pure function tag_name_at(i) result(name)
        integer, intent(in) :: i
        character(len=TAG_NAME_LEN) :: name
        name = ""
        if (i >= 1 .and. i <= n_tags) name = registry(i)%name
    end function tag_name_at

    pure function tag_value_at(i) result(value)
        integer, intent(in) :: i
        real(dp) :: value
        value = 0.0_dp
        if (i >= 1 .and. i <= n_tags) value = registry(i)%value
    end function tag_value_at

    pure function tag_units_at(i) result(units)
        integer, intent(in) :: i
        character(len=TAG_UNITS_LEN) :: units
        units = ""
        if (i >= 1 .and. i <= n_tags) units = registry(i)%units
    end function tag_units_at

    !> Drop every tag (used by tests and engine re-init).
    subroutine tag_clear_all()
        n_tags = 0
    end subroutine tag_clear_all

    pure function find_tag(name) result(idx)
        character(len=*), intent(in) :: name
        integer :: idx
        integer :: i

        idx = 0
        do i = 1, n_tags
            if (trim(registry(i)%name) == trim(name)) then
                idx = i
                return
            end if
        end do
    end function find_tag

end module tag_bus
