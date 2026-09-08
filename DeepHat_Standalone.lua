--!strict
-- DeepHat_Standalone.lua (v5.0 - Kernel-Level Tracking & Visual Suite)
-- Motor de Simulação de Cinética 3D, Detecção de Instâncias, Álgebra Linear e Chams ESP
-- Arquitetura Anti-Lag & Anti-Fail:
-- 1. Detecção Universal de Instâncias: Type Guarding para BasePart e Model (:GetPivot())
-- 2. Motor Vetorial com Guarda Epsilon (1e-4) e Interpolação Lerp Frame-Rate Independent
-- 3. Destruição e Reconstrução Estrita de UI com Design Minimalista em 3 Colunas
-- 4. Overlay Visual com DepthMode AlwaysOnTop e Isolamento de Renderização

-- Destruição Total de Sessões Anteriores ou UIs Legadas
local function PurgeAllLegacyUIs()
    local containers: { Instance } = {}
    local okHui, hui = pcall(function() return (gethui and gethui()) end)
    if okHui and hui then table.insert(containers, hui) end

    local okCore, core = pcall(function() return game:GetService("CoreGui") end)
    if okCore and core then table.insert(containers, core) end

    local pGui = game:GetService("Players").LocalPlayer and game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if pGui then table.insert(containers, pGui) end

    local targetPatterns = {
        "Diagnostic", "Kinematics", "DeepHat", "FovCircle", "HL_"
    }

    for _, container in ipairs(containers) do
        pcall(function()
            for _, child in ipairs(container:GetChildren()) do
                for _, pat in ipairs(targetPatterns) do
                    if child.Name:find(pat) then
                        pcall(function() child:Destroy() end)
                        break
                    end
                end
            end
        end)
    end

    pcall(function()
        for _, obj in ipairs(game:GetService("Workspace"):GetDescendants()) do
            if obj:IsA("Highlight") and (obj.Name:find("DeepHat") or obj.Name:find("HL_")) then
                pcall(function() obj:Destroy() end)
            end
        end
    end)
end
PurgeAllLegacyUIs()

if _G.DeepHat_Cleanup then
    pcall(_G.DeepHat_Cleanup)
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local CoreGuiService = game:GetService("CoreGui")
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera or Workspace:WaitForChild("Camera") :: Camera

-- [1/5] MODULO: SimConfig (Central de Parametros + Observer Pattern)
-- =========================================================================
local SimConfig = {}
do
    local PROFILES: { [string]: ProfileData } = {
        ["Normal"] = {
            SimulationActive = true,
            AimMode = "HoldRMB",
            HoldToAim = true,
            FOV = 70.0,
            Smoothing = 0.15,
            AngularVelocity = 240.0,
            ResponseTime = 16,
            TrajectoryPrecision = 98.5,
            UpdateFrequency = 60,
            VectorRadius = 300.0,
            ActiveProfile = "Normal",
            EventFrequency = 20,
            Intensity = 75,
            MoveSpeed = 16.0,
            AccelerationCurve = 1.25,
            CycleDuration = 30,
            SimulatedAgents = 4,
            TargetRegion = "Head",
            TargetBone = "Head",
            EnableESP = true,
            ShowFovCircle = true,
            EnableLead = true,
            ProjectileSpeed = 900.0,
            VisibleOnly = false,
            TeamCheck = false
        },
        ["Leve"] = {
            SimulationActive = true,
            AimMode = "HoldRMB",
            HoldToAim = true,
            FOV = 45.0,
            Smoothing = 0.28,
            AngularVelocity = 140.0,
            ResponseTime = 30,
            TrajectoryPrecision = 95.0,
            UpdateFrequency = 30,
            VectorRadius = 150.0,
            ActiveProfile = "Leve",
            EventFrequency = 10,
            Intensity = 40,
            MoveSpeed = 12.0,
            AccelerationCurve = 1.0,
            CycleDuration = 20,
            SimulatedAgents = 2,
            TargetRegion = "Torso",
            TargetBone = "Torso",
            EnableESP = true,
            ShowFovCircle = true,
            EnableLead = false,
            ProjectileSpeed = 800.0,
            VisibleOnly = false,
            TeamCheck = false
        },
        ["Medio"] = {
            SimulationActive = true,
            AimMode = "HoldRMB",
            HoldToAim = true,
            FOV = 80.0,
            Smoothing = 0.09,
            AngularVelocity = 320.0,
            ResponseTime = 10,
            TrajectoryPrecision = 90.0,
            UpdateFrequency = 60,
            VectorRadius = 350.0,
            ActiveProfile = "Medio",
            EventFrequency = 30,
            Intensity = 85,
            MoveSpeed = 22.0,
            AccelerationCurve = 1.6,
            CycleDuration = 45,
            SimulatedAgents = 6,
            TargetRegion = "Head",
            TargetBone = "Head",
            EnableESP = true,
            ShowFovCircle = true,
            EnableLead = true,
            ProjectileSpeed = 1000.0,
            VisibleOnly = false,
            TeamCheck = false
        },
        ["Agressivo"] = {
            SimulationActive = true,
            AimMode = "HoldRMB",
            HoldToAim = true,
            FOV = 120.0,
            Smoothing = 0.02,
            AngularVelocity = 600.0,
            ResponseTime = 2,
            TrajectoryPrecision = 80.0,
            UpdateFrequency = 120,
            VectorRadius = 500.0,
            ActiveProfile = "Agressivo",
            EventFrequency = 50,
            Intensity = 100,
            MoveSpeed = 32.0,
            AccelerationCurve = 2.4,
            CycleDuration = 60,
            SimulatedAgents = 10,
            TargetRegion = "Head",
            TargetBone = "Head",
            EnableESP = true,
            ShowFovCircle = true,
            EnableLead = true,
            ProjectileSpeed = 1200.0,
            VisibleOnly = false,
            TeamCheck = false
        },
        ["Custom"] = {
            SimulationActive = true,
            AimMode = "HoldRMB",
            HoldToAim = true,
            FOV = 70.0,
            Smoothing = 0.15,
            AngularVelocity = 240.0,
            ResponseTime = 16,
            TrajectoryPrecision = 98.5,
            UpdateFrequency = 60,
            VectorRadius = 300.0,
            ActiveProfile = "Custom",
            EventFrequency = 20,
            Intensity = 75,
            MoveSpeed = 16.0,
            AccelerationCurve = 1.25,
            CycleDuration = 30,
            SimulatedAgents = 4,
            TargetRegion = "Head",
            TargetBone = "Head",
            EnableESP = true,
            ShowFovCircle = true,
            EnableLead = true,
            ProjectileSpeed = 900.0,
            VisibleOnly = false,
            TeamCheck = false
        }
    }

    -- Estado inicial ativo
    local CurrentState: ProfileData = {
        SimulationActive = true,
        AimMode = "HoldRMB",
        HoldToAim = true,
        FOV = 70.0,
        Smoothing = 0.15,
        AngularVelocity = 240.0,
        ResponseTime = 16,
        TrajectoryPrecision = 98.5,
        UpdateFrequency = 60,
        VectorRadius = 300.0,
        ActiveProfile = "Normal",
        EventFrequency = 20,
        Intensity = 75,
        MoveSpeed = 16.0,
        AccelerationCurve = 1.25,
        CycleDuration = 30,
        SimulatedAgents = 4,
        TargetRegion = "Head",
        TargetBone = "Head",
        EnableESP = true,
        ShowFovCircle = true,
        EnableLead = true,
        ProjectileSpeed = 900.0,
        VisibleOnly = false,
        TeamCheck = false
    }

    local KeyListeners: { [string]: { (any) -> () } } = {}
    local GlobalListeners: { (string, any) -> () } = {}

    function SimConfig.Get(key: string): any
        return (CurrentState :: any)[key]
    end

    function SimConfig.GetAll(): ProfileData
        local clone: any = {}
        for k, v in pairs(CurrentState) do
            clone[k] = v
        end
        return clone
    end

    function SimConfig.Set(key: string, value: any, silent: boolean?)
        if (CurrentState :: any)[key] == value then
            return
        end

        (CurrentState :: any)[key] = value

        if key ~= "ActiveProfile" and key ~= "SimulationActive" and CurrentState.ActiveProfile ~= "Custom" then
            CurrentState.ActiveProfile = "Custom"
            SimConfig.Notify("ActiveProfile", "Custom")
        end

        if not silent then
            SimConfig.Notify(key, value)
        end
    end

    function SimConfig.Notify(key: string, value: any)
        if KeyListeners[key] then
            for _, callback in ipairs(KeyListeners[key]) do
                task.spawn(callback, value)
            end
        end

        for _, callback in ipairs(GlobalListeners) do
            task.spawn(callback, key, value)
        end
    end

    function SimConfig.Subscribe(key: string, callback: (any) -> ()): () -> ()
        if not KeyListeners[key] then
            KeyListeners[key] = {}
        end
        table.insert(KeyListeners[key], callback)

        return function()
            local list = KeyListeners[key]
            if not list then return end
            local idx = table.find(list, callback)
            if idx then
                table.remove(list, idx)
            end
        end
    end

    function SimConfig.SubscribeAll(callback: (string, any) -> ()): () -> ()
        table.insert(GlobalListeners, callback)
        return function()
            local idx = table.find(GlobalListeners, callback)
            if idx then
                table.remove(GlobalListeners, idx)
            end
        end
    end

    function SimConfig.LoadProfile(profileName: string)
        local profile = PROFILES[profileName]
        if not profile then
            warn(string.format("[SimConfig] Perfil desconhecido: %s", tostring(profileName)))
            return
        end

        for k, v in pairs(profile) do
            SimConfig.Set(k, v, true)
        end

        SimConfig.Notify("ActiveProfile", profileName)
    end
