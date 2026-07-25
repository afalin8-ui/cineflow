#!/usr/bin/env node
/*
 * CineLight — мост Art-Net.
 * Принимает DMX-пакеты от пульта (cinelight.html) по WebSocket и рассылает их
 * в локальную сеть как Art-Net (UDP, порт 6454). Заодно раздаёт сам пульт по
 * адресу http://<ip-компьютера>:9070 — удобно открывать на iPad.
 *
 * Запуск:  node cinelight-bridge.js            → Art-Net всем в сети (broadcast)
 *          node cinelight-bridge.js 192.168.1.60 → Art-Net только на этот IP
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
const target = process.argv[2] || '255.255.255.255';

const udp = dgram.createSocket('udp4');
udp.bind(() => { try { udp.setBroadcast(true); } catch (e) {} });
udp.on('error', () => {});

function log(msg) { console.log(new Date().toLocaleTimeString() + '  ' + msg); }

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
    log('Пульт подключился (' + (req.socket.remoteAddress || '?') + ')');

    let buf = Buffer.alloc(0);
    let gotFirst = false;
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
            if (op === 8) { try { socket.end(); } catch (e) {} return; }
            if (op === 9) { // ping → pong
                const p = payload.slice(0, 125);
                try { socket.write(Buffer.concat([Buffer.from([0x8a, p.length]), p])); } catch (e) {}
                continue;
            }
            if (op === 2 && payload.length > 0) {
                udp.send(payload, ARTNET_PORT, target);
                if (!gotFirst) { gotFirst = true; log('Пошли DMX-кадры → ' + target + ':' + ARTNET_PORT); }
            }
        }
    });
    socket.on('error', () => {});
    socket.on('close', () => log('Пульт отключился'));
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
    console.log('  CineLight — мост Art-Net');
    console.log('  ------------------------');
    const ips = [];
    Object.values(os.networkInterfaces()).forEach(list => (list || []).forEach(i => {
        if (i.family === 'IPv4' && !i.internal) ips.push(i.address);
    }));
    if (ips.length === 0) ips.push('localhost');
    ips.forEach(ip => console.log('  Откройте на iPad или компьютере:  http://' + ip + ':' + PORT));
    console.log('  Art-Net уходит на: ' + target + ':' + ARTNET_PORT +
        (process.argv[2] ? '' : '  (всем в сети; свой IP приёмника: node cinelight-bridge.js 192.168.1.60)'));
    console.log('  В пульте: Настройки → «Подключить мост». Окно не закрывайте.');
    console.log('');
});
