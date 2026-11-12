using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using UnityEngine;
using UObject = UnityEngine.Object;

namespace HouseEdgeInGame
{
    /// <summary>One number or on/off value in the game's own code, like PlayerWallet.chips.</summary>
    internal sealed class Member
    {
        public Type Owner;
        public FieldInfo Field;
        public PropertyInfo Prop;
        public bool IsStatic;
        public string Name;
        public Type ValueType;

        public object Get(object target) => Field != null ? Field.GetValue(target) : Prop.GetValue(target, null);
        public void Set(object target, object value) { if (Field != null) Field.SetValue(target, value); else Prop.SetValue(target, value, null); }
        public bool IsBool => ValueType == typeof(bool);
        public bool IsFloat => ValueType == typeof(float) || ValueType == typeof(double);
    }

    /// <summary>A search result: a member on one particular object (or a static, with no object).</summary>
    internal sealed class Hit
    {
        public Member Member;
        public UObject Target;   // null for statics
        public string Label;
        public string Where;
        public string Shown = "";

        public bool Alive => Member.IsStatic || Target != null; // Unity's == null also catches destroyed objects
        public object Instance => Member.IsStatic ? null : Target;
    }

    /// <summary>A value the player kept, optionally locked. Survives scene changes and restarts.</summary>
    internal sealed class Pin
    {
        public string TypeName, MemberName, ObjectName, Label;
        public int Kind;          // 0 = on a scene object, 1 = static, 2 = on a data asset (ScriptableObject)
        public bool All;          // apply to every object of this type, e.g. every enemy's health
        public bool Locked;
        public string LockText = "";

        public Member Member;
        public readonly List<UObject> Targets = new List<UObject>();
        public float NextResolve;
        public object LockValue;
        public string Shown = "—";

        public bool Ready => Member != null && (Kind == 1 || Targets.Any(t => t != null));
    }

    internal static class Finder
    {
        private static readonly HashSet<Type> Supported = new HashSet<Type>
        {
            typeof(int), typeof(float), typeof(double), typeof(long), typeof(short), typeof(byte),
            typeof(uint), typeof(ulong), typeof(ushort), typeof(sbyte), typeof(bool),
        };

        private static readonly string[] EnginePrefixes =
        {
            "UnityEngine", "Unity.", "UnityEditor", "System", "mscorlib", "netstandard", "Mono.", "Microsoft.",
            "BepInEx", "0Harmony", "HarmonyX", "MonoMod", "HouseEdgeInGame", "Newtonsoft", "TextMeshPro",
            "DOTween", "DemiLib", "Rewired", "Sirenix", "FMOD", "Steamworks", "com.rlabrecque", "Facepunch",
            "Cinemachine", "Mirror", "Photon", "Assembly-CSharp-Editor",
        };

        private static readonly Dictionary<Type, List<Member>> InstanceCache = new Dictionary<Type, List<Member>>();
        private static List<Member> _statics;

        public static bool IsGameAssembly(Assembly a)
        {
            if (a.IsDynamic) return false;
            var n = a.GetName().Name ?? "";
            return !EnginePrefixes.Any(p => n.StartsWith(p, StringComparison.OrdinalIgnoreCase));
        }

        public static bool IsGameType(Type t) => t != null && IsGameAssembly(t.Assembly);

        private static IEnumerable<Type> SafeTypes(Assembly a)
        {
            try { return a.GetTypes(); }
            catch (ReflectionTypeLoadException e) { return e.Types.Where(t => t != null); }
            catch (Exception) { return Enumerable.Empty<Type>(); }
        }

        /// <summary>"&lt;Chips&gt;k__BackingField" becomes "Chips"; "m_health" and "_health" become "health".</summary>
        public static string Pretty(string name)
        {
            if (name.StartsWith("<") && name.Contains(">k__BackingField")) return name.Substring(1, name.IndexOf('>') - 1);
            if (name.StartsWith("m_") && name.Length > 2) return name.Substring(2);
            if (name.StartsWith("_") && name.Length > 1) return name.Substring(1);
            return name;
        }

