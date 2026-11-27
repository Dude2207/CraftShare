-- CraftShare: Gilde als Bote. Ist der Empfaenger einer Auftragsnachricht offline, geht sie an die Gilde. Alle, die
-- gerade online sind und das Addon haben, speichern sie und stellen sie zu, sobald sie den Empfaenger sehen.
-- Nachrichten (Felder durch "|"):
--   X|tok|i|n|chunk   an die Gilde: bitte aufbewahren   (Inhalt: to~from~Nachricht, to = "*" = alle)
--   Y|tok|i|n|chunk   Bote an den Empfaenger: zugestellt wird im Namen von "from"
--   Z|key             an die Gilde: erledigt, nicht mehr aufbewahren   (key = to~from~Art~Auftrags-ID)
-- Weitergeleitet wird nur innerhalb der Gilde; ein Bote kann die Echtheit des Absenders nicht beweisen.
local ADDON, ns = ...
local R = {}
ns.Relay = R

local CHUNK = 220
local MAX_AGE = 7 * 86400
local MAX_ENTRIES = 200

local counter = 0
local buffers = {}   -- Teilstuecke, die noch zusammengesetzt werden
local planned = {}   -- Zustellungen mit Wartezeit (damit nicht alle Boten gleichzeitig senden)

local function store()
	ns.db.relay = ns.db.relay or {}
	return ns.db.relay
end

local function offline(name)
	local e = ns.Roster.Get(name)
	return e ~= nil and not e.online
end

local function inGuild(name) return ns.Roster.Get(name) ~= nil end

local function keyOf(to, from, msg)
	local kind, id = strsplit("|", msg)
	return to .. "~" .. from .. "~" .. (kind or "?") .. "~" .. (id or "?")
end

local function chunks(prefix, payload, channel, target)
	counter = counter + 1
	local tok = tostring(math.random(1000, 9999)) .. counter
	local n = math.ceil(#payload / CHUNK)
	if n < 1 or n > 3 then return end
	for i = 1, n do
		ns.Comm.Send(prefix .. "|" .. tok .. "|" .. i .. "|" .. n .. "|" .. payload:sub((i - 1) * CHUNK + 1, i * CHUNK),
			channel, target)
	end
end

-- Boten in der Gilde bitten, die Nachricht aufzubewahren
function R.Store(to, msg)
	if not (IsInGuild and IsInGuild()) then return end
	chunks("X", to .. "~" .. ns.Me() .. "~" .. msg, "GUILD")
end

-- Auftragsnachricht an eine Person: direkt, oder ueber die Gilde, wenn sie offline ist
function R.Send(name, msg)
	if not name or ns.IsMine(name) then return end
	if offline(name) then
		R.Store(ns.ShortName(name), msg)
	else
		ns.Comm.Send(msg, "WHISPER", name)
	end
end

function R.IsOffline(name) return offline(name) end

-- Auftrag ist erledigt/vergeben: Boten sollen ihn vergessen
function R.Cancel(to, kind, id)
	local key = to .. "~" .. ns.Me() .. "~" .. kind .. "~" .. id
	store()[key] = nil
	if IsInGuild and IsInGuild() then ns.Comm.Send("Z|" .. key, "GUILD") end
end

-- ---------------------------------------------------------------- Bote
local function keep(to, from, msg)
	if to == ns.Me() or from == ns.Me() then return end
	local s = store()
	local key = keyOf(to, from, msg)
	if not s[key] then
		local n, oldest, oldKey = 0, nil, nil
		for k, e in pairs(s) do
			n = n + 1
			if not oldest or e.t < oldest then oldest, oldKey = e.t, k end
		end
		if n >= MAX_ENTRIES and oldKey then s[oldKey] = nil end
	end
	-- gleiche Art zum gleichen Auftrag: nur der neueste Stand zaehlt
	s[key] = { to = to, from = from, msg = msg, t = time(), done = {} }
end

local function deliver(key, name)
	local e = store()[key]
	if not e or offline(name) or e.done[name] then return end
	e.done[name] = true
	chunks("Y", e.to .. "~" .. e.from .. "~" .. e.msg, "WHISPER", name)
end

-- jemand ist (wieder) da: alles zustellen, was fuer ihn (oder fuer alle) aufbewahrt wird
function R.Deliver(name)
	if not name or name == ns.Me() or not inGuild(name) then return end
	for key, e in pairs(store()) do
		if (e.to == name or e.to == "*") and e.from ~= name and not e.done[name] and not planned[key .. name] then
			planned[key .. name] = true
			C_Timer.After(2 + math.random() * 8, function()
				planned[key .. name] = nil
				deliver(key, name)
			end)
		end
	end
end

-- ---------------------------------------------------------------- Empfang
local function assemble(sender, text)
	local tok, i, n, chunk = text:match("^%u|(%d+)|(%d)|(%d)|(.*)$")
	i, n = tonumber(i), tonumber(n)
	if not tok or not i or not n or n < 1 or n > 3 or i < 1 or i > n then return end
	local id = text:sub(1, 1) .. sender .. tok
	local b = buffers[id]
	if not b then
		b = { n = n, got = 0, parts = {}, t = GetTime() }
		buffers[id] = b
	end
	if not b.parts[i] then
		b.parts[i] = chunk
		b.got = b.got + 1
	end
	if b.got < b.n then return end
	buffers[id] = nil
	return table.concat(b.parts):match("^(.-)~(.-)~(.*)$")
end

function R.OnMessage(kind, text, sender)
	local name = ns.ShortName(sender)
	-- Boten und Auftraggeber muessen in der eigenen Gilde sein
	if not inGuild(name) then return end
	if kind == "X" then
		local to, from, msg = assemble(name, text)
		-- aufbewahrt wird nur, was der Absender in eigenem Namen schickt
		if to and from == name and msg ~= "" then
			keep(to, from, msg)
			if to ~= "*" and not offline(to) then R.Deliver(to) end
		end
	elseif kind == "Y" then
		local to, from, msg = assemble(name, text)
		if not to or not inGuild(from) or from == ns.Me() then return end
		if to ~= "*" and to ~= ns.Me() then return end
		local k = msg:sub(1, 1)
		if ns.Orders.KINDS[k] and msg:sub(2, 2) == "|" then
			ns.Orders.OnMessage(k, msg, from)
			-- Direktnachricht angekommen: die anderen Boten koennen sie vergessen
			if to ~= "*" then ns.Comm.Send("Z|" .. keyOf(to, from, msg), "GUILD") end
		end
	elseif kind == "Z" then
		local key = text:sub(3)
		local to, from = key:match("^(.-)~(.-)~")
		-- nur Empfaenger oder Absender duerfen etwas loeschen
		if to and (name == from or (to ~= "*" and name == to)) then
			store()[key] = nil
			for p in pairs(planned) do
				if p:sub(1, #key) == key then planned[p] = nil end
			end
		end
	end
end

function R.Init()
	local now = time()
	for key, e in pairs(store()) do
		if now - (e.t or 0) > MAX_AGE then store()[key] = nil end
	end
	-- nach dem Anmelden (Gildenliste geladen): Aufbewahrtes an alle zustellen, die online sind
	C_Timer.After(30, function()
		local names = {}
		for _, e in pairs(store()) do
			if e.to ~= "*" then names[e.to] = true end
		end
		for n in pairs(names) do
			if not offline(n) then R.Deliver(n) end
		end
	end)
end
