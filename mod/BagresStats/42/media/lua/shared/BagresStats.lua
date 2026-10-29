-- Bagres Stats: contadores por jogador, somados no servidor e gravados em Lua/bagres_stats/<usuario>.txt
BagresStats = BagresStats or {}
local S = BagresStats
S.VERSION = "1.1"
S.DIR = "bagres_stats/"

local data = {}
local dirty = {}
local loaded = {}

local function log(msg)
    print("[BagresStats] " .. tostring(msg))
end

local function safe(s)
    s = tostring(s or "")
    s = s:gsub("[^%w%._%-]", "_")
    if s == "" then s = "_" end
    return s
end

local function path(user)
    return S.DIR .. safe(user) .. ".txt"
end

local function load(user)
    if loaded[user] then return data[user] end
    loaded[user] = true
    local t = {}
    local ok, err = pcall(function()
        local reader = getFileReader(path(user), false)
        if not reader then return end
        local line = reader:readLine()
        while line do
            local k, v = line:match("^([^=]+)=(.*)$")
            if k and k ~= "_user" then t[k] = tonumber(v) or 0 end
            line = reader:readLine()
        end
        reader:close()
    end)
    if not ok then log("erro lendo " .. user .. ": " .. tostring(err)) end
    data[user] = t
    return t
end

local function save(user)
    local t = data[user]
    if not t then return end
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys)
    local ok, err = pcall(function()
        local writer = getFileWriter(path(user), true, false)
        writer:write("_user=" .. tostring(user) .. "\n")
        for _, k in ipairs(keys) do
            writer:write(k .. "=" .. tostring(t[k]) .. "\n")
        end
        writer:close()
    end)
    if not ok then log("erro gravando " .. user .. ": " .. tostring(err)) end
end

local function username(character)
    if not character or not instanceof(character, "IsoPlayer") then return nil end
    local ok, u = pcall(function() return character:getUsername() end)
    if ok and u and u ~= "" then return u end
    return nil
end

function S.inc(character, key, n)
    if not isServer() then return end
    local user = username(character)
    if not user then return end
    local t = load(user)
    t[key] = (t[key] or 0) + (n or 1)
    dirty[user] = true
end

function S.max(character, key, v)
    if not isServer() then return end
    local user = username(character)
    if not user then return end
    local t = load(user)
    if (t[key] or 0) < v then t[key] = v; dirty[user] = true end
end

function S.flush()
    if not isServer() then return end
    for user in pairs(dirty) do save(user) end
    dirty = {}
end

function S.typeOf(obj, getter)
    local ok, v = pcall(function() return obj[getter](obj) end)
    if ok and v ~= nil then return safe(tostring(v)) end
    return "desconhecido"
end

-- ------------------------------------------------------------------
-- Ganchos nas acoes do jogo. complete()/animEvent() rodam no servidor
-- com self.character = jogador que executou a acao.
-- ------------------------------------------------------------------
local function wrap(cls, fname, after, before)
    if type(cls) ~= "table" or type(cls[fname]) ~= "function" then return false end
    local orig = cls[fname]
    cls[fname] = function(self, ...)
        local ctx = nil
        if before and isServer() then
            local ok, c = pcall(before, self, ...)
            if ok then ctx = c end
        end
        local r = orig(self, ...)
        if isServer() then
            local ok, err = pcall(after, self, r, ctx, ...)
            if not ok then log(fname .. ": " .. tostring(err)) end
        end
        return r
    end
    return true
end

