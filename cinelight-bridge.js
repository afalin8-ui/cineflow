#!/usr/bin/env node
/*
 * CineLight — сетевой мост (Art-Net и sACN).
 * Принимает DMX-пакеты от пульта (cinelight.html) по WebSocket и рассылает их
 * в локальную сеть: Art-Net на UDP 6454, sACN (E1.31) на UDP 5568. Протокол
 * определяется по самому пакету. Заодно раздаёт пульт по адресу
 * http://<ip-компьютера>:9070 — удобно открывать на iPad.
 *
 * Запуск:  node cinelight-bridge.js            → всем в сети
 *          node cinelight-bridge.js 192.168.1.60 → только на этот IP
 * Зависимостей нет — нужен только Node.js (nodejs.org).
 */
const http = require('http');
const crypto = require('crypto');
const dgram = require('dgram');
const fs = require('fs');
const path = require('path');
const os = require('os');

const PORT = 9070;
const ARTNET_PORT = 6454;
const SACN_PORT = 5568;
const target = process.argv[2] || '255.255.255.255';

function log(msg) { console.log(new Date().toLocaleTimeString() + '  ' + msg); }

const udp = dgram.createSocket({ type: 'udp4', reuseAddr: true });
udp.bind(() => {
    try { udp.setBroadcast(true); } catch (e) {}
    try { udp.setMulticastTTL(16); } catch (e) {}
});
udp.on('error', () => {});

/* Широковещательные адреса всех сетей компьютера.
   Если в машине и Wi-Fi, и кабель, простой 255.255.255.255 уходит только
   в одну из сетей — и нода в другой ничего не получает. Поэтому шлём
   в каждую сеть её собственный broadcast. */
function broadcastAddrs() {
    const out = [];
    Object.values(os.networkInterfaces()).forEach(list => (list || []).forEach(i => {
        if (i.family !== 'IPv4' || i.internal || !i.netmask) return;
        const ip = i.address.split('.').map(Number);
        const mask = i.netmask.split('.').map(Number);
        if (ip.length !== 4 || mask.length !== 4) return;
        out.push(ip.map((o, k) => (o & mask[k]) | (~mask[k] & 255)).join('.'));
    }));
    return out.filter((v, k, a) => a.indexOf(v) === k);
}

let artTargets = process.argv[2] ? [target] : (broadcastAddrs().length ? broadcastAddrs() : [target]);
// сети могут появиться позже (подключили Wi-Fi) — пересматриваем раз в 5 секунд
if (!process.argv[2]) setInterval(() => {
    const fresh = broadcastAddrs();
    if (fresh.length && fresh.join() !== artTargets.join()) {
        artTargets = fresh;
        log('Сети изменились, Art-Net теперь уходит на: ' + artTargets.join(', '));
    }
}, 5000);

/* Пульт шлёт готовые пакеты: Art-Net или sACN. Различаем по первым байтам
   и отправляем каждый по своим правилам — sACN идёт в мультикаст-группу,
   номер которой зависит от юниверса. */
function routePacket(buf) {
    if (buf.length >= 8 && buf.toString('ascii', 0, 7) === 'Art-Net') {
        artTargets.forEach(a => udp.send(buf, ARTNET_PORT, a));
        return 'artnet';
    }
    if (buf.length >= 126 && buf.readUInt16BE(0) === 0x0010 && buf.toString('ascii', 4, 13) === 'ASC-E1.17') {
        const universe = buf.readUInt16BE(113);
        // если задан конкретный приёмник — шлём ему, иначе в стандартный мультикаст
        const addr = process.argv[2] ? target : '239.255.' + ((universe >> 8) & 255) + '.' + (universe & 255);
        udp.send(buf, SACN_PORT, addr);
        return 'sacn';
    }
    return null;
}

/* Все подключённые пульты. Текстовые сообщения (не DMX) мост пересылает
   остальным — так оператор и пультовик видят одну и ту же картину. */
const peers = new Set();

function frameText(str) {
    const body = Buffer.from(str, 'utf8');
    let head;
    if (body.length < 126) {
        head = Buffer.from([0x81, body.length]);
    } else if (body.length < 65536) {
        head = Buffer.alloc(4);
        head[0] = 0x81; head[1] = 126; head.writeUInt16BE(body.length, 2);
    } else {
        head = Buffer.alloc(10);
        head[0] = 0x81; head[1] = 127; head.writeBigUInt64BE(BigInt(body.length), 2);
    }
    return Buffer.concat([head, body]);
}

function relay(str, from) {
    const packet = frameText(str);
    peers.forEach(s => {
        if (s === from || s.destroyed) return;
        try { s.write(packet); } catch (e) {}
    });
}

