// Matrix is a signaling transport, never a transport for game state or files.
export const SIGNAL_EVENT = "im.tabletopclub.signal.v1";
export const SIGNAL_CAPABILITIES = [
  `org.matrix.msc2762.send.event:${SIGNAL_EVENT}`,
  `org.matrix.msc2762.receive.event:${SIGNAL_EVENT}`,
];
export const TURN_CAPABILITY = "town.robin.msc3846.turn_servers";

export class MatrixLobby {
  constructor({widgetId, roomId, send, deliver, randomUUID = () => [...crypto.getRandomValues(new Uint8Array(24))].map(n => n.toString(16).padStart(2, "0")).join(""), randomId = () => 2 + crypto.getRandomValues(new Uint32Array(1))[0] % 2147483645}) {
    Object.assign(this, {widgetId, roomId, send, deliver, randomUUID, randomId});
    this.reset();
  }
  reset() {
    clearTimeout(this.timeout);
    this.active = false;
    this.host = false;
    this.sealed = false;
    this.peers = new Map();
    this.pending = [];
    this.session = null;
    this.hostUser = null;
    this.peer = 0;
  }
  async publish(content) {
    return this.send(SIGNAL_EVENT, {v: 1, widget: this.widgetId, ...content});
  }
  async connect(code = "") {
    await this.disconnect();
    this.active = true;
    this.nonce = this.randomUUID();
    this.host = !code;
    this.code = code.toUpperCase();
    if (this.host) {
      this.session = this.randomUUID();
      this.code = Array.from(crypto.getRandomValues(new Uint8Array(4)), n => String.fromCharCode(65 + n % 26)).join("");
      this.peer = 1;
      this.deliver({kind: "connected", peer: 1});
      this.deliver({kind: "room_joined", code: this.code});
    } else {
      this.timeout = setTimeout(() => {
        if (this.active && !this.session) this.fail("No host answered that room code. Ask the host to keep their table open.");
      }, 30000);
      await this.publish({kind: "join", code: this.code, nonce: this.nonce});
    }
  }
  fail(message) {
    this.reset();
    this.deliver({kind: "error", message});
  }
  async disconnect() {
    if (this.active && this.session) {
      // A crashed/closed tab is also detected by WebRTC; unload delivery is not required.
      this.publish({kind: "leave", session: this.session, from: this.peer, token: this.nonce}).catch(() => {});
    }
    this.reset();
  }
  async seal() {
    if (!this.host || !this.active) return;
    this.sealed = true;
    await this.publish({kind: "sealed", session: this.session, from: 1, token: this.nonce});
  }
  async signal(kind, peer, data) {
    if (!this.active || !this.session || !["O", "A", "C"].includes(kind) || typeof data !== "string" || data.length > 32000) return;
    if (this.host ? !this.peers.has(peer) : peer !== 1) return;
    await this.publish({kind: "signal", session: this.session, from: this.peer, to: peer, token: this.nonce, packet: {kind, data}});
  }
  async receive(event) {
    if (!this.active || event.type !== SIGNAL_EVENT || event.room_id !== this.roomId || typeof event.sender !== "string") return;
    const c = event.content;
    if (!c || c.v !== 1 || c.widget !== this.widgetId) return;
    if (this.host && !this.sealed && c.kind === "join" && c.code === this.code && typeof c.nonce === "string" && c.nonce.length <= 100) {
      let peer = [...this.peers].find(([, p]) => p.user === event.sender && p.token === c.nonce)?.[0];
      const fresh = !peer;
      if (fresh) {
        if (this.peers.size >= 32) return;
        do { peer = this.randomId(); } while (this.peers.has(peer));
        this.peers.set(peer, {user: event.sender, token: c.nonce});
      }
      await this.publish({kind: "welcome", code: this.code, session: this.session, to: c.nonce, peer, host_token: this.nonce});
      if (fresh && this.active) this.deliver({kind: "peer_connected", peer});
      return;
    }
    if (!this.host && !this.session && c.kind === "welcome" && c.to === this.nonce && c.code === this.code &&
        typeof c.session === "string" && typeof c.host_token === "string" && Number.isInteger(c.peer) && c.peer >= 2 && c.peer <= 2147483647) {
      this.session = c.session;
      this.hostUser = event.sender;
      this.hostToken = c.host_token;
      this.peer = c.peer;
      clearTimeout(this.timeout);
      this.deliver({kind: "connected", peer: this.peer});
      this.deliver({kind: "room_joined", code: this.code});
      this.deliver({kind: "peer_connected", peer: 1});
      for (const pending of this.pending.splice(0)) await this.receive(pending);
      return;
    }
    // Parent clients can deliver signaling immediately after the welcome event.
    if (!this.host && !this.session && c.kind === "signal" && this.pending.length < 32) {
      this.pending.push(event);
      return;
    }
    if (c.session !== this.session) return;
    const origin = this.host ? this.peers.get(c.from) : {user: this.hostUser, token: this.hostToken};
    if (!origin || origin.user !== event.sender || origin.token !== c.token || (!this.host && c.from !== 1)) return;
    if (c.kind === "signal" && c.to === this.peer && c.packet && ["O", "A", "C"].includes(c.packet.kind) &&
        typeof c.packet.data === "string" && c.packet.data.length <= 32000) {
      this.deliver({kind: c.packet.kind, peer: c.from, data: c.packet.data});
    } else if (c.kind === "leave") {
      if (this.host) {
        this.peers.delete(c.from);
        this.deliver({kind: "peer_disconnected", peer: c.from});
      } else this.deliver({kind: "error", message: "The host closed the table."});
    } else if (c.kind === "sealed" && !this.host) this.deliver({kind: "sealed"});
  }
}
