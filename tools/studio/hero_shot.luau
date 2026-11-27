-- M9 fixed shots for the hero models, run on the Client datamodel of this project's own
-- Studio window (execute_luau). Hides the UI, parks the camera, optionally spawns the
-- Watcher figure on the shore. Paste with SHOT set to one of the names below.
local SHOT = SHOT_NAME -- replaced before running: "boat", "lantern", "steeple", "shack", "tree", "watcher"
local Players = game:GetService("Players")
for _, g in Players.LocalPlayer.PlayerGui:GetChildren() do
	if g:IsA("ScreenGui") then
		g.Enabled = false
	end
end
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
local boat = workspace:FindFirstChild("DeadCalmBoat", true)
local hull = boat and boat.PrimaryPart
local shots = {
	boat = function()
		return hull.CFrame * Vector3.new(11, 7.5, -3), hull.CFrame * Vector3.new(0, 0.6, -1.5)
	end,
	lantern = function()
		return hull.CFrame * Vector3.new(2.6, 3.6, -4.2), hull.CFrame * Vector3.new(0, 2.6, -8.4)
	end,
	steeple = function()
		return Vector3.new(146, 8, 200), Vector3.new(170, 22, 252)
	end,
	shack = function()
		return Vector3.new(-34, 9, -452), Vector3.new(-52, 6, -486)
	end,
	tree = function()
		return Vector3.new(150, 9, -440), Vector3.new(176, 18, -505)
	end,
	watcher = function()
		local W = require(Players.LocalPlayer.PlayerScripts.Client.fx.Watcher)
		W.handle({ kind = "EntityCue", data = { pos = { x = 162, z = -478 } } })
		return Vector3.new(148, 7, -452), Vector3.new(162, 8, -478)
	end,
}
local from, at = shots[SHOT]()
cam.CFrame = CFrame.lookAt(from, at)
return SHOT .. " set"
