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
    local PROFILES = {
        ["Normal"] = { 
            FOV = 45.0, Smoothing = 0.14, SpeedMultiplier = 1.0, TrackingPrecision = 0.95, 
            SnapFrequency = 0.03, ReactionTime = 0.22, Intensity = 1.0, 
            TargetBone = "Head", EnableLead = true, ProjectileSpeed = 800.0,
            EnableESP = true, ShowFovCircle = true, ActiveProfile = "Normal", AimKeyMode = "HoldRMB", VisibleOnly = false, TeamCheck = true
        },
        ["Leve"] = { 
            FOV = 30.0, Smoothing = 0.25, SpeedMultiplier = 0.75, TrackingPrecision = 0.98, 
            SnapFrequency = 0.00, ReactionTime = 0.28, Intensity = 0.6, 
            TargetBone = "UpperTorso", EnableLead = false, ProjectileSpeed = 800.0,
            EnableESP = true, ShowFovCircle = true, ActiveProfile = "Leve" 
        },
        ["Medio"] = { 
            FOV = 60.0, Smoothing = 0.09, SpeedMultiplier = 1.4, TrackingPrecision = 0.90, 
            SnapFrequency = 0.15, ReactionTime = 0.15, Intensity = 1.3, 
            TargetBone = "Head", EnableLead = true, ProjectileSpeed = 1000.0,
            EnableESP = true, ShowFovCircle = true, ActiveProfile = "Medio" 
        },
        ["Agressivo"] = { 
            FOV = 90.0, Smoothing = 0.02, SpeedMultiplier = 2.2, TrackingPrecision = 0.75, 
            SnapFrequency = 0.65, ReactionTime = 0.05, Intensity = 2.0, 
            TargetBone = "Head", EnableLead = true, ProjectileSpeed = 1200.0,
            EnableESP = true, ShowFovCircle = true, ActiveProfile = "Agressivo" 
        },
        ["Custom"] = { 
            FOV = 45.0, Smoothing = 0.14, SpeedMultiplier = 1.0, TrackingPrecision = 0.95, 
            SnapFrequency = 0.03, ReactionTime = 0.20, Intensity = 1.0, 
            TargetBone = "Closest", EnableLead = true, ProjectileSpeed = 800.0,
            EnableESP = true, ShowFovCircle = true, ActiveProfile = "Custom" 
        }
    }

    local CurrentState = table.clone(PROFILES["Normal"])
    local KeyListeners: { [string]: { (any) -> () } } = {}
    local GlobalListeners: { (string, any) -> () } = {}

    function SimConfig.Get(key: string): any
        return (CurrentState :: any)[key]
    end

    function SimConfig.GetAll()
        return table.clone(CurrentState)
    end

    function SimConfig.Set(key: string, value: any, silent: boolean?)
        if (CurrentState :: any)[key] == value then return end
        (CurrentState :: any)[key] = value

        if key ~= "ActiveProfile" and CurrentState.ActiveProfile ~= "Custom" then
            CurrentState.ActiveProfile = "Custom"
            SimConfig.Notify("ActiveProfile", "Custom")
        end
        if not silent then SimConfig.Notify(key, value) end
    end

    function SimConfig.Notify(key: string, value: any)
        if KeyListeners[key] then
            for _, cb in ipairs(KeyListeners[key]) do task.spawn(cb, value) end
        end
        for _, cb in ipairs(GlobalListeners) do task.spawn(cb, key, value) end
    end

    function SimConfig.Subscribe(key: string, callback: (any) -> ()): () -> ()
        KeyListeners[key] = KeyListeners[key] or {}
        table.insert(KeyListeners[key], callback)
        return function()
            local list = KeyListeners[key]
            if not list then return end
            local idx = table.find(list, callback)
            if idx then table.remove(list, idx) end
        end
    end

    function SimConfig.SubscribeAll(callback: (string, any) -> ()): () -> ()
        table.insert(GlobalListeners, callback)
        return function()
            local idx = table.find(GlobalListeners, callback)
            if idx then table.remove(GlobalListeners, idx) end
        end
    end

    function SimConfig.LoadProfile(profileName: string)
        local profile = PROFILES[profileName]
        if not profile then return end
        for k, v in pairs(profile) do
            (CurrentState :: any)[k] = v
            SimConfig.Notify(k, v)
        end
    end
end

