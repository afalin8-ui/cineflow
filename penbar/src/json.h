// Маленький разбор JSON: объекты, массивы, строки, числа, true/false/null.
// Отдельным заголовком, потому что его можно проверить тестом на любой системе,
// а не только на Windows: ошибка в разборе настроек означает пустую панель.
#pragma once
#include <string>
#include <vector>
#include <memory>

struct JVal;
using JPtr = std::shared_ptr<JVal>;

struct JVal {
    enum Type { NUL, BOOL, NUM, STR, ARR, OBJ } type = NUL;
    bool         b = false;
    double       num = 0;
    std::wstring str;
    std::vector<JPtr>                             arr;
    std::vector<std::pair<std::wstring, JPtr>>    obj;

    static JPtr mkObj() { auto v = std::make_shared<JVal>(); v->type = OBJ; return v; }
    static JPtr mkArr() { auto v = std::make_shared<JVal>(); v->type = ARR; return v; }
    static JPtr mkStr(const std::wstring& s) { auto v = std::make_shared<JVal>(); v->type = STR; v->str = s; return v; }
    static JPtr mkNum(double d) { auto v = std::make_shared<JVal>(); v->type = NUM; v->num = d; return v; }
    static JPtr mkBool(bool x) { auto v = std::make_shared<JVal>(); v->type = BOOL; v->b = x; return v; }

    void set(const std::wstring& k, JPtr v) {
        for (auto& p : obj) if (p.first == k) { p.second = v; return; }
        obj.push_back({k, v});
    }
    void set(const std::wstring& k, const std::wstring& v) { set(k, mkStr(v)); }
    void set(const std::wstring& k, double v)              { set(k, mkNum(v)); }
    void set(const std::wstring& k, bool v)                { set(k, mkBool(v)); }
    void add(JPtr v) { arr.push_back(v); }

    const JVal* get(const std::wstring& k) const {
        for (auto& p : obj) if (p.first == k && p.second) return p.second.get();
        return nullptr;
    }
    std::wstring gets(const std::wstring& k, const std::wstring& def = L"") const {
        const JVal* v = get(k); return (v && v->type == STR) ? v->str : def;
    }
    double getn(const std::wstring& k, double def = 0) const {
        const JVal* v = get(k); return (v && v->type == NUM) ? v->num : def;
    }
    bool getb(const std::wstring& k, bool def = false) const {
        const JVal* v = get(k);
        if (!v) return def;
        if (v->type == BOOL) return v->b;
        if (v->type == NUM)  return v->num != 0;
        return def;
    }
};

