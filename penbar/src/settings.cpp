#include "app.h"
#include <commctrl.h>
#include <shellapi.h>
#include <vector>

// Окно настроек — обычное окно с обычными полями Windows. Своё рисование
// здесь не нужно и вредно: только настоящее поле ввода поднимает на планшете
// экранную клавиатуру, а без неё подпись кнопке не напечатать.

static HWND g_wnd = nullptr, g_tabs = nullptr;
static HFONT g_font = nullptr, g_fontB = nullptr;
static double g_sc = 1.0;
static int  g_tab = 0;
static int  g_prof = 0, g_btn = 0;
static bool g_capturing = false;
static bool g_fill = false;          // идёт заполнение полей — не реагируем на события
static HHOOK g_kbHook = nullptr;
static std::wstring g_prevExe;

enum {
    ID_TABS = 50,
    // вкладка «Кнопки»
    ID_PROFS = 100, ID_PROF_ADD, ID_PROF_DEL, ID_PROF_NAME, ID_PROF_MATCH, ID_PROF_DETECT,
    ID_BTNS, ID_BTN_ADD, ID_BTN_DEL, ID_BTN_UP, ID_BTN_DOWN,
    ID_LABEL, ID_KEYS, ID_CAPTURE, ID_MOUSE, ID_MODE, ID_REPEAT,
    // вкладка «Вид»
    ID_EDGE = 200, ID_ALIGN, ID_MM, ID_MM_MINUS, ID_MM_PLUS, ID_OPACITY,
    ID_PUSH, ID_SWIPE, ID_HANDLE, ID_AUTOSTART, ID_SHOWSTART,
    ID_DPI, ID_DPI_MINUS, ID_DPI_PLUS, ID_DPI_AUTO,
    // вкладка «Проверка»
    ID_DIAG = 300, ID_DIAG_COPY, ID_DIAG_REFRESH, ID_LOG, ID_ADMIN, ID_RESET,
    ID_CLOSE = 390
};

struct Ctl { HWND h; int tab; };
static std::vector<Ctl> g_ctls;

static int  S(double v) { return (int)(v * g_sc + 0.5); }
static Profile* Prof() {
    if (g_prof < 0 || g_prof >= (int)g_cfg.profiles.size()) return nullptr;
    return &g_cfg.profiles[g_prof];
}
static Btn* CurBtn() {
    Profile* p = Prof();
    if (!p || g_btn < 0 || g_btn >= (int)p->btns.size()) return nullptr;
    return &p->btns[g_btn];
}

static HWND Add(const wchar_t* cls, const wchar_t* text, DWORD style,
                int x, int y, int w, int h, int id, int tab, DWORD ex = 0) {
    HWND c = CreateWindowExW(ex, cls, text, WS_CHILD | style,
                             S(x), S(y), S(w), S(h), g_wnd, (HMENU)(INT_PTR)id, g_inst, nullptr);
    SendMessageW(c, WM_SETFONT, (WPARAM)g_font, TRUE);
    g_ctls.push_back({c, tab});
    return c;
}
static HWND C(int id) { return GetDlgItem(g_wnd, id); }

static void ShowTab(int t) {
    g_tab = t;
    for (auto& c : g_ctls) ShowWindow(c.h, (c.tab < 0 || c.tab == t) ? SW_SHOW : SW_HIDE);
    InvalidateRect(g_wnd, nullptr, TRUE);
}

// ---- перенос данных в поля и обратно -------------------------------------
static void FillButtonList() {
    g_fill = true;
    HWND lb = C(ID_BTNS);
    SendMessageW(lb, LB_RESETCONTENT, 0, 0);
    Profile* p = Prof();
    if (p) for (auto& b : p->btns) {
        std::wstring s = b.label;
        for (auto& ch : s) if (ch == L'\n') ch = L' ';
        s += L"   —   ";
        if (!b.keys.empty()) s += b.keys;
        if (b.mouse == PB_LEFT)  s += L" ЛКМ";
        if (b.mouse == PB_RIGHT) s += L" ПКМ";
        if (b.mouse == PB_MID)   s += L" СКМ";
        if (b.mouse == PB_WUP)   s += L" колесо ↑";
        if (b.mouse == PB_WDN)   s += L" колесо ↓";
        if (b.mode == M_HOLD)  s += L" (держать)";
        if (b.mode == M_LATCH) s += L" (залипает)";
        if (b.repeat)          s += L" (повтор)";
        SendMessageW(lb, LB_ADDSTRING, 0, (LPARAM)s.c_str());
    }
    SendMessageW(lb, LB_SETCURSEL, g_btn, 0);
    g_fill = false;
}

