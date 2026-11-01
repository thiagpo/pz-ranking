require "BagresFarm"
require "TimedActions/ISBaseTimedAction"
require "ISUI/ISPanel"

local BF = BagresFarm
local VOZES = { "MaleZombieVoiceA", "MaleZombieVoiceB", "FemaleZombieVoiceA", "MaleZombieSprinterVoiceA", "FemaleZombieSprinterVoiceB" }
local PARTES_SERINGA = { "Hand_L", "Hand_R", "ForeArm_L", "ForeArm_R" }
local ult = {}

local function agora() return getGameTime():getWorldAgeHours() end

local function estado(p)
    local md = p:getModData()
    md.BF = md.BF or {}
    local st = md.BF
    st.ef = st.ef or {}; st.usos = st.usos or {}; st.pos = st.pos or {}; st.ultDose = st.ultDose or {}; st.hist = st.hist or {}
    return st
end

local function nome(id)
    local ok, n = pcall(getItemNameFromFullType, BF.DROGAS[id].item)
    if ok and n and n ~= "" then return n end
    return id
end
local function stat(p, k) return p:getStats():get(k) end
local function setStat(p, k, v) p:getStats():set(k, v) end
local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local function vazio(t) if not t then return true end for _ in pairs(t) do return false end return true end

local function horas(h)
    if h < 1 then return math.max(1, math.floor(h * 60 + 0.5)) .. " min" end
    return string.format("%.1f h", h)
end

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

local function desmaiar(p)
    pcall(function()
        local wake = GameTime.getInstance():getTimeOfDay() + 1
        if wake >= 24 then wake = wake - 24 end
        p:setForceWakeUpTime(wake); p:setAsleepTime(0.0); p:setAsleep(true)
        getSleepingEvent():setPlayerFallAsleep(p, 1)
        UIManager.setFadeBeforeUI(p:getPlayerNum(), true); UIManager.FadeOut(p:getPlayerNum(), 1)
    end)
    HaloTextHelper.addBadText(p, getText("IGUI_BF_Overdose"))
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

local function registrar(p, st, id, t)
    table.insert(st.hist, { id = id, t = t })
    local novo = {}
    for _, h in ipairs(st.hist) do if t - h.t <= BF.HIST_H then table.insert(novo, h) end end
    st.hist = novo
    pcall(function() p:transmitModData() end)
    if isClient() then sendClientCommand(p, "BagresFarm", "uso", { id = id }) end
end

