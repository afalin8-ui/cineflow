// Checks the Deck page against tools/mock_server.py in Chromium at the Deck's 1280x800.
// The gamepad is faked through navigator.getGamepads; everything else is real (WebSocket, JPEG, acks).
// Run: node tests/page-e2e.js
const { chromium } = require('playwright');
const { spawn } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const PORT = 8799;
let failed = 0;
const ok = (cond, what) => { console.log((cond ? 'ok   ' : 'FAIL ') + what); if (!cond) failed++; };
const sleep = ms => new Promise(r => setTimeout(r, ms));

(async () => {
  const browser = await chromium.launch();

  // 1. A test "camera" JPEG: flat terracotta, easy to find by color.
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'deckcam-'));
  const jpegPath = path.join(tmp, 'cam.jpg');
  {
    const p = await browser.newPage();
    const b64 = await p.evaluate(() => {
      const c = document.createElement('canvas'); c.width = 960; c.height = 402;
      const x = c.getContext('2d'); x.fillStyle = '#d97757'; x.fillRect(0, 0, 960, 402);
      return c.toDataURL('image/jpeg', 0.9).split(',')[1];
    });
    fs.writeFileSync(jpegPath, Buffer.from(b64, 'base64'));
    await p.close();
  }

  const mock = spawn('python3', [path.join(ROOT, 'tools/mock_server.py'), '--port', String(PORT), '--jpeg', jpegPath, '--fps', '30']);
  let log = '';
  mock.stdout.on('data', d => { log += d; });
  mock.stderr.on('data', d => { log += d; });
  await sleep(800);

  const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 }, hasTouch: true });
  await ctx.addInitScript(() => {
    const btn = () => ({ pressed: false, value: 0 });
    // As on the Deck: the browser lists the raw controller FIRST (held by Steam, never changes),
    // and Steam's virtual pad second. The page must listen to the one that moves.
    window.__dead = { connected: true, id: 'Valve Steam Deck (raw)', index: 0, mapping: 'standard', axes: [0, 0, 0, 0], buttons: Array.from({ length: 17 }, btn) };
    window.__pad = { connected: true, id: 'Steam Virtual Gamepad', index: 1, mapping: 'standard', axes: [0, 0, 0, 0], buttons: Array.from({ length: 17 }, btn) };
    navigator.getGamepads = () => [window.__dead, window.__pad];
    window.__press = (i, v = 1) => { window.__pad.buttons[i] = { pressed: v > 0.5, value: v }; };
  });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push(String(e)));
  await page.goto(`http://127.0.0.1:${PORT}/`);
  await sleep(1500);

  ok(await page.$eval('#conn', e => e.classList.contains('ok')), 'connected to the server');
  ok((await page.textContent('#modeText')) === 'Кино', 'status arrived (mode = Кино)');

  // Video: the terracotta frame is drawn and frames keep coming (acks work).
  const px = await page.evaluate(() => {
    const c = document.getElementById('view');
    const d = c.getContext('2d').getImageData(c.width / 2, c.height / 2, 1, 1).data;
    return [d[0], d[1], d[2]];
  });
  ok(Math.abs(px[0] - 0xd9) < 12 && Math.abs(px[1] - 0x77) < 12 && Math.abs(px[2] - 0x57) < 12, 'camera frame drawn at the center ' + px);
  await sleep(1200);
  const fps = parseInt(await page.textContent('#fpsText'), 10);
  ok(fps >= 15, 'frames keep coming through the ack loop: ' + fps + ' fps');

  // Button edge -> exactly one command.
  const count = c => (log.match(new RegExp('command: ' + c.replace(/[+]/g, '\\+') + ' ?[-0-9]*\\n', 'g')) || []).length;
  await page.evaluate(() => window.__press(9));
  await sleep(300);
  await page.evaluate(() => window.__press(9, 0));
  await sleep(300);
  ok(count('rec') === 1, 'Menu held for 300 ms sends one "rec"');
  ok(await page.evaluate(() => pad && pad.index === 1), 'listens to the pad that moved, not the first in the list');
  ok(await page.$eval('#rec', e => e.classList.contains('on')), 'REC indicator on');

  // Holding ☰ (Steam's own mouse/gamepad switch in Desktop Mode) must not start a take.
  await page.evaluate(() => window.__press(9)); await sleep(900); await page.evaluate(() => window.__press(9, 0)); await sleep(300);
  ok(count('rec') === 1, 'holding ☰ for ~1 s does not toggle recording');

  // Speed: +1 per press, a quick double press = +10 in total.
  const spd = async () => parseInt(await page.textContent('#spdText'), 10);
  await page.evaluate(() => window.__press(5)); await sleep(80); await page.evaluate(() => window.__press(5, 0)); await sleep(500);
  ok(await spd() === 11, 'RB once -> 11 m/s (' + await spd() + ')');
  await page.evaluate(() => window.__press(5)); await sleep(60); await page.evaluate(() => window.__press(5, 0)); await sleep(60);
  await page.evaluate(() => window.__press(5)); await sleep(60); await page.evaluate(() => window.__press(5, 0)); await sleep(400);
  ok(await spd() === 21, 'RB double -> +10 -> 21 m/s (' + await spd() + ')');
  await page.evaluate(() => window.__press(4)); await sleep(80); await page.evaluate(() => window.__press(4, 0)); await sleep(500);
  ok(await spd() === 20, 'LB once -> 20 m/s (' + await spd() + ')');

  // Sticks, default layout: left = move (forward/sideways), right = turn and up/down.
  const dbg = () => page.evaluate(() => lastStatus.dbg);
  await page.evaluate(() => { window.__pad.axes = [0, -1, 0, 0]; }); await sleep(300);
  let d = await dbg();
  ok(d.pt > 0.9 && Math.abs(d.th) < 0.01, 'left stick up = forward ' + JSON.stringify(d));
  await page.evaluate(() => { window.__pad.axes = [0, 0, 0, -1]; }); await sleep(300);
  d = await dbg();
  ok(d.th > 0.9 && Math.abs(d.pt) < 0.01, 'right stick up = climb ' + JSON.stringify(d));
  await page.evaluate(() => { window.__pad.axes = [0, 0, 1, 0]; }); await sleep(300);
  d = await dbg();
  ok(d.yw > 0.9 && Math.abs(d.rl) < 0.01, 'right stick right = turn ' + JSON.stringify(d));
  // DJI layout from the "?" screen
  await page.evaluate(() => document.querySelector('#sticksSeg [data-layout=dji]').dispatchEvent(new PointerEvent('pointerdown', { bubbles: true })));
  await page.evaluate(() => { window.__pad.axes = [0, -1, 0, 0]; }); await sleep(300);
  d = await dbg();
  ok(d.th > 0.9 && Math.abs(d.pt) < 0.01, 'DJI layout: left stick up = climb ' + JSON.stringify(d));
  await page.evaluate(() => document.querySelector('#sticksSeg [data-layout=game]').dispatchEvent(new PointerEvent('pointerdown', { bubbles: true })));
  await page.evaluate(() => { window.__pad.axes = [0, 0, 0, 0]; }); await sleep(200);

  await page.evaluate(() => window.__press(15)); await sleep(100); await page.evaluate(() => window.__press(15, 0)); await sleep(200);
  ok((await page.textContent('#attText')) === 'Su-27_02', 'D-pad right -> next target');
  await page.evaluate(() => window.__press(0)); await sleep(100); await page.evaluate(() => window.__press(0, 0)); await sleep(300);
  ok((await page.textContent('#attText')) === 'Su-27_02' && await page.$eval('#att', e => e.classList.contains('on')), 'A -> attached, shown');
  ok((await page.textContent('#toast')).includes('Прицепились к: Su-27_02'), 'toast says what it attached to');

  // Held analog inputs stream continuously.
  await page.evaluate(() => { window.__press(12); window.__press(7, 1); });
  await sleep(700);
  await page.evaluate(() => { window.__press(12, 0); window.__press(7, 0); });
  await sleep(300);
  const tilt = parseInt(await page.textContent('#tiltText'), 10);
  const foc = parseInt(await page.textContent('#focText'), 10);
  ok(tilt >= 20, 'D-pad up tilts the camera: ' + tilt + '°');
  ok(foc > 45, 'RT zooms in: ' + foc + ' mm');

  // Gyro: Steam turns Deck rotation into mouse motion; the page forwards it as look deltas.
  // Off by default: a stray mouse must not turn the camera.
  const gpxOff = await page.evaluate(() => lastStatus.gpx);
  for (let i = 1; i <= 5; i++) { await page.mouse.move(100 + i * 30, 100); await sleep(16); }
  await sleep(250);
  ok((await page.evaluate(() => lastStatus.gpx)) === gpxOff && (await page.textContent('#gyroText')) === 'выкл', 'gyro off by default: mouse ignored');
  await page.evaluate(() => document.getElementById('bGyro').dispatchEvent(new PointerEvent('pointerdown', { bubbles: true })));
  await sleep(100);
  await page.evaluate(() => window.__press(1)); await sleep(100); await page.evaluate(() => window.__press(1, 0)); // B: level
  ok(await page.evaluate(() => !!document.pointerLockElement), 'a gamepad press re-captures the pointer for the gyro');
  await sleep(100);
  await page.evaluate(() => document.exitPointerLock()); // headless Chromium sends no movement while locked
  await page.mouse.move(640, 400);
  await sleep(300);
  const tilt0 = parseInt(await page.textContent('#tiltText'), 10);
  for (let i = 1; i <= 10; i++) { await page.mouse.move(640 + i * 20, 400 - i * 20); await sleep(16); }
  await sleep(250);
  const tilt1 = parseInt(await page.textContent('#tiltText'), 10);
  ok(tilt1 - tilt0 >= 9, 'gyro tilt back 200 px -> camera looks up ~10°: ' + tilt0 + '° -> ' + tilt1 + '°');
  await page.evaluate(() => document.getElementById('bGyro').dispatchEvent(new PointerEvent('pointerdown', { bubbles: true })));
  const gpx0 = await page.evaluate(() => lastStatus.gpx);
  for (let i = 1; i <= 10; i++) { await page.mouse.move(840 - i * 20, 200 + i * 20); await sleep(16); }
  await sleep(250);
  ok((await page.evaluate(() => lastStatus.gpx)) === gpx0, '"Гиро" off -> motion not sent');
  ok((await page.textContent('#gyroText')) === 'выкл', 'gyro chip says выкл');
  await page.evaluate(() => document.getElementById('bGyro').dispatchEvent(new PointerEvent('pointerdown', { bubbles: true })));

  // Touch button is on top (not covered).
  const box = await page.$eval('#bRec', e => { const r = e.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 }; });
  ok(await page.evaluate(b => document.elementFromPoint(b.x, b.y).id === 'bRec', box), 'REC touch button receives the tap');
  console.log('     (pointer locked by gyro: ' + await page.evaluate(() => !!document.pointerLockElement) + ')');
  await page.touchscreen.tap(box.x, box.y);   // the Deck screen is touch, not mouse
  await sleep(300);
  ok(count('rec') === 2 && !(await page.$eval('#rec', e => e.classList.contains('on'))), 'tapping REC stops recording');

  // Readability: nothing in the HUD below 12 px, values at least 18 px.
  const sizes = await page.evaluate(() => [...document.querySelectorAll('.chip span, .chip b')].map(e => parseFloat(getComputedStyle(e).fontSize)));
  ok(Math.min(...sizes) >= 18, 'HUD values at least 18 px (min ' + Math.min(...sizes) + ')');

  // Disconnect: page says so, reconnects when the server returns.
  await page.screenshot({ path: path.join(ROOT, 'tests', 'deck-1280x800.png') });
  mock.kill();
  await sleep(1500);
  ok(!(await page.$eval('#conn', e => e.classList.contains('ok'))), 'server gone -> "нет связи"');

  ok(errors.length === 0, 'no page errors ' + errors.join('; '));
  await browser.close();
  console.log(failed ? `\n${failed} FAILED` : '\nall passed');
  process.exit(failed ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
