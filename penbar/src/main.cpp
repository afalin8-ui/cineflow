#include "app.h"
#include <gdiplus.h>
#include <shellapi.h>
#include "resource.h"

HINSTANCE g_inst = nullptr;
HWND      g_main = nullptr;

static ULONG_PTR g_gdip = 0;
static NOTIFYICONDATAW g_ni{};
static HWINEVENTHOOK g_hook = nullptr;
static std::wstring g_lastExe;
static UINT WM_PENBAR_SHOW = 0;

// ---- какой набор кнопок подходит программе -------------------------------
static int MatchProfile(const std::wstring& exe) {
    int fallback = -1;
    for (int i = 0; i < (int)g_cfg.profiles.size(); i++) {
        std::wstring m = LowerW(g_cfg.profiles[i].match);
        if (TrimW(m).empty()) { if (fallback < 0) fallback = i; continue; }
        size_t pos = 0;
        while (pos <= m.size()) {
            size_t e = m.find(L';', pos);
            if (e == std::wstring::npos) e = m.size();
            std::wstring one = TrimW(m.substr(pos, e - pos));
            if (!one.empty() && one == exe) return i;
            pos = e + 1;
        }
    }
    return fallback >= 0 ? fallback : 0;
}

static void CheckForeground(bool force) {
    std::wstring exe = ForegroundExe();
    if (exe.empty()) return;
    if (exe == L"penbar.exe") return;                 // наше же окно настроек
    if (!force && exe == g_lastExe) return;
    g_lastExe = exe;
    PanelSetProfile(MatchProfile(exe));
    PanelSetNeedAdmin(!IsElevated() && ForegroundIsElevated());
}

static void CALLBACK WinEventProc(HWINEVENTHOOK, DWORD, HWND, LONG, LONG, DWORD, DWORD) {
    PostMessageW(g_main, WM_PROFILECH, 0, 0);
}

// ---- значок в трее -------------------------------------------------------
static void TrayAdd() {
    g_ni.cbSize = sizeof(g_ni);
    g_ni.hWnd   = g_main;
    g_ni.uID    = 1;
    g_ni.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
    g_ni.uCallbackMessage = WM_TRAYICON;
    g_ni.hIcon  = (HICON)LoadImageW(g_inst, MAKEINTRESOURCEW(IDI_APP), IMAGE_ICON,
                                    GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON), 0);
    if (!g_ni.hIcon) g_ni.hIcon = LoadIcon(nullptr, IDI_APPLICATION);
    wcscpy(g_ni.szTip, L"Пульт — экранные кнопки");
    Shell_NotifyIconW(NIM_ADD, &g_ni);
}

