-- Bagres Stats: eventos do servidor (abates por arma, mortes, clima, exploracao) e gravacao periodica
if not BagresStats then return end
local S = BagresStats

local lastHit = setmetatable({}, { __mode = "k" })

local function weaponType(weapon)
    if not weapon then return "Base.BareHands" end
    local ok, t = pcall(function() return weapon:getFullType() end)
    if ok and t then return t end
    return "desconhecido"
end

local function onWeaponHitCharacter(attacker, target, weapon, damage)
    if not attacker or not target then return end
    if not instanceof(attacker, "IsoPlayer") or not instanceof(target, "IsoZombie") then return end
    lastHit[target] = { player = attacker, weapon = weaponType(weapon) }
end

local function onZombieDead(zombie)
    if not zombie then return end
    local ok, fake = pcall(function() return zombie:isFakeDead() end)
    if ok and fake then return end
    local killer = nil
    pcall(function() killer = zombie:getAttackedBy() end)
    if not killer or not instanceof(killer, "IsoPlayer") then
        local lh = lastHit[zombie]
        if lh and lh.player then killer = lh.player else return end
    end
    local weapon
    local inVehicle = false
    pcall(function() inVehicle = killer:getVehicle() ~= nil end)
    if inVehicle then
        weapon = "Vehicle"
    else
        local lh = lastHit[zombie]
        if lh and lh.player == killer then weapon = lh.weapon else
            local ok2, item = pcall(function() return killer:getPrimaryHandItem() end)
            weapon = (ok2 and item) and weaponType(item) or "Base.BareHands"
        end
    end
    lastHit[zombie] = nil
    S.inc(killer, "kills")
    S.inc(killer, "kills.weapon." .. (weapon:gsub("[^%w%._%-]", "_")))
end

local function onPlayerDeath(player)
    if not player or not instanceof(player, "IsoPlayer") then return end
    S.inc(player, "deaths")
    local infected = false
    pcall(function() infected = player:getBodyDamage():isInfected() end)
    if infected then S.inc(player, "deaths.infected") end
    local ok, v = pcall(function() return player:getVehicle() ~= nil end)
    if ok and v then S.inc(player, "deaths.vehicle") end
    S.flush()
end

-- contadores enviados pelo cliente (saque): so chaves permitidas
local ALLOWED = { ["loot.items"] = true, ["loot.containers"] = true, ["loot.corpses_items"] = true }
local function onClientCommand(module, command, player, args)
    if module ~= "BagresStats" or command ~= "inc" or type(args) ~= "table" then return end
    for k, n in pairs(args) do
        if ALLOWED[k] and type(n) == "number" and n > 0 and n < 10000 then
            S.inc(player, k, math.floor(n))
        end
    end
end

-- a cada minuto real: clima, noite, exploracao, distancia da base
local base = nil
local function baseXY()
    if base ~= nil then return base end
    base = false
    pcall(function()
        local sp = getServerOptions():getOption("SpawnPoint")
        local x, y = sp:match("^(-?%d+),(-?%d+)")
        if x and y and tonumber(x) ~= 0 then base = { x = tonumber(x), y = tonumber(y) } end
    end)
    return base
end

local function everyMinute()
    S.flush()
    local players = getOnlinePlayers()
    if not players then return end
    local rain, snow, dark = false, false, false
    pcall(function()
        local cm = getClimateManager()
        snow = cm:getSnowStrength() > 0.05 and cm:getPrecipitationIntensity() > 0.05
        rain = (not snow) and cm:getPrecipitationIntensity() > 0.05
        dark = cm:getDayLightStrength() < 0.25
    end)
    local b = baseXY()
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        pcall(function()
            if not p or p:isDead() then return end
            S.inc(p, "online_min")
            local outside = p:isOutside()
            if outside and rain then S.inc(p, "weather.rain_min") end
            if outside and snow then S.inc(p, "weather.snow_min") end
            if outside and dark then S.inc(p, "night.out_min") end
            if b then
                local d = math.sqrt((p:getX() - b.x) ^ 2 + (p:getY() - b.y) ^ 2)
                S.max(p, "explore.maxdist", math.floor(d))
            end
            local sq = p:getSquare()
            if sq then
                local md = p:getModData()
                local bld = sq:getBuilding()
                if bld then
                    local id = nil
                    pcall(function() id = bld:getID() end)
                    if id == nil then pcall(function() local d = bld:getDef(); id = d:getX() .. "," .. d:getY() end) end
                    if id ~= nil then
                        md.BagresBld = md.BagresBld or {}
                        local k = tostring(id)
                        if not md.BagresBld[k] then md.BagresBld[k] = true; S.inc(p, "explore.buildings") end
                    end
                end
                local zones = getZones(sq:getX(), sq:getY(), sq:getZ())
                if zones then
                    for j = 0, zones:size() - 1 do
                        local z = zones:get(j)
                        if z:getType() == "TownZone" then
                            local name = z:getName()
                            if name and name ~= "" then S.max(p, "towns." .. (name:gsub("[^%w%._%-]", "_")), 1) end
                        end
                    end
                end
            end
        end)
    end
end

local function start()
    if not isServer() then return end
    S.installHooks()
    print("[BagresStats] servidor pronto, versao " .. S.VERSION)
end

if Events.OnServerStarted then Events.OnServerStarted.Add(start) end
if Events.OnGameStart then Events.OnGameStart.Add(start) end
if Events.OnWeaponHitCharacter then Events.OnWeaponHitCharacter.Add(onWeaponHitCharacter) end
if Events.OnZombieDead then Events.OnZombieDead.Add(onZombieDead) end
if Events.OnPlayerDeath then Events.OnPlayerDeath.Add(onPlayerDeath) end
if Events.OnClientCommand then Events.OnClientCommand.Add(onClientCommand) end
if Events.OnDisconnect then Events.OnDisconnect.Add(function() S.flush() end) end
if Events.EveryOneMinute then Events.EveryOneMinute.Add(everyMinute) end
