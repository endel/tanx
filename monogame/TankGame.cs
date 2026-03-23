using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;
using Microsoft.Xna.Framework.Input;
using System.Linq.Expressions;
using Colyseus;
using Colyseus.Schema;

namespace TankDemo;

public class TankGame : Game
{
    // ── Colors ──────────────────────────────────────────────────────────────
    static readonly Color BgColor = new(13, 27, 42);
    static readonly Color GroundColor = new(18, 36, 56);
    static readonly Color BlockColor = new(34, 102, 170, 217);
    static readonly Color BlockOutline = new(102, 187, 255, 128);
    static readonly Color WallColor = new(26, 68, 136, 204);
    static readonly Color GridColor = new(68, 136, 204, 25);

    static readonly Color[] TeamColors =
    {
        new(255, 68, 68),  // Red
        new(68, 136, 255), // Blue
        new(68, 255, 68),  // Green
        new(255, 255, 68), // Yellow
    };

    static readonly Color[] TeamColorsDark =
    {
        new(180, 40, 40),
        new(40, 90, 180),
        new(40, 180, 40),
        new(180, 180, 40),
    };

    static readonly string[] TeamNames = { "Red", "Blue", "Green", "Yellow" };

    // ── Level data [centerX, centerY, width, height] ────────────────────────
    static readonly float[][] Level =
    {
        new[]{13.5f,2f,1f,4f},    new[]{13.5f,12f,1f,2f},   new[]{12.5f,13.5f,3f,1f}, new[]{2f,13.5f,4f,1f},
        new[]{11.5f,15f,1f,2f},   new[]{11.5f,23.5f,1f,5f},
        new[]{10f,26.5f,4f,1f},   new[]{6f,26.5f,4f,1f},
        new[]{2f,34.5f,4f,1f},    new[]{12.5f,34.5f,3f,1f}, new[]{13.5f,36f,1f,2f},   new[]{15f,36.5f,2f,1f},
        new[]{13.5f,46f,1f,4f},
        new[]{23.5f,36.5f,5f,1f}, new[]{26.5f,38f,1f,4f},   new[]{26.5f,42f,1f,4f},
        new[]{34.5f,46f,1f,4f},   new[]{34.5f,36f,1f,2f},   new[]{35.5f,34.5f,3f,1f}, new[]{36.5f,33f,1f,2f},
        new[]{46f,34.5f,4f,1f},
        new[]{36.5f,24.5f,1f,5f}, new[]{38f,21.5f,4f,1f},   new[]{42f,21.5f,4f,1f},
        new[]{46f,13.5f,4f,1f},   new[]{35.5f,13.5f,3f,1f}, new[]{34.5f,12f,1f,2f},   new[]{33f,11.5f,2f,1f},
        new[]{34.5f,2f,1f,4f},
        new[]{24.5f,11.5f,5f,1f}, new[]{21.5f,10f,1f,4f},   new[]{21.5f,6f,1f,4f},
        // center
        new[]{18.5f,22f,1f,6f},   new[]{19f,18.5f,2f,1f},   new[]{26f,18.5f,6f,1f},   new[]{29.5f,19f,1f,2f},
        new[]{29.5f,26f,1f,6f},   new[]{29f,29.5f,2f,1f},   new[]{22f,29.5f,6f,1f},   new[]{18.5f,29f,1f,2f},
    };

    const float WorldSize = 48f;
    const float ViewSize = 22f;
    const string ServerUrl = "ws://localhost:2567";

    // ── Fields ──────────────────────────────────────────────────────────────
    readonly GraphicsDeviceManager _graphics;
    SpriteBatch _spriteBatch;
    Texture2D _pixel;
    Texture2D _circle;
    BitmapFont _font;

    // Network
    Client _client;
    Room<BattleState> _room;
    string _sessionId = "";
    bool _connected;
    string _statusText = "Connecting...";

    // Entity visuals
    readonly Dictionary<string, TankVisual> _tankVisuals = new();
    readonly Dictionary<string, BulletVisual> _bulletVisuals = new();
    readonly Dictionary<string, PickableState> _pickables = new();
    readonly object _syncLock = new();

    // Camera
    Vector2 _cameraPos = new(24, 24);

    // Input
    KeyboardState _keyboard;
    MouseState _mouse;
    int _lastDirX = -999, _lastDirY = -999;
    float _lastAngle = -999;
    double _lastAngleTime;
    bool _mouseWasDown;

    // HUD state
    int _myHp = 10, _myShield;
    bool _myDead;
    byte _myTeam;
    int _winnerTeam = -1;
    double _winnerTime;
    readonly int[] _teamScores = new int[4];