// ---- разбор ---------------------------------------------------------------
namespace jsonimpl {
inline void skip(const std::wstring& s, size_t& i) {
    while (i < s.size() && (s[i] == L' ' || s[i] == L'\t' || s[i] == L'\r' || s[i] == L'\n')) i++;
}
inline bool parseVal(const std::wstring& s, size_t& i, JPtr& out);

inline bool parseStr(const std::wstring& s, size_t& i, std::wstring& out) {
    if (i >= s.size() || s[i] != L'"') return false;
    i++;
    out.clear();
    while (i < s.size()) {
        wchar_t c = s[i++];
        if (c == L'"') return true;
        if (c == L'\\') {
            if (i >= s.size()) return false;
            wchar_t e = s[i++];
            switch (e) {
                case L'n': out += L'\n'; break;
                case L't': out += L'\t'; break;
                case L'r': out += L'\r'; break;
                case L'b': out += L'\b'; break;
                case L'f': out += L'\f'; break;
                case L'u': {
                    if (i + 4 > s.size()) return false;
                    int code = 0;
                    for (int k = 0; k < 4; k++) {
                        wchar_t h = s[i++];
                        int d = (h >= L'0' && h <= L'9') ? h - L'0'
                              : (h >= L'a' && h <= L'f') ? h - L'a' + 10
                              : (h >= L'A' && h <= L'F') ? h - L'A' + 10 : -1;
                        if (d < 0) return false;
                        code = code * 16 + d;
                    }
                    out += (wchar_t)code;
                    break;
                }
                default: out += e;
            }
        } else out += c;
    }
    return false;
}

inline bool parseVal(const std::wstring& s, size_t& i, JPtr& out) {
    skip(s, i);
    if (i >= s.size()) return false;
    wchar_t c = s[i];
    if (c == L'{') {
        i++;
        out = JVal::mkObj();
        skip(s, i);
        if (i < s.size() && s[i] == L'}') { i++; return true; }
        while (i < s.size()) {
            skip(s, i);
            std::wstring key;
            if (!parseStr(s, i, key)) return false;
            skip(s, i);
            if (i >= s.size() || s[i] != L':') return false;
            i++;
            JPtr v;
            if (!parseVal(s, i, v)) return false;
            out->obj.push_back({key, v});
            skip(s, i);
            if (i < s.size() && s[i] == L',') { i++; continue; }
            if (i < s.size() && s[i] == L'}') { i++; return true; }
            return false;
        }
        return false;
    }
    if (c == L'[') {
        i++;
        out = JVal::mkArr();
        skip(s, i);
        if (i < s.size() && s[i] == L']') { i++; return true; }
        while (i < s.size()) {
            JPtr v;
            if (!parseVal(s, i, v)) return false;
            out->arr.push_back(v);
            skip(s, i);
            if (i < s.size() && s[i] == L',') { i++; continue; }
            if (i < s.size() && s[i] == L']') { i++; return true; }
            return false;
        }
        return false;
    }
    if (c == L'"') {
        std::wstring v;
        if (!parseStr(s, i, v)) return false;
        out = JVal::mkStr(v);
        return true;
    }
    if (!s.compare(i, 4, L"true"))  { i += 4; out = JVal::mkBool(true);  return true; }
    if (!s.compare(i, 5, L"false")) { i += 5; out = JVal::mkBool(false); return true; }
    if (!s.compare(i, 4, L"null"))  { i += 4; out = std::make_shared<JVal>(); return true; }
    {   // число
        size_t st = i;
        if (i < s.size() && (s[i] == L'-' || s[i] == L'+')) i++;
        bool any = false;
        while (i < s.size() && ((s[i] >= L'0' && s[i] <= L'9') || s[i] == L'.' || s[i] == L'e' ||
                                s[i] == L'E' || s[i] == L'-' || s[i] == L'+')) { i++; any = true; }
        if (!any) return false;
        std::wstring t = s.substr(st, i - st);
        out = JVal::mkNum(wcstod(t.c_str(), nullptr));
        return true;
    }
}
} // namespace jsonimpl

inline JPtr JsonParse(const std::wstring& text) {
    size_t i = 0;
    JPtr root;
    if (!jsonimpl::parseVal(text, i, root)) return nullptr;
    return root;
}

// ---- запись ---------------------------------------------------------------
inline void JsonEscape(const std::wstring& s, std::wstring& out) {
    for (wchar_t c : s) {
        switch (c) {
            case L'"':  out += L"\\\""; break;
            case L'\\': out += L"\\\\"; break;
            case L'\n': out += L"\\n";  break;
            case L'\r': out += L"\\r";  break;
            case L'\t': out += L"\\t";  break;
            default:    out += c;
        }
    }
}

inline std::wstring JsonNum(double d) {
    wchar_t buf[64];
    if (d == (long long)d) swprintf(buf, 64, L"%lld", (long long)d);
    else                   swprintf(buf, 64, L"%.4g", d);
    return buf;
}

inline void JsonWrite(const JPtr& v, std::wstring& out, int indent = 0) {
    std::wstring pad(indent * 2, L' '), pad2((indent + 1) * 2, L' ');
    if (!v) { out += L"null"; return; }
    switch (v->type) {
        case JVal::NUL:  out += L"null"; break;
        case JVal::BOOL: out += v->b ? L"true" : L"false"; break;
        case JVal::NUM:  out += JsonNum(v->num); break;
        case JVal::STR:  out += L'"'; JsonEscape(v->str, out); out += L'"'; break;
        case JVal::ARR:
            if (v->arr.empty()) { out += L"[]"; break; }
            out += L"[\n";
            for (size_t i = 0; i < v->arr.size(); i++) {
                out += pad2;
                JsonWrite(v->arr[i], out, indent + 1);
                if (i + 1 < v->arr.size()) out += L',';
                out += L'\n';
            }
            out += pad; out += L']';
            break;
        case JVal::OBJ:
            if (v->obj.empty()) { out += L"{}"; break; }
            out += L"{\n";
            for (size_t i = 0; i < v->obj.size(); i++) {
                out += pad2; out += L'"';
                JsonEscape(v->obj[i].first, out);
                out += L"\": ";
                JsonWrite(v->obj[i].second, out, indent + 1);
                if (i + 1 < v->obj.size()) out += L',';
                out += L'\n';
            }
            out += pad; out += L'}';
            break;
    }
}
