#!/usr/bin/env python3
"""
Stand-in for the Unreal plugin: the same page, the same protocol, no Unreal.

Use it to check the Steam Deck side (network, browser, button mapping) before touching the project:
    python tools/mock_server.py            -> open http://<this PC>:8787 on the Deck
    python tools/mock_server.py --jpeg some.jpg --port 8787

Only the standard library. Prints every command it receives, so you can see what each button sends.
"""
import argparse
import asyncio
import base64
import hashlib
import json
import os
import struct
import time

HERE = os.path.dirname(os.path.abspath(__file__))
PAGE = os.path.join(HERE, '..', 'Plugins', 'DeckCam', 'Resources', 'Web', 'index.html')
GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'
SPEEDS = [0.5, 1, 3, 10, 30, 100, 300]


class State:
    def __init__(self):
        self.mode = 'cine'
        self.si = 3
        self.foc = 35.0
        self.tilt = 0.0
        self.rec = False
        self.rec_t0 = 0.0
        self.targets = ['Su-27_01', 'Su-27_02', 'Tanker']
        self.ti = 0
        self.att = ''
        self.play = False
        self.pilot = True
        self.inp = {}
        self.last_in = 0.0
        self.commands = []   # log for tests
        self.inputs = 0

    def status(self, vfps):
        return {
            't': 'st', 'mode': self.mode, 'spd': SPEEDS[self.si], 'si': self.si, 'sn': len(SPEEDS),
            'foc': self.foc, 'tilt': self.tilt, 'vel': 0, 'rec': self.rec,
            'rt': time.time() - self.rec_t0 if self.rec else 0, 'tgt': self.targets[self.ti],
            'tn': len(self.targets), 'ti': self.ti, 'att': self.att, 'seq': True, 'play': self.play,
            'pilot': self.pilot, 'video': True, 'vfps': vfps,
        }

    def command(self, c):
        self.commands.append(c)
        msg = None
        if c == 'rec':
            self.rec = not self.rec
            self.rec_t0 = time.time()
            msg = ('rec_start' if self.rec else 'rec_stop', '')
            self.play = self.rec
        elif c == 'spd+':
            self.si = min(self.si + 1, len(SPEEDS) - 1)
        elif c == 'spd-':
            self.si = max(self.si - 1, 0)
        elif c == 'mode':
            self.mode = 'fpv' if self.mode == 'cine' else 'cine'
            msg = ('mode_' + self.mode, '')
        elif c == 'tgt+':
            self.ti = (self.ti + 1) % len(self.targets)
        elif c == 'tgt-':
            self.ti = (self.ti - 1) % len(self.targets)
        elif c == 'attach':
            if self.att:
                msg = ('detached', self.att)
                self.att = ''
            else:
                self.att = self.targets[self.ti]
                msg = ('attached', self.att)
        elif c == 'play':
            self.play = not self.play
        elif c == 'rewind':
            self.play = False
        elif c == 'pilot':
            self.pilot = not self.pilot
            msg = ('pilot_on' if self.pilot else 'pilot_off', '')
        elif c == 'level':
            self.tilt = 0.0
        return msg

    def tick(self, dt):
        if time.time() - self.last_in > 0.3:
            self.inp = {}
        z = self.inp.get('zm', 0)
        self.foc = max(12.0, min(300.0, self.foc * pow(2.718, z * 0.7 * dt)))
        self.tilt = max(-90.0, min(30.0, self.tilt + self.inp.get('tl', 0) * 45 * dt))


def ws_frame(opcode, payload):
    n = len(payload)
    if n < 126:
        head = struct.pack('!BB', 0x80 | opcode, n)
    elif n < 65536:
        head = struct.pack('!BBH', 0x80 | opcode, 126, n)
    else:
        head = struct.pack('!BBQ', 0x80 | opcode, 127, n)
    return head + payload


