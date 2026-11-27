-- CraftShare: kleiner, frei beweglicher Knopf (zeigt/versteckt das Hauptfenster, "!" bei offenen oder neuen Auftraegen).
local ADDON, ns = ...
local M = {}
ns.Mini = M
local T = ns.T

local btn
local withList = false -- hat der Klick den Eingang mit geoeffnet?
local alertUntil = 0 -- Hinweis auf einen neuen Auftrag bis zu diesem Zeitpunkt zeigen

local function cfg()
	ns.db.mini = ns.db.mini or {}
	return ns.db.mini
end

-- drei kleine Felder links am Knopf: A aktueller Auftrag, Q meine Auftraege, H Historie
local SIDE, GAP = 15, 1
local SIZE = 3 * SIDE + 2 * GAP -- Symbol so hoch wie die drei Felder zusammen
-- Symbol und Felder mit demselben Rahmen und runden Ecken
local TEX_ICON = "Interface\\AddOns\\CraftShare\\Media\\MiniIcon"
local TEX_FILL = "Interface" .. string.char(92) .. "AddOns" .. string.char(92) .. "CraftShare" .. string.char(92) .. "Media" .. string.char(92) .. "MiniFill"
local TEX_SLOT = "Interface\\AddOns\\CraftShare\\Media\\MiniSlot"

-- Aufhellen unter der Maus, in der Form des Rahmens
local function glow(b, texture)
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetTexture(texture)
	hl:SetBlendMode("ADD")
	hl:SetAlpha(0.3)
end
local SLOTS = {
	{ key = "A", tip = T("Aktueller Auftrag", "Current order"), click = function() ns.Task.Toggle() end },
	{ key = "Q", tip = T("Meine Aufträge", "My jobs"), click = function() ns.Orders.ToggleList("mine") end },
	{ key = "H", tip = T("Historie", "History"), click = function() ns.History.Toggle() end },
}

local function savePos(b)
	b:StopMovingOrSizing()
	local p, _, rp, x, y = b:GetPoint()
	cfg().pos = { p, rp, x, y }
end

-- jede Schaltflaeche erklaert nur sich selbst
local function showTip(owner, ...)
	GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
	for i = 1, select("#", ...) do
		GameTooltip:AddLine((select(i, ...)), 0.95, 0.92, 0.88)
	end
	GameTooltip:Show()
end

