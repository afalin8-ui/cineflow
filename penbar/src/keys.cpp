#include "app.h"
#include <algorithm>
#include <cmath>

// ---- имена клавиш --------------------------------------------------------
struct KeyName_ { const wchar_t* name; WORD vk; };
static const KeyName_ KEYS[] = {
    {L"ctrl", VK_CONTROL}, {L"control", VK_CONTROL}, {L"shift", VK_SHIFT},
    {L"alt", VK_MENU}, {L"win", VK_LWIN},
    {L"space", VK_SPACE}, {L"tab", VK_TAB}, {L"enter", VK_RETURN}, {L"return", VK_RETURN},
    {L"esc", VK_ESCAPE}, {L"escape", VK_ESCAPE},
    {L"backspace", VK_BACK}, {L"back", VK_BACK},
    {L"del", VK_DELETE}, {L"delete", VK_DELETE}, {L"ins", VK_INSERT}, {L"insert", VK_INSERT},
    {L"home", VK_HOME}, {L"end", VK_END}, {L"pgup", VK_PRIOR}, {L"pageup", VK_PRIOR},
    {L"pgdn", VK_NEXT}, {L"pagedown", VK_NEXT},
    {L"left", VK_LEFT}, {L"right", VK_RIGHT}, {L"up", VK_UP}, {L"down", VK_DOWN},
    {L"plus", VK_OEM_PLUS}, {L"=", VK_OEM_PLUS}, {L"minus", VK_OEM_MINUS}, {L"-", VK_OEM_MINUS},
    {L",", VK_OEM_COMMA}, {L"comma", VK_OEM_COMMA}, {L".", VK_OEM_PERIOD}, {L"period", VK_OEM_PERIOD},
    {L"/", VK_OEM_2}, {L"slash", VK_OEM_2}, {L"\\", VK_OEM_5}, {L"backslash", VK_OEM_5},
    {L";", VK_OEM_1}, {L"'", VK_OEM_7}, {L"`", VK_OEM_3}, {L"tilde", VK_OEM_3},
    {L"[", VK_OEM_4}, {L"]", VK_OEM_6},
    {L"num0", VK_NUMPAD0}, {L"num1", VK_NUMPAD1}, {L"num2", VK_NUMPAD2}, {L"num3", VK_NUMPAD3},
    {L"num4", VK_NUMPAD4}, {L"num5", VK_NUMPAD5}, {L"num6", VK_NUMPAD6}, {L"num7", VK_NUMPAD7},
    {L"num8", VK_NUMPAD8}, {L"num9", VK_NUMPAD9},
    {L"num*", VK_MULTIPLY}, {L"num/", VK_DIVIDE}, {L"num+", VK_ADD}, {L"num-", VK_SUBTRACT},
    {L"num.", VK_DECIMAL},
    {L"caps", VK_CAPITAL}, {L"menu", VK_APPS}, {L"apps", VK_APPS},
};

static bool IsMod(WORD vk) {
    return vk == VK_CONTROL || vk == VK_SHIFT || vk == VK_MENU || vk == VK_LWIN;
}

static bool IsExtended(WORD vk) {
    switch (vk) {
        case VK_LEFT: case VK_RIGHT: case VK_UP: case VK_DOWN:
        case VK_HOME: case VK_END: case VK_PRIOR: case VK_NEXT:
        case VK_INSERT: case VK_DELETE: case VK_DIVIDE: case VK_NUMLOCK:
        case VK_RCONTROL: case VK_RMENU: case VK_APPS: case VK_LWIN:
            return true;
    }
    return false;
}

static WORD NameToVk(const std::wstring& raw) {
    std::wstring s = LowerW(TrimW(raw));
    if (s.empty()) return 0;
    if (s.size() == 1) {
        wchar_t c = s[0];
        if (c >= L'a' && c <= L'z') return (WORD)(L'A' + (c - L'a'));
        if (c >= L'0' && c <= L'9') return (WORD)c;
    }
    if (s[0] == L'f' && s.size() <= 3) {
        int n = _wtoi(s.c_str() + 1);
        if (n >= 1 && n <= 24) return (WORD)(VK_F1 + n - 1);
    }
    for (auto& k : KEYS) if (s == k.name) return k.vk;
    return 0;
}

