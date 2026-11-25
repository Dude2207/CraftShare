-- CraftShare: Synchronisation ueber Addon-Nachrichten (Gilde, Gruppe, Raid, Freunde per Fluestern).
-- Protokoll (Felder durch "|" getrennt):
--   Q|ver                       Anfrage: "schickt mir eure Daten"
--   P|key|name|rank|max|class   Berufskopf, setzt Rezeptliste dieses Berufs zurueck
--   L|key|id,out,item:qty/item:qty;id,out,...   Rezeptzeilen
local ADDON, ns = ...
local Comm = {}
ns.Comm = Comm

local queue = {}
local sending = false
local broadcastPending = false
local replied = {}
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

function Comm.SendOwn(channel, target)
	local c = ns.GetChar(ns.Me())
	if not c then return end
	local class = c.class or ""
	for _, tg in ipairs(targets(channel, target)) do
		for key, p in pairs(c.profs) do
			enqueue(string.format("P|%s|%s|%d|%d|%s", key, p.name or key, p.rank or 0, p.max or 0, class), tg[1], tg[2])
			-- Kategorienamen des Berufs (K|key|ab Nummer|Name;Name;...), in Stuecken
			if p.cats and #p.cats > 0 then
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
			local head = "L|" .. key .. "|"
			local buf = {}
			local len = #head
			for id, rec in pairs(p.recipes or {}) do
				local e = encodeRecipe(id, rec)
				if len + #e + 1 > MAXLEN and #buf > 0 then
					enqueue(head .. table.concat(buf, ";"), tg[1], tg[2])
					buf, len = {}, #head
				end
				buf[#buf + 1] = e
				len = len + #e + 1
			end
			if #buf > 0 then enqueue(head .. table.concat(buf, ";"), tg[1], tg[2]) end
		end
	end
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
		Comm.SendOwn()
	end)
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
	if kind == "P" or kind == "L" then ns.lastSync = time() end
	if kind == "Q" then
		-- Antwort gestaffelt und nur einmal pro Minute je Anfragendem, per Fluestern
		local now = GetTime()
		if replied[name] and now - replied[name] < 60 then return end
		replied[name] = now
		C_Timer.After(1 + math.random() * 5, function() Comm.SendOwn("WHISPER", sender) end)
	elseif kind == "P" then
		local key, pname, rank, max, class = a, b, tonumber(c), tonumber(d), e
		if not key or key == "" or #key > 20 then return end
		if not ns.IsCrafting(pname) then return end
		local ch = ns.GetChar(name, true)
		if class and class ~= "" then ch.class = class end
		ch.updated = time()
		ch.profs[key] = { name = pname or key, rank = rank, max = max, recipes = {}, count = 0 }
		if ns.UI and ns.UI.Dirty then ns.UI.Dirty() end
	elseif kind == "L" then
		local ch = ns.db.chars[name]
		local prof = ch and ch.profs[a]
		if not prof or not b then return end
		for entry in b:gmatch("[^;]+") do
			local id, out, qty, cat, dif, reag = entry:match("^(%d+),(%d+)x?(%d*)@?(%d*)~?(%d*),?(.*)$")
			id, out, qty, cat, dif = tonumber(id), tonumber(out), tonumber(qty), tonumber(cat), tonumber(dif)
			if id and prof.count < 1500 then
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
		prof.cats = prof.cats or {}
		local i = start
		for nm in c:gmatch("[^;]+") do
			if i <= 60 then prof.cats[i] = nm:sub(1, 40) end
			i = i + 1
		end
		if ns.UI and ns.UI.Dirty then ns.UI.Dirty() end
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
				Comm.SendOwn()
			end)
		elseif ev == "GROUP_ROSTER_UPDATE" then
			-- neue Gruppe: einmalig anfragen (gedrosselt)
			if ns.db.autoSync and not Comm._groupCd then
				Comm._groupCd = true
				C_Timer.After(30, function() Comm._groupCd = nil end)
				C_Timer.After(3, function()
					local ch = (IsInRaid and IsInRaid()) and "RAID" or ((IsInGroup and IsInGroup()) and "PARTY")
					if ch then Comm.Request(ch); Comm.SendOwn(ch) end
				end)
			end
		end
	end)
end
