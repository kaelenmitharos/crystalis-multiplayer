// Same-PC netplay check (RetroArch, two instances on 127.0.0.1).
//  1. Port mapping: the host's pad moves player 1, the client's pad joins
//     and moves player 2 (seen the same on both instances).
//  2. Soak: both pads play for MINUTES (walking, swinging, wild warps).
//     Desync detector: both instances' zero page ($0000-$00ff: every
//     object's position, the game mode, the RNG) is sampled every frame;
//     a client sample counts as matched if the host had the same bytes at
//     some point.  In sync, a good share of samples match every minute; a
//     desync drops it to 0 (RetroArch's own CRC resync is turned off with
//     netplay_check_frames = 0, so a desync would stay).
//  3. Control: write player 1's X on the client only and check the
//     detector sees the desync.
const {StreamPad, Cmd, sleep, boot} = require('./ra.js');
const MINUTES = Number(process.argv[2] || 15);

(async () => {
  const hc = new Cmd(55355), cc = new Cmd(55356);
  const hp = new StreamPad(55400), cp = new StreamPad(55500);
  const t0 = Date.now();
  const log = (s) => console.log(`[${((Date.now() - t0) / 1000).toFixed(0).padStart(4)}s] ${s}`);
  const both = async (a, n) => [await hc.read(a, n), await cc.read(a, n)];
  let fails = 0;
  const check = (ok, msg) => { log((ok ? 'ok   ' : 'FAIL ') + msg); if (!ok) fails++; };

  log('booting with the host pad');
  check(await boot(hc, hp), 'host pad boots the game');
  await sleep(4000);  // opening scene
  const warp = async () => {
    hp.set({a: true, b: true}); await sleep(400);
    hp.set({a: true, b: true, start: true}); await sleep(50);
    hp.set({a: true, b: true}); await sleep(150); hp.set({}); await sleep(2500);
  };
  await warp();
  log(`wild warp: loc ${(await both(0x6c, 1)).join(' / ')}`);

  // Port 1 = host pad.
  const [x0] = await both(0x70, 1);
  hp.set({right: true}); await sleep(600); hp.set({left: true}); await sleep(300); hp.set({}); await sleep(500);
  const [x1h, x1c] = await both(0x70, 1);
  const [y0] = await both(0xb0, 1);
  hp.set({down: true}); await sleep(500); hp.set({}); await sleep(500);
  const [y1h, y1c] = await both(0xb0, 1);
  check((x1h[0] !== x0[0] || y1h[0] !== y0[0]) && x1h[0] === x1c[0] && y1h[0] === y1c[0],
        `host pad moves player 1: x ${x0}->${x1h}, y ${y0}->${y1h} (client sees ${x1c}, ${y1c})`);

  // Port 2 = client pad: Start joins player 2.
  // (The game ignores Start during screen changes, so try a few times.)
  const [a0h, a0c] = await both(0x6280, 1);
  let a1h, a1c, tries = 0;
  do {
    tries++;
    cp.set({start: true}); await sleep(50); cp.set({}); await sleep(1500);
    [a1h, a1c] = await both(0x6280, 1);
  } while (a1h[0] !== 1 && tries < 5);
  check(a0h[0] === 0 && a1h[0] === 1 && a1c[0] === 1,
        `client Start joins player 2: P2Active ${a0h}/${a0c} -> ${a1h}/${a1c} (${tries} press${tries > 1 ? 'es' : ''})`);
  const [p1a] = await both(0x70, 1);
  const [g0] = await both(0x6294, 4);
  cp.set({left: true}); await sleep(700); cp.set({up: true}); await sleep(700); cp.set({}); await sleep(600);
  const [g1h, g1c] = await both(0x6294, 4);
  const [p1b] = await both(0x70, 1);
  check(g0.join() !== g1h.join() && g1h.join() === g1c.join(), `client pad moves player 2: ground ${g0} -> ${g1h} (client sees ${g1c})`);
  check(p1a[0] === p1b[0], `client pad leaves player 1 alone: x ${p1a} -> ${p1b}`);
  // Player 2's sword: B on the client pad.
  cp.set({b: true}); await sleep(80); cp.set({}); await sleep(400);
  check((await both(0x6280, 1))[0][0] === 1, 'client B swings without leaving');

  // Desync detector.
  const hostSeen = new Map();   // zero page -> last time seen on the host
  const clientSamples = [];     // [time, zero page]
  let sampling = true;
  const hostLoop = (async () => { while (sampling) { const r = await hc.read(0, 256); if (r) hostSeen.set(r.join(), Date.now()); } })();
  const clientLoop = (async () => { while (sampling) { const r = await cc.read(0, 256); if (r) clientSamples.push([Date.now(), r.join()]); } })();
  // Fraction of client samples taken in [from, to) that the host also had.
  const matchRate = (from, to) => {
    let n = 0, m = 0;
    for (const [t, z] of clientSamples) if (t >= from && t < to) { n++; if (hostSeen.has(z)) m++; }
    return [m, n];
  };

  const DIRS = ['left', 'down', 'right', 'up'];
  const soakStart = Date.now();
  let step = 0, minute = 0, zeroMinutes = 0, warps = 0;
  const locs = new Set();
  while (minute < MINUTES) {
    step++;
    const a = DIRS[Math.floor(step / 9) % 4], b = DIRS[Math.floor(step / 7) % 4];
    hp.set({[a]: true, b: step % 5 === 0});
    cp.set({[b]: true, b: step % 4 === 0});
    await sleep(150);
    if (step % 250 === 0) { await warp(); warps++; }
    if (step % 100 === 0) {
      const [act] = await both(0x6280, 1);
      if (act && act[0] === 0) { cp.set({}); await sleep(100); cp.set({start: true}); await sleep(50); cp.set({}); log('player 2 was not joined: rejoined'); }
    }
    const now = Date.now();
    if (now - soakStart >= (minute + 1) * 60000 + 5000) {
      // Score minute `minute` (allow 5 s for the host to catch up).
      const [m, n] = matchRate(soakStart + minute * 60000, soakStart + (minute + 1) * 60000);
      const [l] = await both(0x6c, 1); locs.add(l[0]);
      const [hph, hpc] = await both(0x6281, 1);
      log(`minute ${minute + 1}: ${m}/${n} client samples match the host (${(100 * m / Math.max(n, 1)).toFixed(0)}%)` +
          ` | loc ${l} P2HP ${hph}/${hpc} warps ${warps}`);
      if (m === 0) zeroMinutes++;
      minute++;
    }
  }
  hp.set({}); cp.set({});
  check(zeroMinutes === 0, `soak: ${minute} minutes scored, ${zeroMinutes} with no matching samples; ${locs.size} locations visited`);

  // Control: desync the client on purpose.
  await sleep(2000);
  const [cx] = [await cc.read(0x70, 1)];
  await cc.ask(`WRITE_CORE_MEMORY 70 ${((cx[0] + 40) & 0xff).toString(16)}`, 300);
  const tw = Date.now();
  for (let i = 0; i < 40; i++) {
    hp.set({[DIRS[i % 4]]: true}); cp.set({[DIRS[(i + 1) % 4]]: true}); await sleep(250);
  }
  hp.set({}); cp.set({});
  await sleep(5000);
  const [m, n] = matchRate(tw + 1000, tw + 10000);
  check(m === 0 && n > 0, `control: after a client-only RAM write, ${m}/${n} client samples match (desync detected)`);
  sampling = false;
  await Promise.all([hostLoop, clientLoop]);
  log(`done: ${fails} failures`);
  for (const x of [hc, cc, hp, cp]) x.close();
  process.exit(fails ? 1 : 0);
})();
