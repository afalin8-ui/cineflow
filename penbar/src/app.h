// Пульт — экранные кнопки для планшета на Windows.
// Общие типы и объявления. Правила, от которых зависит работоспособность,
// описаны в README рядом; здесь только короткие пометки.
#pragma once
#define WINVER       0x0A00
#define _WIN32_WINNT 0x0A00
#include <windows.h>
#include <string>
#include <vector>

// ---- журнал --------------------------------------------------------------
void         LogInit();
void         Log(const wchar_t* fmt, ...);
std::wstring LogPath();

// ---- строки --------------------------------------------------------------
std::string  W2U(const std::wstring& s);
std::wstring U2W(const std::string& s);
std::wstring LowerW(const std::wstring& s);
std::wstring TrimW(const std::wstring& s);

// ---- настройки -----------------------------------------------------------
enum Mode  { M_TAP = 0, M_HOLD = 1, M_LATCH = 2 };
// Вид клетки на полоске. Обычная кнопка — K_KEY; остальные три это ЗОНЫ:
// по ним не стучат, по ним ВЕДУТ пальцем или пером.
enum Kind  { K_KEY = 0, K_PAD, K_JOY, K_WHEEL, K_STICK };
enum MBtn  { PB_NONE = 0, PB_LEFT, PB_RIGHT, PB_MID, PB_WUP, PB_WDN };
enum Edge  { E_LEFT = 0, E_RIGHT, E_TOP, E_BOTTOM };
enum Align { A_START = 0, A_CENTER, A_END };

struct Btn {
    std::wstring label;          // подпись на кнопке
    std::wstring keys;           // "ctrl+shift+z", может быть пустым
    std::wstring keys2;          // долгое нажатие (>= 600 мс), может быть пустым
    int   mouse  = PB_NONE;      // кнопка мыши или колесо
    int   mode   = M_TAP;        // разовое / держать / залипает
    int   kind   = K_KEY;        // кнопка или зона (обзор / джойстик / крутилка)
    int   span   = 1;            // сколько клеток полоски занимает (у зон больше одной)
    bool  repeat = false;        // повтор при удержании
    std::wstring page;           // после нажатия открыть страницу; "-" = вернуться
    std::vector<WORD> vks;       // разобранное сочетание (считается один раз)
    std::vector<WORD> vks2;      // то же для долгого нажатия
    WORD  joyVk[4] = {0, 0, 0, 0};   // джойстик: вперёд, влево, назад, вправо

    // состояние во время работы (в файл не пишется)
    bool  latched = false;       // залипло
    bool  armed   = false;       // ждём, когда перо уйдёт с панели
    bool  down    = false;       // палец на кнопке
    bool  longDone = false;      // долгое нажатие уже сработало
    DWORD downAt  = 0;           // когда нажали (для долгого нажатия)
    DWORD toggleAt = 0;          // когда залипание последний раз переключали
    DWORD repAt   = 0;           // время следующего повтора
    int   joyMask = 0;           // какие стороны джойстика сейчас зажаты
    bool  padDown = false;       // площадка держит свою кнопку мыши
    double joyX = 0, joyY = 0;   // где ручка джойстика, -1..1 (для рисования)
    RECT  rc{};                  // место кнопки в окне панели
};

// Страница — второй ряд кнопок внутри набора. Заведена ради Blender: там
// после G, R и S выбирают ось, и класть на полоску все девять сочетаний
// (сдвиг по X, по Y, по Z, поворот по X…) значит забить её одними осями.
// Кнопка «Сдвиг» сама открывает страницу с осями — ровно как в Blender,
// где после G нажимают X.
struct Page {
    std::wstring name;
    std::vector<Btn> btns;
};

struct Profile {
    std::wstring name;           // "DaVinci Resolve"
    std::wstring match;          // "resolve.exe;fusion.exe" — пусто = общий
    std::vector<Btn> btns;       // основная страница
    std::vector<Page> pages;     // дополнительные страницы
};

struct Config {
    int    edge        = E_LEFT;
    int    align       = A_CENTER;
    double buttonMM    = 11.5;
    int    opacity     = 232;    // 0..255
    bool   pushWindows = true;   // сдвигать окна, а не перекрывать
    bool   swipe       = true;   // вызов свайпом от края
    bool   handle      = true;   // язычок у края
    bool   autostart   = false;
    bool   showOnStart = true;
    bool   penCam      = true;   // вести камеру пером по всему экрану
    double screenDPI   = 0;      // 0 = определить самим
    std::vector<Profile> profiles;
};

extern Config g_cfg;

