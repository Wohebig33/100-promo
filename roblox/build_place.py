"""Builds Sinborn.rbxlx (a Roblox place file) from the Luau sources in src/.

Run:  python3 build_place.py
Then open Sinborn.rbxlx in Roblox Studio. No Rojo needed.
"""
import os
from xml.sax.saxutils import escape

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "src")
ref = [0]


def nxt():
    ref[0] += 1
    return f"RBX{ref[0]:08X}"


def read(rel):
    with open(os.path.join(SRC, rel), encoding="utf-8") as f:
        text = f.read()
    assert "]]>" not in text, rel
    return text


def item(cls, name, children=(), source=None):
    props = f'<string name="Name">{escape(name)}</string>'
    if source is not None:
        props += f'<ProtectedString name="Source"><![CDATA[{source}]]></ProtectedString>'
    kids = "".join(children)
    return f'<Item class="{cls}" referent="{nxt()}"><Properties>{props}</Properties>{kids}</Item>'


tree = [
    item("Workspace", "Workspace"),
    item("ReplicatedStorage", "ReplicatedStorage", [
        item("Folder", "Sinborn", [item("ModuleScript", "Config", source=read("shared/Config.lua"))]),
    ]),
    item("ServerScriptService", "ServerScriptService", [
        item("Script", "SinbornServer", [
            item("ModuleScript", "Data", source=read("server/Data.lua")),
            item("ModuleScript", "World", source=read("server/World.lua")),
        ], source=read("server/init.server.lua")),
    ]),
    item("StarterPlayer", "StarterPlayer", [
        item("StarterPlayerScripts", "StarterPlayerScripts", [
            item("LocalScript", "SinbornClient", [
                item("ModuleScript", "UI", source=read("client/UI.lua")),
                item("ModuleScript", "FX", source=read("client/FX.lua")),
            ], source=read("client/init.client.lua")),
        ]),
        item("StarterCharacterScripts", "StarterCharacterScripts"),
    ]),
]

xml = (
    '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
    'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
    'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">'
    '<External>null</External><External>nil</External>'
    + "".join(tree)
    + "</roblox>\n"
)
out = os.path.join(HERE, "Sinborn.rbxlx")
with open(out, "w", encoding="utf-8") as f:
    f.write(xml)
print("wrote", out, len(xml), "bytes")
