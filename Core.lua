-- CraftShare: Kern (Namespace, Datenbank, Hilfsfunktionen, Slash-Befehle)
local ADDON, ns = ...
ns.VERSION = "0.3.0"
ns.PREFIX = "CraftShare"

local L = {}
ns.L = L
local isDE = (GetLocale and GetLocale() == "deDE")
local function T(de, en) return isDE and de or en end
ns.T = T

function ns.Print(msg)
	print("|cff33ccffCraftShare|r: " .. tostring(msg))
end

-- Spielername ohne Realm. In WoW Forever haben Spieler Vor- UND Nachnamen ("Vorname Nachname"),
-- das Leerzeichen gehoert also zum Namen. Nur der Teil hinter "-" ist der Realm.
function ns.ShortName(name)
	if not name then return nil end
	return (name:match("^([^%-]+)")) or name
end

-- Voller Name des eigenen Charakters. UnitName liefert in Forever evtl. nur den Vornamen; den vollen Namen
-- lernt das Addon (Spiel-APIs, Gildenliste, eigene Nachricht) und speichert ihn in ns.db.fullName.
function ns.Me()
	return ns.fullName or (UnitName("player"))
end

function ns.SetFullName(full)
	full = ns.ShortName(full)
	if not full or full == "" or full == ns.fullName or not ns.db then return end
	local first = UnitName("player")
	local old = ns.fullName or first
	ns.fullName = full
	-- pro Charakter merken (die SavedVariables gelten fuer den ganzen Account!)
	ns.db.fullNames = ns.db.fullNames or {}
	if first then ns.db.fullNames[first] = full end
	ns.db.myChars = ns.db.myChars or {}
	ns.db.myChars[full] = true
	-- bisherige Eintraege des eigenen Charakters (nur Vorname) auf den vollen Namen umziehen; eigene Daten gelten
	local chars = ns.db.chars
	for _, k in ipairs({ first, old }) do
		if k and k ~= full and chars[k] then
			chars[full] = chars[k]
			chars[k] = nil
		end
	end
	for _, o in pairs(ns.db.orders or {}) do
		if o.from == old or o.from == first then o.from = full end
	end
	if ns.UI and ns.UI.Dirty then ns.UI.Dirty() end
	if ns.Mini and ns.Mini.Update then ns.Mini.Update() end
end

