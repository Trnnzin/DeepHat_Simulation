--!strict
-- AdvancedCameraController.lua
-- Modulo de Controle Cinematico de Camera Virtual (Tracking Dinamico com Easing e Ruido Perlin)

local AdvancedCameraController = {}
AdvancedCameraController.__index = AdvancedCameraController

export type ControllerConfig = {
    MaxFovAngleDeg: number,      -- Raio do cone angular de ativacao (em graus)
    BaseSmoothing: number,       -- Coeficiente de interpolacao base [0.01 - 1.0]
    NoiseFrequency: number,      -- Frequencia do ruido procedural (Perlin)
    NoiseAmplitudeDeg: number,   -- Amplitude angular maxima do ruido (em graus)
    MinAngleThresholdDeg: number -- Zona morta onde a interpolacao atinge maxima suavidade
}

export type TrackingResult = {
    isActive: boolean,
    targetInFov: boolean,
    angularErrorDeg: number,
    appliedSpeedDeg: number,
    currentCFrame: CFrame
}

-- Construtor do Controlador
function AdvancedCameraController.new(initialCFrame: CFrame?, config: ControllerConfig?)
    local self = setmetatable({}, AdvancedCameraController)

    self.CurrentCFrame = initialCFrame or CFrame.new(Vector3.new(0, 5, 0), Vector3.new(0, 5, 10))
    self.Config = config or {
        MaxFovAngleDeg = 45.0,
        BaseSmoothing = 0.12,
        NoiseFrequency = 3.5,
        NoiseAmplitudeDeg = 0.25,
        MinAngleThresholdDeg = 1.5
    }

    self.PreviousLookVector = self.CurrentCFrame.LookVector
    self.NoiseSeed = math.random(1000, 9999)

    return self
end

-- 1. Funcao de Transferencia Smoothstep (Curva de Aceleracao Nao-Linear Ease-In / Ease-Out)
local function Smoothstep(x: number): number
    local clamped = math.clamp(x, 0.0, 1.0)
    return clamped * clamped * (3.0 - 2.0 * clamped)
end

-- 2. Calculo do Ruido Procedural para Simulacao de Micro-Oscilacoes (Perlin Noise)
local function ComputePerlinNoiseOffset(timeSec: number, seed: number, freq: number, ampDeg: number): (number, number)
    local sampleX = math.noise(timeSec * freq, seed, 0.5)
    local sampleY = math.noise(timeSec * freq, seed + 100, 0.5)

    local pitchDeg = sampleX * ampDeg
    local yawDeg = sampleY * ampDeg

    return math.rad(pitchDeg), math.rad(yawDeg)
end

-- Atualiza a cinematica de rotacao em direcao a posicao alvo
function AdvancedCameraController:Step(targetPosition: Vector3, dt: number): TrackingResult
    local now = os.clock()
    local eyePos = self.CurrentCFrame.Position
    local toTarget = (targetPosition - eyePos)
    local distance = toTarget.Magnitude

    if distance < 0.001 then
        return {
            isActive = false,
            targetInFov = false,
            angularErrorDeg = 0,
            appliedSpeedDeg = 0,
            currentCFrame = self.CurrentCFrame
        }
    end

    local dirToTarget = toTarget.Unit
    local currentLook = self.CurrentCFrame.LookVector

    -- 3. Verificacao de Cone de Visao (Field of View - FOV Limit)
    local dot = math.clamp(currentLook:Dot(dirToTarget), -1.0, 1.0)
    local angularErrorRad = math.acos(dot)
    local angularErrorDeg = math.deg(angularErrorRad)

    -- Se o alvo estiver fora do angulo de atuacao configurado, nao aplica correcao
    if angularErrorDeg > self.Config.MaxFovAngleDeg then
        return {
            isActive = false,
            targetInFov = false,
            angularErrorDeg = angularErrorDeg,
            appliedSpeedDeg = 0,
            currentCFrame = self.CurrentCFrame
        }
    end

    -- 4. Modulacao Nao-Linear da Suavizacao (Dynamic Smoothing com Curva)
    -- Normaliza o erro angular dentro do intervalo do FOV [0, 1]
    local normalizedError = math.clamp(angularErrorDeg / self.Config.MaxFovAngleDeg, 0.0, 1.0)
    local accelerationCurve = Smoothstep(normalizedError)

    -- Amortecimento adaptativo: reduz aceleracao proxima ao alvo para desacelerar com precisao
    local dynamicAlpha = self.Config.BaseSmoothing * (0.3 + 0.7 * accelerationCurve)
    dynamicAlpha = math.clamp(dynamicAlpha, 0.005, 1.0)

    -- 5. Interpolacao de Orientacao
    local idealTargetRotation = CFrame.lookAt(eyePos, targetPosition)
    local interpolatedRotation = self.CurrentCFrame:Lerp(idealTargetRotation, dynamicAlpha)

    -- 6. Injecao de Micro-Oscilacoes de Inercia Fisica (Jitter Procedural)
    local noisePitchRad, noiseYawRad = ComputePerlinNoiseOffset(
        now, 
        self.NoiseSeed, 
        self.Config.NoiseFrequency, 
        self.Config.NoiseAmplitudeDeg
    )

    local noiseRotation = CFrame.Angles(noisePitchRad, noiseYawRad, 0)
    self.CurrentCFrame = interpolatedRotation * noiseRotation

    -- 7. Metricas de Saida
    local newLook = self.CurrentCFrame.LookVector
    local deltaDot = math.clamp(self.PreviousLookVector:Dot(newLook), -1.0, 1.0)
    local speedDeg = dt > 0 and (math.deg(math.acos(deltaDot)) / dt) or 0
    self.PreviousLookVector = newLook

    return {
        isActive = true,
        targetInFov = true,
        angularErrorDeg = angularErrorDeg,
        appliedSpeedDeg = speedDeg,
        currentCFrame = self.CurrentCFrame
    }
end

return AdvancedCameraController