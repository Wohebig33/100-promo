using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using BepInEx;
using BepInEx.Configuration;
using UnityEngine;
using UnityEngine.SceneManagement;

namespace HouseEdgeInGame
{
    /// <summary>
    /// House Edge In-Game: a mod menu drawn inside the game. Hold Q+E to open it.
    ///   Fun:         game speed, gravity, field of view, Party Mode
    ///   Find values: search the game's own code by name ("chips", "health") and change or lock what it finds
    ///   Pinned:      values you kept. They come back after a scene change or a restart.
    /// </summary>
    [BepInPlugin(Guid, "House Edge In-Game", Version)]
    public class Plugin : BaseUnityPlugin
    {
        public const string Guid = "houseedge.ingame";
        public const string Version = "0.2.0";
        private const int WindowId = 0x4E1D;

        // settings (BepInEx/config/houseedge.ingame.cfg)
        private ConfigEntry<string> _cfgKeys;
        private ConfigEntry<float> _cfgScale;
        private ConfigEntry<bool> _cfgPause;
        private ConfigEntry<int> _cfgPartyEvery;

        private Chord _chord;
        private bool _open;
        private Rect _win = new Rect(40, 40, 600, 640);
        private int _tab;
        private Vector2 _scroll;

        // fun
        private float _speed = 1f, _gravity = 1f, _fov = 75f;
        private bool _speedTouched, _fovOn, _showFps;
        private float _origFixed = -1f, _origFov = -1f, _pausedPrev = -1f;
        private Vector3 _origGrav3; private Vector2 _origGrav2; private bool _gravSaved, _gravTouched;
        private float _fpsSmooth;

        // Party Mode
        private bool _party;
        private float _nextParty;
        private string _effect = "";
        private float _effectUntil;
        private float? _effSpeed, _effGravity, _effFov;

        // value finder
        private string _query = "";
        private List<Hit> _hits = new List<Hit>();
        private int _total = -1;
        private bool _narrowed;
        private readonly Dictionary<object, string> _edits = new Dictionary<object, string>();
        private List<Pin> _pins = new List<Pin>();
        private string _pinsPath;
        private float _refreshAt;

        // cursor while the menu is open
        private bool _cursorSaved, _savedVisible;
        private CursorLockMode _savedLock;

        private sealed class Toast { public string Text; public float Until; public bool Big; }
        private readonly List<Toast> _toasts = new List<Toast>();
        private bool _greeted;
        private readonly HashSet<string> _logged = new HashSet<string>();

        // ======================================================================== lifecycle
        private void Awake()
        {
            _cfgKeys = Config.Bind("General", "MenuKeys", "Q+E", "Hold these keys together to open or close the menu. Examples: Q+E, F1, Ctrl+M");
            _cfgScale = Config.Bind("General", "MenuScale", 1f, "Menu size. 1 is normal, 1.5 is bigger.");
            _cfgPause = Config.Bind("General", "PauseWhileOpen", false, "Freeze the game while the menu is open.");
            _cfgPartyEvery = Config.Bind("Party", "SecondsBetweenSurprises", 20, "How often Party Mode does something random.");
            _chord = Keys.Parse(_cfgKeys.Value) ?? Keys.Parse("Q+E");
            _pinsPath = Path.Combine(Paths.ConfigPath, "houseedge.ingame.pins.txt");
            _pins = Finder.Load(_pinsPath);
            SceneManager.sceneLoaded += (s, m) => { foreach (var p in _pins) { p.Targets.Clear(); p.NextResolve = 0; } _hits.Clear(); _total = -1; _narrowed = false; };
            Logger.LogInfo($"House Edge In-Game {Version} loaded. Hold {_chord.Text} to open the menu. {_pins.Count} pinned values.");
            Logger.LogInfo($"Game: {GameInfo.Summary}");
        }

        private void Update()
        {
            try
            {
                float now = Time.realtimeSinceStartup;
                if (!_greeted && now > 4f) { _greeted = true; ShowToast($"House Edge is ready. Hold {_chord.Text} for the menu.", 6f); }
                bool typing = GUIUtility.keyboardControl != 0;
                if (_chord.Pressed() && !typing) Toggle();

                if (Online.Tick(now)) OnlineChanged(now);
                ResolvePins(now);
                ApplyLocks();
                ApplySpeed();
                PartyTick(now);
                if (_open) FreeCursor();
                if (now >= _refreshAt) { _refreshAt = now + 0.25f; RefreshShown(); }
                _fpsSmooth = Mathf.Lerp(_fpsSmooth, 1f / Mathf.Max(0.0001f, Time.unscaledDeltaTime), 0.1f);
            }
            catch (Exception e) { LogOnce(e); }
        }

        private void LateUpdate()
        {
            try { ApplyLocks(); ApplyFov(); } catch (Exception e) { LogOnce(e); }
        }

        private void LogOnce(Exception e)
        {
            var key = e.GetType().Name + e.Message;
            if (_logged.Add(key)) Logger.LogError($"House Edge In-Game hit a problem (it keeps running): {e}");
        }

