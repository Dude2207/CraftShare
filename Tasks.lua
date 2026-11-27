-- CraftShare: Auftragsfenster. Zeigt einen angenommenen Auftrag als Aufgabenliste, getrennt nach Besteller
-- (Material schicken, Ware empfangen) und Hersteller (herstellen, Ware verschicken).
local ADDON, ns = ...
local Task = {}
ns.Task = Task
local T = ns.T
local K, O

local WIDTH = 460
local STEP_W = WIDTH - 20
local BODY_X = 32
local BODY_W = STEP_W - BODY_X - 10
local MAXLINES, LINE_H = 14, 17
local MAXBTNS = 6

local win
local curId
local folded = false -- bis auf die Kopfzeile eingeklappt (bis zum Schliessen)

-- welcher Auftrag ist je Figur offen, und wo steht das Fenster
local function ui()
	ns.db.ui = ns.db.ui or {}
	ns.db.ui.openTask = ns.db.ui.openTask or {}
	return ns.db.ui
end

local function forget()
	ui().openTask[ns.Me()] = nil
end

local function place(f)
	local p = ui().taskPos
	f:ClearAllPoints()
	if p then
		f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p[1], p[2])
	else
		f:SetPoint("TOP", UIParent, "TOP", 0, -90)
	end
end

local function bags(id)
	return ns.ItemCount(id)
end

local function money(c) return ns.Prices.Money(c) end

local function green(s) return "|cff4fd05a" .. s .. "|r" end
local function red(s) return "|cffd9544a" .. s .. "|r" end
local function muted(s) return "|cff9a8f7e" .. s .. "|r" end

local function partnerName(o)
	if O.Role(o) == "ag" then return o.by or "?" end
	return o.from
end

-- Taschen und Bank (die Bank kennt das Spiel erst, nachdem man sie einmal geoeffnet hat)
local function owned(id) return ns.ItemCount(id, true) end

local function haveText(id, need)
	local have = bags(id)
	if have >= need then return green(have .. T(" in Taschen", " in bags")) end
	local total = math.max(have, owned(id))
	local bank = total - have
	local text = have .. T(" in Taschen", " in bags")
	if bank > 0 then text = text .. ", " .. bank .. T(" Bank", " bank") end
	-- genug da, aber noch von der Bank zu holen
	if total >= need then return "|cffe8a96a" .. text .. "|r" end
	return red(text .. ", " .. (need - total) .. T(" fehlen", " missing"))
end

-- ---------------------------------------------------------------- Inhalt der Schritte
local function set(o, field, value)
	o[field] = value
	O.Push(o)
end

local function undo(fn) return { text = T("Rückgängig", "Undo"), fn = fn, right = true } end

-- Materialkosten (Hersteller besorgt das Material): Zeilen, Betragsfelder und Haekchen im Versandschritt.
-- Bezahlt wird per Nachnahme, die im Spiel derzeit abgeschaltet ist.
local function addCosts(s, o, ag)
	if o.mats ~= "crafter" then return end
	local cost, known = O.CodAmount(o)
	local label = O.COD_ENABLED and T("Nachnahme (Material)", "Cash on delivery (materials)")
		or T("Materialkosten", "Material costs")
	s.lines[#s.lines + 1] = { label, not known and muted(T("legt der Hersteller fest", "set by the crafter"))
		or (cost == 0 and green(T("keine", "none"))) or money(cost) }
	if not O.COD_ENABLED and (not known or cost > 0) then
		s.hint = (s.hint and (s.hint .. " ") or "") .. muted(T("Nachnahme ist derzeit deaktiviert, bitte selbst abrechnen.",
			"Cash on delivery is currently disabled, please settle it yourselves."))
	end
	if ag or o.sh then return end
	local free = o.mcSet and o.mc == 0
	s.checks = { { text = T("Material vorhanden, keine Materialkosten", "I have the materials, no material costs"),
		checked = free and true or false, fn = function(v)
			if v then
				o.mcPrev, o.mcPrevSet = o.mc, o.mcSet
				o.mc, o.mcSet = 0, true
			else
				o.mc, o.mcSet = o.mcPrev, o.mcPrevSet
				if not o.mc or o.mc == 0 then o.mc, o.mcSet = O.SuggestMatCost(o), nil end
			end
			for _, f in ipairs(win.steps) do
				for i = 1, 3 do f.coins[i].edit:ClearFocus() end
			end
			O.Push(o)
		end } }
	if not free then
		local suggested, unknown = O.SuggestMatCost(o)
		s.coins = (o.mcSet and o.mc) or suggested
		if unknown > 0 and not o.mcSet then
			s.hint = (s.hint and (s.hint .. " ") or "") .. red(unknown .. T(" Zutat(en) ohne Preis.", " ingredient(s) without a price."))
		end
	end
end