class Server:
    def __init__(self, jpeg, fps):
        self.state = State()
        self.jpeg = jpeg
        self.fps = fps
        self.clients = []

    async def handle(self, reader, writer):
        try:
            head = await reader.readuntil(b'\r\n\r\n')
        except Exception:
            writer.close()
            return
        lines = head.decode('latin1').split('\r\n')
        path = lines[0].split(' ')[1] if len(lines[0].split(' ')) > 1 else '/'
        headers = {}
        for ln in lines[1:]:
            if ':' in ln:
                k, v = ln.split(':', 1)
                headers[k.strip().lower()] = v.strip()
        if headers.get('upgrade', '').lower() == 'websocket':
            key = headers.get('sec-websocket-key', '')
            acc = base64.b64encode(hashlib.sha1((key + GUID).encode()).digest()).decode()
            writer.write(('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n'
                          'Sec-WebSocket-Accept: %s\r\n\r\n' % acc).encode())
            await writer.drain()
            await self.websocket(reader, writer)
            return
        if path == '/' or path.startswith('/?') or path == '/index.html':
            with open(PAGE, 'rb') as f:
                body = f.read()
            writer.write(b'HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\n'
                         b'Content-Length: %d\r\nConnection: close\r\n\r\n' % len(body) + body)
        else:
            writer.write(b'HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n')
        await writer.drain()
        writer.close()

    async def websocket(self, reader, writer):
        client = {'w': writer, 'ready': True, 'sent_at': 0}
        self.clients.append(client)
        print('controller connected')
        try:
            while True:
                b0, b1 = await reader.readexactly(2)
                op = b0 & 0x0F
                n = b1 & 0x7F
                if n == 126:
                    n = struct.unpack('!H', await reader.readexactly(2))[0]
                elif n == 127:
                    n = struct.unpack('!Q', await reader.readexactly(8))[0]
                mask = await reader.readexactly(4) if b1 & 0x80 else b'\0\0\0\0'
                data = bytearray(await reader.readexactly(n))
                for i in range(n):
                    data[i] ^= mask[i & 3]
                if op == 8:
                    break
                if op == 9:
                    writer.write(ws_frame(0xA, bytes(data)))
                    continue
                if op != 1:
                    continue
                m = json.loads(data.decode('utf-8'))
                t = m.get('t')
                if t == 'ack':
                    client['ready'] = True
                elif t == 'in':
                    self.state.inp = m
                    self.state.last_in = time.time()
                    self.state.inputs += 1
                elif t == 'cmd':
                    print('command:', m.get('c'))
                    msg = self.state.command(m.get('c'))
                    if msg:
                        self.broadcast({'t': 'msg', 'code': msg[0], 'text': msg[1]})
                    self.broadcast(self.state.status(self.fps))
                elif t == 'hello':
                    self.broadcast(self.state.status(self.fps))
        except (asyncio.IncompleteReadError, ConnectionError):
            pass
        finally:
            self.clients.remove(client)
            print('controller disconnected')
            writer.close()

    def broadcast(self, obj):
        frame = ws_frame(1, json.dumps(obj).encode())
        for c in self.clients:
            c['w'].write(frame)

    async def loop(self):
        last = time.time()
        next_status = 0
        next_frame = 0
        while True:
            await asyncio.sleep(0.01)
            now = time.time()
            self.state.tick(now - last)
            last = now
            if now >= next_status:
                next_status = now + 0.1
                self.broadcast(self.state.status(self.fps))
            if self.jpeg and now >= next_frame:
                next_frame = now + 1.0 / self.fps
                for c in self.clients:
                    if c['ready'] or now - c['sent_at'] > 1.0:
                        c['w'].write(ws_frame(2, self.jpeg))
                        c['ready'] = False
                        c['sent_at'] = now


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--port', type=int, default=8787)
    ap.add_argument('--jpeg', help='a JPEG to stream as the "camera"')
    ap.add_argument('--fps', type=int, default=30)
    a = ap.parse_args()
    jpeg = open(a.jpeg, 'rb').read() if a.jpeg else None
    srv = Server(jpeg, a.fps)
    server = await asyncio.start_server(srv.handle, '0.0.0.0', a.port)
    print('DeckCam mock on port %d. Open http://<this computer>:%d on the Deck.' % (a.port, a.port))
    asyncio.get_running_loop().create_task(srv.loop())
    async with server:
        await server.serve_forever()


if __name__ == '__main__':
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
