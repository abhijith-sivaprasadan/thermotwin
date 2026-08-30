#define WIN32_LEAN_AND_MEAN
#define NOMINMAX

#include <windows.h>
#include <objidl.h>
#include <gdiplus.h>

#include <algorithm>
#include <string>
#include <vector>

using namespace Gdiplus;

namespace {

ULONG_PTR gdiplus_token = 0;
bool gdiplus_ready = false;

Color color_from_colorref(int colorref)
{
    const BYTE r = static_cast<BYTE>(colorref & 0xFF);
    const BYTE g = static_cast<BYTE>((colorref >> 8) & 0xFF);
    const BYTE b = static_cast<BYTE>((colorref >> 16) & 0xFF);
    return Color(255, r, g, b);
}

std::wstring widen(const char* text)
{
    if (text == nullptr || *text == '\0') {
        return std::wstring();
    }

    int needed = MultiByteToWideChar(CP_UTF8, 0, text, -1, nullptr, 0);
    UINT code_page = CP_UTF8;
    if (needed == 0) {
        code_page = CP_ACP;
        needed = MultiByteToWideChar(code_page, 0, text, -1, nullptr, 0);
    }
    if (needed <= 0) {
        return std::wstring();
    }

    std::wstring wide(static_cast<size_t>(needed), L'\0');
    MultiByteToWideChar(code_page, 0, text, -1, wide.data(), needed);
    if (!wide.empty() && wide.back() == L'\0') {
        wide.pop_back();
    }
    return wide;
}

void configure(Graphics& graphics)
{
    graphics.SetSmoothingMode(SmoothingModeAntiAlias);
    graphics.SetTextRenderingHint(TextRenderingHintClearTypeGridFit);
    graphics.SetPixelOffsetMode(PixelOffsetModeHalf);
}

// [perf] Reuse ONE Graphics per painted frame instead of constructing+configuring
// a fresh one for every primitive (the dominant cost at 60 ms repaint). When a frame
// is active (hmi_begin_frame), every draw call binds to the cached Graphics; otherwise
// it falls back to a per-call temporary so off-frame draws still work.
Graphics* g_frame = nullptr;
HDC       g_frame_hdc = nullptr;

struct FrameGfx {
    Graphics* g;
    bool owned;
    explicit FrameGfx(HDC hdc) {
        if (g_frame != nullptr && hdc == g_frame_hdc) {
            g = g_frame; owned = false;
        } else {
            g = new Graphics(hdc); configure(*g); owned = true;
        }
    }
    ~FrameGfx() { if (owned) delete g; }
    FrameGfx(const FrameGfx&) = delete;
    FrameGfx& operator=(const FrameGfx&) = delete;
};

int get_encoder_clsid(const wchar_t* format, CLSID* clsid)
{
    if (format == nullptr || clsid == nullptr) {
        return -1;
    }

    UINT count = 0;
    UINT size = 0;
    if (GetImageEncodersSize(&count, &size) != Ok || size == 0) {
        return -1;
    }

    std::vector<BYTE> buffer(size);
    ImageCodecInfo* info = reinterpret_cast<ImageCodecInfo*>(buffer.data());
    if (GetImageEncoders(count, size, info) != Ok) {
        return -1;
    }

    for (UINT i = 0; i < count; ++i) {
        if (wcscmp(info[i].MimeType, format) == 0) {
            *clsid = info[i].Clsid;
            return static_cast<int>(i);
        }
    }
    return -1;
}

REAL rect_width(int left, int right)
{
    return static_cast<REAL>(std::max(0, right - left));
}

REAL rect_height(int top, int bottom)
{
    return static_cast<REAL>(std::max(0, bottom - top));
}

void add_rounded_rect(GraphicsPath& path, REAL left, REAL top, REAL width, REAL height, REAL radius)
{
    radius = std::max<REAL>(0.0f, std::min(radius, std::min(width, height) / 2.0f));
    if (radius <= 0.5f) {
        path.AddRectangle(RectF(left, top, width, height));
        return;
    }

    const REAL diameter = radius * 2.0f;
    path.AddArc(left, top, diameter, diameter, 180.0f, 90.0f);
    path.AddArc(left + width - diameter, top, diameter, diameter, 270.0f, 90.0f);
    path.AddArc(left + width - diameter, top + height - diameter, diameter, diameter, 0.0f, 90.0f);
    path.AddArc(left, top + height - diameter, diameter, diameter, 90.0f, 90.0f);
    path.CloseFigure();
}

} // namespace

