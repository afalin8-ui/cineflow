#include "app.h"
#include <windowsx.h>
#include <gdiplus.h>
#include <shellapi.h>
#include <map>
#include <vector>
using namespace Gdiplus;

HWND g_panel = nullptr, g_handle = nullptr, g_edge = nullptr;

// ---- цвета ---------------------------------------------------------------
// Тёмные и спокойные: панель висит поверх картинки, и яркая рамка сама
// становится первым, что видит глаз.
static const Color C_BG      (255,  28,  27,  26);
static const Color C_BORDER  (255,  58,  55,  51);
static const Color C_BTN     (255,  43,  42,  40);
static const Color C_BTN_DN  (255,  69,  66,  61);
static const Color C_LATCH   (255, 217, 119,  87);   // залипло
static const Color C_ARM     (255, 217, 164,  65);   // ждём пера
static const Color C_TEXT    (255, 240, 238, 230);
static const Color C_TEXT_DK (255,  26,  25,  24);
static const Color C_MUTED   (255, 166, 163, 154);
static const Color C_WARN    (255, 200,  90,  75);
static const Color C_BTN_TOP (255,  56,  54,  51);   // верх кнопки чуть светлее
static const Color C_BTN_EDGE(255,  62,  59,  55);   // кромка кнопки

// На плотном экране волосяная линия в одну точку почти не видна: при 227
// точках на дюйм это 0,11 мм. Толщину линий считаем от размера кнопки, чтобы
// рамка читалась одинаково и на обычном экране, и на плотном.
static int g_btnPx = 0;
static REAL Hair() {
    REAL v = (REAL)(g_btnPx / 52.0);
    return v < 1.0f ? 1.0f : v;
}

// ---- размеры и раскладка -------------------------------------------------
static int g_profileIdx = 0;
static int g_pad = 0, g_gap = 0, g_hdr = 0, g_ftr = 0;
static RECT g_rcHeader{}, g_rcSettings{}, g_rcHide{};
static SIZE g_size{};
static bool g_vertical = true;
static bool g_needAdmin = false;

int  PanelProfile() { return g_profileIdx; }
Profile* CurProfile() {
    if (g_cfg.profiles.empty()) return nullptr;
    if (g_profileIdx < 0 || g_profileIdx >= (int)g_cfg.profiles.size()) g_profileIdx = 0;
    return &g_cfg.profiles[g_profileIdx];
}
void PanelSetNeedAdmin(bool v) { if (g_needAdmin != v) { g_needAdmin = v; PanelRedraw(); } }

static RECT MonitorRect() {
    HMONITOR mon = MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY);
    MONITORINFO mi{sizeof(MONITORINFO)};
    GetMonitorInfoW(mon, &mi);
    return mi.rcMonitor;
}

static RECT WorkArea() {
    HMONITOR mon = MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY);
    MONITORINFO mi{sizeof(MONITORINFO)};
    GetMonitorInfoW(mon, &mi);
    return mi.rcWork;
}

// ---- полоса задач Windows: режим «сдвигать окна» --------------------------
// Полоска регистрируется как панель рабочего стола, и тогда развёрнутые окна
// не залезают под неё. Снимаем регистрацию, когда панель прячется, иначе
// место осталось бы занятым впустую.
static bool  g_abReg = false;
static DWORD g_abAt  = 0;      // когда сами двигали панель рабочего стола

static void AppBarRemove() {
    if (!g_abReg) return;
    APPBARDATA ab{sizeof(APPBARDATA)};
    ab.hWnd = g_panel;
    SHAppBarMessage(ABM_REMOVE, &ab);
    g_abReg = false;
}

static void AppBarSet(RECT r) {
    APPBARDATA ab{sizeof(APPBARDATA)};
    ab.hWnd = g_panel;
    ab.uCallbackMessage = WM_APPBARMSG;
    if (!g_abReg) {
        if (!SHAppBarMessage(ABM_NEW, &ab)) { Log(L"не удалось занять место у края экрана"); return; }
        g_abReg = true;
    }
    ab.uEdge = (g_cfg.edge == E_LEFT) ? ABE_LEFT : (g_cfg.edge == E_RIGHT) ? ABE_RIGHT
             : (g_cfg.edge == E_TOP)  ? ABE_TOP  : ABE_BOTTOM;
    ab.rc = r;
    SHAppBarMessage(ABM_QUERYPOS, &ab);
    // после QUERYPOS система могла подвинуть край — возвращаем толщину
    int th = (g_cfg.edge == E_LEFT || g_cfg.edge == E_RIGHT) ? (r.right - r.left) : (r.bottom - r.top);
    switch (ab.uEdge) {
        case ABE_LEFT:   ab.rc.right  = ab.rc.left + th; break;
        case ABE_RIGHT:  ab.rc.left   = ab.rc.right - th; break;
        case ABE_TOP:    ab.rc.bottom = ab.rc.top + th; break;
        default:         ab.rc.top    = ab.rc.bottom - th; break;
    }
    SHAppBarMessage(ABM_SETPOS, &ab);
    g_abAt = GetTickCount();
    SetWindowPos(g_panel, HWND_TOPMOST, ab.rc.left, ab.rc.top,
                 ab.rc.right - ab.rc.left, ab.rc.bottom - ab.rc.top,
                 SWP_NOACTIVATE);
}

