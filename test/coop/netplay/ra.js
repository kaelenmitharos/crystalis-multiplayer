// Drive RetroArch instances over UDP: the network gamepad (button state per
// user, network_remote_*) and the command port (network_cmd_*, used for
// READ_CORE_MEMORY / WRITE_CORE_MEMORY / GET_STATUS).
const dgram = require('dgram');

const BTN = {b: 0, y: 1, select: 2, start: 3, up: 4, down: 5, left: 6, right: 7, a: 8, x: 9};

class Cmd {
  constructor(port) {
    this.port = port;
    this.sock = dgram.createSocket('udp4');
    this.waiting = [];
    this.sock.on('message', (m) => { const w = this.waiting.shift(); if (w) w(m.toString()); });
    this.sock.bind();
  }
  send(text) { this.sock.send(Buffer.from(text + '\n'), this.port, '127.0.0.1'); }
  ask(text, ms = 1000) {
    return new Promise((res) => {
      const t = setTimeout(() => { const i = this.waiting.indexOf(f); if (i >= 0) this.waiting.splice(i, 1); res(null); }, ms);
      const f = (m) => { clearTimeout(t); res(m); };
      this.waiting.push(f);
      this.send(text);
    });
  }
  async read(addr, n) {
    const r = await this.ask(`READ_CORE_MEMORY ${addr.toString(16)} ${n}`);
    if (!r) return null;
    const parts = r.trim().split(/\s+/).slice(2);
    if (parts[0] === '-1') return null;
    return parts.map((h) => parseInt(h, 16));
  }
  close() { this.sock.close(); }
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
module.exports = {Cmd, sleep, BTN};

// Boot to normal play with pad p: pulse Start only on the title screens
// (MainLoopMode != 1 or GameMode $13), then wait until GameMode 8 holds.
module.exports.boot = async function boot(cmd, pad, log = () => {}) {
  let stable = 0;
  for (let i = 0; i < 400 && stable < 6; i++) {
    const m = await cmd.read(0x40, 2);
    if (!m) { await sleep(300); continue; }
    if (m[0] !== 1 || m[1] === 0x13) { stable = 0; pad.set({start: true}); await sleep(80); pad.set({}); await sleep(300); }
    else { stable = m[1] === 8 ? stable + 1 : 0; await sleep(300); }
    if (i % 10 === 0) log(`boot ${i}: ${m}`);
  }
  return stable >= 6;
};

// RetroArch (Windows) clears a network pad's buttons on every frame that
// has no packet waiting, and reads at most one packet per frame.  So keep
// a steady stream just under the frame rate, each packet re-asserting one
// held button (or releasing one), cycling.
class StreamPad {
  constructor(port, user = 0, hz = 58) {
    this.port = port; this.user = user; this.sock = dgram.createSocket('udp4');
    this.held = []; this.i = 0; this.period = 1000 / hz; this.running = true;
    this.next = performance.now();
    const tick = () => {
      if (!this.running) return;
      const now = performance.now();
      if (now >= this.next) {
        this.next += this.period;
        if (now - this.next > 100) this.next = now + this.period;
        let id, on;
        if (this.held.length) { id = this.held[this.i++ % this.held.length]; on = 1; }
        else { id = BTN.start; on = 0; }
        const b = Buffer.alloc(20);
        b.writeInt32LE(this.user, 0); b.writeInt32LE(1, 4); b.writeInt32LE(0, 8);
        b.writeInt32LE(id, 12); b.writeUInt16LE(on, 16);
        this.sock.send(b, this.port, '127.0.0.1');
      }
      setTimeout(tick, 1);
    };
    tick();
  }
  set(buttons) {
    const ids = Object.entries(BTN).filter(([n]) => buttons[n]).map(([, id]) => id);
    // A released button must be cleared explicitly: send releases first.
    for (const id of this.held) if (!ids.includes(id)) {
      const b = Buffer.alloc(20);
      b.writeInt32LE(this.user, 0); b.writeInt32LE(1, 4); b.writeInt32LE(0, 8);
      b.writeInt32LE(id, 12); b.writeUInt16LE(0, 16);
      this.sock.send(b, this.port, '127.0.0.1');
    }
    this.held = ids; this.i = 0;
  }
  close() { this.running = false; this.sock.close(); }
}
module.exports.StreamPad = StreamPad;
