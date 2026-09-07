--!strict
-- AdvancedKinematics.lua
-- Modulo 2: Motor de Cinematica Avancada (Snap, Tracking Dinamico, Easing e Telemetria)

local SimConfig = require(script.Parent.SimConfig)

local AdvancedKinematics = {}
AdvancedKinematics.__index = AdvancedKinematics

export type TelemetryData = {
    angularVelocity: number,    -- Velocidade angular instantanea (graus/segundo)
    isObstructed: boolean,      -- Se a linha de visao para o alvo esta geometricamente bloqueada
    position: Vector3,          -- Posicao tridimensional atual da camera
    cframe: CFrame,             -- Orientacao e posicao em CFrame
    mode: string,               -- "SNAP" ou "SMOOTH"
    angularErrorDeg: number     -- Desvio angular em relacao ao centro do alvo
}

-- Curva de Aceleracao Sigmoide / Hermite Cubico (Ease-In / Ease-Out)
local function Smoothstep(x: number): number
    local clamped = math.clamp(x, 0.0, 1.0)
    return clamped * clamped * (3.0 - 2.0 * clamped)
end

function AdvancedKinematics.new(initialCFrame: CFrame?, filterInstances: { Instance }?)
    local self = setmetatable({}, AdvancedKinematics)

    self.CurrentCFrame = initialCFrame or CFrame.new(Vector3.new(0, 5, 0), Vector3.new(0, 5, 10))
    self.PreviousLookVector = self.CurrentCFrame.LookVector
    self.NoiseSeed = math.random(1000, 9999)

    local rayParams = RaycastParams.new()
    rayParams.FilterType = RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = filterInstances or {}
    rayParams.IgnoreWater = true
    self.RayParams = rayParams

    self.CachedTelemetry = {
        angularVelocity = 0,
        isObstructed = false,
        position = Vector3.zero,
        cframe = self.CurrentCFrame,
        mode = "SMOOTH",
        angularErrorDeg = 0
    }

    return self
end

function AdvancedKinematics:SetFilterInstances(instances: { Instance })
    self.RayParams.FilterDescendantsInstances = instances
end

function AdvancedKinematics:CheckObstruction(fromPos: Vector3, toPos: Vector3): boolean
    local dir = (toPos - fromPos)
    local dist = dir.Magnitude
    if dist < 0.05 then
        return false
    end

    local raycastResult = workspace:Raycast(fromPos, dir.Unit * dist, self.RayParams)
    return (raycastResult ~= nil)
end

function AdvancedKinematics:StepSnap(targetPosition: Vector3, dt: number): TelemetryData
    local camera = workspace.CurrentCamera
    if camera then
        self.CurrentCFrame = camera.CFrame
    end

    local eyePos = self.CurrentCFrame.Position
    local toTarget = (targetPosition - eyePos)
    local dist = toTarget.Magnitude

    if dist < 0.001 then
        self.CachedTelemetry.angularVelocity = 0
        self.CachedTelemetry.isObstructed = false
        self.CachedTelemetry.position = eyePos
        self.CachedTelemetry.cframe = self.CurrentCFrame
        self.CachedTelemetry.mode = "SNAP"
        self.CachedTelemetry.angularErrorDeg = 0
        return self.CachedTelemetry
    end

    local dirToTarget = toTarget.Unit
    local targetRotation = CFrame.lookAt(eyePos, targetPosition)

    local dot = math.clamp(self.CurrentCFrame.LookVector:Dot(dirToTarget), -1.0, 1.0)
    local angularErrorDeg = math.deg(math.acos(dot))

    self.CurrentCFrame = targetRotation

    local safeDt = (dt and dt > 0) and dt or 0.0166
    local peakAngularVel = angularErrorDeg / safeDt

    local isObstructed = self:CheckObstruction(eyePos, targetPosition)
    self.PreviousLookVector = self.CurrentCFrame.LookVector

    self.CachedTelemetry.angularVelocity = peakAngularVel
    self.CachedTelemetry.isObstructed = isObstructed
    self.CachedTelemetry.position = eyePos
    self.CachedTelemetry.cframe = self.CurrentCFrame
    self.CachedTelemetry.mode = "SNAP"
    self.CachedTelemetry.angularErrorDeg = 0

    return self.CachedTelemetry
end

