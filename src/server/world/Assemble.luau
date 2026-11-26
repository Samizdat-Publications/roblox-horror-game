--!strict
-- Builds the world from the world modules. No requires and no services, so the Lune tool
-- tools/shell/world_count.luau can run the exact same build outside Studio.
--
-- ctx (built by WorldBuilder, or by the Lune tool):
--   cfg      Config (Config.Lake drives everything)
--   look     Look (palette, light values)
--   parts    world/Parts
--   Rng      Core.Rng module
--   rng      Core.Rng state for the world seed; each module gets its own fork
--   warnings { string }  appended to on anything odd
--   anchors  { [string]: any }  named parts other services need (radio, beacon, ...)
--   parent   set per module to that module's Folder

export type Result = {
	root: Folder,
	partCount: number,
	perModule: { [string]: number },
	anchors: { [string]: any },
	warnings: { string },
}

local Assemble = {}

Assemble.ROOT_NAME = "DeadCalmWorld"

local function countParts(inst: Instance): number
	local n = 0
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

function Assemble.build(ctx: any, modules: { any }): Result
	local root = Instance.new("Folder")
	root.Name = Assemble.ROOT_NAME
	ctx.parts.group = "World"
	local perModule = {}
	for _, m in modules do
		local folder = Instance.new("Folder")
		folder.Name = m.name
		folder.Parent = root
		local mctx = table.clone(ctx)
		mctx.parent = folder
		mctx.rng = ctx.Rng.fork(ctx.rng, "world:" .. m.name)
		m.build(mctx)
		perModule[m.name] = countParts(folder)
	end
	ctx.parts.group = "Default"
	return {
		root = root,
		partCount = countParts(root),
		perModule = perModule,
		anchors = ctx.anchors,
		warnings = ctx.warnings,
	}
end

Assemble.countParts = countParts

return Assemble
