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
    use engine_core
    use scenario_runner, only: Scenario, scenario_load, scenario_gui_tick
    use opcua_bridge, only: opcua_start, opcua_stop, opcua_iterate, &
                            opcua_write, opcua_active
    use tag_bus, only: tag_count, tag_name_at, tag_value_at, tag_units_at
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
    integer(c_int), parameter :: VK_F1 = 112_c_int
    integer(c_int), parameter :: VK_F2 = 113_c_int
    integer(c_int), parameter :: VK_F3 = 114_c_int
    integer(c_int), parameter :: VK_F4 = 115_c_int
    integer(c_int), parameter :: VK_F5 = 116_c_int
    integer(c_int), parameter :: VK_F6 = 117_c_int
    integer(c_int), parameter :: VK_F7 = 118_c_int
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
    integer(c_int), parameter :: ID_ROI_MODE = 204_c_int
    integer(c_int), parameter :: ID_FCR_HOLD = 205_c_int
    integer(c_int), parameter :: ID_LOAD_STEP = 206_c_int
    integer(c_int), parameter :: ID_CLOUD_RAMP = 207_c_int
    integer(c_int), parameter :: ID_TURBINE_TRIP = 208_c_int
    integer(c_int), parameter :: ID_CC_MODE = 209_c_int
    integer(c_int), parameter :: ID_MARKET_PROFILE = 210_c_int
    integer(c_int), parameter :: ID_MARKET_REPLAY = 211_c_int
    integer(c_int), parameter :: ID_SCN_PREV     = 212_c_int
    integer(c_int), parameter :: ID_SCN_NEXT     = 213_c_int
    integer(c_int), parameter :: ID_SCN_RUN_STOP = 214_c_int
    integer(c_int), parameter :: ID_NONE = 0_c_int
    integer(c_int), parameter :: TIMER_ID = 1_c_int
    integer(c_int), parameter :: TIMER_MS = 250_c_int
    character(len=*), parameter :: DEBUG_LOG = "gui_debug.log"
    character(len=*), parameter :: CONFIG_FILE = "thermotwin.ini"

    integer, parameter :: SCREEN_OVERVIEW = 1
    integer, parameter :: SCREEN_GRID = 2
    integer, parameter :: SCREEN_GT = 3
    integer, parameter :: SCREEN_CC = 4
    integer, parameter :: SCREEN_MARKET = 5
    integer, parameter :: SCREEN_TRENDS = 6
    integer, parameter :: SCREEN_ALARMS = 7
    integer, parameter :: SCREEN_COUNT = 7
    character(len=14), parameter :: SCREEN_NAV_LABEL(SCREEN_COUNT) = &
        [character(len=14) :: "Overview", "Dispatch", "Turbine", "Cycle", "Market", "Trends", "Alarms"]
    character(len=24), parameter :: SCREEN_FULL_LABEL(SCREEN_COUNT) = &
        [character(len=24) :: "L1 Overview", "L2 Grid Dispatch", "L2 Gas Turbine", &
                              "L2 Combined Cycle", "L2 Market", "L2 Trends", "L2 Alarms"]

    integer, parameter :: FP_NONE = 0
    integer, parameter :: FP_FREQ = 1
    integer, parameter :: FP_THERMAL = 2
    integer, parameter :: FP_IMBALANCE = 3
    integer, parameter :: FP_MARGIN = 4
    integer, parameter :: FP_BESS = 5
    integer, parameter :: FP_RENEWABLE = 6
    integer, parameter :: ALARM_COUNT = 8
    integer, parameter :: ALARM_LOG_N = 36

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

    ! Physical/economic parameters and the GridState type now live in the
    ! engine (src/engine/) and arrive via `use engine_core`.

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
    integer :: hmi_screen = SCREEN_OVERVIEW
    integer :: faceplate_id = FP_NONE
    logical :: alarm_prev(ALARM_COUNT) = .false.
    logical :: alarm_seen(ALARM_COUNT) = .false.
    logical :: alarm_ack(ALARM_COUNT) = .false.
    logical :: alarm_shelved(ALARM_COUNT) = .false.
    integer :: alarm_log_count = 0
    real(dp) :: alarm_log_time(ALARM_LOG_N) = 0.0_dp
    character(len=20) :: alarm_log_name(ALARM_LOG_N) = ""
    character(len=8) :: alarm_log_state(ALARM_LOG_N) = ""
    logical :: native_renderer_ready = .false.

    ! Scenario selector and live playback state
    integer, parameter :: N_SCENARIOS = 9
    character(len=20), parameter :: SCN_LABEL(N_SCENARIOS) = [character(len=20) :: &
        "Load Step           ", "Cloud Ramp          ", "Turbine Trip        ", &
        "UFLS Cascade        ", "LFSM-O Overfreq     ", "Surge Ramp          ", &
        "Combined Cycle      ", "Fleet Dispatch      ", "Market Replay       "]
    character(len=64), parameter :: SCN_PATH(N_SCENARIOS) = [character(len=64) :: &
        "cases/scenarios/load_step.scn                                   ", &
        "cases/scenarios/cloud_ramp.scn                                  ", &
        "cases/scenarios/turbine_trip.scn                                ", &
        "cases/scenarios/ufls_cascade.scn                                ", &
        "cases/scenarios/overfrequency_lfsmo.scn                         ", &
        "cases/scenarios/surge_ramp.scn                                  ", &
        "cases/scenarios/combined_cycle.scn                              ", &
        "cases/scenarios/fleet_dispatch.scn                              ", &
        "cases/scenarios/market_replay.scn                               "]
    integer :: scn_selected = 1
    logical :: scn_playing = .false.
    type(Scenario) :: scn_active

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
            call engine_init(grid)
            call load_hmi_config()
            call refresh_model(grid)
            call append_history(grid)
            call update_alarm_workflow()
            call opcua_start(4840)
            lres = SetTimer(hwnd, int(TIMER_ID, c_intptr_t), TIMER_MS, c_null_ptr)
            call log_debug("message: WM_CREATE complete")
            lres = 0_c_intptr_t
            return

        case (WM_HSCROLL)
            call refresh_model(grid)
            call invalidate_dashboard(hwnd)
            lres = 0_c_intptr_t
            return

        case (WM_COMMAND)
            call handle_command(loword(wParam))
            call invalidate_dashboard(hwnd)
            lres = 0_c_intptr_t
            return

        case (WM_TIMER)
            if (scn_playing) then
                block
                    logical :: scn_done
                    call scenario_gui_tick(scn_active, grid, grid%elapsed_s, scn_done)
                    if (scn_done) scn_playing = .false.
                end block
            end if
            call engine_step(grid, real(TIMER_MS, dp) / 1000.0_dp)
            call update_alarm_workflow()
            call flush_opcua_tags()
            call opcua_iterate()
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
                call refresh_model(grid)
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
            call handle_key(hwnd, wParam)
            call invalidate_dashboard(hwnd)
            lres = 0_c_intptr_t
            return

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
            call save_hmi_config()
            ok = KillTimer(hwnd, int(TIMER_ID, c_intptr_t))
            call opcua_stop()
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

        layout_button_y = min(layout_control_bottom - 570, layout_slider_y(6) + 72)
        layout_footer_y = layout_control_bottom - 50

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
            call balance_now(grid)
        case (ID_CC_MODE)
            call cycle_plant_mode()
        case (ID_RESET)
            call reset_controls(grid)
        case (ID_ROI_MODE)
            grid%roi_dispatch = .not. grid%roi_dispatch
        case (ID_FCR_HOLD)
            grid%fcr_hold = .not. grid%fcr_hold
        case (ID_LOAD_STEP)
            call apply_load_step(grid)
        case (ID_CLOUD_RAMP)
            call apply_cloud_ramp(grid)
        case (ID_TURBINE_TRIP)
            call apply_turbine_trip(grid)
        case (ID_MARKET_PROFILE)
            call cycle_market_profile(grid)
        case (ID_MARKET_REPLAY)
            call toggle_market_replay()
        end select

        call refresh_model(grid)
        if (control_id == ID_RESET) call reset_alarm_workflow()
    end subroutine handle_command

    subroutine handle_mouse_down(hwnd, x, y)
        type(c_ptr), value :: hwnd
        integer, intent(in) :: x, y
        type(c_ptr) :: previous
        integer :: nav_target, fp_target
        logical :: handled

        call compute_layout_from_window(hwnd)
        nav_target = hit_test_nav(x, y)
        if (nav_target /= SCREEN_OVERVIEW - 1) then
            call set_hmi_screen(nav_target)
            active_control = ID_NONE
            return
        end if
        if (faceplate_id /= FP_NONE .and. .not. point_in_rect(x, y, &
                layout_main_left + layout_main_w / 2 - 250, layout_main_top + 110, &
                layout_main_left + layout_main_w / 2 + 250, layout_main_top + 510)) then
            faceplate_id = FP_NONE
            active_control = ID_NONE
            return
        end if
        handled = handle_alarm_mouse(x, y)
        if (handled) then
            active_control = ID_NONE
            return
        end if
        fp_target = hit_test_faceplate(x, y)
        if (fp_target /= FP_NONE) then
            faceplate_id = fp_target
            active_control = ID_NONE
            return
        end if

        active_control = hit_test_control(x, y)
        select case (active_control)
        case (ID_AUTO)
            grid%auto_balance = .not. grid%auto_balance
            active_control = ID_NONE
        case (ID_BALANCE)
            call balance_now(grid)
            active_control = ID_NONE
        case (ID_CC_MODE)
            call cycle_plant_mode()
            active_control = ID_NONE
        case (ID_RESET)
            call reset_controls(grid)
            call reset_alarm_workflow()
            active_control = ID_NONE
        case (ID_ROI_MODE)
            grid%roi_dispatch = .not. grid%roi_dispatch
            active_control = ID_NONE
        case (ID_FCR_HOLD)
            grid%fcr_hold = .not. grid%fcr_hold
            active_control = ID_NONE
        case (ID_LOAD_STEP)
            call apply_load_step(grid)
            active_control = ID_NONE
        case (ID_CLOUD_RAMP)
            call apply_cloud_ramp(grid)
            active_control = ID_NONE
        case (ID_TURBINE_TRIP)
            call apply_turbine_trip(grid)
            active_control = ID_NONE
        case (ID_MARKET_PROFILE)
            call cycle_market_profile(grid)
            active_control = ID_NONE
        case (ID_MARKET_REPLAY)
            call toggle_market_replay()
            active_control = ID_NONE
        case (ID_SCN_PREV)
            scn_selected = mod(scn_selected - 2 + N_SCENARIOS, N_SCENARIOS) + 1
            scn_playing = .false.
            active_control = ID_NONE
        case (ID_SCN_NEXT)
            scn_selected = mod(scn_selected, N_SCENARIOS) + 1
            scn_playing = .false.
            active_control = ID_NONE
        case (ID_SCN_RUN_STOP)
            if (scn_playing) then
                scn_playing = .false.
            else
                block
                    logical :: scn_ok
                    call scenario_load(trim(adjustl(SCN_PATH(scn_selected))), scn_active, scn_ok)
                    if (scn_ok) then
                        call engine_init(grid)
                        call reset_alarm_workflow()
                        scn_playing = .true.
                    end if
                end block
            end if
            active_control = ID_NONE
        case (ID_DEMAND, ID_RENEWABLE, ID_STORAGE, ID_GAS, ID_AMBIENT, ID_TIT)
            previous = SetCapture(hwnd)
            call update_active_slider(x)
        end select
        call refresh_model(grid)
    end subroutine handle_mouse_down

    subroutine handle_key(hwnd, key)
        type(c_ptr), value :: hwnd
        integer(c_intptr_t), intent(in) :: key
        integer(c_int) :: ok

        select case (int(key, c_int))
        case (VK_F1)
            call set_hmi_screen(SCREEN_OVERVIEW)
        case (VK_F2)
            call set_hmi_screen(SCREEN_GRID)
        case (VK_F3)
            call set_hmi_screen(SCREEN_GT)
        case (VK_F4)
            call set_hmi_screen(SCREEN_CC)
        case (VK_F5)
            call set_hmi_screen(SCREEN_MARKET)
        case (VK_F6)
            call set_hmi_screen(SCREEN_TRENDS)
        case (VK_F7)
            call set_hmi_screen(SCREEN_ALARMS)
        case (VK_ESCAPE)
            if (faceplate_id /= FP_NONE) then
                faceplate_id = FP_NONE
            else if (hmi_screen /= SCREEN_OVERVIEW) then
                call set_hmi_screen(SCREEN_OVERVIEW)
            else
                ok = DestroyWindow(hwnd)
            end if
        end select
    end subroutine handle_key

    subroutine set_hmi_screen(screen_id)
        integer, intent(in) :: screen_id

        hmi_screen = min(max(screen_id, SCREEN_OVERVIEW), SCREEN_ALARMS)
        faceplate_id = FP_NONE
    end subroutine set_hmi_screen

    subroutine load_hmi_config()
        integer :: unit, ios, ival
        character(len=160) :: raw
        character(len=64) :: key

        open(newunit=unit, file=CONFIG_FILE, status="old", action="read", iostat=ios)
        if (ios /= 0) return
        do
            read(unit, "(A)", iostat=ios) raw
            if (ios /= 0) exit
            if (len_trim(raw) == 0) cycle
            if (raw(1:1) == "#") cycle
            key = ""
            ival = 0
            read(raw, *, iostat=ios) key, ival
            if (ios /= 0) cycle
            select case (trim(key))
            case ("screen")
                hmi_screen = min(max(ival, SCREEN_OVERVIEW), SCREEN_ALARMS)
            case ("location_profile")
                call apply_market_profile(grid, min(max(ival, 1), MARKET_PROFILE_N))
            case ("weather_enabled")
                grid%market_weather_enabled = ival /= 0
            case ("load_replay")
                grid%market_load_replay_enabled = ival /= 0
            case ("auto_balance")
                grid%auto_balance = ival /= 0
            case ("roi_dispatch")
                grid%roi_dispatch = ival /= 0
            case ("fcr_hold")
                grid%fcr_hold = ival /= 0
            case ("combined_cycle")
                grid%combined_cycle = ival /= 0
            case ("fleet_mode")
                grid%fleet_mode = ival /= 0
                if (grid%fleet_mode) grid%combined_cycle = .true.
            end select
        end do
        close(unit)
    end subroutine load_hmi_config

    subroutine save_hmi_config()
        integer :: unit, ios

        open(newunit=unit, file=CONFIG_FILE, status="replace", action="write", iostat=ios)
        if (ios /= 0) return
        write(unit, "(A)") "# ThermoTwin-F native HMI configuration"
        write(unit, '("screen ",I0)') hmi_screen
        write(unit, '("window_fullscreen ",I0)') 1
        write(unit, '("location_profile ",I0)') grid%market_profile_id
        write(unit, '("weather_enabled ",I0)') merge(1, 0, grid%market_weather_enabled)
        write(unit, '("load_replay ",I0)') merge(1, 0, grid%market_load_replay_enabled)
        write(unit, '("auto_balance ",I0)') merge(1, 0, grid%auto_balance)
        write(unit, '("roi_dispatch ",I0)') merge(1, 0, grid%roi_dispatch)
        write(unit, '("fcr_hold ",I0)') merge(1, 0, grid%fcr_hold)
        write(unit, '("combined_cycle ",I0)') merge(1, 0, grid%combined_cycle)
        write(unit, '("fleet_mode ",I0)') merge(1, 0, grid%fleet_mode)
        write(unit, "(A)") "units SI"
        write(unit, "(A)") "api_eia_key"
        write(unit, "(A)") "api_entsoe_token"
        close(unit)
    end subroutine save_hmi_config

    subroutine reset_alarm_workflow()
        alarm_prev = .false.
        alarm_seen = .false.
        alarm_ack = .false.
        alarm_shelved = .false.
        alarm_log_count = 0
        alarm_log_name = ""
        alarm_log_state = ""
        alarm_log_time = 0.0_dp
        call update_alarm_workflow()
    end subroutine reset_alarm_workflow

    subroutine update_alarm_workflow()
        logical :: states(ALARM_COUNT)
        integer :: i

        call current_alarm_states(states)
        do i = 1, ALARM_COUNT
            if (states(i) .and. .not. alarm_prev(i)) then
                alarm_seen(i) = .true.
                alarm_ack(i) = .false.
                alarm_shelved(i) = .false.
                call log_alarm_event(i, "UNACK")
            else if (.not. states(i) .and. alarm_prev(i)) then
                alarm_seen(i) = .true.
                alarm_shelved(i) = .false.
                call log_alarm_event(i, "RTN")
            else if (states(i)) then
                alarm_seen(i) = .true.
            end if
        end do
        alarm_prev = states
    end subroutine update_alarm_workflow

    subroutine ack_all_alarms()
        logical :: states(ALARM_COUNT)
        integer :: i

        call current_alarm_states(states)
        do i = 1, ALARM_COUNT
            if (.not. alarm_seen(i)) cycle
            if (states(i)) then
                if (.not. alarm_ack(i)) call log_alarm_event(i, "ACK")
                alarm_ack(i) = .true.
            else
                alarm_seen(i) = .false.
                alarm_ack(i) = .false.
                alarm_shelved(i) = .false.
            end if
        end do
    end subroutine ack_all_alarms

    subroutine shelve_active_alarms()
        logical :: states(ALARM_COUNT)
        integer :: i

        call current_alarm_states(states)
        do i = 1, ALARM_COUNT
            if (states(i) .and. alarm_seen(i)) then
                alarm_shelved(i) = .true.
                call log_alarm_event(i, "SHLV")
            end if
        end do
    end subroutine shelve_active_alarms

    subroutine unshelve_all_alarms()
        integer :: i

        do i = 1, ALARM_COUNT
            if (alarm_shelved(i)) call log_alarm_event(i, "UNSHLV")
        end do
        alarm_shelved = .false.
    end subroutine unshelve_all_alarms

    subroutine log_alarm_event(alarm_id, state_text)
        integer, intent(in) :: alarm_id
        character(len=*), intent(in) :: state_text
        integer :: shift_to, i
        character(len=20) :: labels(ALARM_COUNT)

        call alarm_labels(labels)
        if (alarm_log_count < ALARM_LOG_N) then
            alarm_log_count = alarm_log_count + 1
        else
            do i = 1, ALARM_LOG_N - 1
                alarm_log_time(i) = alarm_log_time(i + 1)
                alarm_log_name(i) = alarm_log_name(i + 1)
                alarm_log_state(i) = alarm_log_state(i + 1)
            end do
        end if
        shift_to = alarm_log_count
        alarm_log_time(shift_to) = grid%elapsed_s
        alarm_log_name(shift_to) = labels(alarm_id)
        alarm_log_state(shift_to) = state_text(1:min(len_trim(state_text), len(alarm_log_state(shift_to))))
    end subroutine log_alarm_event

    function handle_alarm_mouse(x, y) result(handled)
        integer, intent(in) :: x, y
        logical :: handled
        integer :: x0, y0, w, h, content_y, btn_y, bx, row_y, i
        logical :: states(ALARM_COUNT)

        handled = .false.
        if (hmi_screen /= SCREEN_ALARMS) return
        x0 = layout_main_left
        y0 = layout_main_top
        w = layout_main_w
        h = layout_main_h
        content_y = hmi_content_top(y0)
        btn_y = content_y + 10
        bx = x0 + 18
        if (point_in_rect(x, y, bx, btn_y, bx + 110, btn_y + 34)) then
            call ack_all_alarms()
            handled = .true.
            return
        end if
        if (point_in_rect(x, y, bx + 122, btn_y, bx + 250, btn_y + 34)) then
            call shelve_active_alarms()
            handled = .true.
            return
        end if
        if (point_in_rect(x, y, bx + 262, btn_y, bx + 390, btn_y + 34)) then
            call unshelve_all_alarms()
            handled = .true.
            return
        end if

        call current_alarm_states(states)
        row_y = content_y + 76
        do i = 1, ALARM_COUNT
            if (point_in_rect(x, y, x0 + 18, row_y, x0 + w - 18, row_y + 32)) then
                if (alarm_seen(i) .and. states(i) .and. .not. alarm_ack(i)) then
                    alarm_ack(i) = .true.
                    call log_alarm_event(i, "ACK")
                else if (alarm_seen(i) .and. states(i)) then
                    alarm_shelved(i) = .not. alarm_shelved(i)
                    call log_alarm_event(i, merge("SHLV  ", "UNSHLV", alarm_shelved(i)))
                else if (alarm_seen(i)) then
                    alarm_seen(i) = .false.
                    alarm_ack(i) = .false.
                    alarm_shelved(i) = .false.
                end if
                handled = .true.
                return
            end if
            row_y = row_y + max(34, (h - (content_y - y0) - 250) / ALARM_COUNT)
        end do
    end function handle_alarm_mouse

    subroutine cycle_plant_mode()
        if (grid%fleet_mode) then
            grid%fleet_mode = .false.
            grid%combined_cycle = .false.
            grid%fleet_load_target_MW = 0.0_dp
        else if (grid%combined_cycle) then
            grid%fleet_mode = .true.
            grid%combined_cycle = .true.
            grid%fleet_load_target_MW = 0.0_dp
        else
            grid%combined_cycle = .true.
        end if
        if (.not. grid%combined_cycle) grid%steam_power_MW = 0.0_dp
    end subroutine cycle_plant_mode

    subroutine toggle_market_replay()
        grid%market_load_replay_enabled = .not. grid%market_load_replay_enabled
        if (grid%market_load_replay_enabled) grid%market_weather_enabled = .true.
        call refresh_market_data(grid, 0.0_dp)
    end subroutine toggle_market_replay

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
            grid%market_load_replay_enabled = .false.
        case (ID_RENEWABLE)
            grid%renewable_MW = f * RENEWABLE_MAX_MW
            grid%renewable_curtail_MW = 0.0_dp
            grid%market_weather_enabled = .false.
        case (ID_STORAGE)
            grid%storage_request_MW = STORAGE_MIN_MW + f * (STORAGE_MAX_MW - STORAGE_MIN_MW)
        case (ID_GAS)
            grid%gas_dispatch_pct = GAS_MIN_PCT + f * (GAS_MAX_PCT - GAS_MIN_PCT)
            grid%auto_balance = .false.
        case (ID_AMBIENT)
            grid%ambient_C = -20.0_dp + f * 65.0_dp
            grid%market_weather_enabled = .false.
        case (ID_TIT)
            grid%TIT_K = 1200.0_dp + f * 400.0_dp
        end select
    end subroutine update_active_slider

    function hit_test_control(x, y) result(control_id)
        integer, intent(in) :: x, y
        integer(c_int) :: control_id
        integer :: bx1, bx2, bx3, by, bw, bh, gap

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

        gap = 10
        bh = 36
        bx1 = layout_control_left + 16
        bx3 = layout_control_left + layout_control_w - 16
        bw = (bx3 - bx1 - gap) / 2
        bx2 = bx1 + bw + gap
        by = layout_button_y
        if (point_in_rect(x, y, bx1, by, bx1 + bw, by + bh)) control_id = ID_AUTO
        if (point_in_rect(x, y, bx2, by, bx3, by + bh)) control_id = ID_BALANCE
        by = layout_button_y + 44
        if (point_in_rect(x, y, bx1, by, bx1 + bw, by + bh)) control_id = ID_CC_MODE
        if (point_in_rect(x, y, bx2, by, bx3, by + bh)) control_id = ID_FCR_HOLD
        by = layout_button_y + 88
        if (point_in_rect(x, y, bx1, by, bx1 + bw, by + bh)) control_id = ID_ROI_MODE
        if (point_in_rect(x, y, bx2, by, bx3, by + bh)) control_id = ID_LOAD_STEP
        by = layout_button_y + 132
        if (point_in_rect(x, y, bx1, by, bx1 + bw, by + bh)) control_id = ID_CLOUD_RAMP
        if (point_in_rect(x, y, bx2, by, bx3, by + bh)) control_id = ID_TURBINE_TRIP
        by = layout_button_y + 176
        if (point_in_rect(x, y, bx1, by, bx1 + bw, by + bh)) control_id = ID_MARKET_PROFILE
        if (point_in_rect(x, y, bx2, by, bx3, by + bh)) control_id = ID_MARKET_REPLAY
        by = layout_button_y + 220
        if (point_in_rect(x, y, bx1, by, bx3, by + bh)) control_id = ID_RESET
        ! Scenario name box: click cycles to next scenario (when not playing)
        by = layout_button_y + 278
        if (point_in_rect(x, y, bx1, by, bx3, by + bh) .and. .not. scn_playing) &
            control_id = ID_SCN_NEXT
        by = layout_button_y + 322
        if (point_in_rect(x, y, bx1, by, bx1 + bw, by + bh)) control_id = ID_SCN_PREV
        if (point_in_rect(x, y, bx2, by, bx3, by + bh)) control_id = ID_SCN_RUN_STOP
    end function hit_test_control

    function hit_test_nav(x, y) result(screen_id)
        integer, intent(in) :: x, y
        integer :: screen_id
        integer :: tab_w, tab_x, i, nav_y, nav_h

        screen_id = 0
        nav_y = layout_main_top + 72
        nav_h = 32
        if (.not. point_in_rect(x, y, layout_main_left, nav_y, &
                layout_main_left + layout_main_w, nav_y + nav_h)) return
        tab_w = max(72, layout_main_w / SCREEN_COUNT)
        do i = 1, SCREEN_COUNT
            tab_x = layout_main_left + (i - 1) * tab_w
            if (i == SCREEN_COUNT) then
                if (point_in_rect(x, y, tab_x, nav_y, layout_main_left + layout_main_w, nav_y + nav_h)) then
                    screen_id = i
                    return
                end if
            else if (point_in_rect(x, y, tab_x, nav_y, tab_x + tab_w, nav_y + nav_h)) then
                screen_id = i
                return
            end if
        end do
    end function hit_test_nav

    function hit_test_faceplate(x, y) result(fp_id)
        integer, intent(in) :: x, y
        integer :: fp_id
        integer :: x0, y0, h, inner_x, inner_w, gy0, gh, fy, fw, fg, tx, i

        fp_id = FP_NONE
        if (hmi_screen /= SCREEN_OVERVIEW) return
        x0 = layout_main_left
        y0 = layout_main_top
        h = layout_main_h
        inner_x = x0 + 16
        inner_w = max(500, layout_main_w - 32)
        gy0 = hmi_content_top(y0)
        gh  = min(280, int(0.26_dp * real(h, dp)))
        fy = gy0 + gh + 12
        fg = 8
        fw = (inner_w - 5 * fg) / 6
        do i = 1, 6
            tx = inner_x + (i - 1) * (fw + fg)
            if (point_in_rect(x, y, tx, fy, tx + fw, fy + 68)) then
                fp_id = i
                return
            end if
        end do
    end function hit_test_faceplate

    pure function hmi_content_top(y0) result(top)
        integer, intent(in) :: y0
        integer :: top

        top = y0 + 154
    end function hmi_content_top

    pure function point_in_rect(x, y, left, top, right, bottom) result(inside)
        integer, intent(in) :: x, y, left, top, right, bottom
        logical :: inside

        inside = (x >= left .and. x <= right .and. y >= top .and. y <= bottom)
    end function point_in_rect

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
        character(len=96) :: status, subtitle, title
        character(len=12) :: auto_text, dispatch_text, reserve_text, plant_text
        integer(c_int) :: status_color
        integer :: gx, gy, content_y, content_h

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
        write(title, '("ThermoTwin-F | Plant Control Console | ",F4.0," Hz ",A)') &
            grid%nominal_frequency_Hz, trim(grid%market_power_zone)
        call draw_title_text(hdc, inner_x + 8, y0 + 10, trim(title), COL_INK)
        if (grid%auto_balance) then
            auto_text = "AUTO"
        else
            auto_text = "MANUAL"
        end if
        if (grid%roi_dispatch) then
            dispatch_text = "ROI"
        else
            dispatch_text = "STABILITY"
        end if
        if (grid%fcr_hold) then
            reserve_text = "FCR HOLD"
        else
            reserve_text = "FREE BESS"
        end if
        if (grid%fleet_mode) then
            plant_text = "FLEET"
        else if (grid%combined_cycle) then
            plant_text = "CC"
        else
            plant_text = "SIMPLE"
        end if
        write(subtitle, '("t=",F6.1,"s  ",A," | ",A," | ",A," | ",A)') &
            grid%elapsed_s, trim(plant_text), trim(auto_text), trim(dispatch_text), trim(reserve_text)
        call draw_text(hdc, x0 + w - 420, y0 + 14, trim(subtitle), &
            merge(COL_LIME, COL_AMBER, grid%auto_balance))

        ! --- Status banner ---
        call grid_status(status, status_color)
        call fill_box(hdc, x0, y0 + 44, x0 + w, y0 + 68, COL_PANEL_ALT)
        call fill_box(hdc, x0, y0 + 44, x0 + 6, y0 + 68, status_color)
        call draw_line(hdc, x0, y0 + 68, x0 + w, y0 + 68, COL_BORDER_SOFT, 1)
        call draw_text(hdc, inner_x + 10, y0 + 50, trim(status), status_color)

        ! --- Screen navigation ---
        call draw_nav_bar(hdc, x0, y0 + 72, w, 32)

        ! --- Annunciator strip ---
        call draw_annunciator_panel(hdc, x0, y0 + 108, w, 38)

        content_y = hmi_content_top(y0)
        content_h = max(260, y0 + h - content_y - 12)

        if (hmi_screen /= SCREEN_OVERVIEW) then
            select case (hmi_screen)
            case (SCREEN_GRID)
                call draw_grid_dispatch_screen(hdc, x0, content_y, w, content_h)
            case (SCREEN_GT)
                call draw_gas_turbine_screen(hdc, x0, content_y, w, content_h)
            case (SCREEN_CC)
                call draw_combined_cycle_screen(hdc, x0, content_y, w, content_h)
            case (SCREEN_MARKET)
                call draw_market_screen(hdc, x0, content_y, w, content_h)
            case (SCREEN_TRENDS)
                call draw_trends_screen(hdc, x0, content_y, w, content_h)
            case (SCREEN_ALARMS)
                call draw_alarms_screen(hdc, x0, content_y, w, content_h)
            end select
            if (faceplate_id /= FP_NONE) call draw_kpi_faceplate_popup(hdc, x0, y0, w, h)
            return
        end if

        ! --- Arc gauges + power balance ---
        block
            integer :: gy0, gh, gr, gcy, gcx1, gcx2, bar_x, bar_w
            character(len=28) :: vt

            gy0 = content_y
            gh  = min(280, int(0.26_dp * real(h, dp)))
            gr  = (gh - 40) / 2
            gcy = gy0 + gh / 2 + 8
            gcx1 = inner_x + gr + 16
            gcx2 = inner_x + 2 * gr + 80 + gr + 16

            call fill_box(hdc, x0, gy0, x0 + w, gy0 + gh, COL_PANEL)
            call draw_line(hdc, x0, gy0 + gh, x0 + w, gy0 + gh, COL_BORDER_SOFT, 1)
            call draw_arc_gauge_freq(hdc, gcx1, gcy, gr)
            call draw_arc_gauge_mw(hdc, gcx2, gcy, gr, grid%plant_power_MW, grid%plant_capacity_MW, "PLANT MW")

            scale_MW = max(max(DEMAND_MAX_MW, grid%demand_MW), max(grid%supply_MW, grid%plant_capacity_MW))
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
                max(1.0_dp, grid%plant_capacity_MW), COL_CYAN)

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
                if (grid%fleet_mode) then
                    write(vt, '(F5.1," MW ST",F4.1)') grid%plant_power_MW, grid%steam_power_MW
                else if (grid%combined_cycle) then
                    write(vt, '(F5.1," MW ST",F4.1)') grid%plant_power_MW, grid%steam_power_MW
                else
                    write(vt, '(F6.1," MW  ",F5.0,"%")') grid%plant_power_MW, &
                        100.0_dp * grid%gas_power_MW / max(grid%gas_capacity_MW, 1.0e-9_dp)
                end if
                call draw_faceplate(hdc, fp2, fy, fw, 68, "THERMAL", trim(adjustl(vt)), COL_LIME)
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
                write(vt, '(F5.1,"/",F4.0," MW")') effective_renewable_MW(grid), grid%renewable_MW
                call draw_faceplate(hdc, fp6, fy, fw, 68, "RES INJECTION", trim(adjustl(vt)), &
                    merge(COL_AMBER, COL_GREEN, grid%renewable_curtail_MW > 0.05_dp))

                ! --- ROI panel ---
                call draw_section_title_width(hdc, inner_x, fy + 80, "ROI and thermodynamic economics", inner_w)
                call draw_roi_panel(hdc, inner_x, fy + 102, inner_w, 90)

                ! --- Live traces + power flow ---
                block
                    integer :: ly, lh, lg, tw, fx2, fw2
                    ly = fy + 80 + 118
                    if (ly > y0 + h - 170) ly = y0 + h - 170
                    if (ly < fy + 198) ly = fy + 198
                    lh = y0 + h - ly - 18
                    lh = min(max(150, lh), 340)
                    if (ly + lh > y0 + h - 12) lh = max(120, y0 + h - ly - 12)
                    lg = 20
                    tw = max(360, int(0.60_dp * real(inner_w, dp)))
                    if (inner_w - tw - lg < 240) tw = max(300, inner_w - 240 - lg)
                    fx2 = inner_x + tw + lg
                    fw2 = max(220, inner_w - tw - lg)
                    call draw_section_title_width(hdc, inner_x, ly, &
                        "Live traces  (Hz | demand MW | turbine %)", tw)
                    call draw_history_traces(hdc, inner_x, ly + 26, tw, lh)
                    call draw_section_title_width(hdc, fx2, ly, "Power flow", fw2)
                    call draw_power_flow(hdc, fx2, ly + 26, fw2, lh)
                end block
            end block
        end block
        if (faceplate_id /= FP_NONE) call draw_kpi_faceplate_popup(hdc, x0, y0, w, h)
    end subroutine draw_dashboard

    subroutine draw_control_panel(hdc)
        type(c_ptr), value :: hdc
        character(len=40) :: value
        character(len=64) :: line, button_text, scn_txt
        integer :: left, top, right, bottom, title_x, panel_top, panel_bottom, row_gap
        integer :: bx1, bx2, bx3, by, btn_w, btn_h, btn_gap
        real(dp) :: scn_prog

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

        write(value, '(F4.1,"/",F4.1," MW")') effective_renewable_MW(grid), grid%renewable_MW
        call draw_custom_slider(hdc, ID_RENEWABLE, layout_slider_x, layout_slider_y(2), layout_slider_w, &
            "Renewable dispatch", trim(adjustl(value)), &
            effective_renewable_MW(grid), 0.0_dp, RENEWABLE_MAX_MW, &
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

        btn_gap = 10
        btn_h = 36
        bx1 = left + 16
        bx3 = right - 16
        btn_w = (bx3 - bx1 - btn_gap) / 2
        bx2 = bx1 + btn_w + btn_gap
        by = layout_button_y

        call draw_text(hdc, title_x, by - 20, "Dispatch controls", COL_MUTED)

        ! AUTO/MAN latching mode button
        if (grid%auto_balance) then
            call draw_industrial_button(hdc, bx1, by, bx1 + btn_w, by + btn_h, &
                "AUTO ON", COL_GREEN, .true.)
        else
            call draw_industrial_button(hdc, bx1, by, bx1 + btn_w, by + btn_h, &
                "MANUAL", COL_PANEL_ALT, .false.)
        end if
        call draw_industrial_button(hdc, bx2, by, bx3, by + btn_h, &
            "BALANCE 1X", COL_PANEL, .false.)

        by = layout_button_y + 44
        if (grid%fleet_mode) then
            call draw_industrial_button(hdc, bx1, by, bx1 + btn_w, by + btn_h, &
                "FLEET", COL_CYAN, .true.)
        else if (grid%combined_cycle) then
            call draw_industrial_button(hdc, bx1, by, bx1 + btn_w, by + btn_h, &
                "COMBINED", COL_CYAN, .true.)
        else
            call draw_industrial_button(hdc, bx1, by, bx1 + btn_w, by + btn_h, &
                "SIMPLE", COL_PANEL_ALT, .false.)
        end if
        if (grid%fcr_hold) then
            call draw_industrial_button(hdc, bx2, by, bx3, by + btn_h, &
                "FCR HOLD", COL_CYAN, .true.)
        else
            call draw_industrial_button(hdc, bx2, by, bx3, by + btn_h, &
                "FREE BESS", COL_PANEL_ALT, .false.)
        end if

        by = layout_button_y + 88
        if (grid%roi_dispatch) then
            call draw_industrial_button(hdc, bx1, by, bx1 + btn_w, by + btn_h, &
                "ROI MODE", COL_GREEN, .true.)
        else
            call draw_industrial_button(hdc, bx1, by, bx1 + btn_w, by + btn_h, &
                "STABILITY", COL_AMBER, .true.)
        end if
        call draw_industrial_button(hdc, bx2, by, bx3, by + btn_h, &
            "LOAD +10", COL_PANEL, .false.)

        by = layout_button_y + 132
        call draw_industrial_button(hdc, bx1, by, bx1 + btn_w, by + btn_h, &
            "CLOUD -15", COL_PANEL, .false.)
        if (grid%fleet_mode) then
            call draw_industrial_button(hdc, bx2, by, bx3, by + btn_h, &
                "CC1 TRIP", COL_RED, .false.)
        else
            call draw_industrial_button(hdc, bx2, by, bx3, by + btn_h, &
                "TURB TRIP", COL_RED, .false.)
        end if

        by = layout_button_y + 176
        button_text = "LOC "//trim(grid%market_power_zone)
        call draw_industrial_button(hdc, bx1, by, bx1 + btn_w, by + btn_h, &
            trim(button_text), COL_CYAN, grid%market_weather_enabled)
        if (grid%market_load_replay_enabled) then
            call draw_industrial_button(hdc, bx2, by, bx3, by + btn_h, &
                "REPLAY ON", COL_GREEN, .true.)
        else
            call draw_industrial_button(hdc, bx2, by, bx3, by + btn_h, &
                "REPLAY", COL_PANEL_ALT, .false.)
        end if

        by = layout_button_y + 220
        call draw_industrial_button(hdc, bx1, by, bx3, by + btn_h, &
            "RESET", COL_PANEL, .false.)

        ! Scenario playback selector
        by = layout_button_y + 262
        call fill_box(hdc, title_x, by, right - 24, by + 1, COL_BORDER_SOFT)
        call draw_text(hdc, title_x, by + 4, "Scenario playback", COL_MUTED)

        by = layout_button_y + 278
        call fill_soft_box(hdc, bx1, by, bx3, by + btn_h, COL_PANEL_ALT)
        call stroke_soft_box(hdc, bx1, by, bx3, by + btn_h, &
            merge(COL_GREEN, COL_BORDER_SOFT, scn_playing), 1)
        write(scn_txt, '(I0,"/",I0,"  ",A)') scn_selected, N_SCENARIOS, &
            trim(SCN_LABEL(scn_selected))
        call draw_text(hdc, bx1 + 10, by + 11, trim(adjustl(scn_txt)), &
            merge(COL_GREEN, COL_INK, scn_playing))
        if (scn_playing .and. scn_active%duration_s > 0.0_dp) then
            scn_prog = min(1.0_dp, grid%elapsed_s / scn_active%duration_s)
            call fill_box(hdc, bx1 + 1, by + btn_h - 4, &
                bx1 + 1 + int(scn_prog * real(bx3 - bx1 - 2, dp)), &
                by + btn_h - 1, COL_GREEN)
        end if

        by = layout_button_y + 322
        call draw_industrial_button(hdc, bx1, by, bx1 + btn_w, by + btn_h, &
            "<< SCN", COL_PANEL, .false.)
        if (scn_playing) then
            call draw_industrial_button(hdc, bx2, by, bx3, by + btn_h, &
                "STOP SCN", COL_RED, .true.)
        else
            call draw_industrial_button(hdc, bx2, by, bx3, by + btn_h, &
                "RUN SCN >>", COL_LIME, .false.)
        end if

        panel_top = layout_button_y + 366
        panel_bottom = layout_footer_y - 28
        if (panel_bottom - panel_top > 120) then
            row_gap = max(20, (panel_bottom - panel_top - 48) / 5)
            call fill_soft_box(hdc, title_x, panel_top, right - 24, panel_bottom, COL_PANEL_ALT)
            call stroke_soft_box(hdc, title_x, panel_top, right - 24, panel_bottom, COL_BORDER_SOFT, 1)
            call draw_text(hdc, title_x + 10, panel_top + 10, "Plant telemetry", COL_MUTED)
            if (opcua_active()) then
                call draw_text(hdc, right - 88, panel_top + 10, "OPC 4840", COL_GREEN)
            end if
            write(line, '("Freq  ",F7.3," Hz")') grid%frequency_Hz
            call draw_text(hdc, title_x + 10, panel_top + 34, adjustl(line), frequency_color())
            if (grid%fleet_mode) then
                write(line, '("Fleet ",F5.1,"/",F4.0," MW")') grid%fleet_total_MW, grid%fleet_online_capacity_MW
                call draw_text(hdc, title_x + 10, panel_top + 34 + row_gap, adjustl(line), COL_CYAN)
                write(line, '("Rsv   ",F5.1,"/",F4.1," MW")') grid%fleet_reserve_MW, grid%fleet_reserve_requirement_MW
                call draw_text(hdc, title_x + 10, panel_top + 34 + 2 * row_gap, adjustl(line), &
                    merge(COL_RED, COL_CYAN, grid%fleet_reserve_binding))
                write(line, '("LMP   $",F5.0,"/MWh")') grid%fleet_lmp_usd_MWh
                call draw_text(hdc, title_x + 10, panel_top + 34 + 3 * row_gap, adjustl(line), COL_GREEN)
                write(line, '("Inert ",F5.0," MWs  MU",I1)') grid%fleet_inertia_MWs, grid%fleet_marginal_unit
                call draw_text(hdc, title_x + 10, panel_top + 34 + 4 * row_gap, adjustl(line), COL_MUTED)
            else if (grid%combined_cycle) then
                write(line, '("ST    ",F5.1,"/",F4.1," MW")') grid%steam_power_MW, grid%steam_capacity_MW
                call draw_text(hdc, title_x + 10, panel_top + 34 + row_gap, adjustl(line), COL_CYAN)
                write(line, '("HRSG  ",F5.1," MW rec")') grid%hrsg_recovered_heat_MW
                call draw_text(hdc, title_x + 10, panel_top + 34 + 2 * row_gap, adjustl(line), COL_MUTED)
                write(line, '("Pinch ",F5.1," K  Stack ",F4.0)') grid%hrsg_pinch_K, grid%hrsg_stack_T_K
                call draw_text(hdc, title_x + 10, panel_top + 34 + 3 * row_gap, adjustl(line), &
                    merge(COL_AMBER, COL_CYAN, grid%alarm_hrsg_pinch))
                write(line, '("Eta   ",F5.1,"%  Cond ",F4.1)') &
                    grid%plant_efficiency * 100.0_dp, grid%condenser_pressure_kPa
                call draw_text(hdc, title_x + 10, panel_top + 34 + 4 * row_gap, adjustl(line), COL_GREEN)
            else
                write(line, '("RES   ",F5.1,"/",F4.0," MW")') effective_renewable_MW(grid), grid%renewable_MW
                call draw_text(hdc, title_x + 10, panel_top + 34 + row_gap, adjustl(line), &
                    merge(COL_AMBER, COL_GREEN, grid%renewable_curtail_MW > 0.05_dp))
                write(line, '("ROCOF ",SP,F5.3," Hz/s")') grid%ROCOF_Hz_s
                call draw_text(hdc, title_x + 10, panel_top + 34 + 2 * row_gap, adjustl(line), COL_MUTED)
                write(line, '("Rsv  ",F6.1," MW  S",I1)') grid%reserve_MW, grid%UFLS_stage
                call draw_text(hdc, title_x + 10, panel_top + 34 + 3 * row_gap, adjustl(line), &
                    merge(COL_RED, COL_CYAN, grid%alarm_ufls_active))
                write(line, '("SOC  ",F5.1,"%  Gov",SP,F5.1)') &
                    grid%battery_soc_pct, grid%governor_delta_MW
                call draw_text(hdc, title_x + 10, panel_top + 34 + 4 * row_gap, adjustl(line), COL_BLUE)
            end if
        end if

        call fill_box(hdc, title_x, layout_footer_y - 12, right - 24, layout_footer_y - 11, COL_BORDER_SOFT)
        write(line, '("Loop 250 ms | ",A)') trim(grid%market_profile_name)
        call draw_text(hdc, title_x, layout_footer_y, trim(line), COL_MUTED)
        write(line, '("P$",F4.0,"/MWh  Gas$",F4.1,"/GJ  CO2$",F4.0,"/t")') &
            grid%power_price_usd_mwh, grid%fuel_price_usd_gj, grid%carbon_price_usd_t
        call draw_text(hdc, title_x, layout_footer_y + 20, trim(adjustl(line)), COL_DIM)
    end subroutine draw_control_panel

    subroutine draw_nav_bar(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: i, tab_w, tx, tx2, key_x
        integer(c_int) :: body, accent, text_col
        character(len=32) :: label

        call fill_box(hdc, x, y, x + width, y + height, COL_PANEL_DEEP)
        call draw_line(hdc, x, y, x + width, y, COL_BORDER, 1)
        call draw_line(hdc, x, y + height, x + width, y + height, COL_BORDER_SOFT, 1)
        tab_w = max(72, width / SCREEN_COUNT)
        do i = 1, SCREEN_COUNT
            tx = x + (i - 1) * tab_w
            tx2 = merge(x + width, tx + tab_w - 2, i == SCREEN_COUNT)
            if (i == hmi_screen) then
                body = COL_PANEL_ALT
                accent = COL_CYAN
                text_col = COL_INK
            else
                body = COL_PANEL_DEEP
                accent = COL_BORDER_SOFT
                text_col = COL_MUTED
            end if
            call fill_box(hdc, tx + 1, y + 3, tx2, y + height - 3, body)
            call fill_box(hdc, tx + 1, y + 3, tx + 4, y + height - 3, accent)
            if (i == hmi_screen) call stroke_box(hdc, tx + 1, y + 3, tx2, y + height - 3, COL_BORDER, 1)
            write(label, '("F",I1," ",A)') i, trim(SCREEN_NAV_LABEL(i))
            key_x = tx + 12
            call draw_text(hdc, key_x, y + 8, trim(label), text_col)
        end do
    end subroutine draw_nav_bar

    subroutine draw_screen_caption(hdc, x, y, width, title, subtitle)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width
        character(len=*), intent(in) :: title, subtitle

        call draw_title_text(hdc, x, y, title, COL_INK)
        call draw_text(hdc, x, y + 28, subtitle, COL_MUTED)
        call draw_line(hdc, x, y + 54, x + width, y + 54, COL_BORDER_SOFT, 1)
    end subroutine draw_screen_caption

    subroutine draw_metric_tile(hdc, x, y, width, height, label, value_text, value_color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        character(len=*), intent(in) :: label, value_text
        integer(c_int), intent(in) :: value_color

        call fill_soft_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
        call fill_box(hdc, x, y, x + 4, y + height, value_color)
        call stroke_soft_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)
        call draw_text(hdc, x + 12, y + 10, label, COL_MUTED)
        call draw_title_text(hdc, x + 12, y + height - 34, value_text, value_color)
    end subroutine draw_metric_tile

    subroutine draw_value_pair(hdc, x, y, label, value_text, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y
        character(len=*), intent(in) :: label, value_text
        integer(c_int), intent(in) :: color

        call draw_text(hdc, x, y, label, COL_MUTED)
        call draw_text(hdc, x + 168, y, value_text, color)
    end subroutine draw_value_pair

    subroutine draw_grid_dispatch_screen(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: ix, iw, top_y, table_w, right_x, right_w, plot_h, flow_h
        character(len=96) :: subtitle, line

        ix = x + 18
        iw = width - 36
        top_y = y + 8
        write(subtitle, '("AGC ",A," | ED ",A," | reserve ",F5.1," MW | inertia ",F5.0," MWs")') &
            merge("AUTO  ", "MANUAL", grid%auto_balance), merge("ROI", "STB", grid%roi_dispatch), &
            merge(grid%fleet_reserve_MW, grid%reserve_MW, grid%fleet_mode), &
            merge(grid%fleet_inertia_MWs, INERTIA_MWs, grid%fleet_mode)
        call draw_screen_caption(hdc, ix, top_y, iw, SCREEN_FULL_LABEL(SCREEN_GRID), trim(subtitle))

        table_w = max(560, int(0.56_dp * real(iw, dp)))
        right_x = ix + table_w + 18
        right_w = max(260, iw - table_w - 18)
        call draw_section_title_width(hdc, ix, top_y + 76, "Unit dispatch and AGC participation", table_w)
        call draw_dispatch_table(hdc, ix, top_y + 104, table_w, min(height - 150, 250))

        call draw_section_title_width(hdc, right_x, top_y + 76, "Frequency and reserve", right_w)
        call draw_frequency_meter(hdc, right_x, top_y + 108, right_w, 38)
        if (grid%fleet_mode) then
            write(line, '("Reserve margin ",F5.1," / ",F5.1," MW")') &
                grid%fleet_reserve_MW, grid%fleet_reserve_requirement_MW
        else
            write(line, '("Reserve margin ",F5.1," MW  governor ",SP,F5.1," MW")') &
                grid%reserve_MW, grid%governor_delta_MW
        end if
        call draw_text(hdc, right_x, top_y + 178, trim(adjustl(line)), &
            merge(COL_RED, COL_CYAN, grid%alarm_low_reserve .or. grid%fleet_reserve_binding))
        write(line, '("BESS actual ",SP,F5.1," MW  SOC ",F5.1,"%  primary ",SP,F5.1," MW")') &
            grid%storage_MW, grid%battery_soc_pct, grid%BESS_primary_MW
        call draw_text(hdc, right_x, top_y + 202, trim(adjustl(line)), COL_BLUE)
        write(line, '("RES actual ",F5.1," MW  curtail ",F5.1," MW  headroom ",F5.1," MW")') &
            effective_renewable_MW(grid), grid%renewable_curtail_MW, renewable_headroom_MW(grid)
        call draw_text(hdc, right_x, top_y + 226, trim(adjustl(line)), COL_GREEN)

        plot_h = max(160, height - 430)
        call draw_section_title_width(hdc, ix, y + height - plot_h - 28, &
            "Live trend context", table_w)
        call draw_history_traces(hdc, ix, y + height - plot_h, table_w, plot_h)
        flow_h = plot_h
        call draw_section_title_width(hdc, right_x, y + height - flow_h - 28, "Power flow", right_w)
        call draw_power_flow(hdc, right_x, y + height - flow_h, right_w, flow_h)
    end subroutine draw_grid_dispatch_screen

    subroutine draw_dispatch_table(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: row_h, row_y, i

        row_h = 34
        call fill_soft_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
        call stroke_soft_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)
        call draw_text(hdc, x + 12, y + 10, "Unit", COL_MUTED)
        call draw_text(hdc, x + 100, y + 10, "State", COL_MUTED)
        call draw_text(hdc, x + 178, y + 10, "SP MW", COL_MUTED)
        call draw_text(hdc, x + 258, y + 10, "Actual", COL_MUTED)
        call draw_text(hdc, x + 350, y + 10, "Capacity", COL_MUTED)
        call draw_text(hdc, x + 456, y + 10, "Cost", COL_MUTED)
        row_y = y + 38
        if (grid%fleet_mode) then
            do i = 1, FLEET_N
                call draw_dispatch_row(hdc, x, row_y, width, trim(FLEET_UNIT_NAME(i)), &
                    grid%fleet_unit_online(i), grid%fleet_unit_setpoint_MW(i), &
                    grid%fleet_unit_actual_MW(i), grid%fleet_unit_capacity_MW(i), &
                    grid%fleet_unit_cost_usd_MWh(i), grid%fleet_unit_participation(i), &
                    merge(COL_RED, COL_CYAN, .not. grid%fleet_unit_online(i)))
                row_y = row_y + row_h
            end do
        else
            call draw_dispatch_row(hdc, x, row_y, width, "GT1", .true., &
                grid%gas_dispatch_pct * grid%gas_capacity_MW / 100.0_dp, grid%gas_power_MW, &
                grid%gas_capacity_MW, grid%fuel_price_usd_gj * grid%gt_heat_rate_kJ_kWh / 3600.0_dp, &
                1.0_dp, COL_LIME)
            row_y = row_y + row_h
            call draw_dispatch_row(hdc, x, row_y, width, "ST1", grid%combined_cycle, &
                grid%steam_power_target_MW, grid%steam_power_MW, grid%steam_capacity_MW, &
                0.0_dp, 0.0_dp, COL_CYAN)
            row_y = row_y + row_h
            call draw_dispatch_row(hdc, x, row_y, width, "REN", .true., &
                grid%renewable_MW, effective_renewable_MW(grid), RENEWABLE_MAX_MW, &
                -grid%renewable_reserve_price_usd_mw_h, 0.0_dp, COL_GREEN)
            row_y = row_y + row_h
            call draw_dispatch_row(hdc, x, row_y, width, "BESS", .true., &
                grid%storage_request_MW, grid%storage_MW, STORAGE_MAX_MW, &
                BESS_DEGRADATION_USD_MWH, 0.0_dp, COL_BLUE)
        end if
    end subroutine draw_dispatch_table

    subroutine draw_dispatch_row(hdc, x, y, width, name, online, sp, actual, capacity, cost, part, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width
        character(len=*), intent(in) :: name
        logical, intent(in) :: online
        real(dp), intent(in) :: sp, actual, capacity, cost, part
        integer(c_int), intent(in) :: color
        character(len=32) :: text

        call draw_line(hdc, x + 8, y - 3, x + width - 8, y - 3, COL_BORDER_SOFT, 1)
        call fill_box(hdc, x + 10, y + 3, x + 14, y + 27, color)
        call draw_text(hdc, x + 22, y + 6, name, COL_INK)
        call draw_text(hdc, x + 100, y + 6, merge("ONLINE ", "OFFLINE", online), merge(COL_GREEN, COL_RED, online))
        write(text, '(SP,F7.1)') sp
        call draw_text(hdc, x + 178, y + 6, trim(adjustl(text)), COL_MUTED)
        write(text, '(SP,F7.1)') actual
        call draw_text(hdc, x + 258, y + 6, trim(adjustl(text)), color)
        write(text, '(F7.1)') capacity
        call draw_text(hdc, x + 350, y + 6, trim(adjustl(text)), COL_MUTED)
        if (abs(cost) > 0.01_dp) then
            write(text, '("$",F6.1)') cost
        else
            write(text, '(F6.2)') part
        end if
        call draw_text(hdc, x + 456, y + 6, trim(adjustl(text)), COL_AMBER)
    end subroutine draw_dispatch_row

    subroutine draw_gas_turbine_screen(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: ix, iw, top_y, map_w, side_x, side_w, row_y
        character(len=96) :: subtitle, value
        integer(c_int) :: surge_color

        ix = x + 18
        iw = width - 36
        top_y = y + 8
        write(subtitle, '("Station ",F4.0," C | TIT ",F5.0," K | IGV ",F5.1,"% | ramp ",SP,F5.1,"%/s")') &
            grid%ambient_C, grid%TIT_actual_K, grid%igv_pct, grid%gas_ramp_pct_per_s
        call draw_screen_caption(hdc, ix, top_y, iw, SCREEN_FULL_LABEL(SCREEN_GT), trim(subtitle))

        map_w = max(520, int(0.58_dp * real(iw, dp)))
        side_x = ix + map_w + 18
        side_w = max(260, iw - map_w - 18)
        call draw_section_title_width(hdc, ix, top_y + 76, "Compressor operating map", map_w)
        call draw_gt_map(hdc, ix, top_y + 104, map_w, max(260, height - 230))

        call draw_section_title_width(hdc, side_x, top_y + 76, "Station values", side_w)
        surge_color = merge(COL_RED, merge(COL_AMBER, COL_GREEN, grid%surge_margin_pct < 12.0_dp), &
            grid%surge_margin_pct < 6.0_dp)
        row_y = top_y + 112
        write(value, '(F6.1," MW / ",F5.1," MW")') grid%gas_power_MW, grid%gas_capacity_MW
        call draw_value_pair(hdc, side_x + 10, row_y, "GT net output", trim(adjustl(value)), COL_LIME)
        row_y = row_y + 28
        write(value, '(F6.1,"%")') grid%surge_margin_pct
        call draw_value_pair(hdc, side_x + 10, row_y, "Surge margin", trim(adjustl(value)), surge_color)
        row_y = row_y + 28
        write(value, '(F6.2)') grid%PR_op
        call draw_value_pair(hdc, side_x + 10, row_y, "Pressure ratio", trim(adjustl(value)), COL_CYAN)
        row_y = row_y + 28
        write(value, '(F6.1,"%  flow ",F5.1,"%")') grid%igv_pct, 100.0_dp * grid%flow_frac
        call draw_value_pair(hdc, side_x + 10, row_y, "IGV / flow", trim(adjustl(value)), COL_MUTED)
        row_y = row_y + 28
        write(value, '(F7.0," kJ/kWh")') grid%gt_heat_rate_kJ_kWh
        call draw_value_pair(hdc, side_x + 10, row_y, "GT heat rate", trim(adjustl(value)), COL_AMBER)
        row_y = row_y + 28
        write(value, '(F6.2," kg/s")') grid%fuel_flow_kg_s
        call draw_value_pair(hdc, side_x + 10, row_y, "Fuel flow", trim(adjustl(value)), COL_MUTED)
        row_y = row_y + 28
        write(value, '(F6.0," K")') grid%exhaust_K
        call draw_value_pair(hdc, side_x + 10, row_y, "Exhaust gas", trim(adjustl(value)), COL_RED)
        row_y = row_y + 44

        call draw_section_title_width(hdc, side_x, row_y, "Thermal economics", side_w)
        call draw_value_stack_compact(hdc, side_x, row_y + 28, side_w, min(132, max(125, y + height - row_y - 44)))
    end subroutine draw_gas_turbine_screen

    subroutine draw_gt_map(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: gx, gy, gw, gh, i, px, py, sx1, sy1, sx2, sy2
        real(dp) :: f, pr
        character(len=64) :: line

        gx = x + 58
        gy = y + 28
        gw = width - 82
        gh = height - 64
        call fill_soft_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
        call stroke_soft_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)
        call fill_box(hdc, gx, gy, gx + gw, gy + gh, COL_BG)
        do i = 1, 4
            call draw_line(hdc, gx + i * gw / 5, gy, gx + i * gw / 5, gy + gh, COL_BG_GRID, 1)
            call draw_line(hdc, gx, gy + i * gh / 5, gx + gw, gy + i * gh / 5, COL_BG_GRID, 1)
        end do
        call stroke_box(hdc, gx, gy, gx + gw, gy + gh, COL_BORDER_SOFT, 1)
        call draw_text(hdc, gx, y + 8, "Corrected mass flow fraction", COL_MUTED)
        call draw_text(hdc, x + 8, gy + gh / 2, "PR", COL_MUTED)

        do i = 0, 39
            f = 0.35_dp + real(i, dp) * 0.65_dp / 39.0_dp
            pr = 7.0_dp + 11.0_dp * f ** 0.72_dp
            px = gx + int((f - 0.35_dp) / 0.65_dp * real(gw, dp))
            py = gy + gh - int((pr - 6.0_dp) / 14.0_dp * real(gh, dp))
            if (i > 0) call draw_line(hdc, sx1, sy1, px, py, COL_CYAN, 2)
            sx1 = px
            sy1 = py
        end do
        do i = 0, 39
            f = 0.35_dp + real(i, dp) * 0.65_dp / 39.0_dp
            pr = 8.5_dp + 13.0_dp * f ** 0.85_dp
            px = gx + int((f - 0.35_dp) / 0.65_dp * real(gw, dp))
            py = gy + gh - int((pr - 6.0_dp) / 14.0_dp * real(gh, dp))
            if (i > 0) call draw_line(hdc, sx2, sy2, px, py, COL_RED, 2)
            sx2 = px
            sy2 = py
        end do
        px = gx + int((clamp_real(grid%flow_frac, 0.35_dp, 1.0_dp) - 0.35_dp) / 0.65_dp * real(gw, dp))
        py = gy + gh - int((clamp_real(grid%PR_op, 6.0_dp, 20.0_dp) - 6.0_dp) / 14.0_dp * real(gh, dp))
        call hmi_fill_pie(hdc, int(px, c_int), int(py, c_int), 8_c_int, 0.0_c_float, 360.0_c_float, COL_LIME)
        call hmi_fill_pie(hdc, int(px, c_int), int(py, c_int), 4_c_int, 0.0_c_float, 360.0_c_float, COL_BG)
        write(line, '("OP  flow ",F5.1,"%  PR ",F5.2)') 100.0_dp * grid%flow_frac, grid%PR_op
        call draw_text(hdc, gx + 12, gy + gh - 28, trim(adjustl(line)), COL_LIME)
        call draw_text(hdc, gx + gw - 170, gy + 14, "surge line", COL_RED)
        call draw_text(hdc, gx + gw - 170, gy + 38, "running line", COL_CYAN)
    end subroutine draw_gt_map

    subroutine draw_combined_cycle_screen(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: ix, iw, top_y, diagram_w, side_x, side_w, row_y
        character(len=96) :: subtitle, value

        ix = x + 18
        iw = width - 36
        top_y = y + 8
        write(subtitle, '("Mode ",A," | GT ",F5.1," MW | ST ",F5.1," MW | eta ",F5.1,"%")') &
            merge("COMBINED", "SIMPLE  ", grid%combined_cycle), grid%gas_power_MW, &
            grid%steam_power_MW, grid%plant_efficiency * 100.0_dp
        call draw_screen_caption(hdc, ix, top_y, iw, SCREEN_FULL_LABEL(SCREEN_CC), trim(subtitle))

        diagram_w = max(560, int(0.62_dp * real(iw, dp)))
        side_x = ix + diagram_w + 18
        side_w = max(250, iw - diagram_w - 18)
        call draw_section_title_width(hdc, ix, top_y + 76, "Heat-balance overview", diagram_w)
        call draw_cc_heat_balance(hdc, ix, top_y + 104, diagram_w, max(300, height - 180))

        call draw_section_title_width(hdc, side_x, top_y + 76, "Bottoming cycle", side_w)
        row_y = top_y + 112
        write(value, '(F6.1," MW")') grid%hrsg_recovered_heat_MW
        call draw_value_pair(hdc, side_x + 10, row_y, "HRSG recovered", trim(adjustl(value)), COL_CYAN)
        row_y = row_y + 28
        write(value, '(F6.1," MW target")') grid%steam_power_target_MW
        call draw_value_pair(hdc, side_x + 10, row_y, "ST target", trim(adjustl(value)), COL_MUTED)
        row_y = row_y + 28
        write(value, '(F6.1," kg/s")') grid%hrsg_steam_flow_kg_s
        call draw_value_pair(hdc, side_x + 10, row_y, "Steam flow", trim(adjustl(value)), COL_INK)
        row_y = row_y + 28
        write(value, '(F6.1," bar")') grid%hrsg_steam_pressure_bar
        call draw_value_pair(hdc, side_x + 10, row_y, "Steam pressure", trim(adjustl(value)), COL_MUTED)
        row_y = row_y + 28
        write(value, '(F6.0," K")') grid%hrsg_steam_T_K
        call draw_value_pair(hdc, side_x + 10, row_y, "Steam temp", trim(adjustl(value)), COL_RED)
        row_y = row_y + 28
        write(value, '(F6.1," K")') grid%hrsg_pinch_K
        call draw_value_pair(hdc, side_x + 10, row_y, "Pinch margin", trim(adjustl(value)), &
            merge(COL_RED, COL_GREEN, grid%alarm_hrsg_pinch))
        row_y = row_y + 28
        write(value, '(F6.1," kPa")') grid%condenser_pressure_kPa
        call draw_value_pair(hdc, side_x + 10, row_y, "Condenser", trim(adjustl(value)), COL_BLUE)
        row_y = row_y + 44
        call draw_section_title_width(hdc, side_x, row_y, "Plant efficiency", side_w)
        call draw_bar(hdc, side_x, row_y + 32, side_w, 28, "Net plant", grid%plant_power_MW, &
            max(grid%plant_capacity_MW, 1.0_dp), COL_GREEN)
        call draw_bar(hdc, side_x, row_y + 72, side_w, 28, "Heat input", grid%heat_input_MW, &
            max(grid%heat_input_MW, 1.0_dp), COL_AMBER)
        if (.not. grid%combined_cycle) call draw_text(hdc, side_x, row_y + 118, &
            "Enable COMBINED from Plant Controls to run the HRSG/ST train.", COL_AMBER)
    end subroutine draw_combined_cycle_screen

    subroutine draw_cc_heat_balance(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: gt_x, hrsg_x, st_x, stack_x, node_w, node_h, mid_y, bar_y
        character(len=64) :: line

        call fill_soft_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
        call stroke_soft_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)
        node_w = min(150, max(112, width / 6))
        node_h = 70
        mid_y = y + height / 2 - node_h / 2
        gt_x = x + 28
        hrsg_x = x + width / 2 - node_w / 2
        st_x = x + width - node_w - 28
        stack_x = hrsg_x + node_w / 2
        call draw_process_node(hdc, gt_x, mid_y, node_w, node_h, "GT1", grid%gas_power_MW, "MW", COL_LIME)
        call draw_process_node(hdc, hrsg_x, mid_y, node_w, node_h, "HRSG", grid%hrsg_recovered_heat_MW, "MWth", COL_CYAN)
        call draw_process_node(hdc, st_x, mid_y, node_w, node_h, "ST1", grid%steam_power_MW, "MW", COL_BLUE)
        call draw_line(hdc, gt_x + node_w, mid_y + node_h / 2, hrsg_x, mid_y + node_h / 2, COL_AMBER, 3)
        call draw_line(hdc, hrsg_x + node_w, mid_y + node_h / 2, st_x, mid_y + node_h / 2, COL_CYAN, 3)
        call draw_line(hdc, stack_x, mid_y, stack_x + width / 8, y + 42, COL_RED, 2)
        write(line, '("Stack ",F5.0," K")') grid%hrsg_stack_T_K
        call draw_text(hdc, stack_x + width / 8 + 8, y + 34, trim(adjustl(line)), COL_RED)
        write(line, '("Pinch ",F4.1," K  Approach ",F4.1," K")') grid%hrsg_pinch_K, grid%hrsg_approach_K
        call draw_text(hdc, hrsg_x - 16, mid_y + node_h + 18, trim(adjustl(line)), &
            merge(COL_RED, COL_MUTED, grid%alarm_hrsg_pinch))
        bar_y = y + height - 86
        call draw_bar(hdc, x + 28, bar_y, width - 56, 24, "GT", grid%gas_power_MW, max(grid%plant_capacity_MW, 1.0_dp), COL_LIME)
        call draw_bar(hdc, x + 28, bar_y + 36, width - 56, 24, "ST", grid%steam_power_MW, max(grid%plant_capacity_MW, 1.0_dp), COL_BLUE)
    end subroutine draw_cc_heat_balance

    subroutine draw_process_node(hdc, x, y, width, height, label, value, unit_text, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        character(len=*), intent(in) :: label, unit_text
        real(dp), intent(in) :: value
        integer(c_int), intent(in) :: color
        character(len=64) :: text

        call fill_box(hdc, x, y, x + width, y + height, COL_PANEL_DEEP)
        call fill_box(hdc, x, y, x + 5, y + height, color)
        call stroke_box(hdc, x, y, x + width, y + height, color, 1)
        call draw_text(hdc, x + 12, y + 10, label, COL_INK)
        write(text, '(F6.1," ",A)') value, trim(unit_text)
        call draw_text(hdc, x + 12, y + 38, trim(adjustl(text)), color)
    end subroutine draw_process_node

    subroutine draw_market_screen(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: ix, iw, top_y, tile_w, gap, panel_y, left_w, right_x, right_w
        character(len=96) :: subtitle, value

        ix = x + 18
        iw = width - 36
        top_y = y + 8
        write(subtitle, '("Profile ",A," | hub ",A," | hour ",F4.1," | source code ",I0)') &
            trim(grid%market_power_zone), trim(grid%market_gas_hub), grid%market_hour, grid%market_source_code
        call draw_screen_caption(hdc, ix, top_y, iw, SCREEN_FULL_LABEL(SCREEN_MARKET), trim(subtitle))

        gap = 12
        tile_w = (iw - 3 * gap) / 4
        write(value, '("$",F6.1,"/MWh")') grid%power_price_usd_mwh
        call draw_metric_tile(hdc, ix, top_y + 76, tile_w, 70, "Power price", trim(adjustl(value)), COL_GREEN)
        write(value, '("$",F5.2,"/GJ")') grid%fuel_price_usd_gj
        call draw_metric_tile(hdc, ix + tile_w + gap, top_y + 76, tile_w, 70, "Fuel hub", trim(adjustl(value)), COL_AMBER)
        write(value, '("$",F5.0,"/t")') grid%carbon_price_usd_t
        call draw_metric_tile(hdc, ix + 2 * (tile_w + gap), top_y + 76, tile_w, 70, "Carbon", trim(adjustl(value)), COL_CYAN)
        write(value, '("$",F5.1,"/MW-h")') grid%fcr_reserve_price_usd_mw_h
        call draw_metric_tile(hdc, ix + 3 * (tile_w + gap), top_y + 76, tile_w, 70, "FCR reserve", trim(adjustl(value)), COL_BLUE)

        panel_y = top_y + 172
        left_w = max(540, int(0.58_dp * real(iw, dp)))
        right_x = ix + left_w + 18
        right_w = max(260, iw - left_w - 18)
        call draw_section_title_width(hdc, ix, panel_y, "Market replay and weather-derived renewable ceiling", left_w)
        call draw_market_profile_panel(hdc, ix, panel_y + 28, left_w, min(210, max(150, height - 250)))
        call draw_section_title_width(hdc, right_x, panel_y, "ROI dispatch value stack", right_w)
        call draw_value_stack_compact(hdc, right_x, panel_y + 28, right_w, min(210, max(150, height - 250)))

        call draw_section_title_width(hdc, ix, y + height - 188, "Cost curve and dispatch merit", iw)
        call draw_cost_curve_panel(hdc, ix, y + height - 160, iw, 140)
    end subroutine draw_market_screen

    subroutine draw_market_profile_panel(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: row_y, bx
        character(len=96) :: line

        call fill_soft_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
        call stroke_soft_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)
        row_y = y + 14
        write(line, '("Location ",A,"  lat ",F5.2," lon ",F6.2)') &
            trim(grid%market_profile_name), grid%market_latitude_deg, grid%market_longitude_deg
        call draw_text(hdc, x + 12, row_y, trim(line), COL_INK)
        row_y = row_y + 28
        write(line, '("Weather ",A,"  wind ",F4.1," m/s  solar ",F5.0," W/m2")') &
            merge("ON ", "OFF", grid%market_weather_enabled), grid%market_wind_speed_m_s, grid%market_solar_W_m2
        call draw_text(hdc, x + 12, row_y, trim(line), COL_MUTED)
        row_y = row_y + 28
        write(line, '("Wind ",F5.1," MW / cap ",F5.1,"  PV ",F5.1," MW / cap ",F5.1)') &
            grid%market_wind_power_MW, grid%market_wind_capacity_MW, &
            grid%market_pv_power_MW, grid%market_pv_capacity_MW
        call draw_text(hdc, x + 12, row_y, trim(line), COL_GREEN)
        row_y = row_y + 28
        write(line, '("Load replay ",A,"  demand range ",F5.1,"-",F5.1," MW  day ",F5.0," s")') &
            merge("ON ", "OFF", grid%market_load_replay_enabled), grid%market_base_demand_MW, &
            grid%market_peak_demand_MW, grid%market_replay_day_s
        call draw_text(hdc, x + 12, row_y, trim(line), COL_CYAN)
        bx = x + 12
        call draw_bar(hdc, bx, y + height - 66, width - 24, 22, "RES available", grid%renewable_MW, RENEWABLE_MAX_MW, COL_GREEN)
        call draw_bar(hdc, bx, y + height - 34, width - 24, 22, "Demand", grid%demand_MW, DEMAND_MAX_MW, COL_RED)
    end subroutine draw_market_profile_panel

    subroutine draw_value_stack_compact(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: row_y
        character(len=96) :: line
        integer(c_int) :: margin_color

        margin_color = merge(COL_GREEN, COL_RED, grid%value_stack_usd_h >= 0.0_dp)
        call fill_soft_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
        call stroke_soft_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)
        row_y = y + 12
        write(line, '("$",F7.0,"/h")') grid%revenue_usd_h
        call draw_value_pair(hdc, x + 12, row_y, "Revenue", trim(adjustl(line)), COL_GREEN)
        row_y = row_y + 25
        write(line, '("$",F7.0,"/h")') grid%fuel_cost_usd_h + grid%co2_cost_usd_h
        call draw_value_pair(hdc, x + 12, row_y, "Fuel + carbon", trim(adjustl(line)), COL_AMBER)
        row_y = row_y + 25
        write(line, '("$",F7.0,"/h")') grid%imbalance_penalty_usd_h
        call draw_value_pair(hdc, x + 12, row_y, "Penalty", trim(adjustl(line)), COL_RED)
        row_y = row_y + 25
        write(line, '("$",F7.0,"/h")') grid%value_stack_usd_h
        call draw_value_pair(hdc, x + 12, row_y, "Net value", trim(adjustl(line)), margin_color)
        if (height > 130) then
            row_y = row_y + 25
            write(line, '("HR ",F7.0," kJ/kWh  CO2 ",F5.2," kg/s")') grid%heat_rate_kJ_kWh, grid%CO2_rate_kg_s
            call draw_text(hdc, x + 12, row_y, trim(adjustl(line)), COL_MUTED)
        end if
    end subroutine draw_value_stack_compact

    subroutine draw_cost_curve_panel(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: gx, gy, gw, gh, i, px, py
        real(dp) :: cap_frac, cost, max_cost
        character(len=64) :: label

        gx = x + 52
        gy = y + 16
        gw = width - 74
        gh = height - 42
        call fill_soft_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
        call stroke_soft_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)
        call fill_box(hdc, gx, gy, gx + gw, gy + gh, COL_BG)
        call stroke_box(hdc, gx, gy, gx + gw, gy + gh, COL_BORDER_SOFT, 1)
        max_cost = max(180.0_dp, grid%fleet_lmp_usd_MWh + 50.0_dp)
        do i = 0, 30
            cap_frac = real(i, dp) / 30.0_dp
            cost = 12.0_dp + 35.0_dp * cap_frac + 130.0_dp * cap_frac ** 3
            px = gx + int(cap_frac * real(gw, dp))
            py = gy + gh - int(clamp_real(cost / max_cost, 0.0_dp, 1.0_dp) * real(gh, dp))
            if (i > 0) call draw_line(hdc, gx + int(real(i - 1, dp) / 30.0_dp * real(gw, dp)), &
                gy + gh - int(clamp_real((12.0_dp + 35.0_dp * real(i - 1, dp) / 30.0_dp + &
                130.0_dp * (real(i - 1, dp) / 30.0_dp) ** 3) / max_cost, 0.0_dp, 1.0_dp) * real(gh, dp)), &
                px, py, COL_AMBER, 2)
        end do
        px = gx + int(clamp_real(grid%demand_MW / DEMAND_MAX_MW, 0.0_dp, 1.0_dp) * real(gw, dp))
        call draw_line(hdc, px, gy, px, gy + gh, COL_RED, 2)
        write(label, '("LMP $",F6.1,"/MWh  net margin $",F7.0,"/h")') &
            merge(grid%fleet_lmp_usd_MWh, grid%power_price_usd_mwh, grid%fleet_mode), grid%margin_usd_h
        call draw_text(hdc, gx + 8, y + 8, trim(adjustl(label)), COL_INK)
        call draw_text(hdc, gx, gy + gh + 8, "low cost", COL_DIM)
        call draw_text(hdc, gx + gw - 72, gy + gh + 8, "scarcity", COL_DIM)
    end subroutine draw_cost_curve_panel

    subroutine draw_trends_screen(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: ix, iw, top_y, right_w, main_w, right_x
        character(len=96) :: subtitle, value

        ix = x + 18
        iw = width - 36
        top_y = y + 8
        write(subtitle, '("Rolling ",I0," sample buffer | loop 250 ms | pens: Hz, demand, turbine dispatch")') HISTORY_N
        call draw_screen_caption(hdc, ix, top_y, iw, SCREEN_FULL_LABEL(SCREEN_TRENDS), trim(subtitle))
        right_w = max(260, iw / 4)
        main_w = iw - right_w - 18
        right_x = ix + main_w + 18

        call draw_section_title_width(hdc, ix, top_y + 76, "Live process trends", main_w)
        call draw_history_traces(hdc, ix, top_y + 104, main_w, max(300, height - 150))
        call draw_section_title_width(hdc, right_x, top_y + 76, "Trend cursor", right_w)
        write(value, '(F7.3," Hz")') grid%frequency_Hz
        call draw_metric_tile(hdc, right_x, top_y + 108, right_w, 70, "Frequency", trim(adjustl(value)), frequency_color())
        write(value, '(F6.1," MW")') grid%demand_MW
        call draw_metric_tile(hdc, right_x, top_y + 190, right_w, 70, "Demand", trim(adjustl(value)), COL_RED)
        write(value, '(F6.1," %")') grid%gas_dispatch_pct
        call draw_metric_tile(hdc, right_x, top_y + 272, right_w, 70, "Turbine dispatch", trim(adjustl(value)), COL_LIME)
        write(value, '(SP,F6.1," MW")') grid%imbalance_MW
        call draw_metric_tile(hdc, right_x, top_y + 354, right_w, 70, "Imbalance", trim(adjustl(value)), &
            merge(COL_GREEN, COL_RED, abs(grid%imbalance_MW) <= 0.5_dp))
        call draw_text(hdc, right_x, y + height - 48, "Live cursor: newest process sample", COL_MUTED)
    end subroutine draw_trends_screen

    subroutine draw_alarms_screen(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: ix, iw, top_y, btn_y, row_y, row_h, log_x, log_w, table_w, i, active_count
        logical :: states(ALARM_COUNT)
        character(len=20) :: labels(ALARM_COUNT)
        integer(c_int) :: colors(ALARM_COUNT), state_color
        character(len=96) :: subtitle, line

        ix = x + 18
        iw = width - 36
        top_y = y + 8
        call current_alarm_states(states)
        call alarm_labels(labels)
        call alarm_colors(colors)
        active_count = count(states)
        write(subtitle, '("ISA-18.2 workflow | active ",I0," | unack ",I0," | shelved ",I0)') &
            active_count, count(alarm_seen .and. .not. alarm_ack), count(alarm_shelved)
        call draw_screen_caption(hdc, ix, top_y, iw, SCREEN_FULL_LABEL(SCREEN_ALARMS), trim(subtitle))

        btn_y = top_y + 76
        call draw_industrial_button(hdc, ix, btn_y, ix + 110, btn_y + 34, "ACK ALL", COL_GREEN, .true.)
        call draw_industrial_button(hdc, ix + 122, btn_y, ix + 250, btn_y + 34, "SHELVE ACTIVE", COL_AMBER, .false.)
        call draw_industrial_button(hdc, ix + 262, btn_y, ix + 390, btn_y + 34, "UNSHELVE", COL_CYAN, .false.)
        call draw_text(hdc, ix + 410, btn_y + 8, "Alarm actions and chronological event state", COL_MUTED)

        table_w = max(650, int(0.62_dp * real(iw, dp)))
        log_x = ix + table_w + 18
        log_w = max(260, iw - table_w - 18)
        call draw_section_title_width(hdc, ix, btn_y + 54, "Alarm list", table_w)
        call fill_soft_box(hdc, ix, btn_y + 82, ix + table_w, y + height - 18, COL_PANEL_ALT)
        call stroke_soft_box(hdc, ix, btn_y + 82, ix + table_w, y + height - 18, COL_BORDER_SOFT, 1)
        call draw_text(hdc, ix + 12, btn_y + 96, "Priority", COL_MUTED)
        call draw_text(hdc, ix + 96, btn_y + 96, "Alarm", COL_MUTED)
        call draw_text(hdc, ix + 306, btn_y + 96, "State", COL_MUTED)
        call draw_text(hdc, ix + 410, btn_y + 96, "Operator action", COL_MUTED)
        row_y = btn_y + 122
        row_h = max(34, (y + height - 158 - row_y) / ALARM_COUNT)
        do i = 1, ALARM_COUNT
            call draw_alarm_row(hdc, ix + 8, row_y, table_w - 16, row_h - 3, i, labels(i), states(i), colors(i))
            row_y = row_y + row_h
        end do

        call draw_section_title_width(hdc, log_x, btn_y + 54, "Chronological log", log_w)
        call fill_soft_box(hdc, log_x, btn_y + 82, log_x + log_w, y + height - 18, COL_PANEL_ALT)
        call stroke_soft_box(hdc, log_x, btn_y + 82, log_x + log_w, y + height - 18, COL_BORDER_SOFT, 1)
        row_y = btn_y + 98
        do i = max(1, alarm_log_count - 12), alarm_log_count
            if (i < 1) cycle
            state_color = alarm_state_color_text(alarm_log_state(i))
            write(line, '(F7.1,"s  ",A,"  ",A)') alarm_log_time(i), trim(alarm_log_state(i)), trim(alarm_log_name(i))
            call draw_text(hdc, log_x + 12, row_y, trim(adjustl(line)), state_color)
            row_y = row_y + 24
        end do
        if (alarm_log_count == 0) call draw_text(hdc, log_x + 12, row_y, "No alarm events this run.", COL_DIM)
    end subroutine draw_alarms_screen

    subroutine draw_alarm_row(hdc, x, y, width, height, alarm_id, label, active, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height, alarm_id
        character(len=*), intent(in) :: label
        logical, intent(in) :: active
        integer(c_int), intent(in) :: color
        character(len=8) :: state_text
        character(len=56) :: action_text
        integer(c_int) :: state_color, body

        state_text = alarm_state_text(alarm_id, active)
        state_color = alarm_state_color_text(state_text)
        body = merge(COL_PANEL, COL_PANEL_DEEP, alarm_seen(alarm_id))
        call fill_box(hdc, x, y, x + width, y + height, body)
        call fill_box(hdc, x, y, x + 5, y + height, merge(color, COL_BORDER_SOFT, alarm_seen(alarm_id)))
        call stroke_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)
        call draw_text(hdc, x + 12, y + 8, alarm_priority_text(alarm_id), merge(color, COL_DIM, alarm_seen(alarm_id)))
        call draw_text(hdc, x + 96, y + 8, label, merge(COL_INK, COL_DIM, alarm_seen(alarm_id)))
        call draw_text(hdc, x + 306, y + 8, trim(state_text), state_color)
        if (active .and. .not. alarm_ack(alarm_id)) then
            action_text = "ACK required"
        else if (active .and. alarm_shelved(alarm_id)) then
            action_text = "Shelved - click row to unshelve"
        else if (active) then
            action_text = "Monitoring active condition"
        else if (alarm_seen(alarm_id)) then
            action_text = "Returned - click row or ACK ALL to clear"
        else
            action_text = "Normal"
        end if
        call draw_text(hdc, x + 410, y + 8, trim(action_text), COL_MUTED)
    end subroutine draw_alarm_row

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

    subroutine draw_kpi_faceplate_popup(hdc, panel_x, panel_y, panel_w, panel_h)
        type(c_ptr), value :: hdc
        integer, intent(in) :: panel_x, panel_y, panel_w, panel_h
        integer :: x, y, w, h, row_y
        character(len=64) :: title, value
        integer(c_int) :: accent

        w = min(520, max(420, panel_w - 120))
        h = min(420, max(330, panel_h - 230))
        x = panel_x + panel_w / 2 - w / 2
        y = panel_y + 110
        if (y + h > panel_y + panel_h - 20) y = panel_y + panel_h - h - 20

        select case (faceplate_id)
        case (FP_FREQ)
            title = "GRID FREQUENCY FACEPLATE"
            accent = frequency_color()
        case (FP_THERMAL)
            title = "THERMAL GENERATION FACEPLATE"
            accent = COL_LIME
        case (FP_IMBALANCE)
            title = "POWER BALANCE FACEPLATE"
            accent = merge(COL_GREEN, COL_RED, abs(grid%imbalance_MW) <= 0.5_dp)
        case (FP_MARGIN)
            title = "ROI / NET MARGIN FACEPLATE"
            accent = merge(COL_GREEN, COL_RED, grid%margin_usd_h >= 0.0_dp)
        case (FP_BESS)
            title = "BESS FACEPLATE"
            accent = COL_BLUE
        case (FP_RENEWABLE)
            title = "RENEWABLE INJECTION FACEPLATE"
            accent = merge(COL_AMBER, COL_GREEN, grid%renewable_curtail_MW > 0.05_dp)
        case default
            return
        end select

        call fill_box(hdc, x - 8, y - 8, x + w + 8, y + h + 8, COL_BG)
        call fill_soft_box(hdc, x, y, x + w, y + h, COL_PANEL)
        call stroke_soft_box(hdc, x, y, x + w, y + h, accent, 2)
        call fill_box(hdc, x, y, x + w, y + 46, COL_PANEL_DEEP)
        call fill_box(hdc, x, y, x + 6, y + h, accent)
        call draw_title_text(hdc, x + 20, y + 12, trim(title), COL_INK)
        call draw_text(hdc, x + w - 120, y + 16, "FACEPLATE", COL_MUTED)
        row_y = y + 66

        select case (faceplate_id)
        case (FP_FREQ)
            write(value, '(F7.3," Hz")') grid%frequency_Hz
            call draw_popup_line(hdc, x, row_y, "Measured frequency", trim(adjustl(value)), accent)
            write(value, '(F7.3," Hz")') grid%nominal_frequency_Hz
            call draw_popup_line(hdc, x, row_y + 28, "Nominal frequency", trim(adjustl(value)), COL_MUTED)
            write(value, '(SP,F7.3," Hz/s")') grid%ROCOF_Hz_s
            call draw_popup_line(hdc, x, row_y + 56, "ROCOF", trim(adjustl(value)), COL_AMBER)
            write(value, '(SP,F6.1," MW")') grid%BESS_primary_MW
            call draw_popup_line(hdc, x, row_y + 84, "BESS primary response", trim(adjustl(value)), COL_BLUE)
            write(value, '("S",I1,"  shed ",F4.0,"%")') grid%UFLS_stage, 100.0_dp * grid%UFLS_shed_fraction
            call draw_popup_line(hdc, x, row_y + 112, "UFLS latch", trim(adjustl(value)), COL_RED)
            call draw_frequency_meter(hdc, x + 26, y + h - 86, w - 52, 28)
        case (FP_THERMAL)
            write(value, '(F6.1," / ",F6.1," MW")') grid%plant_power_MW, grid%plant_capacity_MW
            call draw_popup_line(hdc, x, row_y, "Plant output", trim(adjustl(value)), COL_LIME)
            write(value, '(F6.1," MW  ST ",F6.1," MW")') grid%gas_power_MW, grid%steam_power_MW
            call draw_popup_line(hdc, x, row_y + 28, "GT / ST split", trim(adjustl(value)), COL_CYAN)
            write(value, '(F7.0," kJ/kWh")') grid%heat_rate_kJ_kWh
            call draw_popup_line(hdc, x, row_y + 56, "Plant heat rate", trim(adjustl(value)), COL_AMBER)
            write(value, '(F5.1,"%")') grid%plant_efficiency * 100.0_dp
            call draw_popup_line(hdc, x, row_y + 84, "Plant efficiency", trim(adjustl(value)), COL_GREEN)
            write(value, '(F5.1,"% surge  PR ",F5.2)') grid%surge_margin_pct, grid%PR_op
            call draw_popup_line(hdc, x, row_y + 112, "Map health", trim(adjustl(value)), COL_MUTED)
            call draw_bar(hdc, x + 26, y + h - 70, w - 52, 28, "Plant MW", grid%plant_power_MW, &
                max(grid%plant_capacity_MW, 1.0_dp), COL_LIME)
        case (FP_IMBALANCE)
            write(value, '(F6.1," MW")') grid%demand_MW
            call draw_popup_line(hdc, x, row_y, "Demand", trim(adjustl(value)), COL_RED)
            write(value, '(F6.1," MW")') grid%supply_MW
            call draw_popup_line(hdc, x, row_y + 28, "Supply", trim(adjustl(value)), COL_GREEN)
            write(value, '(SP,F6.1," MW")') grid%imbalance_MW
            call draw_popup_line(hdc, x, row_y + 56, "Net imbalance", trim(adjustl(value)), accent)
            write(value, '(SP,F6.1," MW")') grid%governor_delta_MW
            call draw_popup_line(hdc, x, row_y + 84, "Governor action", trim(adjustl(value)), COL_CYAN)
            write(value, '(F6.1," MW")') merge(grid%fleet_reserve_MW, grid%reserve_MW, grid%fleet_mode)
            call draw_popup_line(hdc, x, row_y + 112, "Reserve", trim(adjustl(value)), COL_BLUE)
            call draw_power_flow(hdc, x + 26, y + h - 118, w - 52, 100)
        case (FP_MARGIN)
            write(value, '("$",F8.0,"/h")') grid%revenue_usd_h
            call draw_popup_line(hdc, x, row_y, "Revenue", trim(adjustl(value)), COL_GREEN)
            write(value, '("$",F8.0,"/h")') grid%fuel_cost_usd_h + grid%co2_cost_usd_h
            call draw_popup_line(hdc, x, row_y + 28, "Fuel + CO2", trim(adjustl(value)), COL_AMBER)
            write(value, '("$",F8.0,"/h")') grid%imbalance_penalty_usd_h
            call draw_popup_line(hdc, x, row_y + 56, "Imbalance penalty", trim(adjustl(value)), COL_RED)
            write(value, '("$",F8.0,"/h")') grid%value_stack_usd_h
            call draw_popup_line(hdc, x, row_y + 84, "Value stack", trim(adjustl(value)), accent)
            write(value, '("P$",F5.0," gas$",F4.1," CO2$",F4.0)') &
                grid%power_price_usd_mwh, grid%fuel_price_usd_gj, grid%carbon_price_usd_t
            call draw_popup_line(hdc, x, row_y + 112, "Market inputs", trim(adjustl(value)), COL_MUTED)
            call draw_roi_panel(hdc, x + 18, y + h - 110, w - 36, 90)
        case (FP_BESS)
            write(value, '(F5.1,"%  ",F5.1," MWh")') grid%battery_soc_pct, grid%battery_energy_MWh
            call draw_popup_line(hdc, x, row_y, "Energy state", trim(adjustl(value)), COL_BLUE)
            write(value, '(SP,F6.1," / ",SP,F6.1," MW")') grid%storage_request_MW, grid%storage_MW
            call draw_popup_line(hdc, x, row_y + 28, "Request / actual", trim(adjustl(value)), COL_CYAN)
            write(value, '("$",F7.0,"/h")') grid%bess_fcr_value_usd_h
            call draw_popup_line(hdc, x, row_y + 56, "FCR reserve value", trim(adjustl(value)), COL_GREEN)
            write(value, '("$",F7.0,"/h")') grid%bess_arbitrage_value_usd_h
            call draw_popup_line(hdc, x, row_y + 84, "Arbitrage value", trim(adjustl(value)), COL_MUTED)
            write(value, '("$",F7.0,"/h")') grid%bess_degradation_cost_usd_h
            call draw_popup_line(hdc, x, row_y + 112, "Degradation cost", trim(adjustl(value)), COL_AMBER)
            call draw_battery_panel(hdc, x + 26, y + h - 76, w - 52, 64)
        case (FP_RENEWABLE)
            write(value, '(F6.1," MW")') grid%renewable_MW
            call draw_popup_line(hdc, x, row_y, "Available ceiling", trim(adjustl(value)), COL_GREEN)
            write(value, '(F6.1," MW")') effective_renewable_MW(grid)
            call draw_popup_line(hdc, x, row_y + 28, "Actual injection", trim(adjustl(value)), accent)
            write(value, '(F6.1," MW")') renewable_headroom_MW(grid)
            call draw_popup_line(hdc, x, row_y + 56, "Held headroom", trim(adjustl(value)), COL_AMBER)
            write(value, '(F5.1," MW / ",F5.1," MW")') grid%market_wind_power_MW, grid%market_pv_power_MW
            call draw_popup_line(hdc, x, row_y + 84, "Wind / PV model", trim(adjustl(value)), COL_CYAN)
            write(value, '(F4.1," m/s  ",F5.0," W/m2")') grid%market_wind_speed_m_s, grid%market_solar_W_m2
            call draw_popup_line(hdc, x, row_y + 112, "Weather input", trim(adjustl(value)), COL_MUTED)
            call draw_bar(hdc, x + 26, y + h - 70, w - 52, 28, "RES actual", effective_renewable_MW(grid), &
                max(RENEWABLE_MAX_MW, 1.0_dp), COL_GREEN)
        end select
    end subroutine draw_kpi_faceplate_popup

    subroutine draw_popup_line(hdc, x, y, label, value_text, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y
        character(len=*), intent(in) :: label, value_text
        integer(c_int), intent(in) :: color

        call draw_text(hdc, x + 26, y, label, COL_MUTED)
        call draw_text(hdc, x + 230, y, value_text, color)
        call draw_line(hdc, x + 26, y + 22, x + 470, y + 22, COL_BORDER_SOFT, 1)
    end subroutine draw_popup_line

    subroutine draw_annunciator_panel(hdc, x, y, w, h)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, w, h
        integer :: tile_w, gap, tx, i
        character(len=20) :: labels(8)
        logical :: states(8)
        integer(c_int) :: colors(8)

        call alarm_labels(labels)
        call current_alarm_states(states)
        call alarm_colors(colors)

        gap = 4
        tile_w = (w - 9 * gap) / 8

        call fill_box(hdc, x, y, x + w, y + h, COL_PANEL_DEEP)
        call stroke_box(hdc, x, y, x + w, y + h, COL_BORDER, 1)

        do i = 1, 8
            tx = x + gap + (i - 1) * (tile_w + gap)
            if (states(i) .and. alarm_shelved(i)) then
                call fill_box(hdc, tx, y + 4, tx + tile_w, y + h - 4, COL_PANEL_DEEP)
                call fill_box(hdc, tx, y + 4, tx + 4, y + h - 4, COL_DIM)
                call stroke_box(hdc, tx, y + 4, tx + tile_w, y + h - 4, COL_DIM, 1)
                call hmi_fill_pie(hdc, int(tx + tile_w - 14, c_int), int(y + h/2, c_int), &
                    5_c_int, 0.0_c_float, 360.0_c_float, COL_DIM)
                call draw_text(hdc, tx + 8, y + (h - 17) / 2, trim(labels(i)), COL_DIM)
            else if (states(i)) then
                ! Active alarm tile: colored with dark body
                call fill_box(hdc, tx, y + 4, tx + tile_w, y + h - 4, COL_PANEL)
                call fill_box(hdc, tx, y + 4, tx + 4, y + h - 4, colors(i))  ! left accent
                call stroke_box(hdc, tx, y + 4, tx + tile_w, y + h - 4, &
                    merge(COL_BORDER, colors(i), alarm_ack(i)), 1)
                ! Lamp circle (filled)
                call hmi_fill_pie(hdc, int(tx + tile_w - 14, c_int), int(y + h/2, c_int), &
                    6_c_int, 0.0_c_float, 360.0_c_float, merge(COL_MUTED, colors(i), alarm_ack(i)))
                call draw_text(hdc, tx + 8, y + (h - 17) / 2, trim(labels(i)), &
                    merge(COL_MUTED, colors(i), alarm_ack(i)))
            else if (alarm_seen(i)) then
                call fill_box(hdc, tx, y + 4, tx + tile_w, y + h - 4, COL_PANEL_DEEP)
                call fill_box(hdc, tx, y + 4, tx + 4, y + h - 4, COL_CYAN)
                call stroke_box(hdc, tx, y + 4, tx + tile_w, y + h - 4, COL_CYAN, 1)
                call hmi_fill_pie(hdc, int(tx + tile_w - 14, c_int), int(y + h/2, c_int), &
                    5_c_int, 0.0_c_float, 360.0_c_float, COL_CYAN)
                call draw_text(hdc, tx + 8, y + (h - 17) / 2, trim(labels(i)), COL_CYAN)
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

    subroutine current_alarm_states(states)
        logical, intent(out) :: states(ALARM_COUNT)

        states(1) = grid%alarm_underfreq
        states(2) = grid%alarm_overfreq
        states(3) = grid%alarm_low_reserve .or. grid%fleet_reserve_binding
        states(4) = grid%alarm_low_soc
        states(5) = grid%alarm_ufls_active
        states(6) = grid%alarm_turbine_max
        states(7) = grid%alarm_surge
        states(8) = grid%alarm_hrsg_pinch
    end subroutine current_alarm_states

    subroutine alarm_labels(labels)
        character(len=20), intent(out) :: labels(ALARM_COUNT)

        labels(1) = "UNDER FREQ"
        labels(2) = "OVER FREQ"
        labels(3) = "LOW RESERVE"
        labels(4) = "LOW BESS SOC"
        labels(5) = "UFLS ACTIVE"
        labels(6) = "TURBINE LIMIT"
        labels(7) = "SURGE MARGIN"
        labels(8) = "HRSG PINCH"
    end subroutine alarm_labels

    subroutine alarm_colors(colors)
        integer(c_int), intent(out) :: colors(ALARM_COUNT)

        colors(1) = COL_RED
        colors(2) = COL_AMBER
        colors(3) = COL_AMBER
        colors(4) = COL_AMBER
        colors(5) = COL_RED
        colors(6) = COL_AMBER
        colors(7) = COL_RED
        colors(8) = COL_AMBER
    end subroutine alarm_colors

    function alarm_state_text(alarm_id, active) result(text)
        integer, intent(in) :: alarm_id
        logical, intent(in) :: active
        character(len=8) :: text

        if (active .and. alarm_shelved(alarm_id)) then
            text = "SHLV"
        else if (active .and. alarm_ack(alarm_id)) then
            text = "ACK"
        else if (active) then
            text = "UNACK"
        else if (alarm_seen(alarm_id)) then
            text = "RTN"
        else
            text = "NORM"
        end if
    end function alarm_state_text

    function alarm_state_color_text(state_text) result(color)
        character(len=*), intent(in) :: state_text
        integer(c_int) :: color

        select case (trim(state_text))
        case ("UNACK")
            color = COL_RED
        case ("ACK")
            color = COL_AMBER
        case ("RTN")
            color = COL_CYAN
        case ("SHLV", "UNSHLV")
            color = COL_DIM
        case default
            color = COL_MUTED
        end select
    end function alarm_state_color_text

    function alarm_priority_text(alarm_id) result(text)
        integer, intent(in) :: alarm_id
        character(len=4) :: text

        select case (alarm_id)
        case (1, 5, 7)
            text = "P1"
        case (2, 3, 4, 6, 8)
            text = "P2"
        case default
            text = "P3"
        end select
    end function alarm_priority_text

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
        if (grid%fleet_mode) then
            cursor = x
            seg_w = scaled_width(grid%fleet_unit_actual_MW(FLEET_GT1), maximum, width)
            call fill_box(hdc, cursor, y, cursor + seg_w, y + height, gas_color)
            cursor = cursor + seg_w
            seg_w = scaled_width(grid%fleet_unit_actual_MW(FLEET_GT2), maximum, width)
            call fill_box(hdc, cursor, y, cursor + seg_w, y + height, COL_AMBER)
            cursor = cursor + seg_w
            seg_w = scaled_width(grid%fleet_unit_actual_MW(FLEET_CC1), maximum, width)
            call fill_box(hdc, cursor, y, cursor + seg_w, y + height, COL_CYAN)
            cursor = cursor + seg_w
            seg_w = scaled_width(effective_renewable_MW(grid), maximum, width)
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
            write(text, '("GT1 ",F4.1,"  GT2 ",F4.1,"  CC1 ",F4.1,"  RES ",F4.1,"  BESS ",SP,F4.1)') &
                grid%fleet_unit_actual_MW(FLEET_GT1), grid%fleet_unit_actual_MW(FLEET_GT2), &
                grid%fleet_unit_actual_MW(FLEET_CC1), effective_renewable_MW(grid), grid%storage_MW
            call draw_text(hdc, x + 10, y + 8, adjustl(text), COL_PANEL_DEEP)
            return
        end if
        cursor = x
        seg_w = scaled_width(grid%gas_power_MW, maximum, width)
        call fill_box(hdc, cursor, y, cursor + seg_w, y + height, gas_color)
        cursor = cursor + seg_w
        if (grid%combined_cycle) then
            seg_w = scaled_width(grid%steam_power_MW, maximum, width)
            call fill_box(hdc, cursor, y, cursor + seg_w, y + height, COL_CYAN)
            cursor = cursor + seg_w
        end if
        seg_w = scaled_width(effective_renewable_MW(grid), maximum, width)
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
        if (grid%combined_cycle .and. grid%renewable_curtail_MW > 0.05_dp) then
            write(text, '("GT ",F4.1,"  ST ",F4.1,"  RES ",F4.1,"/",F4.0,"  Curt ",F4.1,"  BESS ",SP,F4.1)') &
                grid%gas_power_MW, grid%steam_power_MW, effective_renewable_MW(grid), &
                grid%renewable_MW, grid%renewable_curtail_MW, grid%storage_MW
        else if (grid%combined_cycle) then
            write(text, '("GT ",F4.1,"  ST ",F4.1,"  RES ",F4.1,"  BESS ",SP,F4.1," MW")') &
                grid%gas_power_MW, grid%steam_power_MW, effective_renewable_MW(grid), grid%storage_MW
        else if (grid%renewable_curtail_MW > 0.05_dp) then
            write(text, '("GT ",F5.1,"  RES ",F5.1,"/",F4.0,"  Curt ",F4.1,"  BESS ",SP,F5.1)') &
                grid%gas_power_MW, effective_renewable_MW(grid), grid%renewable_MW, &
                grid%renewable_curtail_MW, grid%storage_MW
        else
            write(text, '("GT ",F5.1,"  RES ",F5.1,"  BESS ",SP,F5.1," MW")') &
                grid%gas_power_MW, effective_renewable_MW(grid), grid%storage_MW
        end if
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
        character(len=160) :: line
        real(dp) :: net_usd_mwh, capacity_pct, plant_eta_pct
        integer(c_int) :: margin_color
        integer :: c1, c2, c3, c4, c5, c6, cw  ! six equal columns

        if (height < 1) return
        net_usd_mwh   = grid%value_stack_usd_h / max(grid%demand_MW, 1.0_dp)
        capacity_pct  = 100.0_dp * grid%plant_power_MW / max(grid%plant_capacity_MW, 1.0e-9_dp)
        plant_eta_pct = grid%plant_efficiency * 100.0_dp
        margin_color  = merge(COL_GREEN, COL_RED, grid%value_stack_usd_h >= 0.0_dp)

        call fill_soft_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
        call stroke_soft_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)

        ! Six equal columns for the top two data rows
        cw = (width - 12) / 6
        c1 = x + 12
        c2 = x + 12 + cw
        c3 = x + 12 + 2 * cw
        c4 = x + 12 + 3 * cw
        c5 = x + 12 + 4 * cw
        c6 = x + 12 + 5 * cw
        call draw_line(hdc, c2 - 6, y + 6, c2 - 6, y + height - 6, COL_BORDER_SOFT, 1)
        call draw_line(hdc, c3 - 6, y + 6, c3 - 6, y + height - 6, COL_BORDER_SOFT, 1)
        call draw_line(hdc, c4 - 6, y + 6, c4 - 6, y + height - 6, COL_BORDER_SOFT, 1)
        call draw_line(hdc, c5 - 6, y + 6, c5 - 6, y + height - 6, COL_BORDER_SOFT, 1)
        call draw_line(hdc, c6 - 6, y + 6, c6 - 6, y + height - 6, COL_BORDER_SOFT, 1)

        ! Row A — labels
        call draw_text(hdc, c1, y + 8,  "Revenue",     COL_MUTED)
        call draw_text(hdc, c2, y + 8,  "Fuel+carbon", COL_MUTED)
        call draw_text(hdc, c3, y + 8,  "Value stack", COL_MUTED)
        call draw_text(hdc, c4, y + 8,  "Heat rate",   COL_MUTED)
        call draw_text(hdc, c5, y + 8,  "Plant eta",   COL_MUTED)
        call draw_text(hdc, c6, y + 8,  "CO2 rate",    COL_MUTED)

        ! Row B — values
        write(line, '("$",F7.0,"/h")') grid%revenue_usd_h
        call draw_text(hdc, c1, y + 26, adjustl(line), COL_INK)
        write(line, '("$",F7.0,"/h")') grid%fuel_cost_usd_h + grid%imbalance_penalty_usd_h + grid%co2_cost_usd_h
        call draw_text(hdc, c2, y + 26, adjustl(line), COL_AMBER)
        write(line, '("$",F5.1,"/MWh")') net_usd_mwh
        call draw_text(hdc, c3, y + 26, adjustl(line), margin_color)
        write(line, '(F6.0," kJ/kWh")') grid%heat_rate_kJ_kWh
        call draw_text(hdc, c4, y + 26, adjustl(line), &
            merge(COL_GREEN, COL_AMBER, grid%heat_rate_kJ_kWh < 9500.0_dp))
        write(line, '(F5.1," %")') plant_eta_pct
        call draw_text(hdc, c5, y + 26, adjustl(line), &
            merge(COL_GREEN, COL_AMBER, plant_eta_pct > 38.0_dp))
        write(line, '(F5.2," kg/s")') grid%CO2_rate_kg_s
        call draw_text(hdc, c6, y + 26, adjustl(line), &
            merge(COL_AMBER, COL_MUTED, grid%CO2_rate_kg_s > 10.0_dp))

        ! Separator between rows B and C
        call draw_line(hdc, x + 8, y + 46, x + width - 8, y + 46, COL_BORDER_SOFT, 1)

        ! Row C — four secondary physics metrics, half-width each pair
        if (grid%fleet_mode) then
            write(line, '("GT1 ",F4.1,"/",F4.1," MW  GT2 ",F4.1,"/",F4.1," MW")') &
                grid%fleet_unit_actual_MW(FLEET_GT1), grid%fleet_unit_setpoint_MW(FLEET_GT1), &
                grid%fleet_unit_actual_MW(FLEET_GT2), grid%fleet_unit_setpoint_MW(FLEET_GT2)
            call draw_text(hdc, c1, y + 54, adjustl(line), COL_MUTED)
            write(line, '("CC1 ",F4.1,"/",F4.1," MW  LMP $",F4.0,"/MWh  inertia ",F4.0," MWs")') &
                grid%fleet_unit_actual_MW(FLEET_CC1), grid%fleet_unit_setpoint_MW(FLEET_CC1), &
                grid%fleet_lmp_usd_MWh, grid%fleet_inertia_MWs
            call draw_text(hdc, c4, y + 54, adjustl(line), COL_MUTED)
        else if (grid%combined_cycle) then
            write(line, '("Qin ",F5.1," MWth  m_f ",F4.2," kg/s  load ",F5.1," %")') &
                grid%heat_input_MW, grid%fuel_flow_kg_s, capacity_pct
            call draw_text(hdc, c1, y + 54, adjustl(line), COL_MUTED)
            write(line, '("ST ",F4.1," MW  HRSG ",F5.1," MW  pinch ",F4.1," K  stack ",F4.0," K")') &
                grid%steam_power_MW, grid%hrsg_recovered_heat_MW, grid%hrsg_pinch_K, grid%hrsg_stack_T_K
            call draw_text(hdc, c4, y + 54, adjustl(line), COL_MUTED)
        else
            write(line, '("Qin ",F5.1," MWth  m_f ",F4.2," kg/s  load ",F5.1," %")') &
                grid%heat_input_MW, grid%fuel_flow_kg_s, capacity_pct
            call draw_text(hdc, c1, y + 54, adjustl(line), COL_MUTED)
            write(line, '("P$ ",F4.0,"/MWh  gas ",F4.1,"/GJ  RES hdroom ",F4.1," MW")') &
                grid%power_price_usd_mwh, grid%fuel_price_usd_gj, renewable_headroom_MW(grid)
            call draw_text(hdc, c4, y + 54, adjustl(line), COL_MUTED)
        end if

        ! Row D — dispatch recommendation (full width, cyan)
        if (grid%fleet_mode .and. grid%fleet_reserve_binding) then
            line = "ED: reserve constraint binding — raise supply, restore unit, or lower demand"
        else if (grid%fleet_mode .and. grid%fuel_price_usd_gj > 12.0_dp) then
            line = "ED: high fuel price — RES/BESS priority before thermal MW"
        else if (grid%fleet_mode) then
            line = "ED: cheapest online unit on base load, AGC following ramp limits"
        else if (grid%imbalance_MW < -0.5_dp) then
            line = "AGC: deficit — restore RES headroom, discharge BESS, raise turbine"
        else if (grid%imbalance_MW > 0.5_dp) then
            line = "AGC: surplus — charge BESS, trim curtailed RES, lower turbine"
        else if (grid%fcr_hold .and. grid%bess_fcr_value_usd_h >= grid%bess_arbitrage_value_usd_h) then
            line = "ROI: BESS held mid-SOC for FCR regulation and imbalance value"
        else if (.not. grid%roi_dispatch) then
            line = "Stability mode: frequency correction prioritised over curtailment cost"
        else
            line = "ROI: capturing surplus energy while maintaining BESS frequency reserve"
        end if
        call draw_text(hdc, c1, y + 72, adjustl(line), COL_CYAN)
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
            idx = history_index(grid, i)
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

    subroutine draw_frequency_meter(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: center_x, marker_x
        real(dp) :: frac, f_lo, f_hi
        character(len=20) :: label

        if (height < 1) return
        call fill_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
        center_x = x + width / 2
        call fill_box(hdc, center_x - 34, y, center_x + 34, y + height, int(Z'00406040', c_int))
        call stroke_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)
        call draw_line(hdc, center_x, y, center_x, y + height, COL_GREEN, 1)
        f_lo = grid%nominal_frequency_Hz - 1.5_dp
        f_hi = grid%nominal_frequency_Hz + 1.5_dp
        frac = clamp_real((grid%frequency_Hz - f_lo) / max(f_hi - f_lo, 1.0e-9_dp), 0.0_dp, 1.0_dp)
        marker_x = x + int(frac * real(width, dp))
        call draw_line(hdc, marker_x, y - 4, marker_x, y + height + 4, frequency_color(), 4)
        write(label, '(F4.1," Hz")') f_lo
        call draw_text(hdc, x, y + height + 8, trim(adjustl(label)), COL_DIM)
        write(label, '(F4.1," Hz")') grid%nominal_frequency_Hz
        call draw_text(hdc, center_x - 30, y + height + 8, trim(adjustl(label)), COL_DIM)
        write(label, '(F4.1," Hz")') f_hi
        call draw_text(hdc, x + width - 62, y + height + 8, trim(adjustl(label)), COL_DIM)
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

        if (grid%fleet_mode) then
            call draw_node(hdc, x, row1, node_w, node_h, "Fleet", grid%fleet_total_MW, COL_CYAN)
        else if (grid%combined_cycle) then
            call draw_node(hdc, x, row1, node_w, node_h, "GT+ST", grid%plant_power_MW, COL_CYAN)
        else
            call draw_node(hdc, x, row1, node_w, node_h, "GT", grid%plant_power_MW, COL_LIME)
        end if
        call draw_node(hdc, x, row2, node_w, node_h, "Renew", effective_renewable_MW(grid), &
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
        call draw_line(hdc, x + node_w, row1 + node_h / 2, grid_x, grid_y + 14, &
            merge(COL_CYAN, COL_LIME, grid%combined_cycle .or. grid%fleet_mode), 2)
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
            text = "Grid shortage | restore RES headroom, discharge BESS, raise turbine, or lower demand"
            color = COL_RED
        else
            text = "Grid surplus | trim RES injection, charge BESS, lower turbine, or raise demand"
            color = COL_AMBER
        end if
    end subroutine grid_status

    function frequency_color() result(color)
        integer(c_int) :: color
        real(dp) :: dev

        dev = abs(grid%frequency_Hz - grid%nominal_frequency_Hz)
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

    !> Push every tag bus entry to the OPC UA address space.
    !> Called once per timer tick; tags auto-register on first write.
    subroutine flush_opcua_tags()
        integer :: i
        if (.not. opcua_active()) return
        do i = 1, tag_count()
            call opcua_write(trim(tag_name_at(i)), tag_value_at(i), trim(tag_units_at(i)))
        end do
    end subroutine flush_opcua_tags

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
