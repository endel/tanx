# Realtime Tanks Demo — Godot

![Screenshot](screenshot.webp)

3D client for [Realtime Tanks Demo](../README.md) built with [Godot 4.3+](https://godotengine.org/) and the [Colyseus Godot SDK](https://docs.colyseus.io/getting-started/godot).

## Setup

1. Download the [Colyseus Godot SDK](https://github.com/colyseus/native-sdk/releases) and extract the `addons/` folder into this directory
2. Open the project in Godot 4.3+
3. Enable the plugin: **Project → Project Settings → Plugins → Colyseus → Enable**
4. Press **F5** to run

Make sure the [game server](../server/) is running on port 2567.

## Controls

- **WASD / Arrow keys** — Move
- **Mouse** — Aim turret
- **Left click** — Shoot

## Web Export

When exporting to web, enable **Extensions Support** in **Project → Export → Web (Runnable)**.
