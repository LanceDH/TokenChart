local addonName = ...
local versionNr = GetAddOnMetadata(addonName, "Version")

local TokenChartAddon = LibStub("AceAddon-3.0"):NewAddon("TokenChartAddon")

local defaults = {
	global = {
		use24h = true,
		history = {},
		lifetimeHighest = 0,
		lifetimeLowest = 10000000000,
		version = versionNr
	}
}

local mainEdgefile = nill
local DEFAULT_BG = "Interface\\DialogFrame\\UI-DialogBox-Background"
local DEFAULT_EDGEFILE = "Interface\\DialogFrame\\UI-DialogBox-Border"
local TEX_TOOLTIPBORDER = "Interface\\GLUES\\COMMON\\Glue-Tooltip-Border"
local TEX_TOOLTIPBG = "Interface\\GLUES\\COMMON\\Glue-Tooltip-Background"
local DEFAULT_LOCKVERTEX_OFF = 0.5
local DEFAULT_LOCKVERTEX_ON = 0.8
local HISTORYFRAME_HEIGHT = 15
local TIME_20MIN = 60*41
local CHART_HEIGHT = 85
local CHARTPOINT_SIZE = 3
local HISTORY_VISUAL_MAX = 15
local MAINFRAME_WIDTH =  200
local HISTORY_ENTRIES_MAX = round((MAINFRAME_WIDTH -14 - CHARTPOINT_SIZE) / CHARTPOINT_SIZE)
local TEX_ARROWUP = "Interface\\PETBATTLES\\BattleBar-AbilityBadge-Strong-Small"
local TEX_ARROWDOWN = "Interface\\PETBATTLES\\BattleBar-AbilityBadge-Weak-Small"
local TEX_QUESTION = "Interface\\Worldmap\\QuestionMark_Gold_64Grey"
local TEX_POINTGREEN = "Interface\\FriendsFrame\\StatusIcon-Online"
local TEX_POINTYELLOW = "Interface\\QUESTFRAME\\UI-Quest-BulletPoint"
local STRING_INFO_CHANGEDOWN = "Gold price is going down"
local STRING_INFO_CHANGEUP = "Gold price is going up"
local STRING_INFO_CHANGEUNKNOWN = "Can't determine change"
local STRING_SUGGEST_GOLD = "Gold price is at a LOW point; \nA good time to buy with gold."
local STRING_SUGGEST_REAL = "Gold price is at a HIGH point; \nA good time to sell a token."

local _updateInterval = 60
local _updateTimer = _updateInterval



local _priceHistory = {}
local _historyFrames = {}
local _chartPoints = {}

local _lastPrice = 0
local _lifetimeLowest = 10000000000
local _lifetimeHighest = 0
local _priceGoingUp = true
local _lastChange = 0
local _option_Use24h = false



function round(num, idp)
	local mult = 10^(idp or 0)
	return math.floor(num * mult + 0.5) / mult
end



function isInteger(x)
	return math.floor(x)==x
end




local function CreateHistoryFrame(nr, parent)
	local frame = CreateFrame("frame", "TokenChart_History"..nr, parent)
	frame:SetWidth(parent:GetWidth())
	frame:SetHeight(HISTORYFRAME_HEIGHT)
	frame:SetPoint("top", 0, -7 - HISTORYFRAME_HEIGHT*nr)
	
	frame.timeNrText = frame:CreateFontString(nil, nil, "GameFontNormal")
	frame.timeNrText:SetPoint("left", 7, 0)
	frame.timeNrText:SetJustifyH("left")
	
	frame.goldText = frame:CreateFontString(nil, nil, "GameFontNormal")
	frame.goldText:SetPoint("left", 70, 0)
	frame.goldText:SetJustifyH("left")
	
	frame.changeText = frame:CreateFontString(nil, nil, "GameFontNormal")
	frame.changeText:SetPoint("left", 150, 0)
	frame.changeText:SetJustifyH("left")
	
	frame.arrow = frame:CreateTexture("TokenChart_History"..nr.."_Arrow", "BACKGROUND")
	frame.arrow:SetTexture(nil)
	frame.arrow:SetPoint("topleft", frame, "topleft", 150-HISTORYFRAME_HEIGHT, 0)
	frame.arrow:SetHeight(HISTORYFRAME_HEIGHT)
	frame.arrow:SetWidth(HISTORYFRAME_HEIGHT)
	--frame.arrow:SetPoint("bottomleft", frame, "bottomright", 0, 0)
	
	return frame
