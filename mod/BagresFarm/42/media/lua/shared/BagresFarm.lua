-- Farms do Bagres: nucleo compartilhado (skill Farmacia, tabela de drogas, potencia na fabricacao)
BagresFarm = BagresFarm or {}
local BF = BagresFarm
BF.VERSION = "1.0"
BF.TOLERANCIA_MAX = 0.20
BF.TOLERANCIA_PASSO = 0.02

-- skill Farmacia (definida em media/perks.txt)
BF.PERK = Perks.Pharmacy or Perks.FromString("Pharmacy")
if not BF.PERK or tostring(BF.PERK) == "None" then print("[BagresFarm] skill Pharmacy nao encontrada") end

Events.OnGameBoot.Add(function()
    SkillBook = SkillBook or {}
    if BF.PERK and not SkillBook["Pharmacy"] then
        SkillBook["Pharmacy"] = { perk = BF.PERK, maxMultiplier1 = 3, maxMultiplier2 = 5, maxMultiplier3 = 8, maxMultiplier4 = 12, maxMultiplier5 = 16 }
    end
end)

-- drogas: id -> dados. dur em horas de jogo; inj = seringa (devolve seringa usada)
BF.DROGAS = {
    Ozempic       = { item = "Base.BF_Ozempic",       inj = true,  dur = 24, fome = -0.20, pesoDia = 0.10, fadiga = 0.15 },
    Monjaro       = { item = "Base.BF_Monjaro",       inj = true,  dur = 24, fome = -0.30, pesoDia = 0.20, fadiga = 0.25 },
    Trembolona    = { item = "Base.BF_Trembolona",    inj = true,  dur = 36, forca = 0.10, fome = 0.30 },
    Deca          = { item = "Base.BF_Deca",          inj = true,  dur = 48, forca = 0.15, fome = 0.40 },
    Morfina       = { item = "Base.BF_Morfina",       inj = true,  dur = 8,  dor = 0.80, rigidez = 0.10, paranoia = 3, depressao = 6 },
    Adrenalina    = { item = "Base.BF_Adrenalina",    inj = true,  dur = 1,  folego = true, audicao = true, panico = -60, fadigaFim = 0.50, sangramento = 0.50, posDur = 2 },
    Rebite        = { item = "Base.BF_Rebite",        inj = false, dur = 6,  fadiga = -0.80, recuperacao = 0.50 },
    Dipirona      = { item = "Base.BF_Dipirona",      inj = false, dur = 4,  rigidez = 0.05, dor = 0.30 },
    Metanfetamina = { item = "Base.BF_Metanfetamina", inj = false, dur = 6,  rigidez = 0.12, fadiga = -0.50, paranoia = 1, vicio = 3 },
    Tadala        = { item = "Base.BF_Tadala",        inj = false, dur = 6,  rigidez = 0.08, tristezaFim = 70 },
    Benegripe     = { item = "Base.BF_Benegripe",     inj = false, dur = 12, gripe = true },
    Lolo          = { item = "Base.BF_Lolo",          inj = false, dur = 0,  drenavel = true, lolo = true },
}

-- profissao e traco (definidos nos scripts)
pcall(function() BF.PROF = BF.PROF or CharacterProfession.get(ResourceLocation.of("bagresfarm:farmaceutico")) end)
pcall(function() BF.TRAIT = BF.TRAIT or CharacterTrait.get(ResourceLocation.of("bagresfarm:conhecimentosfarmaco")) end)

-- bonus de XP: profissao Farmacia +100%, Primeiros Socorros +75%, Laminas Curtas +100%; traco Farmacia +75%; Farmacia no maximo +125%
local dentro = false
Events.AddXP.Add(function(p, perk, amount)
    if dentro or not p or not amount or amount <= 0 or isServer() or not p:isLocalPlayer() then return end
    local prof = BF.PROF and p:getDescriptor():isCharacterProfession(BF.PROF)
    local traco = BF.TRAIT and p:hasTrait(BF.TRAIT)
    if not prof and not traco then return end
    local bonus = 0
    if perk == BF.PERK then
        bonus = (prof and 1.0 or 0) + (traco and 0.75 or 0)
        if bonus > 1.25 then bonus = 1.25 end
    elseif prof and perk == Perks.Doctor then bonus = 0.75
    elseif prof and perk == Perks.SmallBlade then bonus = 1.0 end
    if bonus <= 0 then return end
    dentro = true
    pcall(function() p:getXp():AddXP(perk, amount * bonus, false, false, false, false) end)
    dentro = false
end)
BF.POR_ITEM = {}
for id, d in pairs(BF.DROGAS) do BF.POR_ITEM[d.item] = id end

function BF.droga(item)
    if not item then return nil end
    return BF.POR_ITEM[item:getFullType()]
end

-- potencia gravada no item ao fabricar (1.0 achado no mapa, ate 1.5 com Farmacia 10)
function BF.potencia(item)
    local p = item and item:getModData().bf_pot
    return tonumber(p) or 1.0
end

function BF.aoCriar(data, character)
    local nivel = 0
    if character and BF.PERK then nivel = character:getPerkLevel(BF.PERK) end
    local pot = 1 + 0.05 * nivel
    local itens = data:getAllCreatedItems()
    for i = 0, itens:size() - 1 do
        local it = itens:get(i)
        if BF.droga(it) then
            it:getModData().bf_pot = pot
            if nivel > 0 then it:setName(it:getScriptItem():getDisplayName() .. " (F" .. nivel .. ")") end
        end
    end
end

-- tolerancia: cada dose anterior soma 2%, maximo 20%
function BF.fatorTolerancia(usos)
    return 1 + math.min(BF.TOLERANCIA_MAX, BF.TOLERANCIA_PASSO * math.max(0, (usos or 1) - 1))
end