function AdvancedKinematics:StepSmooth(targetPosition: Vector3, dt: number): TelemetryData
    local camera = workspace.CurrentCamera
    if camera then
        self.CurrentCFrame = camera.CFrame
    end

    local eyePos = self.CurrentCFrame.Position
    local toTarget = (targetPosition - eyePos)
    local dist = toTarget.Magnitude

    -- Otimizacao de Magnitude & Guarda Epsilon rigorosa
    if dist < 0.001 then
        self.CachedTelemetry.angularVelocity = 0
        self.CachedTelemetry.isObstructed = false
        self.CachedTelemetry.position = eyePos
        self.CachedTelemetry.cframe = self.CurrentCFrame
        self.CachedTelemetry.mode = "SMOOTH"
        self.CachedTelemetry.angularErrorDeg = 0
        return self.CachedTelemetry
    end

    -- Vetor unitario direto sem recalculate de magnitude
    local dirToTarget = toTarget / dist
    local currentLook = self.CurrentCFrame.LookVector

    local dot = math.clamp(currentLook:Dot(dirToTarget), -1.0, 1.0)
    local angularErrorDeg = math.deg(math.acos(dot))

    local fov = math.max(SimConfig.Get("FOV") or 60.0, 1.0)
    local baseSmoothing = math.clamp(SimConfig.Get("Smoothing") or 0.15, 0.005, 1.0)
    local speedMult = math.clamp((SimConfig.Get("MoveSpeed") or 16.0) / 16.0, 0.25, 3.0)
    local precision = math.clamp((SimConfig.Get("TrajectoryPrecision") or 98.5) / 100.0, 0.5, 1.0)
    local intensity = math.clamp((SimConfig.Get("Intensity") or 75.0) / 100.0, 0.0, 2.0)
    local maxRadius = SimConfig.Get("VectorRadius") or 250.0

    -- Se fora do raio maximo de atuacao ou fora do FOV, nao rotaciona
    if dist > maxRadius or angularErrorDeg > fov then
        self.CachedTelemetry.angularVelocity = 0
        self.CachedTelemetry.isObstructed = self:CheckObstruction(eyePos, targetPosition)
        self.CachedTelemetry.position = eyePos
        self.CachedTelemetry.cframe = self.CurrentCFrame
        self.CachedTelemetry.mode = "IDLE"
        self.CachedTelemetry.angularErrorDeg = angularErrorDeg
        return self.CachedTelemetry
    end

    -- Curva de Aceleracao Hermite Smoothstep com expoente de gradiente
    local normalizedErr = math.clamp(angularErrorDeg / fov, 0.0, 1.0)
    local smoothFactor = normalizedErr * normalizedErr * (3.0 - 2.0 * normalizedErr)
    local accelExponent = SimConfig.Get("AccelerationCurve") or 1.25
    smoothFactor = math.pow(smoothFactor, accelExponent)

    -- Interpolacao Frame-rate Independent via Exponential Decay (Sem Jittering e Sem Delay)
    local safeDt = math.clamp(dt or 0.0166, 0.001, 0.1)
    local k = (baseSmoothing * 28.0 * speedMult) * (0.35 + 0.65 * smoothFactor)
    local dynamicAlpha = math.clamp(1.0 - math.exp(-k * safeDt), 0.001, 1.0)

    local idealTargetRotation = CFrame.lookAt(eyePos, targetPosition)
    local smoothedRotation = self.CurrentCFrame:Lerp(idealTargetRotation, dynamicAlpha)

    -- Insercao de Micro-Oscilacoes (Jitter Organico via Perlin Noise) que cessa ao focar o alvo
    local jitterAmplitude = (1.0 - precision) * intensity * 0.4 * math.clamp(angularErrorDeg / 10.0, 0.0, 1.0)
    if jitterAmplitude > 0.0001 then
        local now = os.clock()
        local noiseFrequency = 3.5 * intensity
        local sampleX = math.noise(now * noiseFrequency, self.NoiseSeed, 0.5)
        local sampleY = math.noise(now * noiseFrequency, self.NoiseSeed + 100, 0.5)
        local pitchJitterRad = math.rad(sampleX * jitterAmplitude)
        local yawJitterRad = math.rad(sampleY * jitterAmplitude)
        self.CurrentCFrame = smoothedRotation * CFrame.Angles(pitchJitterRad, yawJitterRad, 0)
    else
        self.CurrentCFrame = smoothedRotation
    end

    local newLook = self.CurrentCFrame.LookVector
    local deltaDot = math.clamp(self.PreviousLookVector:Dot(newLook), -1.0, 1.0)
    local deltaAngleDeg = math.deg(math.acos(deltaDot))
    local angularVelocity = deltaAngleDeg / safeDt
    self.PreviousLookVector = newLook

    local isObstructed = self:CheckObstruction(eyePos, targetPosition)

    self.CachedTelemetry.angularVelocity = angularVelocity
    self.CachedTelemetry.isObstructed = isObstructed
    self.CachedTelemetry.position = eyePos
    self.CachedTelemetry.cframe = self.CurrentCFrame
    self.CachedTelemetry.mode = "SMOOTH"
    self.CachedTelemetry.angularErrorDeg = angularErrorDeg

    return self.CachedTelemetry
end

return AdvancedKinematics