end

local function CreateHistoryFrames(parent)
	local frame = CreateFrame("frame", "TokenChart_HistoryContainer", parent)
	frame:SetWidth(parent:GetWidth())
	frame:SetHeight(HISTORYFRAME_HEIGHT * HISTORY_VISUAL_MAX)
	frame:SetPoint("top", 0, -35)
	

	for i = 0, HISTORY_VISUAL_MAX-1 do
		table.insert(_historyFrames, CreateHistoryFrame(i, frame))
	end
	
	return frame
end

local function ResetHistoryFrames()
	for i = 1, #_historyFrames do
		_historyFrames[i].timeNrText:SetText("")
		_historyFrames[i].goldText:SetText("")
		_historyFrames[i].changeText:SetText("")
		_historyFrames[i].arrow:SetTexture(nil)
	end
end

local function GetPriceChange(old, new)
	--print("Old " .. old .. " New " .. new)

	local perc = old / new
	
	if(perc > 1) then
		perc = perc - 1
		perc = perc * -1
	else
		perc = 1 - perc
	end
	
	perc = perc * 100
	
	return perc
end

local function CheckPeak(change)
	
	--print(change)
	
	if abs(latestPrice.change) < 0.2 then
		
	end
	
	if abs(change) < 0.40 and abs(change) > 0 then
		
		if _lastChange > 0 then
			-- high point
			TokenChart_InfoContainer.suggestText:SetText(STRING_SUGGEST_Real)
			print("high point")
		else
			-- low point
			TokenChart_InfoContainer.suggestText:SetText(STRING_SUGGEST_GOLD)
			print("low point")
		end
	end
	
	--if _priceGoingUp and change < _lastChange  then
	--
	--end

	_lastChange = change
end

local function ResetChartPoints()
	for i=1, #_chartPoints do
		_chartPoints[i]:SetPoint("bottomleft", CHARTPOINT_SIZE +i*CHARTPOINT_SIZE, 0)
		_chartPoints[i]:Hide()
		_chartPoints[i].historyMoment = nil
	end
end

local function GetLowestAndHighestPrice()
	local lowest = 10000000000
	local highest = 0

	for k,v in ipairs(_priceHistory) do
		if v.price < lowest then
			lowest = v.price
		end
		
		if v.price > highest then
			highest = v.price
		end
	end
	
	return lowest, highest
end

