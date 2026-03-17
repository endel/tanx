using System.Collections.Generic;
using UnityEngine;
using Colyseus;
using Colyseus.Schema;

public class GameManager : MonoBehaviour
{
    [Header("Server")]
    public string serverUrl = "ws://localhost:2567";


    private Client client;
    private Room<BattleState> room;
    private string mySessionId;

    private static readonly Color[] teamColors = {
        new Color(1f, 0.27f, 0.27f),
        new Color(0.27f, 0.53f, 1f),
        new Color(0.27f, 1f, 0.27f),
        new Color(1f, 1f, 0.27f),
    };
    private static readonly string[] teamNames = { "Red", "Blue", "Green", "Yellow" };

    // Game objects
    private Dictionary<string, TankEntity> tanks = new();
    private Dictionary<string, GameObject> bullets = new();
    private Dictionary<string, GameObject> pickables = new();
    private Dictionary<string, Vector2> bulletTargets = new();
    private List<GameObject> blocks = new();

    // Input
    private float lastDirX = -999, lastDirY = -999, lastAngle = -999;
    private float lastTargetSendTime = 0;
    private bool winnerActive = false;
    private float announcementTimer = 0;
    private string announcementString = "";
    private string leaderboardString = "";

    // GUI styles (created once)
    private GUIStyle hpBarStyle, hpBgStyle, shieldBarStyle, leaderboardStyle, announcementStyle;
    private bool guiInitialized = false;

    // Camera
    private Camera cam;

    // Level data (same as server)
    private static readonly float[][] LEVEL = {
        new[]{13.5f,2f,1f,4f}, new[]{13.5f,12f,1f,2f}, new[]{12.5f,13.5f,3f,1f}, new[]{2f,13.5f,4f,1f},
        new[]{11.5f,15f,1f,2f}, new[]{11.5f,23.5f,1f,5f},
        new[]{10f,26.5f,4f,1f}, new[]{6f,26.5f,4f,1f},
        new[]{2f,34.5f,4f,1f}, new[]{12.5f,34.5f,3f,1f}, new[]{13.5f,36f,1f,2f}, new[]{15f,36.5f,2f,1f},
        new[]{13.5f,46f,1f,4f},
        new[]{23.5f,36.5f,5f,1f}, new[]{26.5f,38f,1f,4f}, new[]{26.5f,42f,1f,4f},
        new[]{34.5f,46f,1f,4f}, new[]{34.5f,36f,1f,2f}, new[]{35.5f,34.5f,3f,1f}, new[]{36.5f,33f,1f,2f},
        new[]{46f,34.5f,4f,1f},
        new[]{36.5f,24.5f,1f,5f}, new[]{38f,21.5f,4f,1f}, new[]{42f,21.5f,4f,1f},
        new[]{46f,13.5f,4f,1f}, new[]{35.5f,13.5f,3f,1f}, new[]{34.5f,12f,1f,2f}, new[]{33f,11.5f,2f,1f},
        new[]{34.5f,2f,1f,4f},
        new[]{24.5f,11.5f,5f,1f}, new[]{21.5f,10f,1f,4f}, new[]{21.5f,6f,1f,4f},
        new[]{18.5f,22f,1f,6f}, new[]{19f,18.5f,2f,1f}, new[]{26f,18.5f,6f,1f}, new[]{29.5f,19f,1f,2f},
        new[]{29.5f,26f,1f,6f}, new[]{29f,29.5f,2f,1f}, new[]{22f,29.5f,6f,1f}, new[]{18.5f,29f,1f,2f},
    };

    async void Start()
    {
        // Override server URL in non-development release builds
        if (!Debug.isDebugBuild)
            serverUrl = "wss://tanks-demo.colyseus.dev";

        SetupCamera();
        BuildLevel();
        SetupLighting();

        try
        {
            Debug.Log($"Connecting to {serverUrl}...");
            client = new Client(serverUrl);
            room = await client.JoinOrCreate<BattleState>("battle");
            mySessionId = room.SessionId;
            Debug.Log($"Joined room {room.RoomId} as {mySessionId}");
            BindRoomEvents();
        }
        catch (System.Exception e)
        {
            Debug.LogError($"Connection failed: {e.Message}\n{e.StackTrace}");
        }
    }