static void FillButtonFields() {
    g_fill = true;
    Btn* b = CurBtn();
    SetWindowTextW(C(ID_LABEL), b ? b->label.c_str() : L"");
    SetWindowTextW(C(ID_KEYS),  b ? b->keys.c_str()  : L"");
    SendMessageW(C(ID_MOUSE), CB_SETCURSEL, b ? b->mouse : 0, 0);
    SendMessageW(C(ID_MODE),  CB_SETCURSEL, b ? b->mode  : 0, 0);
    SendMessageW(C(ID_REPEAT), BM_SETCHECK, (b && b->repeat) ? BST_CHECKED : BST_UNCHECKED, 0);
    for (int id = ID_LABEL; id <= ID_REPEAT; id++) EnableWindow(C(id), b != nullptr);
    g_fill = false;
}

static void FillProfileList() {
    g_fill = true;
    HWND lb = C(ID_PROFS);
    SendMessageW(lb, LB_RESETCONTENT, 0, 0);
    for (auto& p : g_cfg.profiles)
        SendMessageW(lb, LB_ADDSTRING, 0, (LPARAM)p.name.c_str());
    SendMessageW(lb, LB_SETCURSEL, g_prof, 0);
    Profile* p = Prof();
    SetWindowTextW(C(ID_PROF_NAME),  p ? p->name.c_str()  : L"");
    SetWindowTextW(C(ID_PROF_MATCH), p ? p->match.c_str() : L"");
    g_fill = false;
    FillButtonList();
    FillButtonFields();
}

static void FillView() {
    g_fill = true;
    SendMessageW(C(ID_EDGE),  CB_SETCURSEL, g_cfg.edge, 0);
    SendMessageW(C(ID_ALIGN), CB_SETCURSEL, g_cfg.align, 0);
    wchar_t b[64];
    swprintf(b, 64, L"%.1f", g_cfg.buttonMM);
    SetWindowTextW(C(ID_MM), b);
    SendMessageW(C(ID_OPACITY), TBM_SETPOS, TRUE, g_cfg.opacity);
    SendMessageW(C(ID_PUSH),      BM_SETCHECK, g_cfg.pushWindows ? BST_CHECKED : BST_UNCHECKED, 0);
    SendMessageW(C(ID_SWIPE),     BM_SETCHECK, g_cfg.swipe       ? BST_CHECKED : BST_UNCHECKED, 0);
    SendMessageW(C(ID_HANDLE),    BM_SETCHECK, g_cfg.handle      ? BST_CHECKED : BST_UNCHECKED, 0);
    SendMessageW(C(ID_SHOWSTART), BM_SETCHECK, g_cfg.showOnStart ? BST_CHECKED : BST_UNCHECKED, 0);
    SendMessageW(C(ID_AUTOSTART), BM_SETCHECK, GetAutostart()    ? BST_CHECKED : BST_UNCHECKED, 0);
    swprintf(b, 64, L"%.0f", ScreenDPI());
    SetWindowTextW(C(ID_DPI), b);
    g_fill = false;
    InvalidateRect(g_wnd, nullptr, TRUE);
}

static std::wstring NumW(double v, int dec = 0) {
    wchar_t b[64];
    swprintf(b, 64, dec ? L"%.1f" : L"%.0f", v);
    return b;
}

// Собираем текст сложением строк, а не через printf. У mingw «%s» в широком
// printf означает УЗКУЮ строку, и такая строчка роняет программу целиком —
// на этом уже один раз попались, повторять незачем.
static std::wstring DiagText() {
    wchar_t exe[MAX_PATH] = {0};
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    HMONITOR mon = MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY);
    MONITORINFO mi{sizeof(MONITORINFO)};
    GetMonitorInfoW(mon, &mi);
    int dig = GetSystemMetrics(SM_DIGITIZER);
    std::wstring t;
    t += L"Пульт 1.0\r\n";
    t += L"Программа: "; t += exe; t += L"\r\n";
    t += L"Настройки: "; t += ConfigPath(); t += L"\r\n";
    t += L"Журнал: ";    t += LogPath();    t += L"\r\n\r\n";
    t += L"Права: ";
    t += IsElevated() ? L"администратора"
                      : L"обычные (программы, запущенные от имени администратора, нажатий не примут)";
    t += L"\r\n";
    t += L"Экран: " + NumW(mi.rcMonitor.right - mi.rcMonitor.left) + L"x" +
         NumW(mi.rcMonitor.bottom - mi.rcMonitor.top) +
         L", рабочая область " + NumW(mi.rcWork.right - mi.rcWork.left) + L"x" +
         NumW(mi.rcWork.bottom - mi.rcWork.top) + L"\r\n";
    t += L"Плотность экрана: " + NumW(ScreenDPI()) + L" точек на дюйм (";
    t += g_cfg.screenDPI > 40 ? L"задано вручную" : L"определено само";
    t += L")\r\n";
    int fitRows = 0; double realMM = 0;
    PanelFit(fitRows, realMM);
    t += L"Кнопка: " + NumW(g_cfg.buttonMM, 1) + L" мм = " + NumW(MM2PX(g_cfg.buttonMM)) + L" точек";
    if (realMM > 0 && realMM < g_cfg.buttonMM - 0.05)
        t += L"  (не влезали, ужаты до " + NumW(realMM, 1) + L" мм)";
    t += L"\r\n";
    if (fitRows > 0)
        t += L"По высоте края помещается кнопок: " + NumW(fitRows) + L"\r\n";
    t += L"Перо: ";   t += (dig & NID_INTEGRATED_PEN)   ? L"есть" : L"нет";
    t += L", сенсор: "; t += (dig & NID_INTEGRATED_TOUCH) ? L"есть" : L"нет";
    t += L", до " + NumW(GetSystemMetrics(SM_MAXIMUMTOUCHES)) + L" касаний\r\n";
    t += L"Набор кнопок сейчас: ";
    t += CurProfile() ? CurProfile()->name : std::wstring(L"—");
    t += L"\r\n";
    t += L"Панель: "; t += PanelVisible() ? L"показана" : L"убрана";
    t += L", край "; t += NumW(g_cfg.edge);
    t += L", сдвигает окна: "; t += g_cfg.pushWindows ? L"да" : L"нет";
    t += L"\r\n";
    t += L"Была впереди программа: " + (g_prevExe.empty() ? std::wstring(L"—") : g_prevExe);
    return t;
}

