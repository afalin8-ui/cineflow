/*
 * Сборка библиотеки приборов для CineLight из Open Fixture Library.
 * OFL распространяется по лицензии MIT (© Florian & Felix Edelmann и участники).
 *
 * Как обновить библиотеку:
 *   1) curl -L https://open-fixture-library.org/download.ofl -o ofl-all.zip
 *   2) unzip -q ofl-all.zip -d ofl
 *   3) node tools-build-fixture-library.js
 *   4) содержимое cinelight-fixtures.json вставить в cinelight.html
 *      внутрь <script type="application/json" id="cl-fixture-lib">…</script>
 *
 * Роли каналов те же, что в самом пульте. Каналы, которыми мы не управляем
 * (гобо, макросы, программы), получают «значение покоя» dv — для шторки это
 * диапазон «открыто», иначе прибор молча не зажжётся.
 */
const fs = require('fs'), path = require('path');

const REASONS = {};
const COLOR_ROLE = {
    Red: 'r', Green: 'g', Blue: 'b', White: 'w', Amber: 'a', UV: 'uv',
    'Warm White': 'w', 'Cold White': 'w', Lime: 'g', Indigo: 'b'
};
const FINE_OF = { dim: 'dimF', pan: 'panF', tilt: 'tiltF', hue: 'hueF' };

function roleOfChannel(chDef, name) {
    const n = (name || '').toLowerCase();
    // тон зелёный/пурпурный и HSI OFL описывает как Generic — узнаём по названию
    if (/green[-\/ ]?magenta|g\/m\b|(^|\W)tint(\W|$)|plus green/.test(n)) return 'gm';
    if (/(^|\W)hue(\W|$)/.test(n)) return 'hue';
    if (/saturation/.test(n)) return 'sat';
    if (!chDef) return 'none';
    const caps = chDef.capabilities || (chDef.capability ? [chDef.capability] : []);
    if (caps.length === 0) return 'none';
    // берём самый частый осмысленный тип
    const first = caps[0];
    switch (first.type) {
        case 'Intensity': return 'dim';
        case 'ColorIntensity': return COLOR_ROLE[first.color] || 'none';
        case 'ColorTemperature': return 'cct';
        case 'Pan': return 'pan';
        case 'Tilt': return 'tilt';
        case 'Zoom': return 'zoom';
        case 'Focus': return 'focus';
        case 'ShutterStrobe': return 'strobe';
        default: return 'none';
    }
}

function pctToByte(v) {
    if (v === undefined || v === null) return null;
    if (typeof v === 'number') return Math.max(0, Math.min(255, Math.round(v)));
    const str = String(v).trim();
    if (/%$/.test(str)) return Math.round(parseFloat(str) / 100 * 255);
    const n = parseInt(str, 10);
    return isNaN(n) ? null : Math.max(0, Math.min(255, n));
}

/* Байт, который надо выставить, если мы этим каналом не управляем.
   Для шторки берём диапазон «открыто» — иначе прибор молча не зажжётся. */
function idleByte(def) {
    if (!def) return null;
    const caps = def.capabilities || (def.capability ? [def.capability] : []);
    const open = caps.find(c => c.type === 'ShutterStrobe' && c.shutterEffect === 'Open');
    if (open && Array.isArray(open.dmxRange)) {
        const [a, b] = open.dmxRange;
        const res = def.dmxValueResolution === '16bit' ? 65535 : 255;
        return Math.round(((a + b) / 2) * 255 / res);
    }
    const hasShutter = caps.some(c => c.type === 'ShutterStrobe');
    if (hasShutter) return 255;
    const d = pctToByte(def.defaultValue);
    return d || null;
}

function buildResolver(fx) {
    const avail = fx.availableChannels || {};
    const fine = {};   // имя тонкого канала → [базовое имя, номер]
    Object.entries(avail).forEach(([name, def]) => {
        (def.fineChannelAliases || []).forEach((alias, i) => { fine[alias] = [name, i]; });
    });
    const tmpl = fx.templateChannels || {};
    Object.entries(tmpl).forEach(([name, def]) => {
        (def.fineChannelAliases || []).forEach((alias, i) => { fine[alias] = [name, i]; });
    });
    return (chName, isTemplate) => {
        if (chName === null || chName === undefined) return 'none';
        if (typeof chName !== 'string') return 'none';
        const table = isTemplate ? { ...avail, ...tmpl } : avail;
        const plain = chName.replace(/\$pixelKey/g, '').replace(/\s+/g, ' ').trim();
        if (table[chName]) return roleOfChannel(table[chName], plain);
        if (table[plain]) return roleOfChannel(table[plain], plain);
        if (fine[chName] || fine[plain]) {
            const [base, idx] = fine[chName] || fine[plain];
            if (idx > 0) return 'none';                       // третий байт не поддерживаем
            const bp = base.replace(/\$pixelKey/g, '').replace(/\s+/g, ' ').trim();
            const r = roleOfChannel(table[base] || avail[base] || tmpl[base], bp);
            return FINE_OF[r] || 'none';
        }
        // переключаемый канал OFL: «Основной / Запасной» — берём основной
        if (chName.indexOf(' / ') > 0) {
            for (const part of chName.split(' / ')) {
                const t = part.trim();
                if (table[t]) return roleOfChannel(table[t], t);
                if (fine[t]) {
                    const [base, idx] = fine[t];
                    if (idx > 0) return 'none';
                    const r = roleOfChannel(table[base] || avail[base] || tmpl[base], base);
                    return FINE_OF[r] || 'none';
                }
            }
            return roleOfChannel(null, chName.split(' / ')[0]);
        }
        return roleOfChannel(null, plain);
    };
}

