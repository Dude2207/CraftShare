-- CraftShare: Hauptfenster (Design v6)
-- Oben: Titel, Suche, Berufssymbole (ein-/ausblenden). Mitte: Berufe > Kategorien > Rezepte mit Rohstoffen.
-- Unten: Hersteller des gewaehlten Rezepts bzw. alle Mitglieder mit ihren Berufen.
local ADDON, ns = ...
local UI = {}
ns.UI = UI
local T = ns.T

local DEF_W, DEF_H, MIN_W, MIN_H = 700, 800, 680, 800
local TOP_H, BOT_H, BAR_H = 88, 150, 34
local ROW_H, ROWS = 24, 18       -- Rezeptliste (ROWS und ROW_W passen sich der Fenstergroesse an)
local MROW_H, MROWS = 26, 4      -- Mitgliederliste unten
local ROW_W = 750
local WHITE = "Interface\\Buttons\\WHITE8X8"

local COL = {
	bg = { 0.082, 0.067, 0.051 }, panel = { 0.114, 0.094, 0.075 }, row = { 0.141, 0.118, 0.090 },
	secbg = { 0.098, 0.082, 0.063 }, black = { 0.059, 0.047, 0.035 }, tree = { 0.10, 0.082, 0.059 },
	border = { 0.30, 0.247, 0.176 }, border2 = { 0.227, 0.184, 0.133 },
	gold = { 0.95, 0.76, 0.19 }, goldDim = { 0.66, 0.54, 0.16 }, text = { 0.945, 0.92, 0.878 }, muted = { 0.604, 0.561, 0.494 },
	orange = { 0.878, 0.443, 0.227 }, yellow = { 0.95, 0.80, 0.20 }, gray = { 0.5, 0.5, 0.5 }, green = { 0.31, 0.816, 0.353 }, red = { 0.85, 0.33, 0.29 }, off = { 0.42, 0.353, 0.267 },
	sel = { 0.29, 0.239, 0.071 }, btn = { 0.165, 0.129, 0.094 }, btnOn = { 0.231, 0.184, 0.106 }, cat = { 0.85, 0.70, 0.29 },
}

-- ---------------------------------------------------------------- Berufe (Reihenfolge, Icons)
local ORDER = { "164", "171", "333", "202", "165", "197", "755", "773", "182", "186", "393", "185", "129", "356" }
local ORDER_IDX = {}
for i, k in ipairs(ORDER) do ORDER_IDX[k] = i end
local ID_ICON = {
	["164"] = "Trade_BlackSmithing", ["171"] = "Trade_Alchemy", ["333"] = "Trade_Engraving", ["202"] = "Trade_Engineering",
	["165"] = "Trade_LeatherWorking", ["197"] = "Trade_Tailoring", ["755"] = "INV_Misc_Gem_01", ["773"] = "INV_Inscription_Tradeskill01",
	["182"] = "Trade_Herbalism", ["186"] = "Trade_Mining", ["393"] = "INV_Misc_Pelt_Wolf_01", ["185"] = "INV_Misc_Food_15",
	["129"] = "Spell_Holy_SealOfSacrifice", ["356"] = "Trade_Fishing",
}
local NAME_ICON = {
	{ "alchem", "Trade_Alchemy" }, { "schmied", "Trade_BlackSmithing" }, { "blacksmith", "Trade_BlackSmithing" },
	{ "verzauber", "Trade_Engraving" }, { "enchant", "Trade_Engraving" }, { "ingenieur", "Trade_Engineering" },
	{ "engineer", "Trade_Engineering" }, { "kräuter", "Trade_Herbalism" }, { "herbal", "Trade_Herbalism" },
	{ "leder", "Trade_LeatherWorking" }, { "leather", "Trade_LeatherWorking" }, { "bergbau", "Trade_Mining" },
	{ "mining", "Trade_Mining" }, { "kürschner", "INV_Misc_Pelt_Wolf_01" }, { "skinning", "INV_Misc_Pelt_Wolf_01" },
	{ "schneider", "Trade_Tailoring" }, { "tailor", "Trade_Tailoring" }, { "koch", "INV_Misc_Food_15" },
	{ "cook", "INV_Misc_Food_15" }, { "erste hilfe", "Spell_Holy_SealOfSacrifice" }, { "first aid", "Spell_Holy_SealOfSacrifice" },
	{ "angeln", "Trade_Fishing" }, { "fish", "Trade_Fishing" }, { "juwel", "INV_Misc_Gem_01" }, { "jewel", "INV_Misc_Gem_01" },
}
local function profIcon(key, name)
	if name then
		local l = name:lower()
		for _, e in ipairs(NAME_ICON) do
			if l:find(e[1], 1, true) then return "Interface\\Icons\\" .. e[2] end
		end
	end
	if ID_ICON[key] then return "Interface\\Icons\\" .. ID_ICON[key] end
	return "Interface\\AddOns\\CraftShare\\Media\\Icon"
end

-- ---------------------------------------------------------------- Kategorien (Ausruestungsplatz des Ergebnis-Items)
local CATS = {
	{ "head", "Kopf", "Head" }, { "neck", "Hals", "Neck" }, { "shoulder", "Schulter", "Shoulders" }, { "back", "Rücken", "Back" },
	{ "chest", "Brust", "Chest" }, { "wrist", "Handgelenke", "Wrists" }, { "hands", "Hände", "Hands" }, { "waist", "Taille", "Waist" },
	{ "legs", "Beine", "Legs" }, { "feet", "Füße", "Feet" }, { "ring", "Ringe", "Rings" }, { "trinket", "Schmuck", "Trinkets" },
	{ "weapon", "Waffen", "Weapons" }, { "shield", "Schilde", "Shields" }, { "bag", "Taschen", "Bags" },
	{ "cons", "Verbrauchsgüter", "Consumables" }, { "inter", "Zwischenprodukte", "Intermediate goods" }, { "other", "Sonstiges", "Other" },
}
local CAT_IDX, CAT_NAME = {}, {}
for i, c in ipairs(CATS) do CAT_IDX[c[1]] = i; CAT_NAME[c[1]] = T(c[2], c[3]) end
local EQUIP = {
	INVTYPE_HEAD = "head", INVTYPE_NECK = "neck", INVTYPE_SHOULDER = "shoulder", INVTYPE_CLOAK = "back",
	INVTYPE_CHEST = "chest", INVTYPE_ROBE = "chest", INVTYPE_WRIST = "wrist", INVTYPE_HAND = "hands",
	INVTYPE_WAIST = "waist", INVTYPE_LEGS = "legs", INVTYPE_FEET = "feet", INVTYPE_FINGER = "ring",
	INVTYPE_TRINKET = "trinket", INVTYPE_WEAPON = "weapon", INVTYPE_2HWEAPON = "weapon", INVTYPE_WEAPONMAINHAND = "weapon",
	INVTYPE_WEAPONOFFHAND = "weapon", INVTYPE_RANGED = "weapon", INVTYPE_RANGEDRIGHT = "weapon", INVTYPE_THROWN = "weapon",
	INVTYPE_SHIELD = "shield", INVTYPE_HOLDABLE = "shield", INVTYPE_BAG = "bag", INVTYPE_QUIVER = "bag",
}

local infoCache = {}
local function itemStatic(id)
	local c = infoCache[id]
	if c then return c end
	local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
	local equip, class
	if f then
		local ok, _, _, _, el, _, cid = pcall(f, id)
		if ok then equip, class = el, cid end
	end
	c = { equip, class }
	infoCache[id] = c
	return c
end

-- ---------------------------------------------------------------- Zustand
local frame, rows, mrows, header, mid, bot, searchBox, mslider, bslider
local iconBtns = {}
local items, bitems = {}, {}
local offset, boffset = 0, 0
local dirty = false
local S = { selKey = nil, selRec = nil }
local relayoutDocks -- weiter unten definiert
local folded = false -- Hauptfenster bis auf die Kopfleiste eingeklappt (nur bis zum Schliessen)
local W = {}
local producers, usedAsReagent, rawCache = {}, {}, {}

local function cfg()
	local db = ns.db
	db.ui = db.ui or {}
	local u = db.ui
	u.hidden = u.hidden or {}
	u.collapsed = u.collapsed or {}
	u.catCollapsed = u.catCollapsed or {}
	u.tab = u.tab or "cr"
	return u
end

-- ---------------------------------------------------------------- Bausteine
local function setc(tex, c, a) tex:SetColorTexture(c[1], c[2], c[3], a or 1) end

local function Box(parent, bg, border, ftype)
	local f = CreateFrame(ftype or "Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	if f.SetBackdrop then
		f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
		f:SetBackdropColor(bg[1], bg[2], bg[3], 1)
		f:SetBackdropBorderColor(border[1], border[2], border[3], 1)
	else
		local t = f:CreateTexture(nil, "BACKGROUND")
		t:SetAllPoints()
		setc(t, bg)
	end
	return f
end

-- Schwierigkeit 0 orange, 1 gelb, 2 gruen, 3 grau (nil: Vorgabe)
local function diffColor(d, default)
	if d == 0 then return COL.orange elseif d == 1 then return COL.yellow
	elseif d == 2 then return COL.green elseif d == 3 then return COL.gray end
	return default
end

local function setBorder(f, c)
	if f.SetBackdropBorderColor then f:SetBackdropBorderColor(c[1], c[2], c[3], 1) end
end

local function setBg(f, c)
	if f.SetBackdropColor then f:SetBackdropColor(c[1], c[2], c[3], 1) end
end

local function FS(parent, size, c, justify)
	local s = parent:CreateFontString(nil, "OVERLAY")
	s:SetFont(STANDARD_TEXT_FONT, size, "")
	s:SetTextColor(c[1], c[2], c[3])
	s:SetJustifyH(justify or "LEFT")
	s:SetWordWrap(false)
	return s
end

local function Btn(parent, text, w, h, onClick, size)
	local b = Box(parent, COL.btn, COL.border, "Button")
	b:SetSize(w, h)
	b.label = FS(b, size or 12, COL.gold, "CENTER")
	b.label:SetPoint("CENTER")
	b.label:SetText(text)
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.08)
	b:SetScript("OnClick", onClick)
	return b
end

local function setSeg(b, on)
	setBg(b, on and COL.btnOn or COL.btn)
	setBorder(b, on and COL.goldDim or COL.border)
	local c = on and COL.gold or COL.muted
	b.label:SetTextColor(c[1], c[2], c[3])
end