-- Versucht, den vollen Namen ueber die Spiel-APIs zu ermitteln (liefert nur etwas, wenn dort der Nachname steht).
function ns.ResolveSelf()
	local first = UnitName("player")
	if not first then return false end
	local cands = {}
	if GetUnitName then cands[#cands + 1] = GetUnitName("player", true) end
	if UnitFullName then cands[#cands + 1] = (UnitFullName("player")) end
	for _, c in ipairs(cands) do
		local s = c and ns.ShortName(c)
		if s and s ~= first and s:sub(1, #first + 1) == first .. " " then
			ns.SetFullName(s)
			return true
		end
	end
	return false
end

-- Datenbank: chars[name] = { class, updated, profs = { [key] = { name, rank, max, recipes = { [id] = { out, r = { {itemID, count}, ... } } } } } }
local function initDB()
	CraftShareDB = CraftShareDB or {}
	local db = CraftShareDB
	db.chars = db.chars or {}
	db.friends = db.friends or {}
	if db.autoSync == nil then db.autoSync = true end
	ns.db = db
	-- Einmalige Bereinigung (Version 2): Der volle Name war account-weit gespeichert, dadurch bekamen Zweitcharaktere
	-- die Daten eines anderen Charakters. Die Daten der eigenen Charaktere werden verworfen und beim naechsten
	-- Oeffnen der Berufsfenster neu eingelesen; die Daten anderer Spieler bleiben.
	if (db.ver or 0) < 2 then
		for name in pairs(db.myChars or {}) do db.chars[name] = nil end
		local first0 = UnitName("player")
		if first0 then db.chars[first0] = nil end
		db.myChars = {}
		db.fullName = nil
		db.fullNames = {}
		db.ver = 2
	end
	db.fullNames = db.fullNames or {}
	ns.fullName = UnitName("player") and db.fullNames[UnitName("player")] or nil
	-- Alle Charaktere dieses Accounts (die SavedVariables gelten fuer den ganzen Account)
	db.myChars = db.myChars or {}
	local first = UnitName("player")
	if first then db.myChars[first] = true end
	for _, full in pairs(db.fullNames) do db.myChars[full] = true end
	-- Altlasten: Eintraege mit Realm im Namen ("Name-Realm") auf den Namen ohne Realm zusammenfuehren.
	local fix = {}
	for name in pairs(db.chars) do
		local s = ns.ShortName(name)
		if s ~= name then fix[#fix + 1] = { name, s } end
	end
	for _, f in ipairs(fix) do
		if not db.chars[f[2]] then db.chars[f[2]] = db.chars[f[1]] end
		db.chars[f[1]] = nil
	end
	-- Altlast: Sammelberufe (Kuerschnerei usw.) haben keine Rezepte und gehoeren nicht in die Daten
	for _, c in pairs(db.chars) do
		for k, p in pairs(c.profs or {}) do
			-- auch Eintraege ohne Namen (falsch gelesenes Berufsfenster) fliegen raus
			if not ns.IsCrafting(p.name) then c.profs[k] = nil end
		end
	end
	local fixF = {}
	for name in pairs(db.friends) do
		local s = ns.ShortName(name)
		if s ~= name then fixF[#fixF + 1] = { name, s } end
	end
	for _, f in ipairs(fixF) do
		db.friends[f[2]] = true
		db.friends[f[1]] = nil
	end
end

-- Berufe ohne Rezepte (Sammelberufe) tauchen im Addon nicht auf.
local NO_RECIPES = { "kürschner", "skinning", "kräuter", "herbal", "angeln", "fishing" }
function ns.IsCrafting(name)
	if not name or name == "" then return false end
	local l = name:lower()
	for _, p in ipairs(NO_RECIPES) do
		if l:find(p, 1, true) then return false end
	end
	return true
end

-- Gehoert dieser Charakter zu meinem Account? (dann liegen seine Daten in denselben SavedVariables)
function ns.IsMine(name)
	return name ~= nil and ns.db.myChars ~= nil and ns.db.myChars[name] == true
end

function ns.GetChar(name, create)
	local c = ns.db.chars[name]
	if not c and create then
		c = { profs = {}, updated = 0 }
		ns.db.chars[name] = c
	end
	return c
end

-- Item- bzw. Rezeptname ueber die Spiel-APIs (kann beim ersten Aufruf noch nil sein).
function ns.ItemName(itemID)
	if not itemID then return nil end
	local name
	if C_Item and C_Item.GetItemNameByID then
		local ok, n = pcall(C_Item.GetItemNameByID, itemID)
		if ok then name = n end
	end
	if not name and GetItemInfo then
		local ok, n = pcall(GetItemInfo, itemID)
		if ok then name = n end
	end
	if not name and C_Item and C_Item.RequestLoadItemDataByID then
		pcall(C_Item.RequestLoadItemDataByID, itemID)
	end
	return name
end

-- Bestand eines Gegenstands (Taschen, mit bank=true auch Bank). Neuere Clients kennen nur C_Item.GetItemCount.
function ns.ItemCount(itemID, bank)
	local get = (C_Item and C_Item.GetItemCount) or GetItemCount
	if not get or not itemID then return 0 end
	return get(itemID, bank and true or false) or 0
end

function ns.ItemIcon(itemID)
	if not itemID then return nil end
	if C_Item and C_Item.GetItemIconByID then
		local ok, i = pcall(C_Item.GetItemIconByID, itemID)
		if ok and i then return i end
	end
	if GetItemIcon then
		local ok, i = pcall(GetItemIcon, itemID)
		if ok and i then return i end
	end
	return "Interface\\Icons\\INV_Misc_QuestionMark"
end

function ns.SpellName(id)
	if not id then return nil end
	if C_Spell and C_Spell.GetSpellName then
		local ok, n = pcall(C_Spell.GetSpellName, id)
		if ok and n then return n end
	end
	if GetSpellInfo then
		local ok, n = pcall(GetSpellInfo, id)
		if ok and type(n) == "string" then return n end
	end
	return nil
end

-- Anzeigename eines Rezepts: Ergebnis-Item, sonst Zaubername (Verzauberungen), sonst ID.
function ns.RecipeName(id, rec)
	local n = rec and rec.out and rec.out > 0 and ns.ItemName(rec.out)
	return n or ns.SpellName(id) or ("[" .. tostring(id) .. "]")
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, ev, name)
	if name ~= ADDON then return end
	self:UnregisterEvent("ADDON_LOADED")
	initDB()
	if ns.Comm and ns.Comm.Init then ns.Comm.Init() end
	if ns.Scan and ns.Scan.Init then ns.Scan.Init() end
	if ns.Orders and ns.Orders.Init then ns.Orders.Init() end
	if ns.Mini and ns.Mini.Init then ns.Mini.Init() end
	C_Timer.After(2, ns.ResolveSelf)
end)

SLASH_CRAFTSHARE1 = "/cs"
SLASH_CRAFTSHARE2 = "/craftshare"
SlashCmdList["CRAFTSHARE"] = function(msg)
	msg = strtrim(msg or "")
	local cmd, rest = msg:match("^(%S+)%s*(.-)$")
	cmd = cmd and cmd:lower() or ""
	if cmd == "" or cmd == "show" or cmd == "toggle" then
		ns.UI.Toggle()
	elseif cmd == "add" then
		if rest == "" then return ns.Print(T("Aufruf: /cs add <Name> (Freund, der CraftShare nutzt)", "Usage: /cs add <name> (a friend running CraftShare)")) end
		ns.db.friends[ns.ShortName(rest)] = true
		ns.Print(T("Freund hinzugefügt: ", "Friend added: ") .. ns.ShortName(rest))
		ns.Comm.Request("WHISPER", ns.ShortName(rest))
		ns.Comm.SendOwn("WHISPER", ns.ShortName(rest))
	elseif cmd == "remove" or cmd == "del" then
		ns.db.friends[ns.ShortName(rest)] = nil
		ns.Print(T("Freund entfernt: ", "Friend removed: ") .. ns.ShortName(rest))
	elseif cmd == "friends" then
		local t = {}
		for n in pairs(ns.db.friends) do t[#t + 1] = n end
		table.sort(t)
		ns.Print(T("Freunde: ", "Friends: ") .. (#t > 0 and table.concat(t, ", ") or "-"))
	elseif cmd == "sync" then
		ns.Comm.Request()
		ns.Comm.SendOwn()
		ns.Print(T("Synchronisation angefordert.", "Sync requested."))
	elseif cmd == "post" then
		ns.Mail.Debug()
	elseif cmd == "ah" then
		ns.Prices.Debug()
	elseif cmd == "debug" then
		ns.Scan.Debug()
	elseif cmd == "mini" then
		ns.Mini.Command(rest)
	elseif cmd == "order" or cmd == "bestellen" then
		ns.Orders.OpenOrder()
	elseif cmd == "orders" or cmd == "auftraege" then
		ns.Orders.OpenList()
	elseif cmd == "scan" then
		ns.Scan.Run(true)
	elseif cmd == "forget" then
		local n = ns.ShortName(rest)
		if n ~= "" and ns.db.chars[n] and n ~= ns.Me() then
			ns.db.chars[n] = nil
			ns.Print(T("Gelöscht: ", "Removed: ") .. n)
			if ns.UI.Refresh then ns.UI.Refresh() end
		else
			ns.Print(T("Aufruf: /cs forget <Name> (nicht der eigene Charakter)", "Usage: /cs forget <name> (not your own character)"))
		end
	elseif cmd == "auto" then
		ns.db.autoSync = (rest ~= "off")
		ns.Print("Auto-Sync: " .. (ns.db.autoSync and "on" or "off"))
	else
		ns.Print("/cs - " .. T("Fenster", "window"))
		ns.Print("/cs scan - " .. T("eigene Berufe erneut einlesen (Berufsfenster vorher öffnen)", "rescan own professions (open the profession window first)"))
		ns.Print("/cs sync - " .. T("Daten anfordern und senden", "request and send data"))
		ns.Print("/cs add|remove <Name>, /cs friends - " .. T("Freunde außerhalb der Gilde", "friends outside the guild"))
		ns.Print("/cs forget <Name>, /cs auto on|off")
	end
end

-- ---------------------------------------------------------------- Tastenbelegung
BINDING_HEADER_CRAFTSHARE = "CraftShare"
BINDING_NAME_CRAFTSHARE_TOGGLE = ns.T("Fenster ein-/ausblenden", "Toggle window")

function CraftShare_Toggle()
	if ns.UI and ns.UI.Toggle then ns.UI.Toggle() end
end

-- Standard: Taste G, einmalig beim ersten Start (spaetere Aenderungen des Spielers bleiben erhalten)
local keyFrame = CreateFrame("Frame")
keyFrame:RegisterEvent("PLAYER_LOGIN")
keyFrame:SetScript("OnEvent", function(self)
	self:UnregisterAllEvents()
	if not ns.db or ns.db.keyBound then return end
	if InCombatLockdown() then return end
	ns.db.keyBound = true
	local old = GetBindingAction("G")
	SetBinding("G", "CRAFTSHARE_TOGGLE")
	if old and old ~= "" and old ~= "CRAFTSHARE_TOGGLE" then
		ns.Print(ns.T("Taste G öffnet jetzt CraftShare (vorher belegt mit: ", "Key G now opens CraftShare (was bound to: ") .. old .. ")")
	end
	if SaveBindings and GetCurrentBindingSet then SaveBindings(GetCurrentBindingSet()) end
end)