static void FillDiag() { SetWindowTextW(C(ID_DIAG), DiagText().c_str()); }

// ---- захват сочетания с клавиатуры ---------------------------------------
static LRESULT CALLBACK KbProc(int code, WPARAM wp, LPARAM lp) {
    if (code == HC_ACTION && g_capturing && (wp == WM_KEYDOWN || wp == WM_SYSKEYDOWN)) {
        KBDLLHOOKSTRUCT* k = (KBDLLHOOKSTRUCT*)lp;
        WORD vk = (WORD)k->vkCode;
        bool isMod = (vk == VK_LCONTROL || vk == VK_RCONTROL || vk == VK_CONTROL ||
                      vk == VK_LSHIFT || vk == VK_RSHIFT || vk == VK_SHIFT ||
                      vk == VK_LMENU || vk == VK_RMENU || vk == VK_MENU ||
                      vk == VK_LWIN || vk == VK_RWIN);
        if (!isMod) {
            std::vector<WORD> v;
            if (GetAsyncKeyState(VK_CONTROL) & 0x8000) v.push_back(VK_CONTROL);
            if (GetAsyncKeyState(VK_SHIFT)   & 0x8000) v.push_back(VK_SHIFT);
            if (GetAsyncKeyState(VK_MENU)    & 0x8000) v.push_back(VK_MENU);
            v.push_back(vk);
            std::wstring s = LowerW(ComboText(v));
            SetWindowTextW(C(ID_KEYS), s.c_str());
            g_capturing = false;
            SetWindowTextW(C(ID_CAPTURE), L"Захватить с клавиатуры");
            if (g_kbHook) { UnhookWindowsHookEx(g_kbHook); g_kbHook = nullptr; }
            return 1;                        // это нажатие никуда дальше не идёт
        }
    }
    return CallNextHookEx(nullptr, code, wp, lp);
}

// ---- изменения ------------------------------------------------------------
static void ApplyLive() {
    if (PanelVisible()) PanelLayout();
    else PanelHelpersUpdate();
}

static std::wstring GetText(int id) {
    wchar_t buf[512] = {0};
    GetWindowTextW(C(id), buf, 511);
    return buf;
}