        private void Toggle()
        {
            _open = !_open;
            if (_open)
            {
                if (_tab == 1 && _total < 0 && _query.Length > 0) DoSearch();
            }
            else
            {
                GUIUtility.keyboardControl = 0;
                RestoreCursor();
                if (_pausedPrev >= 0f) { Time.timeScale = _pausedPrev; _pausedPrev = -1f; }
            }
        }

        private void FreeCursor()
        {
            if (!_cursorSaved) { _savedVisible = Cursor.visible; _savedLock = Cursor.lockState; _cursorSaved = true; }
            Cursor.visible = true;
            Cursor.lockState = CursorLockMode.None;
        }

        private void RestoreCursor()
        {
            if (!_cursorSaved) return;
            Cursor.visible = _savedVisible;
            Cursor.lockState = _savedLock;
            _cursorSaved = false;
        }

        private const string OnlineNote = "Mods are paused in online games. They come back when you leave.";

        /// <summary>Online: put speed and gravity back to normal and stop Party Mode. Offline again: bring back what the player chose.</summary>
        private void OnlineChanged(float now)
        {
            if (!Mathf.Approximately(_speed, 1f)) _speedTouched = true; // only touch the game's speed if House Edge changed it
            if (_gravSaved) ApplyGravity();
            if (Online.Active)
            {
                EndEffect();
                if (_pausedPrev >= 0f) { Time.timeScale = _pausedPrev; _pausedPrev = -1f; }
                ShowToast("Online game. " + OnlineNote, 7f);
                Logger.LogInfo($"Online session found ({Online.Why}). Mods are paused until it ends.");
            }
            else
            {
                _nextParty = now + 5f;
                ShowToast("Offline again. House Edge mods are back on.", 5f);
                Logger.LogInfo("Online session ended. Mods are back on.");
            }
        }

        private bool BlockedOnline()
        {
            if (!Online.Active) return false;
            ShowToast(OnlineNote);
            return true;
        }

        private void ShowToast(string text, float seconds = 3.5f, bool big = false)
        {
            _toasts.Add(new Toast { Text = text, Until = Time.realtimeSinceStartup + seconds, Big = big });
            if (_toasts.Count > 4) _toasts.RemoveAt(0);
        }

        // ======================================================================== fun: speed, gravity, FOV
        private float EffectiveSpeed => Online.Active ? 1f : _effSpeed ?? _speed;
        private float EffectiveGravity => Online.Active ? 1f : _effGravity ?? _gravity;

        private void ApplySpeed()
        {
            if (_open && _cfgPause.Value && !Online.Active)
            {
                if (Time.timeScale != 0f) { if (_pausedPrev < 0f) _pausedPrev = Time.timeScale; Time.timeScale = 0f; }
                return;
            }
            float target = EffectiveSpeed;
            if (!_speedTouched && Mathf.Approximately(target, 1f)) return;
            if (_origFixed < 0f) _origFixed = Time.fixedDeltaTime;
            if (Time.timeScale > 0.0001f && Mathf.Abs(Time.timeScale - target) > 0.001f) Time.timeScale = target; // leave the game's own pause (0) alone
            Time.fixedDeltaTime = _origFixed * Mathf.Min(1f, target); // keeps slow-mo physics smooth
            _speedTouched = !Mathf.Approximately(target, 1f);
        }

        private void SetSpeed(float s) { _speed = Mathf.Clamp(s, 0.05f, 10f); _speedTouched = true; }

        private void ApplyGravity()
        {
            float g = EffectiveGravity;
            if (!_gravSaved)
            {
                if (Mathf.Approximately(g, 1f)) return;
                try { _origGrav3 = Physics.gravity; } catch (Exception) { }
                Save2DGravity();
                _gravSaved = true;
            }
            try { Physics.gravity = _origGrav3 * g; } catch (Exception) { }
            Set2DGravity(g);
            _gravTouched = !Mathf.Approximately(g, 1f);
        }

        // 2D physics lives in its own engine module, and a 3D-only game might not ship it, so these stay in their own methods.
        private void Save2DGravity() { try { _origGrav2 = Physics2D.gravity; } catch (Exception) { } }
        private void Set2DGravity(float g) { try { Physics2D.gravity = _origGrav2 * g; } catch (Exception) { } }

        private void SetGravity(float g) { _gravity = g; ApplyGravity(); }

        private static Camera Cam()
        {
            var c = Camera.main;
            return c != null && !c.orthographic ? c : null;
        }

        private void ApplyFov()
        {
            var cam = Cam();
            if (cam == null) return;
            float? want = _effFov ?? (_fovOn ? _fov : (float?)null);
            if (want.HasValue)
            {
                if (_origFov < 0f) _origFov = cam.fieldOfView;
                cam.fieldOfView = want.Value;
            }
            else if (_origFov > 0f)
            {
                cam.fieldOfView = _origFov;
                _origFov = -1f;
            }
        }