    void SetupCamera()
    {
        cam = Camera.main;
        cam.orthographic = true;
        cam.orthographicSize = 11;
        cam.transform.position = new Vector3(44, 20, 44);
        cam.transform.LookAt(new Vector3(24, 0, 24));
        cam.backgroundColor = new Color(0.051f, 0.106f, 0.165f);
    }

    void SetupLighting()
    {
        RenderSettings.ambientLight = new Color(0.37f, 0.37f, 0.47f);

        var sunGO = new GameObject("Sun");
        var sun = sunGO.AddComponent<Light>();
        sun.type = LightType.Directional;
        sun.color = new Color(1f, 0.93f, 0.87f);
        sun.intensity = 1.2f;
        sun.shadows = LightShadows.Soft;
        sunGO.transform.eulerAngles = new Vector3(50, 30, 0);
    }

    void BuildLevel()
    {
        // Ground
        var ground = GameObject.CreatePrimitive(PrimitiveType.Plane);
        ground.transform.position = new Vector3(24, -0.01f, 24);
        ground.transform.localScale = new Vector3(4.8f, 1, 4.8f);
        ground.GetComponent<Renderer>().material.color = new Color(0.85f, 0.87f, 0.9f);

        // Blocks
        var blockMat = new Material(Shader.Find("Standard"));
        blockMat.color = new Color(0.13f, 0.4f, 0.67f, 0.85f);
        SetMaterialTransparent(blockMat);

        foreach (var b in LEVEL)
        {
            var block = GameObject.CreatePrimitive(PrimitiveType.Cube);
            block.transform.position = new Vector3(b[0], 0.6f, b[1]);
            block.transform.localScale = new Vector3(b[2], 1.2f, b[3]);
            block.GetComponent<Renderer>().material = new Material(blockMat);
            Destroy(block.GetComponent<Collider>());
            blocks.Add(block);
        }

        // Boundary walls
        var wallMat = new Material(Shader.Find("Standard"));
        wallMat.color = new Color(0.1f, 0.27f, 0.53f, 0.8f);
        SetMaterialTransparent(wallMat);

        float t = 1.5f;
        float[][] walls = {
            new[]{24f, -t/2, 48+t*2, t},
            new[]{24f, 48+t/2, 48+t*2, t},
            new[]{-t/2, 24f, t, 48+t*2},
            new[]{48+t/2, 24f, t, 48+t*2},
        };
        foreach (var w in walls)
        {
            var wall = GameObject.CreatePrimitive(PrimitiveType.Cube);
            wall.transform.position = new Vector3(w[0], 1, w[1]);
            wall.transform.localScale = new Vector3(w[2], 2, w[3]);
            wall.GetComponent<Renderer>().material = new Material(wallMat);
            Destroy(wall.GetComponent<Collider>());
            blocks.Add(wall);
        }
    }