// ---- раскладка -----------------------------------------------------------
// Считаем в двух осях: «вдоль» края и «поперёк». Так одна формула годится
// и для полоски слева, и для полоски снизу.
static int g_along = 0, g_across = 0, g_cols = 1, g_used = 0;
static int g_fitRows = 0;      // сколько кнопок влезает по высоте края
static double g_realMM = 0;    // размер кнопки после подгонки

static void PlaceContent(int winAlong) {
    Profile* p = CurProfile();
    int n = p ? (int)p->btns.size() : 0;
    int free_ = winAlong - g_along;
    if (free_ < 0) free_ = 0;
    int off = (g_cfg.align == A_START) ? 0 : (g_cfg.align == A_END) ? free_ : free_ / 2;

    int a0 = off + g_pad;
    g_rcHeader = g_vertical ? RECT{g_pad, a0, g_across - g_pad, a0 + g_hdr}
                            : RECT{a0, g_pad, a0 + g_hdr, g_across - g_pad};
    int base = a0 + g_hdr + g_gap;
    if (p) for (int i = 0; i < n; i++) {
        int col = g_used > 0 ? i / g_used : 0, row = g_used > 0 ? i % g_used : 0;
        int a = base + row * (g_btnPx + g_gap);
        int c = g_pad + col * (g_btnPx + g_gap);
        p->btns[i].rc = g_vertical ? RECT{c, a, c + g_btnPx, a + g_btnPx}
                                   : RECT{a, c, a + g_btnPx, c + g_btnPx};
    }
    int fa0 = off + g_along - g_pad - g_ftr, fa1 = off + g_along - g_pad;
    int half = (g_across - 2 * g_pad - g_gap) / 2;
    int c0 = g_pad, c1 = g_pad + half, c2 = c1 + g_gap, c3 = c2 + half;
    g_rcSettings = g_vertical ? RECT{c0, fa0, c1, fa1} : RECT{fa0, c0, fa1, c1};
    g_rcHide     = g_vertical ? RECT{c2, fa0, c3, fa1} : RECT{fa0, c2, fa1, c3};
}

void PanelLayout() {
    // Занимая край, мы сами меняем рабочую область, а Windows рассылает об
    // этом сообщение — без защиты получился бы бесконечный круг.
    static bool busy = false;
    if (busy) return;
    busy = true;
    struct Done { bool* f; ~Done() { *f = false; } } done{&busy};

    Profile* p = CurProfile();
    int n = p ? (int)p->btns.size() : 0;
    RECT wa = WorkArea();
    g_vertical = (g_cfg.edge == E_LEFT || g_cfg.edge == E_RIGHT);
    int spanAll = g_vertical ? (wa.bottom - wa.top) : (wa.right - wa.left);

    // Если кнопки не помещаются в один ряд, сначала чуть уменьшаем кнопку и
    // только потом ставим второй ряд: второй ряд съедает ширину экрана.
    double mm = g_cfg.buttonMM;
    int rows = 1;
    for (;;) {
        g_btnPx = MM2PX(mm);
        g_pad   = (int)(g_btnPx * 0.10) < 4 ? 4 : (int)(g_btnPx * 0.10);
        g_gap   = (int)(g_btnPx * 0.09) < 3 ? 3 : (int)(g_btnPx * 0.09);
        g_hdr   = (int)(g_btnPx * 0.50);
        g_ftr   = (int)(g_btnPx * 0.52);
        int avail = spanAll - 2 * g_pad - g_hdr - g_ftr - 2 * g_gap;
        rows = (avail + g_gap) / (g_btnPx + g_gap);
        if (rows < 1) rows = 1;
        g_cols = n > 0 ? (n + rows - 1) / rows : 1;
        // Ужимаем кнопку не глубже 10 мм: под палец это уже мало, лучше
        // второй ряд. Ниже — сколько кнопок вообще влезает по высоте.
        if (g_cols <= 1 || mm <= 10.0) break;
        mm -= 0.25;
    }
    if (g_cols < 1) g_cols = 1;
    if (g_cols > 3) g_cols = 3;
    g_used = n > 0 ? (n + g_cols - 1) / g_cols : 0;
    if (g_used > rows) g_used = rows;
    g_fitRows = rows;
    g_realMM  = mm;

    g_along  = 2 * g_pad + g_hdr + g_gap + (g_used > 0 ? g_used * g_btnPx + (g_used - 1) * g_gap + g_gap : 0) + g_ftr;
    g_across = 2 * g_pad + g_cols * g_btnPx + (g_cols - 1) * g_gap;

    bool appbar = g_cfg.pushWindows && IsWindowVisible(g_panel);
    if (appbar) {
        RECT mo = MonitorRect();
        RECT want = g_vertical
            ? RECT{(g_cfg.edge == E_LEFT ? mo.left : mo.right - g_across), mo.top,
                   (g_cfg.edge == E_LEFT ? mo.left + g_across : mo.right), mo.bottom}
            : RECT{mo.left, (g_cfg.edge == E_TOP ? mo.top : mo.bottom - g_across),
                   mo.right, (g_cfg.edge == E_TOP ? mo.top + g_across : mo.bottom)};
        AppBarSet(want);
    } else {
        AppBarRemove();
        int freeSpan = spanAll - g_along;
        if (freeSpan < 0) freeSpan = 0;
        int off = (g_cfg.align == A_START) ? 0 : (g_cfg.align == A_END) ? freeSpan : freeSpan / 2;
        int x, y, w, h;
        if (g_vertical) { w = g_across; h = g_along; x = (g_cfg.edge == E_LEFT) ? wa.left : wa.right - w; y = wa.top + off; }
        else            { w = g_along;  h = g_across; y = (g_cfg.edge == E_TOP)  ? wa.top  : wa.bottom - h; x = wa.left + off; }
        SetWindowPos(g_panel, HWND_TOPMOST, x, y, w, h, SWP_NOACTIVATE);
    }

    // содержимое расставляем по НАСТОЯЩЕМУ размеру окна: в режиме «сдвигать
    // окна» край занят целиком, и кнопки внутри стоят по выравниванию
    RECT got;
    GetWindowRect(g_panel, &got);
    g_size.cx = got.right - got.left;
    g_size.cy = got.bottom - got.top;
    PlaceContent(g_vertical ? g_size.cy : g_size.cx);
    PanelRedraw();
}

