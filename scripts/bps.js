#!/usr/bin/env node
// Minimal BPS patch creator and applier (the format used by Flips, beat
// and Rom Patcher JS).  No dependencies.
//
//   node scripts/bps.js create <source> <target> <patch.bps>
//   node scripts/bps.js apply  <source> <patch.bps> <output>
//
// Format: "BPS1", varint source size, varint target size, varint metadata
// size (0 here), then actions until the last 12 bytes, which hold the
// CRC-32s of source, target and the patch so far (little endian).  Each
// action is a varint ((length - 1) << 2 | command):
//   0 SourceRead  copy source[out .. out+length) to the same place
//   1 TargetRead  the next `length` patch bytes are literal output
//   2 SourceCopy  signed varint delta to the source cursor, then copy
//   3 TargetCopy  signed varint delta to the target cursor, then copy from
//                 output already written (may overlap, byte by byte)

'use strict';
const fs = require('fs');
const {crc32} = require('zlib');

function writeVarint(out, n) {
  for (;;) {
    const x = n & 0x7f;
    n = Math.floor(n / 128);
    if (n === 0) { out.push(0x80 | x); return; }
    out.push(x);
    n--;
  }
}

function writeSigned(out, delta) {
  writeVarint(out, (Math.abs(delta) * 2) + (delta < 0 ? 1 : 0));
}

function u32(out, v) {
  out.push(v & 0xff, (v >>> 8) & 0xff, (v >>> 16) & 0xff, (v >>> 24) & 0xff);
}

// Greedy encoder.  At each output position, in order of preference:
// unchanged bytes (SourceRead), a run of one repeated byte (TargetCopy
// from the byte before), data found elsewhere in the source (SourceCopy,
// found with an index of 8-byte blocks), else a literal byte.
function create(source, target) {
  const MIN = 8;
  const out = [];
  for (const c of 'BPS1') out.push(c.charCodeAt(0));
  writeVarint(out, source.length);
  writeVarint(out, target.length);
  writeVarint(out, 0);

  const key = (buf, i) => buf.toString('latin1', i, i + MIN);
  const index = new Map();
  for (let i = 0; i + MIN <= source.length; i++) {
    const k = key(source, i);
    if (!index.has(k)) index.set(k, i);
  }

  let literal = [];
  let srcCursor = 0;
  let tgtCursor = 0;
  const flush = () => {
    if (!literal.length) return;
    writeVarint(out, ((literal.length - 1) << 2) | 1);
    for (const b of literal) out.push(b);
    literal = [];
  };

  let i = 0;
  while (i < target.length) {
    // SourceRead: same bytes at the same offset.
    let n = 0;
    while (i + n < target.length && i + n < source.length &&
           source[i + n] === target[i + n]) n++;
    if (n >= 4) {
      flush();
      writeVarint(out, ((n - 1) << 2) | 0);
      i += n;
      continue;
    }
    // TargetCopy: a run repeating the previous output byte.
    if (i > 0) {
      n = 0;
      while (i + n < target.length && target[i + n] === target[i - 1]) n++;
      if (n >= MIN) {
        flush();
        writeVarint(out, ((n - 1) << 2) | 3);
        writeSigned(out, (i - 1) - tgtCursor);
        tgtCursor = i - 1 + n;
        i += n;
        continue;
      }
    }
    // SourceCopy: the next bytes appear somewhere else in the source.
    if (i + MIN <= target.length) {
      const at = index.get(key(target, i));
      if (at !== undefined) {
        n = 0;
        while (i + n < target.length && at + n < source.length &&
               source[at + n] === target[i + n]) n++;
        if (n >= MIN) {
          flush();
          writeVarint(out, ((n - 1) << 2) | 2);
          writeSigned(out, at - srcCursor);
          srcCursor = at + n;
          i += n;
          continue;
        }
      }
    }
    literal.push(target[i++]);
  }
  flush();
  u32(out, crc32(source));
  u32(out, crc32(target));
  u32(out, crc32(Buffer.from(out)));
  return Buffer.from(out);
}

function apply(source, patch) {
  let p = 0;
  const readVarint = () => {
    let data = 0;
    let shift = 1;
    for (;;) {
      const x = patch[p++];
      data += (x & 0x7f) * shift;
      if (x & 0x80) return data;
      shift *= 128;
      data += shift;
    }
  };
  const readSigned = () => {
    const v = readVarint();
    return (v & 1 ? -1 : 1) * Math.floor(v / 2);
  };
  if (patch.toString('latin1', 0, 4) !== 'BPS1') throw new Error('not a BPS patch');
  p = 4;
  const end = patch.length - 12;
  if (crc32(patch.subarray(0, patch.length - 4)) !== patch.readUInt32LE(end + 8)) {
    throw new Error('patch checksum mismatch (corrupt patch)');
  }
  if (crc32(source) !== patch.readUInt32LE(end)) {
    throw new Error('source checksum mismatch: wrong source ROM');
  }
  const srcSize = readVarint();
  const tgtSize = readVarint();
  const metaSize = readVarint();
  p += metaSize;
  if (srcSize !== source.length) throw new Error('source size mismatch');
  const target = Buffer.alloc(tgtSize);
  let o = 0;
  let srcCursor = 0;
  let tgtCursor = 0;
  while (p < end) {
    const v = readVarint();
    const cmd = v & 3;
    const len = Math.floor(v / 4) + 1;
    if (cmd === 0) {
      source.copy(target, o, o, o + len);
      o += len;
    } else if (cmd === 1) {
      patch.copy(target, o, p, p + len);
      p += len;
      o += len;
    } else if (cmd === 2) {
      srcCursor += readSigned();
      source.copy(target, o, srcCursor, srcCursor + len);
      srcCursor += len;
      o += len;
    } else {
      tgtCursor += readSigned();
      for (let k = 0; k < len; k++) target[o++] = target[tgtCursor++];
    }
  }
  if (o !== tgtSize) throw new Error('output size mismatch');
  if (crc32(target) !== patch.readUInt32LE(end + 4)) {
    throw new Error('target checksum mismatch');
  }
  return target;
}

module.exports = {create, apply};

if (require.main === module) {
  const [cmd, a, b, c] = process.argv.slice(2);
  if (cmd === 'create' && c) {
    fs.writeFileSync(c, create(fs.readFileSync(a), fs.readFileSync(b)));
  } else if (cmd === 'apply' && c) {
    fs.writeFileSync(c, apply(fs.readFileSync(a), fs.readFileSync(b)));
  } else {
    console.error('usage: bps.js create <source> <target> <patch.bps>\n' +
                  '       bps.js apply <source> <patch.bps> <output>');
    process.exit(2);
  }
}
