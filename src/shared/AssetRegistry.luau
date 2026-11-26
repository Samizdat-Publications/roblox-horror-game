--!strict
-- Every uploaded or Creator Store asset (meshes, textures, decals, models), by name.
-- Id 0 means "not available yet": the shell skips it silently. Every nonzero id must be
-- listed in art/ids.json with its source, or the gate fails (tools/lint/asset_ids.py).

export type AssetEntry = {
	id: number,
	kind: string?, -- "Mesh", "Texture", "Decal", "Model"
}

local AssetRegistry = {}

AssetRegistry.entries = {} :: { [string]: AssetEntry }

function AssetRegistry.get(name: string): AssetEntry?
	return AssetRegistry.entries[name]
end

return AssetRegistry