    void BindRoomEvents()
    {
        var cb = Callbacks.Get(room);

        Debug.Log("Binding room events...");

        // Tanks
        cb.OnAdd(s => s.tanks, (string key, TankState tank) =>
        {
            Debug.Log($"Tank added: {key} team={tank.team} pos=({tank.x},{tank.y})");
            var entity = new TankEntity(tank, teamColors[tank.team % 4]);
            entity.SetPosition(tank.x, tank.y);
            tanks[key] = entity;

            cb.Listen(tank, t => t.x, (float val, float prev) => entity.targetX = val);
            cb.Listen(tank, t => t.y, (float val, float prev) => entity.targetZ = val);
            cb.Listen(tank, t => t.angle, (float val, float prev) =>
            {
                // Skip server angle updates for the current player — the client
                // already sets targetAngle directly from mouse input, and applying
                // the server's (delayed) value causes visual glitches.
                if (key != mySessionId)
                    entity.targetAngle = val;
            });
            cb.Listen(tank, t => t.dead, (bool val, bool prev) =>
            {
                bool wasAlive = !entity.dead;
                entity.SetDead(val);
                if (val && wasAlive && entity.hp <= 0)
                    SpawnExplosion(entity.Position);
                if (key == mySessionId && val && !winnerActive)
                    ShowAnnouncement("DESTROYED\nRespawning...", 2f);
            });
            cb.Listen(tank, t => t.hp, (sbyte val, sbyte prev) =>
            {
                entity.hp = val;
            });
            cb.Listen(tank, t => t.shield, (sbyte val, sbyte prev) =>
            {
                entity.SetShield(val);
            });
            cb.Listen(tank, t => t.score, (ushort val, ushort prev) => UpdateLeaderboard());
        });

        cb.OnRemove(s => s.tanks, (string key, TankState tank) =>
        {
            if (tanks.TryGetValue(key, out var entity))
            {
                entity.Destroy();
                tanks.Remove(key);
            }
        });

        // Bullets
        cb.OnAdd(s => s.bullets, (string key, BulletState bullet) =>
        {
            var go = GameObject.CreatePrimitive(PrimitiveType.Sphere);
            float radius = bullet.special ? 0.2f : 0.12f;
            go.transform.localScale = Vector3.one * radius * 2;
            go.transform.position = new Vector3(bullet.x, 0.55f, bullet.y);
            var color = bullet.special ? new Color(1, 0.53f, 0) : new Color(1, 1, 0.4f);
            go.GetComponent<Renderer>().material.color = color;
            Destroy(go.GetComponent<Collider>());

            bullets[key] = go;
            bulletTargets[key] = new Vector2(bullet.x, bullet.y);

            cb.Listen(bullet, b => b.x, (float val, float prev) =>
            {
                if (bulletTargets.ContainsKey(key))
                    bulletTargets[key] = new Vector2(val, bulletTargets[key].y);
            });
            cb.Listen(bullet, b => b.y, (float val, float prev) =>
            {
                if (bulletTargets.ContainsKey(key))
                    bulletTargets[key] = new Vector2(bulletTargets[key].x, val);
            });
        });

        cb.OnRemove(s => s.bullets, (string key, BulletState bullet) =>
        {
            if (bullets.TryGetValue(key, out var go))
            {
                Destroy(go);
                bullets.Remove(key);
                bulletTargets.Remove(key);
            }
        });

        // Pickables
        cb.OnAdd(s => s.pickables, (string key, PickableState pick) =>
        {
            var go = CreatePickable(pick);
            go.transform.position = new Vector3(pick.x, 0.6f, pick.y);
            pickables[key] = go;
        });

        cb.OnRemove(s => s.pickables, (string key, PickableState pick) =>
        {
            Debug.Log($"Pickable removed: {key}");
            if (pickables.TryGetValue(key, out var go))
            {
                Destroy(go);
                pickables.Remove(key);
            }
        });

        // Teams
        cb.OnAdd(s => s.teams, (int idx, TeamState team) =>
        {
            cb.Listen(team, t => t.score, (ushort val, ushort prev) => UpdateLeaderboard());
        });

        // Winner
        cb.Listen(s => s.winnerTeam, (sbyte val, sbyte prev) =>
        {
            if (val >= 0 && val != prev)
            {
                winnerActive = true;
                bool isWinner = tanks.ContainsKey(mySessionId) && tanks[mySessionId].team == val;
                string text = isWinner ? "VICTORY" : "DEFEAT";
                ShowAnnouncement($"{text}\n{teamNames[val % 4]} Team Wins", 3f);
                Invoke(nameof(ClearWinnerFlag), 3f);
            }
        });
    }

    void ClearWinnerFlag() => winnerActive = false;

    void Update()
    {
        if (room == null) return;

        SendInput();

        foreach (var kvp in tanks)
            kvp.Value.Update(Time.deltaTime);

        // Bullet interpolation (frame-rate independent)
        float bulletSmooth = 1f - Mathf.Pow(1f - 0.4f, Time.deltaTime * 60f);
        foreach (var kvp in bullets)
        {
            if (bulletTargets.TryGetValue(kvp.Key, out var target))
            {
                var pos = kvp.Value.transform.position;
                kvp.Value.transform.position = new Vector3(
                    Mathf.Lerp(pos.x, target.x, bulletSmooth),
                    0.55f,
                    Mathf.Lerp(pos.z, target.y, bulletSmooth));
            }
        }

        // Pickable animation
        float t = Time.time;
        foreach (var kvp in pickables)
        {
            var pos = kvp.Value.transform.position;
            kvp.Value.transform.position = new Vector3(pos.x, 0.6f + Mathf.Sin(t * 2) * 0.15f, pos.z);
            kvp.Value.transform.Rotate(0, Time.deltaTime * 60, 0);
        }

        // Camera follow with mouse look-ahead
        if (tanks.TryGetValue(mySessionId, out var myTank))
        {
            var tankPos = myTank.Position;
            float nx = (Input.mousePosition.x / Screen.width) * 2 - 1;
            float ny = (Input.mousePosition.y / Screen.height) * 2 - 1;
            float lookAhead = 3;
            float offsetX = (nx + ny) * 0.707f * lookAhead;
            float offsetZ = (-nx + ny) * 0.707f * lookAhead;

            var targetCamPos = new Vector3(tankPos.x + 20 + offsetX, 20, tankPos.z + 20 + offsetZ);
            float camSmooth = 1f - Mathf.Pow(1f - 0.08f, Time.deltaTime * 60f);
            cam.transform.position = Vector3.Lerp(cam.transform.position, targetCamPos, camSmooth);
            cam.transform.LookAt(cam.transform.position - new Vector3(20, 20, 20));
        }

        // Announcement timer
        if (announcementTimer > 0)
        {
            announcementTimer -= Time.deltaTime;
            if (announcementTimer <= 0)
                announcementString = "";
        }
    }