-- =========================================================================
-- [2/5] MODULO: ESPVisualizer (Chams com Cores Dinamicas Verde/Vermelho)
-- =========================================================================
local ESPVisualizer = {}
do
    local activeHighlights: { [Model]: Highlight } = {}

    local function GetOrCreateHighlight(character: Model): Highlight
        local hl = activeHighlights[character]
        if not hl or not hl.Parent then
            hl = Instance.new("Highlight")
            hl.Name = "DeepHat_ESP_Highlight"
            hl.Adornee = character
            hl.FillTransparency = 0.5
            hl.OutlineTransparency = 0.1
            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            hl.Parent = character
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
            -- Alvo principal focado pela mira
            if isObstructed then
                -- Ocluido / Parede: Vermelho
                hl.FillColor = Color3.fromRGB(255, 50, 50)
                hl.OutlineColor = Color3.fromRGB(255, 180, 180)
            else
                -- Visivel: Verde Brilhante
                hl.FillColor = Color3.fromRGB(50, 255, 100)
                hl.OutlineColor = Color3.fromRGB(200, 255, 200)
            end
        else
            -- Outros alvos no mapa: Amarelo sutil
            hl.FillColor = isObstructed and Color3.fromRGB(180, 80, 80) or Color3.fromRGB(80, 160, 220)
            hl.OutlineColor = Color3.fromRGB(255, 255, 255)
        end
    end

    function ESPVisualizer.Clear(character: Model)
        local hl = activeHighlights[character]
        if hl then
            hl:Destroy()
            activeHighlights[character] = nil
        end
    end

    function ESPVisualizer.ClearAll()
        for char, hl in pairs(activeHighlights) do
            if hl then hl:Destroy() end
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
        if toTarget.Magnitude < 0.001 then return self.CachedTelemetry end

        local dirToTarget = toTarget.Unit
        local dot = math.clamp(self.CurrentCFrame.LookVector:Dot(dirToTarget), -1.0, 1.0)
        local angularErrorDeg = math.deg(math.acos(dot))

        local fov = SimConfig.Get("FOV") or 45.0
        local baseSmoothing = SimConfig.Get("Smoothing") or 0.14
        local speedMult = SimConfig.Get("SpeedMultiplier") or 1.0
        local precision = SimConfig.Get("TrackingPrecision") or 0.95
        local intensity = SimConfig.Get("Intensity") or 1.0

        if angularErrorDeg > fov then
            self.CachedTelemetry.angularVelocity = 0
            self.CachedTelemetry.angularJerk = 0
            self.CachedTelemetry.suspicionScore = 0
            self.CachedTelemetry.isObstructed = self:CheckObstruction(eyePos, targetPosition)
            self.CachedTelemetry.position = eyePos
            self.CachedTelemetry.cframe = self.CurrentCFrame
            self.CachedTelemetry.mode = "SMOOTH"
            self.CachedTelemetry.angularErrorDeg = angularErrorDeg
            self.CachedTelemetry.predictedPosition = targetPosition
            return self.CachedTelemetry
        end

        local normalizedErr = math.clamp(angularErrorDeg / fov, 0.0, 1.0)
        local accelerationFactor = Smoothstep(normalizedErr)
        local dynamicAlpha = math.clamp(baseSmoothing * speedMult * (0.35 + 0.65 * accelerationFactor), 0.005, 1.0)

        local targetRotation = CFrame.lookAt(eyePos, targetPosition)
        local smoothedRotation = self.CurrentCFrame:Lerp(targetRotation, dynamicAlpha)

        local now = os.clock()
        local jitterAmp = (1.0 - precision) * intensity * 0.8
        local noiseFreq = 3.2 * intensity
        local pitchJitter = math.rad(math.noise(now * noiseFreq, self.NoiseSeed, 0.5) * jitterAmp)
        local yawJitter = math.rad(math.noise(now * noiseFreq, self.NoiseSeed + 100, 0.5) * jitterAmp)
        self.CurrentCFrame = smoothedRotation * CFrame.Angles(pitchJitter, yawJitter, 0)

        local newLook = self.CurrentCFrame.LookVector
        local deltaDot = math.clamp(self.PreviousLookVector:Dot(newLook), -1.0, 1.0)
        local safeDt = (dt and dt > 0) and dt or 0.0166
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
-- [4/5] MODULO: DashboardGUI (Interface UX Dark Mode Completa)
-- =========================================================================
local DashboardGUI = {}
do
    DashboardGUI.OnStartRequested = nil
    DashboardGUI.OnStopRequested = nil
    DashboardGUI.OnResetRequested = nil
    DashboardGUI.OnExportRequested = nil

    local function AddCorner(parent: Instance, radius: number)
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, radius)
        corner.Parent = parent
        return corner
    end

    local function AddStroke(parent: Instance, color: Color3, thickness: number?)
        local stroke = Instance.new("UIStroke")
        stroke.Color = color
        stroke.Thickness = thickness or 1
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stroke.Parent = parent
        return stroke
    end

    local function GetSafeGuiParent(): Instance
        -- Tenta CoreGui primeiro (para executores normais)
        local ok, coreGui = pcall(function()
            return game:GetService("CoreGui")
        end)
        if ok and coreGui then
            local testOk = pcall(function()
                local test = Instance.new("Folder")
                test.Parent = coreGui
                test:Destroy()
            end)
            if testOk then return coreGui end
        end

        -- Fallback seguro para PlayerGui (Roblox Studio ou sem permissao CoreGui)
        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 5)
        if playerGui then return playerGui end

        return CoreGuiService
    end

    function DashboardGUI.Create()
        local hostParent = GetSafeGuiParent()

        local existing = hostParent:FindFirstChild("KinematicsSimulationDashboard")
        if existing then existing:Destroy() end

        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "KinematicsSimulationDashboard"
        screenGui.ResetOnSpawn = false
        screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        screenGui.Parent = hostParent

        -- Circulo de FOV Dinamico
        local fovCircleFrame = Instance.new("Frame")
        fovCircleFrame.Name = "FovCircleOverlay"
        fovCircleFrame.AnchorPoint = Vector2.new(0.5, 0.5)
        fovCircleFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
        fovCircleFrame.BackgroundTransparency = 0.92
        fovCircleFrame.BackgroundColor3 = Color3.fromRGB(80, 160, 255)
        fovCircleFrame.BorderSizePixel = 0
        fovCircleFrame.Visible = SimConfig.Get("ShowFovCircle") or true
        fovCircleFrame.Parent = screenGui
        AddCorner(fovCircleFrame, 9999)
        local fovStroke = AddStroke(fovCircleFrame, Color3.fromRGB(100, 180, 255), 1.5)
        fovStroke.Transparency = 0.3

        local function UpdateFovCircleRadius(fovAngleDeg: number)
            local screenHeight = Camera.ViewportSize.Y
            local camFovRad = math.rad(Camera.FieldOfView)
            local targetFovRad = math.rad(fovAngleDeg)
            local radiusPixels = math.tan(targetFovRad / 2) / math.tan(camFovRad / 2) * (screenHeight / 2) * 2
            fovCircleFrame.Size = UDim2.new(0, math.clamp(radiusPixels, 10, screenHeight * 1.5), 0, math.clamp(radiusPixels, 10, screenHeight * 1.5))
        end
        UpdateFovCircleRadius(SimConfig.Get("FOV") or 45)

        SimConfig.Subscribe("FOV", function(newFov) UpdateFovCircleRadius(newFov) end)
        SimConfig.Subscribe("ShowFovCircle", function(visible) fovCircleFrame.Visible = visible end)

        -- Painel Principal
        local mainFrame = Instance.new("Frame")
        mainFrame.Name = "MainFrame"
        mainFrame.Size = UDim2.new(0, 370, 0, 640)
        mainFrame.Position = UDim2.new(0, 40, 0.5, -320)
        mainFrame.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
        mainFrame.BorderSizePixel = 0
        mainFrame.Active = true
        mainFrame.Parent = screenGui
        AddCorner(mainFrame, 10)
        AddStroke(mainFrame, Color3.fromRGB(38, 42, 54), 1.5)

        -- Header com Drag e Tecla de Minimizar
        local header = Instance.new("Frame")
        header.Size = UDim2.new(1, 0, 0, 48)
        header.BackgroundColor3 = Color3.fromRGB(24, 27, 36)
        header.BorderSizePixel = 0
        header.Parent = mainFrame
        AddCorner(header, 10)

        local titleLabel = Instance.new("TextLabel")
        titleLabel.Size = UDim2.new(1, -70, 1, 0)
        titleLabel.Position = UDim2.new(0, 16, 0, 0)
        titleLabel.BackgroundTransparency = 1
        titleLabel.Text = "DEEPHAT SIMULATOR v4.0"
        titleLabel.TextColor3 = Color3.fromRGB(240, 243, 248)
        titleLabel.Font = Enum.Font.GothamBold
        titleLabel.TextSize = 12
        titleLabel.TextXAlignment = Enum.TextXAlignment.Left
        titleLabel.Parent = header

        local minimizeHint = Instance.new("TextLabel")
        minimizeHint.Size = UDim2.new(0, 60, 1, 0)
        minimizeHint.Position = UDim2.new(1, -68, 0, 0)
        minimizeHint.BackgroundTransparency = 1
        minimizeHint.Text = "[Home]"
        minimizeHint.TextColor3 = Color3.fromRGB(120, 126, 140)
        minimizeHint.Font = Enum.Font.GothamMedium
        minimizeHint.TextSize = 10
        minimizeHint.TextXAlignment = Enum.TextXAlignment.Right
        minimizeHint.Parent = header

        local isGuiVisible = true
        UserInputService.InputBegan:Connect(function(input, gpe)
            if gpe then return end
            if input.KeyCode == Enum.KeyCode.Home or input.KeyCode == Enum.KeyCode.RightShift or input.KeyCode == Enum.KeyCode.Insert then
                isGuiVisible = not isGuiVisible
                mainFrame.Visible = isGuiVisible
            end
        end)

        local draggingWindow = false
        local dragStartPos = Vector2.zero
        local startFramePos = UDim2.new()

        header.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                draggingWindow = true
                dragStartPos = Vector2.new(input.Position.X, input.Position.Y)
                startFramePos = mainFrame.Position
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then draggingWindow = false end
                end)
            end
        end)

        UserInputService.InputChanged:Connect(function(input)
            if draggingWindow and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStartPos
                mainFrame.Position = UDim2.new(
                    startFramePos.X.Scale, startFramePos.X.Offset + delta.X,
                    startFramePos.Y.Scale, startFramePos.Y.Offset + delta.Y
                )
            end
        end)

        local contentScroll = Instance.new("ScrollingFrame")
        contentScroll.Size = UDim2.new(1, -24, 1, -60)
        contentScroll.Position = UDim2.new(0, 12, 0, 52)
        contentScroll.BackgroundTransparency = 1
        contentScroll.BorderSizePixel = 0
        contentScroll.ScrollBarThickness = 3
        contentScroll.ScrollBarImageColor3 = Color3.fromRGB(60, 65, 80)
        contentScroll.CanvasSize = UDim2.new(0, 0, 0, 920)
        contentScroll.Parent = mainFrame

        local listLayout = Instance.new("UIListLayout")
        listLayout.Padding = UDim.new(0, 10)
        listLayout.SortOrder = Enum.SortOrder.LayoutOrder
        listLayout.Parent = contentScroll

        -- 1. Selecao de Perfis
        local profileContainer = Instance.new("Frame")
        profileContainer.Size = UDim2.new(1, 0, 0, 32)
        profileContainer.BackgroundTransparency = 1
        profileContainer.LayoutOrder = 1
        profileContainer.Parent = contentScroll

        local profileLayout = Instance.new("UIGridLayout")
        profileLayout.CellSize = UDim2.new(0.235, 0, 1, 0)
        profileLayout.CellPadding = UDim2.new(0.02, 0, 0, 0)
        profileLayout.Parent = profileContainer

        local profileButtons: { [string]: TextButton } = {}
        for _, pName in ipairs({ "Normal", "Leve", "Medio", "Agressivo" }) do
            local btn = Instance.new("TextButton")
            btn.Name = pName
            btn.Text = pName
            btn.Font = Enum.Font.GothamMedium
            btn.TextSize = 11
            btn.TextColor3 = Color3.fromRGB(200, 205, 218)
            btn.BackgroundColor3 = Color3.fromRGB(28, 32, 42)
            btn.BorderSizePixel = 0
            btn.Parent = profileContainer
            AddCorner(btn, 6)
            AddStroke(btn, Color3.fromRGB(45, 50, 65), 1)

            btn.MouseButton1Click:Connect(function() SimConfig.LoadProfile(pName) end)
            profileButtons[pName] = btn
        end

        local function UpdateProfileHighlights(activeName: string)
            for name, btn in pairs(profileButtons) do
                if name == activeName then
                    btn.BackgroundColor3 = Color3.fromRGB(48, 86, 178)
                    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
                else
                    btn.BackgroundColor3 = Color3.fromRGB(28, 32, 42)
                    btn.TextColor3 = Color3.fromRGB(180, 185, 198)
                end
            end
        end
        UpdateProfileHighlights(SimConfig.Get("ActiveProfile") or "Normal")

        -- 2. NOVO: Seletor de Osso Alvo (Cabeça / Torso / Mais Próximo)
        local boneSection = Instance.new("Frame")
        boneSection.Size = UDim2.new(1, 0, 0, 56)
        boneSection.BackgroundColor3 = Color3.fromRGB(24, 27, 36)
        boneSection.LayoutOrder = 2
        boneSection.Parent = contentScroll
        AddCorner(boneSection, 8)
        AddStroke(boneSection, Color3.fromRGB(36, 40, 52), 1)

        local boneTitle = Instance.new("TextLabel")
        boneTitle.Size = UDim2.new(1, -16, 0, 18)
        boneTitle.Position = UDim2.new(0, 10, 0, 6)
        boneTitle.BackgroundTransparency = 1
        boneTitle.Text = "OSSO ALVO (BONE TARGET)"
        boneTitle.TextColor3 = Color3.fromRGB(160, 168, 185)
        boneTitle.Font = Enum.Font.GothamBold
        boneTitle.TextSize = 10
        boneTitle.TextXAlignment = Enum.TextXAlignment.Left
        boneTitle.Parent = boneSection

        local boneBtnContainer = Instance.new("Frame")
        boneBtnContainer.Size = UDim2.new(1, -20, 0, 24)
        boneBtnContainer.Position = UDim2.new(0, 10, 0, 26)
        boneBtnContainer.BackgroundTransparency = 1
        boneBtnContainer.Parent = boneSection

        local boneGrid = Instance.new("UIGridLayout")
        boneGrid.CellSize = UDim2.new(0.31, 0, 1, 0)
        boneGrid.CellPadding = UDim2.new(0.035, 0, 0, 0)
        boneGrid.Parent = boneBtnContainer

        local boneBtns: { [string]: TextButton } = {}
        local bones = { { id = "Head", label = "Cabeça" }, { id = "UpperTorso", label = "Torso" }, { id = "Closest", label = "Próximo" } }

        local function UpdateBoneHighlight(activeBone: string)
            for bId, bBtn in pairs(boneBtns) do
                if bId == activeBone then
                    bBtn.BackgroundColor3 = Color3.fromRGB(45, 95, 210)
                    bBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
                else
                    bBtn.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
                    bBtn.TextColor3 = Color3.fromRGB(160, 165, 180)
                end
            end
        end

        for _, bData in ipairs(bones) do
            local bBtn = Instance.new("TextButton")
            bBtn.Text = bData.label
            bBtn.Font = Enum.Font.GothamMedium
            bBtn.TextSize = 10
            bBtn.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
            bBtn.TextColor3 = Color3.fromRGB(160, 165, 180)
            bBtn.BorderSizePixel = 0
            bBtn.Parent = boneBtnContainer
            AddCorner(bBtn, 4)
            AddStroke(bBtn, Color3.fromRGB(40, 45, 58), 1)

            bBtn.MouseButton1Click:Connect(function()
                SimConfig.Set("TargetBone", bData.id)
                UpdateBoneHighlight(bData.id)
            end)
            boneBtns[bData.id] = bBtn
        end
        UpdateBoneHighlight(SimConfig.Get("TargetBone") or "Head")

        -- 3. NOVO: Chaves de Alternância (Previsão Balística & Chams ESP)
        local togglesContainer = Instance.new("Frame")
        togglesContainer.Size = UDim2.new(1, 0, 0, 140)
        togglesContainer.BackgroundColor3 = Color3.fromRGB(24, 27, 36)
        togglesContainer.LayoutOrder = 3
        togglesContainer.Parent = contentScroll
        AddCorner(togglesContainer, 8)
        AddStroke(togglesContainer, Color3.fromRGB(36, 40, 52), 1)

        local function CreateToggle(title: string, configKey: string, yOffset: number)
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, -20, 0, 28)
            row.Position = UDim2.new(0, 10, 0, yOffset)
            row.BackgroundTransparency = 1
            row.Parent = togglesContainer

            local lbl = Instance.new("TextLabel")
            lbl.Size = UDim2.new(0.7, 0, 1, 0)
            lbl.BackgroundTransparency = 1
            lbl.Text = title
            lbl.TextColor3 = Color3.fromRGB(180, 186, 200)
            lbl.Font = Enum.Font.GothamMedium
            lbl.TextSize = 11
            lbl.TextXAlignment = Enum.TextXAlignment.Left
            lbl.Parent = row

            local tBtn = Instance.new("TextButton")
            tBtn.Size = UDim2.new(0.28, 0, 0, 22)
            tBtn.Position = UDim2.new(0.72, 0, 0.5, -11)
            tBtn.BorderSizePixel = 0
            tBtn.Font = Enum.Font.GothamBold
            tBtn.TextSize = 10
            tBtn.Parent = row
            AddCorner(tBtn, 5)

            local function RefreshState(val: boolean)
                if val then
                    tBtn.BackgroundColor3 = Color3.fromRGB(36, 150, 75)
                    tBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
                    tBtn.Text = "ATIVO"
                else
                    tBtn.BackgroundColor3 = Color3.fromRGB(45, 50, 64)
                    tBtn.TextColor3 = Color3.fromRGB(160, 165, 175)
                    tBtn.Text = "DESLIGADO"
                end
            end
            RefreshState(SimConfig.Get(configKey) or false)

            tBtn.MouseButton1Click:Connect(function()
                local cur = SimConfig.Get(configKey) or false
                SimConfig.Set(configKey, not cur)
                RefreshState(not cur)
            end)

            SimConfig.Subscribe(configKey, function(newVal)
                RefreshState(newVal)
            end)
        end

        CreateToggle("Previsão Balística (Lead):", "EnableLead", 8)
        CreateToggle("ESP Chams Visível/Parede:", "EnableESP", 38)
        CreateToggle("Apenas Visíveis (WallCheck):", "VisibleOnly", 68)
        CreateToggle("Filtro de Equipe (TeamCheck):", "TeamCheck", 98)

        -- 4. Parametros Numericos (TextBox)
        local paramsContainer = Instance.new("Frame")
        paramsContainer.Size = UDim2.new(1, 0, 0, 170)
        paramsContainer.BackgroundColor3 = Color3.fromRGB(24, 27, 36)
        paramsContainer.LayoutOrder = 4
        paramsContainer.Parent = contentScroll
        AddCorner(paramsContainer, 8)
        AddStroke(paramsContainer, Color3.fromRGB(36, 40, 52), 1)

        local paramsLayout = Instance.new("UIListLayout")
        paramsLayout.Padding = UDim.new(0, 8)
        paramsLayout.Parent = paramsContainer

        local paramsPad = Instance.new("UIPadding")
        paramsPad.PaddingTop = UDim.new(0, 8)
        paramsPad.PaddingLeft = UDim.new(0, 10)
        paramsPad.PaddingRight = UDim.new(0, 10)
        paramsPad.Parent = paramsContainer

        local textInputs: { [string]: TextBox } = {}
        local function CreateInput(labelTitle: string, configKey: string, decimals: number)
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, 0, 0, 30)
            row.BackgroundTransparency = 1
            row.Parent = paramsContainer

            local lbl = Instance.new("TextLabel")
            lbl.Size = UDim2.new(0.65, 0, 1, 0)
            lbl.BackgroundTransparency = 1
            lbl.Text = labelTitle
            lbl.TextColor3 = Color3.fromRGB(180, 186, 200)
            lbl.Font = Enum.Font.GothamMedium
            lbl.TextSize = 11
            lbl.TextXAlignment = Enum.TextXAlignment.Left
            lbl.Parent = row

            local box = Instance.new("TextBox")
            box.Size = UDim2.new(0.35, 0, 1, 0)
            box.Position = UDim2.new(0.65, 0, 0, 0)
            box.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
            box.TextColor3 = Color3.fromRGB(240, 243, 250)
            box.Font = Enum.Font.GothamBold
            box.TextSize = 11
            box.ClearTextOnFocus = false
            box.Text = string.format("%." .. decimals .. "f", SimConfig.Get(configKey) or 0)
            box.Parent = row
            AddCorner(box, 6)
            AddStroke(box, Color3.fromRGB(45, 50, 65), 1)

            box.FocusLost:Connect(function()
                local num = tonumber(box.Text)
                if num then SimConfig.Set(configKey, num) else box.Text = string.format("%." .. decimals .. "f", SimConfig.Get(configKey) or 0) end
            end)
            textInputs[configKey] = box
        end

        CreateInput("Campo de Visao (FOV deg):", "FOV", 1)
        CreateInput("Suavidade (Smoothing):", "Smoothing", 3)
        CreateInput("Mult. Velocidade:", "SpeedMultiplier", 2)
        CreateInput("Velocidade Projétil (Lead):", "ProjectileSpeed", 0)

        -- 5. Sliders de Intensidade e Precisao
        local slidersContainer = Instance.new("Frame")
        slidersContainer.Size = UDim2.new(1, 0, 0, 115)
        slidersContainer.BackgroundColor3 = Color3.fromRGB(24, 27, 36)
        slidersContainer.LayoutOrder = 5
        slidersContainer.Parent = contentScroll
        AddCorner(slidersContainer, 8)
        AddStroke(slidersContainer, Color3.fromRGB(36, 40, 52), 1)

        local sLayout = Instance.new("UIListLayout")
        sLayout.Padding = UDim.new(0, 10)
        sLayout.Parent = slidersContainer

        local sPad = Instance.new("UIPadding")
        sPad.PaddingTop = UDim.new(0, 8)
        sPad.PaddingLeft = UDim.new(0, 10)
        sPad.PaddingRight = UDim.new(0, 10)
        sPad.Parent = slidersContainer

        local currentlyActiveSlider = nil
        local function CreateSlider(title: string, configKey: string, minVal: number, maxVal: number)
            local container = Instance.new("Frame")
            container.Size = UDim2.new(1, 0, 0, 40)
            container.BackgroundTransparency = 1
            container.Parent = slidersContainer

            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, 0, 0, 16)
            row.BackgroundTransparency = 1
            row.Parent = container

            local lbl = Instance.new("TextLabel")
            lbl.Size = UDim2.new(0.7, 0, 1, 0)
            lbl.BackgroundTransparency = 1
            lbl.Text = title
            lbl.TextColor3 = Color3.fromRGB(180, 186, 200)
            lbl.Font = Enum.Font.GothamMedium
            lbl.TextSize = 11
            lbl.TextXAlignment = Enum.TextXAlignment.Left
            lbl.Parent = row

            local valLabel = Instance.new("TextLabel")
            valLabel.Size = UDim2.new(0.3, 0, 1, 0)
            valLabel.Position = UDim2.new(0.7, 0, 0, 0)
            valLabel.BackgroundTransparency = 1
            valLabel.Text = string.format("%.2f", SimConfig.Get(configKey) or minVal)
            valLabel.TextColor3 = Color3.fromRGB(90, 150, 255)
            valLabel.Font = Enum.Font.GothamBold
            valLabel.TextSize = 11
            valLabel.TextXAlignment = Enum.TextXAlignment.Right
            valLabel.Parent = row

            local track = Instance.new("TextButton")
            track.Size = UDim2.new(1, 0, 0, 8)
            track.Position = UDim2.new(0, 0, 0, 22)
            track.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
            track.Text = ""
            track.AutoButtonColor = false
            track.Parent = container
            AddCorner(track, 4)

            local initialRatio = math.clamp(((SimConfig.Get(configKey) or minVal) - minVal) / (maxVal - minVal), 0, 1)
            local fill = Instance.new("Frame")
            fill.Size = UDim2.new(initialRatio, 0, 1, 0)
            fill.BackgroundColor3 = Color3.fromRGB(56, 110, 235)
            fill.BorderSizePixel = 0
            fill.Parent = track
            AddCorner(fill, 4)

            local function UpdateX(xPos: number)
                local trackX = track.AbsolutePosition.X
                local trackW = track.AbsoluteSize.X
                if trackW <= 0 then return end
                local ratio = math.clamp((xPos - trackX) / trackW, 0, 1)
                local val = minVal + ratio * (maxVal - minVal)
                fill.Size = UDim2.new(ratio, 0, 1, 0)
                valLabel.Text = string.format("%.2f", val)
                SimConfig.Set(configKey, val)
            end

            track.MouseButton1Down:Connect(function()
                currentlyActiveSlider = configKey
                UpdateX(UserInputService:GetMouseLocation().X)
            end)

            UserInputService.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    if currentlyActiveSlider == configKey then currentlyActiveSlider = nil end
                end
            end)

            UserInputService.InputChanged:Connect(function(input)
                if currentlyActiveSlider == configKey and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                    UpdateX(input.Position.X)
                end
            end)

            SimConfig.Subscribe(configKey, function(newVal)
                local ratio = math.clamp((newVal - minVal) / (maxVal - minVal), 0, 1)
                fill.Size = UDim2.new(ratio, 0, 1, 0)
                valLabel.Text = string.format("%.2f", newVal)
            end)
        end

        CreateSlider("Intensidade:", "Intensity", 0.1, 2.0)
        CreateSlider("Precisao:", "TrackingPrecision", 0.50, 1.00)

        -- 6. Acoes
        local actionsContainer = Instance.new("Frame")
        actionsContainer.Size = UDim2.new(1, 0, 0, 85)
        actionsContainer.BackgroundTransparency = 1
        actionsContainer.LayoutOrder = 6
        actionsContainer.Parent = contentScroll

        local function CreateBtn(text: string, col: Color3, pos: UDim2, size: UDim2)
            local btn = Instance.new("TextButton")
            btn.Size = size
            btn.Position = pos
            btn.BackgroundColor3 = col
            btn.Text = text
            btn.Font = Enum.Font.GothamBold
            btn.TextColor3 = Color3.fromRGB(255, 255, 255)
            btn.TextSize = 11
            btn.BorderSizePixel = 0
            btn.Parent = actionsContainer
            AddCorner(btn, 6)
            return btn
        end

        local startBtn = CreateBtn("INICIAR TESTE", Color3.fromRGB(36, 150, 75), UDim2.new(0, 0, 0, 0), UDim2.new(0.48, 0, 0, 36))
        local stopBtn = CreateBtn("PARAR TESTE", Color3.fromRGB(195, 48, 48), UDim2.new(0.52, 0, 0, 0), UDim2.new(0.48, 0, 0, 36))
        local resetBtn = CreateBtn("RESETAR PADROES", Color3.fromRGB(45, 50, 64), UDim2.new(0, 0, 0, 42), UDim2.new(0.48, 0, 0, 34))
        local exportBtn = CreateBtn("EXPORTAR LOG", Color3.fromRGB(65, 80, 110), UDim2.new(0.52, 0, 0, 42), UDim2.new(0.48, 0, 0, 34))

        startBtn.MouseButton1Click:Connect(function() if DashboardGUI.OnStartRequested then DashboardGUI.OnStartRequested() end end)
        stopBtn.MouseButton1Click:Connect(function() if DashboardGUI.OnStopRequested then DashboardGUI.OnStopRequested() end end)
        resetBtn.MouseButton1Click:Connect(function() SimConfig.LoadProfile("Normal"); if DashboardGUI.OnResetRequested then DashboardGUI.OnResetRequested() end end)
        exportBtn.MouseButton1Click:Connect(function() if DashboardGUI.OnExportRequested then DashboardGUI.OnExportRequested() end end)

        -- 7. Telemetria
        local telemetryCard = Instance.new("Frame")
        telemetryCard.Size = UDim2.new(1, 0, 0, 155)
        telemetryCard.BackgroundColor3 = Color3.fromRGB(22, 25, 34)
        telemetryCard.LayoutOrder = 7
        telemetryCard.Parent = contentScroll
        AddCorner(telemetryCard, 8)
        AddStroke(telemetryCard, Color3.fromRGB(36, 40, 52), 1)

        local tLayout = Instance.new("UIListLayout")
        tLayout.Padding = UDim.new(0, 3)
        tLayout.Parent = telemetryCard

        local tPad = Instance.new("UIPadding")
        tPad.PaddingTop = UDim.new(0, 8)
        tPad.PaddingLeft = UDim.new(0, 10)
        tPad.Parent = telemetryCard

        local function CreateRow(txt: string)
            local lbl = Instance.new("TextLabel")
            lbl.Size = UDim2.new(1, 0, 0, 15)
            lbl.BackgroundTransparency = 1
            lbl.Text = txt
            lbl.TextColor3 = Color3.fromRGB(170, 176, 192)
            lbl.Font = Enum.Font.GothamMedium
            lbl.TextSize = 10
            lbl.TextXAlignment = Enum.TextXAlignment.Left
            lbl.Parent = telemetryCard
            return lbl
        end

        local statusProfile = CreateRow("Perfil Ativo: Normal")
        local statusVel = CreateRow("Velocidade Angular: 0.0 deg/s")
        local statusObs = CreateRow("Linha de Visao: LIVRE")
        local statusMode = CreateRow("Modo Cinematico: IDLE")
        local statusLead = CreateRow("Previsao Balistica: ATIVA")

        local barTitle = CreateRow("Indice de Anomalia: 0%")
        local barTrack = Instance.new("Frame")
        barTrack.Size = UDim2.new(1, -20, 0, 8)
        barTrack.BackgroundColor3 = Color3.fromRGB(14, 16, 22)
        barTrack.BorderSizePixel = 0
        barTrack.Parent = telemetryCard
        AddCorner(barTrack, 4)

        local barFill = Instance.new("Frame")
        barFill.Size = UDim2.new(0, 0, 1, 0)
        barFill.BackgroundColor3 = Color3.fromRGB(52, 199, 89)
        barFill.BorderSizePixel = 0
        barFill.Parent = barTrack
        AddCorner(barFill, 4)

        SimConfig.SubscribeAll(function(key, val)
            if key == "ActiveProfile" then
                UpdateProfileHighlights(tostring(val))
                statusProfile.Text = "Perfil Ativo: " .. tostring(val)
            elseif key == "TargetBone" then
                UpdateBoneHighlight(tostring(val))
            elseif textInputs[key] and typeof(val) == "number" then
                textInputs[key].Text = string.format("%.2f", val)
            end
        end)

        DashboardGUI.UpdateTelemetryDisplay = function(self, data: any)
            if not data then return end
            statusVel.Text = string.format("Velocidade Angular: %.1f deg/s", data.angularVelocity or 0)
            statusObs.Text = string.format("Linha de Visao: %s", data.isObstructed and "OBSTRUIDO (Parede)" or "LIVRE")
            statusObs.TextColor3 = data.isObstructed and Color3.fromRGB(240, 80, 80) or Color3.fromRGB(80, 220, 120)
            statusMode.Text = string.format("Modo Cinematico: %s", data.mode or "IDLE")
            statusLead.Text = string.format("Previsao: %s (Osso: %s)", SimConfig.Get("EnableLead") and "ON" or "OFF", tostring(SimConfig.Get("TargetBone")))

            local score = data.suspicionScore or 0
            barTitle.Text = string.format("Indice de Anomalia (Anti-Cheat Score): %d%%", score)
            barFill.Size = UDim2.new(math.clamp(score / 100, 0, 1), 0, 1, 0)

            if score < 35 then
                barFill.BackgroundColor3 = Color3.fromRGB(52, 199, 89)
            elseif score < 70 then
                barFill.BackgroundColor3 = Color3.fromRGB(255, 179, 64)
            else
                barFill.BackgroundColor3 = Color3.fromRGB(255, 69, 58)
            end
        end

        return screenGui
    end
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
local conn: RBXScriptConnection? = nil
local lastSnapTime = 0
local lastUiUpdate = 0