local function MakeSlider(parent, onChange)
	local s = CreateFrame("Slider", nil, parent)
	s:SetOrientation("VERTICAL")
	s:SetWidth(12)
	if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
	s:SetValueStep(1)
	s:SetMinMaxValues(0, 0)
	local track = s:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints()
	setc(track, COL.black)
	local thumb = s:CreateTexture(nil, "OVERLAY")
	thumb:SetSize(12, 30)
	thumb:SetColorTexture(0.42, 0.333, 0.125, 1)
	s:SetThumbTexture(thumb)
	s.lock = false
	s:SetScript("OnValueChanged", function(self, v)
		if self.lock then return end
		onChange(math.floor(v + 0.5))
	end)
	function s:Set(val, max)
		self.lock = true
		self:SetMinMaxValues(0, max)
		self:SetValue(val)
		self.lock = false
		self:SetShown(max > 0)
	end
	return s
end

local function classHex(class)
	local col = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if col then return string.format("|cff%02x%02x%02x", col.r * 255, col.g * 255, col.b * 255) end
	return "|cffffffff"
end

local function ago(sec)
	if not sec then return "-" end
	if sec < 90 then return T("gerade eben", "just now") end
	if sec < 3600 then return string.format(T("vor %d Min", "%d min ago"), math.floor(sec / 60)) end
	if sec < 86400 then return string.format(T("vor %d Std.", "%d h ago"), math.floor(sec / 3600)) end
	return string.format(T("vor %d Tagen", "%d d ago"), math.floor(sec / 86400))
end

local function whisper(name)
	if not name or name == ns.Me() then return end
	if ChatFrame_SendTell then ChatFrame_SendTell(name)
	elseif ChatFrame_OpenChat then ChatFrame_OpenChat("/w " .. name .. " ") end
end

local lname = {}
local function itemLower(id)
	local c = lname[id]
	if c then return c end
	local n = ns.ItemName(id)
	if n then c = n:lower(); lname[id] = c end
	return c
end

local function itemText(id, q)
	return q .. "× " .. (ns.ItemName(id) or ("item:" .. id))
end

-- ---------------------------------------------------------------- Rezept-Logik
-- Wer stellt welches Item her (fuer die Aufloesung von Zwischenprodukten), welche Items sind Reagenzien.
local function buildProducers()
	producers, usedAsReagent = {}, {}
	for _, c in pairs(ns.db.chars) do
		for _, p in pairs(c.profs) do
			for _, rec in pairs(p.recipes or {}) do
				if rec.out and rec.out > 0 and not producers[rec.out] then producers[rec.out] = rec end
				for _, r in ipairs(rec.r) do usedAsReagent[r[1]] = true end
			end
		end
	end
	if ns.Prices then ns.Prices.SetProducers(producers) end
end

