-- CraftShare: Synchronisation ueber Addon-Nachrichten (Gilde, Gruppe, Raid, Freunde per Fluestern).
-- Protokoll (Felder durch "|" getrennt):
--   Q|ver                       Anfrage: "ich bin da, schickt mir euren Stand"
--   G|key|rank|max|rev|count|class|name   Stand eines Berufs (rev = Nummer der letzten Aenderung)
--   E|key|since                 Anfrage: Rezepte, die neuer als "since" sind
--   L|key|id,out,item:qty/item:qty;id,out,...   Rezeptzeilen (werden immer dazugenommen, nie geloescht)
--   F|key|rev|since             alle Aenderungen nach "since" bis "rev" wurden gesendet
--   P|key|name|rank|max|class   Berufskopf aelterer Fassungen
local ADDON, ns = ...
local Comm = {}
ns.Comm = Comm

local queue = {}
local sending = false
local broadcastPending = false
local replied = {}
local asked, answered = {}, {}
local MAXLEN = 230

local function rawSend(text, channel, target)
	local send = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
	if send then pcall(send, ns.PREFIX, text, channel, target) end
end

local function pump()
	local item = table.remove(queue, 1)
	if not item then sending = false return end
	rawSend(item[1], item[2], item[3])
	C_Timer.After(0.12, pump)
end