end

-- =========================================================================
-- =========================================================================
-- =========================================================================
-- [2/5] MODULO: InstanceDetector (Scanner de Instâncias de Alta Precisão)
-- =========================================================================
local InstanceDetector = {}
InstanceDetector.__index = InstanceDetector

function InstanceDetector.new(scanInterval: number?)
    local self = setmetatable({}, InstanceDetector)
    self.ScanInterval = scanInterval or 0.15
    self.LastScanTime = 0
    self.CandidatePool = {} :: { Instance }
    self.LocalPlayer = Players.LocalPlayer
    self.KnownTags = { "NPC", "Enemy", "Target", "Zombie", "Bot", "Dummy", "Entity", "Character", "Hitbox" }
    self.SearchFolders = { "NPCs", "Enemies", "Characters", "Zombies", "Bots", "Dummies", "Mobs", "Entities", "Targets", "Spawns" }
    return self
end

-- Validação de Integridade (Type Guarding Estrito)
function InstanceDetector:IsValidTarget(objeto: Instance, teamCheck: boolean?): boolean
    -- Type Guarding: BasePart ou Model válido no DataModel
    if not objeto or not (objeto:IsA("BasePart") or objeto:IsA("Model")) or not objeto:IsDescendantOf(game) then
        return false
    end

    local myChar = self.LocalPlayer and self.LocalPlayer.Character
    if myChar and (objeto == myChar or objeto:IsDescendantOf(myChar)) then
        return false
    end

    -- Ignora geometrias de mapa e terreno
    if objeto:IsA("Terrain") or objeto.Name == "Terrain" or objeto.Name == "Baseplate" then
        return false
    end
    local lowerName = objeto.Name:lower()
    if lowerName == "map" or lowerName == "workspace" or lowerName == "camera" then
        return false
    end

    -- Se possuir Humanoid, verifica se ainda está vivo
    local hum = objeto:FindFirstChildOfClass("Humanoid") or (objeto:IsA("Model") and objeto:FindFirstChildWhichIsA("Humanoid", true))
    if hum and hum.Health <= 0 then
        return false
    end

    -- Filtro de equipe
    if teamCheck and self.LocalPlayer and self.LocalPlayer.Team then
        local otherPlayer = Players:GetPlayerFromCharacter(objeto)
        if otherPlayer and otherPlayer.Team == self.LocalPlayer.Team then
            return false
        end
    end

    return true
end

-- Resolução Afim de Posição via :GetPivot().Position ou BasePart.Position
function InstanceDetector:ResolvePivotPosition(objeto: Instance, preferredBone: string?): (Vector3?, BasePart?, string)
    if not self:IsValidTarget(objeto) then
        return nil, nil, "None"
    end

    -- Caso 1: Objeto primitivo BasePart
    if objeto:IsA("BasePart") then
        return objeto.Position, objeto, objeto.Name
    end

    -- Caso 2: Objeto Model com hierarquia interna
    local model = objeto :: Model
    local bone = string.lower(preferredBone or SimConfig.Get("TargetRegion") or "head")
    local targetPart: BasePart? = nil
    local label = "Pivot"

    if bone == "head" then
        targetPart = model:FindFirstChild("Head", true) :: BasePart?
            or model:FindFirstChild("head", true) :: BasePart?
        label = "Head"
    elseif bone == "torso" or bone == "uppertorso" then
        targetPart = model:FindFirstChild("UpperTorso", true) :: BasePart?
            or model:FindFirstChild("Torso", true) :: BasePart?
            or model:FindFirstChild("LowerTorso", true) :: BasePart?
        label = "Torso"
    elseif bone == "arms" then
        targetPart = model:FindFirstChild("RightUpperArm", true) :: BasePart?
            or model:FindFirstChild("RightArm", true) :: BasePart?
            or model:FindFirstChild("LeftUpperArm", true) :: BasePart?
            or model:FindFirstChild("LeftArm", true) :: BasePart?
        label = "Arms"
    elseif bone == "legs" then
        targetPart = model:FindFirstChild("RightUpperLeg", true) :: BasePart?
            or model:FindFirstChild("RightLeg", true) :: BasePart?
            or model:FindFirstChild("LeftUpperLeg", true) :: BasePart?
            or model:FindFirstChild("LeftLeg", true) :: BasePart?
        label = "Legs"
    end

    if not targetPart then
        targetPart = model.PrimaryPart
            or model:FindFirstChild("HumanoidRootPart", true) :: BasePart?
            or model:FindFirstChild("Head", true) :: BasePart?
            or model:FindFirstChild("Torso", true) :: BasePart?
            or model:FindFirstChildWhichIsA("BasePart", true)
        if targetPart then
            label = targetPart.Name
        end
    end

    if targetPart then
        return targetPart.Position, targetPart, label
    end

    -- Fallback Invariante de Centro de Massa: :GetPivot().Position
    local ok, pivot = pcall(function() return model:GetPivot() end)
    if ok and pivot then
        return pivot.Position, nil, "Pivot"
    end

    return nil, nil, "None"
end

-- Varredura Espacial Desacoplada
function InstanceDetector:ScanCandidates(teamCheck: boolean?, forceRescan: boolean?): { Instance }
    local now = os.clock()
    if not forceRescan and (now - self.LastScanTime < self.ScanInterval) and #self.CandidatePool > 0 then
        local verified: { Instance } = {}
        for _, cand in ipairs(self.CandidatePool) do
            if self:IsValidTarget(cand, teamCheck) then
                table.insert(verified, cand)
            end
        end
        self.CandidatePool = verified
        return self.CandidatePool
    end

    self.LastScanTime = now
    local newPool: { Instance } = {}
    local seen: { [Instance]: boolean } = {}

    local function Ingest(inst: Instance)
        if self:IsValidTarget(inst, teamCheck) and not seen[inst] then
            seen[inst] = true
            table.insert(newPool, inst)
        end
    end

    -- 1. Jogadores
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= self.LocalPlayer and p.Character then
            Ingest(p.Character)
        end
    end

    -- 2. Pastas organizacionais
    for _, folderName in ipairs(self.SearchFolders) do
        local container = Workspace:FindFirstChild(folderName)
        if container then
            for _, child in ipairs(container:GetChildren()) do
                if child:IsA("Model") or child:IsA("BasePart") then Ingest(child) end
            end
            for _, desc in ipairs(container:GetDescendants()) do
                if desc:IsA("Model") or desc:IsA("BasePart") then Ingest(desc) end
            end
        end
    end

    -- 3. CollectionService Tags
    local okCs, CollectionService = pcall(function() return game:GetService("CollectionService") end)
    if okCs and CollectionService then
        for _, tag in ipairs(self.KnownTags) do
            for _, tagged in ipairs(CollectionService:GetTagged(tag)) do
                if tagged:IsA("Model") or tagged:IsA("BasePart") then Ingest(tagged) end
            end
        end
    end

    -- 4. Filhos da raiz do Workspace
    for _, child in ipairs(Workspace:GetChildren()) do
        if child:IsA("Model") then
            local hasHum = child:FindFirstChildOfClass("Humanoid")
            local name = child.Name:lower()
            if hasHum or name:find("dummy") or name:find("npc") or name:find("enemy") or name:find("target") or name:find("bot") then
                Ingest(child)
            end
        elseif child:IsA("BasePart") then
            local name = child.Name:lower()
            if name:find("target") or name:find("dummy") or name:find("hitbox") then
                Ingest(child)
            end
        end
    end

    self.CandidatePool = newPool
    return self.CandidatePool
end

-- =========================================================================
-- [3/5] MODULO: VectorTracker (Motor de Rotação e Interpolação Vetorial)
-- =========================================================================
local VectorTracker = {}
VectorTracker.__index = VectorTracker

local EPSILON = 1e-4

function VectorTracker.new(initialCFrame: CFrame?, filterInstances: { Instance }?)
    local self = setmetatable({}, VectorTracker)
    self.CurrentCFrame = initialCFrame or CFrame.new(0, 5, 0)
    self.PreviousLookVector = self.CurrentCFrame.LookVector
    self.PreviousAngularVelocity = 0
    self.NoiseSeed = math.random(1000, 9999)
    self.VelocityCache = setmetatable({}, { __mode = "k" }) :: { [Instance]: { pos: Vector3, time: number, vel: Vector3 } }

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = filterInstances or {}
    rayParams.IgnoreWater = true
    self.RayParams = rayParams

    self.CachedTelemetry = {
        angularVelocity = 0,
        angularJerk = 0,
        suspicionScore = 0,
        isObstructed = false,
        position = Vector3.zero,
        cframe = self.CurrentCFrame,
        mode = "SMOOTH",
        angularErrorDeg = 0,
        predictedPosition = Vector3.zero
    }

    self.MetricsHistory = {
        totalSamples = 0,
        sumVelocity = 0,
        peakVelocity = 0,
        snapCount = 0,
        obstructedCount = 0
    }

    return self
end

function VectorTracker:SetFilterInstances(instances: { Instance })
    self.RayParams.FilterDescendantsInstances = instances
end

function VectorTracker:CheckObstruction(fromPos: Vector3, toPos: Vector3): boolean
    local dir = (toPos - fromPos)
    local dist = dir.Magnitude
    if dist < EPSILON then return false end
    return (Workspace:Raycast(fromPos, (dir / dist) * dist, self.RayParams) ~= nil)
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

