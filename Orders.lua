-- CraftShare: Bestellungen. Protokoll (Felder durch "|", Absender kommt vom Addon-Kanal):
--   O|id|to|key|pname|rid|out|outq|qty|mats|tip|note|reag   neue Bestellung (to = "*" = alle im Beruf, sonst Spielername)
--   A|id        Hersteller moechte annehmen (an den Besteller, per Fluestern)
--   T|id|by     Besteller bestaetigt: Auftrag gehoert <by> (an den Hersteller und, bei "*", an alle)
--   N|id|by     Besteller lehnt ab: schon vergeben an <by>
--   W|id        Bestellung zurueckgezogen
--   C|id        Hersteller bricht ab (lehnt die Bestellung ab); bei Direktbestellungen ist sie damit beendet
--   D|id        Auftrag erledigt (Hersteller -> Besteller, Besteller -> alle)
--   M|id|ms|msAt  Stand des Bestellers: Material verschickt (0/1), Zeitpunkt des Postversands (Serverzeit)
--   H|id|mr|cr|sh|0|mc|0|0|shAt   Stand des Herstellers: Material erhalten, Anzahl hergestellt, Ware verschickt,
--               Materialkosten in Kupfer, Zeitpunkt des Postversands (Serverzeit); die Nullen sind unbenutzt
-- Stellt der Besteller das Material, geht der Auftrag nur an eine bestimmte Person und gilt als angenommen. Er wird
-- aber erst gesendet, wenn das Material verschickt ist (bis dahin o.hold).
-- Besorgt der Hersteller das Material, sollen die Kosten per Nachnahme bezahlt werden (derzeit abgeschaltet).
-- M und H enthalten immer den ganzen eigenen Stand und koennen beliebig oft wiederholt werden (Nachreichen
-- nach Offline-Zeiten). Jede Seite schreibt nur ihre eigenen Felder.
-- Der Besteller entscheidet allein ueber die Vergabe: wer zuerst annimmt, bekommt den Auftrag.
local ADDON, ns = ...
local O = {}
ns.Orders = O
local T = ns.T
-- Nachnahme ist im Spiel derzeit deaktiviert. Sobald sie wieder geht: auf true setzen.
O.COD_ENABLED = false
O.KINDS = { O = true, A = true, T = true, N = true, W = true, D = true, R = true, U = true, M = true, H = true, C = true }

local seq = 0
local K
local winOrder, winList, toast
local R = { qty = 1, to = "person", mats = "self" }
local openTab = "in"
local onlyCraft = false
local MAX_AGE = 7 * 86400
local MAX_AGE_TAKEN = 30 * 86400

local function db()
	ns.db.orders = ns.db.orders or {}
	return ns.db.orders
end

local function me() return ns.Me() end
-- Nachricht an eine Person: direkt, oder ueber die Gilde als Bote, wenn sie offline ist
local function deliver(name, msg) ns.Relay.Send(name, msg) end
local sendOrder, wantsOrder -- weiter unten definiert, schon von O.Resync gebraucht

local function changed()
	if ns.Mini and ns.Mini.Update then ns.Mini.Update() end
	if ns.UI and ns.UI.Dirty then ns.UI.Dirty() end
	if O.Refresh then O.Refresh() end
end

-- ---------------------------------------------------------------- Auftragsstand
local function clearProgress(o)
	o.ms, o.mr, o.cr, o.sh, o.mc, o.mcSet = nil, nil, nil, nil, nil, nil
	-- Post: festgehaltene Materialliste, schon verschickte Mengen, abschliessender Brief entnommen
	o.plan, o.sentM, o.sentW, o.finalTaken = nil, nil, nil, nil
	o.mcPrev, o.mcPrevSet, o.shAt, o.arrived, o.ack = nil, nil, nil, nil, nil
	o.msAt, o.matArrived = nil, nil
end

-- Material kommt vom Besteller und der Auftrag ging an eine bestimmte Person
local function isDirect(o)
	return o.mats == "self" and o.to ~= "*"
end

-- Post mit Anhang braucht im Spiel bis zu einer Stunde
local TRANSIT = 3600

function O.Now()
	return (GetServerTime and GetServerTime()) or time()
end

-- Sekunden, bis die per Post verschickte Ware da ist; 0, wenn nichts (mehr) unterwegs ist
local function remainingTransit(sentAt, partner)
	-- zwischen eigenen Charakteren kommt Post sofort an
	if not sentAt or ns.IsMine(partner) then return 0 end
	return math.max(0, math.min(TRANSIT, sentAt + TRANSIT - O.Now()))
end

function O.Transit(o)
	if not o.sh or o.arrived then return 0 end
	return remainingTransit(o.shAt, o.from == ns.Me() and o.by or o.from)
end

-- dasselbe fuer das Material auf dem Weg zum Hersteller
function O.MatTransit(o)
	if not o.ms or o.mr or o.matArrived then return 0 end
	return remainingTransit(o.msAt, o.from == ns.Me() and o.by or o.from)
end

function O.Clock(sec)
	return string.format("%d:%02d", math.floor(sec / 60), math.floor(sec % 60))
end

