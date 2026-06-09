!> @file gui_win32.f90
!> @brief Native Win32 real-time grid dashboard for ThermoTwin-F.
!>
!> The GUI is written in Fortran and links directly to the ThermoTwin-F solver.
!> It exposes a small electric-grid balancing sandbox around the gas-turbine
!> model: demand, renewable supply, storage and gas dispatch are manipulated in
!> real time, while `solve_cycle` supplies the gas-turbine power figure.
module thermotwin_win32_gui
    use, intrinsic :: iso_c_binding, only: c_associated, c_char, c_funloc, &
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
    integer(c_int), parameter :: WM_PAINT = 15_c_int
    integer(c_int), parameter :: WM_COMMAND = 273_c_int
    integer(c_int), parameter :: WM_TIMER = 275_c_int
    integer(c_int), parameter :: WM_HSCROLL = 276_c_int
    integer(c_int), parameter :: WM_USER = 1024_c_int

    integer(c_int), parameter :: WS_OVERLAPPEDWINDOW = int(Z'00CF0000', c_int)
    integer(c_int), parameter :: WS_VISIBLE = int(Z'10000000', c_int)
    integer(c_int), parameter :: WS_CHILD = int(Z'40000000', c_int)
    integer(c_int), parameter :: WS_BORDER = int(Z'00800000', c_int)
    integer(c_int), parameter :: BS_PUSHBUTTON = 0_c_int
    integer(c_int), parameter :: TBS_AUTOTICKS = 1_c_int
    integer(c_int), parameter :: COLOR_WINDOW = 5_c_int
    integer(c_int), parameter :: IDC_ARROW = 32512_c_int
    integer(c_int), parameter :: TRANSPARENT = 1_c_int
    integer(c_int), parameter :: PS_SOLID = 0_c_int

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
    integer(c_int), parameter :: TIMER_ID = 1_c_int
    integer(c_int), parameter :: TIMER_MS = 250_c_int

    real(dp), parameter :: DEMAND_MIN_MW = 10.0_dp
    real(dp), parameter :: DEMAND_MAX_MW = 100.0_dp
    real(dp), parameter :: RENEWABLE_MAX_MW = 60.0_dp
    real(dp), parameter :: STORAGE_MIN_MW = -20.0_dp
    real(dp), parameter :: STORAGE_MAX_MW = 20.0_dp
    real(dp), parameter :: GAS_MIN_PCT = 20.0_dp
    real(dp), parameter :: GAS_MAX_PCT = 100.0_dp
    real(dp), parameter :: GAS_RAMP_PCT_PER_S = 18.0_dp

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
        real(dp) :: demand_MW = 45.0_dp
        real(dp) :: renewable_MW = 12.0_dp
        real(dp) :: storage_MW = 0.0_dp
        real(dp) :: gas_dispatch_pct = 82.0_dp
        real(dp) :: ambient_C = 15.0_dp
        real(dp) :: TIT_K = 1400.0_dp
        real(dp) :: gas_power_MW = 0.0_dp
        real(dp) :: gas_capacity_MW = 0.0_dp
        real(dp) :: supply_MW = 0.0_dp
        real(dp) :: imbalance_MW = 0.0_dp
        real(dp) :: reserve_MW = 0.0_dp
        real(dp) :: frequency_Hz = 60.0_dp
        real(dp) :: heat_rate_kJ_kWh = 0.0_dp
        real(dp) :: exhaust_K = 0.0_dp
        real(dp) :: elapsed_s = 0.0_dp
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
    end interface

    type(c_ptr) :: h_instance = c_null_ptr
    type(c_ptr) :: h_main = c_null_ptr
    type(c_ptr) :: h_demand = c_null_ptr
    type(c_ptr) :: h_renewable = c_null_ptr
    type(c_ptr) :: h_storage = c_null_ptr
    type(c_ptr) :: h_gas = c_null_ptr
    type(c_ptr) :: h_ambient = c_null_ptr
    type(c_ptr) :: h_tit = c_null_ptr
    type(c_ptr) :: h_auto_button = c_null_ptr
    type(c_ptr) :: h_value_demand = c_null_ptr
    type(c_ptr) :: h_value_renewable = c_null_ptr
    type(c_ptr) :: h_value_storage = c_null_ptr
    type(c_ptr) :: h_value_gas = c_null_ptr
    type(c_ptr) :: h_value_ambient = c_null_ptr
    type(c_ptr) :: h_value_tit = c_null_ptr
    type(GridState) :: grid

