local Pathfinding = {}
Pathfinding.__index = Pathfinding

-- Services
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

-- ====== GRID NAVIGATION ======

local GridNav = {}
GridNav.__index = GridNav

local root2 = 1.41421356237
local DEFAULTS = {
	cellSize = 4,
	width = 200,
	depth = 200,
	origin = Vector3.new(0,50,0),
	scanHeight = 100,
	clearanceHeight = 5,
	agentRadius = 1.5,
	agentHeight = 5,
	maxStepHeight = 3,
	maxSlopeDeg = 35,
	allowDiagonals = true,
	includeTerrain = true,
	collisionBlacklist = {},
	walkableTag = nil,
	enableLongJumps = true,
	maxLongJumpGap = 14,
	maxLongJumpHeightDiff = 3,
	longJumpCostMultiplier = 1.8,
	losCheckOnWalkEdges = true,
	losCheckOnJumps = true,
}

local function degBetweenUp(normal)
	return math.deg(math.acos(math.clamp(normal:Dot(Vector3.new(0, 1, 0)), -1, 1)))
end

function GridNav.new(config)
	config = setmetatable(config or {}, {__index=DEFAULTS})
	local self = setmetatable({
		cfg = config,
		nodes = {},
		keys = {},
		specialEdges = {},
		occ = {},
		wCount = 0
	}, GridNav)
	self:_build()
	return self
end

function GridNav:_key(ix,iz) return ix..","..iz end
function GridNav:_worldAt(ix,iz)
	local c = self.cfg
	return Vector3.new(
		c.origin.X - c.width * 0.5 + ix*c.cellSize,
		c.origin.Y + c.scanHeight,
		c.origin.Z - c.depth * 0.5 + iz*c.cellSize
	)
end

function GridNav:_edgeIsClear(a,b)
	local y = math.max(a.Y,b.Y) + math.min(self.cfg.agentHeight * 0.8, 3)
	local p1,p2 = Vector3.new(a.X,y,a.Z), Vector3.new(b.X,y,b.Z)
	local dir = p2 - p1
	if dir.Magnitude < 0.001 then return true end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = self.cfg.collisionBlacklist
	return Workspace:Raycast(p1, dir, params)==nil
end

function GridNav:_hasLocalSupport(pos,norm,params)
	if degBetweenUp(norm)>self.cfg.maxSlopeDeg then return false end
	local r = math.max(self.cfg.agentRadius*0.9,0.75)
	local offsets = {Vector3.new(r,0,0), Vector3.new(-r,0,0), Vector3.new(0,0,r), Vector3.new(0,0,-r)}
	for _,off in ipairs(offsets) do
		local start = pos+off+Vector3.new(0,3,0)
		local sub = Workspace:Raycast(start,Vector3.new(0,-6,0),params)
		if not sub then return false end
		local dy = math.abs(sub.Position.Y-pos.Y)
		if dy>self.cfg.maxStepHeight then return false end
		if degBetweenUp(sub.Normal)>self.cfg.maxSlopeDeg then return false end
		if self.cfg.walkableTag then
			if sub.Instance:IsA("Terrain") then
				if not self.cfg.includeTerrain then return false end
			elseif not CollectionService:HasTag(sub.Instance,self.cfg.walkableTag) then return false end
		end
	end
	return true
end

function GridNav:_downcast(ix, iz, params)
	local start = self:_worldAt(ix,iz)
	return Workspace:Raycast(start,Vector3.new(0, -(self.cfg.scanHeight+200) ,0), params)
end

function GridNav:_scanCellFromResult(ix, iz, result, params)
	if not result then return nil end
	if self.cfg.walkableTag then
		if result.Instance:IsA("Terrain") then
			if not self.cfg.includeTerrain then return nil end
		elseif not CollectionService:HasTag(result.Instance,self.cfg.walkableTag) then return nil end
	elseif result.Instance:IsA("Terrain") and not self.cfg.includeTerrain then return nil end
	local footPos = result.Position + Vector3.new(0,0.5,0)
	if Workspace:Raycast(footPos,Vector3.new(0,self.cfg.clearanceHeight,0),params) then return nil end
	if not self:_hasLocalSupport(result.Position,result.Normal,params) then return nil end
	return footPos
end

