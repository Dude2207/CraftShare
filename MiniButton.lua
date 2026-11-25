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

local function build()
	local K = ns.UIK
	local b = CreateFrame("Button", nil, UIParent)
	btn = b
	b:SetSize(40, 40)
	b:SetFrameStrata("MEDIUM")
	b:SetMovable(true)
	b:EnableMouse(true)
	b:SetClampedToScreen(true)
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
	b.icon:SetTexture("Interface\\AddOns\\CraftShare\\Media\\Icon")
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.15)

	-- Ausrufezeichen: offene oder neue Auftraege
	b.mark = b:CreateFontString(nil, "OVERLAY")
	b.mark:SetFont(STANDARD_TEXT_FONT, 24, "OUTLINE")
	b.mark:SetTextColor(1, 0.35, 0.2)
	b.mark:SetPoint("TOPRIGHT", 8, 10)
	b.mark:SetText("!")
	b.mark:Hide()

	b:SetScript("OnDragStart", function(self) self:StartMoving() end)
	b:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local p, _, rp, x, y = self:GetPoint()
		cfg().pos = { p, rp, x, y }
	end)
	b:SetScript("OnClick", function(_, button)
		if button == "RightButton" then ns.Orders.ToggleList() else ns.UI.Toggle() end
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("CraftShare", 0.95, 0.76, 0.19)
		local n = ns.Orders and ns.Orders.IncomingOpen() or 0
		if n > 0 then
			GameTooltip:AddLine(string.format(T("%d offene Aufträge", "%d open orders"), n), 1, 0.45, 0.25)
		end
		GameTooltip:AddLine(T("Linksklick: Fenster ein-/ausblenden", "Left-click: show/hide window"), 0.8, 0.8, 0.8)
		GameTooltip:AddLine(T("Rechtsklick: Offene Aufträge", "Right-click: open orders"), 0.8, 0.8, 0.8)
		GameTooltip:AddLine(T("Ziehen: Knopf verschieben", "Drag: move button"), 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function M.Update()
	if not btn then return end
	local n = ns.Orders and ns.Orders.IncomingOpen() or 0
	btn.mark:SetShown(n > 0)
	if n == 0 and btn.ticker then
		btn.ticker:Cancel()
		btn.ticker = nil
	end
end

-- Neuer Auftrag: "!" blinkt kurz
function M.Pulse()
	if not btn then return end
	btn.mark:Show()
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
