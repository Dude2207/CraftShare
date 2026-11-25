-- CraftShare: Bestellungen. Protokoll (Felder durch "|", Absender kommt vom Addon-Kanal):
--   O|id|to|key|pname|rid|out|outq|qty|mats|tip|note|reag   neue Bestellung (to = "*" = alle im Beruf, sonst Spielername)
--   A|id        Hersteller moechte annehmen (an den Besteller, per Fluestern)
--   T|id|by     Besteller bestaetigt: Auftrag gehoert <by> (an den Hersteller und, bei "*", an alle)
--   N|id|by     Besteller lehnt ab: schon vergeben an <by>
--   W|id        Bestellung zurueckgezogen
--   D|id        Auftrag erledigt (Hersteller -> Besteller, Besteller -> alle)
-- Der Besteller entscheidet allein ueber die Vergabe: wer zuerst annimmt, bekommt den Auftrag.
local ADDON, ns = ...
local O = {}
ns.Orders = O
local T = ns.T
O.KINDS = { O = true, A = true, T = true, N = true, W = true, D = true, R = true, U = true }

local seq = 0
local K
local winOrder, winList, toast
local R = { qty = 1, to = "person", mats = "self" }
local openTab = "in"
local onlyCraft = false
local MAX_AGE = 7 * 86400

local function db()
	ns.db.orders = ns.db.orders or {}
	return ns.db.orders
end

local function me() return ns.Me() end

local function changed()
	if ns.Mini and ns.Mini.Update then ns.Mini.Update() end
	if ns.UI and ns.UI.Dirty then ns.UI.Dirty() end
	if O.Refresh then O.Refresh() end
end

-- ---------------------------------------------------------------- Daten
function O.Name(o)
	return ns.RecipeName(o.rid, { out = o.out })
end

function O.CanCraft(o)
	local c = ns.db.chars[me()]
	local p = c and c.profs[o.key]
	return (p and p.recipes and p.recipes[o.rid]) and true or false
end

-- Hat der eigene Charakter diesen Beruf? Eingehende Auftraege gibt es nur fuer Berufe, die man selbst hat
-- (das Rezept muss man nicht kennen, den Beruf schon).
function O.HasProfession(key)
	local c = ns.db.chars[me()]
	return (c and c.profs[key]) and true or false
end

