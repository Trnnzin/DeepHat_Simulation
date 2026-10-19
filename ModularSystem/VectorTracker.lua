--!strict
-- =========================================================================
-- VectorTracker.lua
-- Pilar 2: Motor de Rotação, Interpolação Vetorial, Trajetória e Silent Aim
-- CFrame.lookAt com Lerp contínuo independente de framerate (Exponential Decay),
-- Proteção Epsilon (1e-4), Jitter Orgânico Perlin Noise, Clamp de Velocidade Angular
-- e Cálculo de Trajetória Desacoplada (Silent Aim Simulation Rig)
-- =========================================================================

local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

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

function VectorTracker:CheckObstruction(originPos: Vector3, targetPos: Vector3, targetInstance: Instance?): boolean
    local displacement = (targetPos - originPos)
    local dist = displacement.Magnitude
    if dist < EPSILON then return false end
    local dir = displacement / dist
    local result = Workspace:Raycast(originPos, dir * dist, self.RayParams)
    if not result then return false end

    -- Se o raio colidiu com o próprio alvo (ou partes constituintes), a linha de visada está livre!
    if targetInstance and result.Instance then
        if result.Instance == targetInstance or result.Instance:IsDescendantOf(targetInstance) then
            return false
        end
    end

    -- Se o ponto de colisão estiver dentro da tolerância de proximidade do alvo (< 0.6 studs)
    if (result.Position - targetPos).Magnitude < 0.6 then
        return false
    end

    return true
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