contains

    subroutine run_gui()
        type(WndClassExA) :: wc
        type(Msg) :: message
        type(c_ptr) :: hwnd
        character(kind=c_char), allocatable, target :: class_name(:)
        character(kind=c_char), allocatable, target :: title(:)
        integer(c_int) :: atom, ok
        integer(c_intptr_t) :: lres

        call InitCommonControls()
        call make_c_string("ThermoTwinFGridDashboard", class_name)
        call make_c_string("ThermoTwin-F Grid Balancer", title)

        h_instance = GetModuleHandleA(c_null_ptr)

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
        if (atom == 0_c_int) stop "Could not register ThermoTwin-F GUI window class."

        hwnd = CreateWindowExA(0_c_int, c_loc(class_name), c_loc(title), &
            WS_OVERLAPPEDWINDOW + WS_VISIBLE, CW_USEDEFAULT, CW_USEDEFAULT, &
            1120_c_int, 760_c_int, c_null_ptr, c_null_ptr, h_instance, c_null_ptr)
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
        type(PaintStruct) :: ps
        type(c_ptr) :: hdc
        integer(c_int) :: ok

        select case (msg)
        case (WM_CREATE)
            h_main = hwnd
            call create_controls(hwnd)
            call read_controls()
            call refresh_model()
            call update_control_labels()
            lres = SetTimer(hwnd, int(TIMER_ID, c_intptr_t), TIMER_MS, c_null_ptr)
            lres = 0_c_intptr_t
            return

        case (WM_HSCROLL)
            call read_controls()
            call refresh_model()
            call update_control_labels()
            ok = InvalidateRect(hwnd, c_null_ptr, 0_c_int)
            lres = 0_c_intptr_t
            return

        case (WM_COMMAND)
            call handle_command(loword(wParam))
            ok = InvalidateRect(hwnd, c_null_ptr, 0_c_int)
            lres = 0_c_intptr_t
            return

        case (WM_TIMER)
            grid%elapsed_s = grid%elapsed_s + real(TIMER_MS, dp) / 1000.0_dp
            call tick_auto_balance(real(TIMER_MS, dp) / 1000.0_dp)
            call refresh_model()
            call update_control_labels()
            ok = InvalidateRect(hwnd, c_null_ptr, 0_c_int)
            lres = 0_c_intptr_t
            return

        case (WM_PAINT)
            hdc = BeginPaint(hwnd, ps)
            call draw_dashboard(hdc)
            ok = EndPaint(hwnd, ps)
            lres = 0_c_intptr_t
            return

        case (WM_DESTROY)
            ok = KillTimer(hwnd, int(TIMER_ID, c_intptr_t))
            call PostQuitMessage(0_c_int)
            lres = 0_c_intptr_t
            return
        end select

        lres = DefWindowProcA(hwnd, msg, wParam, lParam)
    end function window_proc

    subroutine create_controls(parent)
        type(c_ptr), value :: parent
        integer(c_int), parameter :: LABEL = WS_CHILD + WS_VISIBLE
        integer(c_int), parameter :: BUTTON = WS_CHILD + WS_VISIBLE + BS_PUSHBUTTON
        integer(c_int), parameter :: SLIDER = WS_CHILD + WS_VISIBLE + TBS_AUTOTICKS
        type(c_ptr) :: unused

        unused = create_child(parent, "STATIC", "Grid controls", 24, 18, 300, 22, 0, LABEL)

        unused = create_child(parent, "STATIC", "Demand", 24, 54, 140, 20, 0, LABEL)
        h_value_demand = create_child(parent, "STATIC", "", 268, 54, 92, 20, 0, LABEL)
        h_demand = create_child(parent, "msctls_trackbar32", "", 22, 76, 330, 38, ID_DEMAND, SLIDER)
        call configure_slider(h_demand, 10, 100, 45, 10)

        unused = create_child(parent, "STATIC", "Renewables", 24, 128, 140, 20, 0, LABEL)
        h_value_renewable = create_child(parent, "STATIC", "", 268, 128, 92, 20, 0, LABEL)
        h_renewable = create_child(parent, "msctls_trackbar32", "", 22, 150, 330, 38, ID_RENEWABLE, SLIDER)
        call configure_slider(h_renewable, 0, 60, 12, 10)

        unused = create_child(parent, "STATIC", "Storage charge/discharge", 24, 202, 190, 20, 0, LABEL)
        h_value_storage = create_child(parent, "STATIC", "", 268, 202, 92, 20, 0, LABEL)
        h_storage = create_child(parent, "msctls_trackbar32", "", 22, 224, 330, 38, ID_STORAGE, SLIDER)
        call configure_slider(h_storage, 0, 80, 40, 10)

        unused = create_child(parent, "STATIC", "Gas dispatch", 24, 276, 140, 20, 0, LABEL)
        h_value_gas = create_child(parent, "STATIC", "", 268, 276, 92, 20, 0, LABEL)
        h_gas = create_child(parent, "msctls_trackbar32", "", 22, 298, 330, 38, ID_GAS, SLIDER)
        call configure_slider(h_gas, 20, 100, 82, 10)

        unused = create_child(parent, "STATIC", "Ambient temperature", 24, 350, 160, 20, 0, LABEL)
        h_value_ambient = create_child(parent, "STATIC", "", 268, 350, 92, 20, 0, LABEL)
        h_ambient = create_child(parent, "msctls_trackbar32", "", 22, 372, 330, 38, ID_AMBIENT, SLIDER)
        call configure_slider(h_ambient, 0, 65, 35, 5)

        unused = create_child(parent, "STATIC", "Firing temperature", 24, 424, 160, 20, 0, LABEL)
        h_value_tit = create_child(parent, "STATIC", "", 268, 424, 92, 20, 0, LABEL)
        h_tit = create_child(parent, "msctls_trackbar32", "", 22, 446, 330, 38, ID_TIT, SLIDER)
        call configure_slider(h_tit, 1200, 1600, 1400, 50)

        h_auto_button = create_child(parent, "BUTTON", "Auto Balance: ON", 24, 514, 150, 32, ID_AUTO, BUTTON)
        unused = create_child(parent, "BUTTON", "Balance Now", 184, 514, 120, 32, ID_BALANCE, BUTTON)
        unused = create_child(parent, "BUTTON", "Reset", 24, 556, 92, 30, ID_RESET, BUTTON)
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

    subroutine configure_slider(hwnd, min_value, max_value, position, tick_freq)
        type(c_ptr), value :: hwnd
        integer, intent(in) :: min_value, max_value, position, tick_freq
        integer(c_intptr_t) :: ignored

        ignored = SendMessageA(hwnd, TBM_SETRANGE, 1_c_intptr_t, make_lparam(min_value, max_value))
        ignored = SendMessageA(hwnd, TBM_SETPOS, 1_c_intptr_t, int(position, c_intptr_t))
        ignored = SendMessageA(hwnd, TBM_SETTICFREQ, int(tick_freq, c_intptr_t), 0_c_intptr_t)
    end subroutine configure_slider

    subroutine handle_command(control_id)
        integer(c_int), intent(in) :: control_id

        select case (control_id)
        case (ID_AUTO)
            grid%auto_balance = .not. grid%auto_balance
            call update_auto_button()
        case (ID_BALANCE)
            call balance_now()
        case (ID_RESET)
            call reset_controls()
        end select

        call read_controls()
        call refresh_model()
        call update_control_labels()
    end subroutine handle_command

    subroutine read_controls()
        grid%demand_MW = real(get_slider_pos(h_demand), dp)
        grid%renewable_MW = real(get_slider_pos(h_renewable), dp)
        grid%storage_MW = STORAGE_MIN_MW + 0.5_dp * real(get_slider_pos(h_storage), dp)
        grid%gas_dispatch_pct = real(get_slider_pos(h_gas), dp)
        grid%ambient_C = -20.0_dp + real(get_slider_pos(h_ambient), dp)
        grid%TIT_K = real(get_slider_pos(h_tit), dp)
    end subroutine read_controls

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
        grid%supply_MW = grid%gas_power_MW + grid%renewable_MW + grid%storage_MW
        grid%imbalance_MW = grid%supply_MW - grid%demand_MW
        grid%reserve_MW = max(0.0_dp, grid%gas_capacity_MW - grid%gas_power_MW)
        grid%frequency_Hz = clamp_real(60.0_dp + 0.045_dp * grid%imbalance_MW, 58.5_dp, 61.5_dp)
    end subroutine refresh_model

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
        real(dp), intent(in) :: dt_s
        real(dp) :: needed_gas_MW, target_pct, step_pct, next_pct

        if (.not. grid%auto_balance) return

        needed_gas_MW = grid%demand_MW - grid%renewable_MW - grid%storage_MW
        if (grid%gas_capacity_MW > 1.0e-6_dp) then
            target_pct = 100.0_dp * needed_gas_MW / grid%gas_capacity_MW
        else
            target_pct = GAS_MAX_PCT
        end if
        target_pct = clamp_real(target_pct, GAS_MIN_PCT, GAS_MAX_PCT)
        step_pct = GAS_RAMP_PCT_PER_S * dt_s
        next_pct = grid%gas_dispatch_pct + clamp_real(target_pct - grid%gas_dispatch_pct, -step_pct, step_pct)
        call set_slider_pos(h_gas, nint(next_pct))
        grid%gas_dispatch_pct = real(get_slider_pos(h_gas), dp)
    end subroutine tick_auto_balance

    subroutine balance_now()
        real(dp) :: needed_gas_MW, target_pct

        if (grid%gas_capacity_MW <= 1.0e-6_dp) return
        needed_gas_MW = grid%demand_MW - grid%renewable_MW - grid%storage_MW
        target_pct = clamp_real(100.0_dp * needed_gas_MW / grid%gas_capacity_MW, GAS_MIN_PCT, GAS_MAX_PCT)
        call set_slider_pos(h_gas, nint(target_pct))
    end subroutine balance_now

    subroutine reset_controls()
        grid%auto_balance = .true.
        call set_slider_pos(h_demand, 45)
        call set_slider_pos(h_renewable, 12)
        call set_slider_pos(h_storage, 40)
        call set_slider_pos(h_gas, 82)
        call set_slider_pos(h_ambient, 35)
        call set_slider_pos(h_tit, 1400)
        call update_auto_button()
    end subroutine reset_controls

    subroutine update_control_labels()
        call set_text(h_value_demand, format_value(grid%demand_MW, " MW", 1))
        call set_text(h_value_renewable, format_value(grid%renewable_MW, " MW", 1))
        call set_text(h_value_storage, format_value(grid%storage_MW, " MW", 1))
        call set_text(h_value_gas, format_value(grid%gas_dispatch_pct, " %", 0))
        call set_text(h_value_ambient, format_value(grid%ambient_C, " C", 0))
        call set_text(h_value_tit, format_value(grid%TIT_K, " K", 0))
        call update_auto_button()
    end subroutine update_control_labels

    subroutine update_auto_button()
        if (grid%auto_balance) then
            call set_text(h_auto_button, "Auto Balance: ON")
        else
            call set_text(h_auto_button, "Auto Balance: OFF")
        end if
    end subroutine update_auto_button

    function get_slider_pos(hwnd) result(position)
        type(c_ptr), value :: hwnd
        integer :: position
        integer(c_intptr_t) :: raw

        raw = SendMessageA(hwnd, TBM_GETPOS, 0_c_intptr_t, 0_c_intptr_t)
        position = int(raw)
    end function get_slider_pos

    subroutine set_slider_pos(hwnd, position)
        type(c_ptr), value :: hwnd
        integer, intent(in) :: position
        integer(c_intptr_t) :: ignored

        ignored = SendMessageA(hwnd, TBM_SETPOS, 1_c_intptr_t, int(position, c_intptr_t))
    end subroutine set_slider_pos

    subroutine draw_dashboard(hdc)
        type(c_ptr), value :: hdc
        integer(c_int), parameter :: BG = int(Z'00F7F8FA', c_int)
        integer(c_int), parameter :: INK = int(Z'00211B16', c_int)
        integer(c_int), parameter :: MUTED = int(Z'007D746C', c_int)
        integer(c_int), parameter :: PANEL = int(Z'00FFFFFF', c_int)
        integer(c_int), parameter :: BORDER = int(Z'00D4D0CA', c_int)
        integer(c_int), parameter :: GAS = int(Z'0038A06B', c_int)
        integer(c_int), parameter :: RENEW = int(Z'00B48A2C', c_int)
        integer(c_int), parameter :: STORAGE = int(Z'00D87B24', c_int)
        integer(c_int), parameter :: DEMAND = int(Z'004B5FD7', c_int)
        integer(c_int), parameter :: ALERT = int(Z'002A48D9', c_int)
        integer(c_int), parameter :: OK = int(Z'0064A05A', c_int)
        integer(c_int), parameter :: WARN = int(Z'0000A5FF', c_int)
        integer :: x0, y0, w, h
        real(dp) :: scale_MW
        character(len=96) :: status, subtitle
        integer(c_int) :: status_color

        call fill_box(hdc, 0, 0, 1120, 760, BG)

        x0 = 386
        y0 = 18
        w = 690
        h = 670
        call fill_box(hdc, x0, y0, x0 + w, y0 + h, PANEL)
        call stroke_box(hdc, x0, y0, x0 + w, y0 + h, BORDER, 1)

        call draw_text(hdc, x0 + 24, y0 + 22, "ThermoTwin-F Live Grid Balancer", INK)
        write(subtitle, '("Scenario time ",F7.1," s | Auto balance ",A)') &
            grid%elapsed_s, merge("ON ", "OFF", grid%auto_balance)
        call draw_text(hdc, x0 + 24, y0 + 44, trim(subtitle), MUTED)

        scale_MW = max(max(DEMAND_MAX_MW, grid%demand_MW), max(grid%supply_MW, grid%gas_capacity_MW))
        call draw_kpi_tiles(hdc, x0 + 24, y0 + 78)

        call draw_section_title(hdc, x0 + 24, y0 + 190, "Power balance")
        call draw_bar(hdc, x0 + 24, y0 + 220, 610, 24, "Demand", grid%demand_MW, scale_MW, DEMAND)
        call draw_bar(hdc, x0 + 24, y0 + 260, 610, 24, "Total supply", grid%supply_MW, scale_MW, OK)
        call draw_stacked_supply(hdc, x0 + 24, y0 + 304, 610, 32, scale_MW, GAS, RENEW, STORAGE, ALERT)

        call draw_section_title(hdc, x0 + 24, y0 + 372, "Frequency and reserve")
        call draw_frequency_meter(hdc, x0 + 24, y0 + 402, 610, 42)
        call draw_bar(hdc, x0 + 24, y0 + 470, 610, 24, "Gas reserve", grid%reserve_MW, max(1.0_dp, grid%gas_capacity_MW), RENEW)

        call draw_section_title(hdc, x0 + 24, y0 + 530, "One-line power flow")
        call draw_power_flow(hdc, x0 + 26, y0 + 558)

        call grid_status(status, status_color)
        call fill_box(hdc, x0 + 24, y0 + 632, x0 + 634, y0 + 656, status_color)
        call draw_text(hdc, x0 + 34, y0 + 637, trim(status), int(Z'00FFFFFF', c_int))
    end subroutine draw_dashboard

    subroutine draw_kpi_tiles(hdc, x, y)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y
        integer(c_int), parameter :: BORDER = int(Z'00D4D0CA', c_int)
        integer(c_int), parameter :: TILE = int(Z'00F8FBFC', c_int)
        integer(c_int), parameter :: INK = int(Z'00211B16', c_int)
        integer(c_int), parameter :: MUTED = int(Z'007D746C', c_int)
        integer(c_int), parameter :: RED = int(Z'002A48D9', c_int)
        integer(c_int), parameter :: GREEN = int(Z'0064A05A', c_int)
        integer :: i, tx, ty
        character(len=64) :: value

        do i = 0, 2
            tx = x + i * 205
            call fill_box(hdc, tx, y, tx + 185, y + 82, TILE)
            call stroke_box(hdc, tx, y, tx + 185, y + 82, BORDER, 1)
        end do

        write(value, '(F6.1," MW")') grid%gas_power_MW
        call draw_text(hdc, x + 12, y + 12, "Gas output", MUTED)
        call draw_text(hdc, x + 12, y + 38, adjustl(value), INK)

        write(value, '(F7.2," Hz")') grid%frequency_Hz
        call draw_text(hdc, x + 217, y + 12, "Grid frequency", MUTED)
        call draw_text(hdc, x + 217, y + 38, adjustl(value), frequency_color())

        write(value, '(SP,F6.1," MW")') grid%imbalance_MW
        ty = y + 38
        call draw_text(hdc, x + 422, y + 12, "Imbalance", MUTED)
        if (abs(grid%imbalance_MW) <= 0.5_dp) then
            call draw_text(hdc, x + 422, ty, adjustl(value), GREEN)
        else
            call draw_text(hdc, x + 422, ty, adjustl(value), RED)
        end if
    end subroutine draw_kpi_tiles

    subroutine draw_section_title(hdc, x, y, text)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y
        character(len=*), intent(in) :: text

        call draw_text(hdc, x, y, text, int(Z'00211B16', c_int))
        call draw_line(hdc, x, y + 20, x + 610, y + 20, int(Z'00E5E1DB', c_int), 1)
    end subroutine draw_section_title

    subroutine draw_bar(hdc, x, y, width, height, label, value, maximum, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        character(len=*), intent(in) :: label
        real(dp), intent(in) :: value, maximum
        integer(c_int), intent(in) :: color
        integer :: fill_w
        character(len=96) :: text

        fill_w = int(real(width, dp) * clamp_real(value / max(maximum, 1.0e-9_dp), 0.0_dp, 1.0_dp))
        call fill_box(hdc, x, y, x + width, y + height, int(Z'00EFECE8', c_int))
        call fill_box(hdc, x, y, x + fill_w, y + height, color)
        call stroke_box(hdc, x, y, x + width, y + height, int(Z'00D4D0CA', c_int), 1)
        write(text, '(A,": ",F6.1," MW")') trim(label), value
        call draw_text(hdc, x + 8, y + 5, adjustl(text), int(Z'00211B16', c_int))
    end subroutine draw_bar

    subroutine draw_stacked_supply(hdc, x, y, width, height, maximum, gas_color, renewable_color, storage_color, sink_color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        real(dp), intent(in) :: maximum
        integer(c_int), intent(in) :: gas_color, renewable_color, storage_color, sink_color
        integer :: cursor, seg_w
        character(len=128) :: text

        call fill_box(hdc, x, y, x + width, y + height, int(Z'00EFECE8', c_int))
        cursor = x
        seg_w = scaled_width(grid%gas_power_MW, maximum, width)
        call fill_box(hdc, cursor, y, cursor + seg_w, y + height, gas_color)
        cursor = cursor + seg_w
        seg_w = scaled_width(grid%renewable_MW, maximum, width)
        call fill_box(hdc, cursor, y, cursor + seg_w, y + height, renewable_color)
        cursor = cursor + seg_w
        if (grid%storage_MW >= 0.0_dp) then
            seg_w = scaled_width(grid%storage_MW, maximum, width)
            call fill_box(hdc, cursor, y, cursor + seg_w, y + height, storage_color)
        else
            seg_w = scaled_width(abs(grid%storage_MW), maximum, width)
            call fill_box(hdc, x + width - seg_w, y, x + width, y + height, sink_color)
        end if
        call stroke_box(hdc, x, y, x + width, y + height, int(Z'00D4D0CA', c_int), 1)
        write(text, '("Gas ",F5.1," | Renew ",F5.1," | Storage ",SP,F5.1," MW")') &
            grid%gas_power_MW, grid%renewable_MW, grid%storage_MW
        call draw_text(hdc, x + 8, y + 8, adjustl(text), int(Z'00211B16', c_int))
    end subroutine draw_stacked_supply

    subroutine draw_frequency_meter(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: center_x, marker_x
        real(dp) :: frac
        character(len=64) :: text

        call fill_box(hdc, x, y, x + width, y + height, int(Z'00EFECE8', c_int))
        center_x = x + width / 2
        call fill_box(hdc, center_x - 28, y, center_x + 28, y + height, int(Z'00D6EBD2', c_int))
        call stroke_box(hdc, x, y, x + width, y + height, int(Z'00D4D0CA', c_int), 1)
        call draw_line(hdc, center_x, y, center_x, y + height, int(Z'0064A05A', c_int), 2)
        frac = clamp_real((grid%frequency_Hz - 58.5_dp) / 3.0_dp, 0.0_dp, 1.0_dp)
        marker_x = x + int(frac * real(width, dp))
        call draw_line(hdc, marker_x, y - 4, marker_x, y + height + 4, frequency_color(), 4)
        write(text, '("58.5 Hz",30X,"60.0 Hz",30X,"61.5 Hz")')
        call draw_text(hdc, x, y + height + 8, trim(text), int(Z'007D746C', c_int))
    end subroutine draw_frequency_meter

    subroutine draw_power_flow(hdc, x, y)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y
        integer(c_int), parameter :: BORDER = int(Z'00D4D0CA', c_int)
        integer(c_int), parameter :: NODE = int(Z'00F8FBFC', c_int)
        integer(c_int), parameter :: INK = int(Z'00211B16', c_int)
        integer(c_int), parameter :: GAS = int(Z'0038A06B', c_int)
        integer(c_int), parameter :: RENEW = int(Z'00B48A2C', c_int)
        integer(c_int), parameter :: STORAGE = int(Z'00D87B24', c_int)
        integer(c_int), parameter :: DEMAND = int(Z'004B5FD7', c_int)
        character(len=64) :: text

        call draw_node(hdc, x, y, 118, 46, "Gas", grid%gas_power_MW, GAS)
        call draw_node(hdc, x, y + 72, 118, 46, "Renew", grid%renewable_MW, RENEW)
        call draw_node(hdc, x, y + 144, 118, 46, "Storage", grid%storage_MW, STORAGE)

        call fill_box(hdc, x + 238, y + 62, x + 348, y + 128, NODE)
        call stroke_box(hdc, x + 238, y + 62, x + 348, y + 128, BORDER, 1)
        call draw_text(hdc, x + 273, y + 82, "GRID", INK)
        write(text, '(F6.2," Hz")') grid%frequency_Hz
        call draw_text(hdc, x + 264, y + 104, adjustl(text), frequency_color())

        call draw_node(hdc, x + 492, y + 62, 118, 46, "Load", grid%demand_MW, DEMAND)
        call draw_line(hdc, x + 118, y + 23, x + 238, y + 84, GAS, 3)
        call draw_line(hdc, x + 118, y + 95, x + 238, y + 95, RENEW, 3)
        call draw_line(hdc, x + 118, y + 167, x + 238, y + 106, STORAGE, 3)
        call draw_line(hdc, x + 348, y + 95, x + 492, y + 85, DEMAND, 4)
    end subroutine draw_power_flow

    subroutine draw_node(hdc, x, y, width, height, label, value, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        character(len=*), intent(in) :: label
        real(dp), intent(in) :: value
        integer(c_int), intent(in) :: color
        character(len=64) :: text

        call fill_box(hdc, x, y, x + width, y + height, int(Z'00F8FBFC', c_int))
        call stroke_box(hdc, x, y, x + width, y + height, color, 2)
        call draw_text(hdc, x + 10, y + 8, label, int(Z'00211B16', c_int))
        write(text, '(SP,F6.1," MW")') value
        call draw_text(hdc, x + 10, y + 26, adjustl(text), int(Z'007D746C', c_int))
    end subroutine draw_node

    subroutine grid_status(text, color)
        character(len=*), intent(out) :: text
        integer(c_int), intent(out) :: color

        if (abs(grid%imbalance_MW) <= 0.5_dp) then
            text = "BALANCED: supply matches demand within 0.5 MW"
            color = int(Z'0064A05A', c_int)
        else if (grid%imbalance_MW < 0.0_dp) then
            text = "SHORTAGE: raise gas, discharge storage, add renewables, or lower demand"
            color = int(Z'002A48D9', c_int)
        else
            text = "SURPLUS: lower gas, charge storage, curtail renewables, or raise demand"
            color = int(Z'0000A5FF', c_int)
        end if
    end subroutine grid_status

    function frequency_color() result(color)
        integer(c_int) :: color

        if (abs(grid%frequency_Hz - 60.0_dp) <= 0.05_dp) then
            color = int(Z'0064A05A', c_int)
        else if (abs(grid%frequency_Hz - 60.0_dp) <= 0.25_dp) then
            color = int(Z'0000A5FF', c_int)
        else
            color = int(Z'002A48D9', c_int)
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

        r%left = left
        r%top = top
        r%right = right
        r%bottom = bottom
        brush = CreateSolidBrush(color)
        ok = FillRect(hdc, r, brush)
        ok = DeleteObject(brush)
    end subroutine fill_box

    subroutine stroke_box(hdc, left, top, right, bottom, color, width)
        type(c_ptr), value :: hdc
        integer, intent(in) :: left, top, right, bottom, width
        integer(c_int), intent(in) :: color

        call draw_line(hdc, left, top, right, top, color, width)
        call draw_line(hdc, right, top, right, bottom, color, width)
        call draw_line(hdc, right, bottom, left, bottom, color, width)
        call draw_line(hdc, left, bottom, left, top, color, width)
    end subroutine stroke_box

    subroutine draw_line(hdc, x1, y1, x2, y2, color, width)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x1, y1, x2, y2, width
        integer(c_int), intent(in) :: color
        type(c_ptr) :: pen, old_pen
        integer(c_int) :: ok

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
        integer(c_int) :: ignored, ok
        integer :: n

        n = len_trim(text)
        if (n <= 0) return
        call make_c_string(text(1:n), c_text)
        ignored = SetTextColor(hdc, color)
        ignored = SetBkMode(hdc, TRANSPARENT)
        ok = TextOutA(hdc, int(x, c_int), int(y, c_int), c_loc(c_text), int(n, c_int))
    end subroutine draw_text

    subroutine set_text(hwnd, text)
        type(c_ptr), value :: hwnd
        character(len=*), intent(in) :: text
        character(kind=c_char), allocatable, target :: c_text(:)
        integer(c_int) :: ok

        call make_c_string(text, c_text)
        ok = SetWindowTextA(hwnd, c_loc(c_text))
    end subroutine set_text

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

    function format_value(value, suffix, decimals) result(text)
        real(dp), intent(in) :: value
        character(len=*), intent(in) :: suffix
        integer, intent(in) :: decimals
        character(len=32) :: text

        select case (decimals)
        case (0)
            write(text, '(F7.0,A)') value, trim(suffix)
        case default
            write(text, '(F7.1,A)') value, trim(suffix)
        end select
        text = adjustl(text)
    end function format_value

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

    pure function make_lparam(low, high) result(value)
        integer, intent(in) :: low, high
        integer(c_intptr_t) :: value

        value = ior(iand(int(low, c_intptr_t), int(Z'FFFF', c_intptr_t)), &
            ishft(iand(int(high, c_intptr_t), int(Z'FFFF', c_intptr_t)), 16))
    end function make_lparam

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
