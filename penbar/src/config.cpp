#include "app.h"
#include "json.h"
#include <algorithm>

Config g_cfg;

// ---- наборы кнопок по умолчанию ------------------------------------------
// Правило набора: то, за чем на весу тянутся к клавиатуре, и то, чего нет
// на пере. У пера одна нажимаемая кнопка, поэтому средняя и правая кнопки
// мыши, Shift/Ctrl/Alt и «нажал и веду» — здесь.
static Btn B(const wchar_t* label, const wchar_t* keys, int mode = M_TAP,
             int mouse = PB_NONE, bool repeat = false, const wchar_t* page = nullptr) {
    Btn b;
    b.label  = label;
    b.keys   = keys ? keys : L"";
    b.mode   = mode;
    b.mouse  = mouse;
    b.repeat = repeat;
    b.page   = page ? page : L"";
    return b;
}

// Зона: по ней ведут пальцем, а не стучат. span — сколько клеток полоски
// она занимает: джойстик в одну клетку — это пятак, в который не попасть.
static Btn Z(const wchar_t* label, int kind, int span, const wchar_t* keys = nullptr,
             int mouse = PB_NONE) {
    Btn b;
    b.label = label;
    b.kind  = kind;
    b.span  = span;
    b.keys  = keys ? keys : L"";
    b.mouse = mouse;      // у площадки это кнопка, которую она держит, пока ведут
    return b;
}

static Btn Long(Btn b, const wchar_t* keys2) {   // второе действие долгим нажатием
    b.keys2 = keys2;
    return b;
}

// Набор для Unreal собран вокруг одной беды: перо, коснувшееся вьюпорта, —
// это ЛКМ, а ЛКМ вместе с зажатой ПКМ в Unreal означает панорамирование,
// то есть ровно то, что делает средняя кнопка. Поэтому камерой водят по
// зоне «Обзор» на самой панели, а не пером по вьюпорту.
static std::vector<Btn> UnrealBtns() {
    return {
        Z(L"Обзор", K_PAD, 2, nullptr, PB_RIGHT),      // ведут — держится ПКМ
        Z(L"Панорама", K_PAD, 2, nullptr, PB_MID),     // ведут — держится СКМ
        Z(L"Ходьба", K_JOY, 2, L"w,a,s,d"),
        B(L"Вверх E",     L"e", M_HOLD),
        B(L"Вниз Q",      L"q", M_HOLD),
        B(L"Быстро Shift",L"shift", M_LATCH),
        B(L"Фокус F",     L"f"),
        Long(B(L"Отмена", L"ctrl+z"), L"ctrl+y"),
        B(L"Полёт ПКМ",  nullptr, M_LATCH, PB_RIGHT),  // для тех, кто с мышью
        Z(L"Скорость", K_WHEEL, 2),
    };
}

