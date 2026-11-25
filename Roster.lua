-- CraftShare: Gilden-Roster (Online-Status, Stufe, Rang, "zuletzt online").
local ADDON, ns = ...
local R = {}
ns.Roster = R

local info = {}
local pending = false

function R.Update()
	pending = false
	wipe(info)
	if not (IsInGuild and IsInGuild()) then return end
	local n = GetNumGuildMembers and GetNumGuildMembers() or 0
	for i = 1, n do
		local ok, name, rankName, _, level, _, _, _, _, online, _, classFile = pcall(GetGuildRosterInfo, i)
		if ok and name then
			local e = { online = online and true or false, level = level, rank = rankName, class = classFile }
			if not e.online and GetGuildRosterLastOnline then
				local ok2, y, m, d, h = pcall(GetGuildRosterLastOnline, i)
				if ok2 then e.last = ((y or 0) * 365 + (m or 0) * 30 + (d or 0)) * 86400 + (h or 0) * 3600 end
			end
			info[ns.ShortName(name)] = e
		end
	end
	-- Voller Name (mit Nachname) des eigenen Charakters: genau ein Gildenmitglied "Vorname Nachname"
	-- mit gleicher Stufe und Klasse passt.
	local first = UnitName("player")
	if first and not (ns.fullName and ns.fullName ~= first) then
		local lvl = UnitLevel("player")
		local _, class = UnitClass("player")
		local cand, n = nil, 0
		for name, e in pairs(info) do
			if name:sub(1, #first + 1) == first .. " " and e.level == lvl and (not e.class or e.class == class) then
				cand, n = name, n + 1
			end
		end
		if n == 1 then ns.SetFullName(cand) end
	end
end

function R.Request()
	if not (IsInGuild and IsInGuild()) then return end
	if C_GuildInfo and C_GuildInfo.GuildRoster then
		pcall(C_GuildInfo.GuildRoster)
	elseif GuildRoster then
		pcall(GuildRoster)
	end
end

function R.Get(name)
	return info[name]
end

function R.IsOnline(name)
	if name == ns.Me() then return true end
	local e = info[name]
	if e and e.online then return true end
	if UnitExists and UnitExists(name) and UnitIsConnected and UnitIsConnected(name) then return true end
	return false
end

function R.GuildName()
	if IsInGuild and IsInGuild() and GetGuildInfo then
		local ok, n = pcall(GetGuildInfo, "player")
		if ok and n then return n end
	end
	return nil
end

local f = CreateFrame("Frame")
f:RegisterEvent("GUILD_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, ev)
	if ev == "PLAYER_LOGIN" then
		C_Timer.After(5, R.Request)
		return
	end
	if pending then return end
	pending = true
	C_Timer.After(1, function()
		R.Update()
		if ns.UI and ns.UI.Dirty then ns.UI.Dirty() end
	end)
end)
