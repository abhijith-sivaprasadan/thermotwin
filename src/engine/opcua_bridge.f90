!> @file opcua_bridge.f90
!> @brief Fortran iso_c_binding interface to the OPC UA server C wrapper.
!>
!> The thin C layer in gui/opcua_server.c owns the open62541 lifecycle.
!> This module exposes four public routines:
!>
!>   opcua_start(port)   — start the server on the given TCP port (default 4840)
!>   opcua_stop()        — clean shutdown
!>   opcua_iterate()     — call once per GUI timer tick to service the network
!>   opcua_write(name, value, units) — write one tag value to the address space
!>
!> If the server fails to start (port in use, open62541 build missing) all
!> subsequent calls are no-ops — the GUI continues normally without OPC UA.
module opcua_bridge
    use, intrinsic :: iso_c_binding, only: c_int, c_double, c_char, c_null_char
    implicit none
    private

    public :: opcua_start, opcua_stop, opcua_iterate, opcua_write, opcua_active

    interface
        function ua_server_start(port) bind(C, name="ua_server_start") result(rc)
            import :: c_int
            integer(c_int), value :: port
            integer(c_int) :: rc
        end function ua_server_start

        subroutine ua_server_stop() bind(C, name="ua_server_stop")
        end subroutine ua_server_stop

        subroutine ua_server_iterate() bind(C, name="ua_server_iterate")
        end subroutine ua_server_iterate

        subroutine ua_tag_write(name, value, units) &
                bind(C, name="ua_tag_write")
            import :: c_char, c_double
            character(kind=c_char), intent(in) :: name(*)
            real(c_double), value :: value
            character(kind=c_char), intent(in) :: units(*)
        end subroutine ua_tag_write

        function ua_server_active() bind(C, name="ua_server_active") result(flag)
            import :: c_int
            integer(c_int) :: flag
        end function ua_server_active
    end interface

contains

    subroutine opcua_start(port)
        integer, intent(in) :: port
        integer(c_int) :: rc
        rc = ua_server_start(int(port, c_int))
        if (rc /= 0) then
            write(*, '(A,I0)') "OPC UA: server start failed (rc=", rc, ")"
        end if
    end subroutine opcua_start

    subroutine opcua_stop()
        call ua_server_stop()
    end subroutine opcua_stop

    subroutine opcua_iterate()
        call ua_server_iterate()
    end subroutine opcua_iterate

    !> Write a named tag to the OPC UA address space.
    !> name and units are plain Fortran strings; null-terminator added here.
    subroutine opcua_write(name, value, units)
        character(len=*), intent(in) :: name, units
        real(8), intent(in) :: value
        character(len=65, kind=c_char) :: cname
        character(len=17, kind=c_char) :: cunits
        integer :: i

        cname = ' '; cunits = ' '
        do i = 1, min(len_trim(name), 64)
            cname(i:i) = name(i:i)
        end do
        cname(min(len_trim(name), 64) + 1 : min(len_trim(name), 64) + 1) = c_null_char
        do i = 1, min(len_trim(units), 16)
            cunits(i:i) = units(i:i)
        end do
        cunits(min(len_trim(units), 16) + 1 : min(len_trim(units), 16) + 1) = c_null_char
        call ua_tag_write(cname, real(value, c_double), cunits)
    end subroutine opcua_write

    logical function opcua_active()
        opcua_active = ua_server_active() /= 0
    end function opcua_active

end module opcua_bridge