-- Cálculo de Rotação Suavizada com Curva Intuitiva e Limite de Velocidade Angular
function VectorTracker:ComputeSmoothRotation(
    currentCFrame: CFrame,
    targetPosition: Vector3,
    dt: number,
    smoothingFactor: number,
    accelExponent: number?,
    simulateJitter: boolean?,
    intensity: number?,
    maxAngularVel: number?,
    clampMaxVel: boolean?
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

    -- Zona morta ultra-baixa com transição suave (elimina stutter em alvos lentos)
    if angularErrorDeg < 0.04 then
        return currentCFrame, angularErrorDeg, 0
    end

    -- Matriz de Orientação Alvo via CFrame.lookAt
    local targetRotation = CFrame.lookAt(originPos, targetPosition, Vector3.yAxis)

    -- Curva de aceleração Hermite Smoothstep com expoente configurável
    local normErr = math.clamp(angularErrorDeg / 70.0, 0.0, 1.0)
    local hermiteFactor = normErr * normErr * (3.0 - 2.0 * normErr)
    local exponent = accelExponent or 1.25
    hermiteFactor = math.pow(hermiteFactor, exponent)

    -- Mapeamento semântico correto: Menor Smoothing = Maior velocidade de resposta
    local safeSmooth = math.clamp(smoothingFactor or 0.15, 0.01, 1.0)
    local responseRate = 1.0 / safeSmooth
    local k = responseRate * (0.65 + 0.35 * hermiteFactor)
    local dynamicAlpha = math.clamp(1.0 - math.exp(-k * safeDt), 0.001, 1.0)

    -- Atenuação suave na zona de micro-alinhamento (0.04° a 0.25°)
    if angularErrorDeg < 0.25 then
        local deadzoneWeight = math.clamp((angularErrorDeg - 0.04) / 0.21, 0.05, 1.0)
        dynamicAlpha = dynamicAlpha * deadzoneWeight
    end

    -- Aplica clamp de velocidade angular máxima se requisitado
    if clampMaxVel and maxAngularVel and maxAngularVel > 0 then
        local maxDegThisFrame = maxAngularVel * safeDt
        if (angularErrorDeg * dynamicAlpha) > maxDegThisFrame then
            dynamicAlpha = math.clamp(maxDegThisFrame / math.max(angularErrorDeg, 0.001), 0.001, 1.0)
        end
    end

    local smoothedCFrame = currentCFrame:Lerp(targetRotation, dynamicAlpha)

    -- Injeção de Jitter Perlin Noise caso habilitado
    if simulateJitter and intensity and intensity > 0 then
        local now = os.clock()
        local jitterFactor = (intensity / 100.0) * math.clamp(angularErrorDeg / 15.0, 0.0, 1.0) * 0.20
        if jitterFactor > 0.005 then
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
function VectorTracker:ComputeSnapRotation(currentCFrame: CFrame, targetPosition: Vector3, dt: number): (CFrame, number, number)
    local originPos = currentCFrame.Position
    local displacement = (targetPosition - originPos)
    if displacement.Magnitude < EPSILON then return currentCFrame, 0, 0 end

    local safeDt = math.clamp(dt or 0.0166, 0.0001, 0.1)
    local targetRotation = CFrame.lookAt(originPos, targetPosition, Vector3.yAxis)
    local deltaDot = math.clamp(currentCFrame.LookVector:Dot(targetRotation.LookVector), -1.0, 1.0)
    local angularVelocity = math.deg(math.acos(deltaDot)) / safeDt

    self.PreviousLookVector = targetRotation.LookVector
    self.CurrentCFrame = targetRotation
    return targetRotation, 0, angularVelocity
end

-- =========================================================================
-- SIMULAÇÃO DE SILENT AIM (DISPARO DESACOPLADO E TELEMETRIA)
-- =========================================================================

-- Avaliação geométrica do vetor de Silent Aim (Cálculo Puro sem Sorteio de Frame)
function VectorTracker:ComputeSilentAimVector(
    cameraCFrame: CFrame,
    targetPosition: Vector3,
    maxFovDeg: number,
    hitChancePercent: number?
): (boolean, Vector3, number)
    local eyePos = cameraCFrame.Position
    local displacement = (targetPosition - eyePos)
    local distance = displacement.Magnitude

    if distance < EPSILON then
        return false, cameraCFrame.LookVector, 0
    end

    local decoupledDirection = displacement / distance
    local camForward = cameraCFrame.LookVector

    local dot = math.clamp(camForward:Dot(decoupledDirection), -1.0, 1.0)
    local discrepancyAngleDeg = math.deg(math.acos(dot))

    -- Verifica se o alvo está dentro do cone angular de atuação do Silent Aim
    if discrepancyAngleDeg > maxFovDeg then
        return false, camForward, discrepancyAngleDeg
    end

    -- Sorteio opcional (usado quando invocado em evento pontual)
    if hitChancePercent ~= nil then
        local chance = math.clamp(hitChancePercent, 0.0, 100.0)
        if (math.random() * 100.0) > chance then
            return false, camForward, discrepancyAngleDeg
        end
    end

    return true, decoupledDirection, discrepancyAngleDeg
end

export type ShotSimulationResult = {
    Fired: boolean,
    HitRegistered: boolean,
    DiscrepancyAngleDeg: number,
    MuzzlePosition: Vector3,
    TargetPosition: Vector3,
    ShotDirection: Vector3,
    InFov: boolean,
    IsObstructed: boolean
}

-- Execução de Disparo Simulado Controlado (Disparado apenas por evento/trigger de tiro)
function VectorTracker:SimulateShot(
    cameraCFrame: CFrame,
    targetPosition: Vector3,
    maxFovDeg: number,
    hitChancePercent: number,
    isObstructed: boolean?,
    targetInstance: Instance?
): ShotSimulationResult
    local muzzlePos = cameraCFrame.Position + cameraCFrame.LookVector * 1.5 - Vector3.new(0, 0.4, 0)
    local displacement = (targetPosition - muzzlePos)
    local dist = displacement.Magnitude

    if dist < EPSILON then
        return {
            Fired = true,
            HitRegistered = false,
            DiscrepancyAngleDeg = 0,
            MuzzlePosition = muzzlePos,
            TargetPosition = targetPosition,
            ShotDirection = cameraCFrame.LookVector,
            InFov = false,
            IsObstructed = isObstructed == true
        }
    end

    local directDir = displacement / dist
    local dot = math.clamp(cameraCFrame.LookVector:Dot(directDir), -1.0, 1.0)
    local discrepancyAngleDeg = math.deg(math.acos(dot))
    local inFov = (discrepancyAngleDeg <= maxFovDeg)

    local hit = false
    local shotDir = cameraCFrame.LookVector

    if inFov and not isObstructed then
        local roll = math.random() * 100.0
        local chance = math.clamp(hitChancePercent, 0.0, 100.0)
        if roll <= chance then
            hit = true
            shotDir = directDir
        else
            -- Dispersão sutil fora do alvo em caso de erro probabilístico
            local missAngle = math.rad(math.random(3, 8))
            local randAxis = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5).Unit
            shotDir = CFrame.fromAxisAngle(randAxis, missAngle):VectorToWorldSpace(directDir)
        end
    end

    return {
        Fired = true,
        HitRegistered = hit,
        DiscrepancyAngleDeg = discrepancyAngleDeg,
        MuzzlePosition = muzzlePos,
        TargetPosition = targetPosition,
        ShotDirection = shotDir,
        InFov = inFov,
        IsObstructed = isObstructed == true
    }
end

-- Visualizador de Traçador (Tracer 3D Neon com Limpeza de Debris)
function VectorTracker:DrawTracerBeam(origin: Vector3, targetPos: Vector3, color: Color3?, duration: number?)
    local ok, _ = pcall(function()
        local dist = (targetPos - origin).Magnitude
        if dist < 0.1 then return end

        local container = Workspace:FindFirstChild("DeepHat_Tracers")
        if not container or not container:IsA("Folder") then
            local newFolder = Instance.new("Folder")
            newFolder.Name = "DeepHat_Tracers"
            newFolder.Parent = Workspace
            container = newFolder
        end

        local part = Instance.new("Part")
        part.Name = "DeepHat_SilentAimTracer"
        part.Anchored = true
        part.CanCollide = false
        part.CanTouch = false
        part.CanQuery = false
        part.Material = Enum.Material.Neon
        part.Color = color or Color3.fromRGB(255, 45, 60)
        part.Transparency = 0.25
        part.Size = Vector3.new(0.08, 0.08, dist)
        part.CFrame = CFrame.lookAt(origin, targetPos) * CFrame.new(0, 0, -dist / 2)
        part.Parent = container

        Debris:AddItem(part, duration or 0.12)
    end)
end

return VectorTracker