static void OnCommand(int id, int code) {
    if (g_fill) return;
    Profile* p = Prof();
    Btn* b = CurBtn();
    switch (id) {
        case ID_PROFS:
            if (code == LBN_SELCHANGE) {
                g_prof = (int)SendMessageW(C(ID_PROFS), LB_GETCURSEL, 0, 0);
                g_btn = 0;
                FillProfileList();
            }
            return;
        case ID_BTNS:
            if (code == LBN_SELCHANGE) {
                g_btn = (int)SendMessageW(C(ID_BTNS), LB_GETCURSEL, 0, 0);
                FillButtonFields();
            }
            return;
        case ID_PROF_NAME:
            if (code == EN_CHANGE && p) { p->name = GetText(ID_PROF_NAME); FillProfileList(); ApplyLive(); }
            return;
        case ID_PROF_MATCH:
            if (code == EN_CHANGE && p) p->match = GetText(ID_PROF_MATCH);
            return;
        case ID_PROF_DETECT: {
            // имя программы, которая была впереди до открытия настроек
            extern std::wstring SettingsPrevExe();
            std::wstring exe = SettingsPrevExe();
            if (!exe.empty() && p) { p->match = exe; SetWindowTextW(C(ID_PROF_MATCH), exe.c_str()); }
            return;
        }
        case ID_PROF_ADD: {
            Profile np;
            np.name = L"Новый набор";
            g_cfg.profiles.insert(g_cfg.profiles.begin() + (p ? g_prof + 1 : 0), np);
            g_prof = p ? g_prof + 1 : 0;
            g_btn = 0;
            FillProfileList();
            return;
        }
        case ID_PROF_DEL:
            if (p && g_cfg.profiles.size() > 1 &&
                MessageBoxW(g_wnd, (L"Удалить набор «" + p->name + L"»?").c_str(),
                            L"Пульт", MB_YESNO | MB_ICONQUESTION) == IDYES) {
                g_cfg.profiles.erase(g_cfg.profiles.begin() + g_prof);
                if (g_prof >= (int)g_cfg.profiles.size()) g_prof = (int)g_cfg.profiles.size() - 1;
                g_btn = 0;
                FillProfileList();
                ApplyLive();
            }
            return;
        case ID_BTN_ADD:
            if (p) {
                Btn nb;
                nb.label = L"Новая";
                p->btns.insert(p->btns.begin() + (p->btns.empty() ? 0 : g_btn + 1), nb);
                if (!p->btns.empty() && p->btns.size() > 1) g_btn++;
                FillButtonList();
                FillButtonFields();
                ApplyLive();
            }
            return;
        case ID_BTN_DEL:
            if (p && b) {
                p->btns.erase(p->btns.begin() + g_btn);
                if (g_btn >= (int)p->btns.size()) g_btn = (int)p->btns.size() - 1;
                FillButtonList();
                FillButtonFields();
                ApplyLive();
            }
            return;
        case ID_BTN_UP:
            if (p && b && g_btn > 0) {
                std::swap(p->btns[g_btn], p->btns[g_btn - 1]);
                g_btn--;
                FillButtonList();
                ApplyLive();
            }
            return;
        case ID_BTN_DOWN:
            if (p && b && g_btn + 1 < (int)p->btns.size()) {
                std::swap(p->btns[g_btn], p->btns[g_btn + 1]);
                g_btn++;
                FillButtonList();
                ApplyLive();
            }
            return;
        case ID_LABEL:
            if (code == EN_CHANGE && b) { b->label = GetText(ID_LABEL); FillButtonList(); ApplyLive(); }
            return;
        case ID_KEYS:
            if (code == EN_CHANGE && b) { b->keys = GetText(ID_KEYS); BtnCompile(*b); FillButtonList(); }
            return;
        case ID_CAPTURE:
            if (!g_capturing) {
                g_capturing = true;
                SetWindowTextW(C(ID_CAPTURE), L"Нажмите сочетание…");
                g_kbHook = SetWindowsHookExW(WH_KEYBOARD_LL, KbProc, g_inst, 0);
            } else {
                g_capturing = false;
                SetWindowTextW(C(ID_CAPTURE), L"Захватить с клавиатуры");
                if (g_kbHook) { UnhookWindowsHookEx(g_kbHook); g_kbHook = nullptr; }
            }
            return;
        case ID_MOUSE:
            if (code == CBN_SELCHANGE && b) { b->mouse = (int)SendMessageW(C(ID_MOUSE), CB_GETCURSEL, 0, 0); FillButtonList(); }
            return;
        case ID_MODE:
            if (code == CBN_SELCHANGE && b) { b->mode = (int)SendMessageW(C(ID_MODE), CB_GETCURSEL, 0, 0); FillButtonList(); }
            return;
        case ID_REPEAT:
            if (b) { b->repeat = SendMessageW(C(ID_REPEAT), BM_GETCHECK, 0, 0) == BST_CHECKED; FillButtonList(); }
            return;

        case ID_EDGE:
            if (code == CBN_SELCHANGE) { g_cfg.edge = (int)SendMessageW(C(ID_EDGE), CB_GETCURSEL, 0, 0); ApplyLive(); }
            return;
        case ID_ALIGN:
            if (code == CBN_SELCHANGE) { g_cfg.align = (int)SendMessageW(C(ID_ALIGN), CB_GETCURSEL, 0, 0); ApplyLive(); }
            return;
        case ID_MM:
            if (code == EN_CHANGE) {
                double v = _wtof(GetText(ID_MM).c_str());
                if (v >= 6 && v <= 40) { g_cfg.buttonMM = v; ApplyLive(); }
            }
            return;
        case ID_MM_MINUS:
        case ID_MM_PLUS: {
            g_cfg.buttonMM += (id == ID_MM_PLUS ? 0.5 : -0.5);
            if (g_cfg.buttonMM < 6) g_cfg.buttonMM = 6;
            if (g_cfg.buttonMM > 40) g_cfg.buttonMM = 40;
            FillView();
            ApplyLive();
            return;
        }
        case ID_PUSH:
            g_cfg.pushWindows = SendMessageW(C(ID_PUSH), BM_GETCHECK, 0, 0) == BST_CHECKED;
            if (PanelVisible()) { PanelShow(false); PanelShow(true); }
            return;
        case ID_SWIPE:
            g_cfg.swipe = SendMessageW(C(ID_SWIPE), BM_GETCHECK, 0, 0) == BST_CHECKED;
            PanelHelpersUpdate();
            return;
        case ID_HANDLE:
            g_cfg.handle = SendMessageW(C(ID_HANDLE), BM_GETCHECK, 0, 0) == BST_CHECKED;
            PanelHelpersUpdate();
            return;
        case ID_SHOWSTART:
            g_cfg.showOnStart = SendMessageW(C(ID_SHOWSTART), BM_GETCHECK, 0, 0) == BST_CHECKED;
            return;
        case ID_AUTOSTART:
            SetAutostart(SendMessageW(C(ID_AUTOSTART), BM_GETCHECK, 0, 0) == BST_CHECKED);
            return;
        case ID_DPI:
            if (code == EN_CHANGE) {
                double v = _wtof(GetText(ID_DPI).c_str());
                if (v >= 60 && v <= 600) { g_cfg.screenDPI = v; ApplyLive(); InvalidateRect(g_wnd, nullptr, TRUE); }
            }
            return;
        case ID_DPI_MINUS:
        case ID_DPI_PLUS: {
            double v = ScreenDPI() + (id == ID_DPI_PLUS ? 4 : -4);
            g_cfg.screenDPI = v < 60 ? 60 : (v > 600 ? 600 : v);
            FillView();
            ApplyLive();
            return;
        }
        case ID_DPI_AUTO:
            g_cfg.screenDPI = 0;
            FillView();
            ApplyLive();
            return;

        case ID_DIAG_REFRESH: FillDiag(); return;
        case ID_DIAG_COPY: {
            std::wstring t = DiagText();
            if (OpenClipboard(g_wnd)) {
                EmptyClipboard();
                HGLOBAL h = GlobalAlloc(GMEM_MOVEABLE, (t.size() + 1) * sizeof(wchar_t));
                if (h) {
                    memcpy(GlobalLock(h), t.c_str(), (t.size() + 1) * sizeof(wchar_t));
                    GlobalUnlock(h);
                    SetClipboardData(CF_UNICODETEXT, h);
                }
                CloseClipboard();
            }
            return;
        }
        case ID_LOG:   ShellExecuteW(nullptr, L"open", LogPath().c_str(), nullptr, nullptr, SW_SHOW); return;
        case ID_ADMIN: RestartAsAdmin(); return;
        case ID_RESET:
            if (MessageBoxW(g_wnd, L"Вернуть все наборы кнопок и настройки к заводским?\n"
                                   L"Ваши изменения пропадут.",
                            L"Пульт", MB_YESNO | MB_ICONWARNING) == IDYES) {
                ConfigDefaults();
                ConfigSave();
                g_prof = g_btn = 0;
                FillProfileList();
                FillView();
                ApplyLive();
            }
            return;
        case ID_CLOSE: DestroyWindow(g_wnd); return;
    }
}