function VectorTracker:ComputeLead(targetPos: Vector3, targetVelocity: Vector3, eyePos: Vector3): Vector3
    if not SimConfig.Get("EnableLead") then
        return targetPos
    end
    local projSpeed = SimConfig.Get("ProjectileSpeed") or 800.0
    local dist = (targetPos - eyePos).Magnitude
    local timeToHit = projSpeed > 0 and (dist / projSpeed) or 0
    return targetPos + (targetVelocity * timeToHit)
end

function VectorTracker:EvaluateSuspicion(angVel: number, jerk: number, isSnap: boolean, obstructed: boolean): number
    local score = 0
    if isSnap then score = score + 45 end
    if angVel > 350 then score = score + math.clamp((angVel - 350) / 10, 0, 30) end
    if jerk > 4000 then score = score + 15 end
    if obstructed and angVel > 20 then score = score + 10 end
    return math.clamp(math.floor(score), 0, 100)
end

function VectorTracker:StepSnap(rawTargetPosition: Vector3, targetVelocity: Vector3, dt: number)
    local eyePos = Camera.CFrame.Position
    local targetPosition = self:ComputeLead(rawTargetPosition, targetVelocity, eyePos)
    local toTarget = (targetPosition - eyePos)
    local dist = toTarget.Magnitude

    if dist < EPSILON then return self.CachedTelemetry end

    local dirToTarget = toTarget / dist
    local dot = math.clamp(self.CurrentCFrame.LookVector:Dot(dirToTarget), -1.0, 1.0)
    local angularErrorDeg = math.deg(math.acos(dot))

    self.CurrentCFrame = CFrame.lookAt(eyePos, targetPosition, Vector3.yAxis)
    local safeDt = (dt and dt > 0) and dt or 0.0166
    local angVel = angularErrorDeg / safeDt
    local jerk = math.abs(angVel - self.PreviousAngularVelocity) / safeDt
    self.PreviousAngularVelocity = angVel

    local isObstructed = self:CheckObstruction(eyePos, targetPosition)
    local suspicion = self:EvaluateSuspicion(angVel, jerk, true, isObstructed)

    self.MetricsHistory.totalSamples = self.MetricsHistory.totalSamples + 1
    self.MetricsHistory.sumVelocity = self.MetricsHistory.sumVelocity + angVel
    self.MetricsHistory.peakVelocity = math.max(self.MetricsHistory.peakVelocity, angVel)
    self.MetricsHistory.snapCount = self.MetricsHistory.snapCount + 1
    if isObstructed then self.MetricsHistory.obstructedCount = self.MetricsHistory.obstructedCount + 1 end

    self.CachedTelemetry.angularVelocity = angVel
    self.CachedTelemetry.angularJerk = jerk
    self.CachedTelemetry.suspicionScore = suspicion
    self.CachedTelemetry.isObstructed = isObstructed
    self.CachedTelemetry.position = eyePos
    self.CachedTelemetry.cframe = self.CurrentCFrame
    self.CachedTelemetry.mode = "SNAP"
    self.CachedTelemetry.angularErrorDeg = 0
    self.CachedTelemetry.predictedPosition = targetPosition
    self.PreviousLookVector = self.CurrentCFrame.LookVector
    return self.CachedTelemetry
end

function VectorTracker:StepSmooth(rawTargetPosition: Vector3, targetVelocity: Vector3, dt: number)
    local eyePos = Camera.CFrame.Position
    self.CurrentCFrame = Camera.CFrame
    local targetPosition = self:ComputeLead(rawTargetPosition, targetVelocity, eyePos)
    local toTarget = (targetPosition - eyePos)
    local dist = toTarget.Magnitude

    -- PREVENÇÃO DE NaN: Guarda Epsilon estrita
    if dist < EPSILON then return self.CachedTelemetry end

    local dirToTarget = toTarget / dist
    local dot = math.clamp(self.CurrentCFrame.LookVector:Dot(dirToTarget), -1.0, 1.0)
    local angularErrorDeg = math.deg(math.acos(dot))

    local fov = math.max(SimConfig.Get("FOV") or 60.0, 1.0)
    local baseSmoothing = math.clamp(SimConfig.Get("Smoothing") or 0.15, 0.005, 1.0)
    local speedMult = math.clamp((SimConfig.Get("MoveSpeed") or 16.0) / 16.0, 0.25, 3.0)
    local precision = math.clamp((SimConfig.Get("TrackingPrecision") or 98.5) / 100.0, 0.5, 1.0)
    local intensity = math.clamp((SimConfig.Get("Intensity") or 75.0) / 100.0, 0.0, 2.0)
    local maxRadius = SimConfig.Get("VectorRadius") or 300.0

    if dist > maxRadius or angularErrorDeg > fov then
        self.CachedTelemetry.angularVelocity = 0
        self.CachedTelemetry.angularJerk = 0
        self.CachedTelemetry.suspicionScore = 0
        self.CachedTelemetry.isObstructed = self:CheckObstruction(eyePos, targetPosition)
        self.CachedTelemetry.position = eyePos
        self.CachedTelemetry.cframe = self.CurrentCFrame
        self.CachedTelemetry.mode = "IDLE"
        self.CachedTelemetry.angularErrorDeg = angularErrorDeg
        self.CachedTelemetry.predictedPosition = targetPosition
        return self.CachedTelemetry
    end

    -- Curva Hermite Smoothstep com expoente de gradiente
    local normalizedErr = math.clamp(angularErrorDeg / fov, 0.0, 1.0)
    local smoothFactor = normalizedErr * normalizedErr * (3.0 - 2.0 * normalizedErr)
    local accelExponent = SimConfig.Get("AccelerationCurve") or 1.25
    smoothFactor = math.pow(smoothFactor, accelExponent)

    -- Interpolação Angular Contínua via Decaimento Exponencial (Sem Jittering e Independente de FPS)
    local safeDt = math.clamp(dt or 0.0166, 0.0001, 0.1)
    local k = (baseSmoothing * 28.0 * speedMult) * (0.35 + 0.65 * smoothFactor)
    local dynamicAlpha = math.clamp(1.0 - math.exp(-k * safeDt), 0.001, 1.0)

    local targetRotation = CFrame.lookAt(eyePos, targetPosition, Vector3.yAxis)
    local smoothedRotation = self.CurrentCFrame:Lerp(targetRotation, dynamicAlpha)

    -- Jitter orgânico sutil
    local jitterAmplitude = (1.0 - precision) * intensity * 0.4 * math.clamp(angularErrorDeg / 10.0, 0.0, 1.0)
    if jitterAmplitude > 0.0001 then
        local now = os.clock()
        local noiseFreq = 3.5 * intensity
        local pitchJitter = math.rad(math.noise(now * noiseFreq, self.NoiseSeed, 0.5) * jitterAmplitude)
        local yawJitter = math.rad(math.noise(now * noiseFreq, self.NoiseSeed + 100, 0.5) * jitterAmplitude)
        self.CurrentCFrame = smoothedRotation * CFrame.Angles(pitchJitter, yawJitter, 0)
    else
        self.CurrentCFrame = smoothedRotation
    end

    local actualDir = self.CurrentCFrame.LookVector
    local actualDot = math.clamp(self.PreviousLookVector:Dot(actualDir), -1.0, 1.0)
    local actualDegMoved = math.deg(math.acos(actualDot))
    local angVel = actualDegMoved / safeDt
    local jerk = math.abs(angVel - self.PreviousAngularVelocity) / safeDt
    self.PreviousAngularVelocity = angVel
    self.PreviousLookVector = actualDir

    local isObstructed = self:CheckObstruction(eyePos, targetPosition)
    local suspicion = self:EvaluateSuspicion(angVel, jerk, false, isObstructed)

    self.MetricsHistory.totalSamples = self.MetricsHistory.totalSamples + 1
    self.MetricsHistory.sumVelocity = self.MetricsHistory.sumVelocity + angVel
    self.MetricsHistory.peakVelocity = math.max(self.MetricsHistory.peakVelocity, angVel)
    if isObstructed then self.MetricsHistory.obstructedCount = self.MetricsHistory.obstructedCount + 1 end

    self.CachedTelemetry.angularVelocity = angVel
    self.CachedTelemetry.angularJerk = jerk
    self.CachedTelemetry.suspicionScore = suspicion
    self.CachedTelemetry.isObstructed = isObstructed
    self.CachedTelemetry.position = eyePos
    self.CachedTelemetry.cframe = self.CurrentCFrame
    self.CachedTelemetry.mode = "SMOOTH"
    self.CachedTelemetry.angularErrorDeg = angularErrorDeg
    self.CachedTelemetry.predictedPosition = targetPosition
    return self.CachedTelemetry
end

function VectorTracker:ExportReport()
    local hist = self.MetricsHistory
    local avg = hist.totalSamples > 0 and (hist.sumVelocity / hist.totalSamples) or 0
    print("=======================================================")
    print("          RELATORIO DE TELEMETRIA DE AGENTE 3D         ")
    print("=======================================================")
    print(string.format("  Total de Quadros Amostrados: %d", hist.totalSamples))
    print(string.format("  Velocidade Angular Media:    %.2f deg/s", avg))
    print(string.format("  Pico de Velocidade Angular:  %.2f deg/s", hist.peakVelocity))
    print(string.format("  Transicoes Snap (Agressivas):%d", hist.snapCount))
    print(string.format("  Oclusoes Detectadas (Paredes):%d", hist.obstructedCount))
    print("=======================================================")
end

local AdvancedKinematics = VectorTracker

-- =========================================================================
-- [4/5] MODULO: VisualOverlayRenderer (Realce Visual e Highlight Pooling)
-- =========================================================================
local VisualOverlayRenderer = {}
VisualOverlayRenderer.__index = VisualOverlayRenderer

