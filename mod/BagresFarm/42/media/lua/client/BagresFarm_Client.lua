require "BagresFarm"
require "TimedActions/ISBaseTimedAction"

local BF = BagresFarm
local VOZES = { "MaleZombieVoiceA", "MaleZombieVoiceB", "FemaleZombieVoiceA", "MaleZombieSprinterVoiceA", "FemaleZombieSprinterVoiceB" }
local ult = {}

local function agora() return getGameTime():getWorldAgeHours() end

local function estado(p)
    local md = p:getModData()
    md.BF = md.BF or {}
    local st = md.BF
    st.ef = st.ef or {}; st.usos = st.usos or {}; st.pos = st.pos or {}; st.ultDose = st.ultDose or {}
    return st
end

local function nome(id) return getTextOrNull("ItemName_" .. BF.DROGAS[id].item) or getText("ItemName_" .. BF.DROGAS[id].item) end

local function stat(p, k) return p:getStats():get(k) end
local function setStat(p, k, v) p:getStats():set(k, v) end
local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end

local function bonusForca(st)
    local b = 0
    for id, e in pairs(st.ef) do
        local d = BF.DROGAS[id]
        if d and d.forca then b = math.max(b, d.forca * e.m) end
    end
    return b
end

local function aplicarForca(p, st)
    local b = bonusForca(st)
    if b > 0 then
        if not st.mwb then st.mwb = p:getMaxWeightBase() end
        p:setMaxWeightBase(st.mwb * (1 + b))
    elseif st.mwb then
        p:setMaxWeightBase(st.mwb); st.mwb = nil
    end
end

local function audicao(p, st, ligar)
    pcall(function()
        local t = CharacterTrait.KEEN_HEARING
        if ligar then
            if not p:hasTrait(t) then p:getCharacterTraits():add(t); st.audicaoTemp = true end
        elseif st.audicaoTemp then
            p:getCharacterTraits():remove(t); st.audicaoTemp = nil
        end
    end)
end

local function terminar(p, st, id)
    local e = st.ef[id]; local d = BF.DROGAS[id]
    st.ef[id] = nil
    if not e or not d then return end
    local t = agora()
    if d.fadigaFim then setStat(p, CharacterStat.FATIGUE, clamp(stat(p, CharacterStat.FATIGUE) + d.fadigaFim * e.d, 0, 1)) end
    if d.tristezaFim then setStat(p, CharacterStat.UNHAPPINESS, math.max(stat(p, CharacterStat.UNHAPPINESS), clamp(d.tristezaFim * e.d, 0, 100))) end
    if d.recuperacao then st.pos[id] = { fim = t + d.dur, d = e.d } end
    if d.posDur then st.pos[id] = { fim = t + d.posDur, d = e.d } end
    if d.audicao then audicao(p, st, false) end
    if d.forca then aplicarForca(p, st) end
    HaloTextHelper.addBadText(p, nome(id) .. " " .. getText("IGUI_BF_Passou"))
end

function BF.usar(p, id, pot)
    local d = BF.DROGAS[id]; if not d then return end
    local st = estado(p)
    st.usos[id] = (st.usos[id] or 0) + 1
    local fator = BF.fatorTolerancia(st.usos[id])
    local t = agora()
    if d.lolo then
        setStat(p, CharacterStat.NICOTINE_WITHDRAWAL, 0)
        setStat(p, CharacterStat.STRESS, clamp(stat(p, CharacterStat.STRESS) - 0.15, 0, 1))
        setStat(p, CharacterStat.UNHAPPINESS, clamp(stat(p, CharacterStat.UNHAPPINESS) - 5, 0, 100))
        setStat(p, CharacterStat.SICKNESS, clamp(stat(p, CharacterStat.SICKNESS) + 15 * fator, 0, 100))
        setStat(p, CharacterStat.INTOXICATION, clamp(stat(p, CharacterStat.INTOXICATION) + 25 * fator, 0, 100))
        HaloTextHelper.addGoodText(p, nome(id))
        if isClient() then sendClientCommand(p, "BagresFarm", "uso", { id = id }) end
        return
    end
    if d.gripe then
        local bd = p:getBodyDamage()
        bd:setHasACold(false); bd:setColdStrength(0); bd:setCatchACold(0)
    end
    st.ef[id] = { ini = t, fim = t + d.dur, m = fator * (pot or 1), d = fator }
    st.ultDose[id] = t
    if d.panico then setStat(p, CharacterStat.PANIC, clamp(stat(p, CharacterStat.PANIC) + d.panico, 0, 100)) end
    if d.depressao and st.usos[id] >= d.depressao then
        setStat(p, CharacterStat.UNHAPPINESS, clamp(stat(p, CharacterStat.UNHAPPINESS) + 5 * (st.usos[id] - d.depressao + 1), 0, 100))
    end
    if d.audicao then audicao(p, st, true) end
    if d.forca then aplicarForca(p, st) end
    HaloTextHelper.addGoodText(p, nome(id))
    if isClient() then sendClientCommand(p, "BagresFarm", "uso", { id = id }) end
