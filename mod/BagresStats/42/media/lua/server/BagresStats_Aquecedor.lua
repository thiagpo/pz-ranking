-- Bagres Stats: aquecedor de veiculo sem temperatura de motor gerava erro a cada tick (42.22)
require "Vehicles/Vehicles"

local original = Vehicles.Update.Heater
Vehicles.Update.Heater = function(vehicle, part, elapsedMinutes)
    local engine = vehicle:getPartById("Engine")
    if engine then
        local d = engine:getModData()
        if not tonumber(d.temperature) then d.temperature = 0 end
    end
    return original(vehicle, part, elapsedMinutes)
end
