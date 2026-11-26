--!strict
-- Every sound the game plays, by name. Id 0 means "not available yet": the shell skips it
-- silently. Every nonzero id must be listed in audio/ids.json with its source, or the gate
-- fails (tools/lint/asset_ids.py).

export type SoundEntry = {
	id: number,
	volume: number?,
	looped: boolean?,
	spatial: boolean?,
	group: string?, -- mix group, see Look.Mix
}

local SoundRegistry = {}

SoundRegistry.entries = {} :: { [string]: SoundEntry }

function SoundRegistry.get(name: string): SoundEntry?
	return SoundRegistry.entries[name]
end

return SoundRegistry
