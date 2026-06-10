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

extern "C" void hmi_fill_rect(HDC hdc, int left, int top, int right, int bottom, int color)
{
    if (hdc == nullptr) {
        return;
    }

    Graphics graphics(hdc);
    configure(graphics);
    SolidBrush brush(color_from_colorref(color));
    graphics.FillRectangle(&brush, static_cast<REAL>(left), static_cast<REAL>(top),
        rect_width(left, right), rect_height(top, bottom));
}

extern "C" void hmi_fill_round_rect(HDC hdc, int left, int top, int right, int bottom, int radius, int color)
{
    if (hdc == nullptr) {
        return;
    }

    Graphics graphics(hdc);
    configure(graphics);
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

    Graphics graphics(hdc);
    configure(graphics);
    Pen pen(color_from_colorref(color), static_cast<REAL>(width));
    graphics.DrawRectangle(&pen, static_cast<REAL>(left), static_cast<REAL>(top),
        rect_width(left, right), rect_height(top, bottom));
}

extern "C" void hmi_stroke_round_rect(HDC hdc, int left, int top, int right, int bottom, int radius, int color, int width)
{
    if (hdc == nullptr || width <= 0) {
        return;
    }

    Graphics graphics(hdc);
    configure(graphics);
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

    Graphics graphics(hdc);
    configure(graphics);
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

    Graphics graphics(hdc);
    configure(graphics);

    FontFamily family(L"Segoe UI");
    const INT style = weight >= 600 ? FontStyleBold : FontStyleRegular;
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
    Graphics graphics(hdc);
    configure(graphics);
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
    Graphics graphics(hdc);
    configure(graphics);
    Pen pen(color_from_colorref(color), static_cast<REAL>(width));
    const REAL diameter = static_cast<REAL>(radius * 2);
    const REAL left = static_cast<REAL>(cx - radius);
    const REAL top  = static_cast<REAL>(cy - radius);
    graphics.DrawArc(&pen, left, top, diameter, diameter, start_deg, sweep_deg);
}

extern "C" void hmi_draw_polygon(HDC hdc, int* xs, int* ys, int n_pts,
    int fill_color, int stroke_color, int stroke_width)
{
    if (hdc == nullptr || xs == nullptr || ys == nullptr || n_pts < 3) return;
    Graphics graphics(hdc);
    configure(graphics);
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