    // ── Constructor ─────────────────────────────────────────────────────────
    public TankGame()
    {
        _graphics = new GraphicsDeviceManager(this);
        Content.RootDirectory = ".";
        IsMouseVisible = true;
        Window.AllowUserResizing = true;
    }

    // ── Initialize ──────────────────────────────────────────────────────────
    protected override void Initialize()
    {
        _graphics.PreferredBackBufferWidth = 1280;
        _graphics.PreferredBackBufferHeight = 720;
        _graphics.ApplyChanges();
        base.Initialize();
    }

    // ── LoadContent ─────────────────────────────────────────────────────────
    protected override void LoadContent()
    {
        _spriteBatch = new SpriteBatch(GraphicsDevice);

        // 1×1 white pixel for rectangle drawing
        _pixel = new Texture2D(GraphicsDevice, 1, 1);
        _pixel.SetData(new[] { Color.White });

        // 64×64 circle texture
        const int cs = 64;
        _circle = new Texture2D(GraphicsDevice, cs, cs);
        var circleData = new Color[cs * cs];
        const float cr = cs / 2f;
        for (int y = 0; y < cs; y++)
        for (int x = 0; x < cs; x++)
        {
            float dx = x - cr + 0.5f, dy = y - cr + 0.5f;
            circleData[y * cs + x] = MathF.Sqrt(dx * dx + dy * dy) <= cr
                ? Color.White
                : Color.Transparent;
        }
        _circle.SetData(circleData);

        _font = new BitmapFont(_pixel);

        _ = ConnectAsync();
    }

    // ── Network ─────────────────────────────────────────────────────────────
    async Task ConnectAsync()
    {
        try
        {
            _client = new Client(ServerUrl);
            _room = await _client.JoinOrCreate<BattleState>("battle");
            _sessionId = _room.SessionId;
            BindCallbacks();
            _connected = true;
        }
        catch (Exception ex)
        {
            _statusText = $"Failed to connect.\nIs the server running on {ServerUrl}?\n{ex.Message}";
        }
        // connection attempt finished
    }

    void BindCallbacks()
    {
        var callbacks = Callbacks.Get(_room);

        // ── Tanks ──
        callbacks.OnAdd("tanks", (string key, TankState tank) =>
        {
            lock (_syncLock)
            {
                _tankVisuals[key] = new TankVisual
                {
                    CurrentX = tank.x, CurrentY = tank.y,
                    TargetX = tank.x, TargetY = tank.y,
                    PrevTargetX = tank.x, PrevTargetY = tank.y,
                    Team = tank.team,
                    Hp = tank.hp, Shield = tank.shield,
                    Dead = tank.dead,
                    TurretAngle = tank.angle,
                    TargetTurretAngle = tank.angle,
                    Schema = tank,
                };
            }
        });
        callbacks.OnRemove("tanks", (string key, TankState _) =>
        {
            lock (_syncLock) { _tankVisuals.Remove(key); }
        });

        // ── Bullets ──
        callbacks.OnAdd("bullets", (string key, BulletState bullet) =>
        {
            byte team = 0;
            lock (_syncLock)
            {
                if (_tankVisuals.TryGetValue(bullet.owner, out var ownerVis))
                    team = ownerVis.Team;

                _bulletVisuals[key] = new BulletVisual
                {
                    CurrentX = bullet.x, CurrentY = bullet.y,
                    ServerX = bullet.x, ServerY = bullet.y,
                    OwnerTeam = team, Special = bullet.special,
                    Schema = bullet,
                };
            }
        });
        callbacks.OnRemove("bullets", (string key, BulletState _) =>
        {
            lock (_syncLock) { _bulletVisuals.Remove(key); }
        });

        // ── Pickables ──
        callbacks.OnAdd("pickables", (string key, PickableState pick) =>
        {
            lock (_syncLock) { _pickables[key] = pick; }
        });
        callbacks.OnRemove("pickables", (string key, PickableState _) =>
        {
            lock (_syncLock) { _pickables.Remove(key); }
        });
    }

    // ── Update ──────────────────────────────────────────────────────────────
    protected override void Update(GameTime gameTime)
    {
        _keyboard = Keyboard.GetState();
        _mouse = Mouse.GetState();

        if (_keyboard.IsKeyDown(Keys.Escape))
            Exit();

        if (!_connected)
        {
            base.Update(gameTime);
            return;
        }

        double time = gameTime.TotalGameTime.TotalSeconds;

        HandleInput(time);
        SyncAndInterpolate();
        UpdateCamera();
        UpdateHud(time);

        base.Update(gameTime);
    }