// ---- окно ----------------------------------------------------------------
static LRESULT CALLBACK SetProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
        case WM_COMMAND:
            OnCommand(LOWORD(wp), HIWORD(wp));
            return 0;
        case WM_HSCROLL:
            if ((HWND)lp == C(ID_OPACITY)) {
                g_cfg.opacity = (int)SendMessageW(C(ID_OPACITY), TBM_GETPOS, 0, 0);
                PanelRedraw();
            }
            return 0;
        case WM_NOTIFY: {
            NMHDR* n = (NMHDR*)lp;
            if (n->idFrom == ID_TABS && n->code == TCN_SELCHANGE) {
                ShowTab((int)SendMessageW(g_tabs, TCM_GETCURSEL, 0, 0));
                if (g_tab == 2) FillDiag();
            }
            return 0;
        }
        case WM_CTLCOLORSTATIC:
        case WM_CTLCOLORBTN:
            SetBkMode((HDC)wp, TRANSPARENT);
            return (LRESULT)GetSysColorBrush(COLOR_WINDOW);
        case WM_ERASEBKGND: {
            RECT r;
            GetClientRect(hwnd, &r);
            FillRect((HDC)wp, &r, GetSysColorBrush(COLOR_WINDOW));
            return 1;
        }
        case WM_PAINT: {
            PAINTSTRUCT ps;
            HDC dc = BeginPaint(hwnd, &ps);
            if (g_tab == 1) {
                // Линейка для проверки размера: ширина банковской карты 85,6 мм.
                // Если нарисованная полоска совпала с картой, миллиметры честные.
                int w = (int)(85.6 * ScreenDPI() / 25.4);
                int x = S(30), y = S(470);
                RECT r{x, y, x + w, y + S(26)};
                HBRUSH br = CreateSolidBrush(RGB(217, 119, 87));
                FillRect(dc, &r, br);
                DeleteObject(br);
                SetBkMode(dc, TRANSPARENT);
                HGDIOBJ of = SelectObject(dc, g_font);
                const wchar_t* hint = L"Приложите к полоске банковскую карту: она должна совпасть по ширине.";
                TextOutW(dc, x, y + S(30), hint, lstrlenW(hint));
                SelectObject(dc, of);
            }
            EndPaint(hwnd, &ps);
            return 0;
        }
        case WM_DPICHANGED: {
            // Масштаб сменился — пересобираем окно целиком. Так надёжнее, чем
            // пересчитывать полсотни полей по одному, а случается это редко.
            int tab = g_tab, prof = g_prof, btn = g_btn;
            DestroyWindow(hwnd);
            SettingsOpen();
            g_prof = prof; g_btn = btn;
            FillProfileList();
            if (g_tabs) SendMessageW(g_tabs, TCM_SETCURSEL, tab, 0);
            ShowTab(tab);
            return 0;
        }
        case WM_CLOSE:
            DestroyWindow(hwnd);
            return 0;
        case WM_DESTROY:
            if (g_kbHook) { UnhookWindowsHookEx(g_kbHook); g_kbHook = nullptr; }
            g_capturing = false;
            ConfigSave();
            ApplyLive();
            g_ctls.clear();
            g_wnd = nullptr;
            return 0;
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

