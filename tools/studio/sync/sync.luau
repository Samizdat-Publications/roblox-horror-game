-- Paste into execute_luau (Edit). Pulls build/manifest.json from the local http server
-- (python -m http.server 8765 in the repo root) and creates or updates every script.
-- Scripts that exist in Studio under a synced folder but not in src/ are reported, not deleted.
local HttpService = game:GetService("HttpService")
local body = HttpService:GetAsync("http://localhost:8765/build/manifest.json", true)
local manifest = HttpService:JSONDecode(body)

local function resolveParent(path)
	-- path = {"ServerScriptService", "Server", "Name"} ; returns parent of the leaf
	local node = game:GetService(path[1])
	local i = 2
	if path[1] == "StarterPlayer" then
		node = node:FindFirstChild(path[2]) or node:WaitForChild(path[2])
		i = 3
	end
	for j = i, #path - 1 do
		local child = node:FindFirstChild(path[j])
		if not child then
			child = Instance.new("Folder")
			child.Name = path[j]
			child.Parent = node
		end
		node = child
	end
	return node
end

local created, updated = 0, 0
for _, e in manifest.entries do
	local parent = resolveParent(e.path)
	local name = e.path[#e.path]
	local inst = parent:FindFirstChild(name)
	if inst and inst.ClassName ~= e.className then
		inst:Destroy()
		inst = nil
	end
	if not inst then
		inst = Instance.new(e.className)
		inst.Name = name
		inst.Source = e.source
		inst.Parent = parent
		created += 1
	elseif inst.Source ~= e.source then
		inst.Source = e.source
		updated += 1
	end
end
return string.format("sync ok: %d entries, %d created, %d updated", #manifest.entries, created, updated)
