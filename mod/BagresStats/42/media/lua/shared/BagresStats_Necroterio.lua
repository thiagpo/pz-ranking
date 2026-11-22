-- Bagres Stats: limpeza da mesa do necroterio (Zombie Virus Vaccine) sem callback Java->Lua (falha no servidor 42.22)
if not pcall(require, "TimedActions/LabActionMorgueTableClear") then return end
if not LabActionMorgueTableClear or not LabRecipes_PredicateCleaningLiquidEnough then return end

local function acha(inv)
    local items = inv:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if LabRecipes_PredicateCleaningLiquidEnough(it) then return it end
        if it:IsInventoryContainer() then
            local r = acha(it:getInventory())
            if r then return r end
        end
    end
    return nil
end

function LabActionMorgueTableClear:complete()
    local bleach = acha(self.character:getInventory())
    if bleach then
        local fc = bleach:getFluidContainer()
        if fc and fc:getAmount() >= 0.2 then
            fc:removeFluid(0.2, false)
            syncItemFields(self.character, bleach)
        end
    end
    sendClientCommand(self.character, "ZVirusVaccine42BETA", "ClearTable", {
        topX = self.top:getSquare():getX(),
        topY = self.top:getSquare():getY(),
        topZ = self.top:getSquare():getZ()
    })
    return true
end
