# Скевоморфный скин «Чертёжный стол» — сборка в index.html.
#
# Исходник скина — модули skin/01…05-*.css, подробно прокомментированные:
# что за материал, откуда свет, почему именно этот селектор и чего нельзя
# трогать. Комментарии — это документация, и их втрое больше самих правил,
# поэтому в index.html они НЕ кладутся: сборщик вырезает их и вставляет
# чистые правила между метками CF-SKEUO-START/END (блок <style id="cf-skeuo">
# сразу после темы). Так же устроен справочник (build-handbook.py): правят
# исходник рядом, а не блок внутри index.html — следующая сборка его затрёт.
#
# Запуск из корня репозитория:  python3 build-skin.py
#
# Проверки, на которых сборка падает (а не выходит молча с поломкой):
#   · скобки правил не сходятся — обрыв правила уронил бы весь блок;
#   · внутри CSS теги (</style>, <script>) — закрыли бы блок стилей;
#   · @media print — печать скин не трогает (правила печати живут в двух
#     местах и обязаны совпадать, см. CLAUDE.md, «Гайд на печати»).
import io, os, re, sys, glob

ROOT = os.path.dirname(os.path.abspath(__file__))

def strip_comments(css):
    # Вырезает /* … */ ВНЕ строк: в url("data:image/svg+xml,…") может
    # встретиться что угодно, и регулярка по всему файлу однажды съела бы
    # кусок картинки. Строки в кавычках копируются как есть.
    out, i, n, q = [], 0, len(css), None
    while i < n:
        c = css[i]
        if q:
            out.append(c)
            if c == '\\' and i + 1 < n:
                out.append(css[i + 1]); i += 2; continue
            if c == q: q = None
            i += 1; continue
        if c in '"\'':
            q = c; out.append(c); i += 1; continue
        if css.startswith('/*', i):
            j = css.find('*/', i + 2)
            if j < 0: sys.exit('build-skin: незакрытый комментарий')
            i = j + 2; continue
        out.append(c); i += 1
    s = ''.join(out)
    s = re.sub(r'[ \t]+\n', '\n', s)
    return re.sub(r'\n\s*\n+', '\n', s).strip() + '\n'

def braces_ok(css):
    depth, q = 0, None
    for c in css:
        if q:
            if c == q: q = None
            continue
        if c in '"\'': q = c
        elif c == '{': depth += 1
        elif c == '}':
            depth -= 1
            if depth < 0: return False
    return depth == 0

files = sorted(glob.glob(os.path.join(ROOT, 'skin', '[0-9][0-9]-*.css')))
if not files:
    sys.exit('build-skin: нет модулей в skin/')
parts, bad = [], 0
for f in files:
    name = os.path.basename(f)
    raw = io.open(f, encoding='utf-8').read()
    css = strip_comments(raw)
    if not braces_ok(css):
        print(f'!! {name}: скобки правил не сходятся'); bad += 1
    if re.search(r'</style|<script', css, re.I):
        print(f'!! {name}: внутри CSS не место тегам'); bad += 1
    if re.search(r'@media\s+print', css):
        print(f'!! {name}: печать скин не трогает'); bad += 1
    parts.append(f'/* {name} */\n' + css)
if bad:
    sys.exit(1)

p = os.path.join(ROOT, 'index.html')
s = io.open(p, encoding='utf-8').read()
a, b = '    <style id="cf-skeuo">\n', '    </style>\n    <!-- CF-SKEUO-END -->'
if s.count(a) != 1 or s.count(b) != 1:
    sys.exit('build-skin: в index.html нет меток блока скина')
i, j = s.index(a) + len(a), s.index(b)
body = ''.join(parts)
s = s[:i] + body + s[j:]
io.open(p, 'w', encoding='utf-8').write(s)
src = sum(os.path.getsize(f) for f in files)
print(f'build-skin: {len(files)} модулей, исходник {src // 1024} КБ → в index.html {len(body.encode("utf-8")) // 1024} КБ')