local MAX_ACTIVE_HIGHLIGHTS = 16

do
    local activeHighlights = setmetatable({}, { __mode = "k" }) :: { [Instance]: Highlight }
    local highlightContainer: Folder? = nil

    local function GetHighlightContainer(): Folder
        if highlightContainer and highlightContainer.Parent then
            return highlightContainer
        end

        local host: Instance = CoreGuiService
        local okCore = pcall(function() return CoreGuiService:GetChildren() end)
        if not okCore then
            local pGui = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
            host = pGui or Workspace
        end

        local existing = host:FindFirstChild("DeepHat_ESP_Container")
        if existing and existing:IsA("Folder") then
            highlightContainer = existing
            return existing
        end

        local folder = Instance.new("Folder")
        folder.Name = "DeepHat_ESP_Container"
        folder.Parent = host
        highlightContainer = folder
        return folder
    end

    local function GetOrCreateHighlight(target: Instance?): Highlight?
        if not target or not target:IsDescendantOf(game) then return nil end
        local hl = activeHighlights[target]
        if not hl or not hl.Parent then
            local count = 0
            for _, _ in pairs(activeHighlights) do count = count + 1 end
            if count >= MAX_ACTIVE_HIGHLIGHTS then
                for oldTarget, oldHl in pairs(activeHighlights) do
                    if not oldTarget:IsDescendantOf(game) then
                        pcall(function() oldHl:Destroy() end)
                        activeHighlights[oldTarget] = nil
                        break
                    end
                end
            end

            local ok, newHl = pcall(function()
                local container = GetHighlightContainer()
                local inst = Instance.new("Highlight")
                inst.Name = "HL_" .. target.Name
                inst.Adornee = target
                inst.FillTransparency = 0.55
                inst.OutlineTransparency = 0.05
                inst.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                inst.Enabled = true
                inst.Parent = container
                return inst
            end)
            if ok and newHl then
                hl = newHl
                activeHighlights[target] = hl
            end
        end
        return hl
    end

    function VisualOverlayRenderer.UpdateTarget(target: Instance?, isObstructed: boolean, isMainTarget: boolean)
        if not target or not target:IsDescendantOf(game) or not SimConfig.Get("EnableESP") then
            VisualOverlayRenderer.Clear(target)
            return
        end

        local hl = GetOrCreateHighlight(target)
        if not hl then return end

        pcall(function()
            hl.Adornee = target
            hl.Enabled = true
            if isMainTarget then
                if isObstructed then
                    hl.FillColor = Color3.fromRGB(255, 45, 45)
                    hl.OutlineColor = Color3.fromRGB(255, 180, 180)
                else
                    hl.FillColor = Color3.fromRGB(46, 230, 110)
                    hl.OutlineColor = Color3.fromRGB(200, 255, 200)
                end
                hl.FillTransparency = 0.35
                hl.OutlineTransparency = 0.02
            else
                hl.FillColor = isObstructed and Color3.fromRGB(180, 70, 70) or Color3.fromRGB(50, 140, 230)
                hl.OutlineColor = Color3.fromRGB(240, 240, 240)
                hl.FillTransparency = 0.65
                hl.OutlineTransparency = 0.20
            end
        end)
    end

    function VisualOverlayRenderer.Clear(target: Instance?)
        if not target then return end
        pcall(function()
            local hl = activeHighlights[target]
            if hl then pcall(function() hl:Destroy() end) end
            activeHighlights[target] = nil
        end)
    end

    function VisualOverlayRenderer.ClearAll()
        for _, hl in pairs(activeHighlights) do
            pcall(function() if hl then hl:Destroy() end end)
        end
        table.clear(activeHighlights)
    end
end

local ESPVisualizer = VisualOverlayRenderer
-- [4/5] MODULO: DashboardGUI (Interface Profissional Dark Theme 3-Colunas)
-- =========================================================================
local DashboardGUI = {}
DashboardGUI.__index = DashboardGUI

-- [PALETA DE DESIGN TOKENS]
local THEME = {
    BG_MAIN = Color3.fromRGB(13, 14, 18),
    BG_PANEL = Color3.fromRGB(19, 21, 26),
    BG_INPUT = Color3.fromRGB(25, 28, 35),
    BORDER = Color3.fromRGB(36, 40, 50),
    TEXT_MAIN = Color3.fromRGB(240, 240, 240),
    TEXT_MUTED = Color3.fromRGB(120, 128, 142),
    ACCENT_RED = Color3.fromRGB(224, 43, 54),
    ACCENT_HOVER = Color3.fromRGB(255, 65, 75),
    SUCCESS = Color3.fromRGB(46, 204, 113),
}

DashboardGUI.OnStartRequested = nil :: (() -> ())?
DashboardGUI.OnStopRequested = nil :: (() -> ())?
DashboardGUI.OnResetRequested = nil :: (() -> ())?
DashboardGUI.OnSaveRequested = nil :: (() -> ())?

local function AddCorner(parent: Instance, radius: number): UICorner
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    corner.Parent = parent
    return corner
end

local function AddStroke(parent: Instance, color: Color3, thickness: number?): UIStroke
    local stroke = Instance.new("UIStroke")
    stroke.Color = color
    stroke.Thickness = thickness or 1
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = parent
    return stroke
end