        private static List<Member> MembersOf(Type type, bool statics)
        {
            var list = new List<Member>();
            var flags = BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.DeclaredOnly | (statics ? BindingFlags.Static : BindingFlags.Instance);
            for (var t = type; t != null && IsGameType(t); t = t.BaseType)
            {
                var seen = new HashSet<string>();
                FieldInfo[] fields; PropertyInfo[] props;
                try { fields = t.GetFields(flags); props = t.GetProperties(flags); }
                catch (Exception) { continue; }
                foreach (var f in fields)
                {
                    if (f.IsLiteral || !Supported.Contains(f.FieldType)) continue;
                    var n = Pretty(f.Name);
                    seen.Add(n);
                    list.Add(new Member { Owner = t, Field = f, IsStatic = statics, Name = n, ValueType = f.FieldType });
                }
                foreach (var p in props)
                {
                    if (!Supported.Contains(p.PropertyType) || !p.CanRead || !p.CanWrite || p.GetIndexParameters().Length > 0) continue;
                    if (p.GetGetMethod(true) == null || p.GetSetMethod(true) == null || seen.Contains(p.Name)) continue;
                    list.Add(new Member { Owner = t, Prop = p, IsStatic = statics, Name = p.Name, ValueType = p.PropertyType });
                }
            }
            return list;
        }

        private static List<Member> InstanceMembers(Type t)
        {
            if (!InstanceCache.TryGetValue(t, out var list)) InstanceCache[t] = list = MembersOf(t, false);
            return list;
        }

        private static List<Member> StaticMembers()
        {
            if (_statics != null) return _statics;
            _statics = new List<Member>();
            foreach (var a in AppDomain.CurrentDomain.GetAssemblies().Where(IsGameAssembly))
                foreach (var t in SafeTypes(a))
                {
                    if (t.IsGenericTypeDefinition || t.ContainsGenericParameters || t.IsInterface) continue;
                    try { _statics.AddRange(MembersOf(t, true)); } catch (Exception) { }
                }
            return _statics;
        }

        public static IEnumerable<UObject> LiveGameObjects()
        {
            foreach (var mb in UObject.FindObjectsOfType<MonoBehaviour>())
                if (mb != null && IsGameType(mb.GetType())) yield return mb;
            ScriptableObject[] data;
            try { data = Resources.FindObjectsOfTypeAll<ScriptableObject>(); } catch (Exception) { data = new ScriptableObject[0]; }
            foreach (var so in data)
                if (so != null && IsGameType(so.GetType())) yield return so;
        }

        /// <summary>Find every number or on/off value whose name contains the search text.</summary>
        public static List<Hit> Search(string query, int limit, out int total)
        {
            var q = (query ?? "").Trim().ToLowerInvariant();
            var hits = new List<Hit>();
            total = 0;
            if (q.Length == 0) return hits;

            foreach (var obj in LiveGameObjects())
            {
                foreach (var m in InstanceMembers(obj.GetType()))
                {
                    if (m.Name.ToLowerInvariant().IndexOf(q, StringComparison.Ordinal) < 0) continue;
                    total++;
                    if (hits.Count >= limit) continue;
                    var where = obj is Component c ? "on " + c.gameObject.name : "game data: " + obj.name;
                    hits.Add(new Hit { Member = m, Target = obj, Label = m.Owner.Name + "." + m.Name, Where = where });
                }
            }
            foreach (var m in StaticMembers())
            {
                if (m.Name.ToLowerInvariant().IndexOf(q, StringComparison.Ordinal) < 0) continue;
                total++;
                if (hits.Count >= limit) continue;
                hits.Add(new Hit { Member = m, Label = m.Owner.Name + "." + m.Name, Where = "global" });
            }
            // Likely matches first: exact names, then names that start with the search.
            return hits.OrderBy(h => h.Member.Name.ToLowerInvariant() == q ? 0 : h.Member.Name.ToLowerInvariant().StartsWith(q) ? 1 : 2)
                       .ThenBy(h => h.Label).ToList();
        }

