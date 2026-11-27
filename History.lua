-- CraftShare: Historie. Jeder beendete Auftrag wird gemerkt (je Figur) und in einem eigenen Fenster gezeigt.
local ADDON, ns = ...
local H = {}
ns.History = H
local T = ns.T
local K

local MAX = 300
local WIN_W = 520
local ROW_W = WIN_W - 36
local ROWS, ROW_H = 8, 46

local win
local tab = "all" -- all | an (selbst hergestellt) | ag (selbst bestellt)
local allChars = false

-- Ergebnis: Text (deutsch, englisch) und Farbe
local RESULT = {
	done = { "abgeschlossen", "completed", { 0.31, 0.816, 0.353 } },
	withdrawn = { "zurückgezogen", "withdrawn", { 0.91, 0.66, 0.42 } },
	released = { "zurückgegeben", "given back", { 0.91, 0.66, 0.42 } },
	declined = { "abgebrochen", "cancelled", { 0.85, 0.33, 0.29 } },
	expired = { "abgelaufen", "expired", { 0.604, 0.561, 0.494 } },
}

local function log()
	ns.db.history = ns.db.history or {}
	return ns.db.history
end

local function put(entry)
	local list = log()
	-- derselbe Auftrag derselben Figur nur einmal (neuester Stand gewinnt)
	for i = #list, 1, -1 do
		if list[i].id == entry.id and list[i].me == entry.me then table.remove(list, i) end
	end
	table.insert(list, 1, entry)
	while #list > MAX do table.remove(list) end
end

local function entryFor(o, result, who, role, partner)
	return { id = o.id, me = who, role = role, partner = partner, result = result, t = time(),
		out = o.out, rid = o.rid, qty = o.qty, pname = o.pname, key = o.key, mats = o.mats, note = o.note,
		created = tonumber(o.id:match("%-(%d+)%-%d+$")) or o.created }
end

-- Auftrag ist (fuer mich) beendet. Muss vor dem Aendern des Auftrags aufgerufen werden.
-- opts: partner = anderer Name, crafter = ich bin die angesprochene Herstellerfigur
function H.Add(o, result, opts)
	if not o or not ns.db then return end
	opts = opts or {}
	local me = ns.Me()
	local crafter = o.by or opts.partner or (o.to ~= "*" and o.to or nil)
	if o.from == me then
		put(entryFor(o, result, me, "ag", crafter))
		if crafter and ns.IsMine(crafter) and crafter ~= me then put(entryFor(o, result, crafter, "an", me)) end
	elseif o.by == me or opts.crafter then
		put(entryFor(o, result, me, "an", o.from))
		if ns.IsMine(o.from) then put(entryFor(o, result, o.from, "ag", me)) end
	else
		return
	end
	if win and win:IsShown() then H.Refresh() end
end