local function UpdateChartPoints()
	ResetChartPoints()
	
	if #_priceHistory == 0 then return end
	
	local lowest, highest = GetLowestAndHighestPrice()
	--lowest = 340000000
	--highest = 450000000
	-- lowest = _lifetimeLowest - 5000000
	-- highest = _lifetimeHighest + 5000000
	lowest = lowest - 5000000
	highest = highest + 5000000
	local difference = highest - lowest
	local count = 0
	local prevTime = _priceHistory[#_priceHistory].timeNr
	for i=#_priceHistory, 1, -1 do

	local timeGap = prevTime - _priceHistory[i].timeNr
	
	--while prevTime - _priceHistory[i].timeNr > TIME_20MIN do
	--	count = count + 1
	--	prevTime = prevTime - TIME_20MIN
	--end
	
	
	
	if timeGap > TIME_20MIN then
		for i= 0, round(timeGap/TIME_20MIN) do
			count = count + 1
		end
	end
	
	if count < HISTORY_ENTRIES_MAX then
		 local ypos = 0 + ((CHART_HEIGHT * (_priceHistory[i].price-lowest))/difference)
		 local pointNr = HISTORY_ENTRIES_MAX - count
		_chartPoints[pointNr]:SetPoint("bottomleft", CHARTPOINT_SIZE +pointNr*CHARTPOINT_SIZE, ypos)
		_chartPoints[pointNr]:Show()
		_chartPoints[pointNr].historyMoment = _priceHistory[i]
		count = count + 1
		prevTime = _priceHistory[i].timeNr
	end
	
		
		if count >= HISTORY_ENTRIES_MAX then
			break
			--i = #_priceHistory
		end
	end
end

local function RestInfoContainer()
	TokenChart_InfoContainer.priceText:SetText("Current: ")
	TokenChart_InfoContainer.suggestText:SetText("")
	TokenChart_InfoContainer.arrow:SetTexture(TEX_QUESTION)
	TokenChart_InfoContainer.changeText:SetText(STRING_INFO_CHANGEUNKNOWN)
end

local function UpdateInfoContainer()
	RestInfoContainer()
	
	if #_priceHistory == 0 then return end

	local latestPrice = _priceHistory[#_priceHistory]
	TokenChart_InfoContainer.priceText:SetText("Current: " .. GetMoneyString(latestPrice.price))
	
	if latestPrice.change > 0 then
		TokenChart_InfoContainer.arrow:SetTexture(TEX_ARROWUP)
		TokenChart_InfoContainer.changeText:SetText(STRING_INFO_CHANGEUP)
	end
	if latestPrice.change < 0 then
		TokenChart_InfoContainer.arrow:SetTexture(TEX_ARROWDOWN)
		TokenChart_InfoContainer.changeText:SetText(STRING_INFO_CHANGEDOWN)
	end
	if latestPrice.change == 0 then
		TokenChart_InfoContainer.arrow:SetTexture(TEX_QUESTION)
		TokenChart_InfoContainer.changeText:SetText(STRING_INFO_CHANGEUNKNOWN)
	end
end

local function UpdateHistory()

	ResetHistoryFrames()
	local text = ""
	local start = 1
	local endPoint = #_priceHistory
	
	if #_priceHistory > HISTORY_VISUAL_MAX then
		start = #_priceHistory - HISTORY_VISUAL_MAX +1
		endPoint = HISTORY_VISUAL_MAX
	end
	local count = start
	for i = 1, endPoint do
		local historyFrame = _historyFrames[i]
		historyFrame.goldText:SetText(GetMoneyString(_priceHistory[count].price))
		if _option_Use24h then
			historyFrame.timeNrText:SetText(_priceHistory[count].time24)
		else
			historyFrame.timeNrText:SetText(_priceHistory[count].time12)
		end
		historyFrame.changeText:SetText(abs(round(_priceHistory[count].change,2)).."%")
		if _priceHistory[count].change > 0 then
			historyFrame.arrow:SetTexture(TEX_ARROWUP)
		end
		if _priceHistory[count].change < 0 then
			historyFrame.arrow:SetTexture(TEX_ARROWDOWN)
		end
		
		count = count + 1
	end
	
	UpdateChartPoints()
	UpdateInfoContainer()
	--for k, v in ipairs(_priceHistory) do
	--text = text ..  GetMoneyString(v.price)
		--text = text .. v.time12 .. " : " .. GetMoneyString(v.price) .. " (" .. round(v.change, 2) .. "%) \n"
	--end
	
	--TokenChart_Container.text:SetText(text)
end

local function Time24to12(timeString)
	local hours, mins = string.match(timeString, "(%d+):(%d+)")
	local ampm = "am"
	
	if hours/12 >= 1 then
		ampm = "pm"
	end
	
	hours = hours % 12
	
	if hours == 0 then
		hours = 12
	end

	local result = hours .. ":" .. mins .. ampm

	return result
end

local function AddPriceToHistory(newPrice)

	_lastPrice = newPrice
	--_priceHistory[#_priceHistory].price = newPrice
	local historyMoment = {}
	historyMoment.time24 = date("%H:%M")
	historyMoment.time12 = date("%I:%M%p") --Time24to12(historyMoment.time24)
	historyMoment.date = date("%a %b %d")
	historyMoment.timeNr = time()
	historyMoment.price = newPrice
	if #_priceHistory == 0 or historyMoment.timeNr - _priceHistory[#_priceHistory].timeNr >= 60*21 then
		historyMoment.change = 0
	else
		_lastPrice = _priceHistory[#_priceHistory].price	
		historyMoment.change = GetPriceChange(_lastPrice, newPrice)
	end
	
	--CheckPeak(historyMoment.change)
	
	local overload = #_priceHistory - HISTORY_ENTRIES_MAX

	for i = 0, overload do
         table.remove(_priceHistory, 1)
    end
	
	--table.insert(TokenChartAddon.db.global.history, historyMoment)
	
	table.insert(_priceHistory, historyMoment)
	
	UpdateHistory()
	
	
end

local function ShowChartPointTooltip(historyMoment, chartPoint)
	TokenChart_Tooltip:SetPoint("bottomleft", chartPoint, "topright", 0, 0)
	TokenChart_Tooltip.goldText:SetText(GetMoneyString(historyMoment.price))
	TokenChart_Tooltip.changeText:SetText(abs(round(historyMoment.change, 2)).."%")
	if historyMoment.change > 0 then
		TokenChart_Tooltip.arrow:SetTexture(TEX_ARROWUP)
	end
	if historyMoment.change < 0 then
		TokenChart_Tooltip.arrow:SetTexture(TEX_ARROWDOWN)
	end
	if historyMoment.change == 0 then
		TokenChart_Tooltip.arrow:SetTexture(TEX_QUESTION)
	end
	
	if historyMoment.date == nil then
		historyMoment.date = "Some date"
	end
	
	if _option_Use24h then
		TokenChart_Tooltip.timeText:SetText(historyMoment.date .. "  ".. historyMoment.time24)
	else
		TokenChart_Tooltip.timeText:SetText(historyMoment.date .. "  ".. historyMoment.time12)
	end
	
	TokenChart_Tooltip:Show()
end

local function ResetTooltip()
	TokenChart_Tooltip.goldText:SetText("")
	TokenChart_Tooltip.changeText:SetText("")
	TokenChart_Tooltip.timeText:SetText("")
	TokenChart_Tooltip:Hide()
end

local function CreateChartPoint(nr, parent)
	local frame = CreateFrame("frame", "TokenChart_ChartPoint"..nr, parent)
	frame:SetPoint("bottomleft", CHARTPOINT_SIZE +nr*CHARTPOINT_SIZE, 2)
	frame:SetWidth(CHARTPOINT_SIZE*2)
	frame:SetHeight(CHARTPOINT_SIZE*2)
	frame.dot = frame:CreateTexture("TokenChart_ChartPoint"..nr.."_Bg", "BACKGROUND")
	frame.dot:SetTexture(TEX_POINTGREEN)
	--frame.dot:SetTexture("Interface\\BUTTONS\\UI-OptionsButton")
	--frame.dot:SetTexture("Interface\\BUTTONS\\UI-RADIOBUTTON")
	--frame.dot:SetTexCoord(23/64, 25/64, 7/16, 9/16)
	frame.dot:SetPoint("topleft", frame, "topleft", 0, 0)
	frame.dot:SetPoint("bottomright", frame, "bottomright", 0, 0)
	frame.historyMoment = nil
	frame:SetScript("OnEnter", function() 
		frame.dot:SetTexture(TEX_POINTYELLOW)
		frame.dot:SetPoint("topleft", frame, "topleft", -4, 4)
		frame.dot:SetPoint("bottomright", frame, "bottomright", 4, -4)
		ShowChartPointTooltip(frame.historyMoment, frame) 
	end)
	frame:SetScript("OnLeave", function() 
		frame.dot:SetTexture(TEX_POINTGREEN)
		frame.dot:SetPoint("topleft", frame, "topleft", 0, 0)
		frame.dot:SetPoint("bottomright", frame, "bottomright", 0, 0)
		ResetTooltip() 
	end)
	
	return frame
end

local function CreateChart(parent)
	local frame = CreateFrame("frame", "TokenChart_Chart", parent)
	frame:SetWidth(parent:GetWidth()-4)
	frame:SetHeight(CHART_HEIGHT)
	frame:SetPoint("bottom", 0, 3)
	
	frame.bg = frame:CreateTexture("TokenChart_Chart_bg", "BACKGROUND")
	--frame.bg:SetTexture("Interface\\Store\\Store-Splash")
	--frame.bg:SetTexCoord(0, 288/1024, 791/1024, 940/1024)
	--frame.bg:SetTexture("Interface\\Store\\STORE-MAIN")
	--frame.bg:SetTexCoord(289/1024, 568/1024, 793/1024, 932/1024)
	--frame.bg:SetTexCoord(580/1024, 863/1024, 308/1024, 428/1024)
	frame.bg:SetTexture("Interface\\RAIDFRAME\\UI-RaidFrame-GroupOutline")
	frame.bg:SetTexCoord(0, 170/256, 0, 80/128)
	frame.bg:SetPoint("topleft", frame, "topleft", 3, 0)
	frame.bg:SetPoint("bottomright", frame, "bottomright", -3, 3)
	
	
	
	for i=1, HISTORY_ENTRIES_MAX do
		table.insert(_chartPoints, CreateChartPoint(i, frame))
	end
	
end

local function CreateInfoContainer(parent)
	local frame = CreateFrame("frame", "TokenChart_InfoContainer", parent)
	frame:SetWidth(parent:GetWidth()-4)
	frame:SetHeight(CHART_HEIGHT)
	frame:SetPoint("top", parent, "bottom", 0, -20)
	
	frame.arrow = frame:CreateTexture("TokenChart_TokenChart_InfoContainer_Arrow", "BACKGROUND")
	--frame.bg:SetTexture("Interface\\Store\\Store-Splash")
	--frame.bg:SetTexCoord(0, 288/1024, 791/1024, 940/1024)
	--frame.bg:SetTexture("Interface\\Store\\STORE-MAIN")
	--frame.bg:SetTexCoord(289/1024, 568/1024, 793/1024, 932/1024)
	--frame.bg:SetTexCoord(580/1024, 863/1024, 308/1024, 428/1024)
	
	frame.priceText = frame:CreateFontString(nil, nil, "QuestTitleFontBlackShadow")
	frame.priceText:SetPoint("top", frame, "top", 0, -3)
	--frame.priceText:SetPoint("topright", frame, "bottomright", 0, -20)
	--frame.priceText:SetJustifyH("middle")
	--frame:SetWidth(parent:GetWidth()-4)
	frame.priceText:SetText("Current: " .. GetMoneyString(387640000))
	
	frame.arrow:SetTexture(TEX_QUESTION)
	--frame.arrow:SetTexCoord(0, 170/256, 0, 80/128)
	frame.arrow:SetPoint("topleft", frame, "topleft", 5, -25)
	frame.arrow:SetHeight(25)
	frame.arrow:SetWidth(25)
	frame.changeText = frame:CreateFontString(nil, nil, "GameFontNormal")
	frame.changeText:SetPoint("left", frame.arrow, "right", 0, 0)
	frame.changeText:SetJustifyH("left")
	frame.changeText:SetText(STRING_INFO_CHANGEUNKNOWN)
	frame.suggestText = frame:CreateFontString(nil, nil, "GameFontNormal")
	frame.suggestText:SetPoint("topleft", frame, "topleft", 5, -50)
	frame.suggestText:SetJustifyH("left")
	frame.suggestText:SetText("Info goes here")

end

local function ToggleMainFrame()
	if TokenChart_Container:IsShown() then
		PlaySound("igQuestLogClose");
		TokenChart_Container:Hide()
	else
		PlaySound("igQuestLogOpen");
		TokenChart_Container:Show()
	end
end

local function createFrame()

local L_TokenChart = CreateFrame("frame", "TokenChart_Container", UIParent)
 
TokenChart_Container:SetBackdrop({bgFile = TEX_TOOLTIPBG,
      edgeFile = DEFAULT_EDGEFILE,
	  tileSize = 0, edgeSize = 16,
      insets = { left = 3, right = 3, top = 3, bottom = 3 }
	  })
	

	
--TokenChart_Container:Hide()
	  
TokenChart_Container.bg = TokenChart_Container:CreateTexture("TokenChart_Container_bg", "BORDER")
TokenChart_Container.bg:SetTexture("Interface\\Store\\STORE-MAIN")
TokenChart_Container.bg:SetTexCoord(0, 186/1024, 470/1024, 958/1024)
TokenChart_Container.bg:SetPoint("topleft", TokenChart_Container, "topleft", 4,-3)
TokenChart_Container.bg:SetPoint("bottomright", TokenChart_Container, "bottomright", -4,5)



	 
TokenChart_Container:SetFrameLevel(5)
TokenChart_Container:SetPoint("Center", 250, 0)
TokenChart_Container:SetWidth(MAINFRAME_WIDTH)
TokenChart_Container:SetHeight(488)
TokenChart_Container:SetClampedToScreen(true)
TokenChart_Container:EnableMouse(true)
TokenChart_Container:SetMovable(true)
TokenChart_Container:RegisterForDrag("LeftButton")
TokenChart_Container:SetScript("OnDragStart", TokenChart_Container.StartMoving )
TokenChart_Container:SetScript("OnDragStop", TokenChart_Container.StopMovingOrSizing)
--TokenChart_Container:SetPoint("bottomleft", QuestScrollFrame, "bottomleft", 0, 0)
--TokenChart_Container:SetPoint("topright", QuestScrollFrame, "bottomright", 0, 250)
TokenChart_Container.text = TokenChart_Container:CreateFontString(nil, nil, "GameFontNormal")
TokenChart_Container.text:SetPoint("top", 0, -5)
TokenChart_Container.text:SetWidth(MAINFRAME_WIDTH-10)
TokenChart_Container.text:SetHeight(30)
TokenChart_Container.text:SetJustifyH("middle")
TokenChart_Container.text:SetText("Token Chart")


TokenChart_Container.header = TokenChart_Container:CreateTexture("TokenChart_Container_Header", "ARTWORK")
TokenChart_Container.header:SetTexture("Interface\\Store\\STORE-MAIN")
TokenChart_Container.header:SetTexCoord(582/1024, 751/1024, 431/1024, 464/1024)
TokenChart_Container.header:SetPoint("topleft", TokenChart_Container.text, "topleft", 0,0)
TokenChart_Container.header:SetPoint("bottomright", TokenChart_Container.text, "bottomright", 0,0)

TokenChart_Container.icon = TokenChart_Container:CreateTexture("TokenChart_Container_Icon", "OVERLAY")
TokenChart_Container.icon:SetTexture("Interface\\Store\\category-icon-wow")
TokenChart_Container.icon:SetTexCoord(1/4, 3/4, 1/4, 3/4)
TokenChart_Container.icon:SetPoint("left", TokenChart_Container.header, "left", 10,0)
TokenChart_Container.icon:SetHeight(30)
TokenChart_Container.icon:SetWidth(30)
--TokenChart_Container.icon:SetPoint("bottomright", TokenChart_Container.text, "bottomright", 0,0)


local TokenChart_CloseButton = CreateFrame("Button", "TokenChart_CloseButton", TokenChart_Container)
	TokenChart_CloseButton:SetWidth(25)
	TokenChart_CloseButton:SetHeight(25)
	TokenChart_CloseButton:SetHitRectInsets(4, 4, 4, 4)
	TokenChart_CloseButton:SetNormalTexture("Interface\\BUTTONS\\UI-Panel-MinimizeButton-Up")
	TokenChart_CloseButton:SetHighlightTexture("Interface\\BUTTONS\\UI-Panel-MinimizeButton-Highlight")
	TokenChart_CloseButton:SetPushedTexture("Interface\\BUTTONS\\UI-Panel-MinimizeButton-Down")
	TokenChart_CloseButton:SetPoint("topright", TokenChart_Container, "topright", 0, 0)
	TokenChart_CloseButton:Show()
	TokenChart_CloseButton:SetScript("OnClick",  function() 
	
		ToggleMainFrame()
	end)



local L_TokenChart_Tooltip = CreateFrame("frame", "TokenChart_Tooltip", TokenChart_Container)
 
TokenChart_Tooltip:SetBackdrop({bgFile = TEX_TOOLTIPBG,
      edgeFile = TEX_TOOLTIPBORDER,
	  tileSize = 0, edgeSize = 16,
      insets = { left = 8, right = 5, top = 5, bottom = 8 }
	  })

TokenChart_Tooltip:SetFrameLevel(8)
TokenChart_Tooltip:SetPoint("bottomleft", TokenChart_Container, "topleft", 0, 0)
TokenChart_Tooltip:SetWidth(160)
TokenChart_Tooltip:SetHeight(55)

TokenChart_Tooltip.goldText = TokenChart_Tooltip:CreateFontString(nil, nil, "GameFontNormal")
TokenChart_Tooltip.goldText:SetPoint("topleft", 15, -30)
--TokenChart_Tooltip.goldText:SetPoint("bottomright", -7, 7)
TokenChart_Tooltip.goldText:SetJustifyH("left")
TokenChart_Tooltip.goldText:SetJustifyV("top")
TokenChart_Tooltip.goldText:SetText("Information goes here")

TokenChart_Tooltip.timeText = TokenChart_Tooltip:CreateFontString(nil, nil, "GameFontNormal")
TokenChart_Tooltip.timeText:SetPoint("topleft", 12, -10)
--TokenChart_Tooltip.goldText:SetPoint("bottomright", -7, 7)
TokenChart_Tooltip.timeText:SetJustifyH("left")
TokenChart_Tooltip.timeText:SetJustifyV("top")
TokenChart_Tooltip.timeText:SetText("HH:MMam")

TokenChart_Tooltip.arrow = TokenChart_Tooltip:CreateTexture("TokenChart_Tooltip_Arrow", "ARTWORK")
TokenChart_Tooltip.arrow:SetTexture(TEX_QUESTION)
TokenChart_Tooltip.arrow:SetPoint("topleft", 85, -30)
TokenChart_Tooltip.arrow:SetHeight(HISTORYFRAME_HEIGHT)
TokenChart_Tooltip.arrow:SetWidth(HISTORYFRAME_HEIGHT)

TokenChart_Tooltip.changeText = TokenChart_Tooltip:CreateFontString(nil, nil, "GameFontNormal")
TokenChart_Tooltip.changeText:SetPoint("left",TokenChart_Tooltip.arrow, "right", 2, 0)
--TokenChart_Tooltip.goldText:SetPoint("bottomright", -7, 7)
TokenChart_Tooltip.changeText:SetJustifyH("left")
TokenChart_Tooltip.changeText:SetJustifyV("top")
TokenChart_Tooltip.changeText:SetText("change")

TokenChart_Tooltip:Hide()
--TokenChart_Tooltip.bg = TokenChart_Tooltip:CreateTexture("TokenChart_Tooltip_bg", "BACKGROUND")
--TokenChart_Tooltip.bg:SetTexture("Interface\\ACHIEVEMENTFRAME\\UI-Achievement-Parchment-Horizontal-Desaturated")
--TokenChart_Tooltip.bg:SetPoint("topleft", 2,-2)
--TokenChart_Tooltip.bg:SetPoint("bottomright", -2,2)


local historyContainer = CreateHistoryFrames(TokenChart_Container)

CreateInfoContainer(historyContainer)

CreateChart(TokenChart_Container)

TokenChart_Tooltip:SetPoint("bottomleft", TokenChart_Chart, "topleft", 0, 0)



end


------------------------------------------------------------------------------------------------------------------------------



-----------------------------------


function TokenChartAddon:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("AceDBRegionInfo", defaults)
end

function TokenChartAddon:OnEnable()
	_priceHistory = self.db.global.history
	_option_Use24h = self.db.global.use24h
	_lifetimeHighest = self.db.global.lifetimeHighest
	_lifetimeLowest = self.db.global.lifetimeLowest
	
	
	UpdateHistory()
	-- _price = C_WowTokenPublic.GetCurrentMarketPrice()

	-- if _price > _lifetimeHighest then
			-- _lifetimeHighest = _price
		-- end
		
		-- if _price < _lifetimeLowest then
			-- _lifetimeLowest = _price
		-- end
	
	-- if(#_priceHistory == 0 or _price ~= _priceHistory[#_priceHistory].price) then
		
	
		-- AddPriceToHistory(_price)
	-- end
end

-----------------------------------


-------------------------------------------------------------------------------------------------------------------------

local _TokenChart_Events = CreateFrame("FRAME", "TokenChart_Events"); 
TokenChart_Events:RegisterEvent("TOKEN_MARKET_PRICE_UPDATED");
TokenChart_Events:RegisterEvent("PLAYER_LOGOUT");
TokenChart_Events:RegisterEvent("ADDON_LOADED");
TokenChart_Events:SetScript("OnEvent", function(self, event, ...) self[event](self, ...) end)

TokenChart_Events:SetScript("OnUpdate", function(self,elapsed) 
	_updateTimer = _updateTimer + elapsed
	if _updateTimer >= _updateInterval then
		C_WowTokenPublic.UpdateMarketPrice()
	end
	end)

--function TokenChart_Events:PLAYER_ENTERING_WORLD(loadedAddon)
--	if(not TokenChart_Container) then createFrame() end
--	_price = C_WowTokenPublic.GetCurrentMarketPrice()
--	TokenChart_Container.text:SetText(GetMoneyString(_price))
--end

function TokenChart_Events:TOKEN_MARKET_PRICE_UPDATED(loadedAddon)
	--if(not TokenChart_Container) then createFrame() end
	

	_price = C_WowTokenPublic.GetCurrentMarketPrice()

	if _price > _lifetimeHighest then
			_lifetimeHighest = _price
		end
		
		if _price < _lifetimeLowest then
			_lifetimeLowest = _price
		end
	
	if(#_priceHistory == 0 or _price ~= _priceHistory[#_priceHistory].price) then
		
	
		AddPriceToHistory(_price)
	end
	--TokenChart_Container.text:SetText(GetMoneyString(_price))
end

function TokenChart_Events:PLAYER_LOGOUT(loadedAddon)
	--TokenChart_History = _priceHistory
	-- local temp = {}
	-- temp.lowest = _lifetimeLowest
	-- temp.highest = _lifetimeHighest
	-- temp.version = versionNr
	-- TokenChart_Lifetime = temp
	TokenChartAddon.db.global.history = _priceHistory
	TokenChartAddon.db.global.lifetimeHighest = _lifetimeHighest
	TokenChartAddon.db.global.lifetimeLowest = _lifetimeLowest
	TokenChartAddon.db.global.version = versionNr
	TokenChartAddon.db.global.use24h = _option_Use24h
end

function TokenChart_Events:ADDON_LOADED(loadedAddon)
	if loadedAddon ~= addonName then return end
	
	-- if TokenChart_History ~= nil then
		-- _priceHistory = TokenChart_History 
		-- if #_priceHistory ~= 0 then
			-- local latest = _priceHistory[#_priceHistory]
			-- if time() - latest.timeNr < TIME_20MIN then
				-- _priceHistory[#_priceHistory].price = latest.price
			-- end
		-- end
		
		-- if TokenChart_Lifetime.lowest ~= nil then
			-- _lifetimeLowest = TokenChart_Lifetime.lowest
		-- end
	
		-- if TokenChart_Lifetime.highest ~= nil then
			-- _lifetimeHighest = TokenChart_Lifetime.highest
		-- end
	-- end
	
	
	
	createFrame()
	
	UpdateHistory()
	
end


SLASH_TCHARTSLASH1 = '/tchart';
local function slashcmd(msg, editbox)
	if msg == 'time' then
		
		_option_Use24h = not _option_Use24h
		
		TokenChartAddon.db.global.use24h = _option_Use24h
	
		
		UpdateHistory()
	elseif msg == 'u' then
		
		-- UpdateHistory()
		
	elseif msg == 'remove' then
	 -- table.remove(_priceHistory, #_priceHistory)
	 -- UpdateHistory()
	
	elseif msg == 'reset' then
	
	-- _priceHistory = {}
	
	-- UpdateHistory()
	
	-- _price = C_WowTokenPublic.GetCurrentMarketPrice()
	
	-- if(#_priceHistory == 0 or _price ~= _priceHistory[#_priceHistory].price) then
	
		-- AddPriceToHistory(_price)
	-- end
	
	else
		
		ToggleMainFrame()
		--if ( not InterfaceOptionsFramePanelContainer.displayedPanel ) then
		--	InterfaceOptionsFrame_OpenToCategory(CONTROLS_LABEL);
		--end
		--InterfaceOptionsFrame_OpenToCategory(addonName) 
	  
   end
end
SlashCmdList["TCHARTSLASH"] = slashcmd