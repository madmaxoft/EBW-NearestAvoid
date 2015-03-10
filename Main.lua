
-- Main.lua

-- Implements the entire NearestAvoid AI controller
-- The bots target the nearest enemy, but avoid going through a friend bot in front of it





--- Returns true if the first number is between the second and third numbers, inclusive
local function isBetweenOrEqual(a_Val, a_Bounds1, a_Bounds2)
	-- Check params:
	assert(type(a_Val) == "number")
	assert(type(a_Bounds1) == "number")
	assert(type(a_Bounds2) == "number")
	
	if (a_Bounds1 < a_Bounds2) then
		return (a_Val >= a_Bounds1) and (a_Val <= a_Bounds2)
	else
		return (a_Val >= a_Bounds2) and (a_Val <= a_Bounds1)
	end
end





--- Returns the coords of the specified point projected onto the specified line
local function projectPtToLine(a_X, a_Y, a_LineX1, a_LineY1, a_LineX2, a_LineY2)
	-- Check params:
	assert(tonumber(a_X))
	assert(tonumber(a_Y))
	assert(tonumber(a_LineX1))
	assert(tonumber(a_LineY1))
	assert(tonumber(a_LineX2))
	assert(tonumber(a_LineY2))
	
	-- Calculate the coords:
	local dx = a_LineX2 - a_LineX1;
	local dy = a_LineY2 - a_LineY1;
	local divisor = (dx * dx + dy * dy)
	if (divisor < 0.0001) then
		-- The divisor is too small, the line is too short, so return the first point's coords as the projection:
		return a_LineX1, a_LineY1
	end
	local k = (dy * (a_Y - a_LineY1) + dx * (a_X - a_LineX1)) / divisor;
	return a_LineX1 + dx * k, a_LineY1 + dy * k;
end





--- Returns the distance of the specified point from the specified line
local function distPtFromLine(a_X, a_Y, a_LineX1, a_LineY1, a_LineX2, a_LineY2)
	-- Check params:
	assert(tonumber(a_X))
	assert(tonumber(a_Y))
	assert(tonumber(a_LineX1))
	assert(tonumber(a_LineY1))
	assert(tonumber(a_LineX2))
	assert(tonumber(a_LineY2))
	
	-- Calculate the distance, divisor first:
	local deltaX = a_LineX1 - a_LineX2
	local deltaY = a_LineY1 - a_LineY2
	local divisor = math.sqrt(deltaY * deltaY + deltaX * deltaX)
	if (divisor < 0.0001) then
		return 0
	end
	local numerator = math.abs(deltaY * a_X - deltaX * a_Y + a_LineX2 * a_LineY1 - a_LineY2 * a_LineX1)
	return numerator / divisor
end





--- Returns the Euclidean distance between two points
local function distPtFromPt(a_X1, a_Y1, a_X2, a_Y2)
	-- Check params:
	assert(tonumber(a_X1))
	assert(tonumber(a_Y1))
	assert(tonumber(a_X2))
	assert(tonumber(a_Y2))
	
	-- Calculate the distance:
	return math.sqrt((a_X1 - a_X2) * (a_X1 - a_X2) + (a_Y1 - a_Y2) * (a_Y1 - a_Y2))
end





--- Returns the Euclidean of the distance between two bots
local function botDistance(a_Bot1, a_Bot2)
	-- Check params:
	assert(type(a_Bot1) == "table")
	assert(type(a_Bot2) == "table")
	
	-- Calculate the distance:
	return distPtFromPt(a_Bot1.x, a_Bot1.y, a_Bot2.x, a_Bot2.y)
end





