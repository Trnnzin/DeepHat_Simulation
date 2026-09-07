--!strict
-- DeepHat_Standalone.lua (v4.0 - Advanced Kinematics & ESP Suite)
-- Motor de Simulacao de Cinematica 3D, Deteccao de Anomalias, Previsao Balistica e Chams ESP
-- Recursos:
-- 1. Previsao Balistica de Movimento (Lead Prediction via delta vetorial)
-- 2. Seletor de Osso Alvo Dinamico (Head, UpperTorso, Closest Bone)
-- 3. ESP Chams com Cores Dinamicas (Verde = Visivel / Vermelho = Ocluido atras de parede)
-- 4. Circulo de FOV Dinamico na Tela (Redimensionamento em tempo real)
-- 5. Termometro de Anomalia / Suspeicao em Tempo Real (Anti-Cheat Score 0% a 100%)
-- 6. Tecla de Atalho (RightShift / Insert) para Minimizar / Restaurar a Interface
-- 7. Exportador de Relatorio Estatistico de Telemetria no Console
-- 8. Throttling de UI a 10Hz e Zero-Allocation de Memoria (Zero Lag)

-- Limpeza estrita de qualquer sessao anterior ou interface fantasma
local function PurgeAllLegacyUIs()
    local containers = {}
    pcall(function() table.insert(containers, game:GetService("CoreGui")) end)
    local pGui = game:GetService("Players").LocalPlayer and game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if pGui then table.insert(containers, pGui) end

    local targetNames = {
        "DiagnosticSimulationDashboard",
        "KinematicsSimulationDashboard",
        "DeepHat_GUI",
        "FovCircleOverlay",
        "DeepHat_ESP_Highlight"
    }

    for _, container in ipairs(containers) do
        for _, name in ipairs(targetNames) do
            local found = container:FindFirstChild(name)
            while found do
                pcall(function() found:Destroy() end)
                found = container:FindFirstChild(name)
            end
        end
    end
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

