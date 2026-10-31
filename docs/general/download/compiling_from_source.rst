.. _compiling-from-source:

==============================
Running the Godot 4 port
==============================

This fork targets **stock Godot 4.7.2**, using GDScript and the Compatibility
renderer. It does not need the original custom Godot engine or .NET. The port
is based on upstream ``master`` at ``a4fb379b``; it preserves the existing game
rather than adopting the unfinished ``godot4`` scaffold or ``0.2-rewrite``.

The original Godot 3 build instructions remain available in the
`upstream repository <https://github.com/drwhut/tabletop-club/tree/a4fb379b/docs/general/download>`_.

Getting started
---------------

Download the standard editor from the
`Godot 4.7.2 archive <https://godotengine.org/download/archive/4.7.2-stable/>`_.
Clone this fork, then run these commands from its root:

.. code-block:: bash

   python3 tools/setup_webrtc.py
   godot --editor --path game

``setup_webrtc.py`` installs the official ``webrtc-native`` 1.2.2 GDExtension,
with a pinned SHA-256 checksum. It is needed for desktop multiplayer; the
Godot 3 GDNative plugin is incompatible. The downloaded libraries and their
licenses live under ``game/addons/webrtc_native`` and are ignored by Git.
Singleplayer does not require the extension. No export templates are needed
to run the editor or the game from source.

To launch directly:

.. code-block:: bash

   godot --path game -- --base-asset-dir "$PWD"

Use the actual path to your Godot executable if it is not named ``godot``.
Game arguments now follow ``--``. The port uses a separate
``Tabletop Club Godot 4`` user directory so its imported caches and options do
not overwrite the Godot 3 installation. When running with F6/F5 in the editor, the
project's main run arguments point at the bundled ``assets`` directory.

What changed
------------

* Scenes, resources, shaders, fonts, input, physics, dialogs, and scene loading
  use Godot 4 APIs. Piece locking uses ``RigidBody3D.freeze``. Physics behavior
  follows Godot 4's engine, so it will not be identical to the original Bullet
  simulation.
* Runtime imports use public Image, AudioStream, GLTFDocument, and SurfaceTool
  APIs, replacing the custom TabletopImporter engine module. Cached runtime
  resources are stored beside the copied assets with a ``.runtime.res`` suffix.
  OBJ meshes support polygon triangulation, normals, UVs, and basic MTL diffuse
  materials. Collada (``.dae``) needs conversion to glTF; advanced MTL effects
  are not reproduced by this importer.
* Imports and preview construction run on the main thread and yield between
  assets. Network file transfers also yield rather than touching scene nodes
  from background threads. Godot's threaded resource loader handles scene
  transitions.
* WebSocket signaling uses WebSocketPeer and explicit TLSOptions. The upstream
  lobby's bundled self-signed certificate remains trusted. RPC permissions,
  local server calls, transfer modes, and sender IDs use Godot 4 semantics.
  Godot 3 clients cannot join this port's rooms.
* Existing data-only Godot 3 ``.tc`` saves remain readable, including Chess,
  Dominoes, Go, and Poker. New saves use Godot 4 encoding and cannot be opened
  in Godot 3. Saves from a different game version still show the existing
  confirmation dialog. Back up saves before moving between versions.
* The in-game error console uses Godot's public Logger API rather than an
  engine module. SSAO and depth-of-field options require a renderer that
  supports them; depth of field is disabled in Compatibility.

Validation
----------

After installing Godot and WebRTC:

.. code-block:: bash

   python3 tools/test.py --godot /path/to/godot
   # Include real rendering; on Linux without a display, prefix with xvfb-run -a:
   python3 tools/test.py --godot /path/to/godot --render

The runner uses temporary user/cache directories, imports the full bundled
asset pack, compiles all game scripts, and runs local WebRTC lobby/piece RPC
checks. Gameplay checks cover spawning, locking, color, impulses, drawing from
stacks, the four bundled Godot 3 saves, a Godot 4 save round trip, and the object
browser. Script errors, engine errors, missing completion markers, and timeouts
fail the run. Logs and a rendered screenshot are saved to ``.artifacts/tests``.
A second integration test runs two actual game processes through a temporary
copy of the upstream signaling server (pinned commit, verified checksum). It
uses a locally generated TLS certificate and transfers a host-only asset to
check download, runtime import, table synchronization, and gameplay. It requires
Node, npm, OpenSSL, and a display:

.. code-block:: bash

   xvfb-run -a python3 tools/test_session.py --godot /path/to/godot

The ``Godot 4.7.2 integration`` GitHub Actions job runs both rendered suites.

Scope
-----

This is the desktop engine migration. Web export, browser storage, Matrix widget
messaging, and Vommet integration are subsequent work. The Compatibility
renderer and stock engine remove two obstacles to that work, but this branch
does not claim a working WebAssembly export. Automated local WebRTC tests do not
establish connectivity across arbitrary NATs or validate a deployed public lobby.
