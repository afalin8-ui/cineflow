#include "app.h"
#include <shlobj.h>
#include <stdio.h>
#include <stdarg.h>

// ---- строки --------------------------------------------------------------
std::string W2U(const std::wstring& s) {
    if (s.empty()) return {};
    int n = WideCharToMultiByte(CP_UTF8, 0, s.c_str(), (int)s.size(), nullptr, 0, nullptr, nullptr);
    std::string out(n, 0);
    WideCharToMultiByte(CP_UTF8, 0, s.c_str(), (int)s.size(), &out[0], n, nullptr, nullptr);
    return out;
}
std::wstring U2W(const std::string& s) {
    if (s.empty()) return {};
    int n = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.size(), nullptr, 0);
    std::wstring out(n, 0);
    MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.size(), &out[0], n);
    return out;
}
std::wstring LowerW(const std::wstring& s) {
    std::wstring o = s;
    for (auto& c : o) c = (wchar_t)towlower(c);
    return o;
}
std::wstring TrimW(const std::wstring& s) {
    size_t a = s.find_first_not_of(L" \t\r\n");
    if (a == std::wstring::npos) return L"";
    size_t b = s.find_last_not_of(L" \t\r\n");
    return s.substr(a, b - a + 1);
}

// ---- где лежат наши файлы -------------------------------------------------
// Сначала пробуем папку рядом с программой (её удобно носить на флешке).
// Если писать туда нельзя (например, программу положили в Program Files) —
// уходим в %APPDATA%. Молча остаться без настроек нельзя.
std::wstring ExeDir() {
    wchar_t buf[MAX_PATH] = {0};
    GetModuleFileNameW(nullptr, buf, MAX_PATH);
    std::wstring p = buf;
    size_t i = p.find_last_of(L"\\/");
    return (i == std::wstring::npos) ? L"." : p.substr(0, i);
}

static std::wstring g_dataDir;
std::wstring DataDir() {
    if (!g_dataDir.empty()) return g_dataDir;
    std::wstring dir = ExeDir();
    std::wstring probe = dir + L"\\.penbar-write-test";
    HANDLE h = CreateFileW(probe.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
                           FILE_ATTRIBUTE_TEMPORARY | FILE_FLAG_DELETE_ON_CLOSE, nullptr);
    if (h != INVALID_HANDLE_VALUE) { CloseHandle(h); g_dataDir = dir; return g_dataDir; }

    wchar_t* app = nullptr;
    if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_RoamingAppData, 0, nullptr, &app)) && app) {
        g_dataDir = std::wstring(app) + L"\\PenBar";
        CoTaskMemFree(app);
        CreateDirectoryW(g_dataDir.c_str(), nullptr);
    } else {
        g_dataDir = dir;
    }
    return g_dataDir;
}

std::wstring ConfigPath() { return DataDir() + L"\\penbar.json"; }
std::wstring LogPath()    { return DataDir() + L"\\penbar.log";  }

// ---- журнал --------------------------------------------------------------
// Нужен не для красоты: программу проверяет человек на своём планшете,
// а не я — без журнала любая жалоба останется «просто не работает».
static CRITICAL_SECTION g_logCs;
static bool g_logReady = false;

void LogInit() {
    InitializeCriticalSection(&g_logCs);
    g_logReady = true;
    // если журнал разросся — начинаем заново
    WIN32_FILE_ATTRIBUTE_DATA fa{};
    if (GetFileAttributesExW(LogPath().c_str(), GetFileExInfoStandard, &fa)) {
        if (fa.nFileSizeLow > 512 * 1024) DeleteFileW(LogPath().c_str());
    }
    Log(L"--- запуск ---");
}

void Log(const wchar_t* fmt, ...) {
    if (!g_logReady) return;
    wchar_t buf[2048];
    va_list ap;
    va_start(ap, fmt);
    _vsnwprintf(buf, 2040, fmt, ap);
    va_end(ap);
    buf[2040] = 0;

    SYSTEMTIME st;
    GetLocalTime(&st);
    wchar_t line[2200];
    _snwprintf(line, 2190, L"%02d:%02d:%02d.%03d  %s\r\n",
               st.wHour, st.wMinute, st.wSecond, st.wMilliseconds, buf);

    EnterCriticalSection(&g_logCs);
    HANDLE h = CreateFileW(LogPath().c_str(), FILE_APPEND_DATA, FILE_SHARE_READ, nullptr,
                           OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h != INVALID_HANDLE_VALUE) {
        std::string u = W2U(line);
        DWORD wr = 0;
        WriteFile(h, u.data(), (DWORD)u.size(), &wr, nullptr);
        CloseHandle(h);
    }
    LeaveCriticalSection(&g_logCs);
}