        private void ResetFun()
        {
            _speed = 1f; _speedTouched = true;
            _gravity = 1f; ApplyGravity();
            _fovOn = false;
            EndEffect();
            ShowToast("Back to normal.");
        }

        // ======================================================================== Party Mode
        private void PartyTick(float now)
        {
            if (_effect.Length > 0 && now >= _effectUntil) EndEffect();
            if (!_party || Online.Active || now < _nextParty) return;
            _nextParty = now + Mathf.Max(5, _cfgPartyEvery.Value);
            if (_effect.Length > 0) return;

            var options = new List<Action>
            {
                () => StartEffect("TURBO! Double speed", 6f, speed: 2f),
                () => StartEffect("Slow-mo...", 6f, speed: 0.35f),
                () => StartEffect("Moon gravity", 8f, gravity: 0.25f),
                () => StartEffect("Heavy gravity", 6f, gravity: 2.5f),
            };
            if (Cam() != null)
            {
                options.Add(() => StartEffect("Fish-eye!", 8f, fov: 115f));
                options.Add(() => StartEffect("Zoom!", 6f, fov: 35f));
            }
            var numeric = _pins.Where(p => p.Ready && !p.Member.IsBool && !p.Locked).ToList();
            if (numeric.Count > 0)
            {
                options.Add(() =>
                {
                    var p = numeric[UnityEngine.Random.Range(0, numeric.Count)];
                    if (PinOp(p, "x2")) ShowToast($"JACKPOT! {p.Label} doubled", 4f, big: true);
                });
            }
            options[UnityEngine.Random.Range(0, options.Count)]();
        }

        private void StartEffect(string name, float seconds, float? speed = null, float? gravity = null, float? fov = null)
        {
            _effect = name;
            _effectUntil = Time.realtimeSinceStartup + seconds;
            _effSpeed = speed; _effGravity = gravity; _effFov = fov;
            if (speed.HasValue) _speedTouched = true;
            if (gravity.HasValue) ApplyGravity();
            ShowToast(name, Mathf.Min(seconds, 4f), big: true);
        }

        private void EndEffect()
        {
            if (_effect.Length == 0) return;
            bool hadGravity = _effGravity.HasValue;
            _effect = "";
            _effSpeed = null; _effGravity = null; _effFov = null;
            _speedTouched = true;
            if (hadGravity) ApplyGravity();
        }

        // ======================================================================== values and pins
        private void DoSearch()
        {
            _edits.Clear();
            _scroll = Vector2.zero;
            _narrowed = false;
            try { _hits = Finder.Search(_query, 300, out _total); }
            catch (Exception e) { LogOnce(e); _hits = new List<Hit>(); _total = 0; }
            foreach (var h in _hits) h.Base = Finder.ToNum(Finder.Read(h.Member, h.Instance));
            RefreshShown();
        }

        /// <summary>
        /// Keeps the results that moved the way the on-screen number did. Games often keep a display copy next to the real value,
        /// and changing the copy does nothing. Only the real value keeps up when the game changes it.
        /// </summary>
        private void Narrow(string how)
        {
            var kept = new List<Hit>();
            foreach (var h in _hits)
            {
                if (!h.Alive || h.Base == null) continue;
                var cur = Finder.ToNum(Finder.Read(h.Member, h.Instance));
                if (cur == null) continue;
                double was = h.Base.Value, now = cur.Value;
                bool keep = how == "changed" ? now != was : how == "up" ? now > was : how == "down" ? now < was : now == was;
                if (!keep) continue;
                h.Base = now;
                kept.Add(h);
            }
            int before = _hits.Count;
            _hits = kept; _total = kept.Count; _narrowed = true; _scroll = Vector2.zero; _edits.Clear();
            ShowToast(kept.Count == 0 ? "Nothing matched. Search again, change the number in the game, and try again."
                : kept.Count <= 3 ? $"{kept.Count} left. One of these is the real value: change it and pin it." : $"{kept.Count} of {before} left. Change the number in the game again and narrow some more.");
            RefreshShown();
        }

        private void RefreshShown()
        {
            if (_open && _tab == 1)
                foreach (var h in _hits)
                {
                    var v = h.Alive ? Finder.Read(h.Member, h.Instance) : null;
                    h.Shown = h.Alive ? Finder.Show(v) : "gone";
                    var n = Finder.ToNum(v);
                    h.Was = n != null && h.Base != null && n.Value != h.Base.Value ? "   was " + Finder.Show(h.Member.IsBool ? (object)(h.Base.Value != 0) : h.Base.Value) : "";
                }
            foreach (var p in _pins)
                p.Shown = p.Ready ? Finder.Show(Finder.Read(p.Member, Finder.Instances(p).FirstOrDefault())) : "not here";
        }

