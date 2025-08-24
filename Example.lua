local Pathfinding = require(game.ReplicatedStorage:WaitForChild("CustomPathfindingModule"))

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local pval = 0
local oldvis = {}

local npc = workspace.NPC -- PUT YOUR NPC HERE!!
local hum : Humanoid = npc.Humanoid
local root : BasePart = npc.HumanoidRootPart

local function followPath(npc : BasePart, path, speed)
	pval += 1 local oldpval = pval
	speed = speed or 16
	
	for i,v in oldvis do v:Destroy() end
	table.clear(oldvis)
	
	task.spawn(function()
		for i, point in ipairs(path) do
			local visual = Instance.new("Part")
			visual.Size = Vector3.new(0.5,0.5,0.5)
			visual.CanCollide = false
			visual.CanTouch = false
			visual.CanQuery = false
			visual.Position = point
			visual.Anchored = true
			visual.Material = Enum.Material.Neon
			visual.BrickColor = BrickColor.new("Lime green")
			visual.Parent = workspace

			table.insert(oldvis, visual)

			task.wait(0.01)
		end
	end)
	
	local stucktick = tick()
	
	local reached = false
	local lastcon = hum.MoveToFinished:Connect(function()
		reached = true
	end)
	
	for i, point in ipairs(path) do
		stucktick = tick()
		reached = false
		
		while not reached and pval == oldpval do
			if tick() - stucktick > 1 then hum:MoveTo(root.Position + -root.CFrame.LookVector * 10) task.wait(0.2) return end
			
			RunService.Heartbeat:Wait()
			hum:MoveTo(point)
		end
	end
	
	lastcon:Disconnect()
end

local mult = 2

local function PathfindTo(targetpos : Vector3)
	local distance = (targetpos - root.Position).Magnitude
	local GRID_CONFIG = {
		cellSize = 2,
		width = distance * mult,
		depth = distance * mult,
		origin = root.Position,
		scanHeight = 50,
		clearanceHeight = 5,
		agentRadius = 1.5,
		agentHeight = 5,
		agentWidth = 4,
		maxStepHeight = 3,
		maxSlopeDeg = 35,
		allowDiagonals = true,
		includeTerrain = true,
		collisionBlacklist = {},
		enableLongJumps = true,
		maxLongJumpGap = 14,
		maxLongJumpHeightDiff = 3,
		longJumpCostMultiplier = 1.8,
		losCheckOnWalkEdges = true,
		losCheckOnJumps = true,
	}
	
	if GRID_CONFIG.width > 150 then
		warn("LARGE GRID CONFIGS WILL CAUSE MAJOR LAG!")
		warn("STOPPING PATHFINDING")
		mult = 1
	end
	
	-- CREATE GRID NAVIGATION
	local nav = Pathfinding.newGrid(GRID_CONFIG)

	-- CALCULATE PATH
	local pathPoints = nav.findPath(root.Position, targetpos)

	if pathPoints and #pathPoints > 0 then
		print("Path found! Moving NPC...")
		followPath(npc, pathPoints, 16)
		
		mult = 2
	else
		mult += 1
		warn("No path found!")
	end
end

while true do
	PathfindTo(workspace.Goal.Position)
	task.wait()
end
