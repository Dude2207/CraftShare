-- CraftShare: Post zu angenommenen Auftraegen.
-- Beim Oeffnen des Briefkastens werden offene Sendungen vorbereitet (Empfaenger, Betreff, Anhaenge, Geld);
-- auf "Senden" drueckt immer der Spieler. Gesendete und aus der Post genommene Briefe haken die Schritte ab.
-- Betreff: "CraftShare #<Kennung> <Art>: <Auftrag>", Art = Material/Teilmaterial/Geld (Besteller -> Hersteller),
-- Ware/Teilware/Rueckgabe (Hersteller -> Besteller)
local ADDON, ns = ...
local M = {}
ns.Mail = M
local T = ns.T
local K, O

local MAX_ATTACH = ATTACHMENTS_MAX_SEND or 12
local PANEL_W, ROWS, ROW_H = 260, 4, 66
local FINAL = { Material = true, Ware = true }
local TO_CRAFTER = { Material = true, Teilmaterial = true, Geld = true }

local mailOpen = false
local panel
local prepToken = 0
local preparing
local prepared      -- { id, note }
local outgoing      -- Brief, der gerade verschickt wird
local lastMoney = 0 -- zuletzt fuer den Brief gesetztes Geld
local notes = {}    -- Hinweise je Auftrag

-- kurze Kennung aus der Auftrags-ID (steht im Betreff)
function M.Code(id)
	local h = 0
	for i = 1, #id do h = (h * 31 + id:byte(i)) % 65536 end
	return string.format("%04X", h)
end

local function parseSubject(s)
	if type(s) ~= "string" then return end
	return s:match("^CraftShare #(%x%x%x%x) (%a+)")
end

local function sameName(a, b)
	if not a or not b then return false end
	a, b = ns.ShortName(a):lower(), ns.ShortName(b):lower()
	-- Spiel liefert evtl. nur den Vornamen
	return a == b or a:match("^%S+") == b or b:match("^%S+") == a
end

local function subjectFor(id, label, title)
	local s = "CraftShare #" .. M.Code(id) .. " " .. label .. ": " .. title
	if #s > 63 then
		local cut = 63
		-- nicht mitten in einem Umlaut abschneiden
		while cut > 1 and s:byte(cut + 1) and s:byte(cut + 1) >= 128 and s:byte(cut + 1) < 192 do cut = cut - 1 end
		s = s:sub(1, cut)
	end
	return s
end

-- ---------------------------------------------------------------- Taschen
local C = C_Container
-- Rucksack 0, Taschen 1-4 und ggf. der Reagenzienbeutel 5 (Herstellungsergebnisse landen oft dort).
-- Ohne Reagenzienbeutel hat Platz 5 am Briefkasten keine Faecher.
local LAST_BAG = math.max(NUM_TOTAL_EQUIPPED_BAG_SLOTS or 0, 5)

local function numSlots(bag)
	if C and C.GetContainerNumSlots then return C.GetContainerNumSlots(bag) or 0 end
	return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end

local function slotInfo(bag, slot)
	if C and C.GetContainerItemInfo then
		local i = C.GetContainerItemInfo(bag, slot)
		if i then return i.itemID, i.stackCount or 1, i.isLocked, i.isBound end
		return
	end
	if not GetContainerItemInfo then return end
	local tex, count, locked, _, _, _, _, _, _, id, bound = GetContainerItemInfo(bag, slot)
	if tex then return id, count or 1, locked, bound end
end

local function pickup(bag, slot)
	if C and C.PickupContainerItem then C.PickupContainerItem(bag, slot) else PickupContainerItem(bag, slot) end
end

local function split(bag, slot, n)
	if C and C.SplitContainerItem then C.SplitContainerItem(bag, slot, n) else SplitContainerItem(bag, slot, n) end
end