-- Feld A: Funktion, aktueller Stand und was die Farben bedeuten
local function showCurrentTip(owner, tip)
	local active, turn = 0, 0
	if ns.Orders then active, turn = ns.Orders.ActiveCount() end
	GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
	GameTooltip:AddLine(tip, 0.95, 0.92, 0.88)
	if active > 0 then
		GameTooltip:AddLine(string.format(T("Laufend: %d, davon du dran: %d", "Running: %d, your turn: %d"), active, turn), 0.95, 0.76, 0.19)
	end
	GameTooltip:AddLine(T("Orange: du bist dran", "Orange: your turn"), 0.88, 0.44, 0.23)
	GameTooltip:AddLine(T("Blau: du wartest auf den Partner", "Blue: waiting for your partner"), 0.44, 0.70, 1)
	GameTooltip:AddLine(T("Abgeblendet: kein angenommener Auftrag", "Dimmed: no accepted order"), 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

local function buildSide(b, K)
	b.side = {}
	for i, spec in ipairs(SLOTS) do
		local s = CreateFrame("Button", nil, b)
		s:SetSize(SIDE, SIDE)
		s:SetPoint("TOPRIGHT", b, "TOPLEFT", -2, -(i - 1) * (SIDE + GAP))
		local bg = s:CreateTexture(nil, "ARTWORK")
		bg:SetAllPoints()
		bg:SetTexture(TEX_SLOT)
		s.fill = s:CreateTexture(nil, "ARTWORK", nil, 1)
		s.fill:SetAllPoints()
		s.fill:SetTexture(TEX_FILL)
		s.fill:Hide()
		s.label = K.FS(s, 9, K.COL.gold, "CENTER")
		s.label:SetPoint("CENTER", 0, 0)
		s.label:SetText(spec.key)
		glow(s, TEX_SLOT)
		s:SetScript("OnClick", function() if spec.click then spec.click() end end)
		-- auch an den Feldern laesst sich der Knopf verschieben
		s:RegisterForDrag("LeftButton")
		s:SetScript("OnDragStart", function() b:StartMoving() end)
		s:SetScript("OnDragStop", function() savePos(b) end)
		s:SetScript("OnEnter", function(self)
			if spec.key == "A" then showCurrentTip(self, spec.tip) else showTip(self, spec.tip) end
		end)
		s:SetScript("OnLeave", function() GameTooltip:Hide() end)
		b.side[spec.key] = s
	end
end

local function build()
	local K = ns.UIK
	local b = CreateFrame("Button", nil, UIParent)
	btn = b
	b:SetSize(SIZE, SIZE)
	b:SetFrameStrata("MEDIUM")
	b:SetMovable(true)
	b:EnableMouse(true)
	b:SetClampedToScreen(true)
	if b.SetClampRectInsets then b:SetClampRectInsets(-(SIDE + 2), 0, 0, 0) end
	b:RegisterForDrag("LeftButton")
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	local c = cfg()
	if c.pos then
		b:SetPoint(c.pos[1], UIParent, c.pos[2], c.pos[3], c.pos[4])
	else
		b:SetPoint("CENTER", UIParent, "CENTER", 0, 250)
	end

	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0, 1, 0, 1)
	b.icon:SetTexture(TEX_ICON)
	glow(b, TEX_ICON)

	-- Ausrufezeichen: rot = neue (noch nicht gesehene) Auftraege, gruen = gesehen, aber noch offen
	b.mark = b:CreateFontString(nil, "OVERLAY")
	b.mark:SetFont(STANDARD_TEXT_FONT, 24, "OUTLINE")
	b.mark:SetPoint("TOPRIGHT", 8, 10)
	b.mark:SetText("!")
	b.mark:Hide()

	-- neue Auftraege: weiches, pulsierendes Leuchten um das Symbol
	b.glow = b:CreateTexture(nil, "BACKGROUND")
	b.glow:SetSize(SIZE + 22, SIZE + 22)
	b.glow:SetPoint("CENTER")
	b.glow:SetTexture("Interface\\AddOns\\CraftShare\\Media\\MiniGlow")
	b.glow:SetBlendMode("ADD")
	b.glow:SetVertexColor(1, 0.62, 0.15)
	b.glow:Hide()
	b.pulser = CreateFrame("Frame", nil, b)
	b.pulser:Hide()
	b.pulser:SetScript("OnUpdate", function(self, elapsed)
		self.t = (self.t or 0) + elapsed
		b.glow:SetAlpha(0.6 + 0.4 * math.sin(self.t * 3.2))
	end)

	-- Texthinweis am Symbol, Klick oeffnet den Eingang
	local K = ns.UIK
	b.hint = K.Box(b, K.COL.bg, K.COL.gold, "Button")
	b.hint:SetHeight(26)
	b.hint:SetFrameStrata("HIGH")
	b.hint.text = K.FS(b.hint, 14, K.COL.gold, "CENTER")
	b.hint.text:SetPoint("CENTER")
	b.hint:SetScript("OnClick", function() ns.Orders.OpenList("in"); M.AlertDone() end)
	b.hint:Hide()

	b:SetScript("OnDragStart", function(self) self:StartMoving() end)
	b:SetScript("OnDragStop", savePos)
	b:SetScript("OnClick", function(_, button)
		if button == "RightButton" then
			ns.Orders.ToggleList("in")
		else
			-- Hauptfenster; liegen Auftraege vor, den Eingang gleich mit oeffnen
			local wasOpen = _G.CraftShareFrame and _G.CraftShareFrame:IsShown()
			ns.UI.Toggle()
			if wasOpen then
				if withList then ns.Orders.CloseList() end
				withList = false
			elseif ns.Orders.IncomingOpen() > 0 then
				ns.Orders.OpenList("in")
				withList = true
				M.AlertDone()
			end
		end
	end)
	b:SetScript("OnEnter", function(self)
		showTip(self, T("Linksklick: Fenster ein-/ausblenden (mit Eingang, wenn Aufträge offen sind)",
				"Left-click: show/hide window (with incoming orders if any are open)"),
			T("Rechtsklick: Eingang", "Right-click: incoming orders"))
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	buildSide(b, K)
end

function M.Update()
	if not btn then return end
	local n, unseen = 0, 0
	if ns.Orders then n, unseen = ns.Orders.IncomingOpen() end
	if unseen > 0 then btn.mark:SetTextColor(1, 0.25, 0.15) else btn.mark:SetTextColor(0.31, 0.9, 0.35) end
	btn.mark:SetShown(n > 0)
	local alert = unseen > 0 or GetTime() < alertUntil
	btn.glow:SetShown(alert)
	btn.pulser:SetShown(alert)
	btn.hint:SetShown(alert)
	if alert then
		btn.hint.text:SetText(unseen <= 1 and T("Neuer Auftrag!", "New order!")
			or string.format(T("%d neue Aufträge", "%d new orders"), unseen))
		btn.hint:SetWidth(math.ceil(btn.hint.text:GetStringWidth()) + 24)
		-- unter dem Symbol, am unteren Bildschirmrand darueber
		local above = (btn:GetBottom() or 100) < 40
		btn.hint:ClearAllPoints()
		if above then btn.hint:SetPoint("BOTTOMRIGHT", btn, "TOPRIGHT", 0, 8)
		else btn.hint:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, -8) end
		-- am linken Bildschirmrand nach rechts ausrichten
		if (btn:GetLeft() or 200) < 80 then
			btn.hint:ClearAllPoints()
			if above then btn.hint:SetPoint("BOTTOMLEFT", btn, "TOPLEFT", -17, 8)
			else btn.hint:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", -17, -8) end
		end
	end
	-- Feld A zeigt, wer dran ist: orange ich, blau ich warte, abgeblendet kein Auftrag
	if btn.side and ns.Orders then
		local a = btn.side.A
		local active, turn = ns.Orders.ActiveCount()
		a.fill:SetShown(active > 0)
		if turn > 0 then a.fill:SetVertexColor(0.88, 0.44, 0.23) else a.fill:SetVertexColor(0.44, 0.70, 1) end
		if active > 0 then a.label:SetTextColor(0.07, 0.04, 0.02) else a.label:SetTextColor(0.95, 0.76, 0.19) end
		a.label:SetAlpha(active > 0 and 1 or 0.35)
	end
	-- blinken nur, solange etwas ungesehen ist
	if unseen == 0 and btn.ticker then
		btn.ticker:Cancel()
		btn.ticker = nil
		btn.mark:SetAlpha(1)
	end