// ---- сколько точек экрана в миллиметре ------------------------------------
// Кнопка задаётся в миллиметрах, а не в точках: 11 мм под палец — это про
// физический размер, а точки на разных экранах разного размера. Настоящий
// размер экрана Windows напрямую не сообщает, поэтому читаем EDID монитора
// (там он записан заводом). Не вышло — прикидываем, и человек может
// поправить число в настройках по банковской карте.
static bool EdidSize(int wantW, int wantH, int& mmW, int& pxW) {
    HKEY hDisplay;
    if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, L"SYSTEM\\CurrentControlSet\\Enum\\DISPLAY",
                      0, KEY_READ, &hDisplay) != ERROR_SUCCESS) return false;
    bool found = false, any = false;
    int anyMM = 0, anyPX = 0;

    for (DWORD i = 0; !found; i++) {
        wchar_t mfg[256];
        DWORD mfgLen = 256;
        if (RegEnumKeyExW(hDisplay, i, mfg, &mfgLen, nullptr, nullptr, nullptr, nullptr) != ERROR_SUCCESS) break;
        HKEY hMfg;
        if (RegOpenKeyExW(hDisplay, mfg, 0, KEY_READ, &hMfg) != ERROR_SUCCESS) continue;

        for (DWORD j = 0; !found; j++) {
            wchar_t inst[256];
            DWORD instLen = 256;
            if (RegEnumKeyExW(hMfg, j, inst, &instLen, nullptr, nullptr, nullptr, nullptr) != ERROR_SUCCESS) break;
            std::wstring sub = std::wstring(inst) + L"\\Device Parameters";
            HKEY hDev;
            if (RegOpenKeyExW(hMfg, sub.c_str(), 0, KEY_READ, &hDev) != ERROR_SUCCESS) continue;

            BYTE edid[512];
            DWORD sz = sizeof(edid), type = 0;
            if (RegQueryValueExW(hDev, L"EDID", nullptr, &type, edid, &sz) == ERROR_SUCCESS && sz >= 128) {
                const BYTE* d = edid + 54;                       // подробное описание режима
                int hAct = ((d[4] >> 4) << 8) | d[2];
                int vAct = ((d[7] >> 4) << 8) | d[5];
                int hMM  = ((d[14] >> 4) << 8) | d[12];
                if (hMM < 40) hMM = edid[21] * 10;                // запасной вариант: сантиметры
                if (hAct > 200 && hMM > 40) {
                    if (!any) { any = true; anyMM = hMM; anyPX = hAct; }
                    if ((hAct == wantW && vAct == wantH) || (hAct == wantH && vAct == wantW)) {
                        mmW = hMM; pxW = hAct; found = true;
                    }
                }
            }
            RegCloseKey(hDev);
        }
        RegCloseKey(hMfg);
    }
    RegCloseKey(hDisplay);
    if (!found && any) { mmW = anyMM; pxW = anyPX; return true; }
    return found;
}

// Масштаб интерфейса Windows на главном экране (96 = 100%). Спрашиваем
// у монитора, а не у системы: системное значение меняется только после
// перезахода, а масштаб крутят на ходу.
UINT MonitorDPI() {
    HMONITOR mon = MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY);
    if (HMODULE sh = LoadLibraryW(L"shcore.dll")) {
        typedef HRESULT (WINAPI *F)(HMONITOR, int, UINT*, UINT*);
        if (auto f = (F)GetProcAddress(sh, "GetDpiForMonitor")) {
            UINT dx = 0, dy = 0;
            if (SUCCEEDED(f(mon, 0 /*MDT_EFFECTIVE_DPI*/, &dx, &dy)) && dx >= 72) {
                FreeLibrary(sh);
                return dx;
            }
        }
        FreeLibrary(sh);
    }
    UINT dpi = 96;
    HDC dc = GetDC(nullptr);
    if (dc) { dpi = GetDeviceCaps(dc, LOGPIXELSX); ReleaseDC(nullptr, dc); }
    return dpi < 72 ? 96 : dpi;
}

static double g_dpiCache = 0;

// Разрешение экрана и масштаб меняются на ходу: подключили монитор, повернули
// планшет, покрутили масштаб. Всё, что считалось от плотности, надо считать
// заново, иначе кнопки останутся размером от прошлого экрана.
void ScreenDPIReset() {
    g_dpiCache = 0;
    Log(L"плотность экрана пересчитывается заново");
}

