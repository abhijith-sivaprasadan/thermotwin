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

    integer(c_int), parameter :: COL_BG = int(Z'00120F0B', c_int)
    integer(c_int), parameter :: COL_BG_GRID = int(Z'00191610', c_int)
    integer(c_int), parameter :: COL_PANEL = int(Z'001F1A11', c_int)
    integer(c_int), parameter :: COL_PANEL_ALT = int(Z'002A2317', c_int)
    integer(c_int), parameter :: COL_PANEL_DEEP = int(Z'001A150D', c_int)
    integer(c_int), parameter :: COL_BORDER = int(Z'004D4639', c_int)
    integer(c_int), parameter :: COL_BORDER_SOFT = int(Z'00373126', c_int)
    integer(c_int), parameter :: COL_INK = int(Z'00EAE7E2', c_int)
    integer(c_int), parameter :: COL_MUTED = int(Z'00A6A092', c_int)
    integer(c_int), parameter :: COL_DIM = int(Z'00787265', c_int)
    integer(c_int), parameter :: COL_CYAN = int(Z'00B8A46B', c_int)
    integer(c_int), parameter :: COL_BLUE = int(Z'00B88E6D', c_int)
    integer(c_int), parameter :: COL_GREEN = int(Z'0078A86F', c_int)
    integer(c_int), parameter :: COL_LIME = int(Z'006DB19B', c_int)
    integer(c_int), parameter :: COL_AMBER = int(Z'004D92C7', c_int)
    integer(c_int), parameter :: COL_RED = int(Z'00555BC3', c_int)

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

        function SetProcessDPIAware() bind(C, name="SetProcessDPIAware") result(ok)
            import :: c_int
            integer(c_int) :: ok
        end function SetProcessDPIAware

        function GetSystemMetrics(nIndex) bind(C, name="GetSystemMetrics") result(value)
            import :: c_int
            integer(c_int), value :: nIndex
            integer(c_int) :: value
        end function GetSystemMetrics

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