// [perf] Open/close a frame so all primitives share one configured Graphics.
extern "C" void hmi_begin_frame(HDC hdc)
{
    if (g_frame != nullptr) { delete g_frame; g_frame = nullptr; }
    g_frame = new Graphics(hdc);
    configure(*g_frame);
    g_frame_hdc = hdc;
}

extern "C" void hmi_end_frame()
{
    if (g_frame != nullptr) { delete g_frame; g_frame = nullptr; }
    g_frame_hdc = nullptr;
}

extern "C" int hmi_native_init()
{
    if (gdiplus_ready) {
        return 1;
    }

    GdiplusStartupInput input;
    const Status status = GdiplusStartup(&gdiplus_token, &input, nullptr);
    gdiplus_ready = status == Ok;
    return gdiplus_ready ? 1 : 0;
}

extern "C" void hmi_native_shutdown()
{
    if (!gdiplus_ready) {
        return;
    }

    GdiplusShutdown(gdiplus_token);
    gdiplus_token = 0;
    gdiplus_ready = false;
}

extern "C" int hmi_save_window_png(HWND hwnd, const char* path)
{
    if (hwnd == nullptr || path == nullptr || *path == '\0') {
        return 0;
    }
    if (!gdiplus_ready && hmi_native_init() == 0) {
        return 0;
    }

    RECT rc{};
    if (!GetClientRect(hwnd, &rc)) {
        return 0;
    }
    const int width = std::max(1L, rc.right - rc.left);
    const int height = std::max(1L, rc.bottom - rc.top);

    HDC src = GetDC(hwnd);
    if (src == nullptr) {
        return 0;
    }
    HDC mem = CreateCompatibleDC(src);
    HBITMAP bmp = CreateCompatibleBitmap(src, width, height);
    if (mem == nullptr || bmp == nullptr) {
        if (bmp != nullptr) DeleteObject(bmp);
        if (mem != nullptr) DeleteDC(mem);
        ReleaseDC(hwnd, src);
        return 0;
    }

    HGDIOBJ old = SelectObject(mem, bmp);
    const BOOL copied = BitBlt(mem, 0, 0, width, height, src, 0, 0, SRCCOPY);
    SelectObject(mem, old);
    ReleaseDC(hwnd, src);
    DeleteDC(mem);
    if (!copied) {
        DeleteObject(bmp);
        return 0;
    }

    Bitmap image(bmp, nullptr);
    CLSID png_clsid{};
    const std::wstring wide_path = widen(path);
    const int ok = (get_encoder_clsid(L"image/png", &png_clsid) >= 0 &&
                    image.Save(wide_path.c_str(), &png_clsid, nullptr) == Ok) ? 1 : 0;
    DeleteObject(bmp);
    return ok;
}

extern "C" void hmi_fill_rect(HDC hdc, int left, int top, int right, int bottom, int color)
{
    if (hdc == nullptr) {
        return;
    }

    FrameGfx _fg(hdc);
    Graphics& graphics = *_fg.g;
    SolidBrush brush(color_from_colorref(color));
    graphics.FillRectangle(&brush, static_cast<REAL>(left), static_cast<REAL>(top),
        rect_width(left, right), rect_height(top, bottom));
}

extern "C" void hmi_fill_round_rect(HDC hdc, int left, int top, int right, int bottom, int radius, int color)
{
    if (hdc == nullptr) {
        return;
    }

    FrameGfx _fg(hdc);
    Graphics& graphics = *_fg.g;
    SolidBrush brush(color_from_colorref(color));
    GraphicsPath path;
    add_rounded_rect(path, static_cast<REAL>(left), static_cast<REAL>(top),
        rect_width(left, right), rect_height(top, bottom), static_cast<REAL>(radius));
    graphics.FillPath(&brush, &path);
}

