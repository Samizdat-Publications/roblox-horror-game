"""Print a Luau snippet that sets the Source of the scripts for the given src/ files.
Paste the output into execute_luau (Edit). Used when localhost sync is blocked.
Usage: python tools/sync/push_snippet.py src/path/a.luau [src/path/b.luau ...]
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_manifest import ROOT, SRC, classify  # noqa: E402

out = ["local function put(path, cls, src)",
       "\tlocal node = game:GetService(path[1])",
       "\tlocal i = 2",
       "\tif path[1] == 'StarterPlayer' then node = node:WaitForChild(path[2]) i = 3 end",
       "\tfor j = i, #path - 1 do",
       "\t\tlocal c = node:FindFirstChild(path[j])",
       "\t\tif not c then c = Instance.new('Folder') c.Name = path[j] c.Parent = node end",
       "\t\tnode = c",
       "\tend",
       "\tlocal s = node:FindFirstChild(path[#path])",
       "\tif s and s.ClassName ~= cls then s:Destroy() s = nil end",
       "\tif not s then s = Instance.new(cls) s.Name = path[#path] s.Parent = node end",
       "\ts.Source = src",
       "end",
       "local n = 0"]
for f in sys.argv[1:]:
    full = os.path.abspath(f)
    rel = os.path.relpath(full, SRC).replace("\\", "/")
    name, cls = classify(os.path.basename(full))
    parts = rel.split("/")[:-1] + [name]
    src = open(full, encoding="utf-8").read()
    level = "=" * 4
    assert "]" + level + "]" not in src
    path = "{" + ", ".join(repr(p) for p in parts) + "}"
    out.append(f"put({path}, '{cls}', [{level}[\n{src}]{level}]) n += 1")
out.append("return 'pushed ' .. n")
print("\n".join(out))
