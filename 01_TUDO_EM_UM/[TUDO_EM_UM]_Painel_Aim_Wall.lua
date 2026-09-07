--!strict
-- DeepHat_Standalone.lua
-- Versao Otimizada (High-Performance Single-File) para Execucao Remota via HttpGet / loadstring
-- Melhorias: Throttling de UI (zero lag), Raycast otimizado, Drag suave moderno e Garbage Collection reduzido.

-- Limpeza de instancia anterior caso re-executado
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
-- [1/3] MODULO: SimConfig (Central de Parametros + Observer Pattern)
-- =========================================================================
local SimConfig = {}
do
    local PROFILES = {
        ["Normal"] = { FOV = 45.0, Smoothing = 0.14, SpeedMultiplier = 1.0, TrackingPrecision = 0.95, SnapFrequency = 0.03, ReactionTime = 0.22, Intensity = 1.0, ActiveProfile = "Normal" },
        ["Leve"] = { FOV = 30.0, Smoothing = 0.25, SpeedMultiplier = 0.75, TrackingPrecision = 0.98, SnapFrequency = 0.00, ReactionTime = 0.28, Intensity = 0.6, ActiveProfile = "Leve" },
        ["Medio"] = { FOV = 60.0, Smoothing = 0.09, SpeedMultiplier = 1.4, TrackingPrecision = 0.90, SnapFrequency = 0.15, ReactionTime = 0.15, Intensity = 1.3, ActiveProfile = "Medio" },
        ["Agressivo"] = { FOV = 90.0, Smoothing = 0.02, SpeedMultiplier = 2.2, TrackingPrecision = 0.75, SnapFrequency = 0.65, ReactionTime = 0.05, Intensity = 2.0, ActiveProfile = "Agressivo" },
        ["Custom"] = { FOV = 45.0, Smoothing = 0.14, SpeedMultiplier = 1.0, TrackingPrecision = 0.95, SnapFrequency = 0.03, ReactionTime = 0.20, Intensity = 1.0, ActiveProfile = "Custom" }
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
-- [2/3] MODULO: AdvancedKinematics (Motor Fisico de Alta Performance)
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
        self.NoiseSeed = math.random(1000, 9999)

        local rayParams = RaycastParams.new()
        rayParams.FilterType = RaycastFilterType.Exclude
        rayParams.FilterDescendantsInstances = filterInstances or {}
        rayParams.IgnoreWater = true
        self.RayParams = rayParams

        self.CachedTelemetry = {
            angularVelocity = 0, isObstructed = false, position = Vector3.zero,
            cframe = self.CurrentCFrame, mode = "SMOOTH", angularErrorDeg = 0
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

    function AdvancedKinematics:StepSnap(targetPosition: Vector3, dt: number)
        local eyePos = self.CurrentCFrame.Position
        local toTarget = (targetPosition - eyePos)
        if toTarget.Magnitude < 0.001 then return self.CachedTelemetry end

        local dot = math.clamp(self.CurrentCFrame.LookVector:Dot(toTarget.Unit), -1.0, 1.0)
        local angularErrorDeg = math.deg(math.acos(dot))

        self.CurrentCFrame = CFrame.lookAt(eyePos, targetPosition)
        local safeDt = (dt and dt > 0) and dt or 0.0166

        self.CachedTelemetry.angularVelocity = angularErrorDeg / safeDt
        self.CachedTelemetry.isObstructed = self:CheckObstruction(eyePos, targetPosition)
        self.CachedTelemetry.position = eyePos
        self.CachedTelemetry.cframe = self.CurrentCFrame
        self.CachedTelemetry.mode = "SNAP"
        self.CachedTelemetry.angularErrorDeg = 0
        self.PreviousLookVector = self.CurrentCFrame.LookVector
        return self.CachedTelemetry
    end

    function AdvancedKinematics:StepSmooth(targetPosition: Vector3, dt: number)
        local eyePos = self.CurrentCFrame.Position
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
            self.CachedTelemetry.isObstructed = self:CheckObstruction(eyePos, targetPosition)
            self.CachedTelemetry.position = eyePos
            self.CachedTelemetry.cframe = self.CurrentCFrame
            self.CachedTelemetry.mode = "SMOOTH"
            self.CachedTelemetry.angularErrorDeg = angularErrorDeg
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
        self.PreviousLookVector = newLook

        self.CachedTelemetry.angularVelocity = angVel
        self.CachedTelemetry.isObstructed = self:CheckObstruction(eyePos, targetPosition)
        self.CachedTelemetry.position = eyePos
        self.CachedTelemetry.cframe = self.CurrentCFrame
        self.CachedTelemetry.mode = "SMOOTH"
        self.CachedTelemetry.angularErrorDeg = angularErrorDeg
        return self.CachedTelemetry
    end
end

-- =========================================================================
-- [3/3] MODULO: DashboardGUI (Interface Dark Mode Moderna & Drag Estavel)
-- =========================================================================
local DashboardGUI = {}
do
    DashboardGUI.OnStartRequested = nil
    DashboardGUI.OnStopRequested = nil
    DashboardGUI.OnResetRequested = nil

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

    function DashboardGUI.Create()
        local hostParent = (RunService:IsStudio() and LocalPlayer:WaitForChild("PlayerGui") or CoreGuiService)

        local existing = hostParent:FindFirstChild("KinematicsSimulationDashboard")
        if existing then existing:Destroy() end

        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "KinematicsSimulationDashboard"
        screenGui.ResetOnSpawn = false
        screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        screenGui.Parent = hostParent

        local mainFrame = Instance.new("Frame")
        mainFrame.Name = "MainFrame"
        mainFrame.Size = UDim2.new(0, 360, 0, 560)
        mainFrame.Position = UDim2.new(0, 40, 0.5, -280)
        mainFrame.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
        mainFrame.BorderSizePixel = 0
        mainFrame.Active = true
        mainFrame.Parent = screenGui
        AddCorner(mainFrame, 10)
        AddStroke(mainFrame, Color3.fromRGB(38, 42, 54), 1.5)

        local header = Instance.new("Frame")
        header.Size = UDim2.new(1, 0, 0, 48)
        header.BackgroundColor3 = Color3.fromRGB(24, 27, 36)
        header.BorderSizePixel = 0
        header.Parent = mainFrame
        AddCorner(header, 10)

        local titleLabel = Instance.new("TextLabel")
        titleLabel.Size = UDim2.new(1, -24, 1, 0)
        titleLabel.Position = UDim2.new(0, 16, 0, 0)
        titleLabel.BackgroundTransparency = 1
        titleLabel.Text = "DEEPHAT KINEMATICS SIMULATOR"
        titleLabel.TextColor3 = Color3.fromRGB(240, 243, 248)
        titleLabel.Font = Enum.Font.GothamBold
        titleLabel.TextSize = 12
        titleLabel.TextXAlignment = Enum.TextXAlignment.Left
        titleLabel.Parent = header

        local draggingWindow = false
        local dragStartPos = Vector2.zero
        local startFramePos = UDim2.new()

        header.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                draggingWindow = true
                dragStartPos = Vector2.new(input.Position.X, input.Position.Y)
                startFramePos = mainFrame.Position

                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        draggingWindow = false
                    end
                end)
            end
        end)

        UserInputService.InputChanged:Connect(function(input)
            if draggingWindow and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStartPos
                mainFrame.Position = UDim2.new(
                    startFramePos.X.Scale,
                    startFramePos.X.Offset + delta.X,
                    startFramePos.Y.Scale,
                    startFramePos.Y.Offset + delta.Y
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
        contentScroll.CanvasSize = UDim2.new(0, 0, 0, 680)
        contentScroll.Parent = mainFrame

        local listLayout = Instance.new("UIListLayout")
        listLayout.Padding = UDim.new(0, 10)
        listLayout.SortOrder = Enum.SortOrder.LayoutOrder
        listLayout.Parent = contentScroll

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

            btn.MouseButton1Click:Connect(function()
                SimConfig.LoadProfile(pName)
            end)
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

        local paramsContainer = Instance.new("Frame")
        paramsContainer.Size = UDim2.new(1, 0, 0, 170)
        paramsContainer.BackgroundColor3 = Color3.fromRGB(24, 27, 36)
        paramsContainer.LayoutOrder = 2
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
                if num then
                    SimConfig.Set(configKey, num)
                else
                    box.Text = string.format("%." .. decimals .. "f", SimConfig.Get(configKey) or 0)
                end
            end)
            textInputs[configKey] = box
        end

        CreateInput("Campo de Visao (FOV deg):", "FOV", 1)
        CreateInput("Suavidade (Smoothing):", "Smoothing", 3)
        CreateInput("Mult. Velocidade:", "SpeedMultiplier", 2)
        CreateInput("Tempo de Reacao (s):", "ReactionTime", 2)

        local slidersContainer = Instance.new("Frame")
        slidersContainer.Size = UDim2.new(1, 0, 0, 115)
        slidersContainer.BackgroundColor3 = Color3.fromRGB(24, 27, 36)
        slidersContainer.LayoutOrder = 3
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
                    if currentlyActiveSlider == configKey then
                        currentlyActiveSlider = nil
                    end
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

        local actionsContainer = Instance.new("Frame")
        actionsContainer.Size = UDim2.new(1, 0, 0, 85)
        actionsContainer.BackgroundTransparency = 1
        actionsContainer.LayoutOrder = 4
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
        local resetBtn = CreateBtn("RESETAR PADROES", Color3.fromRGB(45, 50, 64), UDim2.new(0, 0, 0, 42), UDim2.new(1, 0, 0, 34))

        startBtn.MouseButton1Click:Connect(function()
            if DashboardGUI.OnStartRequested then DashboardGUI.OnStartRequested() end
        end)
        stopBtn.MouseButton1Click:Connect(function()
            if DashboardGUI.OnStopRequested then DashboardGUI.OnStopRequested() end
        end)
        resetBtn.MouseButton1Click:Connect(function()
            SimConfig.LoadProfile("Normal")
            if DashboardGUI.OnResetRequested then DashboardGUI.OnResetRequested() end
        end)

        local telemetryCard = Instance.new("Frame")
        telemetryCard.Size = UDim2.new(1, 0, 0, 90)
        telemetryCard.BackgroundColor3 = Color3.fromRGB(22, 25, 34)
        telemetryCard.LayoutOrder = 5
        telemetryCard.Parent = contentScroll
        AddCorner(telemetryCard, 8)
        AddStroke(telemetryCard, Color3.fromRGB(36, 40, 52), 1)

        local tLayout = Instance.new("UIListLayout")
        tLayout.Padding = UDim.new(0, 4)
        tLayout.Parent = telemetryCard

        local tPad = Instance.new("UIPadding")
        tPad.PaddingTop = UDim.new(0, 8)
        tPad.PaddingLeft = UDim.new(0, 10)
        tPad.Parent = telemetryCard

        local function CreateRow(txt: string)
            local lbl = Instance.new("TextLabel")
            lbl.Size = UDim2.new(1, -20, 0, 15)
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

        SimConfig.SubscribeAll(function(key, val)
            if key == "ActiveProfile" then
                UpdateProfileHighlights(tostring(val))
                statusProfile.Text = "Perfil Ativo: " .. tostring(val)
            elseif textInputs[key] and typeof(val) == "number" then
                textInputs[key].Text = string.format("%.2f", val)
            end
        end)

        function (DashboardGUI :: any):UpdateTelemetryDisplay(data: any)
            if not data then return end
            statusVel.Text = string.format("Velocidade Angular: %.1f deg/s", data.angularVelocity or 0)
            statusObs.Text = string.format("Linha de Visao: %s", data.isObstructed and "OBSTRUIDO" or "LIVRE")
            statusObs.TextColor3 = data.isObstructed and Color3.fromRGB(240, 80, 80) or Color3.fromRGB(80, 220, 120)
            statusMode.Text = string.format("Modo Cinematico: %s", data.mode or "IDLE")
        end

        return screenGui
    end
end

-- =========================================================================
-- [ORQUESTRADOR] EXECUCAO OTIMIZADA
-- =========================================================================
local guiInstance = DashboardGUI.Create()

local filterInstances: { Instance } = {}
if LocalPlayer.Character then
    table.insert(filterInstances, LocalPlayer.Character)
end

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

local function GetTarget(): Vector3
    local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
    local myPos = myRoot and myRoot.Position or Camera.CFrame.Position

    local closestPlayerDist = math.huge
    local targetPos: Vector3? = nil

    for _, other in ipairs(Players:GetPlayers()) do
        if other ~= LocalPlayer and other.Character and other.Character:FindFirstChild("HumanoidRootPart") then
            local hrp = other.Character.HumanoidRootPart :: BasePart
            local d = (hrp.Position - myPos).Magnitude
            if d < closestPlayerDist then
                closestPlayerDist = d
                targetPos = hrp.Position
            end
        end
    end

    if targetPos then
        return targetPos
    end

    local t = os.clock() * 0.9
    local center = myPos + Vector3.new(0, 3, 0)
    return center + Vector3.new(math.sin(t) * 16, math.sin(t * 0.7) * 2, math.cos(t) * 16)
end

DashboardGUI.OnStartRequested = function()
    if isRunning then return end
    isRunning = true
    print("[DeepHat] Simulador INICIADO!")

    conn = RunService.RenderStepped:Connect(function(dt)
        local target = GetTarget()
        local snapFreq = SimConfig.Get("SnapFrequency") or 0.03
        local reactionTime = SimConfig.Get("ReactionTime") or 0.2
        local now = os.clock()

        local telem
        if math.random() < snapFreq and (now - lastSnapTime > reactionTime) then
            lastSnapTime = now
            telem = Kinematics:StepSnap(target, dt)
        else
            telem = Kinematics:StepSmooth(target, dt)
        end

        Camera.CFrame = telem.cframe

        if (now - lastUiUpdate) >= 0.1 then
            lastUiUpdate = now
            DashboardGUI:UpdateTelemetryDisplay(telem)
        end
    end)
end

DashboardGUI.OnStopRequested = function()
    if not isRunning then return end
    isRunning = false
    if conn then
        conn:Disconnect()
        conn = nil
    end
    print("[DeepHat] Simulador PARADO!")
    DashboardGUI:UpdateTelemetryDisplay({ angularVelocity = 0, isObstructed = false, mode = "PARADO" })
end

DashboardGUI.OnResetRequested = function()
    print("[DeepHat] Parametros resetados para Normal!")
end

_G.DeepHat_Cleanup = function()
    if conn then
        conn:Disconnect()
        conn = nil
    end
    if guiInstance and guiInstance.Parent then
        guiInstance:Destroy()
    end
end

print("[DeepHat] Sistema v2.0 OTIMIZADO carregado com sucesso!")
