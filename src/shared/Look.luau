--!strict
-- Look, mix and UI constants (lighting, colors, fog, mix levels, fonts).
-- Gameplay numbers live in Config.luau. Sections start empty; the shell fills them in.

local Look = {}

Look.Lighting = {} :: { [string]: any }
Look.Mix = {} :: { [string]: any }
Look.UI = {} :: { [string]: any }

return Look