        private void ResolvePins(float now)
        {
            foreach (var p in _pins)
            {
                if (now < p.NextResolve || (p.Ready && !p.All)) continue;
                try
                {
                    if (Finder.Resolve(p))
                    {
                        SavePins();
                        Logger.LogInfo($"{p.Label} has a new name in this version of the game: {p.TypeName}.{p.MemberName}. The pin follows it.");
                    }
                }
                catch (Exception e) { LogOnce(e); }
                p.NextResolve = now + (p.Ready ? 3f : 1.5f);
            }
        }

        private void ApplyLocks()
        {
            if (Online.Active) return;
            foreach (var p in _pins)
            {
                if (!p.Locked || p.LockValue == null || !p.Ready) continue;
                foreach (var target in Finder.Instances(p)) Finder.Write(p.Member, target, p.LockValue);
            }
        }

        private void SavePins() => Finder.Save(_pinsPath, _pins);

        private void AddPin(Hit h)
        {
            var key = h.Member.Owner.FullName + "." + h.Member.Name;
            if (_pins.Any(p => p.TypeName + "." + Finder.Pretty(p.MemberName) == key && (p.Kind == 1 || p.ObjectName == (h.Target != null ? h.Target.name : ""))))
            {
                ShowToast($"{h.Label} is already pinned.");
                return;
            }
            _pins.Add(Finder.PinFrom(h));
            SavePins();
            ShowToast($"Pinned {h.Label}. Lock it on the Pinned tab.");
        }

        private bool SetHit(Hit h, object value)
        {
            if (BlockedOnline()) return false;
            bool ok = h.Alive && Finder.Write(h.Member, h.Instance, value);
            if (!ok) ShowToast("Couldn't change that one. The game may have removed it.");
            return ok;
        }

        private bool PinSet(Pin p, object value)
        {
            if (!p.Ready || BlockedOnline()) return false;
            bool any = false;
            foreach (var t in Finder.Instances(p)) any |= Finder.Write(p.Member, t, value);
            if (p.Locked) { p.LockValue = value; p.LockText = Convert.ToString(value, CultureInfo.InvariantCulture); SavePins(); }
            return any;
        }

        private bool PinOp(Pin p, string op)
        {
            if (!p.Ready) return false;
            var cur = Finder.Read(p.Member, Finder.Instances(p).FirstOrDefault());
            return Finder.TryApplyOp(cur, op, p.Member.ValueType, out var v) && PinSet(p, v);
        }

        private void SetLock(Pin p, bool on)
        {
            if (on)
            {
                if (BlockedOnline()) return;
                if (!p.Ready) { ShowToast("That value isn't in this part of the game right now."); return; }
                var cur = Finder.Read(p.Member, Finder.Instances(p).FirstOrDefault());
                if (cur == null) return;
                p.LockValue = cur;
                p.LockText = Convert.ToString(cur, CultureInfo.InvariantCulture);
            }
            p.Locked = on;
            SavePins();
            ShowToast($"{p.Label} {(on ? "locked at " + Finder.Show(p.LockValue) : "unlocked")}");
        }

        // ======================================================================== drawing
        private GUIStyle _sWindow, _sTitle, _sMuted, _sLabel, _sBold, _sValue, _sBtn, _sBtnOn, _sTab, _sTabOn, _sField, _sRow, _sToast, _sToastBig, _sSection, _sHint;
        private Texture2D _tWin, _tRow, _tBtn, _tBtnHover, _tGold, _tGoldHover, _tField, _tToast;

        private static Texture2D Tex(Color c)
        {
            var t = new Texture2D(1, 1) { hideFlags = HideFlags.HideAndDontSave };
            t.SetPixel(0, 0, c);
            t.Apply();
            return t;
        }

        private static Color Hex(string hex, float a = 1f)
        {
            ColorUtility.TryParseHtmlString(hex, out var c);
            c.a = a;
            return c;
        }

