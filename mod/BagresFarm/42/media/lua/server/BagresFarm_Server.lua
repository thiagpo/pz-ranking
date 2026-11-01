require "BagresFarm"
require "Items/ProceduralDistributions"

local BF = BagresFarm

-- loot: lista -> { item, peso }
local LOOT = {
    MedicalStorageDrugs = { { "BF_SeringaVazia", 3 }, { "BF_Ozempic", 0.5 }, { "BF_Monjaro", 0.3 }, { "BF_Morfina", 1 }, { "BF_Adrenalina", 0.5 }, { "BF_Dipirona", 2 } },
    MedicalClinicTools  = { { "BF_SeringaVazia", 2 } },
    MedicalStorageTools = { { "BF_SeringaVazia", 2 } },
    HospitalRoomCounter = { { "BF_SeringaVazia", 1 }, { "BF_Morfina", 0.3 }, { "BF_Dipirona", 1 } },
    HospitalRoomFridge  = { { "BF_Ozempic", 0.5 }, { "BF_Monjaro", 0.3 } },
    AmbulanceDriverTools = { { "BF_Adrenalina", 1 }, { "BF_Morfina", 0.5 }, { "BF_SeringaVazia", 1 } },
    ArmyStorageMedical  = { { "BF_Morfina", 1 }, { "BF_Adrenalina", 0.5 }, { "BF_SeringaVazia", 1 } },
    ArmyBunkerMedical   = { { "BF_Morfina", 0.5 }, { "BF_Adrenalina", 0.5 } },
    FireDeptLockers     = { { "BF_Adrenalina", 0.3 } },
    BathroomCabinet     = { { "BF_SeringaVazia", 0.3 }, { "BF_Dipirona", 1 }, { "BF_Tadala", 0.5 }, { "BF_Benegripe", 1 } },
    StoreShelfMedical   = { { "BF_Dipirona", 2 }, { "BF_SeringaVazia", 0.5 }, { "BF_Benegripe", 2 } },
    SchoolLockersBad    = { { "BF_Lolo", 1 } },
    SafehouseMedical    = { { "BF_SeringaVazia", 0.5 }, { "BF_Dipirona", 1 } },
    LockerClassy        = { { "BF_Tadala", 0.5 } },
    GymLockers          = { { "BF_Deca", 1 }, { "BF_Trembolona", 1.2 }, { "BF_Rebite", 0.5 }, { "BF_SeringaVazia", 0.5 } },
    BoxingLockers       = { { "BF_Deca", 1 }, { "BF_Trembolona", 1 } },
    GymWeights          = { { "BF_Trembolona", 0.3 } },
    DrugShackDrugs      = { { "BF_SeringaVazia", 2 }, { "BF_Rebite", 2 }, { "BF_Metanfetamina", 3 }, { "BF_Morfina", 0.5 }, { "BF_Lolo", 2 } },
    MedicalClinicDrugs  = { { "BF_SeringaVazia", 2 }, { "BF_Ozempic", 0.4 }, { "BF_Monjaro", 0.2 }, { "BF_Adrenalina", 0.5 }, { "BF_Dipirona", 2 }, { "BF_Tadala", 1 }, { "BF_Benegripe", 2 } },
    DrugLabSupplies     = { { "BF_SeringaVazia", 3 }, { "BF_Metanfetamina", 2 } },
    FridgeDrugLab       = { { "BF_Deca", 0.5 }, { "BF_Trembolona", 0.5 } },
    DerelictHouseDrugs  = { { "BF_Rebite", 1 }, { "BF_Metanfetamina", 1 }, { "BF_SeringaUsada", 2 }, { "BF_Lolo", 1 } },
    BookstoreMedical    = { { "BF_Livro1", 2 }, { "BF_Livro2", 1.5 }, { "BF_Livro3", 1 }, { "BF_Livro4", 0.7 }, { "BF_Livro5", 0.5 }, { "BF_RevistaEmagrecimento", 1 }, { "BF_RevistaAnalgesicos", 1 } },
    LibraryMedical      = { { "BF_Livro1", 2 }, { "BF_Livro2", 1.5 }, { "BF_Livro3", 1 }, { "BF_Livro4", 0.7 }, { "BF_Livro5", 0.5 } },
    MedicalOfficeBooks  = { { "BF_Livro1", 2 }, { "BF_Livro2", 1.5 }, { "BF_Livro3", 1 }, { "BF_Livro4", 0.7 }, { "BF_Livro5", 0.5 }, { "BF_RevistaAnalgesicos", 1 } },
    UniversityLibraryMedical = { { "BF_Livro1", 2 }, { "BF_Livro2", 1.5 }, { "BF_Livro3", 1 }, { "BF_Livro4", 0.7 }, { "BF_Livro5", 0.5 } },
    HospitalMagazineRack = { { "BF_RevistaEmagrecimento", 2 }, { "BF_RevistaAnalgesicos", 2 } },
    DrugShackMisc       = { { "BF_RevistaEstimulantes", 2 } },
    BookstoreBooks      = { { "BF_Livro1", 0.5 }, { "BF_Livro2", 0.3 } },
    LibraryBooks        = { { "BF_Livro1", 0.5 }, { "BF_Livro2", 0.3 } },
    PharmacyCosmetics   = { { "BF_VitaminaC", 2 }, { "BF_BenegripeForte", 1 }, { "BF_Creatina", 0.5 } },
    GymSweatbands       = { { "BF_RevistaAnabolizantes", 1 }, { "BF_Whey", 1 }, { "BF_Creatina", 1 } },
    MedicalOfficeDesk   = { { "BF_KitAntidoping", 1 }, { "BF_LivroHorta", 0.3 } },
    LaboratoryLockers   = { { "BF_Vidraria", 1 }, { "BF_KitAntidoping", 1 } },
    UniversityDesk_Medical = { { "BF_LivroHorta", 1 }, { "BF_KitAntidoping", 0.5 } },
    MagazineRackMixed   = { { "BF_RevistaEmagrecimento", 0.5 }, { "BF_RevistaAnabolizantes", 0.5 }, { "BF_RevistaEstimulantes", 0.5 } },
}

