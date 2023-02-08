-- Pocket Computer
-- Name this file `startup.lua` in ComputerCraft so it starts automatically

local BackgroundColor = colors.black
local TextColor = colors.white
local BorderColor = colors.gray


-- Get ship id from save
local SHIP_ID = 0
local file = fs.open("ConnectedShipID","r")
if file ~= nil then
	SHIP_ID = tonumber(file.readAll())
	file.close()
end




-- Load saved coords
function Split(s, delimiter)
    local result = {};
    for match in (s..delimiter):gmatch("(.-)"..delimiter) do
        table.insert(result, match);
    end
    return result;
end
function FindInTable(table, term)
	for _, v in pairs(table) do
		if v == term then
			return true
		end
	end
	return false
end
local SavedCoords = {}

local file = fs.open("SavedCoords","r")
if file == nil then
	file = fs.open("SavedCoords","w")
else
	local line = file.readLine()
	while line ~= nil do
		local split = Split(line, ",")
		SavedCoords[split[1]] = {tonumber(split[2]), tonumber(split[3]), tonumber(split[4])}
		line = file.readLine()
	end
end


file.close()


rednet.open("back")

local keys = {}

local MainMenuOptions = {
	{"Manual Control", "Allows you to control the ship with WASD SPACE SHIFT",
	function()
		while true do
			local RednetData = {}
			
			for key, keydata in pairs(keys) do
				-- if pressed
				if keydata[1] then
					table.insert(RednetData, key)
				end
			end
			rednet.send(SHIP_ID, {"keys", RednetData})
			sleep()
		end
	end
	},

	{"GOTO Location", "Goes to a previously specified location", function ()
		PrintSavedCoords()
		
		local LocationName = nil
		while SavedCoords[LocationName] == nil do
			LocationName = Prompt("Input Location Name: ")
		end

		rednet.send(SHIP_ID, {"goto", SavedCoords[LocationName]})

		WaitForMsg("arrived")
		print("The airship has arrived!")
		sleep(2)
	end},
	{"SET Location", "Assigns an xyz to a name for easy future reference", function ()
		PrintSavedCoords()

		local coords = GetXYZInput()

		write("Input location name: ")
		local locationName = read():gsub(",", "")

		SavedCoords[locationName] = coords

		SaveCoords()

		print("Saved!")
		sleep(2)
	end},
	{"GOTO Me", "The airship will come to wherever you are. This does requre a gps setup", function ()
		print("Searching for your coords...")
		local x, y, z = gps.locate(2, false)
		if not x then
			print("Failed to get coords. Are you sure you set up a gps?")
			sleep(1)
			return
		end

		rednet.send(SHIP_ID, {"goto", {x, y, z}})

		WaitForMsg("arrived")
		print("The airship has arrived!")
		sleep(2)
	end},
	{"GOTO Coords", "Specify an xyz for the airship to fly to", function ()
		rednet.send(SHIP_ID, {"goto", GetXYZInput()})

		WaitForMsg("arrived")
		print("The airship has arrived!")
		sleep(2)
	end},
	{"Switch Airship", "Enter a AirshipID to switch (AirshipID is shown on ship computer)", function ()
		local Connected = false
		while not Connected do
			local AirshipID = PromptGetNumber("AirshipID")
			write("Connecting.")
			rednet.send(AirshipID, {"sysmsg", "ping"})

			for i = 1, 10, 1 do
				write(".")
				local id, rednetData = rednet.receive(1)

				if rednetData and rednetData[1] == "sysmsg" and rednetData[2] == "pong" then
					SHIP_ID = id
					Connected = true

					local file = fs.open("ConnectedShipID","w")
					file.write(SHIP_ID)
					file.close()

					print("\nConnected!")
					sleep(1)
					return
				end
			end

			print("\nConnection Failed")
			sleep(0.5)
		end
	end},
	{"Control Engine", "Lets you turn the engine on or off (Connect the engine to the bottom of the computer)", function ()
		local function ValidateBoolInput(input)
			local t = {"true", "yes", "y", "t", "on", "powered", "power"}
			local f = {"false", "no", "n", "f", "off"}

			input = input:lower()

			if FindInTable(t, input) then
				return true
			elseif FindInTable(f, input) then
				return false
			else
				return nil
			end
		end

		local on = nil
		while on == nil do
			on = ValidateBoolInput(Prompt("Engine state (on/off): "))
		end
		rednet.send(SHIP_ID, {"redstone", {"bottom", on and 0 or 15}})
	end},
	{"Redstone Out", "Lets you power any side of the computer", function ()


		local side = "not a real side"
		while not FindInTable(rs.getSides(), side) do
			side = Prompt("Side: ")
		end

		local strength = -1
		while strength < 0 or strength > 15 do
			strength = PromptGetNumber("Signal Strength")
		end

		rednet.send(SHIP_ID, {"redstone", {side, strength}})
	end},
	{"Redstone Spam", "Lets you spam toggle power any side of the computer", function ()


		local side = "not a real side"
		while not FindInTable(rs.getSides(), side) do
			side = Prompt("Side: ")
		end

		local on = true
		while true do
			rednet.send(SHIP_ID, {"redstone", {side, on and 0 or 15}})
			on = not on

			sleep(.2)
		end

	end},
	
}

function WaitForcancel()
	while keys[88] == nil or keys[88][1] ~= true do
		sleep()
	end
	rednet.send(SHIP_ID, {"sysmsg", "cancel"})
	sleep()