        private void EnsureStyles()
        {
            if (_sWindow != null && _tWin != null) return;
            var gold = Hex("#f5c542"); var gold2 = Hex("#ffdf7e"); var cream = Hex("#f7efe1"); var muted = Hex("#9fb8ad"); var ink = Hex("#2b1d00");
            _tWin = Tex(Hex("#06201a", 0.96f)); _tRow = Tex(Hex("#0d3b2e", 0.85f)); _tBtn = Tex(Hex("#123f31"));
            _tBtnHover = Tex(Hex("#1d5a46")); _tGold = Tex(gold); _tGoldHover = Tex(gold2); _tField = Tex(Hex("#021410")); _tToast = Tex(Hex("#0c2a21", 0.95f));

            _sWindow = new GUIStyle(GUI.skin.window) { padding = new RectOffset(14, 14, 12, 12), border = new RectOffset(2, 2, 2, 2) };
            _sWindow.normal.background = _sWindow.onNormal.background = _tWin;
            _sWindow.normal.textColor = _sWindow.onNormal.textColor = cream;

            _sTitle = new GUIStyle(GUI.skin.label) { fontSize = 22, fontStyle = FontStyle.Bold };
            _sTitle.normal.textColor = gold;
            _sMuted = new GUIStyle(GUI.skin.label) { fontSize = 12, wordWrap = true };
            _sMuted.normal.textColor = muted;
            _sHint = new GUIStyle(_sMuted) { fontSize = 13 };
            _sLabel = new GUIStyle(GUI.skin.label) { fontSize = 14, wordWrap = true };
            _sLabel.normal.textColor = cream;
            _sBold = new GUIStyle(_sLabel) { fontStyle = FontStyle.Bold, wordWrap = false, clipping = TextClipping.Clip };
            _sSection = new GUIStyle(_sLabel) { fontSize = 15, fontStyle = FontStyle.Bold };
            _sSection.normal.textColor = gold2;
            _sValue = new GUIStyle(_sLabel) { fontSize = 20, fontStyle = FontStyle.Bold, alignment = TextAnchor.MiddleRight, wordWrap = false };
            _sValue.normal.textColor = gold2;

            _sBtn = new GUIStyle(GUI.skin.button) { fontSize = 13, fontStyle = FontStyle.Bold, padding = new RectOffset(10, 10, 6, 6), margin = new RectOffset(2, 2, 2, 2) };
            _sBtn.normal.background = _tBtn; _sBtn.hover.background = _tBtnHover; _sBtn.active.background = _tGold;
            _sBtn.normal.textColor = cream; _sBtn.hover.textColor = gold2; _sBtn.active.textColor = ink;
            _sBtnOn = new GUIStyle(_sBtn);
            _sBtnOn.normal.background = _tGold; _sBtnOn.hover.background = _tGoldHover;
            _sBtnOn.normal.textColor = _sBtnOn.hover.textColor = ink;
            _sTab = new GUIStyle(_sBtn) { fontSize = 14, padding = new RectOffset(14, 14, 8, 8) };
            _sTabOn = new GUIStyle(_sBtnOn) { fontSize = 14, padding = new RectOffset(14, 14, 8, 8) };

            _sField = new GUIStyle(GUI.skin.textField) { fontSize = 14, padding = new RectOffset(8, 8, 6, 6) };
            _sField.normal.background = _sField.focused.background = _sField.hover.background = _tField;
            _sField.normal.textColor = _sField.focused.textColor = _sField.hover.textColor = cream;

            _sRow = new GUIStyle(GUI.skin.box) { padding = new RectOffset(10, 10, 8, 8), margin = new RectOffset(0, 0, 3, 3) };
            _sRow.normal.background = _tRow;

            _sToast = new GUIStyle(GUI.skin.box) { fontSize = 15, alignment = TextAnchor.MiddleCenter, padding = new RectOffset(16, 16, 10, 10), wordWrap = true };
            _sToast.normal.background = _tToast; _sToast.normal.textColor = cream;
            _sToastBig = new GUIStyle(_sToast) { fontSize = 26, fontStyle = FontStyle.Bold };
            _sToastBig.normal.textColor = gold2;
        }

        private float UiScale() => Mathf.Clamp(Screen.height / 1080f, 0.8f, 2.5f) * Mathf.Clamp(_cfgScale.Value, 0.5f, 3f);

        private void OnGUI()
        {
            try
            {
                EnsureStyles();
                float s = UiScale();
                var saved = GUI.matrix;
                GUI.matrix = Matrix4x4.TRS(Vector3.zero, Quaternion.identity, new Vector3(s, s, 1f));
                float w = Screen.width / s, h = Screen.height / s;

                if (_showFps) GUI.Label(new Rect(w - 110, 8, 100, 24), $"{_fpsSmooth:0} FPS", _sValue);
                if (_open)
                {
                    _win.width = Mathf.Min(600, w - 20); _win.height = Mathf.Min(660, h - 20);
                    _win = GUI.Window(WindowId, _win, DrawWindow, GUIContent.none, _sWindow);
                    _win.x = Mathf.Clamp(_win.x, 0, Mathf.Max(0, w - _win.width));
                    _win.y = Mathf.Clamp(_win.y, 0, Mathf.Max(0, h - _win.height));
                }
                DrawToasts(w);
                GUI.matrix = saved;
            }
            catch (Exception e) { LogOnce(e); }
        }

        private void DrawToasts(float w)
        {
            float now = Time.realtimeSinceStartup, y = 18;
            _toasts.RemoveAll(t => now > t.Until);
            foreach (var t in _toasts)
            {
                var st = t.Big ? _sToastBig : _sToast;
                float tw = Mathf.Min(560, w - 40);
                float th = st.CalcHeight(new GUIContent(t.Text), tw);
                var c = GUI.color; GUI.color = new Color(1, 1, 1, Mathf.Clamp01((t.Until - now) * 2f));
                GUI.Box(new Rect((w - tw) / 2, y, tw, th), t.Text, st);
                GUI.color = c;
                y += th + 8;
            }
        }

        private static GUILayoutOption W(float px) => GUILayout.Width(px);