function DashboardGUI.Create(parentGui: Instance?): ScreenGui
    local function GetSafeGuiParent(): Instance
        local okHui, hui = pcall(function() return (gethui and gethui()) end)
        if okHui and hui then return hui end

        local okCore, coreGui = pcall(function() return game:GetService("CoreGui") end)
        if okCore and coreGui then
            local testOk = pcall(function()
                local test = Instance.new("Folder")
                test.Parent = coreGui
                test:Destroy()
            end)
            if testOk then return coreGui end
        end
        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 5)
        if playerGui then return playerGui end
        return CoreGuiService
    end

    local hostParent = parentGui or GetSafeGuiParent()

    -- Destruição Total Prévia da Interface Antiga em todos os contêineres possíveis
    local targetUINames = { "DiagnosticSimulationDashboard", "KinematicsSimulationDashboard", "DeepHat_GUI", "DeepHat_Dashboard_Pro" }
    local cleanupContainers = { hostParent }
    pcall(function() table.insert(cleanupContainers, game:GetService("CoreGui")) end)
    if LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui") then
        table.insert(cleanupContainers, LocalPlayer:FindFirstChildOfClass("PlayerGui"))
    end
    for _, cont in ipairs(cleanupContainers) do
        for _, uiName in ipairs(targetUINames) do
            local found = cont:FindFirstChild(uiName)
            while found do
                pcall(function() found:Destroy() end)
                found = cont:FindFirstChild(uiName)
            end
        end
    end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "DiagnosticSimulationDashboard"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = hostParent

    -- Circulo Dinamico de FOV na Tela
    local fovCircle = Instance.new("Frame")
    fovCircle.Name = "FovCircleOverlay"
    fovCircle.AnchorPoint = Vector2.new(0.5, 0.5)
    fovCircle.Position = UDim2.new(0.5, 0, 0.5, 0)
    fovCircle.BackgroundTransparency = 1
    fovCircle.Visible = SimConfig.Get("ShowFovCircle") == true
    fovCircle.Parent = screenGui
    AddCorner(fovCircle, 9999)
    local fovStroke = AddStroke(fovCircle, THEME.ACCENT_RED, 1.5)
    fovStroke.Transparency = 0.35

    local fovCenterDot = Instance.new("Frame")
    fovCenterDot.Size = UDim2.new(0, 4, 0, 4)
    fovCenterDot.AnchorPoint = Vector2.new(0.5, 0.5)
    fovCenterDot.Position = UDim2.new(0.5, 0, 0.5, 0)
    fovCenterDot.BackgroundColor3 = THEME.ACCENT_RED
    fovCenterDot.BackgroundTransparency = 0.2
    fovCenterDot.Parent = fovCircle
    AddCorner(fovCenterDot, 2)

    -- Janela Principal (Compacta, 3 Colunas, Draggable)
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.new(0, 880, 0, 520)
    mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    mainFrame.BackgroundColor3 = THEME.BG_MAIN
    mainFrame.BorderSizePixel = 0
    mainFrame.Active = true
    mainFrame.Parent = screenGui
    AddCorner(mainFrame, 8)
    AddStroke(mainFrame, THEME.BORDER, 1.5)

    -- Sistema de Arrastar (Drag) pelo Header
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 40)
    header.BackgroundColor3 = THEME.BG_PANEL
    header.BorderSizePixel = 0
    header.Parent = mainFrame
    AddCorner(header, 8)

    local isDragging = false
    local dragStartPos = Vector2.zero
    local frameStartPos = UDim2.new(0.5, 0, 0.5, 0)

    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            isDragging = true
            dragStartPos = Vector2.new(input.Position.X, input.Position.Y)
            frameStartPos = mainFrame.Position
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            isDragging = false
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if isDragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStartPos
            mainFrame.Position = UDim2.new(
                frameStartPos.X.Scale,
                frameStartPos.X.Offset + delta.X,
                frameStartPos.Y.Scale,
                frameStartPos.Y.Offset + delta.Y
            )
        end
    end)

    -- Titulo e Botoes de Janela
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(0.65, 0, 1, 0)
    title.Position = UDim2.new(0, 14, 0, 0)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.TextSize = 12
    title.TextColor3 = THEME.TEXT_MAIN
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Text = "SIMULATION DIAGNOSTICS // VIRTUAL TEST RIG [CONTROL UNIT]"
    title.Parent = header

    local hotkeyNotice = Instance.new("TextLabel")
    hotkeyNotice.Size = UDim2.new(0, 150, 1, 0)
    hotkeyNotice.Position = UDim2.new(1, -195, 0, 0)
    hotkeyNotice.BackgroundTransparency = 1
    hotkeyNotice.Font = Enum.Font.GothamMedium
    hotkeyNotice.TextSize = 10
    hotkeyNotice.TextColor3 = THEME.TEXT_MUTED
    hotkeyNotice.TextXAlignment = Enum.TextXAlignment.Right
    hotkeyNotice.Text = "[HOME] Ocultar / Exibir"
    hotkeyNotice.Parent = header

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 26, 0, 26)
    closeBtn.Position = UDim2.new(1, -34, 0.5, -13)
    closeBtn.BackgroundColor3 = THEME.BG_INPUT
    closeBtn.TextColor3 = THEME.TEXT_MAIN
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 12
    closeBtn.Text = "✕"
    closeBtn.Parent = header
    AddCorner(closeBtn, 4)

    closeBtn.MouseButton1Click:Connect(function()
        mainFrame.Visible = not mainFrame.Visible
    end)

    -- Alternar visibilidade via teclado (Home ou RightShift)
    UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.KeyCode == Enum.KeyCode.Home or input.KeyCode == Enum.KeyCode.RightShift then
            mainFrame.Visible = not mainFrame.Visible
        end
    end)

    -- Container do Conteudo em 3 Colunas
    local contentArea = Instance.new("Frame")
    contentArea.Size = UDim2.new(1, -20, 1, -100)
    contentArea.Position = UDim2.new(0, 10, 0, 48)
    contentArea.BackgroundTransparency = 1
    contentArea.Parent = mainFrame

    local grid = Instance.new("UIGridLayout")
    grid.CellSize = UDim2.new(0.322, 0, 1, 0)
    grid.CellPadding = UDim2.new(0.017, 0, 0, 0)
    grid.SortOrder = Enum.SortOrder.LayoutOrder
    grid.Parent = contentArea

    -- Tabelas de rastreamento para o Observer
    local syncInputs: { [string]: { Input: TextBox, UpdateRatio: (number) -> () } } = {}

    --[[
        Componente de Slider com Input Numerico Sincronizado (Sem sobreposicao)
    --]]
    local function CreateSliderField(parent: Instance, labelText: string, configKey: string, minVal: number, maxVal: number, defaultVal: number, step: number, layoutOrder: number?): Frame
        minVal = tonumber(minVal) or 0
        maxVal = tonumber(maxVal) or 100
        step = tonumber(step) or 1
        if step <= 0 then step = 1 end
        local safeDefault = tonumber(defaultVal) or tonumber(SimConfig.Get(configKey)) or minVal
        local span = math.max(maxVal - minVal, 0.0001)

        local container = Instance.new("Frame")
        container.Name = "Slider_" .. configKey
        container.Size = UDim2.new(1, 0, 0, 42)
        container.BackgroundTransparency = 1
        container.LayoutOrder = layoutOrder or 10
        container.Parent = parent

        local headerRow = Instance.new("Frame")
        headerRow.Size = UDim2.new(1, 0, 0, 18)
        headerRow.BackgroundTransparency = 1
        headerRow.Parent = container

        -- Titulo à esquerda (nunca se sobrepoe)
        local titleLabel = Instance.new("TextLabel")
        titleLabel.Size = UDim2.new(1, -55, 1, 0)
        titleLabel.Position = UDim2.new(0, 0, 0, 0)
        titleLabel.BackgroundTransparency = 1
        titleLabel.Font = Enum.Font.GothamMedium
        titleLabel.TextSize = 11
        titleLabel.TextColor3 = THEME.TEXT_MAIN
        titleLabel.TextXAlignment = Enum.TextXAlignment.Left
        titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
        titleLabel.Text = labelText
        titleLabel.Parent = headerRow

        -- Input numerico à direita (badge compacto de alta precisao)
        local inputBox = Instance.new("TextBox")
        inputBox.Size = UDim2.new(0, 50, 1, 0)
        inputBox.Position = UDim2.new(1, -50, 0, 0)
        inputBox.BackgroundColor3 = THEME.BG_INPUT
        inputBox.TextColor3 = THEME.ACCENT_RED
        inputBox.Font = Enum.Font.GothamBold
        inputBox.TextSize = 11
        inputBox.Text = string.format(step < 1 and "%.2f" or "%d", safeDefault)
        inputBox.ClearTextOnFocus = false
        inputBox.Parent = headerRow
        AddCorner(inputBox, 4)
        AddStroke(inputBox, THEME.BORDER, 1)

        -- Barra do Slider (Trilho)
        local track = Instance.new("Frame")
        track.Size = UDim2.new(1, 0, 0, 6)
        track.Position = UDim2.new(0, 0, 0, 24)
        track.BackgroundColor3 = THEME.BG_INPUT
        track.Parent = container
        AddCorner(track, 3)

        local progress = Instance.new("Frame")
        local initialRatio = math.clamp((safeDefault - minVal) / span, 0, 1)
        progress.Size = UDim2.new(initialRatio, 0, 1, 0)
        progress.BackgroundColor3 = THEME.ACCENT_RED
        progress.BorderSizePixel = 0
        progress.Parent = track
        AddCorner(progress, 3)

        local knob = Instance.new("Frame")
        knob.Size = UDim2.new(0, 12, 0, 12)
        knob.AnchorPoint = Vector2.new(0.5, 0.5)
        knob.Position = UDim2.new(1, 0, 0.5, 0)
        knob.BackgroundColor3 = THEME.TEXT_MAIN
        knob.Parent = progress
        AddCorner(knob, 6)

        local isSliderDragging = false

        local function applyVal(val: number, fromConfig: boolean?)
            val = tonumber(val) or safeDefault
            val = math.clamp(val, minVal, maxVal)
            val = math.round(val / step) * step
            local ratio = math.clamp((val - minVal) / span, 0, 1)
            progress.Size = UDim2.new(ratio, 0, 1, 0)
            inputBox.Text = string.format(step < 1 and "%.2f" or "%d", val)
            if not fromConfig then
                SimConfig.Set(configKey, val)
            end
        end

        inputBox.FocusLost:Connect(function()
            local num = tonumber(inputBox.Text)
            if num then
                applyVal(num)
            else
                local fallback = tonumber(SimConfig.Get(configKey)) or safeDefault
                inputBox.Text = string.format(step < 1 and "%.2f" or "%d", fallback)
            end
        end)

        track.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                isSliderDragging = true
                local trackWidth = math.max(track.AbsoluteSize.X, 1)
                local relX = math.clamp((input.Position.X - track.AbsolutePosition.X) / trackWidth, 0, 1)
                applyVal(minVal + relX * (maxVal - minVal))
            end
        end)

        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                isSliderDragging = false
            end
        end)

        UserInputService.InputChanged:Connect(function(input)
            if isSliderDragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                local trackWidth = math.max(track.AbsoluteSize.X, 1)
                local relX = math.clamp((input.Position.X - track.AbsolutePosition.X) / trackWidth, 0, 1)
                applyVal(minVal + relX * (maxVal - minVal))
            end
        end)

        syncInputs[configKey] = {
            Input = inputBox,
            UpdateRatio = function(newVal: number)
                applyVal(newVal, true)
            end
        }

        return container
    end

    -- =========================================================================
    -- COLUNA 1: Configuracoes de Vetores e Direcao
    -- =========================================================================
    local col1 = Instance.new("ScrollingFrame")
    col1.Name = "Col1_Vectors"
    col1.BackgroundColor3 = THEME.BG_PANEL
    col1.ScrollBarThickness = 3
    col1.ScrollBarImageColor3 = THEME.BORDER
    col1.CanvasSize = UDim2.new(0, 0, 0, 0)
    col1.AutomaticCanvasSize = Enum.AutomaticSize.Y
    col1.Parent = contentArea
    AddCorner(col1, 6)
    AddStroke(col1, THEME.BORDER, 1)

    local list1 = Instance.new("UIListLayout")
    list1.Padding = UDim.new(0, 8)
    list1.SortOrder = Enum.SortOrder.LayoutOrder
    list1.Parent = col1

    local pad1 = Instance.new("UIPadding")
    pad1.PaddingTop = UDim.new(0, 10); pad1.PaddingBottom = UDim.new(0, 10)
    pad1.PaddingLeft = UDim.new(0, 10); pad1.PaddingRight = UDim.new(0, 10)
    pad1.Parent = col1

    local col1Title = Instance.new("TextLabel")
    col1Title.Name = "00_Title"
    col1Title.LayoutOrder = 1
    col1Title.Size = UDim2.new(1, 0, 0, 18)
    col1Title.BackgroundTransparency = 1
    col1Title.Font = Enum.Font.GothamBold
    col1Title.TextSize = 11
    col1Title.TextColor3 = THEME.ACCENT_RED
    col1Title.TextXAlignment = Enum.TextXAlignment.Left
    col1Title.Text = "01 // VETORES E DIREÇÃO"
    col1Title.Parent = col1

    -- Toggle de Ativacao
    local toggleRow = Instance.new("Frame")
    toggleRow.Name = "01_ToggleRow"
    toggleRow.LayoutOrder = 2
    toggleRow.Size = UDim2.new(1, 0, 0, 28)
    toggleRow.BackgroundTransparency = 1
    toggleRow.Parent = col1

    local toggleLbl = Instance.new("TextLabel")
    toggleLbl.Size = UDim2.new(0.75, 0, 1, 0)
    toggleLbl.BackgroundTransparency = 1
    toggleLbl.Font = Enum.Font.GothamMedium
    toggleLbl.TextSize = 11
    toggleLbl.TextColor3 = THEME.TEXT_MAIN
    toggleLbl.TextXAlignment = Enum.TextXAlignment.Left
    toggleLbl.Text = "Ativar Módulo de Simulação"
    toggleLbl.Parent = toggleRow

    local toggleBtn = Instance.new("TextButton")
    toggleBtn.Size = UDim2.new(0, 40, 0, 20)
    toggleBtn.Position = UDim2.new(1, -40, 0.5, -10)
    toggleBtn.BackgroundColor3 = SimConfig.Get("SimulationActive") and THEME.ACCENT_RED or THEME.BG_INPUT
    toggleBtn.Text = ""
    toggleBtn.AutoButtonColor = false
    toggleBtn.Parent = toggleRow
    AddCorner(toggleBtn, 10)
    AddStroke(toggleBtn, THEME.BORDER, 1)

    local toggleDot = Instance.new("Frame")
    toggleDot.Size = UDim2.new(0, 14, 0, 14)
    toggleDot.Position = SimConfig.Get("SimulationActive") and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7)
    toggleDot.BackgroundColor3 = THEME.TEXT_MAIN
    toggleDot.Parent = toggleBtn
    AddCorner(toggleDot, 7)

    toggleBtn.MouseButton1Click:Connect(function()
        local newState = not SimConfig.Get("SimulationActive")
        SimConfig.Set("SimulationActive", newState)
        toggleBtn.BackgroundColor3 = newState and THEME.ACCENT_RED or THEME.BG_INPUT
        toggleDot.Position = newState and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7)
        if newState then
            if DashboardGUI.OnStartRequested then DashboardGUI.OnStartRequested() end
        else
            if DashboardGUI.OnStopRequested then DashboardGUI.OnStopRequested() end
        end
    end)

    CreateSliderField(col1, "Ângulo de Campo (FOV °)", "FOV", 10, 180, SimConfig.Get("FOV"), 1, 3)
    CreateSliderField(col1, "Coeficiente de Suavização", "Smoothing", 0.01, 1.0, SimConfig.Get("Smoothing"), 0.01, 4)
    CreateSliderField(col1, "Velocidade Rotação (°/s)", "AngularVelocity", 30, 720, SimConfig.Get("AngularVelocity"), 5, 5)
    CreateSliderField(col1, "Tempo de Resposta (ms)", "ResponseTime", 0, 250, SimConfig.Get("ResponseTime"), 1, 6)
    CreateSliderField(col1, "Precisão de Trajetória (%)", "TrajectoryPrecision", 50, 100, SimConfig.Get("TrajectoryPrecision"), 0.5, 7)
    CreateSliderField(col1, "Frequência Atualização (Hz)", "UpdateFrequency", 10, 144, SimConfig.Get("UpdateFrequency"), 5, 8)
    CreateSliderField(col1, "Raio de Atuação (m)", "VectorRadius", 10, 500, SimConfig.Get("VectorRadius"), 5, 9)

    -- =========================================================================
    -- COLUNA 2: Parametros de Comportamento do Sistema
    -- =========================================================================
    local col2 = Instance.new("ScrollingFrame")
    col2.Name = "Col2_Behavior"
    col2.BackgroundColor3 = THEME.BG_PANEL
    col2.ScrollBarThickness = 3
    col2.ScrollBarImageColor3 = THEME.BORDER
    col2.CanvasSize = UDim2.new(0, 0, 0, 0)
    col2.AutomaticCanvasSize = Enum.AutomaticSize.Y
    col2.Parent = contentArea
    AddCorner(col2, 6)
    AddStroke(col2, THEME.BORDER, 1)

    local list2 = Instance.new("UIListLayout")
    list2.Padding = UDim.new(0, 8)
    list2.SortOrder = Enum.SortOrder.LayoutOrder
    list2.Parent = col2

    local pad2 = Instance.new("UIPadding")
    pad2.PaddingTop = UDim.new(0, 10); pad2.PaddingBottom = UDim.new(0, 10)
    pad2.PaddingLeft = UDim.new(0, 10); pad2.PaddingRight = UDim.new(0, 10)
    pad2.Parent = col2

    local col2Title = Instance.new("TextLabel")
    col2Title.Name = "00_Title"
    col2Title.LayoutOrder = 1
    col2Title.Size = UDim2.new(1, 0, 0, 18)
    col2Title.BackgroundTransparency = 1
    col2Title.Font = Enum.Font.GothamBold
    col2Title.TextSize = 11
    col2Title.TextColor3 = THEME.ACCENT_RED
    col2Title.TextXAlignment = Enum.TextXAlignment.Left
    col2Title.Text = "02 // COMPORTAMENTO"
    col2Title.Parent = col2

    -- Abas de Selecao de Perfil
    local profileBar = Instance.new("Frame")
    profileBar.Name = "01_ProfileBar"
    profileBar.LayoutOrder = 2
    profileBar.Size = UDim2.new(1, 0, 0, 26)
    profileBar.BackgroundColor3 = THEME.BG_INPUT
    profileBar.Parent = col2
    AddCorner(profileBar, 4)

    local profileLayout = Instance.new("UIListLayout")
    profileLayout.FillDirection = Enum.FillDirection.Horizontal
    profileLayout.Parent = profileBar

    local profileButtons: { [string]: TextButton } = {}
    local profiles = { "Normal", "Leve", "Medio", "Agressivo", "Custom" }

    local function UpdateProfileHighlights(activeName: string)
        for name, btn in pairs(profileButtons) do
            btn.BackgroundTransparency = (name == activeName) and 0 or 1
        end
    end

    for _, prof in ipairs(profiles) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1 / #profiles, 0, 1, 0)
        btn.BackgroundTransparency = (prof == SimConfig.Get("ActiveProfile")) and 0 or 1
        btn.BackgroundColor3 = THEME.ACCENT_RED
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 9
        btn.TextColor3 = THEME.TEXT_MAIN
        btn.Text = prof
        btn.Parent = profileBar
        AddCorner(btn, 4)
        profileButtons[prof] = btn

        btn.MouseButton1Click:Connect(function()
            SimConfig.LoadProfile(prof)
            UpdateProfileHighlights(prof)
        end)
    end

    CreateSliderField(col2, "Frequência de Eventos (Hz)", "EventFrequency", 1, 60, SimConfig.Get("EventFrequency"), 1, 3)
    CreateSliderField(col2, "Intensidade de Resposta (%)", "Intensity", 0, 100, SimConfig.Get("Intensity"), 1, 4)
    CreateSliderField(col2, "Velocidade Deslocamento", "MoveSpeed", 8, 40, SimConfig.Get("MoveSpeed"), 1, 5)
    CreateSliderField(col2, "Gradiente de Aceleração", "AccelerationCurve", 0.2, 3.0, SimConfig.Get("AccelerationCurve"), 0.05, 6)
    CreateSliderField(col2, "Duração do Ciclo (s)", "CycleDuration", 5, 120, SimConfig.Get("CycleDuration"), 5, 7)
    CreateSliderField(col2, "Agentes Simultâneos", "SimulatedAgents", 1, 16, SimConfig.Get("SimulatedAgents"), 1, 8)

    -- =========================================================================
    -- COLUNA 3: Mapeamento de Regioes (HitBox Coords) & Telemetria
    -- =========================================================================
    local col3 = Instance.new("Frame")
    col3.Name = "Col3_Coords"
    col3.BackgroundColor3 = THEME.BG_PANEL
    col3.Parent = contentArea
    AddCorner(col3, 6)
    AddStroke(col3, THEME.BORDER, 1)

    local col3Title = Instance.new("TextLabel")
    col3Title.Size = UDim2.new(1, -20, 0, 18)
    col3Title.Position = UDim2.new(0, 10, 0, 10)
    col3Title.BackgroundTransparency = 1
    col3Title.Font = Enum.Font.GothamBold
    col3Title.TextSize = 11
    col3Title.TextColor3 = THEME.ACCENT_RED
    col3Title.TextXAlignment = Enum.TextXAlignment.Left
    col3Title.Text = "03 // MAPEAMENTO DE COORDENADAS"
    col3Title.Parent = col3

    -- Canvas do Manequim / Dummy
    local dummyCanvas = Instance.new("Frame")
    dummyCanvas.Size = UDim2.new(1, -20, 0.48, 0)
    dummyCanvas.Position = UDim2.new(0, 10, 0, 32)
    dummyCanvas.BackgroundColor3 = THEME.BG_INPUT
    dummyCanvas.Parent = col3
    AddCorner(dummyCanvas, 4)
    AddStroke(dummyCanvas, THEME.BORDER, 1)

    -- Esqueleto Wireframe Estilizado
    local spineLine = Instance.new("Frame")
    spineLine.Size = UDim2.new(0, 2, 0.65, 0)
    spineLine.Position = UDim2.new(0.5, -1, 0.15, 0)
    spineLine.BackgroundColor3 = THEME.BORDER
    spineLine.BorderSizePixel = 0
    spineLine.Parent = dummyCanvas

    local shoulderLine = Instance.new("Frame")
    shoulderLine.Size = UDim2.new(0.5, 0, 0, 2)
    shoulderLine.Position = UDim2.new(0.25, 0, 0.35, 0)
    shoulderLine.BackgroundColor3 = THEME.BORDER
    shoulderLine.BorderSizePixel = 0
    shoulderLine.Parent = dummyCanvas

    local legLineL = Instance.new("Frame")
    legLineL.Size = UDim2.new(0, 2, 0.35, 0)
    legLineL.Position = UDim2.new(0.38, -1, 0.60, 0)
    legLineL.BackgroundColor3 = THEME.BORDER
    legLineL.BorderSizePixel = 0
    legLineL.Parent = dummyCanvas

    local legLineR = Instance.new("Frame")
    legLineR.Size = UDim2.new(0, 2, 0.35, 0)
    legLineR.Position = UDim2.new(0.62, -1, 0.60, 0)
    legLineR.BackgroundColor3 = THEME.BORDER
    legLineR.BorderSizePixel = 0
    legLineR.Parent = dummyCanvas

    local activeRegionBadge = Instance.new("TextLabel")
    activeRegionBadge.Size = UDim2.new(1, -20, 0, 22)
    activeRegionBadge.Position = UDim2.new(0, 10, 0.48, 38)
    activeRegionBadge.BackgroundColor3 = THEME.BG_INPUT
    activeRegionBadge.Font = Enum.Font.GothamBold
    activeRegionBadge.TextSize = 10
    activeRegionBadge.TextColor3 = THEME.TEXT_MAIN
    activeRegionBadge.Text = "REGIÃO ATIVA: [ HEAD ]"
    activeRegionBadge.Parent = col3
    AddCorner(activeRegionBadge, 4)
    AddStroke(activeRegionBadge, THEME.BORDER, 1)

    local regionNodes = {
        { Name = "Head",  Pos = UDim2.new(0.5, -9, 0.10, 0) },
        { Name = "Torso", Pos = UDim2.new(0.5, -9, 0.35, 0) },
        { Name = "Arms",  Pos = UDim2.new(0.25, -9, 0.35, 0) },
        { Name = "Arms",  Pos = UDim2.new(0.75, -9, 0.35, 0) },
        { Name = "Legs",  Pos = UDim2.new(0.38, -9, 0.75, 0) },
        { Name = "Legs",  Pos = UDim2.new(0.62, -9, 0.75, 0) },
    }

    local nodeElements: { { Btn: TextButton, Region: string } } = {}

    local function UpdateRegionHighlights(selected: string)
        activeRegionBadge.Text = "REGIÃO ATIVA: [ " .. string.upper(selected) .. " ]"
        for _, item in ipairs(nodeElements) do
            item.Btn.BackgroundColor3 = (item.Region == selected) and THEME.ACCENT_RED or THEME.BORDER
        end
    end

    for _, n in ipairs(regionNodes) do
        local node = Instance.new("TextButton")
        node.Size = UDim2.new(0, 18, 0, 18)
        node.Position = n.Pos
        node.BackgroundColor3 = (n.Name == SimConfig.Get("TargetRegion")) and THEME.ACCENT_RED or THEME.BORDER
        node.Text = ""
        node.AutoButtonColor = false
        node.Parent = dummyCanvas
        AddCorner(node, 9)
        table.insert(nodeElements, { Btn = node, Region = n.Name })

        node.MouseButton1Click:Connect(function()
            SimConfig.Set("TargetRegion", n.Name)
            SimConfig.Set("TargetBone", n.Name)
            UpdateRegionHighlights(n.Name)
        end)
    end

    -- Mini Painel de Telemetria Integrado na Coluna 3
    local telemetryCard = Instance.new("Frame")
    telemetryCard.Size = UDim2.new(1, -20, 0, 92)
    telemetryCard.Position = UDim2.new(0, 10, 1, -98)
    telemetryCard.BackgroundColor3 = THEME.BG_INPUT
    telemetryCard.Parent = col3
    AddCorner(telemetryCard, 4)
    AddStroke(telemetryCard, THEME.BORDER, 1)

    local teleLayout = Instance.new("UIListLayout")
    teleLayout.Padding = UDim.new(0, 2)
    teleLayout.Parent = telemetryCard

    local telePad = Instance.new("UIPadding")
    telePad.PaddingTop = UDim.new(0, 5); telePad.PaddingLeft = UDim.new(0, 8); telePad.PaddingRight = UDim.new(0, 8)
    telePad.Parent = telemetryCard

    local function CreateTeleLine(titleText: string): TextLabel
        local line = Instance.new("TextLabel")
        line.Size = UDim2.new(1, 0, 0, 15)
        line.BackgroundTransparency = 1
        line.Font = Enum.Font.GothamMedium
        line.TextSize = 9
        line.TextColor3 = THEME.TEXT_MUTED
        line.TextXAlignment = Enum.TextXAlignment.Left
        line.Text = titleText
        line.Parent = telemetryCard
        return line
    end

    local teleVel = CreateTeleLine("VELOCIDADE ANGULAR: 0.0 °/s")
    local teleObs = CreateTeleLine("LINHA DE VISÃO: LIVRE")
    local teleMode = CreateTeleLine("MODO: PARADO")
    local teleTarget = CreateTeleLine("ALVO ATIVO: NENHUM")
    local teleFps = CreateTeleLine("STATUS DO ENGINE: 60 FPS")

    -- =========================================================================
    -- BARRA INFERIOR: Controles de Execucao Profissionais
    -- =========================================================================
    local bottomBar = Instance.new("Frame")
    bottomBar.Size = UDim2.new(1, -20, 0, 38)
    bottomBar.Position = UDim2.new(0, 10, 1, -44)
    bottomBar.BackgroundTransparency = 1
    bottomBar.Parent = mainFrame

    local actionLayout = Instance.new("UIListLayout")
    actionLayout.FillDirection = Enum.FillDirection.Horizontal
    actionLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    actionLayout.Padding = UDim.new(0, 8)
    actionLayout.Parent = bottomBar

    local function CreateActionButton(text: string, isPrimary: boolean, onClick: () -> ()): TextButton
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 135, 1, 0)
        btn.BackgroundColor3 = isPrimary and THEME.ACCENT_RED or THEME.BG_PANEL
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 11
        btn.TextColor3 = THEME.TEXT_MAIN
        btn.Text = text
        btn.Parent = bottomBar
        AddCorner(btn, 4)
        AddStroke(btn, isPrimary and THEME.ACCENT_HOVER or THEME.BORDER, 1)

        btn.MouseButton1Click:Connect(onClick)
        return btn
    end

    local btnReset = CreateActionButton("↺ RESETAR", false, function()
        SimConfig.LoadProfile("Normal")
        UpdateProfileHighlights("Normal")
        if DashboardGUI.OnResetRequested then
            DashboardGUI.OnResetRequested()
        end
    end)

    local btnSave = CreateActionButton("💾 SALVAR CONFIG", false, function()
        pcall(function()
            game:GetService("StarterGui"):SetCore("SendNotification", {
                Title = "DeepHat Suite",
                Text = "Configurações salvas com sucesso!",
                Duration = 3
            })
        end)
        if DashboardGUI.OnSaveRequested then
            DashboardGUI.OnSaveRequested()
        end
    end)

    local btnStop = CreateActionButton("⏹ PARAR", false, function()
        SimConfig.Set("SimulationActive", false)
        toggleBtn.BackgroundColor3 = THEME.BG_INPUT
        toggleDot.Position = UDim2.new(0, 3, 0.5, -7)
        if DashboardGUI.OnStopRequested then
            DashboardGUI.OnStopRequested()
        end
    end)

    local btnStart = CreateActionButton("▶ INICIAR TESTE", true, function()
        SimConfig.Set("SimulationActive", true)
        toggleBtn.BackgroundColor3 = THEME.ACCENT_RED
        toggleDot.Position = UDim2.new(1, -17, 0.5, -7)
        if DashboardGUI.OnStartRequested then
            DashboardGUI.OnStartRequested()
        end
    end)

    -- Sincronizacao Reativa (Observer)
    SimConfig.SubscribeAll(function(key, val)
        if key == "ActiveProfile" then
            UpdateProfileHighlights(tostring(val))
        elseif key == "TargetRegion" then
            UpdateRegionHighlights(tostring(val))
        elseif key == "SimulationActive" then
            toggleBtn.BackgroundColor3 = val and THEME.ACCENT_RED or THEME.BG_INPUT
            toggleDot.Position = val and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7)
            fovCircle.Visible = (val == true and SimConfig.Get("ShowFovCircle") == true)
        elseif syncInputs[key] and typeof(val) == "number" then
            syncInputs[key].UpdateRatio(val)
        end
    end)

    -- Funcao publica para atualizar o circulo de FOV
    function DashboardGUI:UpdateFovCircle()
        if not fovCircle or not fovCircle.Parent then return end
        local active = SimConfig.Get("SimulationActive")
        local show = SimConfig.Get("ShowFovCircle") and active
        fovCircle.Visible = (show == true)
        if show then
            local fov = tonumber(SimConfig.Get("FOV")) or 70.0
            local vp = Camera.ViewportSize
            local halfFovRad = math.rad(fov / 2)
            local camFovRad = math.rad(Camera.FieldOfView / 2)
            local radius = (math.tan(halfFovRad) / math.max(math.tan(camFovRad), 0.001)) * (vp.Y / 2)
            fovCircle.Size = UDim2.new(0, radius * 2, 0, radius * 2)
            fovCircle.Position = UDim2.new(0.5, 0, 0.5, 0)
        end
    end

    -- Funcao publica para atualizar os dados de telemetria
    function DashboardGUI:UpdateTelemetryDisplay(data: any)
        if not data then return end
        local angVel = tonumber(data.angularVelocity) or 0
        teleVel.Text = string.format("VELOCIDADE ANGULAR: %.1f °/s", angVel)
        teleObs.Text = string.format("LINHA DE VISÃO: %s", data.isObstructed and "OBSTRUÍDO (PAREDE)" or "LIVRE")
        teleObs.TextColor3 = data.isObstructed and Color3.fromRGB(240, 80, 80) or THEME.SUCCESS
        teleMode.Text = string.format("MODO: %s", tostring(data.mode or "IDLE"))
        teleTarget.Text = string.format("ALVO ATIVO: %s", tostring(data.targetName or "NENHUM"))
        teleTarget.TextColor3 = data.targetName and THEME.SUCCESS or THEME.TEXT_MUTED
        local dt = tonumber(data.dt) or 0.016
        local fps = math.floor(1 / math.max(dt, 0.001))
        teleFps.Text = string.format("STATUS DO ENGINE: %d FPS", fps)
    end

    return screenGui