--- Returns the command for srcBot to target dstBot
local function cmdTargetBot(a_SrcBot, a_DstBot, a_Game)
	-- Check params:
	assert(type(a_SrcBot) == "table")
	assert(type(a_DstBot) == "table")
	assert(type(a_Game) == "table")
	
	local wantAngle = math.atan2(a_DstBot.y - a_SrcBot.y, a_DstBot.x - a_SrcBot.x) * 180 / math.pi
	local angleDiff = wantAngle - a_SrcBot.angle
	if (angleDiff < -180) then
		angleDiff = angleDiff + 360
	elseif (angleDiff > 180) then
		angleDiff = angleDiff - 360
	end
	
	-- If the current heading is too off, adjust:
	if (math.abs(angleDiff) > 5) then
		if ((a_SrcBot.speedLevel > 1) and (math.abs(angleDiff) > 3 * a_SrcBot.maxAngularSpeed)) then
			-- We're going too fast to steer, brake:
			aiLog(a_SrcBot.id, "Too fast to steer, breaking. Angle is " .. a_SrcBot.angle .. ", wantAngle is " .. wantAngle .. ", angleDiff is " .. angleDiff)
			return { cmd = "brake" }
		else
			aiLog(
				a_SrcBot.id, "Steering, angle is " .. a_SrcBot.angle .. ", wantAngle is " .. wantAngle ..
				", angleDiff is " .. angleDiff .. ", maxAngularSpeed is " .. a_SrcBot.maxAngularSpeed .. ", speed is " .. a_SrcBot.speed
			)
			return { cmd = "steer", angle = angleDiff }
		end
	end
	
	-- If the enemy is further than 20 pixels away, accellerate, else nop:
	local dist = botDistance(a_SrcBot, a_DstBot)
	if ((dist > 20) and (a_SrcBot.speed < a_Game.maxBotSpeed)) then
		aiLog(a_SrcBot.id, "Accellerating (dist is " .. dist .. ")")
		return { cmd = "accelerate" }
	else
		aiLog(a_SrcBot.id, "En route to dst, no command")
		return nil
	end
end





--- Converts bot speed to speed level index:
local function getSpeedLevelIdxFromSpeed(a_Game, a_Speed)
	-- Try the direct lookup first:
	local level = a_Game.speedToSpeedLevel[a_Speed]
	if (level) then
		return level
	end
	
	-- Direct lookup failed, do a manual lookup:
	print("speed level lookup failed for speed " .. a_Speed)
	for idx, lvl in ipairs(a_Game.speedLevels) do
		if (a_Speed <= lvl.linearSpeed) then
			print("Manual speed lookup for speed " .. a_Speed .. " is idx " .. idx .. ", linear speed " .. lvl.linearSpeed)
			return idx
		end
	end
	return 1
end





--- Returns true if there is a bot (from a_Bots) between a_Bot1 and a_Bot2 within the specified distance of the line
local function isBotBetweenBots(a_Bot1, a_Bot2, a_Bots, a_Dist)
	-- Check params:
	assert(type(a_Bot1) == "table")
	assert(type(a_Bot2) == "table")
	assert(type(a_Bots) == "table")
	assert(tonumber(a_Dist))
	
	-- Check each friend's distance from the line between bot1 and bot2:
	local minDist = 1500
	local minDistId = 0
	for _, f in ipairs(a_Bots) do
		if ((f.id ~= a_Bot1.id) and (f.id ~= a_Bot2.id)) then
			local x, y = projectPtToLine(f.x, f.y, a_Bot1.x, a_Bot1.y, a_Bot2.x, a_Bot2.y)
			if (isBetweenOrEqual(x, a_Bot1.x, a_Bot2.x) and isBetweenOrEqual(y, a_Bot1.y, a_Bot2.y)) then
				local dist = distPtFromPt(x, y, f.x, f.y)
				if (dist < minDist) then
					minDist = dist
					minDistId = f.id
				end
				if (dist < a_Dist) then
					aiLog(a_Bot1.id, "Cannot aim towards #" .. a_Bot2.id .. ", #" .. f.id .. " is in the way")
					return true
				end
			end
		end
	end  -- for f - a_Bots[]
	aiLog(a_Bot1.id, "Friend nearest to the line of fire to #" .. a_Bot2.id .. " is #" .. minDistId .. " at distance " .. minDist)
	return false
end