void ConfigDefaults() {
    g_cfg = Config();

    {   // ---- DaVinci Resolve ----
        Profile p;
        p.name  = L"DaVinci Resolve";
        p.match = L"resolve.exe;davinci resolve.exe";
        p.btns = {
            B(L"Пуск стоп",   L"space"),
            B(L"Кадр -1",       L"left",  M_TAP, PB_NONE, true),
            B(L"Кадр +1",       L"right", M_TAP, PB_NONE, true),
            B(L"J",            L"j"),
            B(L"K",            L"k"),
            B(L"L",            L"l"),
            B(L"Стрелка A",   L"a"),
            B(L"Лезвие B",    L"b"),
            B(L"Отмена",       L"ctrl+z"),
            B(L"Вернуть",      L"ctrl+shift+z"),
            B(L"Shift",        L"shift", M_LATCH),
            B(L"ПКМ",          nullptr,  M_TAP, PB_RIGHT),
        };
        g_cfg.profiles.push_back(p);
    }
    {   // ---- Blender ----
        // Сдвиг, поворот и масштаб открывают вторую страницу с осями: в самом
        // Blender после G нажимают X, и панель повторяет тот же порядок.
        Profile p;
        p.name  = L"Blender";
        p.match = L"blender.exe";
        p.btns = {
            B(L"Орбита",     nullptr,  M_LATCH, PB_MID),
            B(L"Панорама",   L"shift", M_LATCH, PB_MID),
            B(L"Зум",        L"ctrl",  M_LATCH, PB_MID),
            B(L"ПКМ",        nullptr,  M_TAP,   PB_RIGHT),
            B(L"Shift",      L"shift", M_LATCH),
            B(L"Ctrl",       L"ctrl",  M_LATCH),
            B(L"Alt",        L"alt",   M_LATCH),
            B(L"Сдвиг G",    L"g",     M_TAP, PB_NONE, false, L"Оси"),
            B(L"Поворот R",  L"r",     M_TAP, PB_NONE, false, L"Оси"),
            B(L"Масштаб S",  L"s",     M_TAP, PB_NONE, false, L"Оси"),
            B(L"Tab",        L"tab"),
            B(L"Отмена",     L"ctrl+z"),
        };
        Page ax;
        ax.name = L"Оси";
        ax.btns = {
            B(L"Сдвиг G",    L"g"),
            B(L"Поворот R",  L"r"),
            B(L"Масштаб S",  L"s"),
            B(L"X",          L"x"),
            B(L"Y",          L"y"),
            B(L"Z",          L"z"),
            B(L"кроме X",    L"shift+x"),
            B(L"кроме Y",    L"shift+y"),
            B(L"кроме Z",    L"shift+z"),
            B(L"Ввод",       L"enter", M_TAP, PB_NONE, false, L"-"),
            B(L"Esc",        L"esc",   M_TAP, PB_NONE, false, L"-"),
            B(L"‹ Назад",    nullptr,  M_TAP, PB_NONE, false, L"-"),
        };
        p.pages.push_back(ax);
        g_cfg.profiles.push_back(p);
    }
    {   // ---- Unreal Engine ----
        Profile p;
        p.name  = L"Unreal";
        p.match = L"unrealeditor.exe;ue4editor.exe;ue5editor.exe";
        p.btns = UnrealBtns();
        g_cfg.profiles.push_back(p);
    }
    {   // ---- Photoshop ----
        Profile p;
        p.name  = L"Photoshop";
        p.match = L"photoshop.exe";
        p.btns = {
            B(L"Панор. пробел", L"space", M_LATCH),
            B(L"Alt",            L"alt",   M_LATCH),
            B(L"Shift",          L"shift", M_LATCH),
            B(L"Ctrl",           L"ctrl",  M_LATCH),
            B(L"Отмена",         L"ctrl+z"),
            B(L"Шаг назад",     L"ctrl+alt+z"),
            B(L"Кисть B",       L"b"),
            B(L"Ластик E",      L"e"),
            B(L"Меньше [",      L"[", M_TAP, PB_NONE, true),
            B(L"Больше ]",      L"]", M_TAP, PB_NONE, true),
            B(L"Сохр.",          L"ctrl+s"),
            B(L"ПКМ",            nullptr,  M_TAP, PB_RIGHT),
        };
        g_cfg.profiles.push_back(p);
    }
    {   // ---- Krita ----
        Profile p;
        p.name  = L"Krita";
        p.match = L"krita.exe";
        p.btns = {
            B(L"Панор. пробел", L"space", M_LATCH),
            B(L"Shift",          L"shift", M_LATCH),
            B(L"Ctrl",           L"ctrl",  M_LATCH),
            B(L"Alt",            L"alt",   M_LATCH),
            B(L"Отмена",         L"ctrl+z"),
            B(L"Вернуть",        L"ctrl+shift+z"),
            B(L"Кисть B",       L"b"),
            B(L"Ластик E",      L"e"),
            B(L"Меньше [",      L"[", M_TAP, PB_NONE, true),
            B(L"Больше ]",      L"]", M_TAP, PB_NONE, true),
            B(L"Сохр.",          L"ctrl+s"),
            B(L"ПКМ",            nullptr,  M_TAP, PB_RIGHT),
        };
        g_cfg.profiles.push_back(p);
    }
    {   // ---- общий: подходит, когда впереди что-то другое ----
        Profile p;
        p.name  = L"Общий";
        p.match = L"";
        p.btns = {
            B(L"Отмена",   L"ctrl+z"),
            B(L"Вернуть",  L"ctrl+shift+z"),
            B(L"Копир.",   L"ctrl+c"),
            B(L"Встав.",   L"ctrl+v"),
            B(L"Сохр.",    L"ctrl+s"),
            B(L"Shift",    L"shift", M_LATCH),
            B(L"Ctrl",     L"ctrl",  M_LATCH),
            B(L"Alt",      L"alt",   M_LATCH),
            B(L"Tab",      L"tab"),
            B(L"Esc",      L"esc"),
            B(L"ПКМ",      nullptr, M_TAP,   PB_RIGHT),
            B(L"СКМ",      nullptr, M_LATCH, PB_MID),
        };
        g_cfg.profiles.push_back(p);
    }

    for (auto& p : g_cfg.profiles) {
        for (auto& b : p.btns) BtnCompile(b);
        for (auto& pg : p.pages)
            for (auto& b : pg.btns) BtnCompile(b);
    }
}

