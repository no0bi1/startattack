BINDING_HEADER_STARTATTACK = "StartAttack"
BINDING_NAME_STARTATTACK_START = "Start Attack"

local MELEE_RANGE    = 3     -- yards
local CHECK_INTERVAL = 0.1   -- seconds between checks
local SWING_TIMEOUT  = 4     -- seconds without a swing (only used if distance is unavailable)
local MAX_TRIES      = 3     -- retarget cycles per out-of-range episode
local CYCLE_MAX      = 6     -- TargetNearestEnemy calls per cycle

local attacking = false
local active    = false
local tries     = 0
local acc       = 0
local dbgAcc    = 0
local lastSwing = 0
local pendingRestart = false
local debug     = false

local function Dbg(msg)
	if debug then DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00SA:|r " .. msg) end
end

local function Distance()
	if not UnitExists("target") then return nil end
	local ok, d = pcall(UnitXP, "distanceBetween", "player", "target")
	if ok and type(d) == "number" then return d end
	return nil
end

local function ValidEnemy()
	return UnitExists("target") and not UnitIsDead("target") and UnitCanAttack("player", "target")
end

-- Cycle Blizzard's nearest-enemy targeting until we land on an enemy in melee range.
local function TryRetarget()
	for i = 1, CYCLE_MAX do
		TargetNearestEnemy()
		if ValidEnemy() then
			local d = Distance()
			Dbg("cycle " .. i .. ": " .. tostring(UnitName("target")) .. " dist=" .. tostring(d))
			if not d or d <= MELEE_RANGE then
				return true
			end
		end
	end
	return false
end

function StartAttack_Start()
	active = true
	tries = 0
	lastSwing = GetTime()

	local retargeted = false
	local d = Distance()
	if UnitExists("target") and (not ValidEnemy() or (d and d > MELEE_RANGE)) then
		retargeted = TryRetarget()
	end

	if attacking then
		-- auto-attack already on: just make sure it follows the new target
		if retargeted then pendingRestart = true end
		return
	end

	StartAttack()

	if not ValidEnemy() then
		ToggleSheath()
	end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTER_COMBAT")
f:RegisterEvent("PLAYER_LEAVE_COMBAT")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
f:RegisterEvent("CHAT_MSG_COMBAT_SELF_MISSES")
f:SetScript("OnEvent", function()
	if event == "PLAYER_ENTER_COMBAT" then
		attacking = true
	elseif event == "PLAYER_LEAVE_COMBAT" then
		attacking = false
	elseif event == "PLAYER_REGEN_DISABLED" then
		lastSwing = GetTime()
	elseif event == "PLAYER_REGEN_ENABLED" then
		active = false
		tries = 0
		pendingRestart = false
	else
		lastSwing = GetTime()
	end
end)

f:SetScript("OnUpdate", function()
	if not active then return end
	if not UnitAffectingCombat("player") then return end

	acc = acc + arg1
	if acc < CHECK_INTERVAL then return end
	acc = 0

	local d = Distance()
	local stalled = (GetTime() - lastSwing) > SWING_TIMEOUT

	if debug then
		dbgAcc = dbgAcc + CHECK_INTERVAL
		if dbgAcc >= 0.5 then
			dbgAcc = 0
			Dbg("dist=" .. tostring(d) .. " attacking=" .. tostring(attacking)
				.. " stalled=" .. tostring(stalled) .. " tries=" .. tries)
		end
	end

	-- Resume swings after a retarget if auto-attack dropped
	if pendingRestart then
		if attacking then
			pendingRestart = false
		elseif ValidEnemy() then
			StartAttack()
			pendingRestart = false
		end
		return
	end

	if d and d <= MELEE_RANGE then
		tries = 0
		return
	end

	-- Out of melee (or distance unavailable and swings stalled)
	local needRetarget = (d and d > MELEE_RANGE) or ((not d) and stalled)
	if needRetarget and tries < MAX_TRIES then
		tries = tries + 1
		if TryRetarget() then
			pendingRestart = true
			lastSwing = GetTime()
		end
	end
end)

SLASH_SADEBUG1 = "/sadebug"
SlashCmdList["SADEBUG"] = function()
	debug = not debug
	DEFAULT_CHAT_FRAME:AddMessage("StartAttack debug: " .. tostring(debug))
end