    void SendInput()
    {
        float rawX = 0, rawY = 0;
        if (Input.GetKey(KeyCode.W) || Input.GetKey(KeyCode.UpArrow)) rawY -= 1;
        if (Input.GetKey(KeyCode.S) || Input.GetKey(KeyCode.DownArrow)) rawY += 1;
        if (Input.GetKey(KeyCode.A) || Input.GetKey(KeyCode.LeftArrow)) rawX += 1;
        if (Input.GetKey(KeyCode.D) || Input.GetKey(KeyCode.RightArrow)) rawX -= 1;

        // Isometric rotation — match camera at (44,20,44) looking at (24,0,24)
        float angle = -Mathf.PI / 4;
        float cos = Mathf.Cos(angle), sin = Mathf.Sin(angle);
        float dirX = Mathf.Round(rawX * cos - rawY * sin);
        float dirY = Mathf.Round(rawX * sin + rawY * cos);

        if (dirX != lastDirX || dirY != lastDirY)
        {
            _ = room.Send("move", new Dictionary<string, object> { { "x", dirX }, { "y", dirY } });
            lastDirX = dirX;
            lastDirY = dirY;
        }

        // Shoot
        if (Input.GetMouseButtonDown(0)) _ = room.Send("shoot", true);
        if (Input.GetMouseButtonUp(0)) _ = room.Send("shoot", false);

        // Aim via raycast to ground plane
        if (tanks.TryGetValue(mySessionId, out var myTank))
        {
            var ray = cam.ScreenPointToRay(Input.mousePosition);
            var plane = new Plane(Vector3.up, Vector3.zero);
            if (plane.Raycast(ray, out float dist))
            {
                var hit = ray.GetPoint(dist);
                float dx = hit.x - myTank.Position.x;
                float dz = hit.z - myTank.Position.z;
                float aimAngle = Mathf.Atan2(dx, dz) * Mathf.Rad2Deg;
                aimAngle = ((aimAngle % 360) + 360) % 360;

                myTank.targetAngle = aimAngle;

                float now = Time.unscaledTime;
                if (Mathf.Abs(aimAngle - lastAngle) > 1 && now - lastTargetSendTime >= 0.1f)
                {
                    _ = room.Send("target", aimAngle);
                    lastAngle = aimAngle;
                    lastTargetSendTime = now;
                }
            }
        }
    }

    void UpdateLeaderboard()
    {
        if (room?.State?.teams == null) return;
        var sorted = new List<(int id, int score)>();
        for (int i = 0; i < room.State.teams.Count; i++)
        {
            var team = room.State.teams[i];
            if (team != null) sorted.Add((i, team.score));
        }
        sorted.Sort((a, b) => b.score.CompareTo(a.score));

        leaderboardString = "";
        foreach (var entry in sorted)
            leaderboardString += $"{teamNames[entry.id % 4]}: {entry.score}\n";
    }

    void ShowAnnouncement(string text, float duration)
    {
        announcementString = text;
        announcementTimer = duration;
    }

