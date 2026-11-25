-- CraftShare: liest die Berufe und Rezepte des eigenen Charakters ein.
local ADDON, ns = ...
local Scan = {}
ns.Scan = Scan

local pending = false

-- Klassische Berufe-API: Kopfzeilen der Rezeptliste sind die Kategorien. Liefert { [rezeptID] = Kategoriename }
-- und die Kategorienamen in Reihenfolge der Liste.
local function classicCategories()
	if not (GetNumTradeSkills and GetTradeSkillInfo and GetTradeSkillRecipeLink) then return nil end
	local map, order, seen, cur = {}, {}, {}, nil
	local n = GetNumTradeSkills() or 0
	for i = 1, n do
		local ok, name, kind = pcall(GetTradeSkillInfo, i)
		if ok and name then
			if kind == "header" then
				cur = name
				if not seen[name] then seen[name] = true; order[#order + 1] = name end
			elseif cur then
				local okl, link = pcall(GetTradeSkillRecipeLink, i)
				local id = okl and link and tonumber(link:match("enchant:(%d+)") or link:match("spell:(%d+)"))
				if id then map[id] = cur end
			end
		end
	end
	if #order == 0 then return nil end
	return map, order
end

local function scanOpenProfession()
	if not (C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeInfo) then return false end
	local base
	if C_TradeSkillUI.GetBaseProfessionInfo then
		local ok, b = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
		if ok and type(b) == "table" then base = b end
	end
	local okIds, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
	if not okIds or type(ids) ~= "table" or #ids == 0 then return false end

	local pname = base and (base.professionName or base.parentProfessionName)
	local pid = base and (base.parentProfessionID or base.professionID)
	if pname == "" then pname = nil end
	-- Name fehlt: ueber die Berufsliste des Charakters nachschlagen (Skill-Linie)
	if not pname and pid and GetProfessions and GetProfessionInfo then
		local list = { GetProfessions() }
		for i = 1, 5 do
			if list[i] then
				local ok, nm, _, _, _, _, _, line = pcall(GetProfessionInfo, list[i])
				if ok and nm and nm ~= "" and tonumber(line) == tonumber(pid) then pname = nm end
			end
		end
	end
	-- ohne Beruf-Namen nichts speichern (das Berufsfenster wechselt gerade)
	if not pname then return false end
	local key = tostring(pid or pname)
	-- Sammelberufe (Kuerschnerei, Kraeuterkunde, Angeln) haben keine Rezepte: ein offenes Berufsfenster
	-- darf nicht als solcher gespeichert werden (sonst landen Rezepte eines anderen Berufs dort).
	if not ns.IsCrafting(pname or key) then return false end

	local recipes, count, cidOf = {}, 0, {}
	for _, id in ipairs(ids) do
		local okr, info = pcall(C_TradeSkillUI.GetRecipeInfo, id)
		if okr and type(info) == "table" and info.learned then
			local rec = { out = 0, r = {} }
			if C_TradeSkillUI.GetRecipeSchematic then
				local oks, s = pcall(C_TradeSkillUI.GetRecipeSchematic, id, false)
				if oks and type(s) == "table" then
					rec.out = tonumber(s.outputItemID) or 0
					-- Menge pro Herstellung (fuer die Aufloesung von Zwischenprodukten)
					local qmin = tonumber(s.quantityMin)
					if qmin and qmin > 1 then rec.q = qmin end
					if type(s.reagentSlotSchematics) == "table" then
						for _, slot in ipairs(s.reagentSlotSchematics) do
							local r1 = type(slot.reagents) == "table" and slot.reagents[1]
							local qty = tonumber(slot.quantityRequired) or 0
							if r1 and r1.itemID and qty > 0 then
								rec.r[#rec.r + 1] = { r1.itemID, qty }
							end
						end
					end
				end
			end
			recipes[id] = rec
			cidOf[id] = tonumber(info.categoryID)
			count = count + 1
		end
	end
	if count == 0 then return false end

	local c = ns.GetChar(ns.Me(), true)
	c.class = select(2, UnitClass("player"))

	-- Sicherung: ein Rezept gehoert genau einem Beruf. Steckt eines davon schon in einem anderen Beruf
	-- dieses Charakters, wurde das Berufsfenster falsch zugeordnet: nichts speichern.
	for k, other in pairs(c.profs) do
		if k ~= key then
			if not ns.IsCrafting(other.name) then
				c.profs[k] = nil -- Altlast: Sammelberuf mit falsch zugeordneten Rezepten
			elseif other.recipes then
				for id in pairs(recipes) do
					if other.recipes[id] then return false end
				end
			end
		end
	end

	-- Kategorien des Spiels (z.B. "Ausdauernahrung"), nach Kategorie-ID geordnet
	local cats
	if C_TradeSkillUI.GetCategoryInfo then
		local cids, seen = {}, {}
		for _, cid in pairs(cidOf) do
			if cid and not seen[cid] then seen[cid] = true; cids[#cids + 1] = cid end
		end
		table.sort(cids)
		local idxOf = {}
		cats = {}
		for _, cid in ipairs(cids) do
			local ok, ci = pcall(C_TradeSkillUI.GetCategoryInfo, cid)
			if ok and type(ci) == "table" and type(ci.name) == "string" and ci.name ~= "" then
				cats[#cats + 1] = ci.name:sub(1, 40)
				idxOf[cid] = #cats
			end
		end
		for id, rec in pairs(recipes) do
			rec.c = cidOf[id] and idxOf[cidOf[id]] or nil
		end
		if #cats == 0 then cats = nil end
	end

	-- Kategorien aus der klassischen Berufe-API (Ueberschriften der Rezeptliste), falls C_TradeSkillUI keine liefert
	if not cats then
		local cmap, corder = classicCategories()
		if cmap then
			local idxOf = {}
			cats = {}
			for _, nm in ipairs(corder) do
				cats[#cats + 1] = nm:sub(1, 40)
				idxOf[nm] = #cats
			end
			for id, rec in pairs(recipes) do
				local nm = cmap[id]
				rec.c = nm and idxOf[nm] or nil
			end
			if #cats == 0 then cats = nil end
		end
	end

	local prof = c.profs[key] or {}
	prof.name = pname or key
	prof.recipes = recipes
	prof.count = count
	prof.cats = cats
	c.profs[key] = prof
	return true
end

-- Rang/Maximum aller Berufe (auch ohne geoeffnetes Berufsfenster).
local function scanRanks()
	if not GetProfessions or not GetProfessionInfo then return end
	local c = ns.GetChar(ns.Me(), true)
	local byName = {}
	for key, p in pairs(c.profs) do byName[p.name] = key end
	local list = { GetProfessions() }
	for i = 1, 5 do
		local idx = list[i]
		if idx then
			local ok, name, _, rank, max = pcall(GetProfessionInfo, idx)
			if ok and name then
				local key = byName[name]
				if key and c.profs[key] then
					c.profs[key].rank = rank
					c.profs[key].max = max
				end
			end
		end
	end
end

function Scan.Run(verbose)
	pending = false
	local ok = scanOpenProfession()
	scanRanks()
	if ok then
		local c = ns.GetChar(ns.Me())
		c.updated = time()
		if ns.Comm then ns.Comm.QueueBroadcast() end
		if ns.UI and ns.UI.Dirty then ns.UI.Dirty() end
		if verbose then ns.Print(ns.T("Berufe eingelesen.", "Professions scanned.")) end
	elseif verbose then
		ns.Print(ns.T("Kein Beruf offen. Öffne ein Berufsfenster und wiederhole /cs scan.", "No profession open. Open a profession window and repeat /cs scan."))
	end
end

local function schedule()
	if pending then return end
	pending = true
	C_Timer.After(1.0, function() Scan.Run(false) end)
end

function Scan.Init()
	local f = CreateFrame("Frame")
	for _, ev in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "LEARNED_SPELL_IN_TAB", "SKILL_LINES_CHANGED" }) do
		pcall(f.RegisterEvent, f, ev)
	end
	f:SetScript("OnEvent", function(_, ev)
		if ev == "SKILL_LINES_CHANGED" or ev == "LEARNED_SPELL_IN_TAB" then
			scanRanks()
		end
		if ev ~= "SKILL_LINES_CHANGED" then schedule() end
	end)
	C_Timer.After(3, function()
		local c = ns.GetChar(ns.Me(), true)
		c.class = select(2, UnitClass("player"))
		scanRanks()
	end)
end

-- /cs debug: zeigt, was das Spiel fuer das offene Berufsfenster liefert (fuer die Kategorie-Suche)
function Scan.Debug()
	local P = ns.Print
	P("C_TradeSkillUI: " .. tostring(C_TradeSkillUI ~= nil) .. ", GetCategoryInfo: " ..
		tostring(C_TradeSkillUI and C_TradeSkillUI.GetCategoryInfo ~= nil))
	if C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo then
		local ok, b = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
		if ok and type(b) == "table" then
			for k, v in pairs(b) do P("  base." .. tostring(k) .. " = " .. tostring(v)) end
		else
			P("  GetBaseProfessionInfo: " .. tostring(b))
		end
	end
	if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then
		local ok, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
		if ok and type(ids) == "table" and ids[1] then
			local okr, info = pcall(C_TradeSkillUI.GetRecipeInfo, ids[1])
			if okr and type(info) == "table" then
				P("Rezept " .. ids[1] .. ": categoryID = " .. tostring(info.categoryID) .. " (" .. #ids .. " Rezepte)")
				if info.categoryID and C_TradeSkillUI.GetCategoryInfo then
					local okc, ci = pcall(C_TradeSkillUI.GetCategoryInfo, info.categoryID)
					if okc and type(ci) == "table" then
						for k, v in pairs(ci) do P("  category." .. tostring(k) .. " = " .. tostring(v)) end
					else
						P("  GetCategoryInfo: " .. tostring(ci))
					end
				end
			end
		else
			P("keine Rezepte (Berufsfenster offen?)")
		end
	end
	P("klassisch: GetNumTradeSkills = " .. tostring(GetNumTradeSkills and GetNumTradeSkills()) ..
		", GetTradeSkillRecipeLink = " .. tostring(GetTradeSkillRecipeLink ~= nil))
	if GetNumTradeSkills and GetTradeSkillInfo then
		for i = 1, math.min(6, GetNumTradeSkills() or 0) do
			local ok, name, kind = pcall(GetTradeSkillInfo, i)
			P("  [" .. i .. "] " .. tostring(name) .. " (" .. tostring(kind) .. ")")
		end
	end
	local c = ns.db.chars[ns.Me()]
	if c then
		for k, p in pairs(c.profs) do
			P("gespeichert: " .. tostring(p.name) .. " [" .. k .. "] Rezepte=" .. tostring(p.count) .. " Kategorien=" .. tostring(p.cats and #p.cats or 0))
		end
	end
end
