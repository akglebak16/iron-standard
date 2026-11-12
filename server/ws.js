// Минимальный WebSocket (RFC 6455) без зависимостей: только текстовые кадры.
const crypto = require('crypto');
const GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

class Conn {
  constructor(sock) { this.sock = sock; this.buf = Buffer.alloc(0); this.open = true; this.onmessage = null; this.onclose = null; this.frag = null;
    sock.on('data', d => { this.buf = Buffer.concat([this.buf, d]); try { this.parse(); } catch (e) { this.close(); } });
    sock.on('close', () => this.fin()); sock.on('error', () => this.fin()); sock.setNoDelay(true); }
  fin() { if (!this.open) return; this.open = false; if (this.onclose) this.onclose(); }
  parse() {
    for (;;) {
      const b = this.buf; if (b.length < 2) return;
      const fin = !!(b[0] & 0x80), op = b[0] & 15, masked = !!(b[1] & 0x80); let len = b[1] & 127, off = 2;
      if (len === 126) { if (b.length < 4) return; len = b.readUInt16BE(2); off = 4; }
      else if (len === 127) { if (b.length < 10) return; len = Number(b.readBigUInt64BE(2)); off = 10; }
      if (len > 1 << 20) throw new Error('big');
      const need = off + (masked ? 4 : 0) + len; if (b.length < need) return;
      let payload = b.slice(off + (masked ? 4 : 0), need);
      if (masked) { const m = b.slice(off, off + 4); payload = Buffer.from(payload); for (let i = 0; i < payload.length; i++) payload[i] ^= m[i & 3]; }
      this.buf = b.slice(need);
      if (op === 8) { this.close(); return; }
      if (op === 9) { this.frame(10, payload); continue; }
      if (op === 10) continue;
      if (op === 1 || op === 0) {
        this.frag = op === 1 ? [payload] : (this.frag || []).concat([payload]);
        if (fin) { const s = Buffer.concat(this.frag).toString('utf8'); this.frag = null; if (this.onmessage) this.onmessage(s); }
      }
    }
  }
  frame(op, data) {
    if (!this.open) return; const n = data.length; let h;
    if (n < 126) h = Buffer.from([0x80 | op, n]); else if (n < 65536) { h = Buffer.alloc(4); h[0] = 0x80 | op; h[1] = 126; h.writeUInt16BE(n, 2); } else { h = Buffer.alloc(10); h[0] = 0x80 | op; h[1] = 127; h.writeBigUInt64BE(BigInt(n), 2); }
    try { this.sock.write(Buffer.concat([h, data])); } catch (e) { }
  }
  send(s) { this.frame(1, Buffer.from(s)); }
  ping() { this.frame(9, Buffer.alloc(0)); }
  close() { if (!this.open) return; try { this.frame(8, Buffer.alloc(0)); this.sock.end(); } catch (e) { } this.fin(); }
}

function attach(server, onconn) {
  server.on('upgrade', (req, sock) => {
    const key = req.headers['sec-websocket-key']; if (!key || (req.headers.upgrade || '').toLowerCase() !== 'websocket') { sock.destroy(); return; }
    const acc = crypto.createHash('sha1').update(key + GUID).digest('base64');
    sock.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ' + acc + '\r\n\r\n');
    onconn(new Conn(sock), req);
  });
}
module.exports = { attach, Conn };