std::wstring KeyName(WORD vk) {
    if (vk >= 'A' && vk <= 'Z') return std::wstring(1, (wchar_t)vk);
    if (vk >= '0' && vk <= '9') return std::wstring(1, (wchar_t)vk);
    if (vk >= VK_F1 && vk <= VK_F24) {
        wchar_t b[8];
        swprintf(b, 8, L"F%d", vk - VK_F1 + 1);
        return b;
    }
    for (auto& k : KEYS) if (k.vk == vk) return k.name;
    return L"?";
}

// "ctrl+shift+z" -> список кодов, модификаторы впереди
bool ParseKeys(const std::wstring& s, std::vector<WORD>& out) {
    out.clear();
    std::wstring cur;
    std::vector<std::wstring> parts;
    for (size_t i = 0; i <= s.size(); i++) {
        // '+' сам по себе тоже клавиша: "num+" и "ctrl++" не должны рассыпаться
        if (i == s.size() || (s[i] == L'+' && !cur.empty())) {
            parts.push_back(cur);
            cur.clear();
        } else if (s[i] != L'+' || cur.empty()) {
            cur += s[i];
        }
    }
    std::vector<WORD> mods, main_;
    for (auto& p : parts) {
        if (TrimW(p).empty()) continue;
        WORD vk = NameToVk(p);
        if (!vk) return false;
        (IsMod(vk) ? mods : main_).push_back(vk);
    }
    for (WORD v : mods)  out.push_back(v);
    for (WORD v : main_) out.push_back(v);
    return !out.empty();
}

std::wstring ComboText(const std::vector<WORD>& vks) {
    std::wstring s;
    for (size_t i = 0; i < vks.size(); i++) {
        if (i) s += L"+";
        std::wstring n = KeyName(vks[i]);
        if (!n.empty()) n[0] = (wchar_t)towupper(n[0]);
        s += n;
    }
    return s;
}

// ---- отправка нажатий ----------------------------------------------------
// Держим список того, что зажали САМИ: если программа закроется с залипшим
// Shift, он останется зажатым во всей системе, и человек решит, что сломалась
// клавиатура. Всё зажатое отпускается при выходе.
static std::vector<WORD> g_heldVk;
static bool g_heldMouse[4] = {false, false, false, false};

static void RememberVk(WORD vk, bool down) {
    auto it = std::find(g_heldVk.begin(), g_heldVk.end(), vk);
    if (down) { if (it == g_heldVk.end()) g_heldVk.push_back(vk); }
    else      { if (it != g_heldVk.end()) g_heldVk.erase(it); }
}

static void RawKey(WORD vk, bool up) {
    INPUT in{};
    in.type       = INPUT_KEYBOARD;
    in.ki.wVk     = vk;
    in.ki.wScan   = (WORD)MapVirtualKeyW(vk, MAPVK_VK_TO_VSC);
    in.ki.dwFlags = up ? KEYEVENTF_KEYUP : 0;
    if (IsExtended(vk)) in.ki.dwFlags |= KEYEVENTF_EXTENDEDKEY;
    SendInput(1, &in, sizeof(INPUT));
    RememberVk(vk, !up);
}

void SendCombo(const std::vector<WORD>& vks, bool down) {
    if (down) for (size_t i = 0; i < vks.size(); i++) RawKey(vks[i], false);
    else      for (size_t i = vks.size(); i-- > 0; )  RawKey(vks[i], true);
}

void SendComboTap(const std::vector<WORD>& vks) {
    SendCombo(vks, true);
    SendCombo(vks, false);
}

// ---- окно, которым мы управляем ------------------------------------------
// Нажатие мыши достаётся окну ПОД УКАЗАТЕЛЕМ. Пальцем панель нажимают, не
// двигая указателя, но ПЕРОМ — двигая: указатель встаёт на саму панель, и
// нажатие ушло бы по нашей же кнопке. Поэтому помним последнее чужое
// активное окно и последнюю точку указателя ВНУТРИ него — это якорь.
static HWND  g_target     = nullptr;
static POINT g_anchor     = {0, 0};
static bool  g_anchorOk   = false;
static DWORD g_targetGone = 0;      // когда цель ушла с переднего плана