function O.List(dir)
	local out = {}
	for _, o in pairs(db()) do
		if o.from == me() then
			if dir == "out" then out[#out + 1] = o end
		elseif dir == "in" and not o.dismissed and O.HasProfession(o.key)
			and (o.to == "*" or ns.ShortName(o.to) == me()) then
			-- (die Liste liegt im Account-weiten Speicher: Direkt-Bestellungen an andere Charaktere gehoeren nicht hierher)
			out[#out + 1] = o
		end
	end
	table.sort(out, function(a, b) return (a.created or 0) > (b.created or 0) end)
	return out
end

function O.IncomingOpen()
	local n = 0
	for _, o in pairs(db()) do
		if o.from ~= me() and not o.dismissed and o.st == "open" and O.HasProfession(o.key)
			and (o.to == "*" or ns.ShortName(o.to) == me()) then n = n + 1 end
	end
	return n
end

-- Rohstoffe der Bestellung (Menge ist schon mit der Bestellmenge multipliziert): { {itemID, q}, ... }
function O.Raw(o)
	local r = {}
	for _, e in ipairs(o.r) do r[#r + 1] = { e[1], e[2] * o.qty } end
	return K.RawFresh({ r = r, out = 0 })
end

local function reagString(r, maxn)
	local t = {}
	for i, e in ipairs(r) do
		if i > (maxn or 99) then break end
		t[#t + 1] = e[1] .. ":" .. e[2]
	end
	return table.concat(t, "/")
end

local function encode(o)
	local note = (o.note or ""):gsub("|", "/")
	local nreag = #o.r
	local function build()
		return table.concat({ "O", o.id, o.to, o.key, o.pname, o.rid, o.out or 0, o.outq or 1, o.qty, o.mats, o.tip or 0, note,
			reagString(o.r, nreag) }, "|")
	end
	local s = build()
	while #s > 250 and #note > 0 do note = note:sub(1, math.max(0, #note - 10)); s = build() end
	while #s > 250 and nreag > 1 do nreag = nreag - 1; s = build() end
	return s
end

local function sendOrder(o)
	local msg = encode(o)
	if o.to == "*" then ns.Comm.Broadcast(msg) else ns.Comm.Send(msg, "WHISPER", o.to) end
end

-- ---------------------------------------------------------------- Aktionen
function O.Create(spec)
	seq = seq + 1
	local id = me() .. "-" .. time() .. "-" .. seq
	local r = {}
	for _, e in ipairs(spec.rec.r) do r[#r + 1] = { e[1], e[2] } end
	local o = {
		id = id, from = me(), to = spec.to, key = spec.key, pname = spec.pname, rid = spec.rid,
		out = spec.rec.out or 0, outq = spec.rec.q or 1, qty = spec.qty, mats = spec.mats,
		tip = spec.tip or 0, note = spec.note or "", r = r, st = "open", created = time(),
	}
	db()[id] = o
	sendOrder(o)
	changed()
	return o
end

-- Hersteller: Auftrag annehmen. Erst nach Bestaetigung durch den Besteller gilt er als vergeben.
function O.Accept(o)
	if o.st ~= "open" or not O.CanCraft(o) then return end
	-- Besteller ist ein anderer Charakter desselben Accounts: gleiche Daten, kein Nachrichtenweg noetig
	if ns.IsMine(o.from) then
		o.st = "taken"
		o.by = me()
		changed()
		return
	end
	o.st = "pending"
	ns.Comm.Send("A|" .. o.id, "WHISPER", o.from)
	C_Timer.After(45, function()
		if o.st == "pending" then
			o.st = "open"
			ns.Print(T("Keine Antwort von ", "No answer from ") .. o.from .. T(" – Auftrag wieder offen.", " – order is open again."))
			changed()
		end
	end)
	changed()
end

function O.Ignore(o)
	o.dismissed = true
	changed()
end

function O.Withdraw(o)
	db()[o.id] = nil
	local msg = "W|" .. o.id
	if o.to == "*" then ns.Comm.Broadcast(msg) else ns.Comm.Send(msg, "WHISPER", o.to) end
	changed()
end

-- Hersteller gibt einen angenommenen Auftrag zurueck: er wird fuer alle wieder offen und erscheint wieder im Eingang.
function O.Release(o)
	if o.from == me() or o.by ~= me() then return end
	if not ns.IsMine(o.from) then ns.Comm.Send("R|" .. o.id, "WHISPER", o.from) end
	o.st = "open"
	o.by = nil
	changed()
end

function O.Done(o)
	db()[o.id] = nil
	local msg = "D|" .. o.id
	if o.from == me() then
		if o.to == "*" then ns.Comm.Broadcast(msg) elseif o.by then ns.Comm.Send(msg, "WHISPER", o.by) end
	else
		ns.Comm.Send(msg, "WHISPER", o.from)
	end
	changed()
end

-- ---------------------------------------------------------------- Hinweis im Addon
function O.Notify(text)
	local U = ns.UIK
	if ns.Mini and ns.Mini.Pulse then ns.Mini.Pulse() end
	if not toast then
		toast = U.Box(UIParent, U.COL.bg, U.COL.goldDim, "Button")
		toast:SetSize(380, 44)
		toast:SetPoint("TOP", UIParent, "TOP", 0, -150)
		toast:SetFrameStrata("DIALOG")
		toast.title = U.FS(toast, 11, U.COL.goldDim)
		toast.title:SetPoint("TOPLEFT", 12, -7)
		toast.title:SetText("CraftShare")
		toast.text = U.FS(toast, 12, U.COL.gold)
		toast.text:SetPoint("TOPLEFT", 12, -22)
		toast.text:SetWidth(356)
		toast:SetScript("OnClick", function(self) self:Hide(); O.OpenList() end)
		toast:Hide()
	end
	toast.text:SetText(text)
	toast:Show()
	toast.token = (toast.token or 0) + 1
	local t = toast.token
	C_Timer.After(10, function() if toast.token == t then toast:Hide() end end)
end

-- ---------------------------------------------------------------- Nachrichten
local function validName(s) return s and #s > 0 and #s < 30 end

function O.OnMessage(kind, text, sender)
	local name = ns.ShortName(sender)
	local f = { strsplit("|", text) }
	local id = f[2]
	if not id or #id > 60 then return end

	if kind == "O" then
		local to, key, pname = f[3], f[4], f[5]
		local rid, out, outq, qty = tonumber(f[6]), tonumber(f[7]), tonumber(f[8]), tonumber(f[9])
		local mats, tip, note, reag = f[10], tonumber(f[11]) or 0, f[12] or "", f[13] or ""
		if not (validName(to) and key and #key > 0 and #key < 20 and pname and rid and out and outq and qty) then return end
		if qty < 1 or qty > 99 or (mats ~= "self" and mats ~= "crafter") then return end
		-- Die Auftrags-ID beginnt mit dem Namen des Bestellers (notfalls nur mit dem Vornamen, solange er seinen vollen Namen noch nicht kennt)
		local first = name:match("^%S+") or name
		if db()[id] or not (id:sub(1, #name + 1) == name .. "-" or id:sub(1, #first + 1) == first .. "-") then return end
		-- Den Beruf muss man haben (auch bei direkten Bestellungen), das Rezept dagegen nicht
		if not O.HasProfession(key) then return end
		if to ~= "*" then
			if ns.ShortName(to) ~= me() then return end
			to = me()
		end
		local r = {}
		for item, q in reag:gmatch("(%d+):(%d+)") do
			if #r < 12 then r[#r + 1] = { tonumber(item), tonumber(q) } end
		end
		local o = { id = id, from = name, to = to, key = key, pname = pname, rid = rid, out = out, outq = math.max(1, outq),
			qty = qty, mats = mats, tip = tip, note = note:sub(1, 60), r = r, st = "open", created = time() }
		db()[id] = o
		O.Notify(string.format(T("Neuer Auftrag von %s: %d× %s", "New order from %s: %d× %s"), name, qty, O.Name(o)))
		changed()
		return
	end

	local o = db()[id]
	if not o then return end

	if kind == "A" then
		-- Besteller entscheidet: wer zuerst kommt
		if o.from ~= me() then return end
		if o.st == "open" and (o.to == "*" or ns.ShortName(o.to) == name) then
			o.st = "taken"
			o.by = name
			ns.Comm.Send("T|" .. id .. "|" .. name, "WHISPER", sender)
			if o.to == "*" then ns.Comm.Broadcast("T|" .. id .. "|" .. name) end
			O.Notify(string.format(T("%s hat deinen Auftrag angenommen: %d× %s", "%s accepted your order: %d× %s"), name, o.qty, O.Name(o)))
		else
			ns.Comm.Send("N|" .. id .. "|" .. (o.by or "?"), "WHISPER", sender)
		end
	elseif kind == "T" then
		if name ~= o.from or not f[3] then return end
		o.st = "taken"
		o.by = ns.ShortName(f[3])
		changed()
	elseif kind == "N" then
		if name ~= o.from or not f[3] then return end
		if o.st == "pending" then
			o.st = "taken"
			o.by = ns.ShortName(f[3])
			ns.Print(string.format(T("Der Auftrag von %s ist schon an %s vergeben.", "%s's order is already taken by %s."), o.from, o.by))
			changed()
		end
	elseif kind == "W" then
		if name ~= o.from then return end
		db()[id] = nil
		changed()
	elseif kind == "R" then
		-- Besteller: der Hersteller gibt den Auftrag zurueck, dann ist er fuer alle wieder offen
		if o.from ~= me() or o.st ~= "taken" or o.by ~= name then return end
		o.st = "open"
		o.by = nil
		local msg = "U|" .. id
		if o.to == "*" then ns.Comm.Broadcast(msg) else ns.Comm.Send(msg, "WHISPER", o.to) end
		O.Notify(string.format(T("%s hat den Auftrag zurückgegeben: %d× %s", "%s gave the order back: %d× %s"), name, o.qty, O.Name(o)))
		changed()
	elseif kind == "U" then
		-- wieder offen (vom Besteller)
		if name ~= o.from then return end
		local was = o.st
		o.st = "open"
		o.by = nil
		-- wer den Auftrag selbst zurueckgegeben hat (schon wieder offen), braucht keinen Hinweis
		if was ~= "open" and not o.dismissed and O.HasProfession(o.key) then
			O.Notify(string.format(T("Auftrag wieder offen: %d× %s von %s", "Order open again: %d× %s from %s"), o.qty, O.Name(o), o.from))
		end
		changed()
	elseif kind == "D" then
		if o.from == me() then
			if name ~= o.by then return end
			db()[id] = nil
			if o.to == "*" then ns.Comm.Broadcast("D|" .. id) end
			O.Notify(string.format(T("%s meldet fertig: %d× %s", "%s reports done: %d× %s"), name, o.qty, O.Name(o)))
		elseif name == o.from then
			db()[id] = nil
		else
			return
		end
		changed()
	end
end

function O.Init()
	K = ns.UIK
	-- alte Auftraege aufraeumen
	local now = time()
	for id, o in pairs(db()) do
		if now - (o.created or 0) > MAX_AGE then db()[id] = nil
		elseif o.st == "pending" then o.st = "open" end
	end
end

-- ---------------------------------------------------------------- Fenster: Bestellen
local function allRecipes(q)
	local seen, out = {}, {}
	q = (q or ""):lower()
	for _, c in pairs(ns.db.chars) do
		for key, p in pairs(c.profs) do
			for id, rec in pairs(p.recipes or {}) do
				local k = key .. ":" .. id
				if not seen[k] then
					seen[k] = true
					local name = ns.RecipeName(id, rec)
					local pn = p.name or key
					if q == "" or name:lower():find(q, 1, true) or pn:lower():find(q, 1, true) then
						out[#out + 1] = { key = key, rid = id, rec = rec, pname = pn, name = name }
					end
				end
			end
		end
	end
	table.sort(out, function(a, b)
		if a.pname ~= b.pname then return a.pname < b.pname end
		return a.name < b.name
	end)
	return out
end

local function Lbl(parent, text, y)
	local s = K.FS(parent, 10, K.COL.goldDim)
	s:SetPoint("TOPLEFT", 12, y)
	s:SetText(text:upper())
	return s
end

local function EditBoxIn(parent, w, h, onChange)
	local b = K.Box(parent, K.COL.black, K.COL.border)
	b:SetSize(w, h)
	local e = CreateFrame("EditBox", nil, b)
	e:SetPoint("TOPLEFT", 6, -2)
	e:SetPoint("BOTTOMRIGHT", -6, 2)
	e:SetAutoFocus(false)
	e:SetFont(STANDARD_TEXT_FONT, 12, "")
	e:SetTextColor(K.COL.text[1], K.COL.text[2], K.COL.text[3])
	e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	if onChange then e:SetScript("OnTextChanged", onChange) end
	b.edit = e
	return b
end

-- kleine scrollbare Liste (Mausrad) mit festen Zeilen
local function MiniList(parent, n, rowH, width, paint, click)
	local L = { rows = {}, items = {}, offset = 0, n = n }
	L.frame = CreateFrame("Frame", nil, parent)
	L.frame:SetSize(width, n * rowH)
	for i = 1, n do
		local r = CreateFrame("Button", nil, L.frame)
		r:SetSize(width, rowH)
		r:SetPoint("TOPLEFT", 0, -(i - 1) * rowH)
		r.bg = r:CreateTexture(nil, "BACKGROUND")
		r.bg:SetPoint("TOPLEFT", 0, -1)
		r.bg:SetPoint("BOTTOMRIGHT", 0, 1)
		local hl = r:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.07)
		r.t1 = K.FS(r, 12, K.COL.text)
		r.t1:SetPoint("LEFT", 8, 0)
		r.t2 = K.FS(r, 11, K.COL.muted, "RIGHT")
		r.t2:SetPoint("RIGHT", -8, 0)
		r:SetScript("OnClick", function(self) if self.item and click then click(self.item) end end)
		L.rows[i] = r
	end
	L.frame:EnableMouseWheel(true)
	L.frame:SetScript("OnMouseWheel", function(_, d)
		L.offset = math.max(0, math.min(math.max(0, #L.items - n), L.offset - d))
		L.Render()
	end)
	function L.Render()
		for i = 1, n do
			local it = L.items[L.offset + i]
			local r = L.rows[i]
			r.item = it
			if it then paint(r, it); r:Show() else r:Hide() end
		end
	end
	function L.Set(items)
		L.items = items
		L.offset = math.min(L.offset, math.max(0, #items - n))
		L.Render()
	end
	return L
end

local function foundRecipe(key, rid)
	for _, c in pairs(ns.db.chars) do
		local p = c.profs[key]
		local rec = p and p.recipes and p.recipes[rid]
		if rec then return rec, p.name or key end
	end
end

local function persons()
	local list = {}
	if not R.key then return list end
	for cname, c in pairs(ns.db.chars) do
		local p = c.profs[R.key]
		if p and cname ~= me() then
			list[#list + 1] = { name = cname, char = c, online = ns.Roster.IsOnline(cname),
				can = (p.recipes and p.recipes[R.rid]) and true or false }
		end
	end
	table.sort(list, function(a, b)
		if a.online ~= b.online then return a.online end
		if a.can ~= b.can then return a.can end
		return a.name < b.name
	end)
	return list
end

local function refreshOrderForm()
	if not winOrder then return end
	local w = winOrder
	local COL = K.COL
	-- Rezept
	if R.rec then
		w.recIcon:SetTexture(ns.ItemIcon(R.rec.out))
		w.recName:SetText(ns.RecipeName(R.rid, R.rec))
		w.recProf:SetText(R.pname or "")
	else
		w.recIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
		w.recName:SetText(T("Kein Rezept gewählt – unten suchen", "No recipe selected – search below"))
		w.recProf:SetText("")
	end
	w.qtyBox.edit:SetText(tostring(R.qty))
	-- Empfaenger
	K.setSeg(w.toPerson, R.to == "person")
	K.setSeg(w.toAll, R.to == "all")
	local list = persons()
	local can, on = 0, 0
	for _, p in ipairs(list) do
		if p.can then can = can + 1 end
		if p.online then on = on + 1 end
	end
	if R.to == "person" then
		w.personList.frame:Show()
		w.allInfo:Hide()
		w.personList.Set(list)
	else
		w.personList.frame:Hide()
		w.allInfo:Show()
		if R.rec then
			w.allInfo:SetText(string.format(T(
				"Geht an alle %d Mitglieder im Beruf %s (%d online) – auch an die, die das Rezept noch nicht kennen. %d davon können es sofort herstellen. Der erste, der annimmt, bekommt den Auftrag.",
				"Goes to all %d members with %s (%d online) – including those who do not know the recipe yet. %d of them can craft it right away. The first to accept gets the order."),
				#list, R.pname or "", on, can))
		else
			w.allInfo:SetText(T("Wähle zuerst ein Rezept.", "Select a recipe first."))
		end
	end
	-- Material
	K.setSeg(w.matSelf, R.mats == "self")
	K.setSeg(w.matCr, R.mats == "crafter")
	if R.rec then
		local r = {}
		for _, e in ipairs(R.rec.r) do r[#r + 1] = { e[1], e[2] * R.qty } end
		local raw = K.RawFresh({ r = r, out = 0 })
		local lines = { string.format(T("Rohstoffe für %d× %s:", "Raw materials for %d× %s:"), R.qty, ns.RecipeName(R.rid, R.rec)) }
		for _, e in ipairs(raw) do
			local have = GetItemCount and GetItemCount(e[1], true) or 0
			local line = K.itemText(e[1], e[2])
			if R.mats == "self" then
				local ok = have >= e[2]
				line = line .. "   |cff" .. (ok and "4fd05a" or "d9544a") .. T("Besitz: ", "Owned: ") .. have .. "|r"
			end
			lines[#lines + 1] = line
		end
		w.needs:SetText(table.concat(lines, "\n"))
	else
		w.needs:SetText("")
	end
end

local function buildOrderWindow()
	local f = K.Box(UIParent, K.COL.bg, K.COL.border)
	winOrder = f
	f:SetSize(440, 520)
	f:SetPoint("CENTER", -200, 20)
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	tinsert(UISpecialFrames, "CraftShareOrderFrame")
	_G.CraftShareOrderFrame = f
	if ns.UI and ns.UI.UserScale then f:SetScale(ns.UI.UserScale()) end
	f:Hide()

	local t = K.FS(f, 15, K.COL.gold)
	t:SetPoint("TOPLEFT", 12, -10)
	t:SetText(T("Bestellen", "Order"))
	local x = K.Btn(f, "X", 20, 20, function() f:Hide() end)
	x:SetPoint("TOPRIGHT", -8, -8)

	-- Rezept
	Lbl(f, T("Rezept", "Recipe"), -34)
	local rb = K.Box(f, K.COL.panel, K.COL.border2)
	rb:SetPoint("TOPLEFT", 12, -48)
	rb:SetSize(416, 32)
	f.recIcon = rb:CreateTexture(nil, "ARTWORK")
	f.recIcon:SetSize(24, 24)
	f.recIcon:SetPoint("LEFT", 6, 0)
	f.recIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	f.recName = K.FS(rb, 13, K.COL.text)
	f.recName:SetPoint("LEFT", f.recIcon, "RIGHT", 8, 5)
	f.recName:SetWidth(300)
	f.recProf = K.FS(rb, 11, K.COL.muted)
	f.recProf:SetPoint("LEFT", f.recIcon, "RIGHT", 8, -8)
	f.recProf:SetWidth(300)

	local results
	local search = EditBoxIn(f, 416, 22, function(self)
		local q = strtrim(self:GetText())
		if q == "" then results.frame:Hide() return end
		results.frame:Show()
		results.Set(allRecipes(q))
	end)
	search:SetPoint("TOPLEFT", 12, -84)
	local ph = K.FS(search, 12, K.COL.muted)
	ph:SetPoint("LEFT", 8, 0)
	ph:SetText(T("anderes Rezept suchen …", "search another recipe …"))
	search.edit:HookScript("OnTextChanged", function(self) ph:SetShown(self:GetText() == "") end)
	f.search = search

	results = MiniList(f, 6, 20, 416, function(r, it)
		r.bg:SetColorTexture(K.COL.panel[1], K.COL.panel[2], K.COL.panel[3], 1)
		r.t1:SetText(it.name)
		r.t2:SetText(it.pname)
	end, function(it)
		R.key, R.rid, R.rec, R.pname, R.person = it.key, it.rid, it.rec, it.pname, nil
		search.edit:SetText("")
		search.edit:ClearFocus()
		results.frame:Hide()
		refreshOrderForm()
	end)
	results.frame:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -1)
	results.frame:SetFrameLevel(f:GetFrameLevel() + 20)
	results.frame:Hide()
	local rbg = results.frame:CreateTexture(nil, "BACKGROUND")
	rbg:SetAllPoints()
	K.setc(rbg, K.COL.black)

	-- Menge
	Lbl(f, T("Menge", "Quantity"), -114)
	local minus = K.Btn(f, "-", 24, 22, function() R.qty = math.max(1, R.qty - 1); refreshOrderForm() end)
	minus:SetPoint("TOPLEFT", 12, -128)
	f.qtyBox = EditBoxIn(f, 50, 22, function(self, user)
		if not user then return end
		local n = tonumber(self:GetText())
		if n then R.qty = math.max(1, math.min(99, math.floor(n))); refreshOrderForm() end
	end)
	f.qtyBox:SetPoint("LEFT", minus, "RIGHT", 4, 0)
	f.qtyBox.edit:SetJustifyH("CENTER")
	f.qtyBox.edit:SetNumeric(true)
	f.qtyBox.edit:SetMaxLetters(2)
	local plus = K.Btn(f, "+", 24, 22, function() R.qty = math.min(99, R.qty + 1); refreshOrderForm() end)
	plus:SetPoint("LEFT", f.qtyBox, "RIGHT", 4, 0)

	-- Empfaenger
	Lbl(f, T("Empfänger", "Recipient"), -160)
	f.toPerson = K.Btn(f, T("Bestimmte Person", "Specific person"), 130, 20, function() R.to = "person"; refreshOrderForm() end, 11)
	f.toPerson:SetPoint("TOPLEFT", 12, -174)
	f.toAll = K.Btn(f, T("Alle im Beruf", "Everyone in profession"), 130, 20, function() R.to = "all"; refreshOrderForm() end, 11)
	f.toAll:SetPoint("LEFT", f.toPerson, "RIGHT", -1, 0)
	f.personList = MiniList(f, 4, 22, 416, function(r, it)
		local sel = (R.person == it.name)
		r.bg:SetColorTexture(sel and 0.29 or 0.141, sel and 0.239 or 0.118, sel and 0.071 or 0.09, 1)
		local dot = it.online and "|cff4fd05a●|r " or ""
		r.t1:SetText(K.classHex(it.char.class) .. it.name .. "|r" .. (it.online and ("  |cff4fd05a" .. T("online", "online") .. "|r") or ""))
		r.t2:SetText(it.can and T("kann herstellen", "can craft") or T("kennt das Rezept noch nicht", "does not know the recipe yet"))
	end, function(it)
		R.person = it.name
		f.personList.Render()
	end)
	f.personList.frame:SetPoint("TOPLEFT", 12, -198)
	f.allInfo = K.FS(f, 11, K.COL.muted)
	f.allInfo:SetPoint("TOPLEFT", 12, -200)
	f.allInfo:SetWidth(416)
	f.allInfo:SetHeight(70)
	f.allInfo:SetWordWrap(true)
	f.allInfo:SetJustifyV("TOP")

	-- Material
	Lbl(f, T("Material", "Materials"), -296)
	f.matSelf = K.Btn(f, T("Ich liefere es", "I provide it"), 130, 20, function() R.mats = "self"; refreshOrderForm() end, 11)
	f.matSelf:SetPoint("TOPLEFT", 12, -310)
	f.matCr = K.Btn(f, T("Hersteller besorgt es", "Crafter gets it"), 140, 20, function() R.mats = "crafter"; refreshOrderForm() end, 11)
	f.matCr:SetPoint("LEFT", f.matSelf, "RIGHT", -1, 0)
	f.needs = K.FS(f, 11, K.COL.text)
	f.needs:SetPoint("TOPLEFT", 12, -336)
	f.needs:SetWidth(416)
	f.needs:SetHeight(98)
	f.needs:SetWordWrap(false)
	f.needs:SetJustifyV("TOP")
	f.needs:SetSpacing(2)

	-- Trinkgeld und Notiz
	Lbl(f, T("Trinkgeld", "Tip"), -440)
	local function coinBox(x, w, letters, tag, color)
		local b = EditBoxIn(f, w, 22)
		b:SetPoint("TOPLEFT", x, -454)
		b.edit:SetNumeric(true)
		b.edit:SetMaxLetters(letters)
		local l = K.FS(f, 12, color)
		l:SetPoint("LEFT", b, "RIGHT", 3, 0)
		l:SetText(tag)
		return b
	end
	f.tipG = coinBox(12, 54, 6, "g", { 1, 0.82, 0.2 })
	f.tipS = coinBox(80, 32, 2, "s", { 0.78, 0.78, 0.82 })
	f.tipC = coinBox(126, 32, 2, "k", { 0.85, 0.5, 0.3 })
	local nl = Lbl(f, T("Notiz (optional)", "Note (optional)"), -440)
	nl:ClearAllPoints()
	nl:SetPoint("TOPLEFT", 180, -440)
	f.note = EditBoxIn(f, 248, 22)
	f.note:SetPoint("TOPLEFT", 180, -454)
	f.note.edit:SetMaxLetters(40)

	local cancel = K.Btn(f, T("Abbrechen", "Cancel"), 100, 24, function() f:Hide() end)
	cancel:SetPoint("BOTTOMLEFT", 12, 10)
	local send = K.Btn(f, T("Bestellung senden", "Send order"), 160, 24, function()
		if not R.rec then ns.Print(T("Bitte zuerst ein Rezept wählen.", "Please select a recipe first.")) return end
		local to = "*"
		if R.to == "person" then
			if not R.person then ns.Print(T("Bitte einen Empfänger wählen.", "Please select a recipient.")) return end
			to = R.person
		end
		O.Create({ key = R.key, pname = R.pname, rid = R.rid, rec = R.rec, qty = R.qty, to = to, mats = R.mats,
			tip = (tonumber(f.tipG.edit:GetText()) or 0) * 10000 + math.min(99, tonumber(f.tipS.edit:GetText()) or 0) * 100 + math.min(99, tonumber(f.tipC.edit:GetText()) or 0), note = strtrim(f.note.edit:GetText()) })
		f:Hide()
		ns.Print(T("Bestellung gesendet an ", "Order sent to ") .. (to == "*" and (T("alle im Beruf ", "everyone in ") .. (R.pname or "")) or to))
	end)
	send:SetPoint("BOTTOMRIGHT", -12, 10)
end

function O.OpenOrder()
	K = K or ns.UIK
	if not winOrder then buildOrderWindow() end
	local key, rid = ns.UI.GetSelection()
	R = { qty = 1, to = "person", mats = "self" }
	if key and rid then
		local rec, pname = foundRecipe(key, rid)
		if rec then R.key, R.rid, R.rec, R.pname = key, rid, rec, pname end
	end
	winOrder.tipG.edit:SetText("")
	winOrder.tipS.edit:SetText("")
	winOrder.tipC.edit:SetText("")
	winOrder.note.edit:SetText("")
	winOrder.search.edit:SetText("")
	winOrder:Show()
	refreshOrderForm()
end

-- ---------------------------------------------------------------- Fenster: Offene Auftraege
local LROWS, LROW_H = 6, 56

local function paintOrderRow(row, o)
	local inc = (o.from ~= me())
	row.icon:SetTexture((o.out and o.out > 0) and ns.ItemIcon(o.out) or K.profIcon(o.key, o.pname))
	row.title:SetText(o.qty .. "× " .. O.Name(o))
	local target
	if o.to == "*" then target = T("an alle im Beruf ", "to everyone in ") .. (o.pname or "")
	elseif inc then target = T("direkt an dich", "directly to you")
	else target = T("an ", "to ") .. o.to end
	local sub = (inc and (T("von ", "from ") .. o.from .. " · ") or "") .. target .. " · " ..
		(o.mats == "self" and T("Material wird gestellt", "materials provided") or T("Hersteller besorgt Material", "crafter gets materials")) ..
		((o.tip or 0) > 0 and (" · " .. T("Trinkgeld ", "tip ") .. ns.Prices.Money(o.tip)) or "") ..
		((o.note or "") ~= "" and (" · „" .. o.note .. "“") or "")
	row.sub:SetText(sub)
	local parts = {}
	for _, e in ipairs(O.Raw(o)) do parts[#parts + 1] = K.itemText(e[1], e[2]) end
	row.raw:SetText(T("Rohstoffe: ", "Raw materials: ") .. table.concat(parts, " · "))

	local COL = K.COL
	local chip, chipC, acts = "", COL.muted, {}
	local accent = COL.orange
	local function B(text, fn, enabled) acts[#acts + 1] = { text = text, fn = fn, enabled = enabled ~= false } end
	if inc then
		if o.st == "open" then
			local can = O.CanCraft(o)
			if not can then chip, chipC = T("Rezept noch unbekannt", "recipe not known yet"), { 0.91, 0.66, 0.42 } end
			B(T("Annehmen", "Accept"), function() O.Accept(o) end, can)
			B(T("Ignorieren", "Ignore"), function() O.Ignore(o) end)
		elseif o.st == "pending" then
			chip, chipC = T("wartet auf Bestätigung …", "waiting for confirmation …"), COL.gold
		elseif o.by == me() then
			accent = COL.green
			chip, chipC = T("Von dir angenommen", "Accepted by you"), COL.green
			B(T("Anflüstern", "Whisper"), function() K.whisper(o.from) end)
			B(T("Fertig", "Done"), function() O.Done(o) end)
			B(T("Zurückgeben", "Give back"), function() O.Release(o) end)
		else
			accent = COL.off
			chip = T("übernommen von ", "taken by ") .. (o.by or "?")
		end
	else
		if o.st ~= "taken" then
			chip, chipC = (o.to == "*") and T("wartet auf Hersteller", "waiting for a crafter") or (T("wartet auf ", "waiting for ") .. o.to), COL.gold
			B(T("Zurückziehen", "Withdraw"), function() O.Withdraw(o) end)
		else
			accent = COL.green
			chip, chipC = T("angenommen von ", "accepted by ") .. (o.by or "?"), COL.green
			B(T("Anflüstern", "Whisper"), function() K.whisper(o.by) end)
			B(T("Erhalten", "Received"), function() O.Done(o) end)
			B(T("Zurückziehen", "Withdraw"), function() O.Withdraw(o) end)
		end
	end
	K.setc(row.bar, accent)
	row.chip:SetText(chip)
	row.chip:SetTextColor(chipC[1], chipC[2], chipC[3])
	-- Knoepfe fuellen sich von rechts: 1-3 Aktionen
	for i = 1, 3 do
		local b = row.btns[i]
		local spec = acts[i - (3 - #acts)]
		if spec then
			b.label:SetText(spec.text)
			b.fn = spec.fn
			if spec.enabled then b:Enable(); b.label:SetTextColor(K.COL.gold[1], K.COL.gold[2], K.COL.gold[3])
			else b:Disable(); b.label:SetTextColor(0.45, 0.4, 0.3) end
			b:Show()
		else
			b:Hide()
		end
	end
	row:SetAlpha((inc and o.st == "taken" and o.by ~= me()) and 0.65 or 1)
end

local function renderList()
	if not winList or not winList:IsShown() then return end
	local w = winList
	local inN, outN = #O.List("in"), #O.List("out")
	w.tabIn.label:SetText(T("Eingehend (", "Incoming (") .. inN .. ")")
	w.tabOut.label:SetText(T("Meine Bestellungen (", "My orders (") .. outN .. ")")
	K.setSeg(w.tabIn, openTab == "in")
	K.setSeg(w.tabOut, openTab == "out")
	w.chk:SetShown(openTab == "in")
	w.chkText:SetShown(openTab == "in")
	local list = O.List(openTab)
	if openTab == "in" and onlyCraft then
		local f = {}
		for _, o in ipairs(list) do if O.CanCraft(o) then f[#f + 1] = o end end
		list = f
	end
	w.items = list
	local maxOff = math.max(0, #list - LROWS)
	if w.offset > maxOff then w.offset = maxOff end
	w.slider:Set(w.offset, maxOff)
	for i = 1, LROWS do
		local row, o = w.rows[i], list[w.offset + i]
		row.item = o
		if o then paintOrderRow(row, o); row:Show() else row:Hide() end
	end
	w.empty:SetShown(#list == 0)
	w.empty:SetText(openTab == "in" and T("Keine Aufträge für dich.", "No orders for you.") or T("Du hast nichts bestellt.", "You have not ordered anything."))
end

local function buildListWindow()
	local f = K.Box(UIParent, K.COL.bg, K.COL.border)
	winList = f
	f.offset = 0
	f:SetSize(640, 470)
	f:SetPoint("CENTER", 220, 20)
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	tinsert(UISpecialFrames, "CraftShareOrdersFrame")
	_G.CraftShareOrdersFrame = f
	if ns.UI and ns.UI.UserScale then f:SetScale(ns.UI.UserScale()) end
	f:Hide()

	local t = K.FS(f, 15, K.COL.gold)
	t:SetPoint("TOPLEFT", 12, -10)
	t:SetText(T("Offene Aufträge", "Open orders"))
	local x = K.Btn(f, "X", 20, 20, function() f:Hide() end)
	x:SetPoint("TOPRIGHT", -8, -8)

	f.tabIn = K.Btn(f, "", 120, 20, function() openTab = "in"; f.offset = 0; renderList() end, 11)
	f.tabIn:SetPoint("TOPLEFT", 12, -36)
	f.tabOut = K.Btn(f, "", 150, 20, function() openTab = "out"; f.offset = 0; renderList() end, 11)
	f.tabOut:SetPoint("LEFT", f.tabIn, "RIGHT", -1, 0)

	f.chk = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	f.chk:SetSize(22, 22)
	f.chk:SetPoint("TOPRIGHT", -190, -34)
	f.chk:SetScript("OnClick", function(self) onlyCraft = self:GetChecked() and true or false; f.offset = 0; renderList() end)
	f.chkText = K.FS(f, 11, K.COL.muted)
	f.chkText:SetPoint("LEFT", f.chk, "RIGHT", 0, 0)
	f.chkText:SetText(T("Nur, was ich herstellen kann", "Only what I can craft"))

	f.rows = {}
	for i = 1, LROWS do
		local row = CreateFrame("Frame", nil, f)
		row:SetSize(600, LROW_H)
		row:SetPoint("TOPLEFT", 12, -64 - (i - 1) * LROW_H)
		row.bg = row:CreateTexture(nil, "BACKGROUND")
		row.bg:SetPoint("TOPLEFT", 0, -1)
		row.bg:SetPoint("BOTTOMRIGHT", 0, 1)
		K.setc(row.bg, K.COL.row)
		row.bar = row:CreateTexture(nil, "BORDER")
		row.bar:SetPoint("TOPLEFT", 0, -1)
		row.bar:SetPoint("BOTTOMLEFT", 0, 1)
		row.bar:SetWidth(4)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(28, 28)
		row.icon:SetPoint("LEFT", 12, 0)
		row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		row.title = K.FS(row, 13, K.COL.text)
		row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 4)
		row.title:SetWidth(300)
		row.sub = K.FS(row, 10, K.COL.muted)
		row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
		row.sub:SetWidth(300)
		row.raw = K.FS(row, 10, K.COL.muted)
		row.raw:SetPoint("TOPLEFT", row.sub, "BOTTOMLEFT", 0, -2)
		row.raw:SetWidth(300)
		row.chip = K.FS(row, 11, K.COL.muted, "RIGHT")
		row.chip:SetPoint("TOPRIGHT", -8, -8)
		row.chip:SetWidth(200)
		row.btns = {}
		for j = 3, 1, -1 do
			local b = K.Btn(row, "", 78, 18, function(self) if self.fn then self.fn() end end, 11)
			if j == 3 then b:SetPoint("BOTTOMRIGHT", -8, 7) else b:SetPoint("RIGHT", row.btns[j + 1], "LEFT", -4, 0) end
			row.btns[j] = b
		end
		-- Tooltip mit allen Angaben (lange Namen und Rohstofflisten sind in der Zeile gekuerzt)
		row:EnableMouse(true)
		row:SetScript("OnEnter", function(self)
			local o = self.item
			if not o then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(o.qty .. "× " .. O.Name(o), 1, 1, 1)
			GameTooltip:AddLine(T("von ", "from ") .. o.from, 0.8, 0.8, 0.8)
			GameTooltip:AddLine((o.to == "*") and (T("an alle im Beruf ", "to everyone in ") .. (o.pname or "")) or (T("an ", "to ") .. o.to), 0.8, 0.8, 0.8)
			if (o.tip or 0) > 0 then GameTooltip:AddLine(T("Trinkgeld: ", "Tip: ") .. ns.Prices.Money(o.tip), 1, 0.82, 0) end
			if (o.note or "") ~= "" then GameTooltip:AddLine("„" .. o.note .. "“", 0.9, 0.9, 0.9, true) end
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(T("Rohstoffe:", "Raw materials:"), 1, 0.82, 0)
			for _, e in ipairs(O.Raw(o)) do GameTooltip:AddLine(K.itemText(e[1], e[2]), 1, 1, 1) end
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		f.rows[i] = row
	end
	f.empty = K.FS(f, 13, K.COL.muted, "CENTER")
	f.empty:SetPoint("CENTER", f, "CENTER", 0, 0)
	f.empty:SetWidth(400)
	f.slider = K.MakeSlider(f, function(v) if v ~= f.offset then f.offset = v; renderList() end end)
	f.slider:SetPoint("TOPRIGHT", -4, -64)
	f.slider:SetHeight(LROWS * LROW_H)
	f:EnableMouseWheel(true)
	f:SetScript("OnMouseWheel", function(_, d)
		f.offset = math.max(0, f.offset - d)
		renderList()
	end)
	local close = K.Btn(f, T("Schließen", "Close"), 100, 24, function() f:Hide() end)
	close:SetPoint("BOTTOMRIGHT", -12, 10)
	f:SetScript("OnShow", renderList)
end

function O.OpenList()
	K = K or ns.UIK
	if not winList then buildListWindow() end
	winList:Show()
	renderList()
end

-- Knopf-Verhalten: erster Klick oeffnet, zweiter schliesst
function O.ToggleOrder()
	if winOrder and winOrder:IsShown() then winOrder:Hide() else O.OpenOrder() end
end

function O.ToggleList()
	if winList and winList:IsShown() then winList:Hide() else O.OpenList() end
end

function O.Refresh()
	if winList and winList:IsShown() then renderList() end
	if winOrder and winOrder:IsShown() then refreshOrderForm() end
end
