-- Preischeck: eigenes Fenster fuer das markierte Rezept (Kosten, guenstigster Weg, Einkaufsliste)
local ADDON, ns = ...
local T = ns.T

local PC = {}
ns.PriceCheck = PC

local K, P
local frame, rows, lines, slider = nil, {}, {}, nil
local offset, qty = 0, 1
local cur, curKey
local W = {}
local shopItems = {}
local detOpen = false
local ROWS, ROW_H = 30, 20

-- Spalten je Zeilenart: { x, breite, ausrichtung }
local COLS = {
	line = { [1] = { 0, 220, "LEFT" }, [2] = { 222, 110, "LEFT" }, [3] = { 334, 80, "RIGHT" }, [4] = { 420, 92, "RIGHT" } },
	wide = { [1] = { 0, 512, "LEFT" } },
	box = { [1] = { 0, 168, "LEFT" }, [2] = { 176, 168, "LEFT" }, [4] = { 352, 160, "LEFT" } },
	shop = { [1] = { 0, 220, "LEFT" }, [2] = { 222, 60, "RIGHT" }, [3] = { 292, 118, "LEFT" }, [4] = { 420, 92, "RIGHT" } },
}

-- ---------------------------------------------------------------- Zeilen berechnen
local function howText(u)
	if not u then return "|cff9a8f7e" .. T("kein Preis", "no price") .. "|r" end
	if u.how == "ah" then return "|cff6fb3ff" .. T("Auktionshaus", "Auction house") .. "|r" end
	if u.how == "vendor" then return "|cffe8c46a" .. T("Händler", "Vendor") .. "|r" end
	return "|cff4fd05a" .. T("herstellen", "craft") .. "|r"
end

local function compareText(id)
	local c = P.Compare(id)
	local function part(key, label, value)
		if c.best == key and value then return "|cff4fd05a" .. label .. " " .. P.Money(value) .. " (" .. T("günstigster", "cheapest") .. ")|r" end
		return "|cff9a8f7e" .. label .. " " .. (value and P.Money(value) or "–") .. "|r"
	end
	return "|cff9a8f7e" .. T("Vergleich je Stück: ", "Compare each: ") .. "|r" ..
		part("ah", T("AH", "AH"), c.ah) .. "|cff9a8f7e · |r" ..
		part("vendor", T("Händler", "Vendor"), c.vendor) .. "|cff9a8f7e · |r" ..
		part("make", T("herstellen", "craft"), c.make)
end