end

-- =========================================================================
-- =========================================================================
-- =========================================================================
-- [5/5] ORQUESTRADOR: EXECUCAO OTIMIZADA COM RASTREIO E CHAMS
-- =========================================================================
local guiInstance = DashboardGUI.Create()

local filterInstances: { Instance } = {}
if LocalPlayer.Character then table.insert(filterInstances, LocalPlayer.Character) end

-- Instanciação dos Módulos Especializados
local Detector = InstanceDetector.new(0.15)
local Kinematics = VectorTracker.new(Camera.CFrame, filterInstances)

LocalPlayer.CharacterAdded:Connect(function(char)
    table.clear(filterInstances)
    table.insert(filterInstances, char)
    Kinematics:SetFilterInstances(filterInstances)
end)

local isRunning = false
local lastSnapTime = 0
local lastUiUpdate = 0

local isRightMouseDown = false
UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        isRightMouseDown = true
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        isRightMouseDown = false
    end
end)

-- Debugger de Instâncias no Console
local lastDebugLog = 0
local lastTargetName = ""
local function DebugLog(targetInst: Instance?, pos: Vector3?, dist: number?, angleDeg: number?, partLabel: string?, isObstructed: boolean?)
    local now = os.clock()
    if targetInst and pos then
        local name = targetInst.Name
        if name ~= lastTargetName or (now - lastDebugLog > 2.5) then
            lastTargetName = name
            lastDebugLog = now
            print(string.format(
                "[DeepHat Debugger] 🎯 ALVO DETECTADO: [%s] | Distância: %.1fm | Ângulo FOV: %.1f° | Região: %s | Obstrução: %s",
                name,
                dist or 0,
                angleDeg or 0,
                partLabel or "Pivot",
                isObstructed and "SIM (PAREDE)" or "NÃO (LIVRE)"
            ))
        end
    else
        if (now - lastDebugLog > 4.0) then
            lastDebugLog = now
            local allCount = #Detector:ScanCandidates(SimConfig.Get("TeamCheck"))
            if allCount == 0 then
                warn("[DeepHat Debugger] ⚠️ Nenhuma entidade alvo encontrada no ambiente. Aguardando modelos no Workspace/Players...")
            else
                print(string.format("[DeepHat Debugger] 🔍 %d entidades detectadas no mapa, mas fora do FOV atual. Aponte a câmera para o alvo.", allCount))
            end
        end
    end