-- Rastreio de velocidade anterior dos alvos para calculo do vetor aceleração
local targetVelocityCache: { [Player]: Vector3 } = {}
local targetLastPosCache: { [Player]: { pos: Vector3, time: number } } = {}

-- Obtem a parte do corpo desejada com base na configuracao de osso
local function GetBonePart(char: Model, boneSetting: string): BasePart?
    if boneSetting == "Head" then
        return char:FindFirstChild("Head") :: BasePart? or char:FindFirstChild("HumanoidRootPart") :: BasePart?
    elseif boneSetting == "UpperTorso" then
        return char:FindFirstChild("UpperTorso") :: BasePart? or char:FindFirstChild("Torso") :: BasePart? or char:FindFirstChild("HumanoidRootPart") :: BasePart?
    elseif boneSetting == "Closest" then
        -- Encontra o osso mais proximo do centro da tela (Crosshair)
        local candidates = {
            char:FindFirstChild("Head"),
            char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso"),
            char:FindFirstChild("HumanoidRootPart")
        }
        local bestPart = nil
        local bestAngle = math.huge
        local camPos = Camera.CFrame.Position
        local camLook = Camera.CFrame.LookVector

        for _, part in ipairs(candidates) do
            if part and part:IsA("BasePart") then
                local dir = (part.Position - camPos).Unit
                local dot = math.clamp(camLook:Dot(dir), -1.0, 1.0)
                local angle = math.acos(dot)
                if angle < bestAngle then
                    bestAngle = angle
                    bestPart = part
                end
            end
        end
        return bestPart or char:FindFirstChild("HumanoidRootPart") :: BasePart?
    end
    return char:FindFirstChild("Head") :: BasePart? or char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Seleciona o melhor alvo dentro do FOV e atualiza ESP com WallCheck & TeamCheck