--- Updates each bot to target the nearest enemy:
local function updateTargets(a_Game)
	-- Check params:
	assert(type(a_Game) == "table")
	assert(type(a_Game.world) == "table")
	assert(tonumber(a_Game.world.botRadius))

	-- Update each bot's stats, based on their speed level:
	for _, m in ipairs(a_Game.myBots) do
		m.speedLevel = getSpeedLevelIdxFromSpeed(a_Game, m.speed)
		m.maxAngularSpeed  = a_Game.speedLevels[m.speedLevel].maxAngularSpeed
	end
	
	for _, m in ipairs(a_Game.myBots) do
		-- Pick the nearest target:
		local minDist = a_Game.world.width * a_Game.world.width + a_Game.world.height * a_Game.world.height
		local target
		for _, e in ipairs(a_Game.enemyBots) do
			if not(isBotBetweenBots(m, e, a_Game.myBots, 2 * a_Game.world.botRadius)) then
				local dist = botDistance(m, e)
				if (dist < minDist) then
					minDist = dist
					target = e
				end
			else
				aiLog(m.id, "Cannot target enemy #" .. e.id .. ", there's a friend in the way")
			end
		end  -- for idx2, e - enemyBots[]
		
		-- Navigate towards the target:
		if (target) then
			aiLog(m.id, "Targetting enemy #" .. target.id)
			a_Game.botCommands[m.id] = cmdTargetBot(m, target, a_Game)
		else
			-- No target available, wander around a bit:
			local cmd
			if (m.speed > 100) then
				cmd = { cmd = "brake" }
			else
				cmd = { cmd = "steer", angle = 120 }
			end
			aiLog(m.id, "No a clear line of attack to any enemy. Idling at " .. cmd.cmd)
			a_Game.botCommands[m.id] = cmd
		end
	end
end





function onGameStarted(a_Game)
	-- Collect all my bots into an array, and enemy bots to another array:
	a_Game.myBots = {}
	a_Game.enemyBots = {}
	for _, bot in pairs(a_Game.allBots) do
		if (bot.isEnemy) then
			table.insert(a_Game.enemyBots, bot)
		else
			table.insert(a_Game.myBots, bot)
		end
	end

	-- Initialize the speed-to-speedLevel table, find min and max:
	a_Game.speedToSpeedLevel = {}
	local minSpeed = a_Game.speedLevels[1].linearSpeed
	local maxSpeed = minSpeed
	for idx, level in ipairs(a_Game.speedLevels) do
		a_Game.speedToSpeedLevel[level.linearSpeed] = idx
		if (level.linearSpeed < minSpeed) then
			minSpeed = level.linearSpeed
		end
		if (level.linearSpeed > maxSpeed) then
			maxSpeed = level.linearSpeed
		end
	end
	a_Game.speedToSpeedLevel[0] = 1  -- Special case - bots with zero speed are handled as having the lowest speed
	a_Game.maxBotSpeed = maxSpeed
	a_Game.minBotSpeed = minSpeed
end





function onGameUpdate(a_Game)
	assert(type(a_Game) == "table")
	-- Nothing needed yet
end





function onGameFinished(a_Game)
	assert(type(a_Game) == "table")
	-- Nothing needed yet
end





function onBotDied(a_Game, a_BotID)
	-- Remove the bot from one of the myBots / enemyBots arrays:
	local whichArray
	if (a_Game.allBots[a_BotID].isEnemy) then
		whichArray = a_Game.enemyBots
	else
		whichArray = a_Game.myBots
	end
	for idx, bot in ipairs(whichArray) do
		if (bot.id == a_BotID) then
			table.remove(whichArray, idx)
			break;
		end
	end  -- for idx, bot - whichArray[]
	
	-- Print an info message:
	local friendliness
	if (a_Game.allBots[a_BotID].isEnemy) then
		friendliness = "(enemy)"
	else
		friendliness = "(my)"
	end
	print("LUA: onBotDied: bot #" .. a_BotID .. friendliness)
end





function onSendingCommands(a_Game)
	-- Update the bot targets:
	updateTargets(a_Game)
end





function onCommandsSent(a_Game)
	assert(type(a_Game) == "table")
	-- Nothing needed
end