void TargetRemember(HWND w) {
    if (!w) return;
    if (w == g_target) { g_targetGone = 0; return; }
    g_target     = w;
    g_anchorOk   = false;
    g_targetGone = 0;
}

HWND TargetWindow() {
    if (g_target && IsWindow(g_target) && IsWindowVisible(g_target)) return g_target;
    g_target = nullptr;
    return nullptr;
}

bool CursorInTarget(const POINT& cur) {
    HWND w = TargetWindow();
    if (!w) return false;
    HWND under = WindowFromPoint(cur);
    if (!under) return false;
    return under == w || GetAncestor(under, GA_ROOT) == w;
}

void TargetSeen(const POINT& cur) {
    if (CursorInTarget(cur)) { g_anchor = cur; g_anchorOk = true; }
}

static bool PointOnPanel(const POINT& p) {
    if (!g_panel || !IsWindowVisible(g_panel)) return false;
    RECT r;
    GetWindowRect(g_panel, &r);
    return PtInRect(&r, p) != 0;
}

// Куда должно прийтись нажатие.
//
// ГЛАВНОЕ ПРАВИЛО: там, где стоит указатель. Так было в первой версии, и так
// оно работало — нажатие приходится ровно под перо. Якорь заведён НЕ вместо
// этого, а на единственный случай, когда указатель стоит на самой полоске:
// нажать мышь там значит нажать по нашей же кнопке. Спрашивать «а внутри ли
// указатель окна цели» нельзя: стоит нам ошибиться с тем, какое окно цель, —
// и нажатие уезжает в сторону от того места, куда человек смотрит.
static POINT InjectPoint(bool& known) {
    POINT cur;
    GetCursorPos(&cur);
    known = true;
    if (!PointOnPanel(cur)) {
        if (CursorInTarget(cur)) { g_anchor = cur; g_anchorOk = true; }
        return cur;
    }
    if (g_anchorOk) return g_anchor;
    HWND w = TargetWindow();
    RECT r;
    if (w && GetWindowRect(w, &r)) {
        POINT c{(r.left + r.right) / 2, (r.top + r.bottom) / 2};
        return c;
    }
    known = false;
    return cur;
}

void CursorToTarget() {
    bool known = false;
    POINT go = InjectPoint(known);
    if (known) SetCursorPos(go.x, go.y);
}

// Нажатие мыши уходит ВМЕСТЕ с переносом указателя, одним событием. Раньше
// указатель переставлялся отдельным вызовом, и между ним и нажатием успевало
// вклиниться движение настоящей мыши или пера — нажатие приходилось не туда.
static void MouseEvent(DWORD flags, DWORD data) {
    bool known = false;
    POINT go = InjectPoint(known);
    INPUT in{};
    in.type         = INPUT_MOUSE;
    in.mi.dwFlags   = flags;
    in.mi.mouseData = data;
    if (known) {
        int vx = GetSystemMetrics(SM_XVIRTUALSCREEN), vy = GetSystemMetrics(SM_YVIRTUALSCREEN);
        int vw = GetSystemMetrics(SM_CXVIRTUALSCREEN), vh = GetSystemMetrics(SM_CYVIRTUALSCREEN);
        if (vw > 1 && vh > 1) {
            in.mi.dx = (LONG)(((double)(go.x - vx) * 65535.0) / (vw - 1) + 0.5);
            in.mi.dy = (LONG)(((double)(go.y - vy) * 65535.0) / (vh - 1) + 0.5);
            in.mi.dwFlags |= MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK;
        }
    }
    UINT sent = SendInput(1, &in, sizeof(INPUT));
    if (!sent) {
        // Ноль значит, что Windows нажатие НЕ ПРОПУСТИЛА. Почти всегда это
        // разные уровни прав: программа под администратором чужой ввод не
        // принимает. Молчать тут нельзя — со стороны это «кнопка не работает».
        Log(L"SendInput не прошёл (ошибка %u): нажатие мыши до программы не дошло",
            GetLastError());
        PanelSetNeedAdmin(true);
    } else {
        Log(L"мышь: флаги 0x%04X в точке %d,%d%s", (unsigned)flags, (int)go.x, (int)go.y,
            known ? L"" : L" (окно цели неизвестно)");
    }
}