end

function WaitForMsg(msg, msgtype)
	msgtype = msgtype or "sysmsg"
	while true do
		local _, rednetData = rednet.receive(SHIP_ID)
		if rednetData and rednetData[1] == msgtype and (rednetData[2] == msg or msg == nil) then
			return rednetData[2]
		end
	end
end

function SaveCoords()
	local file = fs.open("SavedCoords","w")
	for locationName, coords in pairs(SavedCoords) do
		file.writeLine(locationName .. "," .. coords[1]  .. "," .. coords[2] .. "," .. coords[3])
	end
	file.close()
end

function PrintSavedCoords()
	print("Locations: ")
	for locationName, coords in pairs(SavedCoords) do
		print(locationName .. ": " .. coords[1] .. ", " .. coords[2] .. ", " .. coords[3])
	end
	print("")
end



function ClearScreen()
	term.setBackgroundColor(BackgroundColor)   -- Set the background color to black.
	term.setTextColor(TextColor)
	term.clear()                            -- Paint the entire display with the current background colour.
	term.setCursorPos(1,1)                  -- Move the cursor to the top left position.
end

function Prompt(promptText)
	write(promptText)
	local result = read()


	local cX, cY = term.getCursorPos()
	term.setCursorPos(cX, cY - 1)
	term.clearLine()

	return result
end

function PromptGetNumber(coordName)
	local number = "lol not a number"
	while tonumber(number) == nil do
		number = Prompt("Input " .. coordName .. ": ")
	end
	return tonumber(number)
end

function GetXYZInput()


	return {PromptGetNumber("X"), PromptGetNumber("Y"), PromptGetNumber("Z")}
end

function printWithBorder(msg)
	term.setTextColor(BorderColor)
	write("|")
	term.setTextColor(TextColor)

	write(msg)
	local remainingLength = 24 - #msg

	for i = 1, remainingLength, 1 do
		write(" ")
	end

	term.setTextColor(BorderColor)
	write("|")
	term.setTextColor(TextColor)
end

function printTopBorder()
	term.setTextColor(BorderColor)
	print("/------------------------\\")
	term.setTextColor(TextColor)
end
function printBottomBorder()
	term.setTextColor(BorderColor)
	print("\\------------------------/")
	term.setTextColor(TextColor)
end

function printDivider()
	term.setTextColor(BorderColor)
	print("|------------------------|")
	term.setTextColor(TextColor)
end

function ValidateInput(input)
	if input == "#?" then
		print("\nLol, no\n# is meant to be a number\nSo do 1?\nto get info on the first command\n")
		sleep(3)
	end
	local isQuestion = input:sub(2, 2) == "?"
	local index = tonumber(input:sub(1, 1))

	if index == nil or index > #MainMenuOptions then
		return false
	end
	return true, index, isQuestion
end

function RenderTop()
	ClearScreen()

	printTopBorder()

	printWithBorder("Ship Controler")
	printWithBorder("By _creare_")

	printDivider()

	printWithBorder("Connected AirshipID: " .. SHIP_ID)
	
end

function RenderMainMenu()

	RenderTop()
	printDivider()

	for index, command in pairs(MainMenuOptions) do
		printWithBorder("(" .. (index - 1) .. ") " .. command[1])
	end
	
	printWithBorder("")
	printWithBorder("(#?) For Info")


	printBottomBorder()

	local inputValid, inputID, isQuestion = ValidateInput("lol not valid input :)")
	while inputValid == false do


		write("Input: ")

		inputValid, inputID, isQuestion = ValidateInput(read())
		
		
		local cX, cY = term.getCursorPos()
		term.setCursorPos(cX, cY - 1)
		term.clearLine()
	end

	RenderTop()
	printBottomBorder()
	inputID = inputID + 1
	if isQuestion then
		print(MainMenuOptions[inputID][1] .. ":")
		print(MainMenuOptions[inputID][2])
		print("")
		print("Press any key to continue...")
		local _, key = os.pullEvent("key")
		while key == nil do
			_, key = os.pullEvent("key")
			sleep()
		end
		sleep()
		RenderMainMenu()
	else
		

		print("Press (x) to exit")

		parallel.waitForAny(MainMenuOptions[inputID][3], WaitForcancel)

		RenderMainMenu()
	end
	
end

function KeyDown()
	while true do
		local event, key = os.pullEvent("key")
		-- print(key .. " Down")
		if key then
			keys[key] = {true, true, os.clock()}
		end
		--sleep()
	end
end

function KeyUp()
	while true do
		local event, key = os.pullEvent("key_up")
		if key then
			if keys[key] then
				keys[key][1] = false
			else
				keys[key] = {false, false, 0}
			end
			
		end
		--sleep()
	end
end

function RednetReceive()
	while true do
		-- local _, RednetData = rednet.receive()
		-- local yaw = (RednetData[2] / 2 + math.pi / 2) / math.pi
		-- local targetYaw = (RednetData[1] / 2 + math.pi / 2) / math.pi

		-- targetYaw = targetYaw + 0.5

		-- if targetYaw > 1 then
		-- 	targetYaw = targetYaw - 1
		-- end


		-- local _, RednetData = rednet.receive()

		-- print("Target Angle: " .. RednetData[1] .. "\nCurrent Angle: " .. RednetData[2])
		sleep()
	end
end





parallel.waitForAll(RenderMainMenu, KeyDown, KeyUp, RednetReceive)