function BF.usar(p, id, pot, suja)
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
        registrar(p, st, id, t)
        return
    end
    local overdose = d.inj and st.ultDose[id] and (t - st.ultDose[id]) < BF.OVERDOSE_H
    if d.cura then
        local bd = p:getBodyDamage()
        bd:setHasACold(false); bd:setColdStrength(0); bd:setCatchACold(0)
    end
    if d.fadigaJa then setStat(p, CharacterStat.FATIGUE, clamp(stat(p, CharacterStat.FATIGUE) + d.fadigaJa * (pot or 1), 0, 1)) end
    if d.fomeJa then setStat(p, CharacterStat.HUNGER, clamp(stat(p, CharacterStat.HUNGER) + d.fomeJa, 0, 1)) end
    if d.panico then setStat(p, CharacterStat.PANIC, clamp(stat(p, CharacterStat.PANIC) + d.panico, 0, 100)) end
    if d.depressao and st.usos[id] >= d.depressao then
        setStat(p, CharacterStat.UNHAPPINESS, clamp(stat(p, CharacterStat.UNHAPPINESS) + 5 * (st.usos[id] - d.depressao + 1), 0, 100))
    end
    if d.dur > 0 then st.ef[id] = { ini = t, fim = t + d.dur, m = fator * (pot or 1), d = fator } end
    st.ultDose[id] = t
    if d.audicao then audicao(p, st, true) end
    if d.forca then aplicarForca(p, st) end
    if suja then
        local bp = p:getBodyDamage():getBodyPart(BodyPartType[PARTES_SERINGA[ZombRand(1, #PARTES_SERINGA + 1)]])
        local r = ZombRandFloat(0, 1)
        if r < 0.03 then
            pcall(function() local bd = p:getBodyDamage(); bd:setInfected(true); bd:setInfectionTime(-1); bd:setInfectionMortalityDuration(-1) end)
            HaloTextHelper.addBadText(p, getText("IGUI_BF_SeringaSujaZumbi"))
        elseif r < 0.38 then
            bp:setScratched(true, true); bp:setInfectedWound(true)
            HaloTextHelper.addBadText(p, getText("IGUI_BF_SeringaSujaInfeccao"))
        end
    end
    HaloTextHelper.addGoodText(p, nome(id))
    registrar(p, st, id, t)
    if overdose then desmaiar(p) end
end

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

-- acao de injetar / tomar / cheirar
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

function BF_UsarAction:stop()
    ISBaseTimedAction.stop(self)
    self.item:setJobDelta(0.0)
end

function BF_UsarAction:perform()
    self.item:setJobDelta(0.0)
    local p = self.character
    local pot = BF.potencia(self.item)
    local suja = BF.suja(self.item)
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
    BF.usar(p, self.id, pot, suja)
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

local function listaAtivos(p)
    local st = estado(p); local t = agora(); local linhas = {}
    for id, e in pairs(st.ef) do
        table.insert(linhas, { txt = nome(id), resta = e.fim - t, total = e.fim - e.ini, m = e.m, bom = true })
    end
    for id, e in pairs(st.pos) do
        if e.fim > t then table.insert(linhas, { txt = nome(id) .. " (" .. getText("IGUI_BF_Ressaca") .. ")", resta = e.fim - t, total = e.fim - (e.ini or (e.fim - 2)), bom = false }) end
    end
    if st.abst then table.insert(linhas, { txt = getText("IGUI_BF_Abstinencia") .. " x" .. st.abst, resta = 0, total = 0, bom = false }) end
    table.sort(linhas, function(a, b) return a.txt < b.txt end)
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
                .. getText("IGUI_BF_Potencia") .. ": x" .. string.format("%.2f", BF.potencia(item))
            if d.inj then desc = desc .. " <LINE> " .. getText("IGUI_BF_ForaGeladeira") .. ": " .. string.format("%.1f", BF.horasFora(item) / 24) .. " d" end
            if BF.suja(item) then desc = desc .. " <LINE> " .. getText("IGUI_BF_SeringaSujaAviso") end
            desc = desc .. " <LINE> " .. getText("IGUI_BF_Doses") .. ": " .. (st.usos[id] or 0) .. " (" .. getText("IGUI_BF_Tolerancia") .. " +" .. math.floor((BF.fatorTolerancia((st.usos[id] or 0) + 1) - 1) * 100 + 0.5) .. "%)"
            if d.inj and st.ultDose[id] and agora() - st.ultDose[id] < BF.OVERDOSE_H then desc = desc .. " <LINE> " .. getText("IGUI_BF_OverdoseAviso") end
            local ativos = listaAtivos(p)
            if #ativos > 0 then
                local l = {}
                for _, a in ipairs(ativos) do table.insert(l, a.txt .. (a.resta > 0 and (": " .. horas(a.resta)) or "")) end
                desc = desc .. " <LINE> <LINE> " .. getText("IGUI_BF_Ativos") .. ": <LINE> " .. table.concat(l, " <LINE> ")
            end
            tip.description = desc
            op.toolTip = tip
            return
        end
    end
end
Events.OnFillInventoryObjectContextMenu.Add(menu)

-- kit antidoping: clicar em outro jogador
BF_TesteAction = ISBaseTimedAction:derive("BF_TesteAction")
function BF_TesteAction:isValid() return self.alvo and not self.alvo:isDead() and self.character:getInventory():containsRecursive(self.kit) end
function BF_TesteAction:update() self.character:faceThisObject(self.alvo) end
function BF_TesteAction:start() self:setActionAnim(CharacterActionAnims.Bandage) end
function BF_TesteAction:perform()
    local c = self.kit:getContainer(); c:Remove(self.kit)
    if isClient() then sendRemoveItemFromContainer(c, self.kit) end
    if BF.PERK then self.character:getXp():AddXP(BF.PERK, 5) end
    local md = self.alvo:getModData().BF
    local t = agora(); local linhas = {}
    if md and md.hist then
        for _, h in ipairs(md.hist) do
            if t - h.t <= BF.HIST_H and BF.DROGAS[h.id] then table.insert(linhas, nome(h.id) .. " - " .. getText("IGUI_BF_Ha") .. " " .. horas(t - h.t)) end
        end
    end
    local texto = getText("IGUI_BF_TesteTitulo", self.alvo:getDescriptor():getForename()) .. " <LINE> <LINE> "
    if #linhas == 0 then texto = texto .. getText("IGUI_BF_TesteLimpo") else texto = texto .. table.concat(linhas, " <LINE> ") end
    if ISModalRichText then
        local m = ISModalRichText:new(getCore():getScreenWidth() / 2 - 180, getCore():getScreenHeight() / 2 - 100, 360, 200, texto, false)
        m:initialise(); m:addToUIManager()
    else
        HaloTextHelper.addText(self.character, texto)
    end
    ISBaseTimedAction.perform(self)
end
function BF_TesteAction:new(character, alvo, kit)
    local o = ISBaseTimedAction.new(self, character)
    o.alvo = alvo; o.kit = kit; o.maxTime = 150
    if character:isTimedActionInstant() then o.maxTime = 1 end
    return o
end

Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, worldobjects, test)
    if test then return end
    local p = getSpecificPlayer(playerNum)
    if not p or p:isDead() then return end
    local kit = p:getInventory():getFirstTypeRecurse("Base.BF_KitAntidoping")
    if not kit then return end
    local sq
    for _, o in ipairs(worldobjects) do if o and o:getSquare() then sq = o:getSquare(); break end end
    if not sq then return end
    local objs = p:getCell():getObjectList()
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        if instanceof(o, "IsoPlayer") and o ~= p and not o:isDead() and o:DistTo(sq:getX() + 0.5, sq:getY() + 0.5) < 1.6 then
            context:addOption(getText("ContextMenu_BF_Teste") .. " " .. o:getDescriptor():getForename(), p, function(pl)
                ISTimedActionQueue.add(ISWalkToTimedAction:new(pl, o:getSquare()))
                ISTimedActionQueue.add(BF_TesteAction:new(pl, o, kit))
            end)
        end
    end
end)

-- efeitos continuos (so no jogador local)
local function tick(p)
    if not p or p:isDead() or not p:isLocalPlayer() then return end
    local md = p:getModData().BF
    if not md or (vazio(md.ef) and vazio(md.pos) and not md.abst) then return end
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
    if st.abst then fadM = fadM + 0.3 * st.abst end
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

local function abstinencia(p, st, t)
    local total = 0
    for id, d in pairs(BF.DROGAS) do
        if d.vicio then
            local nivel = math.floor((st.usos[id] or 0) / d.vicio.limiar)
            if nivel > 0 and not st.ef[id] and st.ultDose[id] then
                local sem = t - st.ultDose[id]
                if sem > d.vicio.limpar * nivel then
                    st.usos[id] = 0
                    HaloTextHelper.addGoodText(p, getText("IGUI_BF_Curado") .. ": " .. nome(id))
                elseif sem > d.vicio.horas then
                    total = total + nivel
                    setStat(p, CharacterStat.UNHAPPINESS, clamp(stat(p, CharacterStat.UNHAPPINESS) + 0.05 * nivel, 0, 100))
                    setStat(p, CharacterStat.STRESS, clamp(stat(p, CharacterStat.STRESS) + 0.0005 * nivel, 0, 1))
                    if stat(p, CharacterStat.PANIC) < 40 * nivel then setStat(p, CharacterStat.PANIC, stat(p, CharacterStat.PANIC) + 0.2 * nivel) end
                    if d.dor and stat(p, CharacterStat.PAIN) < 30 * nivel then setStat(p, CharacterStat.PAIN, stat(p, CharacterStat.PAIN) + 0.3 * nivel) end
                end
            end
        end
    end
    if total > 0 then
        if t - (st.avisoAbst or 0) >= 1 then st.avisoAbst = t; HaloTextHelper.addBadText(p, getText("IGUI_BF_Abstinencia")) end
        st.abst = total
    else
        st.abst = nil
    end
end

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
                if w > 50 then nut:setWeight(w - peso / 1440) end
            end
            if paranoia > 0 and ZombRandFloat(0, 1) < paranoia then
                p:getEmitter():playSound(VOZES[ZombRand(1, #VOZES + 1)])
                setStat(p, CharacterStat.PANIC, clamp(stat(p, CharacterStat.PANIC) + 10, 0, 100))
            end
            if depress > 0 then setStat(p, CharacterStat.UNHAPPINESS, clamp(stat(p, CharacterStat.UNHAPPINESS) + depress, 0, 100)) end
            abstinencia(p, st, t)
        end
    end
end
Events.EveryOneMinute.Add(minuto)

-- validade: injetaveis fora de geladeira perdem potencia (ate 40% em 14 dias)
local function ehInjetavel(it)
    local id = BF.POR_ITEM[it:getFullType()]
    return id ~= nil and BF.DROGAS[id].inj == true
end
Events.EveryHours.Add(function()
    for i = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(i)
        if p and not p:isDead() then
            local itens = p:getInventory():getAllEvalRecurse(ehInjetavel)
            for j = 0, itens:size() - 1 do
                local it = itens:get(j)
                local c = it:getContainer(); local tipo = c and c:getType() or ""
                if tipo ~= "fridge" and tipo ~= "freezer" then
                    local md = it:getModData()
                    md.bf_fora = (md.bf_fora or 0) + 1
                    if md.bf_fora >= BF.VALIDADE_H and not md.bf_vencido then md.bf_vencido = true; it:setName(BF.nomeItem(it)) end
                end
            end
        end
    end
end)

Events.OnHitZombie.Add(function(zombie, wielder, bodyPart, weapon)
    if not zombie or not wielder or not weapon or not wielder:isLocalPlayer() then return end
    local md = wielder:getModData().BF
    if not md or not md.ef then return end
    local b = bonusForca(md)
    if b <= 0 or zombie:isDead() then return end
    local dmg = (weapon:getMinDamage() + weapon:getMaxDamage()) / 2 * b
    zombie:setHealth(zombie:getHealth() - dmg)
end)

-- moodles proprios (coluna abaixo dos moodles do jogo) e painel de efeitos
BF_Painel = ISPanel:derive("BF_Painel")
function BF_Painel:new(pn)
    local o = ISPanel.new(self, 80, 120, 300, 120)
    o.pn = pn; o.moveWithMouse = true; o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.8 }
    return o
end
function BF_Painel:prerender()
    local p = getSpecificPlayer(self.pn)
    local linhas = p and listaAtivos(p) or {}
    self:setHeight(40 + #linhas * 34)
    ISPanel.prerender(self)
    self:drawText(getText("IGUI_BF_Painel"), 10, 8, 1, 1, 1, 1, UIFont.Medium)
    local y = 36
    for _, l in ipairs(linhas) do
        self:drawText(l.txt, 10, y, 1, 1, 1, 1, UIFont.Small)
        if l.resta > 0 then
            self:drawText(horas(l.resta), self.width - 70, y, 0.8, 0.8, 0.8, 1, UIFont.Small)
            local frac = l.total > 0 and clamp(l.resta / l.total, 0, 1) or 1
            self:drawRect(10, y + 18, self.width - 20, 6, 0.6, 0.2, 0.2, 0.2)
            if l.bom then self:drawRect(10, y + 18, (self.width - 20) * frac, 6, 0.9, 0.3, 0.7, 0.3)
            else self:drawRect(10, y + 18, (self.width - 20) * frac, 6, 0.9, 0.8, 0.3, 0.2) end
        end
        y = y + 34
    end
    if #linhas == 0 then self:drawText(getText("IGUI_BF_Nada"), 10, 36, 0.7, 0.7, 0.7, 1, UIFont.Small) end
end

BF_Moodles = ISUIElement:derive("BF_Moodles")
function BF_Moodles:new(pn)
    local o = ISUIElement.new(self, 0, 0, 36, 160)
    o.pn = pn; o.itens = {}
    return o
end
function BF_Moodles:calcular()
    local p = getSpecificPlayer(self.pn); self.itens = {}
    if not p or p:isDead() then return end
    local md = p:getModData().BF
    if not md then return end
    local nEf, nPos = 0, 0
    for _ in pairs(md.ef or {}) do nEf = nEf + 1 end
    local t = agora()
    for _, e in pairs(md.pos or {}) do if e.fim > t then nPos = nPos + 1 end end
    if nEf > 0 then table.insert(self.itens, { tex = "media/ui/BF_mood_dopado.png", bom = true, lvl = math.min(4, nEf), titulo = getText("IGUI_BF_MoodDopado"), desc = getText("IGUI_BF_MoodDopadoDesc", nEf) }) end
    if nPos > 0 then table.insert(self.itens, { tex = "media/ui/BF_mood_ressaca.png", bom = false, lvl = math.min(4, nPos), titulo = getText("IGUI_BF_Ressaca"), desc = getText("IGUI_BF_MoodRessacaDesc") }) end
    if md.abst then table.insert(self.itens, { tex = "media/ui/BF_mood_abst.png", bom = false, lvl = math.min(4, md.abst), titulo = getText("IGUI_BF_Abstinencia"), desc = getText("IGUI_BF_MoodAbstDesc") }) end
end
function BF_Moodles:render()
    self:calcular()
    local mui = MoodlesUI.getInstance()
    if mui then self:setX(mui:getX()); self:setY(mui:getY() + mui:getHeight() + 6) end
    self:setHeight(#self.itens * 36 + 1)
    local mx, my = self:getMouseX(), self:getMouseY()
    for i, it in ipairs(self.itens) do
        local y = (i - 1) * 36
        local bg = getTexture((it.bom and "Moodle_Bkg_Good_" or "Moodle_Bkg_Bad_") .. it.lvl)
        if bg then self:drawTexture(bg, 2, y, 1, 1, 1, 1) end
        local ic = getTexture(it.tex)
        if ic then self:drawTextureScaled(ic, 7, y + 4, 22, 22, 1, 1, 1, 1) end
        if mx >= 0 and mx <= 36 and my >= y and my < y + 36 then
            local w = math.max(getTextManager():MeasureStringX(UIFont.Small, it.desc), getTextManager():MeasureStringX(UIFont.Medium, it.titulo)) + 16
            self:drawRect(-w - 8, y, w, 50, 0.85, 0, 0, 0)
            self:drawRectBorder(-w - 8, y, w, 50, 0.6, 0.5, 0.5, 0.5)
            self:drawText(it.titulo, -w, y + 4, 1, 1, 1, 1, UIFont.Medium)
            self:drawText(it.desc, -w, y + 26, 0.8, 0.8, 0.8, 1, UIFont.Small)
        end
    end
end
function BF_Moodles:onMouseDown(x, y)
    if #self.itens == 0 then return false end
    local pn = self.pn
    if BF.painel[pn] then BF.painel[pn]:setVisible(not BF.painel[pn]:isVisible()) end
    return true
end
BF.painel = BF.painel or {}
BF.moodles = BF.moodles or {}

Events.OnCreatePlayer.Add(function(i, p)
    if not p then return end
    if p:isLocalPlayer() then
        if not BF.painel[i] then
            BF.painel[i] = BF_Painel:new(i); BF.painel[i]:initialise(); BF.painel[i]:addToUIManager(); BF.painel[i]:setVisible(false)
            BF.moodles[i] = BF_Moodles:new(i); BF.moodles[i]:initialise(); BF.moodles[i]:addToUIManager()
        end
    end
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
