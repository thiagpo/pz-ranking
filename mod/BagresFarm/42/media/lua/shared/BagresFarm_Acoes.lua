require "BagresFarm"
require "TimedActions/ISBaseTimedAction"

local BF = BagresFarm

-- acao de injetar / tomar / cheirar (roda no cliente e no servidor, como as acoes do jogo)
BF_UsarAction = ISBaseTimedAction:derive("BF_UsarAction")

function BF_UsarAction:isValid()
    if not self.item then return false end
    if isClient() then return self.character:getInventory():containsID(self.item:getID()) end
    return self.character:getInventory():containsRecursive(self.item)
end

function BF_UsarAction:animar()
    local d = BF.DROGAS[self.id]
    if not d then return end
    if d.lolo then
        self:setAnimVariable("FoodType", "sniff"); self:setActionAnim(CharacterActionAnims.Eat)
    elseif d.bebida then
        self:setActionAnim(CharacterActionAnims.Drink)
    elseif d.inj then
        local tipo = "LeftArm"
        pcall(function() tipo = ISHealthPanel.getBandageType(self.character:getBodyDamage():getBodyPart(BodyPartType.ForeArm_L)) end)
        self:setAnimVariable("BandageType", tipo); self:setActionAnim(CharacterActionAnims.Bandage)
    else
        self:setActionAnim(CharacterActionAnims.TakePills)
    end
end

function BF_UsarAction:update()
    self.item:setJobDelta(self:getJobDelta())
    self:animar()
end

function BF_UsarAction:start()
    if isClient() and self.item then self.item = self.character:getInventory():getItemById(self.item:getID()) end
    self.item:setJobType(getText(BF.DROGAS[self.id].inj and "ContextMenu_BF_Injetar" or "ContextMenu_BF_Tomar"))
    self.item:setJobDelta(0.0)
    self:animar()
    if BF.DROGAS[self.id].lolo then self:setOverrideHandModels(self.item, nil) else self:setOverrideHandModels(nil, nil) end
end

function BF_UsarAction:stop()
    ISBaseTimedAction.stop(self)
    if self.item then self.item:setJobDelta(0.0) end
end

function BF_UsarAction:perform()
    self.item:setJobDelta(0.0)
    ISBaseTimedAction.perform(self)
end

function BF_UsarAction:complete()
    local p = self.character; local d = BF.DROGAS[self.id]
    local inv = p:getInventory()
    local pot = BF.potencia(self.item)
    local suja = BF.suja(self.item)
    if d.drenavel then
        self.item:Use()
        if d.devolve and self.item:getCurrentUsesFloat() <= 0.001 then
            local j = inv:AddItem(d.devolve)
            if isServer() and j then sendAddItemToContainer(inv, j) end
        end
    else
        inv:Remove(self.item)
        if isServer() then sendRemoveItemFromContainer(inv, self.item) end
    end
    if d.inj then
        local s = inv:AddItem("Base.BF_SeringaUsada")
        if isServer() and s then sendAddItemToContainer(inv, s) end
        pot = pot * (1 + 0.03 * p:getPerkLevel(Perks.Doctor))
        if not isClient() and BF.PERK then p:getXp():AddXP(BF.PERK, 2) end
    end
    local args = { alvo = p:getUsername(), id = self.id, pot = pot, suja = suja, inj = d.inj }
    if d.inj then args.ferida = BF.sortearFerida(p:getPerkLevel(Perks.Doctor)); if args.ferida then BF.aplicarFerida(p, args.ferida) end end
    if isServer() then
        sendServerCommand(p, "BagresFarm", "usar", args)
        if BF.usar then BF.usar(p, self.id, pot, suja) end
    elseif not isClient() and BF.receberUso then
        BF.receberUso(p, args)
    end
    return true
end

function BF_UsarAction:new(character, item, id)
    local o = ISBaseTimedAction.new(self, character)
    o.item = item; o.id = id
    o.stopOnWalk = false; o.stopOnRun = true; o.stopOnAim = false
    o.maxTime = BF.DROGAS[id].inj and 120 or 80
    if character:isTimedActionInstant() then o.maxTime = 1 end
    return o
end

-- kit antidoping em outro jogador
BF_TesteAction = ISBaseTimedAction:derive("BF_TesteAction")

function BF_TesteAction:isValid()
    if not self.alvo or self.alvo:isDead() or not self.kit then return false end
    if isClient() then return self.character:getInventory():containsID(self.kit:getID()) end
    return self.character:getInventory():containsRecursive(self.kit)
end

function BF_TesteAction:update() self.character:faceThisObject(self.alvo) end

function BF_TesteAction:start()
    if isClient() and self.kit then self.kit = self.character:getInventory():getItemById(self.kit:getID()) end
    self:setAnimVariable("BandageType", "LeftArm"); self:setActionAnim(CharacterActionAnims.Bandage)