-- Was der Besteller schickt: Rohstoffe; ein schon fertiges Zwischenprodukt in den Taschen ersetzt seine Rohstoffe.
-- Nach dem ersten Brief bleibt die Liste fest (o.plan).
function O.SendList(o)
	if o.plan then return o.plan end
	local out, idx = {}, {}
	local function add(id, q)
		if idx[id] then out[idx[id]][2] = out[idx[id]][2] + q
		else
			out[#out + 1] = { id, q }
			idx[id] = #out
		end
	end
	for _, e in ipairs(o.r) do
		local need = e[2] * o.qty
		local raw = K.RawFresh({ r = { { e[1], need } }, out = 0 })
		local isRaw = #raw == 1 and raw[1][1] == e[1]
		if isRaw or ns.ItemCount(e[1]) >= need then
			add(e[1], need)
		else
			for _, x in ipairs(raw) do add(x[1], x[2]) end
		end
	end
	return out
end

-- "ag" (Besteller), "an" (Hersteller dieses Auftrags) oder nil
function O.Role(o)
	if o.from == me() then return "ag" end
	if o.by == me() and not o.hold then return "an" end
end

local function partnerOf(o)
	if o.from == me() then return o.by end
	return o.from
end

-- abgeschlossene/zurueckgezogene Auftraege merken, damit ein offline gewesener Partner es noch erfaehrt
local function remember(id, kind, partner)
	if not partner or ns.IsMine(partner) then return end
	ns.db.ordersGone = ns.db.ordersGone or {}
	ns.db.ordersGone[id] = { k = kind, p = partner, mine = me(), t = time() }
end

local function bit01(v) return v and "1" or "0" end

local function stateMessage(o)
	if O.Role(o) == "ag" then return "M|" .. o.id .. "|" .. bit01(o.ms) .. "|" .. (o.msAt or "") end
	return table.concat({ "H", o.id, bit01(o.mr), o.cr or 0, bit01(o.sh), 0, o.mc or "", 0, 0, o.shAt or "" }, "|")
end

-- eigenen Stand an den Partner schicken und anzeigen
function O.Push(o)
	-- Materialkosten stehen fest, sobald verschickt wurde
	if O.Role(o) == "an" and o.mats == "crafter" and not o.sh and not o.mcSet then
		o.mc = O.SuggestMatCost(o)
	end
	-- zurueckgehaltener Auftrag: Material ist raus, jetzt erst senden
	if o.hold and o.ms then
		o.hold = nil
		if not ns.IsMine(o.to) then O.SendAgain(o) end
		ns.Print(string.format(T("Auftrag an %s gesendet.", "Order sent to %s."), o.to))
	end
	if o.st == "taken" and O.Role(o) and not o.hold then deliver(partnerOf(o), stateMessage(o)) end
	changed()
end

-- Partner ist (wieder) da: alles nachreichen, was ihn betrifft
local synced = {}
function O.Resync(name)
	local now = GetTime()
	if synced[name] and now - synced[name] < 30 then return end
	synced[name] = now
	for _, o in pairs(db()) do
		if o.st == "pending" and o.waiting and o.from == name then deliver(name, "A|" .. o.id) end
		-- offene Bestellungen, die die Person verpasst hat (sie war beim Bestellen offline)
		if wantsOrder(o, name) then sendOrder(o, name) end
		if o.st == "taken" and not o.hold and O.Role(o) and partnerOf(o) == name then
			-- Direktauftrag, den der Hersteller noch nicht bestaetigt hat: noch einmal schicken
			if O.Role(o) == "ag" and isDirect(o) and not o.ack then O.SendAgain(o) end
			deliver(name, stateMessage(o))
		end
	end
	for id, g in pairs(ns.db.ordersGone or {}) do
		if g.p == name and g.mine == me() then deliver(name, g.k .. "|" .. id) end
	end
end

-- Materialkosten laut Preisdaten (alle direkten Zutaten, vorhandene nicht abgezogen): Kupfer, Anzahl ohne Preis
function O.SuggestMatCost(o)
	K.RawFresh({ r = o.r, out = 0 }) -- baut die Herstellungskette fuer die Preise auf
	ns.Prices.Begin()
	local total, unknown = 0, 0
	for _, e in ipairs(o.r) do
		local u = ns.Prices.Unit(e[1])
		if u then total = total + u.unit * e[2] * o.qty else unknown = unknown + 1 end
	end
	return math.floor(total + 0.5), unknown
end

-- Betrag fuer die Nachnahme: Materialkosten, falls der Hersteller das Material besorgt.
-- Zweiter Wert false: die Kosten stehen noch nicht fest.
function O.CodAmount(o)
	if o.mats ~= "crafter" then return 0, true end
	local mc = o.mc
	if not mc and O.Role(o) == "an" then mc = O.SuggestMatCost(o) end
	return mc or 0, mc ~= nil
end

-- Gibt der Hersteller (eigene Figur) einen Auftrag auf, fuer den er Material bekommen hat, bleibt eine
-- Rueckgabe offen, die am Briefkasten vorbereitet wird.
function O.QueueReturn(o, reason)
	if reason ~= "back" or not (o.by and ns.IsMine(o.by)) or o.from == o.by or not (o.ms or o.mr) then return end
	local items = {}
	if (o.cr or 0) == 0 then
		for _, e in ipairs(O.SendList(o)) do items[#items + 1] = { e[1], e[2] } end
	else
		for _, e in ipairs(o.r) do
			local q = e[2] * (o.qty - o.cr)
			if q > 0 then items[#items + 1] = { e[1], q } end
		end
	end
	if #items == 0 then return end
	ns.db.returns = ns.db.returns or {}
	ns.db.returns[o.id] = { id = o.id, owner = o.by, to = o.from, name = o.qty .. "x " .. O.Name(o),
		items = items, t = time() }
	if o.by == me() then
		ns.Print(string.format(T("Bitte das Material an %s zurückschicken (wird am Briefkasten vorbereitet).",
			"Please send the materials back to %s (prepared at the mailbox)."), o.from))
	end
end

function O.StageText(o)
	if o.sh then
		local left = O.Transit(o)
		if left > 0 then return T("Ware unterwegs, noch ", "goods on the way, ") .. math.ceil(left / 60) .. T(" Min.", " min") end
		return T("Ware verschickt", "goods sent")
	end
	if (o.cr or 0) >= o.qty then return T("hergestellt", "crafted") end
	if (o.cr or 0) > 0 then return o.cr .. T(" von ", " of ") .. o.qty .. T(" hergestellt", " crafted") end
	if o.mats == "self" then
		if o.hold then return T("noch nicht gesendet: erst Material verschicken", "not sent yet: mail the materials first") end
		if o.mr then return T("Material angekommen", "materials arrived") end
		local left = O.MatTransit(o)
		if left > 0 then return T("Material unterwegs, noch ", "materials on the way, ") .. math.ceil(left / 60) .. T(" Min.", " min") end
		if o.ms then return T("Material unterwegs", "materials on the way") end
		return T("wartet auf Material", "waiting for materials")
	end
	return T("noch nicht hergestellt", "not crafted yet")
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

-- "in" Eingang, "mine" von mir angenommene Auftraege, "out" meine Bestellungen
function O.List(dir)
	local out = {}
	for _, o in pairs(db()) do
		local accepted = o.st == "taken" and o.by == me() and not o.hold
		if o.from == me() then
			if dir == "out" then out[#out + 1] = o end
		elseif accepted then
			if dir == "mine" then out[#out + 1] = o end
		elseif dir == "in" and not o.dismissed and not o.hold and O.HasProfession(o.key)
			and (o.to == "*" or ns.ShortName(o.to) == me()) then
			-- (die Liste liegt im Account-weiten Speicher: Direkt-Bestellungen an andere Charaktere gehoeren nicht hierher)
			out[#out + 1] = o
		end
	end
	table.sort(out, function(a, b) return (a.created or 0) > (b.created or 0) end)
	return out
end

-- offene Auftraege fuer mich: Anzahl insgesamt und davon noch nicht im Eingang gesehen
function O.IncomingOpen()
	local n, unseen = 0, 0
	for _, o in pairs(db()) do
		if o.from ~= me() and not o.dismissed and o.st == "open" and O.HasProfession(o.key)
			and (o.to == "*" or ns.ShortName(o.to) == me()) then
			n = n + 1
			if not (o.seen and o.seen[me()]) then unseen = unseen + 1 end
		end
	end
	return n, unseen
end

-- Bin ich bei diesem angenommenen Auftrag am Zug?
function O.MyTurn(o)
	if O.Role(o) == "ag" then
		if o.sh then return O.Transit(o) == 0 end -- Ware abholen, sobald sie da ist
		return o.mats == "self" and not o.ms and not o.mr and (o.cr or 0) == 0 -- Material schicken
	end
	if o.sh then return false end
	if (o.cr or 0) >= o.qty then return true end -- Ware verschicken
	if o.mats == "self" and O.MatTransit(o) > 0 then return false end -- Material noch unterwegs
	return o.mats == "crafter" or o.mr or o.ms or false -- Material holen bzw. herstellen
end

-- angenommene, noch nicht abgeschlossene Auftraege dieser Figur: Anzahl und davon "ich bin dran"
function O.ActiveCount()
	local n, mine = 0, 0
	for _, o in pairs(db()) do
		if o.st == "taken" and O.Role(o) then
			n = n + 1
			if O.MyTurn(o) then mine = mine + 1 end
		end
	end
	return n, mine
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

-- target: nur an diese Person (Nachreichen), sonst an den Empfaenger bzw. alle
sendOrder = function(o, target)
	local msg = encode(o)
	if target then deliver(target, msg)
	elseif o.to == "*" then
		ns.Comm.Broadcast(msg)
		ns.Relay.Store("*", msg)
	else deliver(o.to, msg) end
end

-- Kann diese Person meinen offenen Auftrag bekommen? (Beruf laut gespeicherten Daten, unbekannt = ja)
wantsOrder = function(o, name)
	if o.from ~= ns.Me() or o.st ~= "open" or o.hold or ns.IsMine(name) then return false end
	if o.declined and o.declined[name] then return false end -- hat schon abgelehnt
	if o.to ~= "*" then return ns.ShortName(o.to) == name end
	local c = ns.db.chars[name]
	return not c or next(c.profs) == nil or c.profs[o.key] ~= nil
end

function O.SendAgain(o) sendOrder(o) end

-- Auftrag als Datenzeile im Brieftext ("|" ist dort ein Steuerzeichen, deshalb "^")
function O.MailData(o)
	local msg = encode(o):gsub("%^", " "):gsub("|", "^")
	return "[CSD:" .. msg .. "]"
end

-- Der Auftrag steckt in der Materialpost: anlegen, falls er noch nicht angekommen ist
function O.FromMail(text, sender)
	local data = type(text) == "string" and text:match("%[CSD:(.-)%]%s*$")
	if not data then return end
	local msg = data:gsub("%^", "|")
	local kind, id = strsplit("|", msg)
	if kind ~= "O" or not id then return end
	if not db()[id] then O.OnMessage("O", msg, sender) end
	local o = db()[id]
	if o and o.st == "taken" and O.Role(o) == "an" and not o.mr then
		o.ms, o.matArrived = true, true -- der Brief liegt im Briefkasten
		changed()
	end
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
		tip = 0, note = spec.note or "", r = r, st = "open", created = time(),
	}
	-- mit Material an eine bestimmte Person: gilt sofort als angenommen
	if isDirect(o) then o.st, o.by, o.hold = "taken", o.to, true end
	db()[id] = o
	if not o.hold then sendOrder(o) end
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
		o.released = nil
		clearProgress(o)
		changed()
		if O.OpenTask then O.OpenTask(o.id, true) end
		return
	end
	o.st = "pending"
	o.released, o.takenBack = nil, nil
	-- ist der Besteller offline, bleibt die Annahme vorgemerkt (Gildenbote bzw. beim naechsten Treffen)
	o.waiting = ns.Relay.IsOffline(o.from) or nil
	deliver(o.from, "A|" .. o.id)
	if o.waiting then
		ns.Print(string.format(T("%s ist offline. Deine Annahme wird zugestellt, sobald möglich.",
			"%s is offline. Your acceptance is delivered as soon as possible."), o.from))
	end
	C_Timer.After(45, function()
		if o.st == "pending" and not o.waiting then
			o.st = "open"
			ns.Print(T("Keine Antwort von ", "No answer from ") .. o.from .. T(" – Auftrag wieder offen.", " – order is open again."))
			changed()
		end
	end)
	changed()
end

-- Hersteller lehnt eine Bestellung ab: verschwindet bei ihm, der Besteller sieht sie als abgebrochen
function O.Decline(o)
	if ns.History then ns.History.Add(o, "declined", { crafter = true }) end
	o.dismissed = true
	if ns.IsMine(o.from) then
		-- gleicher Account, gleiche Daten
		if o.to == "*" then
			o.declined = o.declined or {}
			o.declined[me()] = true
		else
			o.st, o.declinedBy = "declined", me()
		end
	else
		remember(o.id, "C", o.from)
		deliver(o.from, "C|" .. o.id)
	end
	changed()
end

-- vorgemerkte Annahme zuruecknehmen
function O.Unaccept(o)
	if o.st ~= "pending" then return end
	o.st, o.waiting = "open", nil
	o.takenBack = true -- kommt doch noch ein Zuschlag, wird er zurueckgegeben
	ns.Relay.Cancel(o.from, "A", o.id)
	deliver(o.from, "R|" .. o.id)
	changed()
end

-- abgebrochene Bestellung beim Besteller entfernen
function O.Remove(o)
	db()[o.id] = nil
	changed()
end

function O.Withdraw(o)
	if ns.History then ns.History.Add(o, "withdrawn") end
	if not o.hold then ns.Relay.Cancel(o.to, "O", o.id) end
	-- noch nicht gesendet: einfach verwerfen
	if o.hold then
		db()[o.id] = nil
		changed()
		return
	end
	if o.st == "taken" then
		remember(o.id, "W", o.by)
		O.QueueReturn(o, "back")
	end
	db()[o.id] = nil
	local msg = "W|" .. o.id
	if o.to == "*" then ns.Comm.Broadcast(msg) else deliver(o.to, msg) end
	changed()
end

-- Hersteller gibt einen angenommenen Auftrag zurueck: er wird fuer alle wieder offen und erscheint wieder im Eingang.
function O.Release(o)
	if o.from == me() or o.by ~= me() then return end
	if ns.History then ns.History.Add(o, "released") end
	if not ns.IsMine(o.from) then deliver(o.from, "R|" .. o.id) end
	O.QueueReturn(o, "back")
	if isDirect(o) then
		-- der Besteller hat ihn nur an mich gerichtet: er wird nicht wieder angeboten
		remember(o.id, "R", o.from)
		db()[o.id] = nil
		changed()
		return
	end
	o.st = "open"
	o.by = nil
	o.released = true
	clearProgress(o)
	changed()
end

function O.Done(o)
	if ns.History then ns.History.Add(o, "done") end
	if o.st == "taken" then
		remember(o.id, "D", partnerOf(o))
		O.QueueReturn(o, "done")
	end
	db()[o.id] = nil
	local msg = "D|" .. o.id
	if o.from == me() then
		if o.to == "*" then ns.Comm.Broadcast(msg) elseif o.by then deliver(o.by, msg) end
	else
		deliver(o.from, msg)
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
		toast:SetFrameStrata("FULLSCREEN_DIALOG") -- Hinweis immer ueber den Fenstern
		toast.title = U.FS(toast, 11, U.COL.goldDim)
		toast.title:SetPoint("TOPLEFT", 12, -7)
		toast.title:SetText("Guild CraftShare")
		toast.text = U.FS(toast, 12, U.COL.gold)
		toast.text:SetPoint("TOPLEFT", 12, -22)
		toast.text:SetWidth(356)
		toast:SetScript("OnClick", function(self) self:Hide(); O.OpenList(O.IncomingOpen() > 0 and "in" or nil) end)
		toast:Hide()
	end
	-- Breite nach dem Text, sehr lange Meldungen umbrechen
	toast.text:SetWidth(0)
	toast.text:SetWordWrap(false)
	toast.text:SetText(text)
	local w = math.ceil(toast.text:GetStringWidth())
	local width = math.max(260, math.min(600, w + 26))
	toast.text:SetWidth(width - 24)
	toast.text:SetWordWrap(true)
	toast.text:SetText(text)
	toast:SetSize(width, 30 + math.ceil(toast.text:GetStringHeight()))
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
		local gone = ns.db.ordersGone and ns.db.ordersGone[id]
		if gone then
			-- schon erledigt oder abgelehnt, der Besteller weiss es noch nicht
			if gone.p == name and gone.mine == me() then deliver(sender, gone.k .. "|" .. id) end
			return
		end
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
		if isDirect(o) then
			o.st, o.by = "taken", me()
			O.Notify(string.format(T("Auftrag mit Material von %s: %d× %s", "Order with materials from %s: %d× %s"), name, qty, O.Name(o)))
			O.Push(o) -- Empfang bestaetigen
		else
			O.Notify(string.format(T("Neuer Auftrag von %s: %d× %s", "New order from %s: %d× %s"), name, qty, O.Name(o)))
			changed()
		end
		if ns.Mini and ns.Mini.Alert then ns.Mini.Alert() end
		return
	end

	local o = db()[id]
	if not o then
		-- Der Partner hat den Abschluss verpasst
		local g = ns.db.ordersGone and ns.db.ordersGone[id]
		if (kind == "M" or kind == "H") and g and g.p == name and g.mine == me() then
			deliver(sender, g.k .. "|" .. id)
		end
		return
	end

	if kind == "M" then
		if o.from ~= name then return end
		if o.released then
			-- ich hatte den Auftrag zurueckgegeben, das kam nicht an
			deliver(sender, "R|" .. id)
			return
		end
		-- der Besteller fuehrt mich als Hersteller (die Bestaetigung ging verloren)
		if o.st ~= "taken" then
			if o.to ~= "*" and ns.ShortName(o.to) ~= me() then return end
			o.st, o.by = "taken", me()
		end
		if o.by ~= me() then return end
		local ms = (f[3] == "1") or nil
		local msAt = ms and tonumber(f[4]) or nil
		if msAt then msAt = math.min(O.Now(), math.floor(msAt)) end
		if not ms then o.matArrived = nil end
		o.msAt = msAt
		if ms and not o.ms and not o.mr then
			O.Notify(string.format(T("%s hat das Material verschickt: %d× %s", "%s sent the materials: %d× %s"), name, o.qty, O.Name(o)))
		end
		o.ms = ms
		changed()
		return
	elseif kind == "H" then
		if o.from ~= me() or o.st ~= "taken" or o.by ~= name then return end
		local mr, sh = (f[3] == "1") or nil, (f[5] == "1") or nil
		local cr = math.max(0, math.min(o.qty, math.floor(tonumber(f[4]) or 0)))
		local mc = tonumber(f[7])
		if mc then mc = math.max(0, math.min(999999999, math.floor(mc))) end
		local shAt = sh and tonumber(f[10]) or nil
		if shAt then shAt = math.min(O.Now(), math.floor(shAt)) end
		if not sh then o.arrived = nil end
		o.shAt, o.ack = shAt, true
		local note
		if sh and not o.sh then note = T("%s hat die Ware verschickt: %d× %s", "%s sent the goods: %d× %s")
		elseif cr >= o.qty and (o.cr or 0) < o.qty then note = T("%s hat alles hergestellt: %d× %s", "%s crafted everything: %d× %s")
		elseif mr and not o.mr then note = T("%s hat das Material erhalten: %d× %s", "%s received the materials: %d× %s") end
		o.mr, o.cr, o.sh, o.mc = mr, cr, sh, mc
		if note then O.Notify(string.format(note, name, o.qty, O.Name(o))) end
		changed()
		return
	end

	if kind == "A" then
		-- Besteller entscheidet: wer zuerst kommt
		if o.from ~= me() then return end
		if o.st == "taken" and o.by == name then
			deliver(sender, "T|" .. id .. "|" .. name)
		elseif o.st == "open" and (o.to == "*" or ns.ShortName(o.to) == name) then
			o.st = "taken"
			o.by = name
			clearProgress(o)
			if o.to == "*" then ns.Relay.Cancel("*", "O", id) end
			deliver(sender, "T|" .. id .. "|" .. name)
			if o.to == "*" then ns.Comm.Broadcast("T|" .. id .. "|" .. name) end
			O.Notify(string.format(T("%s hat deinen Auftrag angenommen: %d× %s", "%s accepted your order: %d× %s"), name, o.qty, O.Name(o)))
		else
			deliver(sender, "N|" .. id .. "|" .. (o.by or "?"))
		end
	elseif kind == "T" then
		if name ~= o.from or not f[3] then return end
		o.waiting = nil
		if o.takenBack and ns.ShortName(f[3]) == me() then
			deliver(sender, "R|" .. id)
			return
		end
		local mine = o.st == "pending" and ns.ShortName(f[3]) == me()
		if o.st ~= "taken" or o.by ~= ns.ShortName(f[3]) then clearProgress(o) end
		o.st = "taken"
		o.by = ns.ShortName(f[3])
		changed()
		-- meine Annahme wurde bestaetigt: Auftrag gleich zeigen
		if mine and O.OpenTask then O.OpenTask(o.id, true) end
	elseif kind == "N" then
		if name ~= o.from or not f[3] then return end
		o.waiting = nil
		if o.st == "pending" then
			o.st = "taken"
			o.by = ns.ShortName(f[3])
			ns.Print(string.format(T("Der Auftrag von %s ist schon an %s vergeben.", "%s's order is already taken by %s."), o.from, o.by))
			changed()
		end
	elseif kind == "C" then
		-- ein Hersteller bricht ab
		if o.from ~= me() then return end
		if o.to == "*" then
			if o.st ~= "open" then return end
			o.declined = o.declined or {}
			if o.declined[name] then return end
			o.declined[name] = true
			O.Notify(string.format(T("%s lehnt ab: %d× %s", "%s declined: %d× %s"), name, o.qty, O.Name(o)))
		else
			if ns.ShortName(o.to) ~= name or o.st == "declined" then return end
			if o.st == "taken" then return end -- schon angenommen: dafuer gibt es "Zurueckgeben"
			if ns.History then ns.History.Add(o, "declined", { partner = name }) end
			o.st, o.declinedBy = "declined", name
			O.Notify(string.format(T("%s hat den Auftrag abgebrochen: %d× %s", "%s cancelled the order: %d× %s"), name, o.qty, O.Name(o)))
		end
		changed()
	elseif kind == "W" then
		if name ~= o.from then return end
		if o.st == "taken" then
			if ns.History then ns.History.Add(o, "withdrawn") end
			O.QueueReturn(o, "back")
		end
		db()[id] = nil
		changed()
	elseif kind == "R" then
		-- Besteller: der Hersteller gibt den Auftrag zurueck, dann ist er fuer alle wieder offen
		if o.from ~= me() or o.st ~= "taken" or o.by ~= name then return end
		if ns.History then ns.History.Add(o, "released") end
		if isDirect(o) then
			db()[id] = nil
			O.Notify(string.format(T("%s lehnt ab, das Material kommt zurück: %d× %s", "%s declined, the materials come back: %d× %s"), name, o.qty, O.Name(o)))
			changed()
			return
		end
		o.st = "open"
		o.by = nil
		clearProgress(o)
		local msg = "U|" .. id
		if o.to == "*" then ns.Comm.Broadcast(msg) else deliver(o.to, msg) end
		O.Notify(string.format(T("%s hat den Auftrag zurückgegeben: %d× %s", "%s gave the order back: %d× %s"), name, o.qty, O.Name(o)))
		changed()
	elseif kind == "U" then
		-- wieder offen (vom Besteller)
		if name ~= o.from then return end
		local was = o.st
		o.st = "open"
		o.by = nil
		if was ~= "open" then o.seen = nil end
		clearProgress(o)
		-- wer den Auftrag selbst zurueckgegeben hat (schon wieder offen), braucht keinen Hinweis
		if was ~= "open" and not o.dismissed and O.HasProfession(o.key) then
			O.Notify(string.format(T("Auftrag wieder offen: %d× %s von %s", "Order open again: %d× %s from %s"), o.qty, O.Name(o), o.from))
		end
		changed()
	elseif kind == "D" then
		if o.from == me() then
			if name ~= o.by then return end
			if ns.History then ns.History.Add(o, "done") end
			db()[id] = nil
			if o.to == "*" then ns.Comm.Broadcast("D|" .. id) end
			O.Notify(string.format(T("%s meldet fertig: %d× %s", "%s reports done: %d× %s"), name, o.qty, O.Name(o)))
		elseif name == o.from then
			if o.by == me() then
				if ns.History then ns.History.Add(o, "done") end
				O.QueueReturn(o, "done")
				O.Notify(string.format(T("%s hat den Auftrag abgeschlossen: %d× %s", "%s closed the order: %d× %s"), name, o.qty, O.Name(o)))
			end
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
		if now - (o.created or 0) > (o.st == "taken" and MAX_AGE_TAKEN or MAX_AGE) then
			if ns.History then ns.History.Add(o, "expired") end
			db()[id] = nil
		elseif o.st == "pending" and not o.waiting then o.st = "open" end
	end
	for id, g in pairs(ns.db.ordersGone or {}) do
		if now - (g.t or 0) > MAX_AGE_TAKEN then ns.db.ordersGone[id] = nil end
	end
	for id, j in pairs(ns.db.returns or {}) do
		if now - (j.t or 0) > MAX_AGE_TAKEN then ns.db.returns[id] = nil end
	end
	-- nach dem Anmelden den Stand angenommener Auftraege nachreichen (Gildenliste ist dann geladen)
	C_Timer.After(20, function()
		local names = {}
		for _, o in pairs(db()) do
			local p = o.st == "taken" and not o.hold and O.Role(o) and partnerOf(o)
			if p and not ns.IsMine(p) then names[p] = true end
		end
		for _, g in pairs(ns.db.ordersGone or {}) do
			if g.mine == me() then names[g.p] = true end
		end
		-- eigene offene Bestellungen erneut anbieten (wer offline war, bekommt sie so)
		for _, o in pairs(db()) do
			if o.from == me() and o.st == "open" and not o.hold then
				if o.to == "*" then sendOrder(o) elseif not ns.IsMine(o.to) then names[ns.ShortName(o.to)] = true end
			end
		end
		for _, o in pairs(db()) do
			if o.st == "pending" and o.waiting and o.from ~= me() then names[o.from] = true end
		end
		for p in pairs(names) do
			local e = ns.Roster.Get(p)
			if not e or e.online then O.Resync(p) end
		end
	end)
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
	local can, on, found, onlyCan = 0, 0, false, nil
	for _, p in ipairs(list) do
		if p.can then can = can + 1; onlyCan = p.name end
		if p.online then on = on + 1 end
		if p.name == R.person then found = true end
	end
	-- Auswahl passt nicht mehr (anderes Rezept): verwerfen; nur eine sinnvolle Person: vorauswaehlen
	if R.person and not found then R.person = nil end
	if not R.person then
		if #list == 1 then R.person = list[1].name
		elseif can == 1 then R.person = onlyCan end
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
	-- Material (mitgeliefert geht nur an eine bestimmte Person)
	K.setSeg(w.matSelf, R.mats == "self")
	K.setSeg(w.matCr, R.mats == "crafter")
	if R.rec then
		local r = {}
		for _, e in ipairs(R.rec.r) do r[#r + 1] = { e[1], e[2] * R.qty } end
		local raw = K.RawFresh({ r = r, out = 0 })
		local lines = {}
		if R.mats == "self" then
			lines[1] = "|cff9a8f7e" .. T("Mit Material: Der Auftrag wird erst gesendet, wenn die Rohstoffe verschickt sind.",
				"With materials: the order is only sent once the materials are mailed.") .. "|r"
		end
		lines[#lines + 1] = string.format(T("Rohstoffe für %d× %s:", "Raw materials for %d× %s:"), R.qty, ns.RecipeName(R.rid, R.rec))
		for _, e in ipairs(raw) do
			local have = ns.ItemCount(e[1], true)
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

local ORDER_W = 380

local function buildOrderWindow()
	local f = K.Box(UIParent, K.COL.bg, K.COL.border)
	winOrder = f
	f:SetSize(ORDER_W, 520)
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
	rb:SetSize(ORDER_W - 24, 32)
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
	local search = EditBoxIn(f, ORDER_W - 24, 22, function(self)
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

	results = MiniList(f, 6, 20, ORDER_W - 24, function(r, it)
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
	f.toPerson = K.Btn(f, T("Direkt bestellen bei …", "Order directly from …"), 150, 20, function() R.to = "person"; refreshOrderForm() end, 11)
	f.toPerson:SetPoint("TOPLEFT", 12, -174)
	f.toAll = K.Btn(f, T("Alle im Beruf", "Everyone in profession"), 130, 20, function() R.to, R.mats = "all", "crafter"; refreshOrderForm() end, 11)
	f.toAll:SetPoint("LEFT", f.toPerson, "RIGHT", -1, 0)
	f.personList = MiniList(f, 4, 22, ORDER_W - 24, function(r, it)
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
	f.allInfo:SetWidth(ORDER_W - 24)
	f.allInfo:SetHeight(70)
	f.allInfo:SetWordWrap(true)
	f.allInfo:SetJustifyV("TOP")

	-- Material
	Lbl(f, T("Material", "Materials"), -296)
	f.matSelf = K.Btn(f, T("Ich liefere es", "I provide it"), 130, 20, function() R.mats, R.to = "self", "person"; refreshOrderForm() end, 11)
	f.matSelf:SetPoint("TOPLEFT", 12, -310)
	f.matCr = K.Btn(f, T("Hersteller besorgt es", "Crafter gets it"), 140, 20, function() R.mats = "crafter"; refreshOrderForm() end, 11)
	f.matCr:SetPoint("LEFT", f.matSelf, "RIGHT", -1, 0)
	f.needs = K.FS(f, 11, K.COL.text)
	f.needs:SetPoint("TOPLEFT", 12, -336)
	f.needs:SetWidth(ORDER_W - 24)
	f.needs:SetHeight(98)
	f.needs:SetWordWrap(true) -- ohne das zeigt das Spiel nur die erste Zeile
	f.needs:SetJustifyV("TOP")
	f.needs:SetSpacing(2)

	-- Notiz
	Lbl(f, T("Notiz (optional)", "Note (optional)"), -440)
	f.note = EditBoxIn(f, ORDER_W - 24, 22)
	f.note:SetPoint("TOPLEFT", 12, -454)
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
		if R.mats == "self" then
			local can
			for _, p in ipairs(persons()) do
				if p.name == R.person then can = p.can end
			end
			if to == "*" or not can then
				ns.Print(T("Mit Material bitte eine Person wählen, die das Rezept kennt.",
					"With materials, please choose a person who knows the recipe."))
				return
			end
		end
		local o = O.Create({ key = R.key, pname = R.pname, rid = R.rid, rec = R.rec, qty = R.qty, to = to, mats = R.mats,
			note = strtrim(f.note.edit:GetText()) })
		f:Hide()
		if R.mats == "self" then
			ns.Print(T("Auftrag vorbereitet. Er geht an ", "Order prepared. It is sent to ") .. to ..
				T(", sobald das Material verschickt ist.", " once the materials are mailed."))
			if O.OpenTask then O.OpenTask(o.id) end
			-- steht man schon am Briefkasten, wird die Post gleich vorbereitet
			if ns.Mail then ns.Mail.PrepareOrder(o.id) end
		else
			ns.Print(T("Bestellung gesendet an ", "Order sent to ") .. (to == "*" and (T("alle im Beruf ", "everyone in ") .. (R.pname or "")) or to))
		end
	end)
	send:SetPoint("BOTTOMRIGHT", -12, 10)
end

-- Auswahl in der Hauptliste ins offene Bestellfenster uebernehmen (Menge, Material und Notiz bleiben)
function O.SelectionChanged()
	if not (winOrder and winOrder:IsShown()) then return end
	local key, rid = ns.UI.GetSelection()
	if not (key and rid) or (R.key == key and R.rid == rid) then return end
	local rec, pname = foundRecipe(key, rid)
	if not rec then return end
	R.key, R.rid, R.rec, R.pname = key, rid, rec, pname
	winOrder.search.edit:SetText("")
	winOrder.search.edit:ClearFocus()
	refreshOrderForm()
end

function O.OpenOrder()
	K = K or ns.UIK
	if not winOrder then
		buildOrderWindow()
		ns.UI.Dockable(winOrder)
	end
	local key, rid = ns.UI.GetSelection()
	R = { qty = 1, to = "person", mats = "self" }
	if key and rid then
		local rec, pname = foundRecipe(key, rid)
		if rec then R.key, R.rid, R.rec, R.pname = key, rid, rec, pname end
	end
	winOrder.note.edit:SetText("")
	winOrder.search.edit:SetText("")
	winOrder:Show()
	refreshOrderForm()
end

-- ---------------------------------------------------------------- Fenster: Offene Auftraege
local LROWS, LROW_H = 6, 56
local LIST_W = 560
local LROW_W = LIST_W - 32

local function paintOrderRow(row, o)
	local inc = (o.from ~= me())
	row.icon:SetTexture((o.out and o.out > 0) and ns.ItemIcon(o.out) or K.profIcon(o.key, o.pname))
	row.title:SetText(o.qty .. "× " .. O.Name(o))
	local target
	if o.to == "*" then target = T("an alle im Beruf ", "to everyone in ") .. (o.pname or "")
	elseif inc then target = T("direkt an dich", "directly to you")
	else target = T("an ", "to ") .. o.to end
	local sub = (inc and (T("von ", "from ") .. o.from .. " · ") or "") .. target .. " · " ..
		(o.mats == "self" and T("mit Material", "with materials") or T("Material vom Hersteller", "materials from crafter")) ..
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
			B(T("Abbrechen", "Cancel"), function() O.Decline(o) end)
		elseif o.st == "pending" then
			B(T("Zurücknehmen", "Take back"), function() O.Unaccept(o) end)
			chip, chipC = T("wartet auf Bestätigung …", "waiting for confirmation …"), COL.gold
		elseif o.by == me() then
			accent = COL.green
			chip, chipC = T("angenommen · ", "accepted · ") .. O.StageText(o), COL.green
			B(T("Abarbeiten", "Work on it"), function() O.OpenTask(o.id) end)
			B(T("Anflüstern", "Whisper"), function() K.whisper(o.from) end)
			B(T("Zurückgeben", "Give back"), function() O.ConfirmRelease(o) end)
		else
			accent = COL.off
			chip = T("übernommen von ", "taken by ") .. (o.by or "?")
		end
	else
		if o.st == "declined" then
			accent = COL.red
			chip, chipC = T("abgebrochen von ", "cancelled by ") .. (o.declinedBy or o.to), COL.red
			B(T("Entfernen", "Remove"), function() O.Remove(o) end)
		elseif o.st ~= "taken" then
			chip, chipC = (o.to == "*") and T("wartet auf Hersteller", "waiting for a crafter") or (T("wartet auf ", "waiting for ") .. o.to), COL.gold
			local n = 0
			for _ in pairs(o.declined or {}) do n = n + 1 end
			if n > 0 then chip = chip .. " · " .. n .. T(" abgelehnt", " declined") end
			B(T("Zurückziehen", "Withdraw"), function() O.Withdraw(o) end)
		else
			accent = COL.green
			chip, chipC = (o.by or "?") .. " · " .. O.StageText(o), COL.green
			B(T("Abarbeiten", "Work on it"), function() O.OpenTask(o.id) end)
			B(T("Anflüstern", "Whisper"), function() K.whisper(o.by) end)
			B(T("Zurückziehen", "Withdraw"), function() O.ConfirmWithdraw(o) end)
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
	-- Texte nutzen den Platz bis zum Status bzw. zu den Knoepfen
	local left = 12 + 28 + 8
	row.title:SetWidth(math.max(80, LROW_W - left - math.ceil(row.chip:GetStringWidth()) - 20))
	local bw = (#acts > 0) and (#acts * 82 + 8) or 0
	row.sub:SetWidth(math.max(80, LROW_W - left - bw - 10))
	row.raw:SetWidth(math.max(80, LROW_W - left - bw - 10))
	row:SetAlpha((inc and o.st == "taken" and o.by ~= me()) and 0.65 or 1)
end

local function renderList()
	if not winList or not winList:IsShown() then return end
	local w = winList
	local inN, mineN, outN = #O.List("in"), #O.List("mine"), #O.List("out")
	w.tabMine.label:SetText(T("Meine Aufträge (", "My jobs (") .. mineN .. ")")
	K.setSeg(w.tabMine, openTab == "mine")
	w.tabIn.label:SetText(T("Eingehend (", "Incoming (") .. inN .. ")")
	w.tabOut.label:SetText(T("Meine Bestellungen (", "My orders (") .. outN .. ")")
	for _, b in ipairs({ w.tabIn, w.tabMine, w.tabOut }) do b:SetWidth(math.ceil(b.label:GetStringWidth()) + 18) end
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
		-- im Eingang angezeigt = gesehen (je Figur, die Liste gilt account-weit)
		if o and openTab == "in" and o.st == "open" and not (o.seen and o.seen[me()]) then
			o.seen = o.seen or {}
			o.seen[me()] = true
			if ns.Mini and ns.Mini.Update then ns.Mini.Update() end
		end
	end
	w.empty:SetShown(#list == 0)
	local empty = T("Keine Aufträge für dich.", "No orders for you.")
	if openTab == "mine" then empty = T("Du hast keinen Auftrag angenommen.", "You have not accepted any order.")
	elseif openTab == "out" then empty = T("Du hast nichts bestellt.", "You have not ordered anything.") end
	w.empty:SetText(empty)
end

local function buildListWindow()
	local f = K.Box(UIParent, K.COL.bg, K.COL.border)
	winList = f
	f.offset = 0
	f:SetSize(LIST_W, 470)
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
	f.tabMine = K.Btn(f, "", 130, 20, function() openTab = "mine"; f.offset = 0; renderList() end, 11)
	f.tabMine:SetPoint("LEFT", f.tabIn, "RIGHT", -1, 0)
	f.tabOut:SetPoint("LEFT", f.tabMine, "RIGHT", -1, 0)

	f.chk = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	f.chk:SetSize(22, 22)
	f.chk:SetPoint("TOPRIGHT", -130, -34)
	f.chk:SetScript("OnClick", function(self) onlyCraft = self:GetChecked() and true or false; f.offset = 0; renderList() end)
	f.chkText = K.FS(f, 11, K.COL.muted)
	f.chkText:SetPoint("LEFT", f.chk, "RIGHT", 0, 0)
	f.chkText:SetText(T("Nur herstellbare", "Only craftable"))
	f.chk:ClearAllPoints()
	f.chk:SetPoint("TOPRIGHT", -(14 + math.ceil(f.chkText:GetStringWidth())), -34)

	f.rows = {}
	for i = 1, LROWS do
		local row = CreateFrame("Frame", nil, f)
		row:SetSize(LROW_W, LROW_H)
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
		row.chip:SetWidth(0)
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

function O.OpenList(tab)
	if tab and tab ~= openTab then
		openTab = tab
		if winList then winList.offset = 0 end
	end
	K = K or ns.UIK
	if not winList then
		buildListWindow()
		ns.UI.Dockable(winList)
	end
	winList:Show()
	winList:Raise() -- ueber das Hauptfenster
	renderList()
end

function O.CloseList()
	if winList then winList:Hide() end
end

-- Knopf-Verhalten: erster Klick oeffnet, zweiter schliesst
function O.ToggleOrder()
	if winOrder and winOrder:IsShown() then winOrder:Hide() else O.OpenOrder() end
end

-- mit Reiter: schliesst nur, wenn genau dieser schon offen ist
function O.ToggleList(tab)
	if winList and winList:IsShown() and (not tab or tab == openTab) then winList:Hide() else O.OpenList(tab) end
end

-- Rueckfrage, wenn schon etwas passiert ist (Material unterwegs oder verbraucht)
local function confirm(text, fn)
	StaticPopupDialogs["CRAFTSHARE_CONFIRM"] = {
		text = "%s", button1 = YES, button2 = NO, OnAccept = function() fn() end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
		-- ueber den eigenen Fenstern anzeigen
		OnShow = function(self) self:SetFrameStrata("FULLSCREEN_DIALOG") end,
	}
	StaticPopup_Show("CRAFTSHARE_CONFIRM", text)
end

function O.ConfirmWithdraw(o)
	if not (o.ms or o.mr or o.sentM or (o.cr or 0) > 0 or o.sh) then return O.Withdraw(o) end
	confirm(T("Bei diesem Auftrag wurde schon Material verschickt oder hergestellt. Wirklich zurückziehen?",
		"Materials were already sent or items crafted for this order. Really withdraw it?"),
		function() if db()[o.id] == o then O.Withdraw(o) end end)
end

function O.ConfirmRelease(o)
	if not (o.ms or o.mr or (o.cr or 0) > 0 or o.sh) then return O.Release(o) end
	confirm(T("Bei diesem Auftrag wurde schon Material verschickt oder hergestellt. Wirklich zurückgeben?",
		"Materials were already sent or items crafted for this order. Really give it back?"),
		function() if db()[o.id] == o then O.Release(o) end end)
end

-- Abschliessen, ohne dass der Besteller den Empfang ueber den letzten Schritt bestaetigt: erst nachfragen
function O.ConfirmDone(o)
	confirm(T("Auftrag wirklich abschließen? Er wird bei beiden entfernt.", "Really close this order? It is removed for both."),
		function() if db()[o.id] == o then O.Done(o) end end)
end

function O.Get(id) return db()[id] end

function O.Refresh()
	if ns.Task then ns.Task.Refresh() end
	if ns.Mail then ns.Mail.Refresh() end
	if winList and winList:IsShown() then renderList() end
	if winOrder and winOrder:IsShown() then refreshOrderForm() end
end