local function build()
	local out, det = {}, {}
	local tgt = det
	local function add(kind, t, flags)
		local ln = { kind = kind, t = t }
		if flags then for k, v in pairs(flags) do ln[k] = v end end
		tgt[#tgt + 1] = ln
	end
	if not cur then
		tgt = out
		add("wide", { T("Wähle in der Liste ein Rezept und klicke auf „Preis Check“.", "Select a recipe in the list and click “Price check”.") }, { dim = true })
		return out
	end
	P.Begin()
	local rec = cur.rec
	local free = P.Settings().free
	add("line", { T("Benötigt (×", "Required (×") .. qty .. ")", T("Günstigster Weg", "Cheapest way"), T("Stück", "Each"), T("Summe", "Total") }, { hdr = true })

	local total, unk = 0, 0
	local acc, order, how, unit = {}, {}, {}, {}
	local function collect(id, u, need)
		if need <= 0 then return end
		if u and u.how == "make" then
			local crafts = math.ceil(need / (u.prod.q or 1))
			for _, r in ipairs(u.prod.r) do
				local rneed = r[2] * crafts - ns.ItemCount(r[1], true)
				if rneed > 0 then collect(r[1], P.Unit(r[1], 1), rneed) end
			end
		else
			if not acc[id] then acc[id] = 0 order[#order + 1] = id end
			acc[id] = acc[id] + need
			how[id] = u and u.how or nil
			unit[id] = u and u.unit or nil
		end
	end
	local function addSub(u, q, depth)
		local crafts = math.ceil(q / (u.prod.q or 1))
		for _, r in ipairs(u.prod.r) do
			local rq = r[2] * crafts
			local ru = P.Unit(r[1], depth + 1)
			add("line", {
				string.rep("    ", depth) .. "» " .. K.itemText(r[1], rq),
				ru and howText(ru) or "",
				ru and P.Money(ru.unit) or "",
				ru and P.Money(ru.unit * rq) or "",
			}, { dim = true })
			if ru and ru.how == "make" and depth < 2 then addSub(ru, rq, depth + 1) end
		end
	end

	for _, d in ipairs(rec.r) do
		local id, q = d[1], d[2] * qty
		local have = ns.ItemCount(id, true)
		local u = P.Unit(id)
		local hc = have >= q and "|cff4fd05a" or (have > 0 and "|cffe8a96a" or "|cffd9544a")
		local pay = free and math.max(0, q - have) or q
		if u then total = total + u.unit * pay else unk = unk + 1 end
		add("line", { K.itemText(id, q) .. "  " .. hc .. "(" .. have .. ")|r", howText(u), u and P.Money(u.unit) or "", u and P.Money(u.unit * pay) or "" })
		if u and u.how == "make" then addSub(u, q, 0) end
		add("wide", { "  " .. compareText(id) }, { dim = true })
		collect(id, u, math.max(0, q - have))
	end

	-- Zusammenfassung
	local ah = rec.out and rec.out > 0 and P.AH(rec.out)
	local ahTotal = ah and ah * qty
	local verdict = "|cff9a8f7e–|r"
	if unk > 0 then
		verdict = "|cff9a8f7e" .. T("Preise unvollständig", "Prices incomplete") .. "|r"
	elseif ahTotal and total > 0 then
		local diff = ahTotal - total
		if diff > 0 then verdict = "|cff4fd05a" .. T("Herstellen lassen spart ", "Crafting saves ") .. "|r" .. P.Money(diff)
		elseif diff < 0 then verdict = "|cffe8a96a" .. T("Fertig kaufen spart ", "Buying saves ") .. "|r" .. P.Money(-diff)
		else verdict = T("Beides kostet gleich viel", "Both cost the same") end
	end
	tgt = out
	add("wide", { T("ÜBERBLICK", "OVERVIEW") }, { sec = true })
	add("box", { [1] = T("MATERIALKOSTEN", "MATERIAL COST"), [2] = T("KAUFPREIS AM AH", "AH PRICE") .. (qty > 1 and (" (×" .. qty .. ")") or ""), [4] = T("VERGLEICH", "COMPARISON") }, { hdr = true })
	add("box", { [1] = P.Money(total) .. (unk > 0 and " |cff9a8f7e+?|r" or ""), [2] = ahTotal and P.Money(ahTotal) or "–", [4] = verdict })

	-- Einkaufsliste
	add("wide", { "" }, { gap = true })
	add("wide", { T("EINKAUFSLISTE", "SHOPPING LIST") }, { sec = true, shopHdr = true })
	shopItems = {}
	for _, id in ipairs(order) do shopItems[#shopItems + 1] = { id = id, n = acc[id] } end
	if #order == 0 then
		add("wide", { T("Nichts zu besorgen.", "Nothing to buy.") }, { dim = true })
	else
		add("shop", { T("Gegenstand", "Item"), T("Menge", "Qty"), T("Wo", "Where"), T("Preis", "Price") }, { hdr = true })
		local sum, sumUnk = 0, false
		for _, id in ipairs(order) do
			local n = acc[id]
			local w = how[id] == "ah" and ("|cff6fb3ff" .. T("Auktionshaus", "Auction house") .. "|r")
				or (how[id] == "vendor" and ("|cffe8c46a" .. T("Händler", "Vendor") .. "|r"))
				or ("|cff9a8f7e" .. T("unbekannt", "unknown") .. "|r")
			local price = unit[id] and P.Money(unit[id] * n) or "–"
			if unit[id] then sum = sum + unit[id] * n else sumUnk = true end
			add("shop", { ns.ItemName(id) or ("item:" .. id), tostring(n), w, price }, { item = id })
		end
		add("shop", { T("Summe", "Total"), "", "", P.Money(sum) .. (sumUnk and " |cff9a8f7e+?|r" or "") }, { dim = true })
	end
	local n = 0
	for _, ln in ipairs(out) do
		if ln.sec then n = n + 1 end
		if not ln.gap and n > 0 then ln.sid = n end
	end
	return out
end

-- ---------------------------------------------------------------- Zeichnen
local frames = {}
local function sectionFrame(i)
	if frames[i] then return frames[i] end
	local list = rows[1]:GetParent()
	local f = K.Box(list, K.COL.panel, K.COL.border)
	f:SetFrameLevel(list:GetFrameLevel())
	frames[i] = f
	return f
end

local function paintFrames()
	local first, last = {}, {}
	for i = 1, ROWS do
		local ln = lines[offset + i]
		if ln and ln.sid then
			first[ln.sid] = first[ln.sid] or i
			last[ln.sid] = i
		end
	end
	for sid = 1, 3 do
		local f = sectionFrame(sid)
		if first[sid] then
			local fi, li = first[sid], last[sid]
			local list = rows[1]:GetParent()
			f:ClearAllPoints()
			f:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -6 - (fi - 1) * ROW_H + 4)
			f:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -6 - (fi - 1) * ROW_H + 4)
			f:SetHeight((li - fi + 1) * ROW_H + 8)
			f:Show()
		else
			f:Hide()
		end
	end
end

local function paint()
	if not frame then return end
	local n = #lines
	local maxOff = math.max(0, n - ROWS)
	local vis = math.max(1, math.min(n, ROWS))
	local listH = vis * ROW_H + 12
	rows[1]:GetParent():SetHeight(listH)
	frame:SetHeight(10 + 40 + 8 + 52 + 8 + 24 + 8 + listH + 10)
	slider:SetHeight(vis * ROW_H)
	slider:SetShown(maxOff > 0)
	if offset > maxOff then offset = maxOff end
	slider:Set(offset, maxOff)
	for i = 1, ROWS do
		local row, ln = rows[i], lines[offset + i]
		if not ln then
			row:Hide()
		else
			row:Show()
			local cols = COLS[ln.kind]
			local c = ln.sec and K.COL.gold or (ln.hdr and K.COL.goldDim or (ln.dim and K.COL.muted or K.COL.text))
			K.setc(row.bg, (ln.sec or ln.hdr) and K.COL.black or K.COL.tree, ln.sec and 0.95 or (ln.hdr and 0.5 or 0.0))
			row.ln = ln
			row.aucBtn:SetShown(ln.shopHdr and #shopItems > 0 and PC.HasAuctionator())
			row:EnableMouse((ln.toggle or ln.item) and true or false)
			for j = 1, 4 do
				local fs, spec = row.fs[j], cols[j]
				if spec then
					fs:ClearAllPoints()
					fs:SetPoint("LEFT", row, "LEFT", spec[1], 0)
					fs:SetWidth(spec[2])
					fs:SetJustifyH(spec[3])
					fs:SetTextColor(c[1], c[2], c[3])
					fs:SetText(ln.t[j] or "")
					fs:Show()
				else
					fs:SetText("")
					fs:Hide()
				end
			end
		end
	end
	paintFrames()
end

local function updateHead()
	if cur then
		W.icon:SetTexture(ns.ItemIcon(cur.rec.out))
		W.icon:Show()
		W.name:SetText(cur.name or "")
		local prof = cur.crafters and cur.crafters[1] and cur.crafters[1].prof and cur.crafters[1].prof.name or ""
		W.sub:SetText(prof .. ((cur.catName and cur.catName ~= "") and (" · " .. cur.catName) or ""))
	else
		W.icon:Hide()
		W.name:SetText(T("Kein Rezept gewählt", "No recipe selected"))
		W.sub:SetText("")
	end
	W.qty:SetText(qty)
	local txt, ok = P.StatusText()
	W.status:SetText((ok and "|TInterface\\COMMON\\Indicator-Green:12|t " or "|TInterface\\COMMON\\Indicator-Red:12|t ") .. txt)
end

function PC.Refresh()
	if not frame or not frame:IsShown() then return end
	local e = ns.UI and ns.UI.GetSelectedEntry and ns.UI.GetSelectedEntry()
	local key = e and (e.key .. "/" .. e.id) or nil
	if key ~= curKey then qty, offset, curKey = 1, 0, key end
	cur = e
	updateHead()
	lines = build()
	paint()
end

-- Aufruf aus UI.Refresh (Auswahl oder Preise haben sich geaendert)
function PC.OnRefresh()
	if frame and frame:IsShown() then PC.Refresh() end
end

-- ---------------------------------------------------------------- Fenster bauen
local function create()
	K, P = ns.UIK, ns.Prices
	local COL = K.COL
	local f = K.Box(UIParent, COL.bg, COL.border)
	frame = f
	f:SetSize(560, 560)
	f:SetFrameStrata("HIGH")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local p, _, rp, x, y = self:GetPoint()
		ns.db.ui = ns.db.ui or {}
		ns.db.ui.pcPos = { p, rp, x, y }
	end)
	local pos = ns.db.ui and ns.db.ui.pcPos
	if pos then
		f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	elseif _G.CraftShareFrame then
		f:SetPoint("TOPLEFT", _G.CraftShareFrame, "TOPRIGHT", 8, 0)
	else
		f:SetPoint("CENTER")
	end
	_G.CraftSharePriceCheck = f
	if ns.UI and ns.UI.UserScale then f:SetScale(ns.UI.UserScale()) end
	tinsert(UISpecialFrames, "CraftSharePriceCheck")
	f:Hide()

	-- Kopf
	local top = K.Box(f, COL.panel, COL.border)
	top:SetPoint("TOPLEFT", 10, -10)
	top:SetPoint("TOPRIGHT", -10, -10)
	top:SetHeight(40)
	local title = K.FS(top, 18, COL.gold)
	title:SetPoint("LEFT", 12, 0)
	title:SetText(T("Preis Check", "Price check"))
	local close = K.Btn(top, "X", 22, 22, function() f:Hide() end)
	close:SetPoint("RIGHT", -8, 0)
	local recalc = K.Btn(top, T("Neu berechnen", "Recalculate"), 110, 22, function() PC.Refresh() end, 11)
	recalc:SetPoint("RIGHT", close, "LEFT", -6, 0)

	-- Rezeptkopf mit Menge
	local head = K.Box(f, COL.panel, COL.border)
	head:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -8)
	head:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT", 0, -8)
	head:SetHeight(52)
	local ibox = K.Box(head, COL.black, COL.border)
	ibox:SetSize(36, 36)
	ibox:SetPoint("LEFT", 8, 0)
	W.icon = ibox:CreateTexture(nil, "ARTWORK")
	W.icon:SetPoint("TOPLEFT", 2, -2)
	W.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	W.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	W.name = K.FS(head, 16, COL.gold)
	W.name:SetPoint("TOPLEFT", ibox, "TOPRIGHT", 10, -2)
	W.name:SetWidth(300)
	W.sub = K.FS(head, 12, COL.muted)
	W.sub:SetPoint("TOPLEFT", W.name, "BOTTOMLEFT", 0, -3)
	W.sub:SetWidth(300)
	local plus = K.Btn(head, "+", 22, 22, function() qty = math.min(999, qty + (IsShiftKeyDown() and 10 or 1)); PC.Refresh() end)
	plus:SetPoint("RIGHT", -10, 0)
	local qbox = K.Box(head, COL.black, COL.border)
	qbox:SetSize(44, 22)
	qbox:SetPoint("RIGHT", plus, "LEFT", -4, 0)
	W.qty = K.FS(qbox, 12, COL.text, "CENTER")
	W.qty:SetPoint("CENTER")
	local minus = K.Btn(head, "-", 22, 22, function() qty = math.max(1, qty - (IsShiftKeyDown() and 10 or 1)); PC.Refresh() end)
	minus:SetPoint("RIGHT", qbox, "LEFT", -4, 0)
	local ql = K.FS(head, 11, COL.muted, "RIGHT")
	ql:SetPoint("RIGHT", minus, "LEFT", -6, 0)
	ql:SetText(T("Menge", "Quantity"))

	-- Preisquelle
	local st = K.Box(f, COL.panel, COL.border)
	st:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -8)
	st:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", 0, -8)
	st:SetHeight(24)
	W.status = K.FS(st, 11, COL.muted)
	W.status:SetPoint("LEFT", 10, 0)
	W.status:SetPoint("RIGHT", -10, 0)

	-- Liste
	local list = CreateFrame("Frame", nil, f)
	list:SetPoint("TOPLEFT", st, "BOTTOMLEFT", 0, -8)
	list:SetPoint("TOPRIGHT", st, "BOTTOMRIGHT", 0, -8)
	list:SetHeight(100)
	rows = {}
	for i = 1, ROWS do
		local row = CreateFrame("Button", nil, list)
		row:RegisterForClicks("LeftButtonUp")
		row:SetFrameLevel(list:GetFrameLevel() + 3)
		row:SetSize(512, ROW_H)
		row:SetPoint("TOPLEFT", 10, -6 - (i - 1) * ROW_H)
		row.bg = row:CreateTexture(nil, "BACKGROUND")
		row.bg:SetAllPoints()
		row.fs = {}
		for j = 1, 4 do row.fs[j] = K.FS(row, 11, COL.text, "LEFT") end
		row.aucBtn = K.Btn(row, T("Einkaufsliste an Auctionator senden", "Send shopping list to Auctionator"), 230, 18, function() PC.SendToAuctionator() end, 11)
		row.aucBtn:SetPoint("RIGHT", -4, 0)
		row.aucBtn:Hide()
		row:EnableMouseWheel(true)
		row:SetScript("OnMouseWheel", function(_, delta) offset = math.max(0, offset - delta * 2); paint() end)
		row:SetScript("OnClick", function(self)
			local ln = self.ln
			if ln and ln.item and IsShiftKeyDown() then PC.ShiftClick(ln.item) end
		end)
		row:SetScript("OnEnter", function(self)
			local ln = self.ln
			if ln and ln.item then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetHyperlink("item:" .. ln.item)
				GameTooltip:AddLine(T("Shift-Klick: in den Chat / ins AH-Suchfeld", "Shift-click: to chat / AH search"), 0.6, 0.6, 0.6)
				GameTooltip:Show()
			end
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		rows[i] = row
	end
	slider = K.MakeSlider(list, function(v) if v ~= offset then offset = v; paint() end end)
	slider:SetPoint("TOPRIGHT", -6, -6)
	slider:SetFrameLevel(list:GetFrameLevel() + 6)
	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(_, delta)
		offset = math.max(0, offset - delta * 2)
		paint()
	end)