local injetado = false
local function loot()
    if injetado or not ProceduralDistributions or not ProceduralDistributions.list then return end
    injetado = true
    for lista, itens in pairs(LOOT) do
        local c = ProceduralDistributions.list[lista]
        if c and c.items then
            for _, e in ipairs(itens) do
                table.insert(c.items, "Base." .. e[1]); table.insert(c.items, e[2])
            end
        end
    end
end
Events.OnPreDistributionMerge.Add(loot)

-- horta medicinal: quem leu o livro colhe 1 erva a mais e ganha XP de Farmacia
local ERVAS = { ["Base.PoppyPods"] = true, ["Base.Sage"] = true, ["Base.BlackSage"] = true, ["Base.Comfrey"] = true, ["Base.Plantain"] = true,
                ["Base.WildGarlic2"] = true, ["Base.Chamomile"] = true, ["Base.Lavender"] = true, ["Base.Tobacco"] = true }
Events.OnGameBoot.Add(function()
    if not SFarmingSystem or BF.colheitaOk then return end
    BF.colheitaOk = true
    local orig = SFarmingSystem.harvest
    SFarmingSystem.harvest = function(self, luaObject, player)
        local props = farming_vegetableconf and farming_vegetableconf.props[luaObject.typeOfSeed]
        orig(self, luaObject, player)
        if props and player and ERVAS[props.vegetableName] and player:getKnownRecipes():contains("base:poppy growing season") then
            local items = player:getInventory():AddItems(props.vegetableName, 1)
            sendAddItemsToContainer(player:getInventory(), items)
            if BF.PERK then player:getXp():AddXP(BF.PERK, 3) end
        end
    end
end)

-- uso de droga: registra no Bagres Stats quando ele estiver presente
Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= "BagresFarm" or not player or not args then return end
    if command == "aplicar" and args.alvo and BF.DROGAS[args.id] then
        local on = getOnlinePlayers()
        for i = 0, on:size() - 1 do
            local o = on:get(i)
            if o:getUsername() == args.alvo then sendServerCommand(o, "BagresFarm", "aplicado", args) end
        end
        return
    end
    if command ~= "uso" or not args.id then return end
    if not BF.DROGAS[args.id] then return end
    if BagresStats and BagresStats.inc then
        BagresStats.inc(player, "farm." .. args.id)
        BagresStats.inc(player, "farm.total")
    end
end)
