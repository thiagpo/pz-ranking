require "BagresFarm"
-- motor de efeitos: roda no servidor (todos os jogadores online) e no cliente (jogador local), como as acoes do jogo
local BF = BagresFarm
local VOZES = { "MaleZombieVoiceA", "MaleZombieVoiceB", "FemaleZombieVoiceA", "MaleZombieSprinterVoiceA", "FemaleZombieSprinterVoiceB" }
local PARTES_SERINGA = BF.PARTES_SERINGA
local ult = {}
local Halo = {
    addGoodText = function(p, t) if not isServer() and HaloTextHelper then Halo.addGoodText(p, t) end end,
    addBadText = function(p, t) if not isServer() and HaloTextHelper then Halo.addBadText(p, t) end end,
    addText = function(p, t) if not isServer() and HaloTextHelper then Halo.addText(p, t) end end,
}
function BF.chave(p) if isServer() then return p:getUsername() end return p:getPlayerNum() end
function BF.jogadores()
    local lista = {}
    if isServer() then
        local on = getOnlinePlayers()
        for i = 0, on:size() - 1 do table.insert(lista, on:get(i)) end
    else
        for i = 0, getNumActivePlayers() - 1 do local p = getSpecificPlayer(i); if p then table.insert(lista, p) end end
    end
    return lista
end

local function agora() return getGameTime():getWorldAgeHours() end

local function estado(p)
    local md = p:getModData()
    md.BF = md.BF or {}
    local st = md.BF
    st.ef = st.ef or {}; st.usos = st.usos or {}; st.pos = st.pos or {}; st.ultDose = st.ultDose or {}; st.hist = st.hist or {}
    return st
end

local function nome(id)
    local si = getScriptManager():getItem(BF.DROGAS[id].item)
    if si then local n = si:getDisplayName(); if n and n ~= "" then return n end end
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

-- traco temporario generico (adrenalina = Viciado em Adrenalina enquanto durar)
local function tracoTemp(p, st, trait, flag, ligar)
    pcall(function()
        if ligar then
            if not p:hasTrait(trait) then p:getCharacterTraits():add(trait); st[flag] = true end
        elseif st[flag] then
            p:getCharacterTraits():remove(trait); st[flag] = nil
        end
    end)
end

-- visao noturna: quem nao tem Olhos de Gato ganha o traco temporario; quem ja tem ganha o efeito dos oculos de visao noturna
local function visao(p, st, ligar)
    pcall(function()
        local t = CharacterTrait.NIGHT_VISION
        if ligar then
            if not p:hasTrait(t) then p:getCharacterTraits():add(t); st.visaoTemp = true
            else p:setWearingNightVisionGoggles(true); st.visaoNV = true end
        else
            if st.visaoTemp then p:getCharacterTraits():remove(t); st.visaoTemp = nil end
            if st.visaoNV then p:setWearingNightVisionGoggles(false); st.visaoNV = nil end
        end
    end)
end


-- exportado para a interface (arquivo do cliente)
BF.agora = agora; BF.estado = estado; BF.nome = nome; BF.stat = stat; BF.setStat = setStat; BF.clamp = clamp; BF.vazio = vazio; BF.horas = horas
BF.aplicarForca = aplicarForca; BF.audicao = audicao; BF.visao = visao; BF.tracoTemp = tracoTemp

-- zera todos os efeitos, ressacas e tracos emprestados (overdose)
function BF.limparEfeitos(p)
    local st = estado(p)
    for id in pairs(st.ef) do st.ef[id] = nil end
    for id in pairs(st.pos) do st.pos[id] = nil end
    st.abst = nil
    audicao(p, st, false); visao(p, st, false); tracoTemp(p, st, CharacterTrait.ADRENALINE_JUNKIE, "adrTemp", false)
    aplicarForca(p, st)
    if not isServer() then pcall(function() p:transmitModData() end) end
end
BF.visual = BF.visual or {}

