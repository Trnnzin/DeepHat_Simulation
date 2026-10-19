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
    self.CurrentRotation = nil :: CFrame?
    self.TrackingActive = false
    self.LastRawCamRotation = nil :: CFrame?
    self.PreviousLookVector = Vector3.zAxis
    self.PreviousTime = os.clock()
    self.PreviousAngularVelocity = 0
    self.NoiseSeed = math.random(1000, 9999)
    self.VelocityCache = setmetatable({}, { __mode = "k" }) :: { [Instance]: { pos: Vector3, time: number, vel: Vector3 } }

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = filterInstances or {}
    rayParams.IgnoreWater = true
    rayParams.RespectCanCollide = true
    self.RayParams = rayParams

    return self
end

function VectorTracker:ResetTracking()
    self.TrackingActive = false
    self.CurrentRotation = nil
    self.LastRawCamRotation = nil
end

-- Libera por completo o controle da câmera: após Release() o tracker não possui
-- nenhum estado acumulado e o chamador NÃO deve mais escrever em camera.CFrame.
-- (O CameraModule do Roblox reassume o controle no frame seguinte.)
function VectorTracker:Release()
    self:ResetTracking()
    self.PreviousLookVector = Vector3.zAxis
    self.PreviousAngularVelocity = 0
end

function VectorTracker:SetFilterInstances(instances: { Instance })
    self.RayParams.FilterDescendantsInstances = instances
end

export type LosResult = {
    Status: string,        -- "VISIBLE" | "BLOCKED" | "INVALID"
    Reason: string,        -- causa legível
    BlockerName: string?,  -- objeto responsável pela obstrução
    BlockerPart: BasePart?,
    HitDistance: number?,  -- distância origem -> colisão (studs)
    QueryDistance: number, -- distância origem -> destino
}

local function IsFiniteVec(v: Vector3): boolean
    return v.X == v.X and v.Y == v.Y and v.Z == v.Z
        and math.abs(v.X) ~= math.huge and math.abs(v.Y) ~= math.huge and math.abs(v.Z) ~= math.huge
end

-- Política de LOS (documentada):
--  * RespectCanCollide = true: partes com CanCollide=false (decoração, triggers, acessórios
--    não colidíveis) NÃO bloqueiam. Barreiras INVISÍVEIS com CanCollide=true BLOQUEIAM
--    (são colisores de teste legítimos); Transparency NÃO é critério.
--  * IgnoreWater = true: água não bloqueia.
--  * O próprio alvo (e descendentes) conta como VISIBLE; o filtro Exclude cobre o modelo de teste/jogador local.
--  * Colisão a < END_TOLERANCE studs do ponto final é tratada como atingir o destino (VISIBLE).
--  * Entrada não finita, origem == destino ou destino removido => INVALID (nunca VISIBLE).
local END_TOLERANCE = 0.8

function VectorTracker:EvaluateLineOfSight(originPos: Vector3, targetPos: Vector3, targetInstance: Instance?): LosResult
    if typeof(originPos) ~= "Vector3" or typeof(targetPos) ~= "Vector3"
        or not IsFiniteVec(originPos) or not IsFiniteVec(targetPos) then
        return { Status = "INVALID", Reason = "Posição não finita ou ausente", QueryDistance = 0 }
    end
    if targetInstance ~= nil and (targetInstance.Parent == nil or not targetInstance:IsDescendantOf(game)) then
        return { Status = "INVALID", Reason = "Destino removido da árvore", QueryDistance = 0 }
    end

    local displacement = targetPos - originPos
    local dist = displacement.Magnitude
    if dist < EPSILON then
        return { Status = "INVALID", Reason = "Origem e destino coincidentes", QueryDistance = dist }
    end

    local ok, result = pcall(function()
        return Workspace:Raycast(originPos, displacement, self.RayParams)
    end)
    if not ok then
        return { Status = "INVALID", Reason = "Raycast falhou: " .. tostring(result), QueryDistance = dist }
    end
    if not result then
        return { Status = "VISIBLE", Reason = "Nenhuma colisão no trajeto", QueryDistance = dist }
    end

    local hit = result.Instance
    local hitDist = (result.Position - originPos).Magnitude
    if targetInstance and (hit == targetInstance or hit:IsDescendantOf(targetInstance)) then
        return { Status = "VISIBLE", Reason = "Raio atingiu o próprio alvo", HitDistance = hitDist, QueryDistance = dist }
    end
    if (result.Position - targetPos).Magnitude < END_TOLERANCE then
        return { Status = "VISIBLE", Reason = "Colisão dentro da tolerância do ponto final", HitDistance = hitDist, QueryDistance = dist }
    end
    return {
        Status = "BLOCKED",
        Reason = hit.Transparency >= 0.95 and "Barreira invisível colidível" or "Obstrução sólida",
        BlockerName = hit:GetFullName(),
        BlockerPart = hit,
        HitDistance = hitDist,
        QueryDistance = dist,
    }
end

-- Histórico limitado de consultas LOS (para a aba Line of Sight)
VectorTracker.LosHistoryLimit = 50
function VectorTracker:RecordLos(result: LosResult, targetName: string?)
    local history = self.LosHistory
    if not history then
        history = {}
        self.LosHistory = history
    end
    self.LastLos = result
    table.insert(history, {
        Time = os.clock(), Target = targetName or "?", Status = result.Status,
        Reason = result.Reason, Blocker = result.BlockerName, HitDistance = result.HitDistance,
    })
    while #history > math.max(1, self.LosHistoryLimit or VectorTracker.LosHistoryLimit) do
        table.remove(history, 1)
    end
