-- HackrLFG: a compact, modern view of the Group Finder's search results.
--
-- Every listing becomes one row:
--   [TANK] [HEALER] [DPS] [DPS] [DPS]   Title / activity          age
--                                       notes...
-- Each slot shows the member's class icon and level on a role-coloured chip.
-- Empty slots stay in place, tinted by the role they are waiting for.
--
-- The search box filters on activity, leader and member names and zones.
-- Several words must ALL match; a word starting with "-" excludes. Listing
-- titles and notes reach addons only as protected "|K...|k" tokens, so they
-- are shown but cannot be searched.
--
-- Forever runs a modern engine: inside dungeons and raids some listing values
-- are "secret" and erroring to compare, concatenate or lowercase. Everything
-- read from C_LFGList goes through Readable() before it is used in Lua logic;
-- secret values are still handed straight to SetText, which accepts them.

local ADDON_NAME = ...

---------------------------------------------------------------------------
-- Theme
---------------------------------------------------------------------------

local FONT = "Fonts\\ARIALN.TTF"

local C = {
	bg      = { 0.047, 0.051, 0.063, 0.97 },
	panel   = { 1, 1, 1, 0.035 },
	hover   = { 1, 1, 1, 0.065 },
	line    = { 1, 1, 1, 0.08 },
	text    = { 0.94, 0.95, 0.97 },
	muted   = { 0.58, 0.62, 0.70 },
	faint   = { 0.40, 0.43, 0.50 },
	accent  = { 0.2, 1, 0.6 }, -- Hackr family green (same as HackrAH)
}

local ROLE_COLOR = {
	TANK    = { 0.23, 0.46, 0.96 }, -- blue
	HEALER  = { 0.19, 0.72, 0.43 }, -- green
	DAMAGER = { 0.89, 0.26, 0.31 }, -- red
	NONE    = { 0.42, 0.45, 0.52 }, -- unknown role
}
local ROLE_LETTER = { TANK = "T", HEALER = "H", DAMAGER = "D" }
local SLOT_ORDER = { "TANK", "HEALER", "DAMAGER", "DAMAGER", "DAMAGER" }

local WIDTH      = 640
local NUM_ROWS   = 12
local ROW_H      = 34
local ROW_GAP    = 2
local PAD        = 12
local SLOT_W     = 44
local SLOT_H     = 22
local SLOT_GAP   = 3
local SLOTS_W    = #SLOT_ORDER * SLOT_W + (#SLOT_ORDER - 1) * SLOT_GAP
local HEADER_H   = 44
local SEARCH_H   = 30
local COLHEAD_H  = 22
local FOOTER_H   = 26
local LIST_H     = NUM_ROWS * ROW_H + (NUM_ROWS - 1) * ROW_GAP
local HEIGHT     = HEADER_H + SEARCH_H + 8 + COLHEAD_H + LIST_H + FOOTER_H + 6

---------------------------------------------------------------------------
-- Secret-safe helpers
---------------------------------------------------------------------------

local canaccess = canaccessvalue or function() return true end

local function Readable(value, fallback)
	if value == nil or not canaccess(value) then
		return fallback
	end
	return value
end

local function ReadableString(value)
	value = Readable(value, nil)
	if type(value) == "string" and value ~= "" then
		return value
	end
end

-- Listing titles and notes can arrive as protected "|K...|k" tokens: the
-- client draws them as text, but Lua only sees the token. Try to get plain
-- text back by letting a FontString resolve it; nil means it stays protected.
local decoder = UIParent:CreateFontString(nil, "OVERLAY")
decoder:SetFont(FONT, 12, "")
decoder:Hide()

local function IsProtected(s)
	return s:find("|K", 1, true) ~= nil
end

local function PlainText(value)
	local s = ReadableString(value)
	if not s then return nil end
	if not IsProtected(s) then return s end
	decoder:SetText(s)
	local t = decoder:GetText()
	if t and canaccess(t) and type(t) == "string" and not IsProtected(t) then return t end
	return nil
end

local CLASS_ATLAS = {}
for _, class in ipairs(CLASS_SORT_ORDER or {}) do
	CLASS_ATLAS[class] = "groupfinder-icon-class-" .. class:lower()
end

local function SetClassIcon(tex, class)
	class = Readable(class, nil)
	if not class then
		tex:Hide()
		return
	end
	local atlas = CLASS_ATLAS[class]
	if atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
		tex:SetAtlas(atlas, false)
		tex:SetTexCoord(0, 1, 0, 1)
		tex:Show()
		return
	end
	local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
	if coords then
		tex:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
		tex:SetTexCoord(coords[1] + 0.015, coords[2] - 0.015, coords[3] + 0.015, coords[4] - 0.015)
		tex:Show()
		return
	end
	tex:Hide()
end

local function ClassColor(class)
	class = Readable(class, nil)
	local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if c then return c.r, c.g, c.b end
	return C.text[1], C.text[2], C.text[3]
end

local function FormatAge(age)
	age = Readable(age, nil)
	if type(age) ~= "number" then return "" end
	if age < 60 then return "now" end
	if age < 3600 then return math.floor(age / 60) .. "m" end
	return math.floor(age / 3600) .. "h"
end

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------

local activityNames = {}
local function ActivityName(activityID)
	activityID = Readable(activityID, nil)
	if not activityID then return nil end
	local cached = activityNames[activityID]
	if cached ~= nil then return cached or nil end
	local name
	local info = C_LFGList.GetActivityInfoTable and C_LFGList.GetActivityInfoTable(activityID)
	if info then
		if LFGUtil_GetActivityInfoName then
			local ok, n = pcall(LFGUtil_GetActivityInfoName, info)
			if ok then name = ReadableString(n) end
		end
		name = name or ReadableString(info.fullName) or ReadableString(info.shortName)
	end
	activityNames[activityID] = name or false
	return name
end

-- The most players an activity allows (5 for a dungeon, 10 for UBRS, ...);
-- 0 when the client doesn't say.
local activitySizes = {}
local function ActivityMaxPlayers(activityID)
	activityID = Readable(activityID, nil)
	if not activityID then return 0 end
	if activitySizes[activityID] then return activitySizes[activityID] end
	local size = 0
	local info = C_LFGList.GetActivityInfoTable and C_LFGList.GetActivityInfoTable(activityID)
	if info then
		local n = Readable(info.maxNumPlayers, nil)
		if type(n) == "number" then size = n end
	end
	activitySizes[activityID] = size
	return size
end

local ROLE_TOKEN = { TANK = "TANK", HEALER = "HEALER", DAMAGER = "DAMAGER", DPS = "DAMAGER" }

local function MemberRole(info)
	local assigned = Readable(info.assignedRole, nil)
	if type(assigned) == "string" and ROLE_TOKEN[assigned] then
		return ROLE_TOKEN[assigned]
	end
	local roles = Readable(info.lfgRoles, nil)
	if type(roles) == "table" then
		if roles.tank then return "TANK" end
		if roles.healer then return "HEALER" end
		if roles.dps then return "DAMAGER" end
	end
	return "NONE"
end

local function ReadMember(resultID, index)
	local getter = C_LFGList.GetSearchResultPlayerInfo or C_LFGList.GetSearchResultMemberInfo
	if not getter then return nil end
	local ok, info = pcall(getter, resultID, index)
	if not ok or type(info) ~= "table" then return nil end
	return {
		name   = info.name,         -- may be secret: only SetText it
		class  = info.classFilename,
		level  = info.level,
		area   = info.areaName,
		role   = MemberRole(info),
		roles  = Readable(info.lfgRoles, nil),
	}
end