static bool ForegroundIsOurs() {
    HWND fg = GetForegroundWindow();
    if (!fg) return false;
    DWORD pid = 0;
    GetWindowThreadProcessId(fg, &pid);
    return pid == GetCurrentProcessId();
}

void TargetFocus() {
    HWND w = TargetWindow();
    if (!w || GetForegroundWindow() == w) return;
    if (ForegroundIsOurs()) return;             // это наше окно настроек, не отнимаем
    SetForegroundWindow(w);
}

// Залипшая ПКМ делает редактор неуправляемым. Ушли из программы надолго —
// отпускаем всё само: человек уже не видит панель и не помнит про залипание.
void TargetGuard() {
    HWND w  = TargetWindow();
    HWND fg = GetForegroundWindow();
    // Сравниваем ПРОГРАММЫ, а не окна: у Unreal окон много, и переход между
    // ними — это не «человек ушёл из программы». Ошибись мы тут, и всё
    // зажатое отпускалось бы само через две секунды работы.
    bool same = false;
    if (w && fg) {
        DWORD p1 = 0, p2 = 0;
        GetWindowThreadProcessId(w, &p1);
        GetWindowThreadProcessId(fg, &p2);
        same = (p1 && p1 == p2);
    }
    if (!w || same || ForegroundIsOurs() || !AnyHeld()) { g_targetGone = 0; return; }
    DWORD now = GetTickCount();
    if (!g_targetGone) { g_targetGone = now; return; }
    if (now - g_targetGone >= 2000) {
        Log(L"цель ушла с переднего плана — отпускаю всё зажатое");
        ReleaseEverything();
        g_targetGone = 0;
    }
}

void SendMouseMove(int dx, int dy) {
    if (!dx && !dy) return;
    INPUT in{};
    in.type       = INPUT_MOUSE;
    in.mi.dx      = dx;
    in.mi.dy      = dy;
    in.mi.dwFlags = MOUSEEVENTF_MOVE;      // именно относительное: при зажатой
    SendInput(1, &in, sizeof(INPUT));      // ПКМ Unreal читает приращения, а не точку
}

void SendMouseBtn(int mb, bool down) {
    DWORD f = 0;
    int slot = 0;
    switch (mb) {
        case PB_LEFT:  f = down ? MOUSEEVENTF_LEFTDOWN   : MOUSEEVENTF_LEFTUP;   slot = 1; break;
        case PB_RIGHT: f = down ? MOUSEEVENTF_RIGHTDOWN  : MOUSEEVENTF_RIGHTUP;  slot = 2; break;
        case PB_MID:   f = down ? MOUSEEVENTF_MIDDLEDOWN : MOUSEEVENTF_MIDDLEUP; slot = 3; break;
        default: return;
    }
    if (down) {
        MouseEvent(f, 0);            // нажатие — вместе с переносом указателя
    } else {
        INPUT in{};                  // отпускать можно где угодно: окно держит захват
        in.type       = INPUT_MOUSE;
        in.mi.dwFlags = f;
        SendInput(1, &in, sizeof(INPUT));
    }
    g_heldMouse[slot] = down;
}

void SendMouseClick(int mb) {
    SendMouseBtn(mb, true);
    SendMouseBtn(mb, false);
}

void SendWheel(int mb) {
    // колесо достаётся окну под указателем — переносим его тем же событием
    MouseEvent(MOUSEEVENTF_WHEEL, (DWORD)((mb == PB_WUP) ? WHEEL_DELTA : -WHEEL_DELTA));
}

// ---- поведение кнопок ----------------------------------------------------
// Пауза перед повтором и шаг повтора — как у клавиатуры, только чуть быстрее.
static const DWORD REP_DELAY = 350;
static const DWORD REP_STEP  = 55;

static bool HasMouseBtn(const Btn& b) {
    return b.mouse == PB_LEFT || b.mouse == PB_RIGHT || b.mouse == PB_MID;
}