end

function VectorTracker:ClearLosHistory()
    self.LosHistory = {}
    self.LastLos = nil
end

-- Compatibilidade: true somente se BLOCKED comprovado (INVALID não é tratado como obstrução)
function VectorTracker:CheckObstruction(originPos: Vector3, targetPos: Vector3, targetInstance: Instance?): boolean
    return self:EvaluateLineOfSight(originPos, targetPos, targetInstance).Status == "BLOCKED"
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

    -- dt inválido (nil, NaN, <= 0) cai no padrão de 60Hz; dt grande é limitado
    local rawDt = (type(dt) == "number" and dt == dt and dt > 0) and dt or 0.0166
    local safeDt = math.clamp(rawDt, 0.0001, 0.1)

    -- Extração robusta de Pitch e Yaw atuais a partir do LookVector da câmera
    -- Roll é fixado estritamente em 0 para impedir giros contínuos e desorientação 3D
    local curLook = currentCFrame.LookVector
    local curPitch = math.asin(math.clamp(curLook.Y, -1.0, 1.0))
    local curYaw = math.atan2(-curLook.X, -curLook.Z)

    -- Direção alvo para o ponto 3D do alvo
    local unitDir = displacement / distance
    local tgtPitch = math.asin(math.clamp(unitDir.Y, -1.0, 1.0))
    local tgtYaw = math.atan2(-unitDir.X, -unitDir.Z)

    -- Cálculo do menor arco angular para Yaw e Pitch (envoltória periódica [-pi, pi])
    local function ShortestAngle(tgt: number, cur: number): number
        return (tgt - cur + math.pi) % (2.0 * math.pi) - math.pi
    end
    local deltaPitch = ShortestAngle(tgtPitch, curPitch)
    local deltaYaw = ShortestAngle(tgtYaw, curYaw)
    local totalAngularErrRad = math.sqrt(deltaPitch * deltaPitch + deltaYaw * deltaYaw)
    local angularErrorDeg = math.deg(totalAngularErrRad)

    -- Zona morta de estabilidade: se o erro for microscópico (< 0.04°), mantém a câmera imóvel sem trepidações
    if angularErrorDeg < 0.04 then
        self.CurrentCFrame = currentCFrame
        self.TrackingActive = true
        return currentCFrame, angularErrorDeg, 0
    end

    -- Curva de aceleração Hermite Smoothstep com expoente configurável
    local normErr = math.clamp(angularErrorDeg / 70.0, 0.0, 1.0)
    local hermiteFactor = normErr * normErr * (3.0 - 2.0 * normErr)
    local exponent = accelExponent or 1.25
    hermiteFactor = math.pow(hermiteFactor, exponent)

    -- Mapeamento semântico: Menor Smoothing = Maior velocidade de resposta
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
        local maxRadThisFrame = math.rad(maxAngularVel) * safeDt
        if (totalAngularErrRad * dynamicAlpha) > maxRadThisFrame then
            dynamicAlpha = math.clamp(maxRadThisFrame / math.max(totalAngularErrRad, 0.0001), 0.001, 1.0)
        end
    end

    -- Atualização determinística em espaço Euler YXZ (Sem acúmulo de matrizes nem Roll)
    local nextPitch = curPitch + deltaPitch * dynamicAlpha
    nextPitch = math.clamp(nextPitch, -math.rad(89.5), math.rad(89.5))
    local nextYaw = curYaw + deltaYaw * dynamicAlpha

    local smoothedCFrame = CFrame.new(originPos) * CFrame.fromEulerAnglesYXZ(nextPitch, nextYaw, 0)

    -- Injeção de Jitter Perlin Noise caso habilitado
    if simulateJitter and intensity and intensity > 0 then
        local now = os.clock()
        local jitterFactor = (intensity / 100.0) * math.clamp(angularErrorDeg / 15.0, 0.0, 1.0) * 0.15
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
    self.TrackingActive = true

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

    local endPosition = hit and targetPosition or (muzzlePos + shotDir * dist)

    return {
        Fired = true,
        HitRegistered = hit,
        DiscrepancyAngleDeg = discrepancyAngleDeg,
        MuzzlePosition = muzzlePos,
        TargetPosition = endPosition,
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

        local tracerColor = color or Color3.fromRGB(255, 45, 60)
        local life = duration or 0.22

        -- 1. Feixe de Traçador (Cilindro/Viga Neon)
        local part = Instance.new("Part")
        part.Name = "DeepHat_SilentAimTracer"
        part.Anchored = true
        part.CanCollide = false
        part.CanTouch = false
        part.CanQuery = false
        part.Material = Enum.Material.Neon
        part.Color = tracerColor
        part.Transparency = 0.10
        part.Size = Vector3.new(0.16, 0.16, dist)
        part.CFrame = CFrame.lookAt(origin, targetPos) * CFrame.new(0, 0, -dist / 2)
        part.Parent = container
        Debris:AddItem(part, life)

        -- 2. Marcador de Impacto no Ponto de Destino
        local impact = Instance.new("Part")
        impact.Name = "DeepHat_ImpactMarker"
        impact.Shape = Enum.PartType.Ball
        impact.Anchored = true
        impact.CanCollide = false
        impact.CanTouch = false
        impact.CanQuery = false
        impact.Material = Enum.Material.Neon
        impact.Color = tracerColor
        impact.Transparency = 0.15
        impact.Size = Vector3.new(0.70, 0.70, 0.70)
        impact.Position = targetPos
        impact.Parent = container
        Debris:AddItem(impact, life + 0.08)
    end)
end

return VectorTracker