end

-- Toene fuer neue Auftraege (Spielklaenge; die Lautstaerke folgt den Spieleinstellungen)
local SOUNDS = {
	{ key = "ready", de = "Bereitschaftscheck", en = "Ready check", kit = "READY_CHECK", id = 8960 },
	{ key = "raid", de = "Schlachtzugwarnung", en = "Raid warning", kit = "RAID_WARNING", id = 8959 },
	{ key = "alarm", de = "Wecker", en = "Alarm clock", kit = "ALARM_CLOCK_WARNING_3", id = 12889 },
	{ key = "level", de = "Stufenaufstieg", en = "Level up", kit = "LEVELUP", id = 888 },
	{ key = "quest", de = "Quest abgeschlossen", en = "Quest complete", kit = "IG_QUEST_LIST_COMPLETE", id = 878 },
	{ key = "auction", de = "Auktionshaus", en = "Auction house", kit = "AUCTION_WINDOW_OPEN", id = 5274 },
	{ key = "whisper", de = "Flüstern", en = "Whisper", kit = "TELL_MESSAGE", id = 3081 },
	{ key = "ping", de = "Kartenping (leise)", en = "Map ping (quiet)", kit = "MAP_PING", id = 3175 },
	{ key = "off", de = "Aus", en = "Off" },
}

local function soundIndex()
	for i, s in ipairs(SOUNDS) do
		if s.key == (cfg().sound or "ready") then return i end
	end
	return 1
end

function M.SoundName()
	local s = SOUNDS[soundIndex()]
	return T(s.de, s.en)
end

function M.Sound()
	local s = SOUNDS[soundIndex()]
	if not s.id or not PlaySound then return end
	pcall(PlaySound, (SOUNDKIT and SOUNDKIT[s.kit]) or s.id, "Master")
end

function M.CycleSound()
	cfg().sound = SOUNDS[soundIndex() % #SOUNDS + 1].key
	M.Sound()
end

-- neuer Auftrag: Ton, und Hinweis/Leuchten mindestens 20 Sekunden (auch wenn die Liste gerade offen ist)
function M.Alert()
	alertUntil = GetTime() + 20
	M.Sound()
	M.Update()
	C_Timer.After(20.1, M.Update)
end

function M.AlertDone()
	alertUntil = 0
	M.Update()
end

-- Neuer Auftrag: "!" blinkt kurz
function M.Pulse()
	if not btn then return end
	M.Update()
	local _, unseen = ns.Orders.IncomingOpen()
	if unseen == 0 then return end
	btn.mark:SetAlpha(1)
	if btn.ticker then btn.ticker:Cancel() end
	local n = 0
	btn.ticker = C_Timer.NewTicker(0.35, function()
		n = n + 1
		btn.mark:SetAlpha(n % 2 == 0 and 1 or 0.2)
		if n >= 14 then
			btn.mark:SetAlpha(1)
			if btn.ticker then btn.ticker:Cancel(); btn.ticker = nil end
		end
	end)
end

-- /cs mini [show|hide|reset|sound|test]
function M.Command(arg)
	arg = (arg or ""):lower()
	local c = cfg()
	if arg == "sound" then
		M.CycleSound()
		ns.Print(T("Ton bei neuen Aufträgen: ", "Sound for new orders: ") .. M.SoundName())
		return
	end
	if arg == "test" then
		M.Alert()
		return
	end
	if arg == "reset" then
		c.pos = nil
		btn:ClearAllPoints()
		btn:SetPoint("CENTER", UIParent, "CENTER", 0, 250)
		c.hidden = nil
		btn:Show()
	elseif arg == "hide" or (arg == "" and btn:IsShown()) then
		c.hidden = true
		btn:Hide()
		ns.Print(T("Knopf versteckt. Mit /cs mini wieder anzeigen.", "Button hidden. Show it again with /cs mini."))
	else
		c.hidden = nil
		btn:Show()
	end
end

function M.Init()
	build()
	-- Feld A neu faerben, wenn verschickte Ware inzwischen angekommen ist
	if C_Timer.NewTicker then C_Timer.NewTicker(20, M.Update) end
	if cfg().hidden then btn:Hide() end
	M.Update()
end