function pixelCount(fx) {
    const m = fx.matrix;
    if (!m) return 0;
    if (Array.isArray(m.pixelCount)) return m.pixelCount.reduce((a, b) => a * b, 1);
    if (m.pixelKeys) {
        let n = 0;
        const walk = v => Array.isArray(v) ? v.forEach(walk) : (v ? n++ : null);
        walk(m.pixelKeys);
        return n;
    }
    return 0;
}

function convertMode(fx, mode, resolve, lookup) {
    const ch = [], px = [], ch2 = [];
    const dv = {}, dv2 = {};
    let pixels = 0, seenMatrix = false, bad = null;
    for (const entry of mode.channels) {
        if (entry && typeof entry === 'object' && entry.insert === 'matrixChannels') {
            if (seenMatrix) { bad = 'две матрицы'; break; }
            if (entry.channelOrder && entry.channelOrder !== 'perPixel') { bad = 'порядок каналов'; break; }
            const n = pixelCount(fx);
            if (!n) { bad = 'неизвестно число пикселей'; break; }
            const roles = (entry.templateChannels || []).map(c => resolve(c, true));
            if (roles.length === 0 || roles.every(r => r === 'none')) { bad = 'пустая матрица'; break; }
            pixels = n; px.push(...roles); seenMatrix = true;
            continue;
        }
        const role = resolve(entry, false);
        const arr = seenMatrix ? ch2 : ch;
        const map = seenMatrix ? dv2 : ch === arr ? dv : dv;
        if (role === 'none' || role === 'strobe') {
            const iv = idleByte(lookup(entry));
            if (iv) (seenMatrix ? dv2 : dv)[arr.length] = iv;
        }
        arr.push(role);
    }
    if (bad) { REASONS[bad] = (REASONS[bad]||0)+1; return null; }
    const all = ch.concat(px, ch2);
    if (all.length === 0 || all.every(r => r === 'none')) { REASONS['нет полезных каналов'] = (REASONS['нет полезных каналов']||0)+1; return null; }
    const foot = ch.length + px.length * pixels + ch2.length;
    if (foot < 1 || foot > 512) { REASONS['не влезает в 512'] = (REASONS['не влезает в 512']||0)+1; return null; }
    const out = { n: mode.name, ch };
    if (pixels) { out.px = px; out.p = pixels; }
    if (ch2.length) out.ch2 = ch2;
    if (Object.keys(dv).length) out.dv = dv;
    if (Object.keys(dv2).length) out.dv2 = dv2;
    return out;
}

function cctRange(fx) {
    let lo = null, hi = null;
    Object.values(fx.availableChannels || {}).forEach(def => {
        const caps = def.capabilities || (def.capability ? [def.capability] : []);
        caps.forEach(c => {
            if (c.type !== 'ColorTemperature') return;
            const p = v => v ? parseInt(String(v).replace(/[^0-9-]/g, ''), 10) : null;
            const a = p(c.colorTemperatureStart), b = p(c.colorTemperature), d = p(c.colorTemperatureEnd);
            [a, b, d].forEach(v => {
                if (v === null || isNaN(v) || v < 1000 || v > 20000) return;
                lo = lo === null ? v : Math.min(lo, v);
                hi = hi === null ? v : Math.max(hi, v);
            });
        });
    });
    return lo !== null && hi !== null && hi > lo ? [lo, hi] : null;
}

const manufacturers = JSON.parse(fs.readFileSync('ofl/manufacturers.json', 'utf8'));
const brands = {};
let nFix = 0, nModes = 0, skippedModes = 0, skippedFix = 0;

fs.readdirSync('ofl').forEach(manKey => {
    const dir = path.join('ofl', manKey);
    if (!fs.statSync(dir).isDirectory()) return;
    const brandName = (manufacturers[manKey] && manufacturers[manKey].name) || manKey;
    fs.readdirSync(dir).forEach(file => {
        if (!file.endsWith('.json')) return;
        let fx;
        try { fx = JSON.parse(fs.readFileSync(path.join(dir, file), 'utf8')); } catch (e) { return; }
        const resolve = buildResolver(fx);
        const lookup = name => {
            if (typeof name !== 'string') return null;
            const av = fx.availableChannels || {};
            if (av[name]) return av[name];
            if (name.indexOf(' / ') > 0) {
                for (const part of name.split(' / ')) if (av[part.trim()]) return av[part.trim()];
            }
            return null;
        };
        const modes = [];
        (fx.modes || []).forEach(m => {
            const c = convertMode(fx, m, resolve, lookup);
            if (c) modes.push(c); else skippedModes++;
        });
        if (modes.length === 0) { skippedFix++; return; }
        const entry = { m: fx.name, d: modes };
        const cct = cctRange(fx);
        if (cct) entry.c = cct;
        (brands[brandName] = brands[brandName] || []).push(entry);
        nFix++; nModes += modes.length;
    });
});

const list = Object.keys(brands).sort().map(b => ({
    b, f: brands[b].sort((x, y) => x.m.localeCompare(y.m))
}));
const out = {
    source: 'Open Fixture Library (open-fixture-library.org), лицензия MIT',
    generated: new Date().toISOString().slice(0, 10),
    brands: list
};
fs.writeFileSync('cinelight-fixtures.json', JSON.stringify(out));
const size = fs.statSync('cinelight-fixtures.json').size;
console.log('производителей:', list.length, '| приборов:', nFix, '| режимов:', nModes);
console.log('пропущено режимов:', skippedModes, '| приборов без пригодных режимов:', skippedFix);
console.log('причины отказов:', JSON.stringify(REASONS, null, 1));
console.log('размер файла:', (size / 1024).toFixed(0), 'КБ');
