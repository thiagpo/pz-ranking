-- Bagres Stats: eventos do servidor (abates por arma, mortes) e gravacao periodica
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

local function onDisconnect()
    S.flush()
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
if Events.OnDisconnect then Events.OnDisconnect.Add(onDisconnect) end
if Events.EveryOneMinute then Events.EveryOneMinute.Add(function() S.flush() end) end