local installed = false
function S.installHooks()
    if installed then return end
    installed = true
    local n = 0
    local function W(name, fname, after, before)
        local cls = _G[name]
        if wrap(cls, fname, after, before) then n = n + 1 else log("classe nao encontrada: " .. name) end
    end

    -- animais
    W("ISKillAnimal", "complete", function(self, r)
        if r == false then return end
        local tipo = self.animal and S.typeOf(self.animal, "getAnimalType") or "desconhecido"
        S.inc(self.character, "animals.killed." .. tipo); S.inc(self.character, "animals.killed")
    end)
    W("ISKillAnimalInInventory", "complete", function(self, r)
        if r == false then return end
        local tipo = self.animal and S.typeOf(self.animal, "getAnimalType") or "desconhecido"
        S.inc(self.character, "animals.killed." .. tipo); S.inc(self.character, "animals.killed")
    end)
    W("ISButcherAnimal", "complete", function(self, r) if r ~= false then S.inc(self.character, "animals.butchered") end end)
    W("ISCutAnimalOnHook", "complete", function(self, r) if r ~= false then S.inc(self.character, "animals.hook") end end)
    W("ISMilkAnimal", "complete", function(self, r) if r ~= false then S.inc(self.character, "animals.milked") end end)
    W("ISShearAnimal", "complete", function(self, r) if r ~= false then S.inc(self.character, "animals.sheared") end end)
    W("ISHutchGrabEgg", "animEvent", function(self, r, ctx, event) if event == "update" then S.inc(self.character, "animals.eggs") end end)
    W("ISCheckTrapAction", "complete", function(self, r, ctx)
        if ctx and ctx ~= "" then S.inc(self.character, "traps." .. ctx); S.inc(self.character, "traps") end
    end, function(self)
        local trap = STrapSystem and STrapSystem.instance and STrapSystem.instance:getLuaObjectAt(self.trap.x, self.trap.y, self.trap.z)
        return trap and trap.animal and trap.animal.type and safe(trap.animal.type) or nil
    end)

    -- pesca
    W("ISPickupFishAction", "PickupFishUpdate", function(self, r, ctx)
        if ctx == false and self.fishInInv and not self._bagres then
            self._bagres = true
            local tipo = self.item and S.typeOf(self.item, "getFullType") or "desconhecido"
            if tipo:find("Trash") then S.inc(self.character, "fish.trash") else
                S.inc(self.character, "fish." .. tipo); S.inc(self.character, "fish")
                local ok, size = pcall(function() return self.item:getModData().fishing_FishSize end)
                if ok and type(size) == "number" then S.max(self.character, "fish.maxsize", size) end
            end
        end
    end, function(self) return self.fishInInv == true end)
    W("ISCheckFishingNetAction", "complete", function(self, r) if r ~= false then S.inc(self.character, "nets.checked") end end)

    -- agricultura e coleta
    W("ISHarvestPlantAction", "complete", function(self, r)
        if r == false then return end
        local tipo = self.plant and self.plant.typeOfSeed and safe(self.plant.typeOfSeed) or "desconhecido"
        S.inc(self.character, "farming.harvest." .. tipo); S.inc(self.character, "farming.harvest")
    end)
    W("ISSeedActionNew", "complete", function(self, r)
        if r == false then return end
        S.inc(self.character, "farming.sow." .. safe(self.typeOfSeed or "desconhecido")); S.inc(self.character, "farming.sow")
    end)
    W("ISWaterPlantAction", "complete", function(self, r) if r ~= false then S.inc(self.character, "farming.water") end end)
    W("ISForageAction", "complete", function(self, r) if r ~= false then S.inc(self.character, "forage") end end)

    -- arvores, livros, fabricacao
    W("ISChopTreeAction", "animEvent", function(self, r, ctx, event)
        if event == "ChopTree" and self.tree and not self._bagres then
            local ok, hp = pcall(function() return self.tree:getHealth() end)
            if ok and hp and hp <= 0 then self._bagres = true; S.inc(self.character, "trees.cut") end
        end
    end)
    W("ISReadABook", "complete", function(self, r)
        if r == false or self.forceStopped then return end
        local tipo = self.item and S.typeOf(self.item, "getFullType") or "desconhecido"
        S.inc(self.character, "books." .. tipo); S.inc(self.character, "books")
        local ok, skill = pcall(function() return self.item:getSkillTrained() end)
        if ok and skill and skill ~= "" then S.inc(self.character, "books.skill") end
    end)
    W("ISHandcraftAction", "performRecipe", function(self, r)
        local nome = "desconhecido"
        pcall(function() nome = safe(self.craftRecipe:getName()) end)
        S.inc(self.character, "craft." .. nome); S.inc(self.character, "craft")
    end)
    W("ISCraftAction", "complete", function(self, r)
        if r == false then return end
        local nome = "desconhecido"
        pcall(function() nome = safe(self.recipe:getName()) end)
        S.inc(self.character, "craft." .. nome); S.inc(self.character, "craft")
    end)
    W("ISBuryCorpse", "complete", function(self, r) if r ~= false then S.inc(self.character, "corpses.buried") end end)
    W("ISLightFromKindle", "complete", function(self, r) if r ~= false then S.inc(self.character, "fire.lit") end end)
    W("ISLightFromLiterature", "complete", function(self, r) if r ~= false then S.inc(self.character, "fire.lit") end end)
    W("ISLightFromPetrol", "complete", function(self, r) if r ~= false then S.inc(self.character, "fire.lit") end end)

    -- veiculos e reparos
    W("ISInstallVehiclePart", "complete", function(self, r) if r ~= false then S.inc(self.character, "vehicle.install") end end)
    W("ISUninstallVehiclePart", "complete", function(self, r) if r ~= false then S.inc(self.character, "vehicle.uninstall") end end)
    W("ISRepairEngine", "complete", function(self, r) if r ~= false then S.inc(self.character, "vehicle.engine") end end)
    W("ISFixVehiclePartAction", "complete", function(self, r) if r ~= false then S.inc(self.character, "vehicle.fix") end end)
    W("ISFixAction", "complete", function(self, r) if r ~= false then S.inc(self.character, "repair.items") end end)
    W("ISFixGenerator", "complete", function(self, r) if r ~= false then S.inc(self.character, "repair.generator") end end)

    log("ganchos instalados: " .. n)
end