    void HandleInput(double time)
    {
        // ── Movement (WASD / Arrows) ──
        int rawX = 0, rawY = 0;
        if (_keyboard.IsKeyDown(Keys.W) || _keyboard.IsKeyDown(Keys.Up)) rawY -= 1;
        if (_keyboard.IsKeyDown(Keys.S) || _keyboard.IsKeyDown(Keys.Down)) rawY += 1;
        if (_keyboard.IsKeyDown(Keys.A) || _keyboard.IsKeyDown(Keys.Left)) rawX -= 1;
        if (_keyboard.IsKeyDown(Keys.D) || _keyboard.IsKeyDown(Keys.Right)) rawX += 1;

        if (rawX != _lastDirX || rawY != _lastDirY)
        {
            _room.Send("move", new Dictionary<string, object> { { "x", rawX }, { "y", rawY } });
            _lastDirX = rawX;
            _lastDirY = rawY;
        }

        // ── Turret aiming (mouse → world position → angle) ──
        TankVisual myTank;
        lock (_syncLock) { _tankVisuals.TryGetValue(_sessionId, out myTank); }

        if (myTank != null)
        {
            var inv = Matrix.Invert(GetCameraTransform());
            var mouseWorld = Vector2.Transform(new Vector2(_mouse.X, _mouse.Y), inv);

            float dx = mouseWorld.X - myTank.CurrentX;
            float dy = mouseWorld.Y - myTank.CurrentY;
            float angle = MathF.Atan2(dx, dy) * (180f / MathF.PI);
            angle = ((angle % 360) + 360) % 360;

            myTank.TargetTurretAngle = angle;

            if (MathF.Abs(angle - _lastAngle) > 1 && time - _lastAngleTime >= 0.1)
            {
                _room.Send("target", angle);
                _lastAngle = angle;
                _lastAngleTime = time;
            }
        }

        // ── Shooting (left mouse button) ──
        bool mouseDown = _mouse.LeftButton == ButtonState.Pressed;
        if (mouseDown != _mouseWasDown)
        {
            _room.Send("shoot", mouseDown);
            _mouseWasDown = mouseDown;
        }
    }

    void SyncAndInterpolate()
    {
        lock (_syncLock)
        {
            // ── Tanks ──
            foreach (var (key, vis) in _tankVisuals)
            {
                var s = vis.Schema;
                vis.PrevTargetX = vis.TargetX;
                vis.PrevTargetY = vis.TargetY;
                vis.TargetX = s.x;
                vis.TargetY = s.y;
                vis.Team = s.team;
                vis.Hp = s.hp;
                vis.Shield = s.shield;
                vis.Dead = s.dead;

                if (key != _sessionId)
                    vis.TargetTurretAngle = s.angle;

                // Position interpolation
                vis.CurrentX = MathHelper.Lerp(vis.CurrentX, vis.TargetX, 0.2f);
                vis.CurrentY = MathHelper.Lerp(vis.CurrentY, vis.TargetY, 0.2f);

                // Body rotation from movement direction
                float mdx = vis.TargetX - vis.PrevTargetX;
                float mdy = vis.TargetY - vis.PrevTargetY;
                if (mdx * mdx + mdy * mdy > 0.0001f)
                    vis.TargetBodyAngle = MathF.Atan2(mdy, mdx);
                vis.BodyAngle = LerpAngleRad(vis.BodyAngle, vis.TargetBodyAngle, 0.15f);

                // Turret angle interpolation (degrees)
                vis.TurretAngle = LerpAngleDeg(vis.TurretAngle, vis.TargetTurretAngle, 0.25f);

                // Track own state
                if (key == _sessionId)
                {
                    _myHp = s.hp;
                    _myShield = s.shield;
                    _myDead = s.dead;
                    _myTeam = s.team;
                }
            }

            // ── Bullets ──
            foreach (var (_, vis) in _bulletVisuals)
            {
                vis.ServerX = vis.Schema.x;
                vis.ServerY = vis.Schema.y;
                vis.CurrentX = MathHelper.Lerp(vis.CurrentX, vis.ServerX, 0.4f);
                vis.CurrentY = MathHelper.Lerp(vis.CurrentY, vis.ServerY, 0.4f);
            }
        }
    }

    void UpdateCamera()
    {
        TankVisual my;
        lock (_syncLock) { _tankVisuals.TryGetValue(_sessionId, out my); }
        if (my == null) return;

        var target = new Vector2(my.CurrentX, my.CurrentY);

        // Mouse look-ahead
        var vp = GraphicsDevice.Viewport;
        float nx = (_mouse.X / (float)vp.Width) * 2 - 1;
        float ny = (_mouse.Y / (float)vp.Height) * 2 - 1;
        const float lookAhead = 3f;
        target.X += nx * lookAhead;
        target.Y += ny * lookAhead;

        _cameraPos = Vector2.Lerp(_cameraPos, target, 0.08f);
    }