end

-- Pipeline de Avaliação Geométrica e Extração do Melhor Alvo
local function GetTargetData(): (Vector3?, Vector3, Instance?, boolean, string)
    local boneSetting = SimConfig.Get("TargetRegion") or "Head"
    local fov = tonumber(SimConfig.Get("FOV")) or 70.0
    local enableESP = SimConfig.Get("EnableESP")
    local visibleOnly = SimConfig.Get("VisibleOnly")
    local teamCheck = SimConfig.Get("TeamCheck")
    local maxRadius = SimConfig.Get("VectorRadius") or 300.0

    local bestAngle = fov
    local chosenPos: Vector3? = nil
    local chosenVel = Vector3.zero
    local chosenTarget: Instance? = nil
    local chosenLabel = "None"
    local isObstructed = false

    local camPos = Camera.CFrame.Position
    local camLook = Camera.CFrame.LookVector
    local targets = Detector:ScanCandidates(teamCheck)

    for _, obj in ipairs(targets) do
        local currentPos, targetPart, partLabel = Detector:ResolvePivotPosition(obj, boneSetting)

        if currentPos then
            local displacement = (currentPos - camPos)
            local dist = displacement.Magnitude

            -- Filtro de Magnitude (Raio de Atuação)
            if dist <= maxRadius and dist >= 0.05 then
                local vel = Kinematics:EstimateVelocity(obj, currentPos)
                local obstructed = Kinematics:CheckObstruction(camPos, currentPos)

                if enableESP then
                    VisualOverlayRenderer.UpdateTarget(obj, obstructed, false)
                else
                    VisualOverlayRenderer.Clear(obj)
                end

                if visibleOnly and obstructed then
                    continue
                end

                local dir = displacement / dist
                local dot = math.clamp(camLook:Dot(dir), -1.0, 1.0)
                local angleDeg = math.deg(math.acos(dot))

                if angleDeg < bestAngle then
                    bestAngle = angleDeg
                    chosenPos = currentPos
                    chosenVel = vel
                    chosenTarget = obj
                    chosenLabel = partLabel
                    isObstructed = obstructed
                end
            end
        end
    end

    if chosenTarget and enableESP then
        VisualOverlayRenderer.UpdateTarget(chosenTarget, isObstructed, true)
    end

    local chosenDist = chosenPos and (chosenPos - camPos).Magnitude or 0
    DebugLog(chosenTarget, chosenPos, chosenDist, bestAngle, chosenLabel, isObstructed)

    return chosenPos, chosenVel, chosenTarget, isObstructed, chosenLabel
