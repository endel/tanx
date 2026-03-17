# Realtime Tanks Demo — Unity

![Screenshot](screenshot.webp)

3D isometric client for [Realtime Tanks Demo](../README.md) built with [Unity](https://unity.com/) and the [Colyseus Unity SDK](https://docs.colyseus.io/getting-started/unity).

## Setup

1. Create a new Unity project (3D) via Unity Hub
2. Install the Colyseus SDK: **Window → Package Manager → + → Add package from git URL**:
   ```
   https://github.com/colyseus/colyseus-unity-sdk.git#upm
   ```
3. Copy the `Assets/Scripts/` folder into your project
4. Create an empty scene with a `GameManager` object and attach the `GameManager.cs` script
5. Press **Play**

Make sure the [game server](../server/) is running on port 2567.

## Generating Schema Files

The C# schema classes in `Assets/Scripts/Schema/` are generated from the server's TypeScript definitions. To regenerate after server schema changes:

```bash
cd server
npx schema-codegen src/schema/BattleState.ts --csharp --output ../unity/Assets/Scripts/Schema/
```

## Controls

- **WASD / Arrow keys** — Move
- **Mouse** — Aim turret
- **Left click** — Shoot