// ---- чтение и запись -----------------------------------------------------
static const wchar_t* EDGE_NAMES[]  = {L"left", L"right", L"top", L"bottom"};
static const wchar_t* ALIGN_NAMES[] = {L"start", L"center", L"end"};
static const wchar_t* MODE_NAMES[]  = {L"tap", L"hold", L"latch"};
static const wchar_t* MOUSE_NAMES[] = {L"", L"left", L"right", L"middle", L"wheelup", L"wheeldown"};
static const wchar_t* KIND_NAMES[]  = {L"key", L"pad", L"joy", L"wheel"};

static int NameIdx(const std::wstring& s, const wchar_t* const* names, int n, int def) {
    for (int i = 0; i < n; i++) if (s == names[i]) return i;
    return def;
}

static JPtr BtnsToJson(const std::vector<Btn>& btns) {
    JPtr arr = JVal::mkArr();
    for (auto& b : btns) {
        JPtr jb = JVal::mkObj();
        jb->set(L"label", b.label);
        if (!b.keys.empty())    jb->set(L"keys",  b.keys);
        if (!b.keys2.empty())   jb->set(L"keys2", b.keys2);
        if (b.kind != K_KEY)    jb->set(L"kind",  std::wstring(KIND_NAMES[b.kind % 4]));
        if (b.span > 1)         jb->set(L"span",  (double)b.span);
        if (b.mouse != PB_NONE) jb->set(L"mouse", std::wstring(MOUSE_NAMES[b.mouse]));
        jb->set(L"mode", std::wstring(MODE_NAMES[b.mode % 3]));
        if (b.repeat)           jb->set(L"repeat", true);
        if (!b.page.empty())    jb->set(L"page", b.page);
        arr->add(jb);
    }
    return arr;
}

static void JsonToBtns(const JVal* arr, std::vector<Btn>& out) {
    if (!arr || arr->type != JVal::ARR) return;
    for (auto& jb : arr->arr) {
        if (!jb || jb->type != JVal::OBJ) continue;
        Btn b;
        b.label  = jb->gets(L"label", L"?");
        b.keys   = jb->gets(L"keys", L"");
        b.keys2  = jb->gets(L"keys2", L"");
        b.kind   = NameIdx(jb->gets(L"kind", L"key"), KIND_NAMES, 4, K_KEY);
        b.span   = (int)jb->getn(L"span", 1);
        if (b.span < 1) b.span = 1;
        if (b.span > 6) b.span = 6;
        b.page   = jb->gets(L"page", L"");
        b.mouse  = NameIdx(jb->gets(L"mouse", L""), MOUSE_NAMES, 6, PB_NONE);
        b.mode   = NameIdx(jb->gets(L"mode", L"tap"), MODE_NAMES, 3, M_TAP);
        b.repeat = jb->getb(L"repeat", false);
        BtnCompile(b);
        out.push_back(b);
    }
}

bool ConfigSave() {
    JPtr root = JVal::mkObj();
    root->set(L"version", 6.0);
    root->set(L"edge",        std::wstring(EDGE_NAMES[g_cfg.edge  & 3]));
    root->set(L"align",       std::wstring(ALIGN_NAMES[g_cfg.align % 3]));
    root->set(L"buttonMM",    g_cfg.buttonMM);
    root->set(L"opacity",     (double)g_cfg.opacity);
    root->set(L"pushWindows", g_cfg.pushWindows);
    root->set(L"swipe",       g_cfg.swipe);
    root->set(L"handle",      g_cfg.handle);
    root->set(L"showOnStart", g_cfg.showOnStart);
    root->set(L"screenDPI",   g_cfg.screenDPI);

    JPtr profs = JVal::mkArr();
    for (auto& p : g_cfg.profiles) {
        JPtr jp = JVal::mkObj();
        jp->set(L"name",  p.name);
        jp->set(L"match", p.match);
        jp->set(L"buttons", BtnsToJson(p.btns));
        if (!p.pages.empty()) {
            JPtr pages = JVal::mkArr();
            for (auto& pg : p.pages) {
                JPtr jg = JVal::mkObj();
                jg->set(L"name", pg.name);
                jg->set(L"buttons", BtnsToJson(pg.btns));
                pages->add(jg);
            }
            jp->set(L"pages", pages);
        }
        profs->add(jp);
    }
    root->set(L"profiles", profs);

    std::wstring text;
    JsonWrite(root, text);
    std::string utf8 = W2U(text);

    std::wstring tmp = ConfigPath() + L".tmp";
    HANDLE h = CreateFileW(tmp.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
                           FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h == INVALID_HANDLE_VALUE) { Log(L"не удалось записать настройки (%u)", GetLastError()); return false; }
    DWORD wr = 0;
    WriteFile(h, utf8.data(), (DWORD)utf8.size(), &wr, nullptr);
    CloseHandle(h);
    // пишем через временный файл: обрыв питания на планшете не должен
    // оставлять обрезанные настройки вместо рабочих
    if (!MoveFileExW(tmp.c_str(), ConfigPath().c_str(), MOVEFILE_REPLACE_EXISTING)) {
        Log(L"не удалось заменить файл настроек (%u)", GetLastError());
        return false;
    }
    return true;
}