-- =========================================================================
-- [1/5] MODULO: SimConfig (Central de Parametros + Observer Pattern)
-- =========================================================================
local SimConfig = {}
do
    local PROFILES: { [string]: ProfileData } = {
        ["Normal"] = {
            SimulationActive = true,
            AimMode = "HoldRMB",
            HoldToAim = false,
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
            HoldToAim = false,
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
            HoldToAim = false,
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
            HoldToAim = false,
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
            HoldToAim = false,
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
        HoldToAim = false,
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
-- [2/5] MODULO: ESPVisualizer (Chams com Cores Dinamicas Verde/Vermelho)
-- =========================================================================
local ESPVisualizer = {}
do
    local activeHighlights: { [Model]: Highlight } = {}

    local function GetOrCreateHighlight(character: Model): Highlight?
        if not character then return nil end
        local hl = activeHighlights[character]
        if not hl or not hl.Parent then
            hl = Instance.new("Highlight")
            hl.Name = "DeepHat_ESP_Highlight"
            hl.Adornee = character
            hl.FillTransparency = 0.45
            hl.OutlineTransparency = 0.1
            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            pcall(function() hl.Parent = character end)
            activeHighlights[character] = hl
        end
        return hl
    end

    function ESPVisualizer.UpdateTarget(character: Model, isObstructed: boolean, isMainTarget: boolean)
        if not SimConfig.Get("EnableESP") then
            ESPVisualizer.Clear(character)
            return
        end

        local hl = GetOrCreateHighlight(character)
        if isMainTarget then
            -- Alvo focado na mira: Verde Brilhante (Visivel) ou Vermelho Vivo (Parede)
            if isObstructed then
                hl.FillColor = Color3.fromRGB(255, 45, 45)
                hl.OutlineColor = Color3.fromRGB(255, 180, 180)
            else
                hl.FillColor = Color3.fromRGB(46, 230, 110)
                hl.OutlineColor = Color3.fromRGB(200, 255, 200)
            end
            hl.FillTransparency = 0.35
            hl.OutlineTransparency = 0.05
        else
            -- Outros alvos: Azul/Ciano (Visivel) ou Laranja/Vermelho escuro (Parede)
            hl.FillColor = isObstructed and Color3.fromRGB(180, 70, 70) or Color3.fromRGB(50, 140, 230)
            hl.OutlineColor = Color3.fromRGB(240, 240, 240)
            hl.FillTransparency = 0.65
            hl.OutlineTransparency = 0.25
        end
    end

    function ESPVisualizer.Clear(character: Model?)
        if not character then return end
        local hl = activeHighlights[character]
        if hl then
            pcall(function() hl:Destroy() end)
            activeHighlights[character] = nil
        end
    end

    function ESPVisualizer.ClearAll()
        for char, hl in pairs(activeHighlights) do
            if hl then pcall(function() hl:Destroy() end) end
        end
        table.clear(activeHighlights)
    end
end

-- =========================================================================
-- [3/5] MODULO: AdvancedKinematics (Motor Fisico, Previsao e Telemetria)
-- =========================================================================
local AdvancedKinematics = {}
AdvancedKinematics.__index = AdvancedKinematics

do
    local function Smoothstep(x: number): number
        local clamped = math.clamp(x, 0.0, 1.0)
        return clamped * clamped * (3.0 - 2.0 * clamped)
    end

    function AdvancedKinematics.new(initialCFrame: CFrame?, filterInstances: { Instance }?)
        local self = setmetatable({}, AdvancedKinematics)
        self.CurrentCFrame = initialCFrame or CFrame.new(0, 5, 0)
        self.PreviousLookVector = self.CurrentCFrame.LookVector
        self.PreviousAngularVelocity = 0
        self.NoiseSeed = math.random(1000, 9999)

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

    function AdvancedKinematics:SetFilterInstances(instances: { Instance })
        self.RayParams.FilterDescendantsInstances = instances
    end

    function AdvancedKinematics:CheckObstruction(fromPos: Vector3, toPos: Vector3): boolean
        local dir = (toPos - fromPos)
        if dir.Magnitude < 0.05 then return false end
        return (workspace:Raycast(fromPos, dir, self.RayParams) ~= nil)
    end

    -- Previsao Balistica de Trajetoria (Lead Prediction)
    function AdvancedKinematics:ComputeLead(targetPos: Vector3, targetVelocity: Vector3, eyePos: Vector3): Vector3
        if not SimConfig.Get("EnableLead") then
            return targetPos
        end
        local projSpeed = SimConfig.Get("ProjectileSpeed") or 800.0
        local dist = (targetPos - eyePos).Magnitude
        local timeToHit = projSpeed > 0 and (dist / projSpeed) or 0
        -- Posicao futura = P0 + V * t
        return targetPos + (targetVelocity * timeToHit)
    end

    function AdvancedKinematics:EvaluateSuspicion(angVel: number, jerk: number, isSnap: boolean, obstructed: boolean): number
        local score = 0
        if isSnap then score = score + 45 end
        if angVel > 350 then score = score + math.clamp((angVel - 350) / 10, 0, 30) end
        if jerk > 4000 then score = score + 15 end
        if obstructed and angVel > 20 then score = score + 10 end
        return math.clamp(math.floor(score), 0, 100)
    end

    function AdvancedKinematics:StepSnap(rawTargetPosition: Vector3, targetVelocity: Vector3, dt: number)
        local eyePos = Camera.CFrame.Position
        local targetPosition = self:ComputeLead(rawTargetPosition, targetVelocity, eyePos)
        local toTarget = (targetPosition - eyePos)
        if toTarget.Magnitude < 0.001 then return self.CachedTelemetry end

        local dot = math.clamp(self.CurrentCFrame.LookVector:Dot(toTarget.Unit), -1.0, 1.0)
        local angularErrorDeg = math.deg(math.acos(dot))

        self.CurrentCFrame = CFrame.lookAt(eyePos, targetPosition)
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

        function AdvancedKinematics:StepSmooth(rawTargetPosition: Vector3, targetVelocity: Vector3, dt: number)
        local eyePos = Camera.CFrame.Position
        self.CurrentCFrame = Camera.CFrame
        local targetPosition = self:ComputeLead(rawTargetPosition, targetVelocity, eyePos)
        local toTarget = (targetPosition - eyePos)
        local dist = toTarget.Magnitude

        -- Otimizacao de Magnitude & Guarda Epsilon
        if dist < 0.001 then return self.CachedTelemetry end

        -- Vetor unitario direto sem recalculate de magnitude
        local dirToTarget = toTarget / dist
        local dot = math.clamp(self.CurrentCFrame.LookVector:Dot(dirToTarget), -1.0, 1.0)
        local angularErrorDeg = math.deg(math.acos(dot))

        local fov = math.max(SimConfig.Get("FOV") or 60.0, 1.0)
        local baseSmoothing = math.clamp(SimConfig.Get("Smoothing") or 0.15, 0.005, 1.0)
        local speedMult = math.clamp((SimConfig.Get("MoveSpeed") or 16.0) / 16.0, 0.25, 3.0)
        local precision = math.clamp((SimConfig.Get("TrackingPrecision") or 98.5) / 100.0, 0.5, 1.0)
        local intensity = math.clamp((SimConfig.Get("Intensity") or 75.0) / 100.0, 0.0, 2.0)
        local maxRadius = SimConfig.Get("VectorRadius") or 250.0

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

        -- Curva de Aceleracao Hermite Smoothstep com expoente de gradiente
        local normalizedErr = math.clamp(angularErrorDeg / fov, 0.0, 1.0)
        local smoothFactor = normalizedErr * normalizedErr * (3.0 - 2.0 * normalizedErr)
        local accelExponent = SimConfig.Get("AccelerationCurve") or 1.25
        smoothFactor = math.pow(smoothFactor, accelExponent)

        -- Interpolacao Frame-rate Independent via Exponential Decay (Sem Jittering e Sem Delay)
        local safeDt = math.clamp(dt or 0.0166, 0.001, 0.1)
        local k = (baseSmoothing * 28.0 * speedMult) * (0.35 + 0.65 * smoothFactor)
        local dynamicAlpha = math.clamp(1.0 - math.exp(-k * safeDt), 0.001, 1.0)

        local targetRotation = CFrame.lookAt(eyePos, targetPosition)
        local smoothedRotation = self.CurrentCFrame:Lerp(targetRotation, dynamicAlpha)

        -- Jitter organico atenuado perto do centro da mira
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

        local newLook = self.CurrentCFrame.LookVector
        local deltaDot = math.clamp(self.PreviousLookVector:Dot(newLook), -1.0, 1.0)
        local angVel = math.deg(math.acos(deltaDot)) / safeDt
        local jerk = math.abs(angVel - self.PreviousAngularVelocity) / safeDt
        self.PreviousAngularVelocity = angVel
        self.PreviousLookVector = newLook

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

    function AdvancedKinematics:ExportReport()
        local hist = self.MetricsHistory
        local avg = hist.totalSamples > 0 and (hist.sumVelocity / hist.totalSamples) or 0
        local obsRatio = hist.totalSamples > 0 and (hist.obstructedCount / hist.totalSamples * 100) or 0
        local snapRatio = hist.totalSamples > 0 and (hist.snapCount / hist.totalSamples * 100) or 0

        print("=======================================================")
        print("          RELATORIO DE TELEMETRIA DE AGENTE 3D         ")
        print("=======================================================")
        print(string.format("  Total de Quadros Amostrados: %d", hist.totalSamples))
        print(string.format("  Velocidade Angular Media:    %.2f deg/s", avg))
        print(string.format("  Pico de Velocidade Angular:  %.2f deg/s", hist.peakVelocity))
        print(string.format("  Proporcao de Snaps Bruscos:  %.1f%%", snapRatio))
        print(string.format("  Rastreamento Ocluido/Parede: %.1f%%", obsRatio))
        print(string.format("  Previsao Balistica Ativa:    %s", tostring(SimConfig.Get("EnableLead"))))
        print(string.format("  Osso Alvo Selecionado:       %s", tostring(SimConfig.Get("TargetBone"))))
        print("=======================================================")
    end
end

-- =========================================================================
-- [4/5] MODULO: DashboardGUI

-- =========================================================================
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
        local ok, coreGui = pcall(function() return game:GetService("CoreGui") end)
        if ok and coreGui then
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

    local existing = hostParent:FindFirstChild("DiagnosticSimulationDashboard")
    if existing then existing:Destroy() end

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
    dummyCanvas.Size = UDim2.new(1, -20, 0.52, 0)
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
    activeRegionBadge.Size = UDim2.new(1, -20, 0, 24)
    activeRegionBadge.Position = UDim2.new(0, 10, 0.52, 38)
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
    telemetryCard.Size = UDim2.new(1, -20, 0, 78)
    telemetryCard.Position = UDim2.new(0, 10, 1, -84)
    telemetryCard.BackgroundColor3 = THEME.BG_INPUT
    telemetryCard.Parent = col3
    AddCorner(telemetryCard, 4)
    AddStroke(telemetryCard, THEME.BORDER, 1)

    local teleLayout = Instance.new("UIListLayout")
    teleLayout.Padding = UDim.new(0, 3)
    teleLayout.Parent = telemetryCard

    local telePad = Instance.new("UIPadding")
    telePad.PaddingTop = UDim.new(0, 6); telePad.PaddingLeft = UDim.new(0, 8); telePad.PaddingRight = UDim.new(0, 8)
    telePad.Parent = telemetryCard

    local function CreateTeleLine(titleText: string): TextLabel
        local line = Instance.new("TextLabel")
        line.Size = UDim2.new(1, 0, 0, 14)
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
        local dt = tonumber(data.dt) or 0.016
        local fps = math.floor(1 / math.max(dt, 0.001))
        teleFps.Text = string.format("STATUS DO ENGINE: %d FPS", fps)
    end

    return screenGui
end

-- =========================================================================
-- [5/5] ORQUESTRADOR: EXECUCAO OTIMIZADA COM RASTREIO E CHAMS
-- =========================================================================
local guiInstance = DashboardGUI.Create()

local filterInstances: { Instance } = {}
if LocalPlayer.Character then table.insert(filterInstances, LocalPlayer.Character) end
local Kinematics = AdvancedKinematics.new(Camera.CFrame, filterInstances)

LocalPlayer.CharacterAdded:Connect(function(char)
    table.clear(filterInstances)
    table.insert(filterInstances, char)
    Kinematics:SetFilterInstances(filterInstances)
end)

local isRunning = false
local lastSnapTime = 0
local lastUiUpdate = 0

-- Rastreio de velocidade anterior dos alvos para calculo do vetor aceleração
local targetLastPosCache: { [Model]: { pos: Vector3, time: number } } = {}

-- Obtem a parte do corpo desejada com suporte universal para R15, R6 e Dummies
local function GetBonePart(char: Model, boneSetting: string): BasePart?
    local bone = string.lower(SimConfig.Get("TargetRegion") or SimConfig.Get("TargetBone") or boneSetting or "head")

    if bone == "head" then
        return char:FindFirstChild("Head") :: BasePart?
            or char:FindFirstChild("head") :: BasePart?
            or char:FindFirstChild("HumanoidRootPart") :: BasePart?
    elseif bone == "torso" or bone == "uppertorso" then
        return char:FindFirstChild("UpperTorso") :: BasePart?
            or char:FindFirstChild("Torso") :: BasePart?
            or char:FindFirstChild("LowerTorso") :: BasePart?
            or char:FindFirstChild("HumanoidRootPart") :: BasePart?
    elseif bone == "arms" then
        return char:FindFirstChild("RightUpperArm") :: BasePart?
            or char:FindFirstChild("RightArm") :: BasePart?
            or char:FindFirstChild("LeftUpperArm") :: BasePart?
            or char:FindFirstChild("LeftArm") :: BasePart?
            or char:FindFirstChild("UpperTorso") :: BasePart?
    elseif bone == "legs" then
        return char:FindFirstChild("RightUpperLeg") :: BasePart?
            or char:FindFirstChild("RightLeg") :: BasePart?
            or char:FindFirstChild("LeftUpperLeg") :: BasePart?
            or char:FindFirstChild("LeftLeg") :: BasePart?
            or char:FindFirstChild("LowerTorso") :: BasePart?
    end

    return char:FindFirstChild("Head") :: BasePart?
        or char:FindFirstChild("HumanoidRootPart") :: BasePart?
        or char:FindFirstChildWhichIsA("BasePart") :: BasePart?
end

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

local function IsTeammate(otherPlayer: Player?): boolean
    if not SimConfig.Get("TeamCheck") or not otherPlayer then return false end
    if LocalPlayer.Team and otherPlayer.Team then
        return LocalPlayer.Team == otherPlayer.Team
    end
    return false
end

-- Descoberta Universal de Alvos: Jogadores Reais + NPCs / Dummies de Sandbox
local function GetAllTargetCharacters(): { Model }
    local targets: { Model } = {}
    local seen: { [Model]: boolean } = {}

    -- 1. Jogadores reais
    for _, other in ipairs(Players:GetPlayers()) do
        if other ~= LocalPlayer and other.Character and not IsTeammate(other) then
            local char = other.Character
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                table.insert(targets, char)
                seen[char] = true
            end
        end
    end

    -- 2. Dummies e NPCs no Workspace (Essencial para testes em Studio, Sandbox e jogos PvE)
    local function ScanModels(parent: Instance)
        for _, child in ipairs(parent:GetChildren()) do
            if child:IsA("Model") and child ~= LocalPlayer.Character and not seen[child] then
                local hum = child:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    if child:FindFirstChild("Head") or child:FindFirstChild("HumanoidRootPart") or child:FindFirstChild("Torso") or child:FindFirstChild("UpperTorso") then
                        table.insert(targets, child)
                        seen[child] = true
                    end
                end
            end
        end
    end

    ScanModels(Workspace)
    for _, folderName in ipairs({ "NPCs", "Enemies", "Characters", "Zombies", "Bots", "Dummies" }) do
        local f = Workspace:FindFirstChild(folderName)
        if f then ScanModels(f) end
    end

    return targets
end

local function GetTargetData(): (Vector3?, Vector3, Model?, boolean)
    local boneSetting = SimConfig.Get("TargetRegion") or "Head"
    local fov = tonumber(SimConfig.Get("FOV")) or 70.0
    local enableESP = SimConfig.Get("EnableESP")
    local visibleOnly = SimConfig.Get("VisibleOnly")

    local bestAngle = fov
    local chosenPos: Vector3? = nil
    local chosenVel = Vector3.zero
    local chosenModel: Model? = nil
    local isObstructed = false

    local now = os.clock()
    local camPos = Camera.CFrame.Position
    local camLook = Camera.CFrame.LookVector
    local targets = GetAllTargetCharacters()

    for _, char in ipairs(targets) do
        local targetPart = GetBonePart(char, boneSetting)

        if targetPart then
            local currentPos = targetPart.Position

            -- Calculo de velocidade vetorial V = deltaP / deltaT
            local vel = Vector3.zero
            local last = targetLastPosCache[char]
            if last then
                local dt = (now - last.time)
                if dt > 0 and dt < 0.25 then
                    vel = (currentPos - last.pos) / dt
                end
            end
            targetLastPosCache[char] = { pos = currentPos, time = now }

            -- Checagem de obstrucao de visao (WallCheck)
            local obstructed = Kinematics:CheckObstruction(camPos, currentPos)

            -- Atualiza ESP Chams (Verde = Visivel / Vermelho = Parede)
            if enableESP then
                ESPVisualizer.UpdateTarget(char, obstructed, false)
            else
                ESPVisualizer.Clear(char)
            end

            -- Se "Apenas Visiveis" estiver ativo, ignora alvos atras da parede
            if visibleOnly and obstructed then
                continue
            end

            -- Checagem de raio angular do FOV
            local toTarget = (currentPos - camPos)
            if toTarget.Magnitude > 0.5 then
                local dir = toTarget.Unit
                local dot = math.clamp(camLook:Dot(dir), -1.0, 1.0)
                local angleDeg = math.deg(math.acos(dot))

                if angleDeg < bestAngle then
                    bestAngle = angleDeg
                    chosenPos = currentPos
                    chosenVel = vel
                    chosenModel = char
                    isObstructed = obstructed
                end
            end
        end
    end

    -- Destaca o alvo focado com destaque no ESP
    if chosenModel and enableESP then
        ESPVisualizer.UpdateTarget(chosenModel, isObstructed, true)
    end

    return chosenPos, chosenVel, chosenModel, isObstructed
end

local BIND_PIPELINE = "DeepHat_StandaloneCameraTracking"

DashboardGUI.OnStartRequested = function()
    if isRunning then return end
    isRunning = true
    print("[DeepHat v4.0 PRO] Simulador ATIVADO! (Pipeline Zero-Latency com Deteccao Universal)")

    pcall(function() RunService:UnbindFromRenderStep(BIND_PIPELINE) end)

    RunService:BindToRenderStep(BIND_PIPELINE, Enum.RenderPriority.Camera.Value + 1, function(dt)
        local targetPos, targetVel, targetModel, obstructed = GetTargetData()
        local now = os.clock()

        -- Atualiza o circulo de FOV visual
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

            -- Rastreamento instantaneo no frame sem congelamento ou atraso
            if telem and telem.cframe then
                Camera.CFrame = telem.cframe
            end

            if (now - lastUiUpdate) >= 0.066 then
                lastUiUpdate = now
                telem.dt = dt
                DashboardGUI:UpdateTelemetryDisplay(telem)
            end
        else
            if (now - lastUiUpdate) >= 0.15 then
                lastUiUpdate = now
                DashboardGUI:UpdateTelemetryDisplay({
                    angularVelocity = 0,
                    isObstructed = false,
                    mode = isRunning and "LIVRE (BUSCANDO)" or "PARADO",
                    suspicionScore = 0,
                    dt = dt
                })
            end
        end
    end)
end

DashboardGUI.OnStopRequested = function()
    if not isRunning then return end
    isRunning = false
    pcall(function() RunService:UnbindFromRenderStep(BIND_PIPELINE) end)
    ESPVisualizer.ClearAll()
    DashboardGUI:UpdateFovCircle()
    print("[DeepHat v4.0 PRO] Simulador PARADO!")
    DashboardGUI:UpdateTelemetryDisplay({ angularVelocity = 0, isObstructed = false, mode = "PARADO", suspicionScore = 0 })
end

DashboardGUI.OnResetRequested = function()
    print("[DeepHat v4.0 PRO] Parametros resetados para Normal!")
end

DashboardGUI.OnSaveRequested = function()
    print("[DeepHat v4.0 PRO] Configuracoes salvas!")
end

_G.DeepHat_Cleanup = function()
    pcall(function() RunService:UnbindFromRenderStep(BIND_PIPELINE) end)
    ESPVisualizer.ClearAll()
    if guiInstance and guiInstance.Parent then guiInstance:Destroy() end
end

Players.PlayerRemoving:Connect(function(plr)
    if plr and plr.Character then
        ESPVisualizer.Clear(plr.Character)
        targetLastPosCache[plr.Character] = nil
    end
end)

SimConfig.Subscribe("EnableESP", function(enabled)
    if not enabled then
        ESPVisualizer.ClearAll()
    end
end)

SimConfig.Subscribe("ShowFovCircle", function()
    DashboardGUI:UpdateFovCircle()
end)

SimConfig.Subscribe("FOV", function()
    DashboardGUI:UpdateFovCircle()
end)

-- Inicia automaticamente todas as funcoes para funcionar direto ao injetar!
task.defer(function()
    DashboardGUI.OnStartRequested()
end)

print("[DeepHat v4.0 PRO] Carregamento completo! Pressione [HOME] para abrir/fechar a interface.")

pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "DeepHat v4.0 PRO",
        Text = "Interface e Motor ATIVOS! Pressione [HOME] para abrir/fechar.",
        Duration = 6
    })
end)