// Разбор сочетания кэшируем в самой кнопке: повтор дёргает это каждые 55 мс,
// и разбирать строку заново на каждое срабатывание незачем.
void BtnCompile(Btn& b) {
    b.vks.clear();
    b.vks2.clear();
    if (b.kind == K_JOY) {
        // у джойстика в keys лежат четыре клавиши через запятую: вперёд,
        // влево, назад, вправо. Пусто — обычные W A S D. Через ParseKeys это
        // не проходит и не должно: там сочетание, а тут список.
        const wchar_t* def[4] = {L"w", L"a", L"s", L"d"};
        std::wstring src = b.keys;
        for (int i = 0; i < 4; i++) {
            std::wstring one;
            size_t e = src.find(L',');
            if (e == std::wstring::npos) { one = src; src.clear(); }
            else { one = src.substr(0, e); src = src.substr(e + 1); }
            one = TrimW(one);
            b.joyVk[i] = NameToVk(one.empty() ? def[i] : one);
            if (!b.joyVk[i]) b.joyVk[i] = NameToVk(def[i]);
        }
        return;                 // сами клавиши джойстик шлёт поштучно
    }
    if (!b.keys.empty() && !ParseKeys(b.keys, b.vks))
        Log(L"не понял сочетание \"%s\" у кнопки \"%s\"", b.keys.c_str(), b.label.c_str());
    if (!b.keys2.empty() && !ParseKeys(b.keys2, b.vks2))
        Log(L"не понял долгое нажатие \"%s\" у кнопки \"%s\"", b.keys2.c_str(), b.label.c_str());
}
static const std::vector<WORD>& Vks(const Btn& b) { return b.vks; }

// ---- джойстик ------------------------------------------------------------
// Восемь направлений. События шлём ТОЛЬКО на смене состояния: иначе на каждое
// движение пальца летело бы новое «нажал», и вместо ровного полёта вышел бы
// автоповтор — Unreal дёргался бы шагами.
static void ApplyUp(Btn& b);              // объявлена ниже, нужна отпусканию чужих залипаний

static const double JOY_DEAD = 0.18;      // мёртвая зона, доля радиуса
static const int J_FWD = 1, J_LEFT = 2, J_BACK = 4, J_RIGHT = 8;

void JoyMove(Btn& b, double nx, double ny) {
    b.joyX = nx;
    b.joyY = ny;
    double r = sqrt(nx * nx + ny * ny);
    int want = 0;
    if (r >= JOY_DEAD) {
        double ang = atan2(-ny, nx) * 180.0 / 3.14159265358979323846;   // 0 = вправо, 90 = вверх
        if (ang < 0) ang += 360;
        static const int MASKS[8] = {
            J_RIGHT, J_FWD | J_RIGHT, J_FWD, J_FWD | J_LEFT,
            J_LEFT,  J_BACK | J_LEFT, J_BACK, J_BACK | J_RIGHT };
        want = MASKS[((int)((ang + 22.5) / 45.0)) % 8];
    }
    if (want == b.joyMask) return;
    for (int i = 0; i < 4; i++) {
        int bit = 1 << i;
        bool had = (b.joyMask & bit) != 0, now_ = (want & bit) != 0;
        if (had == now_ || !b.joyVk[i]) continue;
        RawKey(b.joyVk[i], !now_);
    }
    b.joyMask = want;
}

void JoyOff(Btn& b) {
    JoyMove(b, 0, 0);
    b.joyX = b.joyY = 0;
}

// Кнопка мыши на панели одна на всех: две залипшие разом дают в Unreal
// совсем третье поведение (ЛКМ+ПКМ — это панорама, а не поворот). Поэтому
// новая залипающая кнопка мыши отпускает прежнюю.
static void DropOtherMouseLatches(const Btn& self) {
    auto scan = [&](std::vector<Btn>& list) {
        for (auto& o : list) {
            if (&o == &self || !HasMouseBtn(o)) continue;
            if (!o.latched && !o.armed) continue;
            if (!o.armed) ApplyUp(o);
            o.latched = o.armed = false;
        }
    };
    for (auto& p : g_cfg.profiles) {
        scan(p.btns);
        for (auto& pg : p.pages) scan(pg.btns);
    }
}

static void ApplyDown(Btn& b) {
    const std::vector<WORD>& v = Vks(b);
    if (!v.empty())    { TargetFocus(); SendCombo(v, true); }
    if (HasMouseBtn(b))  SendMouseBtn(b.mouse, true);
}

static void ApplyUp(Btn& b) {
    if (HasMouseBtn(b))  SendMouseBtn(b.mouse, false);
    const std::vector<WORD>& v = Vks(b);
    if (!v.empty())      SendCombo(v, false);
}