extern "C" void hmi_stroke_rect(HDC hdc, int left, int top, int right, int bottom, int color, int width)
{
    if (hdc == nullptr || width <= 0) {
        return;
    }

    FrameGfx _fg(hdc);
    Graphics& graphics = *_fg.g;
    Pen pen(color_from_colorref(color), static_cast<REAL>(width));
    graphics.DrawRectangle(&pen, static_cast<REAL>(left), static_cast<REAL>(top),
        rect_width(left, right), rect_height(top, bottom));
}

extern "C" void hmi_stroke_round_rect(HDC hdc, int left, int top, int right, int bottom, int radius, int color, int width)
{
    if (hdc == nullptr || width <= 0) {
        return;
    }

    FrameGfx _fg(hdc);
    Graphics& graphics = *_fg.g;
    Pen pen(color_from_colorref(color), static_cast<REAL>(width));
    GraphicsPath path;
    add_rounded_rect(path, static_cast<REAL>(left), static_cast<REAL>(top),
        rect_width(left, right), rect_height(top, bottom), static_cast<REAL>(radius));
    graphics.DrawPath(&pen, &path);
}

extern "C" void hmi_draw_line(HDC hdc, int x1, int y1, int x2, int y2, int color, int width)
{
    if (hdc == nullptr || width <= 0) {
        return;
    }

    FrameGfx _fg(hdc);
    Graphics& graphics = *_fg.g;
    Pen pen(color_from_colorref(color), static_cast<REAL>(width));
    graphics.DrawLine(&pen, static_cast<REAL>(x1), static_cast<REAL>(y1),
        static_cast<REAL>(x2), static_cast<REAL>(y2));
}

extern "C" void hmi_draw_text(
    HDC hdc,
    int x,
    int y,
    const char* text,
    int pixel_size,
    int weight,
    int color)
{
    if (hdc == nullptr || text == nullptr || pixel_size <= 0) {
        return;
    }

    const std::wstring wide = widen(text);
    if (wide.empty()) {
        return;
    }

    FrameGfx _fg(hdc);
    Graphics& graphics = *_fg.g;

    int w = weight;
    const wchar_t* faceName = L"Segoe UI";
    if (w >= 10000) { faceName = L"Consolas"; w -= 10000; }   // [6.0-P2] monospace tabular numerics
    FontFamily family(faceName);
    const INT style = w >= 600 ? FontStyleBold : FontStyleRegular;
    Font font(&family, static_cast<REAL>(pixel_size), style, UnitPixel);
    SolidBrush brush(color_from_colorref(color));
    StringFormat format;
    format.SetFormatFlags(StringFormatFlagsNoWrap);
    format.SetTrimming(StringTrimmingEllipsisCharacter);

    RectF layout(static_cast<REAL>(x), static_cast<REAL>(y), 1600.0f, static_cast<REAL>(pixel_size + 8));
    graphics.DrawString(wide.c_str(), -1, &font, layout, &format, &brush);
}

extern "C" void hmi_fill_pie(HDC hdc, int cx, int cy, int radius,
    float start_deg, float sweep_deg, int color)
{
    if (hdc == nullptr || radius <= 0 || sweep_deg == 0.0f) return;
    FrameGfx _fg(hdc);
    Graphics& graphics = *_fg.g;
    SolidBrush brush(color_from_colorref(color));
    const REAL diameter = static_cast<REAL>(radius * 2);
    const REAL left = static_cast<REAL>(cx - radius);
    const REAL top  = static_cast<REAL>(cy - radius);
    graphics.FillPie(&brush, left, top, diameter, diameter, start_deg, sweep_deg);
}