// ---- рисование -----------------------------------------------------------
static void RoundPath(GraphicsPath& path, RectF r, REAL rad) {
    REAL d = rad * 2;
    if (d > r.Width)  d = r.Width;
    if (d > r.Height) d = r.Height;
    if (d < 1) d = 1;
    path.AddArc(r.X, r.Y, d, d, 180, 90);
    path.AddArc(r.GetRight() - d, r.Y, d, d, 270, 90);
    path.AddArc(r.GetRight() - d, r.GetBottom() - d, d, d, 0, 90);
    path.AddArc(r.X, r.GetBottom() - d, d, d, 90, 90);
    path.CloseFigure();
}

// Кнопка: очень слабый вертикальный переход и светлая кромка. На плотном
// экране это единственное, что отличает «кнопку» от «пятна краски»: плоская
// заливка читается как дырка в панели, а не как клавиша под пальцем.
static void ButtonFace(Graphics& g, RectF r, const Color& base, const Color& top,
                       const Color& edge, REAL rad) {
    GraphicsPath path;
    RoundPath(path, r, rad);
    LinearGradientBrush lg(RectF(r.X, r.Y - 1, r.Width, r.Height + 2), top, base, LinearGradientModeVertical);
    g.FillPath(&lg, &path);
    Pen pen(edge, Hair());
    g.DrawPath(&pen, &path);
}

static void RoundRect_(Graphics& g, const Color& fill, RectF r, REAL rad, const Color* border = nullptr) {
    GraphicsPath path;
    REAL d = rad * 2;
    if (d > r.Width)  d = r.Width;
    if (d > r.Height) d = r.Height;
    if (d < 1) d = 1;
    path.AddArc(r.X, r.Y, d, d, 180, 90);
    path.AddArc(r.GetRight() - d, r.Y, d, d, 270, 90);
    path.AddArc(r.GetRight() - d, r.GetBottom() - d, d, d, 0, 90);
    path.AddArc(r.X, r.GetBottom() - d, d, d, 90, 90);
    path.CloseFigure();
    SolidBrush b(fill);
    g.FillPath(&b, &path);
    if (border) {
        Pen pen(*border, Hair());
        g.DrawPath(&pen, &path);
    }
}

// Текст рисуем обычными средствами Windows, а не GDI+: в окне с прозрачностью
// GDI+ кладёт буквы с нулевой непрозрачностью, и подписи исчезают целиком —
// проверено, панель выходила с пустыми кнопками. Непрозрачность ниже берётся
// от подложки, поэтому способ рисования текста уже не важен.
// На Windows 11 есть Segoe UI Variable — тот же рисунок, но нарисованный
// под мелкие размеры: на плотном экране разница видна сразу. Если шрифта нет
// (Windows 10 и старше), берём обычный Segoe UI.
static int CALLBACK FontProbe(const LOGFONTW*, const TEXTMETRICW*, DWORD, LPARAM lp) {
    *(bool*)lp = true;
    return 0;
}

const wchar_t* UiFace() {
    static const wchar_t* face = nullptr;
    if (!face) {
        bool found = false;
        LOGFONTW q{};
        q.lfCharSet = DEFAULT_CHARSET;
        wcscpy(q.lfFaceName, L"Segoe UI Variable Text");
        HDC dc = GetDC(nullptr);
        if (dc) {
            EnumFontFamiliesExW(dc, &q, FontProbe, (LPARAM)&found, 0);
            ReleaseDC(nullptr, dc);
        }
        face = found ? L"Segoe UI Variable Text" : L"Segoe UI";
        Log(L"шрифт панели: %s", face);
    }
    return face;
}