end

-- acao de injetar / tomar
BF_UsarAction = ISBaseTimedAction:derive("BF_UsarAction")

function BF_UsarAction:isValid()
    return self.item and self.character:getInventory():containsRecursive(self.item)
end

function BF_UsarAction:update()
    self.item:setJobDelta(self:getJobDelta())
end

function BF_UsarAction:start()
    self.item:setJobType(getText(self.inj and "ContextMenu_BF_Injetar" or "ContextMenu_BF_Tomar"))
    self.item:setJobDelta(0.0)
    if BF.DROGAS[self.id].lolo then
        self:setAnimVariable("FoodType", "Sniff"); self:setActionAnim(CharacterActionAnims.Eat)
    else
        self:setActionAnim(self.inj and CharacterActionAnims.Bandage or CharacterActionAnims.TakePills)
    end
    self:setOverrideHandModels(nil, nil)
end

local PARTES_SERINGA = { "Hand_L", "Hand_R", "ForeArm_L", "ForeArm_R" }

-- pouca pratica em Primeiros Socorros: chance de se machucar com a agulha
local function acidenteSeringa(p)
    local doutor = p:getPerkLevel(Perks.Doctor)
    local risco = math.max(0, 5 - doutor) * 0.04
    if ZombRandFloat(0, 1) >= risco then return end
    local bp = p:getBodyDamage():getBodyPart(BodyPartType[PARTES_SERINGA[ZombRand(1, #PARTES_SERINGA + 1)]])
    local r = ZombRandFloat(0, 1)
    if r < 0.6 then bp:setScratched(true, true); HaloTextHelper.addBadText(p, getText("IGUI_BF_Arranhao"))
    elseif r < 0.9 then bp:setCut(true); HaloTextHelper.addBadText(p, getText("IGUI_BF_Corte"))
    else bp:generateDeepWound(); HaloTextHelper.addBadText(p, getText("IGUI_BF_Laceracao")) end
end

function BF_UsarAction:stop()
    ISBaseTimedAction.stop(self)
    self.item:setJobDelta(0.0)
end

function BF_UsarAction:perform()
    self.item:setJobDelta(0.0)
    local p = self.character
    local pot = BF.potencia(self.item)
    if BF.DROGAS[self.id].drenavel then
        self.item:Use()
    else
        local c = self.item:getContainer()
        c:Remove(self.item)
        if isClient() then sendRemoveItemFromContainer(c, self.item) end
    end
    if self.inj then
        local s = p:getInventory():AddItem("Base.BF_SeringaUsada")
        if isClient() and s then sendAddItemToContainer(p:getInventory(), s) end
        pot = pot * (1 + 0.03 * p:getPerkLevel(Perks.Doctor))
        acidenteSeringa(p)
        if BF.PERK then p:getXp():AddXP(BF.PERK, 2) end
    end
    BF.usar(p, self.id, pot)
    ISBaseTimedAction.perform(self)
end

function BF_UsarAction:new(character, item, id)
    local o = ISBaseTimedAction.new(self, character)
    o.item = item; o.id = id; o.inj = BF.DROGAS[id].inj
    o.stopOnWalk = false; o.stopOnRun = true; o.stopOnAim = false
    o.maxTime = o.inj and 120 or 80
    if character:isTimedActionInstant() then o.maxTime = 1 end
    return o
end

local function horas(h)
    if h < 1 then return math.max(1, math.floor(h * 60 + 0.5)) .. " min" end
    return string.format("%.1f h", h)
end

local function descricaoAtivos(p)
    local st = estado(p); local t = agora(); local linhas = {}
    for id, e in pairs(st.ef) do
        table.insert(linhas, nome(id) .. ": " .. horas(e.fim - t) .. " (x" .. string.format("%.2f", e.m) .. ")")
    end
    for id, e in pairs(st.pos) do
        if e.fim > t then table.insert(linhas, nome(id) .. " (" .. getText("IGUI_BF_Ressaca") .. "): " .. horas(e.fim - t)) end
    end
    table.sort(linhas)
    return linhas
end

local function menu(playerNum, context, items)
    local p = getSpecificPlayer(playerNum)
    if not p or p:isDead() then return end
    for _, entry in ipairs(items) do
        local item = entry
        if not instanceof(entry, "InventoryItem") then item = entry.items and entry.items[1] end
        local id = BF.droga(item)
        if id and item:getContainer() and p:getInventory():containsRecursive(item)
            and (not BF.DROGAS[id].drenavel or item:getCurrentUsesFloat() > 0) then
            local d = BF.DROGAS[id]
            local txt = getText(d.inj and "ContextMenu_BF_Injetar" or "ContextMenu_BF_Tomar") .. " " .. item:getDisplayName()
            local op = context:addOption(txt, p, function(pl)
                ISTimedActionQueue.add(BF_UsarAction:new(pl, item, id))
            end)
            local tip = ISInventoryPaneContextMenu.addToolTip()
            tip:setName(item:getDisplayName())
            local st = estado(p)
            local desc = getText("Tooltip_" .. item:getType()) .. " <LINE> <LINE> "
                .. getText("IGUI_BF_Potencia") .. ": x" .. string.format("%.2f", BF.potencia(item)) .. " <LINE> "
                .. getText("IGUI_BF_Doses") .. ": " .. (st.usos[id] or 0) .. " (" .. getText("IGUI_BF_Tolerancia") .. " +" .. math.floor((BF.fatorTolerancia((st.usos[id] or 0) + 1) - 1) * 100 + 0.5) .. "%)"
            local ativos = descricaoAtivos(p)
            if #ativos > 0 then desc = desc .. " <LINE> <LINE> " .. getText("IGUI_BF_Ativos") .. ": <LINE> " .. table.concat(ativos, " <LINE> ") end
            tip.description = desc
            op.toolTip = tip
            return
        end
    end
end
Events.OnFillInventoryObjectContextMenu.Add(menu)

-- efeitos continuos (so no jogador local)
local function tick(p)
    if not p or p:isDead() or not p:isLocalPlayer() then return end
    local md = p:getModData().BF
    if not md or (next(md.ef or {}) == nil and next(md.pos or {}) == nil and not md.abst) then return end
    local st = estado(p); local t = agora()
    local n = p:getPlayerNum()
    local u = ult[n]; if not u then u = { sang = {} }; ult[n] = u end

    local fomeM, fadM, dor = 1, 1, 0
    local folego, sangra = false, 0
    for id, e in pairs(st.ef) do
        local d = BF.DROGAS[id]
        if d then
            if d.fome then fomeM = fomeM + d.fome * (d.fome < 0 and e.m or e.d) end
            if d.fadiga then fadM = fadM + d.fadiga * (d.fadiga < 0 and e.m or e.d) end
            if d.dor then dor = dor + d.dor * e.m end
            if d.folego then folego = true end
            if d.sangramento then sangra = math.max(sangra, d.sangramento * e.d) end
        end
    end
    local recup = 0
    for id, e in pairs(st.pos) do
        if e.fim > t then
            local d = BF.DROGAS[id]
            if d and d.recuperacao then recup = math.max(recup, d.recuperacao * e.d) end
            if d and d.sangramento then sangra = math.max(sangra, d.sangramento * e.d) end
        end
    end
    if st.abst then fadM = fadM + 0.5 end
    fomeM = math.max(0, fomeM); fadM = math.max(0, fadM)

    local fome = stat(p, CharacterStat.HUNGER)
    if u.fome and fome > u.fome and fomeM ~= 1 then
        fome = clamp(u.fome + (fome - u.fome) * fomeM, 0, 1); setStat(p, CharacterStat.HUNGER, fome)
    end
    u.fome = fome

    local fad = stat(p, CharacterStat.FATIGUE)
    if u.fad then
        if fad > u.fad and fadM ~= 1 then fad = clamp(u.fad + (fad - u.fad) * fadM, 0, 1); setStat(p, CharacterStat.FATIGUE, fad)
        elseif fad < u.fad and recup > 0 then fad = clamp(u.fad + (fad - u.fad) * (1 - recup), 0, 1); setStat(p, CharacterStat.FATIGUE, fad) end
    end
    u.fad = fad

    if folego and stat(p, CharacterStat.ENDURANCE) < 0.85 then setStat(p, CharacterStat.ENDURANCE, 0.85) end
    if dor > 0 then
        local pain = stat(p, CharacterStat.PAIN)
        if pain > 0 then setStat(p, CharacterStat.PAIN, pain * (1 - math.min(0.95, dor))) end
    end

    if sangra > 0 then
        local partes = p:getBodyDamage():getBodyParts()
        for i = 0, partes:size() - 1 do
            local bp = partes:get(i); local bt = bp:getBleedingTime()
            local antes = u.sang[i] or 0
            if bt > antes + 0.5 then bt = bt * (1 + sangra); bp:setBleedingTime(bt) end
            u.sang[i] = bt
        end
    else
        u.sang = {}
    end
end
Events.OnPlayerUpdate.Add(tick)

local function minuto()
    for i = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(i)
        if p and not p:isDead() then
            local st = estado(p); local t = agora()
            for id, e in pairs(st.ef) do
                if t >= e.fim then terminar(p, st, id) end
            end
            for id, e in pairs(st.pos) do
                if t >= e.fim then st.pos[id] = nil end
            end
            local rig, peso, paranoia, depress = 0, 0, 0, 0
            for id, e in pairs(st.ef) do
                local d = BF.DROGAS[id]
                if d then
                    if d.gripe then local bd = p:getBodyDamage(); if bd:getCatchACold() > 0 then bd:setCatchACold(0) end end
                    if d.rigidez then rig = rig + d.rigidez * e.m end
                    if d.pesoDia then peso = peso + d.pesoDia * e.m end
                    if d.paranoia and (st.usos[id] or 0) >= d.paranoia then paranoia = paranoia + 0.06 * e.d * (1 + 0.1 * ((st.usos[id] or 0) - d.paranoia)) end
                    if d.depressao and (st.usos[id] or 0) >= d.depressao then depress = depress + 0.01 * (st.usos[id] or 0) * e.d end
                end
            end
            if rig > 0 then
                local partes = p:getBodyDamage():getBodyParts()
                for j = 0, partes:size() - 1 do
                    local bp = partes:get(j); local s = bp:getStiffness()
                    if s > 0 then bp:setStiffness(math.max(0, s - s * math.min(0.9, rig))) end
                end
            end
            if peso > 0 then
                local nut = p:getNutrition(); local w = nut:getWeight()
                if w > 55 then nut:setWeight(w - peso / 1440) end
            end
            if paranoia > 0 and ZombRandFloat(0, 1) < paranoia then
                p:getEmitter():playSound(VOZES[ZombRand(1, #VOZES + 1)])
                setStat(p, CharacterStat.PANIC, clamp(stat(p, CharacterStat.PANIC) + 10, 0, 100))
            end
            if depress > 0 then setStat(p, CharacterStat.UNHAPPINESS, clamp(stat(p, CharacterStat.UNHAPPINESS) + depress, 0, 100)) end

            -- vicio (metanfetamina): abstinencia apos 24 h sem dose, cura apos 5 dias limpo
            local vid = "Metanfetamina"; local dv = BF.DROGAS[vid]
            if dv and dv.vicio and (st.usos[vid] or 0) >= dv.vicio and not st.ef[vid] and st.ultDose[vid] then
                local semDose = t - st.ultDose[vid]
                if semDose > 120 then st.usos[vid] = 0; st.abst = nil; HaloTextHelper.addGoodText(p, getText("IGUI_BF_Curado"))
                elseif semDose > 24 then
                    if not st.abst then st.abst = true; st.avisoAbst = 0 end
                    setStat(p, CharacterStat.UNHAPPINESS, clamp(stat(p, CharacterStat.UNHAPPINESS) + 0.05, 0, 100))
                    setStat(p, CharacterStat.STRESS, clamp(stat(p, CharacterStat.STRESS) + 0.0005, 0, 1))
                    if stat(p, CharacterStat.PANIC) < 40 then setStat(p, CharacterStat.PANIC, stat(p, CharacterStat.PANIC) + 0.2) end
                    if t - (st.avisoAbst or 0) >= 1 then st.avisoAbst = t; HaloTextHelper.addBadText(p, getText("IGUI_BF_Abstinencia")) end
                end
            else
                st.abst = nil
            end
        end
    end
end
Events.EveryOneMinute.Add(minuto)

Events.OnHitZombie.Add(function(zombie, wielder, bodyPart, weapon)
    if not zombie or not wielder or not weapon or not wielder:isLocalPlayer() then return end
    local md = wielder:getModData().BF
    if not md or not md.ef then return end
    local b = bonusForca(md)
    if b <= 0 or zombie:isDead() then return end
    local dmg = (weapon:getMinDamage() + weapon:getMaxDamage()) / 2 * b
    zombie:setHealth(zombie:getHealth() - dmg)
end)

Events.OnCreatePlayer.Add(function(i, p)
    if not p then return end
    local md = p:getModData().BF
    if not md then return end
    local st = estado(p); local t = agora()
    for id, e in pairs(st.ef) do if t >= e.fim then st.ef[id] = nil end end
    aplicarForca(p, st)
    if not st.audicaoTemp then return end
    local ativo = false
    for id in pairs(st.ef) do if BF.DROGAS[id] and BF.DROGAS[id].audicao then ativo = true end end
    if not ativo then audicao(p, st, false) end
end)

Events.OnPlayerDeath.Add(function(p)
    local md = p and p:getModData().BF
    if md and md.mwb then p:setMaxWeightBase(md.mwb) end
end)
