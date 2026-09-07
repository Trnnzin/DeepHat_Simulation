--!strict
-- LineOfSightSimulator.lua
-- Módulo 2: Simulação de Visada Óptica e Oclusão Geométrica

local Workspace = game:GetService("Workspace")

local LineOfSightSimulator = {}
LineOfSightSimulator.__index = LineOfSightSimulator

export type RayTelemetry = {
    isObstructed: boolean,
    hitInstance: Instance?,
    distance: number
}

function LineOfSightSimulator.new(filterInstances: {Instance}?)
    local self = setmetatable({}, LineOfSightSimulator)
    
    -- Reutilização de RaycastParams para otimização de performance (zero overhead de alocação)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterMode.Exclude
    params.FilterDescendantsInstances = filterInstances or {}
    params.IgnoreWater = true
    
    self.RayParams = params
    return self
end

function LineOfSightSimulator:SetFilterInstances(instances: {Instance})
    self.RayParams.FilterDescendantsInstances = instances
end

-- Avalia oclusão por traçado de raios entre dois pontos 3D
function LineOfSightSimulator:EvaluateLineOfSight(origin: Vector3, target: Vector3): RayTelemetry
    local displacement = target - origin
    local distance = displacement.Magnitude
    
    if distance < 0.001 then
        return { isObstructed = false, hitInstance = nil, distance = 0 }
    end

    local result = Workspace:Raycast(origin, displacement, self.RayParams)
    
    local isObstructed = false
    local hitPart = nil
    
    if result and result.Instance then
        local hitDist = (result.Position - origin).Magnitude
        -- Se o ponto atingido pelo raio estiver a uma distância inferior ao alvo, há barreira no caminho
        if hitDist < (distance - 0.1) then
            isObstructed = true
            hitPart = result.Instance
        end
    end

    return {
        isObstructed = isObstructed,
        hitInstance = hitPart,
        distance = distance
    }
end

return LineOfSightSimulator