end

-- Shift-Klick auf einen Gegenstand: in den Chat oder ins Suchfeld des Auktionshauses
local function insertLink(link)
	local fns = {
		_G.ChatFrameUtil and _G.ChatFrameUtil.InsertLink,
		_G.ChatEdit_InsertLink,
	}
	for _, fn in ipairs(fns) do
		local ok, res = pcall(fn, link)
		if ok and res then return true end
	end
	local eb = _G.ChatEdit_GetActiveWindow and _G.ChatEdit_GetActiveWindow()
	if eb and eb:IsVisible() then eb:Insert(link) return true end
	return false
end

function PC.ShiftClick(id)
	local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local name, link = getInfo(id)
	name = name or ns.ItemName(id)
	link = link or ("|cffffffff|Hitem:" .. id .. ":::::::::::::::|h[" .. (name or id) .. "]|h|r")
	if insertLink(link) then return end
	local ahOpen = ns.Prices and ns.Prices.IsAHOpen and ns.Prices.IsAHOpen()
	if ahOpen and name then
		local ok = pcall(function()
			local ah = _G.AuctionHouseFrame
			if ah and ah.SearchBar and ah.SearchBar.SearchBox then
				ah.SearchBar.SearchBox:SetText(name)
				if ah.SearchBar.StartSearch then ah.SearchBar:StartSearch() end
			elseif _G.BrowseName then
				_G.BrowseName:SetText(name)
			else
				error("no search box")
			end
		end)
		if ok then return end
	end
	local ok, err = pcall(function()
		if _G.ChatFrameUtil and _G.ChatFrameUtil.OpenChat then _G.ChatFrameUtil.OpenChat(link)
		else ChatFrame_OpenChat(link) end
	end)
	if not ok then print("|cff4fd05aGuild CraftShare|r: " .. tostring(err)) end