contains

    subroutine run_gui()
        type(WndClassExA) :: wc
        type(Msg) :: message
        type(c_ptr) :: hwnd
        character(kind=c_char), allocatable, target :: class_name(:)
        character(kind=c_char), allocatable, target :: title(:)
        character(len=80) :: logline
        integer(c_int) :: atom, ok, screen_w, screen_h
        integer(c_intptr_t) :: lres

        call reset_debug_log()
        call log_debug("startup: entering run_gui")
        ok = SetProcessDPIAware()
        call log_debug("startup: requested DPI-aware drawing")
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

        screen_w = GetSystemMetrics(SM_CXSCREEN)
        screen_h = GetSystemMetrics(SM_CYSCREEN)
        if (screen_w < 1024_c_int) screen_w = CANVAS_W
        if (screen_h < 720_c_int) screen_h = CANVAS_H
        write(logline, '("startup: full-screen client target ",I0,"x",I0)') screen_w, screen_h
        call log_debug(trim(logline))

        hwnd = CreateWindowExA(0_c_int, c_loc(class_name), c_loc(title), &
            WS_POPUP + WS_VISIBLE, 0_c_int, 0_c_int, &
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
        integer :: inner_x, inner_w, kpi_y, balance_y, battery_y, stability_y, roi_y
        integer :: lower_y, lower_h, lower_gap, trace_w, flow_x, flow_w
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
        inner_x = x0 + 24
        inner_w = max(500, w - 48)
        kpi_y = y0 + 112
        balance_y = max(kpi_y + 100, y0 + max(190, int(0.15_dp * real(h, dp))))
        battery_y = balance_y + max(122, int(0.10_dp * real(h, dp)))
        stability_y = battery_y + max(94, int(0.08_dp * real(h, dp)))
        roi_y = stability_y + max(126, int(0.09_dp * real(h, dp)))
        lower_y = roi_y + max(118, int(0.08_dp * real(h, dp)))
        if (lower_y > y0 + h - 190) lower_y = y0 + h - 190
        lower_h = max(100, y0 + h - lower_y - 34)
        lower_gap = 24
        trace_w = max(360, int(0.58_dp * real(inner_w, dp)))
        if (inner_w - trace_w - lower_gap < 320) trace_w = max(320, inner_w - 320 - lower_gap)
        flow_x = inner_x + trace_w + lower_gap
        flow_w = max(280, inner_w - trace_w - lower_gap)

        call fill_box(hdc, x0, y0, x0 + w, y0 + h, COL_PANEL)
        call stroke_box(hdc, x0, y0, x0 + w, y0 + h, COL_BORDER, 1)
        call fill_box(hdc, x0, y0, x0 + w, y0 + 3, COL_BORDER)

        call draw_title_text(hdc, inner_x, y0 + 20, "ThermoTwin-F Plant Control Console", COL_INK)
        write(subtitle, '("Turbine island + grid bus | t=",F6.1," s | Auto ",A)') &
            grid%elapsed_s, merge("ON ", "OFF", grid%auto_balance)
        call draw_text(hdc, inner_x, y0 + 48, trim(subtitle), COL_MUTED)
        call draw_text(hdc, x0 + w - 142, y0 + 24, "OPERATIONS HMI", COL_MUTED)
        call grid_status(status, status_color)
        call fill_box(hdc, inner_x, y0 + 72, inner_x + inner_w, y0 + 96, COL_PANEL_ALT)
        call fill_box(hdc, inner_x, y0 + 72, inner_x + 6, y0 + 96, status_color)
        call stroke_box(hdc, inner_x, y0 + 72, inner_x + inner_w, y0 + 96, status_color, 1)
        call draw_text(hdc, inner_x + 14, y0 + 76, trim(status), status_color)

        scale_MW = max(max(DEMAND_MAX_MW, grid%demand_MW), max(grid%supply_MW, grid%gas_capacity_MW))
        call draw_kpi_tiles(hdc, inner_x, kpi_y, inner_w)

        call draw_section_title_width(hdc, inner_x, balance_y, "Power balance", inner_w)
        call draw_bar(hdc, inner_x, balance_y + 28, inner_w, 24, "Demand", grid%demand_MW, scale_MW, COL_RED)
        call draw_bar(hdc, inner_x, balance_y + 62, inner_w, 24, "Supply", grid%supply_MW, scale_MW, COL_GREEN)
        call draw_stacked_supply(hdc, inner_x, balance_y + 98, inner_w, 30, scale_MW, COL_LIME, COL_GREEN, COL_BLUE, COL_AMBER)

        call draw_section_title_width(hdc, inner_x, battery_y, "Battery energy storage", inner_w)
        call draw_battery_panel(hdc, inner_x, battery_y + 30, inner_w, 54)

        call draw_section_title_width(hdc, inner_x, stability_y, "Stability and spinning reserve", inner_w)
        call draw_frequency_meter(hdc, inner_x, stability_y + 28, inner_w, 34)
        call draw_bar(hdc, inner_x, stability_y + 90, inner_w, 22, "Gas reserve", grid%reserve_MW, &
            max(1.0_dp, grid%gas_capacity_MW), COL_CYAN)

        call draw_section_title_width(hdc, inner_x, roi_y, "ROI and thermodynamic economics", inner_w)
        call draw_roi_panel(hdc, inner_x, roi_y + 30, inner_w, 86)

        call draw_section_title_width(hdc, inner_x, lower_y, "Live traces", trace_w)
        call draw_history_traces(hdc, inner_x, lower_y + 30, trace_w, lower_h)

        call draw_section_title_width(hdc, flow_x, lower_y, "Power flow", flow_w)
        call draw_power_flow(hdc, flow_x, lower_y + 30, flow_w, lower_h)
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

        call fill_box(hdc, left, top, right, bottom, COL_PANEL_DEEP)
        call stroke_box(hdc, left, top, right, bottom, COL_BORDER, 1)
        call fill_box(hdc, left, top, right, top + 3, COL_BORDER)
        call draw_title_text(hdc, title_x, top + 28, "Plant Controls", COL_INK)
        call draw_text(hdc, title_x, top + 56, "Operator dispatch console", COL_MUTED)
        call fill_box(hdc, title_x, top + 82, right - 24, top + 83, COL_BORDER_SOFT)

        write(value, '(F5.1," MW")') grid%demand_MW
        call draw_custom_slider(hdc, ID_DEMAND, layout_slider_x, layout_slider_y(1), layout_slider_w, &
            "Load demand", trim(adjustl(value)), &
            grid%demand_MW, DEMAND_MIN_MW, DEMAND_MAX_MW, COL_RED)

        write(value, '(F5.1," MW")') grid%renewable_MW
        call draw_custom_slider(hdc, ID_RENEWABLE, layout_slider_x, layout_slider_y(2), layout_slider_w, &
            "Renewable injection", trim(adjustl(value)), &
            grid%renewable_MW, 0.0_dp, RENEWABLE_MAX_MW, COL_GREEN)

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

        if (grid%auto_balance) then
            call draw_button(hdc, left + 16, layout_button_y, left + 158, layout_button_y + 42, "Auto ON", COL_GREEN)
        else
            call draw_button(hdc, left + 16, layout_button_y, left + 158, layout_button_y + 42, "Auto OFF", COL_DIM)
        end if
        call draw_button(hdc, left + 172, layout_button_y, right - 16, layout_button_y + 42, "Balance", COL_CYAN)
        call draw_button(hdc, left + 16, layout_button_y + 56, left + 124, layout_button_y + 98, "Reset", COL_AMBER)

        panel_top = layout_button_y + 124
        panel_bottom = layout_footer_y - 28
        if (panel_bottom - panel_top > 118) then
            row_gap = max(24, (panel_bottom - panel_top - 44) / 4)
            call fill_box(hdc, title_x, panel_top, right - 24, panel_bottom, COL_PANEL_ALT)
            call stroke_box(hdc, title_x, panel_top, right - 24, panel_bottom, COL_BORDER_SOFT, 1)
            call draw_text(hdc, title_x + 10, panel_top + 10, "Plant telemetry", COL_MUTED)
            write(line, '("Frequency     ",F6.2," Hz")') grid%frequency_Hz
            call draw_text(hdc, title_x + 10, panel_top + 34, adjustl(line), frequency_color())
            write(line, '("Gas reserve   ",F6.1," MW")') grid%reserve_MW
            call draw_text(hdc, title_x + 10, panel_top + 34 + row_gap, adjustl(line), COL_CYAN)
            write(line, '("BESS SOC      ",F6.1," %")') grid%battery_soc_pct
            call draw_text(hdc, title_x + 10, panel_top + 34 + 2 * row_gap, adjustl(line), COL_BLUE)
            write(line, '("Net margin $",F7.0,"/h")') grid%margin_usd_h
            call draw_text(hdc, title_x + 10, panel_top + 34 + 3 * row_gap, adjustl(line), &
                merge(COL_GREEN, COL_RED, grid%margin_usd_h >= 0.0_dp))
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
        call fill_box(hdc, x, y, x + width, y + 7, COL_PANEL_ALT)
        call fill_box(hdc, x, y, knob_x, y + 7, color)
        call stroke_box(hdc, x, y, x + width, y + 8, COL_BORDER_SOFT, 1)
        call fill_box(hdc, knob_x - 6, y - 7, knob_x + 6, y + 17, COL_PANEL)
        call stroke_box(hdc, knob_x - 6, y - 7, knob_x + 6, y + 17, color, merge(2, 1, active_control == control_id))
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

        call fill_box(hdc, left, top, right, bottom, COL_PANEL_ALT)
        call fill_box(hdc, left, top, left + 4, bottom, color)
        call stroke_box(hdc, left, top, right, bottom, COL_BORDER_SOFT, 1)
        call draw_text(hdc, left + 16, top + 12, label, COL_INK)
    end subroutine draw_button

    subroutine draw_kpi_tiles(hdc, x, y, width)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width
        integer :: i, tx, ty, tile_w, gap
        character(len=64) :: value

        gap = 16
        tile_w = max(130, (width - 3 * gap) / 4)
        do i = 0, 3
            tx = x + i * (tile_w + gap)
            call fill_box(hdc, tx, y, tx + tile_w, y + 72, COL_PANEL_ALT)
            call stroke_box(hdc, tx, y, tx + tile_w, y + 72, COL_BORDER_SOFT, 1)
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
        call stroke_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)
        write(text, '("Gas ",F5.1,"  Renew ",F5.1,"  BESS ",SP,F5.1," MW")') &
            grid%gas_power_MW, grid%renewable_MW, grid%storage_MW
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

        call fill_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
        call stroke_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)
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
    end subroutine draw_roi_panel

    subroutine draw_history_traces(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: gx, gy, gw, gh

        call fill_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
        call stroke_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)

        call draw_text(hdc, x + 10, y + 6, "Hz", COL_AMBER)
        call draw_text(hdc, x + 44, y + 6, "Demand", COL_MUTED)
        call draw_text(hdc, x + 126, y + 6, "Turbine", COL_MUTED)

        gx = x + 8
        gy = y + 28
        gw = width - 16
        gh = height - 38
        call draw_line(hdc, gx, gy + gh / 2, gx + gw, gy + gh / 2, COL_BORDER_SOFT, 1)
        call draw_line(hdc, gx, gy, gx, gy + gh, COL_BORDER_SOFT, 1)
        call draw_line(hdc, gx, gy + gh, gx + gw, gy + gh, COL_BORDER_SOFT, 1)

        if (grid%history_count < 2) then
            call draw_text(hdc, gx + 56, gy + 22, "Waiting for samples", COL_MUTED)
            return
        end if

        call draw_trace(hdc, gx, gy, gw, gh, 1, 59.0_dp, 61.0_dp, COL_AMBER)
        call draw_trace(hdc, gx, gy, gw, gh, 2, 0.0_dp, DEMAND_MAX_MW, COL_RED)
        call draw_trace(hdc, gx, gy, gw, gh, 3, 0.0_dp, 100.0_dp, COL_LIME)
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
        call fill_box(hdc, center_x - 34, y, center_x + 34, y + height, int(Z'002D3325', c_int))
        call stroke_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)
        call draw_line(hdc, center_x, y, center_x, y + height, COL_GREEN, 1)
        frac = clamp_real((grid%frequency_Hz - 58.5_dp) / 3.0_dp, 0.0_dp, 1.0_dp)
        marker_x = x + int(frac * real(width, dp))
        call draw_line(hdc, marker_x, y - 4, marker_x, y + height + 4, frequency_color(), 4)
        call draw_text(hdc, x, y + height + 8, "58.5 Hz", COL_DIM)
        call draw_text(hdc, center_x - 30, y + height + 8, "60.0 Hz", COL_DIM)
        call draw_text(hdc, x + width - 62, y + height + 8, "61.5 Hz", COL_DIM)
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
        call draw_node(hdc, x, row2, node_w, node_h, "Renew", grid%renewable_MW, COL_GREEN)
        call draw_node(hdc, x, row3, node_w, node_h, "BESS", grid%storage_MW, COL_BLUE)

        call fill_box(hdc, grid_x, grid_y, grid_x + grid_w, grid_y + grid_h, COL_PANEL_ALT)
        call stroke_box(hdc, grid_x, grid_y, grid_x + grid_w, grid_y + grid_h, COL_BORDER_SOFT, 1)
        call draw_text(hdc, grid_x + grid_w / 2 - 16, grid_y + 13, "GRID", COL_INK)
        write(text, '(F6.2," Hz")') grid%frequency_Hz
        call draw_text(hdc, grid_x + grid_w / 2 - 32, grid_y + 34, adjustl(text), frequency_color())

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

        call fill_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
        call stroke_box(hdc, x, y, x + width, y + height, color, 1)
        call draw_text(hdc, x + 10, y + 7, label, COL_INK)
        write(text, '(SP,F6.1," MW")') value
        call draw_text(hdc, x + 10, y + 24, adjustl(text), COL_MUTED)
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

        if (abs(grid%frequency_Hz - 60.0_dp) <= 0.05_dp) then
            color = COL_GREEN
        else if (abs(grid%frequency_Hz - 60.0_dp) <= 0.25_dp) then
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
