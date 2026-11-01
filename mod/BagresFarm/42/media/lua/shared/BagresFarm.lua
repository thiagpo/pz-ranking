-- Farms do Bagres: nucleo compartilhado (skill Farmacia, tabela de drogas, potencia, validade, laboratorio, bonus de XP)
BagresFarm = BagresFarm or {}
local BF = BagresFarm
BF.VERSION = "1.1"
BF.TOLERANCIA_MAX = 0.20
BF.TOLERANCIA_PASSO = 0.02
BF.OVERDOSE_H = 2
BF.VALIDADE_H = 336
BF.LAB_SPRITE = "location_community_medical_01_136"
BF.HIST_H = 48
BF.SUBIDA_H = 10 / 60

-- opcoes de sandbox (menu do servidor), com padrao se o mod for novo no save
function BF.sb(k, padrao)
    local ok, v = pcall(function() return SandboxVars.BagresFarm[k] end)
    if ok and v ~= nil then return v end
    return padrao
end
function BF.validadeH() return BF.sb("ValidadeDias", 14) * 24 end

-- multiplicadores reais de um efeito ativo: sobem nos primeiros 10 min (come-up) e respeitam o sandbox
function BF.mult(e, t)
    local r = 1
    if e.ini and t then r = math.min(1, math.max(0.15, (t - e.ini) / BF.SUBIDA_H)) end
    return e.m * r * BF.sb("Efeito", 1), e.d * r * BF.sb("Colateral", 1)
end

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
-- fome/fadiga: negativo = buff (x potencia), positivo = debuff (x tolerancia)
-- vicio = { limiar = doses por nivel de vicio, horas = sem dose ate abstinencia, limpar = horas limpo por nivel }
BF.DROGAS = {
    Ozempic        = { item = "Base.BF_Ozempic",        inj = true, careca = true,  dur = 24, fome = -0.40, pesoDia = 0.60, fadiga = 0.35 },
    Monjaro        = { item = "Base.BF_Monjaro",        inj = true, careca = true,  dur = 24, fome = -0.60, pesoDia = 1.20, fadiga = 0.50 },
    Trembolona     = { item = "Base.BF_Trembolona",     inj = true, careca = true,  dur = 36, forca = 0.10, fome = 0.60 },
    Deca           = { item = "Base.BF_Deca",           inj = true, careca = true,  dur = 48, forca = 0.15, fome = 0.80 },
    Morfina        = { item = "Base.BF_Morfina",        inj = true,  dur = 8,  dor = 0.80, rigidez = 0.10, paranoia = 3, depressao = 6, vicio = { limiar = 4, horas = 24, limpar = 72 } },
    Adrenalina     = { item = "Base.BF_Adrenalina",     inj = true,  dur = 1,  folego = true, audicao = true, adrenalina = true, panico = -100, fadigaFim = 0.80, sangramento = 0.60, posDur = 2 },
    Rebite         = { item = "Base.BF_Rebite",         inj = false, drenavel = true, dur = 6,  fadiga = -0.90, recuperacao = 0.60, visao = true, vicio = { limiar = 5, horas = 36, limpar = 48 } },
    Dipirona       = { item = "Base.BF_Dipirona",       inj = false, drenavel = true, dur = 4,  rigidez = 0.05, dor = 0.30 },
    Metanfetamina  = { item = "Base.BF_Metanfetamina",  inj = false, drenavel = true, dur = 6,  rigidez = 0.12, fadiga = -0.70, paranoia = 1, vicio = { limiar = 3, horas = 24, limpar = 96 } },
    Tadala         = { item = "Base.BF_Tadala",         inj = false, drenavel = true, dur = 6,  rigidez = 0.08, tristezaFim = 90 },
    Benegripe      = { item = "Base.BF_Benegripe",      inj = false, drenavel = true, dur = 12, gripe = true, cura = 8 },
    BenegripeForte = { item = "Base.BF_BenegripeForte", inj = false, drenavel = true, dur = 36, gripe = true, cura = 4 },
    VitaminaC      = { item = "Base.BF_VitaminaC",      inj = false, drenavel = true, dur = 6,  gripe = true, fadigaJa = -0.10 },
    Creatina       = { item = "Base.BF_Creatina",       inj = false, drenavel = true, dur = 6,  xpForca = 0.50, fomeJa = -0.05 },
    Whey           = { item = "Base.BF_Whey",           inj = false, dur = 6,  xpFitness = 0.50, fomeJa = -0.15, bebida = true },
    Lolo           = { item = "Base.BF_Lolo",           inj = false, dur = 0,  drenavel = true, lolo = true },
}
BF.POR_ITEM = {}
for id, d in pairs(BF.DROGAS) do BF.POR_ITEM[d.item] = id end

function BF.droga(item)
    if not item then return nil end
    return BF.POR_ITEM[item:getFullType()]
end