-- Fill TANK / HEALER / DPS / DPS / DPS in that order. Members whose role does
-- not fit a free matching slot (a 2nd tank, an unknown role) take the next
-- empty slot, DPS slots first, and keep their own colour.
-- Big groups (UBRS, raids) get two parties' worth of slots: T H D D D twice,
-- so the second tank and healer have a visible home in row two.
local function BuildSlots(members, big)
	local slots = {}
	for pass = 1, big and 2 or 1 do
		for _, role in ipairs(SLOT_ORDER) do
			slots[#slots + 1] = { role = role }
		end
	end
	local leftovers = {}
	for _, m in ipairs(members) do
		local placed = false
		for _, slot in ipairs(slots) do
			if not slot.member and slot.role == m.role then
				slot.member, placed = m, true
				break
			end
		end
		if not placed then leftovers[#leftovers + 1] = m end
	end
	local overflow = 0
	for _, m in ipairs(leftovers) do
		local placed = false
		for _, slot in ipairs(slots) do -- empty DPS slots first, then T/H
			if slot.role == "DAMAGER" and not slot.member then
				slot.member, placed = m, true
				break
			end
		end
		if not placed then
			for _, slot in ipairs(slots) do
				if not slot.member then
					slot.member, placed = m, true
					break
				end
			end
		end
		if not placed then overflow = overflow + 1 end
	end
	return slots, overflow
end

local function ReadResult(resultID)
	local ok, info = pcall(C_LFGList.GetSearchResultInfo, resultID)
	if not ok or type(info) ~= "table" then return nil end
	if Readable(info.isDelisted, false) == true then return nil end

	local r = {
		id      = resultID,
		info    = info,
		leader  = info.leaderName,
		notes   = info.comment,
		title   = info.name,
		age     = info.age,
		hasSelf = Readable(info.hasSelf, false) == true,
		acts    = {},
		members = {},
	}

	local activityIDs = Readable(info.activityIDs, nil)
	if type(activityIDs) ~= "table" then activityIDs = { info.activityID } end
	r.maxPlayers = 0
	for _, id in ipairs(activityIDs) do
		local n = ActivityName(id)
		if n then r.acts[#r.acts + 1] = n end
		r.maxPlayers = math.max(r.maxPlayers, ActivityMaxPlayers(id))
	end

	local num = Readable(info.numMembers, nil)
	if type(num) == "number" then
		r.num = num
		for i = 1, num do
			local m = ReadMember(resultID, i)
			if m then r.members[#r.members + 1] = m end
		end
	end
	r.isSolo = r.num == 1
	-- A solo player can sign up for several roles (e.g. Tank OR DPS). Keep
	-- them all, in slot order, so the chip can show every one.
	local solo = r.isSolo and r.members[1]
	if solo and type(solo.roles) == "table" then
		local offered = {}
		if solo.roles.tank then offered[#offered + 1] = "TANK" end
		if solo.roles.healer then offered[#offered + 1] = "HEALER" end
		if solo.roles.dps then offered[#offered + 1] = "DAMAGER" end
		if #offered > 1 then
			solo.offered = offered
			solo.role = offered[1] -- sits in its first role's slot
		end
	end
	-- Two rows when the dungeon allows more than 5, or the group already has
	-- more than 5 (in case the activity's size can't be read).
	r.big = r.maxPlayers > 5 or (r.num or 0) > 5
	r.slots, r.overflow = BuildSlots(r.members, r.big)
	if r.big then
		local tally = { TANK = 0, HEALER = 0, DAMAGER = 0, NONE = 0 }
		for _, m in ipairs(r.members) do tally[m.role] = (tally[m.role] or 0) + 1 end
		r.tally = tally
	end

	-- Search haystack: only readable strings, lowercased once.
	local parts = {}
	local function add(v)
		local s = PlainText(v)
		if s then parts[#parts + 1] = s end
	end
	local rawNotes = ReadableString(info.comment)
	r.notesHidden = rawNotes ~= nil and PlainText(rawNotes) == nil
	add(info.comment); add(info.name); add(info.leaderName)
	for _, a in ipairs(r.acts) do add(a) end
	for _, m in ipairs(r.members) do add(m.name); add(m.area) end
	local okHay, hay = pcall(function() return table.concat(parts, "\n"):lower() end)
	r.hay = okHay and hay or ""
	r.searchable = #parts > 0
	return r
end

local function GetResultIDs()
	-- Unfiltered on purpose: Blizzard's filtered list applies its own rules.
	local fn = C_LFGList.GetSearchResults or C_LFGList.GetFilteredSearchResults
	if not fn then return {} end
	local ok, a, b = pcall(fn)
	if not ok then return {} end
	if type(b) == "table" then return b end
	if type(a) == "table" then return a end
	return {}
end

---------------------------------------------------------------------------
-- UI primitives
---------------------------------------------------------------------------

local function Fill(parent, color, layer, sublevel)
	local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0)
	t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
	return t
end

local function Outline(frame, color)
	local edges = {}
	for i = 1, 4 do
		local t = frame:CreateTexture(nil, "BORDER")
		t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
		edges[i] = t
	end
	edges[1]:SetPoint("TOPLEFT"); edges[1]:SetPoint("TOPRIGHT"); edges[1]:SetHeight(1)
	edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(1)
	edges[3]:SetPoint("TOPLEFT"); edges[3]:SetPoint("BOTTOMLEFT"); edges[3]:SetWidth(1)
	edges[4]:SetPoint("TOPRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT"); edges[4]:SetWidth(1)
	return edges
end

local function SetOutline(edges, r, g, b, a)
	for _, t in ipairs(edges) do t:SetColorTexture(r, g, b, a) end
end

local function Label(parent, size, color, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFont(FONT, size, "")
	fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
	fs:SetJustifyH(justify or "LEFT")
	fs:SetWordWrap(false)
	return fs
end

local function FlatButton(parent, text, width)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width, 24)
	b.bg = Fill(b, C.panel)
	b.bg:SetAllPoints()
	b.edges = Outline(b, C.line)
	b.label = Label(b, 12, C.text, "CENTER")
	b.label:SetPoint("CENTER")
	b.label:SetText(text)
	b:SetScript("OnEnter", function(self) self.bg:SetColorTexture(1, 1, 1, 0.09) end)
	b:SetScript("OnLeave", function(self) self.bg:SetColorTexture(unpack(C.panel)) end)
	return b
end

---------------------------------------------------------------------------
-- Main window
---------------------------------------------------------------------------

local db
local results, visible = {}, {}
local offset = 0

local F = CreateFrame("Frame", "HackrLFGFrame", UIParent)
F:SetSize(WIDTH, HEIGHT)
F:SetFrameStrata("HIGH")
F:SetToplevel(true)
F:SetClampedToScreen(true)
F:SetMovable(true)
F:EnableMouse(true)
F:RegisterForDrag("LeftButton")
F:Hide()
tinsert(UISpecialFrames, "HackrLFGFrame")

Fill(F, C.bg):SetAllPoints()
Outline(F, { 0.2, 1, 0.6, 0.35 }) -- Hackr family: green-tinted frame edge

-- soft drop shadow
for i, a in ipairs({ 0.22, 0.12, 0.05 }) do
	local s = F:CreateTexture(nil, "BACKGROUND", nil, -8)
	s:SetColorTexture(0, 0, 0, a)
	s:SetPoint("TOPLEFT", -i * 2, i * 2)
	s:SetPoint("BOTTOMRIGHT", i * 2, -i * 2)
end

F:SetScript("OnDragStart", function(self) self:StartMoving() end)
F:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local point, _, relPoint, x, y = self:GetPoint()
	db.pos = { point, relPoint, x, y }
	db.moved = true
end)

-- Header: same title bar as HackrAH ("> HackrAH  v0.1.5") -----------------
local HACKR_GREEN = { 0.2, 1, 0.6 }
local STD_FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

local function HackrText(parent, size, color, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFont(STD_FONT, size, "")
	fs:SetShadowOffset(1, -1)
	fs:SetShadowColor(0, 0, 0, 0.9)
	fs:SetTextColor(color[1], color[2], color[3])
	fs:SetJustifyH(justify or "LEFT")
	fs:SetWordWrap(false)
	return fs
end

local titleBar = Fill(F, { 0.071, 0.078, 0.098, 1 }, "BACKGROUND", 1)
titleBar:SetPoint("TOPLEFT", 1, -1)
titleBar:SetPoint("TOPRIGHT", -1, -1)
titleBar:SetHeight(HEADER_H - 1)

local title = HackrText(F, 17, C.text)
title:SetPoint("LEFT", F, "TOPLEFT", 14, -HEADER_H / 2)
title:SetText("|cff33ff99>|r |cff33ff99Hackr|r|cffffffffLFG|r")

local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local version = GetMeta and GetMeta(ADDON_NAME, "Version")
local versionText = HackrText(F, 10, C.muted)
versionText:SetPoint("LEFT", title, "RIGHT", 8, -2)
-- The packager writes the git tag (e.g. "v1.0.1") into the .toc; running
-- straight from the source folder it is still "@project-version@".
if type(version) == "string" and version:find("@", 1, true) then
	versionText:SetText("dev")
elseif type(version) == "string" then
	versionText:SetText("v" .. version:gsub("^v", ""))
end

local countText = Label(F, 12, C.muted)
countText:SetPoint("LEFT", versionText, "RIGHT", 14, 1)

local closeBtn = CreateFrame("Button", nil, F)
closeBtn:SetSize(28, 28)
closeBtn:SetPoint("TOPRIGHT", -7, -(HEADER_H - 28) / 2)
closeBtn.label = HackrText(closeBtn, 17, C.muted, "CENTER")
closeBtn.label:SetPoint("CENTER")
closeBtn.label:SetText("x")
closeBtn:SetScript("OnEnter", function(self) self.label:SetTextColor(1, 0.38, 0.38) end)
closeBtn:SetScript("OnLeave", function(self) self.label:SetTextColor(C.muted[1], C.muted[2], C.muted[3]) end)
closeBtn:SetScript("OnClick", function() F:Hide() end)

local headerLine = Fill(F, { HACKR_GREEN[1], HACKR_GREEN[2], HACKR_GREEN[3], 0.25 }, "ARTWORK")
headerLine:SetHeight(1)
headerLine:SetPoint("TOPLEFT", 0, -HEADER_H)
headerLine:SetPoint("TOPRIGHT", 0, -HEADER_H)

-- Toolbar: [Dungeon picker] [search box] [Search] ---------------------------
local TOOLBAR_Y = -(HEADER_H + 10)

local dropBtn = FlatButton(F, "", 200)
dropBtn:SetHeight(SEARCH_H)
dropBtn:SetPoint("TOPLEFT", PAD, TOOLBAR_Y)
dropBtn.label:ClearAllPoints()
dropBtn.label:SetPoint("LEFT", 10, 0)
dropBtn.label:SetPoint("RIGHT", -26, 0)
dropBtn.label:SetJustifyH("LEFT")
dropBtn.label:SetFont(FONT, 13, "")
for _, spec in ipairs({ { -16.2, -math.pi / 4 }, { -11.8, math.pi / 4 } }) do
	local stroke = dropBtn:CreateTexture(nil, "OVERLAY")
	stroke:SetColorTexture(C.muted[1], C.muted[2], C.muted[3], 1)
	stroke:SetSize(6, 1.5)
	stroke:SetPoint("CENTER", dropBtn, "RIGHT", spec[1], 0)
	stroke:SetRotation(spec[2])
end

local goBtn = FlatButton(F, "Search", 84)
goBtn:SetHeight(SEARCH_H)
goBtn:SetPoint("TOPRIGHT", -PAD, TOOLBAR_Y)
-- Primary button, styled like HackrAH's: solid green, dark text.
local function MakePrimary(b)
	b.label:SetFont(FONT, 13, "")
	b.label:SetTextColor(0.02, 0.07, 0.04)
	b.label:SetShadowOffset(0, 0)
	b.bg:SetColorTexture(0.16, 0.85, 0.52, 1)
	SetOutline(b.edges, 0.3, 1, 0.68, 1)
	b:SetScript("OnEnter", function(self) self.bg:SetColorTexture(0.30, 0.92, 0.64, 1) end)
	b:SetScript("OnLeave", function(self) self.bg:SetColorTexture(0.16, 0.85, 0.52, 1) end)
end
MakePrimary(goBtn)

-- Search box --------------------------------------------------------------
local search = CreateFrame("EditBox", "HackrLFGSearchBox", F)
search:SetHeight(SEARCH_H)
search:SetPoint("TOPLEFT", dropBtn, "TOPRIGHT", 8, 0)
search:SetPoint("TOPRIGHT", goBtn, "TOPLEFT", -8, 0)
search:SetAutoFocus(false)
search:SetFont(FONT, 13, "")
search:SetTextColor(unpack(C.text))
search:SetTextInsets(28, 26, 0, 0)
search.bg = Fill(search, C.panel)
search.bg:SetAllPoints()
search.edges = Outline(search, C.line)

local glass = search:CreateTexture(nil, "ARTWORK")
glass:SetSize(14, 14)
glass:SetPoint("LEFT", 9, 0)
if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("common-search-magnifyingglass") then
	glass:SetAtlas("common-search-magnifyingglass")
	glass:SetVertexColor(unpack(C.muted))
else
	glass:Hide()
	search:SetTextInsets(10, 26, 0, 0)
end

local placeholder = Label(search, 13, C.faint)
placeholder:SetPoint("LEFT", search, "LEFT", glass:IsShown() and 28 or 10, 0)
placeholder:SetText("Filter players, dungeons, zones…")

local clearBtn = CreateFrame("Button", nil, search)
clearBtn:SetSize(20, 20)
clearBtn:SetPoint("RIGHT", -4, 0)
clearBtn.label = Label(clearBtn, 15, C.muted, "CENTER")
clearBtn.label:SetPoint("CENTER")
clearBtn.label:SetText("×")
clearBtn:Hide()
clearBtn:SetScript("OnClick", function() search:SetText(""); search:ClearFocus() end)

search:SetScript("OnEscapePressed", search.ClearFocus)
search:SetScript("OnEnterPressed", search.ClearFocus)
search:SetScript("OnEditFocusGained", function(self) SetOutline(self.edges, C.accent[1], C.accent[2], C.accent[3], 0.8) end)
search:SetScript("OnEditFocusLost", function(self) SetOutline(self.edges, unpack(C.line)) end)

-- Column headings -----------------------------------------------------------
local colTop = HEADER_H + 10 + SEARCH_H + 8
local function ColHead(text, x, justify, anchor)
	local fs = Label(F, 10, C.faint, justify)
	fs:SetText(text)
	fs:SetPoint(anchor or "TOPLEFT", x, -(colTop + 6))
	return fs
end
ColHead("PARTY", PAD + 2)
ColHead("GROUP  ·  NOTES", PAD + SLOTS_W + 14)
-- AGE is a sort toggle: off (server order) -> newest first -> oldest first.
local SORT_LABEL = { new = "NEWEST FIRST", old = "OLDEST FIRST" }
local ageSortBtn = CreateFrame("Button", nil, F)
ageSortBtn:SetSize(110, 18)
ageSortBtn:SetPoint("TOPRIGHT", -PAD, -(colTop + 3))
ageSortBtn.label = Label(ageSortBtn, 10, C.faint, "RIGHT")
ageSortBtn.label:SetPoint("RIGHT", -4, 0)
ageSortBtn.line = Fill(ageSortBtn, C.accent, "OVERLAY")
ageSortBtn.line:SetHeight(1)
ageSortBtn.line:SetPoint("TOPLEFT", ageSortBtn.label, "BOTTOMLEFT", 0, -2)
ageSortBtn.line:SetPoint("TOPRIGHT", ageSortBtn.label, "BOTTOMRIGHT", 0, -2)

local function UpdateSortLabel()
	local mode = db and db.sort
	ageSortBtn.label:SetText(SORT_LABEL[mode] or "AGE")
	if SORT_LABEL[mode] then
		ageSortBtn.label:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
		ageSortBtn.line:Show()
	else
		ageSortBtn.label:SetTextColor(unpack(C.faint))
		ageSortBtn.line:Hide()
	end
end
ageSortBtn:SetScript("OnEnter", function(self)
	if not (db and SORT_LABEL[db.sort]) then self.label:SetTextColor(unpack(C.muted)) end
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:AddLine("Sort by age", 1, 1, 1)
	GameTooltip:AddLine("Click: newest first  >  oldest first  >  off", C.muted[1], C.muted[2], C.muted[3])
	GameTooltip:Show()
end)
ageSortBtn:SetScript("OnLeave", function() UpdateSortLabel(); GameTooltip:Hide() end)

-- List --------------------------------------------------------------------
local list = CreateFrame("Frame", nil, F)
list:SetPoint("TOPLEFT", PAD, -(colTop + COLHEAD_H))
list:SetPoint("TOPRIGHT", -PAD, -(colTop + COLHEAD_H))
list:SetHeight(LIST_H)
list:EnableMouseWheel(true)

local track = Fill(list, { 1, 1, 1, 0.04 }, "ARTWORK")
track:SetWidth(2)
track:SetPoint("TOPRIGHT", 6, 0)
track:SetPoint("BOTTOMRIGHT", 6, 0)
local thumb = Fill(list, { 1, 1, 1, 0.28 }, "OVERLAY")
thumb:SetWidth(2)

local emptyText = Label(list, 13, C.muted, "CENTER")
emptyText:SetPoint("CENTER", 0, 20)
emptyText:SetWordWrap(true)
emptyText:SetWidth(WIDTH - 80)

local function CreateSlot(parent)
	local s = CreateFrame("Frame", nil, parent)
	s:SetSize(SLOT_W, SLOT_H)
	-- Up to three side-by-side colour bands for a multi-role player.
	s.segs = {}
	for i = 1, 3 do
		s.segs[i] = s:CreateTexture(nil, "BACKGROUND", nil, 1)
		s.segs[i]:Hide()
	end
	s.bg = s:CreateTexture(nil, "BACKGROUND")
	s.bg:SetAllPoints()
	s.edges = Outline(s, C.line)
	s.icon = s:CreateTexture(nil, "ARTWORK")
	s.icon:SetSize(16, 16)
	s.icon:SetPoint("LEFT", 4, 0)
	s.level = Label(s, 13, { 1, 1, 1 }, "RIGHT")
	s.level:SetPoint("RIGHT", -5, 0)
	s.level:SetShadowOffset(1, -1)
	s.level:SetShadowColor(0, 0, 0, 0.55)
	s.empty = Label(s, 11, C.faint, "CENTER")
	s.empty:SetPoint("CENTER")
	return s
end

local function PaintSlot(s, slot)
	local m = slot.member
	if m then
		local c = ROLE_COLOR[m.role] or ROLE_COLOR.NONE
		s.bg:SetColorTexture(c[1], c[2], c[3], 0.92)
		local offered = m.offered
		for i, seg in ipairs(s.segs) do
			local role = offered and offered[i]
			if role then
				local rc = ROLE_COLOR[role]
				local w = SLOT_W / #offered
				seg:ClearAllPoints()
				seg:SetPoint("TOPLEFT", (i - 1) * w, 0)
				seg:SetPoint("BOTTOMLEFT", (i - 1) * w, 0)
				seg:SetWidth(w)
				seg:SetColorTexture(rc[1], rc[2], rc[3], 0.92)
				seg:Show()
			else
				seg:Hide()
			end
		end
		SetOutline(s.edges, 1, 1, 1, 0.12)
		SetClassIcon(s.icon, m.class)
		local lvl = Readable(m.level, nil)
		if lvl == nil and m.level ~= nil then
			s.level:SetText(m.level) -- secret: let the client draw it
		elseif type(lvl) == "number" and lvl > 0 then
			s.level:SetText(lvl)
		else
			s.level:SetText("?")
		end
		s.level:Show()
		s.empty:Hide()
	else
		local c = ROLE_COLOR[slot.role]
		s.bg:SetColorTexture(c[1], c[2], c[3], 0.10)
		for _, seg in ipairs(s.segs) do seg:Hide() end
		SetOutline(s.edges, c[1], c[2], c[3], 0.45)
		s.icon:Hide()
		s.level:Hide()
		s.empty:SetText(ROLE_LETTER[slot.role])
		s.empty:SetTextColor(c[1], c[2], c[3], 0.85)
		s.empty:Show()
	end
end

local rows = {}

local function ShowTooltip(row)
	local r = row.result
	if not r then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT", 6, 0)
	local heading = ReadableString(r.title) or r.acts[1] or "Group"
	GameTooltip:AddLine(heading, 1, 1, 1)
	if #r.acts > 0 then
		GameTooltip:AddLine(table.concat(r.acts, ", "), C.muted[1], C.muted[2], C.muted[3], true)
	end
	if r.notes ~= nil and (not canaccess(r.notes) or r.notes ~= "") then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(r.notes, 0.92, 0.92, 0.92, true)
	end
	if #r.members > 0 then
		GameTooltip:AddLine(" ")
		for _, m in ipairs(r.members) do
			local cr, cg, cb = ClassColor(m.class)
			local rc = ROLE_COLOR[m.role] or ROLE_COLOR.NONE
			local roleName = m.role == "TANK" and "Tank" or m.role == "HEALER" and "Healer"
				or m.role == "DAMAGER" and "DPS" or "—"
			local lvl = Readable(m.level, nil)
			local right = roleName .. (type(lvl) == "number" and ("  ·  " .. lvl) or "")
			GameTooltip:AddDoubleLine(m.name or "?", right, cr, cg, cb, rc[1], rc[2], rc[3])
		end
	end
	if r.isSolo and r.members[1] and type(r.members[1].roles) == "table" then
		local roles = r.members[1].roles
		local can = {}
		if roles.tank then can[#can + 1] = "Tank" end
		if roles.healer then can[#can + 1] = "Healer" end
		if roles.dps then can[#can + 1] = "DPS" end
		if #can > 0 then
			GameTooltip:AddLine("Signed up as: " .. table.concat(can, " or "), C.muted[1], C.muted[2], C.muted[3])
		end
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(r.isSolo and "Click: whisper  ·  Shift-click: invite" or "Click: whisper leader",
		C.faint[1], C.faint[2], C.faint[3])
	GameTooltip:Show()
end

local function Whisper(name)
	if ChatFrameUtil and ChatFrameUtil.SendTell then
		ChatFrameUtil.SendTell(name)
	elseif ChatFrame_SendTell then
		ChatFrame_SendTell(name)
	end
end

local function Invite(name)
	if C_PartyInfo and C_PartyInfo.InviteUnit then
		C_PartyInfo.InviteUnit(name)
	elseif InviteUnit then
		InviteUnit(name)
	end
end

local function RowClick(row)
	local r = row.result
	if not r then return end
	local name = ReadableString(r.leader) or (r.members[1] and ReadableString(r.members[1].name))
	if not name then
		print("|cff33ff99HackrLFG|r: player name is hidden while you're in an instance.")
		return
	end
	if IsShiftKeyDown() then Invite(name) else Whisper(name) end
end

-- Rows are placed by Render (big groups are taller), so they start unanchored.
local SLOT_TOP = (ROW_H - SLOT_H) / 2
local BIG_ROW_H = ROW_H + SLOT_H + SLOT_GAP
local MAX_SLOTS = #SLOT_ORDER * 2

for i = 1, NUM_ROWS do
	local row = CreateFrame("Button", nil, list)
	row:SetHeight(ROW_H)
	row:RegisterForClicks("LeftButtonUp")
	row.bg = Fill(row, C.panel)
	row.bg:SetAllPoints()
	row.self = Fill(row, C.accent, "ARTWORK")
	row.self:SetWidth(2)
	row.self:SetPoint("TOPLEFT")
	row.self:SetPoint("BOTTOMLEFT")

	-- Slots 1-5 are the first party, 6-10 a second party under it.
	row.slots = {}
	for s = 1, MAX_SLOTS do
		local col = (s - 1) % #SLOT_ORDER
		local line = math.floor((s - 1) / #SLOT_ORDER)
		local slot = CreateSlot(row)
		slot:SetPoint("TOPLEFT", 6 + col * (SLOT_W + SLOT_GAP), -(SLOT_TOP + line * (SLOT_H + SLOT_GAP)))
		row.slots[s] = slot
	end

	local textX = 6 + SLOTS_W + 14
	row.age = Label(row, 11, C.faint, "RIGHT")
	row.age:SetPoint("RIGHT", -10, 0)
	row.age:SetWidth(34)

	row.title = Label(row, 13, C.text)
	row.title:SetPoint("TOPLEFT", textX, -4)
	row.title:SetPoint("RIGHT", row.age, "LEFT", -8, 0)
	row.title:SetHeight(15)

	row.notes = Label(row, 11, C.muted)
	row.notes:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -1)
	row.notes:SetPoint("RIGHT", row.age, "LEFT", -8, 0)
	row.notes:SetHeight(13)

	-- Big groups only: "6/10  ·  1 Tank  ·  2 Healer  ·  3 DPS" under the notes.
	row.extra = Label(row, 11, C.faint)
	row.extra:SetPoint("TOPLEFT", row.notes, "BOTTOMLEFT", 0, -6)
	row.extra:SetPoint("RIGHT", row.age, "LEFT", -8, 0)
	row.extra:SetHeight(13)

	row:SetScript("OnEnter", function(self) self.bg:SetColorTexture(unpack(C.hover)); ShowTooltip(self) end)
	row:SetScript("OnLeave", function(self) self.bg:SetColorTexture(unpack(C.panel)); GameTooltip:Hide() end)
	row:SetScript("OnClick", RowClick)
	rows[i] = row
end

-- Footer ------------------------------------------------------------------
local footLine = Fill(F, C.line, "ARTWORK")
footLine:SetHeight(1)
footLine:SetPoint("BOTTOMLEFT", 0, FOOTER_H)
footLine:SetPoint("BOTTOMRIGHT", 0, FOOTER_H)

local legend = {}
local lx = PAD
for _, key in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
	local c = ROLE_COLOR[key]
	local sw = Fill(F, c, "ARTWORK")
	sw:SetSize(8, 8)
	sw:SetPoint("BOTTOMLEFT", lx, 9)
	local t = Label(F, 11, C.muted)
	t:SetPoint("LEFT", sw, "RIGHT", 5, 0)
	t:SetText(key == "DAMAGER" and "DPS" or key == "TANK" and "Tank" or "Healer")
	lx = lx + 16 + t:GetStringWidth() + 14
	legend[#legend + 1] = t
end
local hint = Label(F, 11, C.faint, "RIGHT")
hint:SetPoint("BOTTOMRIGHT", -PAD, 8)
hint:SetText("Click: whisper  ·  Shift-click: invite solo  ·  -word excludes")

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------

local function ParseTerms(text)
	local include, exclude = {}, {}
	for word in (text or ""):lower():gmatch("%S+") do
		if word:sub(1, 1) == "-" and #word > 1 then
			exclude[#exclude + 1] = word:sub(2)
		else
			include[#include + 1] = word
		end
	end
	return include, exclude
end

local function Matches(r, include, exclude)
	for _, w in ipairs(include) do
		if not r.hay:find(w, 1, true) then return false end
	end
	for _, w in ipairs(exclude) do
		if r.hay:find(w, 1, true) then return false end
	end
	return true
end

local function RowHeight(r)
	return r.big and BIG_ROW_H or ROW_H
end

-- The largest offset that still fills the list down to the last listing.
local function MaxOffset()
	local h = 0
	for i = #visible, 1, -1 do
		h = h + RowHeight(visible[i]) + (h > 0 and ROW_GAP or 0)
		if h > LIST_H then return i end
	end
	return 0
end

local function TallyText(r)
	local t = r.tally
	local size = r.maxPlayers > 0 and r.maxPlayers or MAX_SLOTS
	local parts = { "|cffc8cdd8" .. (r.num or #r.members) .. "/" .. size .. "|r" }
	local function add(n, word, c)
		if n > 0 then
			parts[#parts + 1] = ("|cff%02x%02x%02x%d %s|r"):format(
				math.floor(math.min(c[1] + 0.15, 1) * 255), math.floor(math.min(c[2] + 0.15, 1) * 255),
				math.floor(math.min(c[3] + 0.15, 1) * 255), n, word)
		end
	end
	add(t.TANK, t.TANK == 1 and "Tank" or "Tanks", ROLE_COLOR.TANK)
	add(t.HEALER, t.HEALER == 1 and "Healer" or "Healers", ROLE_COLOR.HEALER)
	add(t.DAMAGER, "DPS", ROLE_COLOR.DAMAGER)
	if t.NONE > 0 then parts[#parts + 1] = t.NONE .. " unknown" end
	if r.overflow > 0 then parts[#parts + 1] = "+" .. r.overflow .. " not shown" end
	return table.concat(parts, "  ·  ")
end

local function Render()
	local maxOffset = MaxOffset()
	offset = math.min(math.max(offset, 0), maxOffset)

	local y, idx, shown = 0, offset + 1, 0
	for _, row in ipairs(rows) do
		local r = visible[idx]
		if r and y + RowHeight(r) > LIST_H then r = nil end -- no room left
		row.result = r
		if r then
			local h = RowHeight(r)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 0, -y)
			row:SetPoint("TOPRIGHT", 0, -y)
			row:SetHeight(h)
			y, idx, shown = y + h + ROW_GAP, idx + 1, shown + 1

			for s, slotFrame in ipairs(row.slots) do
				if r.slots[s] then
					PaintSlot(slotFrame, r.slots[s])
					slotFrame:Show()
				else
					slotFrame:Hide()
				end
			end
			if r.big then
				row.extra:SetText(TallyText(r))
				row.extra:Show()
			else
				row.extra:Hide()
			end

			local titleText = ReadableString(r.title)
			local actText = #r.acts > 0 and table.concat(r.acts, ", ") or nil
			if r.isSolo then
				local m = r.members[1]
				local name = m and ReadableString(m.name)
				local area = m and ReadableString(m.area)
				titleText = (actText and (actText .. "  ·  ") or "") .. (name or "Solo player")
					.. (area and ("  |cff6b7280" .. area .. "|r") or "")
			elseif titleText and actText then
				titleText = titleText .. "  |cff8b93a5" .. actText .. "|r"
			end
			if titleText then
				row.title:SetText(titleText)
			elseif r.title ~= nil and not canaccess(r.title) then
				row.title:SetText(r.title) -- secret: let the client draw it
			else
				row.title:SetText(actText or "Group")
			end

			if r.notes ~= nil and not canaccess(r.notes) then
				row.notes:SetText(r.notes)
			else
				local n = ReadableString(r.notes)
				row.notes:SetText(n and n:gsub("[\r\n]+", "  ") or "|cff4b5160No notes|r")
			end

			row.age:SetText(FormatAge(r.age))
			row.self:SetShown(r.hasSelf)
			row:Show()
		else
			row:Hide()
		end
	end

	-- scrollbar
	if maxOffset > 0 then
		local h = math.max(LIST_H * shown / #visible, 20)
		thumb:SetHeight(h)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOPRIGHT", list, "TOPRIGHT", 6, -(LIST_H - h) * (offset / maxOffset))
		thumb:Show(); track:Show()
	else
		thumb:Hide(); track:Hide()
	end

	local query = search:GetText()
	if #results == 0 then
		emptyText:SetText("No listings yet.\nPick a dungeon on the left, or just press |cffffffffSearch|r for all of them.")
		emptyText:Show()
	elseif #visible == 0 then
		local hidden = 0
		for _, r in ipairs(results) do if r.notesHidden then hidden = hidden + 1 end end
		if hidden > 0 then
			emptyText:SetText("Nothing matches \"" .. query .. "\".\n|cff8b93a5The game hides the notes text of "
				.. hidden .. " listings from addons, so notes can't be searched.|r")
		else
			emptyText:SetText("Nothing matches \"" .. query .. "\".")
		end
		emptyText:Show()
	else
		emptyText:Hide()
	end

	if query ~= "" then
		countText:SetText(#visible .. " of " .. #results .. " listings")
	else
		countText:SetText(#results .. " listings")
	end
end

local function ApplyFilter()
	local text = search:GetText() or ""
	placeholder:SetShown(text == "")
	clearBtn:SetShown(text ~= "")
	local include, exclude = ParseTerms(text)
	wipe(visible)
	for _, r in ipairs(results) do
		if (#include == 0 and #exclude == 0) or Matches(r, include, exclude) then
			visible[#visible + 1] = r
		end
	end
	local mode = db and db.sort
	if mode == "new" or mode == "old" then
		table.sort(visible, function(a, b)
			local aa, ba = Readable(a.age, nil), Readable(b.age, nil)
			if type(aa) ~= "number" or type(ba) ~= "number" then
				if type(aa) == "number" then return true end   -- unknown ages last
				if type(ba) == "number" then return false end
				return a.index < b.index
			end
			if aa == ba then return a.index < b.index end
			if mode == "new" then return aa < ba end
			return aa > ba
		end)
	end
	Render()
end

local function Rebuild()
	wipe(results)
	for _, id in ipairs(GetResultIDs()) do
		local r = ReadResult(id)
		if r then
			results[#results + 1] = r
			r.index = #results
		end
	end
	ApplyFilter()
end

local pending = false
local function QueueRebuild()
	if pending or not F:IsShown() then return end
	pending = true
	C_Timer.After(0.15, function()
		pending = false
		if F:IsShown() then Rebuild() end
	end)
end

search:SetScript("OnTextChanged", function() offset = 0; ApplyFilter() end)
ageSortBtn:SetScript("OnClick", function()
	db.sort = (db.sort == nil and "new") or (db.sort == "new" and "old") or nil
	offset = 0
	UpdateSortLabel()
	ApplyFilter()
end)
list:SetScript("OnMouseWheel", function(_, delta)
	offset = offset - delta * 3
	Render()
end)

---------------------------------------------------------------------------
-- Dungeon picker + our own search
--
-- Blizzard's finder only searches activities whose suggested level range
-- holds your level. HackrLFG searches the whole category (or the one
-- dungeon you picked) itself, so every listing comes back.
---------------------------------------------------------------------------

local activityCache = {}
local function CategoryActivities(categoryID)
	if activityCache[categoryID] then return activityCache[categoryID] end
	local list = {}
	local ok, ids = pcall(C_LFGList.GetAvailableActivities, categoryID)
	if ok and type(ids) == "table" then
		for _, id in ipairs(ids) do
			local info = C_LFGList.GetActivityInfoTable and C_LFGList.GetActivityInfoTable(id)
			list[#list + 1] = {
				id   = id,
				name = ActivityName(id) or ("Activity " .. id),
				min  = info and Readable(info.minLevelSuggestion, 0) or 0,
				max  = info and Readable(info.maxLevelSuggestion, 0) or 0,
			}
		end
	end
	table.sort(list, function(a, b)
		if a.min ~= b.min then return a.min < b.min end
		return a.name < b.name
	end)
	if #list > 0 then activityCache[categoryID] = list end
	return list
end

local function Categories()
	local out = {}
	local ok, ids = pcall(C_LFGList.GetAvailableCategories)
	if not ok or type(ids) ~= "table" then return out end
	for _, id in ipairs(ids) do
		local okInfo, info = pcall(C_LFGList.GetLfgCategoryInfo, id)
		local name = okInfo and type(info) == "table" and ReadableString(info.name)
		if name and #CategoryActivities(id) > 0 then
			out[#out + 1] = { id = id, name = name }
		end
	end
	return out
end

local function CurrentCategory()
	local cats = Categories()
	for _, c in ipairs(cats) do
		if c.id == db.category then return c end
	end
	for _, c in ipairs(cats) do
		if c.name:lower():find("dungeon", 1, true) then return c end
	end
	return cats[1]
end

local function Suits(a)
	local lvl = UnitLevel("player") or 0
	return (a.min == 0 or a.min <= lvl) and (a.max == 0 or a.max >= lvl)
end

local function RangeText(a)
	if a.min > 0 and a.max > 0 and a.max ~= a.min then return a.min .. "–" .. a.max end
	if a.min > 0 and a.max == 0 then return a.min .. "+" end
	if a.min > 0 then return tostring(a.min) end
	return ""
end

local function SelectionLabel()
	local cat = CurrentCategory()
	if not cat then return "Group Finder not ready" end
	if db.activity == "LEVEL" then return cat.name .. "  ·  My level" end
	if type(db.activity) == "number" then
		for _, a in ipairs(CategoryActivities(cat.id)) do
			if a.id == db.activity then return a.name end
		end
	end
	return "All " .. cat.name
end

local function UpdateDropLabel()
	dropBtn.label:SetText(SelectionLabel())
end

local function RunSearch()
	local cat = CurrentCategory()
	if not cat then
		print("|cff33ff99HackrLFG|r: the Group Finder isn't available yet; open it once with |cffffffffI|r.")
		return
	end
	local ids = {}
	for _, a in ipairs(CategoryActivities(cat.id)) do
		if db.activity == a.id or (db.activity == "LEVEL" and Suits(a)) then
			ids[#ids + 1] = a.id
		end
	end
	if #ids == 0 then -- "All", or nothing matched
		for _, a in ipairs(CategoryActivities(cat.id)) do ids[#ids + 1] = a.id end
	end
	local ok, err = pcall(C_LFGList.Search, cat.id, 0, 0, nil, false, nil, ids)
	if ok then
		offset = 0
		countText:SetText("Searching…")
	else
		print("|cff33ff99HackrLFG|r: search failed: " .. tostring(err))
	end
end

goBtn:SetScript("OnClick", RunSearch)

-- The popup -----------------------------------------------------------------
local MENU_W, MENU_ROWS, MENU_ROW_H, TABS_H = 300, 16, 22, 30

local menu = CreateFrame("Frame", nil, F)
menu:SetFrameStrata("DIALOG")
menu:SetWidth(MENU_W)
menu:SetPoint("TOPLEFT", dropBtn, "BOTTOMLEFT", 0, -4)
menu:EnableMouse(true)
menu:EnableMouseWheel(true)
menu:Hide()
Fill(menu, { 0.07, 0.075, 0.09, 0.99 }):SetAllPoints()
Outline(menu, { 1, 1, 1, 0.12 })
local tabLine = Fill(menu, C.line, "ARTWORK")
tabLine:SetHeight(1)
tabLine:SetPoint("TOPLEFT", 0, -TABS_H)
tabLine:SetPoint("TOPRIGHT", 0, -TABS_H)

menu.offset = 0
menu.tabs, menu.items, menu.entries = {}, {}, {}

local RefreshMenu

local function PickEntry(entry)
	db.activity = entry.key
	menu:Hide()
	UpdateDropLabel()
	RunSearch()
end

for i = 1, MENU_ROWS do
	local b = CreateFrame("Button", nil, menu)
	b:SetHeight(MENU_ROW_H)
	b:SetPoint("TOPLEFT", 4, -(TABS_H + 4 + (i - 1) * MENU_ROW_H))
	b:SetPoint("TOPRIGHT", -4, -(TABS_H + 4 + (i - 1) * MENU_ROW_H))
	b.hl = Fill(b, { 1, 1, 1, 0 })
	b.hl:SetAllPoints()
	b.mark = Fill(b, C.accent, "ARTWORK")
	b.mark:SetWidth(2)
	b.mark:SetPoint("TOPLEFT", 0, -3)
	b.mark:SetPoint("BOTTOMLEFT", 0, 3)
	b.label = Label(b, 12, C.text)
	b.label:SetPoint("LEFT", 10, 0)
	b.label:SetPoint("RIGHT", -70, 0)
	b.range = Label(b, 11, C.faint, "RIGHT")
	b.range:SetPoint("RIGHT", -8, 0)
	b:SetScript("OnEnter", function(self) self.hl:SetColorTexture(1, 1, 1, 0.07) end)
	b:SetScript("OnLeave", function(self) self.hl:SetColorTexture(1, 1, 1, 0) end)
	b:SetScript("OnClick", function(self) if self.entry then PickEntry(self.entry) end end)
	menu.items[i] = b
end

local function MakeTab(i)
	local t = CreateFrame("Button", nil, menu)
	t:SetHeight(TABS_H)
	t.label = Label(t, 12, C.muted, "CENTER")
	t.label:SetPoint("CENTER", 0, 1)
	t.bar = Fill(t, C.accent, "OVERLAY")
	t.bar:SetHeight(2)
	t.bar:SetPoint("BOTTOMLEFT", 8, 0)
	t.bar:SetPoint("BOTTOMRIGHT", -8, 0)
	t:SetScript("OnClick", function(self)
		db.category = self.categoryID
		db.activity = "ALL"
		menu.offset = 0
		UpdateDropLabel()
		RefreshMenu()
	end)
	menu.tabs[i] = t
	return t
end

function RefreshMenu()
	local cats = Categories()
	local cur = CurrentCategory()
	local tabW = math.floor(MENU_W / math.max(#cats, 1))
	for i, c in ipairs(cats) do
		local t = menu.tabs[i] or MakeTab(i)
		t:ClearAllPoints()
		t:SetPoint("TOPLEFT", (i - 1) * tabW, 0)
		t:SetWidth(tabW)
		t.categoryID = c.id
		t.label:SetText(c.name)
		local on = cur and cur.id == c.id
		t.label:SetTextColor(unpack(on and C.text or C.muted))
		t.bar:SetShown(on)
		t:Show()
	end
	for i = #cats + 1, #menu.tabs do menu.tabs[i]:Hide() end

	local entries = menu.entries
	wipe(entries)
	if cur then
		local acts = CategoryActivities(cur.id)
		local suited = 0
		for _, a in ipairs(acts) do if Suits(a) then suited = suited + 1 end end
		entries[#entries + 1] = { key = "ALL", label = "All " .. cur.name, range = #acts .. "", accent = true }
		entries[#entries + 1] = { key = "LEVEL", label = "Around my level", range = suited .. "", accent = true }
		for _, a in ipairs(acts) do
			entries[#entries + 1] = { key = a.id, label = a.name, range = RangeText(a), dim = not Suits(a) }
		end
	end

	local shown = math.min(#entries, MENU_ROWS)
	menu.offset = math.min(math.max(menu.offset, 0), math.max(0, #entries - MENU_ROWS))
	for i, b in ipairs(menu.items) do
		local e = entries[i + menu.offset]
		b.entry = e
		if e then
			local selected = (db.activity == e.key) or (e.key == "ALL" and db.activity ~= "LEVEL" and type(db.activity) ~= "number")
			b.label:SetText(e.label)
			if e.accent then
				b.label:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
			elseif e.dim then
				b.label:SetTextColor(unpack(C.muted))
			else
				b.label:SetTextColor(unpack(C.text))
			end
			b.range:SetText(e.range or "")
			b.mark:SetShown(selected)
			b:Show()
		else
			b:Hide()
		end
	end
	menu:SetHeight(TABS_H + 8 + math.max(shown, 1) * MENU_ROW_H)
end

menu:SetScript("OnMouseWheel", function(self, delta)
	self.offset = self.offset - delta * 3
	RefreshMenu()
end)
menu:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
menu:SetScript("OnHide", function(self) self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)
menu:SetScript("OnEvent", function(self)
	if not self:IsMouseOver() and not dropBtn:IsMouseOver() then self:Hide() end
end)

dropBtn:SetScript("OnClick", function()
	if menu:IsShown() then
		menu:Hide()
	else
		menu.offset = 0
		RefreshMenu()
		menu:Show()
	end
end)

---------------------------------------------------------------------------
-- List yourself
--
-- Lists you (or your group, if you lead one) for the dungeon chosen in the
-- picker, or for every dungeon around your level. Roles are the same ones
-- Blizzard's Listing tab saves (C_LFGListRoles). Addons cannot write the
-- notes text on this client; that stays in Blizzard's Group Finder.
---------------------------------------------------------------------------

local LP_W = 300
local GREEN = ROLE_COLOR.HEALER

local listBtn = FlatButton(F, "List me", 92)
listBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
listBtn.dot = Fill(listBtn, GREEN, "OVERLAY")
listBtn.dot:SetSize(6, 6)
listBtn.dot:SetPoint("LEFT", 10, 0)
listBtn.dot:Hide()

local lp = CreateFrame("Frame", nil, F)
lp:SetFrameStrata("DIALOG")
lp:SetWidth(LP_W)
lp:SetPoint("TOPRIGHT", listBtn, "BOTTOMRIGHT", 0, -6)
lp:EnableMouse(true)
lp:Hide()
Fill(lp, { 0.07, 0.075, 0.09, 0.99 }):SetAllPoints()
Outline(lp, { 1, 1, 1, 0.12 })

local lpTitle = Label(lp, 14, C.text)
lpTitle:SetPoint("TOPLEFT", 14, -14)
lpTitle:SetText("List yourself")

local lpStatus = Label(lp, 11, C.muted, "RIGHT")
lpStatus:SetPoint("TOPRIGHT", -14, -16)

local function SmallCaps(text, y)
	local fs = Label(lp, 10, C.faint)
	fs:SetPoint("TOPLEFT", 14, y)
	fs:SetText(text)
	return fs
end

SmallCaps("ROLES", -42)
local roleState = { tank = false, healer = false, dps = false }
local roleToggles = {}
local ROLE_KEYS = {
	{ key = "tank",   label = "Tank",   color = ROLE_COLOR.TANK },
	{ key = "healer", label = "Healer", color = ROLE_COLOR.HEALER },
	{ key = "dps",    label = "DPS",    color = ROLE_COLOR.DAMAGER },
}
local TOGGLE_W = math.floor((LP_W - 28 - 12) / 3)

local function PaintToggle(t)
	local c, on = t.spec.color, roleState[t.spec.key]
	t.bg:SetColorTexture(c[1], c[2], c[3], on and 0.92 or 0.10)
	SetOutline(t.edges, c[1], c[2], c[3], on and 0.0 or 0.45)
	if on then t.label:SetTextColor(1, 1, 1) else t.label:SetTextColor(c[1], c[2], c[3]) end
end

for i, spec in ipairs(ROLE_KEYS) do
	local t = CreateFrame("Button", nil, lp)
	t:SetSize(TOGGLE_W, 28)
	t:SetPoint("TOPLEFT", 14 + (i - 1) * (TOGGLE_W + 6), -56)
	t.spec = spec
	t.bg = t:CreateTexture(nil, "BACKGROUND")
	t.bg:SetAllPoints()
	t.edges = Outline(t, C.line)
	t.label = Label(t, 13, C.text, "CENTER")
	t.label:SetPoint("CENTER")
	t.label:SetText(spec.label)
	t:SetScript("OnClick", function(self)
		roleState[self.spec.key] = not roleState[self.spec.key]
		PaintToggle(self)
	end)
	roleToggles[i] = t
end

SmallCaps("FOR", -96)
local lpTarget = Label(lp, 13, C.text)
lpTarget:SetPoint("TOPLEFT", 14, -110)
lpTarget:SetPoint("RIGHT", lp, "RIGHT", -14, 0)
lpTarget:SetWordWrap(true)
lpTarget:SetHeight(32)
lpTarget:SetJustifyV("TOP")

local lpNote = Label(lp, 10, C.faint)
lpNote:SetPoint("TOPLEFT", 14, -146)
lpNote:SetPoint("RIGHT", lp, "RIGHT", -14, 0)
lpNote:SetWordWrap(true)
lpNote:SetText("Change the dungeon with the picker. Notes can only be written in Blizzard's Group Finder (I).")

local postBtn = FlatButton(lp, "List me", LP_W - 28)
postBtn:SetHeight(30)
postBtn:SetPoint("BOTTOMLEFT", 14, 14)
MakePrimary(postBtn)

local delistBtn = FlatButton(lp, "Remove listing", 0)
delistBtn:SetHeight(30)
delistBtn:SetPoint("BOTTOMRIGHT", -14, 14)
delistBtn.label:SetFont(FONT, 13, "")
delistBtn.label:SetTextColor(ROLE_COLOR.DAMAGER[1] + 0.08, ROLE_COLOR.DAMAGER[2] + 0.15, ROLE_COLOR.DAMAGER[3] + 0.15)

lp:SetHeight(146 + 28 + 14 + 30 + 14)

local function Say(text) print("|cff33ff99HackrLFG|r: " .. text) end

-- What we would list for: the picker's dungeon, or everything near your level.
local function ListingTarget()
	local cat = CurrentCategory()
	if not cat then return nil, "Group Finder isn't ready yet." end
	local acts = CategoryActivities(cat.id)
	if type(db.activity) == "number" then
		for _, a in ipairs(acts) do
			if a.id == db.activity then return { a.id }, a.name end
		end
	end
	if db.activity == "LEVEL" then
		local ids = {}
		for _, a in ipairs(acts) do if Suits(a) then ids[#ids + 1] = a.id end end
		if #ids > 0 then return ids, cat.name .. " around my level (" .. #ids .. ")" end
	end
	return nil, "Pick a dungeon, or \"Around my level\", in the picker first."
end

local function ActiveListing()
	if not (C_LFGList and C_LFGList.HasActiveEntryInfo) then return nil end
	local ok, has = pcall(C_LFGList.HasActiveEntryInfo)
	if not ok or Readable(has, false) ~= true then return nil end
	local okE, entry = pcall(C_LFGList.GetActiveEntryInfo)
	local ids = okE and type(entry) == "table" and Readable(entry.activityIDs, nil)
	if type(ids) == "table" and #ids > 0 then
		if #ids == 1 then return ActivityName(ids[1]) or "1 dungeon" end
		return #ids .. " dungeons"
	end
	return "a group"
end

local function UpdateListUI()
	if not db then return end
	local active = ActiveListing()
	listBtn.dot:SetShown(active ~= nil)
	listBtn.label:ClearAllPoints()
	if active then
		listBtn.label:SetText("Listed")
		listBtn.label:SetPoint("CENTER", 5, 0)
		lpStatus:SetText("|cff35b86eListed:|r " .. active)
		postBtn:SetWidth((LP_W - 28 - 8) / 2)
		postBtn.label:SetText("Update")
		delistBtn:SetWidth((LP_W - 28 - 8) / 2)
		delistBtn:Show()
	else
		listBtn.label:SetText("List me")
		listBtn.label:SetPoint("CENTER")
		lpStatus:SetText("Not listed")
		postBtn:SetWidth(LP_W - 28)
		postBtn.label:SetText("List me")
		delistBtn:Hide()
	end
	local ids, label = ListingTarget()
	lpTarget:SetText(label or "")
	lpTarget:SetTextColor(unpack(ids and C.text or C.muted))
end

local function LoadRoles()
	local roles
	if C_LFGListRoles and C_LFGListRoles.GetRoles then
		local ok, r = pcall(C_LFGListRoles.GetRoles)
		if ok and type(r) == "table" then roles = r end
	end
	roleState.tank = roles and roles.tank and true or false
	roleState.healer = roles and roles.healer and true or false
	roleState.dps = roles and roles.dps and true or false
	for _, t in ipairs(roleToggles) do PaintToggle(t) end
end

local pendingPost -- what we just asked for, so the result event can report it

local function Post()
	local ids, label = ListingTarget()
	if not ids then Say(label) return end
	if not (roleState.tank or roleState.healer or roleState.dps) then
		Say("pick at least one role.")
		return
	end
	if C_LFGListRoles and C_LFGListRoles.SetRoles then
		pcall(C_LFGListRoles.SetRoles, { tank = roleState.tank, healer = roleState.healer, dps = roleState.dps })
	end
	if not (C_LFGList and C_LFGList.CreateListing) then
		Say("this client doesn't let addons list you; use the Group Finder (I).")
		return
	end
	local update = ActiveListing() ~= nil
	pendingPost = { label = label, update = update }
	local ok, err = pcall(function()
		local data = { activityIDs = ids, newPlayerFriendly = false }
		if update then C_LFGList.UpdateListing(data) else C_LFGList.CreateListing(data) end
	end)
	if not ok then
		pendingPost = nil
		Say("couldn't list you (" .. tostring(err) .. ").")
	else
		lpStatus:SetText("Posting…")
	end
end

postBtn:SetScript("OnClick", Post)
delistBtn:SetScript("OnClick", function()
	local ok, err = pcall(C_LFGList.RemoveListing)
	if not ok then Say("couldn't remove your listing (" .. tostring(err) .. ").") end
end)

lp:SetScript("OnShow", function(self)
	LoadRoles()
	UpdateListUI()
	self:RegisterEvent("GLOBAL_MOUSE_DOWN")
end)
lp:SetScript("OnHide", function(self) self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)
lp:SetScript("OnEvent", function(self)
	if not self:IsMouseOver() and not listBtn:IsMouseOver() and not dropBtn:IsMouseOver() and not menu:IsMouseOver() then
		self:Hide()
	end
end)

listBtn:SetScript("OnClick", function()
	menu:Hide()
	lp:SetShown(not lp:IsShown())
end)

-- The picker changes what we would list for; keep the panel in step.
hooksecurefunc(dropBtn.label, "SetText", function()
	if lp:IsShown() then UpdateListUI() end
end)

local listWatch = CreateFrame("Frame")
listWatch:RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE")
listWatch:RegisterEvent("GROUP_ROSTER_UPDATE")
listWatch:RegisterEvent("ADDON_ACTION_BLOCKED")
listWatch:RegisterEvent("ADDON_ACTION_FORBIDDEN")
listWatch:SetScript("OnEvent", function(_, event, addon)
	if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
		if addon == ADDON_NAME and pendingPost then
			pendingPost = nil
			Say("the game blocked listing from an addon; use the Group Finder (I).")
		end
		return
	end
	if event == "LFG_LIST_ACTIVE_ENTRY_UPDATE" and pendingPost then
		Say((pendingPost.update and "listing changed to " or "listed for ") .. pendingPost.label .. ".")
		pendingPost = nil
	end
	UpdateListUI()
end)

---------------------------------------------------------------------------
-- Positioning, show/hide, events
---------------------------------------------------------------------------

local function Place()
	F:ClearAllPoints()
	if db.moved and db.pos then
		F:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4])
		return
	end
	local anchor = LFGParentFrame or LFGBrowseFrame
	if anchor and anchor:IsShown() then
		F:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 12, 0)
	else
		F:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	end
end

F:SetScript("OnShow", function() Place(); UpdateDropLabel(); UpdateSortLabel(); UpdateListUI(); Rebuild() end)
F:SetScript("OnHide", function() search:ClearFocus(); menu:Hide(); lp:Hide() end)

local autoShown = false
local hooked = {}
local function HookBlizzard()
	for _, name in ipairs({ "LFGParentFrame", "LFGBrowseFrame" }) do
		local frame = _G[name]
		if frame and not hooked[name] then
			hooked[name] = true
			frame:HookScript("OnShow", function()
				if db and db.autoShow and not F:IsShown() then
					autoShown = true
					F:Show()
				end
			end)
			frame:HookScript("OnHide", function()
				if autoShown and not (LFGParentFrame and LFGParentFrame:IsShown()) then
					autoShown = false
					F:Hide()
				end
			end)
		end
	end
end

F:RegisterEvent("ADDON_LOADED")
F:RegisterEvent("PLAYER_LOGIN")
F:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
F:RegisterEvent("LFG_LIST_SEARCH_RESULT_UPDATED")
F:RegisterEvent("LFG_LIST_SEARCH_FAILED")
F:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == ADDON_NAME then
			HackrLFGDB = HackrLFGDB or {}
			db = HackrLFGDB
			if db.autoShow == nil then db.autoShow = true end
			if db.activity == nil then db.activity = "ALL" end
		end
		HookBlizzard()
	elseif event == "PLAYER_LOGIN" then
		HookBlizzard()
	elseif event == "LFG_LIST_SEARCH_FAILED" then
		if F:IsShown() then countText:SetText("Search failed — try again") end
	else
		QueueRebuild()
	end
end)

SLASH_HACKRLFG1 = "/gl"
SLASH_HACKRLFG2 = "/hackrlfg"
SLASH_HACKRLFG3 = "/hlfg"
SlashCmdList.HACKRLFG = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "auto" then
		db.autoShow = not db.autoShow
		print("|cff33ff99HackrLFG|r: open with Group Finder " .. (db.autoShow and "ON" or "OFF"))
	elseif msg == "reset" then
		db.moved, db.pos = nil, nil
		if F:IsShown() then Place() end
		print("|cff33ff99HackrLFG|r: position reset.")
	elseif msg == "help" then
		print("|cff33ff99HackrLFG|r commands (/hlfg, /hackrlfg or /gl):")
		print("  |cffffffff/hlfg|r  show or hide the window")
		print("  |cffffffff/hlfg auto|r  open with the Group Finder on/off")
		print("  |cffffffff/hlfg reset|r  move the window back to its default spot")
	else
		autoShown = false
		F:SetShown(not F:IsShown())
	end
end