    void UpdateHud(double time)
    {
        var state = _room?.State;
        if (state == null) return;

        // Winner detection
        if (state.winnerTeam >= 0 && _winnerTeam < 0)
        {
            _winnerTeam = state.winnerTeam;
            _winnerTime = time;
        }
        if (_winnerTeam >= 0 && time - _winnerTime > 3.5)
            _winnerTeam = -1;

        // Team scores
        if (state.teams != null)
        {
            for (int i = 0; i < 4; i++)
            {
                try { _teamScores[i] = state.teams[i]?.score ?? 0; }
                catch { _teamScores[i] = 0; }
            }
        }
    }

    // ── Draw ────────────────────────────────────────────────────────────────
    protected override void Draw(GameTime gameTime)
    {
        GraphicsDevice.Clear(BgColor);

        var transform = GetCameraTransform();

        // ── World pass ──
        _spriteBatch.Begin(
            SpriteSortMode.Deferred,
            BlendState.AlphaBlend,
            SamplerState.PointClamp,
            null, null, null,
            transform);

        DrawGround();
        DrawGrid();
        DrawBlocks();
        DrawBoundary();
        DrawPickables(gameTime);
        DrawBullets();
        DrawTanks(gameTime);

        _spriteBatch.End();

        // ── HUD pass (screen space) ──
        _spriteBatch.Begin(SpriteSortMode.Deferred, BlendState.AlphaBlend);
        DrawHud(gameTime);
        _spriteBatch.End();

        base.Draw(gameTime);
    }

    // ── World drawing ───────────────────────────────────────────────────────

    void DrawGround()
    {
        // Gradient from lighter (top) to darker (bottom)
        const int strips = 48;
        float stripH = WorldSize / strips;
        for (int i = 0; i < strips; i++)
        {
            float t = i / (float)strips;
            var c = new Color(
                (int)(46 - t * 28),   // 46 → 18
                (int)(75 - t * 39),   // 75 → 36
                (int)(107 - t * 51)); // 107 → 56
            _spriteBatch.Draw(_pixel, new Vector2(0, i * stripH), null, c,
                0f, Vector2.Zero, new Vector2(WorldSize, stripH + 0.02f), SpriteEffects.None, 0);
        }
    }

    void DrawGrid()
    {
        const float thickness = 0.03f;
        for (int i = 0; i <= 48; i++)
        {
            _spriteBatch.Draw(_pixel, new Vector2(i, 0), null, GridColor,
                0f, new Vector2(0.5f, 0), new Vector2(thickness, WorldSize), SpriteEffects.None, 0);
            _spriteBatch.Draw(_pixel, new Vector2(0, i), null, GridColor,
                0f, new Vector2(0, 0.5f), new Vector2(WorldSize, thickness), SpriteEffects.None, 0);
        }
    }

    void DrawBlocks()
    {
        foreach (var b in Level)
        {
            float cx = b[0], cy = b[1], w = b[2], h = b[3];
            _spriteBatch.Draw(_pixel, new Vector2(cx - w / 2, cy - h / 2), null, BlockColor,
                0f, Vector2.Zero, new Vector2(w, h), SpriteEffects.None, 0);
            DrawRectOutline(cx, cy, w, h, BlockOutline, 0.06f);
        }
    }

    void DrawBoundary()
    {
        const float t = 1.5f;
        float total = WorldSize + t * 2;
        // North
        _spriteBatch.Draw(_pixel, new Vector2(-t, -t), null, WallColor,
            0, Vector2.Zero, new Vector2(total, t), SpriteEffects.None, 0);
        // South
        _spriteBatch.Draw(_pixel, new Vector2(-t, WorldSize), null, WallColor,
            0, Vector2.Zero, new Vector2(total, t), SpriteEffects.None, 0);
        // West
        _spriteBatch.Draw(_pixel, new Vector2(-t, 0), null, WallColor,
            0, Vector2.Zero, new Vector2(t, WorldSize), SpriteEffects.None, 0);
        // East
        _spriteBatch.Draw(_pixel, new Vector2(WorldSize, 0), null, WallColor,
            0, Vector2.Zero, new Vector2(t, WorldSize), SpriteEffects.None, 0);
    }