-- potencia base gravada ao fabricar (1.0 achado no mapa, ate 1.5 com Farmacia 10)
function BF.potenciaBase(item)
    return tonumber(item and item:getModData().bf_pot) or 1.0
end

-- horas fora da geladeira (so injetaveis perdem potencia)
function BF.horasFora(item)
    return tonumber(item and item:getModData().bf_fora) or 0
end

function BF.fatorValidade(item)
    local id = BF.droga(item)
    if not id or not BF.DROGAS[id].inj then return 1 end
    return math.max(0.4, 1 - BF.horasFora(item) / BF.validadeH())
end

function BF.potencia(item)
    return BF.potenciaBase(item) * BF.fatorValidade(item)
end

function BF.suja(item)
    return item and item:getModData().bf_suja == true
end

function BF.nomeItem(item)
    local base = item:getScriptItem():getDisplayName()
    local md = item:getModData()
    local extra = {}
    if md.bf_nivel and md.bf_nivel > 0 then table.insert(extra, "F" .. md.bf_nivel) end
    table.insert(extra, math.floor(BF.potencia(item) * 100 + 0.5) .. "%")
    if md.bf_suja then table.insert(extra, getText("IGUI_BF_Suja")) end
    if md.bf_fora and md.bf_fora >= BF.validadeH() then table.insert(extra, getText("IGUI_BF_Vencido")) end
    return base .. " (" .. table.concat(extra, ", ") .. ")"
end

-- item achado no mapa ganha potencia aleatoria (80% a 120%) na primeira vez que o mod o ve
function BF.garantirPotencia(item)
    if not item or not BF.droga(item) then return end
    local md = item:getModData()
    if md.bf_pot == nil then
        md.bf_pot = 0.8 + ZombRandFloat(0, 0.4)
        md.bf_fora = md.bf_fora or 0
        item:setName(BF.nomeItem(item))
    end
end

-- texto com os numeros reais da dose (m = multiplicador do beneficio, dm = do colateral)
function BF.descricaoEfeito(id, m, dm)
    local d = BF.DROGAS[id]; if not d then return "" end
    local bons, maus = {}, {}
    local function pct(v) return math.floor(math.abs(v) * 100 + 0.5) end
    if d.fome and d.fome < 0 then table.insert(bons, getText("IGUI_BF_L_fome") .. " -" .. pct(d.fome * m) .. "%") end
    if d.fome and d.fome > 0 then table.insert(maus, getText("IGUI_BF_L_fome") .. " +" .. pct(d.fome * dm) .. "%") end
    if d.pesoDia then table.insert(bons, "-" .. string.format("%.2f", d.pesoDia * m) .. " kg/" .. getText("IGUI_BF_L_dia")) end
    if d.fadiga and d.fadiga < 0 then table.insert(bons, getText("IGUI_BF_L_cansaco") .. " -" .. pct(d.fadiga * m) .. "%") end
    if d.fadiga and d.fadiga > 0 then table.insert(maus, getText("IGUI_BF_L_cansaco") .. " +" .. pct(d.fadiga * dm) .. "%") end
    if d.forca then table.insert(bons, getText("IGUI_BF_L_forca") .. " +" .. pct(d.forca * m) .. "%") end
    if d.dor then table.insert(bons, getText("IGUI_BF_L_dor") .. " -" .. pct(d.dor * m) .. "%") end
    if d.rigidez then table.insert(bons, getText("IGUI_BF_L_rigidez") .. " -" .. pct(d.rigidez * m) .. "%/min") end
    if d.xpForca then table.insert(bons, "+" .. pct(d.xpForca * m) .. "% XP " .. getText("IGUI_BF_L_xpforca")) end
    if d.xpFitness then table.insert(bons, "+" .. pct(d.xpFitness * m) .. "% XP " .. getText("IGUI_BF_L_xpfitness")) end
    if d.folego then table.insert(bons, getText("IGUI_BF_L_folego")) end
    if d.audicao then table.insert(bons, getText("IGUI_BF_L_audicao")) end
    if d.visao then table.insert(bons, getText("IGUI_BF_L_visao")) end
    if d.cura then table.insert(bons, getText("IGUI_BF_L_cura", string.format("%.1f", d.cura / m))) end
    if d.gripe and not d.cura then table.insert(bons, getText("IGUI_BF_L_gripe")) end
    if d.panico and d.panico < 0 then table.insert(bons, getText("IGUI_BF_L_panico")) end
    if d.adrenalina then table.insert(bons, getText("IGUI_BF_L_adrenalina")) end
    if d.fadigaFim then table.insert(maus, getText("IGUI_BF_L_depois") .. " " .. getText("IGUI_BF_L_cansaco") .. " +" .. pct(d.fadigaFim * dm) .. "%") end
    if d.sangramento then table.insert(maus, getText("IGUI_BF_L_sangra") .. " +" .. pct(d.sangramento * dm) .. "%") end
    if d.recuperacao then table.insert(maus, getText("IGUI_BF_L_depois") .. " " .. getText("IGUI_BF_L_sono") .. " -" .. pct(d.recuperacao * dm) .. "%") end
    if d.tristezaFim then table.insert(maus, getText("IGUI_BF_L_depois") .. " " .. getText("IGUI_BF_L_tristeza") .. " " .. math.floor(math.min(100, d.tristezaFim * dm) + 0.5)) end
    if d.paranoia then table.insert(maus, getText("IGUI_BF_L_paranoia")) end
    if d.vicio then table.insert(maus, getText("IGUI_BF_L_vicio")) end
    if d.lolo then table.insert(bons, getText("IGUI_BF_L_fumo")); table.insert(maus, getText("IGUI_BF_L_enjoo") .. " +" .. math.floor(15 * dm + 0.5) .. ", " .. getText("IGUI_BF_L_bebado") .. " +" .. math.floor(25 * dm + 0.5)) end
    local txt = table.concat(bons, ", ")
    if #maus > 0 then txt = txt .. " | " .. table.concat(maus, ", ") end
    return txt