end

function BF_TesteAction:perform() ISBaseTimedAction.perform(self) end

function BF_TesteAction:complete()
    local inv = self.character:getInventory()
    inv:Remove(self.kit)
    if isServer() then sendRemoveItemFromContainer(inv, self.kit) end
    if not isClient() and BF.PERK then self.character:getXp():AddXP(BF.PERK, 5) end
    local md = self.alvo:getModData().BF
    local hist = {}
    if md and md.hist then for i, h in ipairs(md.hist) do hist[i] = { id = h.id, t = h.t } end end
    local quem = self.alvo:getDescriptor() and self.alvo:getDescriptor():getForename() or tostring(self.alvo:getUsername())
    local args = { alvo = self.character:getUsername(), quem = quem, hist = hist, t = getGameTime():getWorldAgeHours() }
    local laudo = inv:AddItem("Base.BF_Resultado")
    if laudo then
        local md2 = laudo:getModData()
        md2.bf_teste = { quem = quem, t = args.t, hist = hist }
        laudo:setName(getText("ItemName_Base.BF_Resultado") .. ": " .. quem)
        if isServer() then sendAddItemToContainer(inv, laudo) end
    end
    if isServer() then
        sendServerCommand(self.character, "BagresFarm", "teste", args)
    elseif not isClient() and BF.mostrarTeste then
        BF.mostrarTeste(self.character, args)
    end
    return true
end

function BF_TesteAction:new(character, alvo, kit)
    local o = ISBaseTimedAction.new(self, character)
    o.alvo = alvo; o.kit = kit; o.maxTime = 150
    if character:isTimedActionInstant() then o.maxTime = 1 end
    return o
end

-- aplicar injecao em outro jogador: potencia e risco vem dos Primeiros Socorros de quem aplica
BF_AplicarAction = ISBaseTimedAction:derive("BF_AplicarAction")

function BF_AplicarAction:isValid()
    if not self.item or not self.alvo or self.alvo:isDead() then return false end
    if isClient() then return self.character:getInventory():containsID(self.item:getID()) end
    return self.character:getInventory():containsRecursive(self.item)
end

function BF_AplicarAction:update()
    self.item:setJobDelta(self:getJobDelta())
    self.character:faceThisObject(self.alvo)
    self:setAnimVariable("BandageType", "LeftArm"); self:setActionAnim(CharacterActionAnims.Bandage)
end

function BF_AplicarAction:start()
    if isClient() and self.item then self.item = self.character:getInventory():getItemById(self.item:getID()) end
    self.item:setJobType(getText("ContextMenu_BF_Injetar"))
    self.item:setJobDelta(0.0)
    self:setOverrideHandModels(nil, nil)
end

function BF_AplicarAction:stop()
    ISBaseTimedAction.stop(self)
    if self.item then self.item:setJobDelta(0.0) end
end

function BF_AplicarAction:perform()
    self.item:setJobDelta(0.0)
    ISBaseTimedAction.perform(self)
end

function BF_AplicarAction:complete()
    local p = self.character; local inv = p:getInventory()
    local pot = BF.potencia(self.item); local suja = BF.suja(self.item)
    inv:Remove(self.item)
    if isServer() then sendRemoveItemFromContainer(inv, self.item) end
    local s = inv:AddItem("Base.BF_SeringaUsada")
    if isServer() and s then sendAddItemToContainer(inv, s) end
    local doutor = p:getPerkLevel(Perks.Doctor)
    if not isClient() and BF.PERK then p:getXp():AddXP(BF.PERK, 2); p:getXp():AddXP(Perks.Doctor, 3) end
    local ferida = BF.sortearFerida(doutor)
    if ferida then BF.aplicarFerida(self.alvo, ferida) end
    local quem = p:getDescriptor() and p:getDescriptor():getForename() or tostring(p:getUsername())
    local args = { alvo = self.alvo:getUsername(), id = self.id, pot = pot * (1 + 0.03 * doutor), suja = suja, ferida = ferida, quem = quem }
    if isServer() then
        sendServerCommand(self.alvo, "BagresFarm", "aplicado", args)
        if BF.usar then BF.usar(self.alvo, self.id, args.pot, suja) end
    elseif not isClient() and BF.receberAplicacao then
        BF.receberAplicacao(self.alvo, args, quem)
    end
    return true
end

function BF_AplicarAction:new(character, alvo, item, id)
    local o = ISBaseTimedAction.new(self, character)
    o.alvo = alvo; o.item = item; o.id = id
    o.stopOnWalk = true; o.stopOnRun = true; o.stopOnAim = false
    o.maxTime = 140
    if character:isTimedActionInstant() then o.maxTime = 1 end
    return o
end