    void DrawPickables(GameTime gameTime)
    {
        float t = (float)gameTime.TotalGameTime.TotalSeconds;
        float bob = MathF.Sin(t * 2) * 0.15f;
        float pulse = 0.85f + MathF.Sin(t * 3) * 0.15f;

        lock (_syncLock)
        {
            foreach (var (_, pick) in _pickables)
            {
                Color color = pick.type switch
                {
                    "repair" => new Color(68, 255, 68),
                    "shield" => new Color(68, 136, 255),
                    "damage" => new Color(255, 68, 68),
                    _ => Color.White,
                };

                float py = pick.y + bob;
                // Glow
                FillCircle(pick.x, py, 0.5f * pulse, color * 0.12f);
                // Core
                FillCircle(pick.x, py, 0.22f, color);

                // Type indicator
                if (pick.type == "repair")
                {
                    // Plus sign
                    _spriteBatch.Draw(_pixel, new Vector2(pick.x, py), null, Color.White * 0.9f,
                        0, new Vector2(0.5f, 0.5f), new Vector2(0.35f, 0.1f), SpriteEffects.None, 0);
                    _spriteBatch.Draw(_pixel, new Vector2(pick.x, py), null, Color.White * 0.9f,
                        0, new Vector2(0.5f, 0.5f), new Vector2(0.1f, 0.35f), SpriteEffects.None, 0);
                }
                else if (pick.type == "shield")
                {
                    // Small ring outline
                    FillCircle(pick.x, py, 0.18f, Color.White * 0.3f);
                    FillCircle(pick.x, py, 0.12f, color);
                }
                else if (pick.type == "damage")
                {
                    // Diamond shape (rotated square)
                    _spriteBatch.Draw(_pixel, new Vector2(pick.x, py), null, Color.White * 0.9f,
                        MathF.PI / 4, new Vector2(0.5f, 0.5f), new Vector2(0.22f, 0.22f), SpriteEffects.None, 0);
                }
            }
        }
    }

    void DrawBullets()
    {
        lock (_syncLock)
        {
            foreach (var (_, vis) in _bulletVisuals)
            {
                Color color = vis.Special ? new Color(255, 136, 0) : TeamColors[vis.OwnerTeam % 4];
                float radius = vis.Special ? 0.2f : 0.12f;

                // Glow
                FillCircle(vis.CurrentX, vis.CurrentY, radius * 2.5f, color * 0.15f);
                // Core
                FillCircle(vis.CurrentX, vis.CurrentY, radius, color);
            }
        }
    }

    void DrawTanks(GameTime gameTime)
    {
        float time = (float)gameTime.TotalGameTime.TotalSeconds;

        lock (_syncLock)
        {
            foreach (var (key, vis) in _tankVisuals)
            {
                // Dead tanks blink
                if (vis.Dead)
                {
                    if (MathF.Sin(time * 12) < 0) continue;
                }

                Color teamColor = TeamColors[vis.Team % 4];
                Color teamDark = TeamColorsDark[vis.Team % 4];
                float cx = vis.CurrentX, cy = vis.CurrentY;
                bool isMe = key == _sessionId;

                // ── Team indicator ring ──
                FillCircle(cx, cy, 0.85f, teamColor * 0.2f);

                // ── Shield bubble ──
                if (vis.Shield > 0)
                {
                    float sa = 0.10f + 0.04f * MathF.Sin(time * 3);
                    FillCircle(cx, cy, 1.05f, new Color(68, 200, 255) * sa);
                }

                // ── Tank body (rotated rectangle) ──
                _spriteBatch.Draw(_pixel, new Vector2(cx, cy), null, teamDark,
                    vis.BodyAngle, new Vector2(0.5f, 0.5f), new Vector2(1.4f, 0.9f),
                    SpriteEffects.None, 0);

                // Body highlight
                _spriteBatch.Draw(_pixel, new Vector2(cx, cy), null, teamColor * 0.4f,
                    vis.BodyAngle, new Vector2(0.5f, 0.5f), new Vector2(1.3f, 0.8f),
                    SpriteEffects.None, 0);

                // ── Turret ──
                float aRad = MathHelper.ToRadians(vis.TurretAngle);
                float tdx = MathF.Sin(aRad), tdy = MathF.Cos(aRad);
                var turretStart = new Vector2(cx, cy);
                var turretEnd = new Vector2(cx + tdx * 1.2f, cy + tdy * 1.2f);
                DrawLine(turretStart, turretEnd, 0.2f, teamColor);

                // Turret muzzle
                FillCircle(cx + tdx * 1.15f, cy + tdy * 1.15f, 0.14f, teamColor);

                // Turret pivot
                FillCircle(cx, cy, 0.25f, teamDark);

                // ── Health bar (above tank) ──
                if (vis.Hp < 10 && vis.Hp > 0)
                {
                    float barW = 1.2f, barH = 0.1f;
                    float barY = cy - 1.15f;
                    // Background
                    _spriteBatch.Draw(_pixel, new Vector2(cx - barW / 2, barY), null,
                        new Color(0, 0, 0, 160), 0, Vector2.Zero, new Vector2(barW, barH), SpriteEffects.None, 0);
                    // Fill
                    float pct = vis.Hp / 10f;
                    Color hpColor = pct > 0.5f ? Color.Lime : pct > 0.25f ? Color.Orange : Color.Red;
                    _spriteBatch.Draw(_pixel, new Vector2(cx - barW / 2, barY), null,
                        hpColor, 0, Vector2.Zero, new Vector2(barW * pct, barH), SpriteEffects.None, 0);
                }

                // ── "You" indicator ──
                if (isMe && !vis.Dead)
                {
                    float ia = 0.3f + 0.15f * MathF.Sin(time * 2);
                    DrawRectOutline(cx, cy, 1.6f, 1.6f, Color.White * ia, 0.04f);
                }
            }
        }
    }