    void SpawnExplosion(Vector3 pos)
    {
        var go = GameObject.CreatePrimitive(PrimitiveType.Sphere);
        go.transform.position = pos + Vector3.up * 0.5f;
        go.transform.localScale = Vector3.one * 0.5f;
        var mat = go.GetComponent<Renderer>().material;
        mat.color = new Color(1, 0.6f, 0.1f);
        Destroy(go.GetComponent<Collider>());
        StartCoroutine(AnimateExplosion(go));
    }

    System.Collections.IEnumerator AnimateExplosion(GameObject go)
    {
        float elapsed = 0;
        while (elapsed < 0.4f)
        {
            elapsed += Time.deltaTime;
            float t = elapsed / 0.4f;
            float scale = 0.5f + t * 3f;
            go.transform.localScale = Vector3.one * scale;
            var c = go.GetComponent<Renderer>().material.color;
            go.GetComponent<Renderer>().material.color = new Color(c.r, c.g - t * 0.4f, c.b * (1 - t), 1 - t);
            yield return null;
        }
        Destroy(go);
    }

    GameObject CreatePickable(PickableState pick)
    {
        Color color = pick.type switch
        {
            "repair" => new Color(0.27f, 1, 0.27f),
            "damage" => new Color(1, 0.27f, 0.27f),
            "shield" => new Color(0.27f, 0.53f, 1),
            _ => Color.white
        };

        var go = new GameObject("Pickable");

        if (pick.type == "repair")
        {
            var h = GameObject.CreatePrimitive(PrimitiveType.Cube);
            h.transform.SetParent(go.transform);
            h.transform.localScale = new Vector3(0.7f, 0.2f, 0.15f);
            h.GetComponent<Renderer>().material.color = color;
            Destroy(h.GetComponent<Collider>());

            var v = GameObject.CreatePrimitive(PrimitiveType.Cube);
            v.transform.SetParent(go.transform);
            v.transform.localScale = new Vector3(0.2f, 0.7f, 0.15f);
            v.GetComponent<Renderer>().material.color = color;
            Destroy(v.GetComponent<Collider>());
        }
        else if (pick.type == "shield")
        {
            // Shield shape: flattened sphere (like a convex shield face)
            var shape = GameObject.CreatePrimitive(PrimitiveType.Sphere);
            shape.transform.SetParent(go.transform);
            shape.transform.localScale = new Vector3(0.5f, 0.6f, 0.15f);
            shape.GetComponent<Renderer>().material.color = color;
            Destroy(shape.GetComponent<Collider>());

            // Small notch at top to give shield silhouette
            var top = GameObject.CreatePrimitive(PrimitiveType.Cube);
            top.transform.SetParent(go.transform);
            top.transform.localPosition = new Vector3(0, 0.25f, 0);
            top.transform.localScale = new Vector3(0.5f, 0.1f, 0.15f);
            top.GetComponent<Renderer>().material.color = color;
            Destroy(top.GetComponent<Collider>());
        }
        else
        {
            // Damage: rotated cube (diamond)
            var shape = GameObject.CreatePrimitive(PrimitiveType.Cube);
            shape.transform.SetParent(go.transform);
            shape.transform.localScale = Vector3.one * 0.35f;
            shape.GetComponent<Renderer>().material.color = color;
            shape.transform.rotation = Quaternion.Euler(45, 0, 45);
            Destroy(shape.GetComponent<Collider>());
        }

        return go;
    }

    public static void SetMaterialTransparent(Material mat)
    {
        mat.SetFloat("_Mode", 3);
        mat.SetInt("_SrcBlend", (int)UnityEngine.Rendering.BlendMode.SrcAlpha);
        mat.SetInt("_DstBlend", (int)UnityEngine.Rendering.BlendMode.OneMinusSrcAlpha);
        mat.SetInt("_ZWrite", 0);
        mat.DisableKeyword("_ALPHATEST_ON");
        mat.EnableKeyword("_ALPHABLEND_ON");
        mat.DisableKeyword("_ALPHAPREMULTIPLY_ON");
        mat.renderQueue = 3000;
    }