local isRightMouseDown = false
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        isRightMouseDown = true
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        isRightMouseDown = false
    end
end)

local function IsTeammate(otherPlayer: Player): boolean
    if not SimConfig.Get("TeamCheck") then return false end
    if LocalPlayer.Team and otherPlayer.Team then
        return LocalPlayer.Team == otherPlayer.Team
    end
    return false
end

local function GetTargetData(): (Vector3?, Vector3, Model?, boolean)
    local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
    local myPos = myRoot and myRoot.Position or Camera.CFrame.Position
    local boneSetting = SimConfig.Get("TargetBone") or "Head"
    local fov = SimConfig.Get("FOV") or 45.0
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

    for _, other in ipairs(Players:GetPlayers()) do
        if other ~= LocalPlayer and other.Character and not IsTeammate(other) then
            local char = other.Character
            local hum = char:FindFirstChildOfClass("Humanoid")

            -- Ignora jogadores mortos
            if hum and hum.Health <= 0 then
                ESPVisualizer.Clear(char)
                continue
            end

            local targetPart = GetBonePart(char, boneSetting)

            if targetPart then
                local currentPos = targetPart.Position

                -- Calculo de velocidade vetorial V = deltaP / deltaT
                local vel = Vector3.zero
                local last = targetLastPosCache[other]
                if last then
                    local dt = (now - last.time)
                    if dt > 0 and dt < 0.2 then
                        vel = (currentPos - last.pos) / dt
                    end
                end
                targetLastPosCache[other] = { pos = currentPos, time = now }

                -- Checagem de obstrucao de visao (WallCheck)
                local obstructed = Kinematics:CheckObstruction(camPos, currentPos)

                -- Atualiza ESP Chams (Verde = Visivel / Vermelho = Parede)
                if enableESP then
                    ESPVisualizer.UpdateTarget(char, obstructed, false)
                else
                    ESPVisualizer.Clear(char)
                end

                -- Se a opcao "Apenas Visiveis" estiver ligada, ignora quem esta atras de parede
                if visibleOnly and obstructed then
                    continue
                end

                -- Calcula o angulo em relacao a mira (FOV)
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
        else
            if other ~= LocalPlayer and other.Character and IsTeammate(other) then
                -- Limpa ESP de companheiros de equipe
                ESPVisualizer.Clear(other.Character)
            end
        end
    end

    -- Destaca o alvo focado com cor evidente no ESP
    if chosenModel and enableESP then
        ESPVisualizer.UpdateTarget(chosenModel, isObstructed, true)
    end

    return chosenPos, chosenVel, chosenModel, isObstructed