local function filtered()
	local out = {}
	for _, e in ipairs(log()) do
		if (allChars or e.me == ns.Me()) and (tab == "all" or e.role == tab) then out[#out + 1] = e end
	end
	return out
end

local function name(e)
	return ns.RecipeName(e.rid, { out = e.out })
end

local function paint(row, e)
	local COL = K.COL
	local res = RESULT[e.result] or RESULT.done
	row.item = e
	row.bar:SetColorTexture(res[3][1], res[3][2], res[3][3], 1)
	row.icon:SetTexture((e.out and e.out > 0) and ns.ItemIcon(e.out) or K.profIcon(e.key, e.pname))
	row.title:SetText("|cff9a8f7e#" .. ns.Mail.Code(e.id) .. "|r  " .. e.qty .. "× " .. name(e))
	local who = e.partner and ((e.role == "ag" and T("bei ", "with ") or T("für ", "for ")) .. e.partner)
		or T("an alle im Beruf", "to everyone in the profession")
	local sub = (e.role == "ag" and T("Bestellt", "Ordered") or T("Hergestellt", "Crafted"))
	if e.result ~= "done" then sub = e.role == "ag" and T("Bestellung", "Order") or T("Auftrag", "Job") end
	sub = sub .. " " .. who .. " · " .. date("%d.%m. %H:%M", e.t)
	if allChars then sub = sub .. " · " .. e.me end
	row.sub:SetText(sub)
	row.result:SetText(T(res[1], res[2]))
	row.result:SetTextColor(res[3][1], res[3][2], res[3][3])
	row.title:SetWidth(ROW_W - 60 - math.ceil(row.result:GetStringWidth()) - 16)
	row:Show()
end

function H.Refresh()
	if not win then return end
	local list = filtered()
	win.offset = math.max(0, math.min(win.offset or 0, #list - ROWS))
	for i = 1, ROWS do
		local e = list[win.offset + i]
		if e then paint(win.rows[i], e) else win.rows[i]:Hide() end
	end
	win.slider:Set(win.offset, math.max(0, #list - ROWS))
	win.empty:SetShown(#list == 0)
	local done = 0
	for _, e in ipairs(list) do if e.result == "done" then done = done + 1 end end
	win.sum:SetText(string.format(T("%d Einträge · %d abgeschlossen", "%d entries · %d completed"), #list, done))
	K.setSeg(win.tabAll, tab == "all")
	K.setSeg(win.tabAn, tab == "an")
	K.setSeg(win.tabAg, tab == "ag")
	win.chk:SetChecked(allChars)
end

local function clearList()
	local keep = {}
	for _, e in ipairs(log()) do
		if not ((allChars or e.me == ns.Me()) and (tab == "all" or e.role == tab)) then keep[#keep + 1] = e end
	end
	ns.db.history = keep
	H.Refresh()
end

local function build()
	local COL = K.COL
	local f = K.Box(UIParent, COL.bg, COL.border)
	win = f
	f.offset = 0
	f:SetSize(WIN_W, 100 + ROWS * ROW_H + 40)
	f:SetPoint("CENTER", 0, 0)
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	tinsert(UISpecialFrames, "CraftShareHistoryFrame")
	_G.CraftShareHistoryFrame = f
	if ns.UI and ns.UI.UserScale then f:SetScale(ns.UI.UserScale()) end
	f:Hide()

	local t = K.FS(f, 15, COL.gold)
	t:SetPoint("TOPLEFT", 12, -10)
	t:SetText(T("Historie", "History"))
	local x = K.Btn(f, "X", 20, 20, function() f:Hide() end)
	x:SetPoint("TOPRIGHT", -8, -8)

	local function tabButton(text, value, width)
		return K.Btn(f, text, width, 20, function() tab = value; f.offset = 0; H.Refresh() end, 11)
	end
	f.tabAll = tabButton(T("Alle", "All"), "all", 60)
	f.tabAll:SetPoint("TOPLEFT", 12, -36)
	f.tabAn = tabButton(T("Meine Aufträge", "My jobs"), "an", 120)
	f.tabAn:SetPoint("LEFT", f.tabAll, "RIGHT", -1, 0)
	f.tabAg = tabButton(T("Meine Bestellungen", "My orders"), "ag", 140)
	f.tabAg:SetPoint("LEFT", f.tabAn, "RIGHT", -1, 0)

	f.chk = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	f.chk:SetSize(22, 22)
	f.chk:SetScript("OnClick", function(self) allChars = self:GetChecked() and true or false; f.offset = 0; H.Refresh() end)
	local ct = K.FS(f, 11, COL.muted)
	ct:SetText(T("Alle Figuren", "All characters"))
	ct:SetPoint("TOPRIGHT", -14, -40)
	f.chk:SetPoint("RIGHT", ct, "LEFT", 0, 0)

	f.rows = {}
	for i = 1, ROWS do
		local row = CreateFrame("Frame", nil, f)
		row:SetSize(ROW_W, ROW_H - 2)
		row:SetPoint("TOPLEFT", 12, -64 - (i - 1) * ROW_H)
		row.bg = row:CreateTexture(nil, "BACKGROUND")
		row.bg:SetAllPoints()
		K.setc(row.bg, COL.row)
		row.bar = row:CreateTexture(nil, "BORDER")
		row.bar:SetPoint("TOPLEFT", 0, 0)
		row.bar:SetPoint("BOTTOMLEFT", 0, 0)
		row.bar:SetWidth(4)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(28, 28)
		row.icon:SetPoint("LEFT", 12, 0)
		row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		row.title = K.FS(row, 12, COL.text)
		row.title:SetPoint("TOPLEFT", 48, -7)
		row.sub = K.FS(row, 10, COL.muted)
		row.sub:SetPoint("TOPLEFT", 48, -25)
		row.sub:SetWidth(ROW_W - 60)
		row.result = K.FS(row, 11, COL.muted, "RIGHT")
		row.result:SetPoint("TOPRIGHT", -8, -7)
		row:EnableMouse(true)
		row:SetScript("OnEnter", function(self)
			local e = self.item
			if not e then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine("#" .. ns.Mail.Code(e.id) .. "  " .. e.qty .. "× " .. name(e), 1, 1, 1)
			if e.created then GameTooltip:AddLine(T("Bestellt: ", "Ordered: ") .. date("%d.%m.%Y %H:%M", e.created), 0.8, 0.8, 0.8) end
			GameTooltip:AddLine(T("Beendet: ", "Ended: ") .. date("%d.%m.%Y %H:%M", e.t), 0.8, 0.8, 0.8)
			GameTooltip:AddLine(e.mats == "self" and T("Material vom Auftraggeber", "materials from the customer")
				or T("Material vom Hersteller", "materials from the crafter"), 0.8, 0.8, 0.8)
			if (e.note or "") ~= "" then GameTooltip:AddLine("„" .. e.note .. "“", 0.9, 0.9, 0.9, true) end
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		f.rows[i] = row
	end

	f.empty = K.FS(f, 13, COL.muted, "CENTER")
	f.empty:SetPoint("CENTER", 0, 0)
	f.empty:SetWidth(400)
	f.empty:SetText(T("Noch keine beendeten Aufträge.", "No finished orders yet."))
	f.slider = K.MakeSlider(f, function(v) if v ~= f.offset then f.offset = v; H.Refresh() end end)
	f.slider:SetPoint("TOPRIGHT", -6, -64)
	f.slider:SetHeight(ROWS * ROW_H)
	f:EnableMouseWheel(true)
	f:SetScript("OnMouseWheel", function(_, d)
		f.offset = math.max(0, f.offset - d)
		H.Refresh()
	end)

	f.sum = K.FS(f, 11, COL.muted)
	f.sum:SetPoint("BOTTOMLEFT", 12, 16)
	local clear = K.Btn(f, T("Liste leeren", "Clear list"), 100, 22, function()
		StaticPopupDialogs["CRAFTSHARE_HISTORY"] = {
			text = "%s", button1 = YES, button2 = NO, OnAccept = clearList,
			timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
			OnShow = function(self) self:SetFrameStrata("FULLSCREEN_DIALOG") end,
		}
		StaticPopup_Show("CRAFTSHARE_HISTORY", T("Die angezeigten Einträge aus der Historie löschen?",
			"Delete the shown history entries?"))
	end, 11)
	clear:SetPoint("BOTTOMRIGHT", -12, 10)
	f:SetScript("OnShow", H.Refresh)
end

function H.Toggle()
	K = K or ns.UIK
	if not win then
		build()
		ns.UI.Dockable(win)
	end
	if win:IsShown() then win:Hide() else
		win.offset = 0
		win:Show()
		H.Refresh()
	end
end
