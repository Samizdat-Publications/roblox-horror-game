--[[
Loads the pure shared modules (src/shared) under Lune for the simulations, the same way
tools/test/run.luau does for the specs: a fake instance tree so `script.Parent.X`
requires work, and a `require` that loads modules from it.

    local loader = require("./loader")
    local Shared, req = loader.load()
    local Night = req(Shared.Core.Night)

Run from the project root.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local SHARED_DIR = "src/shared"

type NodeInfo = {
	name: string,
	parent: any,
	children: { [string]: any },
	path: string?,
	source: string?,
}
local info: { [any]: NodeInfo } = setmetatable({}, { __mode = "k" }) :: any

local nodeMeta = {}
nodeMeta.__index = function(node, key)
	local i = info[node]
	if key == "Parent" then
		return i.parent
	elseif key == "Name" then
		return i.name
	end
	local child = i.children[key]
	if child == nil then
		error(string.format("%s is not a valid member of %s", tostring(key), i.name), 2)
	end
	return child
end
nodeMeta.__tostring = function(node)
	return info[node].name
end

local function newNode(name: string, parent: any, path: string?, source: string?)
	local node = setmetatable({}, nodeMeta)
	info[node] = { name = name, parent = parent, children = {}, path = path, source = source }
	if parent ~= nil then
		info[parent].children[name] = node
	end
	return node
end

local function buildTree(dir: string, parent: any)
	for _, entry in fs.readDir(dir) do
		local path = dir .. "/" .. entry
		if fs.isDir(path) then
			buildTree(path, newNode(entry, parent))
		else
			local name = entry:match("^(.+)%.luau$")
			if name and not name:find("%.") then
				newNode(name, parent, path, fs.readFile(path))
			end
		end
	end
end

local loader = {}

function loader.load(): (any, (any) -> any)
	local root = newNode("ReplicatedStorage", nil)
	local shared = newNode("Shared", root)
	buildTree(SHARED_DIR, shared)
	local cache: { [any]: any } = {}
	local loading: { [any]: boolean } = {}

	local function req(node: any): any
		local i = if type(node) == "table" then info[node] else nil
		if i == nil or i.source == nil then
			error("require expects a module under Shared, got " .. tostring(node), 2)
		end
		if cache[node] == nil then
			if loading[node] then
				error("require cycle at " .. (i.path :: string), 2)
			end
			loading[node] = true
			local env = setmetatable({ script = node, require = req }, { __index = getfenv(1) :: any })
			local fn = luau.load(i.source :: string, { debugName = i.path, environment = env })
			cache[node] = fn()
			loading[node] = nil
		end
		return cache[node]
	end

	return shared, req
end

return loader
