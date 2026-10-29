-- Bagres Stats (cliente): saque. Transferencias de container rodam no cliente;
-- so o proprio jogador e contado e os totais vao para o servidor a cada 30 s.
if not isClient() then return end
BagresStatsClient = BagresStatsClient or {}
local C = BagresStatsClient
local pending = {}
local seen = {}

local function queue(key, n)
    pending[key] = (pending[key] or 0) + (n or 1)
end

local function flush()
    local player = getPlayer()
    if not player then return end
    local any = false
    for _ in pairs(pending) do any = true; break end
    if not any then return end
    sendClientCommand(player, "BagresStats", "inc", pending)
    pending = {}
end

local function isPlayerContainer(container, character)
    if not container then return false end
    local ok, r = pcall(function() return container:isInCharacterInventory(character) end)
    return ok and r == true
end

local function containerKey(container)
    local ok, key = pcall(function()
        local parent = container:getParent()
        local t = container:getType() or "?"
        if parent and parent.getSquare and parent:getSquare() then
            local sq = parent:getSquare()
            return t .. "@" .. sq:getX() .. "," .. sq:getY() .. "," .. sq:getZ()
        end
        return nil
    end)
    if ok then return key end
    return nil
end

local function install()
    if not ISInventoryTransferAction or C.installed then return end
    C.installed = true
    local orig = ISInventoryTransferAction.transferItem
    ISInventoryTransferAction.transferItem = function(self, item)
        local r = orig(self, item)
        pcall(function()
            local ch = self.character
            if not ch or not ch.isLocalPlayer or not ch:isLocalPlayer() then return end
            local src, dst = self.srcContainer, self.destContainer
            if not src or not dst then return end
            if isPlayerContainer(src, ch) then return end
            if src:getType() == "floor" then return end
            if not isPlayerContainer(dst, ch) then return end
            local parent = src:getParent()
            if parent and instanceof(parent, "IsoPlayer") then return end
            queue("loot.items", 1)
            if parent and instanceof(parent, "IsoDeadBody") then queue("loot.corpses_items", 1) end
            local key = containerKey(src)
            if key and not seen[key] then
                seen[key] = true
                queue("loot.containers", 1)
            end
        end)
        return r
    end
end

Events.OnGameStart.Add(install)
Events.EveryOneMinute.Add(flush)
if Events.OnPlayerDeath then Events.OnPlayerDeath.Add(function() seen = {} end) end
