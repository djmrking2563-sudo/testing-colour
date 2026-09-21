local LocalPlayer = game.Players.LocalPlayer
local SELL_TRESHOLD = getgenv().SellTreshold
if type(SELL_TRESHOLD) ~= "number" or not (SELL_TRESHOLD > 0) then SELL_TRESHOLD = 2500000 end
local SellTreshold = (type(getgenv().SellTreshold) == "number" and getgenv().SellTreshold > 0) and getgenv().SellTreshold or 200
local Depth = getgenv().Depth or 205
getgenv().SellTreshold = SELL_TRESHOLD
getgenv().Depth = Depth
-- (SellArea removed — sell pads are per-area now)
local recovering = false
local areaTransit = false
local rebirthDigging = false
local collapseRecovering = false
local areaRunId = 0
local areaPhaseText = "off"
local lastAreaName = nil
local lastAreaTrackAt = 0
local Areas = {
	{ name = "Cyber",   moveTo = "CyberSpawn",  spawn = Vector3.new(21, 15, 30139),   walkEnd = Vector3.new(19, 13, 30051),   mine = Vector3.new(22, 12, 30037),   bridgeSize = Vector3.new(10, 1, 100), bridgePos = Vector3.new(21, 9.5, 30095) },
	{ name = "Spawn",   moveTo = nil,           spawn = Vector3.new(-86, 14, -12),    walkEnd = Vector3.new(-36, 14, -3),     mine = Vector3.new(-17, 12, -3) },
	{ name = "Space",   moveTo = "SpaceSpawn",  spawn = Vector3.new(-81, 15, 1569),   walkEnd = Vector3.new(-27, 12, 1568),   mine = Vector3.new(-15, 12, 1568) },
	{ name = "Candy",   moveTo = "CandySpawn",  spawn = Vector3.new(-27, 15, 3011),   walkEnd = Vector3.new(2, 13, 3009),     mine = Vector3.new(11, 12, 3010) },
	{ name = "Toy",     moveTo = "ToySpawn",    spawn = Vector3.new(10, 15, 5719),    walkEnd = Vector3.new(11, 13, 5699),    mine = Vector3.new(11, 12, 5687) },
	{ name = "Food",    moveTo = "FoodSpawn",   spawn = Vector3.new(61, 14, 8675),    walkEnd = Vector3.new(59, 13, 8719),    mine = Vector3.new(56, 12, 8732) },
	{ name = "Dino",    moveTo = "DinoSpawn",   spawn = Vector3.new(12, 15, 10581),   walkEnd = Vector3.new(12, 13, 10552),   mine = Vector3.new(14, 12, 10539) },
	{ name = "Sea",     moveTo = "SeaSpawn",    spawn = Vector3.new(14, 12, 10539),   walkEnd = Vector3.new(17, 13, 11969),   mine = Vector3.new(18, 12, 11949) },
	{ name = "Beach",   moveTo = "BeachSpawn",  spawn = Vector3.new(19, 14, 14437),   walkEnd = Vector3.new(15, 13, 14374),   mine = Vector3.new(15, 12, 14357) },
	{ name = "Cavern",  moveTo = "CavernSpawn", spawn = Vector3.new(19, 15, 18461),   walkEnd = Vector3.new(20, 13, 18400),   mine = Vector3.new(21, 12, 18382) },
		{ name = "MagicForest", moveTo = nil,       spawn = Vector3.new(15, 15, 22461),   walkEnd = Vector3.new(16, 13, 22420),   mine = Vector3.new(17, 12, 22409) },
}



	
local function DetectArea()
	local h = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	if not h then return nil end
	local best, bestd = nil, math.huge
	for _, a in ipairs(Areas) do
		local dx = h.Position.X - a.mine.X
		local dz = h.Position.Z - a.mine.Z
		local d = dx * dx + dz * dz
		if d < bestd then bestd = d best = a end
	end
	return best
end
local function FindAreaByName(name)
	if type(name) ~= "string" then return nil end
	for _, a in ipairs(Areas) do if a.name == name then return a end end
	return nil
end
local function TrackArea(force)
	if collapseRecovering or areaTransit then return end
	local now = os.clock()
	if not force and now - lastAreaTrackAt < 5 then return end
	lastAreaTrackAt = now
	pcall(function()
		local a = DetectArea()
		if a then lastAreaName = a.name end
	end)
end

local function Split(s, delimiter)
	local result = {};
	for match in (s..delimiter):gmatch("(.-)"..delimiter) do
		table.insert(result, match);
	end
	return result;
end

local function findDepthLabel()
	local sg = LocalPlayer.PlayerGui:FindFirstChild("ScreenGui")
	if not sg then return nil end
	local candidates = {}
	pcall(function()
		local t1 = sg:FindFirstChild("TopInfoFrame")
		if t1 and t1:FindFirstChild("Depth") then table.insert(candidates, t1.Depth) end
		local t2 = sg:FindFirstChild("TopInfo")
		if t2 and t2:FindFirstChild("Depth") then table.insert(candidates, t2.Depth) end
		local deep = sg:FindFirstChild("Depth", true)
		if deep then table.insert(candidates, deep) end
	end)
	for _, lbl in ipairs(candidates) do
		if lbl and lbl.Text and tonumber((Split(tostring(lbl.Text), " "))[1]) then return lbl end
	end
	return candidates[1]
end

local function GetCurrentDepth()
	local ok, val = pcall(function()
		local DepthLabel = findDepthLabel()
		if not DepthLabel or not DepthLabel.Text then return nil end
		local parts = Split(tostring(DepthLabel.Text), " ")
		return tonumber(parts[1])
	end)
	if ok then return val end
	return nil
end

local Leaderstats = LocalPlayer:WaitForChild("leaderstats", 10)
local Rebirths = Leaderstats and Leaderstats:WaitForChild("Rebirths", 10)

print("Loading Mining Simulator GUI (WindUI)")
pcall(function()
	local OldGui = LocalPlayer.PlayerGui:FindFirstChild("Nice Flex But OK")
	if OldGui then OldGui:Destroy() end
end)
pcall(function()
	if getgenv().__MS_Toggles then
		for k in pairs(getgenv().__MS_Toggles) do getgenv().__MS_Toggles[k] = false end
	end
	if getgenv().__MS_WindUIWindow then getgenv().__MS_WindUIWindow:Destroy() end
	getgenv().__MS_WindUIWindow = nil
	getgenv().__MS_BackpackRunning = false
	getgenv().__MS_ToolsRunning = false
	game:GetService("RunService"):UnbindFromRenderStep("MS_AutoRebirth")
end)

local Remote = nil
local function EnsureRemote()
	if Remote then return Remote end
	-- Priority 1: getsenv method (works in this game)
	pcall(function()
		local ClientScript = LocalPlayer.PlayerGui:FindFirstChild("ScreenGui") and LocalPlayer.PlayerGui.ScreenGui:FindFirstChild("ClientScript")
		if ClientScript and getsenv and getupvalue then
			local Data = getsenv(ClientScript).updatePasses
			local Values = getupvalue(Data, 8)
			if Values and typeof(Values["RemoteEvent"]) == "Instance" and Values["RemoteEvent"]:IsA("RemoteEvent") then
				Remote = Values["RemoteEvent"]
				print("[MS] Remote found via getsenv")
				return Remote
			end
		end
	end)
	-- Priority 2: Network InvokeServer (fallback)
	pcall(function()
		local Network = game:GetService("ReplicatedStorage"):WaitForChild("Network", 5)
		if Network then
			local a, b = Network:InvokeServer()
			if typeof(a) == "Instance" and a:IsA("RemoteEvent") then
				Remote = a
			elseif typeof(b) == "Instance" and b:IsA("RemoteEvent") then
				Remote = b
			end
		end
	end)
	return Remote