std::wstring SettingsPrevExe() { return g_prevExe; }
bool SettingsIsOpen() { return g_wnd != nullptr; }
HWND SettingsHwnd()   { return g_wnd; }

void SettingsOpen() {
    if (g_wnd) { SetForegroundWindow(g_wnd); return; }
    Log(L"настройки: открываю");
    g_prevExe = ForegroundExe();

    INITCOMMONCONTROLSEX icc{sizeof(icc), ICC_TAB_CLASSES | ICC_BAR_CLASSES | ICC_STANDARD_CLASSES};
    InitCommonControlsEx(&icc);

    static bool reg = false;
    if (!reg) {
        WNDCLASSEXW wc{sizeof(WNDCLASSEXW)};
        wc.hInstance     = g_inst;
        wc.lpfnWndProc   = SetProc;
        wc.hCursor       = LoadCursor(nullptr, IDC_ARROW);
        wc.hbrBackground = GetSysColorBrush(COLOR_WINDOW);
        wc.lpszClassName = L"PenBarSettings";
        wc.hIcon         = LoadIconW(g_inst, MAKEINTRESOURCEW(101));
        RegisterClassExW(&wc);
        reg = true;
    }

    // размер окна: по плотности экрана, но не больше рабочей области
    HMONITOR mon = MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY);
    MONITORINFO mi{sizeof(MONITORINFO)};
    GetMonitorInfoW(mon, &mi);
    int wa_w = mi.rcWork.right - mi.rcWork.left, wa_h = mi.rcWork.bottom - mi.rcWork.top;
    UINT dpi = MonitorDPI();
    if (dpi < 96) dpi = 96;
    g_sc = dpi / 96.0;
    const int BASE_W = 900, BASE_H = 600;
    double fitW = wa_w * 0.96 / BASE_W, fitH = wa_h * 0.94 / BASE_H;
    if (g_sc > fitW) g_sc = fitW;
    if (g_sc > fitH) g_sc = fitH;
    if (g_sc < 0.8)  g_sc = 0.8;

    LOGFONTW lf{};
    lf.lfHeight  = -S(15);
    lf.lfWeight  = FW_NORMAL;
    lf.lfQuality = CLEARTYPE_QUALITY;      // обычное окно, прозрачности нет
    wcscpy(lf.lfFaceName, UiFace());
    g_font = CreateFontIndirectW(&lf);
    lf.lfWeight = FW_BOLD;
    g_fontB = CreateFontIndirectW(&lf);

    int w = S(BASE_W), h = S(BASE_H);
    RECT r{0, 0, w, h};
    AdjustWindowRect(&r, WS_OVERLAPPEDWINDOW, FALSE);
    g_wnd = CreateWindowExW(0, L"PenBarSettings", L"Пульт — настройки",
                            WS_OVERLAPPEDWINDOW & ~WS_MAXIMIZEBOX,
                            mi.rcWork.left + (wa_w - (r.right - r.left)) / 2,
                            mi.rcWork.top + (wa_h - (r.bottom - r.top)) / 2,
                            r.right - r.left, r.bottom - r.top,
                            nullptr, nullptr, g_inst, nullptr);
    if (!g_wnd) { Log(L"настройки: окно не создалось (%u)", GetLastError()); return; }
    g_ctls.clear();
    Log(L"настройки: окно создано, масштаб %.2f", g_sc);

    g_tabs = CreateWindowExW(0, WC_TABCONTROLW, L"", WS_CHILD | WS_VISIBLE,
                             S(8), S(8), S(BASE_W - 16), S(40), g_wnd, (HMENU)ID_TABS, g_inst, nullptr);
    SendMessageW(g_tabs, WM_SETFONT, (WPARAM)g_font, TRUE);
    TCITEMW ti{};
    ti.mask = TCIF_TEXT;
    const wchar_t* tabs[] = {L"  Кнопки  ", L"  Вид и поведение  ", L"  Проверка  "};
    for (int i = 0; i < 3; i++) { ti.pszText = (LPWSTR)tabs[i]; SendMessageW(g_tabs, TCM_INSERTITEMW, i, (LPARAM)&ti); }

    const DWORD LBS = WS_VISIBLE | WS_BORDER | WS_VSCROLL | LBS_NOTIFY;
    const DWORD EDS = WS_BORDER | ES_AUTOHSCROLL;
    int T = 62;                                  // верх области под вкладками

    // ---- вкладка «Кнопки» ----
    Add(L"STATIC", L"Наборы кнопок", WS_VISIBLE, 14, T, 200, 22, -1, 0);
    Add(L"LISTBOX", L"", LBS, 14, T + 26, 200, 300, ID_PROFS, 0);
    Add(L"BUTTON", L"+ набор", WS_VISIBLE, 14, T + 332, 96, 34, ID_PROF_ADD, 0);
    Add(L"BUTTON", L"Удалить",  WS_VISIBLE, 118, T + 332, 96, 34, ID_PROF_DEL, 0);
    Add(L"STATIC", L"Название", WS_VISIBLE, 14, T + 376, 200, 20, -1, 0);
    Add(L"EDIT", L"", EDS | WS_VISIBLE, 14, T + 398, 200, 30, ID_PROF_NAME, 0);
    Add(L"STATIC", L"Программа (exe, через ;)", WS_VISIBLE, 14, T + 434, 200, 20, -1, 0);
    Add(L"EDIT", L"", EDS | WS_VISIBLE, 14, T + 456, 200, 30, ID_PROF_MATCH, 0);
    Add(L"BUTTON", L"Взять из активной", WS_VISIBLE, 14, T + 492, 200, 32, ID_PROF_DETECT, 0);

    Add(L"STATIC", L"Кнопки набора (сверху вниз)", WS_VISIBLE, 230, T, 380, 22, -1, 0);
    Add(L"LISTBOX", L"", LBS, 230, T + 26, 380, 380, ID_BTNS, 0);
    Add(L"BUTTON", L"+ кнопка", WS_VISIBLE, 230, T + 412, 92, 34, ID_BTN_ADD, 0);
    Add(L"BUTTON", L"Удалить", WS_VISIBLE, 328, T + 412, 92, 34, ID_BTN_DEL, 0);
    Add(L"BUTTON", L"↑ выше",  WS_VISIBLE, 426, T + 412, 88, 34, ID_BTN_UP, 0);
    Add(L"BUTTON", L"↓ ниже",  WS_VISIBLE, 520, T + 412, 90, 34, ID_BTN_DOWN, 0);

    Add(L"STATIC", L"Подпись (длинная сама встанет в две строки)",
        WS_VISIBLE, 626, T, 260, 40, -1, 0);
    Add(L"EDIT", L"", EDS | WS_VISIBLE, 626, T + 44, 260, 30, ID_LABEL, 0);
    Add(L"STATIC", L"Клавиши", WS_VISIBLE, 626, T + 84, 260, 20, -1, 0);
    Add(L"EDIT", L"", EDS | WS_VISIBLE, 626, T + 106, 260, 30, ID_KEYS, 0);
    Add(L"BUTTON", L"Захватить с клавиатуры", WS_VISIBLE, 626, T + 142, 260, 34, ID_CAPTURE, 0);
    Add(L"STATIC", L"Например: ctrl+z, shift, space, f12, num1, [", WS_VISIBLE, 626, T + 180, 260, 40, -1, 0);
    Add(L"STATIC", L"Кнопка мыши", WS_VISIBLE, 626, T + 226, 260, 20, -1, 0);
    Add(L"COMBOBOX", L"", WS_VISIBLE | CBS_DROPDOWNLIST | WS_VSCROLL, 626, T + 248, 260, 200, ID_MOUSE, 0);
    Add(L"STATIC", L"Как нажимать", WS_VISIBLE, 626, T + 290, 260, 20, -1, 0);
    Add(L"COMBOBOX", L"", WS_VISIBLE | CBS_DROPDOWNLIST | WS_VSCROLL, 626, T + 312, 260, 200, ID_MODE, 0);
    Add(L"BUTTON", L"Повторять, пока нажата", WS_VISIBLE | BS_AUTOCHECKBOX, 626, T + 356, 260, 30, ID_REPEAT, 0);
    Add(L"STATIC",
        L"«Разовое» — нажать и отпустить.\n"
        L"«Держать» — пока палец на кнопке (WASD).\n"
        L"«Залипает» — до второго нажатия: Shift, или средняя кнопка мыши, чтобы "
        L"нажать и вести пером.",
        WS_VISIBLE, 626, T + 392, 260, 110, -1, 0);

    const wchar_t* mice[] = {L"нет", L"левая", L"правая", L"средняя", L"колесо вверх", L"колесо вниз"};
    for (auto m : mice) SendMessageW(C(ID_MOUSE), CB_ADDSTRING, 0, (LPARAM)m);
    const wchar_t* modes[] = {L"разовое нажатие", L"держать, пока палец на кнопке", L"залипает до второго нажатия"};
    for (auto m : modes) SendMessageW(C(ID_MODE), CB_ADDSTRING, 0, (LPARAM)m);

    // ---- вкладка «Вид и поведение» ----
    Add(L"STATIC", L"Край экрана", WS_VISIBLE, 30, T + 10, 220, 22, -1, 1);
    Add(L"COMBOBOX", L"", WS_VISIBLE | CBS_DROPDOWNLIST | WS_VSCROLL, 30, T + 34, 220, 200, ID_EDGE, 1);
    Add(L"STATIC", L"Где вдоль края", WS_VISIBLE, 270, T + 10, 220, 22, -1, 1);
    Add(L"COMBOBOX", L"", WS_VISIBLE | CBS_DROPDOWNLIST | WS_VSCROLL, 270, T + 34, 220, 200, ID_ALIGN, 1);
    const wchar_t* edges[] = {L"слева", L"справа", L"сверху", L"снизу"};
    for (auto e : edges) SendMessageW(C(ID_EDGE), CB_ADDSTRING, 0, (LPARAM)e);
    const wchar_t* aligns[] = {L"в начале", L"посередине", L"в конце"};
    for (auto a : aligns) SendMessageW(C(ID_ALIGN), CB_ADDSTRING, 0, (LPARAM)a);

    Add(L"STATIC", L"Размер кнопки, мм", WS_VISIBLE, 30, T + 84, 220, 22, -1, 1);
    Add(L"EDIT", L"", EDS | WS_VISIBLE, 30, T + 108, 90, 32, ID_MM, 1);
    Add(L"BUTTON", L"−", WS_VISIBLE, 126, T + 108, 44, 32, ID_MM_MINUS, 1);
    Add(L"BUTTON", L"+", WS_VISIBLE, 176, T + 108, 44, 32, ID_MM_PLUS, 1);
    Add(L"STATIC", L"Прозрачность", WS_VISIBLE, 270, T + 84, 220, 22, -1, 1);
    Add(TRACKBAR_CLASSW, L"", WS_VISIBLE | TBS_HORZ, 270, T + 108, 220, 34, ID_OPACITY, 1);
    SendMessageW(C(ID_OPACITY), TBM_SETRANGE, TRUE, MAKELPARAM(100, 255));

    Add(L"BUTTON", L"Сдвигать окна, а не перекрывать их", WS_VISIBLE | BS_AUTOCHECKBOX, 30, T + 156, 460, 30, ID_PUSH, 1);
    Add(L"BUTTON", L"Вызывать проведением от края экрана",  WS_VISIBLE | BS_AUTOCHECKBOX, 30, T + 190, 460, 30, ID_SWIPE, 1);
    Add(L"BUTTON", L"Показывать язычок у края",             WS_VISIBLE | BS_AUTOCHECKBOX, 30, T + 224, 460, 30, ID_HANDLE, 1);
    Add(L"BUTTON", L"Показывать панель сразу при запуске",   WS_VISIBLE | BS_AUTOCHECKBOX, 30, T + 258, 460, 30, ID_SHOWSTART, 1);
    Add(L"BUTTON", L"Запускать вместе с Windows",            WS_VISIBLE | BS_AUTOCHECKBOX, 30, T + 292, 460, 30, ID_AUTOSTART, 1);

    Add(L"STATIC", L"Точек на дюйм экрана (от этого зависят миллиметры)", WS_VISIBLE, 30, T + 336, 460, 22, -1, 1);
    Add(L"EDIT", L"", EDS | WS_VISIBLE, 30, T + 360, 90, 32, ID_DPI, 1);
    Add(L"BUTTON", L"−", WS_VISIBLE, 126, T + 360, 44, 32, ID_DPI_MINUS, 1);
    Add(L"BUTTON", L"+", WS_VISIBLE, 176, T + 360, 44, 32, ID_DPI_PLUS, 1);
    Add(L"BUTTON", L"Определить самим", WS_VISIBLE, 226, T + 360, 180, 32, ID_DPI_AUTO, 1);

    // ---- вкладка «Проверка» ----
    // Обычная надпись, а не поле ввода: текст отсюда всё равно копируют кнопкой,
    // а многострочное поле — лишний тяжёлый элемент ради того же самого.
    Add(L"STATIC", L"", WS_VISIBLE | SS_LEFT, 30, T + 10, 840, 330, ID_DIAG, 2);
    Add(L"BUTTON", L"Скопировать", WS_VISIBLE, 30, T + 352, 180, 36, ID_DIAG_COPY, 2);
    Add(L"BUTTON", L"Обновить", WS_VISIBLE, 220, T + 352, 150, 36, ID_DIAG_REFRESH, 2);
    Add(L"BUTTON", L"Открыть журнал", WS_VISIBLE, 380, T + 352, 200, 36, ID_LOG, 2);
    Add(L"BUTTON", L"Права администратора", WS_VISIBLE, 590, T + 352, 280, 36, ID_ADMIN, 2);
    Add(L"BUTTON", L"Вернуть заводские настройки", WS_VISIBLE, 30, T + 398, 340, 36, ID_RESET, 2);

    // кнопка «Закрыть» видна на всех вкладках
    HWND cl = Add(L"BUTTON", L"Закрыть", WS_VISIBLE, BASE_W - 150, BASE_H - 48, 130, 38, ID_CLOSE, -1);
    (void)cl;

    FillProfileList();
    FillView();
    FillDiag();
    ShowTab(0);
    ShowWindow(g_wnd, SW_SHOW);
    SetForegroundWindow(g_wnd);
}
