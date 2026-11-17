-- Bagres Stats: busca da marreta em Lua puro, sem callback Java->Lua (falha no servidor 42.22)
require "TimedActions/ISDestroyStuffAction"

local function marreta(inv)
    local items = inv:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        local tipo = it:getType()
        if not it:isBroken() and (it:hasTag(ItemTag.SLEDGEHAMMER) or tipo == "Sledgehammer" or tipo == "Sledgehammer2") then
            return it
        end
        if it:IsInventoryContainer() then
            local r = marreta(it:getInventory())
            if r then return r end
        end
    end
    return nil
end

function ISDestroyStuffAction:hasSledgehammerInRange(character, item)
    if not item then return false end
    local m = marreta(character:getInventory())
    if not m and getDebug() then m = instanceItem(ItemKey.Weapon.SLEDGEHAMMER) end
    if not m then return false end
    if isClient() and self.wasValid == nil then
        self.wasValid = self.item:getObjectIndex() ~= -1
    end
    if self.item:getObjectIndex() == -1 then
        if isClient() then return self.wasValid end
        return false
    end
    local dx = math.abs(item:getSquare():getX() + 0.5 - character:getX())
    local dy = math.abs(item:getSquare():getY() + 0.5 - character:getY())
    return dx <= 1.6 and dy <= 1.6
end