end
EnsureRemote()
pcall(function()
	local VU = game:GetService("VirtualUser")
	LocalPlayer.Idled:Connect(function()
		VU:CaptureController()
		VU:ClickButton2(Vector2.new())
	end)
	print("[MS] Anti-AFK on")
end)

local Toggles = getgenv().__MS_Toggles or {
	FastMine = false,
	AutoMine = false,
	AutoBackpack = false,
	AutoTools = false,
	AutoRebirth = false,
	RebirthOnly = false,
	LimitDepth = false,
	SVSell = false
}
for k in pairs(Toggles) do Toggles[k] = false end
getgenv().__MS_Toggles = Toggles
getgenv().__MS_Gen = (getgenv().__MS_Gen or 0) + 1
local myGen = getgenv().__MS_Gen
local buyPause, buyPauseAt = false, 0
local lastMineSpot = nil
local sellTrip = false
local sellDbgAt = 0

local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 10)
local GameGui = PlayerGui:WaitForChild("ScreenGui", 10)
local StatsFrame2 = GameGui and GameGui:WaitForChild("StatsFrame", 10)
local InventoryAmount = StatsFrame2 and StatsFrame2:FindFirstChild("Inventory") and StatsFrame2.Inventory:FindFirstChild("Amount")
local CoinsAmount = Leaderstats and Leaderstats:WaitForChild("Coins", 10)

local function GetCoinsAmount()
	if not CoinsAmount then return 0 end
	local Amount = tostring(CoinsAmount.Value)
	Amount = Amount:gsub(',', '')
	return tonumber(Amount) or 0
end

local function resolveInventoryLabel()
	-- always re-find — never trust a cached reference
	local sg = LocalPlayer.PlayerGui:FindFirstChild("ScreenGui")
	if not sg then return nil end

	-- prefer StatsFrame (main), then StatsFrame2 (secondary)
	for _, frameName in ipairs({"StatsFrame", "StatsFrame2"}) do
		local sf = sg:FindFirstChild(frameName)
		if sf then
			local inv = sf:FindFirstChild("Inventory")
			local amt = inv and inv:FindFirstChild("Amount")
			if amt and amt.Text and amt.Text:find("/") then
				InventoryAmount = amt  -- refresh cache
				return amt
			end
		end
	end
	return nil
end

local function GetInventoryAmount()
	local lbl = resolveInventoryLabel()
	if not lbl or not lbl.Text then return 0, 0 end
	-- handle commas, spaces, and any non-digit noise
	local cleaned = tostring(lbl.Text):gsub(",", ""):gsub("%s+", "")
	-- read the current count from BEFORE the slash (works even if max is "inf")
	local curStr = cleaned:match("([%d]+)/")
	-- read max only if it's actually digits
	local maxStr = cleaned:match("/([%d]+)")
	local cur = tonumber(curStr) or 0
	local max = tonumber(maxStr)
	-- if max isn't a number (e.g. "inf" with infinite backpack), use SELL_TRESHOLD or huge fallback
	if not max then
		max = SELL_TRESHOLD or math.huge
	end
	return cur, max
end


-- ===== PER-AREA SELL PADS =====
local SELL_PADS = {
	Cyber       = Vector3.new(56, 14, 30176),
	-- Add more areas as you find their pads:
	-- Spawn    = Vector3.new(...),
	-- Space    = Vector3.new(...),
	-- Candy    = Vector3.new(...),
	-- Toy      = Vector3.new(...),
	-- Food     = Vector3.new(...),
	-- Dino     = Vector3.new(...),
	-- Sea      = Vector3.new(...),
	-- Beach    = Vector3.new(...),
	-- Cavern   = Vector3.new(...),
	-- MagicForest = Vector3.new(...),
}

local function GetSellPadPos()
	if lastAreaName and SELL_PADS[lastAreaName] then
		return SELL_PADS[lastAreaName]
	end
	return Vector3.new(-116, 13, 38)
end

local function HopOntoSellPad()
	local char = LocalPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp then
		return false
	end

	-- only teleport if the backpack is actually full (or past sell threshold)
	local curInv, curMax = GetInventoryAmount()
	local triggerAt = SELL_TRESHOLD or curMax
	if not curInv or not curMax or curMax <= 0 or curInv < triggerAt then
		return false
	end

	sellTrip = true

	local ok, err = pcall(function()
		local padPos = GetSellPadPos()

		hrp.Anchored = true
		hrp.CFrame = CFrame.new(padPos)
		task.wait(0.5)
		hrp.Anchored = false
		task.wait(0.3)

		local t0 = os.clock()
		local dir = 1
		local step = 1.5
		local interval = 0.12

		while os.clock() - t0 < 4 do
			local c = LocalPlayer.Character
			local h = c and c:FindFirstChild("HumanoidRootPart")
			if not h then break end

			local offset = Vector3.new(step * dir, 0, 0)
			dir = -dir

			h.Anchored = true
			h.CFrame = CFrame.new(padPos) + offset
			task.wait(interval)
			h.Anchored = false
			task.wait(0.05)

			local cur = select(1, GetInventoryAmount())
			if cur == 0 then break end
		end

		local c2 = LocalPlayer.Character
		local h2 = c2 and c2:FindFirstChild("HumanoidRootPart")
		if h2 then
			h2.Anchored = true
			h2.CFrame = CFrame.new(padPos)
			task.wait(0.2)
			h2.Anchored = false
		end
	end)

			if not ok then
		print("[MS] HopOntoSellPad error: " .. tostring(err))
	end

	sellTrip = false
	return true
end
-- ===== END SELL PADS =====

local function StartAutoMine()
	-- 🔧 Reset stuck state
	pcall(function()
		areaRunId = areaRunId + 1
		areaTransit = false
		recovering = false
		collapseRecovering = false
		sellTrip = false

		local char = LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hrp then hrp.Anchored = false end
		if hum then hum.WalkSpeed = 16; hum.JumpPower = 50 end

		local bridge = workspace:FindFirstChild("MS_AreaBridge")
		if bridge then bridge:Destroy() end
	end)



	-- ⛏️ Then mine
	task.spawn(function()
		while Toggles["AutoMine"] do
			if areaTransit or recovering or collapseRecovering then task.wait(0.3)
			elseif buyPause then
				if os.clock() - buyPauseAt > 8 then buyPause = false else task.wait(0.3) end
			else
			if not Remote then EnsureRemote() end
			if Remote then
				local Character = LocalPlayer.Character
				local HumanoidRootPart = Character and Character:FindFirstChild("HumanoidRootPart")
				if HumanoidRootPart then
					local currentDepth = Toggles["LimitDepth"] and GetCurrentDepth() or nil
					if currentDepth == nil or currentDepth < Depth then
	local regionMin = HumanoidRootPart.CFrame + Vector3.new(-1,-10,-1)
	local regionMax = HumanoidRootPart.CFrame + Vector3.new(1,0,1)
	local region = Region3.new(regionMin.Position, regionMax.Position)
	local parts = workspace:FindPartsInRegion3WithWhiteList(region, {game.Workspace.Blocks}, 10)
						for _, block in pairs(parts) do
							if not Toggles["AutoMine"] then break end
							if areaTransit or recovering or collapseRecovering then break end
							Remote:FireServer("MineBlock",{{block.Parent}})
							task.wait()
						end
						if #parts > 0 then lastMineSpot = HumanoidRootPart.Position TrackArea() end
					else
						task.wait(0.5)
					end
				end
			else
				task.wait(1)
			end
			task.wait()
			end
		end
	end)
end