function BF.tracoPermanente(p, trait, chave)
    if not trait then return end
    pcall(function()
        if not p:hasTrait(trait) then
            p:getCharacterTraits():add(trait)
            Halo.addBadText(p, getText(chave))
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
    if d.visao then visao(p, st, false) end
    if d.adrenalina then tracoTemp(p, st, CharacterTrait.ADRENALINE_JUNKIE, "adrTemp", false) end
    if d.forca then aplicarForca(p, st) end
    Halo.addBadText(p, nome(id) .. " " .. getText("IGUI_BF_Passou"))
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
    local tol = BF.tolerancia(st.usos[id])
    local fator = 1 + tol
    local t = agora()
    if d.lolo then
        setStat(p, CharacterStat.NICOTINE_WITHDRAWAL, 0)
        setStat(p, CharacterStat.STRESS, clamp(stat(p, CharacterStat.STRESS) - 0.15, 0, 1))
        setStat(p, CharacterStat.UNHAPPINESS, clamp(stat(p, CharacterStat.UNHAPPINESS) - 5, 0, 100))
        setStat(p, CharacterStat.SICKNESS, clamp(stat(p, CharacterStat.SICKNESS) + 15 * fator, 0, 100))
        setStat(p, CharacterStat.INTOXICATION, clamp(stat(p, CharacterStat.INTOXICATION) + 25 * fator, 0, 100))
        BF.visual[p:getPlayerNum()] = BF.visual[p:getPlayerNum()] or {}; BF.visual[p:getPlayerNum()].loloAte = getTimestampMs() + 90000
        if d.dur > 0 then st.ef[id] = { ini = t, fim = t + d.dur, m = 1, d = fator } end
        st.ultDose[id] = t
        Halo.addGoodText(p, nome(id))
        registrar(p, st, id, t)
        return
    end
    local overdose = d.inj and st.ultDose[id] and (t - st.ultDose[id]) < BF.OVERDOSE_H
    if (st.usos.Ozempic or 0) + (st.usos.Monjaro or 0) >= 8 then BF.tracoPermanente(p, BF.TRAIT_DESNUTRIDO, "IGUI_BF_Desnutrido") end
    if (st.usos.Deca or 0) + (st.usos.Trembolona or 0) >= 10 then BF.tracoPermanente(p, BF.TRAIT_CORACAO, "IGUI_BF_Coracao") end
    if d.cura then p:getBodyDamage():setCatchACold(0) end
    if d.fadigaJa then setStat(p, CharacterStat.FATIGUE, clamp(stat(p, CharacterStat.FATIGUE) + d.fadigaJa * (pot or 1), 0, 1)) end
    if d.fomeJa then setStat(p, CharacterStat.HUNGER, clamp(stat(p, CharacterStat.HUNGER) + d.fomeJa, 0, 1)) end
    if d.panico then setStat(p, CharacterStat.PANIC, clamp(stat(p, CharacterStat.PANIC) + d.panico, 0, 100)) end
    if d.depressao and st.usos[id] >= d.depressao then
        setStat(p, CharacterStat.UNHAPPINESS, clamp(stat(p, CharacterStat.UNHAPPINESS) + 5 * (st.usos[id] - d.depressao + 1), 0, 100))
    end
    if d.dur > 0 then st.ef[id] = { ini = t, fim = t + d.dur, m = (pot or 1) * (1 - tol), d = fator, peso0 = d.pesoDia and p:getNutrition():getWeight() or nil } end
    st.ultDose[id] = t
    if d.audicao then audicao(p, st, true) end
    if d.visao then visao(p, st, true) end
    if d.adrenalina then tracoTemp(p, st, CharacterTrait.ADRENALINE_JUNKIE, "adrTemp", true) end
    if d.forca then aplicarForca(p, st) end
    -- anabolizante e emagrecedor: a partir da 3a dose o cabelo cai
    if d.careca and not st.careca and (st.usos.Trembolona or 0) + (st.usos.Deca or 0) + (st.usos.Ozempic or 0) + (st.usos.Monjaro or 0) >= 3 then
        st.careca = true
        pcall(function() p:getHumanVisual():setHairModel(""); p:resetModelNextFrame(); if isClient() then sendVisual(p) end end)
        Halo.addBadText(p, getText("IGUI_BF_Careca"))
    end
    if suja then
        local bp = p:getBodyDamage():getBodyPart(BodyPartType[PARTES_SERINGA[ZombRand(1, #PARTES_SERINGA + 1)]])
        local r = ZombRandFloat(0, 1)
        if r < 0.03 then
            pcall(function() local bd = p:getBodyDamage(); bd:setInfected(true); bd:setInfectionTime(-1); bd:setInfectionMortalityDuration(-1) end)
            Halo.addBadText(p, getText("IGUI_BF_SeringaSujaZumbi"))
        elseif r < 0.38 then
            bp:setScratched(true, true); bp:setInfectedWound(true)
            Halo.addBadText(p, getText("IGUI_BF_SeringaSujaInfeccao"))
        end
    end
    Halo.addGoodText(p, nome(id))
    registrar(p, st, id, t)
    if overdose and BF.sb("Overdose", true) then desmaiar(p) end
end

-- pouca pratica em Primeiros Socorros: chance de se machucar com a agulha
function BF.acidenteSeringa(p)
    local doutor = p:getPerkLevel(Perks.Doctor)
    local risco = math.max(0, 5 - doutor) * (BF.sb("RiscoAgulha", 4) / 100)
    if ZombRandFloat(0, 1) >= risco then return end
    local bp = p:getBodyDamage():getBodyPart(BodyPartType[PARTES_SERINGA[ZombRand(1, #PARTES_SERINGA + 1)]])
    local r = ZombRandFloat(0, 1)
    if r < 0.6 then bp:setScratched(true, true); Halo.addBadText(p, getText("IGUI_BF_Arranhao"))
    elseif r < 0.9 then bp:setCut(true); Halo.addBadText(p, getText("IGUI_BF_Corte"))
    else bp:generateDeepWound(); Halo.addBadText(p, getText("IGUI_BF_Laceracao")) end
end

-- efeitos continuos (so no jogador local)
local function tick(p)
    if not p or p:isDead() or not p:isLocalPlayer() then return end
    local md = p:getModData().BF
    local n0 = p:getPlayerNum()
    local vis = BF.visual[n0]
    local trDes = vis and vis.trDes; local trCor = vis and vis.trCor
    if not md or (vazio(md.ef) and vazio(md.pos) and not md.abst and not trDes and not trCor) then return end
    local st = estado(p); local t = agora()
    local n = p:getPlayerNum()
    local u = ult[n]; if not u then u = { sang = {} }; ult[n] = u end

    local fomeM, fadM, dor = 1, 1, 0
    local folego, sangra = false, 0
    for id, e in pairs(st.ef) do
        local d = BF.DROGAS[id]
        if d then
            local m2, d2 = BF.mult(e, t)
            if d.fome then fomeM = fomeM + d.fome * (d.fome < 0 and m2 or d2) end
            if d.fadiga then fadM = fadM + d.fadiga * (d.fadiga < 0 and m2 or d2) end
            if d.dor then dor = dor + d.dor * m2 end
            if d.folego then folego = true end
            if d.sangramento then sangra = math.max(sangra, d.sangramento * d2) end
        end
    end
    if trDes then fomeM = fomeM + 0.3 end
    BF.visual[n] = BF.visual[n] or {}
    BF.visual[n].fomeM = fomeM; BF.visual[n].fadM = fadM; BF.visual[n].dor = dor
    local recup = 0
    for id, e in pairs(st.pos) do
        if e.fim > t then
            local d = BF.DROGAS[id]
            if d and d.recuperacao then recup = math.max(recup, d.recuperacao * e.d) end
            if d and d.sangramento then sangra = math.max(sangra, d.sangramento * e.d) end
            if d and d.fadigaPos then fadM = fadM + d.fadigaPos * e.d end
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

    local endu = stat(p, CharacterStat.ENDURANCE)
    if trCor and u.endu and endu > u.endu then endu = u.endu + (endu - u.endu) * 0.7; setStat(p, CharacterStat.ENDURANCE, endu) end
    u.endu = endu
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
                    Halo.addGoodText(p, getText("IGUI_BF_Curado") .. ": " .. nome(id))
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
        if t - (st.avisoAbst or 0) >= 1 then st.avisoAbst = t; Halo.addBadText(p, getText("IGUI_BF_Abstinencia")) end
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
                    local m2, d2 = BF.mult(e, t)
                    if d.gripe then local bd = p:getBodyDamage(); if bd:getCatchACold() > 0 then bd:setCatchACold(0) end end
                    if d.cura then
                        local bd = p:getBodyDamage(); local cs = bd:getColdStrength()
                        if cs > 0 then
                            cs = cs - (100 / (d.cura * 60)) * m2
                            if cs <= 0 then cs = 0; bd:setHasACold(false); Halo.addGoodText(p, getText("IGUI_BF_Curado") .. ": " .. getText("IGUI_BF_Resfriado")) end
                            bd:setColdStrength(cs)
                        end
                    end
                    if d.tosse and ZombRandFloat(0, 1) < 0.3 then pcall(function() p:playerVoiceSound("Cough") end) end
                    if d.grito then
                        if not e.proxGrito then e.proxGrito = t + 1 + ZombRandFloat(0, 2) end
                        if t >= e.proxGrito then
                            e.proxGrito = t + 3
                            pcall(function() p:Callout(false) end)
                            pcall(function() processShoutMessage(getText("IGUI_BF_Grito")) end)
                        end
                    end
                    if d.rigidez then rig = rig + d.rigidez * m2 end
                    if d.pesoDia then peso = peso + d.pesoDia * m2 end
                    if d.paranoia and (st.usos[id] or 0) >= d.paranoia then paranoia = paranoia + 0.12 * d2 * (1 + 0.15 * ((st.usos[id] or 0) - d.paranoia)) end
                    if d.depressao and (st.usos[id] or 0) >= d.depressao then depress = depress + 0.01 * (st.usos[id] or 0) * d2 end
                end
            end
            if rig > 0 then
                local partes = p:getBodyDamage():getBodyParts()
                for j = 0, partes:size() - 1 do
                    local bp = partes:get(j); local s = bp:getStiffness()
                    if s > 0 then
                        local novo = s - s * math.min(0.9, rig)
                        if novo < 3 then
                            bp:setStiffness(0)
                            pcall(function() p:getFitness():removeStiffnessValue(BodyPartType.ToString(bp:getType())) end)
                        else
                            bp:setStiffness(novo)
                        end
                    end
                end
            end
            if peso > 0 then
                local nut = p:getNutrition(); local w = nut:getWeight()
                if w > 50 then nut:setWeight(w - peso / 1440) end
            end
            if paranoia > 0 and ZombRandFloat(0, 1) < paranoia then
                local voz = VOZES[ZombRand(1, #VOZES + 1)]
                local ok = pcall(function() getSoundManager():PlaySound(voz, false, 1) end)
                if not ok then pcall(function() p:getEmitter():playSound(voz) end) end
                setStat(p, CharacterStat.PANIC, 100)
                setStat(p, CharacterStat.STRESS, clamp(stat(p, CharacterStat.STRESS) + 0.15, 0, 1))
                BF.visual[i] = BF.visual[i] or {}; BF.visual[i].flash = getTimestampMs()
            end
            if depress > 0 then setStat(p, CharacterStat.UNHAPPINESS, clamp(stat(p, CharacterStat.UNHAPPINESS) + depress, 0, 100)) end
            abstinencia(p, st, t)
            BF.visual[i] = BF.visual[i] or {}
            local v = BF.visual[i]
            pcall(function()
                v.trDes = BF.TRAIT_DESNUTRIDO ~= nil and p:hasTrait(BF.TRAIT_DESNUTRIDO)
                v.trCor = BF.TRAIT_CORACAO ~= nil and p:hasTrait(BF.TRAIT_CORACAO)
            end)
            -- tremor de abstinencia (animacao do jogo via AnimSet), so parado e desarmado
            if st.abst and ZombRandFloat(0, 1) < 0.5 and not p:getPrimaryHandItem() and not p:isPlayerMoving() then
                p:setVariable("BF_Pose", "tremor"); v.tremorAte = getTimestampMs() + 2500
            end
        end
    end
end
Events.EveryOneMinute.Add(minuto)

Events.OnPlayerUpdate.Add(function(p)
    if not p or not p:isLocalPlayer() then return end
    local v = BF.visual[p:getPlayerNum()]
    if v and v.tremorAte and getTimestampMs() >= v.tremorAte then v.tremorAte = nil; p:clearVariable("BF_Pose") end
end)

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
                BF.garantirPotencia(it)
                if tipo ~= "fridge" and tipo ~= "freezer" then
                    local md = it:getModData()
                    md.bf_fora = (md.bf_fora or 0) + 1
                    if md.bf_fora >= BF.validadeH() and not md.bf_vencido then md.bf_vencido = true end
                    if md.bf_fora % 24 == 0 or md.bf_fora >= BF.validadeH() then it:setName(BF.nomeItem(it)) end
                end
            end
        end
    end
end)

Events.OnPlayerDeath.Add(function(p)
    local md = p and p:getModData().BF
    if md and md.mwb then p:setMaxWeightBase(md.mwb) end
end)