local function expand(itemID, qty, acc, order, depth)
	local prod = producers[itemID]
	-- Verdorbene Lederfetzen gehoeren nur ins Rezept "Leichtes Leder" selbst: Rezepte daraus werden nicht weiter aufgeloest
	if prod and ns.Prices and ns.Prices.UsesScraps(prod) then prod = nil end
	-- Ist Kaufen guenstiger als Herstellen (laut Preisdaten), wird nicht weiter aufgeloest
	if prod and ns.Prices then
		local u = ns.Prices.Unit(itemID)
		if u and u.how ~= "make" then prod = nil end
	end
	if prod and depth < 4 and #prod.r > 0 then
		local crafts = math.ceil(qty / (prod.q or 1))
		for _, r in ipairs(prod.r) do expand(r[1], r[2] * crafts, acc, order, depth + 1) end
	else
		if not acc[itemID] then acc[itemID] = 0; order[#order + 1] = itemID end
		acc[itemID] = acc[itemID] + qty
	end
end

-- Rohstoffe eines Rezepts, Zwischenprodukte immer aufgeloest: { {id, q}, ... }
local function rawOf(rec)
	local c = rawCache[rec]
	if c then return c end
	local acc, order = {}, {}
	for _, r in ipairs(rec.r) do expand(r[1], r[2], acc, order, 0) end
	c = {}
	for _, id in ipairs(order) do c[#c + 1] = { id, acc[id] } end
	rawCache[rec] = c
	return c
end

local function categoryOf(rec)
	local out = rec.out
	if not out or out <= 0 then return "other" end
	local s = itemStatic(out)
	local key = s[1] and EQUIP[s[1]]
	if key then return key end
	if usedAsReagent[out] then return "inter" end
	if s[2] == 1 then return "bag" end
	if s[2] == 0 then return "cons" end
	if s[2] == 7 then return "inter" end
	return "other"
end

local function recipeMatches(q, e, gname)
	if e.name:lower():find(q, 1, true) or gname:lower():find(q, 1, true) or (e.catName or ""):lower():find(q, 1, true) then return true end
	for _, m in ipairs(e.crafters) do
		if m.name:lower():find(q, 1, true) then return true end
	end
	for _, r in ipairs(e.rec.r) do
		local n = itemLower(r[1])
		if n and n:find(q, 1, true) then return true end
	end
	for _, r in ipairs(rawOf(e.rec)) do
		local n = itemLower(r[1])
		if n and n:find(q, 1, true) then return true end
	end
	return false
end

local function treeLines(e)
	local out = { { t = "tl", head = true } }
	for _, d in ipairs(e.rec.r) do
		local have = ns.ItemCount(d[1], true)
		local hc = have >= d[2] and "|cff4fd05a" or (have > 0 and "|cffe8a96a" or "|cffd9544a")
		local acc, order = {}, {}
		expand(d[1], d[2], acc, order, 0)
		local parts = {}
		for _, id in ipairs(order) do parts[#parts + 1] = itemText(id, acc[id]) end
		out[#out + 1] = { t = "tl", left = itemText(d[1], d[2]) .. "  " .. hc .. "(" .. have .. ")|r", raw = table.concat(parts, ", "), id = d[1], rawIds = order }
	end
	return out
end

-- Stufenvoraussetzung und Gegenstandsstufe des Ergebnisses (0: keine, nil: Daten noch nicht geladen)
local levels = {}
local function requiredLevel(id)
	if not id or id <= 0 then return 0, 0 end
	local lv = levels[id]
	if lv then return lv[1], lv[2] end
	local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local name, _, _, itemLevel, minLevel = get(id)
	if not name then return nil end -- das Spiel meldet sich, sobald die Daten da sind
	levels[id] = { minLevel or 0, itemLevel or 0 }
	return levels[id][1], levels[id][2]
end

-- Umlaute wie die Grundbuchstaben einsortieren
local FOLD = { ["Ä"] = "a", ["Ö"] = "o", ["Ü"] = "u", ["ä"] = "a", ["ö"] = "o", ["ü"] = "u", ["ß"] = "ss" }
local function sortName(n)
	-- UTF-8: die Umlaute und das scharfe s beginnen mit Byte 195
	return (n:gsub("\195[\128-\191]", FOLD):lower())
end

-- Reihenfolge in einer Kategorie: Schwierigkeit (orange, gelb, gruen, grau, unbekannt), benoetigte Stufe,
-- Gegenstandsstufe, Materialmenge, Name. Bei grauen Rezepten umgekehrt: die kleinsten Anforderungen stehen unten.
local function materialCount(rec)
	local n = 0
	for _, r in ipairs(rec.r) do n = n + r[2] end
	return n
end

local function recipeLess(a, b)
	local da, db = a.diff or 4, b.diff or 4
	if da ~= db then return da < db end
	local gray = (da == 3)
	local la, ia = requiredLevel(a.rec.out)
	local lb, ib = requiredLevel(b.rec.out)
	-- noch unbekannte Stufen stehen in beiden Richtungen am Ende
	local unknown = gray and -1 or 999
	for _, k in ipairs({
		{ la or unknown, lb or unknown },
		{ ia or unknown, ib or unknown },
		{ materialCount(a.rec), materialCount(b.rec) },
	}) do
		if k[1] ~= k[2] then
			if gray then return k[1] > k[2] end
			return k[1] < k[2]
		end
	end
	local na, nb = sortName(a.name), sortName(b.name)
	if na ~= nb then return na < nb end
	return a.id < b.id
end

local function buildItems()
	local u = cfg()
	local q = strtrim(searchBox and searchBox:GetText() or ""):lower()
	buildProducers()
	rawCache = {}
	if ns.Prices then ns.Prices.Begin() end
	local groups, gkeys = {}, {}

	for cname, c in pairs(ns.db.chars) do
		local online = ns.Roster.IsOnline(cname)
		for key, p in pairs(c.profs) do
			if not u.hidden[key] and ns.IsCrafting(p.name) then
				local g = groups[key]
				if not g then
					g = { key = key, name = p.name or key, recipes = {}, members = 0 }
					groups[key] = g
					gkeys[#gkeys + 1] = key
				end
				g.members = g.members + 1
				for id, rec in pairs(p.recipes or {}) do
					local e = g.recipes[id]
					if not e then
						e = { t = "rec", key = key, id = id, rec = rec, crafters = {} }
						g.recipes[id] = e
					end
					e.crafters[#e.crafters + 1] = { name = cname, char = c, prof = p, online = online }
				end
			end
		end
	end
	table.sort(gkeys, function(a, b)
		local ia, ib = ORDER_IDX[a] or 99, ORDER_IDX[b] or 99
		if ia ~= ib then return ia < ib end
		return groups[a].name < groups[b].name
	end)

	local out = {}
	for _, key in ipairs(gkeys) do
		local g = groups[key]
		local byCat, catKeys, catOrder, total = {}, {}, {}, 0
		for _, e in pairs(g.recipes) do
			e.name = ns.RecipeName(e.id, e.rec)
			-- Kategorie: die des Spiels (vom Hersteller uebermittelt, z.B. "Ausdauernahrung"),
			-- sonst der Ausruestungsplatz des Ergebnis-Items (Kopf, Schulter, ...)
			local cname, cidx
			for _, m in ipairs(e.crafters) do
				local rr = m.prof.recipes and m.prof.recipes[e.id]
				if rr and rr.c and m.prof.cats and m.prof.cats[rr.c] then cname, cidx = m.prof.cats[rr.c], rr.c break end
			end
			if not cname then
				local sk = categoryOf(e.rec)
				cname, cidx = CAT_NAME[sk], 1000 + CAT_IDX[sk]
			end
			e.catName = cname
			-- beste Schwierigkeit unter den Herstellern (0 orange .. 3 grau), nil = unbekannt
			local bd
			for _, m in ipairs(e.crafters) do
				if not (u.onlineOnly and not m.online) then
					local rr = m.prof.recipes and m.prof.recipes[e.id]
					local d = rr and rr.d
					if d and (not bd or d < bd) then bd = d end
				end
			end
			e.diff = bd
			local oid = e.rec.out
			e.inter = (oid and oid > 0 and usedAsReagent[oid] and not EQUIP[itemStatic(oid)[1] or ""]) and true or false
			if (q == "" or recipeMatches(q, e, g.name)) and not (u.skillOnly and e.diff == 3) then
				local list = byCat[cname]
				if not list then
					list = {}
					byCat[cname] = list
					catKeys[#catKeys + 1] = cname
					catOrder[cname] = cidx
				elseif cidx < catOrder[cname] then
					catOrder[cname] = cidx
				end
				list[#list + 1] = e
				total = total + 1
				local nc, on = 0, 0
				for _, m in ipairs(e.crafters) do
					if not (u.onlineOnly and not m.online) then
						nc = nc + 1
						if m.online then on = on + 1 end
					end
				end
				e.nc, e.on = nc, on
				local parts = {}
				for _, r in ipairs(rawOf(e.rec)) do parts[#parts + 1] = itemText(r[1], r[2]) end
				e.matsText = table.concat(parts, " · ")
			end
		end
		if total > 0 then
			local fullKeys = {}
			for _, ck in ipairs(catKeys) do fullKeys[#fullKeys + 1] = key .. "/" .. ck end
			out[#out + 1] = { t = "prof", key = key, name = g.name, n = total, members = g.members, collapsed = u.collapsed[key], cats = fullKeys }
			if not u.collapsed[key] then
				table.sort(catKeys, function(a, b)
					if catOrder[a] ~= catOrder[b] then return catOrder[a] < catOrder[b] end
					return a < b
				end)
				for _, ck in ipairs(catKeys) do
					local list = byCat[ck]
					table.sort(list, recipeLess)
					local full = key .. "/" .. ck
					local collapsed = u.catCollapsed[full]
					out[#out + 1] = { t = "cat", ck = full, name = ck, n = #list, collapsed = collapsed }
					if not collapsed then
						for _, e in ipairs(list) do
							out[#out + 1] = e
							if S.selKey == e.key and S.selRec == e.id then
								for _, ln in ipairs(treeLines(e)) do out[#out + 1] = ln end
							end
						end
					end
				end
			end
		end
	end
	return out
end

-- Untere Liste: Hersteller des gewaehlten Rezepts / alle im Beruf / alle Mitglieder
local function buildBottom()
	local u = cfg()
	local list, title = {}, nil
	local selName
	if S.selRec then
		for _, c in pairs(ns.db.chars) do
			local p = c.profs[S.selKey]
			local rec = p and p.recipes and p.recipes[S.selRec]
			if rec then selName = ns.RecipeName(S.selRec, rec) break end
		end
		if not selName then S.selKey, S.selRec = nil, nil end
	end

	if S.selRec then
		for cname, c in pairs(ns.db.chars) do
			local p = c.profs[S.selKey]
			if p and (u.tab == "all" or (p.recipes and p.recipes[S.selRec])) then
				local online = ns.Roster.IsOnline(cname)
				if not (u.onlineOnly and not online) then
					local rr = p.recipes and p.recipes[S.selRec]
				list[#list + 1] = { name = cname, char = c, prof = p, online = online, d = rr and rr.d }
				end
			end
		end
		table.sort(list, function(a, b)
			if a.online ~= b.online then return a.online end
			local ra, rb = a.prof.rank or 0, b.prof.rank or 0
			if ra ~= rb then return ra > rb end
			return a.name < b.name
		end)
		if u.tab == "all" then
			local pn = ""
			for _, c in pairs(ns.db.chars) do
				if c.profs[S.selKey] then pn = c.profs[S.selKey].name or "" break end
			end
			title = T("Alle · ", "All · ") .. pn
		else
			title = T("Hersteller · ", "Crafters · ") .. selName
		end
	else
		for cname, c in pairs(ns.db.chars) do
			local online = ns.Roster.IsOnline(cname)
			if not (u.onlineOnly and not online) then
				local pl = {}
				for key, p in pairs(c.profs) do
					if not u.hidden[key] and ns.IsCrafting(p.name) then pl[#pl + 1] = { key = key, p = p } end
				end
				if #pl > 0 then
					table.sort(pl, function(a, b)
						local ia, ib = ORDER_IDX[a.key] or 99, ORDER_IDX[b.key] or 99
						if ia ~= ib then return ia < ib end
						return (a.p.name or "") < (b.p.name or "")
					end)
					list[#list + 1] = { name = cname, char = c, online = online, profs = pl, all = true }
				end
			end
		end
		table.sort(list, function(a, b)
			if a.online ~= b.online then return a.online end
			return a.name < b.name
		end)
		title = T("Alle Mitglieder", "All members")
	end
	W.btitle:SetText(title .. "  |cff9a8f7e(" .. #list .. ")|r")
	return list
end

-- Bausteine fuer Orders.lua (Bestell-Fenster)
ns.UIK = {
	Box = Box, FS = FS, Btn = Btn, COL = COL, setSeg = setSeg, MakeSlider = MakeSlider, classHex = classHex, ago = ago,
	whisper = whisper, profIcon = profIcon, setc = setc, setBorder = setBorder, setBg = setBg, itemText = itemText,
	-- Rohstoffe eines (auch fremden) Rezepts, Zwischenprodukte aufgeloest
	RawFresh = function(rec) buildProducers(); rawCache = {}; return rawOf(rec) end,
}

-- Benutzer-Skalierung 0.5 .. 1.5 (Standard 1.0)
function UI.UserScale()
	local v = ns.db and ns.db.ui and ns.db.ui.scale
	if type(v) ~= "number" then return 1 end
	return math.max(0.5, math.min(1.5, v))
end

function UI.SetUserScale(v)
	v = math.max(0.5, math.min(1.5, math.floor(v * 20 + 0.5) / 20))
	ns.db.ui = ns.db.ui or {}
	ns.db.ui.scale = v
	UI.ApplyScale()
	if W.scaleVal then W.scaleVal:SetText(math.floor(v * 100 + 0.5) .. "%") end
end

function UI.ApplyScale()
	local us = UI.UserScale()
	if frame then
		local es = (S.fitScale or 1) * us
		frame:SetScale(es)
		if frame.SetResizeBounds then
			local minH = folded and (TOP_H + 20) or MIN_H
			frame:SetResizeBounds(MIN_W, minH, math.floor(UIParent:GetWidth() / es), math.floor(UIParent:GetHeight() / es))
		end
	end
	for _, n in ipairs({ "CraftSharePriceCheck", "CraftShareOrderFrame", "CraftShareOrdersFrame", "CraftShareTaskFrame", "CraftShareMailFrame", "CraftShareHistoryFrame" }) do
		local g = _G[n]
		if g then g:SetScale(us) end
	end
end

function UI.GetSelection() return S.selKey, S.selRec end

-- Eintrag des markierten Rezepts: { rec, name, catName, key, id } oder nil
function UI.GetSelectedEntry()
	if not S.selKey then return nil end
	for _, it in ipairs(items or {}) do
		if it.t == "rec" and it.key == S.selKey and it.id == S.selRec then return it end
	end
end

-- ---------------------------------------------------------------- Zeichnen: Rezeptliste
local function showParts(row, kind)
	for k, parts in pairs(row.parts) do
		for _, p in ipairs(parts) do
			if k == kind then p:Show() else p:Hide() end
		end
	end
end

local function paintRow(row, it)
	row.item = it
	if not it then row:Hide() return end
	row:Show()
	showParts(row, it.t)
	row.bar:Show()
	local nameW = math.max(100, ROW_W - 68 - 340 - 4)
	if it.t == "prof" then
		setc(row.bg, COL.secbg)
		row.bar:Hide()
		row.chevP:SetTexture(it.collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
		row.piTex:SetTexture(profIcon(it.key, it.name))
		row.profName:SetText(it.name)
		row.profInfo:SetText(string.format(T("%d Rezepte · %d Mitglieder", "%d recipes · %d members"), it.n, it.members))
		row.profLine:SetColorTexture(COL.border2[1], COL.border2[2], COL.border2[3], 1)
	elseif it.t == "cat" then
		setc(row.bg, COL.panel)
		row.bar:Hide()
		row.chevC:SetTexture(it.collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
		row.catName:SetText(it.name)
		row.catInfo:SetText(it.n)
	elseif it.t == "rec" then
		local selected = (S.selKey == it.key and S.selRec == it.id)
		setc(row.bg, selected and COL.sel or COL.row)
		setc(row.bar, diffColor(it.diff, COL.orange))
		row.ricon:SetTexture(ns.ItemIcon(it.rec.out))
		row.recName:SetText(it.name)
		local inter = it.inter
		row.recName:SetWidth(inter and (nameW - 110) or nameW)
		if inter then row.tag:Show() else row.tag:Hide() end
		row.mats:SetText(it.matsText or "")
		local c = it.nc or 0
		row.crafters:SetText(c .. ((it.on and it.on > 0) and ("  |cff4fd05a(" .. it.on .. ")|r") or ""))
	else -- tl
		setc(row.bg, COL.tree)
		setc(row.bar, COL.goldDim)
		row.tlLeft:SetTextColor(COL.text[1], COL.text[2], COL.text[3])
		row.tlRaw:SetTextColor(COL.text[1], COL.text[2], COL.text[3])
		row.tlLeft:SetWidth(row.tlLeftW or 250)
		row.pcBtn:SetShown(it.head and true or false)
		if it.head then
			row.tlLeft:SetTextColor(COL.goldDim[1], COL.goldDim[2], COL.goldDim[3])
			row.tlRaw:SetTextColor(COL.goldDim[1], COL.goldDim[2], COL.goldDim[3])
			row.tlLeft:SetText(T("Benötigt (vorhanden)", "Required (in stock)"))
			row.tlRaw:SetText(T("Rohstoffe", "Raw materials"))
		else
			row.tlLeft:SetTextColor(COL.text[1], COL.text[2], COL.text[3])
			row.tlRaw:SetTextColor(COL.text[1], COL.text[2], COL.text[3])
			row.tlLeft:SetText(it.left or "")
			row.tlRaw:SetText(it.raw or "")
		end
	end
end

local function renderList()
	if not frame then return end
	local n = #items
	local maxOff = math.max(0, n - ROWS)
	if offset > maxOff then offset = maxOff end
	mslider:Set(offset, maxOff)
	for i = 1, ROWS do paintRow(rows[i], items[offset + i]) end
	W.empty:SetShown(n == 0)
end

-- ---------------------------------------------------------------- Zeichnen: Mitglieder unten
local function paintMRow(row, it)
	row.item = it
	if not it then row:Hide() return end
	row:Show()
	setc(row.bg, COL.row)
	setc(row.bar, diffColor(it.d, it.online and COL.orange or COL.off))
	row:SetAlpha(it.online and 1 or 0.65)
	local class = it.char.class
	local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
	row.face:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CharacterCreate-Classes")
	if coords then row.face:SetTexCoord(coords[1], coords[2], coords[3], coords[4]) else row.face:SetTexCoord(0, 1, 0, 1) end
	row.dot:SetTexture(it.online and "Interface\\FriendsFrame\\StatusIcon-Online" or "Interface\\FriendsFrame\\StatusIcon-Offline")
	row.nm:SetText(classHex(class) .. it.name .. "|r")
	local r = ns.Roster.Get(it.name)
	local cn = class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or ""
	row.sub:SetText(((r and r.level) and (T("Stufe ", "Level ") .. r.level .. " · ") or "") .. cn .. ((r and r.rank) and (" · " .. r.rank) or ""))
	row.last:SetText(it.online and T("online", "online") or (T("zuletzt ", "last ") .. ago(r and r.last)))
	local lc = it.online and COL.green or COL.muted
	row.last:SetTextColor(lc[1], lc[2], lc[3])
	if it.all then
		row.skRank:Hide(); row.barBg:Hide(); row.barFill:Hide()
		local parts = {}
		for _, e in ipairs(it.profs) do
			parts[#parts + 1] = "|T" .. profIcon(e.key, e.p.name) .. ":13:13:0:0:64:64:5:59:5:59|t " .. (e.p.name or "") ..
				((e.p.rank and e.p.rank > 0) and (" |cfff2c230" .. e.p.rank .. "|r") or "")
		end
		row.profsFS:SetText(table.concat(parts, "   "))
		-- passt es nicht in die Spalte, nur Symbole und Skill (die Namen stehen im Tooltip)
		if row.profsFS:GetStringWidth() > row.profsFS:GetWidth() then
			local short = {}
			for _, e in ipairs(it.profs) do
				short[#short + 1] = "|T" .. profIcon(e.key, e.p.name) .. ":13:13:0:0:64:64:5:59:5:59|t " ..
					((e.p.rank and e.p.rank > 0) and ("|cfff2c230" .. e.p.rank .. "|r") or "")
			end
			row.profsFS:SetText(table.concat(short, "   "))
		end
		row.profsFS:Show()
	else
		row.profsFS:Hide()
		row.skRank:Show(); row.barBg:Show(); row.barFill:Show()
		local p = it.prof
		local rank, max = p.rank, p.max
		row.skRank:SetText((rank and rank > 0) and (rank .. (max and max > 0 and ("/" .. max) or "")) or "-")
		local ratio = (rank and max and max > 0) and math.min(1, rank / max) or 0
		row.barFill:SetWidth(math.max(1, (row.barBg:GetWidth() - 2) * ratio))
	end
end

local function renderBottom()
	if not frame then return end
	local u = cfg()
	bitems = buildBottom()
	local n = #bitems
	local maxOff = math.max(0, n - MROWS)
	if boffset > maxOff then boffset = maxOff end
	bslider:Set(boffset, maxOff)
	for i = 1, MROWS do paintMRow(mrows[i], bitems[boffset + i]) end
	local hasSel = S.selRec ~= nil
	W.segCr:SetShown(hasSel)
	W.segAll:SetShown(hasSel)
	setSeg(W.segCr, u.tab == "cr")
	setSeg(W.segAll, u.tab == "all")
	W.bempty:SetShown(n == 0)
end

-- ---------------------------------------------------------------- Kopf: Symbole und Status
local function professionCounts()
	local counts, names = {}, {}
	for _, c in pairs(ns.db.chars) do
		for key, p in pairs(c.profs) do
			-- nur Berufe mit Rezepten (Kürschnerei, Kräuterkunde, Angeln haben keine)
			if ns.IsCrafting(p.name) and next(p.recipes or {}) then
				counts[key] = (counts[key] or 0) + 1
				names[key] = names[key] or p.name
			end
		end
	end
	local keys = {}
	for k in pairs(counts) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b)
		local ia, ib = ORDER_IDX[a] or 99, ORDER_IDX[b] or 99
		if ia ~= ib then return ia < ib end
		return (names[a] or a) < (names[b] or b)
	end)
	return keys, counts, names
end

local function renderIcons()
	local u = cfg()
	local keys, counts, names = professionCounts()
	local total, allVisible = 0, true
	-- "Alle": Mitglieder mit mindestens einem Beruf mit Rezepten (nicht alle gespeicherten Charaktere)
	for _, c in pairs(ns.db.chars) do
		for _, p in pairs(c.profs) do
			if ns.IsCrafting(p.name) and next(p.recipes or {}) then total = total + 1 break end
		end
	end
	local avail = (frame and frame:GetWidth() or DEF_W) - 20 - 20 - 36 - 6 - 36 - 230
	local pitch = 42
	if #keys > 1 then pitch = math.max(28, math.min(42, avail / (#keys - 1))) end
	for i, key in ipairs(keys) do
		local b = iconBtns[i]
		if not b then
			b = Box(W.iconRow, COL.black, COL.border, "Button")
			b:SetSize(36, 36)
			b.tex = b:CreateTexture(nil, "ARTWORK")
			b.tex:SetPoint("TOPLEFT", 3, -3)
			b.tex:SetPoint("BOTTOMRIGHT", -3, 3)
			b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
			b.cnt = FS(b, 10, COL.text, "RIGHT")
			b.cnt:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
			b.cnt:SetPoint("BOTTOMRIGHT", -2, 2)
			local hl = b:CreateTexture(nil, "HIGHLIGHT")
			hl:SetAllPoints()
			hl:SetColorTexture(1, 1, 1, 0.1)
			b:SetScript("OnClick", function(self)
				local uu = cfg()
				uu.hidden[self.key] = not uu.hidden[self.key] or nil
				if uu.hidden[self.key] and S.selKey == self.key then S.selKey, S.selRec = nil, nil end
				offset, boffset = 0, 0
				UI.Refresh()
			end)
			b:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
				GameTooltip:AddLine(self.pname or "", 1, 1, 1)
				GameTooltip:AddLine(cfg().hidden[self.key] and T("Ausgeblendet – Klick zum Einblenden", "Hidden – click to show")
					or T("Sichtbar – Klick zum Ausblenden", "Visible – click to hide"), 0.7, 0.7, 0.7)
				GameTooltip:Show()
			end)
			b:SetScript("OnLeave", function() GameTooltip:Hide() end)
			iconBtns[i] = b
		end
		b.key, b.pname = key, names[key]
		b:ClearAllPoints()
		b:SetPoint("LEFT", W.allBtn, "RIGHT", 6 + (i - 1) * pitch, 0)
		b.tex:SetTexture(profIcon(key, names[key]))
		b.cnt:SetText(counts[key])
		local hidden = u.hidden[key]
		if hidden then allVisible = false end
		b.tex:SetDesaturated(hidden and true or false)
		b.tex:SetAlpha(hidden and 0.4 or 1)
		setBorder(b, hidden and COL.border or COL.gold)
		b:Show()
	end
	for i = #keys + 1, #iconBtns do iconBtns[i]:Hide() end
	W.allCnt:SetText(total)
	setBorder(W.allBtn, allVisible and COL.gold or COL.border)
end

local function renderStatus()
	local n, online = 0, 0
	for name, c in pairs(ns.db.chars) do
		if next(c.profs) then
			n = n + 1
			if ns.Roster.IsOnline(name) then online = online + 1 end
		end
	end
	local g = ns.Roster.GuildName()
	local base = string.format(T("%d Mitglieder · %d online", "%d members · %d online"), n, online)
	W.sub:SetText(g and ("<" .. g .. ">  ·  " .. base) or base)
	-- Hinweis nur, wenn jemand eine neuere Version nutzt
	local nv = ns.NewerVersion()
	W.verBox:SetShown(nv ~= nil)
	if nv then W.verText:SetText(T("Neue Version ", "New version ") .. nv.v .. T(" verfügbar", " available")) end
	if W.sub:GetStringWidth() > (W.sub:GetWidth() or 0) then W.sub:SetText(base) end
	W.auto.label:SetText(ns.db.autoSync and T("Auto-Sync: an", "Auto sync: on") or T("Auto-Sync: aus", "Auto sync: off"))
	-- Preis-Optionen
	local P = ns.Prices
	W.srcBtn.label:SetText(T("Preisquelle: ", "Price source: ") .. P.SourceLabel(P.Settings().source))
	W.ptBtn.label:SetText(T("Preisart: ", "Price type: ") .. (P.Settings().ptype == "market" and T("Marktwert (TSM)", "Market value (TSM)") or T("Mindestgebot (Auktion)", "Minimum buyout")))
	for _, c in ipairs(W.chks) do c:SetChecked(P.Settings()[c.key] and true or false) end
	W.priceInfo:SetText(P.NewestText())
	if W.autoMailChk then W.autoMailChk:SetChecked(ns.db.autoMail ~= false) end
	if W.soundBtn and ns.Mini then W.soundBtn.label:SetText(T("Ton neuer Auftrag: ", "New order sound: ") .. ns.Mini.SoundName()) end
	if W.skillChk then W.skillChk:SetChecked(cfg().skillOnly and true or false) end
	if W.scaleVal then W.scaleVal:SetText(math.floor(UI.UserScale() * 100 + 0.5) .. "%") end
	-- Hinweis auf neue Auftraege direkt am Knopf
	local open = ns.Orders and ns.Orders.IncomingOpen() or 0
	W.openBtn.label:SetText(T("Aufträge", "Orders") .. (open > 0 and ("  |cffe0713a(" .. open .. ")|r") or ""))
end

function UI.Refresh()
	if not frame or not frame:IsShown() then return end
	dirty = false
	W.onlineChk:SetChecked(cfg().onlineOnly and true or false)
	renderIcons()
	items = buildItems()
	renderList()
	renderBottom()
	renderStatus()
	if ns.PriceCheck and ns.PriceCheck.OnRefresh then ns.PriceCheck.OnRefresh() end
end

-- Daten haben sich geaendert: gebuendelt neu zeichnen, solange das Fenster offen ist.
function UI.Dirty()
	if not frame or not frame:IsShown() or dirty then return end
	dirty = true
	C_Timer.After(0.5, UI.Refresh)
end

-- ---------------------------------------------------------------- Klicks und Tooltips
-- Gegenstand unter dem Mauszeiger in einer Aufschluesselungszeile (links: benoetigt, rechts: Rohstoff)
local function tlItemAt(row, it)
	if not it.id then return nil end
	local x = GetCursorPosition() / row:GetEffectiveScale()
	if x < row:GetRight() - 342 then return it.id end
	if it.rawIds and #it.rawIds == 1 then return it.rawIds[1] end
	return nil
end

local function onRowClick(row, btn)
	local it = row.item
	if not it then return end
	local u = cfg()
	if btn == "RightButton" then
		-- Rechtsklick auf den Beruf: alle Kategorien ein- bzw. ausklappen
		if it.t ~= "prof" then return end
		local anyOpen = false
		for _, ck in ipairs(it.cats or {}) do
			if not u.catCollapsed[ck] then anyOpen = true break end
		end
		for _, ck in ipairs(it.cats or {}) do u.catCollapsed[ck] = anyOpen or nil end
		u.collapsed[it.key] = nil
		offset = 0
	elseif it.t == "prof" then
		u.collapsed[it.key] = not u.collapsed[it.key] or nil
	elseif it.t == "cat" then
		u.catCollapsed[it.ck] = not u.catCollapsed[it.ck] or nil
	elseif it.t == "rec" then
		if IsShiftKeyDown() and it.rec.out and it.rec.out > 0 and ns.PriceCheck then
			ns.PriceCheck.ShiftClick(it.rec.out)
			return
		end
		if S.selKey == it.key and S.selRec == it.id then
			S.selKey, S.selRec = nil, nil
		else
			S.selKey, S.selRec = it.key, it.id
			-- offenes Bestellfenster uebernimmt die neue Auswahl
			if ns.Orders and ns.Orders.SelectionChanged then ns.Orders.SelectionChanged() end
		end
		boffset = 0
	elseif it.t == "tl" then
		local id = tlItemAt(row, it)
		if id and IsShiftKeyDown() and ns.PriceCheck then ns.PriceCheck.ShiftClick(id) end
		return
	else
		return
	end
	UI.Refresh()
end

local function recipeTooltip(row, it)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	if it.rec.out and it.rec.out > 0 then
		GameTooltip:SetHyperlink("item:" .. it.rec.out)
	else
		GameTooltip:AddLine(it.name, 1, 1, 1)
	end
	GameTooltip:Show()
end

local function memberTooltip(row, it)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:AddLine(classHex(it.char.class) .. it.name .. "|r")
	local r = ns.Roster.Get(it.name)
	if r and r.rank then GameTooltip:AddLine(r.rank, 0.7, 0.7, 0.7) end
	GameTooltip:AddLine(" ")
	local keys = {}
	for k in pairs(it.char.profs) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b) return (ORDER_IDX[a] or 99) < (ORDER_IDX[b] or 99) end)
	for _, k in ipairs(keys) do
		local p = it.char.profs[k]
		local skill = (p.rank and p.rank > 0) and (p.rank .. (p.max and p.max > 0 and ("/" .. p.max) or "")) or "-"
		GameTooltip:AddDoubleLine(p.name or k, skill .. "  (" .. (p.count or 0) .. " " .. T("Rezepte", "recipes") .. ")", 1, 1, 1, 0.9, 0.8, 0.3)
	end
	if it.char.updated and it.char.updated > 0 then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(T("Daten: ", "Data: ") .. ago(time() - it.char.updated), 0.6, 0.6, 0.6)
	end
	GameTooltip:AddLine(T("Rechtsklick: anflüstern", "Right-click: whisper"), 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

-- ---------------------------------------------------------------- Zeilen bauen
local function buildRow(parent, i)
	local row = CreateFrame("Button", nil, parent)
	row:SetSize(ROW_W, ROW_H)
	row:SetPoint("TOPLEFT", 6, -24 - (i - 1) * ROW_H)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetPoint("TOPLEFT", 0, -1)
	row.bg:SetPoint("BOTTOMRIGHT", 0, 1)
	row.bar = row:CreateTexture(nil, "BORDER")
	row.bar:SetPoint("TOPLEFT", 0, -1)
	row.bar:SetPoint("BOTTOMLEFT", 0, 1)
	row.bar:SetWidth(4)
	local hl = row:CreateTexture(nil, "HIGHLIGHT")
	hl:SetPoint("TOPLEFT", 0, -1)
	hl:SetPoint("BOTTOMRIGHT", 0, 1)
	hl:SetColorTexture(1, 1, 1, 0.05)

	-- Beruf
	row.chevP = row:CreateTexture(nil, "ARTWORK")
	row.chevP:SetSize(14, 14)
	row.chevP:SetPoint("LEFT", 6, 0)
	row.piBox = Box(row, COL.black, COL.border)
	row.piBox:SetSize(20, 20)
	row.piBox:SetPoint("LEFT", 26, 0)
	row.piBox:EnableMouse(false)
	row.piTex = row.piBox:CreateTexture(nil, "ARTWORK")
	row.piTex:SetPoint("TOPLEFT", 1, -1)
	row.piTex:SetPoint("BOTTOMRIGHT", -1, 1)
	row.piTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.profName = FS(row, 14, COL.gold)
	row.profName:SetPoint("LEFT", row.piBox, "RIGHT", 8, 0)
	row.profInfo = FS(row, 11, COL.muted)
	row.profInfo:SetPoint("LEFT", row.profName, "RIGHT", 8, 0)
	row.profLine = row:CreateTexture(nil, "ARTWORK")
	row.profLine:SetHeight(1)
	row.profLine:SetPoint("LEFT", row.profInfo, "RIGHT", 10, 0)
	row.profLine:SetPoint("RIGHT", row, "RIGHT", -10, 0)

	-- Kategorie
	row.chevC = row:CreateTexture(nil, "ARTWORK")
	row.chevC:SetSize(12, 12)
	row.chevC:SetPoint("LEFT", 26, 0)
	row.catName = FS(row, 12, COL.cat)
	row.catName:SetPoint("LEFT", 44, 0)
	row.catInfo = FS(row, 11, COL.muted)
	row.catInfo:SetPoint("LEFT", row.catName, "RIGHT", 6, 0)

	-- Rezept
	row.ricon = row:CreateTexture(nil, "ARTWORK")
	row.ricon:SetSize(18, 18)
	row.ricon:SetPoint("LEFT", 42, 0)
	row.ricon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.recName = FS(row, 12, COL.text)
	row.recName:SetPoint("LEFT", 68, 0)
	row.tag = FS(row, 10, { 0.91, 0.66, 0.42 }, "RIGHT")
	row.tag:SetPoint("RIGHT", row, "RIGHT", -(92 + 250 + 8), 0)
	row.tag:SetWidth(104)
	row.tag:SetText(T("Zwischenprodukt", "Intermediate"))
	row.mats = FS(row, 11, COL.muted)
	row.mats:SetPoint("RIGHT", row, "RIGHT", -92, 0)
	row.mats:SetWidth(250)
	row.crafters = FS(row, 12, COL.gold, "RIGHT")
	row.crafters:SetPoint("RIGHT", row, "RIGHT", -12, 0)
	row.crafters:SetWidth(76)

	-- Aufschluesselung unter dem gewaehlten Rezept
	row.tlLeft = FS(row, 11, COL.text)
	row.tlLeft:SetPoint("LEFT", 60, 0)
	row.tlLeft:SetWidth(300)
	row.tlRaw = FS(row, 11, COL.text)
	row.tlRaw:SetPoint("RIGHT", row, "RIGHT", -92, 0)
	row.tlRaw:SetWidth(250)
	row.pcBtn = Btn(row, T("Preis Check …", "Price check …"), 96, 18, function() if ns.PriceCheck then ns.PriceCheck.Toggle() end end, 11)
	row.pcBtn:SetPoint("RIGHT", -10, 0)
	row.pcBtn:Hide()

	row.parts = {
		prof = { row.chevP, row.piBox, row.profName, row.profInfo, row.profLine },
		cat = { row.chevC, row.catName, row.catInfo },
		rec = { row.ricon, row.recName, row.tag, row.mats, row.crafters },
		tl = { row.tlLeft, row.tlRaw, row.pcBtn },
	}
	row:SetScript("OnClick", onRowClick)
	row:SetScript("OnEnter", function(self)
		if self.item and self.item.t == "rec" then recipeTooltip(self, self.item)
		elseif self.item and self.item.t == "tl" then
			local id = tlItemAt(self, self.item)
			if id then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetHyperlink("item:" .. id)
				GameTooltip:Show()
			end
		end
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return row
end

local function buildMRow(parent, i)
	local row = CreateFrame("Button", nil, parent)
	row:SetSize(ROW_W, MROW_H)
	row:SetPoint("TOPLEFT", 6, -30 - (i - 1) * MROW_H)
	row:RegisterForClicks("RightButtonUp")
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetPoint("TOPLEFT", 0, -1)
	row.bg:SetPoint("BOTTOMRIGHT", 0, 1)
	row.bar = row:CreateTexture(nil, "BORDER")
	row.bar:SetPoint("TOPLEFT", 0, -1)
	row.bar:SetPoint("BOTTOMLEFT", 0, 1)
	row.bar:SetWidth(4)
	local hl = row:CreateTexture(nil, "HIGHLIGHT")
	hl:SetPoint("TOPLEFT", 0, -1)
	hl:SetPoint("BOTTOMRIGHT", 0, 1)
	hl:SetColorTexture(1, 1, 1, 0.05)
	row.face = row:CreateTexture(nil, "ARTWORK")
	row.face:SetSize(18, 18)
	row.face:SetPoint("LEFT", 10, 0)
	row.dot = row:CreateTexture(nil, "ARTWORK")
	row.dot:SetSize(10, 10)
	row.dot:SetPoint("LEFT", row.face, "RIGHT", 6, 0)
	row.nm = FS(row, 13, COL.text)
	row.nm:SetPoint("LEFT", row.dot, "RIGHT", 3, 0)
	row.nm:SetWidth(170)
	row.sub = FS(row, 11, COL.muted)
	row.sub:SetPoint("LEFT", row.nm, "RIGHT", 6, 0)
	row.sub:SetWidth(160)
	row.skRank = FS(row, 11, COL.muted)
	row.skRank:SetPoint("LEFT", row, "RIGHT", -415, 0)
	row.skRank:SetWidth(60)
	row.barBg = row:CreateTexture(nil, "ARTWORK")
	row.barBg:SetSize(120, 6)
	row.barBg:SetPoint("LEFT", row, "RIGHT", -350, 0)
	setc(row.barBg, COL.black)
	row.barFill = row:CreateTexture(nil, "OVERLAY")
	row.barFill:SetHeight(4)
	row.barFill:SetPoint("LEFT", row.barBg, "LEFT", 1, 0)
	row.barFill:SetColorTexture(0.95, 0.76, 0.19, 1)
	row.profsFS = FS(row, 11, COL.muted)
	row.profsFS:SetPoint("LEFT", row, "RIGHT", -415, 0)
	row.profsFS:SetWidth(300)
	row.last = FS(row, 11, COL.muted, "RIGHT")
	row.last:SetPoint("RIGHT", row, "RIGHT", -10, 0)
	row.last:SetWidth(105)
	row:SetScript("OnClick", function(self, btn)
		if btn == "RightButton" and self.item then whisper(self.item.name) end
	end)
	row:SetScript("OnEnter", function(self) if self.item then memberTooltip(self, self.item) end end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return row
end

-- Eigenes Symbol (Zahnrad mit Hammer und Schluessel): Berufsuebersicht, Addon-Symbol und Mini-Knopf.
local ICON = "Interface\\AddOns\\CraftShare\\Media\\Icon"
local function setProfessionsIcon(tex)
	tex:SetTexture(ICON)
	tex:SetTexCoord(0, 1, 0, 1)
end

-- Passt Zeilenzahl, Spaltenbreiten und Bereiche an die aktuelle Fenstergroesse an.
local function layout()
	if not frame or not mid or folded then return end
	local w, h = frame:GetWidth(), frame:GetHeight()
	ROW_W = math.floor(w - 20 - 6 - 24)
	local midH = h - 20 - 24 - TOP_H - BAR_H - BOT_H
	mid:SetHeight(midH)
	ROWS = math.max(5, math.floor((midH - 24 - 8) / ROW_H))
	for i = #rows + 1, ROWS do rows[i] = buildRow(mid, i) end
	for i, row in ipairs(rows) do
		row:SetWidth(ROW_W)
		row.tlLeftW = math.max(100, ROW_W - 60 - 350)
		row.tlLeft:SetWidth(row.tlLeftW)
		if i > ROWS then row.item = nil; row:Hide() end
	end
	mslider:SetHeight(ROWS * ROW_H)
	header:SetWidth(ROW_W)
	-- Spalten der Mitgliederzeilen: Name | Info (flexibel) | Berufe/Skill | online-Status
	local pw = math.max(190, math.min(300, math.floor(ROW_W * 0.32)))
	local px = -(120 + pw)
	local subW = ROW_W - 120 - pw - 203 - 8
	for _, r in ipairs(mrows) do
		r:SetWidth(ROW_W)
		r.nm:SetWidth(150)
		r.sub:SetWidth(math.max(1, subW))
		r.sub:SetShown(subW >= 60)
		r.skRank:ClearAllPoints()
		r.skRank:SetPoint("LEFT", r, "RIGHT", px, 0)
		r.barBg:ClearAllPoints()
		r.barBg:SetPoint("LEFT", r, "RIGHT", px + 64, 0)
		r.barBg:SetWidth(math.min(120, pw - 70))
		r.profsFS:ClearAllPoints()
		r.profsFS:SetPoint("LEFT", r, "RIGHT", px, 0)
		r.profsFS:SetWidth(pw)
	end
	-- Platz zwischen Titel und Suchfeld (Suche, Optionen, Einklappen, X brauchen rechts 364)
	W.sub:SetWidth(math.max(60, (w - 20) - 364 - 20 - math.ceil(W.title and W.title:GetStringWidth() or 140)))
end

-- Eingeklappt ist nur die Kopfleiste zu sehen; die Oberkante bleibt dabei an ihrem Platz
local function applyCollapsed()
	if not frame or not W.bar then return end
	local u = cfg()
	local collapsed = folded
	local es = (S.fitScale or 1) * UI.UserScale()
	local maxW, maxH = math.floor(UIParent:GetWidth() / es), math.floor(UIParent:GetHeight() / es)
	local height = collapsed and (TOP_H + 20) or math.max(MIN_H, (u.size and u.size[2]) or DEF_H)
	local width = math.max(MIN_W, (u.size and u.size[1]) or DEF_W)
	local left, top = frame:GetLeft(), frame:GetTop()

	-- Pfeil nach unten: ausklappen, nach oben: einklappen
	if collapsed then W.collapseBtn.arrow:SetTexCoord(0, 1, 0, 1) else W.collapseBtn.arrow:SetTexCoord(0, 1, 1, 0) end
	mid:SetShown(not collapsed)
	bot:SetShown(not collapsed)
	W.bar:SetShown(not collapsed)
	W.grip:SetShown(not collapsed)
	-- zuerst die Grenzen lockern, dann die Groesse setzen
	if frame.SetResizeBounds then pcall(frame.SetResizeBounds, frame, MIN_W, TOP_H + 20, maxW, math.max(maxH, height)) end
	frame:SetSize(width, height)
	if left and top then
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
		u.pos = { "TOPLEFT", "BOTTOMLEFT", left, top }
	end
	if not collapsed then
		if frame.SetResizeBounds then pcall(frame.SetResizeBounds, frame, MIN_W, MIN_H, maxW, math.max(maxH, height)) end
		layout()
		UI.Refresh()
	end
end

-- Fehler sichtbar machen (Lua-Fehler sind im Spiel oft ausgeblendet)
local function safeCollapse()
	local ok, err = pcall(applyCollapsed)
	if not ok then ns.Print("Einklappen: " .. tostring(err)) end
end

local function build()
	local u = cfg()
	local f = Box(UIParent, COL.bg, COL.border)
	frame = f
	f:Hide()
	-- bisherige Standardbreite (800) auf die neue, schmalere umstellen
	if u.size and u.size[1] == 800 then u.size[1] = DEF_W end
	local sz = u.size or { DEF_W, DEF_H }
	f:SetSize(math.max(MIN_W, sz[1] or DEF_W), math.max(MIN_H, sz[2] or DEF_H))
	-- gleiche Ebene wie die Zusatzfenster: angeklickt oder verschoben kommt es nach vorn
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:Raise(); self:StartMoving() end)
	f:SetScript("OnMouseDown", function(self) self:Raise() end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local p, _, rp, x, y = self:GetPoint()
		cfg().pos = { p, rp, x, y }
	end)
	local s = math.min(1, UIParent:GetHeight() / (MIN_H + 10), UIParent:GetWidth() / (MIN_W + 10))
	S.fitScale = s
	f:SetScale(s * UI.UserScale())
	f:SetResizable(true)
	local es = s * UI.UserScale()
	local maxW, maxH = math.floor(UIParent:GetWidth() / es), math.floor(UIParent:GetHeight() / es)
	if f.SetResizeBounds then f:SetResizeBounds(MIN_W, MIN_H, maxW, maxH)
	elseif f.SetMinResize then f:SetMinResize(MIN_W, MIN_H); if f.SetMaxResize then f:SetMaxResize(maxW, maxH) end end
	if u.pos then
		f:SetPoint(u.pos[1], UIParent, u.pos[2], u.pos[3], u.pos[4])
	else
		f:SetPoint("CENTER")
	end
	tinsert(UISpecialFrames, "CraftShareFrame")
	_G.CraftShareFrame = f

	-- ---- Kopf
	local top = Box(f, COL.panel, COL.border)
	top:SetPoint("TOPLEFT", 10, -10)
	top:SetPoint("TOPRIGHT", -10, -10)
	top:SetHeight(TOP_H)
	top:SetFrameLevel(f:GetFrameLevel() + 1)

	local title = FS(top, 18, COL.gold)
	title:SetPoint("TOPLEFT", 10, -8)
	title:SetText(T("Gildenberufe", "Guild professions"))
	W.title = title
	W.sub = FS(top, 12, COL.muted)
	W.sub:SetPoint("LEFT", title, "RIGHT", 10, -1)
	W.sub:SetWidth(200)

	local close = Btn(f, "X", 22, 22, function() f:Hide() end)
	close:SetPoint("TOPRIGHT", top, "TOPRIGHT", -10, -6)
	close:SetFrameLevel(top:GetFrameLevel() + 5)

	-- Optionen: kleines Popup mit Sync und Auto-Sync
	local optBtn = Btn(top, T("Optionen", "Options"), 74, 22, function()
		W.opts:SetShown(not W.opts:IsShown())
	end)
	optBtn:SetPoint("TOPRIGHT", -64, -6)
	-- Einklappen: zwischen Optionen und X
	W.collapseBtn = Btn(top, "", 22, 22, function()
		folded = not folded
		W.opts:Hide()
		GameTooltip:Hide()
		safeCollapse()
	end)
	W.collapseBtn:SetPoint("TOPRIGHT", -38, -6)
	W.collapseBtn.arrow = W.collapseBtn:CreateTexture(nil, "OVERLAY")
	W.collapseBtn.arrow:SetSize(16, 16)
	W.collapseBtn.arrow:SetPoint("CENTER", 0, 0)
	W.collapseBtn.arrow:SetTexture("Interface\\AddOns\\CraftShare\\Media\\Chevron")
	W.collapseBtn.arrow:SetVertexColor(COL.gold[1], COL.gold[2], COL.gold[3])
	W.collapseBtn.arrow:SetTexCoord(0, 1, 1, 0)
	W.collapseBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine(folded and T("Fenster ausklappen", "Expand window")
			or T("Bis auf die Kopfleiste einklappen", "Collapse to the header bar"), 1, 1, 1)
		GameTooltip:Show()
	end)
	W.collapseBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	W.opts = Box(f, COL.bg, COL.border)
	W.opts:SetSize(340, 348)
	W.opts:SetPoint("TOPRIGHT", optBtn, "BOTTOMRIGHT", 0, -2)
	W.opts:SetFrameStrata("FULLSCREEN_DIALOG") -- eine Ebene ueber dem Hauptfenster, sonst vermischen sich die Inhalte
	-- Klicks und Mausrad nicht an die Fenster darunter durchlassen
	W.opts:EnableMouse(true)
	W.opts:EnableMouseWheel(true)
	W.opts:SetScript("OnMouseWheel", function() end)
	W.opts:Hide()
	local function optHead(text, y)
		local h = FS(W.opts, 10, COL.goldDim)
		h:SetPoint("TOPLEFT", 12, y)
		h:SetText(text:upper())
	end
	local function priceChanged() UI.Refresh() end
	optHead(T("Allgemein", "General"), -10)
	local ver = FS(W.opts, 10, COL.muted, "RIGHT")
	ver:SetPoint("TOPRIGHT", -12, -10)
	ver:SetText("Guild CraftShare " .. T("Version ", "version ") .. ns.VERSION)
	local sync = Btn(W.opts, "Sync", 150, 22, function() SlashCmdList["CRAFTSHARE"]("sync"); UI.Refresh() end)
	sync:SetPoint("TOPLEFT", 12, -26)
	W.auto = Btn(W.opts, "", 150, 22, function()
		ns.db.autoSync = not ns.db.autoSync
		UI.Refresh()
	end)
	W.auto:SetPoint("TOPRIGHT", -12, -26)
	-- UI-Skalierung
	local sl = FS(W.opts, 11, COL.text)
	sl:SetPoint("TOPLEFT", 12, -58)
	sl:SetText(T("UI-Skalierung", "UI scale"))
	local plusB = Btn(W.opts, "+", 22, 22, function() UI.SetUserScale(UI.UserScale() + 0.05) end)
	plusB:SetPoint("TOPRIGHT", -12, -54)
	W.scaleVal = FS(W.opts, 12, COL.gold, "CENTER")
	W.scaleVal:SetSize(52, 22)
	W.scaleVal:SetPoint("RIGHT", plusB, "LEFT", -4, 0)
	local minusB = Btn(W.opts, "-", 22, 22, function() UI.SetUserScale(UI.UserScale() - 0.05) end)
	minusB:SetPoint("RIGHT", W.scaleVal, "LEFT", -4, 0)
	W.skillChk = CreateFrame("CheckButton", nil, W.opts, "UICheckButtonTemplate")
	W.skillChk:SetSize(22, 22)
	W.skillChk:SetPoint("TOPLEFT", 10, -230)
	W.skillChk:SetScript("OnClick", function(self)
		cfg().skillOnly = self:GetChecked() and true or false
		offset = 0
		UI.Refresh()
	end)
	local skt = FS(W.opts, 11, COL.text)
	skt:SetPoint("LEFT", W.skillChk, "RIGHT", 2, 0)
	skt:SetText(T("Nur Rezepte mit Skillpunkten", "Only recipes that give skill points"))
	optHead(T("Preise", "Prices"), -88)
	W.srcBtn = Btn(W.opts, "", 316, 22, function() ns.Prices.CycleSource(); priceChanged() end)
	W.srcBtn:SetPoint("TOPLEFT", 12, -104)
	W.ptBtn = Btn(W.opts, "", 316, 22, function()
		local ps = ns.Prices.Settings()
		ps.ptype = (ps.ptype == "market") and "min" or "market"
		priceChanged()
	end)
	W.ptBtn:SetPoint("TOPLEFT", 12, -130)
	W.chks = {}
	local function Chk(key, label, y)
		local c = CreateFrame("CheckButton", nil, W.opts, "UICheckButtonTemplate")
		c:SetSize(22, 22)
		c:SetPoint("TOPLEFT", 10, y)
		c:SetScript("OnClick", function(self)
			ns.Prices.Settings()[key] = self:GetChecked() and true or false
			priceChanged()
		end)
		local t = FS(W.opts, 11, COL.text)
		t:SetPoint("LEFT", c, "RIGHT", 2, 0)
		t:SetText(label)
		c.key = key
		W.chks[#W.chks + 1] = c
	end
	Chk("vendor", T("Händlerpreise einbeziehen (günstigster gewinnt)", "Include vendor prices (cheapest wins)"), -158)
	Chk("chain", T("Herstellungskette prüfen (Leder, Barren, …)", "Check crafting chain (leather, bars, …)"), -182)
	Chk("free", T("Vorhandene Materialien kostenlos rechnen", "Count owned materials as free"), -206)
	-- Ton bei neuen Auftraegen: Klick wechselt und spielt ihn ab
	W.soundBtn = Btn(W.opts, "", 316, 22, function(self)
		ns.Mini.CycleSound()
		self.label:SetText(T("Ton neuer Auftrag: ", "New order sound: ") .. ns.Mini.SoundName())
	end)
	W.soundBtn:SetPoint("BOTTOMLEFT", 12, 46)
	-- ganz unten: Stand der Preisdaten
	W.priceInfo = FS(W.opts, 11, COL.muted)
	W.priceInfo:SetPoint("BOTTOMLEFT", 12, 10)
	W.priceInfo:SetWidth(316)
	W.priceInfo:SetWordWrap(true)
	W.priceInfo:SetJustifyV("BOTTOM")
	-- Post am Briefkasten selbst ausfuellen (Senden drueckt immer der Spieler)
	W.autoMailChk = CreateFrame("CheckButton", nil, W.opts, "UICheckButtonTemplate")
	W.autoMailChk:SetSize(22, 22)
	W.autoMailChk:SetPoint("BOTTOMLEFT", 10, 72)
	W.autoMailChk:SetScript("OnClick", function(self) ns.db.autoMail = self:GetChecked() and true or false end)
	local amt = FS(W.opts, 11, COL.text)
	amt:SetPoint("LEFT", W.autoMailChk, "RIGHT", 2, 0)
	amt:SetText(T("Post automatisch vorbereiten", "Prepare mail automatically"))

	local sbox = Box(top, COL.black, COL.border)
	sbox:SetPoint("RIGHT", optBtn, "LEFT", -8, 0)
	sbox:SetSize(210, 22)
	local clearBtn = Btn(sbox, "x", 16, 16, function()
		searchBox:SetText("")
		searchBox:ClearFocus()
	end, 11)
	clearBtn:SetPoint("RIGHT", -3, 0)
	clearBtn:Hide()
	searchBox = CreateFrame("EditBox", nil, sbox)
	searchBox:SetPoint("TOPLEFT", 6, -2)
	searchBox:SetPoint("BOTTOMRIGHT", -24, 2)
	searchBox:SetAutoFocus(false)
	searchBox:SetFont(STANDARD_TEXT_FONT, 12, "")
	searchBox:SetTextColor(COL.text[1], COL.text[2], COL.text[3])
	local ph = FS(sbox, 12, COL.muted)
	ph:SetPoint("LEFT", 8, 0)
	ph:SetWidth(196)
	ph:SetJustifyH("LEFT")
	ph:SetWordWrap(false)
	ph:SetText(T("Rezept, Material oder Spieler …", "Recipe, material or player …"))
	searchBox:SetScript("OnTextChanged", function(self)
		ph:SetShown(self:GetText() == "")
		clearBtn:SetShown(self:GetText() ~= "")
		offset = 0
		UI.Refresh()
	end)
	searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

	W.iconRow = CreateFrame("Frame", nil, top)
	W.iconRow:SetPoint("TOPLEFT", 10, -40)
	W.iconRow:SetSize(600, 36)
	W.allBtn = Box(W.iconRow, COL.black, COL.border, "Button")
	W.allBtn:SetSize(36, 36)
	W.allBtn:SetPoint("LEFT", 0, 0)
	local at = W.allBtn:CreateTexture(nil, "ARTWORK")
	at:SetPoint("TOPLEFT", 3, -3)
	at:SetPoint("BOTTOMRIGHT", -3, 3)
	at:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	setProfessionsIcon(at)
	W.allCnt = FS(W.allBtn, 10, COL.text, "RIGHT")
	W.allCnt:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
	W.allCnt:SetPoint("BOTTOMRIGHT", -2, 2)
	local ahl = W.allBtn:CreateTexture(nil, "HIGHLIGHT")
	ahl:SetAllPoints()
	ahl:SetColorTexture(1, 1, 1, 0.1)
	local function allShown()
		local u = cfg()
		for _, b in ipairs(iconBtns) do
			if b:IsShown() and u.hidden[b.key] then return false end
		end
		return true
	end
	W.allBtn:SetScript("OnClick", function()
		local u = cfg()
		if allShown() then
			for _, b in ipairs(iconBtns) do
				if b:IsShown() then u.hidden[b.key] = true end
			end
			S.selKey, S.selRec = nil, nil
		else
			u.hidden = {}
		end
		offset, boffset = 0, 0
		UI.Refresh()
	end)
	W.allBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine(allShown() and T("Alle Berufe ausblenden", "Hide all professions") or T("Alle Berufe anzeigen", "Show all professions"), 1, 1, 1)
		GameTooltip:Show()
	end)
	W.allBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- Bestellen / Offene Auftraege (jeweils ein kleines Fenster)
	W.openBtn = Btn(top, "", 140, 24, function() ns.Orders.ToggleList() end)
	W.openBtn:SetPoint("TOPRIGHT", -10, -46)
	-- Versionshinweis links neben "Auftraege"
	W.verBox = CreateFrame("Frame", nil, top)
	W.verBox:SetSize(260, 24)
	W.verBox:SetPoint("RIGHT", W.openBtn, "LEFT", -12, 0)
	W.verText = FS(W.verBox, 12, COL.orange, "RIGHT")
	W.verText:SetPoint("RIGHT", 0, 0)
	W.verText:SetWidth(260)
	W.verBox:EnableMouse(true)
	W.verBox:SetScript("OnEnter", function(self)
		local nv = ns.NewerVersion()
		if not nv then return end
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine(string.format(T("%s nutzt Version %s, du hast %s.", "%s uses version %s, you have %s."),
			nv.by or "?", nv.v, ns.VERSION), 1, 1, 1)
		GameTooltip:AddLine(T("Download: ", "Download: ") .. ns.DOWNLOAD, 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	W.verBox:SetScript("OnLeave", function() GameTooltip:Hide() end)
	W.verBox:Hide()
	-- Leiste zwischen Rezepten und Herstellern
	local bar = Box(f, COL.panel, COL.border)
	W.bar = bar
	bar:SetHeight(BAR_H)
	bar:SetPoint("BOTTOMLEFT", 10, 10 + BOT_H + 8)
	bar:SetPoint("BOTTOMRIGHT", -10, 10 + BOT_H + 8)
	W.orderBtn = Btn(bar, T("Bestellen", "Order"), 100, 22, function() ns.Orders.ToggleOrder() end)
	W.orderBtn:SetPoint("RIGHT", -8, 0)

	-- ---- Mitte: Berufe
	mid = Box(f, COL.panel, COL.border)
	mid:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -8)
	mid:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT", 0, -8)
	mid:SetHeight(400)
	header = CreateFrame("Frame", nil, mid)
	header:SetPoint("TOPLEFT", 6, -5)
	header:SetSize(ROW_W, 16)
	local h1 = FS(header, 11, COL.gold)
	h1:SetPoint("LEFT", 10, 0)
	h1:SetText(T("Rezept", "Recipe"))
	local h2 = FS(header, 11, COL.gold)
	h2:SetPoint("RIGHT", header, "RIGHT", -92, 0)
	h2:SetWidth(250)
	h2:SetText(T("Rohstoffe (gesamt)", "Raw materials (total)"))
	local h3 = FS(header, 11, COL.gold, "RIGHT")
	h3:SetPoint("RIGHT", header, "RIGHT", -12, 0)
	h3:SetWidth(76)
	h3:SetText(T("Hersteller", "Crafters"))

	rows = {}
	for i = 1, ROWS do rows[i] = buildRow(mid, i) end
	W.empty = FS(mid, 13, COL.muted, "CENTER")
	W.empty:SetPoint("CENTER", mid, "CENTER", 0, 0)
	W.empty:SetWidth(600)
	W.empty:SetText(T("Keine Einträge. Öffne ein Berufsfenster oder blende Berufe über die Symbole ein.", "No entries. Open a profession window or show professions via the icons."))
	W.empty:Hide()
	mslider = MakeSlider(mid, function(v) if v ~= offset then offset = v; renderList() end end)
	mslider:SetPoint("TOPRIGHT", -6, -26)
	mslider:SetHeight(ROWS * ROW_H)
	mid:EnableMouseWheel(true)
	mid:SetScript("OnMouseWheel", function(_, delta)
		offset = math.max(0, offset - delta * 3)
		renderList()
	end)

	-- ---- Unten: Mitglieder
	bot = Box(f, COL.panel, COL.border)
	bot:SetPoint("BOTTOMLEFT", 10, 10)
	bot:SetPoint("BOTTOMRIGHT", -10, 10)
	bot:SetHeight(BOT_H)
	W.btitle = FS(bot, 13, COL.gold)
	W.btitle:SetPoint("TOPLEFT", 10, -9)
	W.btitle:SetWidth(330)

	W.segAll = Btn(bot, T("Alle im Beruf", "All in profession"), 96, 18, function() cfg().tab = "all"; boffset = 0; UI.Refresh() end, 11)
	W.segAll:SetPoint("TOPRIGHT", -10, -6)
	W.segCr = Btn(bot, T("Hersteller", "Crafters"), 76, 18, function() cfg().tab = "cr"; boffset = 0; UI.Refresh() end, 11)
	W.segCr:SetPoint("RIGHT", W.segAll, "LEFT", -1, 0)
	W.onlineChk = CreateFrame("CheckButton", nil, bot, "UICheckButtonTemplate")
	W.onlineChk:SetSize(22, 22)
	W.onlineChk:SetPoint("TOPRIGHT", -10 - 96 - 76 - 100, -4)
	W.onlineChk:SetScript("OnClick", function(self)
		cfg().onlineOnly = self:GetChecked() and true or nil
		offset, boffset = 0, 0
		UI.Refresh()
	end)
	local oc = FS(bot, 11, COL.muted)
	oc:SetPoint("LEFT", W.onlineChk, "RIGHT", 0, 0)
	oc:SetText(T("Nur online", "Online only"))

	mrows = {}
	for i = 1, MROWS do mrows[i] = buildMRow(bot, i) end
	W.bempty = FS(bot, 12, COL.muted, "CENTER")
	W.bempty:SetPoint("CENTER", bot, "CENTER", 0, -10)
	W.bempty:SetText(T("Niemand gefunden.", "Nobody found."))
	W.bempty:Hide()
	bslider = MakeSlider(bot, function(v) if v ~= boffset then boffset = v; renderBottom() end end)
	bslider:SetPoint("TOPRIGHT", -6, -30)
	bslider:SetHeight(MROWS * MROW_H)
	bot:EnableMouseWheel(true)
	bot:SetScript("OnMouseWheel", function(_, delta)
		boffset = math.max(0, boffset - delta)
		renderBottom()
	end)

	-- ---- Groesse ziehen: Ecke unten rechts (Minimum 800x800)
	local grip = CreateFrame("Button", nil, f)
	W.grip = grip
	grip:SetSize(18, 18)
	grip:SetPoint("BOTTOMRIGHT", -2, 2)
	grip:SetFrameLevel(bot:GetFrameLevel() + 10)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetScript("OnMouseDown", function()
		-- oben links verankern, damit das Fenster nur nach rechts/unten waechst
		local left, topY = f:GetLeft(), f:GetTop()
		if left and topY then
			f:ClearAllPoints()
			f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, topY)
		end
		f:StartSizing("BOTTOMRIGHT")
	end)
	grip:SetScript("OnMouseUp", function()
		f:StopMovingOrSizing()
		local uu = cfg()
		uu.size = { math.floor(f:GetWidth() + 0.5), math.floor(f:GetHeight() + 0.5) }
		local p, _, rp, x, y = f:GetPoint()
		uu.pos = { p, rp, x, y }
		layout()
		UI.Refresh()
	end)

	layout()
	f:SetScript("OnSizeChanged", function()
		if folded then return end
		layout()
		renderList()
		renderBottom()
		renderIcons()
	end)

	f:SetScript("OnShow", function()
		ns.Roster.Request()
		ns.Roster.Update()
		UI.Refresh()
		if f.ticker then f.ticker:Cancel() end
		f.ticker = C_Timer.NewTicker(30, function()
			if f:IsShown() then ns.Roster.Request(); UI.Refresh() end
		end)
	end)
	f:SetScript("OnHide", function()
		if f.ticker then f.ticker:Cancel(); f.ticker = nil end
		W.opts:Hide() -- beim naechsten Oeffnen ist das Optionenfenster zu
	end)
	f:HookScript("OnShow", function() relayoutDocks() end)
	f:HookScript("OnSizeChanged", function() relayoutDocks() end)
	-- beim Schliessen wieder ausklappen, damit das Fenster immer vollstaendig aufgeht
	f:HookScript("OnHide", function()
		if folded then
			folded = false
			safeCollapse()
		end
	end)
end

-- ---------------------------------------------------------------- Angedockte Fenster
-- Auftragsliste, Bestellen, Auftrag und Preis Check haengen sich an das Hauptfenster: nebeneinander rechts davon,
-- reicht der Platz nicht, links davon. Wer ein Fenster verschiebt, loest es bis zum Schliessen.
local docked = {}

relayoutDocks = function()
	if not frame or not frame:IsShown() then return end
	local sw = UIParent:GetWidth() * UIParent:GetEffectiveScale()
	local right, left = frame, frame
	for _, f in ipairs(docked) do
		if f:IsShown() and not f.csMoved then
			local es = f:GetEffectiveScale()
			local w = f:GetWidth() * es
			local r = (right:GetRight() or 0) * right:GetEffectiveScale()
			f:ClearAllPoints()
			if r + 6 * es + w <= sw then
				f:SetPoint("TOPLEFT", right, "TOPRIGHT", 6, 0)
				right = f
			else
				f:SetPoint("TOPRIGHT", left, "TOPLEFT", -6, 0)
				left = f
			end
		end
	end
end

-- Kanten eines Fensters in Bildschirmpunkten
local function edges(f)
	local es = f:GetEffectiveScale()
	return (f:GetLeft() or 0) * es, (f:GetRight() or 0) * es, (f:GetTop() or 0) * es, (f:GetBottom() or 0) * es
end

-- Wurde ein Fenster nahe an das Hauptfenster (oder ein angedocktes Fenster) gezogen? Dann daran einrasten.
local SNAP = 15
local function snapTarget(f)
	if not frame or not frame:IsShown() then return end
	local l, r, t, b = edges(f)
	local cands = { frame }
	for _, g in ipairs(docked) do
		if g ~= f and g:IsShown() and not g.csMoved then cands[#cands + 1] = g end
	end
	local best, dist
	for _, c in ipairs(cands) do
		local cl, cr, ct, cb = edges(c)
		if t > cb and b < ct then -- uebereinander liegende Bereiche
			for _, d in ipairs({ math.abs(l - cr), math.abs(r - cl) }) do
				if d < SNAP and (not dist or d < dist) then best, dist = c, d end
			end
		end
	end
	return best
end

function UI.Dockable(f)
	if not f or f.csDock then return end
	f.csDock = true
	local home = { f:GetPoint(1) }
	-- alle Zusatzfenster in derselben Ebene, das angeklickte/verschobene liegt ganz oben (ohne Durchscheinen)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:HookScript("OnMouseDown", function(self) self:Raise() end)
	f:HookScript("OnDragStart", function(self) self:Raise() end)
	f:HookScript("OnShow", function(self)
		for i, g in ipairs(docked) do if g == self then table.remove(docked, i) break end end
		docked[#docked + 1] = self -- zuletzt geoeffnet = ganz aussen
		self.csMoved = nil
		self:Raise()
		if frame and frame:IsShown() then
			relayoutDocks()
		elseif home[1] and self:GetNumPoints() > 0 and select(2, self:GetPoint(1)) == frame then
			-- Hauptfenster zu: an den eigenen Platz
			self:ClearAllPoints()
			self:SetPoint(unpack(home))
		end
	end)
	f:HookScript("OnHide", function() relayoutDocks() end)
	f:HookScript("OnDragStop", function(self)
		local target = snapTarget(self)
		if target then
			-- neben dem Ziel einreihen
			for i, g in ipairs(docked) do if g == self then table.remove(docked, i) break end end
			local pos = 1
			for i, g in ipairs(docked) do if g == target then pos = i + 1 end end
			table.insert(docked, pos, self)
			self.csMoved = nil
		else
			self.csMoved = true
		end
		relayoutDocks()
	end)
	if f:IsShown() then relayoutDocks() end
end

function UI.Toggle()
	if not frame then build() end
	if frame:IsShown() then frame:Hide() else frame:Show() end
end

-- Item-Namen kommen verzoegert vom Server, Taschen aendern den Bestand: dann neu zeichnen.
local ev = CreateFrame("Frame")
ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:SetScript("OnEvent", function() UI.Dirty() end)
