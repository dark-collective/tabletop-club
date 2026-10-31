import test from "node:test";
import assert from "node:assert/strict";
import {MatrixLobby, SIGNAL_EVENT} from "../src/signaling.js";

function room() {
  const messages = [], endpoints = [], output = [];
  const roomId = "!room:test";
  function endpoint(user, widgetId = "table-1") {
    const received = [];
    const broker = new MatrixLobby({widgetId, roomId, deliver: e => received.push(e),
      send: async (type, content) => {messages.push({type, content, sender: user, room_id: roomId});},
    });
    endpoints.push(broker);
    output.push(received);
    return broker;
  }
  async function drain() {
    while (messages.length) {
      const event = messages.shift();
      for (const target of endpoints) await target.receive(event);
    }
  }
  return {endpoint, drain, output, messages, roomId};
}

test("host/client signaling keeps WebRTC peer IDs and authenticates event senders", async () => {
  const r = room(), host = r.endpoint("@host:test"), client = r.endpoint("@client:test");
  await host.connect();
  await client.connect(host.code);
  await r.drain();
  assert.equal(client.session, host.session);
  assert.ok(client.peer > 1);
  assert.ok(r.output[0].some(e => e.kind === "peer_connected" && e.peer === client.peer));
  await host.signal("O", client.peer, "offer");
  await r.drain();
  assert.ok(r.output[1].some(e => e.kind === "O" && e.peer === 1 && e.data === "offer"));
  const before = r.output[1].length;
  const forged = {type: SIGNAL_EVENT, room_id: r.roomId, sender: "@attacker:test", content: {
    v: 1, widget: "table-1", kind: "signal", session: host.session, token: host.nonce,
    from: 1, to: client.peer, packet: {kind: "O", data: "forged"},
  }};
  await client.receive(forged);
  await client.receive({...forged, sender: "@host:test", room_id: "!other:test"});
  await client.receive({...forged, sender: "@host:test", content: {...forged.content, widget: "other-widget"}});
  assert.equal(r.output[1].length, before);
  await client.disconnect();
  await r.drain();
  assert.equal(host.peers.size, 0);
  await host.disconnect();
});

test("a second client joins through the host, and stale sessions cannot inject signals", async () => {
  const r = room(), host = r.endpoint("@host:test"), one = r.endpoint("@one:test"), two = r.endpoint("@two:test");
  await host.connect();
  for (const client of [one, two]) {await client.connect(host.code); await r.drain();}
  assert.notEqual(one.peer, two.peer);
  assert.equal(host.peers.size, 2);
  assert.deepEqual(r.output[2].filter(e => e.kind === "peer_connected").map(e => e.peer), [1]);
  const oldSession = host.session, oldToken = host.nonce;
  await host.disconnect(); await r.drain();
  await host.connect();
  const before = r.output[0].length;
  await host.receive({type: SIGNAL_EVENT, room_id: r.roomId, sender: "@one:test", content: {
    v: 1, widget: "table-1", session: oldSession, token: oldToken, from: one.peer,
    to: 1, kind: "signal", packet: {kind: "C", data: "stale"},
  }});
  assert.equal(r.output[0].length, before);
  await Promise.all([host.disconnect(), one.disconnect(), two.disconnect()]);
});

test("sealed tables reject new clients", async () => {
  const r = room(), host = r.endpoint("@host:test"), client = r.endpoint("@client:test");
  await host.connect(); await host.seal();
  await client.connect(host.code); await r.drain();
  assert.equal(host.peers.size, 0);
  assert.equal(client.session, null);
  await Promise.all([host.disconnect(), client.disconnect()]);
});