        private bool Button(string text, bool on = false, float width = -1)
        {
            return width > 0 ? GUILayout.Button(text, on ? _sBtnOn : _sBtn, W(width)) : GUILayout.Button(text, on ? _sBtnOn : _sBtn);
        }

        private void DrawWindow(int id)
        {
            GUILayout.BeginHorizontal();
            GUILayout.Label("HOUSE EDGE", _sTitle);
            GUILayout.FlexibleSpace();
            GUILayout.Label($"{_chord.Text} to hide  ", _sMuted);
            if (Button("X", false, 32)) Toggle();
            GUILayout.EndHorizontal();
            GUILayout.Space(4);

            GUILayout.BeginHorizontal();
            string[] tabs = { "Fun", "Find values", $"Pinned ({_pins.Count})", "About" };
            for (int i = 0; i < tabs.Length; i++)
                if (GUILayout.Button(tabs[i], i == _tab ? _sTabOn : _sTab)) { _tab = i; _scroll = Vector2.zero; GUIUtility.keyboardControl = 0; RefreshShown(); }
            GUILayout.EndHorizontal();
            GUILayout.Space(8);

            if (Online.Active)
            {
                GUILayout.BeginVertical(_sRow);
                GUILayout.Label("ONLINE GAME: MODS PAUSED", _sSection);
                GUILayout.Label($"{Online.Why} House Edge is for single-player and local play, so values, locks, speed, gravity and Party Mode are off for now. Field of view and the FPS counter still work. Everything comes back when you leave.", _sMuted);
                GUILayout.EndVertical();
                GUILayout.Space(6);
            }

            switch (_tab)
            {
                case 0: DrawFun(); break;
                case 1: DrawFind(); break;
                case 2: DrawPinned(); break;
                default: DrawAbout(); break;
            }
            GUI.DragWindow(new Rect(0, 0, 10000, 34));
        }

        private void DrawFun()
        {
            _scroll = GUILayout.BeginScrollView(_scroll);

            string paused = Online.Active ? " (paused: online game)" : "";
            GUILayout.Label($"Game speed: {EffectiveSpeed:0.##}x{paused}", _sSection);
            GUILayout.BeginHorizontal();
            if (Button("Slow-mo", Mathf.Approximately(_speed, 0.25f))) SetSpeed(0.25f);
            if (Button("0.5x", Mathf.Approximately(_speed, 0.5f))) SetSpeed(0.5f);
            if (Button("Normal", Mathf.Approximately(_speed, 1f))) SetSpeed(1f);
            if (Button("2x", Mathf.Approximately(_speed, 2f))) SetSpeed(2f);
            if (Button("Turbo 4x", Mathf.Approximately(_speed, 4f))) SetSpeed(4f);
            GUILayout.EndHorizontal();
            float ns = GUILayout.HorizontalSlider(_speed, 0.1f, 5f);
            if (!Mathf.Approximately(ns, _speed)) SetSpeed(Mathf.Round(ns * 20f) / 20f);
            GUILayout.Space(12);

            GUILayout.Label($"Gravity: {EffectiveGravity:0.##}x{paused}", _sSection);
            GUILayout.BeginHorizontal();
            if (Button("Float", Mathf.Approximately(_gravity, 0f))) SetGravity(0f);
            if (Button("Moon", Mathf.Approximately(_gravity, 0.3f))) SetGravity(0.3f);
            if (Button("Normal", Mathf.Approximately(_gravity, 1f))) SetGravity(1f);
            if (Button("Heavy", Mathf.Approximately(_gravity, 2f))) SetGravity(2f);
            if (Button("Upside down", Mathf.Approximately(_gravity, -1f))) SetGravity(-1f);
            GUILayout.EndHorizontal();
            float ng = GUILayout.HorizontalSlider(_gravity, -1f, 3f);
            if (!Mathf.Approximately(ng, _gravity)) SetGravity(Mathf.Round(ng * 20f) / 20f);
            GUILayout.Label("Gravity only changes things the game moves with Unity physics.", _sMuted);
            GUILayout.Space(12);

            var cam = Cam();
            GUILayout.BeginHorizontal();
            GUILayout.Label($"Field of view: {(_fovOn ? _fov.ToString("0") : "game default")}", _sSection);
            GUILayout.FlexibleSpace();
            if (cam != null && Button(_fovOn ? "ON" : "OFF", _fovOn, 64)) _fovOn = !_fovOn;
            GUILayout.EndHorizontal();
            if (cam == null) GUILayout.Label("No 3D camera in this scene.", _sMuted);
            else if (_fovOn) _fov = Mathf.Round(GUILayout.HorizontalSlider(_fov, 20f, 140f));
            GUILayout.Space(12);

            GUILayout.BeginHorizontal();
            GUILayout.Label($"Party Mode{(_effect.Length > 0 ? ": " + _effect : "")}{(_party ? paused : "")}", _sSection);
            GUILayout.FlexibleSpace();
            if (Button(_party ? "ON" : "OFF", _party, 64))
            {
                _party = !_party;
                _nextParty = Time.realtimeSinceStartup + 3f;
                if (!_party) EndEffect();
                ShowToast(_party ? "Party Mode on. Expect the unexpected." : "Party Mode off.", 3.5f, _party);
            }
            GUILayout.EndHorizontal();
            GUILayout.BeginHorizontal();
            GUILayout.Label($"A random surprise every {_cfgPartyEvery.Value} seconds: turbo, slow-mo, moon gravity, fish-eye, or a jackpot on a pinned value.", _sMuted);
            if (Button("-", false, 30)) _cfgPartyEvery.Value = Mathf.Max(5, _cfgPartyEvery.Value - 5);
            if (Button("+", false, 30)) _cfgPartyEvery.Value = Mathf.Min(300, _cfgPartyEvery.Value + 5);
            GUILayout.EndHorizontal();
            GUILayout.Space(12);

            GUILayout.BeginHorizontal();
            if (Button(_cfgPause.Value ? "Pause while menu is open: ON" : "Pause while menu is open: OFF", _cfgPause.Value)) _cfgPause.Value = !_cfgPause.Value;
            if (Button(_showFps ? "FPS counter: ON" : "FPS counter: OFF", _showFps)) _showFps = !_showFps;
            GUILayout.EndHorizontal();
            if (Button("Reset everything to normal")) ResetFun();

            GUILayout.EndScrollView();
        }

