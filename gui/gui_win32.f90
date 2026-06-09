!> @file gui_win32.f90
!> @brief Native Win32 launcher for ThermoTwin-F, written in Fortran.
!>
!> This executable is intentionally a thin wrapper around thermotwin.exe.  The
!> physics stays in the existing CLI/library modules; the GUI selects a mode,
!> invokes the executable, and displays captured stdout/stderr.
module thermotwin_win32_gui
    use, intrinsic :: iso_c_binding, only: c_associated, c_char, c_funloc, &
        c_funptr, c_int, c_intptr_t, c_loc, c_long, c_null_char, c_null_ptr, &
        c_ptr, c_sizeof
    implicit none
    private

    public :: run_gui

    integer(c_int), parameter :: CW_USEDEFAULT = int(Z'80000000', c_int)
    integer(c_int), parameter :: SW_SHOW = 5_c_int

    integer(c_int), parameter :: WM_CREATE = 1_c_int
    integer(c_int), parameter :: WM_DESTROY = 2_c_int
    integer(c_int), parameter :: WM_COMMAND = 273_c_int

    integer(c_int), parameter :: WS_OVERLAPPEDWINDOW = int(Z'00CF0000', c_int)
    integer(c_int), parameter :: WS_VISIBLE = int(Z'10000000', c_int)
    integer(c_int), parameter :: WS_CHILD = int(Z'40000000', c_int)
    integer(c_int), parameter :: WS_BORDER = int(Z'00800000', c_int)
    integer(c_int), parameter :: WS_VSCROLL = int(Z'00200000', c_int)
    integer(c_int), parameter :: ES_LEFT = 0_c_int
    integer(c_int), parameter :: ES_MULTILINE = 4_c_int
    integer(c_int), parameter :: ES_AUTOVSCROLL = 64_c_int
    integer(c_int), parameter :: ES_AUTOHSCROLL = 128_c_int
    integer(c_int), parameter :: ES_READONLY = 2048_c_int
    integer(c_int), parameter :: BS_PUSHBUTTON = 0_c_int

    integer(c_int), parameter :: COLOR_BTNFACE = 15_c_int
    integer(c_int), parameter :: IDC_ARROW = 32512_c_int

    integer(c_int), parameter :: ID_MODE = 101_c_int
    integer(c_int), parameter :: ID_INPUT = 102_c_int
    integer(c_int), parameter :: ID_OUTPUT = 103_c_int
    integer(c_int), parameter :: ID_LOG = 104_c_int
    integer(c_int), parameter :: ID_RUN = 201_c_int
    integer(c_int), parameter :: ID_SELFTEST = 202_c_int
    integer(c_int), parameter :: ID_DESIGN = 203_c_int
    integer(c_int), parameter :: ID_DEGRADATION = 204_c_int
    integer(c_int), parameter :: ID_TRANSIENT = 205_c_int
    integer(c_int), parameter :: ID_UNCERTAINTY = 206_c_int
    integer(c_int), parameter :: ID_DIAGNOSTICS = 207_c_int

    type, bind(C) :: Point
        integer(c_long) :: x
        integer(c_long) :: y
    end type Point

    type, bind(C) :: Msg
        type(c_ptr) :: hwnd
        integer(c_int) :: message
        integer(c_intptr_t) :: wParam
        integer(c_intptr_t) :: lParam
        integer(c_int) :: time
        type(Point) :: pt
    end type Msg

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

    interface
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

        function ShowWindow(hwnd, nCmdShow) bind(C, name="ShowWindow") result(ok)
            import :: c_int, c_ptr
            type(c_ptr), value :: hwnd
            integer(c_int), value :: nCmdShow
            integer(c_int) :: ok
        end function ShowWindow

        function UpdateWindow(hwnd) bind(C, name="UpdateWindow") result(ok)
            import :: c_int, c_ptr
            type(c_ptr), value :: hwnd
            integer(c_int) :: ok
        end function UpdateWindow

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

        function GetWindowTextA(hwnd, lpString, nMaxCount) bind(C, name="GetWindowTextA") result(n)
            import :: c_int, c_ptr
            type(c_ptr), value :: hwnd
            type(c_ptr), value :: lpString
            integer(c_int), value :: nMaxCount
            integer(c_int) :: n
        end function GetWindowTextA
    end interface

    type(c_ptr) :: h_instance = c_null_ptr
    type(c_ptr) :: h_mode = c_null_ptr
    type(c_ptr) :: h_input = c_null_ptr
    type(c_ptr) :: h_output = c_null_ptr
    type(c_ptr) :: h_log = c_null_ptr