local function StartFastMine()
	task.spawn(function()
		while Toggles["FastMine"] do
			if areaTransit or recovering or collapseRecovering then task.wait(0.3)
			elseif buyPause then
				if os.clock() - buyPauseAt > 8 then buyPause = false else task.wait(0.3) end
			else
			if not Remote then EnsureRemote() end
			if Remote then
				local Character = LocalPlayer.Character
				local HumanoidRootPart = Character and Character:FindFirstChild("HumanoidRootPart")
				if HumanoidRootPart then
					local minp = HumanoidRootPart.CFrame.Position - Vector3.new(5, 5, 5)
					local maxp = HumanoidRootPart.CFrame.Position + Vector3.new(5, 5, 5)
					local region = Region3.new(minp, maxp)
					local parts = workspace:FindPartsInRegion3WithWhiteList(region, {game.Workspace.Blocks}, 50)
						for _, block in ipairs(parts) do
							if not Toggles["FastMine"] then break end
							if areaTransit or recovering or collapseRecovering then break end
							Remote:FireServer("MineBlock", {{block.Parent}})
							task.wait()
						end
						if #parts > 0 then lastMineSpot = HumanoidRootPart.Position TrackArea() end
					end
			else
				task.wait(1)
			end
			task.wait()
			end
		end
	end)
end

local svSellLoopGen = 0
local function StartSVSell()
	svSellLoopGen = svSellLoopGen + 1
	local gen = svSellLoopGen
	task.spawn(function()
		print("[MS] SVSell started")
		while getgenv().__MS_Gen == myGen do
			local ok, err = pcall(function()
				if not Toggles["SVSell"] then task.wait(0.5) return end
				if not Remote then EnsureRemote() end
				if not Remote then task.wait(1) return end
				local curInv, curMax = GetInventoryAmount()
				if not curMax or curMax <= 0 then task.wait(0.5) return end
				local triggerAt = SELL_TRESHOLD or curMax
				if curInv >= triggerAt then
					local Character = LocalPlayer.Character
					local HumanoidRootPart = Character and Character:FindFirstChild("HumanoidRootPart")
					if HumanoidRootPart then
						local SavedLocation = HumanoidRootPart.CFrame
						local SavedText = InventoryAmount and InventoryAmount.Text or ""
						local sellStartTime = os.clock()
						while InventoryAmount and InventoryAmount.Text == SavedText
							and Toggles["SVSell"]
							and os.clock() - sellStartTime < 15
						do
							HumanoidRootPart.CFrame = CFrame.new(-116, 13, 38)
							Remote:FireServer("SellItems", {{}})
							task.wait(0.1)
						end
						HumanoidRootPart.Anchored = true
						HumanoidRootPart.CFrame = SavedLocation
						task.wait(0.1)
						HumanoidRootPart.Anchored = false
						print("[MS] SVSell trip done: inv now " .. tostring(select(1, GetInventoryAmount())) .. " coins " .. tostring(GetCoinsAmount()))
					end
				else
					if os.clock() - sellDbgAt > 15 then
						sellDbgAt = os.clock()
						print("[MS] SVSell waiting: inv " .. tostring(curInv) .. "/" .. tostring(curMax))
					end
					task.wait(0.5)
				end
			end)
			if not ok then
				print("[MS] SVSell error: " .. tostring(err))
				task.wait(1)
			end
			task.wait()
		end
		print("[MS] SVSell off")
	end)
end

local rebirthRunId = 0
local rebirthPhaseText = "off"
rebirthDigging = false
local function StartAutoRebirth()
	pcall(function() game:GetService("RunService"):UnbindFromRenderStep("MS_AutoRebirth") end)
	game:GetService("RunService"):BindToRenderStep("MS_AutoRebirth", Enum.RenderPriority.Camera.Value, function()
		if not Toggles["AutoRebirth"] then return end
		if not Remote then EnsureRemote() end
		if Rebirths and Remote then
			while Toggles["AutoRebirth"] and GetCoinsAmount() >= (10000000 * (Rebirths.Value + 1)) do
				Remote:FireServer("Rebirth",{{}})
				task.wait()
			end
		end
	end)
	rebirthRunId = rebirthRunId + 1
	local run = rebirthRunId
	task.spawn(function()
		rebirthPhaseText = "waiting to mine..."
		while Toggles["AutoRebirth"] and run == rebirthRunId do
			if game:IsLoaded()
				and LocalPlayer.Character
				and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
				and LocalPlayer:FindFirstChild("leaderstats") then
				break
			end
			task.wait(0.5)
		end
		EnsureRemote()
		rebirthPhaseText = "digging to " .. tostring(Depth) .. "..."
		rebirthDigging = true
		local nilStreak = 0
		while Toggles["AutoRebirth"] and run == rebirthRunId do
			if buyPause then task.wait(0.3)
			elseif areaTransit or recovering or collapseRecovering then task.wait(0.3)
			else
				if not Remote then EnsureRemote() end
				if not Remote then task.wait(1)
				else
					local Character = LocalPlayer.Character
					local HumanoidRootPart = Character and Character:FindFirstChild("HumanoidRootPart")
					if not HumanoidRootPart then task.wait(0.5)
					else
						local depthNow = GetCurrentDepth()
						if depthNow ~= nil and depthNow >= Depth then break end
						if depthNow == nil then
							nilStreak = nilStreak + 1
							if nilStreak > 60 then break end
						end
						local regionMin = HumanoidRootPart.CFrame + Vector3.new(-1,-10,-1)
						local regionMax = HumanoidRootPart.CFrame + Vector3.new(1,0,1)
						local region = Region3.new(regionMin.Position, regionMax.Position)
						local parts = workspace:FindPartsInRegion3WithWhiteList(region, {game.Workspace.Blocks}, 10)
						for _, block in pairs(parts) do
							if not Toggles["AutoRebirth"] or run ~= rebirthRunId then break end
							if areaTransit or recovering or collapseRecovering then break end
							Remote:FireServer("MineBlock",{{block.Parent}})
							task.wait()
						end
					end
				end
				task.wait()
			end
		end
		rebirthDigging = false
		rebirthPhaseText = "mining + selling..."
		while Toggles["AutoRebirth"] and run == rebirthRunId do
			if buyPause then task.wait(0.3)
			elseif areaTransit or recovering or collapseRecovering then task.wait(0.3)
			else
				if not Remote then EnsureRemote() end
				if not Remote then task.wait(1)
				else
					local Character = LocalPlayer.Character
					local HumanoidRootPart = Character and Character:FindFirstChild("HumanoidRootPart")
					if HumanoidRootPart then
						local minp = HumanoidRootPart.CFrame.Position - Vector3.new(5, 5, 5)
						local maxp = HumanoidRootPart.CFrame.Position + Vector3.new(5, 5, 5)
						local region = Region3.new(minp, maxp)
						local parts = workspace:FindPartsInRegion3WithWhiteList(region, {game.Workspace.Blocks}, 50)
						for _, block in ipairs(parts) do
							if not Toggles["AutoRebirth"] or run ~= rebirthRunId then break end
							if areaTransit or recovering or collapseRecovering then break end
							Remote:FireServer("MineBlock", {{block.Parent}})
							task.wait()
						end
												if #parts > 0 then lastMineSpot = HumanoidRootPart.Position TrackArea() end
																																											if sellTrip then task.wait(0.3) else
	local curInv, curMax = GetInventoryAmount()
	local triggerAt = SELL_TRESHOLD or curMax
	if curInv and curMax and curMax > 0 and curInv >= triggerAt then
		local SavedPosition = HumanoidRootPart.CFrame
		local SavedText = InventoryAmount and InventoryAmount.Text or ""
		local sellStartTime = os.clock()
		-- sell at the universal pad -116, 13, 38 (same as SV Sell)
		while InventoryAmount and InventoryAmount.Text == SavedText
			and os.clock() - sellStartTime < 15
			and not recovering and not collapseRecovering
		do
			local c = LocalPlayer.Character
			local h = c and c:FindFirstChild("HumanoidRootPart")
			if not h then break end
			h.CFrame = CFrame.new(-116, 13, 38)
			Remote:FireServer("SellItems", {{}})
			task.wait(0.1)
		end
		local freshChar = LocalPlayer.Character
		local freshHRP = freshChar and freshChar:FindFirstChild("HumanoidRootPart")
		if freshHRP then
			freshHRP.Anchored = true
			freshHRP.CFrame = SavedPosition
			task.wait(0.1)
			freshHRP.Anchored = false
		end
		sellTrip = false
	end
end
					end
				end
				task.wait()
			end
		end
		rebirthPhaseText = "off"
	end)
