-- Run in execute_luau (Edit). Returns JSON of script checksums under the synced services,
-- keyed like src/ paths (Service.Folder.Name). Compare with tools/sync/verify.py.
local roots = {
	game.ReplicatedStorage,
	game.ServerScriptService,
	game.ServerStorage,
	game.StarterPlayer.StarterPlayerScripts,
}
local out = {}
for _, root in roots do
	for _, d in root:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			local src = (d :: any).Source:gsub("\r\n", "\n")
			local h = 0
			for i = 1, #src do
				h = (h * 31 + string.byte(src, i)) % 4294967296
			end
			local key = d:GetFullName():gsub("^StarterPlayer%.", "StarterPlayer.")
			out[key] = #src .. ":" .. h
		end
	end
end
return game:GetService("HttpService"):JSONEncode(out)