function GridNav:_build()
	self.nodes, self.keys, self.specialEdges, self.occ, self.wCount = {}, {}, {}, {} ,0
	local ixMax = math.floor(self.cfg.width / self.cfg.cellSize)
	local izMax = math.floor(self.cfg.depth / self.cfg.cellSize)
	
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = self.cfg.collisionBlacklist

	for ix=0,ixMax do
		for iz=0, izMax do
			local key = self:_key(ix, iz)
			local result = self:_downcast(ix, iz ,params)
			self.occ[key] = result ~= nil
			local pos = self:_scanCellFromResult(ix, iz, result,params)
			if pos then
				self.nodes[key] = {pos=pos, walkable=true, ix=ix,iz=iz}
				self.wCount += 1
			else
				self.nodes[key] = {pos=nil, walkable=false, ix=ix,iz=iz}
			end
			table.insert(self.keys, key)
		end
	end

	if self.cfg.enableLongJumps then self:_addLongJumpEdges() end
end

-- // NEIGHORING NODES \\
local NEIGHBORS8 = {{1,0},{-1,0},{0,1},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1}}
local NEIGHBORS4 = {{1,0},{-1,0},{0,1},{0,-1}}

function GridNav:getNeighbors(key)
	local n = self.nodes[key]
	if not n or not n.walkable then return {} end
	local dirs = self.cfg.allowDiagonals and NEIGHBORS8 or NEIGHBORS4
	local list = {}
	for _,d in ipairs(dirs) do
		local nx, nz = n.ix+d[1], n.iz+d[2]
		local nkey=self:_key(nx,nz)
		local nn = self.nodes[nkey]
		if nn and nn.walkable then
			if math.abs(d[1]) + math.abs(d[2]) == 2 then
				local k1=self:_key(n.ix + d[1], n.iz)
				local k2=self:_key(n.ix ,n.iz + d[2])
				if not (self:isWalkable(k1) and self:isWalkable(k2)) then continue end
			end
			if self.cfg.losCheckOnWalkEdges and not self:_edgeIsClear(n.pos, nn.pos) then continue end
			table.insert(list, nkey)
		end
	end
	if self.specialEdges[key] then
		for _,e in ipairs(self.specialEdges[key]) do table.insert(list,e.toKey) end
	end
	return list
end

function GridNav:edgeCost(aKey,bKey)
	local sp = self.specialEdges[aKey]
	if sp then
		for _,e in ipairs(sp) do if e.toKey==bKey then return e.cost end
		end end
	local a,b = self.nodes[aKey],self.nodes[bKey]
	if not (a and b and a.walkable and b.walkable) then return math.huge end
	local dy = math.abs(a.pos.Y-b.pos.Y)
	local base = (a.ix~=b.ix and a.iz~=b.iz) and self.cfg.cellSize*root2 or self.cfg.cellSize
	return base + dy*0.75
end

function GridNav:getPos(key)
	local n = self.nodes[key]
	return n and n.pos or Vector3.new()
end

function GridNav:isWalkable(key)
	local n = self.nodes[key]
	return n and n.walkable or false
end

function GridNav:nearestKeyToWorld(pos)
	local ix = math.floor((pos.X-(self.cfg.origin.X-self.cfg.width*0.5))/self.cfg.cellSize+0.5)
	local iz = math.floor((pos.Z-(self.cfg.origin.Z-self.cfg.depth*0.5))/self.cfg.cellSize+0.5)
	local key = self:_key(ix,iz)
	if not self:isWalkable(key) then
		local best,bestDist
		for _,k in ipairs(self.keys) do
			if self:isWalkable(k) then
				local d = (self:getPos(k)-pos).Magnitude
				if not bestDist or d<bestDist then bestDist,best= d,k end
			end
		end
		return best
	end
	return key
end

local CARDINAL = {{1,0},{-1,0},{0,1},{0,-1}}
function GridNav:_findLandingAfterGap(fromNode,dx,dz)
	local step = self.cfg.cellSize
	local maxSteps = math.floor(self.cfg.maxLongJumpGap/step)
	local seenVoid = false
	for s=1,maxSteps do
		local nx,nz = fromNode.ix+dx*s, fromNode.iz+dz*s
		local k = self:_key(nx,nz)
		local n = self.nodes[k]
		local solid = self.occ[k]==true
		if solid and (not n or not n.walkable) then return nil end
		if n and n.walkable then
			if seenVoid then return n else return nil end
		else
			if not solid then seenVoid=true else return nil end
		end
	end
	return nil
end

