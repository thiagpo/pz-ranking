require "BagresFarm"
require "BagresFarm_Acoes"
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

-- desmaio: cai no chao (animacao que os outros veem) e fica 2 minutos sem conseguir se mover
BF.desmaio = BF.desmaio or {}
local DESMAIO_MS = 120000

local function cair(p)
    pcall(function()
        p:setBumpType("pushed"); p:setBumpDone(false); p:setBumpFall(true); p:setBumpFallType("pushed")
    end)
end

local function desmaiar(p)
    local n = p:getPlayerNum()
    BF.desmaio[n] = { fim = getTimestampMs() + DESMAIO_MS, sentar = getTimestampMs() + 2500 }
    cair(p)
    pcall(function() p:StopAllActionQueue() end)
    pcall(function() p:setBlockMovement(true) end)
    pcall(function() p:getStats():set(CharacterStat.FATIGUE, math.max(p:getStats():get(CharacterStat.FATIGUE), 0.7)) end)
    HaloTextHelper.addBadText(p, getText("IGUI_BF_Overdose"))
    HaloTextHelper.addBadText(p, getText("IGUI_BF_Desmaio"))
end

Events.OnPlayerUpdate.Add(function(p)
    if not p or not p:isLocalPlayer() then return end
    local n = p:getPlayerNum(); local e = BF.desmaio[n]
    if not e then return end
    local agoraMs = getTimestampMs()
    if p:isDead() or agoraMs >= e.fim then
        BF.desmaio[n] = nil
        pcall(function()
            p:setBlockMovement(false); p:setBumpFall(false); p:setBumpDone(true)
            if p:isSitOnGround() or p:isSitting() then p:setVariable("forceGetUp", true) end
        end)
        if not p:isDead() then HaloTextHelper.addGoodText(p, getText("IGUI_BF_Acordou")) end
        return
    end
    pcall(function() p:setBlockMovement(true) end)
    if e.sentar and agoraMs >= e.sentar then
        e.sentar = nil
        pcall(function() p:setAutoWalk(false); p:reportEvent("EventSitOnGround") end)
    end
    if not e.sentar then
        pcall(function()
            if p:getCurrentActionContextStateName() == "idle" and not p:isSitOnGround() and not p:isSitting() then p:reportEvent("EventSitOnGround") end
            local fila = ISTimedActionQueue.getTimedActionQueue(p)
            if fila and fila.queue and #fila.queue > 0 then p:StopAllActionQueue() end
        end)
    end
end)

BF.visual = BF.visual or {}

