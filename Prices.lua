-- Preise: Auctionator / TradeSkillMaster / eigener Auktionshaus-Scan, Haendlerpreise,
-- guenstigster Weg je Material (kaufen am AH, beim Haendler oder ueber die Herstellungskette).
local ADDON, ns = ...
local T = ns.T

local P = {}
ns.Prices = P

local producers = {}
local memo, busy = {}, {}

local DEFAULTS = { source = "latest", ptype = "min", vendor = true, chain = true, show = true, free = false }
local SCRAP_ID = 2934 -- Verdorbene Lederfetzen

local function usesScraps(prod)
	for _, r in ipairs(prod.r) do
		if r[1] == SCRAP_ID then return true end
	end
	return false
end

function P.UsesScraps(prod) return usesScraps(prod) end

-- Hat eine eigene Figur Lederverarbeitung?
local SOURCES = { "latest", "auctionator", "tsm", "scan" }

function P.SourceLabel(s)
	if s == "latest" then return T("Aktuellste (automatisch)", "Newest (automatic)") end
	if s == "auctionator" then return "Auctionator" end
	if s == "tsm" then return "TradeSkillMaster" end
	return T("Eigener Scan", "Own scan")
end

function P.Settings()
	ns.db.pset = ns.db.pset or {}
	local s = ns.db.pset
	for k, v in pairs(DEFAULTS) do
		if s[k] == nil then s[k] = v end
	end
	return s
end