double ScreenDPI() {
    if (g_cfg.screenDPI > 40) return g_cfg.screenDPI;
    double& cached = g_dpiCache;
    if (cached > 0) return cached;

    HMONITOR mon = MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY);
    MONITORINFO mi{sizeof(MONITORINFO)};
    GetMonitorInfoW(mon, &mi);
    int pw = mi.rcMonitor.right - mi.rcMonitor.left;
    int ph = mi.rcMonitor.bottom - mi.rcMonitor.top;

    int mmW = 0, pxW = 0;
    if (EdidSize(pw, ph, mmW, pxW) && mmW > 40) {
        cached = pxW * 25.4 / mmW;
        Log(L"размер экрана из EDID: %d точек / %d мм -> %.0f точек на дюйм", pxW, mmW, cached);
    }
    if (cached < 80 || cached > 500) {
        // Прикидка: у планшетов Windows ставит масштаб «на глаз», и настоящая
        // плотность обычно процентов на 18 выше объявленной.
        cached = MonitorDPI() * 1.18;
        if (cached < 96) cached = 96;
        Log(L"размер экрана определить не удалось, берём %.0f точек на дюйм", cached);
    }
    return cached;
}

int MM2PX(double mm) {
    int v = (int)(mm * ScreenDPI() / 25.4 + 0.5);
    return v < 8 ? 8 : v;
}

// ---- права --------------------------------------------------------------
bool IsElevated() {
    HANDLE tok = nullptr;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &tok)) return false;
    TOKEN_ELEVATION te{};
    DWORD len = 0;
    bool r = GetTokenInformation(tok, TokenElevation, &te, sizeof(te), &len) && te.TokenIsElevated;
    CloseHandle(tok);
    return r;
}

static bool ProcElevated(DWORD pid, bool& unknown) {
    unknown = false;
    HANDLE p = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!p) { unknown = true; return true; }        // не пустили — почти наверняка от админа
    HANDLE tok = nullptr;
    bool r = false;
    if (OpenProcessToken(p, TOKEN_QUERY, &tok)) {
        TOKEN_ELEVATION te{};
        DWORD len = 0;
        if (GetTokenInformation(tok, TokenElevation, &te, sizeof(te), &len)) r = te.TokenIsElevated != 0;
        CloseHandle(tok);
    } else unknown = true;
    CloseHandle(p);
    return r;
}

std::wstring ForegroundExe() {
    HWND h = GetForegroundWindow();
    if (!h) return L"";
    DWORD pid = 0;
    GetWindowThreadProcessId(h, &pid);
    if (!pid) return L"";
    HANDLE p = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!p) return L"";
    wchar_t buf[MAX_PATH] = {0};
    DWORD sz = MAX_PATH;
    std::wstring name;
    if (QueryFullProcessImageNameW(p, 0, buf, &sz)) {
        std::wstring full = buf;
        size_t i = full.find_last_of(L"\\/");
        name = (i == std::wstring::npos) ? full : full.substr(i + 1);
    }
    CloseHandle(p);
    return LowerW(name);
}

bool ForegroundIsElevated() {
    HWND h = GetForegroundWindow();
    if (!h) return false;
    DWORD pid = 0;
    GetWindowThreadProcessId(h, &pid);
    if (!pid) return false;
    bool unknown = false;
    return ProcElevated(pid, unknown);
}

void RestartAsAdmin() {
    wchar_t exe[MAX_PATH] = {0};
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    SHELLEXECUTEINFOW si{sizeof(SHELLEXECUTEINFOW)};
    si.lpVerb = L"runas";
    si.lpFile = exe;
    si.nShow  = SW_SHOWNORMAL;
    if (ShellExecuteExW(&si)) {
        Log(L"перезапуск с правами администратора");
        PostQuitMessage(0);
    }
}

// ---- автозапуск ----------------------------------------------------------
static const wchar_t* RUN_KEY = L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";

void SetAutostart(bool on) {
    HKEY k;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, RUN_KEY, 0, KEY_SET_VALUE, &k) != ERROR_SUCCESS) return;
    if (on) {
        wchar_t exe[MAX_PATH] = {0};
        GetModuleFileNameW(nullptr, exe, MAX_PATH);
        std::wstring v = std::wstring(L"\"") + exe + L"\"";
        RegSetValueExW(k, L"PenBar", 0, REG_SZ, (const BYTE*)v.c_str(),
                       (DWORD)((v.size() + 1) * sizeof(wchar_t)));
    } else {
        RegDeleteValueW(k, L"PenBar");
    }
    RegCloseKey(k);
}

bool GetAutostart() {
    HKEY k;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, RUN_KEY, 0, KEY_READ, &k) != ERROR_SUCCESS) return false;
    wchar_t buf[600];
    DWORD sz = sizeof(buf), type = 0;
    bool r = RegQueryValueExW(k, L"PenBar", nullptr, &type, (BYTE*)buf, &sz) == ERROR_SUCCESS;
    RegCloseKey(k);
    return r;
}