// Файл настроек у человека уже лежит, и defaults до него не доходят, поэтому
// правки набора доносим сюда. Площадку обзора и джойстик убираем: камерой
// водят мышью, а W A S D на полоске не нужны — нужны Q и E.
static void ConfigUpgrade(Config& c, double ver) {
    if (ver >= 6.0) return;
    // Набор Unreal пересобираем начисто. Чинить накопившееся по кусочкам уже
    // нельзя: в файле у человека успели полежать и разовая кнопка «ПКМ»
    // (она давала щелчок вместо удержания), и отдельные W A S D, и площадки,
    // которые следующая же правка удаляла. Один заход, один понятный итог.
    for (auto& p : c.profiles) {
        if (LowerW(p.match).find(L"unreal") == std::wstring::npos) continue;
        p.btns = UnrealBtns();
        for (auto& b : p.btns) BtnCompile(b);
        Log(L"набор \"%s\" пересобран начисто", p.name.c_str());
    }
}

bool ConfigLoad() {
    HANDLE h = CreateFileW(ConfigPath().c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
                           OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h == INVALID_HANDLE_VALUE) return false;
    DWORD size = GetFileSize(h, nullptr);
    std::string buf(size, 0);
    DWORD rd = 0;
    ReadFile(h, &buf[0], size, &rd, nullptr);
    CloseHandle(h);
    buf.resize(rd);
    if (buf.size() >= 3 && (unsigned char)buf[0] == 0xEF) buf = buf.substr(3);   // BOM

    JPtr root = JsonParse(U2W(buf));
    if (!root || root->type != JVal::OBJ) { Log(L"файл настроек испорчен, беру набор по умолчанию"); return false; }

    Config c;
    c.edge        = NameIdx(root->gets(L"edge",  L"left"),   EDGE_NAMES,  4, E_LEFT);
    c.align       = NameIdx(root->gets(L"align", L"center"), ALIGN_NAMES, 3, A_CENTER);
    c.buttonMM    = root->getn(L"buttonMM", 11.5);
    c.opacity     = (int)root->getn(L"opacity", 232);
    c.pushWindows = root->getb(L"pushWindows", true);
    c.swipe       = root->getb(L"swipe", true);
    c.handle      = root->getb(L"handle", true);
    c.showOnStart = root->getb(L"showOnStart", true);
    c.screenDPI   = root->getn(L"screenDPI", 0);
    if (c.buttonMM < 6 || c.buttonMM > 40) c.buttonMM = 11.5;
    if (c.opacity < 60 || c.opacity > 255) c.opacity = 232;

    const JVal* profs = root->get(L"profiles");
    if (profs && profs->type == JVal::ARR) {
        for (auto& jp : profs->arr) {
            if (!jp || jp->type != JVal::OBJ) continue;
            Profile p;
            p.name  = jp->gets(L"name", L"Набор");
            p.match = jp->gets(L"match", L"");
            JsonToBtns(jp->get(L"buttons"), p.btns);
            const JVal* pages = jp->get(L"pages");
            if (pages && pages->type == JVal::ARR) {
                for (auto& jg : pages->arr) {
                    if (!jg || jg->type != JVal::OBJ) continue;
                    Page pg;
                    pg.name = jg->gets(L"name", L"Страница");
                    JsonToBtns(jg->get(L"buttons"), pg.btns);
                    p.pages.push_back(pg);
                }
            }
            c.profiles.push_back(p);
        }
    }
    if (c.profiles.empty()) { Log(L"в настройках нет ни одного набора кнопок"); return false; }

    ConfigUpgrade(c, root->getn(L"version", 1.0));
    g_cfg = c;
    Log(L"настройки прочитаны: %d набор(ов)", (int)g_cfg.profiles.size());
    return true;
}