end

local BIND_PIPELINE = "DeepHat_StandaloneCameraTracking"

DashboardGUI.OnStartRequested = function()
    if isRunning then return end
    isRunning = true
    print("[DeepHat v5.0 PRO] Simulador ATIVADO! (Anti-Lag & Anti-Fail Rig)")

    pcall(function() RunService:UnbindFromRenderStep(BIND_PIPELINE) end)

    RunService:BindToRenderStep(BIND_PIPELINE, Enum.RenderPriority.Camera.Value + 1, function(dt)
        local ok, _ = pcall(function()
            local targetPos, targetVel, targetObj, obstructed, partLabel = GetTargetData()
            local now = os.clock()

            DashboardGUI:UpdateFovCircle()

            local isRmbHeld = isRightMouseDown or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
            local holdToAim = SimConfig.Get("HoldToAim") == true
            local shouldAim = isRunning and (not holdToAim or isRmbHeld)

            if targetPos and shouldAim then
                local snapFreq = SimConfig.Get("SnapFrequency") or 0.03
                local responseTimeSec = (SimConfig.Get("ResponseTime") or 16) / 1000.0

                local telem
                if math.random() < snapFreq and (now - lastSnapTime > responseTimeSec) then
                    lastSnapTime = now
                    telem = Kinematics:StepSnap(targetPos, targetVel, dt)
                else
                    telem = Kinematics:StepSmooth(targetPos, targetVel, dt)
                end

                if telem and telem.cframe then
                    Camera.CFrame = telem.cframe
                end

                if (now - lastUiUpdate) >= 0.066 then
                    lastUiUpdate = now
                    telem.dt = dt
                    telem.targetName = targetObj and targetObj.Name or "DETECTADO"
                    DashboardGUI:UpdateTelemetryDisplay(telem)
                end
            else
                if (now - lastUiUpdate) >= 0.15 then
                    lastUiUpdate = now
                    DashboardGUI:UpdateTelemetryDisplay({
                        angularVelocity = 0,
                        isObstructed = false,
                        mode = isRunning and "LIVRE (BUSCANDO)" or "PARADO",
                        targetName = nil,
                        suspicionScore = 0,
                        dt = dt
                    })
                end
            end
        end)
        if not ok then
            -- Tratamento silencioso de quadro
        end
    end)
end

DashboardGUI.OnStopRequested = function()
    if not isRunning then return end
    isRunning = false
    pcall(function() RunService:UnbindFromRenderStep(BIND_PIPELINE) end)
    VisualOverlayRenderer.ClearAll()
    DashboardGUI:UpdateFovCircle()
    print("[DeepHat v5.0 PRO] Simulador PARADO!")
    DashboardGUI:UpdateTelemetryDisplay({ angularVelocity = 0, isObstructed = false, mode = "PARADO", targetName = nil, suspicionScore = 0 })
end

DashboardGUI.OnResetRequested = function()
    print("[DeepHat v5.0 PRO] Parametros resetados para Normal!")
end

DashboardGUI.OnSaveRequested = function()
    print("[DeepHat v5.0 PRO] Configuracoes salvas!")
end

_G.DeepHat_Cleanup = function()
    pcall(function() RunService:UnbindFromRenderStep(BIND_PIPELINE) end)
    VisualOverlayRenderer.ClearAll()
    if guiInstance and guiInstance.Parent then guiInstance:Destroy() end
end

Players.PlayerRemoving:Connect(function(plr)
    pcall(function()
        if plr and plr.Character then
            VisualOverlayRenderer.Clear(plr.Character)
        end
    end)
end)

SimConfig.Subscribe("EnableESP", function(enabled)
    if not enabled then
        VisualOverlayRenderer.ClearAll()
    end
end)

SimConfig.Subscribe("ShowFovCircle", function()
    DashboardGUI:UpdateFovCircle()
end)

SimConfig.Subscribe("FOV", function()
    DashboardGUI:UpdateFovCircle()
end)

task.defer(function()
    DashboardGUI.OnStartRequested()
end)

print("[DeepHat v5.0 PRO] Motor de Rastreamento e ESP Carregados! Pressione [HOME] para abrir/fechar.")

pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "DeepHat v5.0 PRO",
        Text = "Rastreamento e ESP Ativos! Pressione [HOME] para abrir/fechar.",
        Duration = 6
    })
end)
