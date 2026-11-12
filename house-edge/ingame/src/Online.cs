using System;
using System.Collections;

namespace HouseEdgeInGame
{
    /// <summary>
    /// Tells whether the game is in an online session with other people.
    ///
    /// House Edge is for single-player and local play. In an online session, mods that change the game
    /// (values, locks, speed, gravity, Party Mode) pause by themselves, and the menu says so instead of failing silently.
    /// They come back as soon as the session ends.
    ///
    /// Playing alone counts as offline even when the game runs a "host" behind the scenes, as many games do for solo mode.
    /// The check covers the common Unity networking libraries: Mirror, Netcode for GameObjects, Photon PUN and Fusion, and FishNet.
    /// </summary>
    internal static class Online
    {
        public static bool Active { get; private set; }
        public static string Why { get; private set; } = "";
        private static float _next;

        /// <summary>Re-checks once a second. Returns true when the online state just changed.</summary>
        public static bool Tick(float now)
        {
            if (now < _next) return false;
            _next = now + 1f;
            string why = Mirror() ?? Netcode() ?? Pun() ?? Fusion() ?? FishNet();
            bool was = Active;
            Active = why != null;
            Why = why ?? "";
            return was != Active;
        }

        // Each check reads the library through reflection, so a game that doesn't use it costs nothing.
        private static string Guard(Func<string> check)
        {
            try { return check(); } catch (Exception) { return null; }
        }

        private static string Mirror() => Guard(() =>
        {
            var server = Reflect.Type("Mirror.NetworkServer");
            var client = Reflect.Type("Mirror.NetworkClient");
            if (server == null && client == null) return null;
            bool serverOn = Reflect.Bool(Reflect.Static(server, "active"));
            bool clientOn = Reflect.Bool(Reflect.Static(client, "active"));
            if (clientOn && !serverOn) return "You joined someone else's game.";
            if (serverOn && Others(Reflect.Count(Reflect.Static(server, "connections")), clientOn)) return "Other players are in your game.";
            return null;
        });

        private static string Netcode() => Guard(() =>
        {
            var nm = Reflect.Static(Reflect.Type("Unity.Netcode.NetworkManager"), "Singleton");
            if (nm == null || !Reflect.Bool(Reflect.Get(nm, "IsListening"))) return null;
            bool isServer = Reflect.Bool(Reflect.Get(nm, "IsServer"));
            bool isClient = Reflect.Bool(Reflect.Get(nm, "IsClient"));
            if (isClient && !isServer) return "You joined someone else's game.";
            if (isServer && Others(Reflect.Count(Reflect.Get(nm, "ConnectedClientsIds")), isClient)) return "Other players are in your game.";
            return null;
        });

        private static string Pun() => Guard(() =>
        {
            // PUN 2 lives in Photon.Pun. PUN Classic has no namespace and lower-case names.
            var pun2 = Reflect.Type("Photon.Pun.PhotonNetwork");
            if (pun2 != null)
                return Reflect.Bool(Reflect.Static(pun2, "InRoom")) && !Reflect.Bool(Reflect.Static(pun2, "OfflineMode")) ? "You're in an online room." : null;
            var classic = Reflect.Type("PhotonNetwork");
            if (classic != null)
                return Reflect.Bool(Reflect.Static(classic, "inRoom")) && !Reflect.Bool(Reflect.Static(classic, "offlineMode")) ? "You're in an online room." : null;
            return null;
        });

        private static string Fusion() => Guard(() =>
        {
            if (!(Reflect.Static(Reflect.Type("Fusion.NetworkRunner"), "Instances") is IEnumerable runners)) return null;
            foreach (var r in runners)
            {
                if (r == null || !Reflect.Bool(Reflect.Get(r, "IsRunning"))) continue;
                var mode = Convert.ToString(Reflect.Get(r, "GameMode"));
                if (!string.Equals(mode, "Single", StringComparison.OrdinalIgnoreCase)) return "You're in an online session.";
            }
            return null;
        });

        private static string FishNet() => Guard(() =>
        {
            var finder = Reflect.Type("FishNet.InstanceFinder");
            if (finder == null) return null;
            // FishNet 4 renamed IsServer/IsClient to IsServerStarted/IsClientStarted.
            bool isServer = Reflect.Bool(Reflect.Static(finder, "IsServerStarted") ?? Reflect.Static(finder, "IsServer"));
            bool isClient = Reflect.Bool(Reflect.Static(finder, "IsClientStarted") ?? Reflect.Static(finder, "IsClient"));
            if (isClient && !isServer) return "You joined someone else's game.";
            if (isServer && Others(Reflect.Count(Reflect.Get(Reflect.Static(finder, "ServerManager"), "Clients")), isClient)) return "Other players are in your game.";
            return null;
        });

        /// <summary>True when the server has connections besides this PC's own.</summary>
        private static bool Others(int connections, bool alsoClient) => connections - (alsoClient ? 1 : 0) > 0;
    }
}