static void TrayMenu() {
    HWND prev = GetForegroundWindow();
    HMENU m = CreatePopupMenu();
    AppendMenuW(m, MF_STRING, 10, PanelVisible() ? L"Убрать панель" : L"Показать панель");
    HMENU sub = CreatePopupMenu();
    for (int i = 0; i < (int)g_cfg.profiles.size(); i++)
        AppendMenuW(sub, MF_STRING | (i == PanelProfile() ? MF_CHECKED : 0), 1000 + i,
                    g_cfg.profiles[i].name.c_str());
    AppendMenuW(m, MF_POPUP, (UINT_PTR)sub, L"Набор кнопок");
    AppendMenuW(m, MF_STRING, 11, L"Настройки…");
    AppendMenuW(m, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(m, MF_STRING, 12, L"Отпустить все клавиши");
    if (!IsElevated()) AppendMenuW(m, MF_STRING, 13, L"Перезапустить с правами администратора");
    AppendMenuW(m, MF_STRING, 14, L"Открыть журнал");
    AppendMenuW(m, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(m, MF_STRING, 15, L"Выход");

    POINT pt;
    GetCursorPos(&pt);
    SetForegroundWindow(g_main);
    int cmd = TrackPopupMenu(m, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON,
                             pt.x, pt.y, 0, g_main, nullptr);
    DestroyMenu(m);
    if (prev) SetForegroundWindow(prev);

    if (cmd >= 1000) { PanelSetProfile(cmd - 1000); return; }
    switch (cmd) {
        case 10: PanelShow(!PanelVisible()); break;
        case 11: SettingsOpen(); break;
        case 12: ReleaseEverything(); PanelRedraw(); break;
        case 13: RestartAsAdmin(); break;
        case 14: ShellExecuteW(nullptr, L"open", LogPath().c_str(), nullptr, nullptr, SW_SHOW); break;
        case 15: PostMessageW(g_main, WM_CLOSE, 0, 0); break;
    }
}

// ---- главное (невидимое) окно --------------------------------------------
static LRESULT CALLBACK MainProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    if (msg == WM_PENBAR_SHOW && WM_PENBAR_SHOW) { PanelShow(true); return 0; }
    switch (msg) {
        case WM_TRAYICON:
            if (LOWORD(lp) == WM_LBUTTONUP)      PanelShow(!PanelVisible());
            else if (LOWORD(lp) == WM_RBUTTONUP) TrayMenu();
            return 0;

        case WM_PROFILECH:
            CheckForeground(false);
            return 0;

        case WM_TIMER:
            if (wp == TIMER_TICK) {
                PanelTick();
                if (!PanelVisible() && !AnyHeld()) KillTimer(hwnd, TIMER_TICK);
            } else if (wp == TIMER_FG) {
                CheckForeground(false);
                if (PanelVisible()) {
                    // держим панель поверх: полноэкранные окна и другие
                    // «поверх всех» иначе накрывают её
                    SetWindowPos(g_panel, HWND_TOPMOST, 0, 0, 0, 0,
                                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
                    SetTimer(hwnd, TIMER_TICK, 30, nullptr);
                }
            }
            return 0;

        case WM_DISPLAYCHANGE:
        case WM_DPICHANGED:
            ScreenDPIReset();
            PanelLayout();
            PanelHelpersUpdate();
            return 0;

        case WM_QUERYENDSESSION:
            ConfigSave();
            ReleaseEverything();
            return TRUE;

        case WM_CLOSE:
            DestroyWindow(hwnd);
            return 0;

        case WM_DESTROY:
            ReleaseEverything();
            Shell_NotifyIconW(NIM_DELETE, &g_ni);
            PostQuitMessage(0);
            return 0;
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

// ---- запуск --------------------------------------------------------------
int WINAPI wWinMain(HINSTANCE inst, HINSTANCE, PWSTR, int) {
    g_inst = inst;
    WM_PENBAR_SHOW = RegisterWindowMessageW(L"PenBarShowPanel");

    // одна программа за раз: второй запуск просто показывает панель
    HANDLE once = CreateMutexW(nullptr, FALSE, L"PenBarSingleInstance");
    if (once && GetLastError() == ERROR_ALREADY_EXISTS) {
        PostMessageW(HWND_BROADCAST, WM_PENBAR_SHOW, 0, 0);
        return 0;
    }

    // Разметку считаем в настоящих точках экрана, поэтому просим у Windows
    // не масштабировать нас за нас.
    typedef BOOL (WINAPI *SetCtxFn)(DPI_AWARENESS_CONTEXT);
    if (HMODULE u = GetModuleHandleW(L"user32.dll")) {
        if (auto fn = (SetCtxFn)GetProcAddress(u, "SetProcessDpiAwarenessContext"))
            fn(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
        else SetProcessDPIAware();
    }

    LogInit();
    Gdiplus::GdiplusStartupInput gsi;
    Gdiplus::GdiplusStartup(&g_gdip, &gsi, nullptr);

    bool firstRun = false;
    if (!ConfigLoad()) {
        ConfigDefaults();
        firstRun = true;
        ConfigSave();
        Log(L"первый запуск, файл настроек создан: %s", ConfigPath().c_str());
    }
    g_cfg.autostart = GetAutostart();
    Log(L"экран: %.0f точек на дюйм, кнопка %.1f мм = %d точек",
        ScreenDPI(), g_cfg.buttonMM, MM2PX(g_cfg.buttonMM));

    WNDCLASSEXW wc{sizeof(WNDCLASSEXW)};
    wc.hInstance     = inst;
    wc.lpfnWndProc   = MainProc;
    wc.lpszClassName = L"PenBarMain";
    RegisterClassExW(&wc);
    g_main = CreateWindowExW(WS_EX_TOOLWINDOW, L"PenBarMain", L"Пульт", WS_POPUP,
                             0, 0, 0, 0, nullptr, nullptr, inst, nullptr);
    if (!g_main) return 1;

    if (!PanelCreate()) return 1;
    TrayAdd();

    g_hook = SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, nullptr,
                             WinEventProc, 0, 0, WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);
    CheckForeground(true);
    SetTimer(g_main, TIMER_FG, 1000, nullptr);

    if (g_cfg.showOnStart) PanelShow(true);
    else PanelHelpersUpdate();

    if (firstRun) {
        MessageBoxW(nullptr,
            L"Панель с кнопками появилась у края экрана.\n\n"
            L"• Убрать её — крестик на самой панели.\n"
            L"• Вернуть — провести пальцем от края экрана или нажать язычок.\n"
            L"• Настройки — шестерёнка на панели или значок в трее (у часов).\n\n"
            L"Набор кнопок сам меняется под программу, которая сейчас впереди.",
            L"Пульт — экранные кнопки", MB_OK | MB_ICONINFORMATION);
    }

    MSG msg;
    while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
        // Tab и стрелки в окне настроек: адресуем ИМЕННО его окно.
        // GetActiveWindow() здесь возвращал бы ноль, когда впереди чужая
        // программа, а IsDialogMessage с нулём — это падение.
        HWND sw = SettingsHwnd();
        if (sw && (msg.hwnd == sw || IsChild(sw, msg.hwnd)) && IsDialogMessageW(sw, &msg)) continue;
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }

    if (g_hook) UnhookWinEvent(g_hook);
    ReleaseEverything();
    ConfigSave();
    if (g_gdip) Gdiplus::GdiplusShutdown(g_gdip);
    Log(L"--- выход ---");
    return 0;
}