extern "C" void hmi_draw_arc(HDC hdc, int cx, int cy, int radius,
    float start_deg, float sweep_deg, int color, int width)
{
    if (hdc == nullptr || radius <= 0 || width <= 0 || sweep_deg == 0.0f) return;
    FrameGfx _fg(hdc);
    Graphics& graphics = *_fg.g;
    Pen pen(color_from_colorref(color), static_cast<REAL>(width));
    const REAL diameter = static_cast<REAL>(radius * 2);
    const REAL left = static_cast<REAL>(cx - radius);
    const REAL top  = static_cast<REAL>(cy - radius);
    graphics.DrawArc(&pen, left, top, diameter, diameter, start_deg, sweep_deg);
}

// Alpha-blended rectangle: alpha 0=transparent, 255=opaque.
// Used for screen-transition darkening and semi-transparent modal overlays.
extern "C" void hmi_fill_alpha_rect(HDC hdc, int left, int top, int right, int bottom,
    int color, int alpha)
{
    if (hdc == nullptr) return;
    FrameGfx _fg(hdc);
    Graphics& graphics = *_fg.g;
    const BYTE r = static_cast<BYTE>(color & 0xFF);
    const BYTE g = static_cast<BYTE>((color >> 8) & 0xFF);
    const BYTE b = static_cast<BYTE>((color >> 16) & 0xFF);
    SolidBrush brush(Color(static_cast<BYTE>(std::max(0, std::min(255, alpha))), r, g, b));
    graphics.FillRectangle(&brush, static_cast<REAL>(left), static_cast<REAL>(top),
        rect_width(left, right), rect_height(top, bottom));
}

// Alpha-blended rounded rectangle. Same signature as fill_alpha_rect + radius.
extern "C" void hmi_fill_alpha_round_rect(HDC hdc, int left, int top, int right, int bottom,
    int radius, int color, int alpha)
{
    if (hdc == nullptr) return;
    FrameGfx _fg(hdc);
    Graphics& graphics = *_fg.g;
    const BYTE r = static_cast<BYTE>(color & 0xFF);
    const BYTE g = static_cast<BYTE>((color >> 8) & 0xFF);
    const BYTE b = static_cast<BYTE>((color >> 16) & 0xFF);
    SolidBrush brush(Color(static_cast<BYTE>(std::max(0, std::min(255, alpha))), r, g, b));
    GraphicsPath path;
    add_rounded_rect(path, static_cast<REAL>(left), static_cast<REAL>(top),
        rect_width(left, right), rect_height(top, bottom), static_cast<REAL>(radius));
    graphics.FillPath(&brush, &path);
}

extern "C" void hmi_draw_polygon(HDC hdc, int* xs, int* ys, int n_pts,
    int fill_color, int stroke_color, int stroke_width)
{
    if (hdc == nullptr || xs == nullptr || ys == nullptr || n_pts < 3) return;
    FrameGfx _fg(hdc);
    Graphics& graphics = *_fg.g;
    std::vector<PointF> pts(static_cast<size_t>(n_pts));
    for (int i = 0; i < n_pts; ++i)
        pts[static_cast<size_t>(i)] = PointF(static_cast<REAL>(xs[i]), static_cast<REAL>(ys[i]));
    SolidBrush brush(color_from_colorref(fill_color));
    graphics.FillPolygon(&brush, pts.data(), n_pts);
    if (stroke_width > 0) {
        Pen pen(color_from_colorref(stroke_color), static_cast<REAL>(stroke_width));
        graphics.DrawPolygon(&pen, pts.data(), n_pts);
    }
}

// [perf] Open polyline in a single DrawLines call — for live traces / charts, so a
// series of N points costs one Graphics + one Pen instead of N per-segment calls.
extern "C" void hmi_draw_polyline(HDC hdc, int* xs, int* ys, int n_pts,
    int color, int width)
{
    if (hdc == nullptr || xs == nullptr || ys == nullptr || n_pts < 2 || width <= 0) return;
    FrameGfx _fg(hdc);
    Graphics& graphics = *_fg.g;
    std::vector<Point> pts(static_cast<size_t>(n_pts));
    for (int i = 0; i < n_pts; ++i)
        pts[static_cast<size_t>(i)] = Point(xs[i], ys[i]);
    Pen pen(color_from_colorref(color), static_cast<REAL>(width));
    graphics.DrawLines(&pen, pts.data(), n_pts);
}
