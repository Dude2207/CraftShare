-- CraftShare: kleiner, frei beweglicher Knopf (zeigt/versteckt das Hauptfenster, "!" bei offenen oder neuen Auftraegen).
local ADDON, ns = ...
local M = {}
ns.Mini = M
local T = ns.T

local btn

local function cfg()
	ns.db.mini = ns.db.mini or {}
	return ns.db.mini
end

-- drei kleine Felder links am Knopf: A aktueller Auftrag, Q Auftragsliste, X noch frei
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
	{ key = "X", tip = T("Noch nicht belegt", "Not assigned yet") },
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

	b:SetScript("OnDragStart", function(self) self:StartMoving() end)
	b:SetScript("OnDragStop", savePos)
	b:SetScript("OnClick", function(_, button)
		if button == "RightButton" then ns.Orders.ToggleList("in") else ns.UI.Toggle() end
	end)
	b:SetScript("OnEnter", function(self)
		showTip(self, T("Linksklick: Fenster ein-/ausblenden", "Left-click: show/hide window"),
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

-- /cs mini [show|hide|reset]
function M.Command(arg)
	arg = (arg or ""):lower()
	local c = cfg()
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
	if cfg().hidden then btn:Hide() end
	M.Update()
end
