# Tank Battle Multiplayer — Defold

A 2D top-down game client for [Tank Battle Multiplayer](../README.md) built with [Defold](https://defold.com/) and the [Colyseus Defold SDK](https://docs.colyseus.io/getting-started/defold).

## Setup

1. Open the project in the [Defold Editor](https://defold.com/download/)
2. Select **Project > Fetch Libraries** to download the Colyseus SDK and WebSocket extension
3. Build and run (**Project > Build**)

Make sure the [game server](../server/) is running on port 2567.

## Project Structure

```
defold/
├── game.project              # Project config + Colyseus dependency
├── input/game.input_binding  # WASD + mouse input bindings
├── main/
│   ├── main.collection       # Main scene with factories
│   ├── main.script           # Game logic + Colyseus connection
│   ├── tank.go               # Tank prototype (body + turret + ring)
│   ├── bullet.go             # Bullet prototype
│   ├── pickable.go           # Pickable item prototype
│   └── block.go              # Level block prototype
└── gfx/
    ├── white.png             # 1x1 white pixel (tinted at runtime)
    └── game.atlas            # Texture atlas
```

## Controls

- **WASD / Arrow keys** — Move
- **Mouse** — Aim turret
- **Left click** — Shoot

## Notes

- This is a 2D top-down view (no isometric projection)
- All visuals use a single white pixel tinted with team/item colors
- The `main.collection` and `.go` files may need adjustments in the Defold editor to set up factory components properly