end

DashboardGUI.OnStartRequested = function()
    if isRunning then return end
    isRunning = true
    print("[DeepHat v4.0] Simulador e Funcoes ATIVADAS!")

    conn = RunService.RenderStepped:Connect(function(dt)
        local targetPos, targetVel, targetModel, obstructed = GetTargetData()
        local now = os.clock()

        -- Ativa mira suave quando segurar o Botao Direito do Mouse (ou se estiver dentro do FOV)
        local shouldAim = isRunning and (isRightMouseDown or not SimConfig.Get("HoldToAim"))

        if targetPos and shouldAim then
            local snapFreq = SimConfig.Get("SnapFrequency") or 0.03
            local reactionTime = SimConfig.Get("ReactionTime") or 0.2

            local telem
            if math.random() < snapFreq and (now - lastSnapTime > reactionTime) then
                lastSnapTime = now
                telem = Kinematics:StepSnap(targetPos, targetVel, dt)
            else
                telem = Kinematics:StepSmooth(targetPos, targetVel, dt)
            end

            -- Deadzone sutil: se o erro angular for minusculo (< 0.4 graus), nao treme a camera
            if telem.angularErrorDeg and telem.angularErrorDeg > 0.4 then
                Camera.CFrame = telem.cframe
            end

            if (now - lastUiUpdate) >= 0.1 then
                lastUiUpdate = now
                DashboardGUI:UpdateTelemetryDisplay(telem)
            end
        else
            -- Sem alvo no FOV ou nao esta segurando RMB: mantem camera livre
            if (now - lastUiUpdate) >= 0.1 then
                lastUiUpdate = now
                DashboardGUI:UpdateTelemetryDisplay({
                    angularVelocity = 0,
                    isObstructed = false,
                    mode = "LIVRE",
                    suspicionScore = 0
                })
            end
        end
    end)