local function emptySlot(used)
	local freeFn = (C and C.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
	for bag = 0, NUM_BAG_SLOTS or 4 do
		local family = 0
		if freeFn then
			local _, f = freeFn(bag)
			family = f or 0
		end
		-- Spezialtaschen (Koecher, Berufstaschen) auslassen
		if family == 0 then
			for slot = 1, numSlots(bag) do
				if not slotInfo(bag, slot) and not used[bag .. ":" .. slot] then return bag, slot end
			end
		end
	end
end

-- alle verschickbaren Stapel eines Gegenstands, groesste zuerst; zweiter Wert: gebundene Stueckzahl
local function stacksOf(itemID)
	local list, bound = {}, 0
	for bag = 0, LAST_BAG do
		for slot = 1, numSlots(bag) do
			local id, count, locked, isBound = slotInfo(bag, slot)
			if id == itemID then
				if isBound then bound = bound + count
				elseif not locked then list[#list + 1] = { bag = bag, slot = slot, n = count } end
			end
		end
	end
	table.sort(list, function(a, b) return a.n > b.n end)
	return list, bound
end

-- ---------------------------------------------------------------- Offene Sendungen
-- noch zu verschickende Mengen: { {itemID, q}, ... }
local function remaining(o, kind)
	local out = {}
	if kind == "M" then
		local sent = o.sentM or {}
		for _, e in ipairs(O.SendList(o)) do
			local q = e[2] - (sent[e[1]] or 0)
			if q > 0 then out[#out + 1] = { e[1], q } end
		end
	else
		local q = o.qty * (o.outq or 1) - ((o.sentW or {})[o.out] or 0)
		if q > 0 then out[#out + 1] = { o.out, q } end
	end
	return out
end

-- offene Sendung eines Auftrags: Art, Gegenstaende, Geld
-- M Material (+ Geld), G nur Geld, W Ware (+ Rueckgabe), R Rueckgabe zum Auftrag
local function orderShipment(o)
	if o.st ~= "taken" then return end
	local role = O.Role(o)
	if role == "ag" then
		local owed = O.Owed(o)
		if o.mats == "self" and not o.ms and not o.mr and (o.cr or 0) == 0 and not o.sh then
			local items = remaining(o, "M")
			if #items > 0 then return "M", items, owed end
		end
		if owed > 0 then return "G", {}, owed end
	elseif role == "an" then
		local refund = O.Refund(o)
		local mailable = o.out and o.out > 0
		local made = (o.cr or 0) >= o.qty
		if mailable and made and not o.sh then
			local items = remaining(o, "W")
			if #items > 0 then return "W", items, refund end
		end
		if refund > 0 and (o.sh or (not mailable and made)) then return "R", {}, refund end
	end
end

local function availability(ship)
	local have, missing = 0, 0
	for _, e in ipairs(ship.items) do
		local n = 0
		for _, s in ipairs((stacksOf(e[1]))) do n = n + s.n end
		have = have + math.min(n, e[2])
		if n < e[2] then missing = missing + (e[2] - n) end
	end
	ship.have, ship.missing = have, missing
	ship.poor = ship.money > 0 and GetMoney and GetMoney() < ship.money or false
	if #ship.items > 0 then ship.sendable = have > 0
	else ship.sendable = ship.money > 0 and not ship.poor end
end

function M.Shipments()
	local list = {}
	O = O or ns.Orders
	for id, o in pairs(ns.db.orders or {}) do
		local kind, items, amount = orderShipment(o)
		if kind then
			list[#list + 1] = { id = id, o = o, kind = kind, items = items, money = amount or 0,
				partner = (O.Role(o) == "ag") and o.by or o.from, title = o.qty .. "x " .. O.Name(o), t = o.created or 0 }
		end
	end
	-- offene Rueckgaben (Auftrag zurueckgegeben, zurueckgezogen oder ohne Rueckzahlung abgeschlossen)
	for id, j in pairs(ns.db.returns or {}) do
		if j.owner == ns.Me() then
			local items = {}
			for _, e in ipairs(j.items) do if e[2] > 0 then items[#items + 1] = { e[1], e[2] } end end
			list[#list + 1] = { id = id, job = j, kind = "X", items = items, money = j.money or 0,
				partner = j.to, title = j.name, t = j.t or 0 }
		end
	end
	for _, ship in ipairs(list) do availability(ship) end
	table.sort(list, function(a, b)
		if a.sendable ~= b.sendable then return a.sendable end
		return a.t < b.t
	end)
	return list
end

-- ---------------------------------------------------------------- Versandfenster (Spiel oder Kerzo Postal)
local function kerzo()
	local m = _G.KPE_MarcoRedaccion
	if m and m.AbrirNuevo then return m end
end

local function openSendForm()
	local k = kerzo()
	if k then
		if pcall(k.AbrirNuevo, k) then return end
	end
	if SendMailFrame and not SendMailFrame:IsShown() and MailFrameTab2 then MailFrameTab2:Click() end
	if ClearSendMail then ClearSendMail() end
end

local function coins(copper)
	return math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
end

local function fillForm(recipient, subject, body, amount)
	local k = kerzo()
	if k and k:IsShown() and k.campoPara then
		k.campoPara.autocompletandoInterno = true
		k.campoPara:SetText(recipient)
		k.campoPara.autocompletandoInterno = false
		k.campoAsunto:SetText(subject)
		k.campoAsunto:SetCursorPosition(0)
		if k.campoCuerpo then k.campoCuerpo:SetText(body) end
		if k.radioEnviar then k.radioEnviar:Click() end
		if k.campoOro then
			local g, s, c = coins(amount)
			k.campoOro:SetText(g > 0 and tostring(g) or "")
			k.campoPlata:SetText(s > 0 and tostring(s) or "")
			k.campoCobre:SetText(c > 0 and tostring(c) or "")
		end
		if k.ValidarEnvio then k:ValidarEnvio() end
		return
	end
	if SendMailNameEditBox then SendMailNameEditBox:SetText(recipient) end
	if SendMailSubjectEditBox then
		SendMailSubjectEditBox:SetText(subject)
		SendMailSubjectEditBox:SetCursorPosition(0)
	end
	if SendMailBodyEditBox then
		SendMailBodyEditBox:SetText(body)
	elseif MailEditBox and MailEditBox.SetText then
		MailEditBox:SetText(body)
	end
	if SendMailSendMoneyButton and SendMailSendMoneyButton:IsEnabled() then SendMailSendMoneyButton:Click() end
	if SendMailMoney and MoneyInputFrame_SetCopper then MoneyInputFrame_SetCopper(SendMailMoney, amount) end
end

-- ---------------------------------------------------------------- Vorbereiten
-- wartet, bis der abgeteilte Stapel im Zielplatz liegt
local function waitFor(token, bag, slot, n, tries, done)
	if token ~= prepToken then return end
	local _, count, locked = slotInfo(bag, slot)
	if count == n and not locked then return done(true) end
	if tries <= 0 then return done(false) end
	C_Timer.After(0.1, function() waitFor(token, bag, slot, n, tries - 1, done) end)
end

function M.Prepare(ship)
	if not mailOpen or not ship then return end
	if InCombatLockdown() then return end
	if CursorHasItem and CursorHasItem() then
		ns.Print(T("Bitte zuerst den Gegenstand am Mauszeiger ablegen.", "Please drop the item on your cursor first."))
		return
	end
	prepToken = prepToken + 1
	local token = prepToken
	local id0, o, kind = ship.id, ship.o, ship.kind
	preparing, prepared = id0, nil
	notes[id0] = nil
	openSendForm()
	M.Refresh()

	-- kurz warten, bis alte Anhaenge wieder in den Taschen liegen
	C_Timer.After(0.4, function()
		if token ~= prepToken or not mailOpen then return end
		local jobs, splits, used = {}, {}, {}
		local complete, problem = true, nil
		-- Materialliste jetzt merken, nach dem Anhaengen sieht der Tascheninhalt anders aus
		local plan = (kind == "M") and O.SendList(o) or nil
		local wanted = (kind == "M" or kind == "W") and remaining(o, kind) or ship.items
		for _, e in ipairs(wanted) do
			local id, need = e[1], e[2]
			local stacks, bound = stacksOf(id)
			local rest = need
			local left = {}
			for _, s in ipairs(stacks) do
				if s.n <= rest and #jobs + #splits < MAX_ATTACH then
					jobs[#jobs + 1] = { bag = s.bag, slot = s.slot, id = id, n = s.n }
					rest = rest - s.n
				else
					left[#left + 1] = s
				end
			end
			if rest > 0 and #jobs + #splits < MAX_ATTACH then
				-- kleinsten Stapel nehmen, der reicht, und die Restmenge abteilen
				for i = #left, 1, -1 do
					if left[i].n > rest then
						splits[#splits + 1] = { bag = left[i].bag, slot = left[i].slot, id = id, n = rest }
						rest = 0
						break
					end
				end
			end
			if rest > 0 then
				complete = false
				if #jobs + #splits >= MAX_ATTACH then
					problem = T("Mehr als ein Brief nötig.", "More than one mail needed.")
				elseif bound > 0 then
					problem = T("Seelengebundenes kann nicht verschickt werden.", "Soulbound items cannot be mailed.")
				else
					problem = rest .. "× " .. (ns.ItemName(id) or id) .. T(" fehlt noch.", " still missing.")
				end
			end
		end

		local function attach()
			if token ~= prepToken or not mailOpen then return end
			local slot = 0
			for _, j in ipairs(jobs) do
				slot = slot + 1
				pickup(j.bag, j.slot)
				ClickSendMailItemButton(slot)
				if CursorHasItem and CursorHasItem() then
					ClearCursor()
					complete = false
					problem = T("Ein Gegenstand ließ sich nicht anhängen.", "An item could not be attached.")
					slot = slot - 1
				end
			end
			C_Timer.After(0.4, function()
				if token ~= prepToken or not mailOpen then return end
				preparing = nil
				if slot == 0 and (#wanted > 0 or ship.money == 0) and not (kind == "X" and ship.money > 0) then
					notes[id0] = problem or T("Nichts zum Verschicken in den Taschen.", "Nothing to send in your bags.")
					M.Refresh()
					return
				end
				local label, amount = "Rueckgabe", ship.money
				if kind == "M" then
					label = complete and "Material" or "Teilmaterial"
					if not complete then amount = 0 end -- Geld geht mit dem abschliessenden Brief
				elseif kind == "W" then
					label = complete and "Ware" or "Teilware"
					if not complete then amount = 0 end
				elseif kind == "G" then
					label = "Geld"
				end
				local body = ((kind == "X" or kind == "R") and T("Rückgabe über CraftShare: ", "Return via CraftShare: ")
					or T("Auftrag über CraftShare: ", "Order via CraftShare: ")) .. ship.title
				fillForm(ship.partner, subjectFor(id0, label, ship.title), body, amount)
				prepared = { id = id0, plan = plan, money = amount }
				notes[id0] = (not complete) and (T("Teillieferung. ", "Partial delivery. ") .. (problem or "")) or nil
				M.Refresh()
			end)
		end

		local function doSplit(i)
			if token ~= prepToken or not mailOpen then return end
			local s = splits[i]
			if not s then return attach() end
			local bag, slot = emptySlot(used)
			if not bag then
				complete = false
				problem = T("Kein freier Taschenplatz zum Abteilen.", "No free bag slot to split a stack.")
				return doSplit(i + 1)
			end
			used[bag .. ":" .. slot] = true
			split(s.bag, s.slot, s.n)
			pickup(bag, slot)
			waitFor(token, bag, slot, s.n, 30, function(ok)
				if ok then
					jobs[#jobs + 1] = { bag = bag, slot = slot, id = s.id, n = s.n }
				else
					if CursorHasItem and CursorHasItem() then ClearCursor() end
					complete = false
					problem = T("Stapel ließ sich nicht abteilen.", "Could not split a stack.")
				end
				C_Timer.After(0.1, function() doSplit(i + 1) end)
			end)
		end
		doSplit(1)
	end)
end

-- ---------------------------------------------------------------- Gesendet
local function orderFor(code, role, partner)
	for _, o in pairs(ns.db.orders or {}) do
		if o.st == "taken" and O.Role(o) == role and M.Code(o.id) == code then
			local p = (role == "ag") and o.by or o.from
			if not partner or sameName(p, partner) then return o end
		end
	end
end

local function onSendMail(recipient, subject)
	outgoing = nil
	local code, label = parseSubject(subject)
	local amount = (GetSendMailMoney and GetSendMailMoney()) or lastMoney or 0
	lastMoney = 0
	if not code or not GetSendMailItem then return end
	local items = {}
	for i = 1, MAX_ATTACH do
		local name, itemID, _, count = GetSendMailItem(i)
		if name then
			if not itemID and GetSendMailItemLink then
				local link = GetSendMailItemLink(i)
				itemID = link and tonumber(link:match("item:(%d+)"))
			end
			if itemID then items[itemID] = (items[itemID] or 0) + (count or 1) end
		end
	end
	outgoing = { code = code, label = label, to = recipient, items = items, money = amount }
end

local function returnJob(code, to)
	for id, j in pairs(ns.db.returns or {}) do
		if j.owner == ns.Me() and M.Code(id) == code and sameName(j.to, to) then return id, j end
	end
end

local function onSendSuccess()
	local out = outgoing
	outgoing = nil
	if not out or (not next(out.items) and out.money == 0) then return end
	local label, amount = out.label, out.money
	local id, o, what

	if TO_CRAFTER[label] then
		o = orderFor(out.code, "ag", out.to)
		if not o then return end
		id = o.id
		if label ~= "Geld" and next(out.items) then
			-- Liste ab jetzt festhalten
			o.plan = o.plan or (prepared and prepared.id == id and prepared.plan) or O.SendList(o)
			o.sentM = o.sentM or {}
			for item, n in pairs(out.items) do o.sentM[item] = (o.sentM[item] or 0) + n end
			if #remaining(o, "M") == 0 then o.ms = true end
			what = T("Material verschickt an ", "Materials sent to ")
		else
			what = T("Geld verschickt an ", "Money sent to ")
		end
		if amount > 0 then o.paid = (o.paid or 0) + amount end
	elseif label == "Rueckgabe" and returnJob(out.code, out.to) then
		local job
		id, job = returnJob(out.code, out.to)
		job.money = math.max(0, (job.money or 0) - amount)
		local open = job.money
		for _, e in ipairs(job.items) do
			e[2] = math.max(0, e[2] - (out.items[e[1]] or 0))
			open = open + e[2]
		end
		if open == 0 then ns.db.returns[id] = nil end
		what = T("Rückgabe verschickt an ", "Return sent to ")
	else
		o = orderFor(out.code, "an", out.to)
		if not o then return end
		id = o.id
		if (label == "Ware" or label == "Teilware") and next(out.items) then
			o.sentW = o.sentW or {}
			for item, n in pairs(out.items) do o.sentW[item] = (o.sentW[item] or 0) + n end
			if #remaining(o, "W") == 0 then o.sh = true end
			what = T("Ware verschickt an ", "Goods sent to ")
		else
			what = T("Rückgabe verschickt an ", "Return sent to ")
		end
		if amount > 0 then o.ret = (o.ret or 0) + amount end
	end

	prepared, notes[id] = nil, nil
	ns.Print(what .. (out.to or "?") .. (amount > 0 and (" (" .. ns.Prices.Money(amount) .. ")") or "") .. ".")
	if o then O.Push(o) else O.Refresh() end
	-- naechste Sendung vorbereiten
	if M.Auto() then
		C_Timer.After(1.2, function()
			if not mailOpen or preparing then return end
			for _, ship in ipairs(M.Shipments()) do
				if ship.sendable and ship.id ~= id then return M.Prepare(ship) end
			end
		end)
	end
end

-- ---------------------------------------------------------------- Empfangen
local function header(i)
	local _, _, sender, subject, amount, _, _, itemCount, _, wasReturned = GetInboxHeaderInfo(i)
	return sender, subject, itemCount or 0, wasReturned, amount or 0
end

-- Auftrag zu einem eingegangenen Brief und die Seite, an die er gerichtet ist
local function incoming(code, label, sender)
	local role = TO_CRAFTER[label] and "an" or "ag"
	return orderFor(code, role, sender), role
end

local function scanInbox()
	if not GetInboxNumItems then return end
	for i = 1, GetInboxNumItems() do
		local sender, subject, items, returned, amount = header(i)
		local code, label = parseSubject(subject)
		if code and not returned then
			local o, role = incoming(code, label, sender)
			-- die Post ist da, also wurde verschickt (falls die Nachricht dazu noch fehlt)
			if o then
				local news
				if role == "an" and label == "Material" and items > 0 and not o.ms and not o.mr then o.ms, news = true, true end
				if role == "an" and amount > 0 and not o.paid then o.paid, news = amount, true end
				if role == "ag" and label == "Ware" and items > 0 and not o.sh then o.sh, news = true, true end
				if news then O.Refresh() end
			end
		end
	end
end

local checkTokens = {}
local taking = {}   -- Auftraege, deren Post gerade entnommen wird (nur solange der Briefkasten offen ist)
local warned = {}
local function checkTaken(id)
	checkTokens[id] = (checkTokens[id] or 0) + 1
	local token = checkTokens[id]
	C_Timer.After(1.5, function()
		-- bei geschlossenem Briefkasten ist die Liste leer und sagt nichts aus
		if token ~= checkTokens[id] or not mailOpen or not taking[id] then return end
		local o = ns.db.orders and ns.db.orders[id]
		if not o or not GetInboxNumItems then return end
		local code, role = M.Code(id), O.Role(o)
		-- liegen noch Anhaenge oder Geld zu diesem Auftrag im Briefkasten?
		local itemsLeft, moneyLeft = false, false
		for i = 1, GetInboxNumItems() do
			local sender, subject, items, returned, amount = header(i)
			local c, label = parseSubject(subject)
			if c == code and not returned then
				local _, r = incoming(c, label, sender)
				if r == role then
					if items > 0 then itemsLeft = true end
					if amount > 0 then moneyLeft = true end
				end
			end
		end
		if role == "an" then
			local news
			if o.finalTaken and not itemsLeft and not o.mr then
				o.mr, news = true, true
				ns.Print(T("Material erhalten für ", "Materials received for ") .. o.qty .. "× " .. O.Name(o))
			end
			if o.moneyTaken and not moneyLeft and not o.mg then
				o.mg, news = true, true
				ns.Print(T("Geld erhalten für ", "Money received for ") .. o.qty .. "× " .. O.Name(o))
			end
			if news then O.Push(o) end
		elseif role == "ag" and o.finalTaken and not itemsLeft then
			local owed = O.Owed(o)
			if owed > 0 then
				if not warned[id] then
					warned[id] = true
					ns.Print(T("Ware erhalten, noch zu zahlen: ", "Goods received, still to pay: ") .. ns.Prices.Money(owed))
				end
			else
				ns.Print(T("Auftrag abgeschlossen: ", "Order completed: ") .. o.qty .. "× " .. O.Name(o))
				O.Done(o)
			end
		end
	end)
end

-- etwas wird aus der Post genommen (laeuft nach dem Aufruf, der Brief ist dann noch in der Liste)
local function onTake(index, what)
	if not index or not GetInboxHeaderInfo then return end
	local sender, subject, items, returned, amount = header(index)
	local code, label = parseSubject(subject)
	if not code or returned then return end
	local o, role = incoming(code, label, sender)
	if not o then return end
	if what ~= "money" and items > 0 and FINAL[label] then o.finalTaken = true end
	if what ~= "item" and amount > 0 and role == "an" then o.moneyTaken = true end
	taking[o.id] = true
	checkTaken(o.id)
end

-- ---------------------------------------------------------------- Seitenfenster am Briefkasten
function M.Auto()
	return ns.db.autoMail ~= false
end

-- Leiste neben das sichtbare Postfenster heften. Kerzo Postal blendet das Fenster des Spiels aus und nutzt
-- eigene Fenster (Verfassen, Posteingang), zwischen denen gewechselt wird.
local function dock(f)
	if f.moved then return end
	local target
	if kerzo() then
		for _, w in ipairs({ _G.KPE_MarcoRedaccion, _G.KPE_BandejaEntrada }) do
			if w and w:IsShown() then target = w break end
		end
	end
	-- rechts neben dem Fenster, wie beim Postfenster des Spiels
	local side = target and "right" or "default"
	if f.dockTarget == target and f.dockSide == side then return end
	f.dockTarget, f.dockSide = target, side
	f:ClearAllPoints()
	if target then
		f:SetPoint("TOPLEFT", target, "TOPRIGHT", 8, 0)
	elseif MailFrame and not kerzo() then
		f:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 8, 0)
	else
		f:SetPoint("LEFT", UIParent, "LEFT", 20, 60)
	end
end

local function buildPanel()
	local COL = K.COL
	local f = K.Box(UIParent, COL.bg, COL.border)
	panel = f
	f:SetSize(PANEL_W, 120)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); self.moved = true end)
	f:SetScript("OnUpdate", function(self, elapsed)
		self.wait = (self.wait or 0) + elapsed
		if self.wait < 0.2 then return end
		self.wait = 0
		dock(self)
	end)
	_G.CraftShareMailFrame = f
	if ns.UI and ns.UI.UserScale then f:SetScale(ns.UI.UserScale()) end
	f:Hide()

	local t = K.FS(f, 13, COL.gold)
	t:SetPoint("TOPLEFT", 10, -9)
	t:SetText(T("CraftShare: Sendungen", "CraftShare: shipments"))
	local x = K.Btn(f, "X", 20, 20, function() f.closed = true; f:Hide() end)
	x:SetPoint("TOPRIGHT", -6, -6)

	f.rows = {}
	for i = 1, ROWS do
		local row = K.Box(f, COL.row, COL.border2)
		row:SetSize(PANEL_W - 12, ROW_H - 4)
		row:SetPoint("TOPLEFT", 6, -32 - (i - 1) * ROW_H)
		row.who = K.FS(row, 12, COL.text)
		row.who:SetPoint("TOPLEFT", 8, -5)
		row.who:SetWidth(PANEL_W - 28)
		row.what = K.FS(row, 11, COL.muted)
		row.what:SetPoint("TOPLEFT", 8, -21)
		row.what:SetWidth(PANEL_W - 28)
		row.state = K.FS(row, 10, COL.muted)
		row.state:SetPoint("BOTTOMLEFT", 8, 7)
		row.state:SetWidth(PANEL_W - 122)
		row.state:SetWordWrap(true)
		row.state:SetHeight(24)
		row.state:SetJustifyV("BOTTOM")
		row.btn = K.Btn(row, T("Vorbereiten", "Prepare"), 86, 18, function() M.Prepare(row.ship) end, 11)
		row.btn:SetPoint("BOTTOMRIGHT", -6, 6)
		row:EnableMouse(true)
		row:SetScript("OnEnter", function(self)
			local ship = self.ship
			if not ship then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(ship.title, 1, 1, 1)
			for _, e in ipairs(ship.items) do GameTooltip:AddLine(K.itemText(e[1], e[2]), 0.9, 0.9, 0.9) end
			if ship.money > 0 then GameTooltip:AddLine(T("Geld: ", "Money: ") .. ns.Prices.Money(ship.money), 0.9, 0.9, 0.9) end
			if notes[ship.id] then GameTooltip:AddLine(notes[ship.id], 1, 0.6, 0.4, true) end
			if ship.job then GameTooltip:AddLine(T("Rechtsklick: Rückgabe verwerfen", "Right-click: discard return"), 0.6, 0.6, 0.6) end
			GameTooltip:Show()
		end)
		-- eine Rueckgabe, die anders geregelt wurde, laesst sich verwerfen
		row:SetScript("OnMouseUp", function(self, button)
			if button == "RightButton" and self.ship and self.ship.job then
				ns.db.returns[self.ship.id] = nil
				O.Refresh()
			end
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		f.rows[i] = row
	end

	f.more = K.FS(f, 11, COL.muted)
	f.chk = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	f.chk:SetSize(22, 22)
	f.chk:SetPoint("BOTTOMLEFT", 6, 4)
	f.chk:SetScript("OnClick", function(self) ns.db.autoMail = self:GetChecked() and true or false end)
	local ct = K.FS(f, 11, COL.muted)
	ct:SetPoint("LEFT", f.chk, "RIGHT", 2, 0)
	ct:SetText(T("Automatisch vorbereiten", "Prepare automatically"))
end

-- Ist ein Postfenster zu sehen? Kerzo Postal schliesst seine Fenster, ohne dass das Spiel den Briefkasten
-- als geschlossen meldet. Wurde in diesem Besuch noch keines erkannt (anderes Post-Addon), gilt "offen".
local sawWindow = false
local function windowOpen()
	local k, inbox = _G.KPE_MarcoRedaccion, _G.KPE_BandejaEntrada
	local open = (k and k:IsShown()) or (inbox and inbox:IsShown())
		or (MailFrame and MailFrame:IsShown() and MailFrame:GetAlpha() > 0)
	if open then
		sawWindow = true
		return true
	end
	return not sawWindow
end

local ticker
local function watchWindows()
	if not mailOpen or not panel then return end
	if not windowOpen() then
		if panel:IsShown() then
			panel:Hide()
			panel.byWindow = true -- spaeter wieder zeigen, wenn das Postfenster zurueckkommt
		end
	elseif panel.byWindow then
		panel.byWindow = nil
		if not panel.closed then M.Refresh() end
	end
end

function M.Refresh()
	if not mailOpen or not windowOpen() then
		if panel then
			panel:Hide()
			if mailOpen then panel.byWindow = true end
		end
		return
	end
	K, O = K or ns.UIK, ns.Orders
	local list = M.Shipments()
	if #list == 0 then
		if panel then panel:Hide() end
		return
	end
	if not panel then buildPanel() end
	if panel.closed then return end
	local shown = math.min(ROWS, #list)
	for i = 1, ROWS do
		local row, s = panel.rows[i], list[i]
		row.ship = s
		if s then
			local id = s.id
			local m = s.money > 0 and ns.Prices.Money(s.money) or nil
			local what
			if s.kind == "M" then
				what = T("Material", "Materials") .. (m and (" + " .. m) or "") .. T(" für ", " for ") .. s.title
			elseif s.kind == "G" then
				what = m .. T(" für ", " for ") .. s.title
			elseif s.kind == "W" then
				what = s.title .. (m and (" + " .. m .. T(" zurück", " back")) or "")
			else
				what = T("Rückgabe: ", "Return: ") .. (m and (m .. " ") or "") .. s.title
			end
			row.who:SetText(T("an ", "to ") .. (s.partner or "?"))
			row.what:SetText(what)
			local state
			if preparing == id then state = T("wird vorbereitet …", "preparing …")
			elseif prepared and prepared.id == id then
				state = "|cff4fd05a" .. T("vorbereitet, bitte senden", "ready, please send") .. "|r"
			elseif notes[id] then state = "|cffe8a96a" .. notes[id] .. "|r"
			elseif s.poor then state = "|cffd9544a" .. T("nicht genug Geld", "not enough money") .. "|r"
			elseif #s.items > 0 and s.have == 0 then state = "|cffd9544a" .. T("nichts in den Taschen", "nothing in your bags") .. "|r"
			elseif s.missing > 0 then state = "|cffe8a96a" .. s.missing .. T(" Teile fehlen", " items missing") .. "|r"
			else state = T("alles dabei", "all there") end
			row.state:SetText(state)
			row.btn:SetShown(s.sendable)
			K.setBorder(row, (prepared and prepared.id == id) and K.COL.gold or K.COL.border2)
			row:Show()
		else
			row:Hide()
		end
	end
	local h = 32 + shown * ROW_H
	if #list > ROWS then
		panel.more:ClearAllPoints()
		panel.more:SetPoint("TOPLEFT", 10, -h)
		panel.more:SetText("+" .. (#list - ROWS) .. T(" weitere", " more"))
		panel.more:Show()
		h = h + 16
	else
		panel.more:Hide()
	end
	panel:SetHeight(h + 30)
	panel.chk:SetChecked(M.Auto())
	panel.dockSide = nil -- neu ausrichten
	dock(panel)
	panel:Show()
end

local function onOpen()
	mailOpen = true
	prepared, preparing, outgoing = nil, nil, nil
	sawWindow = false
	if ticker then ticker:Cancel() end
	ticker = C_Timer.NewTicker and C_Timer.NewTicker(0.3, watchWindows)
	wipe(notes)
	wipe(warned)
	if panel then panel.closed = nil end
	K, O = ns.UIK, ns.Orders
	C_Timer.After(0.6, function()
		if not mailOpen then return end
		M.Refresh()
		if not M.Auto() then return end
		local ready = {}
		for _, s in ipairs(M.Shipments()) do
			if s.sendable then ready[#ready + 1] = s end
		end
		-- genau eine Sendung: sofort vorbereiten, sonst waehlt der Spieler
		if #ready == 1 then M.Prepare(ready[1]) end
	end)
end

local function onClose()
	mailOpen = false
	if ticker then ticker:Cancel(); ticker = nil end
	wipe(taking)
	prepToken = prepToken + 1
	prepared, preparing = nil, nil
	if panel then panel:Hide() end
end

-- /cs post: warum wird (k)eine Sendung angeboten?
function M.Debug()
	O = ns.Orders
	local function yn(v) return v and "ja" or "nein" end
	ns.Print("Post: Briefkasten offen " .. yn(mailOpen) .. ", automatisch " .. yn(M.Auto()) ..
		", Kerzo " .. yn(kerzo()) .. ", Leiste " .. yn(panel and panel:IsShown()) .. (panel and panel.closed and " (geschlossen)" or ""))
	local n = 0
	for _, o in pairs(ns.db.orders or {}) do
		if o.st == "taken" and O.Role(o) then
			n = n + 1
			local kind, items, amount = orderShipment(o)
			ns.Print(string.format("%s: Rolle %s, hergestellt %d/%d, mr %s, ms %s, sh %s, bezahlt %d, Sendung %s (Geld %d)",
				O.Name(o), O.Role(o), o.cr or 0, o.qty, yn(o.mr), yn(o.ms), yn(o.sh), o.paid or 0, kind or "keine", amount or 0))
			items = items or { { o.out or 0, o.qty * (o.outq or 1) } }
			for _, e in ipairs(items) do
				local stacks, bound = stacksOf(e[1])
				local free = 0
				for _, s in ipairs(stacks) do free = free + s.n end
				ns.Print("   Item " .. e[1] .. " benoetigt " .. e[2] .. ", versendbar " .. free .. ", gebunden " .. bound ..
					", Bestand " .. ns.ItemCount(e[1]))
				local where = {}
				for bag = -2, 12 do
					for slot = 1, numSlots(bag) do
						local id, count, locked, isBound = slotInfo(bag, slot)
						if id == e[1] then
							where[#where + 1] = "Beutel " .. bag .. "/" .. slot .. ": " .. count ..
								(locked and " gesperrt" or "") .. (isBound and " gebunden" or "")
						end
					end
				end
				ns.Print("   Fundorte: " .. (#where > 0 and table.concat(where, ", ") or "keine"))
			end
		end
	end
	if n == 0 then ns.Print("   kein angenommener Auftrag fuer " .. ns.Me()) end
end

local pending = false
local ev = CreateFrame("Frame")
for _, e in ipairs({ "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE", "MAIL_SEND_SUCCESS", "MAIL_FAILED", "BAG_UPDATE_DELAYED" }) do
	pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event)
	if not ns.db or not ns.Orders then return end
	O = ns.Orders
	if event == "MAIL_SHOW" then onOpen()
	elseif event == "MAIL_CLOSED" then onClose()
	elseif event == "MAIL_INBOX_UPDATE" then
		scanInbox()
		for id in pairs(taking) do checkTaken(id) end
	elseif event == "MAIL_SEND_SUCCESS" then onSendSuccess()
	elseif event == "MAIL_FAILED" then outgoing = nil
	elseif mailOpen and not pending and not preparing then
		pending = true
		C_Timer.After(0.3, function()
			pending = false
			M.Refresh()
		end)
	end
end)

if hooksecurefunc then
	if SendMail then hooksecurefunc("SendMail", onSendMail) end
	if SetSendMailMoney then hooksecurefunc("SetSendMailMoney", function(c) lastMoney = c or 0 end) end
	if TakeInboxItem then hooksecurefunc("TakeInboxItem", function(i) onTake(i, "item") end) end
	if TakeInboxMoney then hooksecurefunc("TakeInboxMoney", function(i) onTake(i, "money") end) end
	if AutoLootMailItem then hooksecurefunc("AutoLootMailItem", function(i) onTake(i, "all") end) end
end