end

function PC.HasAuctionator()
	local A = _G.Auctionator
	return A and A.API and A.API.v1 and A.API.v1.CreateShoppingList and A.API.v1.ConvertToSearchString and true or false
end

-- Einkaufsliste in Auctionator anlegen: items = { { id = Gegenstand, n = Menge }, ... }
function PC.CreateList(title, items)
	if not PC.HasAuctionator() or #items == 0 then return end
	local api = _G.Auctionator.API.v1
	local terms = {}
	for _, it in ipairs(items) do
		local name = ns.ItemName(it.id)
		if name then
			local ok, str = pcall(api.ConvertToSearchString, "CraftShare", { searchString = name, isExact = true, quantity = it.n })
			if ok and str then terms[#terms + 1] = str end
		end
	end
	if #terms == 0 then print("|cff4fd05aGuild CraftShare|r: " .. T("Keine Gegenstandsnamen verfügbar.", "No item names available.")) return end
	local listName = "Guild CraftShare: " .. (title or "")
	local ok, err = pcall(api.CreateShoppingList, "CraftShare", listName, terms)
	if ok then
		print("|cff4fd05aGuild CraftShare|r: " .. T("Einkaufsliste an Auctionator gesendet: ", "Shopping list sent to Auctionator: ") .. listName)
	else
		print("|cff4fd05aGuild CraftShare|r: " .. tostring(err))
	end
end

function PC.SendToAuctionator()
	PC.CreateList(cur and cur.name or "", shopItems)
end

function PC.Toggle()
	if frame and frame:IsShown() then frame:Hide() else PC.Open() end
end

function PC.Open()
	if not frame then
		create()
		ns.UI.Dockable(frame)
	end
	frame:Show()
	curKey = nil
	PC.Refresh()
end
