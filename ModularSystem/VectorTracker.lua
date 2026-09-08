--!strict
-- VectorTracker.lua
-- Módulo 2: Rastreamento Vetorial Otimizado, Proteção Epsilon e Interpolação Lerp
-- Implementa: Cálculo de Direção Vetorial (.Unit Seguro), Dot Product Angular, Easing Hermite e Lead Kinematics

local Workspace = game:GetService("Workspace")

local VectorTracker = {}
VectorTracker.__index = VectorTracker

-- Limiar numérico estrito para prevenir divisão por zero e vetores NaN
local EPSILON = 1e-4

export type TrackingResult = {
    Direction: Vector3,
    Distance: number,
    AngularErrorDeg: number,
    TargetCFrame: CFrame,
    SmoothedCFrame: CFrame,
    LeadPosition: Vector3,
    IsObstructed: boolean,
    IsWithinBounds: boolean
}

function VectorTracker.new(filterInstances: { Instance }?)
    local self = setmetatable({}, VectorTracker)
    self.NoiseSeed = math.random(1000, 9999)
    self.VelocityCache = setmetatable({}, { __mode = "k" }) :: { [Model]: { pos: Vector3, time: number, vel: Vector3 } }

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

-- Verificação geométrica de oclusão de linha de visão
function VectorTracker:CheckObstruction(originPos: Vector3, targetPos: Vector3): boolean
    local displacement = (targetPos - originPos)
    local dist = displacement.Magnitude
    if dist < EPSILON then
        return false
    end
    local result = Workspace:Raycast(originPos, (displacement / dist) * dist, self.RayParams)
    return (result ~= nil)
end

-- Cálculo de velocidade instantânea por derivação temporal (deltaP / deltaT)
function VectorTracker:EstimateVelocity(model: Model, currentPos: Vector3): Vector3
    local now = os.clock()
    local cached = self.VelocityCache[model]
    local vel = Vector3.zero

    if cached then
        local dt = (now - cached.time)
        if dt > 0.001 and dt < 0.3 then
            vel = (currentPos - cached.pos) / dt
        else
            vel = cached.vel
        end
    end

    self.VelocityCache[model] = { pos = currentPos, time = now, vel = vel }
    return vel
end

-- Predição Balística de Primeira Ordem (Lead Vector)
function VectorTracker:ComputeLeadPosition(targetPos: Vector3, targetVel: Vector3, originPos: Vector3, projectileSpeed: number, enabled: boolean): Vector3
    if not enabled or projectileSpeed <= 0 then
        return targetPos
    end
    local distance = (targetPos - originPos).Magnitude
    local timeToHit = distance / projectileSpeed
    return targetPos + (targetVel * timeToHit)
end

-- Cálculo Vetorial Robusto com Guarda Epsilon e Interpolação Lerp
function VectorTracker:CalculateTrajectory(
    currentCFrame: CFrame,
    rawTargetPos: Vector3,
    targetModel: Model,
    dt: number,
    settings: {
        FOV: number,
        Smoothing: number,
        MoveSpeed: number,
        Precision: number,
        Intensity: number,
        VectorRadius: number,
        AccelerationCurve: number,
        EnableLead: boolean,
        ProjectileSpeed: number
    }
): TrackingResult
    local originPos = currentCFrame.Position
    local vel = self:EstimateVelocity(targetModel, rawTargetPos)
    local leadPos = self:ComputeLeadPosition(rawTargetPos, vel, originPos, settings.ProjectileSpeed, settings.EnableLead)

    local toTarget = (leadPos - originPos)
    local dist = toTarget.Magnitude

    -- GUARDA EPSILON: Previne divisão por zero e NaN em distâncias infinitesimais
    if dist < EPSILON then
        return {
            Direction = Vector3.zero,
            Distance = 0,
            AngularErrorDeg = 0,
            TargetCFrame = currentCFrame,
            SmoothedCFrame = currentCFrame,
            LeadPosition = leadPos,
            IsObstructed = false,
            IsWithinBounds = false
        }
    end

    -- Normalização segura de vetor unitário
    local dirToTarget = toTarget / dist

    -- Produto Escalar (Dot Product) para aferição precisa do erro angular
    local forwardVector = currentCFrame.LookVector
    local dot = math.clamp(forwardVector:Dot(dirToTarget), -1.0, 1.0)
    local angularErrorDeg = math.deg(math.acos(dot))

    local isObstructed = self:CheckObstruction(originPos, leadPos)
    local isWithinBounds = (dist <= settings.VectorRadius) and (angularErrorDeg <= settings.FOV)

    local targetRotation = CFrame.lookAt(originPos, leadPos)

    if not isWithinBounds then
        return {
            Direction = dirToTarget,
            Distance = dist,
            AngularErrorDeg = angularErrorDeg,
            TargetCFrame = targetRotation,
            SmoothedCFrame = currentCFrame,
            LeadPosition = leadPos,
            IsObstructed = isObstructed,
            IsWithinBounds = false
        }
    end

    -- Curva Hermite Smoothstep para aceleração gradual
    local normalizedErr = math.clamp(angularErrorDeg / math.max(settings.FOV, 1.0), 0.0, 1.0)
    local smoothFactor = normalizedErr * normalizedErr * (3.0 - 2.0 * normalizedErr)
    smoothFactor = math.pow(smoothFactor, settings.AccelerationCurve)

    -- Interpolação Frame-rate Independent via Decaimento Exponencial
    local safeDt = math.clamp(dt, 0.001, 0.1)
    local speedMult = math.clamp(settings.MoveSpeed / 16.0, 0.25, 3.0)
    local k = (settings.Smoothing * 28.0 * speedMult) * (0.35 + 0.65 * smoothFactor)
    local dynamicAlpha = math.clamp(1.0 - math.exp(-k * safeDt), 0.001, 1.0)

    -- Interpolação Linear de Matriz de Rotação (CFrame:Lerp)
    local smoothedRotation = currentCFrame:Lerp(targetRotation, dynamicAlpha)

    -- Micro-variação de trajetória orgânica
    local precision = math.clamp(settings.Precision / 100.0, 0.5, 1.0)
    local intensity = math.clamp(settings.Intensity / 100.0, 0.0, 2.0)
    local jitterAmp = (1.0 - precision) * intensity * 0.4 * math.clamp(angularErrorDeg / 10.0, 0.0, 1.0)

    local finalCFrame = smoothedRotation
    if jitterAmp > 0.0001 then
        local now = os.clock()
        local noiseFreq = 3.5 * intensity
        local pitchJitter = math.rad(math.noise(now * noiseFreq, self.NoiseSeed, 0.5) * jitterAmp)
        local yawJitter = math.rad(math.noise(now * noiseFreq, self.NoiseSeed + 100, 0.5) * jitterAmp)
        finalCFrame = smoothedRotation * CFrame.Angles(pitchJitter, yawJitter, 0)
    end

    return {
        Direction = dirToTarget,
        Distance = dist,
        AngularErrorDeg = angularErrorDeg,
        TargetCFrame = targetRotation,
        SmoothedCFrame = finalCFrame,
        LeadPosition = leadPos,
        IsObstructed = isObstructed,
        IsWithinBounds = true
    }
end

return VectorTracker
