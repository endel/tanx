# Realtime Tanks Demo — Haxe + Heaps

![Screenshot](screenshot.webp)

3D client for [Realtime Tanks Demo](../README.md) built with [Haxe](https://haxe.org/), [Colyseus Haxe SDK](https://docs.colyseus.io/getting-started/haxe) and the [Heaps](https://heaps.io/) game engine. Targets both Web (JS/WebGL) and Native (HashLink/C with SDL).

## Setup

```bash
haxelib install heaps
haxelib install colyseus
```

### Web (JS)

```bash
haxe build.js.hxml
npx serve .
# Open http://localhost:3000/index.html
```

### Native (HashLink/C)

```bash
haxelib install hlsdl
haxelib install hashlink
./build-native.sh
DYLD_LIBRARY_PATH=/opt/homebrew/Cellar/hashlink/*/lib ./game_native
```

Make sure the [game server](../server/) is running on port 2567.

## Controls

- **WASD / Arrow keys** — Move
- **Mouse** — Aim turret
- **Left click** — Shoot