        private static readonly string[] Quick = { "chips", "money", "cash", "coin", "bet", "health", "hp", "lives", "ammo", "stamina", "score", "speed", "jump", "time", "level", "damage" };

        private void DrawFind()
        {
            GUILayout.Label("Type what a value might be called, like chips or health. House Edge searches the game's own code for it.", _sHint);
            GUILayout.BeginHorizontal();
            GUI.SetNextControlName("he-search");
            var e = Event.current;
            bool enter = e.type == EventType.KeyDown && (e.keyCode == KeyCode.Return || e.keyCode == KeyCode.KeypadEnter) && GUI.GetNameOfFocusedControl() == "he-search";
            _query = GUILayout.TextField(_query, 40, _sField);
            if (Button("Search", true, 90) || enter) { DoSearch(); if (enter) e.Use(); }
            GUILayout.EndHorizontal();

            int perRow = 8;
            for (int i = 0; i < Quick.Length; i += perRow)
            {
                GUILayout.BeginHorizontal();
                for (int j = i; j < Math.Min(i + perRow, Quick.Length); j++)
                    if (Button(Quick[j], _query == Quick[j])) { _query = Quick[j]; GUIUtility.keyboardControl = 0; DoSearch(); }
                GUILayout.EndHorizontal();
            }

            if (_narrowed) GUILayout.Label(_total == 0 ? "None left. Press Search to start over." : $"{_total} left after narrowing down.", _sHint);
            else if (_total == 0) GUILayout.Label($"Nothing called \"{_query}\" here. Try another word, or a shorter one (hp instead of hitpoints).", _sHint);
            else if (_total > 0) GUILayout.Label(_total > _hits.Count ? $"{_total} matches. Showing the first {_hits.Count}. Try a longer word to narrow it down." : $"{_total} match{(_total == 1 ? "" : "es")}. Change one and watch the game, then pin the one that works.", _sHint);

            if (_hits.Count > 1)
            {
                GUILayout.Label("Too many? Change the number in the game (win or lose some chips), then press what it did. Display copies drop out and the real value stays.", _sMuted);
                GUILayout.BeginHorizontal();
                if (Button("Changed")) Narrow("changed");
                if (Button("Went up")) Narrow("up");
                if (Button("Went down")) Narrow("down");
                if (Button("Stayed the same")) Narrow("same");
                GUILayout.EndHorizontal();
            }

            _scroll = GUILayout.BeginScrollView(_scroll);
            foreach (var h in _hits)
            {
                GUILayout.BeginVertical(_sRow);
                GUILayout.BeginHorizontal();
                GUILayout.BeginVertical();
                GUILayout.Label(h.Label, _sBold);
                GUILayout.Label(h.Where + h.Was, _sMuted);
                GUILayout.EndVertical();
                GUILayout.FlexibleSpace();
                GUILayout.Label(h.Shown, _sValue, W(140));
                GUILayout.EndHorizontal();

                GUILayout.BeginHorizontal();
                if (h.Member.IsBool)
                {
                    if (Button("Flip it", false, 90) && Finder.TryApplyOp(Finder.Read(h.Member, h.Instance), "!", typeof(bool), out var flipped)) SetHit(h, flipped);
                }
                else
                {
                    _edits.TryGetValue(h, out var txt);
                    txt = GUILayout.TextField(txt ?? "", 20, _sField, W(120));
                    _edits[h] = txt;
                    if (Button("Set", false, 52) && Finder.TryConvert(txt, h.Member.ValueType, out var v)) { if (SetHit(h, v)) _edits[h] = ""; }
                    foreach (var op in h.Member.IsFloat ? new[] { "+10", "x2" } : new[] { "+100", "x2" })
                        if (Button(op, false, 52) && Finder.TryApplyOp(Finder.Read(h.Member, h.Instance), op, h.Member.ValueType, out var nv)) SetHit(h, nv);
                }
                GUILayout.FlexibleSpace();
                if (Button("Pin", true, 64)) AddPin(h);
                GUILayout.EndHorizontal();
                GUILayout.EndVertical();
            }
            GUILayout.EndScrollView();
        }