    // ── HUD drawing ─────────────────────────────────────────────────────────

    void DrawHud(GameTime gameTime)
    {
        var vp = GraphicsDevice.Viewport;
        int sw = vp.Width, sh = vp.Height;

        // ── Status text while connecting ──
        if (!_connected)
        {
            DrawCenteredText(_statusText, sw / 2, sh / 2, Color.White, 1f);
            return;
        }

        // ── Health bar ──
        const float barW = 200, barH = 14;
        float barX = sw / 2f - barW / 2;
        float barY = sh - 50;

        // Background
        _spriteBatch.Draw(_pixel, new Vector2(barX - 1, barY - 1), null, new Color(0, 0, 0, 200),
            0, Vector2.Zero, new Vector2(barW + 2, barH + 2), SpriteEffects.None, 0);
        float hpPct = Math.Clamp(_myHp / 10f, 0, 1);
        Color hpColor = hpPct > 0.5f ? Color.Lime : hpPct > 0.25f ? Color.Orange : Color.Red;
        _spriteBatch.Draw(_pixel, new Vector2(barX, barY), null, hpColor,
            0, Vector2.Zero, new Vector2(barW * hpPct, barH), SpriteEffects.None, 0);

        // ── Shield bar ──
        if (_myShield > 0)
        {
            float sY = barY - barH - 6;
            _spriteBatch.Draw(_pixel, new Vector2(barX - 1, sY - 1), null, new Color(0, 0, 0, 200),
                0, Vector2.Zero, new Vector2(barW + 2, barH + 2), SpriteEffects.None, 0);
            float sPct = Math.Clamp(_myShield / 10f, 0, 1);
            _spriteBatch.Draw(_pixel, new Vector2(barX, sY), null, new Color(0, 200, 255),
                0, Vector2.Zero, new Vector2(barW * sPct, barH), SpriteEffects.None, 0);
        }

        // ── Team scores ──
        var sorted = new List<(int id, int score)>();
        for (int i = 0; i < 4; i++) sorted.Add((i, _teamScores[i]));
        sorted.Sort((a, b) => b.score.CompareTo(a.score));

        for (int i = 0; i < sorted.Count; i++)
        {
            var (id, score) = sorted[i];
            float tx = sw - 140;
            float ty = 20 + i * 28;

            // Team color swatch
            _spriteBatch.Draw(_pixel, new Vector2(tx - 18, ty + 2), null, TeamColors[id],
                0, Vector2.Zero, new Vector2(12, 12), SpriteEffects.None, 0);

            DrawText($"{TeamNames[id]}: {score}", tx, ty, Color.White);
        }

        // ── Death overlay ──
        if (_myDead)
        {
            _spriteBatch.Draw(_pixel, Vector2.Zero, null, new Color(0, 0, 0, 120),
                0, Vector2.Zero, new Vector2(sw, sh), SpriteEffects.None, 0);

            // Red stripe
            _spriteBatch.Draw(_pixel, new Vector2(0, sh / 2f - 30), null, new Color(200, 30, 30, 200),
                0, Vector2.Zero, new Vector2(sw, 60), SpriteEffects.None, 0);

            DrawCenteredText("DESTROYED", sw / 2, sh / 2, Color.White, 2f);
        }

        // ── Winner overlay ──
        if (_winnerTeam >= 0)
        {
            _spriteBatch.Draw(_pixel, Vector2.Zero, null, new Color(0, 0, 0, 180),
                0, Vector2.Zero, new Vector2(sw, sh), SpriteEffects.None, 0);

            Color stripe = TeamColors[_winnerTeam % 4] * 0.8f;
            _spriteBatch.Draw(_pixel, new Vector2(0, sh / 2f - 45), null, stripe,
                0, Vector2.Zero, new Vector2(sw, 90), SpriteEffects.None, 0);

            bool isWinner = _myTeam == _winnerTeam;
            DrawCenteredText(isWinner ? "VICTORY" : "DEFEAT", sw / 2, sh / 2 - 12, Color.White, 2f);
            DrawCenteredText($"{TeamNames[_winnerTeam % 4]} Team Wins", sw / 2, sh / 2 + 20, Color.White * 0.9f, 1f);
        }
    }