end

local function StopAutoRebirth()
	rebirthRunId = rebirthRunId + 1
	rebirthPhaseText = "off"
	rebirthDigging = false
	pcall(function() game:GetService("RunService"):UnbindFromRenderStep("MS_AutoRebirth") end)
end

local rebirthOnlyRunning = false
local function StartRebirthOnly()
	if rebirthOnlyRunning then return end
	rebirthOnlyRunning = true
	task.spawn(function()
		while Toggles["RebirthOnly"] and getgenv().__MS_Gen == myGen do
			if not Remote then
				EnsureRemote()
				task.wait(1)
			else
				pcall(function()
					while Rebirths and Toggles["RebirthOnly"] and GetCoinsAmount() >= (10000000 * (Rebirths.Value + 1)) do
						Remote:FireServer("Rebirth",{{}})
						task.wait()
					end
				end)
				task.wait(0.1)
			end
		end
		rebirthOnlyRunning = false
	end)
end

local gearToolText, gearPackText = "?", "?"
local lastBoughtToolText, lastBoughtPackText = "none yet", "none yet"
local lastToolTryText = ""

local ShopCache = { tools = nil, packs = nil, at = 0 }
local function requireShopModules()
	local ok, res = pcall(function()
		local mods = game:GetService("Lighting"):FindFirstChild("Assets") and game.Lighting.Assets:FindFirstChild("Modules")
		if not mods then return nil end
		local sm = mods:FindFirstChild("ShopModule")
		local ps = nil
		pcall(function()
			local sg = LocalPlayer.PlayerGui:FindFirstChild("ScreenGui")
			local cs = sg and sg:FindFirstChild("ClientScript")
			local cl = cs and cs:FindFirstChild("Client")
			local psm = cl and cl:FindFirstChild("PlayerState")
			if psm then ps = require(psm) end
		end)
		return {
			shop = sm and require(sm) or nil,
			player = ps,
			backpack = mods:FindFirstChild("BackpackModule") and require(mods.BackpackModule) or nil,
		}
	end)
	if ok then return res end
	return nil
end

local function playerDataTable()
	local ok, pd = pcall(function()
		local sg = LocalPlayer.PlayerGui:FindFirstChild("ScreenGui")
		local cs = sg and sg:FindFirstChild("ClientScript")
		local cl = cs and cs:FindFirstChild("Client")
		local psm = cl and cl:FindFirstChild("PlayerState")
		if psm then
			local m = require(psm)
			if type(m) == "table" and type(m.coins) == "number" then return m end
		end
		return nil
	end)
	if ok and pd then return pd end
	local ok2, found = pcall(function()
		local sg = LocalPlayer.PlayerGui:FindFirstChild("ScreenGui")
		local cs = sg and sg:FindFirstChild("ClientScript")
		if not cs or not getsenv then return nil end
		local env = getsenv(cs)
		if type(env) ~= "table" then return nil end
		for _, v in pairs(env) do
			if type(v) == "table" and type(v.coins) == "number" and type(v.equipped) == "table" then
				return v
			end
		end
		return nil
	end)
	if ok2 then return found end
	return nil
end

local function shopPrice(entry, category)
	if type(entry) ~= "table" or entry[2] == "Group" then return nil end
	local base = tonumber(entry[2])
	if not base then return nil end
	local ok, price = pcall(function()
		local pd = playerDataTable()
		local rb = pd and tonumber(pd.rebirths) or (Rebirths and tonumber(Rebirths.Value) or 0) or 0
		local v
		if entry.fixedPrice or rb == 0 or category == "Rebirth Shop" then
			v = math.ceil(base)
		else
			v = math.ceil(base * ((rb + 1) / 2))
		end
		local mult = tonumber(LocalPlayer:GetAttribute("GuildShopPriceMultiplier")) or 1
		return math.max(0, math.ceil(v * mult))
	end)
	if ok then return price end
	return math.ceil(base)
end

local function entryName(e, idx)
	if type(e) == "string" then return e end
	if type(e) == "table" then
		if type(e[1]) == "string" then return e[1] end
		for _, k in ipairs({"name", "Name", "id", "Id"}) do
			if type(e[k]) == "string" then return e[k] end
		end
	end
	return "item" .. tostring(idx)
end

local function isOwned(entry, pd)
	local name = entryName(entry)
	local ok, owned = pcall(function()
		if not pd then return false end
		for _, list in ipairs({pd.ownedItems, pd.permanentItems}) do
			if type(list) == "table" then
				for _, n in ipairs(list) do if n == name then return true end end
			end
		end
		if type(entry) == "table" and type(entry[3]) == "table" and pd.ownedPasses then
			if pd.ownedPasses[entry[3][2]] then return true end
		end
		return false
	end)
	return ok and owned or false
end

