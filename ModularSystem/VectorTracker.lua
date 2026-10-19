--!strict
-- VectorTracker.lua
-- Pilar 2: Motor de Rotação, Interpolação Vetorial e Cinemática Avançada
-- CFrame.lookAt com Lerp contínuo independente de framerate (Exponential Decay),
-- Proteção Epsilon (1e-4), Jitter Orgânico Perlin Noise e Cálculo Instantâneo de Velocidade Angular

local Workspace = game:GetService("Workspace")

local VectorTracker = {}
VectorTracker.__index = VectorTracker

-- Constante de tolerância estrita contra divisão por zero e NaNs
local EPSILON = 1e-4

export type TrackingTelemetry = {
    Direction: Vector3,
    Distance: number,
    AngularErrorDeg: number,
    AngularVelocityDeg: number,
    TargetCFrame: CFrame,
    SmoothedCFrame: CFrame,
    IsObstructed: boolean,
    Mode: string
}

function VectorTracker.new(filterInstances: { Instance }?)
    local self = setmetatable({}, VectorTracker)
    self.CurrentCFrame = CFrame.identity
    self.PreviousLookVector = Vector3.zAxis
    self.PreviousTime = os.clock()
    self.PreviousAngularVelocity = 0
    self.NoiseSeed = math.random(1000, 9999)
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

-- Cálculo de Rotação Suavizada (Lerp com DeltaTime, Guarda Epsilon, Aceleração Hermite e Jitter)
function VectorTracker:ComputeSmoothRotation(
    currentCFrame: CFrame,
    targetPosition: Vector3,
    dt: number,
    smoothingFactor: number,
    accelExponent: number?,
    simulateJitter: boolean?,
    intensity: number?
): (CFrame, number, number)
    local originPos = currentCFrame.Position
    local displacement = (targetPosition - originPos)
    local distance = displacement.Magnitude

    -- PREVENÇÃO DE NaN: Aborta caso a distância seja menor que o limiar EPSILON
    if distance < EPSILON then
        return currentCFrame, 0, 0
    end

    local safeDt = math.clamp(dt or 0.0166, 0.0001, 0.1)

    -- Normalização segura no R3: u = D / ||D||
    local unitDirection = displacement / distance
    local forward = currentCFrame.LookVector
    local dot = math.clamp(forward:Dot(unitDirection), -1.0, 1.0)
    local angularErrorDeg = math.deg(math.acos(dot))

    -- Matriz de Orientação Alvo via CFrame.lookAt
    local targetRotation = CFrame.lookAt(originPos, targetPosition, Vector3.yAxis)

    -- Curva de aceleração Hermite Smoothstep com expoente configurável
    local normErr = math.clamp(angularErrorDeg / 70.0, 0.0, 1.0)
    local hermiteFactor = normErr * normErr * (3.0 - 2.0 * normErr)
    local exponent = accelExponent or 1.25
    hermiteFactor = math.pow(hermiteFactor, exponent)

    -- Interpolação Linear de Matriz de Rotação (Exponential Decay independente de taxa de quadros)
    local baseAlpha = math.clamp(smoothingFactor or 0.15, 0.005, 1.0)
    local k = (baseAlpha * 26.0) * (0.35 + 0.65 * hermiteFactor)
    local dynamicAlpha = math.clamp(1.0 - math.exp(-k * safeDt), 0.001, 1.0)

    local smoothedCFrame = currentCFrame:Lerp(targetRotation, dynamicAlpha)

    -- Injeção de Jitter Perlin Noise caso habilitado
    if simulateJitter and intensity and intensity > 0 then
        local now = os.clock()
        local jitterFactor = (intensity / 100.0) * math.clamp(angularErrorDeg / 15.0, 0.0, 1.0) * 0.3
        if jitterFactor > 0.01 then
            local noiseX = math.noise(now * 4.0, self.NoiseSeed, 0.5) * jitterFactor
            local noiseY = math.noise(now * 4.0, self.NoiseSeed + 50, 0.5) * jitterFactor
            smoothedCFrame = smoothedCFrame * CFrame.Angles(math.rad(noiseX), math.rad(noiseY), 0)
        end
    end

    -- Cálculo da velocidade angular instantânea em graus/segundo
    local newLook = smoothedCFrame.LookVector
    local deltaDot = math.clamp(self.PreviousLookVector:Dot(newLook), -1.0, 1.0)
    local deltaAngleDeg = math.deg(math.acos(deltaDot))
    local angularVelocity = deltaAngleDeg / safeDt

    self.PreviousLookVector = newLook
    self.CurrentCFrame = smoothedCFrame

    return smoothedCFrame, angularErrorDeg, angularVelocity
end

-- Modo Snap Instantâneo (1 frame) para testes de Anomaly Detection
function VectorTracker:ComputeSnapRotation(
    currentCFrame: CFrame,
    targetPosition: Vector3,
    dt: number
): (CFrame, number, number)
    local originPos = currentCFrame.Position
    local displacement = (targetPosition - originPos)
    local distance = displacement.Magnitude

    if distance < EPSILON then
        return currentCFrame, 0, 0
    end

    local safeDt = math.clamp(dt or 0.0166, 0.0001, 0.1)
    local targetRotation = CFrame.lookAt(originPos, targetPosition, Vector3.yAxis)

    local deltaDot = math.clamp(currentCFrame.LookVector:Dot(targetRotation.LookVector), -1.0, 1.0)
    local angularVelocity = math.deg(math.acos(deltaDot)) / safeDt

    self.PreviousLookVector = targetRotation.LookVector
    self.CurrentCFrame = targetRotation

    return targetRotation, 0, angularVelocity
end

return VectorTracker