static HFONT MakeFont(int px, bool bold) {
    LOGFONTW lf{};
    lf.lfHeight  = -px;
    lf.lfWeight  = bold ? FW_SEMIBOLD : FW_NORMAL;
    // Не ClearType: панель полупрозрачная, и подпиксельные каёмки на просвет
    // читались бы цветной бахромой. При такой плотности разницы всё равно нет.
    lf.lfQuality = ANTIALIASED_QUALITY;
    lf.lfCharSet = DEFAULT_CHARSET;
    wcscpy(lf.lfFaceName, UiFace());
    return CreateFontIndirectW(&lf);
}

// Размер шрифта подбираем под кнопку: длинная подпись сама встаёт в две
// строки и при необходимости мельчает. Так «Панорама» и «J» выглядят одинаково
// аккуратно, и в настройках не нужно вручную расставлять переносы.
static void DrawLabel(HDC dc, const std::wstring& s, RECT rc, COLORREF col, int maxPx, bool bold) {
    if (s.empty()) return;
    int w = rc.right - rc.left, h = rc.bottom - rc.top;
    if (w <= 2 || h <= 2) return;
    if (maxPx < 8) maxPx = 8;

    HFONT use = nullptr;
    RECT calc{};
    for (int px = maxPx; px >= 8; px -= (px > 24 ? 2 : 1)) {
        HFONT f = MakeFont(px, bold);
        HGDIOBJ of = SelectObject(dc, f);
        RECT c = rc;
        c.bottom = rc.top + 4000;
        DrawTextW(dc, s.c_str(), -1, &c, DT_CENTER | DT_WORDBREAK | DT_CALCRECT | DT_NOPREFIX);
        bool fits = (c.bottom - c.top) <= h && (c.right - c.left) <= w;
        SelectObject(dc, of);
        if (fits) { use = f; calc = c; break; }
        DeleteObject(f);
    }
    if (!use) { use = MakeFont(8, bold); calc = rc; }

    HGDIOBJ of = SelectObject(dc, use);
    SetBkMode(dc, TRANSPARENT);
    SetTextColor(dc, col);
    RECT out = rc;
    int hh = calc.bottom - calc.top;
    if (hh < h) out.top += (h - hh) / 2;
    DrawTextW(dc, s.c_str(), -1, &out, DT_CENTER | DT_WORDBREAK | DT_NOPREFIX);
    SelectObject(dc, of);
    DeleteObject(use);
}

static COLORREF RGBof(const Color& c) { return RGB(c.GetR(), c.GetG(), c.GetB()); }

// Значки в подвале рисуем линиями, а не знаками шрифта: нужного знака в шрифте
// может не оказаться, и вместо него встанет пустой квадратик.
static void DrawGear(Graphics& g, RECT r, const Color& col) {
    REAL cx = (r.left + r.right) / 2.0f, cy = (r.top + r.bottom) / 2.0f;
    REAL s = (REAL)((r.right - r.left) < (r.bottom - r.top) ? (r.right - r.left) : (r.bottom - r.top));
    REAL w = s * 0.46f, th = s * 0.07f;
    if (th < 1.5f) th = 1.5f;
    SolidBrush b(col);
    for (int i = -1; i <= 1; i++) {
        REAL y = cy + i * s * 0.16f;
        g.FillRectangle(&b, cx - w / 2, y - th / 2, w, th);
        REAL kx = cx - w / 2 + (i + 1) * w * 0.34f;
        g.FillEllipse(&b, kx - th * 1.5f, y - th * 1.5f, th * 3.0f, th * 3.0f);
    }
}

static void DrawCross(Graphics& g, RECT r, const Color& col) {
    REAL cx = (r.left + r.right) / 2.0f, cy = (r.top + r.bottom) / 2.0f;
    REAL s = (REAL)((r.right - r.left) < (r.bottom - r.top) ? (r.right - r.left) : (r.bottom - r.top)) * 0.22f;
    REAL th = s * 0.34f;
    if (th < 1.5f) th = 1.5f;
    Pen p(col, th);
    p.SetStartCap(LineCapRound);
    p.SetEndCap(LineCapRound);
    g.DrawLine(&p, cx - s, cy - s, cx + s, cy + s);
    g.DrawLine(&p, cx + s, cy - s, cx - s, cy + s);
}