    // ── Drawing helpers ─────────────────────────────────────────────────────

    Matrix GetCameraTransform()
    {
        var vp = GraphicsDevice.Viewport;
        float zoom = vp.Height / ViewSize;
        return Matrix.CreateTranslation(-_cameraPos.X, -_cameraPos.Y, 0) *
               Matrix.CreateScale(zoom, zoom, 1) *
               Matrix.CreateTranslation(vp.Width / 2f, vp.Height / 2f, 0);
    }

    void FillCircle(float cx, float cy, float radius, Color color)
    {
        float scale = radius * 2f / _circle.Width;
        _spriteBatch.Draw(_circle, new Vector2(cx, cy), null, color,
            0f, new Vector2(_circle.Width / 2f, _circle.Height / 2f),
            scale, SpriteEffects.None, 0);
    }

    void DrawRectOutline(float cx, float cy, float w, float h, Color color, float t)
    {
        float l = cx - w / 2, top = cy - h / 2;
        _spriteBatch.Draw(_pixel, new Vector2(l, top), null, color, 0, Vector2.Zero, new Vector2(w, t), SpriteEffects.None, 0);
        _spriteBatch.Draw(_pixel, new Vector2(l, cy + h / 2 - t), null, color, 0, Vector2.Zero, new Vector2(w, t), SpriteEffects.None, 0);
        _spriteBatch.Draw(_pixel, new Vector2(l, top), null, color, 0, Vector2.Zero, new Vector2(t, h), SpriteEffects.None, 0);
        _spriteBatch.Draw(_pixel, new Vector2(cx + w / 2 - t, top), null, color, 0, Vector2.Zero, new Vector2(t, h), SpriteEffects.None, 0);
    }

    void DrawLine(Vector2 start, Vector2 end, float thickness, Color color)
    {
        var diff = end - start;
        float length = diff.Length();
        if (length < 0.001f) return;
        float angle = MathF.Atan2(diff.Y, diff.X);
        _spriteBatch.Draw(_pixel, start, null, color,
            angle, new Vector2(0, 0.5f), new Vector2(length, thickness),
            SpriteEffects.None, 0);
    }

    void DrawText(string text, float x, float y, Color color, float scale = 1f)
    {
        _font?.DrawString(_spriteBatch, text, new Vector2(x, y), color, scale);
    }

    void DrawCenteredText(string text, float cx, float cy, Color color, float scale = 1f)
    {
        if (_font == null) return;
        var size = _font.MeasureString(text, scale);
        _font.DrawString(_spriteBatch, text, new Vector2(cx - size.X / 2, cy - size.Y / 2), color, scale);
    }

    // ── Math helpers ────────────────────────────────────────────────────────

    static float LerpAngleRad(float from, float to, float t)
    {
        float diff = to - from;
        while (diff > MathF.PI) diff -= MathF.PI * 2;
        while (diff < -MathF.PI) diff += MathF.PI * 2;
        return from + diff * t;
    }

    static float LerpAngleDeg(float from, float to, float t)
    {
        float diff = ((to - from + 540) % 360) - 180;
        return from + diff * t;
    }
}

// ── Visual state classes ────────────────────────────────────────────────────

class TankVisual
{
    public float CurrentX, CurrentY;
    public float TargetX, TargetY;
    public float PrevTargetX, PrevTargetY;
    public float BodyAngle, TargetBodyAngle;
    public float TurretAngle, TargetTurretAngle;
    public byte Team;
    public sbyte Hp = 10, Shield;
    public bool Dead;
    public TankState Schema;
}

class BulletVisual
{
    public float CurrentX, CurrentY;
    public float ServerX, ServerY;
    public byte OwnerTeam;
    public bool Special;
    public BulletState Schema;
}

// ── Bitmap font (no Content Pipeline needed) ────────────────────────────────

class BitmapFont
{
    readonly Texture2D _pixel;
    const int CW = 5; // char width in pixels
    const int CH = 7; // char height in pixels
    const int SP = 1; // spacing

