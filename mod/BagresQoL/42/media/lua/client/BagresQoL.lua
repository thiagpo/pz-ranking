require "Entity/ISUI/CraftRecipe/ISWidgetHandCraftControl"

local LOTE = { Tailoring = true }

local iniciar = ISWidgetHandCraftControl.initialise
function ISWidgetHandCraftControl:initialise()
    iniciar(self)
    if self.allowBatchCraft or not self.logic then return end
    local ok, rec = pcall(function() return self.logic:getRecipeData():getRecipe() end)
    if ok and rec and LOTE[rec:getCategory()] then self.allowBatchCraft = true end
end
