# PathForge
A custom grid-based pathfinding module made for Roblox, powered by A* search. Supports walls, clearance checks, and dynamic obstacles.
A high-performance, fully customizable pathfinding module.

---

## ✨ Features
- **Custom Grid-Based Pathfinding** – A* search implementation for precise navigation.  
- **Dynamic Obstacle Handling** – Generates grids that adapt to walls and environment changes.  
- **Configurable Agents** – Supports different clearance heights, radii, and mobility settings.  
- **Wall-Hugging Fix** – Improved navigation logic to prevent NPCs from getting stuck along walls.  
- **Developer-Friendly API** – Easily plug into NPC movement, AI behaviors, or custom gameplay systems.  

---

## 📝 Configuration Notes

- **origin / width / depth: These define the scan box on X/Z. Make sure both the start and the goal are inside this box. If the goal is outside, the “nearest walkable” fallback may choose something unexpected.**
- **cellSize: Smaller = more accurate, slower. Larger = faster, coarser.**

- **agentRadius / clearanceHeight: Used to keep space around/above the agent.**

- **collisionBlacklist: Instances to ignore for ray/overlap (e.g., your NPC’s own parts).**

- **walkableTag: If set, only parts with this tag (and optionally Terrain) will be considered floors.**

- **enableLongJumps: Creates special links across gaps; simple and experimental.**

---

## ⚠️ Current Limitations / TODO
- Incomplete parkour abilities (no climbing, vaulting, or wall-hopping yet).
- `agentWidth` is defined in config but **not yet implemented**.
- Long-jump system may be unstable in complex maps.
- Optimizations for very large grids still in progress.

---

## 🚀 Installation
1. Add the module to **ReplicatedStorage** (or your preferred location).  **
2. Require the module in your server/client script:

---

## 🛠️ Usage
```lua
local GridNav = require(game.ReplicatedStorage.GridNav)

-- Create a configuration
local config = {
	cellSize = 1,
	width = 100,
	depth = 100,
	origin = Vector3.new(0, 0, 0),
	scanHeight = 50,
	clearanceHeight = 5,
	agentRadius = 1.5,
	agentHeight = 5,
	agentWidth = 4, -- not implemented yet
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

-- Create a grid
local grid = GridNav.new(config)

-- Find a path
local path = grid:findPath(startPosition, goalPosition)

if path then
	print("Found path with " .. #path .. " waypoints")
else
	print("No valid path found")
end