void         ConfigDefaults();
bool         ConfigLoad();
bool         ConfigSave();
std::wstring ConfigPath();
std::wstring ExeDir();

// ---- клавиши и нажатия ---------------------------------------------------
bool         ParseKeys(const std::wstring& s, std::vector<WORD>& out);
std::wstring KeyName(WORD vk);
std::wstring ComboText(const std::vector<WORD>& vks);
void         SendCombo(const std::vector<WORD>& vks, bool down);
void         SendComboTap(const std::vector<WORD>& vks);
void         SendMouseBtn(int mb, bool down);
void         SendMouseMove(int dx, int dy);      // относительное движение указателя
bool         MouseHeld(int mb);                  // эта кнопка мыши сейчас зажата нами?
void         SendMouseClick(int mb);
void         SendWheel(int mb);
void         ReleaseEverything();       // отпустить всё зажатое (страховка)

// действия кнопок панели
void  BtnCompile(Btn& b);          // разобрать текст сочетания в коды
void  BtnPress(Btn& b);
void  BtnRelease(Btn& b);
void  BtnTick(Btn& b, DWORD now, const POINT& cur, bool cursorOnPanel);
bool  AnyHeld();                        // есть ли залипшее/зажатое
void  JoyMove(Btn& b, double nx, double ny);   // ручка джойстика, -1..1; центр = отпустить
void  JoyOff(Btn& b);                          // убрали палец с джойстика
void  FlushArmed();                            // дожать то, что ждало ухода пера

// ---- окно, которым мы управляем -----------------------------------------
// Синтетическое нажатие мыши достаётся окну ПОД УКАЗАТЕЛЕМ, а перо в этот
// момент стоит на панели. Поэтому помним последнее чужое активное окно и
// последнюю точку указателя внутри него — это и есть якорь.
void  TargetRemember(HWND w);
HWND  TargetWindow();
void  TargetSeen(const POINT& cur);     // указатель внутри цели — запомнить якорь
bool  CursorInTarget(const POINT& cur);
void  CursorToTarget();                 // переставить указатель в якорь, если он не в цели
void  TargetFocus();                    // вернуть цели передний план, если он ушёл
void  TargetGuard();                    // цель ушла надолго — отпустить всё зажатое

// ---- перо вместо мыши ----------------------------------------------------
// Unreal не принимает ввод пера ВООБЩЕ: ни нажатий, ни движения (проверено —
// даже родной правый щелчок боковой кнопкой пера в Windows работает, а в нём
// нет). Зато синтетическую мышь он принимает как настоящую. Отсюда мост:
// пока мы держим кнопку мыши, движение пера переводится в движение мыши.
void  PenBridgeTick();
void  StickTick(Btn& b);                // камера-джойстик: едем, пока отклонён
void  RawMouseSeen();                   // пришёл «сырой» ввод настоящей мыши

// ---- панель --------------------------------------------------------------
extern HINSTANCE g_inst;
extern HWND      g_panel, g_main, g_handle, g_edge;

bool PanelCreate();
void PanelLayout();                     // пересчитать размеры и положение
void PanelRedraw();
void PanelShow(bool show);
bool PanelVisible();
void PanelSetProfile(int idx);
void PanelTick();                       // повтор нажатий и ожидание пера
void PanelHelpersUpdate();              // переставить язычок и полосу вызова
void PanelSetNeedAdmin(bool v);
void PanelFit(int& fitRows, double& realMM);   // сколько кнопок влезает и какого размера вышли
int  PanelProfile();
Profile* CurProfile();
std::vector<Btn>* CurBtns();            // кнопки текущей страницы
int  PanelPage();                       // -1 = основная страница
void PanelSetPage(const std::wstring& name);

// ---- окружение -----------------------------------------------------------
double ScreenDPI();                     // физических точек на дюйм экрана
void   ScreenDPIReset();                // экран сменился — считать заново
UINT   MonitorDPI();                    // масштаб интерфейса Windows (96 = 100%)
const wchar_t* UiFace();                // шрифт интерфейса (Segoe UI Variable, если есть)
int    MM2PX(double mm);
bool   IsElevated();
bool   ForegroundIsElevated();
std::wstring ForegroundExe();
void   SetAutostart(bool on);
bool   GetAutostart();
void   RestartAsAdmin();

// ---- окно настроек -------------------------------------------------------
void SettingsOpen();
bool SettingsIsOpen();
HWND SettingsHwnd();

// сообщения
#define WM_TRAYICON   (WM_APP + 1)
#define WM_APPBARMSG  (WM_APP + 2)
#define WM_PROFILECH  (WM_APP + 3)

#define TIMER_TICK  1
#define TIMER_FG    2
