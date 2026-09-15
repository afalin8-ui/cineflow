#include "app.h"
#include <algorithm>

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

void SendMouseBtn(int mb, bool down) {
    DWORD f = 0;
    int slot = 0;
    switch (mb) {
        case PB_LEFT:  f = down ? MOUSEEVENTF_LEFTDOWN   : MOUSEEVENTF_LEFTUP;   slot = 1; break;
        case PB_RIGHT: f = down ? MOUSEEVENTF_RIGHTDOWN  : MOUSEEVENTF_RIGHTUP;  slot = 2; break;
        case PB_MID:   f = down ? MOUSEEVENTF_MIDDLEDOWN : MOUSEEVENTF_MIDDLEUP; slot = 3; break;
        default: return;
    }
    INPUT in{};
    in.type         = INPUT_MOUSE;
    in.mi.dwFlags   = f;
    SendInput(1, &in, sizeof(INPUT));
    g_heldMouse[slot] = down;
}

void SendMouseClick(int mb) {
    SendMouseBtn(mb, true);
    SendMouseBtn(mb, false);
}

void SendWheel(int mb) {
    INPUT in{};
    in.type       = INPUT_MOUSE;
    in.mi.dwFlags = MOUSEEVENTF_WHEEL;
    in.mi.mouseData = (DWORD)((mb == PB_WUP) ? WHEEL_DELTA : -WHEEL_DELTA);
    SendInput(1, &in, sizeof(INPUT));
}

// ---- поведение кнопок ----------------------------------------------------
// Пауза перед повтором и шаг повтора — как у клавиатуры, только чуть быстрее.
static const DWORD REP_DELAY = 350;
static const DWORD REP_STEP  = 55;

static POINT g_lastOutside = {0, 0};    // где перо было в последний раз вне панели

static bool HasMouseBtn(const Btn& b) {
    return b.mouse == PB_LEFT || b.mouse == PB_RIGHT || b.mouse == PB_MID;
}

// Разбор сочетания кэшируем в самой кнопке: повтор дёргает это каждые 55 мс,
// и разбирать строку заново на каждое срабатывание незачем.
void BtnCompile(Btn& b) {
    b.vks.clear();
    if (!b.keys.empty() && !ParseKeys(b.keys, b.vks))
        Log(L"не понял сочетание \"%s\" у кнопки \"%s\"", b.keys.c_str(), b.label.c_str());
}
static const std::vector<WORD>& Vks(const Btn& b) { return b.vks; }

static void ApplyDown(Btn& b) {
    const std::vector<WORD>& v = Vks(b);
    if (!v.empty())      SendCombo(v, true);
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
    POINT cur;
    GetCursorPos(&cur);
    bool onPanel = false;
    if (g_panel && IsWindowVisible(g_panel)) {
        RECT r;
        GetWindowRect(g_panel, &r);
        onPanel = PtInRect(&r, cur) != 0;
    }
    b.down  = true;
    b.repAt = GetTickCount() + REP_DELAY;

    if (b.mode == M_LATCH) {
        if (b.latched) {                       // второе нажатие — отпускаем
            if (!b.armed) ApplyUp(b);
            b.latched = false;
            b.armed   = false;
            return;
        }
        b.latched = true;
        if (NeedArm(b, onPanel)) { b.armed = true; return; }
        ApplyDown(b);
        return;
    }

    if (b.mode == M_HOLD) {
        if (NeedArm(b, onPanel)) { b.armed = true; return; }
        ApplyDown(b);
        return;
    }

    // разовое нажатие
    if (HasMouseBtn(b) && onPanel && (g_lastOutside.x || g_lastOutside.y))
        SetCursorPos(g_lastOutside.x, g_lastOutside.y);
    ApplyTap(b);
}

void BtnRelease(Btn& b) {
    b.down = false;
    if (b.mode == M_HOLD) {
        if (b.armed) { b.armed = false; return; }   // перо так и не ушло — ничего не нажимали
        ApplyUp(b);
    }
}

void BtnTick(Btn& b, DWORD now, const POINT& cur, bool cursorOnPanel) {
    if (!cursorOnPanel) g_lastOutside = cur;

    // ждали, пока перо уйдёт с панели
    if (b.armed && !cursorOnPanel) {
        b.armed = false;
        ApplyDown(b);
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

bool AnyHeld() {
    for (auto& p : g_cfg.profiles) {
        for (auto& b : p.btns)
            if (b.latched || b.down || b.armed) return true;
        for (auto& pg : p.pages)
            for (auto& b : pg.btns)
                if (b.latched || b.down || b.armed) return true;
    }
    return !g_heldVk.empty() || g_heldMouse[1] || g_heldMouse[2] || g_heldMouse[3];
}

static void ReleaseList(std::vector<Btn>& list) {
    for (auto& b : list) {
        if ((b.latched || b.down) && !b.armed) ApplyUp(b);
        b.latched = b.down = b.armed = false;
    }
}

void ReleaseEverything() {
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
