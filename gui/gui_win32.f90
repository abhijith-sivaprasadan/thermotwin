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
        c_ptr, c_short, c_sizeof
    use precision_kinds, only: dp
    use engine_core
    use exergy, only: ExergyResult, compute_exergy
    use exergy_uq,         only: ExergyUQ, run_exergy_uq
    use exergy_sobol,      only: SobolResult, run_exergy_sobol, SOBOL_NIN
    use thermo_limits,     only: ThermoLimits, compute_thermo_limits
    use scientific_report, only: write_scientific_report
    use dnn_surrogate,   only: dnn_heat_rate, dnn_commit_probs, dnn_heat_rate_mc
    use scenario_runner, only: Scenario, ScenarioComparison, scenario_load, &
        scenario_gui_tick, scenario_compare
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
    integer(c_int), parameter :: VK_TAB = 9_c_int
    integer(c_int), parameter :: VK_RETURN = 13_c_int
    integer(c_int), parameter :: VK_SPACE = 32_c_int
    integer(c_int), parameter :: VK_F1 = 112_c_int
    integer(c_int), parameter :: VK_F2 = 113_c_int
    integer(c_int), parameter :: VK_F3 = 114_c_int
    integer(c_int), parameter :: VK_F4 = 115_c_int
    integer(c_int), parameter :: VK_F5 = 116_c_int
    integer(c_int), parameter :: VK_F6 = 117_c_int
    integer(c_int), parameter :: VK_F7 = 118_c_int
    integer(c_int), parameter :: VK_F8 = 119_c_int
    integer(c_int), parameter :: VK_F9  = 120_c_int
    integer(c_int), parameter :: VK_F10 = 121_c_int
    integer(c_int), parameter :: VK_F11 = 122_c_int
    integer(c_int), parameter :: VK_F12 = 123_c_int
    integer(c_int), parameter :: VK_F13 = 124_c_int
    integer(c_int), parameter :: VK_F14 = 125_c_int
    integer(c_int), parameter :: VK_F15 = 126_c_int
    integer(c_int), parameter :: VK_QUESTION = 63_c_int   ! '?' key
    integer(c_int), parameter :: VK_1 = 49_c_int   ! module toggle keys
    integer(c_int), parameter :: VK_2 = 50_c_int
    integer(c_int), parameter :: VK_3 = 51_c_int
    integer(c_int), parameter :: VK_4 = 52_c_int
    integer(c_int), parameter :: VK_5 = 53_c_int
    integer(c_int), parameter :: VK_6 = 54_c_int
    integer(c_int), parameter :: VK_UP    = 38_c_int
    integer(c_int), parameter :: VK_DOWN  = 40_c_int
    integer(c_int), parameter :: VK_LEFT  = 37_c_int
    integer(c_int), parameter :: VK_RIGHT = 39_c_int
    integer(c_int), parameter :: VK_CONTROL = 17_c_int
    integer(c_int), parameter :: VK_E   = 69_c_int
    integer(c_int), parameter :: VK_R   = 82_c_int   ! toggle RL mode
    integer(c_int), parameter :: VK_A   = 65_c_int   ! toggle DNN adapting
    integer(c_int), parameter :: VK_T   = 84_c_int   ! Ctrl+T theme toggle
    integer(c_int), parameter :: VK_C   = 67_c_int
    integer(c_int), parameter :: VK_D   = 68_c_int
    integer(c_int), parameter :: VK_H   = 72_c_int
    integer(c_int), parameter :: VK_K   = 75_c_int
    integer(c_int), parameter :: VK_M   = 77_c_int
    integer(c_int), parameter :: VK_N   = 78_c_int
    integer(c_int), parameter :: VK_P   = 80_c_int
    integer(c_int), parameter :: VK_S   = 83_c_int
    integer(c_int), parameter :: WM_SYSKEYDOWN = 260_c_int
    integer(c_int), parameter :: SM_CXSCREEN = 0_c_int
    integer(c_int), parameter :: SM_CYSCREEN = 1_c_int
    integer(c_int), parameter :: SPI_GETWORKAREA = 48_c_int
    integer(c_int), parameter :: TRANSPARENT = 1_c_int
    integer(c_int), parameter :: PS_SOLID = 0_c_int
    integer(c_int), parameter :: SRCCOPY = int(Z'00CC0020', c_int)
    integer(c_int), parameter :: FW_NORMAL = 400_c_int
    integer(c_int), parameter :: FW_SEMIBOLD = 600_c_int
    integer(c_int), parameter :: FW_MONO = 10000_c_int   ! [6.0-P2] add to weight -> Consolas (tabular figures)
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
    integer(c_int), parameter :: ID_EXPORT_CSV   = 215_c_int
    integer(c_int), parameter :: ID_EXPORT_PDF   = 216_c_int
    integer(c_int), parameter :: ID_SHORTCUTS    = 217_c_int
    integer(c_int), parameter :: ID_SCN_B_PREV   = 218_c_int
    integer(c_int), parameter :: ID_SCN_B_NEXT   = 219_c_int
    integer(c_int), parameter :: ID_SCN_COMPARE  = 220_c_int
    integer(c_int), parameter :: ID_NONE = 0_c_int
    integer(c_int), parameter :: FOCUS_COUNT = 23_c_int
    integer(c_int), parameter :: FOCUS_IDS(FOCUS_COUNT) = [integer(c_int) :: &
        ID_DEMAND, ID_RENEWABLE, ID_STORAGE, ID_GAS, ID_AMBIENT, ID_TIT, &
        ID_AUTO, ID_BALANCE, ID_CC_MODE, ID_FCR_HOLD, ID_ROI_MODE, ID_LOAD_STEP, &
        ID_CLOUD_RAMP, ID_TURBINE_TRIP, ID_MARKET_PROFILE, ID_MARKET_REPLAY, &
        ID_RESET, ID_SCN_NEXT, ID_SCN_PREV, ID_SCN_RUN_STOP, ID_EXPORT_CSV, &
        ID_EXPORT_PDF, ID_SHORTCUTS]
    integer(c_int), parameter :: TIMER_ID      = 1_c_int
    integer(c_int), parameter :: TIMER_MS      = 125_c_int    ! [perf] HMI scan/render cadence; sim dt scales to preserve real-time
    integer, parameter :: HISTORY_SAMPLE_MS    = 250          ! [perf] keep 240 samples = 60 s of trends
    character(len=*), parameter :: DEBUG_LOG = "gui_debug.log"
    character(len=*), parameter :: CONFIG_FILE = "thermotwin.ini"

    integer, parameter :: SCREEN_OVERVIEW = 1
    integer, parameter :: SCREEN_GRID = 2
    integer, parameter :: SCREEN_GT = 3
    integer, parameter :: SCREEN_CC = 4
    integer, parameter :: SCREEN_MARKET = 5
    integer, parameter :: SCREEN_TRENDS = 6
    integer, parameter :: SCREEN_ALARMS    = 7
    integer, parameter :: SCREEN_DIAG      = 8
    integer, parameter :: SCREEN_DAYAHEAD  = 9
    integer, parameter :: SCREEN_FLEET_UC  = 10
    integer, parameter :: SCREEN_DNN       = 11
    integer, parameter :: SCREEN_CARBON    = 12
    integer, parameter :: SCREEN_FORECAST  = 13
    integer, parameter :: SCREEN_ADVISORY  = 14
    integer, parameter :: SCREEN_SCENARIO = 15
    integer, parameter :: SCREEN_EXERGY = 16
    integer, parameter :: SCREEN_COUNT = 16
    character(len=14), parameter :: SCREEN_NAV_LABEL(SCREEN_COUNT) = &
        [character(len=14) :: "Ovrvw", "Dispt", "Turbine", "Cycle", "Market", "Trends", &
                              "Alarms", "Diag", "DayAhd", "Fleet", "DNN", &
                              "Carbn", "Frcst", "Advry", "Scen", "Exergy"]
    character(len=28), parameter :: SCREEN_FULL_LABEL(SCREEN_COUNT) = &
        [character(len=28) :: "L1 Overview", "L2 Grid Dispatch", "L2 Gas Turbine", &
                              "L2 Combined Cycle", "L2 Market", "L2 Trends", "L2 Alarms", &
                              "L3 Diagnostics", "L3 Day-Ahead MINLP", &
                              "L3 Fleet UC + Econ Dispatch", "L3 DNN Diagnostics", &
                              "L1 Carbon & Sustainability", "L2 AI Forecast", &
                              "L2 Operator Advisory", "L2 Scenario Builder", &
                              "L3 Exergy Analysis"]
    integer, parameter :: SCREEN_LEVEL(SCREEN_COUNT) = &
        [1, 2, 2, 2, 2, 2, 2, 3, 3, 3, 3, 1, 2, 2, 2, 3]
    character(len=14), parameter :: SCREEN_GROUP_LABEL(3) = &
        [character(len=14) :: "L1 PLANT", "L2 CONTROL", "L3 ANALYTICS"]
    integer, parameter :: NAV_RAIL_TOGGLE = -100
    integer, parameter :: CMD_COUNT = SCREEN_COUNT + 16
    integer, parameter :: SETTINGS_COUNT = 9
    integer, parameter :: DEMO_SCREEN_TICKS = 64

    integer, parameter :: FP_NONE = 0
    integer, parameter :: FP_FREQ = 1
    integer, parameter :: FP_THERMAL = 2
    integer, parameter :: FP_IMBALANCE = 3
    integer, parameter :: FP_MARGIN = 4
    integer, parameter :: FP_BESS = 5
    integer, parameter :: FP_RENEWABLE = 6
    ! [5.0-D1] flagship landing drill-down faceplates
    integer, parameter :: FP_HEALTH  = 7
    integer, parameter :: FP_CO2     = 8
    integer, parameter :: FP_RESERVE = 9
    ! [5.0-D1] subsystem drill-downs (the 6 modules)
    integer, parameter :: FP_SUB_P2X = 10
    integer, parameter :: FP_SUB_CCS = 11
    integer, parameter :: FP_SUB_GFM = 12
    integer, parameter :: FP_SUB_TIE = 13
    integer, parameter :: FP_SUB_MPC = 14
    integer, parameter :: FP_SUB_OU  = 15
    ! [6.0-P3] line-art subsystem icon ids
    integer, parameter :: ICON_P2X = 1
    integer, parameter :: ICON_CCS = 2
    integer, parameter :: ICON_GFM = 3
    integer, parameter :: ICON_TIE = 4
    integer, parameter :: ICON_MPC = 5
    integer, parameter :: ICON_OU  = 6
    integer, parameter :: ALARM_COUNT = 8
    integer, parameter :: ALARM_LOG_N = 36

    integer(c_int), parameter :: CANVAS_W = 1280_c_int
    integer(c_int), parameter :: CANVAS_H = 940_c_int

    ! Runtime palette — toggled between dark (OLED) and light by apply_theme().
    ! COLORREF = 0x00BBGGRR
    logical :: dark_mode = .true.
    ! [6.0-P1] Theming engine: hmi_theme selects the palette; dark_mode is kept as a
    ! derived compatibility flag.  The T key cycles.  Blueprint Dark is the 6.0 default.
    integer, parameter :: THEME_BLUEPRINT  = 0
    integer, parameter :: THEME_CLASSIC_DK = 1
    integer, parameter :: THEME_CLASSIC_LT = 2
    integer, parameter :: THEME_BLUEPRINT_PAPER = 3   ! [6.0-P6] light drafting-sheet variant
    integer, parameter :: THEME_AURORA   = 4   ! [6.0-P10] premium graphite + teal accent
    integer, parameter :: THEME_GLASS    = 5   ! [6.0-P10] holographic indigo + violet/cyan
    integer, parameter :: THEME_HICON    = 6   ! [6.0-P9]  high-contrast control room
    integer, parameter :: THEME_COUNT      = 7
    integer :: hmi_theme = THEME_BLUEPRINT

    integer(c_int) :: COL_BG         = int(Z'00050809', c_int) ! dark navy-black
    integer(c_int) :: COL_BG_GRID    = int(Z'000B0E14', c_int) ! subtle blue grid
    integer(c_int) :: COL_PANEL      = int(Z'000D1014', c_int) ! panel surface
    integer(c_int) :: COL_PANEL_ALT  = int(Z'00161A1F', c_int) ! raised panel
    integer(c_int) :: COL_PANEL_DEEP = int(Z'00040608', c_int) ! deepest layer
    integer(c_int) :: COL_BORDER     = int(Z'00303840', c_int) ! border with blue tint
    integer(c_int) :: COL_BORDER_SOFT= int(Z'001A2028', c_int) ! soft border
    integer(c_int) :: COL_INK        = int(Z'00ECF0F4', c_int) ! primary text (cool white)
    integer(c_int) :: COL_MUTED      = int(Z'00849098', c_int) ! secondary text
    integer(c_int) :: COL_DIM        = int(Z'00424A52', c_int) ! disabled text
    ! Status colours — same in both themes (high-saturation works on any bg)
    integer(c_int) :: COL_GREEN      = int(Z'0064E800', c_int) ! #00E864
    integer(c_int) :: COL_AMBER      = int(Z'000095FF', c_int) ! #FF9500
    integer(c_int) :: COL_RED        = int(Z'00303BFF', c_int) ! #FF3B30
    ! Informational accents
    integer(c_int) :: COL_BLUE       = int(Z'00FF840A', c_int) ! #0A84FF
    integer(c_int) :: COL_CYAN       = int(Z'00E6AD32', c_int) ! #32ADE6
    integer(c_int) :: COL_LIME       = int(Z'0058D130', c_int) ! #30D158
    ! Gauge anatomy
    integer(c_int) :: COL_BEZEL_RING = int(Z'00323232', c_int)
    integer(c_int) :: COL_BEZEL_HI   = int(Z'004A4A4A', c_int)
    integer(c_int) :: COL_GAUGE_FACE = int(Z'00000000', c_int)
    integer(c_int) :: COL_GAUGE_TRACK= int(Z'000F0F0F', c_int)
    ! 3-D button shading
    integer(c_int) :: COL_BTN_HI     = int(Z'00545454', c_int)
    integer(c_int) :: COL_BTN_SH     = int(Z'00000000', c_int)
    integer(c_int) :: COL_BTN_BODY   = int(Z'000D0D0D', c_int)

    ! Revamp 5.0 design tokens.  Keep the HMI on a compact 4/8 px grid so
    ! screens can evolve without reintroducing ad-hoc spacing.
    integer, parameter :: SP_1 = 4
    integer, parameter :: SP_2 = 8
    integer, parameter :: SP_3 = 12
    integer, parameter :: SP_4 = 16
    integer, parameter :: SP_5 = 20
    integer, parameter :: SP_6 = 24
    integer, parameter :: SP_8 = 32
    integer, parameter :: PAD_PANEL_X = SP_4
    integer, parameter :: PAD_PANEL_Y = SP_3
    integer, parameter :: PAD_CARD_X  = SP_3
    integer, parameter :: PAD_CARD_Y  = SP_2
    integer, parameter :: GAP_PANEL   = SP_5
    integer, parameter :: GAP_CARD    = SP_2
    integer, parameter :: KPI_TILE_H  = 68
    integer, parameter :: KPI_TILE_GAP = SP_2
    integer, parameter :: BTN_H_STD   = 36
    integer, parameter :: TABLE_HEAD_H = 34
    integer(c_int), parameter :: RADIUS_SM = 3_c_int
    integer(c_int), parameter :: RADIUS_MD = 5_c_int
    integer(c_int), parameter :: RADIUS_LG = 7_c_int
    integer(c_int), parameter :: FONT_BODY_PX    = 17_c_int
    integer(c_int), parameter :: FONT_TITLE_PX   = 24_c_int
    integer(c_int), parameter :: FONT_SECTION_PX = 17_c_int

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

        function GetKeyState(nVirtKey) bind(C, name="GetKeyState") result(state)
            import :: c_int, c_short
            integer(c_int), value :: nVirtKey
            integer(c_short) :: state
        end function GetKeyState

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

        function hmi_save_window_png(hwnd, lpPath) bind(C, name="hmi_save_window_png") result(ok)
            import :: c_int, c_ptr
            type(c_ptr), value :: hwnd
            type(c_ptr), value :: lpPath
            integer(c_int) :: ok
        end function hmi_save_window_png

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

        subroutine hmi_draw_polyline(hdc, xs, ys, n_pts, color, width) &
                bind(C, name="hmi_draw_polyline")
            import :: c_int, c_ptr
            type(c_ptr), value :: hdc
            type(c_ptr), value :: xs, ys
            integer(c_int), value :: n_pts, color, width
        end subroutine hmi_draw_polyline

        subroutine hmi_begin_frame(hdc) bind(C, name="hmi_begin_frame")
            import :: c_ptr
            type(c_ptr), value :: hdc
        end subroutine hmi_begin_frame

        subroutine hmi_end_frame() bind(C, name="hmi_end_frame")
        end subroutine hmi_end_frame

        subroutine hmi_fill_alpha_rect(hdc, left, top, right, bottom, color, alpha) &
                bind(C, name="hmi_fill_alpha_rect")
            import :: c_int, c_ptr
            type(c_ptr), value :: hdc
            integer(c_int), value :: left, top, right, bottom, color, alpha
        end subroutine hmi_fill_alpha_rect

        subroutine hmi_fill_alpha_round_rect(hdc, left, top, right, bottom, radius, color, alpha) &
                bind(C, name="hmi_fill_alpha_round_rect")
            import :: c_int, c_ptr
            type(c_ptr), value :: hdc
            integer(c_int), value :: left, top, right, bottom, radius, color, alpha
        end subroutine hmi_fill_alpha_round_rect
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
    integer :: layout_nav_left = 366
    integer :: layout_nav_top = 20
    integer :: layout_nav_w = 58
    integer :: layout_nav_bottom = 878
    integer :: layout_main_left = 374
    integer :: layout_main_top = 20
    integer :: layout_main_w = 862
    integer :: layout_main_h = 858
    integer :: hmi_screen = SCREEN_OVERVIEW
    integer :: faceplate_id = FP_NONE
    ! [7.0] cached exergy UQ + Sobol for the Exergy screen — recomputed only when inputs drift
    logical :: exergy_an_valid = .false.
    type(ExergyUQ)    :: exergy_an_uq
    type(SobolResult) :: exergy_an_sob
    real(dp) :: exergy_an_fuel = -1.0_dp
    real(dp) :: exergy_an_tit  = -1.0_dp
    logical :: overview_detail = .false.   ! [5.0-B] F1: .false.=flagship landing, .true.=detailed overview
    integer :: fl_ring(4) = 0              ! [5.0-D1] flagship hit rects (l,t,r,b): health ring
    integer :: fl_card(4,3) = 0            !          3 KPI cards (margin / CO2 / reserve)
    integer :: fl_tile(4,6) = 0            !          6 subsystem tiles (P2X/CCS/GFM/TIE/MPC/OU)
    logical :: alarm_prev(ALARM_COUNT) = .false.
    logical :: alarm_seen(ALARM_COUNT) = .false.
    logical :: alarm_ack(ALARM_COUNT) = .false.
    logical :: alarm_shelved(ALARM_COUNT) = .false.
    integer :: alarm_log_count = 0
    real(dp) :: alarm_log_time(ALARM_LOG_N) = 0.0_dp
    character(len=20) :: alarm_log_name(ALARM_LOG_N) = ""
    character(len=8) :: alarm_log_state(ALARM_LOG_N) = ""
    logical :: native_renderer_ready = .false.
    type(c_ptr) :: back_memdc = c_null_ptr
    type(c_ptr) :: back_bitmap = c_null_ptr
    type(c_ptr) :: back_old_bitmap = c_null_ptr
    integer(c_int) :: back_w = 0_c_int
    integer(c_int) :: back_h = 0_c_int

    ! GUI animation and overlay state
    integer :: anim_tick = 0             ! [6.0-P5] advances each repaint; drives pulses/timing
    integer, parameter :: BOOT_TICKS0 = 12   ! [6.0-P5] self-drawing boot length (x TIMER_MS ~ 1.5 s)
    integer :: boot_ticks = BOOT_TICKS0
    integer :: history_sample_ms_accum = 0
    logical :: help_overlay_active    = .false.
    logical :: shortcuts_popup_active = .false.
    logical :: command_palette_active = .false.
    integer :: command_palette_index = 1
    logical :: settings_overlay_active = .false.
    integer :: settings_focus = 1
    logical :: coach_overlay_active = .false.
    integer :: coach_step = 1
    logical :: demo_mode_active = .false.
    integer :: demo_last_switch_tick = 0
    integer :: demo_screen_index = SCREEN_OVERVIEW
    logical :: nav_rail_collapsed = .true.
    integer :: density_mode = 1      ! 0 compact, 1 comfortable, 2 presentation
    integer :: ui_scale_pct = 100
    logical :: color_blind_safe = .false.
    integer(c_int) :: focus_control_id = ID_DEMAND
    integer :: mouse_hover_x = -1
    integer :: mouse_hover_y = -1
    logical :: mouse_hover_valid = .false.
    character(len=160) :: operator_notice = ""
    integer :: notice_ticks = 0

    ! Scenario selector and live playback state
    integer, parameter :: N_SCENARIOS = 15
    character(len=20), parameter :: SCN_LABEL(N_SCENARIOS) = [character(len=20) :: &
        "Load Step           ", "Cloud Ramp          ", "Turbine Trip        ", &
        "UFLS Cascade        ", "LFSM-O Overfreq     ", "Surge Ramp          ", &
        "Combined Cycle      ", "Fleet Dispatch      ", "Market Replay       ", &
        "P2X Electrolyser    ", "CCS Capture         ", "GFM Inertia         ", &
        "MPC AGC             ", "H2 Cofiring         ", "Manual Frequency    "]
    character(len=64), parameter :: SCN_PATH(N_SCENARIOS) = [character(len=64) :: &
        "cases/scenarios/load_step.scn                                   ", &
        "cases/scenarios/cloud_ramp.scn                                  ", &
        "cases/scenarios/turbine_trip.scn                                ", &
        "cases/scenarios/ufls_cascade.scn                                ", &
        "cases/scenarios/overfrequency_lfsmo.scn                         ", &
        "cases/scenarios/surge_ramp.scn                                  ", &
        "cases/scenarios/combined_cycle.scn                              ", &
        "cases/scenarios/fleet_dispatch.scn                              ", &
        "cases/scenarios/market_replay.scn                               ", &
        "cases/scenarios/p2x_electrolyser.scn                            ", &
        "cases/scenarios/ccs_capture.scn                                 ", &
        "cases/scenarios/gfm_bess_inertia.scn                            ", &
        "cases/scenarios/mpc_agc_regulation.scn                          ", &
        "cases/scenarios/h2_cofiring.scn                                 ", &
        "cases/scenarios/manual_freq_support.scn                         "]
    integer :: scn_selected = 1
    integer :: scn_compare_selected = 2
    logical :: scn_playing = .false.
    type(Scenario) :: scn_active
    type(ScenarioComparison) :: scn_cmp
    character(len=96) :: scn_compare_status = "No comparison run"

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
        screen_w = GetSystemMetrics(SM_CXSCREEN)
        screen_h = GetSystemMetrics(SM_CYSCREEN)
        if (screen_w <= 0_c_int .or. screen_h <= 0_c_int) then
            ok = SystemParametersInfoA(SPI_GETWORKAREA, 0_c_int, c_loc(work_area), 0_c_int)
            if (ok /= 0_c_int) then
                screen_x = int(work_area%left, c_int)
                screen_y = int(work_area%top, c_int)
                screen_w = int(work_area%right - work_area%left, c_int)
                screen_h = int(work_area%bottom - work_area%top, c_int)
            else
                screen_w = CANVAS_W
                screen_h = CANVAS_H
            end if
        end if
        if (screen_w < 1024_c_int) screen_w = CANVAS_W
        if (screen_h < 720_c_int) screen_h = CANVAS_H
        write(logline, '("startup: fullscreen client target ",I0,",",I0," ",I0,"x",I0)') &
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
            call apply_theme()                 ! [6.0-P1] activate the selected palette at launch
            call refresh_model(grid)
            call append_history(grid)
            history_sample_ms_accum = 0
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
            ! HMI scan/render tick: advance engine every frame, sample trend history at
            ! the plant-HMI cadence so a 240-sample buffer remains a real 60 s window.
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
            history_sample_ms_accum = history_sample_ms_accum + int(TIMER_MS)
            if (history_sample_ms_accum >= HISTORY_SAMPLE_MS) then
                call append_history(grid)
                history_sample_ms_accum = mod(history_sample_ms_accum, HISTORY_SAMPLE_MS)
            end if
            anim_tick = anim_tick + 1                 ! [6.0-P5] animation clock
            if (boot_ticks > 0) boot_ticks = boot_ticks - 1
            if (notice_ticks > 0) notice_ticks = notice_ticks - 1
            call update_demo_tour()
            call invalidate_dashboard(hwnd)
            lres = 0_c_intptr_t
            return

        case (WM_LBUTTONDOWN)
            call handle_mouse_down(hwnd, mouse_x(lParam), mouse_y(lParam))
            call invalidate_dashboard(hwnd)
            lres = 0_c_intptr_t
            return

        case (WM_MOUSEMOVE)
            ! [perf] Repaint on mouse-move ONLY while actively dragging a control.
            ! Hover crosshairs refresh on the next WM_TIMER frame, so a
            ! full-canvas redraw for every pixel of cursor movement is pure waste — it
            ! flooded the message loop and made the cursor sluggish.
            mouse_hover_x = mouse_x(lParam)
            mouse_hover_y = mouse_y(lParam)
            mouse_hover_valid = .true.
            if (active_control /= ID_NONE) then
                call update_active_slider(mouse_hover_x)
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

        case (WM_SYSKEYDOWN)
            if (int(wParam, c_int) == VK_F10) then
                call set_hmi_screen(SCREEN_FLEET_UC)
                call invalidate_dashboard(hwnd)
            else if (int(wParam, c_int) == VK_F11) then
                call set_hmi_screen(SCREEN_DNN)
                call invalidate_dashboard(hwnd)
            else if (int(wParam, c_int) == VK_F12) then
                call set_hmi_screen(SCREEN_CARBON)
                call invalidate_dashboard(hwnd)
            else if (int(wParam, c_int) == VK_F13) then
                call set_hmi_screen(SCREEN_FORECAST)
                call invalidate_dashboard(hwnd)
            else if (int(wParam, c_int) == VK_F14) then
                call set_hmi_screen(SCREEN_ADVISORY)
                call invalidate_dashboard(hwnd)
            end if
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
            call destroy_back_buffer()
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
        slider_gap = min(max(ui_slider_gap_min(), available_control / 6), ui_slider_gap_max())
        layout_slider_y(1) = first_slider_y
        layout_slider_y(2) = first_slider_y + slider_gap
        layout_slider_y(3) = first_slider_y + 2 * slider_gap
        layout_slider_y(4) = first_slider_y + 3 * slider_gap
        layout_slider_y(5) = first_slider_y + 4 * slider_gap
        layout_slider_y(6) = first_slider_y + 5 * slider_gap

        layout_button_y = min(layout_control_bottom - ui_control_stack_h(), layout_slider_y(6) + 62)
        layout_footer_y = layout_control_bottom - 50

        layout_nav_left = layout_control_left + layout_control_w + layout_gap
        layout_nav_top = layout_control_top
        layout_nav_bottom = layout_control_bottom
        if (nav_rail_collapsed) then
            layout_nav_w = 58
        else
            layout_nav_w = min(220, max(178, layout_canvas_w / 9))
        end if
        layout_main_left = layout_nav_left + layout_nav_w + max(10, layout_gap / 2)
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

    subroutine destroy_back_buffer()
        integer(c_int) :: ok
        type(c_ptr) :: ignored

        if (c_associated(back_memdc) .and. c_associated(back_old_bitmap)) then
            ignored = SelectObject(back_memdc, back_old_bitmap)
        end if
        if (c_associated(back_bitmap)) ok = DeleteObject(back_bitmap)
        if (c_associated(back_memdc)) ok = DeleteDC(back_memdc)
        back_memdc = c_null_ptr
        back_bitmap = c_null_ptr
        back_old_bitmap = c_null_ptr
        back_w = 0_c_int
        back_h = 0_c_int
    end subroutine destroy_back_buffer

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
        mouse_hover_x = x
        mouse_hover_y = y
        mouse_hover_valid = .true.

        if (command_palette_active) then
            nav_target = hit_test_command_palette(x, y)
            if (nav_target > 0) then
                command_palette_index = nav_target
                call execute_palette_command(command_palette_index)
            else
                command_palette_active = .false.
            end if
            active_control = ID_NONE
            return
        end if

        if (settings_overlay_active) then
            nav_target = hit_test_settings_overlay(x, y)
            if (nav_target > 0) then
                settings_focus = nav_target
                call execute_settings_action(settings_focus)
            else
                settings_overlay_active = .false.
            end if
            active_control = ID_NONE
            return
        end if

        if (coach_overlay_active) then
            coach_step = coach_step + 1
            if (coach_step > 4) coach_overlay_active = .false.
            active_control = ID_NONE
            return
        end if

        nav_target = hit_test_nav(x, y)
        if (nav_target == NAV_RAIL_TOGGLE) then
            nav_rail_collapsed = .not. nav_rail_collapsed
            active_control = ID_NONE
            return
        else if (nav_target /= 0) then
            call set_hmi_screen(nav_target)
            active_control = ID_NONE
            return
        end if
        ! Close shortcuts popup when clicking outside it
        if (shortcuts_popup_active .and. &
            .not. point_in_rect(x, y, &
                layout_main_left + layout_main_w - 398, layout_main_top + 46, &
                layout_main_left + layout_main_w - 6,   layout_main_top + 590)) then
            shortcuts_popup_active = .false.
            active_control = ID_NONE
            return
        end if
        ! [5.0-B/D1] Flagship landing: FLAGSHIP/DETAIL toggle + KPI/subsystem drill-downs.
        if (hmi_screen == SCREEN_OVERVIEW) then
            block
                integer :: tgl_r, tgl_l, tgl_t, tgl_b, fp_fl
                tgl_r = layout_main_left + layout_main_w - PAD_PANEL_X
                tgl_l = tgl_r - 176
                tgl_t = hmi_content_top(layout_main_top) + 12
                tgl_b = tgl_t + 26
                if (point_in_rect(x, y, tgl_l, tgl_t, tgl_r, tgl_b)) then
                    overview_detail = (x >= (tgl_l + tgl_r) / 2)
                    faceplate_id = FP_NONE
                    active_control = ID_NONE
                    return
                end if
                if (.not. overview_detail) then
                    fp_fl = hit_test_flagship(x, y)
                    if (fp_fl /= FP_NONE) then
                        faceplate_id = fp_fl
                        active_control = ID_NONE
                        return
                    end if
                end if
            end block
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
            call ensure_distinct_compare_scenario()
            scn_cmp%ready = .false.
            scn_compare_status = "Scenario A changed"
            scn_playing = .false.
            active_control = ID_NONE
        case (ID_SCN_NEXT)
            scn_selected = mod(scn_selected, N_SCENARIOS) + 1
            call ensure_distinct_compare_scenario()
            scn_cmp%ready = .false.
            scn_compare_status = "Scenario A changed"
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
        case (ID_SCN_B_PREV)
            scn_compare_selected = mod(scn_compare_selected - 2 + N_SCENARIOS, N_SCENARIOS) + 1
            call ensure_distinct_compare_scenario()
            scn_cmp%ready = .false.
            scn_compare_status = "Scenario B changed"
            active_control = ID_NONE
        case (ID_SCN_B_NEXT)
            scn_compare_selected = mod(scn_compare_selected, N_SCENARIOS) + 1
            call ensure_distinct_compare_scenario()
            scn_cmp%ready = .false.
            scn_compare_status = "Scenario B changed"
            active_control = ID_NONE
        case (ID_SCN_COMPARE)
            call run_scenario_comparison()
            active_control = ID_NONE
        case (ID_EXPORT_CSV)
            call export_shift_csv(grid)
            active_control = ID_NONE
        case (ID_EXPORT_PDF)
            call export_shift_csv(grid)
            call launch_pdf_report(grid)
            active_control = ID_NONE
        case (ID_SHORTCUTS)
            shortcuts_popup_active = .not. shortcuts_popup_active
            active_control = ID_NONE
        case (ID_DEMAND, ID_RENEWABLE, ID_STORAGE, ID_GAS, ID_AMBIENT, ID_TIT)
            previous = SetCapture(hwnd)
            call update_active_slider(x)
        end select
        call refresh_model(grid)
    end subroutine handle_mouse_down

    subroutine ensure_distinct_compare_scenario()
        if (N_SCENARIOS <= 1) return
        if (scn_compare_selected == scn_selected) then
            scn_compare_selected = mod(scn_compare_selected, N_SCENARIOS) + 1
        end if
    end subroutine ensure_distinct_compare_scenario

    subroutine run_scenario_comparison()
        type(Scenario) :: sc_a, sc_b
        logical :: ok_a, ok_b

        call ensure_distinct_compare_scenario()
        call scenario_load(trim(adjustl(SCN_PATH(scn_selected))), sc_a, ok_a)
        call scenario_load(trim(adjustl(SCN_PATH(scn_compare_selected))), sc_b, ok_b)
        if (ok_a .and. ok_b) then
            call scenario_compare(sc_a, sc_b, scn_cmp)
            write(scn_compare_status, '("Compared A:",I0," vs B:",I0)') &
                scn_selected, scn_compare_selected
        else
            scn_cmp%ready = .false.
            scn_compare_status = "Comparison failed: scenario load error"
        end if
    end subroutine run_scenario_comparison

    subroutine handle_key(hwnd, key)
        type(c_ptr), value :: hwnd
        integer(c_intptr_t), intent(in) :: key
        integer(c_int) :: ok
        integer(c_int) :: kval

        kval = int(key, c_int)
        if (command_palette_active) then
            call handle_command_palette_key(kval)
            return
        end if
        if (settings_overlay_active) then
            call handle_settings_key(kval)
            return
        end if
        if (coach_overlay_active .and. (kval == VK_RETURN .or. kval == VK_SPACE .or. kval == VK_RIGHT)) then
            coach_step = coach_step + 1
            if (coach_step > 4) coach_overlay_active = .false.
            return
        end if
        if (ctrl_down()) then
            select case (kval)
            case (VK_K)
                command_palette_active = .true.
                shortcuts_popup_active = .false.
                settings_overlay_active = .false.
                call set_notice("Command palette ready: Enter runs, Up/Down selects.")
                return
            case (VK_N)
                nav_rail_collapsed = .not. nav_rail_collapsed
                call set_bool_notice("Navigation rail collapsed.", "Navigation rail expanded.", nav_rail_collapsed)
                return
            case (VK_D)
                call cycle_density()
                return
            case (VK_S)
                settings_overlay_active = .true.
                settings_focus = 1
                shortcuts_popup_active = .false.
                return
            case (VK_M)
                demo_mode_active = .not. demo_mode_active
                demo_last_switch_tick = anim_tick
                demo_screen_index = hmi_screen
                call set_bool_notice("Demo tour started.", "Demo tour stopped.", demo_mode_active)
                return
            case (VK_P)
                call export_screen_png()
                return
            end select
        end if

        if (kval == VK_TAB) then
            call cycle_focus(1)
            return
        else if (kval == VK_RETURN .or. kval == VK_SPACE) then
            call activate_focused_control()
            call refresh_model(grid)
            return
        else if (kval == VK_LEFT) then
            if (adjust_focused_slider(-1)) call refresh_model(grid)
            return
        else if (kval == VK_RIGHT) then
            if (adjust_focused_slider(1)) call refresh_model(grid)
            return
        end if

        select case (kval)
        case (VK_F1)
            if (hmi_screen == SCREEN_OVERVIEW) then
                overview_detail = .not. overview_detail   ! [5.0-B] toggle flagship <-> detail
                faceplate_id = FP_NONE
            else
                call set_hmi_screen(SCREEN_OVERVIEW)
            end if
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
        case (VK_F8)
            call set_hmi_screen(SCREEN_DIAG)
        case (VK_F9)
            call set_hmi_screen(SCREEN_DAYAHEAD)
        case (VK_F10)
            call set_hmi_screen(SCREEN_FLEET_UC)
        case (VK_F11)
            call set_hmi_screen(SCREEN_DNN)
        case (VK_F12)
            call set_hmi_screen(SCREEN_CARBON)
        case (VK_F13)
            call set_hmi_screen(SCREEN_FORECAST)
        case (VK_F14)
            call set_hmi_screen(SCREEN_ADVISORY)
        case (VK_F15)
            call set_hmi_screen(SCREEN_SCENARIO)
        case (VK_QUESTION)
            shortcuts_popup_active = .not. shortcuts_popup_active
            help_overlay_active = .false.
        case (VK_H)
            coach_overlay_active = .not. coach_overlay_active
            coach_step = 1
            shortcuts_popup_active = .false.
        case (VK_S)
            settings_overlay_active = .true.
            settings_focus = 1
            shortcuts_popup_active = .false.
        ! Module toggles — global, work from any screen
        case (VK_1)
            grid%p2x_active = .not. grid%p2x_active
        case (VK_2)
            grid%ccs_active = .not. grid%ccs_active
        case (VK_3)
            grid%gfm_mode = .not. grid%gfm_mode
        case (VK_4)
            grid%tie_active = .not. grid%tie_active
        case (VK_5)
            grid%mpc_active = .not. grid%mpc_active
        case (VK_6)
            grid%ou_active = .not. grid%ou_active
        case (VK_E)
            call export_shift_csv(grid)
        case (VK_R)
            grid%rl_mode = .not. grid%rl_mode
        case (VK_A)
            grid%dnn_adapting = .not. grid%dnn_adapting
        case (VK_T)
            hmi_theme = modulo(hmi_theme + 1, THEME_COUNT)   ! [6.0] Blueprint -> Classic dark -> Classic light
            call apply_theme()
        case (VK_C)
            color_blind_safe = .not. color_blind_safe
            call apply_theme()
            call set_bool_notice("Colour-blind-safe palette on.", "Colour-blind-safe palette off.", color_blind_safe)
        case (VK_D)
            call cycle_density()
        case (VK_M)
            demo_mode_active = .not. demo_mode_active
            demo_last_switch_tick = anim_tick
            demo_screen_index = hmi_screen
            call set_bool_notice("Demo tour started.", "Demo tour stopped.", demo_mode_active)
        case (VK_N)
            nav_rail_collapsed = .not. nav_rail_collapsed
        case (VK_P)
            call export_screen_png()
        case (VK_UP)
            ! Increase H2 blend by 1% on Carbon screen, 5% with Shift (not detected here)
            if (hmi_screen == SCREEN_CARBON) then
                grid%h2_fraction_pct = min(30.0_dp, grid%h2_fraction_pct + 1.0_dp)
                call refresh_model(grid)
            end if
        case (VK_DOWN)
            if (hmi_screen == SCREEN_CARBON) then
                grid%h2_fraction_pct = max(0.0_dp, grid%h2_fraction_pct - 1.0_dp)
                call refresh_model(grid)
            end if
        case (VK_ESCAPE)
            if (command_palette_active) then
                command_palette_active = .false.
            else if (settings_overlay_active) then
                settings_overlay_active = .false.
            else if (coach_overlay_active) then
                coach_overlay_active = .false.
            else if (demo_mode_active) then
                demo_mode_active = .false.
                call set_notice("Demo tour stopped.")
            else if (shortcuts_popup_active) then
                shortcuts_popup_active = .false.
            else if (help_overlay_active) then
                help_overlay_active = .false.
            else if (faceplate_id /= FP_NONE) then
                faceplate_id = FP_NONE
            else if (hmi_screen /= SCREEN_OVERVIEW) then
                call set_hmi_screen(SCREEN_OVERVIEW)
            else
                ok = DestroyWindow(hwnd)
            end if
        end select
    end subroutine handle_key

    subroutine apply_theme()
        ! [6.0-P9/P10] default signal + accent palette; specific themes override below
        COL_GREEN = int(Z'0064E800', c_int);  COL_AMBER = int(Z'000095FF', c_int)
        COL_RED   = int(Z'00303BFF', c_int);  COL_BLUE  = int(Z'00FF840A', c_int)
        COL_CYAN  = int(Z'00E6AD32', c_int);  COL_LIME  = int(Z'0058D130', c_int)
        select case (hmi_theme)
        case (THEME_BLUEPRINT)
            ! [6.0] Blueprint — deep-black CAD ground with a cool drafting grid + cyan accents
            COL_BG          = int(Z'000A0908', c_int)
            COL_BG_GRID     = int(Z'001E1914', c_int)
            COL_PANEL       = int(Z'00120F0C', c_int)
            COL_PANEL_ALT   = int(Z'00201B16', c_int)
            COL_PANEL_DEEP  = int(Z'00070605', c_int)
            COL_BORDER      = int(Z'004C4236', c_int)
            COL_BORDER_SOFT = int(Z'00302A22', c_int)
            COL_INK         = int(Z'00F8F2EC', c_int)
            COL_MUTED       = int(Z'009C948A', c_int)
            COL_DIM         = int(Z'005B534A', c_int)
            COL_BEZEL_RING  = int(Z'003A322A', c_int)
            COL_BEZEL_HI    = int(Z'0052483E', c_int)
            COL_GAUGE_FACE  = int(Z'000A0908', c_int)
            COL_GAUGE_TRACK = int(Z'001A1612', c_int)
            COL_BTN_HI      = int(Z'00564C42', c_int)
            COL_BTN_SH      = int(Z'00040302', c_int)
            COL_BTN_BODY    = int(Z'00120F0C', c_int)
            dark_mode = .true.
        case (THEME_CLASSIC_LT)
            ! High-contrast daylight palette
            COL_BG          = int(Z'00F5F5F5', c_int) ! near-white
            COL_BG_GRID     = int(Z'00E8E8E8', c_int)
            COL_PANEL       = int(Z'00EFEFEF', c_int)
            COL_PANEL_ALT   = int(Z'00E0E0E0', c_int)
            COL_PANEL_DEEP  = int(Z'00D8D8D8', c_int)
            COL_BORDER      = int(Z'00AAAAAA', c_int)
            COL_BORDER_SOFT = int(Z'00C8C8C8', c_int)
            COL_INK         = int(Z'00101010', c_int) ! near-black text
            COL_MUTED       = int(Z'00505050', c_int)
            COL_DIM         = int(Z'00909090', c_int)
            COL_BEZEL_RING  = int(Z'00B0B0B0', c_int)
            COL_BEZEL_HI    = int(Z'00E0E0E0', c_int)
            COL_GAUGE_FACE  = int(Z'00F0F0F0', c_int)
            COL_GAUGE_TRACK = int(Z'00D8D8D8', c_int)
            COL_BTN_HI      = int(Z'00F8F8F8', c_int)
            COL_BTN_SH      = int(Z'00B0B0B0', c_int)
            COL_BTN_BODY    = int(Z'00E8E8E8', c_int)
            dark_mode = .false.
        case (THEME_BLUEPRINT_PAPER)
            ! [6.0-P6] Blueprint Paper — light drafting sheet (parchment + navy ink + blue grid)
            COL_BG          = int(Z'00DCE8EC', c_int)
            COL_BG_GRID     = int(Z'00E0D8D2', c_int)
            COL_PANEL       = int(Z'00EAF2F4', c_int)
            COL_PANEL_ALT   = int(Z'00D8E4E8', c_int)
            COL_PANEL_DEEP  = int(Z'00CCD8DC', c_int)
            COL_BORDER      = int(Z'00906A4A', c_int)
            COL_BORDER_SOFT = int(Z'00C8BEB8', c_int)
            COL_INK         = int(Z'003A2416', c_int)
            COL_MUTED       = int(Z'0078665A', c_int)
            COL_DIM         = int(Z'00A49890', c_int)
            COL_BEZEL_RING  = int(Z'00C0B6B0', c_int)
            COL_BEZEL_HI    = int(Z'00E8E2E0', c_int)
            COL_GAUGE_FACE  = int(Z'00DCE8EC', c_int)
            COL_GAUGE_TRACK = int(Z'00C8D4D8', c_int)
            COL_BTN_HI      = int(Z'00F0F8FA', c_int)
            COL_BTN_SH      = int(Z'00A4AEB0', c_int)
            COL_BTN_BODY    = int(Z'00D8E4E8', c_int)
            dark_mode = .false.
        case (THEME_AURORA)
            ! [6.0-P10] Aurora console — graphite depth + teal signal accent
            COL_BG          = int(Z'00140F0B', c_int)
            COL_BG_GRID     = int(Z'00241C16', c_int)
            COL_PANEL       = int(Z'00211812', c_int)
            COL_PANEL_ALT   = int(Z'0030241B', c_int)
            COL_PANEL_DEEP  = int(Z'00130E0A', c_int)
            COL_BORDER      = int(Z'00473A2E', c_int)
            COL_BORDER_SOFT = int(Z'0030261E', c_int)
            COL_INK         = int(Z'00F4F0EA', c_int)
            COL_MUTED       = int(Z'00A3978A', c_int)
            COL_DIM         = int(Z'005F554A', c_int)
            COL_BEZEL_RING  = int(Z'00473A2E', c_int)
            COL_BEZEL_HI    = int(Z'00604E3A', c_int)
            COL_GAUGE_FACE  = int(Z'00140F0B', c_int)
            COL_GAUGE_TRACK = int(Z'00241C16', c_int)
            COL_BTN_HI      = int(Z'005A4A38', c_int)
            COL_BTN_SH      = int(Z'00080605', c_int)
            COL_BTN_BODY    = int(Z'00211812', c_int)
            COL_CYAN        = int(Z'00BFD42D', c_int)   ! teal
            COL_BLUE        = int(Z'00D6C536', c_int)
            dark_mode = .true.
        case (THEME_GLASS)
            ! [6.0-P10] Holographic glass — deep indigo + violet/cyan
            COL_BG          = int(Z'0020100B', c_int)
            COL_BG_GRID     = int(Z'0040231A', c_int)
            COL_PANEL       = int(Z'00331A14', c_int)
            COL_PANEL_ALT   = int(Z'004D2A1F', c_int)
            COL_PANEL_DEEP  = int(Z'00180C08', c_int)
            COL_BORDER      = int(Z'007A4A3A', c_int)
            COL_BORDER_SOFT = int(Z'00502C23', c_int)
            COL_INK         = int(Z'00FFF0EA', c_int)
            COL_MUTED       = int(Z'00CCA69A', c_int)
            COL_DIM         = int(Z'00855C52', c_int)
            COL_BEZEL_RING  = int(Z'007A4A3A', c_int)
            COL_BEZEL_HI    = int(Z'009A6A5A', c_int)
            COL_GAUGE_FACE  = int(Z'0020100B', c_int)
            COL_GAUGE_TRACK = int(Z'0040231A', c_int)
            COL_BTN_HI      = int(Z'00604530', c_int)
            COL_BTN_SH      = int(Z'00100C08', c_int)
            COL_BTN_BODY    = int(Z'00331A14', c_int)
            COL_CYAN        = int(Z'00EED322', c_int)   ! cyan
            COL_BLUE        = int(Z'00FF5C7C', c_int)   ! violet
            dark_mode = .true.
        case (THEME_HICON)
            ! [6.0-P9] High-contrast control room — pure black + white
            COL_BG          = int(Z'00000000', c_int)
            COL_BG_GRID     = int(Z'001A1A1A', c_int)
            COL_PANEL       = int(Z'000A0A0A', c_int)
            COL_PANEL_ALT   = int(Z'001E1E1E', c_int)
            COL_PANEL_DEEP  = int(Z'00000000', c_int)
            COL_BORDER      = int(Z'00D0D0D0', c_int)
            COL_BORDER_SOFT = int(Z'00808080', c_int)
            COL_INK         = int(Z'00FFFFFF', c_int)
            COL_MUTED       = int(Z'00C8C8C8', c_int)
            COL_DIM         = int(Z'00909090', c_int)
            COL_BEZEL_RING  = int(Z'00A0A0A0', c_int)
            COL_BEZEL_HI    = int(Z'00FFFFFF', c_int)
            COL_GAUGE_FACE  = int(Z'00000000', c_int)
            COL_GAUGE_TRACK = int(Z'00202020', c_int)
            COL_BTN_HI      = int(Z'00FFFFFF', c_int)
            COL_BTN_SH      = int(Z'00000000', c_int)
            COL_BTN_BODY    = int(Z'00141414', c_int)
            dark_mode = .true.
        case default   ! THEME_CLASSIC_DK — original OLED dark
            COL_BG          = int(Z'00050809', c_int)
            COL_BG_GRID     = int(Z'000B0E14', c_int)
            COL_PANEL       = int(Z'000D1014', c_int)
            COL_PANEL_ALT   = int(Z'00161A1F', c_int)
            COL_PANEL_DEEP  = int(Z'00040608', c_int)
            COL_BORDER      = int(Z'00303840', c_int)
            COL_BORDER_SOFT = int(Z'001A2028', c_int)
            COL_INK         = int(Z'00ECF0F4', c_int)
            COL_MUTED       = int(Z'00849098', c_int)
            COL_DIM         = int(Z'00424A52', c_int)
            COL_BEZEL_RING  = int(Z'00283038', c_int)
            COL_BEZEL_HI    = int(Z'00404850', c_int)
            COL_GAUGE_FACE  = int(Z'00050809', c_int)
            COL_GAUGE_TRACK = int(Z'000E1218', c_int)
            COL_BTN_HI      = int(Z'00505860', c_int)
            COL_BTN_SH      = int(Z'00020304', c_int)
            COL_BTN_BODY    = int(Z'000C1018', c_int)
            dark_mode = .true.
        end select
        if (color_blind_safe) then
            ! Okabe-Ito inspired control palette, encoded as COLORREF.
            COL_GREEN = int(Z'00739E00', c_int)  ! #009E73
            COL_AMBER = int(Z'00009FE6', c_int)  ! #E69F00
            COL_RED   = int(Z'00005ED5', c_int)  ! #D55E00
            COL_BLUE  = int(Z'00B27200', c_int)  ! #0072B2
            COL_CYAN  = int(Z'00CC79F0', c_int)  ! #F079CC
            COL_LIME  = int(Z'00E69F00', c_int)  ! #009FE6
        end if
    end subroutine apply_theme

    !> [6.0] Short display name for the active theme (shown on the shortcuts card).
    function theme_name() result(s)
        character(len=16) :: s
        select case (hmi_theme)
        case (THEME_BLUEPRINT);       s = "Blueprint"
        case (THEME_CLASSIC_DK);      s = "Classic dark"
        case (THEME_CLASSIC_LT);      s = "Classic light"
        case (THEME_BLUEPRINT_PAPER); s = "Bluepr. paper"
        case (THEME_AURORA);          s = "Aurora"
        case (THEME_GLASS);           s = "Glass"
        case (THEME_HICON);           s = "High contrast"
        case default;                 s = "Theme"
        end select
    end function theme_name

    function density_name() result(s)
        character(len=14) :: s
        select case (density_mode)
        case (0); s = "Compact"
        case (2); s = "Presentation"
        case default; s = "Comfortable"
        end select
    end function density_name

    integer function ui_font_body_px() result(px)
        px = max(13, min(24, nint(real(FONT_BODY_PX) * real(ui_scale_pct) / 100.0)))
    end function ui_font_body_px

    integer function ui_font_title_px() result(px)
        px = max(18, min(34, nint(real(FONT_TITLE_PX) * real(ui_scale_pct) / 100.0)))
    end function ui_font_title_px

    integer function ui_font_section_px() result(px)
        px = max(13, min(24, nint(real(FONT_SECTION_PX) * real(ui_scale_pct) / 100.0)))
    end function ui_font_section_px

    integer function ui_button_h() result(v)
        select case (density_mode)
        case (0); v = 31
        case (2); v = 42
        case default; v = BTN_H_STD
        end select
    end function ui_button_h

    integer function ui_button_step() result(v)
        select case (density_mode)
        case (0); v = 39
        case (2); v = 54
        case default; v = 46
        end select
    end function ui_button_step

    integer function ui_slider_gap_min() result(v)
        select case (density_mode)
        case (0); v = 66
        case (2); v = 92
        case default; v = 78
        end select
    end function ui_slider_gap_min

    integer function ui_slider_gap_max() result(v)
        select case (density_mode)
        case (0); v = 108
        case (2); v = 146
        case default; v = 130
        end select
    end function ui_slider_gap_max

    integer function ui_control_stack_h() result(v)
        select case (density_mode)
        case (0); v = 520
        case (2); v = 654
        case default; v = 586
        end select
    end function ui_control_stack_h

    subroutine cycle_density()
        density_mode = modulo(density_mode + 1, 3)
        call set_notice("Density: "//trim(density_name()))
    end subroutine cycle_density

    subroutine set_notice(text)
        character(len=*), intent(in) :: text
        operator_notice = text
        notice_ticks = 120
    end subroutine set_notice

    subroutine set_bool_notice(on_text, off_text, enabled)
        character(len=*), intent(in) :: on_text, off_text
        logical, intent(in) :: enabled
        if (enabled) then
            call set_notice(on_text)
        else
            call set_notice(off_text)
        end if
    end subroutine set_bool_notice

    subroutine set_hmi_screen(screen_id)
        integer, intent(in) :: screen_id
        integer :: new_screen

        new_screen = min(max(screen_id, SCREEN_OVERVIEW), SCREEN_COUNT)
        hmi_screen = new_screen
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
                hmi_screen = min(max(ival, SCREEN_OVERVIEW), SCREEN_COUNT)
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
            case ("hmi_theme")
                hmi_theme = min(max(ival, 0), THEME_COUNT - 1)
            case ("density_mode")
                density_mode = min(max(ival, 0), 2)
            case ("ui_scale_pct")
                ui_scale_pct = min(max(ival, 85), 125)
            case ("color_blind_safe")
                color_blind_safe = ival /= 0
            case ("nav_rail_collapsed")
                nav_rail_collapsed = ival /= 0
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
        write(unit, '("hmi_theme ",I0)') hmi_theme
        write(unit, '("density_mode ",I0)') density_mode
        write(unit, '("ui_scale_pct ",I0)') ui_scale_pct
        write(unit, '("color_blind_safe ",I0)') merge(1, 0, color_blind_safe)
        write(unit, '("nav_rail_collapsed ",I0)') merge(1, 0, nav_rail_collapsed)
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
        integer :: x0, y0, w, h, content_y, content_h, top_y, btn_y, bx, row_y, row_h, i
        integer :: ix, iw, table_w
        logical :: states(ALARM_COUNT)

        handled = .false.
        if (hmi_screen /= SCREEN_ALARMS) return
        x0 = layout_main_left
        y0 = layout_main_top
        w = layout_main_w
        h = layout_main_h
        content_y = hmi_content_top(y0)
        content_h = max(260, y0 + h - content_y - 12)
        top_y = content_y + 8
        btn_y = top_y + 76
        ix = x0 + 18
        iw = w - 36
        table_w = max(650, int(0.62_dp * real(iw, dp)))
        bx = ix
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
        row_y = btn_y + 122
        row_h = max(34, (content_y + content_h - 158 - row_y) / ALARM_COUNT)
        do i = 1, ALARM_COUNT
            if (point_in_rect(x, y, ix + 8, row_y, ix + table_w - 8, row_y + row_h - 3)) then
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
            row_y = row_y + row_h
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
            grid%auto_balance = .false.
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

    logical function ctrl_down() result(down)
        down = GetKeyState(VK_CONTROL) < 0_c_short
    end function ctrl_down

    subroutine handle_command_palette_key(kval)
        integer(c_int), intent(in) :: kval
        select case (kval)
        case (VK_ESCAPE)
            command_palette_active = .false.
        case (VK_UP)
            command_palette_index = max(1, command_palette_index - 1)
        case (VK_DOWN)
            command_palette_index = min(CMD_COUNT, command_palette_index + 1)
        case (VK_RETURN, VK_SPACE)
            call execute_palette_command(command_palette_index)
        end select
    end subroutine handle_command_palette_key

    subroutine handle_settings_key(kval)
        integer(c_int), intent(in) :: kval
        select case (kval)
        case (VK_ESCAPE)
            settings_overlay_active = .false.
        case (VK_UP)
            settings_focus = max(1, settings_focus - 1)
        case (VK_DOWN)
            settings_focus = min(SETTINGS_COUNT, settings_focus + 1)
        case (VK_LEFT)
            if (settings_focus == 3) then
                ui_scale_pct = max(85, ui_scale_pct - 5)
                call set_notice("UI scale: "//trim(int_text(ui_scale_pct))//"%")
            else if (settings_focus == 1) then
                hmi_theme = modulo(hmi_theme - 1 + THEME_COUNT, THEME_COUNT)
                call apply_theme()
            end if
        case (VK_RIGHT)
            if (settings_focus == 3) then
                ui_scale_pct = min(125, ui_scale_pct + 5)
                call set_notice("UI scale: "//trim(int_text(ui_scale_pct))//"%")
            else if (settings_focus == 1) then
                hmi_theme = modulo(hmi_theme + 1, THEME_COUNT)
                call apply_theme()
            end if
        case (VK_RETURN, VK_SPACE)
            call execute_settings_action(settings_focus)
        end select
    end subroutine handle_settings_key

    subroutine execute_palette_command(cmd)
        integer, intent(in) :: cmd
        select case (cmd)
        case (1:SCREEN_COUNT)
            call set_hmi_screen(cmd)
        case (SCREEN_COUNT + 1)
            grid%auto_balance = .not. grid%auto_balance
            call set_bool_notice("Auto balance enabled.", "Auto balance disabled.", grid%auto_balance)
        case (SCREEN_COUNT + 2)
            call balance_now(grid)
            call set_notice("One-shot balance command executed.")
        case (SCREEN_COUNT + 3)
            call cycle_plant_mode()
            call set_notice("Plant mode cycled.")
        case (SCREEN_COUNT + 4)
            grid%roi_dispatch = .not. grid%roi_dispatch
            call set_bool_notice("ROI dispatch enabled.", "ROI dispatch disabled.", grid%roi_dispatch)
        case (SCREEN_COUNT + 5)
            grid%fcr_hold = .not. grid%fcr_hold
            call set_bool_notice("FCR hold enabled.", "FCR hold disabled.", grid%fcr_hold)
        case (SCREEN_COUNT + 6)
            hmi_theme = modulo(hmi_theme + 1, THEME_COUNT)
            call apply_theme()
            call set_notice("Theme: "//trim(theme_name()))
        case (SCREEN_COUNT + 7)
            call cycle_density()
        case (SCREEN_COUNT + 8)
            color_blind_safe = .not. color_blind_safe
            call apply_theme()
            call set_bool_notice("Colour-blind-safe palette on.", "Colour-blind-safe palette off.", color_blind_safe)
        case (SCREEN_COUNT + 9)
            settings_overlay_active = .true.
            settings_focus = 1
        case (SCREEN_COUNT + 10)
            nav_rail_collapsed = .not. nav_rail_collapsed
            call set_bool_notice("Navigation rail collapsed.", "Navigation rail expanded.", nav_rail_collapsed)
        case (SCREEN_COUNT + 11)
            demo_mode_active = .not. demo_mode_active
            demo_last_switch_tick = anim_tick
            demo_screen_index = hmi_screen
            call set_bool_notice("Demo tour started.", "Demo tour stopped.", demo_mode_active)
        case (SCREEN_COUNT + 12)
            coach_overlay_active = .true.
            coach_step = 1
        case (SCREEN_COUNT + 13)
            call export_screen_png()
        case (SCREEN_COUNT + 14)
            call export_shift_csv(grid)
            call set_notice("CSV exported.")
        case (SCREEN_COUNT + 15)
            scn_selected = mod(scn_selected, N_SCENARIOS) + 1
            call ensure_distinct_compare_scenario()
            scn_playing = .false.
            call set_notice("Scenario selected: "//trim(SCN_LABEL(scn_selected)))
        case (SCREEN_COUNT + 16)
            call reset_controls(grid)
            call reset_alarm_workflow()
            call set_notice("Plant controls reset.")
        end select
        command_palette_active = .false.
        call refresh_model(grid)
    end subroutine execute_palette_command

    function palette_command_label(cmd) result(s)
        integer, intent(in) :: cmd
        character(len=64) :: s
        select case (cmd)
        case (1:SCREEN_COUNT)
            write(s, '("Go to ",A)') trim(SCREEN_FULL_LABEL(cmd))
        case (SCREEN_COUNT + 1); s = "Toggle auto balance"
        case (SCREEN_COUNT + 2); s = "Run one-shot balance"
        case (SCREEN_COUNT + 3); s = "Cycle plant mode"
        case (SCREEN_COUNT + 4); s = "Toggle ROI dispatch"
        case (SCREEN_COUNT + 5); s = "Toggle FCR hold"
        case (SCREEN_COUNT + 6); s = "Cycle theme"
        case (SCREEN_COUNT + 7); s = "Cycle density"
        case (SCREEN_COUNT + 8); s = "Toggle colour-blind-safe palette"
        case (SCREEN_COUNT + 9); s = "Open Settings"
        case (SCREEN_COUNT + 10); s = "Collapse / expand navigation rail"
        case (SCREEN_COUNT + 11); s = "Start / stop demo tour"
        case (SCREEN_COUNT + 12); s = "Start guided coach marks"
        case (SCREEN_COUNT + 13); s = "Export active screen to PNG"
        case (SCREEN_COUNT + 14); s = "Export engineering CSV"
        case (SCREEN_COUNT + 15); s = "Select next scenario"
        case (SCREEN_COUNT + 16); s = "Reset plant controls"
        case default; s = ""
        end select
    end function palette_command_label

    subroutine execute_settings_action(action)
        integer, intent(in) :: action
        select case (action)
        case (1)
            hmi_theme = modulo(hmi_theme + 1, THEME_COUNT)
            call apply_theme()
            call set_notice("Theme: "//trim(theme_name()))
        case (2)
            call cycle_density()
        case (3)
            ui_scale_pct = min(125, ui_scale_pct + 5)
            call set_notice("UI scale: "//trim(int_text(ui_scale_pct))//"%")
        case (4)
            color_blind_safe = .not. color_blind_safe
            call apply_theme()
            call set_bool_notice("Colour-blind-safe palette on.", "Colour-blind-safe palette off.", color_blind_safe)
        case (5)
            hmi_theme = THEME_HICON
            call apply_theme()
            call set_notice("High contrast control-room theme active.")
        case (6)
            nav_rail_collapsed = .not. nav_rail_collapsed
            call set_bool_notice("Navigation rail collapsed.", "Navigation rail expanded.", nav_rail_collapsed)
        case (7)
            demo_mode_active = .not. demo_mode_active
            demo_last_switch_tick = anim_tick
            demo_screen_index = hmi_screen
            call set_bool_notice("Demo tour started.", "Demo tour stopped.", demo_mode_active)
        case (8)
            coach_overlay_active = .true.
            coach_step = 1
            settings_overlay_active = .false.
        case (9)
            settings_overlay_active = .false.
        end select
    end subroutine execute_settings_action

    function settings_action_label(action) result(s)
        integer, intent(in) :: action
        character(len=72) :: s
        select case (action)
        case (1); s = "Theme  ["//trim(theme_name())//"]"
        case (2); s = "Density  ["//trim(density_name())//"]"
        case (3); s = "UI scale  ["//trim(int_text(ui_scale_pct))//"%]"
        case (4); s = "Colour-blind-safe signals  ["//merge("ON ", "OFF", color_blind_safe)//"]"
        case (5); s = "Switch to high-contrast control-room mode"
        case (6); s = "Navigation rail  ["//merge("collapsed", "expanded ", nav_rail_collapsed)//"]"
        case (7); s = "Presentation auto-tour  ["//merge("ON ", "OFF", demo_mode_active)//"]"
        case (8); s = "Start guided coach marks"
        case (9); s = "Close Settings"
        case default; s = ""
        end select
    end function settings_action_label

    subroutine cycle_focus(delta)
        integer, intent(in) :: delta
        integer :: i, idx
        idx = 1
        do i = 1, FOCUS_COUNT
            if (FOCUS_IDS(i) == focus_control_id) then
                idx = i
                exit
            end if
        end do
        idx = modulo(idx - 1 + delta, FOCUS_COUNT) + 1
        focus_control_id = FOCUS_IDS(idx)
    end subroutine cycle_focus

    subroutine activate_focused_control()
        active_control = focus_control_id
        select case (focus_control_id)
        case (ID_AUTO, ID_BALANCE, ID_RESET, ID_ROI_MODE, ID_FCR_HOLD, ID_LOAD_STEP, &
              ID_CLOUD_RAMP, ID_TURBINE_TRIP, ID_CC_MODE, ID_MARKET_PROFILE, ID_MARKET_REPLAY)
            call handle_command(focus_control_id)
        case (ID_SCN_PREV)
            scn_selected = mod(scn_selected - 2 + N_SCENARIOS, N_SCENARIOS) + 1
            call ensure_distinct_compare_scenario()
        case (ID_SCN_NEXT)
            scn_selected = mod(scn_selected, N_SCENARIOS) + 1
            call ensure_distinct_compare_scenario()
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
        case (ID_EXPORT_CSV)
            call export_shift_csv(grid)
            call set_notice("CSV exported.")
        case (ID_EXPORT_PDF)
            call export_shift_csv(grid)
            call launch_pdf_report(grid)
        case (ID_SHORTCUTS)
            shortcuts_popup_active = .not. shortcuts_popup_active
        case (ID_DEMAND, ID_RENEWABLE, ID_STORAGE, ID_GAS, ID_AMBIENT, ID_TIT)
            call set_notice("Use Left/Right to trim the focused slider.")
        end select
        active_control = ID_NONE
    end subroutine activate_focused_control

    logical function adjust_focused_slider(direction) result(changed)
        integer, intent(in) :: direction
        real(dp) :: d
        changed = .true.
        select case (focus_control_id)
        case (ID_DEMAND)
            d = 1.0_dp * real(direction, dp)
            grid%demand_MW = clamp_real(grid%demand_MW + d, DEMAND_MIN_MW, DEMAND_MAX_MW)
            grid%market_load_replay_enabled = .false.
        case (ID_RENEWABLE)
            d = 1.0_dp * real(direction, dp)
            grid%renewable_MW = clamp_real(grid%renewable_MW + d, 0.0_dp, RENEWABLE_MAX_MW)
            grid%renewable_curtail_MW = 0.0_dp
            grid%market_weather_enabled = .false.
        case (ID_STORAGE)
            d = 0.5_dp * real(direction, dp)
            grid%storage_request_MW = clamp_real(grid%storage_request_MW + d, STORAGE_MIN_MW, STORAGE_MAX_MW)
            grid%auto_balance = .false.
        case (ID_GAS)
            d = 1.0_dp * real(direction, dp)
            grid%gas_dispatch_pct = clamp_real(grid%gas_dispatch_pct + d, GAS_MIN_PCT, GAS_MAX_PCT)
            grid%auto_balance = .false.
        case (ID_AMBIENT)
            d = 1.0_dp * real(direction, dp)
            grid%ambient_C = clamp_real(grid%ambient_C + d, -20.0_dp, 45.0_dp)
            grid%market_weather_enabled = .false.
        case (ID_TIT)
            d = 5.0_dp * real(direction, dp)
            grid%TIT_K = clamp_real(grid%TIT_K + d, 1200.0_dp, 1600.0_dp)
        case default
            changed = .false.
        end select
    end function adjust_focused_slider

    subroutine update_demo_tour()
        if (.not. demo_mode_active) return
        if (command_palette_active .or. settings_overlay_active .or. coach_overlay_active) return
        if (anim_tick - demo_last_switch_tick < DEMO_SCREEN_TICKS) return
        demo_screen_index = modulo(demo_screen_index, SCREEN_COUNT) + 1
        call set_hmi_screen(demo_screen_index)
        demo_last_switch_tick = anim_tick
    end subroutine update_demo_tour

    subroutine export_screen_png()
        character(kind=c_char), allocatable, target :: c_path(:)
        character(len=160) :: path
        integer(c_int) :: ok
        if (.not. c_associated(h_main)) return
        write(path, '("output\\screen_f",I2.2,"_",I0,".png")') hmi_screen, max(0, nint(grid%elapsed_s * 10.0_dp))
        call make_c_string(trim(path), c_path)
        ok = hmi_save_window_png(h_main, c_loc(c_path))
        if (ok /= 0_c_int) then
            call set_notice("PNG exported: "//trim(path))
        else
            call set_notice("PNG export failed. Check the output folder.")
        end if
    end subroutine export_screen_png

    function int_text(v) result(s)
        integer, intent(in) :: v
        character(len=12) :: s
        write(s, '(I0)') v
    end function int_text

    function hit_test_control(x, y) result(control_id)
        integer, intent(in) :: x, y
        integer(c_int) :: control_id
        integer :: bx1, bx2, bx3, by, bw, bh, gap, step

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

        gap = KPI_TILE_GAP
        bh = ui_button_h()
        step = ui_button_step()
        bx1 = layout_control_left + 16
        bx3 = layout_control_left + layout_control_w - 16
        bw = (bx3 - bx1 - gap) / 2
        bx2 = bx1 + bw + gap
        by = layout_button_y
        if (point_in_rect(x, y, bx1, by, bx1 + bw, by + bh)) control_id = ID_AUTO
        if (point_in_rect(x, y, bx2, by, bx3, by + bh)) control_id = ID_BALANCE
        by = layout_button_y + step
        if (point_in_rect(x, y, bx1, by, bx1 + bw, by + bh)) control_id = ID_CC_MODE
        if (point_in_rect(x, y, bx2, by, bx3, by + bh)) control_id = ID_FCR_HOLD
        by = layout_button_y + 2 * step
        if (point_in_rect(x, y, bx1, by, bx1 + bw, by + bh)) control_id = ID_ROI_MODE
        if (point_in_rect(x, y, bx2, by, bx3, by + bh)) control_id = ID_LOAD_STEP
        by = layout_button_y + 3 * step
        if (point_in_rect(x, y, bx1, by, bx1 + bw, by + bh)) control_id = ID_CLOUD_RAMP
        if (point_in_rect(x, y, bx2, by, bx3, by + bh)) control_id = ID_TURBINE_TRIP
        by = layout_button_y + 4 * step
        if (point_in_rect(x, y, bx1, by, bx1 + bw, by + bh)) control_id = ID_MARKET_PROFILE
        if (point_in_rect(x, y, bx2, by, bx3, by + bh)) control_id = ID_MARKET_REPLAY
        by = layout_button_y + 5 * step
        if (point_in_rect(x, y, bx1, by, bx3, by + bh)) control_id = ID_RESET
        ! Scenario name box: click cycles to next scenario (when not playing)
        by = layout_button_y + 6 * step + 58
        if (point_in_rect(x, y, bx1, by, bx3, by + bh) .and. .not. scn_playing) &
            control_id = ID_SCN_NEXT
        by = layout_button_y + 6 * step + 108
        if (point_in_rect(x, y, bx1, by, bx1 + bw, by + bh)) control_id = ID_SCN_PREV
        if (point_in_rect(x, y, bx2, by, bx3, by + bh)) control_id = ID_SCN_RUN_STOP
        by = layout_button_y + 6 * step + 158
        if (point_in_rect(x, y, bx1, by, bx1 + bw, by + bh)) control_id = ID_EXPORT_CSV
        if (point_in_rect(x, y, bx2, by, bx3, by + bh)) control_id = ID_EXPORT_PDF
        if (hmi_screen == SCREEN_SCENARIO) then
            block
                integer :: ix, iw, top_y, col1_w, col2_x, col2_w, cmp_x, cmp_y, cmp_w
                ix = layout_main_left + 18
                iw = layout_main_w - 36
                top_y = hmi_content_top(layout_main_top) + 8
                col1_w = iw * 42 / 100
                col2_x = ix + col1_w + 20
                col2_w = iw - col1_w - 20
                cmp_w = 104
                cmp_y = top_y + 118
                cmp_x = col2_x + col2_w - (3 * cmp_w + 2 * gap)
                if (point_in_rect(x, y, cmp_x, cmp_y, cmp_x + cmp_w, cmp_y + bh)) &
                    control_id = ID_SCN_B_PREV
                if (point_in_rect(x, y, cmp_x + cmp_w + gap, cmp_y, &
                        cmp_x + 2 * cmp_w + gap, cmp_y + bh)) &
                    control_id = ID_SCN_B_NEXT
                if (point_in_rect(x, y, cmp_x + 2 * (cmp_w + gap), cmp_y, &
                        cmp_x + 3 * cmp_w + 2 * gap, cmp_y + bh)) &
                    control_id = ID_SCN_COMPARE
            end block
        end if
        ! [?] shortcuts button in main-area header bar (top-right)
        if (point_in_rect(x, y, layout_main_left + layout_main_w - 68, layout_main_top + 8, &
                layout_main_left + layout_main_w - 6, layout_main_top + 40)) &
            control_id = ID_SHORTCUTS
    end function hit_test_control

    function hit_test_nav(x, y) result(screen_id)
        integer, intent(in) :: x, y
        integer :: screen_id
        integer :: tab_w, tab_x, i, nav_y, nav_h, row_y, row_h

        screen_id = 0
        if (point_in_rect(x, y, layout_nav_left, layout_nav_top, &
                layout_nav_left + layout_nav_w, layout_nav_bottom)) then
            if (point_in_rect(x, y, layout_nav_left + 8, layout_nav_top + 8, &
                    layout_nav_left + layout_nav_w - 8, layout_nav_top + 44)) then
                screen_id = NAV_RAIL_TOGGLE
                return
            end if
            row_h = merge(34, 38, nav_rail_collapsed)
            row_y = layout_nav_top + 70
            do i = 1, SCREEN_COUNT
                if (.not. nav_rail_collapsed) then
                    if (i == 1) then
                        row_y = row_y + 24
                    else if (SCREEN_LEVEL(i) /= SCREEN_LEVEL(i - 1)) then
                        row_y = row_y + 24
                    end if
                end if
                if (point_in_rect(x, y, layout_nav_left + 6, row_y, &
                        layout_nav_left + layout_nav_w - 6, row_y + row_h)) then
                    screen_id = i
                    return
                end if
                row_y = row_y + row_h + 4
            end do
        end if
        nav_y = layout_main_top + 72
        nav_h = 32
        if (.not. point_in_rect(x, y, layout_main_left, nav_y, &
                layout_main_left + layout_main_w, nav_y + nav_h)) return
        tab_w = max(1, layout_main_w / SCREEN_COUNT)
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

    function hit_test_command_palette(x, y) result(cmd)
        integer, intent(in) :: x, y
        integer :: cmd
        integer :: pw, px, py, row_h, first_cmd, visible_n, i, row_y

        cmd = 0
        pw = min(720, max(520, layout_main_w / 2))
        px = layout_main_left + layout_main_w / 2 - pw / 2
        py = layout_main_top + 92
        row_h = 34
        first_cmd = max(1, min(command_palette_index - 5, max(1, CMD_COUNT - 11)))
        visible_n = min(12, CMD_COUNT - first_cmd + 1)
        if (.not. point_in_rect(x, y, px, py, px + pw, py + 74 + visible_n * row_h + 18)) return
        do i = 1, visible_n
            row_y = py + 68 + (i - 1) * row_h
            if (point_in_rect(x, y, px + 12, row_y, px + pw - 12, row_y + row_h - 4)) then
                cmd = first_cmd + i - 1
                return
            end if
        end do
    end function hit_test_command_palette

    function hit_test_settings_overlay(x, y) result(action)
        integer, intent(in) :: x, y
        integer :: action
        integer :: pw, px, py, row_h, i, row_y

        action = 0
        pw = min(680, max(520, layout_main_w / 2))
        px = layout_main_left + layout_main_w / 2 - pw / 2
        py = layout_main_top + 118
        row_h = 40
        if (.not. point_in_rect(x, y, px, py, px + pw, py + 92 + SETTINGS_COUNT * row_h)) return
        do i = 1, SETTINGS_COUNT
            row_y = py + 74 + (i - 1) * row_h
            if (point_in_rect(x, y, px + 14, row_y, px + pw - 14, row_y + row_h - 6)) then
                action = i
                return
            end if
        end do
    end function hit_test_settings_overlay

    function hit_test_faceplate(x, y) result(fp_id)
        integer, intent(in) :: x, y
        integer :: fp_id
        integer :: x0, y0, h, inner_x, inner_w, gy0, gh, fy, fw, fg, tx, i

        fp_id = FP_NONE
        if (hmi_screen /= SCREEN_OVERVIEW .or. .not. overview_detail) return
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

        if (.not. c_associated(back_memdc) .or. .not. c_associated(back_bitmap) .or. &
                back_w /= cw .or. back_h /= ch) then
            call destroy_back_buffer()
            back_memdc = CreateCompatibleDC(hdc)
            back_bitmap = CreateCompatibleBitmap(hdc, cw, ch)
            if (.not. c_associated(back_memdc) .or. .not. c_associated(back_bitmap)) then
                call destroy_back_buffer()
                call draw_dashboard(hdc, int(cw), int(ch))
                return
            end if
            back_old_bitmap = SelectObject(back_memdc, back_bitmap)
            back_w = cw
            back_h = ch
        end if

        ! [perf] One configured Graphics for the whole frame (see hmi_begin_frame),
        ! ended before the BitBlt so GDI+ flushes into the back buffer.
        if (native_renderer_ready) call hmi_begin_frame(back_memdc)
        call draw_dashboard(back_memdc, int(cw), int(ch))
        if (native_renderer_ready) call hmi_end_frame()
        ok = BitBlt(hdc, 0_c_int, 0_c_int, cw, ch, back_memdc, 0_c_int, 0_c_int, SRCCOPY)
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
        if (boot_ticks > 0) then          ! [6.0-P5] self-drawing boot sequence
            call draw_boot_overlay(hdc, canvas_w, canvas_h, &
                real(BOOT_TICKS0 - boot_ticks, dp) / real(BOOT_TICKS0, dp))
            return
        end if
        call fill_box(hdc, 0, 0, canvas_w, canvas_h, COL_BG)
        ! [6.0] Drafting grid — fine minor lines + stronger major lines (graph-paper read)
        block
            integer :: gg
            ! [perf] Coarser drafting grid (48 px minor / 192 px major) — was 28/112,
            ! which drew ~188 AA lines/frame, most of them hidden behind opaque panels.
            do gg = 0, canvas_w, 48
                call draw_line(hdc, gg, 0, gg, canvas_h, COL_BG_GRID, 1)
            end do
            do gg = 0, canvas_h, 48
                call draw_line(hdc, 0, gg, canvas_w, gg, COL_BG_GRID, 1)
            end do
            do gg = 0, canvas_w, 192
                call draw_line(hdc, gg, 0, gg, canvas_h, COL_BORDER_SOFT, 1)
            end do
            do gg = 0, canvas_h, 192
                call draw_line(hdc, 0, gg, canvas_w, gg, COL_BORDER_SOFT, 1)
            end do
        end block
        call draw_control_panel(hdc)
        call draw_nav_rail(hdc)

        x0 = layout_main_left
        y0 = layout_main_top
        w = layout_main_w
        h = layout_main_h
        inner_x = x0 + PAD_PANEL_X
        inner_w = max(500, w - 2 * PAD_PANEL_X)

        ! --- Header bar ---
        call fill_box(hdc, x0, y0, x0 + w, y0 + 44, COL_PANEL_DEEP)
        ! Left accent — 6 px cyan stripe
        call fill_box(hdc, x0, y0, x0 + 6, y0 + 44, COL_CYAN)
        ! Subtle blue tint wash on right portion (faux depth)
        call hmi_fill_alpha_rect(hdc, int(x0 + w - 340, c_int), int(y0, c_int), &
            int(x0 + w, c_int), int(y0 + 44, c_int), COL_CYAN, 12_c_int)
        call draw_line(hdc, x0, y0 + 44, x0 + w, y0 + 44, COL_BORDER, 1)
        write(title, '("ThermoTwin-F  |  Plant Control Console  |  ",I2," Hz  ",A)') &
            nint(grid%nominal_frequency_Hz), trim(grid%market_power_zone)
        call draw_title_text(hdc, inner_x + 10, y0 + 10, trim(title), COL_INK)
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
            plant_text = "GT ONLY"
        end if
        write(subtitle, '("t=",F6.1,"s  ",A," | ",A," | ",A," | ",A)') &
            grid%elapsed_s, trim(plant_text), trim(auto_text), trim(dispatch_text), trim(reserve_text)
        call draw_text(hdc, x0 + w - 490, y0 + 14, trim(subtitle), &
            merge(COL_LIME, COL_AMBER, grid%auto_balance))
        ! [?] shortcuts button — top-right of header
        block
            integer :: bx, bw2, by2, bh2
            bx = x0 + w - 68;  bw2 = 62;  by2 = y0 + 8;  bh2 = 32
            call fill_soft_box(hdc, bx, by2, bx + bw2, by2 + bh2, &
                merge(COL_CYAN, COL_PANEL_ALT, shortcuts_popup_active))
            call stroke_soft_box(hdc, bx, by2, bx + bw2, by2 + bh2, &
                merge(COL_INK, COL_BORDER, shortcuts_popup_active), 1)
            call draw_text(hdc, bx + 10, by2 + 8, "? Keys", &
                merge(COL_PANEL_DEEP, COL_INK, shortcuts_popup_active))
            call draw_focus_box(hdc, ID_SHORTCUTS, bx, by2, bx + bw2, by2 + bh2)
        end block

        ! --- Status banner ---
        call grid_status(status, status_color)
        call fill_box(hdc, x0, y0 + 44, x0 + w, y0 + 68, COL_PANEL_ALT)
        call fill_box(hdc, x0, y0 + 44, x0 + 6, y0 + 68, status_color)
        call draw_line(hdc, x0, y0 + 68, x0 + w, y0 + 68, COL_BORDER_SOFT, 1)
        call draw_text(hdc, inner_x + 10, y0 + 50, trim(status), status_color)
        if (notice_ticks > 0 .and. len_trim(operator_notice) > 0) then
            call draw_text(hdc, inner_x + min(520, w / 2), y0 + 50, trim(operator_notice), COL_CYAN)
        end if
        ! --- Right-aligned status cluster: subsystem chips + transient alerts ---
        ! [5.0-P1] One shared right-to-left cursor keeps the two groups from ever
        ! overlapping (they previously both anchored at x0+w and collided).
        block
            integer :: cx, ctop, cbot, cw_chip
            character(len=24) :: bv
            ctop = y0 + 47;  cbot = y0 + 67;  cw_chip = 38
            cx = x0 + w - 10

            ! Subsystem module chips (persistent), right-to-left
            cx = cx - cw_chip
            call draw_module_chip(hdc, cx, ctop, cbot, cw_chip, "OU",  grid%ou_active,  COL_AMBER)
            cx = cx - cw_chip - 4
            call draw_module_chip(hdc, cx, ctop, cbot, cw_chip, "MPC", grid%mpc_active, COL_CYAN)
            cx = cx - cw_chip - 4
            call draw_module_chip(hdc, cx, ctop, cbot, cw_chip, "TIE", grid%tie_active, COL_BLUE)
            cx = cx - cw_chip - 4
            call draw_module_chip(hdc, cx, ctop, cbot, cw_chip, "GFM", grid%gfm_mode,   COL_LIME)
            cx = cx - cw_chip - 4
            call draw_module_chip(hdc, cx, ctop, cbot, cw_chip, "CCS", grid%ccs_active, COL_GREEN)
            cx = cx - cw_chip - 4
            call draw_module_chip(hdc, cx, ctop, cbot, cw_chip, "P2X", grid%p2x_active, COL_GREEN)

            ! Transient alert badges chained to the LEFT of the chips (12 px divider)
            cx = cx - 12
            if (grid%dnn_active) then
                cx = cx - 42
                call draw_status_badge(hdc, cx, ctop, 40, cbot - ctop, "DNN", COL_CYAN, .true.)
                cx = cx - 4
            end if
            if (grid%gt_opt_saving_h > 50.0_dp) then
                write(bv, '("+$",I0,"/h")') nint(grid%gt_opt_saving_h)
                cx = cx - 78
                call draw_status_badge(hdc, cx, ctop, 76, cbot - ctop, trim(adjustl(bv)), COL_AMBER, .true.)
                cx = cx - 4
            end if
            if (abs(grid%ROCOF_Hz_s) > 0.02_dp) then
                write(bv, '("RoCoF ",F4.2)') abs(grid%ROCOF_Hz_s)
                cx = cx - 104
                if (abs(grid%ROCOF_Hz_s) > 1.0_dp) then
                    call draw_status_badge(hdc, cx, ctop, 102, cbot - ctop, trim(adjustl(bv)), COL_RED, .true.)
                else if (abs(grid%ROCOF_Hz_s) > 0.5_dp) then
                    call draw_status_badge(hdc, cx, ctop, 102, cbot - ctop, trim(adjustl(bv)), COL_AMBER, .true.)
                else
                    call draw_status_badge(hdc, cx, ctop, 102, cbot - ctop, trim(adjustl(bv)), COL_BORDER, .false.)
                end if
            end if
        end block

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
            case (SCREEN_DIAG)
                call draw_diagnostics_screen(hdc, x0, content_y, w, content_h)
            case (SCREEN_DAYAHEAD)
                call draw_dayahead_screen(hdc, x0, content_y, w, content_h)
            case (SCREEN_FLEET_UC)
                call draw_fleet_uc_screen(hdc, x0, content_y, w, content_h)
            case (SCREEN_DNN)
                call draw_dnn_screen(hdc, x0, content_y, w, content_h)
            case (SCREEN_CARBON)
                call draw_carbon_screen(hdc, x0, content_y, w, content_h)
            case (SCREEN_FORECAST)
                call draw_forecast_screen(hdc, x0, content_y, w, content_h)
            case (SCREEN_ADVISORY)
                call draw_advisory_screen(hdc, x0, content_y, w, content_h)
            case (SCREEN_SCENARIO)
                call draw_scenario_screen(hdc, x0, content_y, w, content_h)
            case (SCREEN_EXERGY)
                call draw_exergy_screen(hdc, x0, content_y, w, content_h)
            end select
            if (faceplate_id /= FP_NONE) call draw_kpi_faceplate_popup(hdc, x0, y0, w, h)
            if (help_overlay_active) call draw_help_overlay(hdc, x0, y0, w, h)
            if (shortcuts_popup_active) call draw_shortcuts_popup(hdc, x0, y0, w)
            call draw_global_overlays(hdc, x0, y0, w, h)
            return
        end if

        ! [5.0-B] Flagship executive landing is the default face of F1; the
        ! FLAGSHIP/DETAIL toggle (or pressing F1 again) drops to the detailed view below.
        if (.not. overview_detail) then
            call draw_flagship_screen(hdc, x0, content_y, w, content_h)
            if (faceplate_id /= FP_NONE) call draw_kpi_faceplate_popup(hdc, x0, y0, w, h)
            if (shortcuts_popup_active)  call draw_shortcuts_popup(hdc, x0, y0, w)
            call draw_global_overlays(hdc, x0, y0, w, h)
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
            call fill_box(hdc, x0, gy0, x0 + 6, gy0 + gh, COL_CYAN)   ! 6px left accent
            call hmi_fill_alpha_rect(hdc, int(x0 + w - 180, c_int), int(gy0, c_int), &
                int(x0 + w, c_int), int(gy0 + gh, c_int), COL_CYAN, 8_c_int)  ! subtle right glow
            call draw_line(hdc, x0, gy0 + gh, x0 + w, gy0 + gh, COL_BORDER_SOFT, 1)
            call draw_arc_gauge_freq(hdc, gcx1, gcy, gr)
            call draw_arc_gauge_mw(hdc, gcx2, gcy, gr, grid%plant_power_MW, grid%plant_capacity_MW, "PLANT MW")

            scale_MW = max(max(DEMAND_MAX_MW, grid%demand_MW), max(grid%supply_MW, grid%plant_capacity_MW))
            bar_x = gcx2 + gr + 32
            bar_w = inner_w - (bar_x - inner_x) - 76   ! 76px reserved for SOC bar at right
            call draw_section_title_width(hdc, bar_x, gy0 + 10, "Power balance", bar_w)
            call draw_bar(hdc, bar_x, gy0 + 32, bar_w, 26, "Demand", grid%demand_MW, scale_MW, COL_RED)
            call draw_bar(hdc, bar_x, gy0 + 68, bar_w, 26, "Supply", grid%supply_MW, scale_MW, COL_GREEN)
            call draw_stacked_supply(hdc, bar_x, gy0 + 106, bar_w, 28, scale_MW, &
                COL_LIME, COL_GREEN, COL_BLUE, COL_AMBER)
            if (grid%UFLS_stage > 0) then
                write(vt, '("UFLS S",I1,"  ",I2,"% shed")') grid%UFLS_stage, nint(grid%UFLS_shed_fraction*100.0_dp)
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
                fg = KPI_TILE_GAP
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
                    write(vt, '(F5.1," MW ",F5.1,"%")') grid%plant_power_MW, &
                        100.0_dp * grid%gas_power_MW / max(grid%gas_capacity_MW, 1.0e-9_dp)
                end if
                call draw_faceplate(hdc, fp2, fy, fw, 68, "THERMAL", trim(adjustl(vt)), COL_LIME)
                write(vt, '(SP,F6.1," MW")') grid%imbalance_MW
                call draw_faceplate(hdc, fp3, fy, fw, 68, "IMBALANCE", trim(adjustl(vt)), &
                    merge(COL_GREEN, COL_RED, abs(grid%imbalance_MW) <= 0.5_dp))
                write(vt, '("$ ",I0,"/h")') nint(grid%margin_usd_h)
                call draw_faceplate(hdc, fp4, fy, fw, 68, "NET MARGIN", trim(adjustl(vt)), &
                    merge(COL_GREEN, merge(COL_AMBER, COL_RED, grid%margin_usd_h > -1000.0_dp), &
                    grid%margin_usd_h >= 0.0_dp))
                write(vt, '(F5.1,"% ",F4.1," MWh")') &
                    grid%battery_soc_pct, grid%battery_energy_MWh
                call draw_faceplate(hdc, fp5, fy, fw, 68, "BESS SOC", trim(adjustl(vt)), &
                    merge(COL_RED, COL_BLUE, grid%alarm_low_soc))
                write(vt, '(F4.1,"/",F4.1," MW")') effective_renewable_MW(grid), grid%renewable_MW
                call draw_faceplate(hdc, fp6, fy, fw, 68, "RES INJECTION", trim(adjustl(vt)), &
                    merge(COL_AMBER, COL_GREEN, grid%renewable_curtail_MW > 0.05_dp))

                ! --- ROI panel ---
                call draw_section_title_width(hdc, inner_x, fy + 80, "ROI and thermodynamic economics", inner_w)
                call draw_roi_panel(hdc, inner_x, fy + 102, inner_w, 90)

                ! --- Live traces + power flow ---
                block
                    integer :: ly, lh, lg, tw, fx2, fw2, bottom_y, flow_h, hr_h, flow_gap
                    ly = fy + 80 + 118
                    if (ly > y0 + h - 170) ly = y0 + h - 170
                    if (ly < fy + 198) ly = fy + 198
                    bottom_y = y0 + h - 18
                    lh = max(120, bottom_y - (ly + 26))
                    lg = 20
                    tw = max(360, int(0.60_dp * real(inner_w, dp)))
                    if (inner_w - tw - lg < 240) tw = max(300, inner_w - 240 - lg)
                    fx2 = inner_x + tw + lg
                    fw2 = max(220, inner_w - tw - lg)
                    call draw_section_title_width(hdc, inner_x, ly, &
                        "Live traces  (Hz | demand MW | turbine %)", tw)
                    call draw_history_traces(hdc, inner_x, ly + 26, tw, lh)
                    if (lh > 260) then
                        flow_gap = 12
                        flow_h = max(150, lh * 46 / 100)
                    else
                        flow_gap = 8
                        flow_h = max(70, min(lh - 48, lh * 54 / 100))
                    end if
                    hr_h = max(40, lh - flow_h - flow_gap)
                    call draw_section_title_width(hdc, fx2, ly, "Plant schematic  (live)", fw2)
                    call draw_plant_schematic(hdc, fx2, ly + 26, fw2, flow_h)
                    call draw_heat_rate_chart(hdc, fx2, ly + 26 + flow_h + flow_gap, fw2, hr_h)
                end block
            end block
        end block
        ! [5.0-B] Keep the FLAGSHIP/DETAIL toggle visible in detail mode too — the gauges
        ! panel repaints the header band, so without this the user can't find the way back.
        call draw_overview_toggle(hdc, inner_x, inner_w, content_y + 8)
        if (faceplate_id /= FP_NONE) call draw_kpi_faceplate_popup(hdc, x0, y0, w, h)
        if (shortcuts_popup_active)  call draw_shortcuts_popup(hdc, x0, y0, w)
        call draw_global_overlays(hdc, x0, y0, w, h)
    end subroutine draw_dashboard

    !> [6.0-P5] Self-drawing boot sequence — the drafting grid plots itself in (left to
    !> right) behind the title + progress bar, before the console appears. Gated by
    !> boot_ticks in draw_dashboard; advances on the WM_TIMER animation clock.
    subroutine draw_boot_overlay(hdc, w, h, progress)
        type(c_ptr), value :: hdc
        integer, intent(in) :: w, h
        real(dp), intent(in) :: progress
        integer :: cx, cy, gg, gx_max, bar_w, bar_fill
        character(len=40) :: pc

        cx = w / 2;  cy = h / 2
        call fill_box(hdc, 0, 0, w, h, COL_BG)
        gx_max = nint(progress * real(w, dp))
        do gg = 0, gx_max, 28
            call draw_line(hdc, gg, 0, gg, h, COL_BG_GRID, 1)
        end do
        do gg = 0, h, 28
            call draw_line(hdc, 0, gg, gx_max, gg, COL_BG_GRID, 1)
        end do
        do gg = 0, gx_max, 112
            call draw_line(hdc, gg, 0, gg, h, COL_BORDER_SOFT, 1)
        end do
        call draw_line(hdc, cx - 46, cy, cx + 46, cy, COL_BORDER, 1)
        call draw_line(hdc, cx, cy - 46, cx, cy + 46, COL_BORDER, 1)
        call draw_big_number(hdc, cx, cy - 74, "THERMOTWIN-F", 40, COL_INK)
        call draw_text(hdc, cx - 150, cy - 26, "PLANT CONTROL CONSOLE   .   BLUEPRINT REVISION 6.0", COL_CYAN)
        bar_w = 380;  bar_fill = nint(progress * real(bar_w, dp))
        call stroke_soft_box(hdc, cx - bar_w/2, cy + 22, cx + bar_w/2, cy + 38, COL_BORDER, 1)
        call fill_box(hdc, cx - bar_w/2 + 1, cy + 23, cx - bar_w/2 + bar_fill, cy + 37, COL_CYAN)
        write(pc, '("INITIALISING PLANT MODEL   ",I0,"%")') nint(progress * 100.0_dp)
        call draw_text(hdc, cx - 130, cy + 48, trim(pc), COL_MUTED)
    end subroutine draw_boot_overlay

    subroutine draw_control_panel(hdc)
        type(c_ptr), value :: hdc
        character(len=40) :: value
        character(len=64) :: line, button_text, scn_txt
        integer :: left, top, right, bottom, title_x, panel_top, panel_bottom, row_gap
        integer :: bx1, bx2, bx3, by, btn_w, btn_h, btn_gap, btn_step
        real(dp) :: scn_prog

        left = layout_control_left
        top = layout_control_top
        right = layout_control_left + layout_control_w
        bottom = layout_control_bottom
        title_x = left + 24

        ! Panel shell — rounded soft box
        call draw_panel_box_deep(hdc, left, top, right - left, bottom - top)
        ! Title area with cyan left edge accent
        call fill_box(hdc, left, top, right, top + 62, COL_PANEL)
        call fill_box(hdc, left, top, left + 5, top + 62, COL_CYAN)
        call hmi_fill_alpha_rect(hdc, int(right - 80, c_int), int(top, c_int), &
            int(right, c_int), int(top + 62, c_int), COL_CYAN, 15_c_int)
        call draw_line(hdc, left, top + 62, right, top + 62, COL_BORDER, 1)
        call draw_title_text(hdc, title_x, top + 12, "Plant Controls", COL_INK)
        call draw_text(hdc, title_x, top + 40, "Dispatch console", COL_MUTED)

        write(value, '(F5.1," MW")') grid%demand_MW
        call draw_custom_slider(hdc, ID_DEMAND, layout_slider_x, layout_slider_y(1), layout_slider_w, &
            "Load demand", trim(adjustl(value)), &
            grid%demand_MW, DEMAND_MIN_MW, DEMAND_MAX_MW, COL_RED)

        write(value, '(F4.1,"/",F4.1," MW")') effective_renewable_MW(grid), grid%renewable_MW
        call draw_custom_slider(hdc, ID_RENEWABLE, layout_slider_x, layout_slider_y(2), layout_slider_w, &
            "Renewable dispatch", trim(adjustl(value)), &
            effective_renewable_MW(grid), 0.0_dp, RENEWABLE_MAX_MW, &
            merge(COL_AMBER, COL_GREEN, grid%renewable_curtail_MW > 0.05_dp))

        write(value, '(SP,F6.1," MW")') grid%storage_request_MW
        call draw_custom_slider(hdc, ID_STORAGE, layout_slider_x, layout_slider_y(3), layout_slider_w, &
            "Battery command", trim(adjustl(value)), &
            grid%storage_request_MW, STORAGE_MIN_MW, STORAGE_MAX_MW, COL_BLUE)

        write(value, '(I3," %")') nint(grid%gas_dispatch_pct)
        call draw_custom_slider(hdc, ID_GAS, layout_slider_x, layout_slider_y(4), layout_slider_w, &
            "Turbine dispatch", trim(adjustl(value)), &
            grid%gas_dispatch_pct, GAS_MIN_PCT, GAS_MAX_PCT, COL_LIME)

        write(value, '(I3," C")') nint(grid%ambient_C)
        call draw_custom_slider(hdc, ID_AMBIENT, layout_slider_x, layout_slider_y(5), layout_slider_w, &
            "Ambient air", trim(adjustl(value)), &
            grid%ambient_C, -20.0_dp, 45.0_dp, COL_AMBER)

        write(value, '(I4," K")') nint(grid%TIT_K)
        call draw_custom_slider(hdc, ID_TIT, layout_slider_x, layout_slider_y(6), layout_slider_w, &
            "Turbine inlet temp", trim(adjustl(value)), &
            grid%TIT_K, 1200.0_dp, 1600.0_dp, COL_RED)

        btn_gap = 12
        btn_h = ui_button_h()
        btn_step = ui_button_step()
        bx1 = left + 16
        bx3 = right - 16
        btn_w = (bx3 - bx1 - btn_gap) / 2
        bx2 = bx1 + btn_w + btn_gap
        by = layout_button_y

        call draw_text(hdc, title_x, by - 28, "Dispatch controls", COL_MUTED)

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
        call draw_focus_box(hdc, ID_AUTO, bx1, by, bx1 + btn_w, by + btn_h)
        call draw_focus_box(hdc, ID_BALANCE, bx2, by, bx3, by + btn_h)

        by = layout_button_y + btn_step
        if (grid%fleet_mode) then
            call draw_industrial_button(hdc, bx1, by, bx1 + btn_w, by + btn_h, &
                "FLEET", COL_CYAN, .true.)
        else if (grid%combined_cycle) then
            call draw_industrial_button(hdc, bx1, by, bx1 + btn_w, by + btn_h, &
                "COMBINED", COL_CYAN, .true.)
        else
            call draw_industrial_button(hdc, bx1, by, bx1 + btn_w, by + btn_h, &
                "GT ONLY", COL_PANEL_ALT, .false.)
        end if
        if (grid%fcr_hold) then
            call draw_industrial_button(hdc, bx2, by, bx3, by + btn_h, &
                "FCR HOLD", COL_CYAN, .true.)
        else
            call draw_industrial_button(hdc, bx2, by, bx3, by + btn_h, &
                "FREE BESS", COL_PANEL_ALT, .false.)
        end if
        call draw_focus_box(hdc, ID_CC_MODE, bx1, by, bx1 + btn_w, by + btn_h)
        call draw_focus_box(hdc, ID_FCR_HOLD, bx2, by, bx3, by + btn_h)

        by = layout_button_y + 2 * btn_step
        if (grid%roi_dispatch) then
            call draw_industrial_button(hdc, bx1, by, bx1 + btn_w, by + btn_h, &
                "ROI MODE", COL_GREEN, .true.)
        else
            call draw_industrial_button(hdc, bx1, by, bx1 + btn_w, by + btn_h, &
                "STABILITY", COL_AMBER, .true.)
        end if
        call draw_industrial_button(hdc, bx2, by, bx3, by + btn_h, &
            "LOAD +10", COL_PANEL, .false.)
        call draw_focus_box(hdc, ID_ROI_MODE, bx1, by, bx1 + btn_w, by + btn_h)
        call draw_focus_box(hdc, ID_LOAD_STEP, bx2, by, bx3, by + btn_h)

        by = layout_button_y + 3 * btn_step
        call draw_industrial_button(hdc, bx1, by, bx1 + btn_w, by + btn_h, &
            "CLOUD -15", COL_PANEL, .false.)
        if (grid%fleet_mode) then
            call draw_industrial_button(hdc, bx2, by, bx3, by + btn_h, &
                "CC1 TRIP", COL_RED, .false.)
        else
            call draw_industrial_button(hdc, bx2, by, bx3, by + btn_h, &
                "TURB TRIP", COL_RED, .false.)
        end if
        call draw_focus_box(hdc, ID_CLOUD_RAMP, bx1, by, bx1 + btn_w, by + btn_h)
        call draw_focus_box(hdc, ID_TURBINE_TRIP, bx2, by, bx3, by + btn_h)

        by = layout_button_y + 4 * btn_step
        button_text = "ZONE "//trim(grid%market_power_zone)
        call draw_industrial_button(hdc, bx1, by, bx1 + btn_w, by + btn_h, &
            trim(button_text), COL_CYAN, grid%market_weather_enabled)
        if (grid%market_load_replay_enabled) then
            call draw_industrial_button(hdc, bx2, by, bx3, by + btn_h, &
                "REPLAY ON", COL_GREEN, .true.)
        else
            call draw_industrial_button(hdc, bx2, by, bx3, by + btn_h, &
                "REPLAY", COL_PANEL_ALT, .false.)
        end if
        call draw_focus_box(hdc, ID_MARKET_PROFILE, bx1, by, bx1 + btn_w, by + btn_h)
        call draw_focus_box(hdc, ID_MARKET_REPLAY, bx2, by, bx3, by + btn_h)

        by = layout_button_y + 5 * btn_step
        call draw_industrial_button(hdc, bx1, by, bx3, by + btn_h, &
            "RESET", COL_PANEL, .false.)
        call draw_focus_box(hdc, ID_RESET, bx1, by, bx3, by + btn_h)

        ! Scenario playback selector
        by = layout_button_y + 6 * btn_step + 20
        call fill_box(hdc, title_x, by, right - 24, by + 1, COL_BORDER_SOFT)
        call draw_text(hdc, title_x, by + 10, "Scenario playback", COL_MUTED)

        by = layout_button_y + 6 * btn_step + 58
        call fill_soft_box(hdc, bx1, by, bx3, by + btn_h, COL_PANEL_ALT)
        call stroke_soft_box(hdc, bx1, by, bx3, by + btn_h, &
            merge(COL_GREEN, COL_BORDER_SOFT, scn_playing), 1)
        write(scn_txt, '(I0,"/",I0,"  ",A)') scn_selected, N_SCENARIOS, &
            trim(SCN_LABEL(scn_selected))
        call draw_text(hdc, bx1 + 10, by + 11, trim(adjustl(scn_txt)), &
            merge(COL_GREEN, COL_INK, scn_playing))
        call draw_focus_box(hdc, ID_SCN_NEXT, bx1, by, bx3, by + btn_h)
        if (scn_playing .and. scn_active%duration_s > 0.0_dp) then
            scn_prog = min(1.0_dp, grid%elapsed_s / scn_active%duration_s)
            call fill_box(hdc, bx1 + 1, by + btn_h - 4, &
                bx1 + 1 + int(scn_prog * real(bx3 - bx1 - 2, dp)), &
                by + btn_h - 1, COL_GREEN)
        end if

        by = layout_button_y + 6 * btn_step + 108
        call draw_industrial_button(hdc, bx1, by, bx1 + btn_w, by + btn_h, &
            "<< SCN", COL_PANEL, .false.)
        if (scn_playing) then
            call draw_industrial_button(hdc, bx2, by, bx3, by + btn_h, &
                "STOP SCN", COL_RED, .true.)
        else
            call draw_industrial_button(hdc, bx2, by, bx3, by + btn_h, &
                "RUN SCN >>", COL_LIME, .false.)
        end if
        call draw_focus_box(hdc, ID_SCN_PREV, bx1, by, bx1 + btn_w, by + btn_h)
        call draw_focus_box(hdc, ID_SCN_RUN_STOP, bx2, by, bx3, by + btn_h)

        ! Export report buttons
        by = layout_button_y + 6 * btn_step + 158
        call draw_industrial_button(hdc, bx1, by, bx1 + btn_w, by + btn_h, &
            "EXPORT CSV", COL_CYAN, .false.)
        call draw_industrial_button(hdc, bx2, by, bx3, by + btn_h, &
            "GEN PDF", COL_GREEN, .false.)
        call draw_focus_box(hdc, ID_EXPORT_CSV, bx1, by, bx1 + btn_w, by + btn_h)
        call draw_focus_box(hdc, ID_EXPORT_PDF, bx2, by, bx3, by + btn_h)

        panel_top = layout_button_y + 6 * btn_step + 208
        panel_bottom = layout_footer_y - 28
        if (panel_bottom - panel_top > 70) then
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
                write(line, '("Fleet ",F5.1,"/",I3," MW")') grid%fleet_total_MW, nint(grid%fleet_online_capacity_MW)
                call draw_text(hdc, title_x + 10, panel_top + 34 + row_gap, adjustl(line), COL_CYAN)
                write(line, '("Rsv   ",F5.1,"/",F4.1," MW")') grid%fleet_reserve_MW, grid%fleet_reserve_requirement_MW
                call draw_text(hdc, title_x + 10, panel_top + 34 + 2 * row_gap, adjustl(line), &
                    merge(COL_RED, COL_CYAN, grid%fleet_reserve_binding))
                write(line, '("LMP   $",I3,"/MWh")') nint(grid%fleet_lmp_usd_MWh)
                call draw_text(hdc, title_x + 10, panel_top + 34 + 3 * row_gap, adjustl(line), COL_GREEN)
                write(line, '("Inert ",I4," MWs  MU",I1)') nint(grid%fleet_inertia_MWs), grid%fleet_marginal_unit
                call draw_text(hdc, title_x + 10, panel_top + 34 + 4 * row_gap, adjustl(line), COL_MUTED)
            else if (grid%combined_cycle) then
                write(line, '("ST    ",F5.1,"/",F4.1," MW")') grid%steam_power_MW, grid%steam_capacity_MW
                call draw_text(hdc, title_x + 10, panel_top + 34 + row_gap, adjustl(line), COL_CYAN)
                write(line, '("HRSG  ",F5.1," MW rec")') grid%hrsg_recovered_heat_MW
                call draw_text(hdc, title_x + 10, panel_top + 34 + 2 * row_gap, adjustl(line), COL_MUTED)
                write(line, '("Pinch ",F5.1," K  Stack ",I3)') grid%hrsg_pinch_K, nint(grid%hrsg_stack_T_K)
                call draw_text(hdc, title_x + 10, panel_top + 34 + 3 * row_gap, adjustl(line), &
                    merge(COL_AMBER, COL_CYAN, grid%alarm_hrsg_pinch))
                write(line, '("Eta   ",F5.1,"%  Cond ",F4.1)') &
                    grid%plant_efficiency * 100.0_dp, grid%condenser_pressure_kPa
                call draw_text(hdc, title_x + 10, panel_top + 34 + 4 * row_gap, adjustl(line), COL_GREEN)
            else
                write(line, '("RES   ",F5.1,"/",F4.1," MW")') effective_renewable_MW(grid), grid%renewable_MW
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
        write(line, '("Scan ",I0," ms | trends 250 ms | ",A)') int(TIMER_MS), trim(grid%market_profile_name)
        call draw_text(hdc, title_x, layout_footer_y, trim(line), COL_MUTED)
        write(line, '("Price $",I3,"/MWh | Gas $",F4.1,"/GJ | CO2 $",I3,"/t")') &
            nint(grid%power_price_usd_mwh), grid%fuel_price_usd_gj, nint(grid%carbon_price_usd_t)
        call draw_text(hdc, title_x, layout_footer_y + 20, trim(adjustl(line)), COL_DIM)
    end subroutine draw_control_panel

    subroutine draw_nav_rail(hdc)
        type(c_ptr), value :: hdc
        integer :: left, top, right, bottom, row_h, row_y, i, icon_x, icon_y
        integer(c_int) :: body, accent, txt
        character(len=32) :: label

        left = layout_nav_left
        top = layout_nav_top
        right = layout_nav_left + layout_nav_w
        bottom = layout_nav_bottom

        call draw_panel_box_deep(hdc, left, top, right - left, bottom - top)
        call fill_box(hdc, left, top, right, top + 58, COL_PANEL)
        call fill_box(hdc, left, top, left + 5, top + 58, COL_CYAN)
        call draw_line(hdc, left, top + 58, right, top + 58, COL_BORDER, 1)
        call stroke_soft_box(hdc, left + 8, top + 8, right - 8, top + 44, &
            merge(COL_CYAN, COL_BORDER_SOFT, .not. nav_rail_collapsed), 1)
        if (nav_rail_collapsed) then
            call draw_text(hdc, left + 20, top + 17, ">>", COL_CYAN)
        else
            call draw_text(hdc, left + 18, top + 17, "<< NAV", COL_CYAN)
        end if

        row_h = merge(34, 38, nav_rail_collapsed)
        row_y = top + 70
        do i = 1, SCREEN_COUNT
            if (.not. nav_rail_collapsed) then
                if (i == 1) then
                    call draw_text(hdc, left + 14, row_y + 2, trim(SCREEN_GROUP_LABEL(SCREEN_LEVEL(i))), COL_DIM)
                    row_y = row_y + 24
                else if (SCREEN_LEVEL(i) /= SCREEN_LEVEL(i - 1)) then
                    call draw_text(hdc, left + 14, row_y + 2, trim(SCREEN_GROUP_LABEL(SCREEN_LEVEL(i))), COL_DIM)
                    row_y = row_y + 24
                end if
            end if

            if (i == hmi_screen) then
                body = COL_PANEL_ALT
                accent = COL_CYAN
                txt = COL_INK
            else
                body = COL_PANEL_DEEP
                accent = COL_BORDER_SOFT
                txt = COL_MUTED
            end if
            call fill_soft_box(hdc, left + 6, row_y, right - 6, row_y + row_h, body)
            call fill_box(hdc, left + 6, row_y + 2, left + 10, row_y + row_h - 2, accent)
            if (i == hmi_screen) call stroke_soft_box(hdc, left + 6, row_y, right - 6, row_y + row_h, COL_CYAN, 1)
            icon_x = left + 28
            icon_y = row_y + row_h / 2
            call draw_nav_icon(hdc, icon_x, icon_y, i, merge(COL_CYAN, COL_MUTED, i == hmi_screen))
            if (.not. nav_rail_collapsed) then
                write(label, '("F",I0,"  ",A)') i, trim(SCREEN_NAV_LABEL(i))
                call draw_text(hdc, left + 52, row_y + 9, trim(label), txt)
            else
                write(label, '(I0)') i
                call draw_text(hdc, left + 41, row_y + 9, trim(label), txt)
            end if
            row_y = row_y + row_h + 4
        end do

        if (.not. nav_rail_collapsed .and. row_y + 78 < bottom) then
            call fill_box(hdc, left + 16, bottom - 90, right - 16, bottom - 89, COL_BORDER_SOFT)
            call draw_text(hdc, left + 16, bottom - 76, "Ctrl-K command", COL_MUTED)
            call draw_text(hdc, left + 16, bottom - 54, "Ctrl-S settings", COL_MUTED)
            call draw_text(hdc, left + 16, bottom - 32, "Ctrl-M tour", COL_MUTED)
        end if
    end subroutine draw_nav_rail

    subroutine draw_nav_bar(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: i, tab_w, tx, tx2, key_x, n_alm, bx2, icon_x, icon_y
        integer(c_int) :: body, accent, text_col, glyph_col
        character(len=32) :: label
        character(len=3)  :: cnt_s

        call fill_box(hdc, x, y, x + width, y + height, COL_PANEL_DEEP)
        call draw_line(hdc, x, y, x + width, y, COL_BORDER, 1)
        call draw_line(hdc, x, y + height, x + width, y + height, COL_BORDER_SOFT, 1)
        tab_w = max(1, width / SCREEN_COUNT)
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
            call fill_soft_box(hdc, tx + 1, y + 3, tx2, y + height - 3, body)
            call fill_box(hdc, tx + 1, y + 3, tx + 4, y + height - 3, accent)
            if (i == hmi_screen) then
                ! Bottom accent bar spans full tab width
                call fill_box(hdc, tx + 1, y + height - 4, tx2, y + height - 1, COL_CYAN)
                call stroke_soft_box(hdc, tx + 1, y + 3, tx2, y + height - 3, COL_BORDER, 1)
            end if
            icon_y = y + height / 2 + 1
            glyph_col = merge(COL_CYAN, COL_MUTED, i == hmi_screen)
            if (tab_w >= 96) then
                icon_x = tx + 17
                call draw_nav_icon(hdc, icon_x, icon_y, i, glyph_col)
                write(label, '("F",I0," ",A)') i, trim(SCREEN_NAV_LABEL(i))
                key_x = tx + 34
            else if (tab_w >= 62) then
                icon_x = tx + 14
                call draw_nav_icon(hdc, icon_x, icon_y, i, glyph_col)
                write(label, '("F",I0)') i
                key_x = tx + 30
            else
                write(label, '("F",I0)') i
                key_x = tx + max(6, (tab_w - 14) / 2)
            end if
            call draw_text(hdc, key_x, y + 8, trim(label), text_col)
            ! Red alarm count badge on the SCREEN_ALARMS tab
            if (i == SCREEN_ALARMS) then
                n_alm = count([grid%alarm_surge, grid%alarm_turbine_max, &
                               grid%alarm_ufls_active, grid%alarm_underfreq, &
                               grid%alarm_overfreq, grid%alarm_hrsg_pinch, &
                               grid%alarm_low_reserve, grid%alarm_low_soc])
                if (n_alm > 0) then
                    write(cnt_s, '(I2)') n_alm
                    bx2 = tx2 - 22
                    block
                        integer :: pa
                        pa = 18 + nint(26.0_dp * (0.5_dp + 0.5_dp * sin(real(anim_tick, dp) * 0.45_dp)))
                        call fill_box(hdc, bx2, y + 5, bx2 + 18, y + height - 5, COL_RED)
                        call hmi_fill_alpha_rect(hdc, int(bx2, c_int), int(y + 5, c_int), &
                            int(bx2 + 18, c_int), int(y + height - 5, c_int), COL_INK, int(pa, c_int))  ! [6.0-P5] breathing
                        call draw_text(hdc, bx2 + 2, y + 9, trim(adjustl(cnt_s)), COL_INK)
                    end block
                end if
            end if
        end do
    end subroutine draw_nav_bar

    !> [6.0-P3] Thin line-art glyph per F-key screen, centred at (cx,cy) (~12 px).
    subroutine draw_nav_icon(hdc, cx, cy, sid, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: cx, cy, sid
        integer(c_int), intent(in) :: color

        select case (sid)
        case (SCREEN_OVERVIEW)   ! 2x2 tiles
            call fill_box(hdc, cx-6, cy-6, cx-1, cy-1, color)
            call fill_box(hdc, cx+1, cy-6, cx+6, cy-1, color)
            call fill_box(hdc, cx-6, cy+1, cx-1, cy+6, color)
            call fill_box(hdc, cx+1, cy+1, cx+6, cy+6, color)
        case (SCREEN_GRID)       ! 3 vertical bars
            call fill_box(hdc, cx-6, cy+0, cx-4, cy+6, color)
            call fill_box(hdc, cx-1, cy-4, cx+1, cy+6, color)
            call fill_box(hdc, cx+4, cy-2, cx+6, cy+6, color)
        case (SCREEN_GT)         ! turbine rotor: box + X
            call stroke_soft_box(hdc, cx-6, cy-6, cx+6, cy+6, color, 1)
            call draw_line(hdc, cx-6, cy-6, cx+6, cy+6, color, 1)
            call draw_line(hdc, cx-6, cy+6, cx+6, cy-6, color, 1)
        case (SCREEN_CC)         ! two linked cycles
            call stroke_soft_box(hdc, cx-6, cy-3, cx-1, cy+3, color, 1)
            call stroke_soft_box(hdc, cx+1, cy-3, cx+6, cy+3, color, 1)
            call draw_line(hdc, cx-1, cy, cx+1, cy, color, 1)
        case (SCREEN_MARKET)     ! up arrow
            call draw_line(hdc, cx-6, cy+5, cx+5, cy-5, color, 2)
            call draw_line(hdc, cx+5, cy-5, cx-0, cy-5, color, 1)
            call draw_line(hdc, cx+5, cy-5, cx+5, cy-0, color, 1)
        case (SCREEN_TRENDS)     ! zigzag
            call draw_line(hdc, cx-6, cy-2, cx-2, cy+4, color, 1)
            call draw_line(hdc, cx-2, cy+4, cx+2, cy-4, color, 1)
            call draw_line(hdc, cx+2, cy-4, cx+6, cy+2, color, 1)
        case (SCREEN_ALARMS)     ! warning triangle + dot
            call draw_line(hdc, cx, cy-6, cx-6, cy+5, color, 1)
            call draw_line(hdc, cx, cy-6, cx+6, cy+5, color, 1)
            call draw_line(hdc, cx-6, cy+5, cx+6, cy+5, color, 1)
            call fill_box(hdc, cx-1, cy+0, cx+1, cy+3, color)
        case (SCREEN_DIAG)       ! heartbeat
            call draw_line(hdc, cx-6, cy, cx-2, cy, color, 1)
            call draw_line(hdc, cx-2, cy, cx, cy-5, color, 1)
            call draw_line(hdc, cx, cy-5, cx+2, cy+4, color, 1)
            call draw_line(hdc, cx+2, cy+4, cx+3, cy, color, 1)
            call draw_line(hdc, cx+3, cy, cx+6, cy, color, 1)
        case (SCREEN_DAYAHEAD)   ! calendar
            call stroke_soft_box(hdc, cx-6, cy-4, cx+6, cy+6, color, 1)
            call draw_line(hdc, cx-6, cy-1, cx+6, cy-1, color, 1)
            call draw_line(hdc, cx-3, cy-6, cx-3, cy-3, color, 1)
            call draw_line(hdc, cx+3, cy-6, cx+3, cy-3, color, 1)
        case (SCREEN_FLEET_UC)   ! 3 stacked bars
            call fill_box(hdc, cx-6, cy-5, cx+6, cy-3, color)
            call fill_box(hdc, cx-6, cy-1, cx+3, cy+1, color)
            call fill_box(hdc, cx-6, cy+3, cx+5, cy+5, color)
        case (SCREEN_DNN)        ! network 2 -> 1
            call draw_line(hdc, cx-5, cy-5, cx+4, cy, color, 1)
            call draw_line(hdc, cx-5, cy+5, cx+4, cy, color, 1)
            call fill_box(hdc, cx-6, cy-6, cx-3, cy-3, color)
            call fill_box(hdc, cx-6, cy+3, cx-3, cy+6, color)
            call fill_box(hdc, cx+3, cy-1, cx+6, cy+2, color)
        case (SCREEN_CARBON)     ! leaf (diamond + midrib)
            call draw_line(hdc, cx, cy-6, cx-5, cy, color, 1)
            call draw_line(hdc, cx-5, cy, cx, cy+6, color, 1)
            call draw_line(hdc, cx, cy+6, cx+5, cy, color, 1)
            call draw_line(hdc, cx+5, cy, cx, cy-6, color, 1)
            call draw_line(hdc, cx, cy-5, cx, cy+5, color, 1)
        case (SCREEN_FORECAST)   ! ascending forecast points + baseline
            call draw_line(hdc, cx-6, cy+6, cx+6, cy+6, color, 1)
            call fill_box(hdc, cx-6, cy+2, cx-4, cy+4, color)
            call fill_box(hdc, cx-1, cy-1, cx+1, cy+1, color)
            call fill_box(hdc, cx+4, cy-5, cx+6, cy-3, color)
        case (SCREEN_ADVISORY)   ! info: box + i
            call stroke_soft_box(hdc, cx-5, cy-6, cx+5, cy+6, color, 1)
            call fill_box(hdc, cx-1, cy-4, cx+1, cy-2, color)
            call draw_line(hdc, cx, cy-0, cx, cy+4, color, 2)
        case (SCREEN_SCENARIO)   ! branch Y
            call draw_line(hdc, cx-5, cy+6, cx, cy, color, 2)
            call draw_line(hdc, cx, cy, cx+5, cy-6, color, 2)
            call draw_line(hdc, cx, cy, cx+5, cy+6, color, 2)
        case (SCREEN_EXERGY)     ! availability split
            call draw_line(hdc, cx-8, cy, cx+6, cy, color, 2)
            call draw_line(hdc, cx+2, cy-4, cx+7, cy, color, 2)
            call draw_line(hdc, cx+2, cy+4, cx+7, cy, color, 2)
            call draw_line(hdc, cx-1, cy, cx-5, cy+7, color, 1)
            call draw_line(hdc, cx+1, cy, cx+5, cy+7, color, 1)
            call fill_box(hdc, cx-9, cy-2, cx-5, cy+2, color)
        end select
    end subroutine draw_nav_icon

    !> [6.0-P3] Annunciator line glyphs: compact ISA-style symbols before labels.
    subroutine draw_alarm_icon(hdc, cx, cy, alarm_id, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: cx, cy, alarm_id
        integer(c_int), intent(in) :: color

        select case (alarm_id)
        case (1) ! under-frequency: descending arrow
            call draw_line(hdc, cx-5, cy-5, cx, cy+5, color, 2)
            call draw_line(hdc, cx+5, cy-2, cx, cy+5, color, 2)
            call draw_line(hdc, cx-5, cy-5, cx+4, cy-5, color, 1)
        case (2) ! over-frequency: rising arrow
            call draw_line(hdc, cx-5, cy+5, cx, cy-5, color, 2)
            call draw_line(hdc, cx+5, cy+2, cx, cy-5, color, 2)
            call draw_line(hdc, cx-5, cy+5, cx+4, cy+5, color, 1)
        case (3) ! reserve: tank/level reserve bar
            call stroke_soft_box(hdc, cx-6, cy-5, cx+6, cy+5, color, 1)
            call fill_box(hdc, cx-4, cy+1, cx+4, cy+4, color)
            call draw_line(hdc, cx-7, cy, cx+7, cy, color, 1)
        case (4) ! BESS: battery outline
            call stroke_soft_box(hdc, cx-7, cy-4, cx+5, cy+4, color, 1)
            call fill_box(hdc, cx+6, cy-2, cx+8, cy+2, color)
            call fill_box(hdc, cx-5, cy+1, cx+2, cy+3, color)
        case (5) ! UFLS: breaker open
            call fill_box(hdc, cx-7, cy-1, cx-3, cy+2, color)
            call fill_box(hdc, cx+4, cy-1, cx+8, cy+2, color)
            call draw_line(hdc, cx-3, cy, cx+3, cy-6, color, 2)
        case (6) ! turbine limit: rotor with redline
            call stroke_soft_box(hdc, cx-6, cy-6, cx+6, cy+6, color, 1)
            call draw_line(hdc, cx-6, cy, cx+6, cy, color, 1)
            call draw_line(hdc, cx, cy-6, cx, cy+6, color, 1)
        case (7) ! surge: compressor map knee
            call draw_line(hdc, cx-7, cy+5, cx-2, cy+0, color, 1)
            call draw_line(hdc, cx-2, cy+0, cx+2, cy-2, color, 1)
            call draw_line(hdc, cx+2, cy-2, cx+7, cy-6, color, 1)
            call draw_line(hdc, cx-6, cy-5, cx+5, cy+5, color, 1)
        case (8) ! HRSG pinch: heat exchanger split
            call stroke_soft_box(hdc, cx-7, cy-5, cx+7, cy+5, color, 1)
            call draw_line(hdc, cx-5, cy-2, cx+5, cy-2, color, 1)
            call draw_line(hdc, cx-5, cy+2, cx+5, cy+2, color, 1)
            call draw_line(hdc, cx, cy-6, cx, cy+6, color, 1)
        end select
    end subroutine draw_alarm_icon

    !> [6.0-P3] Title-block corner registration ticks (technical-drawing frame motif).
    subroutine draw_corner_ticks(hdc, x, y, w, h)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, w, h
        integer, parameter :: t = 6
        call draw_line(hdc, x+1,   y+1,   x+1+t, y+1,   COL_BORDER, 1)
        call draw_line(hdc, x+1,   y+1,   x+1,   y+1+t, COL_BORDER, 1)
        call draw_line(hdc, x+w-1, y+1,   x+w-1-t, y+1, COL_BORDER, 1)
        call draw_line(hdc, x+w-1, y+1,   x+w-1, y+1+t, COL_BORDER, 1)
        call draw_line(hdc, x+1,   y+h-1, x+1+t, y+h-1, COL_BORDER, 1)
        call draw_line(hdc, x+1,   y+h-1, x+1,   y+h-1-t, COL_BORDER, 1)
        call draw_line(hdc, x+w-1, y+h-1, x+w-1-t, y+h-1, COL_BORDER, 1)
        call draw_line(hdc, x+w-1, y+h-1, x+w-1, y+h-1-t, COL_BORDER, 1)
    end subroutine draw_corner_ticks

    !> [6.0-P3] Shared technical drawing frame for panels/cards.
    subroutine draw_title_block_frame(hdc, x, y, width, height, fill_color, border_color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer(c_int), intent(in) :: fill_color, border_color
        integer :: x2, y2, rule_w

        x2 = x + width
        y2 = y + height
        call fill_soft_box(hdc, x, y, x2, y2, fill_color)
        call stroke_soft_box(hdc, x, y, x2, y2, border_color, 1)
        if (width >= 48 .and. height >= 28) then
            call draw_corner_ticks(hdc, x, y, width, height)
            rule_w = min(width - 18, max(30, width / 5))
            call draw_line(hdc, x + 10, y + 9, x + 10 + rule_w, y + 9, border_color, 1)
            call draw_line(hdc, x + width - 10 - rule_w, y2 - 9, x + width - 10, y2 - 9, border_color, 1)
        end if
    end subroutine draw_title_block_frame

    subroutine draw_panel_box(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height

        call draw_title_block_frame(hdc, x, y, width, height, COL_PANEL_ALT, COL_BORDER_SOFT)
    end subroutine draw_panel_box

    subroutine draw_panel_box_deep(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height

        call draw_title_block_frame(hdc, x, y, width, height, COL_PANEL_DEEP, COL_BORDER_SOFT)
    end subroutine draw_panel_box_deep

    subroutine draw_accent_card(hdc, x, y, width, height, accent)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer(c_int), intent(in) :: accent

        call draw_panel_box(hdc, x, y, width, height)
        call fill_box(hdc, x, y, x + SP_1, y + height, accent)
        call fill_box(hdc, x + SP_1, y, min(x + width, x + 120), y + 2, accent)
    end subroutine draw_accent_card

    subroutine draw_kpi_card(hdc, x, y, width, height, label, value_text, value_color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        character(len=*), intent(in) :: label, value_text
        integer(c_int), intent(in) :: value_color
        integer :: sep_y

        call draw_accent_card(hdc, x, y, width, height, value_color)
        sep_y = y + max(28, height - 38)
        call draw_text(hdc, x + PAD_CARD_X, y + PAD_CARD_Y, label, COL_MUTED)
        call draw_line(hdc, x + PAD_CARD_X, sep_y, x + width - PAD_CARD_X, sep_y, COL_BORDER_SOFT, 1)
        call draw_mono_title(hdc, x + PAD_CARD_X, sep_y + SP_1, value_text, value_color)
    end subroutine draw_kpi_card

    subroutine draw_screen_caption(hdc, x, y, width, title, subtitle)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width
        character(len=*), intent(in) :: title, subtitle

        call fill_box(hdc, x, y + 2, x + SP_1, y + 24, COL_CYAN)
        call draw_title_text(hdc, x + SP_3, y, title, COL_INK)
        call draw_text(hdc, x + SP_3, y + SP_8, subtitle, COL_MUTED)
        call fill_box(hdc, x, y + 56, x + width, y + 57, COL_CYAN)
        call fill_box(hdc, x, y + 57, x + width, y + 58, COL_BORDER_SOFT)
    end subroutine draw_screen_caption

    subroutine draw_metric_tile(hdc, x, y, width, height, label, value_text, value_color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        character(len=*), intent(in) :: label, value_text
        integer(c_int), intent(in) :: value_color

        call draw_kpi_card(hdc, x, y, width, height, label, value_text, value_color)
    end subroutine draw_metric_tile

    subroutine draw_value_pair(hdc, x, y, label, value_text, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y
        character(len=*), intent(in) :: label, value_text
        integer(c_int), intent(in) :: color

        call draw_text(hdc, x, y, label, COL_MUTED)
        call draw_mono(hdc, x + 168, y, value_text, color)
    end subroutine draw_value_pair

    subroutine draw_grid_dispatch_screen(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: ix, iw, top_y, table_w, right_x, right_w, plot_h, flow_h
        integer :: horizon_y, horizon_h
        character(len=96) :: subtitle, line

        ix = x + 18
        iw = width - 36
        top_y = y + 8
        write(subtitle, '("AGC ",A," | ED ",A," | reserve ",F5.1," MW | inertia ",I4," MWs")') &
            merge("AUTO  ", "MANUAL", grid%auto_balance), merge("ROI", "STB", grid%roi_dispatch), &
            merge(grid%fleet_reserve_MW, grid%reserve_MW, grid%fleet_mode), &
            nint(merge(grid%fleet_inertia_MWs, INERTIA_MWs, grid%fleet_mode))
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

        ! Frequency nadir predictor
        write(line, '("Nadir pred ",F6.3," Hz  ROCOF ",SP,F6.3," Hz/s")') &
            grid%freq_nadir_Hz, grid%freq_rocof_Hz_s
        call draw_text(hdc, right_x, top_y + 250, trim(adjustl(line)), &
            merge(COL_RED, merge(COL_AMBER, COL_CYAN, grid%freq_nadir_Hz < 49.0_dp), &
                  grid%freq_nadir_Hz < 47.5_dp))

        ! GFM BESS status
        if (grid%gfm_mode) then
            write(line, '("GFM BESS ON  Hv=",F4.1,"s  synth ",SP,F5.1," MW  Heq=",F4.1)') &
                grid%gfm_virtual_H, grid%gfm_synth_MW, grid%gfm_H_equiv
            call draw_text(hdc, right_x, top_y + 270, trim(adjustl(line)), COL_LIME)
        else
            call draw_text(hdc, right_x, top_y + 270, "GFM BESS OFF  (toggle: engine_core)", COL_DIM)
        end if

        ! Tie-line / ACE
        if (grid%tie_active) then
            write(line, '("Tie ",SP,F6.1," MW  ACE ",SP,F6.1," MW  Z2f ",F7.3," Hz")') &
                grid%tie_flow_MW, grid%ace_MW, grid%zone2_freq_Hz
            call draw_text(hdc, right_x, top_y + 290, trim(adjustl(line)), &
                merge(COL_AMBER, COL_MUTED, abs(grid%ace_MW) > 10.0_dp))
        else
            call draw_text(hdc, right_x, top_y + 290, "Tie-line inactive (single zone)", COL_DIM)
        end if

        ! MPC-AGC indicator
        if (grid%mpc_active) then
            write(line, '("MPC-AGC ON  setpt ",F5.1," MW  J=",F7.1,"  save ",F6.1)') &
                grid%mpc_setpt_MW, grid%mpc_cost_last, grid%mpc_cost_saving
            call draw_text(hdc, right_x, top_y + 310, trim(adjustl(line)), COL_BLUE)
        else
            call draw_text(hdc, right_x, top_y + 310, "MPC-AGC OFF  (PI droop active)", COL_DIM)
        end if

        horizon_y = top_y + 338
        horizon_h = 176
        if (height > 640) then
            call draw_section_title_width(hdc, right_x, horizon_y - 22, &
                "Economic MPC horizon", right_w)
            call draw_mpc_horizon_panel(hdc, right_x, horizon_y, right_w, horizon_h)
            plot_h = max(160, height - 620)
        else
            plot_h = max(160, height - 430)
        end if

        call draw_section_title_width(hdc, ix, y + height - plot_h - 28, &
            "Live trend context", table_w)
        call draw_history_traces(hdc, ix, y + height - plot_h, table_w, plot_h)
        flow_h = plot_h
        call draw_section_title_width(hdc, right_x, y + height - flow_h - 28, "Power flow", right_w)
        call draw_power_flow(hdc, right_x, y + height - flow_h, right_w, flow_h)
    end subroutine draw_grid_dispatch_screen

    subroutine draw_mpc_horizon_panel(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height

        integer :: gx, gy, gw, gh, k, n, px, py, px_prev, py_prev
        integer :: y_nom, y_lo, y_hi, bar_y, bar_w, fill_w
        real(dp) :: f_lo, f_hi, f_rng, pmax, pfrac
        character(len=72) :: lbl
        integer(c_int) :: freq_col

        call draw_panel_box_deep(hdc, x, y, width, height)

        if (.not. grid%mpc_active) then
            call draw_text(hdc, x + 12, y + 12, "MPC inactive", COL_DIM)
            call draw_text(hdc, x + 12, y + 36, "Toggle MPC to preview receding-horizon dispatch.", COL_MUTED)
            return
        end if
        if (.not. grid%mpc_horizon_ready .or. grid%mpc_horizon_n <= 0) then
            call draw_text(hdc, x + 12, y + 12, "Waiting for MPC solve...", COL_AMBER)
            return
        end if

        n = min(grid%mpc_horizon_n, size(grid%mpc_pred_freq_Hz))
        write(lbl, '("SP ",F5.1," MW  J ",F5.1," / hold ",F5.1)') &
            grid%mpc_setpt_MW, grid%mpc_cost_last, grid%mpc_cost_hold
        call draw_text(hdc, x + 12, y + 10, trim(adjustl(lbl)), COL_CYAN)
        write(lbl, '("save ",F5.1,"  ",I0," min")') grid%mpc_cost_saving, n
        call draw_text(hdc, x + width - 116, y + 10, trim(adjustl(lbl)), &
            merge(COL_GREEN, COL_MUTED, grid%mpc_cost_saving > 0.1_dp))

        gx = x + 42
        gy = y + 38
        gw = max(80, width - 60)
        gh = max(58, height - 92)
        f_lo = 49.5_dp
        f_hi = 50.5_dp
        f_rng = f_hi - f_lo
        call fill_soft_box(hdc, gx, gy, gx + gw, gy + gh, COL_PANEL)
        call stroke_soft_box(hdc, gx, gy, gx + gw, gy + gh, COL_BORDER_SOFT, 1)

        y_nom = gy + gh - nint((50.0_dp - f_lo) / f_rng * real(gh, dp))
        y_lo  = gy + gh - nint((49.8_dp - f_lo) / f_rng * real(gh, dp))
        y_hi  = gy + gh - nint((50.2_dp - f_lo) / f_rng * real(gh, dp))
        call draw_line(hdc, gx, y_nom, gx + gw, y_nom, COL_GREEN, 1)
        call draw_line(hdc, gx, y_lo,  gx + gw, y_lo,  COL_AMBER, 1)
        call draw_line(hdc, gx, y_hi,  gx + gw, y_hi,  COL_AMBER, 1)
        call draw_text(hdc, x + 6, y_hi - 8, "50.2", COL_AMBER)
        call draw_text(hdc, x + 6, y_nom - 8, "50.0", COL_GREEN)
        call draw_text(hdc, x + 6, y_lo - 8, "49.8", COL_AMBER)

        px_prev = 0
        py_prev = 0
        do k = 1, n
            if (n > 1) then
                px = gx + nint(real(k - 1, dp) / real(n - 1, dp) * real(gw, dp))
            else
                px = gx + gw
            end if
            py = gy + gh - nint((clamp_real(grid%mpc_pred_freq_Hz(k), f_lo, f_hi) - f_lo) / f_rng * real(gh, dp))
            freq_col = merge(COL_GREEN, merge(COL_AMBER, COL_RED, &
                abs(grid%mpc_pred_freq_Hz(k) - 50.0_dp) < 0.30_dp), &
                abs(grid%mpc_pred_freq_Hz(k) - 50.0_dp) < 0.08_dp)
            if (k > 1) call draw_line(hdc, px_prev, py_prev, px, py, freq_col, 2)
            call fill_box(hdc, px - 2, py - 2, px + 2, py + 2, freq_col)
            px_prev = px
            py_prev = py
        end do
        bar_y = y + height - 32
        pmax = max(grid%gas_capacity_MW, maxval(grid%mpc_pred_pgen_MW(1:n)), 1.0_dp)
        pfrac = clamp_real(grid%mpc_pred_pgen_MW(n) / pmax, 0.0_dp, 1.0_dp)
        bar_w = max(80, width - 236)
        call draw_text(hdc, x + 12, bar_y - 16, "GT preview", COL_MUTED)
        call fill_soft_box(hdc, x + 86, bar_y - 18, x + 86 + bar_w, bar_y - 6, COL_PANEL)
        fill_w = nint(pfrac * real(bar_w, dp))
        call fill_soft_box(hdc, x + 86, bar_y - 18, x + 86 + fill_w, bar_y - 6, COL_BLUE)
        write(lbl, '(F5.1," MW")') grid%mpc_pred_pgen_MW(n)
        call draw_text(hdc, x + 92 + bar_w, bar_y - 20, trim(adjustl(lbl)), COL_BLUE)
        write(lbl, '("MW error ",SP,F5.1," MW")') grid%mpc_pred_imbalance_MW(n)
        call draw_text(hdc, x + 12, bar_y + 2, trim(adjustl(lbl)), &
            merge(COL_GREEN, COL_RED, grid%mpc_pred_imbalance_MW(n) >= 0.0_dp))
    end subroutine draw_mpc_horizon_panel

    subroutine draw_dispatch_table(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: row_h, row_y, i

        row_h = 34
        call draw_panel_box(hdc, x, y, width, height)
        call fill_box(hdc, x + 1, y + 1, x + width - 1, y + TABLE_HEAD_H, COL_PANEL)
        call draw_line(hdc, x, y + TABLE_HEAD_H, x + width, y + TABLE_HEAD_H, COL_BORDER_SOFT, 1)
        call draw_text(hdc, x + PAD_CARD_X, y + 10, "Unit", COL_MUTED)
        call draw_text(hdc, x + 100, y + 10, "State", COL_MUTED)
        call draw_text(hdc, x + 178, y + 10, "SP MW", COL_MUTED)
        call draw_text(hdc, x + 258, y + 10, "Actual", COL_MUTED)
        call draw_text(hdc, x + 350, y + 10, "Capacity", COL_MUTED)
        call draw_text(hdc, x + 456, y + 10, "Cost", COL_MUTED)
        row_y = y + TABLE_HEAD_H + SP_1
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
        integer :: fill_px, bar_w

        ! Row background — soft alternating shade + left pip
        call fill_soft_box(hdc, x + 4, y - 2, x + width - 4, y + 30, COL_PANEL)
        call fill_box(hdc, x + 4, y - 2, x + 8, y + 30, color)
        ! Capacity mini-bar in the row background — pill style
        bar_w  = 100
        fill_px = max(2, nint(min(actual / max(capacity, 1.0_dp), 1.2_dp) * real(bar_w, dp)))
        call fill_soft_box(hdc, x + width - 120, y + 20, x + width - 120 + bar_w, y + 26, COL_PANEL_DEEP)
        call fill_soft_box(hdc, x + width - 120, y + 20, x + width - 120 + fill_px, y + 26, &
            merge(COL_AMBER, color, actual > capacity * 1.02_dp))
        call stroke_soft_box(hdc, x + width - 120, y + 20, x + width - 120 + bar_w, y + 26, COL_BORDER_SOFT, 1)
        call draw_text(hdc, x + 18, y + 6, name, COL_INK)
        call draw_text(hdc, x + 96, y + 6, merge("ONLINE ", "OFFLINE", online), &
            merge(COL_GREEN, COL_RED, online))
        write(text, '(SP,F7.1)') sp
        call draw_text(hdc, x + 174, y + 6, trim(adjustl(text)), COL_MUTED)
        write(text, '(SP,F7.1)') actual
        call draw_title_text(hdc, x + 248, y + 4, trim(adjustl(text)), color)
        write(text, '(F7.1)') capacity
        call draw_text(hdc, x + 342, y + 6, trim(adjustl(text)), COL_MUTED)
        if (abs(cost) > 0.01_dp) then
            write(text, '("$",F6.1)') cost
        else
            write(text, '(F6.2)') part
        end if
        call draw_text(hdc, x + 450, y + 6, trim(adjustl(text)), COL_AMBER)
    end subroutine draw_dispatch_row

    subroutine draw_gas_turbine_screen(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: ix, iw, top_y, map_w, side_x, side_w, row_y
        integer :: map_h, ts_h, ts_y, remaining, p2_h, wash_h, pid_h
        character(len=96) :: subtitle, value
        integer(c_int) :: surge_color

        ix = x + 18
        iw = width - 36
        top_y = y + 8
        write(subtitle, '("Station ",I3," C | TIT ",I4," K | IGV ",F5.1,"% | ramp ",SP,F5.1,"%/s")') &
            nint(grid%ambient_C), nint(grid%TIT_actual_K), grid%igv_pct, grid%gas_ramp_pct_per_s
        call draw_screen_caption(hdc, ix, top_y, iw, SCREEN_FULL_LABEL(SCREEN_GT), trim(subtitle))

        map_w = max(520, int(0.58_dp * real(iw, dp)))
        side_x = ix + map_w + 18
        side_w = max(260, iw - map_w - 18)

        ! Split left panel: compressor map (top ~65%) + Brayton T-s (bottom ~35%)
        ts_h  = max(80, min(150, height / 4))
        map_h = max(220, height - 250 - ts_h)
        ts_y  = top_y + 104 + map_h + 8

        call draw_section_title_width(hdc, ix, top_y + 76, "Compressor map  (iso-speed + surge limit)", map_w)
        call draw_gt_map(hdc, ix, top_y + 104, map_w, map_h)
        call draw_section_title_width(hdc, ix, ts_y, "Brayton T-s  (state points 1-4)", map_w)
        call draw_brayton_ts(hdc, ix, ts_y + 26, map_w, ts_h)

        pid_h = max(104, min(144, height / 7))
        call draw_section_title_width(hdc, side_x, top_y + 76, "GT P&ID single-line", side_w)
        call draw_plant_schematic(hdc, side_x, top_y + 104, side_w, pid_h)
        call draw_section_title_width(hdc, side_x, top_y + 104 + pid_h + 16, "Station values", side_w)
        surge_color = merge(COL_RED, merge(COL_AMBER, COL_GREEN, grid%surge_margin_pct < 12.0_dp), &
            grid%surge_margin_pct < 6.0_dp)
        row_y = top_y + 104 + pid_h + 52
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
        write(value, '(I6," kJ/kWh")') nint(grid%gt_heat_rate_kJ_kWh)
        call draw_value_pair(hdc, side_x + 10, row_y, "GT heat rate", trim(adjustl(value)), COL_AMBER)
        row_y = row_y + 28
        write(value, '(I6," map")') nint(grid%physics_gt_hr_ref_kJ_kWh)
        call draw_value_pair(hdc, side_x + 10, row_y, "GT map ref", trim(adjustl(value)), COL_CYAN)
        row_y = row_y + 28
        write(value, '(SP,F6.1,"%")') grid%physics_gt_hr_gap_pct
        call draw_value_pair(hdc, side_x + 10, row_y, "HR map gap", trim(adjustl(value)), &
            merge(COL_GREEN, merge(COL_AMBER, COL_RED, grid%physics_gt_hr_gap_pct < 12.0_dp), &
            grid%physics_gt_hr_gap_pct < 5.0_dp))
        row_y = row_y + 28
        write(value, '(F6.2," kg/s")') grid%fuel_flow_kg_s
        call draw_value_pair(hdc, side_x + 10, row_y, "Fuel flow", trim(adjustl(value)), COL_MUTED)
        row_y = row_y + 28
        write(value, '(I4," K")') nint(grid%exhaust_K)
        call draw_value_pair(hdc, side_x + 10, row_y, "Exhaust gas", trim(adjustl(value)), COL_RED)
        row_y = row_y + 44

        call draw_section_title_width(hdc, side_x, row_y, "Thermal economics", side_w)
        call draw_value_stack_compact(hdc, side_x, row_y + 28, side_w, 112)

        row_y = row_y + 156
        remaining = max(132, y + height - row_y - 26)
        p2_h  = remaining * 55 / 100
        wash_h = max(52, remaining - p2_h - 36)
        call draw_section_title_width(hdc, side_x, row_y, "P2 Economic dispatch optimum", side_w)
        call draw_gt_optim_panel(hdc, side_x, row_y + 26, side_w, p2_h)
        row_y = row_y + 26 + p2_h + 18
        call draw_section_title_width(hdc, side_x, row_y, "Compressor wash ROI", side_w)
        call draw_washing_roi_panel(hdc, side_x, row_y + 26, side_w, wash_h)
    end subroutine draw_gas_turbine_screen

    ! -------------------------------------------------------------------------
    ! P2 Economic dispatch optimizer panel: HR curve + margin curve side-by-side.
    ! -------------------------------------------------------------------------
    subroutine draw_gt_optim_panel(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer, parameter :: N = 20   ! mirrors GT_OPT_N from engine_state
        integer :: lx, ly, lw, lh    ! left sub-chart (HR)
        integer :: rx, ry, rw, rh    ! right sub-chart (margin)
        integer :: i, px, py, ppx, ppy, bx, col_w
        integer :: cur_idx           ! scan point closest to current dispatch
        real(dp) :: hr_lo, hr_hi, margin_lo, margin_hi
        real(dp) :: frac, disp_frac, disp_scan
        character(len=32) :: lbl
        integer(c_int) :: bar_col

        call fill_soft_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
        call stroke_soft_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)

        if (.not. grid%gt_opt_solved) then
            call draw_text(hdc, x + 12, y + height / 2 - 8, "Optimizer initialising (~2 s)...", COL_MUTED)
            return
        end if

        ! Split into left (HR) and right (margin) sub-charts
        ! lh/rh reduced so x-axis labels (at ly+lh+2) don't collide with summary (at y+height-14)
        lx = x + 4;       lw = width / 2 - 8
        rx = x + width / 2 + 4;  rw = width - width / 2 - 8
        ly = y + 20;      lh = height - 52
        ry = y + 20;      rh = height - 52

        ! Sub-chart backgrounds
        call fill_box(hdc, lx, ly, lx + lw, ly + lh, COL_BG)
        call fill_box(hdc, rx, ry, rx + rw, ry + rh, COL_BG)

        ! Axis labels
        call draw_text(hdc, lx, y + 4, "HR  kJ/kWh", COL_MUTED)
        call draw_text(hdc, rx, y + 4, "Margin  $/h", COL_MUTED)

        ! --- HR curve ---
        hr_lo = min(minval(grid%gt_opt_hr(1:N)), minval(grid%physics_ref_gt_hr_kJ_kWh(1:FIDELITY_N)))
        hr_hi = max(maxval(grid%gt_opt_hr(1:N)), maxval(grid%physics_ref_gt_hr_kJ_kWh(1:FIDELITY_N)))
        if (hr_hi - hr_lo < 50.0_dp) hr_hi = hr_lo + 50.0_dp  ! min range

        ! Published-map reference envelope, overlaid behind the optimizer scan.
        ppx = -1; ppy = -1
        do i = 1, FIDELITY_N
            px = lx + nint((grid%physics_load_pct(i) - 30.0_dp) / 70.0_dp * real(lw, dp))
            frac = max(0.0_dp, min(1.0_dp, &
                (grid%physics_ref_gt_hr_kJ_kWh(i) - hr_lo) / (hr_hi - hr_lo)))
            py = ly + lh - 2 - nint(frac * real(lh - 4, dp))
            py = max(ly + 2, min(ly + lh - 2, py))
            if (ppx >= 0) call draw_line(hdc, ppx, ppy, px, py, COL_MUTED, 1)
            ppx = px; ppy = py
        end do
        call draw_text(hdc, lx + lw - 66, ly + 4, "ref map", COL_MUTED)

        ppx = -1; ppy = -1
        do i = 1, N
            px = lx + (i - 1) * lw / (N - 1)
            frac = max(0.0_dp, min(1.0_dp, &
                (grid%gt_opt_hr(i) - hr_lo) / (hr_hi - hr_lo)))
            py = ly + lh - 2 - nint(frac * real(lh - 4, dp))
            py = max(ly + 2, min(ly + lh - 2, py))
            if (ppx >= 0) call draw_line(hdc, ppx, ppy, px, py, COL_CYAN, 2)
            ppx = px; ppy = py
        end do

        ! Optimal HR point (cyan dot at best_idx)
        i  = grid%gt_opt_best_idx
        px = lx + (i - 1) * lw / (N - 1)
        frac = max(0.0_dp, min(1.0_dp, &
            (grid%gt_opt_hr(i) - hr_lo) / (hr_hi - hr_lo)))
        py = ly + lh - 2 - nint(frac * real(lh - 4, dp))
        py = max(ly + 2, min(ly + lh - 2, py))
        call fill_box(hdc, px - 4, py - 4, px + 4, py + 4, COL_CYAN)

        ! Current dispatch vertical marker
        disp_frac = max(0.0_dp, min(1.0_dp, &
            (grid%gas_dispatch_pct / 100.0_dp - 0.30_dp) / 0.70_dp))
        px = lx + nint(disp_frac * real(lw, dp))
        call draw_line(hdc, px, ly, px, ly + lh, COL_INK, 1)

        ! Y-axis tick labels
        write(lbl, '(I6)') nint(hr_hi)
        call draw_text(hdc, lx - 2, ly, trim(adjustl(lbl)), COL_DIM)
        write(lbl, '(I6)') nint(hr_lo)
        call draw_text(hdc, lx - 2, ly + lh - 12, trim(adjustl(lbl)), COL_DIM)

        ! --- Margin bars ---
        margin_lo = min(-1.0_dp, minval(grid%gt_opt_margin(1:N)))
        margin_hi = max( 1.0_dp, maxval(grid%gt_opt_margin(1:N)))
        col_w = max(1, rw / N)

        ! Zero line position
        frac = max(0.0_dp, min(1.0_dp, (0.0_dp - margin_lo) / (margin_hi - margin_lo)))
        bx = ry + rh - 2 - nint(frac * real(rh - 4, dp))
        bx = max(ry + 2, min(ry + rh - 2, bx))
        call draw_line(hdc, rx, bx, rx + rw, bx, COL_BORDER_SOFT, 1)

        do i = 1, N
            px = rx + (i - 1) * col_w
            frac = max(0.0_dp, min(1.0_dp, &
                (grid%gt_opt_margin(i) - margin_lo) / (margin_hi - margin_lo)))
            py = ry + rh - 2 - nint(frac * real(rh - 4, dp))
            py = max(ry + 2, min(ry + rh - 2, py))
            bar_col = merge(COL_GREEN, COL_RED, grid%gt_opt_margin(i) >= 0.0_dp)
            if (grid%gt_opt_margin(i) >= 0.0_dp) then
                call fill_box(hdc, px + 1, py, px + col_w - 1, bx, bar_col)
            else
                call fill_box(hdc, px + 1, bx, px + col_w - 1, py, bar_col)
            end if
        end do

        ! Optimal margin marker (cyan outline)
        i  = grid%gt_opt_best_idx
        px = rx + (i - 1) * col_w
        frac = max(0.0_dp, min(1.0_dp, &
            (grid%gt_opt_margin(i) - margin_lo) / (margin_hi - margin_lo)))
        py = ry + rh - 2 - nint(frac * real(rh - 4, dp))
        py = max(ry + 2, min(ry + rh - 2, py))
        call stroke_box(hdc, px, min(py, bx), px + col_w, max(py, bx), COL_CYAN, 1)

        ! Current dispatch marker on margin chart
        disp_frac = max(0.0_dp, min(1.0_dp, &
            (grid%gas_dispatch_pct / 100.0_dp - 0.30_dp) / 0.70_dp))
        px = rx + nint(disp_frac * real(rw, dp))
        call draw_line(hdc, px, ry, px, ry + rh, COL_INK, 1)

        ! X-axis labels (30% / 100%)
        call draw_text(hdc, lx,       ly + lh + 2, "30%", COL_DIM)
        call draw_text(hdc, lx + lw - 20, ly + lh + 2, "100%", COL_DIM)
        call draw_text(hdc, rx,       ry + rh + 2, "30%", COL_DIM)
        call draw_text(hdc, rx + rw - 20, ry + rh + 2, "100%", COL_DIM)

        ! Summary recommendation
        if (abs(grid%gt_opt_saving_h) < 5.0_dp) then
            write(lbl, '("Near-optimal  ($",SP,I0,"/h)")')  nint(grid%gt_opt_saving_h)
        else if (grid%gt_opt_saving_h > 0.0_dp) then
            write(lbl, '("P*=",F5.1," MW  +$",I0,"/h")') &
                grid%gt_opt_pwr(grid%gt_opt_best_idx), nint(grid%gt_opt_saving_h)
        else
            write(lbl, '("P*=",F5.1," MW  $",SP,I0,"/h")') &
                grid%gt_opt_pwr(grid%gt_opt_best_idx), nint(grid%gt_opt_saving_h)
        end if
        call draw_text(hdc, x + 4, y + height - 14, trim(lbl), &
            merge(COL_GREEN, merge(COL_AMBER, COL_MUTED, &
            abs(grid%gt_opt_saving_h) >= 5.0_dp), grid%gt_opt_saving_h > 5.0_dp))
    end subroutine draw_gt_optim_panel

    subroutine draw_gt_map(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: gx, gy, gw, gh, i, px, py, pxp, pyp, is, smx
        real(dp) :: f, pr, pr_run, n, f_surge_at_PR
        character(len=64) :: line
        real(dp), parameter :: N_ISO(3)   = [0.80_dp, 0.90_dp, 1.00_dp]
        integer(c_int) :: COL_ISO(3)
        COL_ISO = [COL_DIM, COL_MUTED, COL_CYAN]

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

        ! Axis labels and tick values
        call draw_text(hdc, gx + gw / 2 - 60, y + 8, "Corrected mass flow fraction", COL_MUTED)
        call draw_text(hdc, x + 6, gy + gh / 2 - 6, "PR", COL_MUTED)
        call draw_text(hdc, gx - 4,          gy + gh + 2, "0.35", COL_DIM)
        call draw_text(hdc, gx + gw / 2 - 8, gy + gh + 2, "0.68", COL_DIM)
        call draw_text(hdc, gx + gw - 10,    gy + gh + 2, "1.0",  COL_DIM)
        call draw_text(hdc, x + 8, gy - 7,         "20", COL_DIM)
        call draw_text(hdc, x + 8, gy + gh / 2 - 7,"13", COL_DIM)
        call draw_text(hdc, x + 8, gy + gh - 7,    "6",  COL_DIM)

        ! Iso-speed lines: 80%, 90%, 100%.  PR scales as N^2 (fan law) from the running line.
        do is = 1, 3
            n = N_ISO(is)
            pxp = -1; pyp = -1
            do i = 0, 39
                f    = 0.35_dp + real(i, dp) * (n - 0.35_dp) / 39.0_dp
                pr_run = 7.0_dp + 11.0_dp * f ** 0.72_dp
                pr   = max(6.5_dp, (pr_run - 6.0_dp) * n * n + 6.0_dp)
                px   = gx + int((f - 0.35_dp) / 0.65_dp * real(gw, dp))
                py   = gy + gh - int((clamp_real(pr, 6.0_dp, 20.0_dp) - 6.0_dp) / 14.0_dp * real(gh, dp))
                if (i > 0 .and. pxp >= 0) &
                    call draw_line(hdc, pxp, pyp, px, py, COL_ISO(is), merge(2, 1, is == 3))
                pxp = px; pyp = py
            end do
            write(line, '(I0,"% N")') nint(n * 100.0_dp)
            call draw_text(hdc, min(px + 3, gx + gw - 52), py - 8, trim(adjustl(line)), COL_ISO(is))
        end do

        ! Surge limit line
        pxp = -1; pyp = -1
        do i = 0, 39
            f  = 0.35_dp + real(i, dp) * 0.65_dp / 39.0_dp
            pr = 8.5_dp + 13.0_dp * f ** 0.85_dp
            px = gx + int((f - 0.35_dp) / 0.65_dp * real(gw, dp))
            py = gy + gh - int((clamp_real(pr, 6.0_dp, 20.0_dp) - 6.0_dp) / 14.0_dp * real(gh, dp))
            if (i > 0 .and. pxp >= 0) call draw_line(hdc, pxp, pyp, px, py, COL_RED, 2)
            pxp = px; pyp = py
        end do
        call draw_text(hdc, gx + gw - 88, gy + 14, "surge limit", COL_RED)

        ! Operating point dot
        px = gx + int((clamp_real(grid%flow_frac, 0.35_dp, 1.0_dp) - 0.35_dp) / 0.65_dp * real(gw, dp))
        py = gy + gh - int((clamp_real(grid%PR_op, 6.0_dp, 20.0_dp) - 6.0_dp) / 14.0_dp * real(gh, dp))
        call hmi_fill_pie(hdc, int(px, c_int), int(py, c_int), 8_c_int, 0.0_c_float, 360.0_c_float, COL_LIME)
        call hmi_fill_pie(hdc, int(px, c_int), int(py, c_int), 4_c_int, 0.0_c_float, 360.0_c_float, COL_BG)

        ! Surge margin arrow: horizontal line from OP toward surge boundary at same PR
        if (grid%PR_op > 8.6_dp) then
            f_surge_at_PR = ((clamp_real(grid%PR_op, 8.6_dp, 21.4_dp) - 8.5_dp) / 13.0_dp) ** (1.0_dp / 0.85_dp)
        else
            f_surge_at_PR = 0.35_dp
        end if
        smx = gx + int((clamp_real(f_surge_at_PR, 0.35_dp, 1.0_dp) - 0.35_dp) / 0.65_dp * real(gw, dp))
        call draw_line(hdc, smx, py, px, py, COL_AMBER, 1)
        call draw_line(hdc, smx, py, smx + 7, py - 4, COL_AMBER, 1)
        call draw_line(hdc, smx, py, smx + 7, py + 4, COL_AMBER, 1)
        write(line, '(F4.1,"% SM")') grid%surge_margin_pct
        call draw_text(hdc, (px + smx) / 2 - 14, py - 14, trim(adjustl(line)), COL_AMBER)

        ! OP readout
        write(line, '("OP  flow ",F5.1,"%  PR ",F5.2)') 100.0_dp * grid%flow_frac, grid%PR_op
        call draw_text(hdc, gx + 12, gy + gh - 28, trim(adjustl(line)), COL_LIME)
    end subroutine draw_gt_map

    ! Brayton cycle T-s diagram using live engine state points.
    ! Plots the four state points: 1=comp inlet, 2=comp outlet, 3=turbine inlet, 4=exhaust.
    subroutine draw_brayton_ts(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        real(dp), parameter :: GAMMA   = 1.4_dp
        real(dp), parameter :: CP      = 1.005_dp   ! kJ/kgK
        real(dp), parameter :: R_AIR   = 0.287_dp   ! kJ/kgK
        real(dp), parameter :: ETA_C   = 0.82_dp    ! compressor isentropic efficiency
        real(dp) :: T1, T2, T3, T4, s1, s2, s3, s4
        real(dp) :: T_min, T_max, s_min, s_max
        integer :: gx, gy, gw, gh
        integer :: px1, py1, px2, py2, px3, py3, px4, py4
        character(len=64) :: lbl

        if (height < 40 .or. width < 80) return

        ! Compute state points from live engine values
        T1 = grid%ambient_C + 273.15_dp
        T2 = T1 * (1.0_dp + (grid%PR_op ** ((GAMMA - 1.0_dp) / GAMMA) - 1.0_dp) / ETA_C)
        T3 = max(grid%TIT_actual_K, T2 + 100.0_dp)
        T4 = max(grid%exhaust_K, T1 + 10.0_dp)

        s1 = 0.0_dp
        s2 = s1 + CP * log(T2 / T1) - R_AIR * log(max(grid%PR_op, 1.01_dp))
        s3 = s2 + CP * log(T3 / T2)
        s4 = s3 + CP * log(T4 / T3) + R_AIR * log(max(grid%PR_op, 1.01_dp))

        T_min = T1 - 60.0_dp
        T_max = T3 + 80.0_dp
        s_min = min(s2 - 0.06_dp, -0.02_dp)
        s_max = max(s4, s3) + 0.08_dp

        gx = x + 52
        gy = y + 4
        gw = max(40, width - 60)
        gh = max(28, height - 14)

        call fill_soft_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
        call stroke_soft_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)
        call fill_box(hdc, gx, gy, gx + gw, gy + gh, COL_BG)
        call stroke_box(hdc, gx, gy, gx + gw, gy + gh, COL_BORDER_SOFT, 1)

        ! [7.0-P6] Carnot envelope: isotherms at TIT (T3) and ambient (T1) over the
        ! heat-addition entropy span (s2 -> s3) — the theoretical-limit rectangle the
        ! real Brayton cycle sits inside.
        block
            integer :: cax, cbx, clo, chi
            cax = max(gx, min(gx+gw, gx + nint((s2 - s_min) / (s_max - s_min) * real(gw, dp))))
            cbx = max(gx, min(gx+gw, gx + nint((s3 - s_min) / (s_max - s_min) * real(gw, dp))))
            clo = max(gy, min(gy+gh, gy + nint((1.0_dp - (T1 - T_min) / (T_max - T_min)) * real(gh, dp))))
            chi = max(gy, min(gy+gh, gy + nint((1.0_dp - (T3 - T_min) / (T_max - T_min)) * real(gh, dp))))
            call draw_line(hdc, cax, clo, cbx, clo, COL_AMBER, 1)
            call draw_line(hdc, cax, chi, cbx, chi, COL_AMBER, 1)
            call draw_line(hdc, cax, clo, cax, chi, COL_AMBER, 1)
            call draw_line(hdc, cbx, clo, cbx, chi, COL_AMBER, 1)
            call draw_text(hdc, cax + 3, chi - 13, "Carnot", COL_AMBER)
        end block

        ! Map state points to pixels
        px1 = gx + nint((s1 - s_min) / (s_max - s_min) * real(gw, dp))
        py1 = gy + nint((1.0_dp - (T1 - T_min) / (T_max - T_min)) * real(gh, dp))
        px2 = gx + nint((s2 - s_min) / (s_max - s_min) * real(gw, dp))
        py2 = gy + nint((1.0_dp - (T2 - T_min) / (T_max - T_min)) * real(gh, dp))
        px3 = gx + nint((s3 - s_min) / (s_max - s_min) * real(gw, dp))
        py3 = gy + nint((1.0_dp - (T3 - T_min) / (T_max - T_min)) * real(gh, dp))
        px4 = gx + nint((s4 - s_min) / (s_max - s_min) * real(gw, dp))
        py4 = gy + nint((1.0_dp - (T4 - T_min) / (T_max - T_min)) * real(gh, dp))
        ! Clamp to plot area
        px1=max(gx,min(gx+gw,px1)); py1=max(gy,min(gy+gh,py1))
        px2=max(gx,min(gx+gw,px2)); py2=max(gy,min(gy+gh,py2))
        px3=max(gx,min(gx+gw,px3)); py3=max(gy,min(gy+gh,py3))
        px4=max(gx,min(gx+gw,px4)); py4=max(gy,min(gy+gh,py4))

        ! Process lines: 1→2 compression, 2→3 combustion, 3→4 expansion
        call draw_line(hdc, px1, py1, px2, py2, COL_CYAN, 2)
        call draw_line(hdc, px2, py2, px3, py3, COL_RED,  2)
        call draw_line(hdc, px3, py3, px4, py4, COL_LIME, 2)

        ! State point dots
        call fill_box(hdc, px1-4, py1-4, px1+4, py1+4, COL_INK)
        call fill_box(hdc, px2-4, py2-4, px2+4, py2+4, COL_CYAN)
        call fill_box(hdc, px3-4, py3-4, px3+4, py3+4, COL_RED)
        call fill_box(hdc, px4-4, py4-4, px4+4, py4+4, COL_LIME)

        ! State labels with temperature
        write(lbl, '("1 ",I0,"K")') nint(T1)
        call draw_text(hdc, px1 - 6,  py1 + 4,  adjustl(lbl), COL_INK)
        write(lbl, '("2 ",I0,"K")') nint(T2)
        call draw_text(hdc, px2 + 5,  py2 - 12, adjustl(lbl), COL_CYAN)
        write(lbl, '("3 ",I0,"K")') nint(T3)
        call draw_text(hdc, px3 - 12, py3 - 12, adjustl(lbl), COL_RED)
        write(lbl, '("4 ",I0,"K")') nint(T4)
        call draw_text(hdc, px4 + 5,  py4 + 4,  adjustl(lbl), COL_LIME)

        ! Y-axis range labels (K)
        write(lbl, '(I0,"K")') nint(T_min)
        call draw_text(hdc, x + 4, gy + gh - 8, adjustl(lbl), COL_DIM)
        write(lbl, '(I0,"K")') nint(T_max - 80.0_dp)
        call draw_text(hdc, x + 4, gy + 2, adjustl(lbl), COL_DIM)
        call draw_text(hdc, x + 4, gy + gh / 2 - 6, "T", COL_MUTED)
        call draw_text(hdc, gx + gw/2 - 22, gy + gh + 2, "s (kJ/kgK)", COL_MUTED)
    end subroutine draw_brayton_ts

    subroutine draw_combined_cycle_screen(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: ix, iw, top_y, diagram_w, side_x, side_w, row_y
        integer :: avail_h, schm_h, tq_h, tq_y
        character(len=96) :: subtitle, value

        ix = x + 18
        iw = width - 36
        top_y = y + 8
        write(subtitle, '("Mode ",A," | GT ",F5.1," MW | ST ",F5.1," MW | eta ",F5.1,"%")') &
            merge("COMBINED", "GT ONLY ", grid%combined_cycle), grid%gas_power_MW, &
            grid%steam_power_MW, grid%plant_efficiency * 100.0_dp
        call draw_screen_caption(hdc, ix, top_y, iw, SCREEN_FULL_LABEL(SCREEN_CC), trim(subtitle))

        diagram_w = max(560, int(0.62_dp * real(iw, dp)))
        side_x = ix + diagram_w + 18
        side_w = max(250, iw - diagram_w - 18)

        ! Left column: schematic (top 38%) + T-Q diagram (bottom 62%)
        avail_h = max(300, height - 180)
        schm_h  = max(130, avail_h * 38 / 100)
        tq_h    = max(100, avail_h - schm_h - 32)
        tq_y    = top_y + 104 + schm_h + 32

        call draw_section_title_width(hdc, ix, top_y + 76, "GT-HRSG P&ID overview", diagram_w)
        call draw_plant_schematic(hdc, ix, top_y + 104, diagram_w, schm_h)
        call draw_section_title_width(hdc, ix, tq_y - 26, "HRSG T-Q diagram  (HP pinch + LP recovery)", diagram_w)
        call draw_hrsg_tq_diagram(hdc, ix, tq_y, diagram_w, tq_h)

        call draw_section_title_width(hdc, side_x, top_y + 76, "Bottoming cycle", side_w)
        row_y = top_y + 112
        if (grid%combined_cycle) then
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
            write(value, '(I4," K")') nint(grid%hrsg_steam_T_K)
            call draw_value_pair(hdc, side_x + 10, row_y, "Steam temp", trim(adjustl(value)), COL_RED)
            row_y = row_y + 28
            write(value, '(F6.1," K")') grid%hrsg_pinch_K
            call draw_value_pair(hdc, side_x + 10, row_y, "Pinch margin", trim(adjustl(value)), &
                merge(COL_RED, COL_GREEN, grid%alarm_hrsg_pinch))
            row_y = row_y + 28
            write(value, '(F5.1," ref  ",SP,F5.1," dK")') &
                grid%physics_hrsg_pinch_ref_K, grid%physics_hrsg_pinch_gap_K
            call draw_value_pair(hdc, side_x + 10, row_y, "Pinch map", trim(adjustl(value)), &
                merge(COL_GREEN, merge(COL_AMBER, COL_RED, grid%physics_hrsg_pinch_gap_K > -1.0_dp), &
                grid%physics_hrsg_pinch_gap_K >= 2.0_dp))
            row_y = row_y + 28
            write(value, '(F6.1," kPa")') grid%condenser_pressure_kPa
            call draw_value_pair(hdc, side_x + 10, row_y, "Condenser", trim(adjustl(value)), COL_BLUE)
        else
            call draw_value_pair(hdc, side_x + 10, row_y, "HRSG recovered", "OFFLINE", COL_DIM)
            row_y = row_y + 28
            call draw_value_pair(hdc, side_x + 10, row_y, "ST target", "OFFLINE", COL_DIM)
            row_y = row_y + 28
            call draw_value_pair(hdc, side_x + 10, row_y, "Steam flow", "--", COL_DIM)
            row_y = row_y + 28
            call draw_value_pair(hdc, side_x + 10, row_y, "Steam pressure", "--", COL_DIM)
            row_y = row_y + 28
            call draw_value_pair(hdc, side_x + 10, row_y, "Steam temp", "--", COL_DIM)
            row_y = row_y + 28
            call draw_value_pair(hdc, side_x + 10, row_y, "Pinch margin", "--", COL_DIM)
            row_y = row_y + 28
            call draw_value_pair(hdc, side_x + 10, row_y, "Pinch map", "--", COL_DIM)
            row_y = row_y + 28
            call draw_value_pair(hdc, side_x + 10, row_y, "Condenser", "--", COL_DIM)
        end if
        row_y = row_y + 44
        call draw_section_title_width(hdc, side_x, row_y, "Plant efficiency", side_w)
        call draw_bar(hdc, side_x, row_y + 32, side_w, 28, "Net plant", grid%plant_power_MW, &
            max(grid%plant_capacity_MW, 1.0_dp), COL_GREEN)
        call draw_bar(hdc, side_x, row_y + 72, side_w, 28, "Heat input", grid%heat_input_MW, &
            max(grid%heat_input_MW, 1.0_dp), COL_AMBER)
        if (.not. grid%combined_cycle) call draw_text(hdc, side_x, row_y + 118, &
            "Press GT ONLY to enable the GT+HRSG/ST train.", COL_AMBER)
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
        if (grid%combined_cycle) then
            call draw_line(hdc, stack_x, mid_y, stack_x + width / 8, y + 42, COL_RED, 2)
            write(line, '("Stack ",I4," K")') nint(grid%hrsg_stack_T_K)
            call draw_text(hdc, stack_x + width / 8 + 8, y + 34, trim(adjustl(line)), COL_RED)
            write(line, '("Pinch ",F4.1," K  Approach ",F4.1," K")') grid%hrsg_pinch_K, grid%hrsg_approach_K
            call draw_text(hdc, hrsg_x - 16, mid_y + node_h + 18, trim(adjustl(line)), &
                merge(COL_RED, COL_MUTED, grid%alarm_hrsg_pinch))
        else
            call draw_text(hdc, hrsg_x - 16, mid_y + node_h + 18, "HRSG and steam turbine offline", COL_AMBER)
        end if
        bar_y = y + height - 86
        call draw_bar(hdc, x + 28, bar_y, width - 56, 24, "GT", grid%gas_power_MW, max(grid%plant_capacity_MW, 1.0_dp), COL_LIME)
        call draw_bar(hdc, x + 28, bar_y + 36, width - 56, 24, "ST", grid%steam_power_MW, max(grid%plant_capacity_MW, 1.0_dp), COL_BLUE)
    end subroutine draw_cc_heat_balance

    ! HRSG T-Q composite diagram.  Q increases left→right; hot end on left.
    ! Gas line: linear T_exhaust→T_stack.
    ! Water/steam line: piecewise — superheater (diagonal), evaporator (plateau), economizer (diagonal).
    ! Section heats are derived from the same HRSG formulas used by the engine.
    subroutine draw_hrsg_tq_diagram(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        ! HRSG physical constants (mirror of hrsg.f90 parameters)
        real(dp), parameter :: T_SAT    = 515.0_dp    ! K  saturation temperature
        real(dp), parameter :: APPROACH = 8.0_dp      ! K  approach margin (econ exit to sat)
        real(dp), parameter :: CP_W     = 4200.0_dp   ! J/kgK water
        real(dp), parameter :: CP_S     = 2200.0_dp   ! J/kgK steam
        real(dp), parameter :: LH       = 1.55e6_dp   ! J/kg  latent heat evaporation
        real(dp) :: T_gin, T_gout, T_steam, T_feed, Q_total
        real(dp) :: q_ec, q_ev, q_sh_kj, q_tot, frac_sh, frac_sh_ev
        real(dp) :: t_lo, t_hi
        integer :: gx, gy, gw, gh, i, px, py, pxp, pyp
        integer :: px_sh, px_sh_ev, py_sat, py_pinch, py_ref
        character(len=32) :: lbl

        if (height < 50 .or. width < 80) return
        if (.not. grid%combined_cycle) then
            call fill_soft_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
            call draw_text(hdc, x + 16, y + height / 2 - 8, &
                "Enable GT+HRSG mode to view the HRSG T-Q diagram", COL_MUTED)
            return
        end if

        T_gin  = grid%exhaust_K
        T_gout = grid%hrsg_stack_T_K
        T_steam = grid%hrsg_steam_T_K
        T_feed = max(303.15_dp, grid%ambient_C + 305.15_dp)   ! ambient + 32 K
        Q_total = max(grid%hrsg_recovered_heat_MW, 1.0_dp)

        ! Section heat fractions (mirrors hrsg.f90 solve_hrsg)
        q_ec    = CP_W * max(0.0_dp, T_SAT - APPROACH - T_feed)
        q_ev    = LH
        q_sh_kj = CP_S * max(0.0_dp, T_steam - T_SAT)
        q_tot   = max(q_ec + q_ev + q_sh_kj, 1.0_dp)
        frac_sh    = q_sh_kj / q_tot            ! superheater fraction
        frac_sh_ev = (q_sh_kj + q_ev) / q_tot   ! superheater + evaporator fraction

        t_lo = min(T_feed, T_gout) - 30.0_dp
        t_hi = max(T_gin, T_steam) + 30.0_dp

        gx = x + 52;  gy = y + 4
        gw = max(60, width - 60);  gh = max(36, height - 18)

        call fill_soft_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
        call stroke_soft_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)
        call fill_box(hdc, gx, gy, gx + gw, gy + gh, COL_BG)
        call stroke_box(hdc, gx, gy, gx + gw, gy + gh, COL_BORDER_SOFT, 1)

        ! Grid lines
        do i = 1, 3
            call draw_line(hdc, gx, gy + i * gh / 4, gx + gw, gy + i * gh / 4, COL_BG_GRID, 1)
        end do

        ! Section boundary verticals and labels
        px_sh    = gx + nint(frac_sh    * real(gw, dp))
        px_sh_ev = gx + nint(frac_sh_ev * real(gw, dp))
        call draw_line(hdc, px_sh,    gy, px_sh,    gy + gh, COL_BG_GRID, 1)
        call draw_line(hdc, px_sh_ev, gy, px_sh_ev, gy + gh, COL_BG_GRID, 1)
        call draw_text(hdc, gx + 4,               gy + gh - 14, "SH", COL_CYAN)
        call draw_text(hdc, px_sh    + 4,          gy + gh - 14, "EV", COL_CYAN)
        call draw_text(hdc, px_sh_ev + 4,          gy + gh - 14, "EC", COL_CYAN)

        ! T_sat horizontal reference (dashed)
        py_sat = gy + nint((1.0_dp - (T_SAT - t_lo) / (t_hi - t_lo)) * real(gh, dp))
        py_sat = max(gy, min(gy + gh, py_sat))
        do i = gx + 2, gx + gw - 4, 10
            call draw_line(hdc, i, py_sat, min(i + 6, gx + gw - 2), py_sat, COL_MUTED, 1)
        end do
        write(lbl, '("Tsat ",I0,"K")') nint(T_SAT)
        call draw_text(hdc, gx + 4, py_sat - 12, adjustl(lbl), COL_MUTED)

        ! Hot-side (exhaust gas): straight line from (0, T_gin) to (Q_total, T_gout)
        pxp = -1; pyp = -1
        do i = 0, 40
            px = gx + i * gw / 40
            py = gy + nint((1.0_dp - (T_gin + real(i, dp) / 40.0_dp * (T_gout - T_gin) - t_lo) &
                / (t_hi - t_lo)) * real(gh, dp))
            py = max(gy, min(gy + gh, py))
            if (i > 0 .and. pxp >= 0) call draw_line(hdc, pxp, pyp, px, py, COL_RED, 2)
            pxp = px; pyp = py
        end do

        ! Cold-side (water/steam): piecewise three segments
        ! Superheater (Q=0→q_sh_mw): T_steam → T_sat
        pxp = gx
        pyp = gy + nint((1.0_dp - (T_steam - t_lo) / (t_hi - t_lo)) * real(gh, dp))
        pyp = max(gy, min(gy + gh, pyp))
        py = max(gy, min(gy + gh, py_sat))
        call draw_line(hdc, pxp, pyp, px_sh, py, COL_CYAN, 2)
        ! Evaporator (q_sh_mw→q_sh_ev_mw): T_sat plateau
        call draw_line(hdc, px_sh, py, px_sh_ev, py, COL_CYAN, 2)
        ! Economizer (q_sh_ev_mw→Q_total): T_sat → T_feed
        pxp = gy + nint((1.0_dp - (T_feed - t_lo) / (t_hi - t_lo)) * real(gh, dp))
        pxp = max(gy, min(gy + gh, pxp))
        call draw_line(hdc, px_sh_ev, py, gx + gw, pxp, COL_CYAN, 2)

        ! Pinch point annotation (at q_sh_ev_mw, the minimum T approach)
        py_pinch = gy + nint((1.0_dp - (T_SAT + grid%hrsg_pinch_K - t_lo) / (t_hi - t_lo)) &
            * real(gh, dp))
        py_pinch = max(gy, min(gy + gh, py_pinch))
        call draw_line(hdc, px_sh_ev, py_sat, px_sh_ev, py_pinch, COL_AMBER, 1)
        call draw_line(hdc, px_sh_ev, py_pinch, px_sh_ev - 5, py_pinch + 5, COL_AMBER, 1)
        call draw_line(hdc, px_sh_ev, py_pinch, px_sh_ev + 5, py_pinch + 5, COL_AMBER, 1)
        write(lbl, '(F4.1,"K")') grid%hrsg_pinch_K
        call draw_text(hdc, px_sh_ev + 6, (py_sat + py_pinch) / 2 - 6, adjustl(lbl), COL_AMBER)
        call draw_text(hdc, px_sh_ev + 6, (py_sat + py_pinch) / 2 + 6, "pinch", COL_AMBER)

        py_ref = gy + nint((1.0_dp - (T_SAT + grid%physics_hrsg_pinch_ref_K - t_lo) / (t_hi - t_lo)) &
            * real(gh, dp))
        py_ref = max(gy, min(gy + gh, py_ref))
        do i = px_sh_ev - 34, px_sh_ev + 34, 10
            call draw_line(hdc, max(gx, i), py_ref, min(gx + gw, i + 5), py_ref, COL_GREEN, 1)
        end do
        write(lbl, '("ref ",F4.1,"K")') grid%physics_hrsg_pinch_ref_K
        call draw_text(hdc, min(px_sh_ev + 46, gx + gw - 58), py_ref - 9, adjustl(lbl), COL_GREEN)

        ! Axis labels
        call draw_text(hdc, x + 4, gy + gh / 2 - 6, "T(K)", COL_MUTED)
        call draw_text(hdc, gx + gw / 2 - 12, gy + gh + 2, "Q (MW)", COL_MUTED)
        write(lbl, '(F5.1)') Q_total
        call draw_text(hdc, gx + gw - 20, gy + gh + 2, adjustl(lbl), COL_DIM)
        write(lbl, '(I0,"K")') nint(t_lo + 30.0_dp)
        call draw_text(hdc, x + 4, gy + gh - 8, adjustl(lbl), COL_DIM)
        write(lbl, '(I0,"K")') nint(t_hi - 30.0_dp)
        call draw_text(hdc, x + 4, gy + 2, adjustl(lbl), COL_DIM)
        call draw_text(hdc, gx + gw - 52, gy + 8, "-- gas", COL_RED)
        call draw_text(hdc, gx + gw - 76, gy + 22, "-- H2O/stm", COL_CYAN)
    end subroutine draw_hrsg_tq_diagram

    subroutine draw_process_node(hdc, x, y, width, height, label, value, unit_text, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        character(len=*), intent(in) :: label, unit_text
        real(dp), intent(in) :: value
        integer(c_int), intent(in) :: color
        character(len=64) :: text

        call fill_soft_box(hdc, x, y, x + width, y + height, COL_PANEL_DEEP)
        call fill_box(hdc, x, y, x + 5, y + height, color)
        call stroke_soft_box(hdc, x, y, x + width, y + height, color, 1)
        call draw_text(hdc, x + 12, y + 10, label, COL_INK)
        write(text, '(F6.1," ",A)') value, trim(unit_text)
        call draw_text(hdc, x + 12, y + 38, trim(adjustl(text)), color)
    end subroutine draw_process_node

    subroutine draw_market_screen(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: ix, iw, top_y, tile_w, gap, panel_y, left_w, right_x, right_w
        integer :: body_bottom, body_h, top_panel_h, chart_title_y, chart_y, chart_h
        integer :: co2_h, emissions_h, emissions_y
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
        write(value, '("$",I3,"/t")') nint(grid%carbon_price_usd_t)
        call draw_metric_tile(hdc, ix + 2 * (tile_w + gap), top_y + 76, tile_w, 70, "Carbon", trim(adjustl(value)), COL_CYAN)
        write(value, '("$",F5.1,"/MW-h")') grid%fcr_reserve_price_usd_mw_h
        call draw_metric_tile(hdc, ix + 3 * (tile_w + gap), top_y + 76, tile_w, 70, "FCR reserve", trim(adjustl(value)), COL_BLUE)

        panel_y = top_y + 172
        body_bottom = y + height - 18
        body_h = max(1, body_bottom - panel_y)
        if (body_h > 560) then
            top_panel_h = min(320, max(180, body_h * 30 / 100))
        else
            top_panel_h = max(130, body_h * 36 / 100)
        end if
        top_panel_h = min(top_panel_h, max(120, body_h - 200))
        left_w = max(540, int(0.58_dp * real(iw, dp)))
        right_x = ix + left_w + GAP_PANEL
        right_w = max(260, iw - left_w - GAP_PANEL)
        call draw_section_title_width(hdc, ix, panel_y, "Market replay and weather-derived renewable ceiling", left_w)
        call draw_market_profile_panel(hdc, ix, panel_y + 28, left_w, top_panel_h)
        call draw_section_title_width(hdc, right_x, panel_y, "ROI dispatch value stack", right_w)
        call draw_value_stack_compact(hdc, right_x, panel_y + 28, right_w, top_panel_h)

        chart_title_y = panel_y + 28 + top_panel_h + 24
        chart_y = chart_title_y + 28
        chart_h = max(80, body_bottom - chart_y)
        if (chart_h > 220) then
            co2_h = max(110, chart_h * 42 / 100)
        else
            co2_h = max(60, chart_h / 2)
        end if
        co2_h = min(co2_h, max(50, chart_h - 62))
        emissions_y = chart_y + co2_h + 12
        emissions_h = max(50, body_bottom - emissions_y)

        call draw_section_title_width(hdc, ix, chart_title_y, "Cost curve and dispatch merit", left_w)
        call draw_cost_curve_panel(hdc, ix, chart_y, left_w, chart_h)
        call draw_section_title_width(hdc, right_x, chart_title_y, "Emissions & carbon intensity", right_w)
        call draw_co2_intensity_chart(hdc, right_x, chart_y, right_w, co2_h)
        call draw_emissions_kpis(hdc, right_x, emissions_y, right_w, emissions_h)
    end subroutine draw_market_screen

    subroutine draw_market_profile_panel(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: row_y, bx, mid_y
        character(len=96) :: line

        call draw_panel_box(hdc, x, y, width, height)
        row_y = y + PAD_PANEL_Y
        write(line, '("Location ",A,"  lat ",F5.2," lon ",F6.2)') &
            trim(grid%market_profile_name), grid%market_latitude_deg, grid%market_longitude_deg
        call draw_text(hdc, x + PAD_CARD_X, row_y, trim(line), COL_INK)
        row_y = row_y + 28
        write(line, '("Weather ",A,"  wind ",F4.1," m/s  solar ",I4," W/m2")') &
            merge("ON ", "OFF", grid%market_weather_enabled), grid%market_wind_speed_m_s, nint(grid%market_solar_W_m2)
        call draw_text(hdc, x + PAD_CARD_X, row_y, trim(line), COL_MUTED)
        row_y = row_y + 28
        write(line, '("Wind ",F5.1," MW / cap ",F5.1,"  PV ",F5.1," MW / cap ",F5.1)') &
            grid%market_wind_power_MW, grid%market_wind_capacity_MW, &
            grid%market_pv_power_MW, grid%market_pv_capacity_MW
        call draw_text(hdc, x + PAD_CARD_X, row_y, trim(line), COL_GREEN)
        row_y = row_y + 28
        write(line, '("Load replay ",A,"  demand range ",F5.1,"-",F5.1," MW  day ",I5," s")') &
            merge("ON ", "OFF", grid%market_load_replay_enabled), grid%market_base_demand_MW, &
            grid%market_peak_demand_MW, nint(grid%market_replay_day_s)
        call draw_text(hdc, x + PAD_CARD_X, row_y, trim(line), COL_CYAN)
        bx = x + PAD_CARD_X
        if (height > 245) then
            mid_y = y + 132
            call draw_text(hdc, bx, mid_y, "Renewable availability mix", COL_MUTED)
            call draw_bar(hdc, bx, mid_y + 24, width - 24, 20, "Wind", &
                grid%market_wind_power_MW, max(grid%market_wind_capacity_MW, 1.0_dp), COL_GREEN)
            call draw_bar(hdc, bx, mid_y + 54, width - 24, 20, "PV", &
                grid%market_pv_power_MW, max(grid%market_pv_capacity_MW, 1.0_dp), COL_CYAN)
            if (height > 310) call draw_bar(hdc, bx, mid_y + 84, width - 24, 20, "RES headroom", &
                renewable_headroom_MW(grid), RENEWABLE_MAX_MW, COL_AMBER)
        end if
        call draw_bar(hdc, bx, y + height - 66, width - 2 * PAD_CARD_X, 22, &
            "RES available", grid%renewable_MW, RENEWABLE_MAX_MW, COL_GREEN)
        call draw_bar(hdc, bx, y + height - 34, width - 2 * PAD_CARD_X, 22, &
            "Demand", grid%demand_MW, DEMAND_MAX_MW, COL_RED)
    end subroutine draw_market_profile_panel

    subroutine draw_value_stack_compact(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: row_y
        character(len=96) :: line
        integer(c_int) :: margin_color

        margin_color = merge(COL_GREEN, COL_RED, grid%value_stack_usd_h >= 0.0_dp)
        call draw_panel_box(hdc, x, y, width, height)
        row_y = y + PAD_PANEL_Y
        write(line, '("$ ",I0,"/h")') nint(grid%revenue_usd_h)
        call draw_value_pair(hdc, x + PAD_CARD_X, row_y, "Revenue", trim(adjustl(line)), COL_GREEN)
        row_y = row_y + 25
        write(line, '("$ ",I0,"/h")') nint(grid%fuel_cost_usd_h + grid%co2_cost_usd_h)
        call draw_value_pair(hdc, x + PAD_CARD_X, row_y, "Fuel + carbon", trim(adjustl(line)), COL_AMBER)
        row_y = row_y + 25
        write(line, '("$ ",I0,"/h")') nint(grid%imbalance_penalty_usd_h)
        call draw_value_pair(hdc, x + PAD_CARD_X, row_y, "Penalty", trim(adjustl(line)), COL_RED)
        row_y = row_y + 25
        write(line, '("$ ",I0,"/h")') nint(grid%value_stack_usd_h)
        call draw_value_pair(hdc, x + PAD_CARD_X, row_y, "Net value", trim(adjustl(line)), margin_color)
        if (height > 130) then
            row_y = row_y + 25
            write(line, '("HR ",I6," kJ/kWh  CO2 ",F5.2," kg/s")') nint(grid%heat_rate_kJ_kWh), grid%CO2_rate_kg_s
            call draw_text(hdc, x + PAD_CARD_X, row_y, trim(adjustl(line)), COL_MUTED)
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
        call draw_panel_box(hdc, x, y, width, height)
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
        write(label, '("LMP $",F6.1,"/MWh  net margin $",I0,"/h")') &
            merge(grid%fleet_lmp_usd_MWh, grid%power_price_usd_mwh, grid%fleet_mode), nint(grid%margin_usd_h)
        call draw_text(hdc, gx + 8, y + 8, trim(adjustl(label)), COL_INK)
        call draw_text(hdc, gx, gy + gh + 8, "low cost", COL_DIM)
        call draw_text(hdc, gx + gw - 72, gy + gh + 8, "scarcity", COL_DIM)
    end subroutine draw_cost_curve_panel

    ! CO₂ intensity gauge with EU ETS benchmark lines.
    ! Horizontal bar 0–1000 g/kWh; color zones; live marker; reference lines.
    subroutine draw_co2_intensity_chart(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        real(dp), parameter :: SCALE_MAX   = 1000.0_dp  ! g/kWh axis maximum
        real(dp), parameter :: REF_CCGT    = 340.0_dp   ! CCGT best-in-class
        real(dp), parameter :: REF_ETS     = 550.0_dp   ! EU ETS benchmark / directive limit
        real(dp), parameter :: REF_COAL    = 820.0_dp   ! average hard coal CCPP
        integer, parameter  :: BAR_H       = 22
        integer :: gx, gy, gw, bx_live, bx_ccgt, bx_ets, bx_coal
        integer :: zone_amber, zone_red, bar_y, row_y
        integer(c_int) :: intensity_color
        real(dp) :: intensity, annual_t, ets_cost_usd_h
        character(len=64) :: lbl

        if (height < 40 .or. width < 80) return
        call draw_panel_box(hdc, x, y, width, height)

        intensity = max(0.0_dp, min(SCALE_MAX, grid%CO2_intensity_g_kWh))
        intensity_color = merge(COL_RED, merge(COL_AMBER, COL_GREEN, intensity > 400.0_dp), intensity > 600.0_dp)

        ! Header: live value
        write(lbl, '(F6.1," g CO2/kWh")') intensity
        call draw_text(hdc, x + 12, y + 8, "CO2 intensity:", COL_MUTED)
        call draw_text(hdc, x + 142, y + 8, trim(adjustl(lbl)), intensity_color)

        ! Gauge axis
        gx = x + 12
        gy = y + 28
        gw = width - 24
        bar_y = gy + 4

        ! Background: three color zones
        zone_amber = gx + nint(400.0_dp / SCALE_MAX * real(gw, dp))
        zone_red   = gx + nint(600.0_dp / SCALE_MAX * real(gw, dp))
        call fill_box(hdc, gx, bar_y, zone_amber, bar_y + BAR_H, int(Z'00104010', c_int))
        call fill_box(hdc, zone_amber, bar_y, zone_red, bar_y + BAR_H, int(Z'00105040', c_int))
        call fill_box(hdc, zone_red, bar_y, gx + gw, bar_y + BAR_H, int(Z'00102040', c_int))

        ! Live fill
        bx_live = gx + nint(clamp_real(intensity, 0.0_dp, SCALE_MAX) / SCALE_MAX * real(gw, dp))
        call fill_box(hdc, gx, bar_y, bx_live, bar_y + BAR_H, intensity_color)

        ! Outline
        call stroke_soft_box(hdc, gx, bar_y, gx + gw, bar_y + BAR_H, COL_BORDER_SOFT, 1)

        ! Benchmark lines
        bx_ccgt = gx + nint(REF_CCGT / SCALE_MAX * real(gw, dp))
        bx_ets  = gx + nint(REF_ETS  / SCALE_MAX * real(gw, dp))
        bx_coal = gx + nint(REF_COAL / SCALE_MAX * real(gw, dp))
        call draw_line(hdc, bx_ccgt, bar_y - 2, bx_ccgt, bar_y + BAR_H + 2, COL_LIME, 1)
        call draw_line(hdc, bx_ets,  bar_y - 2, bx_ets,  bar_y + BAR_H + 2, COL_AMBER, 2)
        call draw_line(hdc, bx_coal, bar_y - 2, bx_coal, bar_y + BAR_H + 2, COL_RED,   1)
        call draw_text(hdc, bx_ccgt - 8, bar_y - 14, "CCGT", COL_LIME)
        call draw_text(hdc, bx_ets  - 10, bar_y - 14, "ETS", COL_AMBER)
        call draw_text(hdc, bx_coal - 10, bar_y - 14, "coal", COL_RED)
        ! Axis labels
        call draw_text(hdc, gx, bar_y + BAR_H + 4, "0", COL_DIM)
        call draw_text(hdc, gx + gw / 2 - 8, bar_y + BAR_H + 4, "500", COL_DIM)
        call draw_text(hdc, gx + gw - 24, bar_y + BAR_H + 4, "1000", COL_DIM)
        call draw_text(hdc, gx + gw / 2 - 20, bar_y + BAR_H + 16, "g CO2/kWh", COL_MUTED)

        ! Secondary info row
        row_y = bar_y + BAR_H + 34
        annual_t = grid%CO2_rate_kg_s * 3600.0_dp * 8760.0_dp / 1000.0_dp  ! tonnes/yr
        ets_cost_usd_h = grid%CO2_rate_kg_s * 3600.0_dp * grid%carbon_price_usd_t / 1000.0_dp
        write(lbl, '("Rate ",F5.2," kg/s  |  ETS $",I0,"/h  |  Annual ",I0," t/yr")') &
            grid%CO2_rate_kg_s, nint(ets_cost_usd_h), nint(annual_t)
        call draw_text(hdc, x + 12, row_y, trim(adjustl(lbl)), COL_MUTED)
        if (height > 100) then
            row_y = row_y + 18
            write(lbl, '("Cumulative ",F8.1," t  |  Carbon cost $",I0,"/h")') &
                grid%CO2_cumulative_t, nint(ets_cost_usd_h)
            call draw_text(hdc, x + 12, row_y, trim(adjustl(lbl)), COL_DIM)
        end if
    end subroutine draw_co2_intensity_chart

    ! Stack gas KPIs from the P3 combustion-chemistry model, corrected to 15% O2.
    subroutine draw_emissions_kpis(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        real(dp) :: lambda, o2_dry_pct, co2_vol_pct
        real(dp) :: nox_ppm, nox_corr_mg, co_ppm, co_corr_mg
        integer  :: row_y, bar_max, bx_live, bx_ccgt, bx_coal
        integer(c_int) :: nox_col, co_col
        character(len=64) :: lbl

        if (height < 40 .or. width < 80) return
        call draw_panel_box(hdc, x, y, width, height)

        lambda     = grid%combustion_lambda
        o2_dry_pct = grid%stack_o2_dry_pct
        co2_vol_pct = grid%stack_co2_vol_pct
        nox_ppm = grid%nox_ppm_15o2
        nox_corr_mg = grid%nox_mg_nm3_15o2
        co_ppm = grid%co_ppm_15o2
        co_corr_mg = grid%co_mg_nm3_15o2

        nox_col = merge(COL_RED,   merge(COL_AMBER, COL_GREEN, nox_corr_mg > 50.0_dp),  nox_corr_mg > 100.0_dp)
        co_col  = merge(COL_RED,   merge(COL_AMBER, COL_GREEN, co_corr_mg  > 50.0_dp),  co_corr_mg  > 100.0_dp)

        ! Display
        call draw_text(hdc, x + 12, y + 8, "Stack gases  (EN ISO 11042, 15% O2 ref)", COL_MUTED)
        row_y = y + 28
        write(lbl, '("CO2  ",F4.1," vol%  (stack)")') co2_vol_pct
        call draw_text(hdc, x + 12, row_y, trim(adjustl(lbl)), COL_CYAN)
        row_y = row_y + 20
        write(lbl, '("O2   ",F4.1," %  lambda ",F4.2)') o2_dry_pct, lambda
        call draw_text(hdc, x + 12, row_y, trim(adjustl(lbl)), COL_MUTED)
        row_y = row_y + 20
        write(lbl, '("NOx  ",F5.1," mg/Nm3  (",F4.1," ppm @15%)")') nox_corr_mg, nox_ppm
        call draw_text(hdc, x + 12, row_y, trim(adjustl(lbl)), nox_col)
        row_y = row_y + 20
        write(lbl, '("CO   ",F5.1," mg/Nm3  (",F4.1," ppm @15%)")') co_corr_mg, co_ppm
        call draw_text(hdc, x + 12, row_y, trim(adjustl(lbl)), co_col)

        ! Comparison bar: live vs benchmarks (g CO₂/kWh)
        if (height > 120) then
            row_y = row_y + 30
            call draw_text(hdc, x + 12, row_y - 14, "Carbon intensity comparison:", COL_MUTED)
            bar_max = width - 110
            ! Live
            bx_live = x + 96 + min(bar_max, nint(clamp_real( &
                grid%CO2_intensity_g_kWh, 0.0_dp, 1000.0_dp) / 1000.0_dp * real(bar_max, dp)))
            call fill_soft_box(hdc, x + 96, row_y, x + 96 + bar_max, row_y + 16, COL_PANEL_DEEP)
            if (bx_live > x + 96) call fill_soft_box(hdc, x + 96, row_y, bx_live, row_y + 16, intensity_color_fn(grid%CO2_intensity_g_kWh))
            call stroke_soft_box(hdc, x + 96, row_y, x + 96 + bar_max, row_y + 16, COL_BORDER_SOFT, 1)
            write(lbl, '(I4)') nint(grid%CO2_intensity_g_kWh)
            call draw_text(hdc, bx_live + 3, row_y + 1, trim(adjustl(lbl)), COL_INK)
            call draw_text(hdc, x + 12, row_y + 1, "Live", COL_MUTED)
            ! CCGT best
            row_y = row_y + 22
            bx_ccgt = x + 96 + nint(340.0_dp / 1000.0_dp * real(bar_max, dp))
            call fill_soft_box(hdc, x + 96, row_y, x + 96 + bar_max, row_y + 16, COL_PANEL_DEEP)
            call fill_soft_box(hdc, x + 96, row_y, bx_ccgt, row_y + 16, COL_LIME)
            call stroke_soft_box(hdc, x + 96, row_y, x + 96 + bar_max, row_y + 16, COL_BORDER_SOFT, 1)
            call draw_text(hdc, bx_ccgt + 3, row_y + 1, "340", COL_INK)
            call draw_text(hdc, x + 12, row_y + 1, "CCGT*", COL_LIME)
            ! Coal
            row_y = row_y + 22
            bx_coal = x + 96 + nint(820.0_dp / 1000.0_dp * real(bar_max, dp))
            call fill_soft_box(hdc, x + 96, row_y, x + 96 + bar_max, row_y + 16, COL_PANEL_DEEP)
            call fill_soft_box(hdc, x + 96, row_y, bx_coal, row_y + 16, COL_RED)
            call stroke_soft_box(hdc, x + 96, row_y, x + 96 + bar_max, row_y + 16, COL_BORDER_SOFT, 1)
            call draw_text(hdc, bx_coal + 3, row_y + 1, "820", COL_INK)
            call draw_text(hdc, x + 12, row_y + 1, "Coal", COL_RED)
            call draw_text(hdc, x + 12, row_y + 22, "*g CO2/kWh", COL_DIM)
        end if
    end subroutine draw_emissions_kpis

    ! Returns a color appropriate for the given CO₂ intensity value.
    pure function intensity_color_fn(intens) result(col)
        real(dp), intent(in) :: intens
        integer(c_int) :: col
        if (intens > 600.0_dp) then
            col = COL_RED
        else if (intens > 400.0_dp) then
            col = COL_AMBER
        else
            col = COL_GREEN
        end if
    end function intensity_color_fn

    subroutine draw_trends_screen(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: ix, iw, top_y, right_w, main_w, right_x
        character(len=96) :: subtitle, value

        ix = x + 18
        iw = width - 36
        top_y = y + 8
        write(subtitle, '("Rolling ",I0," sample buffer | trend sample 250 ms | render ",I0," ms")') &
            HISTORY_N, int(TIMER_MS)
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
        ! [5.0-A4] Fixed comfortable rows (were stretched to ~120 px, two-thirds empty);
        ! the reclaimed space below carries an ISA-18.2 alarm-performance KPI strip.
        call draw_section_title_width(hdc, ix, btn_y + 54, "Alarm list", table_w)
        block
            integer :: list_h, kp_y, kp_w, kp_gap, kc, nP1, nP2
            character(len=16) :: vtxt
            row_h  = 48
            list_h = 40 + ALARM_COUNT * row_h + 12
            call draw_panel_box(hdc, ix, btn_y + 82, table_w, list_h)
            call draw_text(hdc, ix + 12,  btn_y + 96, "Priority",        COL_MUTED)
            call draw_text(hdc, ix + 96,  btn_y + 96, "Alarm",           COL_MUTED)
            call draw_text(hdc, ix + 306, btn_y + 96, "State",           COL_MUTED)
            call draw_text(hdc, ix + 410, btn_y + 96, "Operator action", COL_MUTED)
            row_y = btn_y + 122
            do i = 1, ALARM_COUNT
                call draw_alarm_row(hdc, ix + 8, row_y, table_w - 16, row_h - 4, i, labels(i), states(i), colors(i))
                row_y = row_y + row_h
            end do

            nP1 = 0;  nP2 = 0
            do i = 1, ALARM_COUNT
                if (states(i)) then
                    if (trim(alarm_priority_text(i)) == "P1") then;  nP1 = nP1 + 1
                    else;  nP2 = nP2 + 1;  end if
                end if
            end do
            kp_gap = GAP_CARD
            kp_w   = (table_w - 16 - 3 * kp_gap) / 4
            kp_y   = btn_y + 82 + list_h + 32
            call draw_section_title_width(hdc, ix, btn_y + 82 + list_h + 8, "Alarm performance  (ISA-18.2)", table_w)
            write(vtxt, '(I0)') active_count
            call draw_kpi_card(hdc, ix,                   kp_y, kp_w, 76, "STANDING", trim(vtxt), merge(COL_RED, COL_GREEN, active_count > 0))
            write(vtxt, '(I0)') count(alarm_seen .and. .not. alarm_ack)
            kc = ix + (kp_w + kp_gap)
            call draw_kpi_card(hdc, kc,                   kp_y, kp_w, 76, "UNACK", trim(vtxt), merge(COL_AMBER, COL_GREEN, any(alarm_seen .and. .not. alarm_ack)))
            write(vtxt, '(I0)') count(alarm_shelved)
            kc = ix + 2 * (kp_w + kp_gap)
            call draw_kpi_card(hdc, kc,                   kp_y, kp_w, 76, "SHELVED", trim(vtxt), merge(COL_CYAN, COL_MUTED, any(alarm_shelved)))
            write(vtxt, '(I0," P1 / ",I0," P2")') nP1, nP2
            kc = ix + 3 * (kp_w + kp_gap)
            call draw_kpi_card(hdc, kc,                   kp_y, kp_w, 76, "BY PRIORITY", trim(adjustl(vtxt)), merge(COL_RED, COL_MUTED, nP1 > 0))
        end block

        ! [5.0-A4] Right column: live ISA-18.2 state summary above the chronological log
        ! (the log alone was a tall, empty panel during calm operation).
        call draw_section_title_width(hdc, log_x, btn_y + 54, "Alarm state summary", log_w)
        block
            integer :: sy, log_top
            call draw_panel_box(hdc, log_x, btn_y + 82, log_w, 196)
            sy = btn_y + 96
            call draw_value_pair(hdc, log_x + 12, sy, "Configured points", "8", COL_INK);  sy = sy + 26
            write(line, '(I0)') active_count
            call draw_value_pair(hdc, log_x + 12, sy, "Standing alarms", trim(adjustl(line)), merge(COL_RED, COL_GREEN, active_count > 0));  sy = sy + 26
            write(line, '(I0)') count(alarm_seen .and. .not. alarm_ack)
            call draw_value_pair(hdc, log_x + 12, sy, "Unacknowledged", trim(adjustl(line)), merge(COL_AMBER, COL_MUTED, any(alarm_seen .and. .not. alarm_ack)));  sy = sy + 26
            write(line, '(I0)') count(alarm_shelved)
            call draw_value_pair(hdc, log_x + 12, sy, "Shelved", trim(adjustl(line)), merge(COL_CYAN, COL_MUTED, any(alarm_shelved)));  sy = sy + 26
            write(line, '(I0)') alarm_log_count
            call draw_value_pair(hdc, log_x + 12, sy, "Events this run", trim(adjustl(line)), COL_MUTED);  sy = sy + 26
            line = "None"
            do i = 1, ALARM_COUNT
                if (states(i)) then;  line = labels(i);  exit;  end if
            end do
            call draw_value_pair(hdc, log_x + 12, sy, "Highest standing", trim(line), merge(COL_RED, COL_GREEN, active_count > 0))

            log_top = btn_y + 82 + 196 + 46
            call draw_section_title_width(hdc, log_x, btn_y + 82 + 196 + 18, "Chronological log", log_w)
            call draw_panel_box(hdc, log_x, log_top, log_w, y + height - 18 - log_top)
            row_y = log_top + 16
            do i = max(1, alarm_log_count - 14), alarm_log_count
                if (i < 1) cycle
                state_color = alarm_state_color_text(alarm_log_state(i))
                write(line, '(F7.1,"s  ",A,"  ",A)') alarm_log_time(i), trim(alarm_log_state(i)), trim(alarm_log_name(i))
                call draw_text(hdc, log_x + 12, row_y, trim(adjustl(line)), state_color)
                row_y = row_y + 24
            end do
            if (alarm_log_count == 0) call draw_text(hdc, log_x + 12, row_y, "No alarm events this run.", COL_DIM)
        end block
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
        call fill_soft_box(hdc, x, y, x + width, y + height, body)
        call fill_box(hdc, x, y, x + 5, y + height, merge(color, COL_BORDER_SOFT, alarm_seen(alarm_id)))
        call stroke_soft_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)
        call draw_text(hdc, x + 12, y + 8, alarm_priority_text(alarm_id), merge(color, COL_MUTED, alarm_seen(alarm_id)))
        call draw_text(hdc, x + 96, y + 8, label, merge(COL_INK, COL_MUTED, alarm_seen(alarm_id)))
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

    ! =========================================================================
    ! F8 Diagnostics screen — health tiles, performance gap, fault log
    ! =========================================================================

    subroutine draw_diagnostics_screen(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: ix, iw, top_y, tile_w, gap, tiles_y
        integer :: left_w, right_x, right_w, mid_y, perf_h, gantt_y, gantt_h, watch_y, watch_h, panel_bottom
        integer :: active_alarm_count, score_comp, score_comb, score_turb
        integer :: score_hrsg, score_steam, score_bess
        character(len=32) :: status_comp, status_comb, status_turb
        character(len=32) :: status_hrsg, status_steam, status_bess
        character(len=96) :: subtitle
        integer(c_int) :: col_comp, col_comb, col_turb, col_hrsg, col_steam, col_bess

        ix     = x + 18
        iw     = width - 36
        top_y  = y + 8

        ! Count active alarms for subtitle
        active_alarm_count = 0
        if (grid%alarm_surge)       active_alarm_count = active_alarm_count + 1
        if (grid%alarm_turbine_max) active_alarm_count = active_alarm_count + 1
        if (grid%alarm_ufls_active) active_alarm_count = active_alarm_count + 1
        if (grid%alarm_underfreq)   active_alarm_count = active_alarm_count + 1
        if (grid%alarm_overfreq)    active_alarm_count = active_alarm_count + 1
        if (grid%alarm_hrsg_pinch)  active_alarm_count = active_alarm_count + 1
        if (grid%alarm_low_reserve) active_alarm_count = active_alarm_count + 1
        if (grid%alarm_low_soc)     active_alarm_count = active_alarm_count + 1
        write(subtitle, '(I0," active alarm(s)  |  GT eta ",F4.1,"%  |  SM ",F4.1,"%  |  t+",I0,"s")') &
            active_alarm_count, grid%gt_thermal_efficiency * 100.0_dp, grid%surge_margin_pct, nint(grid%elapsed_s)
        call draw_screen_caption(hdc, ix, top_y, iw, SCREEN_FULL_LABEL(SCREEN_DIAG), trim(adjustl(subtitle)))

        ! --- Component health scores ---
        ! Compressor
        score_comp = 100
        if (grid%surge_margin_pct < 15.0_dp) &
            score_comp = score_comp - min(40, nint((15.0_dp - grid%surge_margin_pct) / 15.0_dp * 40.0_dp))
        if (grid%alarm_surge) score_comp = score_comp - 30
        score_comp = max(0, score_comp)
        if (grid%alarm_surge) then
            write(status_comp, '("SURGE  SM ",F4.1,"%")') grid%surge_margin_pct
        else
            write(status_comp, '("SM ",F4.1,"%  PR ",F4.1)') grid%surge_margin_pct, grid%PR_op
        end if
        col_comp = health_color(score_comp)

        ! Combustor
        score_comb = 100
        if (grid%TIT_actual_K > 1480.0_dp) &
            score_comb = score_comb - min(40, nint((grid%TIT_actual_K - 1480.0_dp) / 20.0_dp * 40.0_dp))
        if (grid%alarm_turbine_max) score_comb = score_comb - 25
        score_comb = max(0, score_comb)
        if (grid%alarm_turbine_max) then
            write(status_comb, '("TIT MAX  ",I4,"K")') nint(grid%TIT_actual_K)
        else
            write(status_comb, '("TIT",I4,"K ",F4.2,"kg/s")') nint(grid%TIT_actual_K), grid%fuel_flow_kg_s
        end if
        col_comb = health_color(score_comb)

        ! Turbine
        score_turb = 100
        if (grid%exhaust_K > 900.0_dp) &
            score_turb = score_turb - min(30, nint((grid%exhaust_K - 900.0_dp) / 50.0_dp * 30.0_dp))
        if (grid%alarm_turbine_max) score_turb = score_turb - 30
        if (grid%gt_thermal_efficiency < 0.33_dp) &
            score_turb = score_turb - nint((0.33_dp - grid%gt_thermal_efficiency) / 0.33_dp * 25.0_dp)
        score_turb = max(0, score_turb)
        write(status_turb, '("eta",F4.1,"% Tx",I3,"K")') &
            grid%gt_thermal_efficiency * 100.0_dp, nint(grid%exhaust_K)
        col_turb = health_color(score_turb)

        ! HRSG
        if (.not. grid%combined_cycle) then
            score_hrsg = 100
            write(status_hrsg, '("N/A — simple cycle")')
            col_hrsg = COL_DIM
        else
            score_hrsg = 100
            if (grid%alarm_hrsg_pinch) score_hrsg = score_hrsg - 35
            if (grid%hrsg_pinch_K < 10.0_dp) &
                score_hrsg = score_hrsg - min(25, nint((10.0_dp - grid%hrsg_pinch_K) / 10.0_dp * 25.0_dp))
            if (grid%hrsg_stack_T_K > 450.0_dp) &
                score_hrsg = score_hrsg - min(20, nint((grid%hrsg_stack_T_K - 450.0_dp) / 50.0_dp * 20.0_dp))
            score_hrsg = max(0, score_hrsg)
            write(status_hrsg, '("pnch",F4.1,"K stk",I3,"K")') grid%hrsg_pinch_K, nint(grid%hrsg_stack_T_K)
            col_hrsg = health_color(score_hrsg)
        end if

        ! Steam turbine
        if (.not. grid%combined_cycle) then
            score_steam = 100
            write(status_steam, '("N/A — simple cycle")')
            col_steam = COL_DIM
        else
            score_steam = 100
            if (grid%steam_power_MW < grid%steam_power_target_MW * 0.9_dp) score_steam = score_steam - 20
            if (grid%hrsg_steam_pressure_bar < 30.0_dp) score_steam = score_steam - 15
            score_steam = max(0, score_steam)
            write(status_steam, '(F4.1,"/",F4.1,"MW",I3,"b")') &
                grid%steam_power_MW, grid%steam_power_target_MW, nint(grid%hrsg_steam_pressure_bar)
            col_steam = health_color(score_steam)
        end if

        ! BESS
        score_bess = 100
        if (grid%alarm_low_soc) score_bess = score_bess - 30
        if (grid%battery_soc_pct < 20.0_dp) &
            score_bess = score_bess - min(30, nint((20.0_dp - grid%battery_soc_pct) / 20.0_dp * 30.0_dp))
        if (grid%bess_degradation_cost_usd_h > 20.0_dp) score_bess = score_bess - 15
        score_bess = max(0, score_bess)
        write(status_bess, '("SoC ",F4.1,"%  ",SP,F5.1,"MW")') &
            grid%battery_soc_pct, grid%BESS_primary_MW
        col_bess = health_color(score_bess)

        ! --- Draw health tiles row ---
        tiles_y = top_y + 76
        gap     = 10
        tile_w  = (iw - 5 * gap) / 6
        call draw_health_tile(hdc, ix,                    tiles_y, tile_w, 70, "COMPRESSOR", score_comp, status_comp, col_comp)
        call draw_health_tile(hdc, ix + tile_w + gap,     tiles_y, tile_w, 70, "COMBUSTOR",  score_comb, status_comb, col_comb)
        call draw_health_tile(hdc, ix + 2*(tile_w+gap),   tiles_y, tile_w, 70, "TURBINE",    score_turb, status_turb, col_turb)
        call draw_health_tile(hdc, ix + 3*(tile_w+gap),   tiles_y, tile_w, 70, "HRSG",       score_hrsg, status_hrsg, col_hrsg)
        call draw_health_tile(hdc, ix + 4*(tile_w+gap),   tiles_y, tile_w, 70, "STEAM",      score_steam, status_steam, col_steam)
        call draw_health_tile(hdc, ix + 5*(tile_w+gap),   tiles_y, tile_w, 70, "BESS",       score_bess, status_bess, col_bess)

        ! --- Mid: performance gap (left) + fault log (right) ---
        mid_y   = tiles_y + 88
        left_w  = max(400, iw * 55 / 100)
        right_x = ix + left_w + 18
        right_w = max(300, iw - left_w - 18)

        panel_bottom = y + height - 18
        perf_h = min(260, max(190, (panel_bottom - (mid_y + 28)) * 38 / 100))
        call draw_section_title_width(hdc, ix, mid_y, "Performance gap  (live vs design point)", left_w)
        call draw_perf_gap_panel(hdc, ix, mid_y + 28, left_w, perf_h)

        gantt_y = mid_y + 28 + perf_h + 34
        gantt_h = 128
        call draw_section_title_width(hdc, ix, gantt_y - 26, "Predictive maintenance  (running hours)", left_w)
        call draw_maintenance_gantt(hdc, ix, gantt_y, left_w, gantt_h)

        watch_y = gantt_y + gantt_h + 34
        watch_h = max(80, panel_bottom - watch_y)
        call draw_section_title_width(hdc, ix, watch_y - 26, "Maintenance watch", left_w)
        call draw_maintenance_watch(hdc, ix, watch_y, left_w, watch_h)

        ! Right: grid code compliance (112px) + LCF life bars (100px) + fault log (remainder)
        call draw_section_title_width(hdc, right_x, mid_y, "Grid code  (ENTSO-E RfG)", right_w)
        call draw_grid_compliance_panel(hdc, right_x, mid_y + 28, right_w, 112)
        call draw_section_title_width(hdc, right_x, mid_y + 154, "Hot-parts LCF life consumed", right_w)
        call draw_lcf_bars(hdc, right_x, mid_y + 180, right_w, 96)
        call draw_section_title_width(hdc, right_x, mid_y + 290, "Active faults  (ISA-18.2)", right_w)
        call draw_fault_log(hdc, right_x, mid_y + 318, right_w, max(80, panel_bottom - (mid_y + 318)))
    end subroutine draw_diagnostics_screen

    ! ENTSO-E RfG / LFSM-O compliance status panel (4 checks, compact).
    subroutine draw_grid_compliance_panel(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: row_y, bx
        integer(c_int) :: col
        real(dp) :: rsv_mw, rsv_pct
        character(len=40) :: val_s

        call fill_soft_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
        call stroke_soft_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)
        row_y = y + 8
        bx    = x + 12

        ! RoCoF <= 2 Hz/s (ENTSO-E RfG Art. 14)
        col = merge(COL_GREEN, COL_RED, abs(grid%ROCOF_Hz_s) <= 2.0_dp)
        write(val_s, '(F5.3," Hz/s  ",A)') grid%ROCOF_Hz_s, &
            merge("OK  ", "TRIP", abs(grid%ROCOF_Hz_s) <= 2.0_dp)
        call draw_value_pair(hdc, bx, row_y, "RoCoF lim", trim(adjustl(val_s)), col)
        row_y = row_y + 18

        ! Frequency normal operating range
        if (grid%frequency_Hz >= 49.5_dp .and. grid%frequency_Hz <= 50.5_dp) then
            col = COL_GREEN
        else if (grid%frequency_Hz >= 49.0_dp .and. grid%frequency_Hz <= 51.0_dp) then
            col = COL_AMBER
        else
            col = COL_RED
        end if
        write(val_s, '(F6.3," Hz")') grid%frequency_Hz
        call draw_value_pair(hdc, bx, row_y, "Freq band", trim(adjustl(val_s)), col)
        row_y = row_y + 18

        ! Spinning reserve >= 5 % demand
        rsv_mw  = merge(grid%fleet_reserve_MW, grid%reserve_MW, grid%fleet_mode)
        rsv_pct = 100.0_dp * rsv_mw / max(grid%demand_MW, 1.0_dp)
        if (rsv_pct >= 5.0_dp) then; col = COL_GREEN
        else if (rsv_pct >= 2.0_dp) then; col = COL_AMBER
        else; col = COL_RED; end if
        write(val_s, '(F4.1,"% (",F5.1," MW)")') rsv_pct, rsv_mw
        call draw_value_pair(hdc, bx, row_y, "Reserve", trim(adjustl(val_s)), col)
        row_y = row_y + 18

        ! UFLS / LFSM-O
        if (grid%alarm_ufls_active) then
            call draw_value_pair(hdc, bx, row_y, "UFLS", "ACTIVE  load shedding", COL_RED)
        else if (grid%alarm_underfreq) then
            call draw_value_pair(hdc, bx, row_y, "LFSM-O", "under-freq  governor", COL_AMBER)
        else
            call draw_value_pair(hdc, bx, row_y, "LFSM-O", "normal  compliant", COL_GREEN)
        end if
    end subroutine draw_grid_compliance_panel

    ! Single component health tile: label + score + bar + status line.
    subroutine draw_health_tile(hdc, x, y, width, height, label, score, status_msg, bar_color)
        type(c_ptr), value :: hdc
        integer, intent(in)          :: x, y, width, height, score
        character(len=*), intent(in) :: label, status_msg
        integer(c_int), intent(in)   :: bar_color
        integer :: bar_w, bar_px, arc_cx, arc_cy, arc_r
        character(len=8) :: score_str

        call fill_soft_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
        ! Colored top accent stripe
        call fill_box(hdc, x, y, x + width, y + 3, bar_color)
        call stroke_soft_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)

        call draw_text(hdc, x + 8, y + 8, label, COL_MUTED)

        ! Circular arc score indicator (top-right corner)
        arc_r  = 14
        arc_cx = x + width - arc_r - 8
        arc_cy = y + arc_r + 10
        ! Track arc
        call hmi_draw_arc(hdc, int(arc_cx,c_int), int(arc_cy,c_int), int(arc_r,c_int), &
            -225.0_c_float, 270.0_c_float, COL_BG_GRID, 3_c_int)
        ! Score arc (sweeps 270 * score/100 degrees)
        call hmi_draw_arc(hdc, int(arc_cx,c_int), int(arc_cy,c_int), int(arc_r,c_int), &
            -225.0_c_float, real(270 * score / 100, c_float), bar_color, 3_c_int)
        write(score_str, '(I0)') score
        call draw_text(hdc, arc_cx - len_trim(score_str)*4, arc_cy - 7, &
            trim(adjustl(score_str)), bar_color)

        ! Health bar — rounded pill style
        bar_w  = width - 16
        bar_px = max(2, nint(real(score, dp) / 100.0_dp * real(bar_w, dp)))
        call fill_soft_box(hdc, x + 8, y + 38, x + 8 + bar_w, y + 50, COL_PANEL_DEEP)
        call fill_soft_box(hdc, x + 8, y + 38, x + 8 + bar_px, y + 50, bar_color)
        call stroke_soft_box(hdc, x + 8, y + 38, x + 8 + bar_w, y + 50, COL_BORDER_SOFT, 1)

        ! Status text
        call draw_text(hdc, x + 8, y + 56, trim(status_msg), COL_INK)
    end subroutine draw_health_tile

    ! Performance gap panel: 5 KPIs, each with deviation bar and pct gap.
    subroutine draw_perf_gap_panel(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        real(dp), parameter :: HR_DESIGN   = 9200.0_dp   ! kJ/kWh, lower is better
        real(dp), parameter :: ETA_DESIGN  = 39.0_dp     ! GT thermal efficiency %
        real(dp), parameter :: SM_DESIGN   = 25.0_dp     ! surge margin %
        real(dp), parameter :: PR_DESIGN   = 15.0_dp     ! pressure ratio
        integer, parameter  :: N_KPI = 5
        real(dp) :: actual(N_KPI), design(N_KPI), gap_pct(N_KPI)
        integer  :: kpi_color(N_KPI)
        logical  :: lower_better(N_KPI)
        character(len=18) :: kpi_label(N_KPI)
        character(len=20) :: act_str(N_KPI), des_str(N_KPI), gap_str(N_KPI)
        integer :: row_y, i, bx, bar_w, bar_half, bar_px, mid_x
        integer(c_int) :: col

        call fill_soft_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
        call stroke_soft_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)

        ! Build KPI data
        lower_better = [.true., .false., .false., .false., .false.]
        kpi_label(1) = "Heat rate";      actual(1) = grid%gt_heat_rate_kJ_kWh;          design(1) = HR_DESIGN
        kpi_label(2) = "GT efficiency";  actual(2) = grid%gt_thermal_efficiency * 100.0_dp; design(2) = ETA_DESIGN
        kpi_label(3) = "Surge margin";   actual(3) = grid%surge_margin_pct;               design(3) = SM_DESIGN
        kpi_label(4) = "Press. ratio";   actual(4) = grid%PR_op;                           design(4) = PR_DESIGN
        kpi_label(5) = "TIT";            actual(5) = grid%TIT_actual_K;                    design(5) = grid%TIT_K

        ! Format strings
        write(act_str(1), '(I6)') nint(actual(1))
        write(des_str(1), '("des ",I6," kJ/kWh")') nint(design(1))
        write(act_str(2), '(F5.1," %")') actual(2)
        write(des_str(2), '("des ",F5.1,"%")') design(2)
        write(act_str(3), '(F5.1," %")') actual(3)
        write(des_str(3), '("des ",F5.1,"%")') design(3)
        write(act_str(4), '(F5.2)') actual(4)
        write(des_str(4), '("des ",F5.2)') design(4)
        write(act_str(5), '(I4," K")') nint(actual(5))
        write(des_str(5), '("set ",I4,"K")') nint(design(5))

        do i = 1, N_KPI
            if (abs(design(i)) > 0.001_dp) then
                gap_pct(i) = (actual(i) - design(i)) / design(i) * 100.0_dp
            else
                gap_pct(i) = 0.0_dp
            end if
            write(gap_str(i), '(SP,F5.1,"%")') gap_pct(i)
            if (lower_better(i)) then
                kpi_color(i) = merge(COL_RED, merge(COL_AMBER, COL_GREEN, gap_pct(i) > 5.0_dp), gap_pct(i) > 15.0_dp)
            else
                kpi_color(i) = merge(COL_RED, merge(COL_AMBER, COL_GREEN, gap_pct(i) < -5.0_dp), gap_pct(i) < -15.0_dp)
            end if
        end do

        ! Column layout: label | actual | bar | gap% | design
        bar_w    = min(200, max(80, (width - 420) / 1))
        bar_half = bar_w / 2
        mid_x    = x + 220 + bar_half   ! center of deviation bar
        bx       = mid_x - bar_half

        row_y = y + 14
        call draw_text(hdc, x + 12, row_y, "Metric", COL_DIM)
        call draw_text(hdc, x + 160, row_y, "Live", COL_DIM)
        call draw_text(hdc, bx, row_y, "Deviation", COL_DIM)
        call draw_text(hdc, mid_x + bar_half + 12, row_y, "Design", COL_DIM)
        row_y = row_y + 22

        do i = 1, N_KPI
            col = int(kpi_color(i), c_int)
            call draw_text(hdc, x + 12, row_y, trim(kpi_label(i)), COL_INK)
            call draw_text(hdc, x + 160, row_y, trim(adjustl(act_str(i))), col)
            ! Deviation bar: centered at mid_x, filled toward right (pos gap) or left (neg)
            call fill_soft_box(hdc, bx, row_y + 2, bx + bar_w, row_y + 14, COL_PANEL_DEEP)
            call stroke_soft_box(hdc, bx, row_y + 2, bx + bar_w, row_y + 14, COL_BORDER_SOFT, 1)
            ! Center tick
            call draw_line(hdc, mid_x, row_y + 2, mid_x, row_y + 14, COL_DIM, 1)
            bar_px = min(bar_half - 2, nint(abs(gap_pct(i)) / 20.0_dp * real(bar_half, dp)))
            if (gap_pct(i) > 0.0_dp) then
                call fill_box(hdc, mid_x, row_y + 3, mid_x + bar_px, row_y + 13, col)
            else
                call fill_box(hdc, mid_x - bar_px, row_y + 3, mid_x, row_y + 13, col)
            end if
            call draw_text(hdc, bx + bar_w + 8, row_y, trim(adjustl(gap_str(i))), col)
            call draw_text(hdc, mid_x + bar_half + 96, row_y, trim(adjustl(des_str(i))), COL_MUTED)
            row_y = row_y + 30
        end do
    end subroutine draw_perf_gap_panel

    ! Predictive maintenance Gantt: three scheduled interval bars (compressor wash,
    ! borescope, hot-section OH) cycling over GT running hours from elapsed_s.
    subroutine draw_maintenance_gantt(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        real(dp), parameter :: WASH_H = 2000.0_dp
        real(dp), parameter :: BORE_H = 8000.0_dp
        real(dp), parameter :: HOT_H  = 24000.0_dp
        real(dp) :: run_h, pct_w, pct_b, pct_h, due_w, due_b, due_h_val
        integer  :: row_y, label_w, bar_x, bar_w, bh, fill_px
        integer(c_int) :: col_w, col_b, col_h
        character(len=40) :: s1

        call fill_soft_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
        call stroke_soft_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)

        run_h     = grid%elapsed_s / 3600.0_dp
        pct_w     = min(1.0_dp, mod(run_h, WASH_H) / WASH_H)
        pct_b     = min(1.0_dp, mod(run_h, BORE_H) / BORE_H)
        pct_h     = min(1.0_dp, mod(run_h, HOT_H)  / HOT_H)
        due_w     = WASH_H - mod(run_h, WASH_H)
        due_b     = BORE_H - mod(run_h, BORE_H)
        due_h_val = HOT_H  - mod(run_h, HOT_H)

        col_w = merge(COL_RED, merge(COL_AMBER, COL_GREEN, pct_w > 0.70_dp), pct_w > 0.90_dp)
        col_b = merge(COL_RED, merge(COL_AMBER, COL_GREEN, pct_b > 0.70_dp), pct_b > 0.90_dp)
        col_h = merge(COL_RED, merge(COL_AMBER, COL_GREEN, pct_h > 0.70_dp), pct_h > 0.90_dp)

        label_w = 225
        bar_x   = x + 12 + label_w
        bar_w   = max(80, width - 12 - label_w - 8 - 130 - 12)
        bh      = 16

        ! Column headers
        row_y = y + 10
        call draw_text(hdc, x + 12,               row_y, "Maintenance task",  COL_DIM)
        call draw_text(hdc, bar_x,                 row_y, "Interval progress", COL_DIM)
        call draw_text(hdc, bar_x + bar_w + 8,     row_y, "%",                 COL_DIM)
        call draw_text(hdc, bar_x + bar_w + 50,    row_y, "Due in",            COL_DIM)
        row_y = row_y + 26

        ! Row 1 — Compressor wash (every 2 000 h)
        call draw_text(hdc, x + 12, row_y + 1, "Compressor wash (2 000 h)", COL_INK)
        call fill_soft_box(hdc, bar_x, row_y, bar_x + bar_w, row_y + bh, COL_PANEL_DEEP)
        fill_px = max(0, nint(real(bar_w, dp) * pct_w))
        if (fill_px > 0) call fill_soft_box(hdc, bar_x, row_y, bar_x + fill_px, row_y + bh, col_w)
        call stroke_soft_box(hdc, bar_x, row_y, bar_x + bar_w, row_y + bh, COL_BORDER_SOFT, 1)
        write(s1, '(I3,"%")') nint(pct_w * 100.0_dp)
        call draw_text(hdc, bar_x + bar_w + 8,  row_y + 1, trim(adjustl(s1)), col_w)
        write(s1, '(I7,"h")') nint(due_w)
        call draw_text(hdc, bar_x + bar_w + 50, row_y + 1, trim(adjustl(s1)), COL_MUTED)
        row_y = row_y + 28

        ! Row 2 — Borescope inspection (every 8 000 h)
        call draw_text(hdc, x + 12, row_y + 1, "Borescope insp. (8 000 h)", COL_INK)
        call fill_soft_box(hdc, bar_x, row_y, bar_x + bar_w, row_y + bh, COL_PANEL_DEEP)
        fill_px = max(0, nint(real(bar_w, dp) * pct_b))
        if (fill_px > 0) call fill_soft_box(hdc, bar_x, row_y, bar_x + fill_px, row_y + bh, col_b)
        call stroke_soft_box(hdc, bar_x, row_y, bar_x + bar_w, row_y + bh, COL_BORDER_SOFT, 1)
        write(s1, '(I3,"%")') nint(pct_b * 100.0_dp)
        call draw_text(hdc, bar_x + bar_w + 8,  row_y + 1, trim(adjustl(s1)), col_b)
        write(s1, '(I7,"h")') nint(due_b)
        call draw_text(hdc, bar_x + bar_w + 50, row_y + 1, trim(adjustl(s1)), COL_MUTED)
        row_y = row_y + 28

        ! Row 3 — Hot section overhaul (every 24 000 h)
        call draw_text(hdc, x + 12, row_y + 1, "Hot section OH (24 000 h)", COL_INK)
        call fill_soft_box(hdc, bar_x, row_y, bar_x + bar_w, row_y + bh, COL_PANEL_DEEP)
        fill_px = max(0, nint(real(bar_w, dp) * pct_h))
        if (fill_px > 0) call fill_soft_box(hdc, bar_x, row_y, bar_x + fill_px, row_y + bh, col_h)
        call stroke_soft_box(hdc, bar_x, row_y, bar_x + bar_w, row_y + bh, COL_BORDER_SOFT, 1)
        write(s1, '(I3,"%")') nint(pct_h * 100.0_dp)
        call draw_text(hdc, bar_x + bar_w + 8,  row_y + 1, trim(adjustl(s1)), col_h)
        write(s1, '(I7,"h")') nint(due_h_val)
        call draw_text(hdc, bar_x + bar_w + 50, row_y + 1, trim(adjustl(s1)), COL_MUTED)
        row_y = row_y + 28

        ! Running hours annotation
        write(s1, '("GT on-stream: ",F8.1,"h (mod-cycled)")') run_h
        call draw_text(hdc, x + 12, row_y + 4, trim(adjustl(s1)), COL_DIM)
    end subroutine draw_maintenance_gantt

    subroutine draw_maintenance_watch(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: row_y, row_gap
        integer(c_int) :: hr_col, sm_col, tit_col, soc_col, res_col, cycle_col
        real(dp) :: hr_gap_pct, tit_margin, res_headroom
        character(len=96) :: value, action

        call fill_soft_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
        call stroke_soft_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)

        hr_gap_pct = (grid%gt_heat_rate_kJ_kWh - 9200.0_dp) / 9200.0_dp * 100.0_dp
        tit_margin = grid%TIT_K - grid%TIT_actual_K
        res_headroom = renewable_headroom_MW(grid)
        hr_col = merge(COL_RED, merge(COL_AMBER, COL_GREEN, hr_gap_pct > 8.0_dp), hr_gap_pct > 20.0_dp)
        sm_col = merge(COL_RED, merge(COL_AMBER, COL_GREEN, grid%surge_margin_pct < 15.0_dp), grid%surge_margin_pct < 8.0_dp)
        tit_col = merge(COL_RED, merge(COL_AMBER, COL_GREEN, tit_margin < 25.0_dp), tit_margin < 5.0_dp)
        soc_col = merge(COL_RED, merge(COL_AMBER, COL_BLUE, grid%battery_soc_pct < 30.0_dp), grid%battery_soc_pct < 15.0_dp)
        res_col = merge(COL_AMBER, COL_GREEN, res_headroom < 0.5_dp)
        cycle_col = merge(COL_CYAN, COL_MUTED, grid%combined_cycle)

        row_gap = max(24, min(38, (height - 30) / 6))
        row_y = y + 12
        call draw_text(hdc, x + 12, row_y, "Watch item", COL_DIM)
        call draw_text(hdc, x + 170, row_y, "Live", COL_DIM)
        call draw_text(hdc, x + 320, row_y, "Operator meaning", COL_DIM)
        row_y = row_y + row_gap

        write(value, '(SP,F5.1,"%")') hr_gap_pct
        if (hr_gap_pct > 8.0_dp) then
            action = "High heat-rate gap: check compressor fouling / part-load operation"
        else
            action = "Near expected simple-cycle heat-rate band"
        end if
        call draw_maintenance_row(hdc, x, row_y, "Heat-rate gap", trim(adjustl(value)), trim(action), hr_col)
        row_y = row_y + row_gap

        write(value, '(F5.1,"%")') grid%surge_margin_pct
        if (grid%surge_margin_pct < 15.0_dp) then
            action = "Low margin: unload GT or restore compressor flow margin"
        else
            action = "Compressor operating point clear of surge line"
        end if
        call draw_maintenance_row(hdc, x, row_y, "Surge margin", trim(adjustl(value)), trim(action), sm_col)
        row_y = row_y + row_gap

        write(value, '(SP,I3," K")') nint(tit_margin)
        if (tit_margin < 25.0_dp) then
            action = "TIT headroom tight: limiter may bind on dispatch"
        else
            action = "Turbine inlet temperature has dispatch headroom"
        end if
        call draw_maintenance_row(hdc, x, row_y, "TIT headroom", trim(adjustl(value)), trim(action), tit_col)
        row_y = row_y + row_gap

        write(value, '(F5.1,"%  ",SP,F5.1," MW")') grid%battery_soc_pct, grid%BESS_primary_MW
        if (grid%battery_soc_pct < 30.0_dp) then
            action = "BESS reserve constrained: restore mid-SOC"
        else
            action = "BESS available for FCR and imbalance support"
        end if
        call draw_maintenance_row(hdc, x, row_y, "BESS support", trim(adjustl(value)), trim(action), soc_col)
        row_y = row_y + row_gap

        write(value, '(F5.1,"/",F4.1," MW")') effective_renewable_MW(grid), grid%renewable_MW
        if (res_headroom < 0.5_dp) then
            action = "No RES headroom: cloud or dispatch ceiling binding"
        else
            action = "Renewable ceiling can still move if dispatch calls"
        end if
        call draw_maintenance_row(hdc, x, row_y, "RES ceiling", trim(adjustl(value)), trim(action), res_col)
        row_y = row_y + row_gap

        if (grid%combined_cycle) then
            write(value, '("CC  pinch ",F4.1," K")') grid%hrsg_pinch_K
            action = "HRSG/ST online: monitor pinch and condenser pressure"
        else
            value = "GT only"
            action = "HRSG/ST train offline; use GT ONLY button to enable combined cycle"
        end if
        call draw_maintenance_row(hdc, x, row_y, "Cycle train", trim(adjustl(value)), trim(action), cycle_col)
    end subroutine draw_maintenance_watch

    subroutine draw_maintenance_row(hdc, x, y, label, value, action, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y
        character(len=*), intent(in) :: label, value, action
        integer(c_int), intent(in) :: color

        call draw_text(hdc, x + 12, y, label, COL_INK)
        call draw_text(hdc, x + 170, y, value, color)
        call draw_text(hdc, x + 320, y, action, COL_MUTED)
    end subroutine draw_maintenance_row

    ! Fault log: active alarms with ISA-18.2 severity (Critical/High/Medium/Low).
    ! Derived from current alarm flags in GridState.
    subroutine draw_fault_log(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer, parameter  :: MAX_FAULTS = 8
        character(len=20)   :: sev_label(MAX_FAULTS)
        character(len=60)   :: fault_desc(MAX_FAULTS)
        integer(c_int)      :: sev_color(MAX_FAULTS)
        integer :: n_faults, i, row_y

        call fill_soft_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
        call stroke_soft_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)

        n_faults = 0

        if (grid%alarm_surge) then
            n_faults = n_faults + 1
            sev_label(n_faults) = "CRITICAL"
            fault_desc(n_faults) = "Compressor surge — reduce load or increase SM"
            sev_color(n_faults) = COL_RED
        end if
        if (grid%alarm_turbine_max) then
            n_faults = n_faults + 1
            sev_label(n_faults) = "CRITICAL"
            fault_desc(n_faults) = "Turbine TIT at maximum — TIT limiter active"
            sev_color(n_faults) = COL_RED
        end if
        if (grid%alarm_ufls_active) then
            n_faults = n_faults + 1
            sev_label(n_faults) = "HIGH"
            fault_desc(n_faults) = "Under-frequency load shed — stage active"
            sev_color(n_faults) = COL_AMBER
        end if
        if (grid%alarm_underfreq) then
            n_faults = n_faults + 1
            sev_label(n_faults) = "HIGH"
            fault_desc(n_faults) = "Grid frequency below 49.5 Hz threshold"
            sev_color(n_faults) = COL_AMBER
        end if
        if (grid%alarm_hrsg_pinch) then
            n_faults = n_faults + 1
            sev_label(n_faults) = "HIGH"
            fault_desc(n_faults) = "HRSG pinch margin below minimum — check flow"
            sev_color(n_faults) = COL_AMBER
        end if
        if (grid%alarm_overfreq) then
            n_faults = n_faults + 1
            sev_label(n_faults) = "MEDIUM"
            fault_desc(n_faults) = "Grid frequency above 50.5 Hz (LFSM-O zone)"
            sev_color(n_faults) = COL_CYAN
        end if
        if (grid%alarm_low_reserve) then
            n_faults = n_faults + 1
            sev_label(n_faults) = "MEDIUM"
            fault_desc(n_faults) = "Reserve margin below minimum requirement"
            sev_color(n_faults) = COL_CYAN
        end if
        if (grid%alarm_low_soc) then
            n_faults = n_faults + 1
            sev_label(n_faults) = "MEDIUM"
            fault_desc(n_faults) = "BESS state of charge below 20 % threshold"
            sev_color(n_faults) = COL_CYAN
        end if

        row_y = y + 12
        if (n_faults == 0) then
            call draw_text(hdc, x + 16, row_y, "No active faults.", COL_GREEN)
            call draw_text(hdc, x + 16, row_y + 24, "All monitored parameters within limits.", COL_DIM)
            if (height > 170) then
                row_y = row_y + 64
                call draw_text(hdc, x + 16, row_y, "Normal protection channels", COL_MUTED)
                row_y = row_y + 28
                call draw_fault_normal_row(hdc, x, row_y, "Frequency", "49.5-50.5 Hz envelope", frequency_color())
                row_y = row_y + 26
                call draw_fault_normal_row(hdc, x, row_y, "Reserve", "spinning reserve above minimum", &
                    merge(COL_RED, COL_GREEN, grid%alarm_low_reserve))
                row_y = row_y + 26
                call draw_fault_normal_row(hdc, x, row_y, "BESS SOC", "low-SOC trip not active", &
                    merge(COL_RED, COL_BLUE, grid%alarm_low_soc))
                row_y = row_y + 26
                call draw_fault_normal_row(hdc, x, row_y, "Turbine", "TIT limiter clear", &
                    merge(COL_RED, COL_GREEN, grid%alarm_turbine_max))
                row_y = row_y + 26
                call draw_fault_normal_row(hdc, x, row_y, "Compressor", "surge protection clear", &
                    merge(COL_RED, COL_GREEN, grid%alarm_surge))
                if (height > 330) then
                    row_y = row_y + 26
                    if (grid%combined_cycle) then
                        call draw_fault_normal_row(hdc, x, row_y, "HRSG", "pinch protection clear", &
                            merge(COL_RED, COL_GREEN, grid%alarm_hrsg_pinch))
                    else
                        call draw_fault_normal_row(hdc, x, row_y, "HRSG", "offline in GT-only mode", COL_MUTED)
                    end if
                end if
            end if
            return
        end if

        call draw_text(hdc, x + 12, row_y, "SEV", COL_DIM)
        call draw_text(hdc, x + 76, row_y, "Description", COL_DIM)
        row_y = row_y + 20

        do i = 1, n_faults
            if (row_y > y + height - 24) exit
            call fill_soft_box(hdc, x + 12, row_y, x + 70, row_y + 18, sev_color(i))
            call draw_text(hdc, x + 14, row_y + 2, trim(sev_label(i)), COL_BG)
            call draw_text(hdc, x + 76, row_y + 2, trim(fault_desc(i)), COL_INK)
            row_y = row_y + 26
        end do
    end subroutine draw_fault_log

    subroutine draw_fault_normal_row(hdc, x, y, label, detail, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y
        character(len=*), intent(in) :: label, detail
        integer(c_int), intent(in) :: color

        call fill_box(hdc, x + 12, y - 4, x + 16, y + 16, color)
        call draw_text(hdc, x + 26, y, label, COL_INK)
        call draw_text(hdc, x + 140, y, detail, COL_MUTED)
    end subroutine draw_fault_normal_row

    ! Returns COL_GREEN / COL_AMBER / COL_RED for a 0-100 health score.
    pure function health_color(score) result(col)
        integer, intent(in) :: score
        integer(c_int) :: col
        if (score >= 75) then
            col = COL_GREEN
        else if (score >= 50) then
            col = COL_AMBER
        else
            col = COL_RED
        end if
    end function health_color

    ! =========================================================================
    ! F10 Fleet Unit Commitment + Economic Dispatch screen  (P1)
    ! =========================================================================

    subroutine draw_fleet_uc_screen(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: ix, iw, top_y, tile_y, tile_w, gap
        integer :: left_w, right_x, right_w
        integer :: chart_x, chart_y, chart_w, chart_h
        integer :: ord(FLEET_N), i, j, k, tmp_i
        integer :: by, bw, bx, row_h, row_y, px_d, col_h_px
        real(dp) :: residual_MW, total_cap, disp_frac
        integer(c_int) :: unit_col, bar_col
        character(len=8)  :: uc_names(FLEET_N)
        character(len=48) :: lbl
        character(len=160) :: subtitle

        ix    = x + 18;  iw = width - 36
        top_y = y + 8

        uc_names(FLEET_GT1) = "TwinGT"
        uc_names(FLEET_GT2) = "GT-Peer"
        uc_names(FLEET_CC1) = "CC-Plant"

        residual_MW = max(0.0_dp, grid%demand_MW - effective_renewable_MW(grid) - grid%storage_MW)

        write(subtitle, '("Demand ",F5.1," MW | Residual ",F5.1," MW | Unserved ",F5.1, &
            &" MW | LMP $",F5.1,"/MWh | ",I1,"/",I1," units")') &
            grid%demand_MW, residual_MW, grid%fleet_unserved_dispatch_MW, &
            grid%fleet_lmp_usd_MWh, count(grid%fleet_uc_commit == 1), FLEET_N
        call draw_screen_caption(hdc, ix, top_y, iw, SCREEN_FULL_LABEL(SCREEN_FLEET_UC), trim(adjustl(subtitle)))

        ! --- KPI tiles ---
        tile_y = top_y + 76
        gap    = 10
        tile_w = (iw - 3 * gap) / 4

        write(lbl, '(F5.1," MW")') residual_MW
        call draw_metric_tile(hdc, ix, tile_y, tile_w, 60, "Residual demand", trim(adjustl(lbl)), COL_AMBER)
        write(lbl, '(F5.1," MW")') grid%fleet_unserved_dispatch_MW
        call draw_metric_tile(hdc, ix + tile_w + gap, tile_y, tile_w, 60, "Unserved", trim(adjustl(lbl)), &
            merge(COL_RED, COL_GREEN, grid%fleet_unserved_dispatch_MW > 0.05_dp))
        write(lbl, '("$",I0,"/h")') nint(grid%fleet_uc_total_cost_h)
        call draw_metric_tile(hdc, ix + 2*(tile_w+gap), tile_y, tile_w, 60, "Fleet var cost", trim(adjustl(lbl)), COL_CYAN)
        write(lbl, '("$",F5.1,"/MWh")') grid%fleet_lmp_usd_MWh
        call draw_metric_tile(hdc, ix + 3*(tile_w+gap), tile_y, tile_w, 60, "System LMP", trim(adjustl(lbl)), COL_MUTED)

        if (.not. grid%fleet_uc_solved) then
            call draw_text(hdc, ix, tile_y + 90, "Fleet UC initialising (~4 s)...", COL_MUTED)
            return
        end if

        ! --- Merit-order sort (ascending variable cost) ---
        ord(1) = 1;  ord(2) = 2;  ord(3) = 3
        do i = 1, FLEET_N - 1
            do j = 1, FLEET_N - i
                if (grid%fleet_unit_cost_usd_MWh(ord(j)) > grid%fleet_unit_cost_usd_MWh(ord(j+1))) then
                    tmp_i = ord(j);  ord(j) = ord(j+1);  ord(j+1) = tmp_i
                end if
            end do
        end do

        ! --- Layout ---
        left_w  = max(400, min(iw * 44 / 100, iw - 340))
        right_x = ix + left_w + 16
        right_w = max(300, iw - left_w - 16)
        total_cap = sum(grid%fleet_unit_capacity_MW)

        call draw_section_title_width(hdc, ix,      tile_y + 78, "Merit-order capacity dispatch (cheapest first)", left_w)
        call draw_section_title_width(hdc, right_x, tile_y + 78, "Unit economics", right_w)

        ! ---------------------------------------------------------------
        ! LEFT: horizontal merit-order bar chart
        ! Each unit = a labelled row with a capacity bar + dispatch fill
        ! ---------------------------------------------------------------
        chart_x = ix + 88          ! room for rank + unit labels
        chart_w = left_w - 98
        chart_y = tile_y + 118
        row_h   = max(38, min(54, (height - 290) / FLEET_N))

        ! Demand cursor x-pixel
        px_d = chart_x + nint(residual_MW / max(total_cap, 1.0_dp) * real(chart_w, dp))
        px_d = max(chart_x, min(chart_x + chart_w, px_d))

        do k = 1, FLEET_N
            i  = ord(k)
            by = chart_y + (k - 1) * (row_h + 8)

            ! Row background — rounded pill
            call fill_soft_box(hdc, chart_x, by, chart_x + chart_w, by + row_h, COL_PANEL_DEEP)
            call stroke_soft_box(hdc, chart_x, by, chart_x + chart_w, by + row_h, COL_BORDER_SOFT, 1)

            ! Rank + name label left of bar
            if (i == FLEET_GT1) then
                unit_col = COL_CYAN
            else
                unit_col = COL_INK
            end if
            write(lbl, '(I1,".  ",A)') k, trim(uc_names(i))
            call draw_text(hdc, ix, by + row_h / 2 - 8, trim(lbl), unit_col)

            ! Capacity background bar (dim, rounded)
            bw = nint(grid%fleet_unit_capacity_MW(i) / max(total_cap, 1.0_dp) * real(chart_w, dp))
            bw = max(6, bw)
            call fill_soft_box(hdc, chart_x + 1, by + 4, chart_x + bw - 1, by + row_h - 4, COL_DIM)

            ! Dispatch fill (lime = committed)
            if (grid%fleet_uc_commit(i) == 1 .and. grid%fleet_uc_p(i) > 0.1_dp) then
                bx = nint(grid%fleet_uc_p(i) / max(total_cap, 1.0_dp) * real(chart_w, dp))
                bx = max(2, min(bx, bw - 2))
                call fill_soft_box(hdc, chart_x + 1, by + 4, chart_x + bx, by + row_h - 4, COL_LIME)
            end if

            ! ThermoTwin: cyan outline on capacity bar
            if (i == FLEET_GT1) then
                call stroke_soft_box(hdc, chart_x + 1, by + 4, chart_x + bw - 1, by + row_h - 4, COL_CYAN, 1)
            end if

            ! Capacity label inside/right of bar
            write(lbl, '(I0," MW")') nint(grid%fleet_unit_capacity_MW(i))
            if (bw >= 50) then
                call draw_text(hdc, chart_x + bw - 46, by + row_h / 2 - 8, trim(adjustl(lbl)), COL_INK)
            else
                call draw_text(hdc, chart_x + bw + 4, by + row_h / 2 - 8, trim(adjustl(lbl)), COL_MUTED)
            end if

            ! Dispatch label (inside committed fill, if large enough)
            if (grid%fleet_uc_commit(i) == 1 .and. grid%fleet_uc_p(i) > 0.1_dp) then
                bx = nint(grid%fleet_uc_p(i) / max(total_cap, 1.0_dp) * real(chart_w, dp))
                if (bx >= 46) then
                    write(lbl, '(I0," MW")') nint(grid%fleet_uc_p(i))
                    call draw_text(hdc, chart_x + 6, by + row_h / 2 - 8, trim(adjustl(lbl)), COL_PANEL_DEEP)
                end if
            end if

            ! Cost label (right of the whole chart)
            write(lbl, '("$",I3)') nint(grid%fleet_unit_cost_usd_MWh(i))
            if (i == grid%fleet_marginal_unit) then
                call draw_text(hdc, chart_x + chart_w + 4, by + row_h / 2 - 8, &
                    trim(adjustl(lbl))//"*", COL_AMBER)
            else
                call draw_text(hdc, chart_x + chart_w + 4, by + row_h / 2 - 8, trim(adjustl(lbl)), COL_MUTED)
            end if
        end do

        ! Demand cursor line
        call draw_line(hdc, px_d, chart_y - 16, px_d, chart_y + FLEET_N * (row_h + 8) - 4, COL_AMBER, 2)
        write(lbl, '(F5.1," MW")') residual_MW
        call draw_text(hdc, px_d + 4, chart_y - 16, trim(adjustl(lbl)), COL_AMBER)

        ! X-axis labels
        by = chart_y + FLEET_N * (row_h + 8) + 2
        call draw_text(hdc, chart_x, by, "0", COL_DIM)
        write(lbl, '(I0," MW")') nint(total_cap / 2.0_dp)
        call draw_text(hdc, chart_x + chart_w / 2 - 12, by, trim(adjustl(lbl)), COL_DIM)
        write(lbl, '(I0," MW")') nint(total_cap)
        call draw_text(hdc, chart_x + chart_w - 26, by, trim(adjustl(lbl)), COL_DIM)
        call draw_text(hdc, ix, by, "$/MWh", COL_DIM)

        ! ---------------------------------------------------------------
        ! RIGHT: unit economics table
        ! ---------------------------------------------------------------
        row_y = tile_y + 118
        call fill_soft_box(hdc, right_x, row_y, right_x + right_w, &
            row_y + FLEET_N * 58 + 36, COL_PANEL_ALT)
        call stroke_soft_box(hdc, right_x, row_y, right_x + right_w, &
            row_y + FLEET_N * 58 + 36, COL_BORDER_SOFT, 1)

        ! Table header
        row_y = row_y + 10
        call draw_text(hdc, right_x + 14, row_y, "Unit", COL_MUTED)
        call draw_text(hdc, right_x + 90, row_y, "HR kJ/kWh", COL_MUTED)
        call draw_text(hdc, right_x + 170, row_y, "VC $/MWh", COL_MUTED)
        row_y = row_y + 18
        call draw_line(hdc, right_x + 6, row_y, right_x + right_w - 6, row_y, COL_BORDER_SOFT, 1)
        row_y = row_y + 6

        do k = 1, FLEET_N
            i = ord(k)
            ! Side color bar: green=committed, dim=offline
            bar_col = merge(COL_LIME, COL_DIM, grid%fleet_uc_commit(i) == 1)
            call fill_box(hdc, right_x + 6, row_y, right_x + 10, row_y + 48, bar_col)

            ! Unit name
            if (i == FLEET_GT1) then
                call draw_text(hdc, right_x + 16, row_y + 4, trim(uc_names(i)), COL_CYAN)
                call draw_text(hdc, right_x + 16, row_y + 22, "(live physics)", COL_DIM)
            else
                call draw_text(hdc, right_x + 16, row_y + 4, trim(uc_names(i)), COL_INK)
            end if

            ! Heat rate
            write(lbl, '(I6)') nint(grid%fleet_unit_heat_rate_kJ_kWh(i))
            call draw_text(hdc, right_x + 90, row_y + 4, trim(adjustl(lbl)), COL_AMBER)

            ! Variable cost (highlighted if marginal)
            write(lbl, '("$",F5.1)') grid%fleet_unit_cost_usd_MWh(i)
            if (i == grid%fleet_marginal_unit) then
                call draw_text(hdc, right_x + 170, row_y + 4, trim(adjustl(lbl))//" LMP", COL_AMBER)
            else
                call draw_text(hdc, right_x + 170, row_y + 4, trim(adjustl(lbl)), COL_MUTED)
            end if

            ! Dispatch / status
            if (grid%fleet_uc_commit(i) == 1) then
                write(lbl, '(F5.1," / ",F5.1," MW")') grid%fleet_uc_p(i), grid%fleet_unit_capacity_MW(i)
                call draw_text(hdc, right_x + 16, row_y + 34, trim(adjustl(lbl)), COL_LIME)
            else
                write(lbl, '("Offline  cap ",F5.1," MW")') grid%fleet_unit_capacity_MW(i)
                call draw_text(hdc, right_x + 16, row_y + 34, trim(adjustl(lbl)), COL_DIM)
            end if

            row_y = row_y + 58
            if (k < FLEET_N) call draw_line(hdc, right_x + 6, row_y, right_x + right_w - 6, row_y, COL_BORDER_SOFT, 1)
        end do

        ! LMP summary
        row_y = row_y + 8
        if (grid%fleet_marginal_unit >= 1 .and. grid%fleet_marginal_unit <= FLEET_N) then
            write(lbl, '("LMP: $",F5.1," (marginal unit: ",A,")")') &
                grid%fleet_lmp_usd_MWh, trim(uc_names(grid%fleet_marginal_unit))
        else
            write(lbl, '("LMP: $",F5.1,"/MWh")') grid%fleet_lmp_usd_MWh
        end if
        call draw_text(hdc, right_x + 8, row_y, trim(adjustl(lbl)), COL_AMBER)

        ! --- ThermoTwin position summary (bottom) ---
        row_y = chart_y + FLEET_N * (row_h + 8) + 28
        ! Find ThermoTwin's merit-order rank
        do k = 1, FLEET_N
            if (ord(k) == FLEET_GT1) exit
        end do
        if (grid%fleet_uc_commit(FLEET_GT1) == 1) then
            disp_frac = grid%fleet_uc_p(FLEET_GT1) / max(grid%fleet_unit_capacity_MW(FLEET_GT1), 1.0_dp) * 100.0_dp
            write(subtitle, '("TwinGT merit rank ",I1,"/",I1," | VC $",F5.1,"/MWh | ", &
                &F5.1," MW (",F5.1,"%) dispatched")') &
                k, FLEET_N, grid%fleet_unit_cost_usd_MWh(FLEET_GT1), &
                grid%fleet_uc_p(FLEET_GT1), disp_frac
        else
            write(subtitle, '("TwinGT merit rank ",I1,"/",I1," | VC $",F5.1,"/MWh | not dispatched this hour")') &
                k, FLEET_N, grid%fleet_unit_cost_usd_MWh(FLEET_GT1)
        end if
        call draw_text(hdc, ix, row_y, trim(adjustl(subtitle)), COL_CYAN)

        ! [5.0-A4] Reclaim the empty lower canvas: full-width merit-order supply
        ! curve (the canonical market-clearing diagram) + a fleet KPI row.
        block
            integer :: lower_y, avail, curve_h, kpi_y, kw, kg, kx
            real(dp) :: comm_cap, disp_mw, util
            character(len=24) :: kv
            lower_y = tile_y + 392
            avail   = (y + height - 18) - lower_y
            if (avail > 180) then
                curve_h = max(220, min(avail - 110, 520))
                call draw_section_title_width(hdc, ix, lower_y - 26, &
                    "Fleet merit-order supply curve  (cumulative capacity vs marginal cost, clearing at system LMP)", iw)
                call draw_fleet_supply_curve(hdc, ix, lower_y, iw, curve_h, ord, uc_names)
                comm_cap = sum(grid%fleet_unit_capacity_MW, mask = grid%fleet_uc_commit == 1)
                disp_mw  = sum(grid%fleet_uc_p)
                util     = 100.0_dp * disp_mw / max(comm_cap, 1.0_dp)
                kpi_y = lower_y + curve_h + 16
                kg = GAP_CARD;  kw = (iw - 3 * kg) / 4
                write(kv, '(F6.1," MW")') comm_cap
                call draw_kpi_card(hdc, ix,               kpi_y, kw, 80, "COMMITTED CAP", trim(adjustl(kv)), COL_LIME)
                write(kv, '(F6.1," MW")') disp_mw
                kx = ix + (kw + kg)
                call draw_kpi_card(hdc, kx,               kpi_y, kw, 80, "DISPATCHED",    trim(adjustl(kv)), COL_CYAN)
                write(kv, '(F6.1," MW")') max(0.0_dp, comm_cap - disp_mw)
                kx = ix + 2 * (kw + kg)
                call draw_kpi_card(hdc, kx,               kpi_y, kw, 80, "FLEET RESERVE", trim(adjustl(kv)), COL_BLUE)
                write(kv, '(F5.1," %")') util
                kx = ix + 3 * (kw + kg)
                call draw_kpi_card(hdc, kx,               kpi_y, kw, 80, "UTILISATION",   trim(adjustl(kv)), &
                    merge(COL_AMBER, COL_GREEN, util > 92.0_dp))
            end if
        end block
    end subroutine draw_fleet_uc_screen

    ! [5.0-A4] Merit-order supply curve: a step chart of cumulative committed-and-
    ! available capacity (x, MW) against each unit's marginal cost (y, $/MWh).
    ! The residual-demand cursor crosses the stack at the marginal unit, setting the
    ! system clearing price (LMP) drawn as a horizontal marker. Committed = lime.
    subroutine draw_fleet_supply_curve(hdc, x, y, width, height, ord, uc_names)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer, intent(in) :: ord(FLEET_N)
        character(len=8), intent(in) :: uc_names(FLEET_N)
        integer :: gx, gy, gw, gh, k, i, x0p, x1p, yp, y0p, px_d
        real(dp) :: total_cap, max_cost, cum, residual_MW, ymax
        integer(c_int) :: col
        character(len=32) :: lbl

        call draw_panel_box_deep(hdc, x, y, width, height)
        gx = x + 56;        gy = y + 22
        gw = width - 80;    gh = height - 58
        y0p = gy + gh
        total_cap = max(1.0_dp, sum(grid%fleet_unit_capacity_MW))
        max_cost  = maxval(grid%fleet_unit_cost_usd_MWh)
        ymax      = max(10.0_dp, max_cost * 1.25_dp)
        residual_MW = max(0.0_dp, grid%demand_MW - effective_renewable_MW(grid) - grid%storage_MW)

        ! Axes + y gridlines/labels ($/MWh)
        do k = 0, 4
            yp = y0p - nint(real(k, dp) / 4.0_dp * real(gh, dp))
            call draw_line(hdc, gx, yp, gx + gw, yp, COL_BG_GRID, 1)
            write(lbl, '(I0)') nint(real(k, dp) / 4.0_dp * ymax)
            call draw_text(hdc, x + 10, yp - 8, trim(adjustl(lbl)), COL_DIM)
        end do
        call draw_line(hdc, gx, gy, gx, y0p, COL_BORDER, 1)
        call draw_line(hdc, gx, y0p, gx + gw, y0p, COL_BORDER, 1)

        ! Merit-order step blocks (cheapest first)
        cum = 0.0_dp
        do k = 1, FLEET_N
            i   = ord(k)
            x0p = gx + nint(cum / total_cap * real(gw, dp))
            cum = cum + grid%fleet_unit_capacity_MW(i)
            x1p = gx + nint(cum / total_cap * real(gw, dp))
            yp  = y0p - nint(min(grid%fleet_unit_cost_usd_MWh(i), ymax) / ymax * real(gh, dp))
            col = merge(COL_LIME, COL_DIM, grid%fleet_uc_commit(i) == 1)
            call fill_soft_box(hdc, x0p, yp, max(x0p + 2, x1p - 1), y0p, col)
            call stroke_soft_box(hdc, x0p, yp, max(x0p + 2, x1p - 1), y0p, COL_BORDER_SOFT, 1)
            if (x1p - x0p > 70) then
                call draw_text(hdc, (x0p + x1p) / 2 - len_trim(uc_names(i)) * 4, yp - 20, &
                    trim(uc_names(i)), merge(COL_CYAN, COL_PANEL_DEEP, i == FLEET_GT1))
                write(lbl, '("$",I0)') nint(grid%fleet_unit_cost_usd_MWh(i))
                call draw_text(hdc, (x0p + x1p) / 2 - 14, yp + 6, trim(adjustl(lbl)), COL_PANEL_DEEP)
            end if
        end do

        ! Residual-demand cursor + system clearing price (LMP)
        px_d = gx + nint(min(residual_MW, total_cap) / total_cap * real(gw, dp))
        call draw_line(hdc, px_d, gy, px_d, y0p, COL_AMBER, 2)
        write(lbl, '(F5.1," MW")') residual_MW
        call draw_text(hdc, px_d + 4, gy, trim(adjustl(lbl)), COL_AMBER)
        yp = y0p - nint(min(grid%fleet_lmp_usd_MWh, ymax) / ymax * real(gh, dp))
        call draw_line(hdc, gx, yp, gx + gw, yp, COL_AMBER, 1)
        write(lbl, '("LMP $",F5.1)') grid%fleet_lmp_usd_MWh
        call draw_text(hdc, gx + gw - 116, yp - 18, trim(adjustl(lbl)), COL_AMBER)

        call draw_text(hdc, gx + gw / 2 - 44, y0p + 18, "cumulative capacity, MW", COL_DIM)
        call draw_text(hdc, x + 6, gy - 16, "$/MWh", COL_DIM)
    end subroutine draw_fleet_supply_curve

    ! =========================================================================
    ! F11  DNN Surrogate Diagnostics screen
    ! =========================================================================

    subroutine draw_dnn_screen(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height

        integer  :: ix, iw, top_y, tile_y, gap, tile_w, tile_h
        integer  :: chart_x, chart_y, chart_w, chart_h
        integer  :: right_x, right_w, left_w
        real(dp) :: load_frac, dnn_hr_val, poly_hr_val, delta_hr, delta_cost_h
        character(len=128) :: lbl, sub_txt

        ix = x + 18;   iw = width - 36;   top_y = y + 8

        ! ── Screen caption ──────────────────────────────────────────────────
        if (grid%dnn_active) then
            if (DNN_POLICY_ACTIVE) then
                write(sub_txt,'("HR MAE ",F5.1," | val n=",I0," DNN ",F5.1," | policy active | adapt ",A," (n=",I0,")")') &
                    grid%dnn_hr_mae, grid%model_val_n, grid%model_val_dnn_hr_mae_kJ_kWh, &
                    merge("ON ", "OFF", grid%dnn_adapting), grid%dnn_online_n
            else
                write(sub_txt,'("HR MAE ",F5.1," | val n=",I0," DNN ",F5.1," | policy weights missing | adapt ",A)') &
                    grid%dnn_hr_mae, grid%model_val_n, grid%model_val_dnn_hr_mae_kJ_kWh, &
                    merge("ON ", "OFF", grid%dnn_adapting)
            end if
        else
            sub_txt = "DNN inactive  --  run train_dnn.py, place dnn_weights.txt alongside exe"
        end if
        call draw_screen_caption(hdc, ix, top_y, iw, "F11  DNN SURROGATE DIAGNOSTICS", trim(sub_txt))

        ! ── Current operating conditions ────────────────────────────────────
        load_frac    = clamp_real(grid%gas_power_MW / max(grid%gas_capacity_MW, 1.0_dp), 0.05_dp, 1.0_dp)
        dnn_hr_val   = dnn_heat_rate(load_frac, grid%ambient_C, grid%TIT_K, grid%wash_hr_gap_pct)
        poly_hr_val  = 9200.0_dp + 4600.0_dp * (1.0_dp - load_frac)**2
        delta_hr     = dnn_hr_val - poly_hr_val
        delta_cost_h = abs(delta_hr) * grid%gas_power_MW * grid%fuel_price_usd_gj / 1000.0_dp

        ! ── Metric tiles (5) ────────────────────────────────────────────────
        tile_y = top_y + 66;   gap = 10;   tile_h = 64
        tile_w = (iw - 4 * gap) / 5

        write(lbl, '(F8.1," kJ/kWh")') dnn_hr_val
        call draw_metric_tile(hdc, ix,                  tile_y, tile_w, tile_h, &
                              "DNN heat rate", trim(adjustl(lbl)), COL_CYAN)

        write(lbl, '(F8.1," kJ/kWh")') poly_hr_val
        call draw_metric_tile(hdc, ix + tile_w + gap,   tile_y, tile_w, tile_h, &
                              "Poly heat rate", trim(adjustl(lbl)), COL_DIM)

        if (delta_hr < 0.0_dp) then
            write(lbl, '(SP,F7.1," kJ/kWh")') delta_hr
        else
            write(lbl, '("+",F7.1," kJ/kWh")') delta_hr
        end if
        call draw_metric_tile(hdc, ix + 2*(tile_w+gap), tile_y, tile_w, tile_h, &
                              "DNN - poly HR", trim(adjustl(lbl)), &
                              merge(COL_GREEN, COL_AMBER, abs(delta_hr) < 300.0_dp))

        write(lbl, '(F6.2," $/h  (",F4.1,"% err)")') &
            delta_cost_h, 100.0_dp * abs(delta_hr) / max(poly_hr_val, 1.0_dp)
        call draw_metric_tile(hdc, ix + 3*(tile_w+gap), tile_y, tile_w, tile_h, &
                              "HR err cost now", trim(adjustl(lbl)), &
                              merge(COL_GREEN, COL_AMBER, delta_cost_h < 2.0_dp))

        ! MC dropout uncertainty tile
        if (grid%dnn_hr_sigma > 0.0_dp) then
            write(lbl, '(F7.1," kJ/kWh  ",F4.1,"%")') &
                grid%dnn_hr_sigma, 100.0_dp * grid%dnn_hr_sigma / max(dnn_hr_val, 1.0_dp)
        else
            lbl = "n/a  (not computed)"
        end if
        call draw_metric_tile(hdc, ix + 4*(tile_w+gap), tile_y, tile_w, tile_h, &
                              "MC dropout sigma", trim(adjustl(lbl)), &
                              merge(COL_GREEN, merge(COL_AMBER, COL_RED, &
                              grid%dnn_hr_sigma < 600.0_dp), grid%dnn_hr_sigma < 300.0_dp))

        ! ── Two-panel layout ────────────────────────────────────────────────
        left_w  = iw * 62 / 100
        right_x = ix + left_w + 14
        right_w = iw - left_w - 14
        chart_x = ix;   chart_w = left_w
        chart_y = tile_y + tile_h + 28
        chart_h = max(220, y + height - chart_y - 12)

        call draw_section_title_width(hdc, chart_x, chart_y - 20, &
            "Heat-rate vs load fraction  (DNN cyan, polynomial dim)  at current T_amb / TIT / fouling", &
            chart_w)
        call draw_hr_curve_panel(hdc, chart_x, chart_y, chart_w, chart_h, load_frac)

        call draw_section_title_width(hdc, right_x, chart_y - 20, "Policy & conditions", right_w)
        call draw_dnn_policy_panel(hdc, right_x, chart_y, right_w, chart_h)

    end subroutine draw_dnn_screen

    ! =========================================================================
    ! F12  Carbon & Sustainability screen
    ! =========================================================================
    subroutine draw_carbon_screen(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: ix, iw, top_y, left_w, right_x, right_w, tile_y, tile_w, gap
        integer :: row_y, bx, budget_y, bar_total, bar_fill, spark_y, spark_h
        integer :: i, sx, sy, prev_sy
        integer(c_int) :: col
        real(dp) :: intensity_baseline, pct_avoided, budget_t, proj_t
        real(dp) :: elapsed_h
        character(len=96) :: subtitle, lbl

        ix    = x + 18
        iw    = width - 36
        top_y = y + 8

        ! Subtitle
        intensity_baseline = grid%fuel_flow_kg_s * CO2_KG_PER_KG_FUEL * &
            3600.0_dp / max(grid%plant_power_MW, 0.1_dp)
        if (grid%CO2_intensity_g_kWh > 0.01_dp .and. intensity_baseline > 0.01_dp) then
            pct_avoided = 100.0_dp * (1.0_dp - grid%CO2_intensity_g_kWh / intensity_baseline)
        else
            pct_avoided = 0.0_dp
        end if
        write(subtitle, '("H2 blend ",F4.1," vol%  |  CO2 ",I3," g/kWh  |  baseline ",I3, &
            &"  |  avoided ",SP,F4.1,"%")') &
            grid%h2_fraction_pct, nint(grid%CO2_intensity_g_kWh), nint(intensity_baseline), pct_avoided
        call draw_screen_caption(hdc, ix, top_y, iw, SCREEN_FULL_LABEL(SCREEN_CARBON), &
            trim(adjustl(subtitle)))

        ! ── 4 metric tiles ───────────────────────────────────────────────────
        tile_y = top_y + 76
        gap    = 10
        tile_w = (iw - 3 * gap) / 4

        write(lbl, '(I4," g/kWh")') nint(grid%CO2_intensity_g_kWh)
        call draw_metric_tile(hdc, ix, tile_y, tile_w, 60, "CO2 intensity", &
            trim(adjustl(lbl)), merge(COL_GREEN, merge(COL_AMBER, COL_RED, &
            grid%CO2_intensity_g_kWh < 450.0_dp), grid%CO2_intensity_g_kWh < 300.0_dp))

        write(lbl, '(F5.1," mg/Nm3")') grid%nox_mg_nm3_15o2
        call draw_metric_tile(hdc, ix + tile_w + gap, tile_y, tile_w, 60, "NOx @15% O2", &
            trim(adjustl(lbl)), merge(COL_RED, merge(COL_AMBER, COL_GREEN, &
            grid%nox_mg_nm3_15o2 > 50.0_dp), grid%nox_mg_nm3_15o2 > 100.0_dp))

        write(lbl, '("$",F6.1,"/h")') grid%co2_cost_usd_h
        call draw_metric_tile(hdc, ix + 2*(tile_w+gap), tile_y, tile_w, 60, "Carbon cost", &
            trim(adjustl(lbl)), merge(COL_GREEN, COL_AMBER, grid%co2_cost_usd_h < 10.0_dp))

        write(lbl, '(F4.1," vol%")') grid%h2_fraction_pct
        col = merge(COL_CYAN, merge(COL_GREEN, COL_AMBER, grid%h2_fraction_pct < 15.0_dp), &
                    grid%h2_fraction_pct > 0.01_dp)
        call draw_metric_tile(hdc, ix + 3*(tile_w+gap), tile_y, tile_w, 60, "H2 blend", &
            trim(adjustl(lbl)), col)

        ! ── Layout: left 58% carbon budget + blend details; right 42% sparkline ──
        left_w  = max(400, iw * 58 / 100)
        right_x = ix + left_w + 16
        right_w = max(260, iw - left_w - 16)
        budget_y = tile_y + 78

        ! ── LEFT: daily carbon budget bar ────────────────────────────────────
        call draw_section_title_width(hdc, ix, budget_y, "Daily carbon budget  (target 50 t/day)", left_w)
        budget_t = 50.0_dp   ! configurable target tonne/day
        elapsed_h = grid%elapsed_s / 3600.0_dp
        ! Projected end-of-day total (linear extrapolation from current rate)
        if (elapsed_h > 0.1_dp) then
            proj_t = grid%co2_daily_t + grid%CO2_rate_kg_s * &
                (24.0_dp - mod(elapsed_h, 24.0_dp)) * 3600.0_dp / 1000.0_dp
        else
            proj_t = 0.0_dp
        end if
        row_y = budget_y + 28
        bx    = ix
        bar_total = left_w - 8

        ! Actual so-far bar — rounded pill
        bar_fill = max(2, min(bar_total, nint(grid%co2_daily_t / max(budget_t, 0.01_dp) * real(bar_total, dp))))
        call fill_soft_box(hdc, bx, row_y, bx + bar_total, row_y + 18, COL_PANEL_DEEP)
        col = merge(COL_RED, merge(COL_AMBER, COL_GREEN, grid%co2_daily_t > budget_t * 0.8_dp), &
                    grid%co2_daily_t > budget_t)
        call fill_soft_box(hdc, bx, row_y, bx + bar_fill, row_y + 18, col)
        call stroke_soft_box(hdc, bx, row_y, bx + bar_total, row_y + 18, COL_BORDER_SOFT, 1)
        write(lbl, '(F5.1," / ",I4," t  (today so far)")') grid%co2_daily_t, nint(budget_t)
        call draw_text(hdc, bx + bar_fill + 6, row_y + 2, trim(adjustl(lbl)), COL_MUTED)
        row_y = row_y + 26

        ! Projected end-of-day bar — thinner rounded pill
        bar_fill = max(2, min(bar_total, nint(proj_t / max(budget_t, 0.01_dp) * real(bar_total, dp))))
        call fill_soft_box(hdc, bx, row_y, bx + bar_total, row_y + 14, COL_PANEL_DEEP)
        call fill_soft_box(hdc, bx, row_y, bx + bar_fill, row_y + 14, merge(COL_RED, COL_DIM, proj_t > budget_t))
        call stroke_soft_box(hdc, bx, row_y, bx + bar_total, row_y + 14, COL_BORDER_SOFT, 1)
        write(lbl, '("projected ",F5.1," t end-of-day")') proj_t
        call draw_text(hdc, bx + 4, row_y + 1, trim(adjustl(lbl)), COL_DIM)
        row_y = row_y + 30

        ! ── LEFT: H2 co-firing details ────────────────────────────────────────
        call draw_section_title_width(hdc, ix, row_y, "H2 co-firing properties", left_w)
        row_y = row_y + 28

        write(lbl, '(F5.2," MJ/kg  (pure NG: 50.0)")') grid%h2_lhv_mj_kg
        call draw_value_pair(hdc, ix, row_y, "Blend LHV", trim(adjustl(lbl)), COL_INK)
        row_y = row_y + 18

        write(lbl, '(F5.2,"% mass H2")') 100.0_dp * grid%h2_mass_fraction
        call draw_value_pair(hdc, ix, row_y, "Mass fraction", trim(adjustl(lbl)), COL_CYAN)
        row_y = row_y + 18

        write(lbl, '(F4.2," kg/kg  (NG: 2.75)")') grid%h2_co2_factor
        call draw_value_pair(hdc, ix, row_y, "CO2 factor", trim(adjustl(lbl)), &
            merge(COL_GREEN, COL_MUTED, grid%h2_fraction_pct > 0.1_dp))
        row_y = row_y + 18

        write(lbl, '(F5.1," K  shift ",SP,F5.1," K")') &
            grid%flame_temp_ad_K, grid%flame_temp_shift_K
        call draw_value_pair(hdc, ix, row_y, "Adiabatic flame", trim(adjustl(lbl)), &
            merge(COL_AMBER, COL_INK, grid%flame_temp_shift_K > 35.0_dp))
        row_y = row_y + 18

        write(lbl, '(F5.1," ppm  ",F5.1," mg/Nm3")') &
            grid%nox_ppm_15o2, grid%nox_mg_nm3_15o2
        call draw_value_pair(hdc, ix, row_y, "Thermal NOx", trim(adjustl(lbl)), &
            merge(COL_RED, merge(COL_AMBER, COL_GREEN, grid%nox_mg_nm3_15o2 > 50.0_dp), &
            grid%nox_mg_nm3_15o2 > 100.0_dp))
        row_y = row_y + 18

        write(lbl, '(F5.1," ppm  ",F5.1," mg/Nm3")') &
            grid%co_ppm_15o2, grid%co_mg_nm3_15o2
        call draw_value_pair(hdc, ix, row_y, "CO slip", trim(adjustl(lbl)), &
            merge(COL_AMBER, COL_GREEN, grid%co_mg_nm3_15o2 > 50.0_dp))
        row_y = row_y + 18

        write(lbl, '(F5.1," MJ/m3  ",SP,F5.1,"%")') &
            grid%h2_wobbe_mj_m3, grid%h2_wobbe_deviation_pct
        call draw_value_pair(hdc, ix, row_y, "Wobbe index", trim(adjustl(lbl)), &
            merge(COL_GREEN, COL_RED, grid%h2_wobbe_ok))
        row_y = row_y + 18

        call draw_value_pair(hdc, ix, row_y, "Wobbe check", &
            merge("OK  within +/-5% of NG             ", &
                  "WARNING  burner modification needed", &
                  grid%h2_wobbe_ok), &
            merge(COL_GREEN, COL_RED, grid%h2_wobbe_ok))
        row_y = row_y + 18

        write(lbl, '(F5.1,"%  cooling ",F4.1,"%")') &
            grid%flashback_margin_pct, grid%turbine_cooling_air_pct
        call draw_value_pair(hdc, ix, row_y, "Flashback margin", trim(adjustl(lbl)), &
            merge(COL_RED, merge(COL_AMBER, COL_GREEN, grid%flashback_margin_pct < 45.0_dp), &
            grid%flashback_margin_pct < 20.0_dp))
        row_y = row_y + 18

        write(lbl, '(F4.2," mm  loss ",F4.2,"%")') grid%tip_clearance_mm, grid%tip_loss_pct
        call draw_value_pair(hdc, ix, row_y, "Tip clearance", trim(adjustl(lbl)), COL_MUTED)
        row_y = row_y + 18

        write(lbl, '(F7.3," t  total avoided vs 0% H2")') grid%h2_co2_avoided_t
        call draw_value_pair(hdc, ix, row_y, "CO2 avoided", trim(adjustl(lbl)), COL_CYAN)
        row_y = row_y + 28

        ! Controls hint
        call draw_line(hdc, ix, row_y, ix + left_w - 8, row_y, COL_BORDER_SOFT, 1)
        row_y = row_y + 10
        call draw_text(hdc, ix, row_y, &
            "[ F12 screen  ]  UP arrow +1 vol%  DOWN arrow -1 vol%  range 0-30%", COL_DIM)

        ! ── RIGHT: CO2 intensity history sparkline ────────────────────────────
        call draw_section_title_width(hdc, right_x, budget_y, "CO2 intensity  (g/kWh  live)", right_w)
        spark_y = budget_y + 28
        spark_h = max(140, height - (budget_y + 28) - 60)

        call fill_soft_box(hdc, right_x, spark_y, right_x + right_w, spark_y + spark_h, COL_PANEL_ALT)
        call stroke_soft_box(hdc, right_x, spark_y, right_x + right_w, spark_y + spark_h, COL_BORDER_SOFT, 1)

        ! Draw intensity trace using demand history as proxy (scaled by CO2 intensity)
        block
            real(dp) :: hi_val, lo_val, span, yf
            integer  :: n_pts, idx, ix2
            n_pts = min(grid%history_count, HISTORY_N)
            hi_val = 600.0_dp;   lo_val = 0.0_dp;   span = 600.0_dp
            if (n_pts >= 2) then
                prev_sy = 0
                do i = 1, n_pts
                    idx = history_index(grid, i)
                    ! Approximate CO2 intensity from history: demand as load proxy
                    yf = clamp_real((grid%hist_gas_dispatch_pct(idx) * 2.2_dp - lo_val) / span, 0.0_dp, 1.0_dp)
                    sx = right_x + 6 + nint(real(i - 1, dp) / real(n_pts - 1, dp) * real(right_w - 12, dp))
                    sy = spark_y + spark_h - 6 - nint(yf * real(spark_h - 12, dp))
                    if (i > 1) call draw_line(hdc, sx - nint(real(right_w-12,dp)/real(n_pts-1,dp)), &
                        prev_sy, sx, sy, COL_CYAN, 1)
                    prev_sy = sy
                end do
            end if
        end block

        ! Ref lines at 300 and 450 g/kWh
        block
            integer :: y300, y450
            y300 = spark_y + spark_h - 6 - nint(300.0_dp / 600.0_dp * real(spark_h - 12, dp))
            y450 = spark_y + spark_h - 6 - nint(450.0_dp / 600.0_dp * real(spark_h - 12, dp))
            call draw_line(hdc, right_x + 4, y300, right_x + right_w - 4, y300, COL_GREEN, 1)
            call draw_text(hdc, right_x + 6, y300 - 14, "300", COL_GREEN)
            call draw_line(hdc, right_x + 4, y450, right_x + right_w - 4, y450, COL_AMBER, 1)
            call draw_text(hdc, right_x + 6, y450 - 14, "450", COL_AMBER)
        end block

        ! Scope breakdown below sparkline
        row_y = spark_y + spark_h + 14
        call draw_text(hdc, right_x, row_y, "Scope breakdown (approx)", COL_INK)
        row_y = row_y + 20
        write(lbl, '(F6.2," kg/s  direct combustion")') grid%CO2_rate_kg_s
        call draw_value_pair(hdc, right_x, row_y, "Scope 1", trim(adjustl(lbl)), COL_AMBER)
        row_y = row_y + 18
        call draw_value_pair(hdc, right_x, row_y, "Scope 2", "~0  (self-generation)", COL_GREEN)
        row_y = row_y + 18
        write(lbl, '(F7.3," t avoided  (H2 displacement)")') grid%h2_co2_avoided_t
        call draw_value_pair(hdc, right_x, row_y, "Offset", trim(adjustl(lbl)), COL_CYAN)

    end subroutine draw_carbon_screen

    ! =========================================================================
    ! Revamp 7.0-P1  Exergy Analysis — second-law availability accounting
    ! =========================================================================
    subroutine draw_exergy_screen(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        type(ExergyResult) :: ex
        integer :: ix, iw, top_y, gap, kpi_y, kpi_w, kx
        integer :: panel_y, panel_h, left_w, right_x, right_w, bottom_y, bottom_h
        character(len=128) :: subtitle
        character(len=32) :: value
        integer(c_int) :: closure_col

        call compute_exergy(grid, ex)

        ix = x + 18
        iw = width - 36
        top_y = y + 8
        closure_col = merge(COL_GREEN, COL_RED, abs(ex%closure) <= 0.02_dp)
        write(subtitle, '("Second-law availability balance | eta_II ",F5.1,"% | closure ",SP,F6.2,"% | T0 ",SS,F6.1," K")') &
            100.0_dp * ex%eta_II, 100.0_dp * ex%closure, ex%T0_K
        call draw_screen_caption(hdc, ix, top_y, iw, "L3 Exergy Analysis", trim(adjustl(subtitle)))

        gap = 10
        kpi_y = top_y + 76
        kpi_w = max(118, (iw - 5 * gap) / 6)
        kx = ix
        write(value, '(F7.1," MW")') ex%ex_fuel / 1000.0_dp
        call draw_kpi_card(hdc, kx, kpi_y, kpi_w, 72, "FUEL EXERGY", trim(adjustl(value)), COL_AMBER)
        kx = kx + kpi_w + gap
        write(value, '(F7.1," MW")') ex%w_net / 1000.0_dp
        call draw_kpi_card(hdc, kx, kpi_y, kpi_w, 72, "USEFUL WORK", trim(adjustl(value)), COL_GREEN)
        kx = kx + kpi_w + gap
        write(value, '(F6.1,"%")') 100.0_dp * ex%eta_II
        call draw_kpi_card(hdc, kx, kpi_y, kpi_w, 72, "ETA_II", trim(adjustl(value)), &
            merge(COL_GREEN, COL_AMBER, ex%eta_II >= 0.40_dp))
        kx = kx + kpi_w + gap
        write(value, '(F7.1," MW")') ex%dest_total / 1000.0_dp
        call draw_kpi_card(hdc, kx, kpi_y, kpi_w, 72, "DESTROYED", trim(adjustl(value)), COL_RED)
        kx = kx + kpi_w + gap
        write(value, '(F7.1," MW")') (ex%ex_stack + ex%ex_cond) / 1000.0_dp
        call draw_kpi_card(hdc, kx, kpi_y, kpi_w, 72, "EXTERNAL LOSS", trim(adjustl(value)), COL_BLUE)
        kx = kx + kpi_w + gap
        write(value, '(SP,F6.2,"%")') 100.0_dp * ex%closure
        call draw_kpi_card(hdc, kx, kpi_y, kpi_w, 72, "BALANCE ERROR", trim(adjustl(value)), closure_col)

        ! [7.0-P4/P6] theoretical limits (cheap, every frame) + cached UQ/Sobol summary line
        block
            type(ThermoLimits) :: lim
            character(len=200) :: anlz
            character(len=12)  :: drv
            call compute_thermo_limits(grid, lim)
            if (.not. exergy_an_valid .or. abs(grid%fuel_flow_kg_s - exergy_an_fuel) > 0.02_dp &
                    .or. abs(grid%TIT_actual_K - exergy_an_tit) > 5.0_dp) then
                call run_exergy_uq(grid, 3.0_dp, 25.0_dp, 15.0_dp, 0.08_dp, 0.5_dp, 1200, exergy_an_uq)
                call run_exergy_sobol(grid, [3.0_dp, 25.0_dp, 15.0_dp, 0.08_dp, 0.5_dp], 300, 1, exergy_an_sob)
                exergy_an_fuel  = grid%fuel_flow_kg_s
                exergy_an_tit   = grid%TIT_actual_K
                exergy_an_valid = .true.
            end if
            select case (exergy_an_sob%dominant)
            case (1);     drv = "ambient T"
            case (2);     drv = "TIT"
            case (3);     drv = "exhaust T"
            case (4);     drv = "fuel flow"
            case default; drv = "press ratio"
            end select
            write(anlz, '("UQ  eta_II ",F4.1,"% +/- ",F3.1,"%  (95% CI ",F4.1,"-",F4.1,"%)     |     Carnot ",F4.1,"% (",I0,"% achieved)     |     top sensitivity: ",A)') &
                100.0_dp*exergy_an_uq%eta_II_mean, 100.0_dp*exergy_an_uq%eta_II_std, &
                100.0_dp*exergy_an_uq%eta_II_lo95, 100.0_dp*exergy_an_uq%eta_II_hi95, &
                100.0_dp*lim%eta_carnot, nint(100.0_dp*lim%carnot_fraction), trim(drv)
            call draw_text(hdc, ix, kpi_y + 82, trim(anlz), COL_CYAN)
            ! [7.0-P4] Sobol total-effect tornado (which input drives eta_II variance)
            block
                integer :: bi, by0, bx0, bw0, bl
                real(dp) :: stmax
                character(len=12) :: nm(SOBOL_NIN)
                nm = [character(len=12) :: "ambient T", "TIT", "exhaust T", "fuel flow", "press ratio"]
                stmax = max(maxval(exergy_an_sob%ST), 0.01_dp)
                bx0 = ix + 120
                bw0 = max(120, min(360, iw - 150))
                call draw_text(hdc, ix, kpi_y + 106, "Sobol sensitivity (total-effect ST)", COL_MUTED)
                do bi = 1, SOBOL_NIN
                    by0 = kpi_y + 126 + (bi - 1) * 14
                    call draw_text(hdc, ix, by0 - 2, trim(nm(bi)), COL_MUTED)
                    bl = nint(max(0.0_dp, exergy_an_sob%ST(bi)) / stmax * real(bw0, dp))
                    call fill_box(hdc, bx0, by0, bx0 + max(2, bl), by0 + 9, &
                        merge(COL_CYAN, COL_DIM, bi == exergy_an_sob%dominant))
                end do
            end block
        end block

        panel_y = kpi_y + 222
        panel_h = max(330, int(0.56_dp * real(height - 170, dp)))
        left_w = max(600, int(0.60_dp * real(iw, dp)))
        right_x = ix + left_w + 18
        right_w = iw - left_w - 18
        if (right_w < 300) then
            left_w = max(520, iw - 330)
            right_x = ix + left_w + 18
            right_w = iw - left_w - 18
        end if

        call draw_section_title_width(hdc, ix, panel_y - 24, "Grassmann availability flow", left_w)
        call draw_exergy_grassmann(hdc, ix, panel_y, left_w, panel_h, ex)

        call draw_section_title_width(hdc, right_x, panel_y - 24, "Exergy destruction waterfall", right_w)
        call draw_exergy_waterfall(hdc, right_x, panel_y, right_w, panel_h, ex)

        bottom_y = panel_y + panel_h + 34
        bottom_h = max(120, y + height - bottom_y - 8)
        call draw_section_title_width(hdc, ix, bottom_y - 24, "Physical interpretation and V&V closure", iw)
        call draw_exergy_interpretation(hdc, ix, bottom_y, iw, bottom_h, ex)
    end subroutine draw_exergy_screen

    subroutine draw_exergy_grassmann(hdc, x, y, width, height, ex)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        type(ExergyResult), intent(in) :: ex
        real(dp) :: fuel_MW, work_MW, dest_MW, stack_MW, cond_MW, max_MW
        integer :: cx1, cx2, cy, node_x, branch_x, line_w
        character(len=48) :: label

        call draw_panel_box_deep(hdc, x, y, width, height)
        fuel_MW = ex%ex_fuel / 1000.0_dp
        work_MW = ex%w_net / 1000.0_dp
        dest_MW = ex%dest_total / 1000.0_dp
        stack_MW = ex%ex_stack / 1000.0_dp
        cond_MW = ex%ex_cond / 1000.0_dp
        max_MW = max(1.0_dp, fuel_MW)

        cx1 = x + 34
        cx2 = x + width - 34
        cy = y + height / 2
        node_x = x + int(0.43_dp * real(width, dp))
        branch_x = x + int(0.68_dp * real(width, dp))
        line_w = max(5, min(28, nint(24.0_dp * fuel_MW / max_MW)))

        call draw_exergy_flow(hdc, cx1, cy, node_x, cy, line_w, COL_AMBER)
        call draw_exergy_node(hdc, node_x, cy, "PLANT", COL_CYAN)
        write(label, '(F7.1," MW  fuel chemical exergy")') fuel_MW
        call draw_text(hdc, cx1, cy - 42, trim(adjustl(label)), COL_AMBER)

        call draw_exergy_flow(hdc, node_x + 50, cy, cx2 - 24, cy, &
            max(4, min(22, nint(22.0_dp * work_MW / max_MW))), COL_GREEN)
        write(label, '(F7.1," MW useful shaft/electric work")') work_MW
        call draw_text(hdc, branch_x, cy - 42, trim(adjustl(label)), COL_GREEN)

        call draw_exergy_flow(hdc, node_x + 18, cy + 18, branch_x, y + height - 58, &
            max(3, min(18, nint(20.0_dp * dest_MW / max_MW))), COL_RED)
        write(label, '(F7.1," MW destroyed by irreversibility")') dest_MW
        call draw_text(hdc, branch_x - 12, y + height - 42, trim(adjustl(label)), COL_RED)

        call draw_exergy_flow(hdc, node_x + 18, cy - 18, branch_x, y + 58, &
            max(3, min(16, nint(18.0_dp * stack_MW / max_MW))), COL_BLUE)
        write(label, '(F7.1," MW stack/exhaust availability")') stack_MW
        call draw_text(hdc, branch_x - 12, y + 42, trim(adjustl(label)), COL_BLUE)

        if (cond_MW > 0.05_dp) then
            call draw_exergy_flow(hdc, node_x + 10, cy + 4, cx2 - 90, y + height - 96, &
                max(2, min(12, nint(15.0_dp * cond_MW / max_MW))), COL_CYAN)
            write(label, '(F6.1," MW condenser loss")') cond_MW
            call draw_text(hdc, cx2 - 190, y + height - 118, trim(adjustl(label)), COL_CYAN)
        end if

        call draw_text(hdc, x + 16, y + 14, "Ex_fuel = W_net + D_components + Ex_stack + Ex_condenser + residual", COL_MUTED)
        write(label, '("closure residual ",SP,F6.2,"%")') 100.0_dp * ex%closure
        call draw_mono(hdc, x + 16, y + height - 26, trim(adjustl(label)), &
            merge(COL_GREEN, COL_RED, abs(ex%closure) <= 0.02_dp))
    end subroutine draw_exergy_grassmann

    subroutine draw_exergy_flow(hdc, x1, y1, x2, y2, width, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x1, y1, x2, y2, width
        integer(c_int), intent(in) :: color
        integer :: ah

        call draw_line(hdc, x1, y1, x2, y2, color, width)
        ah = max(5, min(12, width + 3))
        call draw_line(hdc, x2 - ah, y2 - ah / 2, x2, y2, color, max(1, width / 3))
        call draw_line(hdc, x2 - ah, y2 + ah / 2, x2, y2, color, max(1, width / 3))
    end subroutine draw_exergy_flow

    subroutine draw_exergy_node(hdc, cx, cy, label, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: cx, cy
        character(len=*), intent(in) :: label
        integer(c_int), intent(in) :: color

        call fill_soft_box(hdc, cx - 44, cy - 24, cx + 44, cy + 24, COL_PANEL_ALT)
        call stroke_soft_box(hdc, cx - 44, cy - 24, cx + 44, cy + 24, color, 2)
        call draw_mono_title(hdc, cx - 30, cy - 10, label, color)
    end subroutine draw_exergy_node

    subroutine draw_exergy_waterfall(hdc, x, y, width, height, ex)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        type(ExergyResult), intent(in) :: ex
        character(len=18) :: names(6)
        real(dp) :: vals(6), max_val, pct
        integer(c_int) :: colors(6)
        integer :: i, row_y, row_h, bx, bw, fill_w
        character(len=40) :: label

        call draw_panel_box_deep(hdc, x, y, width, height)
        names = [character(len=18) :: "Compressor", "Combustor", "Turbine", &
                 "HRSG / ST", "Stack", "Condenser"]
        vals = [ex%dest_comp, ex%dest_comb, ex%dest_turb, ex%dest_hrsg, ex%ex_stack, ex%ex_cond] / 1000.0_dp
        colors = [COL_CYAN, COL_RED, COL_AMBER, COL_BLUE, COL_MUTED, COL_LIME]
        max_val = max(1.0_dp, maxval(vals))
        row_h = max(31, (height - 42) / 6)
        bx = x + max(116, width / 3)
        bw = max(70, width - (bx - x) - 78)

        do i = 1, 6
            row_y = y + 28 + (i - 1) * row_h
            pct = 100.0_dp * vals(i) / max(ex%ex_fuel / 1000.0_dp, 1.0_dp)
            call draw_text(hdc, x + 14, row_y + 7, trim(names(i)), COL_INK)
            call fill_box(hdc, bx, row_y + 8, bx + bw, row_y + 24, COL_PANEL_ALT)
            fill_w = int(real(bw, dp) * vals(i) / max_val)
            call fill_box(hdc, bx, row_y + 8, bx + fill_w, row_y + 24, colors(i))
            call stroke_box(hdc, bx, row_y + 8, bx + bw, row_y + 24, COL_BORDER_SOFT, 1)
            write(label, '(F6.1," MW  ",F5.1,"%")') vals(i), pct
            call draw_mono(hdc, bx + bw + 10, row_y + 5, trim(adjustl(label)), colors(i))
        end do
    end subroutine draw_exergy_waterfall

    subroutine draw_exergy_interpretation(hdc, x, y, width, height, ex)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        type(ExergyResult), intent(in) :: ex
        character(len=160) :: line
        integer :: col_w, rx, row_y
        integer(c_int) :: closure_col

        call draw_panel_box(hdc, x, y, width, height)
        col_w = max(360, (width - 36) / 2)
        rx = x + col_w + 28
        row_y = y + 18
        closure_col = merge(COL_GREEN, COL_RED, abs(ex%closure) <= 0.02_dp)

        line = "Dominant irreversibility: "//trim(exergy_dominant_component(ex))// &
               " - chemical reaction and finite-temperature heat transfer consume useful work potential."
        call draw_text(hdc, x + 16, row_y, trim(line), COL_INK)
        row_y = row_y + 24
        write(line, '("Rational efficiency eta_II = useful net work / fuel chemical exergy = ",F5.1,"%")') &
            100.0_dp * ex%eta_II
        call draw_text(hdc, x + 16, row_y, trim(line), COL_MUTED)
        row_y = row_y + 24
        write(line, '("Balance check residual = ",SP,F6.2,"%  (target < +/-2.0% for P1 live estimate)")') &
            100.0_dp * ex%closure
        call draw_text(hdc, x + 16, row_y, trim(line), closure_col)

        row_y = y + 18
        call draw_value_pair(hdc, rx, row_y, "Air mass flow", trim(real_unit(ex%m_air, "kg/s")), COL_MUTED)
        row_y = row_y + 24
        call draw_value_pair(hdc, rx, row_y, "Gas mass flow", trim(real_unit(ex%m_gas, "kg/s")), COL_MUTED)
        row_y = row_y + 24
        call draw_value_pair(hdc, rx, row_y, "Comp work", trim(real_unit(ex%w_comp / 1000.0_dp, "MW")), COL_CYAN)
        row_y = row_y + 24
        call draw_value_pair(hdc, rx, row_y, "GT / ST work", &
            trim(real_unit(ex%w_gt / 1000.0_dp, "MW"))//" / "//trim(real_unit(ex%w_st / 1000.0_dp, "MW")), COL_GREEN)
    end subroutine draw_exergy_interpretation

    function exergy_dominant_component(ex) result(name)
        type(ExergyResult), intent(in) :: ex
        character(len=24) :: name
        real(dp) :: vals(4)
        integer :: idx

        vals = [ex%dest_comp, ex%dest_comb, ex%dest_turb, ex%dest_hrsg]
        idx = maxloc(vals, dim=1)
        select case (idx)
        case (1); name = "compressor"
        case (2); name = "combustor"
        case (3); name = "turbine"
        case (4); name = "HRSG / bottoming cycle"
        case default; name = "unknown"
        end select
    end function exergy_dominant_component

    function real_unit(value, unit) result(text)
        real(dp), intent(in) :: value
        character(len=*), intent(in) :: unit
        character(len=28) :: text

        write(text, '(F8.2,1X,A)') value, trim(unit)
        text = adjustl(text)
    end function real_unit

    ! =========================================================================
    ! F13  AI Forecast screen — 4-hour demand + price forecast with confidence
    ! =========================================================================
    subroutine draw_forecast_screen(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: ix, iw, top_y, tile_w, gap, chart_y, chart_h, chart_w
        integer :: right_x, right_w, left_w, gx, gy, gw, gh
        integer :: i, px, py, px_prev, py_prev, py_lo, py_hi
        real(dp) :: d_min, d_max, p_min, p_max, t_max_s
        real(dp) :: d_rng, p_rng, frac_x, frac_y
        character(len=64) :: lbl
        integer(c_int) :: tick_col

        ix = x + 18;   iw = width - 36;   top_y = y + 8

        write(lbl,'("Horizon +4h  |  48 steps × 5min  |  RL ",A," |  adapt n=",I0)') &
            merge("ON ", "OFF", grid%rl_mode), grid%dnn_online_n
        call draw_screen_caption(hdc, ix, top_y, iw, SCREEN_FULL_LABEL(SCREEN_FORECAST), trim(lbl))

        ! ── 4 metric tiles ───────────────────────────────────────────────────
        gap    = 10
        tile_w = (iw - 3 * gap) / 4
        write(lbl,'(F6.1," MW")') grid%demand_MW
        call draw_metric_tile(hdc, ix,                  top_y+76, tile_w, 64, &
            "Current demand", trim(adjustl(lbl)), COL_INK)
        write(lbl,'(F6.1," MW")') grid%fcast_demand(6)
        call draw_metric_tile(hdc, ix + tile_w + gap,   top_y+76, tile_w, 64, &
            "+30 min demand", trim(adjustl(lbl)), COL_CYAN)
        write(lbl,'(F6.1," MW")') grid%fcast_demand(24)
        call draw_metric_tile(hdc, ix + 2*(tile_w+gap), top_y+76, tile_w, 64, &
            "+2h demand",     trim(adjustl(lbl)), COL_BLUE)
        write(lbl,'("$",F5.1,"/MWh")') grid%fcast_price(24)
        call draw_metric_tile(hdc, ix + 3*(tile_w+gap), top_y+76, tile_w, 64, &
            "+2h price",      trim(adjustl(lbl)), COL_AMBER)

        ! ── Two-panel chart layout ────────────────────────────────────────────
        chart_y = top_y + 166
        chart_h = max(180, y + height - chart_y - 12)
        left_w  = iw * 62 / 100
        right_x = ix + left_w + 16
        right_w = iw - left_w - 16
        chart_w = left_w

        ! Left: demand forecast chart
        call draw_section_title_width(hdc, ix, chart_y, &
            "Demand forecast  (band = P10-P90 confidence)", left_w)
        gx = ix;   gy = chart_y + 28;   gw = chart_w;   gh = chart_h - 36
        call fill_soft_box(hdc, gx, gy, gx + gw, gy + gh, COL_PANEL_ALT)
        call stroke_soft_box(hdc, gx, gy, gx + gw, gy + gh, COL_BORDER_SOFT, 1)

        ! Data range
        d_min = grid%demand_MW * 0.7_dp
        d_max = grid%demand_MW * 1.3_dp
        do i = 1, FC_N
            if (grid%fcast_dem_lo(i) < d_min) d_min = grid%fcast_dem_lo(i)
            if (grid%fcast_dem_hi(i) > d_max) d_max = grid%fcast_dem_hi(i)
        end do
        d_min  = d_min - 2.0_dp
        d_max  = d_max + 2.0_dp
        d_rng  = max(1.0_dp, d_max - d_min)
        t_max_s = real(FC_N, dp) * 300.0_dp

        ! Confidence band (semi-transparent fill)
        do i = 1, FC_N - 1
            frac_x  = real(i - 1, dp) / real(FC_N - 1, dp)
            px      = gx + 8 + int(frac_x * real(gw - 16, dp))
            frac_x  = real(i, dp) / real(FC_N - 1, dp)
            px_prev = gx + 8 + int(frac_x * real(gw - 16, dp))
            py_lo   = gy + gh - 8 - int((grid%fcast_dem_lo(i) - d_min) / d_rng * real(gh - 16, dp))
            py_hi   = gy + gh - 8 - int((grid%fcast_dem_hi(i) - d_min) / d_rng * real(gh - 16, dp))
            call hmi_fill_alpha_rect(hdc, int(px,c_int), int(py_hi,c_int), &
                int(px_prev,c_int), int(py_lo,c_int), COL_BLUE, 40_c_int)
        end do

        ! Demand mean line
        px_prev = gx + 8
        py_prev = gy + gh - 8 - int((grid%demand_MW - d_min) / d_rng * real(gh - 16, dp))
        do i = 1, FC_N
            frac_x = real(i, dp) / real(FC_N, dp)
            px     = gx + 8 + int(frac_x * real(gw - 16, dp))
            frac_y = (grid%fcast_demand(i) - d_min) / d_rng
            py     = gy + gh - 8 - int(frac_y * real(gh - 16, dp))
            py     = max(gy + 4, min(gy + gh - 4, py))
            call draw_line(hdc, px_prev, py_prev, px, py, COL_CYAN, 2)
            px_prev = px;   py_prev = py
        end do

        ! Axis labels
        write(lbl,'(I4," MW")') nint(d_min)
        call draw_text(hdc, gx + 2, gy + gh - 18, trim(adjustl(lbl)), COL_DIM)
        write(lbl,'(I4," MW")') nint(d_max)
        call draw_text(hdc, gx + 2, gy + 4,       trim(adjustl(lbl)), COL_DIM)
        call draw_text(hdc, gx + gw/2 - 20, gy + gh - 18, "now + 4h", COL_DIM)

        ! 30-min tick marks
        do i = 1, 7
            frac_x = real(i * 6, dp) / real(FC_N, dp)
            px     = gx + 8 + int(frac_x * real(gw - 16, dp))
            tick_col = merge(COL_BORDER, COL_BORDER_SOFT, mod(i, 2) == 0)
            call draw_line(hdc, px, gy, px, gy + gh, tick_col, 1)
        end do

        ! Right: price forecast chart
        call draw_section_title_width(hdc, right_x, chart_y, "Price forecast  ($/MWh)", right_w)
        gx = right_x;   gw = right_w
        call fill_soft_box(hdc, gx, gy, gx + gw, gy + gh, COL_PANEL_ALT)
        call stroke_soft_box(hdc, gx, gy, gx + gw, gy + gh, COL_BORDER_SOFT, 1)

        p_min = grid%power_price_usd_mwh * 0.6_dp
        p_max = grid%power_price_usd_mwh * 1.5_dp
        do i = 1, FC_N
            if (grid%fcast_price(i) < p_min) p_min = grid%fcast_price(i)
            if (grid%fcast_price(i) > p_max) p_max = grid%fcast_price(i)
        end do
        p_min = max(0.0_dp, p_min - 5.0_dp)
        p_max = p_max + 5.0_dp
        p_rng = max(1.0_dp, p_max - p_min)

        px_prev = gx + 8
        py_prev = gy + gh - 8 - int((grid%power_price_usd_mwh - p_min) / p_rng * real(gh - 16, dp))
        do i = 1, FC_N
            frac_x = real(i, dp) / real(FC_N, dp)
            px     = gx + 8 + int(frac_x * real(gw - 16, dp))
            frac_y = (grid%fcast_price(i) - p_min) / p_rng
            py     = gy + gh - 8 - int(frac_y * real(gh - 16, dp))
            py     = max(gy + 4, min(gy + gh - 4, py))
            call draw_line(hdc, px_prev, py_prev, px, py, COL_AMBER, 2)
            px_prev = px;   py_prev = py
        end do

        write(lbl,'("$",I4)') nint(p_min)
        call draw_text(hdc, gx + 2, gy + gh - 18, trim(adjustl(lbl)), COL_DIM)
        write(lbl,'("$",I4)') nint(p_max)
        call draw_text(hdc, gx + 2, gy + 4, trim(adjustl(lbl)), COL_DIM)

        ! RL Q-table stats
        call draw_section_title_width(hdc, right_x, gy + gh + 18, "RL dispatch  (R = toggle)", right_w)
        call draw_rl_status_panel(hdc, right_x, gy + gh + 44, right_w, max(80, y + height - (gy + gh + 44) - 8))
    end subroutine draw_forecast_screen

    subroutine draw_rl_status_panel(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: row_y
        character(len=48) :: s1
        integer(c_int) :: mode_col

        call fill_soft_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
        call stroke_soft_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)

        row_y    = y + 10
        mode_col = merge(COL_GREEN, COL_DIM, grid%rl_mode)
        call draw_text(hdc, x + 12, row_y, merge("RL POLICY ACTIVE (greedy) ", &
                                                   "RL LEARNING (eps-greedy)  ", grid%rl_mode), mode_col)
        row_y = row_y + 22
        write(s1, '("Action: ",I0,"  (1=charge 2=hold 3=dis)")') grid%rl_action_prev
        call draw_text(hdc, x + 12, row_y, trim(adjustl(s1)), COL_INK)
        row_y = row_y + 20
        write(s1, '("Reward last: ",SP,F7.1," $/h")') grid%rl_last_reward
        call draw_text(hdc, x + 12, row_y, trim(adjustl(s1)), COL_MUTED)
        row_y = row_y + 20
        write(s1, '("Cumulative:  ",SP,F9.1," $")') grid%rl_cumreward
        call draw_text(hdc, x + 12, row_y, trim(adjustl(s1)), COL_MUTED)
        row_y = row_y + 20
        write(s1, '("Storage setpt: ",SP,F6.1," MW")') grid%rl_storage_setpt
        call draw_text(hdc, x + 12, row_y, trim(adjustl(s1)), mode_col)
    end subroutine draw_rl_status_panel

    ! =========================================================================
    ! F14  Operator Advisory screen — NLP narrative + anomaly Z-scores + fault
    ! =========================================================================
    subroutine draw_advisory_screen(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: ix, iw, top_y, left_w, right_x, right_w
        integer :: txt_y, txt_h, row_y, i, bar_w, fill_px
        integer :: line_start, line_end, n_char, y_line, nlines
        character(len=64) :: lbl
        character(len=2048) :: adv
        integer(c_int) :: bar_col

        ix = x + 18;   iw = width - 36;   top_y = y + 8

        write(lbl,'("Composite Z=",F4.1,"  |  FC class ",I0,"  (",I2,"%)")') &
            grid%anom_composite, grid%fc_class1, nint(grid%fc_conf1 * 100.0_dp)
        call draw_screen_caption(hdc, ix, top_y, iw, SCREEN_FULL_LABEL(SCREEN_ADVISORY), trim(lbl))

        left_w  = iw * 65 / 100
        right_x = ix + left_w + 16
        right_w = iw - left_w - 16

        ! ── Left: advisory text ───────────────────────────────────────────────
        txt_y = top_y + 76
        txt_h = y + height - txt_y - 10
        call draw_section_title_width(hdc, ix, txt_y, "Operator advisory  (auto-generated)", left_w)
        txt_y = txt_y + 28
        call fill_soft_box(hdc, ix, txt_y, ix + left_w, txt_y + txt_h, COL_PANEL_ALT)
        call stroke_soft_box(hdc, ix, txt_y, ix + left_w, txt_y + txt_h, COL_BORDER_SOFT, 1)

        adv    = grid%advisory_text
        n_char = len_trim(adv)
        y_line = txt_y + 10
        nlines = 0
        line_start = 1
        do i = 1, n_char + 1
            if (i > n_char .or. adv(i:i) == char(10)) then
                line_end = i - 1
                if (line_end >= line_start) then
                    call draw_text(hdc, ix + 12, y_line, adv(line_start:line_end), COL_INK)
                end if
                y_line     = y_line + 18
                nlines     = nlines + 1
                line_start = i + 1
                if (y_line > txt_y + txt_h - 18) exit
            end if
        end do
        if (n_char == 0) &
            call draw_text(hdc, ix + 12, txt_y + 10, "Advisory will appear after baseline window (20 ticks).", COL_DIM)

        ! ── Right: anomaly Z-scores ───────────────────────────────────────────
        row_y = top_y + 76
        call draw_section_title_width(hdc, right_x, row_y, "Anomaly Z-scores  (EWMA)", right_w)
        row_y = row_y + 28
        call fill_soft_box(hdc, right_x, row_y, right_x + right_w, row_y + 120, COL_PANEL_ALT)
        call stroke_soft_box(hdc, right_x, row_y, right_x + right_w, row_y + 120, COL_BORDER_SOFT, 1)

        bar_w = right_w - 130
        call draw_anom_bar(hdc, right_x + 8, row_y + 10, bar_w, &
            "Heat rate", grid%anom_score_hr)
        call draw_anom_bar(hdc, right_x + 8, row_y + 38, bar_w, &
            "Exhaust K", grid%anom_score_tex)
        call draw_anom_bar(hdc, right_x + 8, row_y + 66, bar_w, &
            "Surge SM%", grid%anom_score_sm)
        call draw_anom_bar(hdc, right_x + 8, row_y + 94, bar_w, &
            "GT eta   ", grid%anom_score_eta)

        ! ── Fault classifier results ──────────────────────────────────────────
        row_y = row_y + 140
        call draw_section_title_width(hdc, right_x, row_y - 26, "Fault classifier  (decision tree)", right_w)
        call fill_soft_box(hdc, right_x, row_y, right_x + right_w, row_y + 110, COL_PANEL_ALT)
        call stroke_soft_box(hdc, right_x, row_y, right_x + right_w, row_y + 110, COL_BORDER_SOFT, 1)

        if (grid%fc_class1 > 0 .and. grid%fc_conf1 > 0.1_dp) then
            bar_col = merge(COL_RED, merge(COL_AMBER, COL_GREEN, grid%fc_conf1 > 0.4_dp), grid%fc_conf1 > 0.7_dp)
            write(lbl,'(I0,". ",A)') grid%fc_class1, fault_class_name(grid%fc_class1)
            call draw_text(hdc, right_x + 10, row_y + 10, trim(lbl), bar_col)
            fill_px = max(4, nint(grid%fc_conf1 * real(right_w - 24, dp)))
            call fill_soft_box(hdc, right_x + 10, row_y + 30, right_x + 10 + right_w - 24, row_y + 44, COL_PANEL_DEEP)
            call fill_soft_box(hdc, right_x + 10, row_y + 30, right_x + 10 + fill_px, row_y + 44, bar_col)
            call stroke_soft_box(hdc, right_x + 10, row_y + 30, right_x + 10 + right_w - 24, row_y + 44, COL_BORDER_SOFT, 1)
            write(lbl,'(I3,"% confidence")') nint(grid%fc_conf1 * 100.0_dp)
            call draw_text(hdc, right_x + 10, row_y + 48, trim(adjustl(lbl)), COL_MUTED)
        else
            call draw_text(hdc, right_x + 10, row_y + 10, "No fault pattern detected.", COL_DIM)
        end if
        if (grid%fc_class2 > 0 .and. grid%fc_conf2 > 0.1_dp) then
            bar_col = merge(COL_RED, merge(COL_AMBER, COL_GREEN, grid%fc_conf2 > 0.4_dp), grid%fc_conf2 > 0.7_dp)
            write(lbl,'("2nd: ",I0,". ",A)') grid%fc_class2, fault_class_name(grid%fc_class2)
            call draw_text(hdc, right_x + 10, row_y + 68, trim(lbl), bar_col)
            write(lbl,'(I3,"% conf.")') nint(grid%fc_conf2 * 100.0_dp)
            call draw_text(hdc, right_x + 10, row_y + 88, trim(adjustl(lbl)), COL_DIM)
        end if

        ! ── Baseline status ───────────────────────────────────────────────────
        row_y = row_y + 128
        if (grid%anom_tick <= 20) then
            write(lbl,'("Baseline: tick ",I0,"/20  (learning...)")') grid%anom_tick
            call draw_text(hdc, right_x, row_y, trim(adjustl(lbl)), COL_AMBER)
        else
            write(lbl,'("Baseline: ready  (n=",I0," ticks)")') grid%anom_tick
            call draw_text(hdc, right_x, row_y, trim(adjustl(lbl)), COL_GREEN)
        end if
    end subroutine draw_advisory_screen

    pure function fault_class_name(fc) result(name)
        integer, intent(in) :: fc
        character(len=20)   :: name
        select case (fc)
        case (1); name = "Compressor fouling"
        case (2); name = "Tip clearance loss"
        case (3); name = "TBC spallation"
        case (4); name = "Fuel valve bias"
        case (5); name = "Sensor drift"
        case (6); name = "HRSG pinch"
        case default; name = "Unknown"
        end select
    end function fault_class_name

    subroutine draw_anom_bar(hdc, x, y, bar_w, label, score)
        type(c_ptr), value :: hdc
        integer,          intent(in) :: x, y, bar_w
        character(len=*), intent(in) :: label
        real(dp),         intent(in) :: score
        integer  :: fill_px, bh
        integer(c_int) :: bar_col
        character(len=8) :: s1

        bh      = 16
        bar_col = merge(COL_RED, merge(COL_AMBER, COL_GREEN, score > 2.0_dp), score > 4.0_dp)
        call draw_text(hdc, x, y + 1, label, COL_INK)
        call fill_soft_box(hdc, x + 90, y, x + 90 + bar_w, y + bh, COL_PANEL_DEEP)
        fill_px = max(0, min(bar_w, nint(score / 10.0_dp * real(bar_w, dp))))
        if (fill_px > 0) call fill_soft_box(hdc, x + 90, y, x + 90 + fill_px, y + bh, bar_col)
        call stroke_soft_box(hdc, x + 90, y, x + 90 + bar_w, y + bh, COL_BORDER_SOFT, 1)
        write(s1, '(F4.1)') score
        call draw_text(hdc, x + 90 + bar_w + 4, y + 1, trim(adjustl(s1)), bar_col)
    end subroutine draw_anom_bar

    ! ─────────────────────────────────────────────────────────────────────────
    ! HR curve: DNN vs quadratic polynomial, load_frac [0.1,1.0] on X axis
    ! ─────────────────────────────────────────────────────────────────────────
    subroutine draw_hr_curve_panel(hdc, x, y, width, height, cur_lf)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        real(dp), intent(in) :: cur_lf

        integer, parameter :: NC = 40
        real(dp) :: dnn_v(NC), poly_v(NC), lf_i, hr_lo, hr_hi, hr_rng
        integer  :: i, px0, px1, py0, py1
        integer  :: gx, gy, gw, gh, cur_px, cur_py_dnn, cur_py_poly
        integer  :: lm, rm, tm, bm, tick_y, n_tick
        integer  :: band_y_lo, band_y_hi
        real(dp) :: tick_hr, cur_lf_s, mc_mean_unused, sigma_band
        character(len=12) :: lbl_y
        integer(c_int) :: col_dnn

        lm = 60;   rm = 12;   tm = 8;   bm = 30

        call fill_soft_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
        call stroke_soft_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)

        gx = x + lm;   gy = y + tm;   gw = width - lm - rm;   gh = height - tm - bm
        if (gw < 20 .or. gh < 20) return

        ! Compute both curves
        do i = 1, NC
            lf_i = 0.1_dp + 0.9_dp * real(i-1, dp) / real(NC-1, dp)
            poly_v(i) = 9200.0_dp + 4600.0_dp * (1.0_dp - lf_i)**2
            if (grid%dnn_active) then
                dnn_v(i) = dnn_heat_rate(lf_i, grid%ambient_C, grid%TIT_K, grid%wash_hr_gap_pct)
            else
                dnn_v(i) = poly_v(i)   ! no weights loaded; curves overlap
            end if
        end do

        hr_lo = real(floor((min(minval(dnn_v), minval(poly_v)) - 400.0_dp) / 500.0_dp), dp) * 500.0_dp
        hr_hi = real(ceiling((max(maxval(dnn_v), maxval(poly_v)) + 400.0_dp) / 500.0_dp), dp) * 500.0_dp
        hr_rng = max(hr_hi - hr_lo, 1.0_dp)

        ! Y-axis grid lines + labels (500 kJ/kWh spacing)
        n_tick = 0
        tick_hr = hr_lo
        do while (tick_hr <= hr_hi + 1.0_dp .and. n_tick <= 20)
            tick_y = gy + gh - nint((tick_hr - hr_lo) / hr_rng * real(gh, dp))
            if (tick_y >= gy .and. tick_y <= gy + gh) then
                call draw_line(hdc, gx, tick_y, gx + gw, tick_y, COL_BG_GRID, 1)
                write(lbl_y, '(I0)') nint(tick_hr)
                call draw_text(hdc, x + 2, tick_y - 8, trim(lbl_y), COL_DIM)
            end if
            tick_hr = tick_hr + 500.0_dp
            n_tick  = n_tick + 1
        end do

        ! Axis labels
        call draw_text(hdc, x + 2, gy,     "kJ/kWh", COL_DIM)
        call draw_text(hdc, gx,             y + height - bm + 7, "10%",  COL_DIM)
        call draw_text(hdc, gx + gw*2/9,   y + height - bm + 7, "30%",  COL_DIM)
        call draw_text(hdc, gx + gw*4/9,   y + height - bm + 7, "60%",  COL_DIM)
        call draw_text(hdc, gx + gw*7/9,   y + height - bm + 7, "90%",  COL_DIM)
        call draw_text(hdc, gx + gw - 18,  y + height - bm + 7, "100%", COL_DIM)

        ! Polynomial curve (COL_DIM, 1px)
        do i = 2, NC
            px0 = gx + (i-2) * gw / (NC-1)
            px1 = gx + (i-1) * gw / (NC-1)
            py0 = gy + gh - nint((poly_v(i-1) - hr_lo) / hr_rng * real(gh, dp))
            py1 = gy + gh - nint((poly_v(i)   - hr_lo) / hr_rng * real(gh, dp))
            call draw_line(hdc, px0, py0, px1, py1, COL_DIM, 1)
        end do

        ! DNN curve (COL_CYAN when active, else COL_MUTED as alias for poly)
        col_dnn = merge(COL_CYAN, COL_MUTED, grid%dnn_active)

        ! MC dropout ±σ band (shaded using per-pixel vertical segments)
        if (grid%dnn_active .and. grid%dnn_hr_sigma > 0.0_dp) then
            sigma_band = grid%dnn_hr_sigma
            do i = 1, NC
                px0 = gx + (i-1) * gw / (NC-1)
                band_y_hi = gy + gh - nint((dnn_v(i) + sigma_band - hr_lo) / hr_rng * real(gh, dp))
                band_y_lo = gy + gh - nint((dnn_v(i) - sigma_band - hr_lo) / hr_rng * real(gh, dp))
                band_y_hi = max(gy, band_y_hi)
                band_y_lo = min(gy + gh, band_y_lo)
                if (band_y_lo > band_y_hi) &
                    call draw_line(hdc, px0, band_y_hi, px0, band_y_lo, &
                                   int(Z'001A3040', c_int), 1)
            end do
        end if

        do i = 2, NC
            px0 = gx + (i-2) * gw / (NC-1)
            px1 = gx + (i-1) * gw / (NC-1)
            py0 = gy + gh - nint((dnn_v(i-1) - hr_lo) / hr_rng * real(gh, dp))
            py1 = gy + gh - nint((dnn_v(i)   - hr_lo) / hr_rng * real(gh, dp))
            call draw_line(hdc, px0, py0, px1, py1, col_dnn, 2)
        end do

        ! Current operating-point vertical marker
        cur_lf_s = clamp_real(cur_lf, 0.1_dp, 1.0_dp)
        cur_px   = gx + nint((cur_lf_s - 0.1_dp) / 0.9_dp * real(gw, dp))
        call draw_line(hdc, cur_px, gy, cur_px, gy + gh, COL_BORDER, 1)

        cur_py_poly = gy + gh - nint((9200.0_dp + 4600.0_dp*(1.0_dp-cur_lf_s)**2 - hr_lo) / hr_rng * real(gh, dp))
        call fill_box(hdc, cur_px-3, cur_py_poly-3, cur_px+3, cur_py_poly+3, COL_MUTED)

        if (grid%dnn_active) then
            cur_py_dnn = gy + gh - nint((dnn_heat_rate(cur_lf_s, grid%ambient_C, grid%TIT_K, &
                                          grid%wash_hr_gap_pct) - hr_lo) / hr_rng * real(gh, dp))
            call fill_box(hdc, cur_px-4, cur_py_dnn-4, cur_px+4, cur_py_dnn+4, COL_CYAN)
        end if

        ! Legend (top-right of plot)
        call draw_line(hdc, gx + gw - 68, gy + 10, gx + gw - 50, gy + 10, col_dnn, 2)
        call draw_text(hdc, gx + gw - 46, gy + 4, "DNN", col_dnn)
        call draw_line(hdc, gx + gw - 68, gy + 28, gx + gw - 50, gy + 28, COL_DIM, 1)
        call draw_text(hdc, gx + gw - 46, gy + 22, "Poly", COL_DIM)
        if (grid%dnn_hr_sigma > 0.0_dp) then
            call fill_box(hdc, gx + gw - 68, gy + 40, gx + gw - 50, gy + 50, int(Z'001A3040', c_int))
            call draw_text(hdc, gx + gw - 46, gy + 40, "+-sigma", COL_MUTED)
        end if

        ! DNN-not-loaded overlay
        if (.not. grid%dnn_active) then
            call draw_text(hdc, gx + 12, gy + gh/2 - 16, "DNN weights not loaded", COL_AMBER)
            call draw_text(hdc, gx + 12, gy + gh/2 + 4,  "curves are identical (polynomial)", COL_DIM)
        end if

    end subroutine draw_hr_curve_panel

    ! ─────────────────────────────────────────────────────────────────────────
    ! Policy confidence bars + current operating-condition values
    ! ─────────────────────────────────────────────────────────────────────────
    subroutine draw_dnn_policy_panel(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height

        real(dp)  :: probs(3), hour_f, price_n, demand_n, soc_f, prev_n, load_frac
        integer   :: i, row_y, bar_x, bar_w, bar_h, fill_w
        character(len=64) :: lbl
        integer, parameter :: BAR_PIX = 22
        integer(c_int), dimension(3) :: BAR_COL
        character(len=10), parameter             :: BAR_LBL(3) = ["P(off/low)", "P(mid)    ", "P(high)   "]

        BAR_COL = [COL_AMBER, COL_BLUE, COL_GREEN]

        call fill_soft_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
        call stroke_soft_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)

        bar_x = x + 12;   bar_w = width - 24
        row_y = y + 10

        ! ── Policy confidence bars ───────────────────────────────────────────
        call draw_text(hdc, bar_x, row_y, "Policy confidence (current conditions)", COL_INK)
        row_y = row_y + 22

        if (DNN_POLICY_ACTIVE) then
            load_frac = clamp_real(grid%gas_power_MW / max(grid%gas_capacity_MW, 1.0_dp), 0.0_dp, 1.0_dp)
            hour_f    = 0.5_dp
            price_n   = clamp_real(grid%fuel_price_usd_gj / 150.0_dp, 0.0_dp, 2.0_dp)
            demand_n  = clamp_real(grid%demand_MW           / 120.0_dp, 0.0_dp, 2.0_dp)
            soc_f     = clamp_real(grid%battery_soc_pct    / 100.0_dp, 0.0_dp, 1.0_dp)
            prev_n    = load_frac

            call dnn_commit_probs(hour_f, price_n, demand_n, soc_f, prev_n, probs)

            do i = 1, 3
                bar_h  = BAR_PIX
                fill_w = max(2, min(bar_w - 84, nint(probs(i) * real(bar_w - 84, dp))))
                call fill_soft_box(hdc, bar_x + 72, row_y, bar_x + bar_w - 8, row_y + bar_h, COL_PANEL_DEEP)
                if (fill_w > 0) call fill_soft_box(hdc, bar_x + 72, row_y, bar_x + 72 + fill_w, row_y + bar_h, BAR_COL(i))
                call stroke_soft_box(hdc, bar_x + 72, row_y, bar_x + bar_w - 8, row_y + bar_h, COL_BORDER_SOFT, 1)
                call draw_text(hdc, bar_x, row_y + 4, trim(BAR_LBL(i)), COL_MUTED)
                write(lbl, '(F5.1,"%")') probs(i) * 100.0_dp
                call draw_text(hdc, bar_x + bar_w - 32, row_y + 4, trim(adjustl(lbl)), BAR_COL(i))
                row_y = row_y + bar_h + 6
            end do
        else
            call draw_text(hdc, bar_x, row_y + 8,  "Policy weights not loaded.", COL_MUTED)
            call draw_text(hdc, bar_x, row_y + 26, "Retrain with train_dnn.py", COL_DIM)
            row_y = row_y + 60
        end if

        ! ── Operating conditions ─────────────────────────────────────────────
        row_y = row_y + 10
        call draw_line(hdc, bar_x, row_y, x + width - 12, row_y, COL_BORDER_SOFT, 1)
        row_y = row_y + 10
        call draw_text(hdc, bar_x, row_y, "Operating conditions", COL_INK)
        row_y = row_y + 22

        load_frac = clamp_real(grid%gas_power_MW / max(grid%gas_capacity_MW, 1.0_dp), 0.0_dp, 1.0_dp)

        write(lbl, '(I3,"% (",F5.1,"/",F5.1," MW)")') &
            nint(load_frac*100.0_dp), grid%gas_power_MW, grid%gas_capacity_MW
        call draw_value_pair(hdc, bar_x, row_y, "Load frac", trim(adjustl(lbl)), COL_INK)
        row_y = row_y + 18

        write(lbl, '(F5.1," C")') grid%ambient_C
        call draw_value_pair(hdc, bar_x, row_y, "Ambient T", trim(adjustl(lbl)), &
            merge(COL_AMBER, COL_GREEN, grid%ambient_C > 35.0_dp))
        row_y = row_y + 18

        write(lbl, '(F7.1," K")') grid%TIT_K
        call draw_value_pair(hdc, bar_x, row_y, "TIT", trim(adjustl(lbl)), COL_INK)
        row_y = row_y + 18

        write(lbl, '(F5.2," % HR gap")') grid%wash_hr_gap_pct
        call draw_value_pair(hdc, bar_x, row_y, "Fouling", trim(adjustl(lbl)), &
            merge(COL_RED, merge(COL_AMBER, COL_GREEN, &
                  grid%wash_hr_gap_pct > 1.0_dp), grid%wash_hr_gap_pct > 3.0_dp))
        row_y = row_y + 18

        write(lbl, '(F5.1," %")') grid%battery_soc_pct
        call draw_value_pair(hdc, bar_x, row_y, "BESS SoC", trim(adjustl(lbl)), &
            merge(COL_AMBER, COL_MUTED, grid%battery_soc_pct < 20.0_dp))
        row_y = row_y + 18

        write(lbl, '(F5.2," $/GJ")') grid%fuel_price_usd_gj
        call draw_value_pair(hdc, bar_x, row_y, "Fuel price", trim(adjustl(lbl)), COL_MUTED)
        row_y = row_y + 24

        ! ── DNN model status ──────────────────────────────────────────────────
        call draw_line(hdc, bar_x, row_y, x + width - 12, row_y, COL_BORDER_SOFT, 1)
        row_y = row_y + 10

        if (grid%dnn_active) then
            write(lbl,'("HR surrogate  MAE ",F5.1," kJ/kWh  (",F3.1,"% base)")') &
                grid%dnn_hr_mae, 100.0_dp * grid%dnn_hr_mae / 11000.0_dp
            call draw_text(hdc, bar_x, row_y, trim(lbl), COL_CYAN)
            row_y = row_y + 18
            if (DNN_POLICY_ACTIVE) then
                call draw_text(hdc, bar_x, row_y, "Policy: active  (prunes DP branches)", COL_GREEN)
            else
                call draw_text(hdc, bar_x, row_y, "Policy: no weights  (all branches kept)", COL_MUTED)
            end if
            row_y = row_y + 24
        else
            call draw_text(hdc, bar_x, row_y, "DNN not loaded  --  using polynomial", COL_AMBER)
            row_y = row_y + 24
        end if

        if (grid%model_val_ready .and. row_y + 112 < y + height - 8) then
            call draw_model_validation_panel(hdc, bar_x, row_y, bar_w, 106)
            row_y = row_y + 118
        end if

        if (grid%dnn_active .and. row_y + 112 < y + height - 8) then
            ! T_amb sensitivity strip (4 isotherms at current load)
            call draw_line(hdc, bar_x, row_y, x + width - 12, row_y, COL_BORDER_SOFT, 1)
            row_y = row_y + 10
            call draw_text(hdc, bar_x, row_y, "T_amb sensitivity  (current load)", COL_INK)
            row_y = row_y + 20
            load_frac = clamp_real(grid%gas_power_MW / max(grid%gas_capacity_MW, 1.0_dp), 0.0_dp, 1.0_dp)
            write(lbl, '(I6," kJ/kWh")') &
                nint(dnn_heat_rate(load_frac, 0.0_dp, grid%TIT_K, grid%wash_hr_gap_pct))
            call draw_value_pair(hdc, bar_x, row_y, "@ 0 C", trim(adjustl(lbl)), COL_CYAN)
            row_y = row_y + 18
            write(lbl, '(I6," kJ/kWh")') &
                nint(dnn_heat_rate(load_frac, 15.0_dp, grid%TIT_K, grid%wash_hr_gap_pct))
            call draw_value_pair(hdc, bar_x, row_y, "@ 15 C", trim(adjustl(lbl)), COL_GREEN)
            row_y = row_y + 18
            write(lbl, '(I6," kJ/kWh  (live: ",F4.1," C)")') &
                nint(dnn_heat_rate(load_frac, grid%ambient_C, grid%TIT_K, grid%wash_hr_gap_pct)), grid%ambient_C
            call draw_value_pair(hdc, bar_x, row_y, "@ live", trim(adjustl(lbl)), COL_INK)
            row_y = row_y + 18
            write(lbl, '(I6," kJ/kWh")') &
                nint(dnn_heat_rate(load_frac, 35.0_dp, grid%TIT_K, grid%wash_hr_gap_pct))
            call draw_value_pair(hdc, bar_x, row_y, "@ 35 C", trim(adjustl(lbl)), COL_AMBER)
        end if

    end subroutine draw_dnn_policy_panel

    subroutine draw_model_validation_panel(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: row_y, col2_x, val1_x, val2_x
        character(len=88) :: lbl
        integer(c_int) :: cyc_col, dnn_col

        call fill_soft_box(hdc, x, y, x + width, y + height, COL_PANEL_DEEP)
        call stroke_soft_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)

        call draw_text(hdc, x + 10, y + 8, "Model validation harness", COL_INK)
        write(lbl, '("n=",I0," fixed cases")') grid%model_val_n
        call draw_text(hdc, x + width - 104, y + 8, trim(adjustl(lbl)), COL_MUTED)

        if (.not. grid%model_val_ready) then
            call draw_text(hdc, x + 10, y + 36, "Waiting for first validation pass", COL_AMBER)
            return
        end if

        cyc_col = COL_GREEN
        if (grid%model_val_cycle_hr_mae_kJ_kWh > 1200.0_dp) cyc_col = COL_AMBER
        if (grid%model_val_cycle_hr_mae_kJ_kWh > 2200.0_dp) cyc_col = COL_RED
        dnn_col = COL_GREEN
        if (grid%model_val_dnn_hr_mae_kJ_kWh > 250.0_dp) dnn_col = COL_AMBER
        if (grid%model_val_dnn_hr_mae_kJ_kWh > 650.0_dp) dnn_col = COL_RED

        col2_x = x + max(238, width / 2 + 8)
        val1_x = x + 118
        val2_x = col2_x + 88
        row_y = y + 34

        call draw_text(hdc, x + 10, row_y, "Cycle power", COL_MUTED)
        write(lbl, '(F5.2," MW  bias ",SP,F5.2,SS)') &
            grid%model_val_cycle_power_mae_MW, grid%model_val_cycle_power_bias_MW
        call draw_text(hdc, val1_x, row_y, trim(adjustl(lbl)), COL_CYAN)

        call draw_text(hdc, col2_x, row_y, "Cycle HR", COL_MUTED)
        write(lbl, '(I5," kJ  bias ",SP,I5,SS)') &
            nint(grid%model_val_cycle_hr_mae_kJ_kWh), nint(grid%model_val_cycle_hr_bias_kJ_kWh)
        call draw_text(hdc, val2_x, row_y, trim(adjustl(lbl)), cyc_col)
        row_y = row_y + 22

        if (grid%model_val_dnn_available) then
            call draw_text(hdc, x + 10, row_y, "DNN HR", COL_MUTED)
            write(lbl, '(I5," kJ  bias ",SP,I5,SS)') &
                nint(grid%model_val_dnn_hr_mae_kJ_kWh), nint(grid%model_val_dnn_hr_bias_kJ_kWh)
            call draw_text(hdc, val1_x, row_y, trim(adjustl(lbl)), dnn_col)

            call draw_text(hdc, col2_x, row_y, "Worst pt", COL_MUTED)
            write(lbl, '("#",I0,"  max ",I5," kJ")') &
                grid%model_val_worst_idx, nint(grid%model_val_dnn_hr_max_abs_kJ_kWh)
            call draw_text(hdc, val2_x, row_y, trim(adjustl(lbl)), dnn_col)
        else
            call draw_text(hdc, x + 10, row_y, "DNN HR", COL_MUTED)
            call draw_text(hdc, val1_x, row_y, "weights unavailable", COL_AMBER)
        end if
        row_y = row_y + 24

        call draw_line(hdc, x + 10, row_y, x + width - 10, row_y, COL_BORDER_SOFT, 1)
        call draw_text(hdc, x + 10, row_y + 9, "cycle vs GT map; DNN vs train_dnn dispatch labels", COL_DIM)
    end subroutine draw_model_validation_panel

    ! =========================================================================
    ! F9 Day-Ahead MINLP Optimizer screen
    ! =========================================================================

    subroutine draw_dayahead_screen(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: ix, iw, top_y, left_w, right_x, right_w
        integer :: tile_w, gap, tile_y
        character(len=96) :: subtitle, lbl
        real(dp) :: net_usd

        ix    = x + 18
        iw    = width - 36
        top_y = y + 8

        if (.not. grid%da_solved) then
            write(subtitle, '("Waiting for first solve (~5 s)...")')
        else
            net_usd = grid%da_revenue_usd - grid%da_cost_usd
            if (grid%dnn_active) then
                write(subtitle, '("cost $",I0,"  net $",SP,I0,SS,"  |  ",I2, &
                    &"h GT  |  LP-gap ",F5.1,"%  |  DNN+DP")') &
                    nint(grid%da_cost_usd), nint(net_usd), sum(grid%da_commit), grid%da_gap_pct
            else
                write(subtitle, '("cost $",I0,"  net $",SP,I0,SS,"  |  ",I2, &
                    &"h GT  |  LP-gap ",F5.1,"%  |  POLY+DP")') &
                    nint(grid%da_cost_usd), nint(net_usd), sum(grid%da_commit), grid%da_gap_pct
            end if
        end if
        call draw_screen_caption(hdc, ix, top_y, iw, SCREEN_FULL_LABEL(SCREEN_DAYAHEAD), trim(adjustl(subtitle)))

        ! Metric tiles
        tile_y = top_y + 76
        gap    = 10
        tile_w = (iw - 3 * gap) / 4
        if (grid%da_solved) then
            net_usd = grid%da_revenue_usd - grid%da_cost_usd
            write(lbl, '("$",I0)') nint(grid%da_cost_usd)
            call draw_metric_tile(hdc, ix,                   tile_y, tile_w, 60, "GT cost 24h",  trim(adjustl(lbl)), COL_AMBER)
            write(lbl, '("$",I0)') nint(grid%da_revenue_usd)
            call draw_metric_tile(hdc, ix + tile_w + gap,    tile_y, tile_w, 60, "Revenue 24h",  trim(adjustl(lbl)), COL_GREEN)
            write(lbl, '("$",SP,I0)') nint(net_usd)
            call draw_metric_tile(hdc, ix + 2*(tile_w+gap),  tile_y, tile_w, 60, "Net margin",   trim(adjustl(lbl)), &
                merge(COL_GREEN, COL_RED, net_usd >= 0.0_dp))
            write(lbl, '(I2," / 24 h on")') sum(grid%da_commit)
            call draw_metric_tile(hdc, ix + 3*(tile_w+gap),  tile_y, tile_w, 60, "GT committed", trim(adjustl(lbl)), COL_CYAN)
            ! DA tracking: actual vs planned dispatch for current hour
            if (grid%da_current_hour >= 1 .and. grid%da_current_hour <= DA_H) then
                block
                    real(dp) :: plan_mw, dev_pct
                    integer(c_int) :: dev_col
                    character(len=64) :: track_s
                    plan_mw = grid%da_p_gt(grid%da_current_hour)
                    if (plan_mw > 1.0_dp) then
                        dev_pct = (grid%gas_power_MW - plan_mw) / plan_mw * 100.0_dp
                        dev_col = merge(COL_GREEN, merge(COL_AMBER, COL_RED, &
                                        abs(dev_pct) < 20.0_dp), abs(dev_pct) < 5.0_dp)
                        write(track_s, '("h",I2,"  actual ",F5.1," MW  plan ",F5.1," MW  (",SP,F5.1,"% dev)")') &
                            grid%da_current_hour, grid%gas_power_MW, plan_mw, dev_pct
                        call draw_text(hdc, ix, tile_y + 66, trim(adjustl(track_s)), dev_col)
                    end if
                end block
            end if
        else
            call draw_metric_tile(hdc, ix, tile_y, iw, 60, "Status", "Optimizer solving...", COL_MUTED)
        end if

        ! Layout: Gantt left (62%) + economics right (38%)
        left_w  = max(500, iw * 62 / 100)
        right_x = ix + left_w + 16
        right_w = max(280, iw - left_w - 16)

        call draw_section_title_width(hdc, ix, tile_y + 78, "24-hour commitment & dispatch schedule", left_w)
        ! Legend inline in the section title row (right-aligned)
        call fill_box(hdc, ix + left_w - 196, tile_y + 83, ix + left_w - 186, tile_y + 93, COL_LIME)
        call draw_text(hdc, ix + left_w - 182, tile_y + 81, "GT/disp", COL_MUTED)
        call fill_box(hdc, ix + left_w - 118, tile_y + 83, ix + left_w - 108, tile_y + 93, COL_LIME)
        call draw_text(hdc, ix + left_w - 104, tile_y + 81, "BESS +/-", COL_MUTED)
        call draw_text(hdc, ix + left_w - 36, tile_y + 81, "SoC--", COL_CYAN)
        ! Intraday re-dispatch alert: show when P2 optimizer sees >$50 improvement vs DA plan
        if (grid%da_solved .and. grid%da_redispatch_saving_usd > 50.0_dp) then
            write(lbl, '(">> Hour ",I2," re-dispatch  +$",I0," vs DA plan")') &
                grid%da_current_hour, nint(grid%da_redispatch_saving_usd)
            call draw_text(hdc, ix + left_w - 340, tile_y + 99, trim(adjustl(lbl)), COL_AMBER)
        end if
        call draw_dayahead_gantt(hdc, ix, tile_y + 118, left_w, max(200, height - 248))

        ! Trigger Pareto front computation if dirty (lazy, runs in engine tick)
        if (grid%pareto_dirty) call compute_pareto_front(grid)

        block
            integer :: rh_total, econ_h, pareto_y, pareto_h
            rh_total = max(200, height - 248)
            econ_h   = rh_total * 55 / 100
            pareto_y = tile_y + 118 + econ_h + 26
            pareto_h = max(100, rh_total - econ_h - 26)
            call draw_section_title_width(hdc, right_x, tile_y + 78, "Hourly economics & SoC", right_w)
            call draw_dayahead_economics(hdc, right_x, tile_y + 118, right_w, econ_h)
            call draw_section_title_width(hdc, right_x, pareto_y - 22, "Pareto front  (cost vs CO2)", right_w)
            call draw_pareto_panel(hdc, right_x, pareto_y, right_w, pareto_h)
        end block
    end subroutine draw_dayahead_screen

    ! -------------------------------------------------------------------------
    ! Gantt-style chart: GT commitment + dispatch + BESS + SoC over 24 hours.
    ! -------------------------------------------------------------------------
    subroutine draw_dayahead_gantt(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer, parameter :: DA_H_loc = 24   ! mirrors DA_H from engine_state
        integer :: gx, gy, gw, gh
        integer :: row_commit_h, row_dispatch_h, row_bess_h, row_soc_h
        integer :: row_commit_y, row_dispatch_y, row_bess_y, row_soc_y
        integer :: t, col_w, cx, bx, px, py, pxp, pyp
        integer :: commit_color
        real(dp) :: p_max, p_bess_max, soc_max
        real(dp) :: d_max, price_max, price_min, norm_p
        real(dp) :: frac
        character(len=8) :: lbl

        if (.not. grid%da_solved) then
            call fill_soft_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
            call draw_text(hdc, x + 20, y + height / 2 - 8, "No solution yet — optimizer runs every 5 s", COL_MUTED)
            return
        end if

        gx = x + 40; gy = y + 4
        gw = max(60, width - 48); gh = max(60, height - 16)

        ! Row heights: commit (10%) | dispatch (34%) | BESS (24%) | SoC (20%) | remainder for axis
        row_commit_h   = gh * 10 / 100
        row_dispatch_h = gh * 34 / 100
        row_bess_h     = gh * 24 / 100
        row_soc_h      = gh * 20 / 100

        row_commit_y   = gy
        row_dispatch_y = row_commit_y   + row_commit_h   + 4
        row_bess_y     = row_dispatch_y + row_dispatch_h + 4
        row_soc_y      = row_bess_y     + row_bess_h     + 4

        call fill_soft_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
        call stroke_soft_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)

        ! Match the solver's p_gt_max floor so frac = da_p_gt/p_max is always ≤ 1
        p_max     = max(grid%gas_capacity_MW, 80.0_dp)
        p_bess_max = STORAGE_MAX_MW
        soc_max    = BATTERY_CAPACITY_MWH

        ! Price shading background for dispatch row (darker = more expensive)
        price_max = max(maxval(grid%da_price), maxval(grid%da_price_hi))
        price_min = min(minval(grid%da_price), minval(grid%da_price_lo))
        col_w = max(1, gw / DA_H_loc)
        do t = 1, DA_H_loc
            cx = gx + (t - 1) * col_w
            norm_p = max(0.0_dp, min(1.0_dp, &
                (grid%da_price(t) - price_min) / max(price_max - price_min, 0.01_dp)))
            ! Background shade: dim amber for expensive hours
            if (norm_p > 0.5_dp) then
                call fill_box(hdc, cx, row_dispatch_y, cx + col_w, row_dispatch_y + row_dispatch_h, &
                    int(Z'00101820', c_int))
            end if
        end do

        ! Stochastic price fan: lo/hi scenario lines on commit row (thin colored tops)
        d_max = price_max; d_max = max(d_max, 1.0_dp)   ! reuse real variable as scale
        do t = 1, DA_H_loc
            cx = gx + (t - 1) * col_w + col_w / 2
            ! hi scenario tick (amber, top of commit row)
            bx = row_commit_y + 1
            if (grid%da_price_hi(t) > grid%da_price(t) + 0.5_dp) &
                call fill_box(hdc, cx - 1, bx, cx + 1, bx + 3, COL_AMBER)
            ! lo scenario tick (blue, bottom of commit row)
            bx = row_commit_y + row_commit_h - 4
            if (grid%da_price_lo(t) < grid%da_price(t) - 0.5_dp) &
                call fill_box(hdc, cx - 1, bx, cx + 1, bx + 3, COL_BLUE)
        end do

        ! Row backgrounds
        call fill_box(hdc, gx, row_commit_y,   gx + gw, row_commit_y   + row_commit_h,   COL_BG)
        call fill_box(hdc, gx, row_dispatch_y, gx + gw, row_dispatch_y + row_dispatch_h, COL_BG)
        call fill_box(hdc, gx, row_bess_y,     gx + gw, row_bess_y     + row_bess_h,     COL_BG)
        call fill_box(hdc, gx, row_soc_y,      gx + gw, row_soc_y      + row_soc_h,      COL_BG)
        call stroke_box(hdc, gx, row_commit_y,   gx + gw, row_commit_y   + row_commit_h,   COL_BORDER_SOFT, 1)
        call stroke_box(hdc, gx, row_dispatch_y, gx + gw, row_dispatch_y + row_dispatch_h, COL_BORDER_SOFT, 1)
        call stroke_box(hdc, gx, row_bess_y,     gx + gw, row_bess_y     + row_bess_h,     COL_BORDER_SOFT, 1)
        call stroke_box(hdc, gx, row_soc_y,      gx + gw, row_soc_y      + row_soc_h,      COL_BORDER_SOFT, 1)

        ! Row labels
        call draw_text(hdc, x + 4, row_commit_y   + 2, "GT", COL_MUTED)
        call draw_text(hdc, x + 4, row_dispatch_y + 2, "MW", COL_MUTED)
        call draw_text(hdc, x + 4, row_bess_y     + 2, "BESS", COL_MUTED)
        call draw_text(hdc, x + 4, row_soc_y      + 2, "SoC", COL_MUTED)

        ! Draw each hour column
        do t = 1, DA_H_loc
            cx = gx + (t - 1) * col_w

            ! Commitment bar
            commit_color = merge(COL_GREEN, COL_DIM, grid%da_commit(t) == 1)
            call fill_box(hdc, cx + 1, row_commit_y + 2, cx + col_w - 1, row_commit_y + row_commit_h - 2, commit_color)

            ! Dispatch bars (filled from bottom)
            if (grid%da_commit(t) == 1 .and. p_max > 0.0_dp) then
                frac = min(1.0_dp, grid%da_p_gt(t) / p_max)
                bx = row_dispatch_y + row_dispatch_h - nint(frac * real(row_dispatch_h, dp))
                bx = max(row_dispatch_y, bx)
                call fill_box(hdc, cx + 1, bx, cx + col_w - 1, row_dispatch_y + row_dispatch_h, COL_LIME)
            end if

            ! BESS bars: zero line at mid; discharge upward (lime), charge downward (blue)
            py = row_bess_y + row_bess_h / 2
            if (abs(grid%da_p_bess(t)) > 0.1_dp) then
                bx = nint(abs(grid%da_p_bess(t)) / p_bess_max * real(row_bess_h / 2, dp))
                bx = min(bx, row_bess_h / 2 - 1)
                if (grid%da_p_bess(t) > 0.0_dp) then
                    call fill_box(hdc, cx + 1, py - bx, cx + col_w - 1, py, COL_LIME)
                else
                    call fill_box(hdc, cx + 1, py, cx + col_w - 1, py + bx, COL_BLUE)
                end if
            end if
            call draw_line(hdc, gx, py, gx + gw, py, COL_BORDER_SOFT, 1)
        end do

        ! SoC trajectory line chart
        pxp = -1; pyp = -1
        do t = 1, DA_H_loc + 1
            px = gx + (t - 1) * col_w
            frac = max(0.0_dp, min(1.0_dp, grid%da_soc(t) / max(soc_max, 0.01_dp)))
            py = row_soc_y + row_soc_h - nint(frac * real(row_soc_h, dp))
            py = max(row_soc_y, min(row_soc_y + row_soc_h, py))
            if (t > 1 .and. pxp >= 0) call draw_line(hdc, pxp, pyp, px, py, COL_CYAN, 2)
            pxp = px; pyp = py
        end do

        ! X-axis hour labels
        py = row_soc_y + row_soc_h + 6
        call draw_text(hdc, gx, py, "0h", COL_DIM)
        call draw_text(hdc, gx + gw / 4 - 8, py, "6h", COL_DIM)
        call draw_text(hdc, gx + gw / 2 - 10, py, "12h", COL_DIM)
        call draw_text(hdc, gx + 3 * gw / 4 - 10, py, "18h", COL_DIM)
        call draw_text(hdc, gx + gw - 16, py, "24h", COL_DIM)

        ! Vertical hour ticks
        do t = 0, DA_H_loc, 6
            cx = gx + t * col_w
            call draw_line(hdc, cx, gy, cx, row_soc_y + row_soc_h, COL_BG_GRID, 1)
        end do

        ! Y-axis scale labels (p_max tick)
        write(lbl, '(I4)') nint(p_max)
        call draw_text(hdc, x + 2, row_dispatch_y + 2, trim(adjustl(lbl)), COL_DIM)
        call draw_text(hdc, x + 2, row_dispatch_y + row_dispatch_h - 14, "0", COL_DIM)
    end subroutine draw_dayahead_gantt

    ! -------------------------------------------------------------------------
    ! Right panel: hourly revenue vs cost bars + SoC trend numbers.
    ! -------------------------------------------------------------------------
    subroutine draw_dayahead_economics(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer, parameter :: DA_H_loc = 24
        integer :: t, row_y, bar_x, bar_w, bar_h_px, bar_max_h
        real(dp) :: p_max, hr, fc, cc, rev, net, max_rev
        real(dp) :: frac
        integer(c_int) :: bar_col
        character(len=48) :: lbl
        integer :: gx, gy, gw, gh, col_w, cx, py_zero, py_top

        if (.not. grid%da_solved) then
            call fill_soft_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
            call draw_text(hdc, x + 12, y + 20, "Waiting for solution...", COL_MUTED)
            return
        end if

        call fill_soft_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
        call stroke_soft_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)

        p_max = max(grid%gas_capacity_MW, 80.0_dp)   ! match solver floor

        ! Net margin per hour bar chart
        gx = x + 12; gy = y + 28
        gw = width - 24; gh = max(80, height / 2 - 16)

        call draw_text(hdc, gx, y + 10, "Net margin $/h (revenue - fuel - carbon)", COL_MUTED)
        call fill_box(hdc, gx, gy, gx + gw, gy + gh, COL_BG)
        call stroke_box(hdc, gx, gy, gx + gw, gy + gh, COL_BORDER_SOFT, 1)

        ! Find max |net| for scaling
        max_rev = 1.0_dp
        do t = 1, DA_H_loc
            hr  = 9200.0_dp + 4600.0_dp * (1.0_dp - grid%da_p_gt(t) / p_max) ** 2
            fc  = grid%da_p_gt(t) * hr * grid%fuel_price_usd_gj / 1000.0_dp
            cc  = grid%da_p_gt(t) * 1000.0_dp * hr * CO2_KG_PER_KG_FUEL * &
                  grid%carbon_price_usd_t / (50000.0_dp * 1000.0_dp)
            rev = grid%da_price(t) * grid%da_demand(t)
            net = rev - fc - cc
            max_rev = max(max_rev, abs(net))
        end do

        col_w   = max(1, gw / DA_H_loc)
        py_zero = gy + gh / 2
        bar_max_h = gh / 2 - 2
        call draw_line(hdc, gx, py_zero, gx + gw, py_zero, COL_BORDER_SOFT, 1)

        do t = 1, DA_H_loc
            cx = gx + (t - 1) * col_w
            if (grid%da_commit(t) == 1) then
                hr  = 9200.0_dp + 4600.0_dp * (1.0_dp - grid%da_p_gt(t) / p_max) ** 2
                fc  = grid%da_p_gt(t) * hr * grid%fuel_price_usd_gj / 1000.0_dp
                cc  = grid%da_p_gt(t) * 1000.0_dp * hr * CO2_KG_PER_KG_FUEL * &
                      grid%carbon_price_usd_t / (50000.0_dp * 1000.0_dp)
                rev = grid%da_price(t) * grid%da_demand(t)
                net = rev - fc - cc
            else
                net = 0.0_dp
            end if
            bar_h_px = min(bar_max_h, nint(abs(net) / max_rev * real(bar_max_h, dp)))
            bar_col  = merge(COL_GREEN, COL_RED, net >= 0.0_dp)
            if (net >= 0.0_dp) then
                call fill_box(hdc, cx + 1, py_zero - bar_h_px, cx + col_w - 1, py_zero, bar_col)
            else
                call fill_box(hdc, cx + 1, py_zero, cx + col_w - 1, py_zero + bar_h_px, bar_col)
            end if
        end do

        ! X labels
        call draw_text(hdc, gx, gy + gh + 4, "0h", COL_DIM)
        call draw_text(hdc, gx + gw / 2 - 8, gy + gh + 4, "12h", COL_DIM)
        call draw_text(hdc, gx + gw - 16, gy + gh + 4, "24h", COL_DIM)

        ! Summary table
        row_y = gy + gh + 24
        write(lbl, '("GT hours on:   ",I2," / 24")') sum(grid%da_commit)
        call draw_text(hdc, x + 12, row_y, trim(lbl), COL_INK)
        row_y = row_y + 18
        write(lbl, '("Operating cost: $",I0)') nint(grid%da_cost_usd)
        call draw_text(hdc, x + 12, row_y, trim(lbl), COL_AMBER)
        row_y = row_y + 18
        write(lbl, '("Revenue:        $",I0)') nint(grid%da_revenue_usd)
        call draw_text(hdc, x + 12, row_y, trim(lbl), COL_GREEN)
        row_y = row_y + 18
        net = grid%da_revenue_usd - grid%da_cost_usd
        write(lbl, '("Net margin:    $",SP,I0)') nint(net)
        call draw_text(hdc, x + 12, row_y, trim(lbl), merge(COL_GREEN, COL_RED, net >= 0.0_dp))
        row_y = row_y + 22
        write(lbl, '("MUT=2 MDT=1  N_SOC=50  N_PGT=20  LP-gap ",F5.1,"%")') grid%da_gap_pct
        call draw_text(hdc, x + 12, row_y, trim(adjustl(lbl)), COL_DIM)
        row_y = row_y + 18
        if (grid%dnn_active) then
            write(lbl, '("DNN+DP  HR surrogate MAE ",F5.1," kJ/kWh")') grid%dnn_hr_mae
            call draw_text(hdc, x + 12, row_y, trim(adjustl(lbl)), COL_CYAN)
        else
            call draw_text(hdc, x + 12, row_y, "POLY+DP  (run train_dnn.py for DNN)", COL_DIM)
        end if
    end subroutine draw_dayahead_economics

    ! =========================================================================
    ! Compressor washing ROI panel — shown on F3 below the P2 optimizer.
    ! Quantifies the fuel-cost penalty from fouling and the wash breakeven.
    ! =========================================================================
    subroutine draw_washing_roi_panel(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        character(len=80) :: lbl
        integer :: row_y
        integer(c_int) :: hr_col

        call fill_soft_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
        call stroke_soft_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)

        hr_col = merge(COL_RED, merge(COL_AMBER, COL_GREEN, &
            grid%wash_hr_gap_pct > 5.0_dp), grid%wash_hr_gap_pct > 15.0_dp)

        row_y = y + 8
        write(lbl, '("HR gap (fouling):   +",F4.1,"% (+",I4," kJ/kWh)")') &
            grid%wash_hr_gap_pct, nint(grid%wash_hr_gap_pct * 92.0_dp)
        call draw_text(hdc, x + 10, row_y, trim(adjustl(lbl)), hr_col)
        row_y = row_y + 18
        write(lbl, '("Fuel penalty:        $",I0,"/day")') nint(grid%wash_daily_saving_usd)
        call draw_text(hdc, x + 10, row_y, trim(adjustl(lbl)), COL_AMBER)
        row_y = row_y + 18
        if (grid%wash_breakeven_days < 900.0_dp) then
            write(lbl, '("Wash breakeven:      ",F5.1," days  (fee $2500 + 6h down)")') &
                grid%wash_breakeven_days
        else
            write(lbl, '("Wash breakeven:      N/A — HR gap < 0.1 %")')
        end if
        call draw_text(hdc, x + 10, row_y, trim(adjustl(lbl)), COL_MUTED)
        if (height <= 74) return
        row_y = row_y + 22
        if (grid%wash_hr_gap_pct > 5.0_dp .and. grid%wash_breakeven_days < 30.0_dp) then
            write(lbl, '(">> Wash now: saves $",I0,"/day in fuel  (P2 already penalised)")') &
                nint(grid%wash_daily_saving_usd)
            call draw_text(hdc, x + 10, row_y, trim(adjustl(lbl)), COL_LIME)
        else if (grid%wash_hr_gap_pct > 2.0_dp) then
            write(lbl, '("Monitor: gap rising — optimal window ~",I0," days")') &
                nint(grid%wash_breakeven_days)
            call draw_text(hdc, x + 10, row_y, trim(adjustl(lbl)), COL_CYAN)
        else
            write(lbl, '("Clean: heat-rate within design band  (gap < 2%)")')
            call draw_text(hdc, x + 10, row_y, trim(adjustl(lbl)), COL_GREEN)
        end if
    end subroutine draw_washing_roi_panel

    ! =========================================================================
    ! Structured CSV export — full shift data from all tabs (key 'E' or EXPORT CSV button).
    ! =========================================================================
    subroutine export_shift_csv(st)
        type(GridState), intent(in) :: st
        integer :: iunit, ios, t, i
        character(len=80) :: filename
        character(len=4)  :: unitname

        write(filename, '("shift_data_t",I0,".csv")') nint(st%elapsed_s)
        open(newunit=iunit, file=trim(filename), status='replace', action='write', iostat=ios)
        if (ios /= 0) return

        write(iunit, '("# ThermoTwin-F Shift Data Export")')
        write(iunit, '("# t=",F10.1," s")') st%elapsed_s

        call write_report_meta(iunit, filename, st)
        call write_advisory_export(iunit, st)
        call write_active_screen_export(iunit, st)

        ! [SUMMARY] — scalar fields from all HMI tabs
        write(iunit, '(a)') ''
        write(iunit, '("[SUMMARY]")')
        write(iunit, '("field,value,unit")')
        write(iunit, '("elapsed_s,",F12.3,",s")') st%elapsed_s
        write(iunit, '("demand_MW,",F10.4,",MW")') st%demand_MW
        write(iunit, '("frequency_Hz,",F12.6,",Hz")') st%frequency_Hz
        write(iunit, '("ROCOF_Hz_s,",F10.6,",Hz/s")') st%ROCOF_Hz_s
        write(iunit, '("reserve_MW,",F10.4,",MW")') st%reserve_MW
        write(iunit, '("gas_power_MW,",F10.4,",MW")') st%gas_power_MW
        write(iunit, '("gas_capacity_MW,",F10.4,",MW")') st%gas_capacity_MW
        write(iunit, '("gas_dispatch_pct,",F10.4,",pct")') st%gas_dispatch_pct
        write(iunit, '("gt_heat_rate_kJ_kWh,",F10.4,",kJ/kWh")') st%gt_heat_rate_kJ_kWh
        write(iunit, '("plant_efficiency,",F12.8,",-")') st%plant_efficiency
        write(iunit, '("flame_temp_ad_K,",F10.4,",K")') st%flame_temp_ad_K
        write(iunit, '("nox_mg_nm3_15o2,",F10.4,",mg/Nm3")') st%nox_mg_nm3_15o2
        write(iunit, '("co_mg_nm3_15o2,",F10.4,",mg/Nm3")') st%co_mg_nm3_15o2
        write(iunit, '("flashback_margin_pct,",F10.4,",pct")') st%flashback_margin_pct
        write(iunit, '("cooling_air_pct,",F10.4,",pct")') st%turbine_cooling_air_pct
        write(iunit, '("tip_loss_pct,",F10.4,",pct")') st%tip_loss_pct
        write(iunit, '("battery_soc_pct,",F10.4,",pct")') st%battery_soc_pct
        write(iunit, '("battery_energy_MWh,",F10.4,",MWh")') st%battery_energy_MWh
        write(iunit, '("fuel_price_usd_gj,",F10.4,",USD/GJ")') st%fuel_price_usd_gj
        write(iunit, '("power_price_usd_mwh,",F10.4,",USD/MWh")') st%power_price_usd_mwh
        write(iunit, '("carbon_price_usd_t,",F10.4,",USD/t")') st%carbon_price_usd_t
        write(iunit, '("renewable_MW,",F10.4,",MW")') st%renewable_MW
        write(iunit, '("fleet_total_MW,",F10.4,",MW")') st%fleet_total_MW
        write(iunit, '("fleet_lmp_usd_MWh,",F10.4,",USD/MWh")') st%fleet_lmp_usd_MWh
        write(iunit, '("fleet_uc_total_cost_h,",F12.4,",USD/h")') st%fleet_uc_total_cost_h
        write(iunit, '("da_cost_usd,",F12.2,",USD")') st%da_cost_usd
        write(iunit, '("da_revenue_usd,",F12.2,",USD")') st%da_revenue_usd
        write(iunit, '("da_gap_pct,",F10.4,",pct")') st%da_gap_pct
        write(iunit, '("da_current_hour,",I0,",h")') st%da_current_hour
        write(iunit, '("da_redispatch_saving_usd,",F10.2,",USD")') st%da_redispatch_saving_usd
        write(iunit, '("gt_opt_best_margin,",F10.4,",USD/h")') st%gt_opt_best_margin
        write(iunit, '("gt_opt_saving_h,",F10.4,",USD/h")') st%gt_opt_saving_h
        write(iunit, '("wash_hr_gap_pct,",F10.4,",pct")') st%wash_hr_gap_pct
        write(iunit, '("wash_daily_saving_usd,",F10.2,",USD/day")') st%wash_daily_saving_usd
        write(iunit, '("wash_breakeven_days,",F10.4,",days")') st%wash_breakeven_days
        write(iunit, '("dnn_active,",L1,",bool")') st%dnn_active
        write(iunit, '("dnn_hr_mae,",F8.2,",kJ/kWh")') st%dnn_hr_mae
        write(iunit, '("model_val_ready,",L1,",bool")') st%model_val_ready
        write(iunit, '("model_val_n,",I0,",count")') st%model_val_n
        write(iunit, '("model_val_cycle_power_mae_MW,",F10.4,",MW")') st%model_val_cycle_power_mae_MW
        write(iunit, '("model_val_cycle_power_bias_MW,",F10.4,",MW")') st%model_val_cycle_power_bias_MW
        write(iunit, '("model_val_cycle_hr_mae_kJ_kWh,",F10.4,",kJ/kWh")') st%model_val_cycle_hr_mae_kJ_kWh
        write(iunit, '("model_val_cycle_hr_bias_kJ_kWh,",F10.4,",kJ/kWh")') st%model_val_cycle_hr_bias_kJ_kWh
        write(iunit, '("model_val_dnn_available,",L1,",bool")') st%model_val_dnn_available
        write(iunit, '("model_val_dnn_hr_mae_kJ_kWh,",F10.4,",kJ/kWh")') st%model_val_dnn_hr_mae_kJ_kWh
        write(iunit, '("model_val_dnn_hr_bias_kJ_kWh,",F10.4,",kJ/kWh")') st%model_val_dnn_hr_bias_kJ_kWh
        write(iunit, '("model_val_dnn_hr_max_abs_kJ_kWh,",F10.4,",kJ/kWh")') st%model_val_dnn_hr_max_abs_kJ_kWh
        write(iunit, '("model_val_worst_idx,",I0,",index")') st%model_val_worst_idx
        write(iunit, '("physics_fidelity_ready,",L1,",bool")') st%physics_fidelity_ready
        write(iunit, '("physics_gt_hr_ref_kJ_kWh,",F10.4,",kJ/kWh")') st%physics_gt_hr_ref_kJ_kWh
        write(iunit, '("physics_gt_hr_gap_pct,",F10.4,",pct")') st%physics_gt_hr_gap_pct
        write(iunit, '("physics_hrsg_pinch_ref_K,",F10.4,",K")') st%physics_hrsg_pinch_ref_K
        write(iunit, '("physics_hrsg_pinch_gap_K,",F10.4,",K")') st%physics_hrsg_pinch_gap_K
        write(iunit, '("mpc_active,",L1,",bool")') st%mpc_active
        write(iunit, '("mpc_horizon_ready,",L1,",bool")') st%mpc_horizon_ready
        write(iunit, '("mpc_setpt_MW,",F10.4,",MW")') st%mpc_setpt_MW
        write(iunit, '("mpc_cost_last,",F10.4,",index")') st%mpc_cost_last
        write(iunit, '("mpc_cost_hold,",F10.4,",index")') st%mpc_cost_hold
        write(iunit, '("mpc_cost_saving,",F10.4,",index")') st%mpc_cost_saving

        ! [MODEL_VALIDATION] - compact C1 validation block for reporting.
        write(iunit, '(a)') ''
        write(iunit, '("[MODEL_VALIDATION]")')
        write(iunit, '("metric,mae,bias,max_abs,unit")')
        write(iunit, '("cycle_power,",F10.4,",",F10.4,",",F10.4,",MW")') &
            st%model_val_cycle_power_mae_MW, st%model_val_cycle_power_bias_MW, 0.0_dp
        write(iunit, '("cycle_heat_rate,",F10.4,",",F10.4,",",F10.4,",kJ/kWh")') &
            st%model_val_cycle_hr_mae_kJ_kWh, st%model_val_cycle_hr_bias_kJ_kWh, 0.0_dp
        write(iunit, '("dnn_heat_rate,",F10.4,",",F10.4,",",F10.4,",kJ/kWh")') &
            st%model_val_dnn_hr_mae_kJ_kWh, st%model_val_dnn_hr_bias_kJ_kWh, &
            st%model_val_dnn_hr_max_abs_kJ_kWh

        ! [MPC_HORIZON] - C2 receding-horizon preview.
        write(iunit, '(a)') ''
        write(iunit, '("[MPC_HORIZON]")')
        write(iunit, '("step,time_s,freq_Hz,pgen_MW,setpt_MW,imbalance_MW")')
        do i = 1, size(st%mpc_pred_freq_Hz)
            write(iunit, '(I2,",",F8.2,",",F10.6,",",F9.4,",",F9.4,",",F9.4)') &
                i, st%mpc_pred_time_s(i), st%mpc_pred_freq_Hz(i), st%mpc_pred_pgen_MW(i), &
                st%mpc_pred_setpt_MW(i), st%mpc_pred_imbalance_MW(i)
        end do

        ! [PHYSICS_FIDELITY] - C3 reference-map overlays used by F1/F3/F4.
        write(iunit, '(a)') ''
        write(iunit, '("[PHYSICS_FIDELITY]")')
        write(iunit, '("idx,load_pct,gt_ref_hr_kJ_kWh,hrsg_ref_pinch_K")')
        do i = 1, FIDELITY_N
            write(iunit, '(I2,",",F7.2,",",F10.4,",",F9.4)') &
                i, st%physics_load_pct(i), st%physics_ref_gt_hr_kJ_kWh(i), &
                st%physics_ref_hrsg_pinch_K(i)
        end do

        ! [DA_SCHEDULE] — 24-hour day-ahead plan
        write(iunit, '(a)') ''
        write(iunit, '("[DA_SCHEDULE]")')
        write(iunit, '("hour,commit,p_gt_MW,p_bess_MW,soc_MWh,price_usd_MWh,demand_MW,price_lo,price_hi")')
        do t = 1, DA_H
            write(iunit, '(I2,",",I1,",",F9.4,",",F9.4,",",F8.4,",",F8.4,",",F8.4,",",F8.4,",",F8.4)') &
                t, st%da_commit(t), st%da_p_gt(t), st%da_p_bess(t), &
                st%da_soc(t), st%da_price(t), st%da_demand(t), &
                st%da_price_lo(t), st%da_price_hi(t)
        end do

        ! [GT_OPTIMIZER] — P2 dispatch curve (20 scan points)
        write(iunit, '(a)') ''
        write(iunit, '("[GT_OPTIMIZER]")')
        write(iunit, '("idx,power_MW,heat_rate_kJ_kWh,margin_usd_h")')
        do i = 1, GT_OPT_N
            write(iunit, '(I3,",",F9.4,",",F10.4,",",F10.4)') &
                i, st%gt_opt_pwr(i), st%gt_opt_hr(i), st%gt_opt_margin(i)
        end do

        ! [FLEET_UC] — 3-unit merit-order dispatch
        write(iunit, '(a)') ''
        write(iunit, '("[FLEET_UC]")')
        write(iunit, '("unit_id,name,online,capacity_MW,dispatch_MW,cost_usd_MWh,heat_rate_kJ_kWh")')
        do i = 1, FLEET_N
            select case (i)
            case (FLEET_GT1); unitname = 'GT1'
            case (FLEET_GT2); unitname = 'GT2'
            case (FLEET_CC1); unitname = 'CC1'
            case default;     unitname = 'UNK'
            end select
            write(iunit, '(I2,",",A4,",",I1,",",F9.4,",",F9.4,",",F9.4,",",F10.4)') &
                i, unitname, merge(1, 0, st%fleet_unit_online(i)), &
                st%fleet_unit_capacity_MW(i), st%fleet_uc_p(i), &
                st%fleet_unit_cost_usd_MWh(i), st%fleet_unit_heat_rate_kJ_kWh(i)
        end do

        ! [HISTORY] — 240-sample ring buffer (60 s at 250 ms)
        write(iunit, '(a)') ''
        write(iunit, '("[HISTORY]")')
        write(iunit, '("sample_idx,freq_Hz,demand_MW,gas_pct")')
        do i = 1, HISTORY_N
            write(iunit, '(I4,",",F10.6,",",F8.4,",",F7.3)') &
                i, st%hist_frequency_Hz(i), st%hist_demand_MW(i), st%hist_gas_dispatch_pct(i)
        end do

        ! [ALARMS] — active alarm states
        write(iunit, '(a)') ''
        write(iunit, '("[ALARMS]")')
        write(iunit, '("severity,description")')
        if (st%alarm_surge)       write(iunit, '("CRITICAL,Compressor surge")')
        if (st%alarm_turbine_max) write(iunit, '("CRITICAL,TIT at maximum")')
        if (st%alarm_ufls_active) write(iunit, '("HIGH,UFLS active")')
        if (st%alarm_underfreq)   write(iunit, '("HIGH,Under-frequency")')
        if (st%alarm_overfreq)    write(iunit, '("HIGH,Over-frequency")')
        if (st%alarm_low_reserve) write(iunit, '("MEDIUM,Low reserve")')
        if (st%alarm_low_soc)     write(iunit, '("MEDIUM,Low BESS SoC")')
        if (st%alarm_hrsg_pinch)  write(iunit, '("MEDIUM,HRSG pinch alarm")')

        ! [7.0-P7] Full scientific analysis report (exergy + UQ + Sobol + limits + V&V)
        write(iunit, '(a)') ''
        write(iunit, '("[SCIENTIFIC_ANALYSIS]")')
        call write_scientific_report(iunit, st)

        close(iunit)
        call log_debug("CSV export: "//trim(filename))
    end subroutine export_shift_csv

    ! Launch Python PDF report generator against the most recent CSV export.
    subroutine launch_pdf_report(st)
        type(GridState), intent(in) :: st
        character(len=120) :: cmd
        character(len=80)  :: csvname
        write(csvname, '("shift_data_t",I0,".csv")') nint(st%elapsed_s)
        write(cmd, '("python generate_report.py ",A)') trim(csvname)
        call execute_command_line(trim(cmd), wait=.false.)
        call log_debug("PDF report launched: "//trim(csvname))
    end subroutine launch_pdf_report

    subroutine write_report_meta(iunit, filename, st)
        integer, intent(in) :: iunit
        character(len=*), intent(in) :: filename
        type(GridState), intent(in) :: st
        character(len=8) :: date_s
        character(len=10) :: time_s
        character(len=24) :: mode_s, plant_s

        call date_and_time(date=date_s, time=time_s)
        if (st%auto_balance) then
            mode_s = "AUTO"
        else
            mode_s = "MANUAL"
        end if
        if (st%fleet_mode) then
            plant_s = "FLEET"
        else if (st%combined_cycle) then
            plant_s = "COMBINED_CYCLE"
        else
            plant_s = "GT_ONLY"
        end if
        write(iunit, '(a)') ''
        write(iunit, '("[REPORT_META]")')
        write(iunit, '("field,value,unit")')
        call write_csv_metric_text(iunit, "product", "ThermoTwin-F", "-")
        call write_csv_metric_text(iunit, "report_type", "Operations HMI export", "-")
        call write_csv_metric_text(iunit, "csv_file", trim(filename), "-")
        call write_csv_metric_text(iunit, "generated_date", trim(date_s), "YYYYMMDD")
        call write_csv_metric_text(iunit, "generated_time", trim(time_s), "HHMMSS.sss")
        call write_csv_metric_int(iunit, "active_screen_id", hmi_screen, "-")
        call write_csv_metric_text(iunit, "active_screen", trim(SCREEN_FULL_LABEL(hmi_screen)), "-")
        call write_csv_metric_text(iunit, "power_zone", trim(st%market_power_zone), "-")
        call write_csv_metric_text(iunit, "market_profile", trim(st%market_profile_name), "-")
        call write_csv_metric_text(iunit, "dispatch_mode", trim(mode_s), "-")
        call write_csv_metric_text(iunit, "plant_mode", trim(plant_s), "-")
        call write_csv_metric_text(iunit, "advisory_severity", advisory_severity(st), "-")
    end subroutine write_report_meta

    subroutine write_advisory_export(iunit, st)
        integer, intent(in) :: iunit
        type(GridState), intent(in) :: st
        character(len=2048) :: adv
        character(len=256) :: part
        integer :: start, last, rel, n

        write(iunit, '(a)') ''
        write(iunit, '("[ADVISORY]")')
        write(iunit, '("line_no,severity,text")')
        adv = st%advisory_text
        last = len_trim(adv)
        if (last <= 0) then
            call write_csv_record3(iunit, "1", advisory_severity(st), "STATUS OK - no advisory text")
            return
        end if

        start = 1
        n = 0
        do while (start <= last .and. n < 18)
            rel = index(adv(start:last), char(10))
            if (rel <= 0) then
                part = adv(start:last)
                start = last + 1
            else
                if (rel > 1) then
                    part = adv(start:start + rel - 2)
                else
                    part = ""
                end if
                start = start + rel
            end if
            if (len_trim(part) <= 0) cycle
            n = n + 1
            call write_csv_record3(iunit, trim(int_to_text(n)), advisory_severity(st), trim(part))
        end do
        if (n == 0) call write_csv_record3(iunit, "1", advisory_severity(st), &
            "STATUS OK - advisory text empty")
    end subroutine write_advisory_export

    subroutine write_active_screen_export(iunit, st)
        integer, intent(in) :: iunit
        type(GridState), intent(in) :: st
        integer :: n_alm
        type(ExergyResult) :: ex

        n_alm = active_alarm_count(st)
        write(iunit, '(a)') ''
        write(iunit, '("[ACTIVE_SCREEN]")')
        write(iunit, '("metric,value,unit")')
        call write_csv_metric_text(iunit, "screen", trim(SCREEN_FULL_LABEL(hmi_screen)), "-")
        call write_csv_metric_text(iunit, "zone", trim(st%market_power_zone), "-")
        call write_csv_metric_real(iunit, "elapsed_s", st%elapsed_s, "s")
        call write_csv_metric_real(iunit, "frequency_Hz", st%frequency_Hz, "Hz")
        call write_csv_metric_real(iunit, "demand_MW", st%demand_MW, "MW")
        call write_csv_metric_real(iunit, "supply_MW", st%supply_MW, "MW")
        call write_csv_metric_real(iunit, "imbalance_MW", st%imbalance_MW, "MW")
        call write_csv_metric_int(iunit, "active_alarm_count", n_alm, "count")

        select case (hmi_screen)
        case (SCREEN_OVERVIEW)
            call write_csv_metric_int(iunit, "plant_health_score", plant_health_score(), "score")
            call write_csv_metric_real(iunit, "net_margin_usd_h", st%margin_usd_h, "USD/h")
            call write_csv_metric_real(iunit, "CO2_intensity_g_kWh", st%CO2_intensity_g_kWh, "g/kWh")
            call write_csv_metric_real(iunit, "reserve_MW", merge(st%fleet_reserve_MW, st%reserve_MW, st%fleet_mode), "MW")
            call write_csv_metric_real(iunit, "value_stack_usd_h", st%value_stack_usd_h, "USD/h")
        case (SCREEN_GRID)
            call write_csv_metric_real(iunit, "ROCOF_Hz_s", st%ROCOF_Hz_s, "Hz/s")
            call write_csv_metric_real(iunit, "BESS_primary_MW", st%BESS_primary_MW, "MW")
            call write_csv_metric_int(iunit, "UFLS_stage", st%UFLS_stage, "stage")
            call write_csv_metric_real(iunit, "governor_delta_MW", st%governor_delta_MW, "MW")
            call write_csv_metric_real(iunit, "mpc_setpt_MW", st%mpc_setpt_MW, "MW")
        case (SCREEN_GT)
            call write_csv_metric_real(iunit, "gas_power_MW", st%gas_power_MW, "MW")
            call write_csv_metric_real(iunit, "gas_dispatch_pct", st%gas_dispatch_pct, "pct")
            call write_csv_metric_real(iunit, "TIT_actual_K", st%TIT_actual_K, "K")
            call write_csv_metric_real(iunit, "surge_margin_pct", st%surge_margin_pct, "pct")
            call write_csv_metric_real(iunit, "gt_heat_rate_kJ_kWh", st%gt_heat_rate_kJ_kWh, "kJ/kWh")
            call write_csv_metric_real(iunit, "physics_gt_hr_gap_pct", st%physics_gt_hr_gap_pct, "pct")
        case (SCREEN_CC)
            call write_csv_metric_logical(iunit, "combined_cycle", st%combined_cycle, "bool")
            call write_csv_metric_real(iunit, "steam_power_MW", st%steam_power_MW, "MW")
            call write_csv_metric_real(iunit, "hrsg_pinch_K", st%hrsg_pinch_K, "K")
            call write_csv_metric_real(iunit, "hrsg_pinch_gap_K", st%physics_hrsg_pinch_gap_K, "K")
            call write_csv_metric_real(iunit, "hrsg_stack_T_K", st%hrsg_stack_T_K, "K")
            call write_csv_metric_real(iunit, "plant_efficiency", st%plant_efficiency, "-")
        case (SCREEN_MARKET)
            call write_csv_metric_real(iunit, "power_price_usd_mwh", st%power_price_usd_mwh, "USD/MWh")
            call write_csv_metric_real(iunit, "carbon_price_usd_t", st%carbon_price_usd_t, "USD/t")
            call write_csv_metric_real(iunit, "revenue_usd_h", st%revenue_usd_h, "USD/h")
            call write_csv_metric_real(iunit, "margin_usd_h", st%margin_usd_h, "USD/h")
            call write_csv_metric_real(iunit, "wind_power_MW", st%market_wind_power_MW, "MW")
            call write_csv_metric_real(iunit, "pv_power_MW", st%market_pv_power_MW, "MW")
        case (SCREEN_TRENDS)
            call write_csv_metric_int(iunit, "history_count", st%history_count, "samples")
            call write_csv_metric_real(iunit, "hist_latest_frequency_Hz", st%frequency_Hz, "Hz")
            call write_csv_metric_real(iunit, "hist_latest_demand_MW", st%demand_MW, "MW")
            call write_csv_metric_real(iunit, "hist_latest_gas_dispatch_pct", st%gas_dispatch_pct, "pct")
        case (SCREEN_ALARMS)
            call write_csv_metric_logical(iunit, "alarm_surge", st%alarm_surge, "bool")
            call write_csv_metric_logical(iunit, "alarm_turbine_max", st%alarm_turbine_max, "bool")
            call write_csv_metric_logical(iunit, "alarm_ufls_active", st%alarm_ufls_active, "bool")
            call write_csv_metric_logical(iunit, "alarm_low_reserve", st%alarm_low_reserve, "bool")
            call write_csv_metric_logical(iunit, "alarm_low_soc", st%alarm_low_soc, "bool")
            call write_csv_metric_logical(iunit, "alarm_hrsg_pinch", st%alarm_hrsg_pinch, "bool")
        case (SCREEN_DIAG)
            call write_csv_metric_real(iunit, "anom_composite", st%anom_composite, "score")
            call write_csv_metric_int(iunit, "fault_class_1", st%fc_class1, "class")
            call write_csv_metric_real(iunit, "fault_conf_1", st%fc_conf1, "prob")
            call write_csv_metric_real(iunit, "compressor_life_pct", st%lcf_comp_life_pct, "pct")
            call write_csv_metric_real(iunit, "hot_section_life_pct", st%lcf_hst_life_pct, "pct")
            call write_csv_metric_real(iunit, "hrsg_life_pct", st%lcf_hrsg_life_pct, "pct")
        case (SCREEN_DAYAHEAD)
            call write_csv_metric_logical(iunit, "da_solved", st%da_solved, "bool")
            call write_csv_metric_real(iunit, "da_revenue_usd", st%da_revenue_usd, "USD")
            call write_csv_metric_real(iunit, "da_cost_usd", st%da_cost_usd, "USD")
            call write_csv_metric_real(iunit, "da_net_usd", st%da_revenue_usd - st%da_cost_usd, "USD")
            call write_csv_metric_real(iunit, "da_gap_pct", st%da_gap_pct, "pct")
            call write_csv_metric_real(iunit, "da_redispatch_saving_usd", st%da_redispatch_saving_usd, "USD")
        case (SCREEN_FLEET_UC)
            call write_csv_metric_logical(iunit, "fleet_mode", st%fleet_mode, "bool")
            call write_csv_metric_real(iunit, "fleet_total_MW", st%fleet_total_MW, "MW")
            call write_csv_metric_real(iunit, "fleet_reserve_MW", st%fleet_reserve_MW, "MW")
            call write_csv_metric_real(iunit, "fleet_lmp_usd_MWh", st%fleet_lmp_usd_MWh, "USD/MWh")
            call write_csv_metric_real(iunit, "fleet_uc_total_cost_h", st%fleet_uc_total_cost_h, "USD/h")
            call write_csv_metric_int(iunit, "fleet_marginal_unit", st%fleet_marginal_unit, "unit")
        case (SCREEN_DNN)
            call write_csv_metric_logical(iunit, "dnn_active", st%dnn_active, "bool")
            call write_csv_metric_real(iunit, "dnn_hr_mae", st%dnn_hr_mae, "kJ/kWh")
            call write_csv_metric_logical(iunit, "model_val_ready", st%model_val_ready, "bool")
            call write_csv_metric_real(iunit, "model_val_cycle_power_mae_MW", st%model_val_cycle_power_mae_MW, "MW")
            call write_csv_metric_real(iunit, "model_val_dnn_hr_mae_kJ_kWh", st%model_val_dnn_hr_mae_kJ_kWh, "kJ/kWh")
        case (SCREEN_CARBON)
            call write_csv_metric_real(iunit, "h2_fraction_pct", st%h2_fraction_pct, "pct")
            call write_csv_metric_real(iunit, "h2_mass_fraction_pct", 100.0_dp * st%h2_mass_fraction, "pct")
            call write_csv_metric_real(iunit, "h2_wobbe_mj_m3", st%h2_wobbe_mj_m3, "MJ/m3")
            call write_csv_metric_real(iunit, "h2_wobbe_deviation_pct", st%h2_wobbe_deviation_pct, "pct")
            call write_csv_metric_logical(iunit, "h2_wobbe_ok", st%h2_wobbe_ok, "bool")
            call write_csv_metric_real(iunit, "flame_temp_ad_K", st%flame_temp_ad_K, "K")
            call write_csv_metric_real(iunit, "flame_temp_shift_K", st%flame_temp_shift_K, "K")
            call write_csv_metric_real(iunit, "nox_ppm_15o2", st%nox_ppm_15o2, "ppm")
            call write_csv_metric_real(iunit, "nox_mg_nm3_15o2", st%nox_mg_nm3_15o2, "mg/Nm3")
            call write_csv_metric_real(iunit, "co_ppm_15o2", st%co_ppm_15o2, "ppm")
            call write_csv_metric_real(iunit, "co_mg_nm3_15o2", st%co_mg_nm3_15o2, "mg/Nm3")
            call write_csv_metric_real(iunit, "flashback_margin_pct", st%flashback_margin_pct, "pct")
            call write_csv_metric_real(iunit, "cooling_air_pct", st%turbine_cooling_air_pct, "pct")
            call write_csv_metric_real(iunit, "cooling_air_kg_s", st%turbine_cooling_air_kg_s, "kg/s")
            call write_csv_metric_real(iunit, "tip_clearance_mm", st%tip_clearance_mm, "mm")
            call write_csv_metric_real(iunit, "tip_loss_pct", st%tip_loss_pct, "pct")
            call write_csv_metric_real(iunit, "CO2_rate_kg_s", st%CO2_rate_kg_s, "kg/s")
            call write_csv_metric_real(iunit, "CO2_intensity_g_kWh", st%CO2_intensity_g_kWh, "g/kWh")
            call write_csv_metric_real(iunit, "CO2_cumulative_t", st%CO2_cumulative_t, "t")
            call write_csv_metric_real(iunit, "ccs_co2_captured_t_h", st%ccs_co2_captured_t_h, "t/h")
        case (SCREEN_FORECAST)
            call write_csv_metric_real(iunit, "forecast_demand_now_MW", st%fcast_demand(1), "MW")
            call write_csv_metric_real(iunit, "forecast_demand_4h_MW", st%fcast_demand(FC_N), "MW")
            call write_csv_metric_real(iunit, "forecast_price_now_usd_mwh", st%fcast_price(1), "USD/MWh")
            call write_csv_metric_real(iunit, "forecast_price_4h_usd_mwh", st%fcast_price(FC_N), "USD/MWh")
        case (SCREEN_ADVISORY)
            call write_csv_metric_text(iunit, "advisory_severity", advisory_severity(st), "-")
            call write_csv_metric_text(iunit, "advisory_headline", advisory_headline(st), "-")
            call write_csv_metric_real(iunit, "anom_composite", st%anom_composite, "score")
            call write_csv_metric_real(iunit, "net_margin_usd_h", st%margin_usd_h, "USD/h")
        case (SCREEN_SCENARIO)
            call write_csv_metric_text(iunit, "scenario_A", trim(SCN_LABEL(scn_selected)), "-")
            call write_csv_metric_text(iunit, "scenario_B", trim(SCN_LABEL(scn_compare_selected)), "-")
            call write_csv_metric_logical(iunit, "comparison_ready", scn_cmp%ready, "bool")
            if (scn_cmp%ready) then
                call write_csv_metric_real(iunit, "delta_min_frequency_Hz", scn_cmp%delta_min_frequency_Hz, "Hz")
                call write_csv_metric_real(iunit, "delta_max_abs_imbalance_MW", &
                    scn_cmp%delta_max_abs_imbalance_MW, "MW")
                call write_csv_metric_real(iunit, "delta_final_margin_usd_h", &
                    scn_cmp%delta_final_margin_usd_h, "USD/h")
                call write_csv_metric_real(iunit, "delta_final_CO2_intensity_g_kWh", &
                    scn_cmp%delta_final_CO2_intensity_g_kWh, "g/kWh")
            end if
        case (SCREEN_EXERGY)
            call compute_exergy(st, ex)
            call write_csv_metric_real(iunit, "exergy_fuel_MW", ex%ex_fuel / 1000.0_dp, "MW")
            call write_csv_metric_real(iunit, "exergy_net_work_MW", ex%w_net / 1000.0_dp, "MW")
            call write_csv_metric_real(iunit, "exergy_eta_II_pct", 100.0_dp * ex%eta_II, "pct")
            call write_csv_metric_real(iunit, "exergy_destruction_total_MW", ex%dest_total / 1000.0_dp, "MW")
            call write_csv_metric_real(iunit, "exergy_dest_compressor_MW", ex%dest_comp / 1000.0_dp, "MW")
            call write_csv_metric_real(iunit, "exergy_dest_combustor_MW", ex%dest_comb / 1000.0_dp, "MW")
            call write_csv_metric_real(iunit, "exergy_dest_turbine_MW", ex%dest_turb / 1000.0_dp, "MW")
            call write_csv_metric_real(iunit, "exergy_dest_hrsg_MW", ex%dest_hrsg / 1000.0_dp, "MW")
            call write_csv_metric_real(iunit, "exergy_stack_loss_MW", ex%ex_stack / 1000.0_dp, "MW")
            call write_csv_metric_real(iunit, "exergy_condenser_loss_MW", ex%ex_cond / 1000.0_dp, "MW")
            call write_csv_metric_real(iunit, "exergy_balance_closure_pct", 100.0_dp * ex%closure, "pct")
            call write_csv_metric_text(iunit, "exergy_dominant_component", trim(exergy_dominant_component(ex)), "-")
        end select
    end subroutine write_active_screen_export

    subroutine write_csv_metric_real(iunit, field, value, unit)
        integer, intent(in) :: iunit
        character(len=*), intent(in) :: field, unit
        real(dp), intent(in) :: value
        character(len=40) :: value_s

        write(value_s, '(ES16.8)') value
        call write_csv_record3(iunit, field, trim(adjustl(value_s)), unit)
    end subroutine write_csv_metric_real

    subroutine write_csv_metric_int(iunit, field, value, unit)
        integer, intent(in) :: iunit, value
        character(len=*), intent(in) :: field, unit

        call write_csv_record3(iunit, field, trim(int_to_text(value)), unit)
    end subroutine write_csv_metric_int

    subroutine write_csv_metric_logical(iunit, field, value, unit)
        integer, intent(in) :: iunit
        character(len=*), intent(in) :: field, unit
        logical, intent(in) :: value

        call write_csv_record3(iunit, field, merge("true ", "false", value), unit)
    end subroutine write_csv_metric_logical

    subroutine write_csv_metric_text(iunit, field, value, unit)
        integer, intent(in) :: iunit
        character(len=*), intent(in) :: field, value, unit

        call write_csv_record3(iunit, field, value, unit)
    end subroutine write_csv_metric_text

    subroutine write_csv_record3(iunit, a, b, c)
        integer, intent(in) :: iunit
        character(len=*), intent(in) :: a, b, c

        write(iunit, '(A,",",A,",",A)') trim(csv_token(a)), trim(csv_token(b)), trim(csv_token(c))
    end subroutine write_csv_record3

    function csv_token(text) result(out)
        character(len=*), intent(in) :: text
        character(len=256) :: out
        integer :: i, n

        out = ""
        n = min(len_trim(text), len(out))
        do i = 1, n
            select case (text(i:i))
            case (",")
                out(i:i) = ";"
            case (char(10), char(13))
                out(i:i) = " "
            case default
                out(i:i) = text(i:i)
            end select
        end do
    end function csv_token

    function int_to_text(value) result(text)
        integer, intent(in) :: value
        character(len=24) :: text

        write(text, '(I0)') value
    end function int_to_text

    function advisory_severity(st) result(level)
        type(GridState), intent(in) :: st
        character(len=12) :: level

        if (st%alarm_surge .or. st%alarm_turbine_max .or. st%alarm_ufls_active) then
            level = "CRITICAL"
        else if (st%alarm_underfreq .or. st%alarm_overfreq .or. st%alarm_low_reserve .or. &
                 st%alarm_low_soc .or. st%alarm_hrsg_pinch) then
            level = "HIGH"
        else if (abs(st%imbalance_MW) > 0.75_dp .or. st%anom_composite > 2.5_dp) then
            level = "ADVISORY"
        else
            level = "NORMAL"
        end if
    end function advisory_severity

    function advisory_headline(st) result(headline)
        type(GridState), intent(in) :: st
        character(len=256) :: headline
        integer :: nl, last

        headline = "STATUS OK - no advisory text"
        last = len_trim(st%advisory_text)
        if (last <= 0) return
        nl = index(st%advisory_text(1:last), char(10))
        if (nl > 1) then
            headline = st%advisory_text(1:nl-1)
        else
            headline = st%advisory_text(1:min(last, len(headline)))
        end if
    end function advisory_headline

    function active_alarm_count(st) result(n)
        type(GridState), intent(in) :: st
        integer :: n

        n = count([st%alarm_surge, st%alarm_turbine_max, st%alarm_ufls_active, &
                   st%alarm_underfreq, st%alarm_overfreq, st%alarm_hrsg_pinch, &
                   st%alarm_low_reserve, st%alarm_low_soc])
    end function active_alarm_count

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
        ! Flat pill track
        call fill_soft_box(hdc, x, y + 2, x + width, y + 8, COL_PANEL_DEEP)
        call fill_soft_box(hdc, x, y + 2, knob_x, y + 8, color)
        call stroke_soft_box(hdc, x, y + 2, x + width, y + 8, COL_BORDER_SOFT, 1)
        if (focus_control_id == control_id) then
            call stroke_soft_box(hdc, x - 10, y - 36, x + width + 10, y + 42, COL_CYAN, 1)
        end if
        ! Clean lozenge knob — no 3D serrations
        call fill_soft_box(hdc, knob_x - 8, y - 7, knob_x + 8, y + 17, COL_PANEL_ALT)
        call stroke_soft_box(hdc, knob_x - 8, y - 7, knob_x + 8, y + 17, color, &
            merge(2, 1, active_control == control_id))
        write(lo_text, '(I0)') nint(lo)
        write(hi_text, '(I0)') nint(hi)
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
        tx = left + bw / 2 - len_trim(label) * 4
        ty = top  + bh / 2 - 8

        if (pressed) then
            ! Active/latched: deep body, colored border + left pip + colored label
            call fill_soft_box(hdc, left, top, right, bottom, COL_PANEL_DEEP)
            call stroke_soft_box(hdc, left, top, right, bottom, body_color, 2)
            call fill_box(hdc, left + 1, top + 1, left + 1 + SP_1, bottom - 1, body_color)
            call draw_text(hdc, tx + SP_1, ty, trim(label), body_color)
        else
            ! Inactive: subtle offset shadow then rounded body
            call fill_soft_box(hdc, left + 1, top + 1, right + 1, bottom + 1, COL_BTN_SH)
            call fill_soft_box(hdc, left, top, right, bottom, body_color)
            call stroke_soft_box(hdc, left, top, right, bottom, COL_BORDER, 1)
            call draw_text(hdc, tx, ty, trim(label), COL_INK)
        end if
    end subroutine draw_industrial_button

    subroutine draw_focus_box(hdc, control_id, left, top, right, bottom)
        type(c_ptr), value :: hdc
        integer(c_int), intent(in) :: control_id
        integer, intent(in) :: left, top, right, bottom
        if (focus_control_id == control_id) then
            call stroke_soft_box(hdc, left - 3, top - 3, right + 3, bottom + 3, COL_CYAN, 1)
        end if
    end subroutine draw_focus_box

    subroutine draw_faceplate(hdc, x, y, width, height, label, value_text, value_color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        character(len=*), intent(in) :: label, value_text
        integer(c_int), intent(in) :: value_color

        call draw_kpi_card(hdc, x, y, width, height, label, value_text, value_color)
        if (width >= 118 .and. height >= 58) then
            call draw_kpi_sparkline(hdc, x + width - 68, y + 10, 54, 14, label, value_color)
        end if
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
        case (FP_HEALTH)
            title = "PLANT HEALTH INDEX"
            accent = health_color(plant_health_score())
        case (FP_CO2)
            title = "CARBON INTENSITY"
            accent = merge(COL_GREEN, COL_AMBER, grid%CO2_intensity_g_kWh < 600.0_dp)
        case (FP_RESERVE)
            title = "RESERVE MARGIN"
            accent = COL_BLUE
        case (FP_SUB_P2X)
            title = "POWER-TO-X  ELECTROLYSER"
            accent = merge(COL_GREEN, COL_DIM, grid%p2x_active)
        case (FP_SUB_CCS)
            title = "CARBON CAPTURE  (CCS)"
            accent = merge(COL_GREEN, COL_DIM, grid%ccs_active)
        case (FP_SUB_GFM)
            title = "GRID-FORMING INVERTER"
            accent = merge(COL_LIME, COL_DIM, grid%gfm_mode)
        case (FP_SUB_TIE)
            title = "TIE-LINE INTERCHANGE"
            accent = merge(COL_BLUE, COL_DIM, grid%tie_active)
        case (FP_SUB_MPC)
            title = "MODEL-PREDICTIVE AGC"
            accent = merge(COL_CYAN, COL_DIM, grid%mpc_active)
        case (FP_SUB_OU)
            title = "ONLINE MODEL UPDATES"
            accent = merge(COL_AMBER, COL_DIM, grid%ou_active)
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
            write(value, '("S",I1,"  shed ",I3,"%")') grid%UFLS_stage, nint(100.0_dp * grid%UFLS_shed_fraction)
            call draw_popup_line(hdc, x, row_y + 112, "UFLS latch", trim(adjustl(value)), COL_RED)
            call draw_frequency_meter(hdc, x + 26, y + h - 86, w - 52, 28)
        case (FP_THERMAL)
            write(value, '(F6.1," / ",F6.1," MW")') grid%plant_power_MW, grid%plant_capacity_MW
            call draw_popup_line(hdc, x, row_y, "Plant output", trim(adjustl(value)), COL_LIME)
            write(value, '(F6.1," MW  ST ",F6.1," MW")') grid%gas_power_MW, grid%steam_power_MW
            call draw_popup_line(hdc, x, row_y + 28, "GT / ST split", trim(adjustl(value)), COL_CYAN)
            write(value, '(I7," kJ/kWh")') nint(grid%heat_rate_kJ_kWh)
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
            write(value, '("$",I0,"/h")') nint(grid%revenue_usd_h)
            call draw_popup_line(hdc, x, row_y, "Revenue", trim(adjustl(value)), COL_GREEN)
            write(value, '("$",I0,"/h")') nint(grid%fuel_cost_usd_h + grid%co2_cost_usd_h)
            call draw_popup_line(hdc, x, row_y + 28, "Fuel + CO2", trim(adjustl(value)), COL_AMBER)
            write(value, '("$",I0,"/h")') nint(grid%imbalance_penalty_usd_h)
            call draw_popup_line(hdc, x, row_y + 56, "Imbalance penalty", trim(adjustl(value)), COL_RED)
            write(value, '("$",I0,"/h")') nint(grid%value_stack_usd_h)
            call draw_popup_line(hdc, x, row_y + 84, "Value stack", trim(adjustl(value)), accent)
            write(value, '("Price $",I3,"  Gas $",F4.1,"  CO2 $",I3)') &
                nint(grid%power_price_usd_mwh), grid%fuel_price_usd_gj, nint(grid%carbon_price_usd_t)
            call draw_popup_line(hdc, x, row_y + 112, "Market inputs", trim(adjustl(value)), COL_MUTED)
            call draw_roi_panel(hdc, x + 18, y + h - 110, w - 36, 90)
        case (FP_BESS)
            write(value, '(F5.1,"%  ",F5.1," MWh")') grid%battery_soc_pct, grid%battery_energy_MWh
            call draw_popup_line(hdc, x, row_y, "Energy state", trim(adjustl(value)), COL_BLUE)
            write(value, '(SP,F6.1," / ",SP,F6.1," MW")') grid%storage_request_MW, grid%storage_MW
            call draw_popup_line(hdc, x, row_y + 28, "Request / actual", trim(adjustl(value)), COL_CYAN)
            write(value, '("$",I0,"/h")') nint(grid%bess_fcr_value_usd_h)
            call draw_popup_line(hdc, x, row_y + 56, "FCR reserve value", trim(adjustl(value)), COL_GREEN)
            write(value, '("$",I0,"/h")') nint(grid%bess_arbitrage_value_usd_h)
            call draw_popup_line(hdc, x, row_y + 84, "Arbitrage value", trim(adjustl(value)), COL_MUTED)
            write(value, '("$",I0,"/h")') nint(grid%bess_degradation_cost_usd_h)
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
            write(value, '(F4.1," m/s  ",I5," W/m2")') grid%market_wind_speed_m_s, nint(grid%market_solar_W_m2)
            call draw_popup_line(hdc, x, row_y + 112, "Weather input", trim(adjustl(value)), COL_MUTED)
            call draw_bar(hdc, x + 26, y + h - 70, w - 52, 28, "RES actual", effective_renewable_MW(grid), &
                max(RENEWABLE_MAX_MW, 1.0_dp), COL_GREEN)
        case (FP_HEALTH)
            block
                integer :: hs, na
                hs = plant_health_score()
                write(value, '(I0," / 100")') hs
                call draw_popup_line(hdc, x, row_y, "Composite health index", trim(adjustl(value)), accent)
                write(value, '(F7.3," Hz")') grid%frequency_Hz
                call draw_popup_line(hdc, x, row_y + 28, "Frequency", trim(adjustl(value)), frequency_color())
                write(value, '(F4.1,"% of demand")') 100.0_dp * &
                    merge(grid%fleet_reserve_MW, grid%reserve_MW, grid%fleet_mode) / max(grid%demand_MW, 1.0_dp)
                call draw_popup_line(hdc, x, row_y + 56, "Spinning reserve", trim(adjustl(value)), COL_BLUE)
                write(value, '(F5.1,"%")') grid%surge_margin_pct
                call draw_popup_line(hdc, x, row_y + 84, "Compressor surge margin", trim(adjustl(value)), COL_CYAN)
                na = count([grid%alarm_surge, grid%alarm_turbine_max, grid%alarm_ufls_active, &
                    grid%alarm_underfreq, grid%alarm_overfreq, grid%alarm_hrsg_pinch, &
                    grid%alarm_low_reserve, grid%alarm_low_soc])
                write(value, '(I0," active")') na
                call draw_popup_line(hdc, x, row_y + 112, "Alarms", trim(adjustl(value)), merge(COL_RED, COL_GREEN, na > 0))
                call draw_bar(hdc, x + 26, y + h - 70, w - 52, 28, "Health", real(hs, dp), 100.0_dp, accent)
            end block
        case (FP_CO2)
            write(value, '(I0," g/kWh")') nint(grid%CO2_intensity_g_kWh)
            call draw_popup_line(hdc, x, row_y, "Carbon intensity", trim(adjustl(value)), accent)
            write(value, '(F6.2," kg/s")') grid%CO2_rate_kg_s
            call draw_popup_line(hdc, x, row_y + 28, "CO2 mass rate", trim(adjustl(value)), COL_MUTED)
            write(value, '(F6.1," t")') grid%co2_daily_t
            call draw_popup_line(hdc, x, row_y + 56, "Emitted today", trim(adjustl(value)), COL_AMBER)
            write(value, '(F5.1,"%")') grid%h2_fraction_pct
            call draw_popup_line(hdc, x, row_y + 84, "H2 co-firing fraction", trim(adjustl(value)), COL_CYAN)
            write(value, '(F5.1," t/h")') grid%ccs_co2_captured_t_h
            call draw_popup_line(hdc, x, row_y + 112, "CCS capture rate", trim(adjustl(value)), COL_GREEN)
            call draw_bar(hdc, x + 26, y + h - 70, w - 52, 28, "Intensity", grid%CO2_intensity_g_kWh, 800.0_dp, accent)
        case (FP_RESERVE)
            write(value, '(F6.1," MW")') merge(grid%fleet_reserve_MW, grid%reserve_MW, grid%fleet_mode)
            call draw_popup_line(hdc, x, row_y, "Spinning reserve", trim(adjustl(value)), accent)
            write(value, '(F4.1,"% of demand")') 100.0_dp * &
                merge(grid%fleet_reserve_MW, grid%reserve_MW, grid%fleet_mode) / max(grid%demand_MW, 1.0_dp)
            call draw_popup_line(hdc, x, row_y + 28, "Reserve margin", trim(adjustl(value)), COL_MUTED)
            write(value, '(F6.1," MW")') grid%demand_MW
            call draw_popup_line(hdc, x, row_y + 56, "Demand", trim(adjustl(value)), COL_RED)
            write(value, '(SP,F6.1," MW")') grid%BESS_primary_MW
            call draw_popup_line(hdc, x, row_y + 84, "BESS primary response", trim(adjustl(value)), COL_BLUE)
            write(value, '(F5.1,"%")') grid%battery_soc_pct
            call draw_popup_line(hdc, x, row_y + 112, "BESS SOC", trim(adjustl(value)), COL_CYAN)
            call draw_power_flow(hdc, x + 26, y + h - 118, w - 52, 100)
        case (FP_SUB_P2X)
            call draw_popup_line(hdc, x, row_y, "Status", merge("ONLINE ", "OFFLINE", grid%p2x_active), accent)
            write(value, '(F5.1," MW")') grid%p2x_capacity_MW
            call draw_popup_line(hdc, x, row_y + 28, "Rated capacity", trim(adjustl(value)), COL_MUTED)
            write(value, '(F6.3," kg/s")') grid%p2x_h2_kg_s
            call draw_popup_line(hdc, x, row_y + 56, "H2 production rate", trim(adjustl(value)), COL_CYAN)
            call draw_text(hdc, x + 26, row_y + 96, "Soaks up surplus renewable energy as hydrogen,", COL_MUTED)
            call draw_text(hdc, x + 26, row_y + 118, "cutting curtailment and firming the grid.  [key 1]", COL_DIM)
        case (FP_SUB_CCS)
            call draw_popup_line(hdc, x, row_y, "Status", merge("ONLINE ", "OFFLINE", grid%ccs_active), accent)
            write(value, '(F5.1," t/h")') grid%ccs_co2_captured_t_h
            call draw_popup_line(hdc, x, row_y + 28, "CO2 captured", trim(adjustl(value)), COL_GREEN)
            write(value, '(F5.1," MW")') grid%ccs_parasitic_MW
            call draw_popup_line(hdc, x, row_y + 56, "Regen parasitic load", trim(adjustl(value)), COL_AMBER)
            write(value, '(F5.1,"%")') grid%ccs_capture_eff * 100.0_dp
            call draw_popup_line(hdc, x, row_y + 84, "Capture efficiency", trim(adjustl(value)), COL_CYAN)
            call draw_text(hdc, x + 26, row_y + 124, "Post-combustion amine capture; parasitic", COL_MUTED)
            call draw_text(hdc, x + 26, row_y + 146, "steam draw lowers net output.  [key 2]", COL_DIM)
        case (FP_SUB_GFM)
            call draw_popup_line(hdc, x, row_y, "Status", merge("ONLINE ", "OFFLINE", grid%gfm_mode), accent)
            write(value, '(F5.2," s")') grid%gfm_virtual_H
            call draw_popup_line(hdc, x, row_y + 28, "Virtual inertia constant", trim(adjustl(value)), COL_LIME)
            write(value, '(SP,F6.3," Hz/s")') grid%ROCOF_Hz_s
            call draw_popup_line(hdc, x, row_y + 56, "System RoCoF", trim(adjustl(value)), COL_AMBER)
            call draw_text(hdc, x + 26, row_y + 96, "Grid-forming inverter synthesises inertia and", COL_MUTED)
            call draw_text(hdc, x + 26, row_y + 118, "fault current, arresting fast RoCoF.  [key 3]", COL_DIM)
        case (FP_SUB_TIE)
            call draw_popup_line(hdc, x, row_y, "Status", merge("ONLINE ", "OFFLINE", grid%tie_active), accent)
            write(value, '(SP,F6.1," MW")') grid%tie_flow_MW
            call draw_popup_line(hdc, x, row_y + 28, "Actual interchange", trim(adjustl(value)), COL_BLUE)
            write(value, '(SP,F6.1," MW")') grid%tie_scheduled_MW
            call draw_popup_line(hdc, x, row_y + 56, "Scheduled interchange", trim(adjustl(value)), COL_MUTED)
            write(value, '(SP,F6.2," MW")') grid%ace_MW
            call draw_popup_line(hdc, x, row_y + 84, "Area control error", trim(adjustl(value)), COL_CYAN)
            call draw_text(hdc, x + 26, row_y + 124, "Net interchange with the neighbouring area;", COL_MUTED)
            call draw_text(hdc, x + 26, row_y + 146, "ACE drives tie-line bias control.  [key 4]", COL_DIM)
        case (FP_SUB_MPC)
            call draw_popup_line(hdc, x, row_y, "Status", merge("ONLINE ", "OFFLINE", grid%mpc_active), accent)
            write(value, '(SP,F6.2," MW")') grid%ace_MW
            call draw_popup_line(hdc, x, row_y + 28, "Area control error", trim(adjustl(value)), COL_CYAN)
            write(value, '(SP,F6.1," MW")') grid%governor_delta_MW
            call draw_popup_line(hdc, x, row_y + 56, "Governor action", trim(adjustl(value)), COL_BLUE)
            call draw_text(hdc, x + 26, row_y + 96, "Receding-horizon optimal AGC replaces the PI", COL_MUTED)
            call draw_text(hdc, x + 26, row_y + 118, "regulator, anticipating ramps.  [key 5]", COL_DIM)
        case (FP_SUB_OU)
            call draw_popup_line(hdc, x, row_y, "OU disturbance", &
                merge("ACTIVE ", "OFFLINE", grid%ou_active), accent)
            write(value, '(SP,F6.2," MW")') grid%ou_demand_noise
            call draw_popup_line(hdc, x, row_y + 28, "Load noise", trim(adjustl(value)), COL_AMBER)
            write(value, '(SP,F6.2," MW")') grid%ou_wind_noise
            call draw_popup_line(hdc, x, row_y + 56, "RES noise", trim(adjustl(value)), COL_GREEN)
            call draw_text(hdc, x + 26, row_y + 96, "Mean-reverting stochastic load and renewable", COL_MUTED)
            call draw_text(hdc, x + 26, row_y + 118, "disturbances for controller stress testing.", COL_MUTED)
            call draw_text(hdc, x + 26, row_y + 140, "[key 6 toggles OU; key A toggles DNN adaptation]", COL_DIM)
        end select
    end subroutine draw_kpi_faceplate_popup

    subroutine draw_popup_line(hdc, x, y, label, value_text, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y
        character(len=*), intent(in) :: label, value_text
        integer(c_int), intent(in) :: color

        call draw_text(hdc, x + 26, y, label, COL_MUTED)
        call draw_mono(hdc, x + 230, y, value_text, color)
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

        call fill_soft_box(hdc, x, y, x + w, y + h, COL_PANEL_DEEP)
        call stroke_soft_box(hdc, x, y, x + w, y + h, COL_BORDER, 1)

        do i = 1, 8
            tx = x + gap + (i - 1) * (tile_w + gap)
            if (states(i) .and. alarm_shelved(i)) then
                call fill_soft_box(hdc, tx, y + 4, tx + tile_w, y + h - 4, COL_PANEL_DEEP)
                call fill_box(hdc, tx, y + 4, tx + 4, y + h - 4, COL_DIM)
                call stroke_soft_box(hdc, tx, y + 4, tx + tile_w, y + h - 4, COL_DIM, 1)
                call hmi_fill_pie(hdc, int(tx + tile_w - 14, c_int), int(y + h/2, c_int), &
                    5_c_int, 0.0_c_float, 360.0_c_float, COL_DIM)
                call draw_alarm_icon(hdc, tx + 17, y + h / 2, i, COL_DIM)
                call draw_text(hdc, tx + 32, y + (h - 17) / 2, trim(labels(i)), COL_DIM)
            else if (states(i)) then
                ! Active alarm tile: colored with dark body
                call fill_soft_box(hdc, tx, y + 4, tx + tile_w, y + h - 4, COL_PANEL)
                call fill_box(hdc, tx, y + 4, tx + 4, y + h - 4, colors(i))  ! left accent
                call stroke_soft_box(hdc, tx, y + 4, tx + tile_w, y + h - 4, &
                    merge(COL_BORDER, colors(i), alarm_ack(i)), 1)
                ! Lamp circle (filled)
                call hmi_fill_pie(hdc, int(tx + tile_w - 14, c_int), int(y + h/2, c_int), &
                    6_c_int, 0.0_c_float, 360.0_c_float, merge(COL_MUTED, colors(i), alarm_ack(i)))
                call draw_alarm_icon(hdc, tx + 17, y + h / 2, i, &
                    merge(COL_MUTED, colors(i), alarm_ack(i)))
                call draw_text(hdc, tx + 32, y + (h - 17) / 2, trim(labels(i)), &
                    merge(COL_MUTED, colors(i), alarm_ack(i)))
            else if (alarm_seen(i)) then
                call fill_soft_box(hdc, tx, y + 4, tx + tile_w, y + h - 4, COL_PANEL_DEEP)
                call fill_box(hdc, tx, y + 4, tx + 4, y + h - 4, COL_CYAN)
                call stroke_soft_box(hdc, tx, y + 4, tx + tile_w, y + h - 4, COL_CYAN, 1)
                call hmi_fill_pie(hdc, int(tx + tile_w - 14, c_int), int(y + h/2, c_int), &
                    5_c_int, 0.0_c_float, 360.0_c_float, COL_CYAN)
                call draw_alarm_icon(hdc, tx + 17, y + h / 2, i, COL_CYAN)
                call draw_text(hdc, tx + 32, y + (h - 17) / 2, trim(labels(i)), COL_CYAN)
            else
                ! Inactive: dim tile
                call fill_soft_box(hdc, tx, y + 4, tx + tile_w, y + h - 4, COL_PANEL_DEEP)
                call fill_box(hdc, tx, y + 4, tx + 4, y + h - 4, COL_BORDER_SOFT)
                call stroke_soft_box(hdc, tx, y + 4, tx + tile_w, y + h - 4, COL_BORDER_SOFT, 1)
                ! Dim lamp circle
                call hmi_fill_pie(hdc, int(tx + tile_w - 14, c_int), int(y + h/2, c_int), &
                    5_c_int, 0.0_c_float, 360.0_c_float, COL_DIM)
                call draw_alarm_icon(hdc, tx + 17, y + h / 2, i, COL_DIM)
                call draw_text(hdc, tx + 32, y + (h - 17) / 2, trim(labels(i)), COL_DIM)
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
        call fill_soft_box(hdc, bx - 3, bar_top - 3, bx + bw + 3, bar_top + bar_h + 3, COL_BEZEL_RING)
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
        call stroke_soft_box(hdc, bx - 3, bar_top - 3, bx + bw + 3, bar_top + bar_h + 3, COL_BORDER, 1)
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
        integer :: tile_w, gap
        character(len=64) :: value

        gap = KPI_TILE_GAP
        tile_w = max(130, (width - 3 * gap) / 4)

        write(value, '(F6.1," MW")') grid%gas_power_MW
        call draw_kpi_card(hdc, x, y, tile_w, 72, "Turbine MW", trim(adjustl(value)), COL_INK)

        write(value, '(F7.2," Hz")') grid%frequency_Hz
        call draw_kpi_card(hdc, x + tile_w + gap, y, tile_w, 72, "Grid frequency", &
            trim(adjustl(value)), frequency_color())

        write(value, '(SP,F6.1," MW")') grid%imbalance_MW
        if (abs(grid%imbalance_MW) <= 0.5_dp) then
            call draw_kpi_card(hdc, x + 2 * (tile_w + gap), y, tile_w, 72, &
                "Net imbalance", trim(adjustl(value)), COL_GREEN)
        else
            call draw_kpi_card(hdc, x + 2 * (tile_w + gap), y, tile_w, 72, &
                "Net imbalance", trim(adjustl(value)), COL_RED)
        end if

        write(value, '("$",I0,"/h")') nint(grid%margin_usd_h)
        if (grid%margin_usd_h >= 0.0_dp) then
            call draw_kpi_card(hdc, x + 3 * (tile_w + gap), y, tile_w, 72, &
                "Net margin", trim(adjustl(value)), COL_GREEN)
        else if (grid%margin_usd_h > -1000.0_dp) then
            call draw_kpi_card(hdc, x + 3 * (tile_w + gap), y, tile_w, 72, &
                "Net margin", trim(adjustl(value)), COL_AMBER)
        else
            call draw_kpi_card(hdc, x + 3 * (tile_w + gap), y, tile_w, 72, &
                "Net margin", trim(adjustl(value)), COL_RED)
        end if
    end subroutine draw_kpi_tiles

    subroutine draw_section_title_width(hdc, x, y, text, width)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width
        character(len=*), intent(in) :: text
        integer :: rule_x

        ! Compact section header.  This intentionally uses the normal HMI text
        ! size; the 24 px title font was taller than the reserved header band
        ! and caused divider lines to cut through headings on scaled displays.
        call fill_box(hdc, x, y + 4, x + 3, y + 20, COL_CYAN)
        call draw_text(hdc, x + 8, y + 2, text, COL_INK)
        rule_x = x + min(max(190, 12 + len_trim(text) * 8), max(190, width - 60))
        if (rule_x < x + width - 8) call draw_line(hdc, rule_x, y + 15, x + width, y + 15, COL_BORDER_SOFT, 1)
    end subroutine draw_section_title_width

    subroutine draw_bar(hdc, x, y, width, height, label, value, maximum, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        character(len=*), intent(in) :: label
        real(dp), intent(in) :: value, maximum
        integer(c_int), intent(in) :: color
        integer :: fill_w
        integer(c_int) :: lbl_col, val_col
        character(len=32) :: mw_text
        integer :: ty

        fill_w = max(0, int(real(width, dp) * clamp_real(value / max(maximum, 1.0e-9_dp), 0.0_dp, 1.0_dp)))
        ty = y + max(0, (height - 14) / 2)
        ! Pill track
        call fill_soft_box(hdc, x, y, x + width, y + height, COL_PANEL_DEEP)
        ! Colored fill
        if (fill_w > 0) call fill_soft_box(hdc, x, y, x + fill_w, y + height, color)
        ! Subtle 1px top highlight inside fill
        if (fill_w > 4) call draw_line(hdc, x + 3, y + 1, x + fill_w - 3, y + 1, COL_BORDER, 1)
        call stroke_soft_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)
        ! Label left, value right — use light text when fill covers the label area
        if (fill_w >= len_trim(label) * 7 + 9) then
            lbl_col = COL_PANEL_DEEP  ! fully inside fill, merge with background
        else if (fill_w > 8) then
            lbl_col = COL_INK         ! fill partially covers label, need contrast
        else
            lbl_col = COL_MUTED       ! no fill under label
        end if
        val_col = merge(COL_PANEL_DEEP, color, fill_w >= width - 74)
        call draw_text(hdc, x + 8, ty, trim(label), lbl_col)
        write(mw_text, '(F6.1," MW")') value
        call draw_text(hdc, x + width - 72, ty, trim(adjustl(mw_text)), val_col)
    end subroutine draw_bar

    subroutine draw_stacked_supply(hdc, x, y, width, height, maximum, gas_color, renewable_color, storage_color, sink_color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        real(dp), intent(in) :: maximum
        integer(c_int), intent(in) :: gas_color, renewable_color, storage_color, sink_color
        integer :: cursor, seg_w
        character(len=128) :: text

        ! Rounded pill track — segments fill inside, stroke overdraw rounds corners
        call fill_soft_box(hdc, x, y, x + width, y + height, COL_PANEL_DEEP)
        if (grid%fleet_mode) then
            cursor = x
            seg_w = scaled_width(grid%fleet_unit_actual_MW(FLEET_GT1), maximum, width)
            call fill_box(hdc, cursor, y, cursor + seg_w, y + height, gas_color)
            cursor = cursor + seg_w
            if (seg_w > 0) call draw_line(hdc, cursor, y + 2, cursor, y + height - 2, COL_BG, 1)
            seg_w = scaled_width(grid%fleet_unit_actual_MW(FLEET_GT2), maximum, width)
            call fill_box(hdc, cursor, y, cursor + seg_w, y + height, COL_AMBER)
            cursor = cursor + seg_w
            if (seg_w > 0) call draw_line(hdc, cursor, y + 2, cursor, y + height - 2, COL_BG, 1)
            seg_w = scaled_width(grid%fleet_unit_actual_MW(FLEET_CC1), maximum, width)
            call fill_box(hdc, cursor, y, cursor + seg_w, y + height, COL_CYAN)
            cursor = cursor + seg_w
            if (seg_w > 0) call draw_line(hdc, cursor, y + 2, cursor, y + height - 2, COL_BG, 1)
            seg_w = scaled_width(effective_renewable_MW(grid), maximum, width)
            call fill_box(hdc, cursor, y, cursor + seg_w, y + height, renewable_color)
            cursor = cursor + seg_w
            if (grid%storage_MW >= 0.0_dp) then
                seg_w = scaled_width(grid%storage_MW, maximum, width)
                if (seg_w > 0) call draw_line(hdc, cursor, y + 2, cursor, y + height - 2, COL_BG, 1)
                call fill_box(hdc, cursor, y, cursor + seg_w, y + height, storage_color)
            else
                seg_w = scaled_width(abs(grid%storage_MW), maximum, width)
                call fill_box(hdc, x + width - seg_w, y, x + width, y + height, sink_color)
            end if
            call stroke_soft_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)
            write(text, '("GT1 ",F5.1,"  GT2 ",F5.1,"  CC1 ",F5.1,"  RES ",F5.1,"  BESS ",SP,F5.1)') &
                grid%fleet_unit_actual_MW(FLEET_GT1), grid%fleet_unit_actual_MW(FLEET_GT2), &
                grid%fleet_unit_actual_MW(FLEET_CC1), effective_renewable_MW(grid), grid%storage_MW
            call draw_text(hdc, x + 10, y + 8, adjustl(text), COL_INK)
            return
        end if
        cursor = x
        seg_w = scaled_width(grid%gas_power_MW, maximum, width)
        call fill_box(hdc, cursor, y, cursor + seg_w, y + height, gas_color)
        cursor = cursor + seg_w
        if (grid%combined_cycle) then
            if (seg_w > 0) call draw_line(hdc, cursor, y + 2, cursor, y + height - 2, COL_BG, 1)
            seg_w = scaled_width(grid%steam_power_MW, maximum, width)
            call fill_box(hdc, cursor, y, cursor + seg_w, y + height, COL_CYAN)
            cursor = cursor + seg_w
        end if
        if (seg_w > 0) call draw_line(hdc, cursor, y + 2, cursor, y + height - 2, COL_BG, 1)
        seg_w = scaled_width(effective_renewable_MW(grid), maximum, width)
        call fill_box(hdc, cursor, y, cursor + seg_w, y + height, renewable_color)
        cursor = cursor + seg_w
        ! Curtailed renewable energy shown as dim segment with amber outline
        if (grid%renewable_curtail_MW > 0.05_dp) then
            if (seg_w > 0) call draw_line(hdc, cursor, y + 2, cursor, y + height - 2, COL_BG, 1)
            seg_w = scaled_width(grid%renewable_curtail_MW, maximum, width)
            call fill_box(hdc, cursor, y, cursor + seg_w, y + height, COL_PANEL_ALT)
            call stroke_soft_box(hdc, cursor, y, cursor + seg_w, y + height, COL_AMBER, 1)
            cursor = cursor + seg_w
        end if
        if (grid%storage_MW >= 0.0_dp) then
            seg_w = scaled_width(grid%storage_MW, maximum, width)
            if (seg_w > 0) call draw_line(hdc, cursor, y + 2, cursor, y + height - 2, COL_BG, 1)
            call fill_box(hdc, cursor, y, cursor + seg_w, y + height, storage_color)
        else
            seg_w = scaled_width(abs(grid%storage_MW), maximum, width)
            call fill_box(hdc, x + width - seg_w, y, x + width, y + height, sink_color)
        end if
        call stroke_soft_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)
        if (grid%combined_cycle .and. grid%renewable_curtail_MW > 0.05_dp) then
            write(text, '("GT ",F5.1,"  ST ",F5.1,"  RES ",F5.1,"/",I4,"  Curt ",F5.1,"  BESS ",SP,F5.1)') &
                grid%gas_power_MW, grid%steam_power_MW, effective_renewable_MW(grid), &
                nint(grid%renewable_MW), grid%renewable_curtail_MW, grid%storage_MW
        else if (grid%combined_cycle) then
            write(text, '("GT ",F5.1,"  ST ",F5.1,"  RES ",F5.1,"  BESS ",SP,F5.1," MW")') &
                grid%gas_power_MW, grid%steam_power_MW, effective_renewable_MW(grid), grid%storage_MW
        else if (grid%renewable_curtail_MW > 0.05_dp) then
            write(text, '("GT ",F5.1,"  RES ",F5.1,"/",I4,"  Curt ",F4.1,"  BESS ",SP,F5.1)') &
                grid%gas_power_MW, effective_renewable_MW(grid), nint(grid%renewable_MW), &
                grid%renewable_curtail_MW, grid%storage_MW
        else
            write(text, '("GT ",F5.1,"  RES ",F5.1,"  BESS ",SP,F5.1," MW")') &
                grid%gas_power_MW, effective_renewable_MW(grid), grid%storage_MW
        end if
        call draw_text(hdc, x + 10, y + 8, adjustl(text), COL_INK)
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

        fill_w = max(0, int(real(width - 190, dp) * clamp_real(grid%battery_soc_pct / 100.0_dp, 0.0_dp, 1.0_dp)))
        call fill_soft_box(hdc, x, y, x + width - 190, y + 24, COL_PANEL_DEEP)
        if (fill_w > 0) call fill_soft_box(hdc, x, y, x + fill_w, y + 24, color)
        call stroke_soft_box(hdc, x, y, x + width - 190, y + 24, COL_BORDER_SOFT, 1)

        write(line1, '("SOC ",F5.1,"%   ",F5.1,"/",I4," MWh")') &
            grid%battery_soc_pct, grid%battery_energy_MWh, nint(BATTERY_CAPACITY_MWH)
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
        write(line, '("$",I0,"/h")') nint(grid%revenue_usd_h)
        call draw_text(hdc, c1, y + 26, adjustl(line), COL_INK)
        write(line, '("$",I0,"/h")') nint(grid%fuel_cost_usd_h + grid%imbalance_penalty_usd_h + grid%co2_cost_usd_h)
        call draw_text(hdc, c2, y + 26, adjustl(line), COL_AMBER)
        write(line, '("$",F5.1,"/MWh")') net_usd_mwh
        call draw_text(hdc, c3, y + 26, adjustl(line), margin_color)
        write(line, '(I6," kJ/kWh")') nint(grid%heat_rate_kJ_kWh)
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
            write(line, '("CC1 ",F4.1,"/",F4.1," MW  LMP $",I4,"/MWh  inertia ",I4," MWs")') &
                grid%fleet_unit_actual_MW(FLEET_CC1), grid%fleet_unit_setpoint_MW(FLEET_CC1), &
                nint(grid%fleet_lmp_usd_MWh), nint(grid%fleet_inertia_MWs)
            call draw_text(hdc, c4, y + 54, adjustl(line), COL_MUTED)
        else if (grid%combined_cycle) then
            write(line, '("Qin ",F5.1," MWth  m_f ",F4.2," kg/s  load ",F5.1," %")') &
                grid%heat_input_MW, grid%fuel_flow_kg_s, capacity_pct
            call draw_text(hdc, c1, y + 54, adjustl(line), COL_MUTED)
            write(line, '("ST ",F4.1," MW  HRSG ",F5.1," MW  pinch ",F4.1," K  stack ",I4," K")') &
                grid%steam_power_MW, grid%hrsg_recovered_heat_MW, grid%hrsg_pinch_K, nint(grid%hrsg_stack_T_K)
            call draw_text(hdc, c4, y + 54, adjustl(line), COL_MUTED)
        else
            write(line, '("Qin ",F5.1," MWth  m_f ",F4.2," kg/s  load ",F5.1," %")') &
                grid%heat_input_MW, grid%fuel_flow_kg_s, capacity_pct
            call draw_text(hdc, c1, y + 54, adjustl(line), COL_MUTED)
            write(line, '("Price $",I3,"/MWh  Gas $",F4.1,"/GJ  Ren headroom ",F4.1," MW")') &
                nint(grid%power_price_usd_mwh), grid%fuel_price_usd_gj, renewable_headroom_MW(grid)
            call draw_text(hdc, c4, y + 54, adjustl(line), COL_MUTED)
        end if

        ! Row D — live operator-advisory headline, else dispatch heuristic (full width)
        ! [5.0-B3] Surface the AI advisory's lead line on the landing screen so the
        ! "brain" of the twin is visible at a glance; fall back to the ED/AGC/ROI
        ! heuristic when the advisory is just STATUS OK / empty.
        block
            integer :: nl, adv_col
            character(len=200) :: adv1
            character(len=120) :: heur
            nl = index(grid%advisory_text, char(10))
            if (nl > 1) then
                adv1 = adjustl(grid%advisory_text(1:nl-1))
            else
                adv1 = adjustl(grid%advisory_text)
            end if
            adv_col = COL_CYAN
            if (adv1(1:5) == "ALERT") then
                adv_col = COL_RED
            else if (adv1(1:9) == "DIAGNOSIS" .or. adv1(1:7) == "ANOMALY") then
                adv_col = COL_AMBER
            else if (adv1(1:3) /= "OPT") then
                adv1 = ""   ! STATUS OK / empty → use the heuristic line instead
            end if
            if (len_trim(adv1) > 140) adv1 = adv1(1:138) // ".."
            if (len_trim(adv1) > 0) then
                call draw_text(hdc, c1, y + 72, trim(adv1), adv_col)
            else
                if (grid%fleet_mode .and. grid%fleet_reserve_binding) then
                    heur = "ED: reserve constraint binding — raise supply, restore unit, or lower demand"
                else if (grid%fleet_mode .and. grid%fuel_price_usd_gj > 12.0_dp) then
                    heur = "ED: high fuel price — RES/BESS priority before thermal MW"
                else if (grid%fleet_mode) then
                    heur = "ED: cheapest online unit on base load, AGC following ramp limits"
                else if (grid%imbalance_MW < -0.5_dp) then
                    heur = "AGC: deficit — restore RES headroom, discharge BESS, raise turbine"
                else if (grid%imbalance_MW > 0.5_dp) then
                    heur = "AGC: surplus — charge BESS, trim curtailed RES, lower turbine"
                else if (grid%fcr_hold .and. grid%bess_fcr_value_usd_h >= grid%bess_arbitrage_value_usd_h) then
                    heur = "ROI: BESS held mid-SOC for FCR regulation and imbalance value"
                else if (.not. grid%roi_dispatch) then
                    heur = "Stability mode: frequency correction prioritised over curtailment cost"
                else
                    heur = "ROI: capturing surplus energy while maintaining BESS frequency reserve"
                end if
                call draw_text(hdc, c1, y + 72, adjustl(heur), COL_CYAN)
            end if
        end block
    end subroutine draw_roi_panel

    subroutine draw_history_traces(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: gx, gy, gw, gh, gi, leg_step
        integer :: py_lo, py_hi   ! pixel rows for FCR guard-band lines
        real(dp) :: span_s, f_nom, f_min, f_max, f_guard_lo, f_guard_hi
        character(len=64) :: lbl, hover1, hover2
        integer :: hover_pos, hover_idx
        real(dp) :: hover_frac, hover_age

        ! Panel shell: amber accent strip + rounded body
        call fill_soft_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
        call fill_box(hdc, x, y, x + 4, y + height, COL_AMBER)        ! left accent
        call fill_box(hdc, x + 4, y, x + width, y + 2, COL_AMBER)    ! top stripe
        call stroke_soft_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)

        ! Plot area: wider left margin for 5-char Y labels, extra bottom for X labels
        gx = x + 48
        gy = y + 28
        gw = width - 56
        gh = height - 40
        f_nom = grid%nominal_frequency_Hz
        f_min = f_nom - 1.5_dp
        f_max = f_nom + 1.5_dp
        f_guard_lo = f_nom - 0.2_dp
        f_guard_hi = f_nom + 0.2_dp

        call fill_box(hdc, gx, gy, gx + gw, gy + gh, COL_BG)

        ! Horizontal grid lines at 25 / 50 / 75 %
        do gi = 1, 3
            call draw_line(hdc, gx, gy + gi * gh / 4, gx + gw, gy + gi * gh / 4, COL_BG_GRID, 1)
        end do
        ! Vertical grid lines at 25 / 50 / 75 %
        do gi = 1, 3
            call draw_line(hdc, gx + gi * gw / 4, gy, gx + gi * gw / 4, gy + gh, COL_BG_GRID, 1)
        end do
        ! Nominal frequency centre — brighter horizontal reference
        call draw_line(hdc, gx, gy + gh / 2, gx + gw, gy + gh / 2, COL_BORDER, 1)

        ! FCR deadband guard lines: nominal +/- 0.2 Hz (dashed cyan)
        py_lo = gy + gh - nint((f_guard_lo - f_min) / (f_max - f_min) * real(gh, dp))
        py_hi = gy + gh - nint((f_guard_hi - f_min) / (f_max - f_min) * real(gh, dp))
        do gi = gx + 2, gx + gw - 4, 10
            call draw_line(hdc, gi, py_lo, min(gi + 6, gx + gw - 2), py_lo, COL_CYAN, 1)
            call draw_line(hdc, gi, py_hi, min(gi + 6, gx + gw - 2), py_hi, COL_CYAN, 1)
        end do

        ! Y-axis labels (Hz)
        write(lbl, '(F4.1)') f_max
        call draw_text(hdc, x + 4, gy - 7,          adjustl(lbl), COL_DIM)
        write(lbl, '(F4.1)') f_guard_hi
        call draw_text(hdc, x + 4, py_hi - 7,       adjustl(lbl), COL_CYAN)
        write(lbl, '(F4.1)') f_nom
        call draw_text(hdc, x + 4, gy + gh / 2 - 7, adjustl(lbl), COL_AMBER)
        write(lbl, '(F4.1)') f_guard_lo
        call draw_text(hdc, x + 4, py_lo - 7,       adjustl(lbl), COL_CYAN)
        write(lbl, '(F4.1)') f_min
        call draw_text(hdc, x + 4, gy + gh - 7,     adjustl(lbl), COL_DIM)

        call stroke_box(hdc, gx, gy, gx + gw, gy + gh, COL_BORDER_SOFT, 1)

        if (grid%history_count < 2) then
            call draw_text(hdc, gx + 40, gy + gh / 2 - 8, "Waiting for samples...", COL_MUTED)
        else
            call draw_trace(hdc, gx, gy, gw, gh, 1, f_min, f_max, COL_AMBER)
            call draw_trace(hdc, gx, gy, gw, gh, 2, 0.0_dp, DEMAND_MAX_MW, COL_RED)
            call draw_trace(hdc, gx, gy, gw, gh, 3, 0.0_dp, 100.0_dp, COL_LIME)
        end if

        if (mouse_hover_valid .and. grid%history_count >= 2 .and. &
                point_in_rect(mouse_hover_x, mouse_hover_y, gx, gy, gx + gw, gy + gh)) then
            hover_frac = clamp_real(real(mouse_hover_x - gx, dp) / real(max(gw, 1), dp), 0.0_dp, 1.0_dp)
            hover_pos = max(1, min(grid%history_count, 1 + nint(hover_frac * real(grid%history_count - 1, dp))))
            hover_idx = history_index(grid, hover_pos)
            hover_age = (1.0_dp - hover_frac) * real(HISTORY_N, dp) * 0.25_dp
            write(hover1, '("t-",I0,"s   F ",F7.3," Hz")') nint(hover_age), grid%hist_frequency_Hz(hover_idx)
            write(hover2, '("Load ",F5.1," MW   GT ",F5.1,"%")') &
                grid%hist_demand_MW(hover_idx), grid%hist_gas_dispatch_pct(hover_idx)
            call draw_chart_crosshair(hdc, gx, gy, gw, gh, trim(hover1), trim(hover2))
        end if

        ! X-axis time labels below plot border: fixed to the rolling history window.
        span_s = real(HISTORY_N, dp) * 0.25_dp
        write(lbl, '("-",I0,"s")') nint(span_s)
        call draw_text(hdc, gx,               gy + gh + 3, adjustl(lbl), COL_DIM)
        write(lbl, '("-",I0,"s")') nint(span_s * 0.75_dp)
        call draw_text(hdc, gx + gw / 4 - 8,  gy + gh + 3, adjustl(lbl), COL_DIM)
        write(lbl, '("-",I0,"s")') nint(span_s * 0.5_dp)
        call draw_text(hdc, gx + gw / 2 - 8,  gy + gh + 3, adjustl(lbl), COL_DIM)
        write(lbl, '("-",I0,"s")') nint(span_s * 0.25_dp)
        call draw_text(hdc, gx + 3*gw / 4 - 8,gy + gh + 3, adjustl(lbl), COL_DIM)
        call draw_text(hdc, gx + gw - 12,      gy + gh + 3, "0s",          COL_DIM)

        ! Live legend: colored dot + value, proportionally spaced
        leg_step = max(80, gw / 3)
        write(lbl, '("o ",F7.3," Hz")') grid%frequency_Hz
        call draw_text(hdc, gx + 2,             y + 10, adjustl(lbl), COL_AMBER)
        write(lbl, '("o ",F5.1," MW")') grid%demand_MW
        call draw_text(hdc, gx + leg_step,      y + 10, adjustl(lbl), COL_RED)
        write(lbl, '("o ",F5.1," %")') grid%gas_dispatch_pct
        call draw_text(hdc, gx + 2 * leg_step,  y + 10, adjustl(lbl), COL_LIME)
        call draw_text(hdc, gx + gw - 120,      y + 10, "FCR +/-0.2 Hz",  COL_CYAN)
    end subroutine draw_history_traces

    subroutine draw_trace(hdc, x, y, width, height, series, lo, hi, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height, series
        real(dp), intent(in) :: lo, hi
        integer(c_int), intent(in) :: color
        integer :: i, idx, n
        real(dp) :: value, norm
        integer(c_int), target :: px(HISTORY_N), py(HISTORY_N)

        n = min(grid%history_count, HISTORY_N)
        if (n < 2) return
        do i = 1, n
            idx = history_index(grid, i)
            select case (series)
            case (1)
                value = grid%hist_frequency_Hz(idx)
            case (2)
                value = grid%hist_demand_MW(idx)
            case default
                value = grid%hist_gas_dispatch_pct(idx)
            end select
            norm  = clamp_real((value - lo) / max(hi - lo, 1.0e-9_dp), 0.0_dp, 1.0_dp)
            px(i) = int(x + int(real(width, dp) * real(i - 1, dp) / real(n - 1, dp)), c_int)
            py(i) = int(y + height - int(real(height, dp) * norm), c_int)
        end do
        ! [perf] One batched DrawLines per series instead of N GDI+ Graphics-per-segment.
        if (native_renderer_ready) then
            call hmi_draw_polyline(hdc, c_loc(px), c_loc(py), int(n, c_int), color, 2_c_int)
        else
            do i = 2, n
                call draw_line(hdc, int(px(i-1)), int(py(i-1)), int(px(i)), int(py(i)), color, 2)
            end do
        end if
    end subroutine draw_trace

    subroutine draw_chart_crosshair(hdc, gx, gy, gw, gh, line1, line2)
        type(c_ptr), value :: hdc
        integer, intent(in) :: gx, gy, gw, gh
        character(len=*), intent(in) :: line1, line2
        integer :: hx, hy, tx, ty, tw
        if (.not. mouse_hover_valid) return
        if (.not. point_in_rect(mouse_hover_x, mouse_hover_y, gx, gy, gx + gw, gy + gh)) return
        hx = mouse_hover_x
        hy = mouse_hover_y
        call draw_line(hdc, hx, gy, hx, gy + gh, COL_CYAN, 1)
        call draw_line(hdc, gx, hy, gx + gw, hy, COL_CYAN, 1)
        tw = 270
        tx = min(gx + gw - tw - 8, hx + 14)
        if (tx < gx + 8) tx = gx + 8
        ty = max(gy + 8, min(gy + gh - 58, hy - 50))
        call hmi_fill_alpha_round_rect(hdc, int(tx, c_int), int(ty, c_int), int(tx + tw, c_int), &
            int(ty + 50, c_int), RADIUS_SM, COL_PANEL_DEEP, 225_c_int)
        call stroke_soft_box(hdc, tx, ty, tx + tw, ty + 50, COL_CYAN, 1)
        call draw_mono(hdc, tx + 10, ty + 9, trim(line1), COL_CYAN)
        call draw_mono(hdc, tx + 10, ty + 29, trim(line2), COL_INK)
    end subroutine draw_chart_crosshair

    subroutine draw_kpi_sparkline(hdc, x, y, width, height, label, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        character(len=*), intent(in) :: label
        integer(c_int), intent(in) :: color
        integer, parameter :: MAX_SPARK_POINTS = 48
        integer :: i, idx, pos, series, n_total, n_plot
        real(dp) :: value, lo, hi, norm
        integer(c_int), target :: px(MAX_SPARK_POINTS), py(MAX_SPARK_POINTS)

        if (grid%history_count < 2 .or. width < 18 .or. height < 8) return
        n_total = min(grid%history_count, HISTORY_N)
        n_plot = min(MAX_SPARK_POINTS, n_total)
        if (n_plot < 2) return
        series = 3
        lo = 0.0_dp
        hi = 100.0_dp
        if (index(label, "FREQ") > 0 .or. index(label, "Frequency") > 0) then
            series = 1
            lo = grid%nominal_frequency_Hz - 0.7_dp
            hi = grid%nominal_frequency_Hz + 0.7_dp
        else if (index(label, "DEMAND") > 0 .or. index(label, "Demand") > 0) then
            series = 2
            lo = 0.0_dp
            hi = DEMAND_MAX_MW
        else if (index(label, "THERMAL") > 0 .or. index(label, "Turbine") > 0) then
            series = 3
        end if
        call stroke_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)
        do i = 1, n_plot
            pos = 1 + int(real(i - 1, dp) * real(n_total - 1, dp) / real(max(1, n_plot - 1), dp))
            idx = history_index(grid, pos)
            select case (series)
            case (1); value = grid%hist_frequency_Hz(idx)
            case (2); value = grid%hist_demand_MW(idx)
            case default; value = grid%hist_gas_dispatch_pct(idx)
            end select
            norm = clamp_real((value - lo) / max(hi - lo, 1.0e-9_dp), 0.0_dp, 1.0_dp)
            px(i) = int(x + int(real(width, dp) * real(i - 1, dp) / real(max(1, n_plot - 1), dp)), c_int)
            py(i) = int(y + height - int(real(height, dp) * norm), c_int)
        end do
        if (native_renderer_ready) then
            call hmi_draw_polyline(hdc, c_loc(px), c_loc(py), int(n_plot, c_int), color, 1_c_int)
        else
            do i = 2, n_plot
                call draw_line(hdc, int(px(i-1)), int(py(i-1)), int(px(i)), int(py(i)), color, 1)
            end do
        end if
    end subroutine draw_kpi_sparkline

    subroutine draw_frequency_meter(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: center_x, marker_x
        real(dp) :: frac, f_lo, f_hi
        character(len=20) :: label

        if (height < 1) return
        call fill_soft_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
        center_x = x + width / 2
        call fill_soft_box(hdc, center_x - 34, y, center_x + 34, y + height, int(Z'00406040', c_int))
        call stroke_soft_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)
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

        if (height < 56 .or. width < 180) return
        call fill_soft_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
        call stroke_soft_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)

        diagram_h = max(96, min(height - 16, 420))
        diagram_y = y + 8 + max(0, (height - 16 - diagram_h) / 2)
        node_w = min(max(88, width / 4), 150)
        node_h = max(30, min(50, (diagram_h - 16) / 3))
        row_gap = max(6, (diagram_h - 3 * node_h) / 2)
        row1 = diagram_y + max(0, (diagram_h - 3 * node_h - 2 * row_gap) / 2)
        row2 = row1 + node_h + row_gap
        row3 = row2 + node_h + row_gap
        grid_w = min(max(78, width / 5), 135)
        grid_h = max(48, min(80, diagram_h / 3))
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
        call fill_soft_box(hdc, grid_x, grid_y, grid_x + grid_w, grid_y + grid_h, COL_BTN_SH)
        call fill_soft_box(hdc, grid_x+1, grid_y+1, grid_x+grid_w-1, grid_y+grid_h-1, COL_PANEL)
        call fill_box(hdc, grid_x+1, grid_y+1, grid_x+5, grid_y+grid_h-1, frequency_color())
        call draw_line(hdc, grid_x+1, grid_y+1, grid_x+grid_w-2, grid_y+1, COL_BORDER, 1)
        call stroke_soft_box(hdc, grid_x, grid_y, grid_x+grid_w, grid_y+grid_h, frequency_color(), 2)
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

    ! Heat-rate vs load operating curve — fills bottom-right of the F1 overview.
    ! Shows a pre-computed part-load HR curve, ISO design-point and warning
    ! threshold lines, and a live coloured dot at the current operating point.
    subroutine draw_heat_rate_chart(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        character(len=72) :: lbl, hover1, hover2
        integer :: gx, gy, gw, gh, i, px, py, px2, py2, dot_col
        real(dp) :: load_pct, hr_live, fx, fy_r, hr_lo, hr_hi, pad, hover_load, hover_hr

        if (height < 40 .or. width < 60) return

        gx = x + 4
        gy = y + 16
        gw = max(40, width - 8)
        gh = max(24, height - 20)

        hr_live = max(1.0_dp, grid%gt_heat_rate_kJ_kWh)
        hr_lo = min(hr_live, minval(grid%physics_ref_gt_hr_kJ_kWh(1:FIDELITY_N)))
        hr_hi = max(hr_live, maxval(grid%physics_ref_gt_hr_kJ_kWh(1:FIDELITY_N)))
        pad = max(300.0_dp, 0.08_dp * max(1.0_dp, hr_hi - hr_lo))
        hr_lo = max(7000.0_dp, hr_lo - pad)
        hr_hi = hr_hi + pad

        ! Title + live value on the same row
        write(lbl, '("GT HR vs map | ",I6," kJ/kWh  gap ",SP,F4.1,"%")') &
            nint(grid%gt_heat_rate_kJ_kWh), grid%physics_gt_hr_gap_pct
        if (grid%physics_gt_hr_gap_pct < 5.0_dp) then
            dot_col = COL_GREEN
        else if (grid%physics_gt_hr_gap_pct < 12.0_dp) then
            dot_col = COL_AMBER
        else
            dot_col = COL_RED
        end if
        call draw_text(hdc, gx, y + 2, adjustl(lbl), dot_col)

        call fill_soft_box(hdc, gx, gy, gx + gw, gy + gh, COL_PANEL_ALT)
        call stroke_soft_box(hdc, gx, gy, gx + gw, gy + gh, COL_BORDER_SOFT, 1)

        ! Draw three reference lines (dashed): current map, +8%, +20%
        call draw_hr_hline(hdc, gx, gy, gw, gh, hr_lo, hr_hi, grid%physics_gt_hr_ref_kJ_kWh, COL_GREEN)
        call draw_hr_hline(hdc, gx, gy, gw, gh, hr_lo, hr_hi, grid%physics_gt_hr_ref_kJ_kWh * 1.08_dp, COL_AMBER)
        call draw_hr_hline(hdc, gx, gy, gw, gh, hr_lo, hr_hi, grid%physics_gt_hr_ref_kJ_kWh * 1.20_dp, COL_RED)

        ! Part-load reference curve
        do i = 1, FIDELITY_N - 1
            fx   = real(gx, dp) + (grid%physics_load_pct(i) - 30.0_dp) / 70.0_dp * real(gw, dp)
            fy_r = real(gy + gh, dp) - (grid%physics_ref_gt_hr_kJ_kWh(i) - hr_lo) / &
                (hr_hi - hr_lo) * real(gh, dp)
            px  = nint(fx); py  = max(gy, min(gy + gh, nint(fy_r)))
            fx   = real(gx, dp) + (grid%physics_load_pct(i + 1) - 30.0_dp) / 70.0_dp * real(gw, dp)
            fy_r = real(gy + gh, dp) - (grid%physics_ref_gt_hr_kJ_kWh(i + 1) - hr_lo) / &
                (hr_hi - hr_lo) * real(gh, dp)
            px2 = nint(fx); py2 = max(gy, min(gy + gh, nint(fy_r)))
            call draw_line(hdc, px, py, px2, py2, COL_CYAN, 1)
        end do

        ! Live operating dot
        load_pct = grid%gas_dispatch_pct
        hr_live  = max(hr_lo, min(hr_hi, grid%gt_heat_rate_kJ_kWh))
        load_pct = max(30.0_dp, min(100.0_dp, load_pct))
        fx   = real(gx, dp) + (load_pct - 30.0_dp) / 70.0_dp * real(gw, dp)
        fy_r = real(gy + gh, dp) - (hr_live - hr_lo) / (hr_hi - hr_lo) * real(gh, dp)
        px = nint(fx); py = max(gy, min(gy + gh, nint(fy_r)))
        call fill_box(hdc, px - 5, py - 5, px + 5, py + 5, dot_col)
        call stroke_box(hdc, px - 5, py - 5, px + 5, py + 5, COL_PANEL_ALT, 1)

        if (mouse_hover_valid .and. point_in_rect(mouse_hover_x, mouse_hover_y, gx, gy, gx + gw, gy + gh)) then
            hover_load = 30.0_dp + 70.0_dp * real(mouse_hover_x - gx, dp) / real(max(gw, 1), dp)
            hover_hr = hr_hi - (hr_hi - hr_lo) * real(mouse_hover_y - gy, dp) / real(max(gh, 1), dp)
            write(hover1, '("Load ",F5.1,"%   HR ",I6)') hover_load, nint(hover_hr)
            write(hover2, '("Live gap ",SP,F5.1,"%   ref map")') grid%physics_gt_hr_gap_pct
            call draw_chart_crosshair(hdc, gx, gy, gw, gh, trim(hover1), trim(hover2))
        end if

        ! Axis labels
        call draw_text(hdc, gx,             gy + gh + 2, "30%",  COL_MUTED)
        call draw_text(hdc, gx + gw/2 - 8,  gy + gh + 2, "65%",  COL_MUTED)
        call draw_text(hdc, gx + gw - 22,   gy + gh + 2, "100%", COL_MUTED)
        call draw_text(hdc, gx + gw - 62,   gy + 4, "ref map", COL_CYAN)
    end subroutine draw_heat_rate_chart

    ! Helper: draw a dashed horizontal line at heat-rate value hr_val inside chart axes.
    subroutine draw_hr_hline(hdc, gx, gy, gw, gh, hr_min, hr_max, hr_val, col)
        type(c_ptr), value :: hdc
        integer, intent(in) :: gx, gy, gw, gh, col
        real(dp), intent(in) :: hr_min, hr_max, hr_val
        integer :: py, i
        py = nint(real(gy + gh, dp) - (hr_val - hr_min) / (hr_max - hr_min) * real(gh, dp))
        if (py < gy .or. py > gy + gh) return
        do i = gx + 2, gx + gw - 4, 8
            call draw_line(hdc, i, py, min(i + 4, gx + gw - 2), py, col, 1)
        end do
    end subroutine draw_hr_hline

    subroutine draw_node(hdc, x, y, width, height, label, value, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        character(len=*), intent(in) :: label
        real(dp), intent(in) :: value
        integer(c_int), intent(in) :: color
        character(len=64) :: text

        ! Outer shadow frame
        call fill_soft_box(hdc, x, y, x + width, y + height, COL_BTN_SH)
        ! Inset body
        call fill_soft_box(hdc, x+1, y+1, x+width-1, y+height-1, COL_PANEL_DEEP)
        ! Left colour accent stripe
        call fill_box(hdc, x+1, y+1, x+4, y+height-1, color)
        ! Top highlight
        call draw_line(hdc, x+1, y+1, x+width-2, y+1, COL_BORDER, 1)
        ! Colour border
        call stroke_soft_box(hdc, x, y, x+width, y+height, color, 1)
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
                int(bottom, c_int), RADIUS_MD, color)
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
                int(bottom, c_int), RADIUS_MD, color, int(width, c_int))
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
                int(ui_font_body_px(), c_int), FW_NORMAL, color)
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
                int(ui_font_title_px(), c_int), FW_SEMIBOLD, color)
            return
        end if
        if (c_associated(h_font_title)) old_font = SelectObject(hdc, h_font_title)
        ignored = SetTextColor(hdc, color)
        ignored = SetBkMode(hdc, TRANSPARENT)
        ok = TextOutA(hdc, int(x, c_int), int(y, c_int), c_loc(c_text), int(n, c_int))
        if (c_associated(h_font_title)) old_font = SelectObject(hdc, old_font)
    end subroutine draw_title_text

    !> [6.0-P2] Monospace (tabular-figure) numeric readout — body size.
    subroutine draw_mono(hdc, x, y, text, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y
        character(len=*), intent(in) :: text
        integer(c_int), intent(in) :: color
        character(kind=c_char), allocatable, target :: c_text(:)
        integer :: n
        n = len_trim(text)
        if (n <= 0) return
        call make_c_string(text(1:n), c_text)
        if (native_renderer_ready) then
            call hmi_draw_text_native(hdc, int(x, c_int), int(y, c_int), c_loc(c_text), &
                int(ui_font_body_px(), c_int), FW_NORMAL + FW_MONO, color)
        else
            call draw_text(hdc, x, y, text, color)
        end if
    end subroutine draw_mono

    !> [6.0-P2] Monospace numeric readout — title size (KPI card values, big readouts).
    subroutine draw_mono_title(hdc, x, y, text, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y
        character(len=*), intent(in) :: text
        integer(c_int), intent(in) :: color
        character(kind=c_char), allocatable, target :: c_text(:)
        integer :: n
        n = len_trim(text)
        if (n <= 0) return
        call make_c_string(text(1:n), c_text)
        if (native_renderer_ready) then
            call hmi_draw_text_native(hdc, int(x, c_int), int(y, c_int), c_loc(c_text), &
                int(ui_font_title_px(), c_int), FW_SEMIBOLD + FW_MONO, color)
        else
            call draw_title_text(hdc, x, y, text, color)
        end if
    end subroutine draw_mono_title

    !> [5.0-P1] Header subsystem chip: filled+labelled when active, outlined+muted when not.
    !> Label is horizontally centered in the chip; text vertically centered in the 20 px band.
    subroutine draw_module_chip(hdc, left, top, bot, width, label, active, accent)
        type(c_ptr), value :: hdc
        integer, intent(in) :: left, top, bot, width
        character(len=*), intent(in) :: label
        logical, intent(in) :: active
        integer(c_int), intent(in) :: accent
        integer :: tx
        call fill_soft_box(hdc, left, top, left + width, bot, &
            merge(accent, COL_PANEL_DEEP, active))
        call stroke_soft_box(hdc, left, top, left + width, bot, &
            merge(accent, COL_BORDER, active), 1)
        tx = left + max(3, (width - len_trim(label) * 8) / 2)   ! ~8 px/char, centered
        call draw_text(hdc, tx, top + 3, trim(label), &
            merge(COL_PANEL_DEEP, COL_MUTED, active))
    end subroutine draw_module_chip

    subroutine draw_status_badge(hdc, left, top, width, height, label, accent, filled)
        type(c_ptr), value :: hdc
        integer, intent(in) :: left, top, width, height
        character(len=*), intent(in) :: label
        integer(c_int), intent(in) :: accent
        logical, intent(in) :: filled
        integer(c_int) :: text_col
        integer :: tx

        tx = left + max(SP_2, (width - len_trim(label) * 8) / 2)
        if (filled) then
            text_col = merge(COL_INK, COL_PANEL_DEEP, accent == COL_RED)
            call fill_soft_box(hdc, left, top, left + width, top + height, accent)
            call draw_text(hdc, tx, top + 3, trim(label), text_col)
        else
            call stroke_soft_box(hdc, left, top, left + width, top + height, accent, 1)
            call draw_text(hdc, tx, top + 3, trim(label), COL_MUTED)
        end if
    end subroutine draw_status_badge

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

    ! =========================================================================
    ! P&ID plant schematic  (F1 Overview bottom-right panel)
    ! =========================================================================
    ! =========================================================================
    ! [5.0-B] Flagship executive landing — "Plant Health & Economics".
    !   B1  single-line animated plant schematic hero (live power/heat/CO2 flows)
    !   B2  composite health ring + top-3 KPI cards + live operator-advisory headline
    !   B3  subsystem status strip (the 6 modules) as first-class tiles
    ! The ring, the 3 KPI cards and the 6 subsystem tiles are all click-through to
    ! faceplate drill-downs — geometry is cached in fl_ring/fl_card/fl_tile for
    ! hit_test_flagship ([5.0-D1]).
    ! =========================================================================
    subroutine draw_flagship_screen(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: ix, iw, y1, band_y, band_h
        integer :: ring_x, ring_w, ring_cx, ring_cy, ring_r
        integer :: kpi_x, kpi_total_w, card_w, card_h, kpi_gap, cx2
        integer :: adv_y, adv_h, hero_y, hero_bottom, hero_h
        integer :: strip_y, strip_h, tile_w, tile_h, tile_gap, tx, nl, hscore
        integer(c_int) :: hcol, adv_col
        real(dp) :: rmw, rpct
        character(len=96)  :: subtitle
        character(len=120) :: advline
        character(len=200) :: advfull
        character(len=32)  :: vt, auto_text, plant_text
        character(len=12)  :: hstat

        ix = x + PAD_PANEL_X
        iw = width - 2 * PAD_PANEL_X
        y1 = y + 8

        ! --- Caption + mode subtitle + FLAGSHIP/DETAIL toggle ---
        if (grid%auto_balance) then; auto_text = "AUTO balancing"
        else;                        auto_text = "MANUAL control"; end if
        if (grid%fleet_mode) then;          plant_text = "Fleet"
        else if (grid%combined_cycle) then; plant_text = "Combined cycle"
        else;                               plant_text = "Simple cycle"; end if
        write(subtitle, '(A," | ",A," | t+",I0,"s")') &
            trim(plant_text), trim(auto_text), nint(grid%elapsed_s)
        call draw_screen_caption(hdc, ix, y1, iw, "Plant Health & Economics", trim(subtitle))
        call draw_overview_toggle(hdc, ix, iw, y1)

        ! --- Band 1: health ring (left) | 3 KPI cards + advisory headline (right) ---
        band_y = y1 + 66
        band_h = 196
        ring_w = max(230, iw * 22 / 100)
        ring_x = ix
        call draw_panel_box(hdc, ring_x, band_y, ring_w, band_h)
        fl_ring = [ring_x, band_y, ring_x + ring_w, band_y + band_h]
        call draw_text(hdc, ring_x + PAD_CARD_X, band_y + PAD_CARD_Y, "PLANT HEALTH INDEX", COL_MUTED)
        hscore = plant_health_score()
        hcol   = health_color(hscore)
        ring_cx = ring_x + ring_w / 2
        ring_cy = band_y + band_h / 2 + 16
        ring_r  = min(ring_w / 2 - 30, (band_h - 78) / 2)
        call hmi_draw_arc(hdc, int(ring_cx,c_int), int(ring_cy,c_int), int(ring_r,c_int), &
            -225.0_c_float, 270.0_c_float, COL_BG_GRID, 11_c_int)
        call hmi_draw_arc(hdc, int(ring_cx,c_int), int(ring_cy,c_int), int(ring_r,c_int), &
            -225.0_c_float, real(270 * hscore / 100, c_float), hcol, 11_c_int)
        write(vt, '(I0)') hscore
        call draw_big_number(hdc, ring_cx, ring_cy - 22, trim(vt), 46, hcol)
        if (hscore >= 75) then;      hstat = "HEALTHY"
        else if (hscore >= 50) then; hstat = "WATCH"
        else;                        hstat = "ALERT"; end if
        call draw_text(hdc, ring_cx - len_trim(hstat) * 4, ring_cy + 26, trim(hstat), hcol)

        ! 3 top KPI cards
        kpi_x       = ix + ring_w + GAP_PANEL
        kpi_total_w = iw - ring_w - GAP_PANEL
        kpi_gap     = GAP_CARD
        card_w      = (kpi_total_w - 2 * kpi_gap) / 3
        card_h      = 104
        write(vt, '("$ ",I0,"/h")') nint(grid%margin_usd_h)
        cx2 = kpi_x
        call draw_kpi_card(hdc, cx2, band_y, card_w, card_h, "NET MARGIN", trim(adjustl(vt)), &
            merge(COL_GREEN, merge(COL_AMBER, COL_RED, grid%margin_usd_h > -1000.0_dp), grid%margin_usd_h >= 0.0_dp))
        fl_card(:,1) = [cx2, band_y, cx2 + card_w, band_y + card_h]
        write(vt, '(I0," g/kWh")') nint(grid%CO2_intensity_g_kWh)
        cx2 = kpi_x + card_w + kpi_gap
        call draw_kpi_card(hdc, cx2, band_y, card_w, card_h, "CARBON INTENSITY", trim(adjustl(vt)), &
            merge(COL_GREEN, merge(COL_AMBER, COL_RED, grid%CO2_intensity_g_kWh < 600.0_dp), grid%CO2_intensity_g_kWh < 400.0_dp))
        fl_card(:,2) = [cx2, band_y, cx2 + card_w, band_y + card_h]
        rmw  = merge(grid%fleet_reserve_MW, grid%reserve_MW, grid%fleet_mode)
        rpct = 100.0_dp * rmw / max(grid%demand_MW, 1.0_dp)
        write(vt, '(F4.1,"%")') rpct
        cx2 = kpi_x + 2 * (card_w + kpi_gap)
        call draw_kpi_card(hdc, cx2, band_y, card_w, card_h, "RESERVE MARGIN", trim(adjustl(vt)), &
            merge(COL_GREEN, merge(COL_AMBER, COL_RED, rpct >= 2.0_dp), rpct >= 5.0_dp))
        fl_card(:,3) = [cx2, band_y, cx2 + card_w, band_y + card_h]

        ! Live operator-advisory headline (severity-colored first line of the twin's brain)
        adv_y = band_y + card_h + GAP_CARD
        adv_h = band_h - card_h - GAP_CARD
        call draw_accent_card(hdc, kpi_x, adv_y, kpi_total_w, adv_h, COL_CYAN)
        call draw_text(hdc, kpi_x + PAD_CARD_X, adv_y + PAD_CARD_Y, "OPERATOR ADVISORY", COL_MUTED)
        advfull = grid%advisory_text
        nl = index(advfull, char(10))
        if (nl > 1) then
            advline = advfull(1:nl-1)
        else
            advline = advfull
        end if
        if (len_trim(advline) == 0) then
            advline = "STATUS OK  —  all subsystems within normal operating envelope."
            adv_col = COL_GREEN
        else if (advline(1:min(5,max(1,len_trim(advline)))) == "ALERT") then
            adv_col = COL_RED
        else if (index(advline, "DIAGNOSIS") == 1 .or. index(advline, "ANOMALY") == 1) then
            adv_col = COL_AMBER
        else if (index(advline, "OPT") == 1) then
            adv_col = COL_CYAN
        else
            adv_col = COL_INK
        end if
        if (len_trim(advline) > 88) advline = advline(1:86) // ".."
        call draw_title_text(hdc, kpi_x + PAD_CARD_X, adv_y + 34, trim(advline), adv_col)
        call draw_text(hdc, kpi_x + PAD_CARD_X, adv_y + adv_h - 24, &
            "F14 -> full advisory   ·   click any tile to drill down", COL_DIM)

        ! --- Hero: single-line plant schematic (B1) ---
        strip_h     = 92
        hero_y      = band_y + band_h + GAP_PANEL
        hero_bottom = y + height - strip_h - GAP_PANEL
        hero_h      = max(150, hero_bottom - hero_y)
        call draw_section_title_width(hdc, ix, hero_y, "Single-line plant schematic  (live flows)", iw)
        call draw_plant_schematic(hdc, ix, hero_y + 26, iw, hero_h - 26)

        ! --- Subsystem status strip (B3) ---
        strip_y  = hero_bottom + GAP_PANEL
        tile_gap = GAP_CARD
        tile_w   = (iw - 5 * tile_gap) / 6
        tile_h   = strip_h
        block
            character(len=24) :: l1, l2
            write(l1, '(F4.1," MW rated")') grid%p2x_capacity_MW
            write(l2, '(F4.2," kg/s H2")')  grid%p2x_h2_kg_s
            tx = ix
            call draw_subsystem_tile(hdc, tx, strip_y, tile_w, tile_h, "P2X", grid%p2x_active, COL_GREEN, &
                trim(adjustl(l1)), trim(adjustl(l2)))
            fl_tile(:,1) = [tx, strip_y, tx + tile_w, strip_y + tile_h]
            write(l1, '(F4.1," t/h CO2")')  grid%ccs_co2_captured_t_h
            write(l2, '(F4.1," MW par.")')  grid%ccs_parasitic_MW
            tx = ix + (tile_w + tile_gap)
            call draw_subsystem_tile(hdc, tx, strip_y, tile_w, tile_h, "CCS", grid%ccs_active, COL_GREEN, &
                trim(adjustl(l1)), trim(adjustl(l2)))
            fl_tile(:,2) = [tx, strip_y, tx + tile_w, strip_y + tile_h]
            write(l1, '(F4.1," s inertia")') grid%gfm_virtual_H
            l2 = "grid-forming"
            tx = ix + 2 * (tile_w + tile_gap)
            call draw_subsystem_tile(hdc, tx, strip_y, tile_w, tile_h, "GFM", grid%gfm_mode, COL_LIME, &
                trim(adjustl(l1)), trim(l2))
            fl_tile(:,3) = [tx, strip_y, tx + tile_w, strip_y + tile_h]
            write(l1, '(SP,F5.1," MW")')    grid%tie_flow_MW
            write(l2, '("sch ",SP,F5.1)')   grid%tie_scheduled_MW
            tx = ix + 3 * (tile_w + tile_gap)
            call draw_subsystem_tile(hdc, tx, strip_y, tile_w, tile_h, "TIE", grid%tie_active, COL_BLUE, &
                trim(adjustl(l1)), trim(adjustl(l2)))
            fl_tile(:,4) = [tx, strip_y, tx + tile_w, strip_y + tile_h]
            write(l1, '(SP,F5.1," ACE")')   grid%ace_MW
            l2 = "predictive AGC"
            tx = ix + 4 * (tile_w + tile_gap)
            call draw_subsystem_tile(hdc, tx, strip_y, tile_w, tile_h, "MPC", grid%mpc_active, COL_CYAN, &
                trim(adjustl(l1)), trim(l2))
            fl_tile(:,5) = [tx, strip_y, tx + tile_w, strip_y + tile_h]
            l1 = "online updates"
            l2 = merge("adapting    ", "monitoring  ", grid%dnn_adapting)
            tx = ix + 5 * (tile_w + tile_gap)
            call draw_subsystem_tile(hdc, tx, strip_y, tile_w, tile_h, "OU", grid%ou_active, COL_AMBER, &
                trim(l1), trim(l2))
            fl_tile(:,6) = [tx, strip_y, tx + tile_w, strip_y + tile_h]
        end block
    end subroutine draw_flagship_screen

    !> FLAGSHIP | DETAIL segmented toggle, top-right of the F1 caption row.
    !> Geometry must match the hit-test in handle_mouse_down.
    subroutine draw_overview_toggle(hdc, ix, iw, y1)
        type(c_ptr), value :: hdc
        integer, intent(in) :: ix, iw, y1
        integer :: l, r, t, b, midx

        r = ix + iw
        l = r - 176
        t = y1 + 4
        b = t + 26
        midx = (l + r) / 2
        call fill_soft_box(hdc, l, t, midx, b, merge(COL_PANEL_ALT, COL_CYAN, overview_detail))
        call draw_text(hdc, l + 12, t + 5, "FLAGSHIP", merge(COL_MUTED, COL_PANEL_DEEP, overview_detail))
        call fill_soft_box(hdc, midx, t, r, b, merge(COL_CYAN, COL_PANEL_ALT, overview_detail))
        call draw_text(hdc, midx + 20, t + 5, "DETAIL", merge(COL_PANEL_DEEP, COL_MUTED, overview_detail))
        call stroke_soft_box(hdc, l, t, r, b, COL_BORDER, 1)
    end subroutine draw_overview_toggle

    !> One subsystem status tile for the flagship strip (B3).
    subroutine draw_subsystem_tile(hdc, x, y, w, h, label, active, accent, line1, line2)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, w, h
        character(len=*), intent(in) :: label, line1, line2
        logical, intent(in) :: active
        integer(c_int), intent(in) :: accent
        integer :: pill_x, icid

        call fill_soft_box(hdc, x, y, x + w, y + h, merge(COL_PANEL_ALT, COL_PANEL_DEEP, active))
        call stroke_soft_box(hdc, x, y, x + w, y + h, merge(accent, COL_BORDER, active), merge(2, 1, active))
        call fill_box(hdc, x, y, x + w, y + 3, merge(accent, COL_BORDER_SOFT, active))
        ! [6.0-P3] line-art subsystem glyph (derived from the label) + name
        select case (trim(label))
        case ("P2X"); icid = ICON_P2X
        case ("CCS"); icid = ICON_CCS
        case ("GFM"); icid = ICON_GFM
        case ("TIE"); icid = ICON_TIE
        case ("MPC"); icid = ICON_MPC
        case ("OU");  icid = ICON_OU
        case default; icid = 0
        end select
        if (icid > 0) call draw_subsystem_icon(hdc, x + 22, y + 19, 11, icid, merge(accent, COL_MUTED, active))
        call draw_title_text(hdc, x + 42, y + 8, trim(label), merge(accent, COL_MUTED, active))
        pill_x = x + w - 44
        if (active) then
            call fill_soft_box(hdc, pill_x, y + 10, x + w - 8, y + 26, accent)
            call draw_text(hdc, pill_x + 9, y + 11, "ON", COL_PANEL_DEEP)
        else
            call stroke_soft_box(hdc, pill_x, y + 10, x + w - 8, y + 26, COL_BORDER, 1)
            call draw_text(hdc, pill_x + 5, y + 11, "OFF", COL_DIM)
        end if
        call draw_text(hdc, x + 10, y + 40, trim(line1), merge(COL_INK, COL_DIM, active))
        call draw_text(hdc, x + 10, y + 60, trim(line2), COL_MUTED)
    end subroutine draw_subsystem_tile

    !> [6.0-P3] Thin line-art glyph for a subsystem, centred at (cx,cy), half-size r.
    !> Pure line/box primitives (no fonts) — the technical-drawing icon language.
    subroutine draw_subsystem_icon(hdc, cx, cy, r, which, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: cx, cy, r, which
        integer(c_int), intent(in) :: color
        integer :: x0, y0, x1, y1

        x0 = cx - r;  y0 = cy - r;  x1 = cx + r;  y1 = cy + r
        select case (which)
        case (ICON_P2X)   ! electrolyser cell — tank + two electrodes + bubble
            call stroke_soft_box(hdc, x0, y0, x1, y1, color, 2)
            call draw_line(hdc, cx - 4, y0 + 3, cx - 4, y1 - 3, color, 2)
            call draw_line(hdc, cx + 4, y0 + 3, cx + 4, y1 - 3, color, 2)
            call fill_box(hdc, cx - 1, y0 + 4, cx + 1, y0 + 6, color)
        case (ICON_CCS)   ! carbon capture — column + down-arrow into storage baseline
            call stroke_soft_box(hdc, cx - 5, y0, cx + 5, y1 - 4, color, 2)
            call draw_line(hdc, cx, y0 + 4, cx, cy + 2, color, 2)
            call draw_line(hdc, cx - 3, cy - 1, cx, cy + 2, color, 2)
            call draw_line(hdc, cx + 3, cy - 1, cx, cy + 2, color, 2)
            call draw_line(hdc, x0, y1, x1, y1, color, 2)
        case (ICON_GFM)   ! grid-forming inverter — box, diagonal, AC sine / DC bars
            call stroke_soft_box(hdc, x0, y0, x1, y1, color, 2)
            call draw_line(hdc, x0, y1, x1, y0, color, 1)
            call draw_line(hdc, x0 + 3, cy + 4, x0 + 5, cy + 1, color, 1)
            call draw_line(hdc, x0 + 5, cy + 1, x0 + 7, cy + 4, color, 1)
            call draw_line(hdc, cx + 1, cy - 5, x1 - 2, cy - 5, color, 1)
            call draw_line(hdc, cx + 1, cy - 2, x1 - 2, cy - 2, color, 1)
        case (ICON_TIE)   ! tie-line — two nodes + bidirectional link
            call fill_box(hdc, x0, cy - 2, x0 + 4, cy + 2, color)
            call fill_box(hdc, x1 - 4, cy - 2, x1, cy + 2, color)
            call draw_line(hdc, x0 + 4, cy, x1 - 4, cy, color, 2)
            call draw_line(hdc, x0 + 7, cy - 3, x0 + 4, cy, color, 1)
            call draw_line(hdc, x0 + 7, cy + 3, x0 + 4, cy, color, 1)
            call draw_line(hdc, x1 - 7, cy - 3, x1 - 4, cy, color, 1)
            call draw_line(hdc, x1 - 7, cy + 3, x1 - 4, cy, color, 1)
        case (ICON_MPC)   ! predictive horizon — axes + measured rise + forecast dots
            call draw_line(hdc, x0, y0, x0, y1, color, 1)
            call draw_line(hdc, x0, y1, x1, y1, color, 1)
            call draw_line(hdc, x0, y1 - 2, cx, cy - 1, color, 2)
            call fill_box(hdc, cx + 3, cy - 4, cx + 5, cy - 2, color)
            call fill_box(hdc, x1 - 3, y0 + 2, x1 - 1, y0 + 4, color)
        case (ICON_OU)    ! online updates — small network (2 -> 1)
            call draw_line(hdc, x0 + 3, cy - 5, x1 - 3, cy, color, 1)
            call draw_line(hdc, x0 + 3, cy + 5, x1 - 3, cy, color, 1)
            call fill_box(hdc, x0, cy - 7, x0 + 4, cy - 3, color)
            call fill_box(hdc, x0, cy + 3, x0 + 4, cy + 7, color)
            call fill_box(hdc, x1 - 4, cy - 2, x1, cy + 2, color)
        end select
    end subroutine draw_subsystem_icon

    !> Big centered number for the health ring (uses the native renderer at a
    !> larger pixel size than the standard title font).
    subroutine draw_big_number(hdc, cx, cy, text, px, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: cx, cy, px
        character(len=*), intent(in) :: text
        integer(c_int), intent(in) :: color
        character(kind=c_char), allocatable, target :: c_text(:)
        integer :: n, tx

        n = len_trim(text)
        if (n <= 0) return
        call make_c_string(text(1:n), c_text)
        tx = cx - n * px / 4
        if (native_renderer_ready) then
            call hmi_draw_text_native(hdc, int(tx, c_int), int(cy, c_int), c_loc(c_text), &
                int(px, c_int), FW_SEMIBOLD + FW_MONO, color)
        else
            call draw_title_text(hdc, tx, cy, trim(text), color)
        end if
    end subroutine draw_big_number

    !> [5.0-B] Composite plant-health index (0-100) used by the flagship ring.
    !> Plant-wide "weakest link" heuristic over frequency, alarms, surge margin,
    !> reserve adequacy and BESS state — colored via the shared health_color().
    function plant_health_score() result(score)
        integer :: score, n_alm
        real(dp) :: rpct

        score = 100
        score = score - min(35, nint(max(0.0_dp, &
            abs(grid%frequency_Hz - grid%nominal_frequency_Hz) - 0.05_dp) / 0.05_dp * 8.0_dp))
        n_alm = count([grid%alarm_surge, grid%alarm_turbine_max, grid%alarm_ufls_active, &
                       grid%alarm_underfreq, grid%alarm_overfreq, grid%alarm_hrsg_pinch, &
                       grid%alarm_low_reserve, grid%alarm_low_soc])
        score = score - min(40, n_alm * 10)
        if (grid%surge_margin_pct < 15.0_dp) &
            score = score - min(20, nint(15.0_dp - grid%surge_margin_pct))
        rpct = 100.0_dp * merge(grid%fleet_reserve_MW, grid%reserve_MW, grid%fleet_mode) &
               / max(grid%demand_MW, 1.0_dp)
        if (rpct < 5.0_dp) score = score - min(15, nint((5.0_dp - rpct) * 3.0_dp))
        if (grid%battery_soc_pct < 20.0_dp) &
            score = score - min(10, nint((20.0_dp - grid%battery_soc_pct) / 2.0_dp))
        if (score < 0) score = 0
    end function plant_health_score

    !> [5.0-D1] Hit-test the flagship's clickable regions (cached during draw).
    function hit_test_flagship(x, y) result(fp_id)
        integer, intent(in) :: x, y
        integer :: fp_id, i
        integer, parameter :: CARD_FP(3) = [FP_MARGIN, FP_CO2, FP_RESERVE]
        integer, parameter :: SUB_FP(6)  = [FP_SUB_P2X, FP_SUB_CCS, FP_SUB_GFM, &
                                            FP_SUB_TIE, FP_SUB_MPC, FP_SUB_OU]

        fp_id = FP_NONE
        if (point_in_rect(x, y, fl_ring(1), fl_ring(2), fl_ring(3), fl_ring(4))) then
            fp_id = FP_HEALTH; return
        end if
        do i = 1, 3
            if (point_in_rect(x, y, fl_card(1,i), fl_card(2,i), fl_card(3,i), fl_card(4,i))) then
                fp_id = CARD_FP(i); return
            end if
        end do
        do i = 1, 6
            if (point_in_rect(x, y, fl_tile(1,i), fl_tile(2,i), fl_tile(3,i), fl_tile(4,i))) then
                fp_id = SUB_FP(i); return
            end if
        end do
    end function hit_test_flagship

    !> [6.0-P4] Process-arrow helper for P&ID-style single-line drawings.
    subroutine draw_pid_arrow_line(hdc, x1, y1, x2, y2, color, pen_w)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x1, y1, x2, y2, pen_w
        integer(c_int), intent(in) :: color
        integer :: a

        a = 7
        call draw_line(hdc, x1, y1, x2, y2, color, pen_w)
        if (abs(x2 - x1) >= abs(y2 - y1)) then
            if (x2 >= x1) then
                call draw_line(hdc, x2, y2, x2 - a, y2 - 4, color, pen_w)
                call draw_line(hdc, x2, y2, x2 - a, y2 + 4, color, pen_w)
            else
                call draw_line(hdc, x2, y2, x2 + a, y2 - 4, color, pen_w)
                call draw_line(hdc, x2, y2, x2 + a, y2 + 4, color, pen_w)
            end if
        else
            if (y2 >= y1) then
                call draw_line(hdc, x2, y2, x2 - 4, y2 - a, color, pen_w)
                call draw_line(hdc, x2, y2, x2 + 4, y2 - a, color, pen_w)
            else
                call draw_line(hdc, x2, y2, x2 - 4, y2 + a, color, pen_w)
                call draw_line(hdc, x2, y2, x2 + 4, y2 + a, color, pen_w)
            end if
        end if
    end subroutine draw_pid_arrow_line

    !> [6.0-P4] Dimension-line motif used to make the schematic read like a drawing.
    subroutine draw_pid_dimension(hdc, x1, y1, x2, y2, label, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x1, y1, x2, y2
        character(len=*), intent(in) :: label
        integer(c_int), intent(in) :: color
        integer :: tx, ty

        call draw_line(hdc, x1, y1, x2, y2, color, 1)
        if (abs(x2 - x1) >= abs(y2 - y1)) then
            call draw_line(hdc, x1, y1 - 5, x1, y1 + 5, color, 1)
            call draw_line(hdc, x2, y2 - 5, x2, y2 + 5, color, 1)
            tx = (x1 + x2) / 2 - len_trim(label) * 4
            ty = y1 - 18
        else
            call draw_line(hdc, x1 - 5, y1, x1 + 5, y1, color, 1)
            call draw_line(hdc, x2 - 5, y2, x2 + 5, y2, color, 1)
            tx = x1 + 8
            ty = (y1 + y2) / 2 - 8
        end if
        call draw_text(hdc, tx, ty, trim(label), color)
    end subroutine draw_pid_dimension

    !> [6.0-P4] Instrument callout box, tagged like a plant drawing.
    subroutine draw_pid_callout(hdc, anchor_x, anchor_y, box_x, box_y, tag, value_text, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: anchor_x, anchor_y, box_x, box_y
        character(len=*), intent(in) :: tag, value_text
        integer(c_int), intent(in) :: color
        integer :: w, h

        w = max(104, min(170, 28 + max(len_trim(tag), len_trim(value_text)) * 8))
        h = 40
        call draw_line(hdc, anchor_x, anchor_y, box_x, box_y + h / 2, color, 1)
        call fill_soft_box(hdc, box_x, box_y, box_x + w, box_y + h, COL_PANEL_ALT)
        call stroke_soft_box(hdc, box_x, box_y, box_x + w, box_y + h, color, 1)
        call fill_box(hdc, box_x, box_y, box_x + 4, box_y + h, color)
        call draw_text(hdc, box_x + 10, box_y + 5, trim(tag), COL_MUTED)
        call draw_mono(hdc, box_x + 10, box_y + 21, trim(value_text), color)
    end subroutine draw_pid_callout

    !> [6.0-P4] Generic equipment tag box for non-rotating skids.
    subroutine draw_pid_equipment(hdc, cx, cy, w, h, tag, value_text, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: cx, cy, w, h
        character(len=*), intent(in) :: tag, value_text
        integer(c_int), intent(in) :: color
        integer :: x0, y0, x1, y1

        x0 = cx - w / 2
        y0 = cy - h / 2
        x1 = cx + w / 2
        y1 = cy + h / 2
        call fill_soft_box(hdc, x0, y0, x1, y1, COL_PANEL_ALT)
        call stroke_soft_box(hdc, x0, y0, x1, y1, color, 1)
        call fill_box(hdc, x0, y0, x1, y0 + 3, color)
        call draw_text(hdc, x0 + 7, y0 + 5, trim(tag), color)
        if (h >= 34) call draw_mono(hdc, x0 + 7, y0 + h / 2, trim(value_text), COL_INK)
    end subroutine draw_pid_equipment

    subroutine draw_pid_compressor(hdc, cx, cy, w, h, tag, value_text, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: cx, cy, w, h
        character(len=*), intent(in) :: tag, value_text
        integer(c_int), intent(in) :: color
        integer :: x0, y0, x1, y1

        x0 = cx - w / 2; y0 = cy - h / 2; x1 = cx + w / 2; y1 = cy + h / 2
        call fill_soft_box(hdc, x0, y0, x1, y1, COL_PANEL_ALT)
        call stroke_soft_box(hdc, x0, y0, x1, y1, color, 1)
        call draw_line(hdc, x0 + 8, y0 + 7, x1 - 8, cy, color, 2)
        call draw_line(hdc, x1 - 8, cy, x0 + 8, y1 - 7, color, 2)
        call draw_line(hdc, x0 + 8, y1 - 7, x0 + 8, y0 + 7, color, 2)
        call draw_text(hdc, x0 + 7, y0 + 4, trim(tag), color)
        if (h >= 38) call draw_mono(hdc, x0 + 7, cy + 5, trim(value_text), COL_INK)
    end subroutine draw_pid_compressor

    subroutine draw_pid_combustor(hdc, cx, cy, w, h, tag, value_text, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: cx, cy, w, h
        character(len=*), intent(in) :: tag, value_text
        integer(c_int), intent(in) :: color
        integer :: x0, y0, x1, y1

        x0 = cx - w / 2; y0 = cy - h / 2; x1 = cx + w / 2; y1 = cy + h / 2
        call fill_soft_box(hdc, x0, y0, x1, y1, COL_PANEL_ALT)
        call stroke_soft_box(hdc, x0, y0, x1, y1, color, 1)
        call draw_line(hdc, x0 + 8, y0 + 8, x1 - 8, y0 + 8, color, 1)
        call draw_line(hdc, x0 + 8, y1 - 8, x1 - 8, y1 - 8, color, 1)
        call draw_line(hdc, cx - 6, cy + 5, cx, cy - 8, color, 2)
        call draw_line(hdc, cx, cy - 8, cx + 6, cy + 5, color, 2)
        call draw_text(hdc, x0 + 7, y0 + 4, trim(tag), color)
        if (h >= 38) call draw_mono(hdc, x0 + 7, cy + 5, trim(value_text), COL_INK)
    end subroutine draw_pid_combustor

    subroutine draw_pid_turbine(hdc, cx, cy, w, h, tag, value_text, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: cx, cy, w, h
        character(len=*), intent(in) :: tag, value_text
        integer(c_int), intent(in) :: color
        integer :: x0, y0, x1, y1

        x0 = cx - w / 2; y0 = cy - h / 2; x1 = cx + w / 2; y1 = cy + h / 2
        call fill_soft_box(hdc, x0, y0, x1, y1, COL_PANEL_ALT)
        call stroke_soft_box(hdc, x0, y0, x1, y1, color, 1)
        call draw_line(hdc, x0 + 8, cy, x1 - 8, y0 + 7, color, 2)
        call draw_line(hdc, x1 - 8, y0 + 7, x1 - 8, y1 - 7, color, 2)
        call draw_line(hdc, x1 - 8, y1 - 7, x0 + 8, cy, color, 2)
        call draw_text(hdc, x0 + 7, y0 + 4, trim(tag), color)
        if (h >= 38) call draw_mono(hdc, x0 + 7, cy + 5, trim(value_text), COL_INK)
    end subroutine draw_pid_turbine

    subroutine draw_pid_generator(hdc, cx, cy, r, tag, value_text, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: cx, cy, r
        character(len=*), intent(in) :: tag, value_text
        integer(c_int), intent(in) :: color

        call hmi_fill_pie(hdc, int(cx, c_int), int(cy, c_int), int(r, c_int), &
            0.0_c_float, 360.0_c_float, COL_PANEL_ALT)
        call hmi_draw_arc(hdc, int(cx, c_int), int(cy, c_int), int(r, c_int), &
            0.0_c_float, 360.0_c_float, color, 2_c_int)
        call draw_text(hdc, cx - r + 8, cy - 9, trim(tag), color)
        if (r >= 20) call draw_mono(hdc, cx - r + 8, cy + 8, trim(value_text), COL_INK)
    end subroutine draw_pid_generator

    subroutine draw_pid_inverter(hdc, cx, cy, w, h, tag, value_text, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: cx, cy, w, h
        character(len=*), intent(in) :: tag, value_text
        integer(c_int), intent(in) :: color
        integer :: x0, y0, x1, y1

        x0 = cx - w / 2; y0 = cy - h / 2; x1 = cx + w / 2; y1 = cy + h / 2
        call fill_soft_box(hdc, x0, y0, x1, y1, COL_PANEL_ALT)
        call stroke_soft_box(hdc, x0, y0, x1, y1, color, 1)
        call draw_line(hdc, x0 + 5, y1 - 5, x1 - 5, y0 + 5, color, 1)
        call draw_text(hdc, x0 + 7, y0 + 4, trim(tag), color)
        if (h >= 34) call draw_mono(hdc, x0 + 7, cy + 3, trim(value_text), COL_INK)
    end subroutine draw_pid_inverter

    subroutine draw_pid_battery(hdc, cx, cy, w, h, tag, value_text, color)
        type(c_ptr), value :: hdc
        integer, intent(in) :: cx, cy, w, h
        character(len=*), intent(in) :: tag, value_text
        integer(c_int), intent(in) :: color
        integer :: x0, y0, x1, y1, sx

        x0 = cx - w / 2; y0 = cy - h / 2; x1 = cx + w / 2; y1 = cy + h / 2
        call fill_soft_box(hdc, x0, y0, x1, y1, COL_PANEL_ALT)
        call stroke_soft_box(hdc, x0, y0, x1, y1, color, 1)
        sx = x0 + 7
        call stroke_box(hdc, sx, y0 + 8, sx + 20, y1 - 8, color, 1)
        call fill_box(hdc, sx + 20, cy - 4, sx + 24, cy + 4, color)
        call draw_text(hdc, x0 + 34, y0 + 4, trim(tag), color)
        if (h >= 34) call draw_mono(hdc, x0 + 34, cy + 3, trim(value_text), COL_INK)
    end subroutine draw_pid_battery

    subroutine draw_plant_schematic(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height

        integer :: eq_w, eq_h, main_y, branch_y, h2_y, aux_y, hrsg_y
        integer :: x_air, x_comp, x_comb, x_turb, x_gen, x_bus, x_load
        integer :: x_bess, x_res, x_hrsg, x_st, x_p2x, x_ccs
        integer :: dot_x, dot_y, i, seg_len, seg_y, n_dots, spacing, gen_r
        integer :: bus_top, bus_bot, stack_x, stack_y
        integer(c_int) :: stream_col, bess_col, res_col
        character(len=24) :: lbl, lbl2, lbl3, lbl4, lbl5
        logical :: compact, show_callouts, show_branches
        integer, save :: flow_phase = 0   ! animation counter, advances each repaint

        if (width < 260 .or. height < 68) return

        compact = height < 170 .or. width < 640
        show_callouts = .not. compact .and. height >= 220
        show_branches = height >= 150 .and. width >= 520

        eq_w = max(46, min(92, width / 11))
        eq_h = max(30, min(50, height / 5))
        if (compact) then
            eq_w = max(42, min(72, width / 10))
            eq_h = max(28, min(38, height / 4))
        end if
        gen_r = max(18, min(28, eq_h / 2 + 4))
        main_y = y + merge(height / 2, height * 43 / 100, compact)
        main_y = max(y + eq_h + 18, min(y + height - eq_h - 20, main_y))
        branch_y = y + height - eq_h / 2 - 16
        aux_y = branch_y
        hrsg_y = branch_y
        if (.not. compact .and. height >= 260) then
            hrsg_y = main_y + eq_h + 56
            if (hrsg_y > y + height - eq_h - 72) hrsg_y = y + height - eq_h - 72
            if (hrsg_y < main_y + eq_h + 34) hrsg_y = main_y + eq_h + 34
            aux_y = y + height - eq_h / 2 - 16
        end if
        h2_y = aux_y

        x_air  = x + 22
        x_comp = x + width * 13 / 100
        x_comb = x + width * 30 / 100
        x_turb = x + width * 47 / 100
        x_gen  = x + width * 62 / 100
        x_bus  = x + width * 76 / 100
        x_load = x + width - max(36, eq_w / 2 + 14)
        x_hrsg = x + width * 52 / 100
        x_st   = x + width * 64 / 100
        x_bess = x + width * 67 / 100
        x_res  = x + width * 86 / 100
        x_p2x  = x + width * 23 / 100
        x_ccs  = x + width * 56 / 100

        ! Advance animation phase against elapsed time so flow speed stays stable as
        ! the HMI scan cadence changes.
        flow_phase = mod(flow_phase + max(1, nint(real(TIMER_MS, dp) * 8.0_dp / 1000.0_dp)), 256)

        call draw_panel_box_deep(hdc, x, y, width, height)
        if (.not. compact) then
            call draw_text(hdc, x + 12, y + 8, "PFD-001  LIVE PLANT SINGLE-LINE", COL_MUTED)
            call draw_text(hdc, x + width - 172, y + 8, "ISA STYLE / REALTIME", COL_DIM)
        end if

        ! Main gas/electrical train: air -> compressor -> combustor -> turbine -> generator -> bus.
        stream_col = merge(int(Z'00BBFFFF', c_int), COL_AMBER, grid%exhaust_K < 800.0_dp)
        call draw_pid_arrow_line(hdc, x_air, main_y, x_comp - eq_w / 2, main_y, COL_BORDER_SOFT, 2)
        call draw_pid_arrow_line(hdc, x_comp + eq_w / 2, main_y, x_comb - eq_w / 2, main_y, COL_CYAN, 2)
        call draw_pid_arrow_line(hdc, x_comb + eq_w / 2, main_y, x_turb - eq_w / 2, main_y, COL_AMBER, 2)
        call draw_pid_arrow_line(hdc, x_turb + eq_w / 2, main_y, x_gen - gen_r, main_y, stream_col, 2)
        call draw_pid_arrow_line(hdc, x_gen + gen_r, main_y, x_bus, main_y, COL_GREEN, 2)
        call draw_pid_arrow_line(hdc, x_bus, main_y, x_load - eq_w / 2, main_y, COL_RED, 2)

        ! Animated flow markers stay subtle; the linework remains the main artifact.
        stream_col = merge(int(Z'00BBFFFF', c_int), COL_AMBER, &
                           grid%exhaust_K < 800.0_dp)
        spacing = 18
        seg_len = max(1, x_load - (x_comp + eq_w/2))
        n_dots  = seg_len / spacing + 2
        do i = 0, n_dots
            dot_x = x_comp + eq_w/2 + mod(i * spacing + flow_phase, seg_len)
            if (dot_x >= x_comp + eq_w/2 .and. dot_x < x_load - 4) then
                call fill_box(hdc, dot_x - 1, main_y - 1, dot_x + 2, main_y + 2, stream_col)
            end if
        end do

        ! Equipment symbols and live tags.
        write(lbl, '("PR ",F4.1)') grid%PR_op
        call draw_pid_compressor(hdc, x_comp, main_y, eq_w, eq_h, "C-101", trim(adjustl(lbl)), COL_CYAN)
        write(lbl, '(I4,"K")') nint(grid%TIT_actual_K)
        call draw_pid_combustor(hdc, x_comb, main_y, eq_w, eq_h, "CB-201", trim(adjustl(lbl)), &
            merge(COL_RED, COL_AMBER, grid%TIT_actual_K > 1480.0_dp))
        write(lbl, '(I4,"K")') nint(grid%exhaust_K)
        call draw_pid_turbine(hdc, x_turb, main_y, eq_w, eq_h, "GT-301", trim(adjustl(lbl)), &
            merge(COL_RED, COL_AMBER, grid%alarm_turbine_max))
        write(lbl, '(I4,"MW")') nint(grid%plant_power_MW)
        call draw_pid_generator(hdc, x_gen, main_y, gen_r, "G-401", trim(adjustl(lbl)), COL_GREEN)
        write(lbl, '(F5.2,"Hz")') grid%frequency_Hz
        bus_top = main_y - max(34, eq_h)
        bus_bot = main_y + max(42, eq_h + 10)
        call draw_line(hdc, x_bus, bus_top, x_bus, bus_bot, frequency_color(), 3)
        call draw_line(hdc, x_bus - 8, bus_top, x_bus + 8, bus_top, frequency_color(), 1)
        call draw_line(hdc, x_bus - 8, bus_bot, x_bus + 8, bus_bot, frequency_color(), 1)
        call draw_text(hdc, x_bus + 8, bus_top + 2, "BUS-001", COL_MUTED)
        call draw_mono(hdc, x_bus + 8, bus_top + 20, trim(adjustl(lbl)), frequency_color())
        write(lbl, '(I4,"MW")') nint(grid%demand_MW)
        call draw_pid_equipment(hdc, x_load, main_y, eq_w, eq_h, "LOAD", trim(adjustl(lbl)), COL_RED)

        if (.not. compact) then
            call draw_text(hdc, x_air, main_y - 24, "AIR", COL_DIM)
            call draw_pid_dimension(hdc, x_comp, main_y - eq_h / 2 - 14, x_gen, main_y - eq_h / 2 - 14, &
                "GT SHAFT TRAIN", COL_DIM)
            call draw_pid_dimension(hdc, x_gen + gen_r, main_y + eq_h / 2 + 14, x_bus, main_y + eq_h / 2 + 14, &
                "ELECTRICAL BUS", COL_DIM)
        end if

        ! Fuel and optional H2/P2X line into combustor.
        if (show_branches) then
            write(lbl, '(F4.2,"kg/s")') grid%fuel_flow_kg_s
            call draw_pid_arrow_line(hdc, x_comb, aux_y, x_comb, main_y + eq_h / 2, COL_AMBER, 2)
            call draw_text(hdc, x_comb + 6, aux_y - 10, "NG", COL_AMBER)
            call draw_mono(hdc, x_comb + 28, aux_y - 10, trim(adjustl(lbl)), COL_MUTED)
            if (grid%p2x_active .or. grid%h2_fraction_pct > 0.1_dp) then
                write(lbl, '(F4.1,"% H2")') grid%h2_fraction_pct
                call draw_pid_inverter(hdc, x_p2x, h2_y, eq_w, eq_h, "P2X", trim(adjustl(lbl)), COL_CYAN)
                call draw_pid_arrow_line(hdc, x_p2x + eq_w / 2, h2_y, x_comb - 2, h2_y, COL_CYAN, 1)
                call draw_pid_arrow_line(hdc, x_comb - 2, h2_y, x_comb - 2, main_y + eq_h / 2, COL_CYAN, 1)
            end if
        end if

        ! Heat-recovery branch: visible only in combined-cycle mode.
        if (show_branches .and. grid%combined_cycle .and. height >= 220) then
            write(lbl, '(I4,"K")') nint(grid%hrsg_stack_T_K)
            write(lbl2, '(I4,"MW")') nint(grid%hrsg_recovered_heat_MW)
            write(lbl3, '(I4,"MW")') nint(grid%steam_power_MW)
            call draw_pid_arrow_line(hdc, x_turb + eq_w / 2, main_y + eq_h / 2, x_turb + eq_w / 2, hrsg_y, COL_RED, 2)
            call draw_pid_arrow_line(hdc, x_turb + eq_w / 2, hrsg_y, x_hrsg - eq_w / 2, hrsg_y, COL_RED, 2)
            call draw_pid_equipment(hdc, x_hrsg, hrsg_y, eq_w, eq_h, "H-501", trim(adjustl(lbl2)), COL_RED)
            call draw_pid_arrow_line(hdc, x_hrsg + eq_w / 2, hrsg_y, x_st - eq_w / 2, hrsg_y, COL_CYAN, 2)
            call draw_pid_turbine(hdc, x_st, hrsg_y, eq_w, eq_h, "ST-601", trim(adjustl(lbl3)), COL_BLUE)
            call draw_pid_arrow_line(hdc, x_st + eq_w / 2, hrsg_y, x_bus, main_y + 18, COL_BLUE, 1)
            stack_x = x_hrsg
            stack_y = max(y + 20, hrsg_y - eq_h - 26)
            call draw_pid_arrow_line(hdc, x_hrsg, hrsg_y - eq_h / 2, stack_x, stack_y, COL_RED, 1)
            call draw_text(hdc, stack_x + 8, stack_y - 8, "STACK", COL_MUTED)
            call draw_mono(hdc, stack_x + 8, stack_y + 8, trim(adjustl(lbl)), COL_RED)
            if (grid%ccs_active) then
                write(lbl4, '(F4.1,"t/h")') grid%ccs_co2_captured_t_h
                call draw_pid_equipment(hdc, x_ccs + eq_w, stack_y + 12, eq_w, eq_h, "CCS", trim(adjustl(lbl4)), COL_GREEN)
                call draw_pid_arrow_line(hdc, stack_x + 18, stack_y + 8, x_ccs + eq_w / 2, stack_y + 12, COL_GREEN, 1)
            end if
        end if

        ! BESS and renewable injection onto the bus.
        if (show_branches) then
            bess_col = merge(COL_GREEN, merge(COL_RED, COL_BLUE, grid%storage_MW < -0.1_dp), grid%storage_MW > 0.1_dp)
            write(lbl, '(I3,"%")') nint(grid%battery_soc_pct)
            call draw_pid_battery(hdc, x_bess, aux_y, eq_w, eq_h, "BESS", trim(adjustl(lbl)), bess_col)
            call draw_line(hdc, x_bess, aux_y - eq_h / 2, x_bess, main_y + eq_h / 2, COL_BLUE, 1)
            call draw_pid_arrow_line(hdc, x_bess, main_y + eq_h / 2, x_bus, main_y + eq_h / 2, bess_col, 1)
            if (abs(grid%storage_MW) > 0.1_dp) then
                seg_y = max(1, aux_y - eq_h / 2 - (main_y + eq_h / 2))
                n_dots = seg_y / spacing + 2
                do i = 0, n_dots
                    if (grid%storage_MW > 0.0_dp) then
                        dot_y = aux_y - eq_h / 2 - mod(i * spacing + flow_phase, seg_y)
                        stream_col = COL_GREEN
                    else
                        dot_y = main_y + eq_h / 2 + mod(i * spacing + flow_phase, seg_y)
                        stream_col = COL_RED
                    end if
                    if (dot_y > main_y + eq_h / 2 .and. dot_y < branch_y - eq_h / 2) &
                        call fill_box(hdc, x_bess - 1, dot_y - 1, x_bess + 2, dot_y + 2, stream_col)
                end do
            end if

            res_col = merge(COL_AMBER, COL_GREEN, grid%renewable_curtail_MW > 0.05_dp)
            write(lbl, '(F4.1,"MW")') effective_renewable_MW(grid)
            call draw_pid_inverter(hdc, x_res, aux_y, eq_w, eq_h, "RES", trim(adjustl(lbl)), res_col)
            call draw_line(hdc, x_res, aux_y - eq_h / 2, x_res, main_y + eq_h / 2, res_col, 1)
            call draw_pid_arrow_line(hdc, x_res, main_y + eq_h / 2, x_bus, main_y + eq_h / 2, res_col, 1)
        end if

        ! Instrument boxes and drawing annotations.
        if (show_callouts) then
            write(lbl, '(F4.1)') grid%PR_op
            write(lbl2, '(I4,"K")') nint(grid%TIT_actual_K)
            write(lbl3, '(I4,"MW")') nint(grid%plant_power_MW)
            write(lbl4, '(I4,"g/kWh")') nint(grid%CO2_intensity_g_kWh)
            write(lbl5, '(SP,F5.1,"MW")') grid%imbalance_MW
            call draw_pid_callout(hdc, x_comp, main_y - eq_h / 2, x + 16, y + 32, "PI-101 PR", trim(adjustl(lbl)), COL_CYAN)
            call draw_pid_callout(hdc, x_comb, main_y - eq_h / 2, x + width * 28 / 100, y + 32, "TI-201 TIT", trim(adjustl(lbl2)), COL_AMBER)
            call draw_pid_callout(hdc, x_gen, main_y - gen_r, x + width * 55 / 100, y + 32, "EI-401 MW", trim(adjustl(lbl3)), COL_GREEN)
            call draw_pid_callout(hdc, x_bus, main_y, x + width - 160, y + 32, "AI-001 BAL", trim(adjustl(lbl5)), &
                merge(COL_GREEN, COL_RED, abs(grid%imbalance_MW) <= 0.5_dp))
            if (height >= 280) call draw_pid_callout(hdc, x_turb, main_y + eq_h / 2, x + 18, y + height - 58, &
                "CI-501 CO2", trim(adjustl(lbl4)), merge(COL_GREEN, COL_AMBER, grid%CO2_intensity_g_kWh < 600.0_dp))
        end if

    end subroutine draw_plant_schematic

    ! =========================================================================
    ! Keyboard help overlay  (? key toggles, Escape dismisses)
    ! =========================================================================
    subroutine draw_help_overlay(hdc, x0, y0, w, h)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x0, y0, w, h
        integer :: mx, my, mw, mh, row_y, col1, col2

        ! Semi-transparent dark background
        call hmi_fill_alpha_rect(hdc, int(x0,c_int), int(y0,c_int), &
            int(x0+w,c_int), int(y0+h,c_int), COL_BG, 220_c_int)

        ! Modal box
        mw = min(700, w - 80);   mh = min(560, h - 80)
        mx = x0 + (w - mw) / 2; my = y0 + (h - mh) / 2
        call hmi_fill_alpha_round_rect(hdc, int(mx,c_int), int(my,c_int), &
            int(mx+mw,c_int), int(my+mh,c_int), 8_c_int, COL_PANEL_ALT, 250_c_int)
        call stroke_soft_box(hdc, mx, my, mx + mw, my + mh, COL_CYAN, 1)

        row_y = my + 14
        call draw_title_text(hdc, mx + 18, row_y, "Keyboard Reference", COL_INK)
        call draw_text(hdc, mx + mw - 120, row_y + 6, "Esc or ? to close", COL_DIM)
        row_y = row_y + 40
        call draw_line(hdc, mx + 12, row_y, mx + mw - 12, row_y, COL_BORDER_SOFT, 1)
        row_y = row_y + 12

        col1 = mx + 18
        col2 = mx + mw / 2 + 10

        ! Left column: screen navigation
        call draw_text(hdc, col1, row_y, "SCREEN NAVIGATION", COL_MUTED)
        row_y = row_y + 20
        call draw_value_pair(hdc, col1, row_y, "F1",  "Overview  (arc gauges, P&ID)", COL_INK)
        row_y = row_y + 16
        call draw_value_pair(hdc, col1, row_y, "F2",  "Grid Dispatch & Frequency",    COL_INK)
        row_y = row_y + 16
        call draw_value_pair(hdc, col1, row_y, "F3",  "Gas Turbine operating point",  COL_INK)
        row_y = row_y + 16
        call draw_value_pair(hdc, col1, row_y, "F4",  "Combined Cycle (HRSG/steam)",  COL_INK)
        row_y = row_y + 16
        call draw_value_pair(hdc, col1, row_y, "F5",  "Market & Economics",           COL_INK)
        row_y = row_y + 16
        call draw_value_pair(hdc, col1, row_y, "F6",  "Trends (history plots)",       COL_INK)
        row_y = row_y + 16
        call draw_value_pair(hdc, col1, row_y, "F7",  "Alarms  (ISA-18.2 log)",       COL_INK)
        row_y = row_y + 16
        call draw_value_pair(hdc, col1, row_y, "F8",  "Diagnostics  (health + ENTSO-E)", COL_INK)
        row_y = row_y + 16
        call draw_value_pair(hdc, col1, row_y, "F9",  "Day-Ahead MINLP  (24 h plan)", COL_INK)
        row_y = row_y + 16
        call draw_value_pair(hdc, col1, row_y, "F10", "Fleet UC + Econ Dispatch",     COL_INK)
        row_y = row_y + 16
        call draw_value_pair(hdc, col1, row_y, "F11", "DNN Diagnostics  (HR + policy)",COL_INK)
        row_y = row_y + 16
        call draw_value_pair(hdc, col1, row_y, "F12", "Carbon & Sustainability  (H2)",COL_CYAN)
        row_y = row_y + 16
        call draw_value_pair(hdc, col1, row_y, "Esc", "Back to Overview  /  close",   COL_MUTED)

        ! Right column: actions
        row_y = my + 66
        call draw_text(hdc, col2, row_y, "CONTROLS & ACTIONS", COL_MUTED)
        row_y = row_y + 20
        call draw_value_pair(hdc, col2, row_y, "Up / Down", "H2 blend ±1 vol% (on F12)",COL_CYAN)
        row_y = row_y + 16
        call draw_value_pair(hdc, col2, row_y, "E",         "Export shift CSV",         COL_INK)
        row_y = row_y + 16
        call draw_value_pair(hdc, col2, row_y, "?",         "Toggle this help overlay", COL_INK)
        row_y = row_y + 28
        call draw_text(hdc, col2, row_y, "LEFT PANEL SLIDERS", COL_MUTED)
        row_y = row_y + 20
        call draw_value_pair(hdc, col2, row_y, "Demand",    "Grid demand  [MW]",        COL_INK)
        row_y = row_y + 16
        call draw_value_pair(hdc, col2, row_y, "Renewable", "Renewable capacity  [MW]", COL_INK)
        row_y = row_y + 16
        call draw_value_pair(hdc, col2, row_y, "Storage",   "BESS power request  [MW]", COL_INK)
        row_y = row_y + 16
        call draw_value_pair(hdc, col2, row_y, "Gas CT",    "GT dispatch target  [%]",  COL_INK)
        row_y = row_y + 16
        call draw_value_pair(hdc, col2, row_y, "Ambient",   "Ambient temperature  [°C]",COL_INK)
        row_y = row_y + 16
        call draw_value_pair(hdc, col2, row_y, "TIT",       "Turbine inlet temp  [K]",  COL_INK)
        row_y = row_y + 28
        call draw_text(hdc, col2, row_y, "SCENARIOS", COL_MUTED)
        row_y = row_y + 20
        call draw_value_pair(hdc, col2, row_y, "Prev / Next", "Cycle through .scn files", COL_INK)
        row_y = row_y + 16
        call draw_value_pair(hdc, col2, row_y, "Run / Stop",  "Play the selected scenario", COL_INK)

        ! Footer
        call draw_line(hdc, mx + 12, my + mh - 28, mx + mw - 12, my + mh - 28, COL_BORDER_SOFT, 1)
        call draw_text(hdc, mx + 18, my + mh - 18, &
            "ThermoTwin-F  |  Fortran 2008 + Win32 + GDI+  |  claude-sonnet-4-6", COL_DIM)

    end subroutine draw_help_overlay

    subroutine draw_global_overlays(hdc, x0, y0, w, h)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x0, y0, w, h
        if (demo_mode_active) call draw_demo_caption(hdc, x0, y0, w, h)
        if (coach_overlay_active) call draw_coach_overlay(hdc, x0, y0, w, h)
        if (settings_overlay_active) call draw_settings_overlay(hdc, x0, y0, w, h)
        if (command_palette_active) call draw_command_palette(hdc, x0, y0, w, h)
    end subroutine draw_global_overlays

    subroutine draw_command_palette(hdc, x0, y0, w, h)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x0, y0, w, h
        integer :: pw, px, py, row_h, first_cmd, visible_n, i, cmd, row_y
        character(len=64) :: label

        pw = min(720, max(520, w / 2))
        px = x0 + w / 2 - pw / 2
        py = y0 + 92
        row_h = 34
        first_cmd = max(1, min(command_palette_index - 5, max(1, CMD_COUNT - 11)))
        visible_n = min(12, CMD_COUNT - first_cmd + 1)
        call hmi_fill_alpha_rect(hdc, int(x0, c_int), int(y0, c_int), int(x0 + w, c_int), int(y0 + h, c_int), COL_BG, 168_c_int)
        call fill_soft_box(hdc, px, py, px + pw, py + 74 + visible_n * row_h + 18, COL_PANEL_DEEP)
        call stroke_soft_box(hdc, px, py, px + pw, py + 74 + visible_n * row_h + 18, COL_CYAN, 1)
        call fill_box(hdc, px, py, px + pw, py + 46, COL_PANEL)
        call fill_box(hdc, px, py, px + 5, py + 46, COL_CYAN)
        call draw_title_text(hdc, px + 18, py + 11, "Command Palette", COL_INK)
        call draw_text(hdc, px + pw - 246, py + 15, "Ctrl-K  |  Enter run  |  Esc close", COL_MUTED)
        call draw_text(hdc, px + 18, py + 52, "Jump to screens, switch HMI modes, or run operator commands.", COL_MUTED)

        do i = 1, visible_n
            cmd = first_cmd + i - 1
            row_y = py + 68 + (i - 1) * row_h
            if (cmd == command_palette_index) then
                call fill_soft_box(hdc, px + 12, row_y, px + pw - 12, row_y + row_h - 4, COL_PANEL_ALT)
                call stroke_soft_box(hdc, px + 12, row_y, px + pw - 12, row_y + row_h - 4, COL_CYAN, 1)
            end if
            label = palette_command_label(cmd)
            call draw_text(hdc, px + 28, row_y + 8, trim(label), merge(COL_CYAN, COL_INK, cmd == command_palette_index))
        end do
    end subroutine draw_command_palette

    subroutine draw_settings_overlay(hdc, x0, y0, w, h)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x0, y0, w, h
        integer :: pw, px, py, row_h, row_y, i
        character(len=96) :: label

        pw = min(680, max(520, w / 2))
        px = x0 + w / 2 - pw / 2
        py = y0 + 118
        row_h = 40
        call hmi_fill_alpha_rect(hdc, int(x0, c_int), int(y0, c_int), int(x0 + w, c_int), int(y0 + h, c_int), COL_BG, 150_c_int)
        call fill_soft_box(hdc, px, py, px + pw, py + 92 + SETTINGS_COUNT * row_h, COL_PANEL_DEEP)
        call stroke_soft_box(hdc, px, py, px + pw, py + 92 + SETTINGS_COUNT * row_h, COL_CYAN, 1)
        call fill_box(hdc, px, py, px + pw, py + 50, COL_PANEL)
        call fill_box(hdc, px, py, px + 5, py + 50, COL_CYAN)
        call draw_title_text(hdc, px + 18, py + 12, "Settings", COL_INK)
        call draw_text(hdc, px + pw - 270, py + 16, "Enter toggles  |  Left/Right adjusts  |  Esc closes", COL_MUTED)
        call draw_text(hdc, px + 18, py + 58, "Accessibility, density, presentation, and shell controls.", COL_MUTED)

        do i = 1, SETTINGS_COUNT
            row_y = py + 74 + (i - 1) * row_h
            if (i == settings_focus) then
                call fill_soft_box(hdc, px + 14, row_y, px + pw - 14, row_y + row_h - 6, COL_PANEL_ALT)
                call stroke_soft_box(hdc, px + 14, row_y, px + pw - 14, row_y + row_h - 6, COL_CYAN, 1)
            else
                call fill_soft_box(hdc, px + 14, row_y, px + pw - 14, row_y + row_h - 6, COL_PANEL)
                call stroke_soft_box(hdc, px + 14, row_y, px + pw - 14, row_y + row_h - 6, COL_BORDER_SOFT, 1)
            end if
            label = settings_action_label(i)
            call draw_text(hdc, px + 30, row_y + 9, trim(label), merge(COL_CYAN, COL_INK, i == settings_focus))
        end do
    end subroutine draw_settings_overlay

    subroutine draw_demo_caption(hdc, x0, y0, w, h)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x0, y0, w, h
        integer :: bx, by, bw
        character(len=120) :: txt
        bw = min(700, max(420, w / 2))
        bx = x0 + w - bw - 16
        by = y0 + h - 70
        write(txt, '("AUTO TOUR  |  ",A,"  |  Ctrl-M stops")') trim(SCREEN_FULL_LABEL(hmi_screen))
        call hmi_fill_alpha_round_rect(hdc, int(bx, c_int), int(by, c_int), int(bx + bw, c_int), &
            int(by + 48, c_int), RADIUS_MD, COL_PANEL_DEEP, 210_c_int)
        call stroke_soft_box(hdc, bx, by, bx + bw, by + 48, COL_CYAN, 1)
        call fill_box(hdc, bx, by, bx + 5, by + 48, COL_CYAN)
        call draw_text(hdc, bx + 18, by + 15, trim(txt), COL_INK)
    end subroutine draw_demo_caption

    subroutine draw_coach_overlay(hdc, x0, y0, w, h)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x0, y0, w, h
        integer :: bx, by, bw, bh, ax, ay
        character(len=120) :: title, body

        select case (coach_step)
        case (1)
            title = "1/4 Navigation shell"
            body = "Use the left rail for L1/L2/L3 screen groups; Ctrl-K opens command search."
            bx = layout_nav_left + layout_nav_w + 18; by = layout_nav_top + 86
            ax = layout_nav_left + layout_nav_w - 4; ay = layout_nav_top + 140
        case (2)
            title = "2/4 Operator controls"
            body = "Tab focuses controls. Left/Right trims sliders. Enter runs focused buttons."
            bx = layout_control_left + layout_control_w + 18; by = layout_control_top + 250
            ax = layout_control_left + layout_control_w - 4; ay = layout_button_y + 18
        case (3)
            title = "3/4 Live inspection"
            body = "Move the mouse over trend charts for crosshair and tooltip readouts."
            bx = x0 + max(120, w / 4); by = y0 + h - 230
            ax = x0 + w / 2; ay = y0 + h - 170
        case default
            title = "4/4 Presentation mode"
            body = "Ctrl-M cycles screens, Ctrl-P exports a PNG, and Settings controls density/themes."
            bx = x0 + w / 2 - 260; by = y0 + 96
            ax = x0 + w - 100; ay = y0 + 22
        end select
        bw = min(560, max(420, w / 3))
        bh = 120
        call hmi_fill_alpha_rect(hdc, int(x0, c_int), int(y0, c_int), int(x0 + w, c_int), int(y0 + h, c_int), COL_BG, 120_c_int)
        call draw_line(hdc, ax, ay, bx, by + bh / 2, COL_CYAN, 2)
        call fill_soft_box(hdc, bx, by, bx + bw, by + bh, COL_PANEL_DEEP)
        call stroke_soft_box(hdc, bx, by, bx + bw, by + bh, COL_CYAN, 1)
        call fill_box(hdc, bx, by, bx + 5, by + bh, COL_CYAN)
        call draw_title_text(hdc, bx + 18, by + 14, trim(title), COL_INK)
        call draw_text(hdc, bx + 18, by + 54, trim(body), COL_MUTED)
        call draw_text(hdc, bx + 18, by + 88, "Click, Enter, or Right arrow for next. Esc closes.", COL_CYAN)
    end subroutine draw_coach_overlay

    ! =========================================================================
    ! LCF hot-parts life consumed bars (F8 right panel)
    ! =========================================================================
    subroutine draw_lcf_bars(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: row_y, bx, bw, fill_w, bar_h
        integer(c_int) :: col
        character(len=40) :: lbl

        bar_h = 18
        bx = x + 6;  bw = width - 12

        call fill_soft_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
        call stroke_soft_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)

        row_y = y + 8

        ! Compressor (cold starts vs 500 design)
        col = merge(COL_RED, merge(COL_AMBER, COL_GREEN, grid%lcf_comp_life_pct > 50.0_dp), &
                    grid%lcf_comp_life_pct > 80.0_dp)
        fill_w = max(2, nint(grid%lcf_comp_life_pct / 100.0_dp * real(bw - 110, dp)))
        call fill_soft_box(hdc, bx + 104, row_y, bx + 104 + (bw - 110), row_y + bar_h, COL_PANEL_DEEP)
        call fill_soft_box(hdc, bx + 104, row_y, bx + 104 + fill_w,      row_y + bar_h, col)
        call stroke_soft_box(hdc, bx + 104, row_y, bx + 104 + (bw - 110), row_y + bar_h, COL_BORDER_SOFT, 1)
        write(lbl, '("Compressor  ",F5.1,"%  (",I0," starts)")') &
            grid%lcf_comp_life_pct, grid%lcf_starts
        call draw_text(hdc, bx, row_y + 2, trim(adjustl(lbl)), col)
        row_y = row_y + bar_h + 8

        ! Hot section turbine (hot hours vs 24000h)
        col = merge(COL_RED, merge(COL_AMBER, COL_GREEN, grid%lcf_hst_life_pct > 50.0_dp), &
                    grid%lcf_hst_life_pct > 80.0_dp)
        fill_w = max(2, nint(grid%lcf_hst_life_pct / 100.0_dp * real(bw - 110, dp)))
        call fill_soft_box(hdc, bx + 104, row_y, bx + 104 + (bw - 110), row_y + bar_h, COL_PANEL_DEEP)
        call fill_soft_box(hdc, bx + 104, row_y, bx + 104 + fill_w,      row_y + bar_h, col)
        call stroke_soft_box(hdc, bx + 104, row_y, bx + 104 + (bw - 110), row_y + bar_h, COL_BORDER_SOFT, 1)
        write(lbl, '("Hot section ",F5.1,"%  (",I0,"h)")') &
            grid%lcf_hst_life_pct, nint(grid%lcf_hot_hours)
        call draw_text(hdc, bx, row_y + 2, trim(adjustl(lbl)), col)
        row_y = row_y + bar_h + 8

        ! HRSG (hot hours vs 100000h)
        col = merge(COL_RED, merge(COL_AMBER, COL_GREEN, grid%lcf_hrsg_life_pct > 50.0_dp), &
                    grid%lcf_hrsg_life_pct > 80.0_dp)
        fill_w = max(2, nint(grid%lcf_hrsg_life_pct / 100.0_dp * real(bw - 110, dp)))
        call fill_soft_box(hdc, bx + 104, row_y, bx + 104 + (bw - 110), row_y + bar_h, COL_PANEL_DEEP)
        call fill_soft_box(hdc, bx + 104, row_y, bx + 104 + fill_w,      row_y + bar_h, col)
        call stroke_soft_box(hdc, bx + 104, row_y, bx + 104 + (bw - 110), row_y + bar_h, COL_BORDER_SOFT, 1)
        write(lbl, '("HRSG        ",F5.1,"%  (",I0,"h)")') &
            grid%lcf_hrsg_life_pct, nint(grid%lcf_hot_hours)
        call draw_text(hdc, bx, row_y + 2, trim(adjustl(lbl)), col)

    end subroutine draw_lcf_bars

    ! =========================================================================
    ! Pareto front scatter (cost vs CO2) — F9 right panel lower half
    ! =========================================================================
    subroutine draw_pareto_panel(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: i, gx, gy, gw, gh, lm, rm, tm, bm
        integer :: px, py
        real(dp) :: cost_lo, cost_hi, co2_lo, co2_hi, cost_rng, co2_rng
        character(len=14) :: lbl_ax

        lm = 56;  rm = 12;  tm = 10;  bm = 28
        gx = x + lm;  gy = y + tm;  gw = width - lm - rm;  gh = height - tm - bm

        call fill_soft_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
        call stroke_soft_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)

        if (gw < 30 .or. gh < 30) return

        if (grid%pareto_n_pts < 2) then
            call draw_text(hdc, gx + 8, gy + gh/2 - 8, "Pareto not available yet.", COL_DIM)
            return
        end if

        ! Axis ranges
        cost_lo = minval(grid%pareto_cost(1:grid%pareto_n_pts))
        cost_hi = maxval(grid%pareto_cost(1:grid%pareto_n_pts))
        co2_lo  = minval(grid%pareto_co2(1:grid%pareto_n_pts))
        co2_hi  = maxval(grid%pareto_co2(1:grid%pareto_n_pts))
        cost_rng = max(cost_hi - cost_lo, 1.0_dp)
        co2_rng  = max(co2_hi  - co2_lo,  1.0_dp)

        ! Axis labels
        call draw_text(hdc, x + 2, gy,                "CO2", COL_DIM)
        call draw_text(hdc, x + 2, gy + 10,           "t/h", COL_DIM)
        call draw_text(hdc, gx,              y + height - bm + 8, "$cost", COL_DIM)
        write(lbl_ax, '(I0)') nint(cost_lo)
        call draw_text(hdc, gx,              y + height - bm + 8, trim(adjustl(lbl_ax)), COL_DIM)
        write(lbl_ax, '(I0)') nint(cost_hi)
        call draw_text(hdc, gx + gw - 40,   y + height - bm + 8, trim(adjustl(lbl_ax)), COL_DIM)

        ! Grid lines
        call draw_line(hdc, gx, gy,      gx + gw, gy,      COL_BG_GRID, 1)
        call draw_line(hdc, gx, gy + gh/2, gx + gw, gy + gh/2, COL_BG_GRID, 1)
        call draw_line(hdc, gx, gy + gh, gx + gw, gy + gh, COL_BG_GRID, 1)

        ! Pareto points (gradient from cyan = low cost to green = low CO2)
        do i = 1, grid%pareto_n_pts
            px = gx + nint((grid%pareto_cost(i) - cost_lo) / cost_rng * real(gw, dp))
            py = gy + gh - nint((grid%pareto_co2(i)  - co2_lo)  / co2_rng  * real(gh, dp))
            px = min(gx + gw - 3, max(gx + 3, px))
            py = min(gy + gh - 3, max(gy + 3, py))
            call fill_box(hdc, px - 4, py - 4, px + 4, py + 4, &
                merge(COL_GREEN, COL_CYAN, i <= grid%pareto_n_pts / 2))
        end do

        ! Connect with thin line showing frontier shape
        do i = 2, grid%pareto_n_pts
            call draw_line(hdc, &
                gx + nint((grid%pareto_cost(i-1) - cost_lo)/cost_rng*real(gw,dp)), &
                gy + gh - nint((grid%pareto_co2(i-1)  - co2_lo)/co2_rng*real(gh,dp)),  &
                gx + nint((grid%pareto_cost(i)   - cost_lo)/cost_rng*real(gw,dp)), &
                gy + gh - nint((grid%pareto_co2(i)    - co2_lo)/co2_rng*real(gh,dp)),  &
                COL_BORDER_SOFT, 1)
        end do

        ! Availability colour legend note
        call draw_text(hdc, gx + 2, gy + 2, "cyan=low$ / green=low CO2", COL_DIM)

    end subroutine draw_pareto_panel

    ! =========================================================================
    ! F15  Scenario Builder — toggle switches + parameter sliders
    ! =========================================================================
    subroutine draw_scenario_screen(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height

        integer :: ix, iw, top_y, row_y, col2_x, col2_w, col1_w
        integer :: bx, bw, bar_h, fill_w
        integer(c_int) :: col
        character(len=96) :: line

        ix = x + 18;  iw = width - 36;  top_y = y + 8
        call draw_screen_caption(hdc, ix, top_y, iw, &
            "F15  SCENARIO COMPARISON", &
            "A/B playback overlay with deterministic scenario traces")

        col1_w = iw * 42 / 100
        col2_x = ix + col1_w + 20
        col2_w = iw - col1_w - 20
        row_y  = top_y + 76

        ! ── Left column: Physics module toggles ─────────────────────────────
        call draw_section_title_width(hdc, ix, row_y, "Physics module toggles", col1_w)
        row_y = row_y + 28

        bar_h = 26

        ! P2X Electrolyser
        col = merge(COL_GREEN, COL_DIM, grid%p2x_active)
        call fill_soft_box(hdc, ix, row_y, ix + 60, row_y + bar_h, &
            merge(int(Z'00003020', c_int), COL_PANEL_DEEP, grid%p2x_active))
        call draw_text(hdc, ix + 6, row_y + 5, merge("ON ", "OFF", grid%p2x_active), col)
        write(line, '("P2X Electrolyser    ",F5.1," MW  H2: ",F6.4," kg/s")') &
            grid%p2x_load_MW, grid%p2x_h2_kg_s
        call draw_text(hdc, ix + 68, row_y + 5, trim(adjustl(line)), col)
        row_y = row_y + bar_h + 6

        ! CCS / MEA
        col = merge(COL_GREEN, COL_DIM, grid%ccs_active)
        call fill_soft_box(hdc, ix, row_y, ix + 60, row_y + bar_h, &
            merge(int(Z'00003020', c_int), COL_PANEL_DEEP, grid%ccs_active))
        call draw_text(hdc, ix + 6, row_y + 5, merge("ON ", "OFF", grid%ccs_active), col)
        write(line, '("CCS / MEA           ",F5.1," MW parasitic  CO2: ",F5.2," t/h")') &
            grid%ccs_parasitic_MW, grid%ccs_co2_captured_t_h
        call draw_text(hdc, ix + 68, row_y + 5, trim(adjustl(line)), col)
        row_y = row_y + bar_h + 6

        ! GFM BESS
        col = merge(COL_LIME, COL_DIM, grid%gfm_mode)
        call fill_soft_box(hdc, ix, row_y, ix + 60, row_y + bar_h, &
            merge(int(Z'00001A2A', c_int), COL_PANEL_DEEP, grid%gfm_mode))
        call draw_text(hdc, ix + 6, row_y + 5, merge("ON ", "OFF", grid%gfm_mode), col)
        write(line, '("GFM BESS            H_virt=",F4.1,"s  droop=",F4.1,"%  synth ",SP,F5.1," MW")') &
            grid%gfm_virtual_H, grid%gfm_droop_pct, grid%gfm_synth_MW
        call draw_text(hdc, ix + 68, row_y + 5, trim(adjustl(line)), col)
        row_y = row_y + bar_h + 6

        ! Tie-line
        col = merge(COL_BLUE, COL_DIM, grid%tie_active)
        call fill_soft_box(hdc, ix, row_y, ix + 60, row_y + bar_h, &
            merge(int(Z'00001020', c_int), COL_PANEL_DEEP, grid%tie_active))
        call draw_text(hdc, ix + 6, row_y + 5, merge("ON ", "OFF", grid%tie_active), col)
        write(line, '("Tie-line / ACE      flow ",SP,F5.1," MW  ACE ",SP,F5.1," MW")') &
            grid%tie_flow_MW, grid%ace_MW
        call draw_text(hdc, ix + 68, row_y + 5, trim(adjustl(line)), col)
        row_y = row_y + bar_h + 6

        ! MPC-AGC
        col = merge(COL_CYAN, COL_DIM, grid%mpc_active)
        call fill_soft_box(hdc, ix, row_y, ix + 60, row_y + bar_h, &
            merge(int(Z'00001828', c_int), COL_PANEL_DEEP, grid%mpc_active))
        call draw_text(hdc, ix + 6, row_y + 5, merge("ON ", "OFF", grid%mpc_active), col)
        write(line, '("MPC-AGC             setpt ",F5.1," MW  cost ",F7.1," $/h")') &
            grid%mpc_setpt_MW, grid%mpc_cost_last
        call draw_text(hdc, ix + 68, row_y + 5, trim(adjustl(line)), col)
        row_y = row_y + bar_h + 6

        ! OU noise
        col = merge(COL_AMBER, COL_DIM, grid%ou_active)
        call fill_soft_box(hdc, ix, row_y, ix + 60, row_y + bar_h, &
            merge(int(Z'00201800', c_int), COL_PANEL_DEEP, grid%ou_active))
        call draw_text(hdc, ix + 6, row_y + 5, merge("ON ", "OFF", grid%ou_active), col)
        write(line, '("OU Noise            dem ",SP,F5.2," MW  wind ",SP,F5.2," MW")') &
            grid%ou_demand_noise, grid%ou_wind_noise
        call draw_text(hdc, ix + 68, row_y + 5, trim(adjustl(line)), col)
        row_y = row_y + bar_h + 14

        ! Module state separator
        call draw_line(hdc, ix, row_y, ix + col1_w, row_y, COL_BORDER_SOFT, 1)
        row_y = row_y + 10
        call draw_text(hdc, ix, row_y, "Live module state from engine_core", COL_DIM)
        row_y = row_y + 16

        ! ── Left column lower: parameter sliders (read-only display) ────────
        bw = col1_w - 12
        call draw_section_title_width(hdc, ix, row_y, "Operating parameters", col1_w)
        row_y = row_y + 28

        ! Gas dispatch %
        write(line, '("GT dispatch   ",F5.1,"%")') grid%gas_dispatch_pct
        call draw_text(hdc, ix, row_y + 4, trim(adjustl(line)), COL_CYAN)
        fill_w = max(2, nint(max(0.0_dp, min(100.0_dp, grid%gas_dispatch_pct)) / 100.0_dp * real(bw - 140, dp)))
        call fill_soft_box(hdc, ix + 134, row_y, ix + 134 + (bw - 140), row_y + bar_h, COL_PANEL_DEEP)
        call fill_soft_box(hdc, ix + 134, row_y, ix + 134 + fill_w,      row_y + bar_h, COL_CYAN)
        call stroke_soft_box(hdc, ix + 134, row_y, ix + 134 + (bw - 140), row_y + bar_h, COL_BORDER_SOFT, 1)
        row_y = row_y + bar_h + 8

        ! Demand MW
        write(line, '("Demand        ",F6.1," MW")') grid%demand_MW
        call draw_text(hdc, ix, row_y + 4, trim(adjustl(line)), COL_INK)
        fill_w = max(2, nint(min(1.0_dp, grid%demand_MW / max(grid%gas_capacity_MW * 1.2_dp, 1.0_dp)) &
                             * real(bw - 140, dp)))
        call fill_soft_box(hdc, ix + 134, row_y, ix + 134 + (bw - 140), row_y + bar_h, COL_PANEL_DEEP)
        call fill_soft_box(hdc, ix + 134, row_y, ix + 134 + fill_w,      row_y + bar_h, COL_BORDER)
        call stroke_soft_box(hdc, ix + 134, row_y, ix + 134 + (bw - 140), row_y + bar_h, COL_BORDER_SOFT, 1)
        row_y = row_y + bar_h + 8

        ! Renewable MW
        write(line, '("Renewable     ",F6.1," MW")') grid%renewable_MW
        call draw_text(hdc, ix, row_y + 4, trim(adjustl(line)), COL_GREEN)
        fill_w = max(2, nint(min(1.0_dp, grid%renewable_MW / max(grid%gas_capacity_MW, 1.0_dp)) &
                             * real(bw - 140, dp)))
        call fill_soft_box(hdc, ix + 134, row_y, ix + 134 + (bw - 140), row_y + bar_h, COL_PANEL_DEEP)
        call fill_soft_box(hdc, ix + 134, row_y, ix + 134 + fill_w,      row_y + bar_h, COL_GREEN)
        call stroke_soft_box(hdc, ix + 134, row_y, ix + 134 + (bw - 140), row_y + bar_h, COL_BORDER_SOFT, 1)
        row_y = row_y + bar_h + 8

        ! P2X capacity
        write(line, '("P2X capacity  ",F5.1," MW")') grid%p2x_capacity_MW
        col = merge(COL_GREEN, COL_DIM, grid%p2x_active)
        call draw_text(hdc, ix, row_y + 4, trim(adjustl(line)), col)
        fill_w = max(2, nint(grid%p2x_capacity_MW / 100.0_dp * real(bw - 140, dp)))
        call fill_soft_box(hdc, ix + 134, row_y, ix + 134 + (bw - 140), row_y + bar_h, COL_PANEL_DEEP)
        call fill_soft_box(hdc, ix + 134, row_y, ix + 134 + fill_w,      row_y + bar_h, col)
        call stroke_soft_box(hdc, ix + 134, row_y, ix + 134 + (bw - 140), row_y + bar_h, COL_BORDER_SOFT, 1)
        row_y = row_y + bar_h + 8

        ! OU sigma demand
        write(line, '("OU sig-demand ",F5.2," MW")') grid%ou_sigma_demand
        col = merge(COL_AMBER, COL_DIM, grid%ou_active)
        call draw_text(hdc, ix, row_y + 4, trim(adjustl(line)), col)
        fill_w = max(2, nint(grid%ou_sigma_demand / 10.0_dp * real(bw - 140, dp)))
        call fill_soft_box(hdc, ix + 134, row_y, ix + 134 + (bw - 140), row_y + bar_h, COL_PANEL_DEEP)
        call fill_soft_box(hdc, ix + 134, row_y, ix + 134 + fill_w,      row_y + bar_h, col)
        call stroke_soft_box(hdc, ix + 134, row_y, ix + 134 + (bw - 140), row_y + bar_h, COL_BORDER_SOFT, 1)

        ! Right column: deterministic scenario comparison
        row_y = top_y + 76
        call draw_section_title_width(hdc, col2_x, row_y, "Scenario A/B comparison", col2_w)
        row_y = row_y + 28
        call draw_scenario_compare_header(hdc, col2_x, row_y, col2_w)
        row_y = row_y + 78
        call draw_scenario_compare_kpis(hdc, col2_x, row_y, col2_w)
        row_y = row_y + 82
        call draw_scenario_compare_panel(hdc, col2_x, row_y, col2_w, &
            max(120, y + height - 44 - row_y))

        ! Footer
        call draw_line(hdc, ix, y + height - 36, ix + iw, y + height - 36, COL_BORDER_SOFT, 1)
        call draw_text(hdc, ix, y + height - 22, &
            "F15 D2: A/B scenario traces use the same solver path as playback and tests.", COL_DIM)

    end subroutine draw_scenario_screen

    subroutine draw_scenario_compare_header(hdc, x, y, width)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width
        integer :: btn_w, btn_h, gap, btn_x
        integer(c_int) :: status_col
        character(len=96) :: line

        btn_w = 104
        btn_h = 36
        gap = KPI_TILE_GAP
        btn_x = x + width - (3 * btn_w + 2 * gap)

        call fill_soft_box(hdc, x, y, x + width, y + 66, COL_PANEL_ALT)
        call stroke_soft_box(hdc, x, y, x + width, y + 66, COL_BORDER_SOFT, 1)
        call fill_box(hdc, x, y, x + 4, y + 66, COL_CYAN)

        write(line, '("A  ",I0,"/",I0,"  ",A)') scn_selected, N_SCENARIOS, &
            trim(SCN_LABEL(scn_selected))
        call draw_text(hdc, x + 12, y + 8, trim(adjustl(line)), COL_AMBER)
        write(line, '("B  ",I0,"/",I0,"  ",A)') scn_compare_selected, N_SCENARIOS, &
            trim(SCN_LABEL(scn_compare_selected))
        call draw_text(hdc, x + 12, y + 32, trim(adjustl(line)), COL_CYAN)

        if (scn_cmp%ready) then
            status_col = merge(COL_GREEN, COL_AMBER, &
                scn_cmp%a%assertion_failures + scn_cmp%b%assertion_failures == 0)
            write(line, '("samples ",I0,"/",I0,"  assertions A/B ",I0,"/",I0)') &
                scn_cmp%a%n, scn_cmp%b%n, scn_cmp%a%assertion_failures, &
                scn_cmp%b%assertion_failures
            call draw_text(hdc, x + 12, y + 52, trim(adjustl(line)), status_col)
        else
            call draw_text(hdc, x + 12, y + 52, trim(scn_compare_status), COL_MUTED)
        end if

        call draw_industrial_button(hdc, btn_x, y + 14, btn_x + btn_w, y + 50, &
            "B PREV", COL_PANEL, .false.)
        call draw_industrial_button(hdc, btn_x + btn_w + gap, y + 14, &
            btn_x + 2 * btn_w + gap, y + 50, "B NEXT", COL_PANEL, .false.)
        call draw_industrial_button(hdc, btn_x + 2 * (btn_w + gap), y + 14, &
            btn_x + 3 * btn_w + 2 * gap, y + 50, "COMPARE", COL_CYAN, scn_cmp%ready)
    end subroutine draw_scenario_compare_header

    subroutine draw_scenario_compare_kpis(hdc, x, y, width)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width
        integer :: gap, card_w
        integer(c_int) :: c_nadir, c_imb, c_margin, c_co2
        character(len=24) :: nadir_s, imb_s, margin_s, co2_s

        gap = KPI_TILE_GAP
        card_w = (width - 3 * gap) / 4
        if (scn_cmp%ready) then
            write(nadir_s, '(SP,F7.3," Hz")') scn_cmp%delta_min_frequency_Hz
            write(imb_s, '(SP,F7.2," MW")') scn_cmp%delta_max_abs_imbalance_MW
            write(margin_s, '(SP,"$",F8.0,"/h")') scn_cmp%delta_final_margin_usd_h
            write(co2_s, '(SP,F7.1," g/kWh")') scn_cmp%delta_final_CO2_intensity_g_kWh
            c_nadir = merge(COL_GREEN, COL_RED, scn_cmp%delta_min_frequency_Hz >= -0.001_dp)
            c_imb = merge(COL_GREEN, COL_RED, scn_cmp%delta_max_abs_imbalance_MW <= 0.001_dp)
            c_margin = merge(COL_GREEN, COL_RED, scn_cmp%delta_final_margin_usd_h >= -1.0_dp)
            c_co2 = merge(COL_GREEN, COL_RED, scn_cmp%delta_final_CO2_intensity_g_kWh <= 0.1_dp)
        else
            nadir_s = "--"
            imb_s = "--"
            margin_s = "--"
            co2_s = "--"
            c_nadir = COL_MUTED
            c_imb = COL_MUTED
            c_margin = COL_MUTED
            c_co2 = COL_MUTED
        end if

        call draw_metric_tile(hdc, x, y, card_w, 62, "B-A frequency nadir", &
            trim(adjustl(nadir_s)), c_nadir)
        call draw_metric_tile(hdc, x + card_w + gap, y, card_w, 62, "B-A max imbalance", &
            trim(adjustl(imb_s)), c_imb)
        call draw_metric_tile(hdc, x + 2 * (card_w + gap), y, card_w, 62, "B-A net margin", &
            trim(adjustl(margin_s)), c_margin)
        call draw_metric_tile(hdc, x + 3 * (card_w + gap), y, &
            width - 3 * (card_w + gap), 62, "B-A CO2 intensity", trim(adjustl(co2_s)), c_co2)
    end subroutine draw_scenario_compare_kpis

    subroutine draw_scenario_compare_panel(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: plot_y, plot_h, plot_gap, bottom_h, available_h

        if (height < 96) return
        call draw_panel_box_deep(hdc, x, y, width, height)
        call draw_text(hdc, x + 12, y + 10, "Overlay trends", COL_MUTED)
        call draw_text(hdc, x + 148, y + 10, "A", COL_AMBER)
        call draw_text(hdc, x + 166, y + 10, "baseline", COL_MUTED)
        call draw_text(hdc, x + 244, y + 10, "B", COL_CYAN)
        call draw_text(hdc, x + 262, y + 10, "candidate", COL_MUTED)

        if (.not. scn_cmp%ready) then
            call draw_text(hdc, x + 24, y + height / 2 - 8, &
                "Run COMPARE to generate deterministic A/B traces.", COL_DIM)
            return
        end if

        plot_gap = 26
        plot_y = y + 34
        available_h = height - 52 - plot_gap
        if (available_h < 96) then
            call draw_text(hdc, x + 24, y + height / 2 - 8, &
                "Scenario plots need more vertical space.", COL_DIM)
            return
        end if
        plot_h = available_h / 2
        bottom_h = available_h - plot_h
        call draw_scenario_frequency_plot(hdc, x + 10, plot_y, width - 20, plot_h)
        call draw_scenario_imbalance_plot(hdc, x + 10, plot_y + plot_h + plot_gap, &
            width - 20, bottom_h)
    end subroutine draw_scenario_compare_panel

    subroutine draw_scenario_frequency_plot(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: gx, gy, gw, gh
        real(dp) :: nom, f_lo, f_hi
        character(len=32) :: label

        if (height < 48) return
        gx = x + 54
        gy = y + 26
        gw = width - 66
        gh = height - 38
        if (gw < 20 .or. gh < 20) return

        nom = 0.5_dp * (scn_cmp%a%nominal_frequency_Hz + scn_cmp%b%nominal_frequency_Hz)
        f_lo = min(min(scn_cmp%a%min_frequency_Hz, scn_cmp%b%min_frequency_Hz), nom - 0.35_dp) - 0.05_dp
        f_hi = max(max(scn_cmp%a%max_frequency_Hz, scn_cmp%b%max_frequency_Hz), nom + 0.35_dp) + 0.05_dp
        call draw_scenario_plot_frame(hdc, x, y, width, height, "Frequency response", f_lo, f_hi)
        call draw_scenario_hline(hdc, gx, gy, gw, gh, f_lo, f_hi, nom, COL_GREEN, .false.)
        call draw_scenario_hline(hdc, gx, gy, gw, gh, f_lo, f_hi, nom - 0.2_dp, COL_CYAN, .true.)
        call draw_scenario_hline(hdc, gx, gy, gw, gh, f_lo, f_hi, nom + 0.2_dp, COL_CYAN, .true.)
        call draw_scenario_trace_array(hdc, gx, gy, gw, gh, scn_cmp%a%time_s, &
            scn_cmp%a%frequency_Hz, scn_cmp%a%n, scn_cmp%a%duration_s, f_lo, f_hi, COL_AMBER, 2)
        call draw_scenario_trace_array(hdc, gx, gy, gw, gh, scn_cmp%b%time_s, &
            scn_cmp%b%frequency_Hz, scn_cmp%b%n, scn_cmp%b%duration_s, f_lo, f_hi, COL_CYAN, 2)
        write(label, '("A min ",F7.3)') scn_cmp%a%min_frequency_Hz
        call draw_text(hdc, gx + 8, y + 8, trim(adjustl(label)), COL_AMBER)
        write(label, '("B min ",F7.3)') scn_cmp%b%min_frequency_Hz
        call draw_text(hdc, gx + 122, y + 8, trim(adjustl(label)), COL_CYAN)
    end subroutine draw_scenario_frequency_plot

    subroutine draw_scenario_imbalance_plot(hdc, x, y, width, height)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        integer :: gx, gy, gw, gh
        real(dp) :: lim, v_lo, v_hi
        character(len=32) :: label

        if (height < 48) return
        gx = x + 54
        gy = y + 26
        gw = width - 66
        gh = height - 38
        if (gw < 20 .or. gh < 20) return

        lim = max(max(scn_cmp%a%max_abs_imbalance_MW, scn_cmp%b%max_abs_imbalance_MW), 1.0_dp)
        v_lo = -1.15_dp * lim
        v_hi =  1.15_dp * lim
        call draw_scenario_plot_frame(hdc, x, y, width, height, "Supply-demand imbalance", v_lo, v_hi)
        call draw_scenario_hline(hdc, gx, gy, gw, gh, v_lo, v_hi, 0.0_dp, COL_GREEN, .false.)
        call draw_scenario_trace_array(hdc, gx, gy, gw, gh, scn_cmp%a%time_s, &
            scn_cmp%a%imbalance_MW, scn_cmp%a%n, scn_cmp%a%duration_s, v_lo, v_hi, COL_AMBER, 2)
        call draw_scenario_trace_array(hdc, gx, gy, gw, gh, scn_cmp%b%time_s, &
            scn_cmp%b%imbalance_MW, scn_cmp%b%n, scn_cmp%b%duration_s, v_lo, v_hi, COL_CYAN, 2)
        write(label, '("A max |imb| ",F6.2)') scn_cmp%a%max_abs_imbalance_MW
        call draw_text(hdc, gx + 8, y + 8, trim(adjustl(label)), COL_AMBER)
        write(label, '("B max |imb| ",F6.2)') scn_cmp%b%max_abs_imbalance_MW
        call draw_text(hdc, gx + 146, y + 8, trim(adjustl(label)), COL_CYAN)
    end subroutine draw_scenario_imbalance_plot

    subroutine draw_scenario_plot_frame(hdc, x, y, width, height, title, lo, hi)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        character(len=*), intent(in) :: title
        real(dp), intent(in) :: lo, hi
        integer :: gx, gy, gw, gh, i
        real(dp) :: mid
        character(len=64) :: label, hover1, hover2
        real(dp) :: hover_t, hover_v

        gx = x + 54
        gy = y + 26
        gw = width - 66
        gh = height - 38
        call fill_soft_box(hdc, x, y, x + width, y + height, COL_PANEL_ALT)
        call stroke_soft_box(hdc, x, y, x + width, y + height, COL_BORDER_SOFT, 1)
        call draw_text(hdc, x + 8, y + 8, title, COL_MUTED)
        call fill_box(hdc, gx, gy, gx + gw, gy + gh, COL_BG)
        do i = 1, 3
            call draw_line(hdc, gx, gy + i * gh / 4, gx + gw, gy + i * gh / 4, COL_BG_GRID, 1)
            call draw_line(hdc, gx + i * gw / 4, gy, gx + i * gw / 4, gy + gh, COL_BG_GRID, 1)
        end do
        call stroke_box(hdc, gx, gy, gx + gw, gy + gh, COL_BORDER_SOFT, 1)
        mid = 0.5_dp * (lo + hi)
        write(label, '(F7.2)') hi
        call draw_text(hdc, x + 6, gy - 7, trim(adjustl(label)), COL_DIM)
        write(label, '(F7.2)') mid
        call draw_text(hdc, x + 6, gy + gh / 2 - 7, trim(adjustl(label)), COL_DIM)
        write(label, '(F7.2)') lo
        call draw_text(hdc, x + 6, gy + gh - 7, trim(adjustl(label)), COL_DIM)
        call draw_text(hdc, gx, gy + gh + 3, "0s", COL_DIM)
        call draw_text(hdc, gx + gw - 36, gy + gh + 3, "end", COL_DIM)
        if (mouse_hover_valid .and. point_in_rect(mouse_hover_x, mouse_hover_y, gx, gy, gx + gw, gy + gh)) then
            hover_t = real(mouse_hover_x - gx, dp) / real(max(gw, 1), dp)
            hover_v = hi - (hi - lo) * real(mouse_hover_y - gy, dp) / real(max(gh, 1), dp)
            write(hover1, '("Scenario t ",I0,"%")') nint(hover_t * 100.0_dp)
            write(hover2, '("Y ",F8.3)') hover_v
            call draw_chart_crosshair(hdc, gx, gy, gw, gh, trim(hover1), trim(hover2))
        end if
    end subroutine draw_scenario_plot_frame

    subroutine draw_scenario_hline(hdc, x, y, width, height, lo, hi, value, color, dashed)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height
        real(dp), intent(in) :: lo, hi, value
        integer(c_int), intent(in) :: color
        logical, intent(in) :: dashed
        integer :: py, px
        real(dp) :: norm

        if (value < lo .or. value > hi) return
        norm = clamp_real((value - lo) / max(hi - lo, 1.0e-9_dp), 0.0_dp, 1.0_dp)
        py = y + height - int(real(height, dp) * norm)
        if (dashed) then
            do px = x + 2, x + width - 4, 12
                call draw_line(hdc, px, py, min(px + 7, x + width - 2), py, color, 1)
            end do
        else
            call draw_line(hdc, x, py, x + width, py, color, 1)
        end if
    end subroutine draw_scenario_hline

    subroutine draw_scenario_trace_array(hdc, x, y, width, height, t, v, n, duration, lo, hi, color, pen_w)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x, y, width, height, n, pen_w
        real(dp), intent(in) :: t(:), v(:), duration, lo, hi
        integer(c_int), intent(in) :: color
        integer :: i
        real(dp) :: tx, norm, dur
        integer(c_int), allocatable, target :: px(:), py(:)

        if (n < 2) return
        dur = max(duration, 1.0e-9_dp)
        allocate(px(n), py(n))
        do i = 1, n
            tx    = clamp_real(t(i) / dur, 0.0_dp, 1.0_dp)
            norm  = clamp_real((v(i) - lo) / max(hi - lo, 1.0e-9_dp), 0.0_dp, 1.0_dp)
            px(i) = int(x + int(real(width, dp) * tx), c_int)
            py(i) = int(y + height - int(real(height, dp) * norm), c_int)
        end do
        ! [perf] one batched DrawLines per scenario trace
        if (native_renderer_ready) then
            call hmi_draw_polyline(hdc, c_loc(px), c_loc(py), int(n, c_int), color, int(pen_w, c_int))
        else
            do i = 2, n
                call draw_line(hdc, int(px(i-1)), int(py(i-1)), int(px(i)), int(py(i)), color, pen_w)
            end do
        end if
        deallocate(px, py)
    end subroutine draw_scenario_trace_array

    ! Formatting helpers used by draw_scenario_screen
    function format_hz(v) result(s)
        real(dp), intent(in) :: v
        character(len=14) :: s
        write(s, '(F8.3," Hz")') v
        s = adjustl(s)
    end function format_hz

    function format_rocof(v) result(s)
        real(dp), intent(in) :: v
        character(len=14) :: s
        write(s, '(SP,F7.4," Hz/s")') v
        s = adjustl(s)
    end function format_rocof

    function format_mw(v) result(s)
        real(dp), intent(in) :: v
        character(len=14) :: s
        write(s, '(SP,F7.2," MW")') v
        s = adjustl(s)
    end function format_mw

    function format_kgs(v) result(s)
        real(dp), intent(in) :: v
        character(len=14) :: s
        write(s, '(F7.4," kg/s")') v
        s = adjustl(s)
    end function format_kgs

    function format_ccs(v) result(s)
        real(dp), intent(in) :: v
        character(len=14) :: s
        write(s, '(F6.2," t/h")') v
        s = adjustl(s)
    end function format_ccs

    function format_int(n) result(s)
        integer, intent(in) :: n
        character(len=14) :: s
        write(s, '(I0)') n
        s = adjustl(s)
    end function format_int

    function format_pct(v) result(s)
        real(dp), intent(in) :: v
        character(len=14) :: s
        write(s, '(F6.2,"%")') v
        s = adjustl(s)
    end function format_pct

    ! =========================================================================
    ! Shortcuts popup card — anchored top-right under the [? Keys] button
    ! =========================================================================
    subroutine draw_shortcuts_popup(hdc, x0, y0, w)
        type(c_ptr), value :: hdc
        integer, intent(in) :: x0, y0, w

        integer, parameter :: PW = 392
        integer, parameter :: PH = 632
        integer :: px, py, row, col_a, col_b, lh
        character(len=20) :: sv

        px = x0 + w - PW - 6
        py = y0 + 46
        lh = 18

        ! Shadow
        call fill_box(hdc, px + 4, py + 4, px + PW + 4, py + PH + 4, int(Z'00050505', c_int))
        ! Card background + border
        call fill_soft_box(hdc, px, py, px + PW, py + PH, COL_PANEL_DEEP)
        call stroke_soft_box(hdc, px, py, px + PW, py + PH, COL_CYAN, 1)

        col_a = px + 12
        col_b = px + 202

        ! Title row
        call fill_box(hdc, px, py, px + PW, py + 28, COL_PANEL_ALT)
        call draw_title_text(hdc, col_a, py + 6, "Keyboard shortcuts", COL_CYAN)
        call draw_text(hdc, px + PW - 64, py + 8, "ESC closes", COL_DIM)
        call draw_line(hdc, px, py + 28, px + PW, py + 28, COL_BORDER, 1)

        row = py + 36

        ! ── Navigation ──────────────────────────────────────────────────────
        call draw_text(hdc, col_a, row, "NAVIGATION", COL_MUTED)
        row = row + lh
        call draw_text(hdc, col_a,      row, "F1",  COL_CYAN)
        call draw_text(hdc, col_a + 26, row, "Overview",           COL_INK)
        call draw_text(hdc, col_b,      row, "F2",  COL_CYAN)
        call draw_text(hdc, col_b + 26, row, "Grid Dispatch",      COL_INK)
        row = row + lh
        call draw_text(hdc, col_a,      row, "F3",  COL_CYAN)
        call draw_text(hdc, col_a + 26, row, "Gas Turbine",        COL_INK)
        call draw_text(hdc, col_b,      row, "F4",  COL_CYAN)
        call draw_text(hdc, col_b + 26, row, "Combined Cycle",     COL_INK)
        row = row + lh
        call draw_text(hdc, col_a,      row, "F5",  COL_CYAN)
        call draw_text(hdc, col_a + 26, row, "Market",             COL_INK)
        call draw_text(hdc, col_b,      row, "F6",  COL_CYAN)
        call draw_text(hdc, col_b + 26, row, "Trends",             COL_INK)
        row = row + lh
        call draw_text(hdc, col_a,      row, "F7",  COL_CYAN)
        call draw_text(hdc, col_a + 26, row, "Alarms",             COL_INK)
        call draw_text(hdc, col_b,      row, "F8",  COL_CYAN)
        call draw_text(hdc, col_b + 26, row, "Diagnostics / LCF",  COL_INK)
        row = row + lh
        call draw_text(hdc, col_a,      row, "F9",  COL_CYAN)
        call draw_text(hdc, col_a + 26, row, "Day-Ahead + Pareto", COL_INK)
        call draw_text(hdc, col_b,      row, "F10", COL_CYAN)
        call draw_text(hdc, col_b + 32, row, "Fleet UC",           COL_INK)
        row = row + lh
        call draw_text(hdc, col_a,      row, "F11", COL_CYAN)
        call draw_text(hdc, col_a + 32, row, "DNN + MC-dropout",   COL_INK)
        call draw_text(hdc, col_b,      row, "F12", COL_CYAN)
        call draw_text(hdc, col_b + 32, row, "Carbon",             COL_INK)
        row = row + lh
        call draw_text(hdc, col_a,      row, "F13", COL_CYAN)
        call draw_text(hdc, col_a + 32, row, "AI Forecast",        COL_INK)
        call draw_text(hdc, col_b,      row, "F14", COL_CYAN)
        call draw_text(hdc, col_b + 32, row, "Operator Advisory",  COL_INK)
        row = row + lh
        call draw_text(hdc, col_a,      row, "F15", COL_CYAN)
        call draw_text(hdc, col_a + 32, row, "Scenario Builder",   COL_INK)
        call draw_text(hdc, col_b,      row, "ESC", COL_CYAN)
        call draw_text(hdc, col_b + 32, row, "Back / close",       COL_INK)
        row = row + lh
        call draw_text(hdc, col_a,      row, "Ctrl-K", COL_CYAN)
        call draw_text(hdc, col_a + 50, row, "Exergy Analysis",    COL_INK)
        call draw_text(hdc, col_b,      row, "Rail", COL_CYAN)
        call draw_text(hdc, col_b + 32, row, "All L1/L2/L3 screens", COL_INK)

        row = row + lh + 5
        call draw_line(hdc, px + 8, row, px + PW - 8, row, COL_BORDER_SOFT, 1)
        row = row + 8

        ! ── Physics module toggles ───────────────────────────────────────────
        call draw_text(hdc, col_a, row, "MODULE TOGGLES", COL_MUTED)
        row = row + lh
        call draw_text(hdc, col_a,      row, "1", COL_GREEN)
        call draw_text(hdc, col_a + 14, row, &
            merge("P2X ON  ", "P2X OFF ", grid%p2x_active), &
            merge(COL_GREEN, COL_DIM, grid%p2x_active))
        call draw_text(hdc, col_b,      row, "2", COL_GREEN)
        call draw_text(hdc, col_b + 14, row, &
            merge("CCS ON  ", "CCS OFF ", grid%ccs_active), &
            merge(COL_GREEN, COL_DIM, grid%ccs_active))
        row = row + lh
        call draw_text(hdc, col_a,      row, "3", COL_LIME)
        call draw_text(hdc, col_a + 14, row, &
            merge("GFM ON  ", "GFM OFF ", grid%gfm_mode), &
            merge(COL_LIME, COL_DIM, grid%gfm_mode))
        call draw_text(hdc, col_b,      row, "4", COL_BLUE)
        call draw_text(hdc, col_b + 14, row, &
            merge("TIE ON  ", "TIE OFF ", grid%tie_active), &
            merge(COL_BLUE, COL_DIM, grid%tie_active))
        row = row + lh
        call draw_text(hdc, col_a,      row, "5", COL_CYAN)
        call draw_text(hdc, col_a + 14, row, &
            merge("MPC ON  ", "MPC OFF ", grid%mpc_active), &
            merge(COL_CYAN, COL_DIM, grid%mpc_active))
        call draw_text(hdc, col_b,      row, "6", COL_AMBER)
        call draw_text(hdc, col_b + 14, row, &
            merge("OU  ON  ", "OU  OFF ", grid%ou_active), &
            merge(COL_AMBER, COL_DIM, grid%ou_active))

        row = row + lh + 5
        call draw_line(hdc, px + 8, row, px + PW - 8, row, COL_BORDER_SOFT, 1)
        row = row + 8

        ! ── Simulation controls ──────────────────────────────────────────────
        call draw_text(hdc, col_a, row, "SIMULATION", COL_MUTED)
        row = row + lh
        call draw_text(hdc, col_a,      row, "Up/Dn", COL_CYAN)
        call draw_text(hdc, col_a + 42, row, "H2 blend (on F12)",  COL_INK)
        call draw_text(hdc, col_b,      row, "E",     COL_CYAN)
        call draw_text(hdc, col_b + 14, row, "Export shift CSV",   COL_INK)
        row = row + lh
        call draw_text(hdc, col_a,      row, "R",     COL_CYAN)
        call draw_text(hdc, col_a + 14, row, &
            merge("RL  ON  ", "RL  OFF ", grid%rl_mode), &
            merge(COL_LIME, COL_DIM, grid%rl_mode))
        call draw_text(hdc, col_b,      row, "A",     COL_CYAN)
        call draw_text(hdc, col_b + 14, row, &
            merge("DNN adapt ON ", "DNN adapt OFF", grid%dnn_adapting), &
            merge(COL_CYAN, COL_DIM, grid%dnn_adapting))
        row = row + lh
        call draw_text(hdc, col_a,      row, "T",     COL_CYAN)
        call draw_text(hdc, col_a + 14, row, &
            "Theme ["//trim(theme_name())//"]", COL_CYAN)
        call draw_text(hdc, col_b,      row, "?",     COL_CYAN)
        call draw_text(hdc, col_b + 14, row, "This shortcuts card", COL_INK)
        row = row + lh
        call draw_text(hdc, col_a,      row, "Ctrl-K", COL_CYAN)
        call draw_text(hdc, col_a + 50, row, "Command palette", COL_INK)
        call draw_text(hdc, col_b,      row, "Ctrl-S", COL_CYAN)
        call draw_text(hdc, col_b + 50, row, "Settings", COL_INK)
        row = row + lh
        call draw_text(hdc, col_a,      row, "Ctrl-N", COL_CYAN)
        call draw_text(hdc, col_a + 50, row, "Nav rail", COL_INK)
        call draw_text(hdc, col_b,      row, "Ctrl-D", COL_CYAN)
        call draw_text(hdc, col_b + 50, row, "Density", COL_INK)
        row = row + lh
        call draw_text(hdc, col_a,      row, "Ctrl-M", COL_CYAN)
        call draw_text(hdc, col_a + 50, row, "Demo tour", COL_INK)
        call draw_text(hdc, col_b,      row, "Ctrl-P", COL_CYAN)
        call draw_text(hdc, col_b + 50, row, "PNG export", COL_INK)
        row = row + lh
        call draw_text(hdc, col_a,      row, "Tab", COL_CYAN)
        call draw_text(hdc, col_a + 50, row, "Focus controls", COL_INK)
        call draw_text(hdc, col_b,      row, "H", COL_CYAN)
        call draw_text(hdc, col_b + 50, row, "Coach marks", COL_INK)

        row = row + lh + 5
        call draw_line(hdc, px + 8, row, px + PW - 8, row, COL_BORDER_SOFT, 1)
        row = row + 8

        ! ── Live snapshot ────────────────────────────────────────────────────
        call draw_text(hdc, col_a, row, "LIVE", COL_MUTED)
        row = row + lh
        write(sv,'(F8.3," Hz")') grid%frequency_Hz
        call draw_text(hdc, col_a,      row, "Freq",   COL_MUTED)
        call draw_text(hdc, col_a + 38, row, trim(adjustl(sv)), COL_CYAN)
        write(sv,'(F7.3," Hz")') grid%freq_nadir_Hz
        call draw_text(hdc, col_b,      row, "Nadir",  COL_MUTED)
        call draw_text(hdc, col_b + 42, row, trim(adjustl(sv)), &
            merge(COL_RED, merge(COL_AMBER, COL_GREEN, &
            grid%freq_nadir_Hz < 49.0_dp), grid%freq_nadir_Hz < 47.5_dp))
        row = row + lh
        write(sv,'(F6.1," MW")') grid%plant_power_MW
        call draw_text(hdc, col_a,      row, "Plant",  COL_MUTED)
        call draw_text(hdc, col_a + 38, row, trim(adjustl(sv)), COL_INK)
        write(sv,'(F6.1," MW")') grid%demand_MW
        call draw_text(hdc, col_b,      row, "Demand", COL_MUTED)
        call draw_text(hdc, col_b + 52, row, trim(adjustl(sv)), COL_INK)

        ! Footer
        call fill_box(hdc, px, py + PH - 20, px + PW, py + PH, COL_PANEL_ALT)
        call draw_line(hdc, px, py + PH - 20, px + PW, py + PH - 20, COL_BORDER_SOFT, 1)
        call draw_text(hdc, col_a, py + PH - 13, "Click outside or ESC to dismiss", COL_DIM)

    end subroutine draw_shortcuts_popup

end module thermotwin_win32_gui

program thermotwin_gui
    use thermotwin_win32_gui, only: run_gui
    implicit none

    call run_gui()
end program thermotwin_gui