// одно разовое срабатывание
static void ApplyTap(Btn& b) {
    const std::vector<WORD>& v = Vks(b);
    if (!v.empty()) TargetFocus();
    if (b.mouse == PB_WUP || b.mouse == PB_WDN) {
        if (!v.empty()) SendCombo(v, true);
        SendWheel(b.mouse);
        if (!v.empty()) SendCombo(v, false);
        return;
    }
    if (HasMouseBtn(b)) {
        if (!v.empty()) SendCombo(v, true);
        SendMouseClick(b.mouse);
        if (!v.empty()) SendCombo(v, false);
        return;
    }
    if (!v.empty()) SendComboTap(v);
}

// Мышь нажимается там, где стоит указатель. Пальцем панель нажимают, не двигая
// указателя, — тогда всё сразу попадает в холст. Но по панели могут ткнуть и
// ПЕРОМ, и тогда указатель стоит на самой панели: нажать мышь там же значит
// нажать по нашей же кнопке. Поэтому ждём, пока перо уйдёт с панели, и только
// тогда жмём — заодно получается «нажал и веду»: линия начинается там, где
// перо коснулось холста, а не там, где была кнопка.
static bool NeedArm(const Btn& b, bool cursorOnPanel) {
    return HasMouseBtn(b) && cursorOnPanel;
}

void BtnPress(Btn& b) {
    if (b.kind != K_KEY) return;        // зоны живут ведением, а не нажатием
    POINT cur;
    GetCursorPos(&cur);
    bool onPanel = false;
    if (g_panel && IsWindowVisible(g_panel)) {
        RECT r;
        GetWindowRect(g_panel, &r);
        onPanel = PtInRect(&r, cur) != 0;
    }
    // Пишем в журнал КАЖДОЕ нажатие вместе с набором: «кнопка не работает»
    // чаще всего означает, что нажали не ту кнопку не того набора.
    {
        Profile* pr = CurProfile();
        Log(L"набор \"%s\", кнопка \"%s\": %s%s",
            pr ? pr->name.c_str() : L"?", b.label.c_str(),
            b.mode == M_LATCH ? L"залипающая" : b.mode == M_HOLD ? L"держать" : L"разовая",
            b.mouse == PB_RIGHT ? L", ПКМ" : b.mouse == PB_MID ? L", СКМ" :
            b.mouse == PB_LEFT ? L", ЛКМ" : L"");
    }
    bool wasDown = b.down;              // спросить НАДО до того, как выставим флаг
    b.down     = true;
    b.downAt   = GetTickCount();
    b.longDone = false;
    b.repAt    = b.downAt + REP_DELAY;

    if (b.mode == M_LATCH) {
        // ОДНО касание Windows умеет показать дважды: сообщением указателя и
        // мышиным двойником следом, иногда уже после отпускания. Для залипания
        // это смертельно — первое включает, второе тут же выключает, и выходит
        // обычный щелчок вместо удержания. Отличить второе касание от двойника
        // можно только временем: человек не переключает кнопку дважды за
        // четверть секунды.
        DWORD tnow = GetTickCount();
        if (wasDown || (int)(tnow - b.toggleAt) < 250) {
            Log(L"\"%s\": повторное нажатие через %d мс — это двойник, пропускаю",
                b.label.c_str(), (int)(tnow - b.toggleAt));
            return;
        }
        b.toggleAt = tnow;
        if (b.latched) {                       // второе нажатие — отпускаем
            Log(L"\"%s\": отпустили", b.label.c_str());
            if (!b.armed) ApplyUp(b);
            b.latched = false;
            b.armed   = false;
            return;
        }
        if (HasMouseBtn(b)) DropOtherMouseLatches(b);
        b.latched = true;
        if (NeedArm(b, onPanel)) {
            b.armed = true;
            Log(L"\"%s\": залипла, ждём ухода пера с панели", b.label.c_str());
            return;
        }
        Log(L"\"%s\": залипла, жму сразу", b.label.c_str());
        ApplyDown(b);
        return;
    }

    if (b.mode == M_HOLD) {
        if (HasMouseBtn(b)) DropOtherMouseLatches(b);
        if (NeedArm(b, onPanel)) { b.armed = true; return; }
        ApplyDown(b);
        return;
    }

    // Разовое нажатие. У кнопки с долгим нажатием оно срабатывает на
    // ОТПУСКАНИИ: иначе «Отмена» успела бы отменить ещё до того, как человек
    // додержал её до «Вернуть».
    if (!b.vks2.empty()) return;
    ApplyTap(b);
}