contains

    subroutine run_gui()
        type(WndClassExA) :: wc
        type(Msg) :: message
        type(c_ptr) :: hwnd
        character(kind=c_char), allocatable, target :: class_name(:)
        character(kind=c_char), allocatable, target :: title(:)
        integer(c_int) :: atom, ok
        integer(c_intptr_t) :: lres

        call make_c_string("ThermoTwinFWin32Gui", class_name)
        call make_c_string("ThermoTwin-F Launcher", title)

        h_instance = GetModuleHandleA(c_null_ptr)

        wc%cbSize = int(c_sizeof(wc), c_int)
        wc%style = 0_c_int
        wc%lpfnWndProc = c_funloc(window_proc)
        wc%cbClsExtra = 0_c_int
        wc%cbWndExtra = 0_c_int
        wc%hInstance = h_instance
        wc%hIcon = c_null_ptr
        wc%hCursor = LoadCursorA(c_null_ptr, int_to_cptr(IDC_ARROW))
        wc%hbrBackground = GetSysColorBrush(COLOR_BTNFACE)
        wc%lpszMenuName = c_null_ptr
        wc%lpszClassName = c_loc(class_name)
        wc%hIconSm = c_null_ptr

        atom = RegisterClassExA(wc)
        if (atom == 0_c_int) stop "Could not register ThermoTwin-F GUI window class."

        hwnd = CreateWindowExA(0_c_int, c_loc(class_name), c_loc(title), &
            WS_OVERLAPPEDWINDOW + WS_VISIBLE, CW_USEDEFAULT, CW_USEDEFAULT, &
            820_c_int, 610_c_int, c_null_ptr, c_null_ptr, h_instance, c_null_ptr)
        if (.not. c_associated(hwnd)) stop "Could not create ThermoTwin-F GUI window."

        ok = ShowWindow(hwnd, SW_SHOW)
        ok = UpdateWindow(hwnd)

        do while (GetMessageA(message, c_null_ptr, 0_c_int, 0_c_int) > 0_c_int)
            ok = TranslateMessage(message)
            lres = DispatchMessageA(message)
        end do

        if (ok < 0_c_int .and. lres == -1_c_intptr_t) then
            stop "ThermoTwin-F GUI message loop failed."
        end if
    end subroutine run_gui

    function window_proc(hwnd, msg, wParam, lParam) bind(C) result(lres)
        type(c_ptr), value :: hwnd
        integer(c_int), value :: msg
        integer(c_intptr_t), value :: wParam
        integer(c_intptr_t), value :: lParam
        integer(c_intptr_t) :: lres
        integer(c_int) :: control_id

        select case (msg)
        case (WM_CREATE)
            call create_controls(hwnd)
            lres = 0_c_intptr_t
            return

        case (WM_COMMAND)
            control_id = loword(wParam)
            select case (control_id)
            case (ID_RUN)
                call run_current_case()
            case (ID_SELFTEST)
                call preset_and_run("selftest", "", "")
            case (ID_DESIGN)
                call preset_and_run("run", "cases\design_point.csv", "output\results_gui_run.csv")
            case (ID_DEGRADATION)
                call preset_and_run("degradation", "cases\degradation_cases.csv", "")
            case (ID_TRANSIENT)
                call preset_and_run("transient", "cases\transient_baseline.csv", "")
            case (ID_UNCERTAINTY)
                call preset_and_run("uncertainty", "cases\uncertainty_baseline.csv", "")
            case (ID_DIAGNOSTICS)
                call preset_and_run("diagnostics", "cases\diagnostics_baseline.csv", "")
            end select
            lres = 0_c_intptr_t
            return

        case (WM_DESTROY)
            call PostQuitMessage(0_c_int)
            lres = 0_c_intptr_t
            return
        end select

        lres = DefWindowProcA(hwnd, msg, wParam, lParam)
    end function window_proc

    subroutine create_controls(parent)
        type(c_ptr), value :: parent
        integer(c_int), parameter :: LABEL = WS_CHILD + WS_VISIBLE
        integer(c_int), parameter :: EDIT = WS_CHILD + WS_VISIBLE + WS_BORDER + ES_LEFT + ES_AUTOHSCROLL
        integer(c_int), parameter :: BUTTON = WS_CHILD + WS_VISIBLE + BS_PUSHBUTTON
        integer(c_int), parameter :: LOG_EDIT = WS_CHILD + WS_VISIBLE + WS_BORDER + WS_VSCROLL + &
            ES_LEFT + ES_MULTILINE + ES_AUTOVSCROLL + ES_READONLY
        type(c_ptr) :: unused

        unused = create_child(parent, "STATIC", "Mode", 18, 18, 90, 22, 0, LABEL)
        h_mode = create_child(parent, "EDIT", "run", 118, 14, 180, 25, ID_MODE, EDIT)

        unused = create_child(parent, "STATIC", "Input CSV", 18, 50, 90, 22, 0, LABEL)
        h_input = create_child(parent, "EDIT", "cases\design_point.csv", 118, 46, 640, 25, ID_INPUT, EDIT)

        unused = create_child(parent, "STATIC", "Output CSV", 18, 82, 90, 22, 0, LABEL)
        h_output = create_child(parent, "EDIT", "output\results_gui_run.csv", 118, 78, 640, 25, ID_OUTPUT, EDIT)

        unused = create_child(parent, "BUTTON", "Run", 18, 120, 92, 30, ID_RUN, BUTTON)
        unused = create_child(parent, "BUTTON", "Selftest", 118, 120, 92, 30, ID_SELFTEST, BUTTON)
        unused = create_child(parent, "BUTTON", "Design", 218, 120, 92, 30, ID_DESIGN, BUTTON)
        unused = create_child(parent, "BUTTON", "Degrade", 318, 120, 92, 30, ID_DEGRADATION, BUTTON)
        unused = create_child(parent, "BUTTON", "Transient", 418, 120, 92, 30, ID_TRANSIENT, BUTTON)
        unused = create_child(parent, "BUTTON", "Uncertain", 518, 120, 92, 30, ID_UNCERTAINTY, BUTTON)
        unused = create_child(parent, "BUTTON", "Diagnose", 618, 120, 92, 30, ID_DIAGNOSTICS, BUTTON)

        h_log = create_child(parent, "EDIT", "", 18, 166, 740, 375, ID_LOG, LOG_EDIT)
        call set_text(h_log, "Ready. Build thermotwin.exe first, then choose a mode and run it.")
    end subroutine create_controls

    function create_child(parent, class_name, text, x, y, width, height, control_id, style) result(hwnd)
        type(c_ptr), value :: parent
        character(len=*), intent(in) :: class_name
        character(len=*), intent(in) :: text
        integer, intent(in) :: x, y, width, height, control_id
        integer(c_int), intent(in) :: style
        type(c_ptr) :: hwnd
        character(kind=c_char), allocatable, target :: c_class(:)
        character(kind=c_char), allocatable, target :: c_text(:)

        call make_c_string(class_name, c_class)
        call make_c_string(text, c_text)
        hwnd = CreateWindowExA(0_c_int, c_loc(c_class), c_loc(c_text), style, &
            int(x, c_int), int(y, c_int), int(width, c_int), int(height, c_int), &
            parent, int_to_cptr(control_id), h_instance, c_null_ptr)
    end function create_child

    subroutine preset_and_run(mode, input, output)
        character(len=*), intent(in) :: mode
        character(len=*), intent(in) :: input
        character(len=*), intent(in) :: output

        call set_text(h_mode, mode)
        call set_text(h_input, input)
        call set_text(h_output, output)
        call run_current_case()
    end subroutine preset_and_run

    subroutine run_current_case()
        character(len=:), allocatable :: mode, input, output, command, shell_command
        character(len=:), allocatable :: log_text, display_text
        character(len=*), parameter :: LOG_FILE = "output\gui_last_run.txt"
        integer :: exitstat
        logical :: exe_exists

        inquire(file="thermotwin.exe", exist=exe_exists)
        if (.not. exe_exists) then
            call set_text(h_log, "thermotwin.exe was not found. Build it first with `make` or `.\scripts\build.sh`.")
            return
        end if

        mode = lower_ascii(trim(get_text(h_mode, 256)))
        input = trim(get_text(h_input, 1024))
        output = trim(get_text(h_output, 1024))

        select case (mode)
        case ("selftest")
            command = ".\thermotwin.exe selftest"
        case ("run", "design")
            if (len_trim(input) == 0 .or. len_trim(output) == 0) then
                call set_text(h_log, "Run/design mode needs both an input CSV and output CSV.")
                return
            end if
            command = ".\thermotwin.exe run " // quote_arg(input) // " " // quote_arg(output)
        case ("degradation", "transient", "uncertainty", "diagnostics")
            if (len_trim(input) == 0) then
                call set_text(h_log, trim(mode) // " mode needs an input CSV.")
                return
            end if
            command = ".\thermotwin.exe " // trim(mode) // " " // quote_arg(input)
        case default
            call set_text(h_log, "Unknown mode: " // trim(mode) // &
                ". Use run, selftest, degradation, transient, uncertainty, or diagnostics.")
            return
        end select

        call set_text(h_log, "Running:" // crlf() // trim(command))
        call execute_command_line('cmd /c if not exist output mkdir output', exitstat=exitstat)

        shell_command = 'cmd /c ' // trim(command) // ' > ' // quote_arg(LOG_FILE) // ' 2>&1'
        call execute_command_line(shell_command, exitstat=exitstat)
        call read_text_file(LOG_FILE, log_text)

        display_text = "Command:" // crlf() // trim(command) // crlf() // crlf() // &
            trim(log_text) // crlf() // "Exit status: " // int_to_string(exitstat)
        call set_text(h_log, display_text)
    end subroutine run_current_case

    subroutine read_text_file(path, text)
        character(len=*), intent(in) :: path
        character(len=:), allocatable, intent(out) :: text
        character(len=1024) :: line
        integer :: unit, ios

        text = ""
        open(newunit=unit, file=path, status="old", action="read", iostat=ios)
        if (ios /= 0) then
            text = "Could not read " // trim(path) // "."
            return
        end if

        do
            read(unit, "(A)", iostat=ios) line
            if (ios /= 0) exit
            text = text // trim(line) // crlf()
        end do
        close(unit)

        if (len_trim(text) == 0) text = "(command produced no output)"
    end subroutine read_text_file

    subroutine set_text(hwnd, text)
        type(c_ptr), value :: hwnd
        character(len=*), intent(in) :: text
        character(kind=c_char), allocatable, target :: c_text(:)
        integer(c_int) :: ok

        call make_c_string(text, c_text)
        ok = SetWindowTextA(hwnd, c_loc(c_text))
    end subroutine set_text

    function get_text(hwnd, max_len) result(text)
        type(c_ptr), value :: hwnd
        integer, intent(in) :: max_len
        character(len=:), allocatable :: text
        character(kind=c_char), allocatable, target :: buffer(:)
        integer(c_int) :: copied
        integer :: i

        allocate(buffer(max_len + 1))
        buffer = c_null_char
        copied = GetWindowTextA(hwnd, c_loc(buffer), int(max_len + 1, c_int))
        allocate(character(len=max(0, copied)) :: text)
        do i = 1, copied
            text(i:i) = achar(iachar(buffer(i)))
        end do
    end function get_text

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

    function quote_arg(text) result(quoted)
        character(len=*), intent(in) :: text
        character(len=:), allocatable :: quoted

        quoted = '"' // trim(text) // '"'
    end function quote_arg

    pure function lower_ascii(text) result(lowered)
        character(len=*), intent(in) :: text
        character(len=len(text)) :: lowered
        integer :: i, code

        lowered = text
        do i = 1, len(text)
            code = iachar(text(i:i))
            if (code >= iachar("A") .and. code <= iachar("Z")) then
                lowered(i:i) = achar(code + 32)
            end if
        end do
    end function lower_ascii

    pure function crlf() result(text)
        character(len=2) :: text

        text = achar(13) // achar(10)
    end function crlf

    pure function int_to_string(value) result(text)
        integer, intent(in) :: value
        character(len=32) :: text

        write(text, "(I0)") value
        text = adjustl(text)
    end function int_to_string

    pure function loword(value) result(word)
        integer(c_intptr_t), intent(in) :: value
        integer(c_int) :: word

        word = int(iand(value, int(Z'FFFF', c_intptr_t)), c_int)
    end function loword

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