void PanelRedraw() {
    if (!g_panel || !IsWindowVisible(g_panel)) return;
    RECT wr;
    GetWindowRect(g_panel, &wr);
    int w = wr.right - wr.left, h = wr.bottom - wr.top;
    if (w <= 0 || h <= 0) return;

    BITMAPINFO bi{};
    bi.bmiHeader.biSize        = sizeof(BITMAPINFOHEADER);
    bi.bmiHeader.biWidth       = w;
    bi.bmiHeader.biHeight      = -h;             // сверху вниз
    bi.bmiHeader.biPlanes      = 1;
    bi.bmiHeader.biBitCount    = 32;
    bi.bmiHeader.biCompression = BI_RGB;
    void* bits = nullptr;
    HDC screen = GetDC(nullptr);
    HBITMAP dib = CreateDIBSection(screen, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
    if (!dib) { ReleaseDC(nullptr, screen); return; }
    HDC mem = CreateCompatibleDC(screen);
    HGDIOBJ old = SelectObject(mem, dib);
    memset(bits, 0, (size_t)w * h * 4);

    REAL rad = (REAL)(g_btnPx * 0.16);
    {
        Graphics g(mem);
        g.SetSmoothingMode(SmoothingModeAntiAlias);
        REAL hw = Hair();
        RoundRect_(g, C_BG, RectF(hw / 2, hw / 2, (REAL)w - hw, (REAL)h - hw), rad + 2, &C_BORDER);
    }

    // Непрозрачность берём ТОЛЬКО от подложки: всё нарисованное поверх остаётся
    // видимым, чем бы его ни рисовали.
    std::vector<unsigned char> mask((size_t)w * h);
    {
        unsigned char* px = (unsigned char*)bits;
        for (size_t i = 0; i < mask.size(); i++) mask[i] = px[i * 4 + 3];
    }

    {
        Graphics g(mem);
        g.SetSmoothingMode(SmoothingModeAntiAlias);
        Profile* p = CurProfile();
        if (p) for (auto& b : p->btns) {
            RECT r = b.rc;
            RectF rf((REAL)r.left, (REAL)r.top, (REAL)(r.right - r.left), (REAL)(r.bottom - r.top));
            if (b.armed)        ButtonFace(g, rf, C_ARM,    Color(255, 230, 178,  84), Color(255, 236, 190, 110), rad);
            else if (b.latched) ButtonFace(g, rf, C_LATCH,  Color(255, 228, 133, 101), Color(255, 236, 148, 116), rad);
            else if (b.down)    ButtonFace(g, rf, C_BTN_DN, C_BTN_DN,                  Color(255,  92,  88,  82), rad);
            else                ButtonFace(g, rf, C_BTN,    C_BTN_TOP,                 C_BTN_EDGE, rad);
        }
        RectF sf((REAL)g_rcSettings.left, (REAL)g_rcSettings.top,
                 (REAL)(g_rcSettings.right - g_rcSettings.left),
                 (REAL)(g_rcSettings.bottom - g_rcSettings.top));
        RectF hf((REAL)g_rcHide.left, (REAL)g_rcHide.top,
                 (REAL)(g_rcHide.right - g_rcHide.left),
                 (REAL)(g_rcHide.bottom - g_rcHide.top));
        ButtonFace(g, sf, C_BTN, C_BTN_TOP, C_BTN_EDGE, rad);
        ButtonFace(g, hf, C_BTN, C_BTN_TOP, C_BTN_EDGE, rad);
        DrawGear(g, g_rcSettings, C_MUTED);
        DrawCross(g, g_rcHide, C_MUTED);
    }

    {
        Profile* p = CurProfile();
        if (p) {
            std::wstring title = p->name;
            if (g_needAdmin) title += L"  (!)";
            DrawLabel(mem, title, g_rcHeader, RGBof(g_needAdmin ? C_WARN : C_MUTED),
                      (int)(g_btnPx * 0.22), false);
            for (auto& b : p->btns) {
                bool dark = b.armed || b.latched;
                RECT tr = b.rc;
                InflateRect(&tr, -(int)(g_btnPx * 0.08), -(int)(g_btnPx * 0.06));
                DrawLabel(mem, b.label, tr, RGBof(dark ? C_TEXT_DK : C_TEXT),
                          (int)(g_btnPx * 0.30), dark || b.down);
            }
        }
    }

    unsigned char* px = (unsigned char*)bits;
    for (int i = 0; i < w * h; i++) {
        unsigned a = mask[i];
        px[3] = (unsigned char)a;
        if (a != 255) { px[0] = (unsigned char)(px[0] * a / 255);
                        px[1] = (unsigned char)(px[1] * a / 255);
                        px[2] = (unsigned char)(px[2] * a / 255); }
        px += 4;
    }

    POINT src{0, 0}, dst{wr.left, wr.top};
    SIZE  sz{w, h};
    BLENDFUNCTION bf{AC_SRC_OVER, 0, (BYTE)g_cfg.opacity, AC_SRC_ALPHA};
    UpdateLayeredWindow(g_panel, screen, &dst, &sz, mem, &src, 0, &bf, ULW_ALPHA);

    SelectObject(mem, old);
    DeleteDC(mem);
    DeleteObject(dib);
    ReleaseDC(nullptr, screen);
}

// ---- язычок и полоса вызова свайпом --------------------------------------
static void DrawSimple(HWND hwnd, const Color& fill, bool rounded) {
    RECT wr;
    GetWindowRect(hwnd, &wr);
    int w = wr.right - wr.left, h = wr.bottom - wr.top;
    if (w <= 0 || h <= 0) return;
    BITMAPINFO bi{};
    bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = w; bi.bmiHeader.biHeight = -h;
    bi.bmiHeader.biPlanes = 1; bi.bmiHeader.biBitCount = 32; bi.bmiHeader.biCompression = BI_RGB;
    void* bits = nullptr;
    HDC screen = GetDC(nullptr);
    HBITMAP dib = CreateDIBSection(screen, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
    if (!dib) { ReleaseDC(nullptr, screen); return; }
    HDC mem = CreateCompatibleDC(screen);
    HGDIOBJ old = SelectObject(mem, dib);
    memset(bits, 0, (size_t)w * h * 4);
    {
        Graphics g(mem);
        g.SetSmoothingMode(SmoothingModeAntiAlias);
        if (rounded) {
            REAL rad = (REAL)((w < h ? w : h) * 0.45);
            RoundRect_(g, fill, RectF(0, 0, (REAL)w, (REAL)h), rad);
            SolidBrush dots(C_MUTED);
            REAL cx = w / 2.0f, cy = h / 2.0f, s = (REAL)((w < h ? w : h) * 0.13);
            for (int i = -1; i <= 1; i++)
                g.FillEllipse(&dots, cx - s / 2, cy - s / 2 + i * s * 2.2f, s, s);
        } else {
            SolidBrush b(fill);
            g.FillRectangle(&b, 0, 0, w, h);
        }
    }
    unsigned char* px = (unsigned char*)bits;
    for (int i = 0; i < w * h; i++) {
        unsigned a = px[3];
        if (a != 255) { px[0] = (unsigned char)(px[0] * a / 255);
                        px[1] = (unsigned char)(px[1] * a / 255);
                        px[2] = (unsigned char)(px[2] * a / 255); }
        px += 4;
    }
    POINT src{0, 0}, dst{wr.left, wr.top};
    SIZE sz{w, h};
    BLENDFUNCTION bf{AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
    UpdateLayeredWindow(hwnd, screen, &dst, &sz, mem, &src, 0, &bf, ULW_ALPHA);
    SelectObject(mem, old);
    DeleteDC(mem);
    DeleteObject(dib);
    ReleaseDC(nullptr, screen);
}

static void PlaceHelpers() {
    RECT wa = WorkArea();
    bool vert = (g_cfg.edge == E_LEFT || g_cfg.edge == E_RIGHT);
    bool show = g_cfg.handle && !IsWindowVisible(g_panel);
    if (g_handle) {
        int th = MM2PX(5), len = MM2PX(20);
        int x, y, w, h;
        if (vert) { w = th; h = len; x = (g_cfg.edge == E_LEFT) ? wa.left : wa.right - th;
                    y = wa.top + (wa.bottom - wa.top - len) / 2; }
        else      { w = len; h = th; y = (g_cfg.edge == E_TOP) ? wa.top : wa.bottom - th;
                    x = wa.left + (wa.right - wa.left - len) / 2; }
        SetWindowPos(g_handle, HWND_TOPMOST, x, y, w, h, SWP_NOACTIVATE);
        ShowWindow(g_handle, show ? SW_SHOWNOACTIVATE : SW_HIDE);
        if (show) DrawSimple(g_handle, Color(150, 43, 42, 40), true);
    }
    if (g_edge) {
        bool sw = g_cfg.swipe && !IsWindowVisible(g_panel);
        int th = 6;
        int x, y, w, h;
        if (vert) { w = th; h = wa.bottom - wa.top; x = (g_cfg.edge == E_LEFT) ? wa.left : wa.right - th; y = wa.top; }
        else      { w = wa.right - wa.left; h = th; y = (g_cfg.edge == E_TOP) ? wa.top : wa.bottom - th; x = wa.left; }
        SetWindowPos(g_edge, HWND_TOPMOST, x, y, w, h, SWP_NOACTIVATE);
        ShowWindow(g_edge, sw ? SW_SHOWNOACTIVATE : SW_HIDE);
        if (sw) DrawSimple(g_edge, Color(8, 255, 255, 255), false);
    }
}

// ---- показать / спрятать -------------------------------------------------
bool PanelVisible() { return g_panel && IsWindowVisible(g_panel); }

void PanelShow(bool show) {
    if (!g_panel) return;
    if (show) {
        ShowWindow(g_panel, SW_SHOWNOACTIVATE);
        PanelLayout();
        if (g_main) SetTimer(g_main, TIMER_TICK, 30, nullptr);
    } else {
        ReleaseEverything();          // с залипшим Shift панель прятать нельзя
        AppBarRemove();
        ShowWindow(g_panel, SW_HIDE);
    }
    PlaceHelpers();
    Log(show ? L"панель показана" : L"панель убрана");
}

void PanelSetProfile(int idx) {
    if (idx < 0 || idx >= (int)g_cfg.profiles.size() || idx == g_profileIdx) return;
    ReleaseEverything();
    g_profileIdx = idx;
    Log(L"набор кнопок: %s", g_cfg.profiles[idx].name.c_str());
    if (PanelVisible()) PanelLayout();
}

// ---- касания -------------------------------------------------------------
static std::map<UINT32, int> g_ptr;      // указатель -> номер кнопки
static const int SYS_HEADER = -3, SYS_SETTINGS = -1, SYS_HIDE = -2;

static int HitTest(POINT pt) {
    Profile* p = CurProfile();
    if (p) for (int i = 0; i < (int)p->btns.size(); i++)
        if (PtInRect(&p->btns[i].rc, pt)) return i;
    if (PtInRect(&g_rcSettings, pt)) return SYS_SETTINGS;
    if (PtInRect(&g_rcHide, pt))     return SYS_HIDE;
    if (PtInRect(&g_rcHeader, pt))   return SYS_HEADER;
    return -100;
}

static void ProfileMenu() {
    // Меню открывается только по нажатию на название набора. Чтобы оно
    // закрывалось как положено, окно приходится сделать активным — фокус
    // возвращаем той программе, у которой он был.
    HWND prev = GetForegroundWindow();
    HMENU m = CreatePopupMenu();
    for (int i = 0; i < (int)g_cfg.profiles.size(); i++)
        AppendMenuW(m, MF_STRING | (i == g_profileIdx ? MF_CHECKED : 0), 1000 + i,
                    g_cfg.profiles[i].name.c_str());
    AppendMenuW(m, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(m, MF_STRING, 1, L"Настройки…");
    POINT pt;
    GetCursorPos(&pt);
    RECT wr;
    GetWindowRect(g_panel, &wr);
    pt.x = (g_cfg.edge == E_RIGHT) ? wr.left : wr.right;
    pt.y = wr.top + g_hdr;
    SetForegroundWindow(g_panel);
    int cmd = TrackPopupMenu(m, TPM_RETURNCMD | TPM_NONOTIFY |
                             (g_cfg.edge == E_RIGHT ? TPM_RIGHTALIGN : TPM_LEFTALIGN),
                             pt.x, pt.y, 0, g_panel, nullptr);
    DestroyMenu(m);
    if (prev) SetForegroundWindow(prev);
    if (cmd >= 1000) PanelSetProfile(cmd - 1000);
    else if (cmd == 1) SettingsOpen();
}

static void OnDown(UINT32 id, POINT client) {
    int idx = HitTest(client);
    if (idx == -100) return;
    // повтор и ожидание пера считаются по таймеру — заводим его сразу,
    // а не ждём до секунды общей проверки
    if (g_main) SetTimer(g_main, TIMER_TICK, 30, nullptr);
    g_ptr[id] = idx;
    if (idx >= 0) {
        Profile* p = CurProfile();
        if (p && idx < (int)p->btns.size()) {
            BtnPress(p->btns[idx]);
            PanelRedraw();
        }
    }
}

static void OnUp(UINT32 id, POINT client) {
    auto it = g_ptr.find(id);
    if (it == g_ptr.end()) return;
    int idx = it->second;
    g_ptr.erase(it);
    if (idx >= 0) {
        Profile* p = CurProfile();
        if (p && idx < (int)p->btns.size()) BtnRelease(p->btns[idx]);
        PanelRedraw();
        return;
    }
    if (HitTest(client) != idx) return;      // палец уехал с кнопки — не считаем
    if (idx == SYS_HIDE)     PanelShow(false);
    else if (idx == SYS_SETTINGS) SettingsOpen();
    else if (idx == SYS_HEADER)   ProfileMenu();
}

// ---- окна ----------------------------------------------------------------
static LRESULT CALLBACK PanelProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
        case WM_MOUSEACTIVATE:   return MA_NOACTIVATE;
        case WM_POINTERACTIVATE: return PA_NOACTIVATE;

        case WM_POINTERDOWN:
        case WM_POINTERUP:
        case WM_POINTERUPDATE: {
            POINT pt{GET_X_LPARAM(lp), GET_Y_LPARAM(lp)};   // экранные
            ScreenToClient(hwnd, &pt);
            UINT32 id = GET_POINTERID_WPARAM(wp);
            if (msg == WM_POINTERDOWN) OnDown(id, pt);
            else if (msg == WM_POINTERUP) OnUp(id, pt);
            return 0;
        }
        case WM_LBUTTONDOWN: OnDown(0xFFFF, POINT{GET_X_LPARAM(lp), GET_Y_LPARAM(lp)}); return 0;
        case WM_LBUTTONUP:   OnUp  (0xFFFF, POINT{GET_X_LPARAM(lp), GET_Y_LPARAM(lp)}); return 0;

        case WM_APPBARMSG:
            if (wp == ABN_POSCHANGED || wp == ABN_FULLSCREENAPP) PanelLayout();
            return 0;

        case WM_DISPLAYCHANGE:
        case WM_DPICHANGED:
            ScreenDPIReset();
            PanelLayout();
            PlaceHelpers();
            return 0;
        case WM_SETTINGCHANGE:
            if (GetTickCount() - g_abAt < 600) return 0;    // это мы сами и подвинули
            PanelLayout();
            PlaceHelpers();
            return 0;

        case WM_DESTROY:
            AppBarRemove();
            return 0;
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

// Полоса у самого края: ведём палец внутрь экрана — панель выезжает.
// У касания и пера окно само получает продолжение жеста, а мышь надо
// захватить: без этого движение уходит соседнему окну уже через шесть точек,
// и порог никогда не набирается — проверено, свайп мышью не срабатывал.
static LRESULT CALLBACK EdgeProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    static POINT start{};
    static bool tracking = false;
    switch (msg) {
        case WM_MOUSEACTIVATE:   return MA_NOACTIVATE;
        case WM_POINTERACTIVATE: return PA_NOACTIVATE;

        case WM_POINTERDOWN:
            start.x = GET_X_LPARAM(lp);
            start.y = GET_Y_LPARAM(lp);
            tracking = true;
            return 0;
        case WM_LBUTTONDOWN:
            GetCursorPos(&start);
            tracking = true;
            SetCapture(hwnd);
            return 0;

        case WM_POINTERUPDATE:
        case WM_MOUSEMOVE: {
            if (!tracking) return 0;
            POINT now{GET_X_LPARAM(lp), GET_Y_LPARAM(lp)};
            if (msg == WM_MOUSEMOVE) ClientToScreen(hwnd, &now);
            int need = MM2PX(6);
            int d = (g_cfg.edge == E_LEFT)  ? now.x - start.x
                  : (g_cfg.edge == E_RIGHT) ? start.x - now.x
                  : (g_cfg.edge == E_TOP)   ? now.y - start.y
                                            : start.y - now.y;
            if (d > need) {
                tracking = false;
                if (GetCapture() == hwnd) ReleaseCapture();
                PanelShow(true);
            }
            return 0;
        }

        case WM_POINTERUP:
        case WM_LBUTTONUP:
            tracking = false;
            if (GetCapture() == hwnd) ReleaseCapture();
            return 0;
        case WM_CAPTURECHANGED:
            tracking = false;
            return 0;
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

// язычок: нажатие показывает панель
static LRESULT CALLBACK HandleProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
        case WM_MOUSEACTIVATE:   return MA_NOACTIVATE;
        case WM_POINTERACTIVATE: return PA_NOACTIVATE;
        case WM_POINTERUP:
        case WM_LBUTTONUP:
            PanelShow(true);
            return 0;
        case WM_POINTERDOWN:
        case WM_LBUTTONDOWN:
            return 0;
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

bool PanelCreate() {
    WNDCLASSEXW wc{sizeof(WNDCLASSEXW)};
    wc.hInstance     = g_inst;
    wc.hCursor       = LoadCursor(nullptr, IDC_ARROW);
    wc.lpfnWndProc   = PanelProc;
    wc.lpszClassName = L"PenBarPanel";
    RegisterClassExW(&wc);
    wc.lpfnWndProc   = EdgeProc;
    wc.lpszClassName = L"PenBarEdge";
    RegisterClassExW(&wc);
    wc.lpfnWndProc   = HandleProc;
    wc.lpszClassName = L"PenBarHandle";
    RegisterClassExW(&wc);

    DWORD ex = WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_LAYERED | WS_EX_NOACTIVATE;
    g_panel = CreateWindowExW(ex, L"PenBarPanel", L"Пульт", WS_POPUP,
                              0, 0, 100, 100, nullptr, nullptr, g_inst, nullptr);
    g_edge = CreateWindowExW(ex, L"PenBarEdge", L"", WS_POPUP,
                             0, 0, 10, 10, nullptr, nullptr, g_inst, nullptr);
    g_handle = CreateWindowExW(ex, L"PenBarHandle", L"", WS_POPUP,
                               0, 0, 10, 10, nullptr, nullptr, g_inst, nullptr);
    if (!g_panel || !g_edge || !g_handle) { Log(L"не удалось создать окна панели"); return false; }
    PlaceHelpers();
    return true;
}

// вызывается по таймеру из главного окна
void PanelTick() {
    POINT cur;
    GetCursorPos(&cur);
    bool onPanel = false;
    if (PanelVisible()) {
        RECT r;
        GetWindowRect(g_panel, &r);
        onPanel = PtInRect(&r, cur) != 0;
    }
    DWORD now = GetTickCount();
    bool redraw = false;
    Profile* p = CurProfile();
    if (p) for (auto& b : p->btns) {
        bool wasArmed = b.armed;
        BtnTick(b, now, cur, onPanel);
        if (wasArmed != b.armed) redraw = true;
    }
    if (redraw) PanelRedraw();
}

void PanelHelpersUpdate() { PlaceHelpers(); }

void PanelFit(int& fitRows, double& realMM) { fitRows = g_fitRows; realMM = g_realMM; }