void BtnRelease(Btn& b) {
    if (b.kind != K_KEY) return;
    b.down = false;
    if (b.mode == M_HOLD) {
        if (b.armed) { b.armed = false; return; }   // перо так и не ушло — ничего не нажимали
        ApplyUp(b);
        return;
    }
    if (b.mode == M_TAP && !b.vks2.empty() && !b.longDone) ApplyTap(b);
    b.longDone = false;
}

void BtnTick(Btn& b, DWORD now, const POINT& cur, bool cursorOnPanel) {
    (void)cur;
    if (b.kind != K_KEY) return;

    // ждали, пока перо уйдёт с панели
    if (b.armed && !cursorOnPanel) {
        b.armed = false;
        ApplyDown(b);
    }

    // долгое нажатие — второе действие той же кнопки
    if (b.down && !b.longDone && !b.vks2.empty() && (int)(now - b.downAt) >= 600) {
        b.longDone = true;
        TargetFocus();
        SendComboTap(b.vks2);
    }

    if (!b.repeat) return;
    bool active = (b.mode == M_LATCH) ? b.latched : b.down;
    if (!active || b.armed) return;
    if ((int)(now - b.repAt) < 0) return;
    b.repAt = now + REP_STEP;

    if (b.mode == M_TAP) {
        ApplyTap(b);
    } else {
        const std::vector<WORD>& v = Vks(b);
        if (!v.empty()) RawKey(v.back(), false);      // повтор основной клавиши
        else if (b.mouse == PB_WUP || b.mouse == PB_WDN) SendWheel(b.mouse);
    }
}

// Кнопка мыши, нажатая ПЕРОМ, ждёт, пока перо уйдёт с панели (иначе нажатие
// пришлось бы по самой панели). Но если человек тут же берётся за зону —
// обзор, джойстик, крутилку, — перо с панели не уйдёт НИКОГДА, и ПКМ не
// нажалась бы вовсе. Взялись за зону — значит ждать больше нечего: место
// нажатия и так считается по якорю.
void FlushArmed() {
    auto scan = [](std::vector<Btn>& list) {
        for (auto& b : list) {
            if (!b.armed) continue;
            b.armed = false;
            ApplyDown(b);
        }
    };
    for (auto& p : g_cfg.profiles) {
        scan(p.btns);
        for (auto& pg : p.pages) scan(pg.btns);
    }
}

bool AnyHeld() {
    for (auto& p : g_cfg.profiles) {
        for (auto& b : p.btns)
            if (b.latched || b.down || b.armed || b.joyMask || b.padDown) return true;
        for (auto& pg : p.pages)
            for (auto& b : pg.btns)
                if (b.latched || b.down || b.armed || b.joyMask || b.padDown) return true;
    }
    return !g_heldVk.empty() || g_heldMouse[1] || g_heldMouse[2] || g_heldMouse[3];
}

static void ReleaseList(std::vector<Btn>& list) {
    for (auto& b : list) {
        if (b.kind == K_JOY) { JoyOff(b); continue; }
        if (b.padDown) { SendMouseBtn(b.mouse, false); b.padDown = false; b.down = false; continue; }
        if ((b.latched || b.down) && !b.armed) ApplyUp(b);
        b.latched = b.down = b.armed = b.longDone = false;
    }
}

void ReleaseEverything() {
    if (AnyHeld()) Log(L"отпускаю всё зажатое");
    for (auto& p : g_cfg.profiles) {
        ReleaseList(p.btns);
        for (auto& pg : p.pages) ReleaseList(pg.btns);
    }
    for (int i = 1; i <= 3; i++)
        if (g_heldMouse[i]) SendMouseBtn(i == 1 ? PB_LEFT : i == 2 ? PB_RIGHT : PB_MID, false);
    std::vector<WORD> left = g_heldVk;
    for (size_t i = left.size(); i-- > 0; ) RawKey(left[i], true);
    g_heldVk.clear();
}
