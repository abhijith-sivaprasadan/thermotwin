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
    integer(c_int), parameter :: WM_ERASEBKGND = 20_c_int
    integer(c_int), parameter :: WM_PAINT = 15_c_int
    integer(c_int), parameter :: WM_SETFONT = 48_c_int
    integer(c_int), parameter :: WM_COMMAND = 273_c_int
    integer(c_int), parameter :: WM_TIMER = 275_c_int
    integer(c_int), parameter :: WM_HSCROLL = 276_c_int
    integer(c_int), parameter :: WM_MOUSEMOVE = 512_c_int
    integer(c_int), parameter :: WM_LBUTTONDOWN = 513_c_int
    integer(c_int), parameter :: WM_LBUTTONUP = 514_c_int
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
    real(dp), parameter :: GAS_MIN_PCT = 20.0_dp
    real(dp), parameter :: GAS_MAX_PCT = 100.0_dp
    real(dp), parameter :: GAS_RAMP_PCT_PER_S = 18.0_dp
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
        real(dp) :: demand_MW = 45.0_dp
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
        real(dp) :: frequency_Hz = 60.0_dp
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
        integer :: history_count = 0
        integer :: history_head = 0
        real(dp) :: hist_frequency_Hz(HISTORY_N) = 60.0_dp
        real(dp) :: hist_demand_MW(HISTORY_N) = 45.0_dp
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
    end interface

    type(c_ptr) :: h_instance = c_null_ptr
    type(c_ptr) :: h_main = c_null_ptr
    type(c_ptr) :: h_font_ui = c_null_ptr
    type(c_ptr) :: h_font_title = c_null_ptr
    integer(c_int) :: active_control = ID_NONE
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

        call reset_debug_log()
        call log_debug("startup: entering run_gui")
        call InitCommonControls()
        call log_debug("startup: InitCommonControls returned")
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

        hwnd = CreateWindowExA(0_c_int, c_loc(class_name), c_loc(title), &
            WS_OVERLAPPEDWINDOW + WS_VISIBLE, CW_USEDEFAULT, CW_USEDEFAULT, &
            1240_c_int, 900_c_int, c_null_ptr, c_null_ptr, h_instance, c_null_ptr)
        if (.not. c_associated(hwnd)) then
            call fatal_gui("Could not create ThermoTwin-F GUI window.")
            stop
        end if
        call log_debug("startup: created main window")

        ok = ShowWindow(hwnd, SW_SHOW)
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
            grid%elapsed_s = grid%elapsed_s + real(TIMER_MS, dp) / 1000.0_dp
            call tick_auto_balance(real(TIMER_MS, dp) / 1000.0_dp)
            call refresh_model()
            call update_battery_soc(real(TIMER_MS, dp) / 1000.0_dp)
            call refresh_model()
            call append_history()
            call invalidate_dashboard(hwnd)
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

        case (WM_ERASEBKGND)
            lres = 1_c_intptr_t
            return

        case (WM_PAINT)
            hdc = BeginPaint(hwnd, ps)
            call draw_dashboard_buffered(hdc)
            ok = EndPaint(hwnd, ps)
            lres = 0_c_intptr_t
            return

        case (WM_DESTROY)
            call log_debug("message: WM_DESTROY")
            ok = KillTimer(hwnd, int(TIMER_ID, c_intptr_t))
            call destroy_fonts()
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

    subroutine invalidate_dashboard(hwnd)
        type(c_ptr), value :: hwnd
        type(Rect), target :: r
        integer(c_int) :: ok

        r%left = 0
        r%top = 0
        r%right = 1240
        r%bottom = 900
        ok = InvalidateRect(hwnd, c_loc(r), 0_c_int)
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
        f = clamp_real(real(x - 42, dp) / 270.0_dp, 0.0_dp, 1.0_dp)
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
        if (point_in_rect(x, y, 30, 84, 324, 146)) control_id = ID_DEMAND
        if (point_in_rect(x, y, 30, 170, 324, 232)) control_id = ID_RENEWABLE
        if (point_in_rect(x, y, 30, 256, 324, 318)) control_id = ID_STORAGE
        if (point_in_rect(x, y, 30, 342, 324, 404)) control_id = ID_GAS
        if (point_in_rect(x, y, 30, 428, 324, 490)) control_id = ID_AMBIENT
        if (point_in_rect(x, y, 30, 514, 324, 576)) control_id = ID_TIT
        if (point_in_rect(x, y, 36, 674, 172, 714)) control_id = ID_AUTO
        if (point_in_rect(x, y, 186, 674, 316, 714)) control_id = ID_BALANCE
        if (point_in_rect(x, y, 36, 728, 132, 766)) control_id = ID_RESET
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
        grid%supply_MW = grid%gas_power_MW + grid%renewable_MW + grid%storage_MW
        grid%imbalance_MW = grid%supply_MW - grid%demand_MW
        grid%reserve_MW = max(0.0_dp, grid%gas_capacity_MW - grid%gas_power_MW)
        grid%frequency_Hz = clamp_real(60.0_dp + 0.045_dp * grid%imbalance_MW, 58.5_dp, 61.5_dp)
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
    end subroutine refresh_economics

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
        grid%gas_dispatch_pct = next_pct
    end subroutine tick_auto_balance

    subroutine balance_now()
        real(dp) :: needed_gas_MW, target_pct

        if (grid%gas_capacity_MW <= 1.0e-6_dp) return
        needed_gas_MW = grid%demand_MW - grid%renewable_MW - grid%storage_MW
        target_pct = clamp_real(100.0_dp * needed_gas_MW / grid%gas_capacity_MW, GAS_MIN_PCT, GAS_MAX_PCT)
        grid%gas_dispatch_pct = target_pct
    end subroutine balance_now

    subroutine reset_controls()
        grid%auto_balance = .true.
        grid%battery_energy_MWh = BATTERY_CAPACITY_MWH * BATTERY_INITIAL_SOC_PCT / 100.0_dp
        grid%battery_soc_pct = BATTERY_INITIAL_SOC_PCT
        grid%elapsed_s = 0.0_dp
        grid%history_count = 0
        grid%history_head = 0
        grid%demand_MW = 45.0_dp
        grid%renewable_MW = 12.0_dp
        grid%storage_request_MW = 0.0_dp
        grid%storage_MW = 0.0_dp
        grid%gas_dispatch_pct = 82.0_dp
        grid%ambient_C = 15.0_dp
        grid%TIT_K = 1400.0_dp
    end subroutine reset_controls

    subroutine draw_dashboard_buffered(hdc)
        type(c_ptr), value :: hdc
        integer(c_int), parameter :: W = 1240_c_int
        integer(c_int), parameter :: H = 900_c_int
        type(c_ptr) :: memdc, bitmap, old_bitmap
        integer(c_int) :: ok

        memdc = CreateCompatibleDC(hdc)
        bitmap = CreateCompatibleBitmap(hdc, W, H)
        if (.not. c_associated(memdc) .or. .not. c_associated(bitmap)) then
            call draw_dashboard(hdc)
            return
        end if

        old_bitmap = SelectObject(memdc, bitmap)
        call draw_dashboard(memdc)
        ok = BitBlt(hdc, 0_c_int, 0_c_int, W, H, memdc, 0_c_int, 0_c_int, SRCCOPY)
        old_bitmap = SelectObject(memdc, old_bitmap)
        ok = DeleteObject(bitmap)
        ok = DeleteDC(memdc)
    end subroutine draw_dashboard_buffered

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
        integer :: x0, y0, w, h
        real(dp) :: scale_MW
        character(len=96) :: status, subtitle
        integer(c_int) :: status_color

        call fill_box(hdc, 0, 0, 1240, 900, BG)
        call draw_control_panel(hdc)

        x0 = 360
        y0 = 24
        w = 840
        h = 824
        call fill_box(hdc, x0, y0, x0 + w, y0 + h, PANEL)
        call stroke_box(hdc, x0, y0, x0 + w, y0 + h, BORDER, 1)

        call draw_title_text(hdc, x0 + 24, y0 + 22, "ThermoTwin-F Live Grid Balancer", INK)
        write(subtitle, '("Scenario time ",F7.1," s | Auto balance ",A)') &
            grid%elapsed_s, merge("ON ", "OFF", grid%auto_balance)
        call draw_text(hdc, x0 + 24, y0 + 50, trim(subtitle), MUTED)

        scale_MW = max(max(DEMAND_MAX_MW, grid%demand_MW), max(grid%supply_MW, grid%gas_capacity_MW))
        call draw_kpi_tiles(hdc, x0 + 24, y0 + 82)

        call draw_section_title_width(hdc, x0 + 24, y0 + 178, "Power balance", 752)
        call draw_bar(hdc, x0 + 24, y0 + 208, 752, 22, "Demand", grid%demand_MW, scale_MW, DEMAND)
        call draw_bar(hdc, x0 + 24, y0 + 242, 752, 22, "Total supply", grid%supply_MW, scale_MW, OK)
        call draw_stacked_supply(hdc, x0 + 24, y0 + 278, 752, 28, scale_MW, GAS, RENEW, STORAGE, ALERT)

        call draw_section_title_width(hdc, x0 + 24, y0 + 330, "Battery", 752)
        call draw_battery_panel(hdc, x0 + 24, y0 + 360, 752, 56)

        call draw_section_title_width(hdc, x0 + 24, y0 + 434, "Stability and reserve", 752)
        call draw_frequency_meter(hdc, x0 + 24, y0 + 464, 752, 36)
        call draw_bar(hdc, x0 + 24, y0 + 526, 752, 20, "Gas reserve", grid%reserve_MW, max(1.0_dp, grid%gas_capacity_MW), RENEW)

        call draw_section_title_width(hdc, x0 + 24, y0 + 572, "ROI and thermodynamic economics", 752)
        call draw_roi_panel(hdc, x0 + 24, y0 + 602, 752, 62)

        call draw_section_title_width(hdc, x0 + 24, y0 + 690, "Live traces", 390)
        call draw_history_traces(hdc, x0 + 24, y0 + 720, 390, 82)

        call draw_section_title_width(hdc, x0 + 448, y0 + 690, "Power flow", 328)
        call draw_power_flow(hdc, x0 + 450, y0 + 720)

        call grid_status(status, status_color)
        call fill_box(hdc, x0 + 24, y0 + 806, x0 + 776, y0 + 832, status_color)
        call draw_text(hdc, x0 + 34, y0 + 812, trim(status), int(Z'00FFFFFF', c_int))
    end subroutine draw_dashboard

    subroutine draw_control_panel(hdc)
        type(c_ptr), value :: hdc
        integer(c_int), parameter :: PANEL = int(Z'00FFFFFF', c_int)
        integer(c_int), parameter :: BORDER = int(Z'00D4D0CA', c_int)
        integer(c_int), parameter :: INK = int(Z'00211B16', c_int)
        integer(c_int), parameter :: MUTED = int(Z'007D746C', c_int)
        integer(c_int), parameter :: BLUE = int(Z'00D87B24', c_int)
        integer(c_int), parameter :: GREEN = int(Z'0064A05A', c_int)
        integer(c_int), parameter :: ORANGE = int(Z'0000A5FF', c_int)
        integer(c_int), parameter :: RED = int(Z'002A48D9', c_int)
        character(len=40) :: value

        call fill_box(hdc, 24, 24, 330, 848, PANEL)
        call stroke_box(hdc, 24, 24, 330, 848, BORDER, 1)
        call draw_title_text(hdc, 42, 48, "Grid Controls", INK)
        call draw_text(hdc, 42, 78, "Interactive dispatch inputs", MUTED)

        write(value, '(F5.1," MW")') grid%demand_MW
        call draw_custom_slider(hdc, ID_DEMAND, 42, 116, 270, "Demand", trim(adjustl(value)), &
            grid%demand_MW, DEMAND_MIN_MW, DEMAND_MAX_MW, RED)

        write(value, '(F5.1," MW")') grid%renewable_MW
        call draw_custom_slider(hdc, ID_RENEWABLE, 42, 202, 270, "Renewables", trim(adjustl(value)), &
            grid%renewable_MW, 0.0_dp, RENEWABLE_MAX_MW, GREEN)

        write(value, '(SP,F5.1," MW")') grid%storage_request_MW
        call draw_custom_slider(hdc, ID_STORAGE, 42, 288, 270, "Storage command", trim(adjustl(value)), &
            grid%storage_request_MW, STORAGE_MIN_MW, STORAGE_MAX_MW, BLUE)

        write(value, '(F5.0," %")') grid%gas_dispatch_pct
        call draw_custom_slider(hdc, ID_GAS, 42, 374, 270, "Gas dispatch", trim(adjustl(value)), &
            grid%gas_dispatch_pct, GAS_MIN_PCT, GAS_MAX_PCT, GREEN)

        write(value, '(F5.0," C")') grid%ambient_C
        call draw_custom_slider(hdc, ID_AMBIENT, 42, 460, 270, "Ambient", trim(adjustl(value)), &
            grid%ambient_C, -20.0_dp, 45.0_dp, ORANGE)

        write(value, '(F5.0," K")') grid%TIT_K
        call draw_custom_slider(hdc, ID_TIT, 42, 546, 270, "Firing temperature", trim(adjustl(value)), &
            grid%TIT_K, 1200.0_dp, 1600.0_dp, RED)

        if (grid%auto_balance) then
            call draw_button(hdc, 36, 674, 172, 714, "Auto: ON", GREEN)
        else
            call draw_button(hdc, 36, 674, 172, 714, "Auto: OFF", MUTED)
        end if
        call draw_button(hdc, 186, 674, 316, 714, "Balance", BLUE)
        call draw_button(hdc, 36, 728, 132, 766, "Reset", MUTED)

        call draw_text(hdc, 42, 798, "Timer: 250 ms | Solver: in-process", MUTED)
        call draw_text(hdc, 42, 820, "Units: MW, Hz, MWh, USD/h", MUTED)
    end subroutine draw_control_panel

    subroutine draw_custom_slider(hdc, control_id, x, y, width, label, value_text, value, lo, hi, color)
        type(c_ptr), value :: hdc
        integer(c_int), intent(in) :: control_id
        integer, intent(in) :: x, y, width
        character(len=*), intent(in) :: label, value_text
        real(dp), intent(in) :: value, lo, hi
        integer(c_int), intent(in) :: color
        integer(c_int), parameter :: TRACK = int(Z'00E4E7EA', c_int)
        integer(c_int), parameter :: INK = int(Z'00211B16', c_int)
        integer(c_int), parameter :: MUTED = int(Z'007D746C', c_int)
        integer :: knob_x
        real(dp) :: f

        call draw_text(hdc, x, y - 30, label, INK)
        call draw_text(hdc, x + width - 82, y - 30, value_text, MUTED)
        f = clamp_real((value - lo) / max(hi - lo, 1.0e-9_dp), 0.0_dp, 1.0_dp)
        knob_x = x + int(f * real(width, dp))
        call fill_box(hdc, x, y, x + width, y + 6, TRACK)
        call fill_box(hdc, x, y, knob_x, y + 6, color)
        call fill_box(hdc, knob_x - 6, y - 8, knob_x + 6, y + 14, int(Z'00FFFFFF', c_int))
        call stroke_box(hdc, knob_x - 6, y - 8, knob_x + 6, y + 14, color, merge(3, 2, active_control == control_id))
        call draw_text(hdc, x, y + 18, trim(format_range(lo, hi)), MUTED)
    end subroutine draw_custom_slider

    subroutine draw_button(hdc, left, top, right, bottom, label, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: left, top, right, bottom
        character(len=*), intent(in) :: label
        integer(c_int), intent(in) :: color

        call fill_box(hdc, left, top, right, bottom, int(Z'00F8FBFC', c_int))
        call stroke_box(hdc, left, top, right, bottom, color, 2)
        call draw_text(hdc, left + 14, top + 11, label, int(Z'00211B16', c_int))
    end subroutine draw_button

    function format_range(lo, hi) result(text)
        real(dp), intent(in) :: lo, hi
        character(len=48) :: text

        write(text, '(F0.0," to ",F0.0)') lo, hi
        text = adjustl(text)
    end function format_range

    subroutine draw_kpi_tiles(hdc, x, y)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y
        integer(c_int), parameter :: BORDER = int(Z'00D4D0CA', c_int)
        integer(c_int), parameter :: TILE = int(Z'00F8FBFC', c_int)
        integer(c_int), parameter :: INK = int(Z'00211B16', c_int)
        integer(c_int), parameter :: MUTED = int(Z'007D746C', c_int)
        integer(c_int), parameter :: RED = int(Z'002A48D9', c_int)
        integer(c_int), parameter :: GREEN = int(Z'0064A05A', c_int)
        integer(c_int), parameter :: AMBER = int(Z'0000A5FF', c_int)
        integer :: i, tx, ty
        character(len=64) :: value

        do i = 0, 3
            tx = x + i * 190
            call fill_box(hdc, tx, y, tx + 176, y + 70, TILE)
            call stroke_box(hdc, tx, y, tx + 176, y + 70, BORDER, 1)
        end do

        write(value, '(F6.1," MW")') grid%gas_power_MW
        call draw_text(hdc, x + 12, y + 12, "Gas output", MUTED)
        call draw_text(hdc, x + 12, y + 36, adjustl(value), INK)

        write(value, '(F7.2," Hz")') grid%frequency_Hz
        call draw_text(hdc, x + 202, y + 12, "Frequency", MUTED)
        call draw_text(hdc, x + 202, y + 36, adjustl(value), frequency_color())

        write(value, '(SP,F6.1," MW")') grid%imbalance_MW
        ty = y + 36
        call draw_text(hdc, x + 392, y + 12, "Imbalance", MUTED)
        if (abs(grid%imbalance_MW) <= 0.5_dp) then
            call draw_text(hdc, x + 392, ty, adjustl(value), GREEN)
        else
            call draw_text(hdc, x + 392, ty, adjustl(value), RED)
        end if

        write(value, '("$",F7.0,"/h")') grid%margin_usd_h
        call draw_text(hdc, x + 582, y + 12, "Net margin", MUTED)
        if (grid%margin_usd_h >= 0.0_dp) then
            call draw_text(hdc, x + 582, y + 36, adjustl(value), GREEN)
        else if (grid%margin_usd_h > -1000.0_dp) then
            call draw_text(hdc, x + 582, y + 36, adjustl(value), AMBER)
        else
            call draw_text(hdc, x + 582, y + 36, adjustl(value), RED)
        end if
    end subroutine draw_kpi_tiles

    subroutine draw_section_title_width(hdc, x, y, text, width)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width
        character(len=*), intent(in) :: text

        call draw_text(hdc, x, y, text, int(Z'00211B16', c_int))
        call draw_line(hdc, x, y + 20, x + width, y + 20, int(Z'00E5E1DB', c_int), 1)
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

    subroutine draw_battery_panel(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer(c_int), parameter :: BORDER = int(Z'00D4D0CA', c_int)
        integer(c_int), parameter :: FILL = int(Z'00D87B24', c_int)
        integer(c_int), parameter :: LOW = int(Z'002A48D9', c_int)
        integer(c_int), parameter :: INK = int(Z'00211B16', c_int)
        integer :: fill_w
        integer(c_int) :: color
        character(len=128) :: line1, line2

        if (height < 1) return
        if (grid%battery_soc_pct < 15.0_dp .or. grid%battery_soc_pct > 95.0_dp) then
            color = LOW
        else
            color = FILL
        end if

        fill_w = int(real(width - 160, dp) * clamp_real(grid%battery_soc_pct / 100.0_dp, 0.0_dp, 1.0_dp))
        call fill_box(hdc, x, y, x + width - 160, y + 22, int(Z'00EFECE8', c_int))
        call fill_box(hdc, x, y, x + fill_w, y + 22, color)
        call stroke_box(hdc, x, y, x + width - 160, y + 22, BORDER, 1)

        write(line1, '("SOC ",F5.1,"%  ",F5.1,"/",F4.0," MWh")') &
            grid%battery_soc_pct, grid%battery_energy_MWh, BATTERY_CAPACITY_MWH
        call draw_text(hdc, x + width - 148, y + 4, adjustl(line1), INK)

        write(line2, '("Request ",SP,F5.1," MW | actual ",SP,F5.1," MW")') &
            grid%storage_request_MW, grid%storage_MW
        call draw_text(hdc, x, y + 34, adjustl(line2), INK)
    end subroutine draw_battery_panel

    subroutine draw_roi_panel(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer(c_int), parameter :: BORDER = int(Z'00D4D0CA', c_int)
        integer(c_int), parameter :: PANEL = int(Z'00F8FBFC', c_int)
        integer(c_int), parameter :: INK = int(Z'00211B16', c_int)
        integer(c_int), parameter :: MUTED = int(Z'007D746C', c_int)
        integer(c_int), parameter :: GREEN = int(Z'0064A05A', c_int)
        integer(c_int), parameter :: RED = int(Z'002A48D9', c_int)
        character(len=96) :: line

        if (height < 1) return
        call fill_box(hdc, x, y, x + width, y + height, PANEL)
        call stroke_box(hdc, x, y, x + width, y + height, BORDER, 1)

        write(line, '("Revenue $",F7.0,"/h   Fuel $",F7.0,"/h   Penalty $",F7.0,"/h")') &
            grid%revenue_usd_h, grid%fuel_cost_usd_h, grid%imbalance_penalty_usd_h
        call draw_text(hdc, x + 10, y + 8, adjustl(line), INK)

        write(line, '("Heat input ",F6.1," MWth   Fuel ",F5.2," kg/s   HR ",F7.0," kJ/kWh")') &
            grid%heat_input_MW, grid%fuel_flow_kg_s, grid%heat_rate_kJ_kWh
        call draw_text(hdc, x + 10, y + 30, adjustl(line), MUTED)

        if (grid%battery_payback_years < 98.0_dp) then
            write(line, '("Battery value $",F6.0,"/h   simple payback ",F5.1," yr @ ",F5.0," h/yr")') &
                grid%battery_value_usd_h, grid%battery_payback_years, ROI_EQUIVALENT_HOURS_PER_YEAR
        else
            write(line, '("Battery value $",F6.0,"/h   simple payback: no active storage value")') &
                grid%battery_value_usd_h
        end if
        if (grid%margin_usd_h >= 0.0_dp) then
            call draw_text(hdc, x + 420, y + 8, "profitable", GREEN)
        else
            call draw_text(hdc, x + 420, y + 8, "loss-making", RED)
        end if
        call draw_text(hdc, x + 10, y + 48, adjustl(line), MUTED)
    end subroutine draw_roi_panel

    subroutine draw_history_traces(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer(c_int), parameter :: BORDER = int(Z'00D4D0CA', c_int)
        integer(c_int), parameter :: FREQ = int(Z'002A48D9', c_int)
        integer(c_int), parameter :: DEMAND = int(Z'004B5FD7', c_int)
        integer(c_int), parameter :: GAS = int(Z'0038A06B', c_int)
        integer(c_int), parameter :: MUTED = int(Z'007D746C', c_int)
        integer :: gx, gy, gw, gh

        call fill_box(hdc, x, y, x + width, y + height, int(Z'00F8FBFC', c_int))
        call stroke_box(hdc, x, y, x + width, y + height, BORDER, 1)

        call draw_text(hdc, x + 8, y + 6, "Hz", FREQ)
        call draw_text(hdc, x + 42, y + 6, "Demand", DEMAND)
        call draw_text(hdc, x + 112, y + 6, "Gas dispatch", GAS)

        gx = x + 8
        gy = y + 28
        gw = width - 16
        gh = height - 38
        call draw_line(hdc, gx, gy + gh / 2, gx + gw, gy + gh / 2, int(Z'00E5E1DB', c_int), 1)
        call draw_line(hdc, gx, gy, gx, gy + gh, int(Z'00E5E1DB', c_int), 1)
        call draw_line(hdc, gx, gy + gh, gx + gw, gy + gh, int(Z'00E5E1DB', c_int), 1)

        if (grid%history_count < 2) then
            call draw_text(hdc, gx + 56, gy + 28, "Waiting for samples", MUTED)
            return
        end if

        call draw_trace(hdc, gx, gy, gw, gh, 1, 59.0_dp, 61.0_dp, FREQ)
        call draw_trace(hdc, gx, gy, gw, gh, 2, 0.0_dp, DEMAND_MAX_MW, DEMAND)
        call draw_trace(hdc, gx, gy, gw, gh, 3, 0.0_dp, 100.0_dp, GAS)
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
        character(len=96) :: text

        if (height < 1) return
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

        call draw_node(hdc, x, y, 82, 34, "Gas", grid%gas_power_MW, GAS)
        call draw_node(hdc, x, y + 43, 82, 34, "Renew", grid%renewable_MW, RENEW)
        call draw_node(hdc, x, y + 86, 82, 34, "Storage", grid%storage_MW, STORAGE)

        call fill_box(hdc, x + 118, y + 36, x + 194, y + 88, NODE)
        call stroke_box(hdc, x + 118, y + 36, x + 194, y + 88, BORDER, 1)
        call draw_text(hdc, x + 140, y + 50, "GRID", INK)
        write(text, '(F6.2," Hz")') grid%frequency_Hz
        call draw_text(hdc, x + 130, y + 70, adjustl(text), frequency_color())

        call draw_node(hdc, x + 228, y + 43, 82, 34, "Load", grid%demand_MW, DEMAND)
        call draw_line(hdc, x + 82, y + 17, x + 118, y + 48, GAS, 3)
        call draw_line(hdc, x + 82, y + 60, x + 118, y + 62, RENEW, 3)
        call draw_line(hdc, x + 82, y + 103, x + 118, y + 76, STORAGE, 3)
        call draw_line(hdc, x + 194, y + 62, x + 228, y + 60, DEMAND, 4)
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
        type(c_ptr) :: old_font
        integer(c_int) :: ignored, ok
        integer :: n

        n = len_trim(text)
        if (n <= 0) return
        call make_c_string(text(1:n), c_text)
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