local function enqueue(text, channel, target)
	queue[#queue + 1] = { text, channel, target }
	if not sending then
		sending = true
		C_Timer.After(0.05, pump)
	end
end

local function targets(channel, target)
	if channel then return { { channel, target } } end
	local t = {}
	if IsInGuild and IsInGuild() then t[#t + 1] = { "GUILD" } end
	if IsInRaid and IsInRaid() then t[#t + 1] = { "RAID" }
	elseif IsInGroup and IsInGroup() then t[#t + 1] = { "PARTY" } end
	for name in pairs(ns.db.friends) do t[#t + 1] = { "WHISPER", name } end
	return t
end

local function encodeRecipe(id, rec)
	local parts = {}
	for _, r in ipairs(rec.r) do parts[#parts + 1] = r[1] .. ":" .. r[2] end
	-- Ergebnis-Item, bei Mehrfachherstellung "ItemxMenge"
	local out = tostring(rec.out or 0)
	if rec.q and rec.q > 1 then out = out .. "x" .. rec.q end
	-- Kategorie (Nummer in der Kategorieliste des Berufs, Nachricht K)
	if rec.c then out = out .. "@" .. rec.c end
	-- Schwierigkeit (0 orange, 1 gelb, 2 gruen, 3 grau)
	if rec.d then out = out .. "~" .. rec.d end
	return id .. "," .. out .. "," .. table.concat(parts, "/")
end

-- Kategorienamen des Berufs (K|key|ab Nummer|Name;Name;...), in Stuecken
local function sendCats(key, p, tg)
	if not p.cats or #p.cats == 0 then return end
	local names, start, size = {}, 1, 0
	for i, nm in ipairs(p.cats) do
		local s = (nm:gsub("[|;]", ""))
		if size + #s + 1 > 170 and #names > 0 then
			enqueue("K|" .. key .. "|" .. start .. "|" .. table.concat(names, ";"), tg[1], tg[2])
			names, start, size = {}, i, 0
		end
		names[#names + 1] = s
		size = size + #s + 1
	end
	if #names > 0 then enqueue("K|" .. key .. "|" .. start .. "|" .. table.concat(names, ";"), tg[1], tg[2]) end
end

-- Rezeptzeilen: alle, die neuer als "since" sind
local function sendRecipes(key, p, since, tg)
	local head = "L|" .. key .. "|"
	local buf = {}
	local len = #head
	for id, rec in pairs(p.recipes or {}) do
		if (rec.v or 0) > since or since == 0 then
			local e = encodeRecipe(id, rec)
			if len + #e + 1 > MAXLEN and #buf > 0 then
				enqueue(head .. table.concat(buf, ";"), tg[1], tg[2])
				buf, len = {}, #head
			end
			buf[#buf + 1] = e
			len = len + #e + 1
		end
	end
	if #buf > 0 then enqueue(head .. table.concat(buf, ";"), tg[1], tg[2]) end
end

-- Stand eines eigenen Berufs: Nummer der letzten Aenderung (rev), je Rezept die Nummer seiner Aenderung (v).
-- "old" sind die Rezepte vor einem neuen Scan. true, wenn etwas neu oder geaendert ist.
function Comm.Stamp(p, old)
	local now = math.max(time(), (p.rev or 0) + 1)
	local changed = false
	for id, rec in pairs(p.recipes or {}) do
		local before = old and old[id]
		if before and before.v and encodeRecipe(id, before) == encodeRecipe(id, rec) then
			rec.v = before.v
		elseif old or not rec.v then
			rec.v = now
			changed = true
		end
	end
	if changed or not p.rev then p.rev = now end
	return changed
end

local function ownProfs()
	local c = ns.GetChar(ns.Me())
	if not c then return {}, "" end
	for _, p in pairs(c.profs) do
		if not p.rev then Comm.Stamp(p) end
	end
	return c.profs, c.class or ""
end

local function countOf(p)
	local n = 0
	for _ in pairs(p.recipes or {}) do n = n + 1 end
	return n
end

local function digest(key, p, class)
	return string.format("G|%s|%d|%d|%d|%d|%s|%s|%s", key, p.rank or 0, p.max or 0, p.rev or 0, countOf(p), class,
		(p.name or key):gsub("|", ""), ns.VERSION)
end

-- Nur der Stand (G): wer weniger hat, fragt die fehlenden Rezepte an
function Comm.SendDigest(channel, target)
	local profs, class = ownProfs()
	for _, tg in ipairs(targets(channel, target)) do
		for key, p in pairs(profs) do enqueue(digest(key, p, class), tg[1], tg[2]) end
	end
end

-- Antwort auf eine Anfrage: alles Neuere als "since", abgeschlossen mit F|key|rev|since
function Comm.SendDelta(key, since, channel, target)
	local profs, class = ownProfs()
	local p = profs[key]
	if not p then return end
	local tg = { channel, target }
	if since > (p.rev or 0) then since = 0 end
	enqueue(digest(key, p, class), channel, target)
	sendCats(key, p, tg)
	sendRecipes(key, p, since, tg)
	enqueue("F|" .. key .. "|" .. (p.rev or 0) .. "|" .. since, channel, target)
end

-- Alles auf einmal, nur noch fuer aeltere Fassungen (die den Stand nicht verstehen)
function Comm.SendOwn(channel, target)
	local profs, class = ownProfs()
	for _, tg in ipairs(targets(channel, target)) do
		for key, p in pairs(profs) do
			enqueue(string.format("P|%s|%s|%d|%d|%s", key, p.name or key, p.rank or 0, p.max or 0, class), tg[1], tg[2])
			sendCats(key, p, tg)
			sendRecipes(key, p, 0, tg)
		end
	end
end

-- nach einem Scan: nur die neuen Rezepte an alle, danach der Stand
local function publish()
	local profs, class = ownProfs()
	for _, tg in ipairs(targets()) do
		for key, p in pairs(profs) do
			local since = p.pubRev or 0
			if since > 0 and (p.rev or 0) > since then
				sendCats(key, p, tg)
				sendRecipes(key, p, since, tg)
				enqueue("F|" .. key .. "|" .. p.rev .. "|" .. since, tg[1], tg[2])
			end
			enqueue(digest(key, p, class), tg[1], tg[2])
		end
	end
	for _, p in pairs(profs) do p.pubRev = p.rev end
end

-- Einzelne Nachricht (fuer Bestellungen): an einen Kanal/Spieler bzw. an alle ueblichen Ziele.
function Comm.Send(text, channel, target)
	enqueue(text, channel, target)
end

function Comm.Broadcast(text)
	for _, tg in ipairs(targets()) do enqueue(text, tg[1], tg[2]) end
end

function Comm.Request(channel, target)
	for _, tg in ipairs(targets(channel, target)) do
		enqueue("Q|" .. ns.VERSION, tg[1], tg[2])
	end
end

-- Mehrere Scans kurz hintereinander zu einem Versand zusammenfassen.
function Comm.QueueBroadcast()
	if not ns.db.autoSync or broadcastPending then return end
	broadcastPending = true
	C_Timer.After(5, function()
		broadcastPending = false
		publish()
	end)
end

-- Stimmt die Fassung des Gegenuebers den Abgleich ueber den Stand?
local function understandsDigest(ver)
	local major, minor = tostring(ver or ""):match("^(%d+)%.(%d+)")
	major, minor = tonumber(major), tonumber(minor)
	return major ~= nil and (major > 0 or minor >= 4)
end

local function request(name, sender, key, since)
	local id = name .. "/" .. key
	local now = GetTime()
	if asked[id] and now - asked[id] < 30 then return end
	asked[id] = now
	enqueue("E|" .. key .. "|" .. since, "WHISPER", sender)
end

local function onDigest(text, name, sender)
	local f = { strsplit("|", text) }
	local key, rank, max, rev, count, class, pname = f[2], tonumber(f[3]), tonumber(f[4]), tonumber(f[5]), tonumber(f[6]), f[7], f[8]
	if f[9] then ns.NoteVersion(name, f[9]) end
	if not (key and key ~= "" and #key <= 20 and rev and count and pname and ns.IsCrafting(pname)) then return end
	local ch = ns.GetChar(name, true)
	if class and class ~= "" then ch.class = class end
	ch.updated = time()
	local prof = ch.profs[key]
	if not prof then
		prof = { recipes = {}, count = 0 }
		ch.profs[key] = prof
	end
	prof.name, prof.rank, prof.max = pname, rank, max
	if (prof.rev or 0) ~= rev then
		-- nur das Neue anfordern
		request(name, sender, key, (prof.rev or 0) < rev and (prof.rev or 0) or 0)
	elseif countOf(prof) < count then
		request(name, sender, key, 0) -- unterwegs ging etwas verloren
	end
	if ns.UI and ns.UI.Dirty then ns.UI.Dirty() end
end

local function onMessage(text, channel, sender)
	local name = ns.ShortName(sender)
	if not name then return end
	-- Selbsttest: unsere eigene Nachricht kommt mit dem vollen Namen (Vor- und Nachname) zurueck
	if text:sub(1, 2) == "S|" then
		if ns.nonce and text == "S|" .. ns.nonce then ns.SetFullName(sender) end
		return
	end
	if name == ns.Me() then return end
	if #text > 255 then return end
	local kind, a, b, c, d, e = strsplit("|", text)
	if kind == "P" or kind == "L" or kind == "G" or kind == "F" then ns.lastSync = time() end
	if kind == "Q" then
		ns.NoteVersion(name, a)
		-- der Anfragende ist gerade online gekommen: Auftragsstand nachreichen
		if ns.Orders and ns.Orders.Resync then C_Timer.After(2, function() ns.Orders.Resync(name) end) end
		if ns.Relay then C_Timer.After(3, function() ns.Relay.Deliver(name) end) end
		-- Antwort gestaffelt und nur einmal pro Minute je Anfragendem, per Fluestern
		local now = GetTime()
		if replied[name] and now - replied[name] < 60 then return end
		replied[name] = now
		local send = understandsDigest(a) and Comm.SendDigest or Comm.SendOwn
		C_Timer.After(1 + math.random() * 5, function() send("WHISPER", sender) end)
	elseif kind == "G" then
		onDigest(text, name, sender)
	elseif kind == "E" then
		local since = tonumber(b)
		if not a or not since then return end
		local id = name .. "/" .. a
		local now = GetTime()
		if answered[id] and now - answered[id] < 10 then return end
		answered[id] = now
		Comm.SendDelta(a, since, "WHISPER", sender)
	elseif kind == "F" then
		local ch = ns.db.chars[name]
		local prof = ch and ch.profs[a]
		local rev, since = tonumber(b), tonumber(c)
		if not prof or not rev or not since then return end
		asked[name .. "/" .. a] = nil
		-- Stand nur uebernehmen, wenn nichts dazwischen fehlt
		if (prof.rev or 0) >= since then prof.rev = rev end
	elseif kind == "P" then
		local key, pname, rank, max, class = a, b, tonumber(c), tonumber(d), e
		if not key or key == "" or #key > 20 then return end
		if not ns.IsCrafting(pname) then return end
		local ch = ns.GetChar(name, true)
		if class and class ~= "" then ch.class = class end
		ch.updated = time()
		-- bekannte Rezepte bleiben erhalten, neue kommen dazu
		local prof = ch.profs[key] or { recipes = {}, count = 0 }
		prof.name, prof.rank, prof.max = pname or key, rank, max
		ch.profs[key] = prof
		if ns.UI and ns.UI.Dirty then ns.UI.Dirty() end
	elseif kind == "L" then
		local ch = ns.db.chars[name]
		local prof = ch and ch.profs[a]
		if not prof or not b then return end
		for entry in b:gmatch("[^;]+") do
			local id, out, qty, cat, dif, reag = entry:match("^(%d+),(%d+)x?(%d*)@?(%d*)~?(%d*),?(.*)$")
			id, out, qty, cat, dif = tonumber(id), tonumber(out), tonumber(qty), tonumber(cat), tonumber(dif)
			if id and (prof.recipes[id] or prof.count < 1500) then
				local rec = { out = out or 0, r = {} }
				if cat and cat >= 1 and cat <= 60 then rec.c = cat end
				if qty and qty > 1 and qty < 1000 then rec.q = qty end
				if dif and dif >= 0 and dif <= 3 then rec.d = dif end
				for item, qty in (reag or ""):gmatch("(%d+):(%d+)") do
					rec.r[#rec.r + 1] = { tonumber(item), tonumber(qty) }
				end
				if not prof.recipes[id] then prof.count = prof.count + 1 end
				prof.recipes[id] = rec
			end
		end
		if ns.UI and ns.UI.Dirty then ns.UI.Dirty() end
	elseif kind == "K" then
		local ch = ns.db.chars[name]
		local prof = ch and ch.profs[a]
		local start = tonumber(b)
		if not prof or not start or start < 1 or start > 60 or not c then return end
		prof.cats = (start > 1 and prof.cats) or {}
		local i = start
		for nm in c:gmatch("[^;]+") do
			if i <= 60 then prof.cats[i] = nm:sub(1, 40) end
			i = i + 1
		end
		if ns.UI and ns.UI.Dirty then ns.UI.Dirty() end
	elseif (kind == "X" or kind == "Y" or kind == "Z") and ns.Relay then
		ns.Relay.OnMessage(kind, text, sender)
	elseif ns.Orders and ns.Orders.KINDS[kind] then
		ns.Orders.OnMessage(kind, text, sender)
	end
end

function Comm.Init()
	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
		C_ChatInfo.RegisterAddonMessagePrefix(ns.PREFIX)
	elseif RegisterAddonMessagePrefix then
		RegisterAddonMessagePrefix(ns.PREFIX)
	end
	local f = CreateFrame("Frame")
	f:RegisterEvent("CHAT_MSG_ADDON")
	f:RegisterEvent("PLAYER_LOGIN")
	f:RegisterEvent("GROUP_ROSTER_UPDATE")
	f:SetScript("OnEvent", function(_, ev, prefix, text, channel, sender)
		if ev == "CHAT_MSG_ADDON" then
			if prefix == ns.PREFIX and text then onMessage(text, channel, sender) end
		elseif ev == "PLAYER_LOGIN" then
			C_Timer.After(6, function()
				ns.nonce = tostring(math.random(10000000, 99999999))
				Comm.Broadcast("S|" .. ns.nonce)
			end)
			C_Timer.After(10, function()
				if not ns.db.autoSync then return end
				Comm.Request()
				Comm.SendDigest()
			end)
		elseif ev == "GROUP_ROSTER_UPDATE" then
			-- neue Gruppe: einmalig anfragen (gedrosselt)
			if ns.db.autoSync and not Comm._groupCd then
				Comm._groupCd = true
				C_Timer.After(30, function() Comm._groupCd = nil end)
				C_Timer.After(3, function()
					local ch = (IsInRaid and IsInRaid()) and "RAID" or ((IsInGroup and IsInGroup()) and "PARTY")
					if ch then Comm.Request(ch); Comm.SendDigest(ch) end
				end)
			end
		end
	end)
end