        private void DrawPinned()
        {
            if (_pins.Count == 0)
            {
                GUILayout.Label("Nothing pinned yet. Find a value on the Find values tab and press Pin. Pinned values come back by themselves after a level change or a restart.", _sHint);
                return;
            }
            _scroll = GUILayout.BeginScrollView(_scroll);
            Pin remove = null;
            foreach (var p in _pins)
            {
                GUILayout.BeginVertical(_sRow);
                GUILayout.BeginHorizontal();
                GUILayout.BeginVertical();
                GUILayout.Label(p.Label, _sBold);
                string where = Online.Active && p.Locked ? "Lock paused: online game"
                    : !p.Ready ? "Not in this part of the game. It'll reconnect when it shows up."
                    : p.Kind == 1 ? "global" : p.All ? $"all {p.Targets.Count(t => t != null)} of them" : "on " + p.ObjectName;
                GUILayout.Label(where, _sMuted);
                GUILayout.EndVertical();
                GUILayout.FlexibleSpace();
                GUILayout.Label(p.Locked ? "LOCKED " + p.Shown : p.Shown, _sValue, W(170));
                GUILayout.EndHorizontal();

                GUILayout.BeginHorizontal();
                if (Button(p.Locked ? "Locked" : "Lock", p.Locked, 76)) SetLock(p, !p.Locked);
                if (p.Member != null && p.Member.IsBool)
                {
                    if (Button("Flip it", false, 80)) PinOp(p, "!");
                }
                else if (p.Member != null)
                {
                    foreach (var op in p.Member.IsFloat ? new[] { "+10", "x2", "9999" } : new[] { "+100", "x2", "999999" })
                        if (Button(op.StartsWith("+") || op.StartsWith("x") ? op : "=" + op, false, 70)) PinOp(p, op);
                    _edits.TryGetValue(p, out var txt);
                    txt = GUILayout.TextField(txt ?? "", 20, _sField, W(90));
                    _edits[p] = txt;
                    if (Button("Set", false, 48) && Finder.TryConvert(txt, p.Member.ValueType, out var v) && PinSet(p, v)) _edits[p] = "";
                }
                GUILayout.FlexibleSpace();
                if (p.Kind != 1 && Button(p.All ? "All" : "One", p.All, 52))
                {
                    p.All = !p.All; p.NextResolve = 0; SavePins();
                    ShowToast(p.All ? $"{p.Label}: changes now hit every one of them" : $"{p.Label}: back to just one");
                }
                if (Button("Remove", false, 76)) remove = p;
                GUILayout.EndHorizontal();
                GUILayout.EndVertical();
            }
            GUILayout.EndScrollView();
            if (remove != null) { _pins.Remove(remove); SavePins(); ShowToast($"Removed {remove.Label}."); }
        }

        private void DrawAbout()
        {
            _scroll = GUILayout.BeginScrollView(_scroll);
            GUILayout.Label($"House Edge In-Game {Version}", _sSection);
            GUILayout.Label("A mod menu for single-player and local play. In online games its mods pause by themselves.", _sLabel);
            GUILayout.Label($"Running on: {GameInfo.Summary}", _sMuted);
            GUILayout.Space(8);
            GUILayout.Label("Every version", _sSection);
            GUILayout.Label("The same install works in the full game and the demo, in 32-bit and 64-bit builds, and after game updates. When an update renames something you pinned, the pin follows the new name if it can tell which one it is.", _sLabel);
            GUILayout.Space(8);
            GUILayout.Label("How to find a value", _sSection);
            GUILayout.Label("1. On Find values, search for what it's probably called: chips, money, health, lives.\n2. Several results? Change the number in the game, then press Changed (or Went up / Went down) to keep only the ones that moved with it.\n3. Press Pin on the one that works. On the Pinned tab, Lock keeps it from changing.\n4. Use All to change every copy at once, for example every enemy's health.", _sLabel);
            GUILayout.Space(8);
            GUILayout.Label("Tips", _sSection);
            GUILayout.Label("- Menu keys, size and Party Mode timing are in BepInEx/config/houseedge.ingame.cfg.\n- Typing in the search box also reaches the game. Turn on Pause while menu is open on the Fun tab if that's a problem.\n- If something goes wrong, BepInEx/LogOutput.log says what happened.", _sLabel);
            GUILayout.EndScrollView();
        }
    }
}