local function stepMaterials(o, ag)
	local done = o.mr or (o.cr or 0) > 0 or o.sh
	local s = { title = ag and T("Material an ", "Send materials to ") .. partnerName(o) .. T(" schicken", "")
		or T("Material von ", "Materials from ") .. o.from, lines = {}, buttons = {} }
	if done then
		s.state, s.chip = "done", T("erledigt", "done")
		if not ag and o.mr and (o.cr or 0) == 0 and not o.sh then
			s.buttons[1] = undo(function() o.finalTaken = nil; set(o, "mr", nil) end)
		end
		return s
	end
	local list = O.SendList(o)
	local sent = o.sentM or {}
	for i, e in ipairs(list) do
		local right
		local rest = e[2] - (sent[e[1]] or 0)
		if o.ms or (ag and rest <= 0) then right = muted(T("verschickt", "sent"))
		elseif ag and rest < e[2] then right = haveText(e[1], rest) .. muted(" (" .. (e[2] - rest) .. T(" verschickt", " sent") .. ")")
		elseif ag then right = haveText(e[1], e[2])
		else right = muted(T("offen", "open")) end
		s.lines[i] = { K.itemText(e[1], e[2]), right, e[1] }
	end
	if ag then
		if o.ms then
			s.state, s.chip = "wait", T("unterwegs zu ", "on the way to ") .. partnerName(o)
			s.buttons[1] = undo(function() o.plan, o.sentM, o.msAt = nil, nil, nil; set(o, "ms", nil) end)
		else
			s.state, s.chip = "act", T("deine Aufgabe", "your task")
			s.hint = T("Geh zum Briefkasten, die Post wird vorbereitet. Bei Übergabe per Handel hier abhaken.",
				"Go to a mailbox and the mail is prepared. If you trade it, tick it off here.")
			if o.hold then
				s.hint = s.hint .. " " .. red(T("Der Auftrag wird erst danach an ", "The order is only sent to ") .. partnerName(o) ..
					T(" gesendet.", " after that."))
			end
			s.buttons[1] = { tick = true, tip = T("Von Hand abhaken", "Tick off manually"), fn = function() set(o, "ms", true) end }
			-- was noch fehlt, als Einkaufsliste an Auctionator geben
			local need = {}
			for _, e in ipairs(list) do
				local missing = e[2] - (sent[e[1]] or 0) - owned(e[1])
				if missing > 0 then need[#need + 1] = { id = e[1], n = missing } end
			end
			-- am Bankschalter: das Fehlende aus der Bank in die Taschen holen
			local fetch = {}
			for _, e in ipairs(list) do
				local want = e[2] - (sent[e[1]] or 0) - bags(e[1])
				local inBank = owned(e[1]) - bags(e[1])
				if want > 0 and inBank > 0 then fetch[#fetch + 1] = { id = e[1], n = math.min(want, inBank) } end
			end
			if #need > 0 and ns.PriceCheck and ns.PriceCheck.HasAuctionator() then
				s.buttons[2] = { text = T("Einkaufsliste an Auctionator", "Shopping list to Auctionator"), fn = function()
					ns.PriceCheck.CreateList(o.qty .. "x " .. O.Name(o) .. " #" .. ns.Mail.Code(o.id), need)
				end }
			end
			if #fetch > 0 and ns.Mail and ns.Mail.bankOpen then
				s.buttons[#s.buttons + 1] = { text = T("Aus Bank holen", "Fetch from bank"), main = true,
					fn = function() ns.Mail.FetchFromBank(fetch) end }
			end
		end
	else
		-- per Post verschickt: Zeitpunkt, und Restzeit solange sie noch unterwegs ist
		local left = O.MatTransit(o)
		if o.ms and o.msAt then
			s.hint = o.from .. T(" hat die Rohstoffe um ", " sent the materials at ") .. date("%H:%M", o.msAt) .. T(" Uhr verschickt. ", ". ")
			s.hint = s.hint .. (left > 0 and (T("Ankunft in höchstens ", "Arrives within ") .. O.Clock(left) .. T(" Minuten.", " minutes."))
				or green(T("Die Post sollte da sein.", "The mail should have arrived.")))
		end
		if left > 0 then
			s.state, s.chip = "wait", T("unterwegs ", "on the way ") .. O.Clock(left)
		elseif o.ms then
			s.state, s.chip = "act", T("Post abholen", "check your mail")
		else
			s.state, s.chip = "wait", T("wartet auf ", "waiting for ") .. o.from
		end
		s.buttons[1] = { text = T("Material erhalten", "Materials received"), main = o.ms, fn = function() set(o, "mr", true) end }
	end
	return s
end

-- wie oft reichen die Zutaten in den Taschen
local function craftable(reagents)
	local n
	for _, e in ipairs(reagents) do
		local c = math.floor(bags(e[1]) / e[2])
		if not n or c < n then n = c end
	end
	return n or 0
end

-- eigenes Rezept, das diesen Gegenstand herstellt
local function ownRecipeFor(itemID)
	local c = ns.db.chars[ns.Me()]
	for key, p in pairs(c and c.profs or {}) do
		for rid, rec in pairs(p.recipes or {}) do
			if rec.out == itemID and rec.r and #rec.r > 0 then return rid, rec, key end
		end
	end
end

local function stepCraft(o, ag)
	local cr = o.cr or 0
	local what = o.qty .. "× " .. O.Name(o)
	local s = { title = ag and (partnerName(o) .. T(" stellt her", " crafts")) or what .. T(" herstellen", ": craft"), lines = {}, buttons = {} }
	local count = cr .. T(" von ", " of ") .. o.qty
	if cr >= o.qty or o.sh then
		s.state, s.chip = "done", o.qty .. T(" von ", " of ") .. o.qty
		if not ag and not o.sh then s.buttons[1] = undo(function() set(o, "cr", o.qty - 1) end) end
		return s
	end
	if not (o.mats == "crafter" or o.mr) then
		s.state, s.chip = "idle", T("noch nicht dran", "not yet")
		return s
	end
	if ag then
		s.state, s.chip = "wait", count
		return s
	end
	s.state, s.chip = "act", count
	local rest = o.qty - cr
	for i, e in ipairs(o.r) do
		s.lines[i] = { K.itemText(e[1], e[2] * rest), haveText(e[1], e[2] * rest), e[1] }
	end
	local raw = K.RawFresh({ r = o.r, out = 0 })
	local differs = #raw ~= #o.r
	for i, e in ipairs(raw) do
		if not o.r[i] or o.r[i][1] ~= e[1] then differs = true end
	end
	if differs then
		local parts = {}
		for _, e in ipairs(raw) do parts[#parts + 1] = K.itemText(e[1], e[2] * rest) end
		s.hint = T("Rohstoffe dafür: ", "Raw materials: ") .. table.concat(parts, ", ")
	end
	-- Herstellen direkt aus dem Fenster
	local n = math.min(rest, craftable(o.r))
	s.buttons[1] = { text = n > 0 and (T("Herstellen (", "Craft (") .. n .. "×)") or T("Herstellen", "Craft"), main = n > 0,
		enabled = n > 0, fn = function() Task.Craft(o, o.rid, n) end }
	s.buttons[2] = { text = T("Beruf öffnen", "Open profession"), fn = function() Task.OpenProfession(o.key) end }
	s.buttons[3] = { text = T("1× abhaken", "Tick off 1×"), fn = function() set(o, "cr", cr + 1) end }
	if cr > 0 then s.buttons[4] = undo(function() set(o, "cr", cr - 1) end) end
	-- am Bankschalter: fehlende Zutaten in die Taschen holen
	if ns.Mail and ns.Mail.bankOpen then
		local fetch = {}
		for _, e in ipairs(o.r) do
			local want = e[2] * rest - bags(e[1])
			local inBank = owned(e[1]) - bags(e[1])
			if want > 0 and inBank > 0 then fetch[#fetch + 1] = { id = e[1], n = math.min(want, inBank) } end
		end
		if #fetch > 0 then
			s.buttons[#s.buttons + 1] = { text = T("Aus Bank holen", "Fetch from bank"), main = true,
				fn = function() ns.Mail.FetchFromBank(fetch) end }
		end
	end
	-- fehlt ein Zwischenprodukt, das ich selbst herstellen kann: zuerst dieses
	for _, e in ipairs(o.r) do
		local missing = e[2] * rest - bags(e[1])
		if missing > 0 then
			local rid, rec, key = ownRecipeFor(e[1])
			if rid then
				local times = math.ceil(missing / (rec.q or 1))
				local m = math.min(times, craftable(rec.r))
				s.buttons[#s.buttons + 1] = { text = T("Erst: ", "First: ") .. K.itemText(e[1], missing), enabled = m > 0,
					fn = function() Task.Craft(nil, rid, m, key) end }
				break
			end
		end
	end
	return s
end

local function stepShip(o, ag)
	local enchant = not (o.out and o.out > 0) -- Verzauberungen lassen sich nicht verschicken
	local s = { lines = {}, buttons = {} }
	if ag then
		s.title = (enchant and T("Übergabe durch ", "Hand-over by ") or T("Versand durch ", "Shipping by ")) .. partnerName(o)
	else
		s.title = enchant and T("Mit ", "Meet and trade with ") .. o.from .. T(" treffen und handeln", "")
			or T("Ware an ", "Send goods to ") .. o.from .. T(" schicken", "")
	end
	if o.sh then
		s.state, s.chip = "done", enchant and T("übergeben", "handed over") or T("verschickt", "sent")
		if not ag then s.buttons[1] = undo(function() o.sentW, o.shAt = nil, nil; set(o, "sh", nil) end) end
		return s
	end
	if (o.cr or 0) < o.qty then
		s.state, s.chip = "idle", T("noch nicht dran", "not yet")
		addCosts(s, o, ag)
		return s
	end
	if ag then
		s.state, s.chip = "wait", T("wartet auf Versand", "waiting for shipping")
		addCosts(s, o, ag)
		return s
	end
	s.state, s.chip = "act", T("deine Aufgabe", "your task")
	if not enchant then
		local total = o.qty * (o.outq or 1)
		local done = (o.sentW or {})[o.out] or 0
		local rest = math.max(0, total - done)
		s.lines[1] = { K.itemText(o.out, total), haveText(o.out, rest) .. (done > 0 and muted(" (" .. done .. T(" verschickt", " sent") .. ")") or ""), o.out }
		s.hint = T("Geh zum Briefkasten, die Post wird vorbereitet.", "Go to a mailbox and the mail is prepared.")
	end
	addCosts(s, o, ag)
	s.buttons[1] = { tick = true, tip = enchant and T("Als übergeben abhaken", "Mark as handed over") or T("Von Hand abhaken", "Tick off manually"), main = enchant,
		fn = function() set(o, "sh", true) end }
	return s
end

local function stepReceive(o, ag)
	local s = { title = ag and T("Ware empfangen", "Receive the goods") or o.from .. T(" holt die Ware ab", " picks up the goods"),
		lines = {}, buttons = {} }
	if not o.sh then
		s.state, s.chip = "idle", T("noch nicht dran", "not yet")
		if ag then s.buttons[1] = { text = T("Schon erhalten", "Already received"), fn = function() O.ConfirmDone(o) end } end
		return s
	end
	if ag then
		s.state, s.chip = "act", (o.out and o.out > 0) and T("Post abholen", "check your mail") or T("deine Aufgabe", "your task")
		if o.out and o.out > 0 then s.lines[1] = { K.itemText(o.out, o.qty * (o.outq or 1)), muted(T("unterwegs", "on the way")), o.out } end
		-- per Post verschickt: Zeitpunkt und Restzeit
		local left = O.Transit(o)
		if o.shAt then
			s.hint = partnerName(o) .. T(" hat die Ware um ", " sent the goods at ") .. date("%H:%M", o.shAt) .. T(" Uhr abgeschickt. ", ". ")
			if left > 0 then
				s.state, s.chip = "wait", T("unterwegs ", "on the way ") .. O.Clock(left)
				s.hint = s.hint .. T("Ankunft in höchstens ", "Arrives within ") .. O.Clock(left) .. T(" Minuten.", " minutes.")
			else
				s.hint = s.hint .. green(T("Die Post sollte da sein.", "The mail should have arrived."))
				if s.lines[1] then s.lines[1][2] = green(T("angekommen", "arrived")) end
			end
		end
		addCosts(s, o, ag)
		s.buttons[1] = { text = T("Erhalten – Auftrag abschließen", "Received – close order"), main = true,
			fn = function() O.Done(o) end }
	else
		s.state, s.chip = "wait", T("wartet auf ", "waiting for ") .. o.from
		s.hint = T("Der Auftrag verschwindet, sobald der Besteller den Empfang bestätigt.", "The order disappears once the customer confirms receipt.")
		s.buttons[1] = { text = T("Auftrag abschließen", "Close order"), fn = function() O.ConfirmDone(o) end }
	end
	return s
end

-- ---------------------------------------------------------------- Fenster
local function coinCopper(f)
	local g = tonumber(f.coins[1].edit:GetText()) or 0
	local s = math.min(99, tonumber(f.coins[2].edit:GetText()) or 0)
	local c = math.min(99, tonumber(f.coins[3].edit:GetText()) or 0)
	return g * 10000 + s * 100 + c
end

local function coinsChanged(box)
	local o = curId and O.Get(curId)
	if not o or o.sh then return end
	o.mc, o.mcSet = coinCopper(box), true
	box.token = (box.token or 0) + 1
	local token = box.token
	-- erst nach einer Tipp-Pause an den Partner senden
	C_Timer.After(1, function()
		if box.token == token and O.Get(o.id) == o then O.Push(o) end
	end)
	Task.Refresh()
end

local function makeStep(parent, n)
	local COL = K.COL
	local f = K.Box(parent, COL.panel, COL.border)
	f:SetWidth(STEP_W)
	f.bar = f:CreateTexture(nil, "BORDER")
	f.bar:SetPoint("TOPLEFT", 1, -1)
	f.bar:SetPoint("BOTTOMLEFT", 1, 1)
	f.bar:SetWidth(4)
	f.num = K.FS(f, 12, COL.goldDim, "CENTER")
	f.num:SetPoint("TOPLEFT", 10, -9)
	f.num:SetWidth(16)
	f.num:SetText(n)
	f.chip = K.FS(f, 11, COL.muted, "RIGHT")
	f.chip:SetPoint("TOPRIGHT", -10, -9)
	f.chip:SetWidth(0) -- so breit wie der Text
	f.title = K.FS(f, 13, COL.text)
	f.title:SetPoint("TOPLEFT", BODY_X, -8)
	f.title:SetWidth(STEP_W - BODY_X - 146)

	f.lines = {}
	for i = 1, MAXLINES do
		local row = CreateFrame("Button", nil, f)
		row:SetSize(BODY_W, LINE_H)
		row.left = K.FS(row, 11, COL.text)
		row.left:SetPoint("LEFT", 0, 0)
		row.left:SetWidth(BODY_W - 180)
		row.right = K.FS(row, 11, COL.text, "RIGHT")
		row.right:SetPoint("RIGHT", 0, 0)
		row.right:SetWidth(175)
		row:SetScript("OnClick", function(self)
			if self.id and IsShiftKeyDown() and ns.PriceCheck then ns.PriceCheck.ShiftClick(self.id) end
		end)
		row:SetScript("OnEnter", function(self)
			if not self.id then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.id) else GameTooltip:SetHyperlink("item:" .. self.id) end
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		f.lines[i] = row
	end

	f.hint = K.FS(f, 11, COL.muted)
	f.hint:SetWidth(BODY_W)
	f.hint:SetWordWrap(true)
	f.hint:SetJustifyV("TOP")

	f.coinRow = CreateFrame("Frame", nil, f)
	f.coinRow:SetSize(BODY_W, 22)
	f.coins = {}
	local x = 0
	for i, spec in ipairs({ { 54, 6, "g", { 1, 0.82, 0.2 } }, { 32, 2, "s", { 0.78, 0.78, 0.82 } }, { 32, 2, "k", { 0.85, 0.5, 0.3 } } }) do
		local b = K.Box(f.coinRow, COL.black, COL.border)
		b:SetSize(spec[1], 22)
		b:SetPoint("LEFT", x, 0)
		local e = CreateFrame("EditBox", nil, b)
		e:SetPoint("TOPLEFT", 5, -2)
		e:SetPoint("BOTTOMRIGHT", -5, 2)
		e:SetAutoFocus(false)
		e:SetFont(STANDARD_TEXT_FONT, 12, "")
		e:SetTextColor(COL.text[1], COL.text[2], COL.text[3])
		e:SetNumeric(true)
		e:SetMaxLetters(spec[2])
		e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
		e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
		e:SetScript("OnTextChanged", function(_, user) if user then coinsChanged(f) end end)
		b.edit = e
		local l = K.FS(f.coinRow, 12, spec[4])
		l:SetPoint("LEFT", b, "RIGHT", 3, 0)
		l:SetText(spec[3])
		f.coins[i] = b
		x = x + spec[1] + 18
	end

	f.checks = {}
	for i = 1, 2 do
		local c = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
		c:SetSize(22, 22)
		c:SetScript("OnClick", function(self) if self.fn then self.fn(self:GetChecked() and true or false) end end)
		c.text = K.FS(f, 11, COL.text)
		c.text:SetPoint("LEFT", c, "RIGHT", 2, 0)
		f.checks[i] = c
	end

	f.btns = {}
	for i = 1, MAXBTNS do
		local b = K.Btn(f, "", 100, 20, function(self) if self.fn then self.fn() end end, 11)
		-- Haken-Knopf (rechts): Symbol statt Text, Erklaerung beim Ueberfahren
		b.check = b:CreateTexture(nil, "OVERLAY")
		b.check:SetSize(20, 20)
		b.check:SetPoint("CENTER")
		b.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
		b.check:Hide()
		b:SetScript("OnEnter", function(self)
			if not self.tip then return end
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:AddLine(self.tip, 1, 1, 1)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		f.btns[i] = b
	end
	return f
end

-- Schritt zeichnen, gibt die benoetigte Hoehe zurueck
local function paintStep(f, s, n)
	local COL = K.COL
	local state = s.state
	local accent = (state == "act" and COL.orange) or (state == "wait" and { 0.44, 0.70, 1 }) or (state == "done" and COL.green) or COL.border
	K.setc(f.bar, accent)
	f.num:SetText(n)
	f.chip:SetText(s.chip or "")
	f.title:SetWidth(STEP_W - BODY_X - math.ceil(f.chip:GetStringWidth()) - 22)
	f.title:SetText(s.title)
	local cc = state == "idle" and COL.muted or accent
	f.chip:SetTextColor(cc[1], cc[2], cc[3])
	f:SetAlpha(state == "idle" and 0.6 or 1)

	local y = 28
	for i = 1, MAXLINES do
		local row, ln = f.lines[i], s.lines[i]
		if ln then
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", BODY_X, -y)
			row.left:SetText(ln[1])
			row.right:SetText(ln[2] or "")
			row.id = ln[3]
			row:Show()
			y = y + LINE_H
		else
			row:Hide()
		end
	end
	if s.hint then
		f.hint:ClearAllPoints()
		f.hint:SetPoint("TOPLEFT", BODY_X, -(y + 3))
		f.hint:SetText(s.hint)
		f.hint:Show()
		y = y + 3 + math.max(12, math.ceil(f.hint:GetStringHeight())) + 2
	else
		f.hint:Hide()
	end
	if s.coins then
		f.coinRow:ClearAllPoints()
		f.coinRow:SetPoint("TOPLEFT", BODY_X, -(y + 2))
		local vals = { math.floor(s.coins / 10000), math.floor(s.coins % 10000 / 100), s.coins % 100 }
		local focus = false
		for i = 1, 3 do focus = focus or f.coins[i].edit:HasFocus() end
		-- waehrend des Tippens nichts ueberschreiben
		if not focus then
			for i = 1, 3 do f.coins[i].edit:SetText(tostring(vals[i])) end
		end
		f.coinRow:Show()
		y = y + 26
	else
		f.coinRow:Hide()
	end
	for i = 1, 2 do
		local c, spec = f.checks[i], s.checks and s.checks[i]
		if spec then
			c:ClearAllPoints()
			c:SetPoint("TOPLEFT", BODY_X - 3, -(y + 2))
			c:SetChecked(spec.checked)
			c.fn = spec.fn
			c.text:SetText(spec.text)
			c:Show()
			c.text:Show()
			y = y + 24
		else
			c:Hide()
			c.text:Hide()
		end
	end
	-- Haken und "Rueckgaengig" stehen rechts, alles andere fliesst von links
	local x, rx, limit = BODY_X, STEP_W - 10, STEP_W - 8
	for i = 1, MAXBTNS do
		local spec = s.buttons[i]
		if spec and spec.tick then limit = limit - 32
		elseif spec and spec.right then limit = limit - 90 end
	end
	for i = 1, MAXBTNS do
		local b, spec = f.btns[i], s.buttons[i]
		if spec then
			b.label:SetText(spec.text or "")
			b.tip = spec.tip
			b.check:SetShown(spec.tick and true or false)
			local w = spec.tick and 26 or math.max(80, math.ceil(b.label:GetStringWidth()) + 20)
			b:SetWidth(w)
			b.fn = spec.fn
			K.setBg(b, spec.main and K.COL.btnOn or K.COL.btn)
			K.setBorder(b, spec.main and K.COL.gold or K.COL.border)
			local on = spec.enabled ~= false
			b:SetEnabled(on)
			local c = on and K.COL.gold or K.COL.off
			b.label:SetTextColor(c[1], c[2], c[3])
			b:ClearAllPoints()
			if spec.tick or spec.right then
				b:SetPoint("TOPRIGHT", b:GetParent(), "TOPLEFT", rx, -(y + 5))
				rx = rx - w - 6
			else
				if x > BODY_X and x + w > limit then
					x = BODY_X
					y = y + 25
				end
				b:SetPoint("TOPLEFT", x, -(y + 5))
				x = x + w + 6
			end
			b:Show()
		else
			b:Hide()
		end
	end
	if s.buttons[1] then y = y + 27 end
	local h = y + 6
	f:SetHeight(h)
	return h
end

-- ---------------------------------------------------------------- Auswahlliste: alle laufenden Auftraege dieser Figur
local DROP_ROWS, DROP_ROW_H = 10, 24

local function myOrders()
	local list = {}
	for _, o in pairs(ns.db.orders or {}) do
		if o.st == "taken" and O.Role(o) then list[#list + 1] = o end
	end
	table.sort(list, function(a, b)
		local ta, tb = O.MyTurn(a) and true or false, O.MyTurn(b) and true or false
		if ta ~= tb then return ta end
		return (a.created or 0) > (b.created or 0)
	end)
	return list
end

local function renderDrop()
	local d = win.drop
	local list = myOrders()
	d.offset = math.max(0, math.min(d.offset or 0, #list - DROP_ROWS))
	for i = 1, DROP_ROWS do
		local row, o = d.rows[i], list[d.offset + i]
		row.id = o and o.id
		if o then
			local ag = O.Role(o) == "ag"
			row.left:SetText(muted("#" .. ns.Mail.Code(o.id)) .. "  " .. o.qty .. "× " .. O.Name(o))
			local who = (ag and T("bei ", "with ") or T("für ", "for ")) .. (partnerName(o) or "?")
			local state = O.MyTurn(o) and "|cffe0713a" .. T("du bist dran", "your turn") .. "|r"
				or "|cff6fb3ff" .. T("wartet", "waiting") .. "|r"
			row.right:SetText(muted(who) .. "  " .. state)
			if o.id == curId then row.bg:SetColorTexture(0.29, 0.239, 0.071, 1)
			else K.setc(row.bg, K.COL.row) end
			row:Show()
		else
			row:Hide()
		end
	end
	local n = math.max(1, math.min(DROP_ROWS, #list))
	d:SetHeight(n * DROP_ROW_H + 8 + (#list > DROP_ROWS and 14 or 0))
	d.more:SetShown(#list > DROP_ROWS)
	d.more:SetText(T("Mausrad: weitere Aufträge", "Mouse wheel: more orders") .. " (" .. #list .. ")")
end

local function buildDrop(f)
	local COL = K.COL
	local d = K.Box(f, COL.bg, COL.goldDim)
	d:SetWidth(STEP_W)
	d:SetPoint("TOPLEFT", 10, -32)
	d:SetFrameStrata("FULLSCREEN_DIALOG")
	d:EnableMouse(true)
	d:EnableMouseWheel(true)
	d:SetScript("OnMouseWheel", function(_, delta)
		d.offset = (d.offset or 0) - delta
		renderDrop()
	end)
	d.rows = {}
	for i = 1, DROP_ROWS do
		local row = CreateFrame("Button", nil, d)
		row:SetSize(STEP_W - 8, DROP_ROW_H - 2)
		row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * DROP_ROW_H)
		row.bg = row:CreateTexture(nil, "BACKGROUND")
		row.bg:SetAllPoints()
		local hl = row:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.08)
		row.left = K.FS(row, 12, COL.text)
		row.left:SetPoint("LEFT", 8, 0)
		row.left:SetWidth(STEP_W - 200)
		row.right = K.FS(row, 11, COL.muted, "RIGHT")
		row.right:SetPoint("RIGHT", -8, 0)
		row.right:SetWidth(175)
		row:SetScript("OnClick", function(self)
			d:Hide()
			if self.id then Task.Open(self.id, true) end
		end)
		d.rows[i] = row
	end
	d.more = K.FS(d, 10, COL.muted, "CENTER")
	d.more:SetPoint("BOTTOM", 0, 4)
	d.more:SetWidth(STEP_W - 20)
	d:Hide()
	return d
end

local function build()
	local COL = K.COL
	local f = K.Box(UIParent, COL.bg, COL.border)
	win = f
	f:SetSize(WIDTH, 400)
	place(f)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		-- oben verankern, damit das Fenster nach unten waechst
		local l, t = self:GetLeft(), self:GetTop()
		if l and t then
			ui().taskPos = { l, t }
			place(self)
		end
	end)
	-- bewusst nicht in UISpecialFrames: Briefkasten, Berufsfenster und Esc sollen den Auftrag nicht schliessen
	_G.CraftShareTaskFrame = f
	if ns.UI and ns.UI.UserScale then f:SetScale(ns.UI.UserScale()) end
	f:Hide()

	local t = K.FS(f, 15, COL.gold)
	t:SetPoint("TOPLEFT", 12, -10)
	t:SetText(T("Auftrag", "Order"))
	-- Auftragsnummer (steht auch im Betreff der Post)
	-- anklickbar: Auswahl aller laufenden Auftraege
	f.pick = K.Btn(f, "", 90, 20, function()
		if f.drop:IsShown() then f.drop:Hide() return end
		f.drop.offset = 0
		renderDrop()
		f.drop:Show()
	end, 11)
	f.pick:SetPoint("LEFT", t, "RIGHT", 10, 0)
	f.pick.label:ClearAllPoints()
	f.pick.label:SetPoint("LEFT", 8, 0)
	f.number = f.pick.label
	f.pick.arrow = f.pick:CreateTexture(nil, "OVERLAY")
	f.pick.arrow:SetSize(12, 12)
	f.pick.arrow:SetPoint("RIGHT", -5, -1)
	f.pick.arrow:SetTexture("Interface\\AddOns\\CraftShare\\Media\\Chevron")
	f.pick.arrow:SetVertexColor(COL.gold[1], COL.gold[2], COL.gold[3])
	f.drop = buildDrop(f)
	f:HookScript("OnHide", function() f.drop:Hide() end)
	local x = K.Btn(f, "X", 20, 20, function() forget(); f:Hide() end)
	-- Einklappen wie beim Hauptfenster: Pfeil nach oben = einklappen, nach unten = ausklappen
	f.fold = K.Btn(f, "", 20, 20, function()
		folded = not folded
		GameTooltip:Hide()
		Task.Refresh()
	end)
	f.fold:SetPoint("TOPRIGHT", -32, -8)
	f.fold.arrow = f.fold:CreateTexture(nil, "OVERLAY")
	f.fold.arrow:SetSize(14, 14)
	f.fold.arrow:SetPoint("CENTER", 0, 0)
	f.fold.arrow:SetTexture("Interface\\AddOns\\CraftShare\\Media\\Chevron")
	f.fold.arrow:SetVertexColor(COL.gold[1], COL.gold[2], COL.gold[3])
	f.fold:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine(folded and T("Auftrag ausklappen", "Expand order") or T("Bis auf die Kopfzeile einklappen", "Collapse to the header"), 1, 1, 1)
		GameTooltip:Show()
	end)
	f.fold:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f:HookScript("OnHide", function() folded = false end)
	x:SetPoint("TOPRIGHT", -8, -8)

	local head = K.Box(f, COL.panel, COL.border2)
	head:SetPoint("TOPLEFT", 10, -34)
	head:SetSize(STEP_W, 60)
	f.head = head
	head.icon = head:CreateTexture(nil, "ARTWORK")
	head.icon:SetSize(32, 32)
	head.icon:SetPoint("LEFT", 10, 0)
	head.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	local lines = {}
	for i, c in ipairs({ COL.text, COL.muted, COL.muted }) do
		local s = K.FS(head, i == 1 and 13 or 11, c)
		s:SetPoint("TOPLEFT", 52, -(i == 1 and 7 or 8 + (i - 1) * 16))
		s:SetWidth(STEP_W - 62)
		lines[i] = s
	end
	head.title, head.who, head.pay = lines[1], lines[2], lines[3]
	-- Zeitpunkt der Bestellung rechts in der Titelzeile
	head.created = K.FS(head, 11, COL.muted, "RIGHT")
	head.created:SetPoint("TOPRIGHT", -10, -9)

	f.steps = {}
	for i = 1, 5 do f.steps[i] = makeStep(f, i) end

	f.all = K.Btn(f, T("Alle Aufträge", "All orders"), 110, 22, function()
		O.OpenList()
		if CraftShareOrdersFrame then CraftShareOrdersFrame:Raise() end
	end, 11)
	f.all:SetPoint("BOTTOMLEFT", 10, 10)
	f.leave = K.Btn(f, "", 110, 22, function()
		local o = curId and O.Get(curId)
		if not o then return end
		if O.Role(o) == "ag" then O.ConfirmWithdraw(o) else O.ConfirmRelease(o) end
	end, 11)
	f.leave:SetPoint("BOTTOMRIGHT", -10, 10)
	f.whisper = K.Btn(f, T("Anflüstern", "Whisper"), 90, 22, function()
		local o = curId and O.Get(curId)
		if o then K.whisper(partnerName(o)) end
	end, 11)
	f.whisper:SetPoint("RIGHT", f.leave, "LEFT", -6, 0)
end

function Task.Refresh()
	if not win or not win:IsShown() then return end
	local o = curId and O.Get(curId)
	if not o or o.st ~= "taken" or not O.Role(o) then
		forget()
		win:Hide()
		return
	end
	local count = #myOrders()
	win.number:SetText("#" .. ns.Mail.Code(o.id) .. (count > 1 and ("  |cff9a8f7e(" .. count .. ")|r") or ""))
	win.pick:SetWidth(math.ceil(win.number:GetStringWidth()) + 30)
	if win.drop:IsShown() then renderDrop() end
	-- eingeklappt: nur die Kopfzeile
	for _, e in ipairs({ win.head, win.all, win.leave, win.whisper }) do e:SetShown(not folded) end
	if folded then win.fold.arrow:SetTexCoord(0, 1, 0, 1) else win.fold.arrow:SetTexCoord(0, 1, 1, 0) end
	if folded then
		for _, f in ipairs(win.steps) do f:Hide() end
		win:SetHeight(36)
		return
	end
	local ag = O.Role(o) == "ag"
	local head = win.head
	head.icon:SetTexture((o.out and o.out > 0) and ns.ItemIcon(o.out) or K.profIcon(o.key, o.pname))
	head.title:SetText(o.qty .. "× " .. O.Name(o))
	-- Zeitpunkt beim Besteller steht in der Auftrags-ID; sonst der Eingang beim eigenen Client
	local at = tonumber(o.id:match("%-(%d+)%-%d+$")) or o.created
	if at then
		local today = date("%d.%m.%Y") == date("%d.%m.%Y", at)
		head.created:SetText(T("Bestellt ", "Ordered ") .. (today and T("heute ", "today ") or date("%d.%m. ", at)) ..
			date("%H:%M", at))
	else
		head.created:SetText("")
	end
	head.title:SetWidth(STEP_W - 62 - math.ceil(head.created:GetStringWidth()) - 14)
	local partner = partnerName(o)
	head.who:SetText((ag and T("Du bist Auftraggeber · Hersteller: ", "You ordered · crafter: ")
		or T("Du bist Auftragnehmer · Besteller: ", "You craft · customer: ")) .. partner ..
		(ns.Roster.IsOnline(partner) and "  " .. green("online") or ""))
	local note = (o.note or "") ~= "" and (" · „" .. o.note .. "“") or ""
	head.pay:SetText((o.mats == "self" and T("Material stellt der Auftraggeber", "materials from the customer")
		or T("Material besorgt der Hersteller", "crafter gets the materials")) .. note)
	win.leave.label:SetText(ag and T("Zurückziehen", "Withdraw") or T("Zurückgeben", "Give back"))

	local steps = {}
	if o.mats == "self" then steps[#steps + 1] = stepMaterials(o, ag) end
	steps[#steps + 1] = stepCraft(o, ag)
	steps[#steps + 1] = stepShip(o, ag)
	steps[#steps + 1] = stepReceive(o, ag)

	local y = 34 + 60 + 6
	for i, f in ipairs(win.steps) do
		local s = steps[i]
		if s then
			f:ClearAllPoints()
			f:SetPoint("TOPLEFT", 10, -y)
			f:Show()
			y = y + paintStep(f, s, i) + 6
		else
			f:Hide()
		end
	end
	win:SetHeight(y + 36)
end

-- ---------------------------------------------------------------- Herstellen und Mitzaehlen
local craftOrder    -- Auftrag, fuer den zuletzt aus dem Fenster hergestellt wurde
local craftPending  -- wartet, ob die Herstellung beginnt

-- Berufsfenster unsichtbar: manche Clients stellen nur bei geoeffnetem Beruf her. Es wird fuer die Herstellung
-- verdeckt geoeffnet und danach wieder geschlossen.
local hidden        -- laufende verdeckte Sitzung: { left, recipe, started, idle, waited }
local savedScale

local function profFrame() return _G.ProfessionsFrame or _G.TradeSkillFrame end

local function conceal()
	local f = profFrame()
	if not f or not hidden then return end
	savedScale = savedScale or f:GetScale()
	f:SetAlpha(0)
	f:SetScale(0.001) -- winzig, damit das unsichtbare Fenster keine Klicks abfaengt
end

local function reveal()
	local f = profFrame()
	if f and savedScale then
		f:SetAlpha(1)
		f:SetScale(savedScale)
	end
	savedScale = nil
end

local function closeHidden()
	if not hidden then return end
	hidden = nil
	if C_TradeSkillUI.CloseTradeSkill then pcall(C_TradeSkillUI.CloseTradeSkill) end
	C_Timer.After(0.2, function() if not hidden then reveal() end end)
end

local function prepareFrame()
	if not profFrame() then
		local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
		if load then pcall(load, "Blizzard_Professions") end
	end
	local f = profFrame()
	if f and not f.csHooked then
		f.csHooked = true
		-- das Spiel setzt Groesse/Sichtbarkeit beim Anzeigen ggf. neu
		f:HookScript("OnShow", function() conceal(); C_Timer.After(0, conceal) end)
		f:HookScript("OnHide", function() hidden = nil; reveal() end)
	end
	return f
end

-- schliesst die verdeckte Sitzung, wenn nichts (mehr) hergestellt wird
local function watch(session)
	C_Timer.After(1, function()
		if hidden ~= session then return end
		if UnitCastingInfo and UnitCastingInfo("player") then
			session.started, session.idle = true, 0
		else
			session.idle = session.idle + 1
		end
		-- noch nichts begonnen: laenger offen lassen, damit ein zweiter Klick reicht
		if session.idle >= (session.started and 3 or 30) then return closeHidden() end
		watch(session)
	end)
end

-- Beruf oeffnen, ohne dass man es sieht. false: nicht moeglich
local function openHidden(key)
	local id = tonumber(key)
	if not (id and C_TradeSkillUI.OpenTradeSkill) then return false end
	local f = prepareFrame()
	if not f then return false end
	-- ein selbst geoeffnetes Fenster bleibt sichtbar
	if f:IsShown() and not hidden then
		pcall(C_TradeSkillUI.OpenTradeSkill, id)
		return true
	end
	local fresh = not hidden
	hidden = hidden or { idle = 0 }
	hidden.idle = 0
	conceal()
	pcall(C_TradeSkillUI.OpenTradeSkill, id)
	conceal()
	if fresh then watch(hidden) end
	return true
end

function Task.OpenProfession(key)
	if hidden then hidden = nil; reveal() end
	local id = tonumber(key)
	if id and C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill then
		if pcall(C_TradeSkillUI.OpenTradeSkill, id) then return end
	end
	ns.Print(T("Bitte öffne dein Berufsfenster.", "Please open your profession window."))
end

-- muss direkt aus einem Klick kommen, sonst lehnt das Spiel die Herstellung ab
function Task.Craft(order, recipeID, count, key)
	if not (C_TradeSkillUI and C_TradeSkillUI.CraftRecipe) or not count or count < 1 then return end
	if InCombatLockdown() then return end
	craftOrder = order and order.id or nil
	key = key or (order and order.key)
	local opened = openHidden(key)
	if hidden then hidden.recipe, hidden.left, hidden.started = recipeID, count, nil end
	local pending = {}
	craftPending = pending
	local ok, err = pcall(C_TradeSkillUI.CraftRecipe, recipeID, count)
	if not ok then
		craftPending = nil
		ns.Print(T("Herstellen abgelehnt: ", "Crafting refused: ") .. tostring(err))
		return
	end
	C_Timer.After(1.5, function()
		if craftPending ~= pending then return end
		craftPending = nil
		if UnitCastingInfo and UnitCastingInfo("player") then return end
		local ready = C_TradeSkillUI.IsTradeSkillReady and C_TradeSkillUI.IsTradeSkillReady()
		ns.Print(T("Die Herstellung hat nicht begonnen. Bitte noch einmal auf „Herstellen“ klicken.",
			"Crafting did not start. Please click “Craft” again.") ..
			"  [Rezept " .. tostring(recipeID) .. ", Beruf " .. tostring(key) .. ", geöffnet " .. tostring(opened) ..
			", bereit " .. tostring(ready) .. (pending.error and (", Spiel: " .. pending.error) or "") .. "]")
	end)
end

local function counts(o, recipeID)
	return o and o.st == "taken" and O.Role(o) == "an" and o.rid == recipeID and not o.sh
		and (o.cr or 0) < o.qty and (o.mats == "crafter" or o.mr or o.ms)
end

-- ein abgeschlossener Herstellungszauber zaehlt fuer den passenden Auftrag (auch aus dem Berufsfenster des Spiels)
local function crafted(recipeID)
	if not ns.db or not ns.Orders then return end
	O = ns.Orders
	local o = craftOrder and O.Get(craftOrder)
	if not counts(o, recipeID) then
		o = nil
		for _, c in pairs(ns.db.orders or {}) do
			if counts(c, recipeID) and (not o or (c.created or 0) < (o.created or 0)) then o = c end
		end
	end
	if not o then return end
	o.cr = (o.cr or 0) + 1
	if o.cr >= o.qty then
		ns.Print(T("Alles hergestellt: ", "All crafted: ") .. o.qty .. "× " .. O.Name(o))
	end
	O.Push(o)
end

local cast = CreateFrame("Frame")
for _, e in ipairs({ "UNIT_SPELLCAST_SUCCEEDED", "TRADE_SKILL_CRAFT_BEGIN", "UNIT_SPELLCAST_START", "UI_ERROR_MESSAGE" }) do
	pcall(cast.RegisterEvent, cast, e)
end
cast:SetScript("OnEvent", function(_, event, unit, message, spellID)
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		if unit == "player" and spellID then
			crafted(spellID)
			if hidden and hidden.recipe == spellID then
				hidden.left = hidden.left - 1
				if hidden.left <= 0 then
					local session = hidden
					C_Timer.After(0.3, function() if hidden == session then closeHidden() end end)
				end
			end
		end
	elseif event == "TRADE_SKILL_CRAFT_BEGIN" or (event == "UNIT_SPELLCAST_START" and unit == "player") then
		craftPending = nil
	elseif event == "UI_ERROR_MESSAGE" and craftPending then
		craftPending.error = tostring(message or unit)
	end
end)

-- Restzeit der Post laufend anzeigen (und einmal beim Ablauf)
local ticking = false
if C_Timer.NewTicker then
	C_Timer.NewTicker(1, function()
		if not (win and win:IsShown() and curId and O) then return end
		local o = O.Get(curId)
		local role = o and O.Role(o)
		local running = (role == "ag" and O.Transit(o) > 0) or (role == "an" and O.MatTransit(o) > 0) or false
		if running or ticking then Task.Refresh() end
		ticking = running
	end)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
local pending = false
ev:SetScript("OnEvent", function()
	if pending or not (win and win:IsShown()) then return end
	pending = true
	C_Timer.After(0.2, function()
		pending = false
		Task.Refresh()
	end)
end)

function Task.Open(id, keepList)
	K, O = K or ns.UIK, ns.Orders
	local o = O.Get(id)
	if not o or o.st ~= "taken" or not O.Role(o) then return end
	if not win then
		build()
		ns.UI.Dockable(win)
	end
	curId = id
	ui().openTask[ns.Me()] = id
	ui().lastTask = id
	if not keepList and CraftShareOrdersFrame then CraftShareOrdersFrame:Hide() end
	for _, f in ipairs(win.steps) do
		for i = 1, 3 do f.coins[i].edit:ClearFocus() end
	end
	win:Show()
	win:Raise()
	-- Hersteller: aktuellen Stand (inkl. vorgeschlagener Materialkosten) an den Besteller schicken
	if O.Role(o) == "an" then O.Push(o) else Task.Refresh() end
end

ns.Orders.OpenTask = Task.Open

-- aktueller Auftrag dieser Figur: der zuletzt geoeffnete, sonst der neueste (eigene Auftraege zum Herstellen zuerst)
function Task.Active()
	local orders = ns.db and ns.db.orders
	if not orders then return end
	O = ns.Orders
	local last = ui().openTask[ns.Me()] or ui().lastTask
	local o = last and orders[last]
	local lastValid = o and o.st == "taken" and O.Role(o)
	if lastValid and O.MyTurn(o) then return o.id end
	local best, bestRank
	for _, c in pairs(orders) do
		local role = c.st == "taken" and O.Role(c)
		if role then
			local rank = (O.MyTurn(c) and 1e13 or 0) + (role == "an" and 1e12 or 0) + (c.created or 0)
			if not best or rank > bestRank then best, bestRank = c.id, rank end
		end
	end
	-- niemand wartet auf mich: beim zuletzt geoeffneten bleiben
	if lastValid and not (best and O.MyTurn(orders[best])) then return o.id end
	return best
end

function Task.Toggle()
	if win and win:IsShown() then
		forget()
		win:Hide()
		return
	end
	local id = Task.Active()
	if id then
		Task.Open(id, true)
	else
		ns.Print(T("Du hast keinen angenommenen Auftrag.", "You have no accepted order."))
	end
end

-- nach Anmelden oder /reload den offenen Auftrag wieder zeigen (der volle Name steht dann fest)
local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function()
	C_Timer.After(5, function()
		local id = ns.db and ui().openTask[ns.Me()]
		if id and not (win and win:IsShown()) then Task.Open(id, true) end
	end)
end)