local function discoverShop()
	if (ShopCache.tools or ShopCache.packs) and os.clock() - ShopCache.at < 60 then return ShopCache end
	pcall(function()
		local m = requireShopModules()
		local sm = m and m.shop
		if type(sm) == "table" then
			local function looksLikeShopRow(e)
				if type(e) ~= "table" then return type(e) == "string" end
				if type(e[1]) ~= "string" or e[1] == "" then return false end
				return tonumber(e[2]) ~= nil or e[2] == "Group" or type(e[3]) == "table"
			end
			local function validList(t)
				if type(t) ~= "table" or #t <= 5 then return false end
				local good, checked = 0, 0
				for i = 1, math.min(#t, 20) do
					checked = checked + 1
					if looksLikeShopRow(t[i]) then good = good + 1 end
				end
				return checked > 0 and good / checked >= 0.7
			end
			local tools, packs = sm.Tools, sm.Backpack
			if validList(tools) then ShopCache.tools = tools else ShopCache.tools = nil end
			if validList(packs) then ShopCache.packs = packs else ShopCache.packs = nil end
		end
		ShopCache.at = os.clock()
		pcall(function()
			if not ShopCache._dumped then
				ShopCache._dumped = true
				local m2 = requireShopModules()
				local keys = {}
				if m2 and type(m2.shop) == "table" then
					for k in pairs(m2.shop) do table.insert(keys, tostring(k)) end
				end
				print("[MS] ShopModule keys: " .. table.concat(keys, ","))
				for _, kn in ipairs({"Tools", "Backpack"}) do
					local t = m2 and m2.shop and m2.shop[kn]
					print("[MS] " .. kn .. ": type=" .. type(t) .. " len=" .. tostring(t and #t or 0))
					if type(t) == "table" then
						for i = 1, math.min(3, #t) do
							local e = t[i]
							print("[MS] " .. kn .. "[" .. i .. "] type=" .. type(e) .. " [1]=" .. tostring(type(e) == "table" and e[1] or e) .. " [2]=" .. tostring(type(e) == "table" and e[2] or "-"))
						end
					end
				end
				local pd = playerDataTable()
				print("[MS] playerData: " .. tostring(pd ~= nil) .. " equipped=" .. tostring(pd and pd.equipped and table.concat(pd.equipped, "|") or "?"))
			end
		end)
	end)
	return ShopCache
end

local bestToolName
local function ownedToolIndex(shop)
	local ok, idx = pcall(function()
		local pd = playerDataTable()
		local cur = pd and pd.equipped and pd.equipped[3]
		if type(cur) ~= "string" or cur == "" then
			cur = bestToolName()
			if cur == "?" then return 0 end
		end
		if shop then
			for i, e in ipairs(shop) do
				if entryName(e, i) == cur then return i end
			end
		end
		return 0
	end)
	return (ok and idx) or 0
end

local function ownedPackIndex(shop)
	local ok, idx = pcall(function()
		if not shop then return 0 end
		local pd = playerDataTable()
		local cur = pd and pd.equipped and pd.equipped[1]
		if type(cur) == "string" and cur ~= "" then
			for i, e in ipairs(shop) do
				if entryName(e, i) == cur then return i end
			end
		end
		return 0
	end)
	return (ok and idx) or 0
end

local refusedBuy = {}
local function bestBuy(shop, ownedIdx, startIdx, coins, category)
	if type(shop) ~= "table" or #shop == 0 then return nil, "NOSHOP" end
	local pd = playerDataTable()
	local best, cheapestMissing = nil, nil
	for i = math.max(ownedIdx + 1, startIdx or 1), #shop do
		if not refusedBuy[category .. "#" .. i] and not isOwned(shop[i], pd) then
			local price = shopPrice(shop[i], category)
			if price ~= nil then
				if not cheapestMissing then cheapestMissing = price end
				if price <= coins then best = i end
			end
		end
	end
	if best then return best, "OK" end
	if cheapestMissing and cheapestMissing > coins then return nil, "POOR" end
	return nil, "MAX"
end

local function toolSignature()
	local ok, sig = pcall(function()
		local names = {}
		local bp = LocalPlayer:FindFirstChild("Backpack")
		if bp then for _, t in pairs(bp:GetChildren()) do if t:IsA("Tool") then table.insert(names, t.Name) end end end
		local ch = LocalPlayer.Character
		if ch then for _, t in pairs(ch:GetChildren()) do if t:IsA("Tool") then table.insert(names, t.Name) end end end
		table.sort(names)
		return table.concat(names, "|") .. "#" .. tostring(#names)
	end)
	if ok and sig then return sig end
	return ""
end

local function packSignature()
	local ok, sig = pcall(function()
		local _, mx = GetInventoryAmount()
		local extra = ""
		local ls = LocalPlayer:FindFirstChild("leaderstats")
		if ls then for _, v in pairs(ls:GetChildren()) do
			if tostring(v.Name):lower():find("pack") and (v:IsA("IntValue") or v:IsA("NumberValue") or v:IsA("StringValue")) then
				extra = extra .. "=" .. tostring(v.Value)
			end
		end end
		return "max" .. tostring(mx) .. extra
	end)
	if ok and sig then return sig end
	return ""
end

function bestToolName()
	local ok, name = pcall(function()
		local ch = LocalPlayer.Character
		if ch then for _, t in pairs(ch:GetChildren()) do if t:IsA("Tool") then return t.Name end end end
		local bp = LocalPlayer:FindFirstChild("Backpack")
		if bp then for _, t in pairs(bp:GetChildren()) do if t:IsA("Tool") then return t.Name end end end
		return "?"
	end)
	if ok and name then return name end
	return "?"
end

local function awaitChange(sigFn, before, timeout)
	local t0 = os.clock()
	while os.clock() - t0 < (timeout or 1.2) do
		task.wait(0.15)
		local ok, now = pcall(sigFn)
		if ok and now ~= before then return true end
	end
	return false
end

local function snapTool()
	local ok, s = pcall(function()
		local pd = playerDataTable()
		local eq = pd and pd.equipped
		return {
			sig = toolSignature(),
			eq = (eq and eq[3]) or nil,
			coins = GetCoinsAmount(),
			rb = Rebirths and Rebirths.Value or 0,
		}
	end)
	return ok and s or nil
end
local function toolChanged(a, b)
	if not a or not b then return false end
	if a.sig ~= b.sig then return true end
	if a.eq ~= b.eq then return true end
	if b.rb == a.rb and (a.coins - b.coins) > 0 then return true end
	return false
end
local function awaitTool(before, timeout)
	local t0 = os.clock()
	while os.clock() - t0 < (timeout or 0.9) do
		task.wait(0.1)
		if toolChanged(before, snapTool()) then return true end
	end
	return false
end

local function snapPack()
	local ok, s = pcall(function()
		local pd = playerDataTable()
		local eq = pd and pd.equipped
		return {
			sig = packSignature(),
			eq = (eq and eq[1]) or nil,
			coins = GetCoinsAmount(),
			rb = Rebirths and Rebirths.Value or 0,
		}
	end)
	return ok and s or nil
end
local function packChanged(a, b)
	if not a or not b then return false end
	if a.sig ~= b.sig then return true end
	if a.eq ~= b.eq then return true end
	if b.rb == a.rb and (a.coins - b.coins) > 0 then return true end
	return false
end
local function awaitPack(before, timeout)
	local t0 = os.clock()
	while os.clock() - t0 < (timeout or 0.9) do
		task.wait(0.1)
		if packChanged(before, snapPack()) then return true end
	end
	return false
end

local function StartAutoBackpack()
	local mem = 3
	local fails = 0
	local timeoutIdx, timeoutStreak = nil, 0
	if getgenv().__MS_BackpackRunning then return end
	getgenv().__MS_BackpackRunning = true
	task.spawn(function()
		while Toggles["AutoBackpack"] and getgenv().__MS_Gen == myGen do
			if areaTransit or recovering or collapseRecovering then task.wait(0.5)
			else
			if not Remote then EnsureRemote() end
			if not Remote then task.wait(1)
			else
				local bought = 0
				local shop = discoverShop().packs
				if shop then
					local chained = 0
					while Toggles["AutoBackpack"] and chained < 10 do
						local coins = GetCoinsAmount()
						local owned = ownedPackIndex(shop)
						local idx, why = bestBuy(shop, owned, 3, coins, "Backpack")
						if not idx then
							lastBoughtPackText = (why == "MAX") and "MAX (best owned)" or "saving (next too pricey)"
							break
						end
						local before = snapPack()
						buyPause, buyPauseAt = true, os.clock()
						Remote:FireServer("BuyItem", {{"Backpack", idx}})
						local changed = awaitPack(before, 0.9)
						buyPause = false
						if changed then
							bought = bought + 1
							chained = chained + 1
							lastBoughtPackText = "Pack #" .. tostring(idx)
							mem = idx + 1
							timeoutIdx, timeoutStreak = nil, 0
						elseif timeoutIdx == idx then
							timeoutStreak = timeoutStreak + 1
							if timeoutStreak >= 3 then
								refusedBuy["Backpack#" .. idx] = true
								mem = idx + 1
								timeoutIdx, timeoutStreak = nil, 0
							end
							break
						else
							timeoutIdx, timeoutStreak = idx, 1
							break
						end
					end
					gearPackText = "max " .. tostring(select(2, GetInventoryAmount()))
				end
				if not shop then
					local tries, i = 0, mem
					while Toggles["AutoBackpack"] and tries < 10 and i <= 50 do
						local before = snapPack()
						buyPause, buyPauseAt = true, os.clock()
						Remote:FireServer("BuyItem", {{"Backpack", i}})
						task.wait(0.3)
						buyPause = false
						tries = tries + 1
						if packChanged(before, snapPack()) then
							bought = bought + 1
							lastBoughtPackText = "Pack #" .. tostring(i)
							mem = i + 1
						else
							mem = i + 1
						end
						i = i + 1
					end
					if mem > 50 then mem = 3 end
					gearPackText = "max " .. tostring(select(2, GetInventoryAmount()))
				end
				fails = (bought == 0) and fails + 1 or 0
				if bought == 0 and fails >= 3 and lastBoughtPackText == "none yet" then lastBoughtPackText = "MAX / nothing to buy" end
				task.wait(bought > 0 and 0.1 or math.min(2 + fails * 2, 12))
			end
			end
		end
		getgenv().__MS_BackpackRunning = false
	end)
end

local function StartAutoTools()
	local mem = 1
	local fails = 0
	local timeoutIdx, timeoutStreak = nil, 0
	if getgenv().__MS_ToolsRunning then return end
	getgenv().__MS_ToolsRunning = true
	task.spawn(function()
		while Toggles["AutoTools"] and getgenv().__MS_Gen == myGen do
			if areaTransit or recovering or collapseRecovering then task.wait(0.5)
			else
			if not Remote then EnsureRemote() end
			if not Remote then task.wait(1)
			else
				local bought = 0
				local shop = discoverShop().tools
				if shop then
					local chained = 0
					while Toggles["AutoTools"] and chained < 10 do
						local coins = GetCoinsAmount()
						local owned = ownedToolIndex(shop)
						local idx, why = bestBuy(shop, owned, 1, coins, "Tools")
						if not idx then
							lastBoughtToolText = (why == "MAX") and "MAX (best owned)" or "saving (next too pricey)"
							break
						end
						local before = snapTool()
						buyPause, buyPauseAt = true, os.clock()
						Remote:FireServer("BuyItem", {{"Tools", idx}})
						task.wait(0.35)
						pcall(function()
							Remote:FireServer("EquipItem", {{"Tools", entryName(shop[idx], idx)}})
						end)
						local changed = awaitTool(before, 2.0)
						buyPause = false
						if changed then
							bought = bought + 1
							chained = chained + 1
							lastBoughtToolText = "Tool #" .. tostring(idx)
							gearToolText = bestToolName()
							mem = idx + 1
							timeoutIdx, timeoutStreak = nil, 0
							lastToolTryText = ""
						else
							local nowC = GetCoinsAmount()
							local wasC = (before and before.coins) or 0
							lastToolTryText = string.format("T#%d ~%s coins %s->%s owned#%s", idx, tostring(shopPrice(shop[idx], "Tools") or "?"), tostring(wasC), tostring(nowC), tostring(owned))
							if timeoutIdx == idx then
								timeoutStreak = timeoutStreak + 1
								if timeoutStreak >= 3 then
									refusedBuy["Tools#" .. idx] = true
									mem = idx + 1
									timeoutIdx, timeoutStreak = nil, 0
								end
							else
								timeoutIdx, timeoutStreak = idx, 1
							end
							break
						end
					end
					gearToolText = bestToolName()
				end
				if not shop then
					local tries, i = 0, mem
					while Toggles["AutoTools"] and tries < 10 and i <= 50 do
						local before = snapTool()
						buyPause, buyPauseAt = true, os.clock()
						Remote:FireServer("BuyItem", {{"Tools", i}})
						task.wait(0.3)
						buyPause = false
						tries = tries + 1
						if toolChanged(before, snapTool()) then
							bought = bought + 1
							lastBoughtToolText = "Tool #" .. tostring(i)
							gearToolText = bestToolName()
							mem = i + 1
						else
							mem = i + 1
						end
						i = i + 1
					end
					if mem > 50 then mem = 1 end
					gearToolText = bestToolName()
				end
				fails = (bought == 0) and fails + 1 or 0
				if bought == 0 and fails >= 3 and lastBoughtToolText == "none yet" then lastBoughtToolText = "MAX / nothing to buy" end
				task.wait(bought > 0 and 0.1 or math.min(2 + fails * 2, 12))
			end
			end
		end
		getgenv().__MS_ToolsRunning = false
	end)
end

local WindUI = loadstring(game:HttpGet("https://cdn.jsdelivr.net/gh/Footagesus/WindUI@main/dist/main.lua"))()
local function StopAreaRun()
	areaRunId = areaRunId + 1
	areaPhaseText = "off"
	areaTransit = false
	Toggles["AutoRebirth"] = false
	StopAutoRebirth()
	pcall(function()
		local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
		if hum then hum.WalkSpeed, hum.JumpPower = 16, 50 end
	end)
end
local function StartAreaRun(area)
	areaRunId = areaRunId + 1
	local run = areaRunId
	Toggles["AutoRebirth"] = false
	StopAutoRebirth()
	areaTransit = true
	local function clearTransit() if run == areaRunId then areaTransit = false end end
	task.spawn(function()
		local function alive() return run == areaRunId end
		areaPhaseText = area.name .. ": teleporting..."
		while alive() do
			if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then break end
			task.wait(0.5)
		end
		if not alive() then clearTransit() return end
		EnsureRemote()
		local Character = LocalPlayer.Character
		local HRP = Character and Character:FindFirstChild("HumanoidRootPart")
		local hum = Character and Character:FindFirstChildOfClass("Humanoid")
		if not HRP then areaPhaseText = "no character" clearTransit() return end
		if hum then hum.WalkSpeed, hum.JumpPower = 0, 0 end
		if area.moveTo and Remote then
			HRP.Anchored = true
			Remote:FireServer("MoveTo", {{area.moveTo}})
			local arriveFrom = HRP.Position
			local arrivedAt = os.clock()
			while os.clock() - arrivedAt < 4 do
				if (HRP.Position - arriveFrom).Magnitude > 5 then break end
				task.wait(0.1)
			end
			Remote:FireServer("MoveTo", {{"SurfaceSpawn"}})
			arriveFrom = HRP.Position
			arrivedAt = os.clock()
			while os.clock() - arrivedAt < 4 do
				if (HRP.Position - arriveFrom).Magnitude > 5 then break end
				task.wait(0.1)
			end
			HRP.CFrame = CFrame.new(area.spawn)
			task.wait(1)
		end
		if not alive() then clearTransit() return end
		HRP.Anchored = true
		Character = LocalPlayer.Character
		HRP = Character and Character:FindFirstChild("HumanoidRootPart")
		if not HRP then areaPhaseText = "no character" clearTransit() return end
		for _ = 1, 3 do
			HRP.CFrame = CFrame.new(area.spawn)
			task.wait(0.5)
			Character = LocalPlayer.Character
			HRP = Character and Character:FindFirstChild("HumanoidRootPart")
			if HRP and (HRP.Position - area.spawn).Magnitude <= 15 then break end
		end
		if not HRP or (HRP.Position - area.spawn).Magnitude > 15 then areaPhaseText = "stuck" clearTransit() return end
		task.wait(0.5)
		pcall(function()
			local old = workspace:FindFirstChild("MS_AreaBridge")
			if old then old:Destroy() end
			local floor = Instance.new("Part")
			floor.Name = "MS_AreaBridge"
			floor.Anchored = true
			if area.bridgeSize and area.bridgePos then
				floor.Size = area.bridgeSize
				floor.Position = area.bridgePos
			else
				local a, b = area.spawn, area.walkEnd
				local dist = (Vector3.new(b.X - a.X, 0, b.Z - a.Z)).Magnitude
				local mid = (a + b) / 2
				floor.Size = Vector3.new(12, 1, dist + 30)
				floor.Position = Vector3.new(mid.X, math.min(a.Y, b.Y) - 4, mid.Z)
			end
			floor.Material = Enum.Material.ForceField
			floor.Parent = workspace
		end)
		HRP.Anchored = false
		if not alive() then clearTransit() return end
		areaPhaseText = area.name .. ": moving..."
		local guard = os.clock()
		while alive() and os.clock() - guard < 120 do
			Character = LocalPlayer.Character
			HRP = Character and Character:FindFirstChild("HumanoidRootPart")
			if not HRP then task.wait(0.5)
			else
				local flat = Vector3.new(area.walkEnd.X - HRP.Position.X, 0, area.walkEnd.Z - HRP.Position.Z)
				if flat.Magnitude <= 1.5 then break end
				local step = flat.Unit * 0.5
				HRP.CFrame = CFrame.new(Vector3.new(HRP.Position.X + step.X, area.walkEnd.Y, HRP.Position.Z + step.Z))
				task.wait(0.01)
			end
		end
		if not alive() then clearTransit() return end
		areaPhaseText = area.name .. ": to mine spot..."
		Character = LocalPlayer.Character
		HRP = Character and Character:FindFirstChild("HumanoidRootPart")
		if HRP then
			HRP.Anchored = true
			for _ = 1, 3 do
				HRP.CFrame = CFrame.new(area.mine)
				task.wait(0.5)
				Character = LocalPlayer.Character
				HRP = Character and Character:FindFirstChild("HumanoidRootPart")
				if HRP and (HRP.Position - area.mine).Magnitude <= 15 then break end
			end
			if HRP then HRP.Anchored = false end
		end
		if not HRP or (HRP.Position - area.mine).Magnitude > 15 then areaPhaseText = "stuck" clearTransit() return end
		task.wait(0.5)
		if not alive() then clearTransit() return end
		areaPhaseText = area.name .. ": running autorebirth..."
		lastAreaName = area.name
		TrackArea(true)
		clearTransit()
		Toggles["AutoRebirth"] = true
		StartAutoRebirth()
	end)
end

local collapseGen = 0
local function BlocksNear(pos, radius, maxParts)
	local ok, parts = pcall(function()
		local region = Region3.new(pos - Vector3.new(radius, radius, radius), pos + Vector3.new(radius, radius, radius))
		return workspace:FindPartsInRegion3WithWhiteList(region, {game.Workspace.Blocks}, maxParts or 10)
	end)
	if ok and type(parts) == "table" then return #parts end
	return -1
end

local function RecoverFromCollapse(reason)
	collapseGen = collapseGen + 1
	local gen = collapseGen
	if collapseRecovering then return end
if not (Toggles["AutoMine"] or Toggles["FastMine"] or Toggles["AutoRebirth"] or Toggles["SVSell"]) then return end

	collapseRecovering = true
	recovering = true
	areaTransit = true

	print("[MS] Collapse detected (" .. tostring(reason) .. "). Moving forward for 7s then resuming...")
	areaPhaseText = "collapsed: moving forward..."

	task.spawn(function()
		for _ = 1, 30 do
			if gen ~= collapseGen then return end
			task.wait(0.5)
			local done = false
			pcall(function()
				local col = workspace:FindFirstChild("Collapsed")
				if not col or col.Value ~= true then done = true end
			end)
			if done then break end
		end
		if gen ~= collapseGen then return end

		for _ = 1, 20 do
			if gen ~= collapseGen then return end
			if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then break end
			task.wait(0.5)
		end
		if gen ~= collapseGen then return end

		local MOVE_DURATION = 4
		local MOVE_SPEED = 25
		local startedAt = os.clock()

		areaPhaseText = "collapsed: moving forward for " .. tostring(MOVE_DURATION) .. "s..."
		print("[MS] Moving forward for " .. tostring(MOVE_DURATION) .. " seconds...")

		while gen == collapseGen and (os.clock() - startedAt) < MOVE_DURATION do
			local char = LocalPlayer.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hrp then
				pcall(function() hrp.Anchored = false end)
				local forwardDir = hrp.CFrame.LookVector
				hrp.CFrame = hrp.CFrame + forwardDir * (MOVE_SPEED * 0.05)
				if hum then
					hum.WalkSpeed = 0
					hum.JumpPower = 0
				end
			end
			task.wait(0.05)
		end

		if gen ~= collapseGen then return end

		areaPhaseText = "collapsed: dropping into fresh blocks..."
		local char = LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			pcall(function() hrp.Anchored = false end)
			hrp.CFrame = hrp.CFrame + Vector3.new(0, -3, 0)
			task.wait(0.5)
		end

		local char2 = LocalPlayer.Character
		local hum2 = char2 and char2:FindFirstChildOfClass("Humanoid")
		if hum2 then hum2.WalkSpeed, hum2.JumpPower = 16, 50 end

		if gen ~= collapseGen then return end

		collapseRecovering = false
		recovering = false
		areaTransit = false

		local finalChar = LocalPlayer.Character
		local finalHRP = finalChar and finalChar:FindFirstChild("HumanoidRootPart")
		if finalHRP then
			lastMineSpot = finalHRP.Position
		end

		TrackArea(true)
		areaPhaseText = "recovered, resuming mining..."
		print("[MS] Move-forward recovery done. Resuming mining.")
	end)
end

task.spawn(function()
	local col = nil
	pcall(function() col = workspace:WaitForChild("Collapsed", 30) end)
	if col then
		col.Changed:Connect(function()
			local isCol = false
			pcall(function() isCol = col.Value == true end)
			if isCol then RecoverFromCollapse("Collapsed=true") end
		end)
	else
		print("[MS] WARNING: workspace.Collapsed not found, using block-watchdog only")
	end
	local emptyStreak = 0
	while true do
		task.wait(2)
		pcall(function()
			local mining = Toggles["AutoMine"] or Toggles["FastMine"] or Toggles["AutoRebirth"]
			if not mining or collapseRecovering or areaTransit or sellTrip then emptyStreak = 0 return end
			local h = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
			if not h then emptyStreak = 0 return end
			local n = BlocksNear(h.Position, 8, 10)
			if n == 0 then
				emptyStreak = emptyStreak + 1
				local colNow = false
				pcall(function()
					local c = workspace:FindFirstChild("Collapsed")
					colNow = c and c.Value == true
				end)
				if emptyStreak >= 4 and (colNow or BlocksNear(h.Position, 20, 20) == 0) then
					emptyStreak = 0
					RecoverFromCollapse("no-blocks-watchdog")
				end
			else
				emptyStreak = 0
			end
		end)
	end
end)

local Window = WindUI:CreateWindow({
	Title = "Mining Simulator",
	Icon = "pickaxe",
	Author = "by V444JAA",
	Folder = "MiningSimGui",
	Size = UDim2.fromOffset(520, 420),
	Theme = "Dark",
		ToggleKey = Enum.KeyCode.LeftShift,
})
getgenv().__MS_WindUIWindow = Window


local MineTab = Window:Tab({ Title = "Mining", Icon = "pickaxe" })
local SellTab = Window:Tab({ Title = "Sell", Icon = "coins" })
local MiscTab = Window:Tab({ Title = "Shop / Rebirth", Icon = "settings" })
local AreasTab = Window:Tab({ Title = "Areas", Icon = "map" })


MineTab:Toggle({
	Title = "Auto Mine (straight down)",
	Desc = "Mines -1,-10,-1 straight down like AutoRebirth dig",
	Value = false,
	Callback = function(state)
		Toggles["AutoMine"] = state
		if state then StartAutoMine() end
	end
})

MineTab:Toggle({
	Title = "Fast Mine (aura)",
	Desc = "Mines everything in 5,5,5 around you",
	Value = false,
	Callback = function(state)
		Toggles["FastMine"] = state
		if state then StartFastMine() end
	end
})

MineTab:Toggle({
	Title = "Limit depth",
	Desc = "AutoMine stops once Depth target is reached (off = dig forever)",
	Value = false,
	Callback = function(state)
		Toggles["LimitDepth"] = state
	end
})

local MineStatus = MineTab:Paragraph({
	Title = "Status",
	Desc = "waiting...",
})



SellTab:Toggle({
	Title = "SV Sell",
	Desc = "Test toggle — same sell logic as Auto Sell",
	Value = false,
	Callback = function(state)
		Toggles["SVSell"] = state
		if state then StartSVSell() end
	end
})

local syncingThreshold = false
local sellEchoUntil = 0
local depthEchoUntil = 0
local syncingDepth = false
local SellInput
local DepthInput
local SellStatus = SellTab:Paragraph({
	Title = "Inventory",
	Desc = "waiting...",
})
local function setThreshold(v)
	SELL_TRESHOLD = v
	SellTreshold = v
	getgenv().SellTreshold = v
	if syncingThreshold then return end
	syncingThreshold = true
	pcall(function()
		if SellInput then SellInput:Set(tostring(v)) end
	end)
	syncingThreshold = false
end

SellInput = SellTab:Input({
	Title = "Sell Threshold",
	Desc = "Type a number + ENTER, or FULL.",
	Type = "Input",
	Value = SELL_TRESHOLD == nil and "FULL" or tostring(SELL_TRESHOLD),
	Placeholder = "FULL or number (e.g. 30000)",
	Callback = function(input)
		if syncingThreshold then return end
		local ok, err = pcall(function()
			local raw = tostring(input or "")
			local t = raw:upper():gsub("%s+", "")
			if t == "" or t == "FULL" or t == "NIL" or t == "MAX" then
				local _, packMax = GetInventoryAmount()
				SELL_TRESHOLD = nil
				SellTreshold = (packMax and packMax > 0) and packMax or 200
				getgenv().SellTreshold = nil
				syncingThreshold = true
				pcall(function() if SellInput then SellInput:Set("FULL") end end)
				syncingThreshold = false
				sellEchoUntil = os.clock() + 5
				SellStatus:SetDesc("threshold FULL (got [" .. raw .. "])")
			else
				local digits = t:gsub(",", ""):match("%d+")
				local amount = digits and tonumber(digits)
				if amount and amount > 0 then
					setThreshold(math.floor(amount))
					sellEchoUntil = os.clock() + 5
					SellStatus:SetDesc("threshold " .. tostring(math.floor(amount)) .. " (got [" .. raw .. "])")
				else
					sellEchoUntil = os.clock() + 5
					SellStatus:SetDesc("ignored [" .. raw .. "] - type a number or FULL")
				end
			end
		end)
		if not ok then
			sellEchoUntil = os.clock() + 5
			pcall(function() SellStatus:SetDesc("input error: " .. tostring(err)) end)
		end
	end
})

MiscTab:Toggle({
	Title = "Auto Rebirth",
	Desc = "Full AutoRebirth: dig to Depth, then aura+sell + instant rebirths (no teleport)",
	Value = false,
	Callback = function(state)
		Toggles["AutoRebirth"] = state
		if state then StartAutoRebirth() else StopAutoRebirth() end
	end
})

MiscTab:Toggle({
	Title = "Rebirth Only",
	Desc = "Only fires Rebirth when affordable, nothing else",
	Value = false,
	Callback = function(state)
		Toggles["RebirthOnly"] = state
		if state then StartRebirthOnly() end
	end
})

MiscTab:Toggle({
	Title = "Auto Backpack",
	Desc = "Buys next missing pack 3-50, stops at MAX",
	Value = false,
	Callback = function(state)
		Toggles["AutoBackpack"] = state
		if state then StartAutoBackpack() end
	end
})

MiscTab:Toggle({
	Title = "Auto Tools",
	Desc = "Buys next missing tool 1-50, stops at MAX",
	Value = false,
	Callback = function(state)
		Toggles["AutoTools"] = state
		if state then StartAutoTools() end
	end
})

local MiscStatus = MiscTab:Paragraph({
	Title = "Depth",
	Desc = "waiting...",
})

DepthInput = MiscTab:Input({
	Title = "Depth",
	Desc = "Dig target for AutoRebirth (default 205). Type + ENTER.",
	Type = "Input",
	Value = tostring(Depth),
	Placeholder = "e.g. 205",
	Callback = function(input)
		if syncingDepth then return end
		local ok, err = pcall(function()
			local raw = tostring(input or "")
			local digits = raw:gsub(",", ""):match("%d+")
			local typed = digits and tonumber(digits)
			if typed then
				Depth = math.clamp(math.floor(typed), 0, 5000)
				getgenv().Depth = Depth
				syncingDepth = true
				pcall(function() if DepthInput then DepthInput:Set(tostring(Depth)) end end)
				syncingDepth = false
				depthEchoUntil = os.clock() + 5
				MiscStatus:SetDesc("depth target " .. tostring(Depth) .. " (got [" .. raw .. "])")
			else
				depthEchoUntil = os.clock() + 5
				MiscStatus:SetDesc("ignored [" .. raw .. "] - type a number")
			end
		end)
		if not ok then
			depthEchoUntil = os.clock() + 5
			pcall(function() MiscStatus:SetDesc("input error: " .. tostring(err)) end)
		end
	end
})

local GearStatus = MiscTab:Paragraph({
	Title = "Gear",
	Desc = "buyers off",
})

for _, area in ipairs(Areas) do
	local a = area
	AreasTab:Button({
		Title = "Run " .. a.name,
		Desc = string.format("Teleport -> walk -> mine @ %d,%d,%d, then full autorebirth", math.floor(a.mine.X), math.floor(a.mine.Y), math.floor(a.mine.Z)),
		Callback = function()
			StartAreaRun(a)
		end
	})
end
AreasTab:Button({
	Title = "STOP area run",
	Desc = "Stops movement + full autorebirth, restores walkspeed",
	Callback = function()
		StopAreaRun()
	end
})
local AreaStatus = AreasTab:Paragraph({
	Title = "Area status",
	Desc = "off",
})

task.spawn(function()
	while Window and getgenv().__MS_Gen == myGen do
		pcall(function()
			local curInv, maxInv = GetInventoryAmount()
			local curDepth = GetCurrentDepth()
			local sellTxt = SELL_TRESHOLD == nil and "FULL" or tostring(SELL_TRESHOLD)
			MineStatus:SetDesc(string.format("depth %s / target %s", tostring(curDepth), tostring(Depth)))
			if os.clock() >= sellEchoUntil then
				SellStatus:SetDesc(string.format("inv %s/%s | threshold %s", tostring(curInv), tostring(maxInv), sellTxt))
			end
			if os.clock() >= depthEchoUntil then
				MiscStatus:SetDesc(string.format("depth %s / target %s | coins %s | rebirth %s", tostring(curDepth), tostring(Depth), tostring(GetCoinsAmount()), tostring(rebirthPhaseText)))
			end
			AreaStatus:SetDesc(tostring(areaPhaseText))
			GearStatus:SetDesc(string.format("tool %s (%s) | pack %s (%s)%s", tostring(gearToolText), tostring(lastBoughtToolText), tostring(gearPackText), tostring(lastBoughtPackText), lastToolTryText ~= "" and (" | " .. lastToolTryText) or ""))
		end)
		task.wait(0.5)
	end
end)

print("Subscribe to V444JAA")
