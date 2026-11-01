BINDING_HEADER_STARTATTACK = "StartAttack"
BINDING_NAME_STARTATTACK_START = "Start Attack"

local MELEE_RANGE    = 2.5   -- yards
local CHECK_INTERVAL = 0.1   -- seconds between range checks
local RETRY_DELAY    = 0.4   -- seconds to wait after a restart before checking again
local MAX_TRIES      = 3     -- restarts per out-of-range episode

local attacking = false   -- auto-attack on (PLAYER_ENTER/LEAVE_COMBAT)
local active    = false   -- engaged by the keybind, cleared on leaving real combat
local tries     = 0
local acc       = 0
local wait      = 0
local dbgAcc    = 0
local debug     = false
local ignoreUntil = 0   -- ignore target changes caused by our own restart

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

-- Clear the target, then let the native StartAttack pick the nearest enemy and attack
local function Restart()
	Dbg("restart: clearing " .. tostring(UnitName("target")))
	ignoreUntil = GetTime() + 0.5
	ClearTarget()
	StartAttack()
	wait = RETRY_DELAY
end

function StartAttack_Start()
	active = true
	tries = 0

	local d = Distance()
	if UnitExists("target") and (not ValidEnemy() or (d and d > MELEE_RANGE)) then
		Restart()
		return
	end

	-- In range and already swinging: nothing to do, so spamming can't toggle it off
	if attacking then
		return
	end

	StartAttack()

	-- Nothing to attack: use the key to draw/sheathe the weapon instead
	if not ValidEnemy() then
		ToggleSheath()
	end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTER_COMBAT")
f:RegisterEvent("PLAYER_LEAVE_COMBAT")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:SetScript("OnEvent", function()
	if event == "PLAYER_ENTER_COMBAT" then
		attacking = true
	elseif event == "PLAYER_LEAVE_COMBAT" then
		attacking = false
	elseif event == "PLAYER_REGEN_ENABLED" then
		-- real combat ended
		active = false
		tries = 0
		wait = 0
	elseif event == "PLAYER_TARGET_CHANGED" then
		-- You changed target yourself (click, tab, etc.): stop auto-restarting
		if GetTime() > ignoreUntil then
			active = false
			tries = 0
			wait = 0
			Dbg("manual target change, loop paused")
		end
	end
end)

f:SetScript("OnUpdate", function()
	if not active then return end
	if not UnitAffectingCombat("player") then return end

	-- Give the restart time to take effect before checking again
	if wait > 0 then
		wait = wait - arg1
		return
	end

	acc = acc + arg1
	if acc < CHECK_INTERVAL then return end
	acc = 0

	local d = Distance()

	if debug then
		dbgAcc = dbgAcc + CHECK_INTERVAL
		if dbgAcc >= 0.5 then
			dbgAcc = 0
			Dbg("dist=" .. tostring(d) .. " attacking=" .. tostring(attacking) .. " tries=" .. tries)
		end
	end

	if not d then return end

	if d <= MELEE_RANGE then
		tries = 0
		return
	end

	-- Out of melee range: clear target and restart native StartAttack
	if tries < MAX_TRIES then
		tries = tries + 1
		Restart()
	end
end)

SLASH_SADEBUG1 = "/sadebug"
SlashCmdList["SADEBUG"] = function()
	debug = not debug
	DEFAULT_CHAT_FRAME:AddMessage("StartAttack debug: " .. tostring(debug))
end