function GridNav:_addLongJumpEdges()
	for _,keyA in ipairs(self.keys) do
		local a = self.nodes[keyA]
		if a.walkable then
			for _,dir in ipairs(CARDINAL) do
				local landing = self:_findLandingAfterGap(a,dir[1],dir[2])
				if landing then
					local dy = math.abs(landing.pos.Y-a.pos.Y)
					if dy <= self.cfg.maxLongJumpHeightDiff and 
						(not self.cfg.losCheckOnJumps or self:_edgeIsClear(a.pos,landing.pos)) then
						local dx = (landing.ix-a.ix)*self.cfg.cellSize
						local dz = (landing.iz-a.iz)*self.cfg.cellSize
						local dist = math.sqrt(dx*dx+dz*dz)
						self.specialEdges[keyA] = self.specialEdges[keyA] or {}
						table.insert(self.specialEdges[keyA], {toKey=self:_key(landing.ix,landing.iz),cost=dist*self.cfg.longJumpCostMultiplier,type="LongJump"})
					end
				end
			end
		end
	end
end

-- // A* PATHFINDING \\
local AStar = {}
AStar.__index = AStar

local Heap = {}
Heap.__index = Heap
function Heap.new() return setmetatable({arr={}},Heap) end
local function swap(t,i,j) t[i],t[j]=t[j],t[i] end
function Heap:push(node,priority)
	local arr=self.arr
	table.insert(arr,{node=node,priority=priority})
	local i=#arr
	while i>1 do
		local p=math.floor(i/2)
		if arr[p].priority<=arr[i].priority then break end
		swap(arr,i,p)
		i=p
	end
end
function Heap:pop()
	local arr=self.arr
	local n=#arr
	if n==0 then return nil end
	swap(arr,1,n)
	local item=table.remove(arr,n)
	local i=1
	while true do
		local l,r=i*2,i*2+1
		local s=i
		if l<=#arr and arr[l].priority<arr[s].priority then s=l end
		if r<=#arr and arr[r].priority<arr[s].priority then s=r end
		if s==i then break end
		swap(arr,i,s)
		i=s
	end
	return item.node
end
function Heap:empty() return #self.arr==0 end

local function euclidean(a,b)
	local dx,dy,dz = a.X-b.X,a.Y-b.Y,a.Z-b.Z
	return math.sqrt(dx*dx+dy*dy+dz*dz)
end

function AStar.find(startKey,goalKey,getNeighbors,getPos,costFn,heuristicFn)
	heuristicFn = heuristicFn or euclidean
	local open = Heap.new()
	local cameFrom, gScore = {},{}
	local startPos, goalPos = getPos(startKey), getPos(goalKey)
	gScore[startKey] = 0
	open:push(startKey,heuristicFn(startPos,goalPos))
	local closed = {}
	while not open:empty() do
		local current = open:pop()
		if current==goalKey then
			local path = {}
			local c=current
			while c do path[#path+1]=c;c=cameFrom[c] end
			for i=1,#path//2 do path[i],path[#path-i+1]=path[#path-i+1],path[i] end
			return path
		end
		closed[current] = true
		local currentG = gScore[current]
		for _,nbr in ipairs(getNeighbors(current)) do
			if not closed[nbr] then
				local tentative = currentG + costFn(current,nbr)
				if tentative<(gScore[nbr] or math.huge) then
					cameFrom[nbr]=current
					gScore[nbr]=tentative
					open:push(nbr,tentative+heuristicFn(getPos(nbr),goalPos))
				end
			end
		end
	end
	return nil
end

-- // MODULE INTERFACE \\
function Pathfinding.newGrid(config)
	local nav = GridNav.new(config)
	local lastPaths = {}
	return setmetatable({
		nav = nav,
		lastPaths = lastPaths,
		findPath = function(startPos,endPos,id)
			-- reuse if path still valid
			local key = id or tostring(startPos)
			if lastPaths[key] then
				local last = lastPaths[key]
				local dist = (last.endPos-endPos).Magnitude
				if dist<1 then return last.points end
			end
			local startKey,goalKey = nav:nearestKeyToWorld(startPos), nav:nearestKeyToWorld(endPos)
			local pathKeys = AStar.find(startKey,goalKey,function(k) return nav:getNeighbors(k) end,function(k) return nav:getPos(k) end,function(a,b) return nav:edgeCost(a,b) end)
			local points = {}
			if pathKeys then for _,k in ipairs(pathKeys) do table.insert(points,nav:getPos(k)) end end
			lastPaths[key] = {points=points,endPos=endPos}
			return points
		end
	},{__index=Pathfinding})
end

return Pathfinding