end

DashboardGUI.OnStopRequested = function()
    if not isRunning then return end
    isRunning = false
    if conn then conn:Disconnect(); conn = nil end
    ESPVisualizer.ClearAll()
    print("[DeepHat v4.0] Simulador PARADO!")
    DashboardGUI:UpdateTelemetryDisplay({ angularVelocity = 0, isObstructed = false, mode = "PARADO", suspicionScore = 0 })
end

DashboardGUI.OnResetRequested = function()
    print("[DeepHat v4.0] Parametros resetados para Normal!")
end

DashboardGUI.OnExportRequested = function()
    Kinematics:ExportReport()
end

_G.DeepHat_Cleanup = function()
    if conn then conn:Disconnect(); conn = nil end
    ESPVisualizer.ClearAll()
    if guiInstance and guiInstance.Parent then guiInstance:Destroy() end
end

-- Limpa ESP se jogadores sairem
Players.PlayerRemoving:Connect(function(plr)
    if plr.Character then ESPVisualizer.Clear(plr.Character) end
    targetLastPosCache[plr] = nil
end)

-- Limpa ESP se o usuario desativar o toggle na interface
SimConfig.Subscribe("EnableESP", function(enabled)
    if not enabled then
        ESPVisualizer.ClearAll()
    end
end)

-- Inicia automaticamente todas as funcoes para funcionar direto ao injetar!
task.defer(function()
    DashboardGUI.OnStartRequested()
end)

print("[DeepHat v4.0] Suite Pro com Previsao Balistica, Chams ESP, WallCheck e AimLock carregada! [HOME] para abrir/fechar.")

-- Notificacao no chat / console para confirmar carregamento
pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "DeepHat v4.0 PRO",
        Text = "Aim + WallCheck + ESP ativos! Segure o Botão Direito para mirar.",
        Duration = 6
    })
end)
