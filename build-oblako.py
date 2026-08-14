# Инструкция живёт в двух видах и собирается из ОДНОГО источника,
# чтобы они не разъехались:
#   scratchpad/oblako.html — для артефакта: без doctype и <head>,
#       площадка добавляет их сама;
#   cineflow/oblako.html   — отдельная страница в репозитории: та же
#       разметка, но с полной обвязкой. Без явной кодировки русский
#       текст едет в кракозябры на любом сервере, который не подставит
#       charset за нас.
import io, re

SRC = '/tmp/claude-0/-home-user-cineflow/9cfa3e1f-3640-5efc-8101-3df591eedd25/scratchpad/oblako.html'
DST = '/home/user/cineflow/oblako.html'

body = io.open(SRC, encoding='utf-8').read()

m = re.search(r'<title>(.*?)</title>', body)
title = m.group(1) if m else 'Своё облако для фотографий'
body = body.replace(m.group(0), '', 1) if m else body

page = (
    '<!doctype html>\n'
    '<html lang="ru">\n'
    '<head>\n'
    '<meta charset="utf-8">\n'
    '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
    '<meta name="color-scheme" content="light dark">\n'
    f'<title>{title} — CineFlow</title>\n'
    '<link rel="icon" href="./icon.svg">\n'
    + body.lstrip() +
    '\n</body>\n</html>\n'
)
# <style> и <script> из источника попадают в <head>/<body> как есть;
# закрываем head сразу после стилей, чтобы разметка была правильной.
page = page.replace('</style>\n', '</style>\n</head>\n<body>\n', 1)

io.open(DST, 'w', encoding='utf-8').write(page)
print('собрано:', DST, len(page), 'знаков')