end

function BF.aoCriar(data, character)
    local nivel = 0
    if character and BF.PERK then nivel = character:getPerkLevel(BF.PERK) end
    local suja = false
    local gastos = data:getAllConsumedItems()
    for i = 0, gastos:size() - 1 do
        if gastos:get(i):getFullType() == "Base.BF_SeringaUsada" then suja = true end
    end
    local itens = data:getAllCreatedItems()
    for i = 0, itens:size() - 1 do
        local it = itens:get(i)
        if BF.droga(it) then
            local md = it:getModData()
            md.bf_pot = 1 + 0.05 * nivel
            md.bf_nivel = nivel
            md.bf_fora = 0
            if suja then md.bf_suja = true end
            it:setName(BF.nomeItem(it))
        end
    end
end

-- receitas avancadas so perto da bancada de laboratorio (3 quadros)
function BF.pertoDoLab(item, character)
    if not character then return true end
    local sq = character:getSquare()
    if not sq then return false end
    local cell = character:getCell()
    for dx = -3, 3 do
        for dy = -3, 3 do
            local s = cell:getGridSquare(sq:getX() + dx, sq:getY() + dy, sq:getZ())
            if s then
                local objs = s:getObjects()
                for i = 0, objs:size() - 1 do
                    local spr = objs:get(i):getSprite()
                    if spr and spr:getName() == BF.LAB_SPRITE then return true end
                end
            end
        end
    end
    return false
end

-- tolerancia: cada dose anterior tira 2% do efeito e soma 2% ao colateral, maximo 20%
function BF.tolerancia(usos)
    return math.min(BF.TOLERANCIA_MAX, BF.TOLERANCIA_PASSO * math.max(0, (usos or 1) - 1))
end
function BF.fatorTolerancia(usos) return 1 + BF.tolerancia(usos) end

-- profissao e traco (registrados em media/registries.lua)
pcall(function() BF.PROF = BF.PROF or CharacterProfession.get(ResourceLocation.of("bagresfarm:farmaceutico")) end)
pcall(function() BF.TRAIT = BF.TRAIT or CharacterTrait.get(ResourceLocation.of("bagresfarm:conhecimentosfarmaco")) end)
pcall(function() BF.TRAIT_DESNUTRIDO = BF.TRAIT_DESNUTRIDO or CharacterTrait.get(ResourceLocation.of("bagresfarm:desnutrido")) end)
pcall(function() BF.TRAIT_CORACAO = BF.TRAIT_CORACAO or CharacterTrait.get(ResourceLocation.of("bagresfarm:coracaocansado")) end)

-- bonus de XP: Farmacia vem dos niveis iniciais do jogo (3 niveis = +125%, traco 1 nivel = +75%);
-- a profissao soma +75% em Primeiros Socorros e +100% em Laminas Curtas; creatina/whey +50% em Forca / Aptidao enquanto ativos
local dentro = false
Events.AddXP.Add(function(p, perk, amount)
    if dentro or not p or not amount or amount <= 0 or isServer() or not p:isLocalPlayer() then return end
    local bonus = 0
    local prof = BF.PROF and p:getDescriptor():isCharacterProfession(BF.PROF)
    if prof and perk == Perks.Doctor then bonus = 0.75
    elseif prof and perk == Perks.SmallBlade then bonus = 1.0 end
    local md = p:getModData().BF
    if md and md.ef then
        for id, e in pairs(md.ef) do
            local d = BF.DROGAS[id]
            if d then
                if d.xpForca and perk == Perks.Strength then bonus = bonus + d.xpForca * e.m end
                if d.xpFitness and perk == Perks.Fitness then bonus = bonus + d.xpFitness * e.m end
            end
        end
    end
    if bonus <= 0 then return end
    dentro = true
    pcall(function() p:getXp():AddXP(perk, amount * bonus, false, false, false, false) end)
    dentro = false
end)
