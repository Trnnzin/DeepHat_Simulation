--!strict
-- VectorTracker.lua
-- Pilar 2: Motor de Rotação e Interpolação Vetorial (Smoothness & Vector Math)
-- CFrame.lookAt com Lerp contínuo dependente de DeltaTime e Prevenção de NaN via EPSILON

local Workspace = game:GetService("Workspace")

local VectorTracker = {}
VectorTracker.__index = VectorTracker

-- Constante de tolerância estrita contra divisão por zero e NaNs
local EPSILON = 1e-4

export type TrackingTelemetry = {
    Direction: Vector3,
    Distance: number,
    AngularErrorDeg: number,
    TargetCFrame: CFrame,
    SmoothedCFrame: CFrame,
    IsObstructed: boolean
}

function VectorTracker.new(filterInstances: { Instance }?)
    local self = setmetatable({}, VectorTracker)
    self.CurrentCFrame = CFrame.identity
    self.PreviousLookVector = Vector3.zAxis
    self.PreviousAngularVelocity = 0
    self.VelocityCache = setmetatable({}, { __mode = "k" }) :: { [Instance]: { pos: Vector3, time: number, vel: Vector3 } }

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = filterInstances or {}
    rayParams.IgnoreWater = true
    self.RayParams = rayParams

    return self
end

function VectorTracker:SetFilterInstances(instances: { Instance })
    self.RayParams.FilterDescendantsInstances = instances
end

function VectorTracker:CheckObstruction(originPos: Vector3, targetPos: Vector3): boolean
    local displacement = (targetPos - originPos)
    local dist = displacement.Magnitude
    if dist < EPSILON then return false end
    local dir = displacement / dist
    local result = Workspace:Raycast(originPos, dir * dist, self.RayParams)
    return (result ~= nil)
end

function VectorTracker:EstimateVelocity(inst: Instance, currentPos: Vector3): Vector3
    local now = os.clock()
    local cached = self.VelocityCache[inst]
    local vel = Vector3.zero

    if cached then
        local dt = (now - cached.time)
        if dt > 0.001 and dt < 0.3 then
            vel = (currentPos - cached.pos) / dt
        else
            vel = cached.vel
        end
    end

    self.VelocityCache[inst] = { pos = currentPos, time = now, vel = vel }
    return vel
end

function VectorTracker:ComputeLead(targetPos: Vector3, targetVel: Vector3, eyePos: Vector3, projSpeed: number, enabled: boolean): Vector3
    if not enabled or projSpeed <= 0 then
        return targetPos
    end
    local dist = (targetPos - eyePos).Magnitude
    local timeToHit = dist / projSpeed
    return targetPos + (targetVel * timeToHit)
end

-- Cálculo de Rotação Suavizada (Lerp com DeltaTime e Guarda Epsilon)
function VectorTracker:ComputeSmoothRotation(
    currentCFrame: CFrame,
    targetPosition: Vector3,
    dt: number,
    smoothingFactor: number,
    angularVelocityLimit: number?
): (CFrame, number)
    local originPos = currentCFrame.Position
    local displacement = (targetPosition - originPos)
    local distance = displacement.Magnitude

    -- PREVENÇÃO DE NaN: Aborta caso a distância seja menor que o limiar EPSILON
    if distance < EPSILON then
        return currentCFrame, 0
    end

    -- Normalização segura no R3: u = D / ||D||
    local unitDirection = displacement / distance
    local forward = currentCFrame.LookVector
    local dot = math.clamp(forward:Dot(unitDirection), -1.0, 1.0)
    local angularErrorDeg = math.deg(math.acos(dot))

    -- Matriz de Orientação Alvo via CFrame.lookAt
    local targetRotation = CFrame.lookAt(originPos, targetPosition, Vector3.yAxis)

    -- Interpolação Linear de Matriz de Rotação (Lerp) baseada em Alpha e DeltaTime
    -- alpha_eff = 1 - e^(-k * dt) -> Taxa de rotação angular independente de FPS
    local safeDt = math.clamp(dt or 0.0166, 0.0001, 0.1)
    local baseAlpha = math.clamp(smoothingFactor or 0.15, 0.01, 1.0)
    local k = (baseAlpha * 24.0)
    local dynamicAlpha = math.clamp(1.0 - math.exp(-k * safeDt), 0.001, 1.0)

    local smoothedCFrame = currentCFrame:Lerp(targetRotation, dynamicAlpha)
    self.CurrentCFrame = smoothedCFrame

    return smoothedCFrame, angularErrorDeg
end

return VectorTracker