function P.CycleSource()
	local s = P.Settings()
	for i, k in ipairs(SOURCES) do
		if k == s.source then s.source = SOURCES[i % #SOURCES + 1] return end
	end
	s.source = "latest"
end

function P.SetProducers(t) producers = t or {} end
function P.Begin() memo, busy = {}, {} end

-- ---------------------------------------------------------------- Formatierung
function P.Money(c)
	if not c then return "–" end
	c = math.floor(c + 0.5)
	local g, s, k = math.floor(c / 10000), math.floor(c % 10000 / 100), c % 100
	local out = {}
	if g > 0 then out[#out + 1] = "|cffffd24a" .. g .. "g|r" end
	if g > 0 or s > 0 then out[#out + 1] = "|cffd0d6dc" .. s .. "s|r" end
	if g == 0 or k > 0 then out[#out + 1] = "|cffd9915a" .. k .. "k|r" end
	return table.concat(out, " ")
end

-- ---------------------------------------------------------------- Quellen
local function refreshAHButton()
	local b = P.ahButton
	if not b then return end
	local bar = P.ahBar
	local parent = bar and bar.ahParent
	if bar and parent then bar:SetShown(parent:IsShown()) end
	local txt = P.scanning and T("Scan abbrechen", "Cancel scan") or T("Berufe-Preise scannen", "Scan profession prices")
	if b.label then b.label:SetText(txt) end
	local pct = P.scanning and tonumber((P.progress or ""):match("(%d+) %%"))
	if bar then
		if P.scanning then
			bar.fill:SetWidth(math.max(1, math.floor(bar.fillMax * (pct or 0) / 100)))
			bar.fill:Show()
			bar.txt:SetText(pct and (pct .. " %") or (P.progress or ""))
		else
			bar.fill:Hide()
			local n, t = P.ScanInfo()
			bar.txt:SetText(n > 0 and (T("Letzter Scan: ", "Last scan: ") .. date("%d.%m. %H:%M", t)) or T("noch kein Scan", "no scan yet"))
		end
	end
end

function P.Notify()
	refreshAHButton()
	if ns.UI and ns.UI.Dirty then ns.UI.Dirty() end
end

-- Auktionshaus-Fenster finden (Standardnamen, sonst ein grosses sichtbares Fenster mit "Auction" im Namen)
function P.FindAHFrame()
	local f = _G.AuctionHouseFrame or _G.AuctionFrame
	if f then return f end
	local best, bw = nil, 0
	for _, c in ipairs({ UIParent:GetChildren() }) do
		-- geschuetzte Fenster des Spiels duerfen Fehler werfen, die uns nicht interessieren
		pcall(function()
			local n = c:GetName()
			if n and n:find("Auction") and c:IsShown() and c:GetWidth() > bw and c:GetWidth() > 400 then best, bw = c, c:GetWidth() end
		end)
	end
	return best
end

-- Leiste mit Knopf und Fortschritt, ausserhalb ueber dem Auktionshaus-Fenster
local function ensureAHButtonInner()
	if P.ahButton then return end
	local parent = P.FindAHFrame()
	if not parent or not (ns.UIK and ns.UIK.Box and ns.UIK.Btn) then return end
	local K = ns.UIK
	local bar = K.Box(UIParent, K.COL.panel, K.COL.border)
	bar:SetSize(370, 28)
	bar:SetPoint("BOTTOMLEFT", parent, "TOPLEFT", 0, 3)
	bar:SetFrameStrata(parent:GetFrameStrata())
	bar:SetFrameLevel(parent:GetFrameLevel() + 5)
	bar.ahParent = parent
	local b = K.Btn(bar, "", 190, 20, function() P.StartScan() end, 11)
	b:SetPoint("LEFT", 4, 0)
	-- Fortschrittsbalken
	local track = bar:CreateTexture(nil, "ARTWORK")
	track:SetPoint("LEFT", b, "RIGHT", 8, 0)
	track:SetSize(160, 14)
	track:SetColorTexture(0.06, 0.047, 0.035, 1)
	bar.fillMax = 158
	bar.fill = bar:CreateTexture(nil, "OVERLAY")
	bar.fill:SetPoint("LEFT", track, "LEFT", 1, 0)
	bar.fill:SetHeight(12)
	bar.fill:SetColorTexture(0.31, 0.82, 0.35, 0.9)
	bar.fill:Hide()
	bar.txt = bar:CreateFontString(nil, "OVERLAY")
	bar.txt:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
	bar.txt:SetPoint("CENTER", track, "CENTER", 0, 0)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine("Guild CraftShare", 1, 0.82, 0.2)
		GameTooltip:AddLine(T("Liest die Preise aller Rohstoffe und Produkte der bekannten Rezepte ein.", "Reads prices of all materials and products of known recipes."), 1, 1, 1, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	P.ahBar = bar
	P.ahButton = b
	refreshAHButton()
end

local function hasAuctionator()
	local A = _G.Auctionator
	return A and A.API and A.API.v1 and A.API.v1.GetAuctionPriceByItemID and true or false
end
local function hasTSM()
	return _G.TSM_API and _G.TSM_API.GetCustomPriceValue and true or false
end

local function fromAuctionator(id)
	if not hasAuctionator() then return nil end
	local ok, v = pcall(_G.Auctionator.API.v1.GetAuctionPriceByItemID, "CraftShare", id)
	if ok and type(v) == "number" and v > 0 then return v end
end

local function fromTSM(id)
	if not hasTSM() then return nil end
	local src = (P.Settings().ptype == "market") and "DBMarket" or "DBMinBuyout"
	local ok, v = pcall(_G.TSM_API.GetCustomPriceValue, src, "i:" .. id)
	if ok and type(v) == "number" and v > 0 then return v end
end

local function fromScan(id)
	local e = ns.db.prices and ns.db.prices[id]
	if e and e.p then return e.p, e.t end
end

-- Auktionshaus-Einzelpreis nach gewaehlter Quelle: preis, quellenname
function P.AH(id)
	if not id or id <= 0 then return nil end
	local src = P.Settings().source
	if src == "auctionator" then local v = fromAuctionator(id) return v, v and "Auctionator" end
	if src == "tsm" then local v = fromTSM(id) return v, v and "TSM" end
	if src == "scan" then local v = fromScan(id) return v, v and T("Scan", "Scan") end
	-- aktuellste: die Quelle mit dem juengsten Datenstand gewinnt
	local sp, st = fromScan(id)
	local best, bp, bn, bt = nil, nil, nil, -1
	local function try(v, name, t)
		if v and (t or 0) > bt then bp, bn, bt = v, name, t or 0 end
	end
	try(sp, T("Scan", "Scan"), st)
	try(fromAuctionator(id), "Auctionator", P.SourceTime("auctionator"))
	try(fromTSM(id), "TSM", P.SourceTime("tsm"))
	if bp then return bp, bn end
end

function P.Vendor(id)
	if not P.Settings().vendor then return nil end
	local v = ns.db.vendor and ns.db.vendor[id]
	if v and v > 0 then return v end
end

-- Guenstigster Kaufpreis: AH oder Haendler
function P.Buy(id)
	local a = P.AH(id)
	local v = P.Vendor(id)
	if a and v then
		if v <= a then return v, "vendor" end
		return a, "ah"
	end
	if v then return v, "vendor" end
	if a then return a, "ah" end
end

-- Guenstigster Weg fuer 1 Stueck: { unit = Kupfer, how = "ah"|"vendor"|"make", prod = Rezept } oder nil
function P.Unit(id, depth)
	depth = depth or 0
	local m = memo[id]
	if m ~= nil then return m or nil end
	local best
	local bp, how = P.Buy(id)
	if bp then best = { unit = bp, how = how } end
	local ps = P.Settings()
	local prod = ps.chain and producers[id]
	if prod and usesScraps(prod) then prod = nil end
	if prod and depth < 4 and not busy[id] and #prod.r > 0 then
		busy[id] = true
		local total, ok = 0, true
		for _, r in ipairs(prod.r) do
			local u = P.Unit(r[1], depth + 1)
			if not u then ok = false break end
			total = total + u.unit * r[2]
		end
		busy[id] = nil
		if ok then
			local per = total / (prod.q or 1)
			if not best or per < best.unit then best = { unit = per, how = "make", prod = prod } end
		end
	end
	memo[id] = best or false
	return best
end

-- Vergleich je Stueck fuer ein Material: AH, Haendler, Herstellen (jeweils nil, wenn nicht moeglich) und der billigste Weg
function P.Compare(id)
	local ah = P.AH(id)
	local vend = P.Vendor(id)
	local make
	local ps = P.Settings()
	local prod = ps.chain and producers[id]
	if prod and usesScraps(prod) then prod = nil end
	if prod and #prod.r > 0 then
		local total, ok = 0, true
		for _, r in ipairs(prod.r) do
			local u = P.Unit(r[1], 1)
			if not u then ok = false break end
			total = total + u.unit * r[2]
		end
		if ok then make = total / (prod.q or 1) end
	end
	local best, bv
	for _, k in ipairs({ "ah", "vendor", "make" }) do
		local v = (k == "ah" and ah) or (k == "vendor" and vend) or make
		if v and (not bv or v < bv) then best, bv = k, v end
	end
	return { ah = ah, vendor = vend, make = make, best = best }
end

-- Kosten eines Rezepts: total, anzahlOhnePreis, zeilen
function P.RecipeCost(rec)
	local free = P.Settings().free
	local total, unk, lines = 0, 0, {}
	for i, r in ipairs(rec.r) do
		local id, q = r[1], r[2]
		local have = ns.ItemCount(id, true)
		local pay = free and math.max(0, q - have) or q
		local u = P.Unit(id)
		local ln = { id = id, q = q, have = have, u = u }
		if u then
			ln.sum = u.unit * pay
			total = total + ln.sum
		else
			unk = unk + 1
		end
		lines[i] = ln
	end
	return total, unk, lines
end

-- ---------------------------------------------------------------- Status
local function agoText(sec)
	local k = ns.UIK and ns.UIK.ago
	return k and k(sec) or (math.floor(sec / 60) .. " min")
end

function P.ScanInfo()
	local n, newest = 0, 0
	for _, e in pairs(ns.db.prices or {}) do
		n = n + 1
		if e.t and e.t > newest then newest = e.t end
	end
	return n, newest
end

-- Text fuer die Statuszeile unter dem Kopf: text, ok
-- TSM nennt das Alter seiner Daten nur im Gegenstands-Tooltip ("... (vor 45 Min. 44 Sek.)"): dort auslesen.
local tsmCache = { t = nil, at = 0 }
local function secondsFrom(txt)
	local sec, found = 0, false
	for num, unit in txt:gmatch("(%d+)%s*([%a%.]+)") do
		num = tonumber(num)
		local u = unit:lower()
		if u:find("^tag") or u:find("^tg") or u:find("^day") or u:find("^d$") then sec = sec + num * 86400 found = true
		elseif u:find("^std") or u:find("^h") then sec = sec + num * 3600 found = true
		elseif u:find("^min") then sec = sec + num * 60 found = true
		elseif u:find("^sek") or u:find("^sec") or u:find("^s") then sec = sec + num found = true end
	end
	return found and sec or nil
end

local function tsmTime()
	if not hasTSM() then return nil end
	if GetTime() - tsmCache.at < 60 then return tsmCache.t end
	if not (GameTooltip and GameTooltip.SetHyperlink) or GameTooltip:IsShown() then return tsmCache.t end
	tsmCache.at = GetTime()
	tsmCache.t = nil
	-- Beispiel-Gegenstaende: Reagenzien bekannter Rezepte
	local tried = 0
	for _, c in pairs(ns.db.chars) do
		for _, p in pairs(c.profs) do
			for _, rec in pairs(p.recipes or {}) do
				local r = rec.r and rec.r[1]
				if r and tried < 6 then
					tried = tried + 1
					GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
					GameTooltip:SetHyperlink("item:" .. r[1])
					for i = 1, GameTooltip:NumLines() do
						for _, side in ipairs({ "Left", "Right" }) do
							local fs = _G["GameTooltipText" .. side .. i]
							local txt = fs and fs:GetText()
							if txt then
								txt = txt:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
								local inner = txt:match("%((vor [^%)]+)%)") or txt:match("%((%d+[^%)]*ago)%)")
								if inner then
									local sec = secondsFrom(inner)
									if sec then
										GameTooltip:Hide()
										tsmCache.t = time() - sec
										return tsmCache.t
									end
								end
							end
						end
					end
					GameTooltip:Hide()
				end
			end
		end
		if tried >= 6 then break end
	end
	return nil
end

-- Zeitpunkt der letzten Aktualisierung je Quelle (nil = unbekannt)
local function sourceTime(src)
	if src == "scan" then
		local n, t = P.ScanInfo()
		return n > 0 and t or nil
	elseif src == "auctionator" then
		local st = _G.Auctionator and _G.Auctionator.SavedState
		if type(st) ~= "table" then return nil end
		local best
		for _, k in ipairs({ "TimeOfLastBrowseScan", "TimeOfLastGetAllScan", "TimeOfLastReplicateScan", "TimeOfLastScan" }) do
			local v = st[k]
			if type(v) == "number" and v > 0 and (not best or v > best) then best = v end
		end
		return best
	elseif src == "tsm" then
		return tsmTime()
	end
	return nil
end

P.SourceTime = sourceTime

-- Welche Quelle gilt gerade (bei "Aktuellste" nach derselben Regel wie P.AH)
local function effectiveSource()
	local src = P.Settings().source
	if src ~= "latest" then return src end
	local n = P.ScanInfo()
	local best, bt = "none", -1
	local function try(name, ok)
		if not ok then return end
		local t = sourceTime(name) or 0
		if t > bt then best, bt = name, t end
	end
	try("scan", n > 0)
	try("auctionator", hasAuctionator())
	try("tsm", hasTSM())
	return best
end

-- Text fuer die Statuszeile unter dem Kopf: text, ok
function P.StatusText()
	local s = P.Settings()
	if not s.show then return T("Preise ausgeblendet (Optionen)", "Prices hidden (options)"), true end
	local eff = effectiveSource()
	local avail = (eff == "scan" and P.ScanInfo() > 0) or (eff == "auctionator" and hasAuctionator()) or (eff == "tsm" and hasTSM())
	if not avail then
		local vendorN = 0
		for _ in pairs(ns.db.vendor or {}) do vendorN = vendorN + 1 end
		local txt = T("Keine Preisdaten – im Auktionshaus scannen", "No price data – scan at the auction house")
		if s.vendor and vendorN > 0 then txt = txt .. T(" (Händlerpreise werden genutzt)", " (vendor prices in use)") end
		return txt, false
	end
	local label = P.SourceLabel(eff)
	if s.source == "latest" then label = P.SourceLabel("latest"):gsub(" %(.-%)", "") .. " (" .. label .. ")" end
	local t = sourceTime(eff)
	local stand = T("unbekannt", "unknown")
	if t then
		local d = math.max(0, time() - t)
		local rel
		if d < 60 then rel = T("vor wenigen Sekunden aktualisiert", "updated moments ago")
		elseif d < 3600 then
			local m = math.floor(d / 60)
			rel = T("vor " .. m .. (m == 1 and " Minute" or " Minuten") .. " aktualisiert", "updated " .. m .. (m == 1 and " minute" or " minutes") .. " ago")
		elseif d < 86400 then
			local h = math.floor(d / 3600)
			rel = T("vor " .. h .. (h == 1 and " Stunde" or " Stunden") .. " aktualisiert", "updated " .. h .. (h == 1 and " hour" or " hours") .. " ago")
		else
			local dd = math.floor(d / 86400)
			rel = T("vor " .. dd .. (dd == 1 and " Tag" or " Tagen") .. " aktualisiert", "updated " .. dd .. (dd == 1 and " day" or " days") .. " ago")
		end
		stand = date("%d.%m.%Y %H:%M", t) .. " (" .. rel .. ")"
	end
	local txt = T("Preise: ", "Prices: ") .. "|cfff1ebe0" .. label .. "|r · " .. T("Stand: ", "As of: ") .. stand
	return txt, true
end

local function ensureAHButton()
	local ok, err = pcall(ensureAHButtonInner)
	if not ok then P.ahErr = tostring(err) else P.ahErr = nil end
end

-- Diagnose-Zeile fuer die Optionen (ohne Chatbefehl lesbar)
function P.DiagText()
	local f = P.FindAHFrame()
	local api = (_G.C_AuctionHouse and C_AuctionHouse.SendBrowseQuery) and "neu" or ((QueryAuctionItems and "alt") or "keine")
	local b = P.ahButton
	local info = b and string.format("Knopf: ja (%s, Stufe %d, %s)", b:IsShown() and "sichtbar" or "verborgen", b:GetFrameLevel(), b:GetFrameStrata()) or "Knopf: nein"
	return string.format("AH-Fenster: %s · Schnittstelle: %s · %s · Takt: %d%s", f and (f:GetName() or "?") or "nicht gefunden", api, info, P.ticks or 0, P.ahErr and (" · Fehler: " .. P.ahErr) or "")
end

-- Fuer die Optionen: welche Preisdaten die neuesten sind und von wann
function P.NewestText()
	local best, bt
	local function try(name, ok)
		if not ok then return end
		local t = sourceTime(name)
		if t and (not bt or t > bt) then best, bt = name, t end
	end
	try("scan", P.ScanInfo() > 0)
	try("auctionator", hasAuctionator())
	try("tsm", hasTSM())
	if not best then
		return T("Noch keine Preisdaten (im Auktionshaus scannen).", "No price data yet (scan at the auction house).")
	end
	local text = T("Aktuellste Preisdaten: ", "Newest price data: ") .. P.SourceLabel(best) .. "\n" ..
		T("Stand: ", "As of: ") .. date("%d.%m. %H:%M", bt) .. " (" .. agoText(math.max(0, time() - bt)) .. ")"
	local used = P.Settings().source
	if used ~= "latest" and used ~= best then text = text .. T(" · verwendet: ", " · in use: ") .. P.SourceLabel(used) end
	return text
end

-- ---------------------------------------------------------------- Haendlerpreise lernen
local function learnMerchant()
	if not (GetMerchantNumItems and GetMerchantItemInfo and GetMerchantItemLink) then return end
	ns.db.vendor = ns.db.vendor or {}
	local changed = false
	for i = 1, GetMerchantNumItems() do
		local _, _, price, qty, avail, _, extended = GetMerchantItemInfo(i)
		local link = GetMerchantItemLink(i)
		local id = link and tonumber(link:match("item:(%d+)"))
		if id and price and price > 0 and not extended then
			local unit = price / math.max(1, qty or 1)
			if ns.db.vendor[id] ~= unit then ns.db.vendor[id] = unit changed = true end
		end
	end
	if changed and ns.UI and ns.UI.Dirty then ns.UI.Dirty() end
end

-- ---------------------------------------------------------------- Auktionshaus-Scan
local function wantedItems()
	local set, list = {}, {}
	local function add(id)
		if id and id > 0 and not set[id] then set[id] = true list[#list + 1] = id end
	end
	for _, c in pairs(ns.db.chars) do
		for _, p in pairs(c.profs) do
			for _, rec in pairs(p.recipes or {}) do
				for _, r in ipairs(rec.r) do add(r[1]) end
			end
		end
	end
	-- Ergebnisse (Zwischenprodukte und Kaufpreis des fertigen Gegenstands)
	local reagents = #list
	for _, c in pairs(ns.db.chars) do
		for _, p in pairs(c.profs) do
			for _, rec in pairs(p.recipes or {}) do add(rec.out) end
		end
	end
	return set, list, reagents
end

local function finish(msg)
	P.scanning = false
	P.progress = nil
	P.queue = nil
	if msg then print("|cffffd24aGuild CraftShare:|r " .. msg) end
	P.Notify()
end

local function store(id, unit)
	ns.db.prices = ns.db.prices or {}
	ns.db.prices[id] = { p = unit, t = time() }
end

local function itemIdOfAuction(i)
	local r = { GetAuctionItemInfo("list", i) }
	local id = r[17]
	if not id or id == 0 then
		local link = GetAuctionItemLink and GetAuctionItemLink("list", i)
		id = link and tonumber(link:match("item:(%d+)"))
	end
	return id, r[3], r[10]
end

-- Komplett-Scan (ein Aufruf, alle Auktionen); Verarbeitung in Haeppchen
local function processAll(set)
	local num = GetNumAuctionItems("list")
	local best = {}
	local i = 1
	local function step()
		if not P.scanning then return end
		local stop = math.min(num, i + 799)
		while i <= stop do
			local id, count, buyout = itemIdOfAuction(i)
			if id and set[id] and buyout and buyout > 0 then
				local unit = buyout / math.max(1, count or 1)
				if not best[id] or unit < best[id] then best[id] = unit end
			end
			i = i + 1
		end
		P.progress = string.format(T("Auswertung %d %%", "Processing %d %%"), math.floor(math.min(i, num) / math.max(1, num) * 100))
		if i <= num then
			C_Timer.After(0, step)
		else
			local n = 0
			for id, unit in pairs(best) do store(id, unit) n = n + 1 end
			finish(string.format(T("AH-Scan fertig: %d Preise gespeichert.", "AH scan finished: %d prices stored."), n))
		end
	end
	step()
end

local startModern
local function nextItem()
	if not P.scanning then return end
	local q = P.queue
	if not q or #q.list == 0 then
		finish(string.format(T("AH-Scan fertig: %d Preise gespeichert.", "AH scan finished: %d prices stored."), q and q.found or 0))
		return
	end
	if not P.IsAHOpen() then finish(T("AH-Scan abgebrochen (Auktionshaus geschlossen).", "AH scan cancelled (auction house closed).")) return end
	local id = table.remove(q.list)
	local name = ns.ItemName(id)
	q.total = q.total or #q.list + 1
	P.progress = string.format("Scan %d %%", math.floor((q.total - #q.list) / math.max(1, q.total) * 100))
	P.Notify()
	if not name or name == "" or name:find("^item:") then C_Timer.After(0.05, nextItem) return end
	q.id, q.name = id, name
	local waited = 0
	local function try()
		if not P.scanning then return end
		if CanSendAuctionQuery and CanSendAuctionQuery() then
			q.waiting = true
			q.stamp = GetTime()
			QueryAuctionItems(name, nil, nil, 0, false, 0, false, true)
			-- Sicherheitsnetz, falls kein Ergebnis-Ereignis kommt
			local token = q.stamp
			C_Timer.After(6, function()
				if P.scanning and q.waiting and q.stamp == token then q.waiting = false nextItem() end
			end)
		else
			waited = waited + 0.3
			if waited > 20 then nextItem() else C_Timer.After(0.3, try) end
		end
	end
	try()
end

local function onListUpdate()
	if not P.scanning then return end
	if P.mass then
		if P.massWait then
			P.massWait = false
			local set = P.massSet
			processAll(set)
		end
		return
	end
	local q = P.queue
	if not q or not q.waiting then return end
	q.waiting = false
	local num = GetNumAuctionItems("list")
	local best
	for i = 1, num do
		local id, count, buyout = itemIdOfAuction(i)
		if id == q.id and buyout and buyout > 0 then
			local unit = buyout / math.max(1, count or 1)
			if not best or unit < best then best = unit end
		end
	end
	if best then store(q.id, best) q.found = (q.found or 0) + 1 end
	C_Timer.After(0.35, nextItem)
end

function P.IsAHOpen()
	if P.ahOpen then return true end
	local f = P.FindAHFrame()
	return f and f.IsShown and f:IsShown() and true or false
end

-- Neues Auktionshaus (C_AuctionHouse): Durchsuchen ohne Suchtext liefert je Gegenstand den Mindestpreis
local function processModern()
	local set = P.modernSet or {}
	local best = {}
	for _, r in ipairs(C_AuctionHouse.GetBrowseResults() or {}) do
		local id = r.itemKey and r.itemKey.itemID
		local mp = r.minPrice
		if id and set[id] and mp and mp > 0 and (not best[id] or mp < best[id]) then best[id] = mp end
	end
	local n = 0
	for id, unit in pairs(best) do store(id, unit) n = n + 1 end
	local total = #(C_AuctionHouse.GetBrowseResults() or {})
	if total > 0 then ns.db.lastScanTotal = total end
	finish(string.format(T("AH-Scan fertig: %d Preise gespeichert.", "AH scan finished: %d prices stored."), n))
end

local function modernProgress()
	local res = C_AuctionHouse.GetBrowseResults() or {}
	local expected = ns.db.lastScanTotal
	if expected and expected > 0 then
		P.progress = string.format("Scan %d %%", math.min(99, math.floor(#res / expected * 100)))
	else
		P.progress = string.format(T("Scan: %d geladen", "Scan: %d loaded"), #res)
	end
	P.loaded = #res
	P.modernStamp = GetTime()
	local token = P.modernStamp
	-- Sicherheitsnetz: kommt nichts mehr, mit den bisherigen Daten auswerten
	C_Timer.After(12, function()
		if P.scanning and P.mass == "modern" and P.modernStamp == token then processModern() end
	end)
	P.Notify()
end

local function onModernUpdate()
	if not (P.scanning and P.mass == "modern") then return end
	if C_AuctionHouse.HasFullBrowseResults and C_AuctionHouse.HasFullBrowseResults() then
		processModern()
		return
	end
	modernProgress()
	C_AuctionHouse.RequestMoreBrowseResults()
end

startModern = function(set)
	P.mass, P.modernSet = "modern", set
	P.progress = T("Scan startet …", "Scan starting …")
	local sorts = {}
	if Enum and Enum.AuctionHouseSortOrder then sorts[1] = { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } end
	C_AuctionHouse.SendBrowseQuery({ searchString = "", sorts = sorts, filters = {}, itemClassFilters = {} })
	modernProgress()
end

function P.StartScan()
	if P.scanning then
		finish(T("AH-Scan abgebrochen.", "AH scan cancelled."))
		return
	end
	if not P.IsAHOpen() then
		print("|cffffd24aGuild CraftShare:|r " .. T("Bitte zuerst das Auktionshaus öffnen.", "Please open the auction house first."))
		return
	end
	local modern = _G.C_AuctionHouse and C_AuctionHouse.SendBrowseQuery and C_AuctionHouse.GetBrowseResults
	if not modern and not (QueryAuctionItems and GetNumAuctionItems and GetAuctionItemInfo) then
		print("|cffffd24aGuild CraftShare:|r " .. T("Auktionshaus-Schnittstelle nicht verfügbar.", "Auction house API not available."))
		return
	end
	local set, list, reagentN = wantedItems()
	if #list == 0 then
		print("|cffffd24aGuild CraftShare:|r " .. T("Keine Rezepte bekannt – es gibt nichts zu scannen.", "No known recipes – nothing to scan."))
		return
	end
	P.scanning = true
	if modern then
		startModern(set)
		return
	end
	local canQuery, canMass = true, false
	if CanSendAuctionQuery then canQuery, canMass = CanSendAuctionQuery() end
	if canMass then
		P.mass, P.massWait, P.massSet = true, true, set
		P.progress = T("Komplett-Scan läuft …", "Full scan running …")
		QueryAuctionItems("", nil, nil, 0, false, 0, true, false)
	else
		P.mass = false
		-- zuerst die Rohstoffe, dann die Ergebnisse; begrenzt, damit der Scan nicht ewig dauert
		local q = { list = {}, found = 0 }
		local cap = math.min(#list, 400)
		for i = cap, 1, -1 do q.list[#q.list + 1] = list[i] end
		-- table.remove nimmt das letzte Element: Reihenfolge so umgekehrt, dass Rohstoffe zuerst drankommen
		P.queue = q
		P.progress = T("Scan startet …", "Scan starting …")
		nextItem()
	end
	P.Notify()
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "AUCTION_ITEM_LIST_UPDATE", "MERCHANT_SHOW", "ADDON_LOADED",
	"AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED", "AUCTION_HOUSE_BROWSE_FAILURE" }) do
	-- unbekannte Ereignisse (je nach Spielversion) duerfen das Laden nicht abbrechen
	pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if tostring(arg1):find("^Blizzard_Auction") or _G.AuctionHouseFrame or _G.AuctionFrame then ensureAHButton() end
		return
	end
	if event == "AUCTION_HOUSE_SHOW" then
		P.ahOpen = true
		ensureAHButton()
		C_Timer.After(0.3, ensureAHButton)
		C_Timer.After(1.5, ensureAHButton)
		P.Notify()
	elseif event == "AUCTION_HOUSE_CLOSED" then
		P.ahOpen = false
		if P.scanning then finish(T("AH-Scan abgebrochen (Auktionshaus geschlossen).", "AH scan cancelled (auction house closed).")) end
	elseif event == "AUCTION_ITEM_LIST_UPDATE" then
		onListUpdate()
	elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
		onModernUpdate()
	elseif event == "AUCTION_HOUSE_BROWSE_FAILURE" then
		if P.scanning and P.mass == "modern" then finish(T("AH-Scan fehlgeschlagen.", "AH scan failed.")) end
	elseif event == "MERCHANT_SHOW" then
		learnMerchant()
	end
end)

-- Falls das Auktionshaus-Fenster erst spaeter oder ohne Ereignis auftaucht: Knopf nachruesten
C_Timer.NewTicker(1, function()
	P.ticks = (P.ticks or 0) + 1
	if not P.ahButton then ensureAHButton() end
	if P.ahButton then refreshAHButton() end
end)

function P.Debug()
	local function say(t) print("|cffffd24aGuild CraftShare AH:|r " .. t) end
	say("AuctionHouseFrame=" .. tostring(_G.AuctionHouseFrame ~= nil) .. " AuctionFrame=" .. tostring(_G.AuctionFrame ~= nil))
	say("C_AuctionHouse=" .. tostring(_G.C_AuctionHouse ~= nil) .. " SendBrowseQuery=" .. tostring(_G.C_AuctionHouse and C_AuctionHouse.SendBrowseQuery ~= nil) .. " QueryAuctionItems=" .. tostring(QueryAuctionItems ~= nil))
	say("IsAHOpen=" .. tostring(P.IsAHOpen()) .. " Button=" .. tostring(P.ahButton ~= nil))
end