const server = http.createServer((req, res) => {
    if (req.url === '/' || req.url === '/index.html' || req.url === '/cinelight.html') {
        fs.readFile(path.join(__dirname, 'cinelight.html'), (err, data) => {
            res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
            if (err) {
                res.end('<meta charset="utf-8"><body style="font-family:sans-serif;background:#1a1918;color:#f0eee6;padding:40px">' +
                        '<h2>Мост CineLight работает</h2>' +
                        '<p>Чтобы пульт открывался прямо по этому адресу, положите файл cinelight.html в ту же папку, где лежит мост.</p></body>');
                return;
            }
            res.end(data);
        });
    } else {
        res.writeHead(404); res.end();
    }
});

server.on('upgrade', (req, socket) => {
    const key = req.headers['sec-websocket-key'];
    if (!key) { socket.destroy(); return; }
    const accept = crypto.createHash('sha1').update(key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
    socket.write('HTTP/1.1 101 Switching Protocols\r\n' +
                 'Upgrade: websocket\r\nConnection: Upgrade\r\n' +
                 'Sec-WebSocket-Accept: ' + accept + '\r\n\r\n');
    socket.setNoDelay(true);
    peers.add(socket);
    log('Пульт подключился (' + (req.socket.remoteAddress || '?') + '), всего пультов: ' + peers.size);
    // новичку сообщаем, что он не один — он попросит проект у напарника
    if (peers.size > 1) relay(JSON.stringify({ t: 'peers', n: peers.size }));

    let buf = Buffer.alloc(0);
    let gotFirst = null;
    socket.on('data', chunk => {
        buf = Buffer.concat([buf, chunk]);
        while (true) {
            if (buf.length < 2) break;
            const op = buf[0] & 0x0f;
            const masked = buf[1] & 0x80;
            let len = buf[1] & 0x7f, off = 2;
            if (len === 126) { if (buf.length < 4) break; len = buf.readUInt16BE(2); off = 4; }
            else if (len === 127) { if (buf.length < 10) break; len = Number(buf.readBigUInt64BE(2)); off = 10; }
            const dataOff = off + (masked ? 4 : 0);
            if (buf.length < dataOff + len) break;
            let payload = buf.slice(dataOff, dataOff + len);
            if (masked) {
                const mask = buf.slice(off, off + 4);
                payload = Buffer.from(payload);
                for (let i = 0; i < payload.length; i++) payload[i] ^= mask[i & 3];
            }
            buf = buf.slice(dataOff + len);
            if (op === 8) { peers.delete(socket); try { socket.end(); } catch (e) {} return; }
            if (op === 9) { // ping → pong
                const p = payload.slice(0, 125);
                try { socket.write(Buffer.concat([Buffer.from([0x8a, p.length]), p])); } catch (e) {}
                continue;
            }
            if (op === 1) { // текст — это синхронизация пультов, не DMX
                relay(payload.toString('utf8'), socket);
                continue;
            }
            if (op === 2 && payload.length > 0) {
                const kind = routePacket(payload);
                if (kind && kind !== gotFirst) {
                    gotFirst = kind;
                    log(kind === 'sacn'
                        ? 'Пошли кадры sACN → ' + (process.argv[2] ? target : 'мультикаст 239.255.x.x') + ':' + SACN_PORT
                        : 'Пошли кадры Art-Net → ' + artTargets.join(', ') + ':' + ARTNET_PORT);
                }
            }
        }
    });
    socket.on('error', () => {});
    socket.on('close', () => {
        peers.delete(socket);
        log('Пульт отключился, осталось: ' + peers.size);
        relay(JSON.stringify({ t: 'peers', n: peers.size }));
    });
});

server.on('error', err => {
    if (err.code === 'EADDRINUSE') {
        console.log('Порт ' + PORT + ' уже занят — возможно, мост уже запущен в другом окне.');
    } else {
        console.log('Ошибка: ' + err.message);
    }
    process.exit(1);
});

server.listen(PORT, () => {
    console.log('');
    console.log('  CineLight — сетевой мост (Art-Net / sACN)');
    console.log('  -----------------------------------------');
    const ips = [];
    Object.values(os.networkInterfaces()).forEach(list => (list || []).forEach(i => {
        if (i.family === 'IPv4' && !i.internal) ips.push(i.address);
    }));
    if (ips.length === 0) ips.push('localhost');
    ips.forEach(ip => console.log('  Откройте на iPad или компьютере:  http://' + ip + ':' + PORT));
    if (process.argv[2]) {
        console.log('  Art-Net и sACN уходят на: ' + target);
    } else {
        console.log('  Art-Net уходит в сети: ' + artTargets.join(', ') + '  (порт ' + ARTNET_PORT + ')');
        console.log('  sACN уходит в мультикаст 239.255.x.x:' + SACN_PORT + ' — как требует стандарт');
        console.log('  Нода не отвечает? Укажите её адрес: cinelight-bridge.bat 192.168.1.60');
    }
    console.log('');
    console.log('  Если Windows спросит про доступ в сеть — разрешите, иначе');
    console.log('  ни iPad, ни нода до моста не достучатся.');
    console.log('  В пульте: Настройки → «Подключить мост». Окно не закрывайте.');
    console.log('');
});
