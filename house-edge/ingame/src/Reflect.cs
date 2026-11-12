using System;
using System.Collections;
using System.Collections.Generic;
using System.Reflection;

namespace HouseEdgeInGame
{
    /// <summary>Small reflection helpers for reading other libraries without referencing them.</summary>
    internal static class Reflect
    {
        private const BindingFlags Any = BindingFlags.Public | BindingFlags.NonPublic;
        private static readonly Dictionary<string, Type> Types = new Dictionary<string, Type>();
        private static int _assemblyCount;

        /// <summary>A type by full name from any loaded assembly, or null. Re-checks when new assemblies load.</summary>
        public static Type Type(string fullName)
        {
            var assemblies = AppDomain.CurrentDomain.GetAssemblies();
            if (assemblies.Length != _assemblyCount) { Types.Clear(); _assemblyCount = assemblies.Length; }
            if (Types.TryGetValue(fullName, out var found)) return found;
            found = null;
            foreach (var a in assemblies)
            {
                if (a.IsDynamic) continue;
                try { found = a.GetType(fullName, false); } catch (Exception) { }
                if (found != null) break;
            }
            Types[fullName] = found;
            return found;
        }

        public static object Static(Type t, string name) => t == null ? null : Value(t, null, name, BindingFlags.Static);

        public static object Get(object o, string name) => o == null ? null : Value(o.GetType(), o, name, BindingFlags.Instance);

        private static object Value(Type t, object o, string name, BindingFlags kind)
        {
            try
            {
                var p = t.GetProperty(name, Any | kind);
                if (p != null && p.GetIndexParameters().Length == 0) return p.GetValue(o, null);
                var f = t.GetField(name, Any | kind);
                return f?.GetValue(o);
            }
            catch (Exception) { return null; }
        }

        public static bool Bool(object v) => v is bool b && b;

        /// <summary>How many items a collection holds, or -1 if it isn't one.</summary>
        public static int Count(object v)
        {
            if (v is ICollection c) return c.Count;
            if (v is IEnumerable e) { int n = 0; foreach (var _ in e) n++; return n; }
            return -1;
        }
    }
}