        public static Pin PinFrom(Hit h)
        {
            var kind = h.Member.IsStatic ? 1 : h.Target is ScriptableObject ? 2 : 0;
            return new Pin
            {
                TypeName = h.Member.Owner.FullName, MemberName = h.Member.Field != null ? h.Member.Field.Name : h.Member.Prop.Name,
                ObjectName = h.Target != null ? h.Target.name : "", Label = h.Label, Kind = kind, Member = h.Member,
                Targets = { h.Target },
            };
        }

        // ------------------------------------------------------------------ reading and writing values
        public static object Read(Member m, object target)
        {
            try { return m.Get(target); } catch (Exception) { return null; }
        }

        public static bool Write(Member m, object target, object value)
        {
            try { m.Set(target, value); return true; } catch (Exception) { return false; }
        }

        public static string Show(object v)
        {
            if (v == null) return "—";
            if (v is bool b) return b ? "ON" : "OFF";
            if (v is float f) return f.ToString("#,0.##", CultureInfo.InvariantCulture);
            if (v is double d) return d.ToString("#,0.##", CultureInfo.InvariantCulture);
            return Convert.ToDouble(v, CultureInfo.InvariantCulture).ToString("#,0", CultureInfo.InvariantCulture);
        }

        /// <summary>Text to the member's type, clamped so a huge number can't wrap around to negative.</summary>
        public static bool TryConvert(string text, Type t, out object value)
        {
            value = null;
            var s = (text ?? "").Trim().Replace(",", "");
            if (t == typeof(bool))
            {
                var l = s.ToLowerInvariant();
                if (l == "1" || l == "true" || l == "on" || l == "yes") { value = true; return true; }
                if (l == "0" || l == "false" || l == "off" || l == "no") { value = false; return true; }
                return false;
            }
            if (!double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out var d)) return false;
            return TryFromDouble(d, t, out value);
        }

        public static bool TryFromDouble(double d, Type t, out object value)
        {
            value = null;
            if (double.IsNaN(d) || double.IsInfinity(d)) return false;
            if (t == typeof(float)) { value = (float)Math.Max(float.MinValue, Math.Min(float.MaxValue, d)); return true; }
            if (t == typeof(double)) { value = d; return true; }
            double lo, hi;
            if (t == typeof(int)) { lo = int.MinValue; hi = int.MaxValue; }
            else if (t == typeof(long)) { lo = long.MinValue; hi = long.MaxValue; }
            else if (t == typeof(short)) { lo = short.MinValue; hi = short.MaxValue; }
            else if (t == typeof(byte)) { lo = 0; hi = byte.MaxValue; }
            else if (t == typeof(uint)) { lo = 0; hi = uint.MaxValue; }
            else if (t == typeof(ulong)) { lo = 0; hi = ulong.MaxValue; }
            else if (t == typeof(ushort)) { lo = 0; hi = ushort.MaxValue; }
            else if (t == typeof(sbyte)) { lo = sbyte.MinValue; hi = sbyte.MaxValue; }
            else return false;
            d = Math.Round(Math.Max(lo, Math.Min(hi, d)));
            try { value = Convert.ChangeType(d, t, CultureInfo.InvariantCulture); return true; }
            catch (Exception) { return false; }
        }

