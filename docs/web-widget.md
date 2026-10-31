# Tabletop Club in Vommet

The browser edition uses Godot 4.7.2's single-threaded WASM export. It runs in an ordinary cross-origin Matrix widget iframe, without SharedArrayBuffer, cross-origin isolation headers, a native extension, or a separate lobby server.

## Add the widget

Use this URL when adding a custom widget to a room in Vommet:

```
https://dark-collective.github.io/tabletop-club/?roomId=$matrix_room_id&userId=$matrix_user_id&displayName=$matrix_display_name
```

Vommet appends `widgetId` and `parentUrl` and substitutes the Matrix variables. Everyone must open the **same room widget**; independently added widgets have separate signaling namespaces. Allow its requested room signaling permissions. One person clicks **Host table** and shares the four-letter code with the room; others enter the code and click **Join**. The host must keep their widget open.

The toolbar reports the connected player count. **Solo** also works when the URL is opened directly, or when room permissions are denied. **Download save** exports a `.tc` file; the host can use **Import save** to restore it. Browser settings and cached bundled assets live in origin-local IndexedDB. Browser storage is not a backup: download saves before clearing site data or switching browsers.

On first load, the game downloads its WASM program and asset pack and unpacks the bundled assets. Subsequent loads reuse the extracted cache. Browser textures are limited to 1024 pixels on their longest edge; source assets remain available to the existing asset system. Desktop imports retain their original texture resolution.

## Permissions and networking

The widget requests only these Matrix capabilities:

- `org.matrix.msc2762.send.event:im.tabletopclub.signal.v1`
- `org.matrix.msc2762.receive.event:im.tabletopclub.signal.v1`
- `town.robin.msc3846.turn_servers`

Room events carry join/leave notices and WebRTC SDP/ICE signaling. Game state and asset transfers use Godot's existing WebRTC data channels. The widget never asks for an access token or connects directly to the homeserver. Room events pass through the Matrix client's normal encryption and permissions handling. Sender identity comes from the parent client's event envelope; session tokens and room/widget IDs prevent accidental cross-session routing.

Vommet's TURN credentials are passed to the browser WebRTC API when available. Without TURN, STUN is used, and restrictive networks may prevent peers from connecting. WebRTC exposes network information to participants according to browser policy. The desktop game's certificate-pinned public lobby cannot be used from a browser; the web edition uses Matrix signaling instead. Standalone web multiplayer is therefore disabled.

The widget supports the Matrix widget API implemented by Vommet, including capability approval, room events, and TURN updates. Automated tests use a cross-origin parent fixture matching those messages and actual browser WebRTC peers; testing the installed Vommet application remains a separate manual check.

## Build and run locally

Install Node 22+, Python 3, Godot **4.7.2**, and its matching standard export templates. No .NET tools are needed.

```sh
npm ci
python3 tools/build_web.py --godot /path/to/Godot_v4.7.2-stable_linux.x86_64
python3 tools/serve_web.py
```

If templates are not installed in Godot's normal location, pass `--template /path/to/web_nothreads_release.zip`. The build imports assets in an isolated temporary user directory, prebuilds collision shapes and compressed resource caches, and exports to `.artifacts/web`. It restores the tracked export preset after using a custom template.

Open `http://127.0.0.1:8176`. For an HTTPS-hosted Vommet client, use an HTTPS deployment rather than an HTTP iframe. A temporary HTTPS tunnel can be useful for local integration testing.

```sh
npm run test:widget
npx playwright install --with-deps chromium
npm run test:web
```

The browser tests exercise the actual exported game, without isolation headers, plus two cross-origin widgets negotiating capabilities and exchanging game traffic over WebRTC. The parent fixture is served only by the local preview server and is excluded from the deployed build.

## Deployment

Serve every file in `.artifacts/web` over HTTPS. Serve `.wasm` as `application/wasm`. Allow Vommet to frame the page: do not set `X-Frame-Options: DENY`/`SAMEORIGIN` or a restrictive `frame-ancestors` policy. No COOP/COEP headers are required. The export intentionally does not install a service worker.

`.github/workflows/web.yml` builds and tests the export and publishes the `web/matrix-widget` branch of `dark-collective/tabletop-club` to GitHub Pages after the web checks pass. Other repositories receive a downloadable Pages artifact and can configure their own deployment job. Update the widget URL above when hosting elsewhere.
