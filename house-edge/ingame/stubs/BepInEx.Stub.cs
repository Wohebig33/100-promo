// Compile-time stand-in for the parts of BepInEx 5 that House Edge In-Game uses.
// It exists only so the plugin can build where the real BepInEx.dll can't be downloaded.
// Release builds (CI) compile against the real BepInEx, and this file is never shipped.
using System;
using UnityEngine;

namespace BepInEx
{
    [AttributeUsage(AttributeTargets.Class, AllowMultiple = false)]
    public class BepInPlugin : Attribute
    {
        public BepInPlugin(string GUID, string Name, string Version) { }
    }

    public abstract class BaseUnityPlugin : MonoBehaviour
    {
        protected Logging.ManualLogSource Logger { get; } = new Logging.ManualLogSource();
        public Configuration.ConfigFile Config { get; } = new Configuration.ConfigFile();
    }

    public static class Paths
    {
        public static string ConfigPath { get; } = "";
    }
}

namespace BepInEx.Logging
{
    public class ManualLogSource
    {
        public void LogInfo(object data) { }
        public void LogWarning(object data) { }
        public void LogError(object data) { }
    }
}

namespace BepInEx.Configuration
{
    public class ConfigFile
    {
        public ConfigEntry<T> Bind<T>(string section, string key, T defaultValue, string description) => new ConfigEntry<T> { Value = defaultValue };
    }

    public class ConfigEntry<T>
    {
        public T Value { get; set; }
    }
}