    // 5×7 pixel font glyphs — each byte = one row, lower 5 bits used
    static readonly Dictionary<char, byte[]> Glyphs = new()
    {
        [' '] = new byte[] { 0, 0, 0, 0, 0, 0, 0 },
        ['!'] = new byte[] { 4, 4, 4, 4, 4, 0, 4 },
        ['.'] = new byte[] { 0, 0, 0, 0, 0, 0, 4 },
        [','] = new byte[] { 0, 0, 0, 0, 0, 4, 8 },
        [':'] = new byte[] { 0, 4, 0, 0, 0, 4, 0 },
        ['-'] = new byte[] { 0, 0, 0, 14, 0, 0, 0 },
        ['/'] = new byte[] { 1, 1, 2, 4, 8, 16, 16 },
        ['?'] = new byte[] { 14, 17, 1, 6, 4, 0, 4 },
        ['('] = new byte[] { 2, 4, 8, 8, 8, 4, 2 },
        [')'] = new byte[] { 8, 4, 2, 2, 2, 4, 8 },
        ['0'] = new byte[] { 14, 17, 19, 21, 25, 17, 14 },
        ['1'] = new byte[] { 4, 12, 4, 4, 4, 4, 14 },
        ['2'] = new byte[] { 14, 17, 1, 6, 8, 16, 31 },
        ['3'] = new byte[] { 14, 17, 1, 6, 1, 17, 14 },
        ['4'] = new byte[] { 2, 6, 10, 18, 31, 2, 2 },
        ['5'] = new byte[] { 31, 16, 30, 1, 1, 17, 14 },
        ['6'] = new byte[] { 6, 8, 16, 30, 17, 17, 14 },
        ['7'] = new byte[] { 31, 1, 2, 4, 8, 8, 8 },
        ['8'] = new byte[] { 14, 17, 17, 14, 17, 17, 14 },
        ['9'] = new byte[] { 14, 17, 17, 15, 1, 2, 12 },
        ['A'] = new byte[] { 14, 17, 17, 31, 17, 17, 17 },
        ['B'] = new byte[] { 30, 17, 17, 30, 17, 17, 30 },
        ['C'] = new byte[] { 14, 17, 16, 16, 16, 17, 14 },
        ['D'] = new byte[] { 30, 17, 17, 17, 17, 17, 30 },
        ['E'] = new byte[] { 31, 16, 16, 30, 16, 16, 31 },
        ['F'] = new byte[] { 31, 16, 16, 30, 16, 16, 16 },
        ['G'] = new byte[] { 14, 17, 16, 23, 17, 17, 14 },
        ['H'] = new byte[] { 17, 17, 17, 31, 17, 17, 17 },
        ['I'] = new byte[] { 14, 4, 4, 4, 4, 4, 14 },
        ['J'] = new byte[] { 7, 2, 2, 2, 18, 18, 12 },
        ['K'] = new byte[] { 17, 18, 20, 24, 20, 18, 17 },
        ['L'] = new byte[] { 16, 16, 16, 16, 16, 16, 31 },
        ['M'] = new byte[] { 17, 27, 21, 21, 17, 17, 17 },
        ['N'] = new byte[] { 17, 25, 21, 19, 17, 17, 17 },
        ['O'] = new byte[] { 14, 17, 17, 17, 17, 17, 14 },
        ['P'] = new byte[] { 30, 17, 17, 30, 16, 16, 16 },
        ['Q'] = new byte[] { 14, 17, 17, 17, 21, 18, 13 },
        ['R'] = new byte[] { 30, 17, 17, 30, 20, 18, 17 },
        ['S'] = new byte[] { 14, 17, 16, 14, 1, 17, 14 },
        ['T'] = new byte[] { 31, 4, 4, 4, 4, 4, 4 },
        ['U'] = new byte[] { 17, 17, 17, 17, 17, 17, 14 },
        ['V'] = new byte[] { 17, 17, 17, 17, 10, 10, 4 },
        ['W'] = new byte[] { 17, 17, 17, 21, 21, 27, 17 },
        ['X'] = new byte[] { 17, 17, 10, 4, 10, 17, 17 },
        ['Y'] = new byte[] { 17, 17, 10, 4, 4, 4, 4 },
        ['Z'] = new byte[] { 31, 1, 2, 4, 8, 16, 31 },
    };

    public BitmapFont(Texture2D pixel) => _pixel = pixel;

    public void DrawString(SpriteBatch sb, string text, Vector2 pos, Color color, float scale = 1f)
    {
        float px = pos.X;
        float s = scale; // each "pixel" in the glyph = scale screen pixels
        foreach (char c in text.ToUpperInvariant())
        {
            if (Glyphs.TryGetValue(c, out var rows))
            {
                for (int row = 0; row < CH; row++)
                {
                    byte bits = rows[row];
                    for (int col = 0; col < CW; col++)
                    {
                        if ((bits & (1 << (CW - 1 - col))) != 0)
                        {
                            sb.Draw(_pixel, new Vector2(px + col * s, pos.Y + row * s), null, color,
                                0, Vector2.Zero, new Vector2(s, s), SpriteEffects.None, 0);
                        }
                    }
                }
            }
            px += (CW + SP) * s;
        }
    }

    public Vector2 MeasureString(string text, float scale = 1f)
    {
        return new Vector2(text.Length * (CW + SP) * scale, CH * scale);
    }
}