    void InitGUIStyles()
    {
        if (guiInitialized) return;
        guiInitialized = true;

        hpBgStyle = new GUIStyle();
        var bgTex = new Texture2D(1, 1);
        bgTex.SetPixel(0, 0, new Color(0, 0, 0, 0.5f));
        bgTex.Apply();
        hpBgStyle.normal.background = bgTex;

        hpBarStyle = new GUIStyle();
        var hpTex = new Texture2D(1, 1);
        hpTex.SetPixel(0, 0, new Color(0.3f, 1f, 0.3f));
        hpTex.Apply();
        hpBarStyle.normal.background = hpTex;

        shieldBarStyle = new GUIStyle();
        var shieldTex = new Texture2D(1, 1);
        shieldTex.SetPixel(0, 0, new Color(0.27f, 0.53f, 1f));
        shieldTex.Apply();
        shieldBarStyle.normal.background = shieldTex;

        leaderboardStyle = new GUIStyle(GUI.skin.box);
        leaderboardStyle.alignment = TextAnchor.UpperLeft;
        leaderboardStyle.fontSize = 14;
        leaderboardStyle.normal.textColor = new Color(0.9f, 0.9f, 0.6f);
        leaderboardStyle.padding = new RectOffset(8, 8, 6, 6);

        announcementStyle = new GUIStyle(GUI.skin.label);
        announcementStyle.alignment = TextAnchor.MiddleCenter;
        announcementStyle.fontSize = 36;
        announcementStyle.fontStyle = FontStyle.Bold;
        announcementStyle.normal.textColor = new Color(1f, 0.85f, 0.3f);

        // Shadow outline for readability
        var shadowTex = new Texture2D(1, 1);
        shadowTex.SetPixel(0, 0, new Color(0, 0, 0, 0.7f));
        shadowTex.Apply();
        announcementStyle.normal.background = shadowTex;
    }

    void OnGUI()
    {
        InitGUIStyles();

        // ── Per-tank health bars (world → screen) ──
        foreach (var kvp in tanks)
        {
            var tank = kvp.Value;
            if (tank.dead && Mathf.FloorToInt(Time.time * 4) % 2 == 0) continue;

            Vector3 worldPos = tank.Position + Vector3.up * 1.2f;
            Vector3 screenPos = cam.WorldToScreenPoint(worldPos);

            // Behind camera check
            if (screenPos.z < 0) continue;

            // Unity screen Y is bottom-up, GUI Y is top-down
            float guiY = Screen.height - screenPos.y;

            float barW = 40, barH = 4;
            float x = screenPos.x - barW / 2;

            // HP background
            GUI.Box(new Rect(x, guiY, barW, barH), GUIContent.none, hpBgStyle);

            // HP fill
            float hpPct = Mathf.Max(0, tank.hp / 10f);
            var hpColor = hpPct > 0.5f ? new Color(0.3f, 1f, 0.3f) :
                          hpPct > 0.25f ? new Color(1f, 0.67f, 0.27f) :
                          new Color(1f, 0.3f, 0.3f);
            var hpTex = hpBarStyle.normal.background;
            hpTex.SetPixel(0, 0, hpColor);
            hpTex.Apply();
            GUI.Box(new Rect(x, guiY, barW * hpPct, barH), GUIContent.none, hpBarStyle);

            // Shield bar (above HP)
            if (tank.shieldBubble.activeSelf)
            {
                GUI.Box(new Rect(x, guiY - 5, barW, 3), GUIContent.none, hpBgStyle);
                float shieldPct = Mathf.Max(0, tank.shieldValue / 10f);
                GUI.Box(new Rect(x, guiY - 5, barW * shieldPct, 3), GUIContent.none, shieldBarStyle);
            }
        }

        // ── Leaderboard (top-right) ──
        if (!string.IsNullOrEmpty(leaderboardString))
        {
            GUI.Box(new Rect(Screen.width - 160, 10, 150, 100), leaderboardString, leaderboardStyle);
        }

        // ── Announcement (center) ──
        if (!string.IsNullOrEmpty(announcementString))
        {
            GUI.Label(new Rect(0, Screen.height / 2 - 50, Screen.width, 100), announcementString, announcementStyle);
        }
    }

    async void OnDestroy()
    {
        if (room != null)
            await room.Leave();

        // Cleanup all spawned objects
        foreach (var kvp in tanks) kvp.Value.Destroy();
        tanks.Clear();

        foreach (var kvp in bullets) Destroy(kvp.Value);
        bullets.Clear();
        bulletTargets.Clear();

        foreach (var kvp in pickables) Destroy(kvp.Value);
        pickables.Clear();

        foreach (var b in blocks) Destroy(b);
        blocks.Clear();
    }
}
