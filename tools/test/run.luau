--[[
Runs the specs (tests/**/*.spec.luau) outside Studio with Lune.

    lune run tools/test/run.luau [filter]

Run it from the project root. A spec returns `function(t, Shared)` and uses
`t.test(name, fn)`, `t.ok(cond, msg)` and `t.eq(actual, expected, msg)`.

It fakes just enough of Roblox for the pure shared modules: `Shared` and `script` are
fake instances built from the files under src/shared (folders nest, so
`script.Parent.Parent.Types` works from Core/entities), and `require` loads them.
Vector3, Color3 and CFrame come from Lune's Roblox library for the shell-side shared
modules (Look). Core itself must not need any of them.

The optional filter keeps only spec files whose path contains it, or tests whose name
contains it. Exit code is 1 on any failure.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local SHARED_DIR = "src/shared"
local TESTS_DIR = "tests"

-- Fake instances. Each node is an empty table; its data lives in `info` so a child named
-- like a field can never collide with it.
type NodeInfo = {
	name: string,
	parent: any,
	children: { [string]: any },
	path: string?, -- set for modules
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

-- Read the whole tree up front (file reads cannot happen inside a metamethod).
local function buildTree(dir: string, parent: any)
	for _, entry in fs.readDir(dir) do
		local path = dir .. "/" .. entry
		if fs.isDir(path) then
			buildTree(path, newNode(entry, parent))
		else
			local name = entry:match("^(.+)%.luau$")
			if name and not name:find("%.") then -- skip X.server.luau and X.client.luau
				newNode(name, parent, path, fs.readFile(path))
			end
		end
	end
end

local function baseEnv(): { [string]: any }
	local env = {
		Vector3 = roblox.Vector3,
		Color3 = roblox.Color3,
		CFrame = roblox.CFrame,
	}
	return setmetatable(env, { __index = getfenv(1) :: any })
end

-- A fresh tree and module cache per spec file, so module state never leaks between specs.
local function makeShared()
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
			local env = baseEnv()
			env.script = node
			env.require = req
			local fn = luau.load(i.source :: string, { debugName = i.path, environment = env })
			local result = fn()
			if result == nil then
				error((i.path :: string) .. " did not return a value", 2)
			end
			cache[node] = result
			loading[node] = nil
		end
		return cache[node]
	end

	return shared, req
end

local function listSpecs(dir: string, out: { string })
	if not fs.isDir(dir) then
		return
	end
	local entries = fs.readDir(dir)
	table.sort(entries)
	for _, entry in entries do
		local path = dir .. "/" .. entry
		if fs.isDir(path) then
			listSpecs(path, out)
		elseif entry:match("%.spec%.luau$") then
			table.insert(out, path)
		end
	end
end

local filter = process.args[1]
local specs: { string } = {}
listSpecs(TESTS_DIR, specs)

local passed, failed = 0, {}
for _, file in specs do
	local fileMatches = filter == nil or file:find(filter, 1, true) ~= nil
	local shared, req = makeShared()
	local env = baseEnv()
	env.require = req
	local ok, specFn = pcall(luau.load, fs.readFile(file), { debugName = file, environment = env })
	local t = {}
	function t.test(name: string, body: () -> ())
		if not fileMatches and not name:find(filter :: string, 1, true) then
			return
		end
		local ok2, err = pcall(body)
		if ok2 then
			passed += 1
		else
			table.insert(failed, file .. " > " .. name .. ": " .. tostring(err))
		end
	end
	function t.ok(cond: any, msg: string?)
		if not cond then
			error(msg or "expected true", 2)
		end
	end
	function t.eq(a: any, b: any, msg: string?)
		if a ~= b then
			error(string.format("%s: expected %s, got %s", msg or "eq", tostring(b), tostring(a)), 2)
		end
	end
	if not ok then
		table.insert(failed, file .. " did not load: " .. tostring(specFn))
	else
		local ok3, err = pcall(function()
			local entry = specFn()
			assert(type(entry) == "function", "spec must return function(t, Shared)")
			entry(t, shared)
		end)
		if not ok3 then
			table.insert(failed, file .. " crashed: " .. tostring(err))
		end
	end
end

for _, f in failed do
	print("  FAIL " .. f)
end
print(string.format("TESTS: %d passed, %d failed, %d spec files", passed, #failed, #specs))
process.exit(if #failed == 0 then 0 else 1)