        /// <summary>Quick buttons: "+100" adds, "x2" doubles, "=999999" or "999999" sets, "!" flips an on/off value.</summary>
        public static bool TryApplyOp(object current, string op, Type t, out object value)
        {
            value = null;
            op = op.Trim().ToLowerInvariant();
            if (t == typeof(bool)) { value = !(current is bool b && b); return true; }
            double cur = current == null ? 0 : Convert.ToDouble(current, CultureInfo.InvariantCulture);
            double n;
            if (op.StartsWith("x") && double.TryParse(op.Substring(1), NumberStyles.Float, CultureInfo.InvariantCulture, out n)) return TryFromDouble(cur * n, t, out value);
            if ((op.StartsWith("+") || op.StartsWith("-")) && double.TryParse(op, NumberStyles.Float, CultureInfo.InvariantCulture, out n)) return TryFromDouble(cur + n, t, out value);
            if (double.TryParse(op.TrimStart('='), NumberStyles.Float, CultureInfo.InvariantCulture, out n)) return TryFromDouble(n, t, out value);
            return false;
        }

        // ------------------------------------------------------------------ pins: finding targets again after a scene load
        public static void Resolve(Pin p)
        {
            if (p.Member == null)
            {
                var type = AppDomain.CurrentDomain.GetAssemblies().Where(IsGameAssembly).SelectMany(SafeTypes).FirstOrDefault(t => t.FullName == p.TypeName);
                if (type == null) return;
                var members = p.Kind == 1 ? MembersOf(type, true) : InstanceMembers(type);
                p.Member = members.FirstOrDefault(m => (m.Field != null ? m.Field.Name : m.Prop.Name) == p.MemberName);
                if (p.Member == null) return;
                if (p.LockText.Length > 0 && TryConvert(p.LockText, p.Member.ValueType, out var lv)) p.LockValue = lv;
            }
            if (p.Kind == 1) return;
            p.Targets.RemoveAll(t => t == null);
            if (p.Targets.Count > 0 && !p.All) return;
            UObject[] found;
            try { found = p.Kind == 2 ? Resources.FindObjectsOfTypeAll(p.Member.Owner) : UObject.FindObjectsOfType(p.Member.Owner); }
            catch (Exception) { return; }
            var matches = found.Where(o => o != null && p.Member.Owner.IsInstanceOfType(o)).ToList();
            p.Targets.Clear();
            if (p.All) p.Targets.AddRange(matches);
            else
            {
                var best = matches.FirstOrDefault(o => o.name == p.ObjectName) ?? matches.FirstOrDefault();
                if (best != null) p.Targets.Add(best);
            }
        }

        public static IEnumerable<object> Instances(Pin p)
        {
            if (p.Kind == 1) { yield return null; yield break; }
            foreach (var t in p.Targets) if (t != null) yield return t;
        }

        // ------------------------------------------------------------------ saving pins
        public static void Save(string path, IEnumerable<Pin> pins)
        {
            try
            {
                var lines = pins.Select(p => string.Join("\t", new[]
                {
                    p.Kind.ToString(), p.TypeName, p.MemberName, Clean(p.ObjectName), p.All ? "1" : "0", p.Locked ? "1" : "0",
                    Clean(p.LockText), Clean(p.Label),
                }));
                File.WriteAllLines(path, new[] { "# House Edge In-Game pins: kind, type, member, object, all, locked, lock value, label" }.Concat(lines).ToArray());
            }
            catch (Exception) { }
        }

        public static List<Pin> Load(string path)
        {
            var pins = new List<Pin>();
            try
            {
                if (!File.Exists(path)) return pins;
                foreach (var line in File.ReadAllLines(path))
                {
                    if (line.StartsWith("#")) continue;
                    var c = line.Split('\t');
                    if (c.Length < 8) continue;
                    pins.Add(new Pin
                    {
                        Kind = int.TryParse(c[0], out var k) ? k : 0, TypeName = c[1], MemberName = c[2], ObjectName = c[3],
                        All = c[4] == "1", Locked = c[5] == "1", LockText = c[6], Label = c[7],
                    });
                }
            }
            catch (Exception) { }
            return pins;
        }

        private static string Clean(string s) => (s ?? "").Replace("\t", " ").Replace("\n", " ").Replace("\r", " ");
    }
}
