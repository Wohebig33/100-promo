// Stand-ins with the same names as the real networking libraries, so Online.cs finds them by reflection
// exactly as it would in a game. Each test sets one library's state and checks what Online decides.
using System;
using System.Collections.Generic;
using HouseEdgeInGame;

namespace Mirror
{
    public static class NetworkServer { public static bool active; public static Dictionary<int, object> connections = new Dictionary<int, object>(); }
    public static class NetworkClient { public static bool active; }
}

namespace Unity.Netcode
{
    public class NetworkManager
    {
        public static NetworkManager Singleton { get; set; }
        public bool IsListening { get; set; }
        public bool IsServer { get; set; }
        public bool IsClient { get; set; }
        public IReadOnlyList<ulong> ConnectedClientsIds { get; set; } = new List<ulong>();
    }
}

namespace Photon.Pun
{
    public static class PhotonNetwork { public static bool InRoom { get; set; } public static bool OfflineMode { get; set; } }
}

namespace Fusion
{
    public enum GameMode { Single = 1, Shared, Server, Host, Client, AutoHostOrClient }
    public class NetworkRunner
    {
        public static List<NetworkRunner> Instances { get; } = new List<NetworkRunner>();
        public bool IsRunning { get; set; }
        public GameMode GameMode { get; set; }
    }
}

namespace FishNet
{
    public class ServerManagerStandIn { public Dictionary<int, object> Clients { get; } = new Dictionary<int, object>(); }
    public static class InstanceFinder
    {
        public static bool IsServerStarted { get; set; }
        public static bool IsClientStarted { get; set; }
        public static ServerManagerStandIn ServerManager { get; } = new ServerManagerStandIn();
    }
}

internal static class Program
{
    private static float _now;
    private static int _failed, _passed;

    private static void Reset()
    {
        Mirror.NetworkServer.active = false; Mirror.NetworkClient.active = false; Mirror.NetworkServer.connections.Clear();
        Unity.Netcode.NetworkManager.Singleton = null;
        Photon.Pun.PhotonNetwork.InRoom = false; Photon.Pun.PhotonNetwork.OfflineMode = false;
        Fusion.NetworkRunner.Instances.Clear();
        FishNet.InstanceFinder.IsServerStarted = false; FishNet.InstanceFinder.IsClientStarted = false; FishNet.InstanceFinder.ServerManager.Clients.Clear();
    }

    private static void Expect(string name, bool online)
    {
        _now += 2f; // Online re-checks at most once a second
        Online.Tick(_now);
        bool ok = Online.Active == online;
        if (ok) _passed++; else _failed++;
        Console.WriteLine($"{(ok ? "PASS" : "FAIL")}  {name}: {(Online.Active ? "online (" + Online.Why + ")" : "offline")}");
        Reset();
    }

    private static int Main()
    {
        Reset();
        Expect("nothing running", false);

        Mirror.NetworkServer.active = true; Mirror.NetworkClient.active = true; Mirror.NetworkServer.connections[0] = new object();
        Expect("Mirror: solo host, only this PC", false);
        Mirror.NetworkServer.active = true; Mirror.NetworkClient.active = true; Mirror.NetworkServer.connections[0] = new object(); Mirror.NetworkServer.connections[1] = new object();
        Expect("Mirror: host with a friend connected", true);
        Mirror.NetworkClient.active = true;
        Expect("Mirror: joined someone's game", true);

        Unity.Netcode.NetworkManager.Singleton = new Unity.Netcode.NetworkManager { IsListening = true, IsServer = true, IsClient = true, ConnectedClientsIds = new List<ulong> { 0 } };
        Expect("Netcode: solo host", false);
        Unity.Netcode.NetworkManager.Singleton = new Unity.Netcode.NetworkManager { IsListening = true, IsServer = true, IsClient = true, ConnectedClientsIds = new List<ulong> { 0, 7 } };
        Expect("Netcode: host with a friend", true);
        Unity.Netcode.NetworkManager.Singleton = new Unity.Netcode.NetworkManager { IsListening = true, IsClient = true };
        Expect("Netcode: joined as client", true);
        Unity.Netcode.NetworkManager.Singleton = new Unity.Netcode.NetworkManager { IsListening = false, IsClient = true };
        Expect("Netcode: manager exists but not started", false);

        Photon.Pun.PhotonNetwork.InRoom = true; Photon.Pun.PhotonNetwork.OfflineMode = true;
        Expect("PUN: offline mode room", false);
        Photon.Pun.PhotonNetwork.InRoom = true;
        Expect("PUN: online room", true);

        Fusion.NetworkRunner.Instances.Add(new Fusion.NetworkRunner { IsRunning = true, GameMode = Fusion.GameMode.Single });
        Expect("Fusion: single-player runner", false);
        Fusion.NetworkRunner.Instances.Add(new Fusion.NetworkRunner { IsRunning = true, GameMode = Fusion.GameMode.Shared });
        Expect("Fusion: shared session", true);

        FishNet.InstanceFinder.IsServerStarted = true; FishNet.InstanceFinder.IsClientStarted = true; FishNet.InstanceFinder.ServerManager.Clients[0] = new object();
        Expect("FishNet: solo host", false);
        FishNet.InstanceFinder.IsServerStarted = true; FishNet.InstanceFinder.IsClientStarted = true; FishNet.InstanceFinder.ServerManager.Clients[0] = new object(); FishNet.InstanceFinder.ServerManager.Clients[1] = new object();
        Expect("FishNet: host with a friend", true);
        FishNet.InstanceFinder.IsClientStarted = true;
        Expect("FishNet: joined as client", true);

        Expect("back to nothing running", false);
        Console.WriteLine($"{_passed} passed, {_failed} failed");
        return _failed == 0 ? 0 : 1;
    }
}
