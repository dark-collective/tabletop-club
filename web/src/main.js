import {WidgetApi} from "matrix-widget-api";
import {MatrixLobby, SIGNAL_CAPABILITIES, TURN_CAPABILITY} from "./signaling.js";

const params = new URLSearchParams(location.search);
const status = document.querySelector("#status");
const progress = document.querySelector("#progress");
const errorBox = document.querySelector("#error");
const controls = document.querySelector("#controls");
let gameCallback, broker, api;
let scene = "";
const queued = [];
const isWidget = Boolean(params.get("widgetId") && params.get("parentUrl"));
const roomId = params.get("roomId") || params.get("room_id") || "";
const widgetId = params.get("widgetId");
const showError = error => {
  const message = error instanceof Error ? error.message : String(error);
  errorBox.textContent = message;
  errorBox.hidden = false;
};
function deliver(data) {
  const payload = JSON.stringify(data);
  if (gameCallback) gameCallback(payload); else queued.push(payload);
}
function updateControls() {
  controls.hidden = false;
  for (const button of controls.querySelectorAll("#solo,#host,#join")) button.disabled = scene !== "MainMenu" || (!bridge.multiplayerReady && button.id !== "solo");
  document.querySelector("#save").disabled = scene !== "Game";
  document.querySelector("#load").disabled = scene !== "Game" || (broker?.active && !broker.host);
}
const bridge = window.tabletopWidget = {
  isWidget,
  multiplayerReady: false,
  displayName: (params.get("displayName") || params.get("userId") || "Player").slice(0, 100),
  iceServersJSON: JSON.stringify([{urls: ["stun:stun.l.google.com:19302"]}]),
  registerGame(callback) {
    gameCallback = callback;
    for (const data of queued.splice(0)) callback(data);
  },
  fromGame(raw) {
    const data = JSON.parse(raw);
    if (data.action === "scene") {
      scene = data.name;
      document.body.dataset.scene = scene;
      if (scene === "MainMenu" || scene === "Game") document.querySelector("#loading").hidden = true;
      updateControls();
    } else if (data.action === "participants") {
      document.querySelector("#players").textContent = `${data.count} player${data.count === 1 ? "" : "s"}`;
    } else if (data.action === "loading") {
      status.textContent = data.message;
      progress.value = data.progress;
    } else if (data.action === "connect") {
      if (!bridge.multiplayerReady) deliver({action: "lobby", kind: "error", message: "Allow the widget's room signaling permissions to host or join a table."});
      else broker.connect(data.code).catch(error => {broker.fail(String(error)); showError(error);});
    } else if (data.action === "disconnect") broker?.disconnect();
    else if (data.action === "seal") broker?.seal().catch(showError);
    else if (data.action === "signal") broker?.signal(data.kind, data.peer, data.data).catch(showError);
  },
};
document.querySelector("#solo").onclick = () => deliver({action: "start_singleplayer"});
document.querySelector("#host").onclick = () => deliver({action: "host"});
document.querySelector("#join").onclick = () => {
  const code = document.querySelector("#room-code").value.trim().toUpperCase();
  if (/^[A-Z]{4}$/.test(code)) deliver({action: "join", code});
  else showError("Enter the four-letter room code from your host.");
};
document.querySelector("#save").onclick = () => deliver({action: "export_save"});
document.querySelector("#load").onclick = () => document.querySelector("#save-file").click();
document.querySelector("#save-file").onchange = async event => {
  const file = event.target.files[0];
  if (!file) return;
  if (file.size > 16 * 1024 * 1024) return showError("Choose a save smaller than 16 MiB.");
  const reader = new FileReader();
  reader.onload = () => deliver({action: "import_save", data: reader.result.split(",")[1]});
  reader.readAsDataURL(file);
  event.target.value = "";
};
document.querySelector("#dismiss").onclick = () => { errorBox.hidden = true; };

if (isWidget) {
  try {
    // Vommet's native runners use an opaque/custom parent origin. SDK defaults
    // to '*' for those; inbound replies still validate source and widget ID.
    const parent = new URL(params.get("parentUrl"));
    const origin = ["http:", "https:"].includes(parent.protocol) ? parent.origin : "*";
    // Reject forged API traffic before the SDK's message listener runs.
    window.addEventListener("message", event => {
      if (["toWidget", "fromWidget"].includes(event.data?.api) &&
          (event.source !== window.parent || (origin !== "*" && event.origin !== origin))) {
        event.stopImmediatePropagation();
      }
    }, {capture: true});
    api = new WidgetApi(widgetId, origin);
    api.requestCapabilities([...SIGNAL_CAPABILITIES, TURN_CAPABILITY]);
    broker = new MatrixLobby({widgetId, roomId,
      send: (type, content) => api.sendRoomEvent(type, content),
      deliver: data => {
        if (data.kind === "room_joined") document.querySelector("#session").textContent = `Room ${data.code}`;
        deliver({action: "lobby", ...data});
        updateControls();
      },
    });
    api.on("action:send_event", event => {
      event.preventDefault();
      api.transport.reply(event.detail, {});
      broker.receive(event.detail.data).catch(showError);
    });
    api.on("action:update_turn_servers", event => {
      event.preventDefault();
      api.transport.reply(event.detail, {});
      const {uris, username, password} = event.detail.data;
      if (Array.isArray(uris) && uris.every(uri => typeof uri === "string" && /^(stun|turn|turns):/.test(uri))) {
        bridge.iceServersJSON = JSON.stringify([{urls: uris, username, credential: password}]);
      }
    });
    api.on("ready", () => {
      bridge.multiplayerReady = Boolean(roomId.startsWith("!") && SIGNAL_CAPABILITIES.every(c => api.hasCapability(c)));
      document.querySelector("#connection").textContent = bridge.multiplayerReady ? "Matrix room connected" : "Solo mode · room permissions unavailable";
      if (api.hasCapability(TURN_CAPABILITY)) api.transport.send("watch_turn_servers", {}).catch(() => {});
      updateControls();
    });
    api.start();
    api.sendContentLoaded().catch(() => {});
  } catch (error) { showError(error); }
} else document.querySelector("#connection").textContent = "Solo mode · add this page as a Matrix widget for room multiplayer";

const config = window.GODOT_CONFIG;
const engine = new Engine(config);
const missing = Engine.getMissingFeatures({threads: false});
if (missing.length) showError(`This browser needs ${missing.join(", ")} to run Tabletop Club.`);
else engine.startGame({
  canvas: document.querySelector("#canvas"),
  canvasResizePolicy: 2,
  focusCanvas: false,
  onProgress(current, total) {
    status.textContent = "Loading Tabletop Club…";
    if (total) progress.value = current / total;
  },
  onPrint: line => console.info(line),
  onPrintError: line => console.error(line),
  onExit(code) { showError(code ? `The game stopped (code ${code}). Reload to try again.` : "The game has closed. Reload to play again."); },
}).catch(showError);
