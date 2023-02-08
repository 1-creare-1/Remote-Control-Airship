-- Airship
-- Name this file `startup.lua` in ComputerCraft so it starts automatically

local POCKET_ID = 0

local file = fs.open("ConnectedPocketID","r")
if file ~= nil then
	POCKET_ID = tonumber(file.readAll())
	file.close()
end


function ErrorIfNil(value, error_text)
    error_text = error_text or "UndefinedPerepherial"
    if value == nil then
        print("Cant find " .. error_text)
        sleep(3)
        os.shutdown()
        return nil
    end
    return value
end

function GetWithError(peripheralName)
    return ErrorIfNil(peripheral.find(peripheralName), peripheralName)
end

local helm = GetWithError("ship_helm")
local shipReader = GetWithError("ship_reader")

local modemSide = nil
for _, Side in ipairs(rs.getSides()) do
    if peripheral.getType(Side) == "modem" and peripheral.wrap(Side).isWireless() then
        modemSide = Side
    end
end

ErrorIfNil(modemSide, "Modem")

rednet.open(modemSide)

print("AirshipID: " .. os.getComputerID())


local impulseTicks = 1
local AltitudeGain = 10
local HeightMaxDeveation = .2

local IsTargeting = false
local TargetingStage = 0
local StartPosition = {}
local targetPosition = {0, 0, 0}


function Theta(cx, cy, x, y)

    local angle = math.atan2(cy - y, x - cx)
	return angle
	
    --if angle <= 180 then
        --return angle
    --end
    --return angle - 360
    --return angle <= 180? angle: angle - 360;
end

function getRPY(x,y,z,w)
    local rX,rY,rZ,rW = shipReader.getRotation()
    local pitch = math.atan2(2*rX*rW-2*rY*rZ,1-2*rX*rX-2*rZ*rZ)
    local yaw = math.atan2(2*rY*rW-2*rX*rZ,1-2*rY*rY-2*rZ*rZ)
    local roll = math.asin(2*rX*rY+2*rZ*rW)
    return roll, pitch, yaw
end

function shortestDistRadians(start, stop)
    start = math.deg(start)
    stop = math.deg(stop)

    local modDiff = (stop - start) % 360
    local shortestDistance = 180 - math.abs(math.abs(modDiff) - 180)
    local a = (modDiff + 360) % 360 < 180 and shortestDistance * 1 or shortestDistance * -1
    return math.rad(a)
end

function shortestDistPercent(start, stop)

    local modDiff = (stop - start) % 1
    local shortestDistance = .5 - math.abs(math.abs(modDiff) - .5)
    local a = (modDiff + 1) % 1 < .5 and shortestDistance * 1 or shortestDistance * -1
    return a
end

local commands = {
	[87] = function() helm.impulseForward(impulseTicks) end,
	[83] = function() helm.impulseBack(impulseTicks) end,
	
	[65] = function() helm.impluseLeft(impulseTicks) end,
	[68] = function() helm.impulseRight(impulseTicks) end,
	
	[32] = function() helm.impulseUp(impulseTicks * 2) end,
	[340] = function() helm.impulseDown(impulseTicks * 2) end,
}


local RednetData = {}

function RednetReceive()
	while true do
		RednetIP, RednetData = rednet.receive()
		sleep()
	end
end

function HandleKeys()
	for i, key in pairs(RednetData[2]) do
		if commands[key] then
			commands[key]()
		end
		
		if i % 5 == 0 then sleep() end
	end
end

function MainLoop()
	while true do
		if RednetData then
			local DataType = RednetData[1]
			if DataType == "keys" then
				HandleKeys()
				IsTargeting = false
			elseif DataType == "goto" then
				
				targetPosition = RednetData[2]
				StartPosition = {shipReader.getWorldspacePosition()}
				
				TargetingStage = 0
				IsTargeting = true
	
				RednetData = nil
			elseif DataType == "redstone" then
				redstone.setAnalogOutput(RednetData[2][1], RednetData[2][2])
			elseif DataType == "getredstone" then
				rednet.send(POCKET_ID, {"redstone", redstone.getAnalogInput(RednetData[2][1])})
			elseif DataType == "sysmsg" then
				if RednetData[2] == "cancel" then
					IsTargeting = false
				elseif RednetData[2] == "ping" then
					POCKET_ID = RednetIP

					local file = fs.open("ConnectedPocketID","w")
					file.write(POCKET_ID)
					file.close()

					rednet.send(POCKET_ID, {"sysmsg", "pong"})
					RednetData = nil
				end
			end
		end
		sleep()
	end
end

function TargetingLoop()

	local LastY = math.huge

	while true do
		if IsTargeting == true then
			-- Get ship info
			local myX, myY, myZ = shipReader.getWorldspacePosition()
			
			local shipScale = {shipReader.getScale()}

			-- Get yaw
			local _, _, yaw = getRPY()
			yaw = (yaw / 2 + math.pi / 2) / math.pi
	
			-- Get target yaw
			local targetYaw = Theta(myX, myZ, targetPosition[1], targetPosition[3])
			targetYaw = (targetYaw / 2 + math.pi / 2) / math.pi + 0.5
			if targetYaw > 1 then
				targetYaw = targetYaw - 1
			end
			
			-- calculate angle to rotate
			local TargetAngleOfset = (yaw - targetYaw)

			local heightDif = myY - targetPosition[2] + shipScale[2] / 2
			
			
			
			local DistanceFromTarget = math.sqrt( math.pow(myX - targetPosition[1], 2) + math.pow(myZ - targetPosition[3], 2) )
			

			-- Min CruiseHeight is 110, if the start or target is above that, add their hights plus a buffer of like 20

			local CruiseHeight = 100

			local StartYCruise = StartPosition[2]
			local EndYCruise = targetPosition[2]

			if StartYCruise > EndYCruise then
				if StartYCruise > CruiseHeight - 10 then
					CruiseHeight = StartYCruise + 20
				end
			else
				if EndYCruise > CruiseHeight - 10 then
					CruiseHeight = EndYCruise + 20
				end
			end

			-- V2
			-- Airship goes up to alt
			-- Airship points towards target position constantly for the rest of the time untill above
			-- Airship also moves forward untill at target position
			-- Airship goes down

			if TargetingStage == 0 then
				if myY < CruiseHeight then
					helm.impulseUp(impulseTicks * 2)
				else
					TargetingStage = 1
				end
			elseif TargetingStage == 1 then
				if math.abs(TargetAngleOfset) > 0.03 then
					if shortestDistPercent(yaw, targetYaw) > 0 then
						helm.impluseLeft(1)
					else
						helm.impulseRight(1)
					end
					-- if TargetAngleOfset > 0 then
					-- 	helm.impulseRight(1)
					-- else
					-- 	helm.impluseLeft(1)
					-- end
				else
					if DistanceFromTarget > 1 then
						helm.impulseForward(1)
					elseif DistanceFromTarget < -1 then
						helm.impulseBack(1)
					else
						TargetingStage = 2
					end
				end
			elseif TargetingStage == 2 then
				if myY > targetPosition[2] + shipScale[2] / 2 + HeightMaxDeveation then
					helm.impulseDown(impulseTicks * 2)
				else
					IsTargeting = false
					rednet.send(POCKET_ID, {"sysmsg", "arrived"})
				end

				_, myY, _ = shipReader.getWorldspacePosition()

				if LastY - myY < .001 then
					IsTargeting = false
					rednet.send(POCKET_ID, {"sysmsg", "arrived"})
				end


			end
			LastY = myY
		end
		sleep()
	end
end

parallel.waitForAll(MainLoop, RednetReceive, TargetingLoop)