function BF.tracoPermanente(p, trait, chave)
    if not trait then return end
    pcall(function()
        if not p:hasTrait(trait) then
            p:getCharacterTraits():add(trait)
            HaloTextHelper.addBadText(p, getText(chave))
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
        HaloTextHelper.addGoodText(p, nome(id))
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
        HaloTextHelper.addBadText(p, getText("IGUI_BF_Careca"))
    end
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
    if overdose and BF.sb("Overdose", true) then desmaiar(p) end
end

-- pouca pratica em Primeiros Socorros: chance de se machucar com a agulha
function BF.acidenteSeringa(p)
    local doutor = p:getPerkLevel(Perks.Doctor)
    local risco = math.max(0, 5 - doutor) * (BF.sb("RiscoAgulha", 4) / 100)
    if ZombRandFloat(0, 1) >= risco then return end
    local bp = p:getBodyDamage():getBodyPart(BodyPartType[PARTES_SERINGA[ZombRand(1, #PARTES_SERINGA + 1)]])
    local r = ZombRandFloat(0, 1)
    if r < 0.6 then bp:setScratched(true, true); HaloTextHelper.addBadText(p, getText("IGUI_BF_Arranhao"))
    elseif r < 0.9 then bp:setCut(true); HaloTextHelper.addBadText(p, getText("IGUI_BF_Corte"))
    else bp:generateDeepWound(); HaloTextHelper.addBadText(p, getText("IGUI_BF_Laceracao")) end
end

local function listaAtivos(p)
    local st = estado(p); local t = agora(); local linhas = {}
    for id, e in pairs(st.ef) do
        local desc = BF.descricaoEfeito(id, e.m, e.d)
        if e.peso0 then desc = desc .. " " .. getText("IGUI_BF_Peso", string.format("%.1f", p:getNutrition():getWeight()), string.format("%.2f", e.peso0 - p:getNutrition():getWeight())) end
        table.insert(linhas, { id = id, txt = nome(id), resta = e.fim - t, total = e.fim - e.ini, m = e.m, bom = true, desc = desc })
    end
    for id, e in pairs(st.pos) do
        if e.fim > t then table.insert(linhas, { id = id, txt = nome(id) .. " (" .. getText("IGUI_BF_Ressaca") .. ")", resta = e.fim - t, total = e.fim - (e.ini or (e.fim - 2)), bom = false, desc = getText("IGUI_BF_RessacaDesc") }) end
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
        if id and item:getContainer() and (not BF.DROGAS[id].drenavel or item:getCurrentUsesFloat() > 0) then
            local d = BF.DROGAS[id]
            local noInv = p:getInventory():containsRecursive(item)
            local txt = getText(d.inj and "ContextMenu_BF_Injetar" or "ContextMenu_BF_Tomar") .. " " .. item:getDisplayName()
            local op = context:addOption(txt, p, function(pl)
                if not noInv then ISTimedActionQueue.add(ISInventoryTransferAction:new(pl, item, item:getContainer(), pl:getInventory())) end
                ISTimedActionQueue.add(BF_UsarAction:new(pl, item, id))
            end)
            local st = estado(p)
            local tip = ISInventoryPaneContextMenu.addToolTip()
            tip:setName(item:getDisplayName())
            BF.garantirPotencia(item)
            local tolProx = BF.tolerancia((st.usos[id] or 0) + 1)
            local desc = getText("Tooltip_" .. item:getType()) .. " <LINE> <LINE> "
                .. getText("IGUI_BF_ComEstaDose") .. ": " .. BF.descricaoEfeito(id, BF.potencia(item) * (1 - tolProx) * (d.inj and (1 + 0.03 * p:getPerkLevel(Perks.Doctor)) or 1), 1 + tolProx) .. " <LINE> <LINE> "
                .. getText("IGUI_BF_Potencia") .. ": x" .. string.format("%.2f", BF.potencia(item))
            if d.inj then desc = desc .. " <LINE> " .. getText("IGUI_BF_ForaGeladeira") .. ": " .. string.format("%.1f", BF.horasFora(item) / 24) .. " d" end
            if BF.suja(item) then desc = desc .. " <LINE> " .. getText("IGUI_BF_SeringaSujaAviso") end
            local pct = math.floor(BF.tolerancia((st.usos[id] or 0) + 1) * 100 + 0.5)
            desc = desc .. " <LINE> " .. getText("IGUI_BF_Doses") .. ": " .. (st.usos[id] or 0) .. " (" .. getText("IGUI_BF_Tolerancia") .. ": " .. getText("IGUI_BF_TolInfo", 100 - pct, pct) .. ")"
            if d.inj and st.ultDose[id] and agora() - st.ultDose[id] < BF.OVERDOSE_H then desc = desc .. " <LINE> " .. getText("IGUI_BF_OverdoseAviso") end
            local ativos = listaAtivos(p)
            if #ativos > 0 then
                local l = {}
                for _, a in ipairs(ativos) do table.insert(l, a.txt .. (a.resta > 0 and (": " .. horas(a.resta)) or "")) end
                desc = desc .. " <LINE> <LINE> " .. getText("IGUI_BF_Ativos") .. ": <LINE> " .. table.concat(l, " <LINE> ")
            end
            tip.description = desc
            op.toolTip = tip
            if d.inj and noInv then
                for _, alvo in ipairs(BF.jogadoresPerto(p)) do
                    local quem = alvo:getDescriptor() and alvo:getDescriptor():getForename() or tostring(alvo:getUsername())
                    local op2 = context:addOption(getText("ContextMenu_BF_InjetarEm") .. " " .. quem .. ": " .. item:getDisplayName(), p, function(pl)
                        BF.pedirInjecao(pl, alvo, item, id)
                    end)
                    local tip2 = ISInventoryPaneContextMenu.addToolTip()
                    tip2.description = getText("IGUI_BF_AplicarInfo", p:getPerkLevel(Perks.Doctor), math.floor(math.max(0, 5 - p:getPerkLevel(Perks.Doctor)) * 4 + 0.5), 3 * p:getPerkLevel(Perks.Doctor))
                    op2.toolTip = tip2
                end
            end
            return
        end
    end
end
Events.OnFillInventoryObjectContextMenu.Add(menu)

-- uso proprio confirmado pelo servidor (a acao termina la): aplica o efeito no cliente
local AVISO_FERIDA = { "IGUI_BF_Arranhao", "IGUI_BF_Corte", "IGUI_BF_Laceracao" }
function BF.receberUso(p, args)
    if not p or not args or not BF.DROGAS[args.id] then return end
    if args.ferida then BF.aplicarFerida(p, args.ferida); HaloTextHelper.addBadText(p, getText(AVISO_FERIDA[args.ferida.tipo] or "IGUI_BF_Arranhao")) end
    BF.usar(p, args.id, args.pot, args.suja)
end

-- autorizacao: quem vai receber a injecao precisa aceitar (como na avaliacao medica)
BF.pedidos = BF.pedidos or {}
function BF.pedirInjecao(p, alvo, item, id)
    local quem = p:getDescriptor() and p:getDescriptor():getForename() or tostring(p:getUsername())
    BF.pedidos[alvo:getUsername()] = { item = item, id = id, alvo = alvo, t = getTimestampMs() }
    local args = { alvo = alvo:getUsername(), de = p:getUsername(), quem = quem, droga = nome(id) }
    if alvo:isLocalPlayer() then
        BF.receberPedido(alvo, args)
    elseif isClient() then
        sendClientCommand(p, "BagresFarm", "pedir", args)
    end
    HaloTextHelper.addText(p, getText("IGUI_BF_PedidoEnviado", quem))
end
function BF.receberPedido(p, args)
    local modal = ISModalDialog:new(getCore():getScreenWidth() / 2 - 175, getCore():getScreenHeight() / 2 - 75, 350, 150,
        getText("IGUI_BF_Pedido", args.quem or "?", args.droga or "?"), true, nil, function(_, button)
            if button.internal == "YES" then
                local resposta = { alvo = args.de, de = p:getUsername() }
                if isClient() then sendClientCommand(p, "BagresFarm", "aceitar", resposta) else BF.receberAceite(getSpecificPlayer(0), resposta) end
            end
        end)
    modal:initialise(); modal:addToUIManager(); modal.moveWithMouse = true; modal:bringToTop()
end
function BF.receberAceite(p, args)
    local ped = BF.pedidos[args.de]
    if not ped or getTimestampMs() - ped.t > 120000 then return end
    BF.pedidos[args.de] = nil
    if not p:getInventory():containsRecursive(ped.item) then return end
    ISTimedActionQueue.add(ISWalkToTimedAction:new(p, ped.alvo:getSquare()))
    ISTimedActionQueue.add(BF_AplicarAction:new(p, ped.alvo, ped.item, ped.id))
end

-- aplicacao em outro jogador: o efeito roda no cliente do alvo
function BF.receberAplicacao(p, args, quem)
    if args.ferida then
        BF.aplicarFerida(p, args.ferida)
        HaloTextHelper.addBadText(p, getText("IGUI_BF_AplicouMal", quem))
    end
    HaloTextHelper.addGoodText(p, getText("IGUI_BF_Injetado", quem, nome(args.id)))
    BF.usar(p, args.id, args.pot, args.suja)
end
local receberAplicacao = BF.receberAplicacao

function BF.aplicarEm(p, alvo, id, pot, suja, ferida)
    local quem = p:getDescriptor() and p:getDescriptor():getForename() or tostring(p:getUsername())
    local args = { alvo = alvo:getUsername(), id = id, pot = pot, suja = suja, ferida = ferida, quem = quem }
    if alvo:isLocalPlayer() then receberAplicacao(alvo, args, quem); return end
    if isClient() then sendClientCommand(p, "BagresFarm", "aplicar", args) end
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "BagresFarm" or not args then return end
    for i = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(i)
        if p and not p:isDead() and p:getUsername() == args.alvo then
            if command == "aplicado" then receberAplicacao(p, args, args.quem or "?")
            elseif command == "usar" then BF.receberUso(p, args)
            elseif command == "teste" then BF.mostrarTeste(p, args)
            elseif command == "pedido" then BF.receberPedido(p, args)
            elseif command == "aceite" then BF.receberAceite(p, args) end
        end
    end
end)

-- kit antidoping: botao direito no kit lista os jogadores a ate 3 quadros
function BF.jogadoresPerto(p)
    local lista = {}
    local function add(o)
        if o and o ~= p and not o:isDead() and math.abs(o:getX() - p:getX()) <= 3 and math.abs(o:getY() - p:getY()) <= 3 then table.insert(lista, o) end
    end
    if isClient() then
        local ok, on = pcall(getOnlinePlayers)
        if ok and on then for i = 0, on:size() - 1 do add(on:get(i)) end end
    end
    for i = 0, getNumActivePlayers() - 1 do add(getSpecificPlayer(i)) end
    return lista
end

function BF.textoLaudo(args)
    local t0 = args.t or agora(); local linhas = {}
    for _, h in ipairs(args.hist or {}) do
        if t0 - h.t <= BF.HIST_H and BF.DROGAS[h.id] then table.insert(linhas, nome(h.id) .. " - " .. getText("IGUI_BF_Ha") .. " " .. horas(t0 - h.t)) end
    end
    local quem = args.quem or "?"
    local texto = getText("IGUI_BF_TesteTitulo", quem) .. " <LINE> <LINE> "
    if #linhas == 0 then texto = texto .. getText("IGUI_BF_TesteLimpo") else texto = texto .. table.concat(linhas, " <LINE> ") end
    return texto
end

function BF.mostrarTeste(p, args)
    local t = agora(); local linhas = {}
    for _, h in ipairs(args.hist or {}) do
        if t - h.t <= BF.HIST_H and BF.DROGAS[h.id] then table.insert(linhas, nome(h.id) .. " - " .. getText("IGUI_BF_Ha") .. " " .. horas(t - h.t)) end
    end
    local quem = args.quem or "?"
    local texto = getText("IGUI_BF_TesteTitulo", quem) .. " <LINE> <LINE> "
    if #linhas == 0 then texto = texto .. getText("IGUI_BF_TesteLimpo") else texto = texto .. table.concat(linhas, " <LINE> ") end
    if ISModalRichText then
        local m = ISModalRichText:new(getCore():getScreenWidth() / 2 - 180, getCore():getScreenHeight() / 2 - 100, 360, 200, texto, false)
        m:initialise(); m:addToUIManager()
    else
        HaloTextHelper.addText(p, texto)
    end
end

local function menuKit(playerNum, context, items)
    local p = getSpecificPlayer(playerNum)
    if not p or p:isDead() then return end
    for _, entry in ipairs(items) do
        local item = entry
        if not instanceof(entry, "InventoryItem") then item = entry.items and entry.items[1] end
        if item and item:getFullType() == "Base.BF_Resultado" then
            local md = item:getModData().bf_teste
            local op = context:addOption(getText("ContextMenu_BF_Ler"), p, function(pl)
                local texto = md and BF.textoLaudo(md) or getText("IGUI_BF_LaudoVazio")
                if ISModalRichText then
                    local m = ISModalRichText:new(getCore():getScreenWidth() / 2 - 180, getCore():getScreenHeight() / 2 - 100, 360, 200, texto, false)
                    m:initialise(); m:addToUIManager()
                else HaloTextHelper.addText(pl, texto) end
            end)
            local tip = ISInventoryPaneContextMenu.addToolTip(); tip:setName(item:getDisplayName())
            tip.description = (md and BF.textoLaudo(md) or getText("IGUI_BF_LaudoVazio")) .. " <LINE> <LINE> " .. getText("IGUI_BF_LaudoData", md and string.format("%.0f", (agora() - (md.t or agora()))) or "0")
            op.toolTip = tip
            return
        end
        if item and item:getFullType() == "Base.BF_KitAntidoping" and p:getInventory():containsRecursive(item) then
            local perto = BF.jogadoresPerto(p)
            if #perto == 0 then
                local op = context:addOption(getText("ContextMenu_BF_Teste") .. "...", nil, nil); op.notAvailable = true
                local tip = ISInventoryPaneContextMenu.addToolTip(); tip.description = getText("IGUI_BF_Ninguem"); op.toolTip = tip
            end
            for _, alvo in ipairs(perto) do
                local quem = alvo:getDescriptor() and alvo:getDescriptor():getForename() or tostring(alvo:getUsername())
                context:addOption(getText("ContextMenu_BF_Teste") .. " " .. quem, p, function(pl)
                    ISTimedActionQueue.add(BF_TesteAction:new(pl, alvo, item))
                end)
            end
            return
        end
    end
end
Events.OnFillInventoryObjectContextMenu.Add(menuKit)

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
                    local m2, d2 = BF.mult(e, t)
                    if d.gripe then local bd = p:getBodyDamage(); if bd:getCatchACold() > 0 then bd:setCatchACold(0) end end
                    if d.cura then
                        local bd = p:getBodyDamage(); local cs = bd:getColdStrength()
                        if cs > 0 then
                            cs = cs - (100 / (d.cura * 60)) * m2
                            if cs <= 0 then cs = 0; bd:setHasACold(false); HaloTextHelper.addGoodText(p, getText("IGUI_BF_Curado") .. ": " .. getText("IGUI_BF_Resfriado")) end
                            bd:setColdStrength(cs)
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
                    if s > 0 then bp:setStiffness(math.max(0, s - s * math.min(0.9, rig))) end
                end
            end
            if peso > 0 then
                local nut = p:getNutrition(); local w = nut:getWeight()
                if w > 50 then nut:setWeight(w - peso / 1440) end
            end
            if paranoia > 0 and ZombRandFloat(0, 1) < paranoia then
                p:getEmitter():playSound(VOZES[ZombRand(1, #VOZES + 1)])
                setStat(p, CharacterStat.PANIC, 100)
                setStat(p, CharacterStat.STRESS, clamp(stat(p, CharacterStat.STRESS) + 0.15, 0, 1))
                BF.visual[i] = BF.visual[i] or {}; BF.visual[i].flash = getTimestampMs()
                HaloTextHelper.addBadText(p, getText("IGUI_BF_Paranoia"))
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

-- overlays de tela: sedado (verde), paranoia (vermelho), loló (quente), desmaio e ressaca (escuro)
local OV = {}
local function tex(nome)
    if OV[nome] == nil then OV[nome] = getTexture("media/ui/" .. nome .. ".png") or false end
    return OV[nome] or nil
end
local function camada(nome, a, w, h)
    if a <= 0.01 then return end
    local tx = tex(nome); if not tx then return end
    UIManager.DrawTexture(tx, 0, 0, w, h, math.min(1, a))
end
Events.OnPostUIDraw.Add(function()
    if not BF.sb("Overlays", true) then return end
    local p = getSpecificPlayer(0)
    if not p or p:isDead() then return end
    local md = p:getModData().BF
    local v = BF.visual[0] or {}
    local ms = getTimestampMs()
    local w, h = getCore():getScreenWidth(), getCore():getScreenHeight()
    local pulso = 0.5 + 0.5 * math.sin(ms / 900)
    local verde, vermelho, escuro, quente, roxo = 0, 0, 0, 0, 0
    if md and md.ef then
        local t = agora()
        for id, e in pairs(md.ef) do
            local m2 = BF.mult(e, t)
            if id == "Morfina" then verde = math.max(verde, 0.45 * math.min(1, m2)) end
            if id == "Metanfetamina" then vermelho = math.max(vermelho, 0.12 + 0.12 * pulso) end
            if id == "Rebite" then roxo = math.max(roxo, 0.18 + 0.08 * pulso) end
            if id == "Tadala" or id == "Dipirona" then verde = math.max(verde, 0.12) end
        end
        if md.abst then escuro = math.max(escuro, 0.15 + 0.1 * pulso) end
        for id, e in pairs(md.pos or {}) do if e.fim > agora() and id == "Rebite" then escuro = math.max(escuro, 0.3) end end
    end
    if v.flash then local dt = (ms - v.flash) / 1500; if dt < 1 then vermelho = math.max(vermelho, 0.7 * (1 - dt)) else v.flash = nil end end
    if v.loloAte then if ms < v.loloAte then quente = 0.35 * math.min(1, (v.loloAte - ms) / 90000) + 0.05 * pulso else v.loloAte = nil end end
    if BF.desmaio[0] then escuro = 0.9 end
    camada("BF_ov_verde", verde, w, h); camada("BF_ov_roxo", roxo, w, h); camada("BF_ov_quente", quente, w, h)
    camada("BF_ov_vermelho", vermelho, w, h); camada("BF_ov_escuro", escuro, w, h)
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
local LINHA = 26
function BF_Painel:new(pn)
    local o = ISPanel.new(self, 80, 120, 300, 60)
    o.pn = pn; o.moveWithMouse = true; o.backgroundColor = { r = 0.05, g = 0.06, b = 0.07, a = 0.88 }; o.borderColor = { r = 0.3, g = 0.5, b = 0.35, a = 0.8 }
    o.aberto = {}; o.diag = false; o.linhas = {}
    return o
end
function BF_Painel:prerender()
    local p = getSpecificPlayer(self.pn)
    local ativos = p and listaAtivos(p) or {}
    self.linhas = {}
    local y = 26
    for _, l in ipairs(ativos) do
        local alt = LINHA + ((self.aberto[l.txt] and l.desc and l.desc ~= "") and 16 or 0)
        table.insert(self.linhas, { l = l, y = y, alt = alt }); y = y + alt
    end
    if #ativos == 0 then y = y + LINHA end
    local v = BF.visual[self.pn]
    if self.diag and v and v.fomeM then y = y + 16 end
    self:setHeight(y + 6)
    ISPanel.prerender(self)
    self:drawText(getText("IGUI_BF_Painel"), 8, 5, 1, 1, 1, 1, UIFont.Small)
    -- botoes do cabecalho: i (diagnostico) e x (fechar)
    self:drawRectBorder(self.width - 44, 5, 16, 16, 0.7, 0.6, 0.6, 0.6); self:drawTextCentre("i", self.width - 36, 4, 1, 1, 1, self.diag and 1 or 0.6, UIFont.Small)
    self:drawRectBorder(self.width - 24, 5, 16, 16, 0.7, 0.6, 0.6, 0.6); self:drawTextCentre("x", self.width - 16, 4, 1, 0.6, 0.6, 1, UIFont.Small)
    for _, r in ipairs(self.linhas) do
        local l = r.l
        local frac = l.total > 0 and clamp(l.resta / l.total, 0, 1) or 1
        self:drawRect(8, r.y, self.width - 16, 22, 0.45, 0.14, 0.15, 0.17)
        if l.resta > 0 then
            if l.bom then self:drawRect(8, r.y, (self.width - 16) * frac, 22, 0.5, 0.22, 0.55, 0.28)
            else self:drawRect(8, r.y, (self.width - 16) * frac, 22, 0.5, 0.65, 0.3, 0.2) end
        end
        if l.id then
            local ic = getTexture("Item_BF_" .. l.id)
            if ic then self:drawTextureScaled(ic, 11, r.y + 2, 18, 18, 1, 1, 1, 1) end
        end
        self:drawText(l.txt, 34, r.y + 3, 1, 1, 1, 1, UIFont.Small)
        if l.resta > 0 then self:drawTextRight(horas(l.resta), self.width - 12, r.y + 3, 0.85, 0.85, 0.85, 1, UIFont.Small) end
        if self.aberto[l.txt] and l.desc and l.desc ~= "" then self:drawText(l.desc, 34, r.y + 23, 0.75, 0.8, 0.75, 1, UIFont.Small) end
    end
    if #ativos == 0 then self:drawText(getText("IGUI_BF_Nada"), 12, 30, 0.7, 0.7, 0.7, 1, UIFont.Small) end
    if self.diag and v and v.fomeM and p then
        local diag = getText("IGUI_BF_Diag", string.format("%.2f", v.fomeM), string.format("%.2f", v.fadM or 1), math.floor(stat(p, CharacterStat.HUNGER) * 100 + 0.5), math.floor(stat(p, CharacterStat.FATIGUE) * 100 + 0.5))
        self:drawText(diag, 12, self.height - 20, 0.6, 0.8, 0.6, 1, UIFont.Small)
    end
end
function BF_Painel:onMouseDown(x, y)
    if y >= 5 and y <= 21 then
        if x >= self.width - 44 and x <= self.width - 28 then self.diag = not self.diag; return true end
        if x >= self.width - 24 and x <= self.width - 8 then self:setVisible(false); return true end
    end
    for _, r in ipairs(self.linhas) do
        if y >= r.y and y < r.y + 22 then self.aberto[r.l.txt] = not self.aberto[r.l.txt]; return true end
    end
    return ISPanel.onMouseDown(self, x, y)
end

-- botao pequeno que abre e fecha o painel
BF_Botao = ISUIElement:derive("BF_Botao")
function BF_Botao:new(pn)
    local o = ISUIElement.new(self, 0, 0, 26, 26)
    o.pn = pn
    return o
end
function BF_Botao:render()
    local tex = getTexture("media/ui/BF_botao.png")
    if tex then self:drawTexture(tex, 0, 0, 1, 1, 1, 1) else self:drawRect(0, 0, 26, 26, 0.8, 0.2, 0.5, 0.3) end
    local p = getSpecificPlayer(self.pn)
    local md = p and p:getModData().BF
    local n = 0
    if md then for _ in pairs(md.ef or {}) do n = n + 1 end end
    if n > 0 then self:drawTextCentre(tostring(n), 13, 1, 1, 1, 1, 1, UIFont.Small) end
    if self:isMouseOver() then
        local txt = getText("IGUI_BF_Botao")
        local w = getTextManager():MeasureStringX(UIFont.Small, txt) + 12
        self:drawRect(-w - 4, 2, w, 20, 0.85, 0, 0, 0); self:drawText(txt, -w + 2, 4, 1, 1, 1, 1, UIFont.Small)
    end
end
function BF_Botao:onMouseDown(x, y)
    if BF.painel[self.pn] then BF.painel[self.pn]:setVisible(not BF.painel[self.pn]:isVisible()) end
    return true
end

local TIPOS_MOODLE = { "ANGRY", "BLEEDING", "BORED", "CANT_SPRINT", "DEAD", "DRUNK", "ENDURANCE", "FOOD_EATEN", "HAS_A_COLD", "HEAVY_LOAD", "HUNGRY",
    "HYPERTHERMIA", "HYPOTHERMIA", "INJURED", "NOXIOUS_SMELL", "PAIN", "PANIC", "SICK", "STRESS", "THIRST", "TIRED", "UNCOMFORTABLE", "UNHAPPY", "WINDCHILL", "ZOMBIE" }
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
    local p = getSpecificPlayer(self.pn)
    local tam = ({ 32, 48, 64, 80, 96, 128 })[(getCore():getOptionMoodleSize() or 1)] or 32
    local passo = tam + 13
    local n = 0
    if p then
        local mo = p:getMoodles()
        for _, k in ipairs(TIPOS_MOODLE) do
            local ok, lv = pcall(function() return mo:getMoodleLevel(MoodleType[k]) end)
            if ok and lv and lv > 0 then n = n + 1 end
        end
    end
    local bx = getCore():getScreenWidth() - 10 - tam
    local by = 118 + n * passo
    self:setX(bx + (tam - 36) / 2); self:setY(by + 30)
    if BF.botao[self.pn] then BF.botao[self.pn]:setX(bx + (tam - 26) / 2); BF.botao[self.pn]:setY(by) end
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
BF.botao = BF.botao or {}

Events.OnCreatePlayer.Add(function(i, p)
    if not p then return end
    if p:isLocalPlayer() then
        if not BF.painel[i] then
            BF.painel[i] = BF_Painel:new(i); BF.painel[i]:initialise(); BF.painel[i]:addToUIManager(); BF.painel[i]:setVisible(false)
            BF.moodles[i] = BF_Moodles:new(i); BF.moodles[i]:initialise(); BF.moodles[i]:addToUIManager()
            BF.botao[i] = BF_Botao:new(i); BF.botao[i]:initialise(); BF.botao[i]:addToUIManager()
        end
        -- farmaceutico: comeca com Primeiros Socorros 2 (o bonus de XP vem do Lua, nao do nivel)
        local st0 = estado(p)
        if not st0.inicial then
            st0.inicial = true
            if BF.PROF and p:getDescriptor():isCharacterProfession(BF.PROF) and p:getPerkLevel(Perks.Doctor) < 2 and p:getHoursSurvived() < 1 then
                pcall(function() p:getXp():setXPToLevel(Perks.Doctor, 2) end)
            end
        end
    end
    local md = p:getModData().BF
    if not md then return end
    local st = estado(p); local t = agora()
    for id, e in pairs(st.ef) do if t >= e.fim then st.ef[id] = nil end end
    aplicarForca(p, st)
    local temAud, temVis = false, false
    for id in pairs(st.ef) do
        if BF.DROGAS[id] and BF.DROGAS[id].audicao then temAud = true end
        if BF.DROGAS[id] and BF.DROGAS[id].visao then temVis = true end
    end
    if st.audicaoTemp and not temAud then audicao(p, st, false) end
    local temAdr = false
    for id in pairs(st.ef) do if BF.DROGAS[id] and BF.DROGAS[id].adrenalina then temAdr = true end end
    if st.adrTemp and not temAdr then tracoTemp(p, st, CharacterTrait.ADRENALINE_JUNKIE, "adrTemp", false) end
    if (st.visaoTemp or st.visaoNV) and not temVis then visao(p, st, false) end
    if temVis and not st.visaoTemp and not st.visaoNV then visao(p, st, true) end
end)

Events.OnPlayerDeath.Add(function(p)
    local md = p and p:getModData().BF
    if md and md.mwb then p:setMaxWeightBase(md.mwb) end
end)
