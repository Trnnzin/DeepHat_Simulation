--!strict
-- DashboardGUI.lua
-- Modulo 3: Interface de Usuario Moderna e Minimalista (Dark Mode) desacoplada

local SimConfig = require(script.Parent.SimConfig)

local DashboardGUI = {}
DashboardGUI.__index = DashboardGUI

-- Callbacks publicos para o orquestrador
DashboardGUI.OnStartRequested = nil :: (() -> ())?
DashboardGUI.OnStopRequested = nil :: (() -> ())?
DashboardGUI.OnResetRequested = nil :: (() -> ())?

-- Utilitario: Cria UICorner
local function AddCorner(parent: Instance, radius: number)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    corner.Parent = parent
    return corner
end

-- Utilitario: Cria UIStroke (Borda sutil)
local function AddStroke(parent: Instance, color: Color3, thickness: number?)
    local stroke = Instance.new("UIStroke")
    stroke.Color = color
    stroke.Thickness = thickness or 1
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = parent
    return stroke
end

function DashboardGUI.Create(parentGui: Instance?): ScreenGui
    local CoreGuiService = game:GetService("CoreGui")
    local Players = game:GetService("Players")
    local UserInputService = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")

    local hostParent = parentGui or (RunService:IsStudio() and Players.LocalPlayer:WaitForChild("PlayerGui") or CoreGuiService)

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "KinematicsSimulationDashboard"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = hostParent

    -- Painel Principal (Draggable e Dark Slate)
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.new(0, 360, 0, 580)
    mainFrame.Position = UDim2.new(0, 40, 0.5, -290)
    mainFrame.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
    mainFrame.BorderSizePixel = 0
    mainFrame.Active = true
    mainFrame.Draggable = true
    mainFrame.Parent = screenGui
    AddCorner(mainFrame, 10)
    AddStroke(mainFrame, Color3.fromRGB(38, 42, 54), 1.5)

    -- Top Header
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
    titleLabel.Text = "SIMULADOR DE AGENTE 3D"
    titleLabel.TextColor3 = Color3.fromRGB(240, 243, 248)
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextSize = 13
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = header

    -- Container de Conteudo com Scrolling
    local contentScroll = Instance.new("ScrollingFrame")
    contentScroll.Size = UDim2.new(1, -24, 1, -60)
    contentScroll.Position = UDim2.new(0, 12, 0, 52)
    contentScroll.BackgroundTransparency = 1
    contentScroll.BorderSizePixel = 0
    contentScroll.ScrollBarThickness = 3
    contentScroll.ScrollBarImageColor3 = Color3.fromRGB(60, 65, 80)
    contentScroll.CanvasSize = UDim2.new(0, 0, 0, 710)
    contentScroll.Parent = mainFrame

    local listLayout = Instance.new("UIListLayout")
    listLayout.Padding = UDim.new(0, 10)
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Parent = contentScroll

    -- 1. Seletor de Perfis (Botoes)
    local profileLabel = Instance.new("TextLabel")
    profileLabel.Size = UDim2.new(1, 0, 0, 18)
    profileLabel.BackgroundTransparency = 1
    profileLabel.Text = "PERFIL DE SIMULAÇÃO"
    profileLabel.TextColor3 = Color3.fromRGB(140, 146, 160)
    profileLabel.Font = Enum.Font.GothamBold
    profileLabel.TextSize = 11
    profileLabel.TextXAlignment = Enum.TextXAlignment.Left
    profileLabel.LayoutOrder = 1
    profileLabel.Parent = contentScroll

    local profileContainer = Instance.new("Frame")
    profileContainer.Size = UDim2.new(1, 0, 0, 32)
    profileContainer.BackgroundTransparency = 1
    profileContainer.LayoutOrder = 2
    profileContainer.Parent = contentScroll

    local profileLayout = Instance.new("UIGridLayout")
    profileLayout.CellSize = UDim2.new(0.235, 0, 1, 0)
    profileLayout.CellPadding = UDim2.new(0.02, 0, 0, 0)
    profileLayout.Parent = profileContainer

    local profileButtons: { [string]: TextButton } = {}
    local profiles = { "Normal", "Leve", "Medio", "Agressivo" }

    for _, pName in ipairs(profiles) do
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

    -- Atualizacao visual dos botoes de perfil
    local function UpdateProfileButtonHighlights(activeName: string)
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
    UpdateProfileButtonHighlights(SimConfig.Get("ActiveProfile") or "Normal")

    -- 2. Campos de Entrada Numerica (TextBox)
    local paramsContainer = Instance.new("Frame")
    paramsContainer.Size = UDim2.new(1, 0, 0, 180)
    paramsContainer.BackgroundColor3 = Color3.fromRGB(24, 27, 36)
    paramsContainer.LayoutOrder = 3
    paramsContainer.Parent = contentScroll
    AddCorner(paramsContainer, 8)
    AddStroke(paramsContainer, Color3.fromRGB(36, 40, 52), 1)

    local paramsLayout = Instance.new("UIListLayout")
    paramsLayout.Padding = UDim.new(0, 8)
    paramsLayout.Parent = paramsContainer

    local paramsPadding = Instance.new("UIPadding")
    paramsPadding.PaddingTop = UDim.new(0, 8)
    paramsPadding.PaddingLeft = UDim.new(0, 10)
    paramsPadding.PaddingRight = UDim.new(0, 10)
    paramsPadding.Parent = paramsContainer

    local textInputs: { [string]: TextBox } = {}

    local function CreateNumberInput(labelTitle: string, configKey: string, formatDecimals: number)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 32)
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
        box.Text = string.format("%." .. formatDecimals .. "f", SimConfig.Get(configKey) or 0)
        box.Parent = row
        AddCorner(box, 6)
        AddStroke(box, Color3.fromRGB(45, 50, 65), 1)

        box.FocusLost:Connect(function(enterPressed)
            local num = tonumber(box.Text)
            if num then
                SimConfig.Set(configKey, num)
            else
                box.Text = string.format("%." .. formatDecimals .. "f", SimConfig.Get(configKey) or 0)
            end
        end)

        textInputs[configKey] = box
    end

    CreateNumberInput("Campo de Visao (FOV deg):", "FOV", 1)
    CreateNumberInput("Suavidade (Smoothing):", "Smoothing", 3)
    CreateNumberInput("Mult. Velocidade:", "SpeedMultiplier", 2)
    CreateNumberInput("Tempo de Reacao (s):", "ReactionTime", 2)

    -- 3. Sliders (Intensidade e Precisao)
    local slidersContainer = Instance.new("Frame")
    slidersContainer.Size = UDim2.new(1, 0, 0, 120)
    slidersContainer.BackgroundColor3 = Color3.fromRGB(24, 27, 36)
    slidersContainer.LayoutOrder = 4
    slidersContainer.Parent = contentScroll
    AddCorner(slidersContainer, 8)
    AddStroke(slidersContainer, Color3.fromRGB(36, 40, 52), 1)

    local slidersLayout = Instance.new("UIListLayout")
    slidersLayout.Padding = UDim.new(0, 12)
    slidersLayout.Parent = slidersContainer

    local slidersPadding = Instance.new("UIPadding")
    slidersPadding.PaddingTop = UDim.new(0, 10)
    slidersPadding.PaddingLeft = UDim.new(0, 10)
    slidersPadding.PaddingRight = UDim.new(0, 10)
    slidersPadding.Parent = slidersContainer

    local function CreateSlider(title: string, configKey: string, minVal: number, maxVal: number)
        local container = Instance.new("Frame")
        container.Size = UDim2.new(1, 0, 0, 42)
        container.BackgroundTransparency = 1
        container.Parent = slidersContainer

        local titleRow = Instance.new("Frame")
        titleRow.Size = UDim2.new(1, 0, 0, 18)
        titleRow.BackgroundTransparency = 1
        titleRow.Parent = container

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(0.7, 0, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = title
        lbl.TextColor3 = Color3.fromRGB(180, 186, 200)
        lbl.Font = Enum.Font.GothamMedium
        lbl.TextSize = 11
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = titleRow

        local valLabel = Instance.new("TextLabel")
        valLabel.Size = UDim2.new(0.3, 0, 1, 0)
        valLabel.Position = UDim2.new(0.7, 0, 0, 0)
        valLabel.BackgroundTransparency = 1
        valLabel.Text = string.format("%.2f", SimConfig.Get(configKey) or minVal)
        valLabel.TextColor3 = Color3.fromRGB(90, 150, 255)
        valLabel.Font = Enum.Font.GothamBold
        valLabel.TextSize = 11
        valLabel.TextXAlignment = Enum.TextXAlignment.Right
        valLabel.Parent = titleRow

        local track = Instance.new("TextButton")
        track.Size = UDim2.new(1, 0, 0, 10)
        track.Position = UDim2.new(0, 0, 0, 24)
        track.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
        track.Text = ""
        track.AutoButtonColor = false
        track.Parent = container
        AddCorner(track, 5)

        local initialRatio = math.clamp(((SimConfig.Get(configKey) or minVal) - minVal) / (maxVal - minVal), 0, 1)
        local fill = Instance.new("Frame")
        fill.Size = UDim2.new(initialRatio, 0, 1, 0)
        fill.BackgroundColor3 = Color3.fromRGB(56, 110, 235)
        fill.BorderSizePixel = 0
        fill.Parent = track
        AddCorner(fill, 5)

        local isDragging = false
        local function UpdateFromX(xPos: number)
            local trackAbsPos = track.AbsolutePosition.X
            local trackAbsWidth = track.AbsoluteSize.X
            local ratio = math.clamp((xPos - trackAbsPos) / trackAbsWidth, 0, 1)
            local computedVal = minVal + ratio * (maxVal - minVal)

            fill.Size = UDim2.new(ratio, 0, 1, 0)
            valLabel.Text = string.format("%.2f", computedVal)
            SimConfig.Set(configKey, computedVal)
        end

        track.MouseButton1Down:Connect(function()
            isDragging = true
            UpdateFromX(UserInputService:GetMouseLocation().X)
        end)

        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                isDragging = false
            end
        end)

        UserInputService.InputChanged:Connect(function(input)
            if isDragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                UpdateFromX(input.Position.X)
            end
        end)

        -- Listener para atualizar slider se SimConfig for modificado externamente
        SimConfig.Subscribe(configKey, function(newVal)
            local ratio = math.clamp((newVal - minVal) / (maxVal - minVal), 0, 1)
            fill.Size = UDim2.new(ratio, 0, 1, 0)
            valLabel.Text = string.format("%.2f", newVal)
        end)
    end

    CreateSlider("Intensidade da Simulação:", "Intensity", 0.1, 2.0)
    CreateSlider("Precisão de Tracking:", "TrackingPrecision", 0.50, 1.00)

    -- 4. Botoes de Acao (Iniciar, Parar, Resetar)
    local actionsContainer = Instance.new("Frame")
    actionsContainer.Size = UDim2.new(1, 0, 0, 90)
    actionsContainer.BackgroundTransparency = 1
    actionsContainer.LayoutOrder = 5
    actionsContainer.Parent = contentScroll

    local function CreateActionButton(text: string, bgColor: Color3, pos: UDim2, size: UDim2)
        local btn = Instance.new("TextButton")
        btn.Size = size
        btn.Position = pos
        btn.BackgroundColor3 = bgColor
        btn.Text = text
        btn.Font = Enum.Font.GothamBold
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.TextSize = 12
        btn.BorderSizePixel = 0
        btn.Parent = actionsContainer
        AddCorner(btn, 8)
        return btn
    end

    local startBtn = CreateActionButton("INICIAR TESTE", Color3.fromRGB(36, 150, 75), UDim2.new(0, 0, 0, 0), UDim2.new(0.48, 0, 0, 38))
    local stopBtn = CreateActionButton("PARAR TESTE", Color3.fromRGB(195, 48, 48), UDim2.new(0.52, 0, 0, 38), UDim2.new(0.48, 0, 0, 38))
    local resetBtn = CreateActionButton("RESETAR PADRÕES", Color3.fromRGB(45, 50, 64), UDim2.new(0, 0, 0, 46), UDim2.new(1, 0, 0, 36))

    startBtn.MouseButton1Click:Connect(function()
        if DashboardGUI.OnStartRequested then
            DashboardGUI.OnStartRequested()
        end
    end)

    stopBtn.MouseButton1Click:Connect(function()
        if DashboardGUI.OnStopRequested then
            DashboardGUI.OnStopRequested()
        end
    end)

    resetBtn.MouseButton1Click:Connect(function()
        SimConfig.LoadProfile("Normal")
        if DashboardGUI.OnResetRequested then
            DashboardGUI.OnResetRequested()
        end
    end)

    -- 5. Monitor de Telemetria em Tempo Real (Status Card)
    local telemetryCard = Instance.new("Frame")
    telemetryCard.Size = UDim2.new(1, 0, 0, 95)
    telemetryCard.BackgroundColor3 = Color3.fromRGB(22, 25, 34)
    telemetryCard.LayoutOrder = 6
    telemetryCard.Parent = contentScroll
    AddCorner(telemetryCard, 8)
    AddStroke(telemetryCard, Color3.fromRGB(36, 40, 52), 1)

    local teleLayout = Instance.new("UIListLayout")
    teleLayout.Padding = UDim.new(0, 4)
    teleLayout.Parent = telemetryCard

    local telePad = Instance.new("UIPadding")
    telePad.PaddingTop = UDim.new(0, 8)
    telePad.PaddingLeft = UDim.new(0, 10)
    telePad.Parent = telemetryCard

    local function CreateStatusRow(prefix: string)
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -20, 0, 16)
        lbl.BackgroundTransparency = 1
        lbl.Text = prefix .. ": --"
        lbl.TextColor3 = Color3.fromRGB(170, 176, 192)
        lbl.Font = Enum.Font.GothamMedium
        lbl.TextSize = 10
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = telemetryCard
        return lbl
    end

    local statusProfile = CreateStatusRow("Perfil Ativo")
    local statusVel = CreateStatusRow("Velocidade Angular")
    local statusObs = CreateStatusRow("Linha de Visão (Oclusão)")
    local statusMode = CreateStatusRow("Modo Cinemático")

    -- Observer: Sincroniza inputs de texto e botoes caso o perfil mude
    SimConfig.SubscribeAll(function(key, val)
        if key == "ActiveProfile" then
            UpdateProfileButtonHighlights(tostring(val))
            statusProfile.Text = "Perfil Ativo: " .. tostring(val)
        elseif textInputs[key] and typeof(val) == "number" then
            textInputs[key].Text = string.format("%.2f", val)
        end
    end)

    -- Funcao publica para alimentar o display de telemetria
    function (DashboardGUI :: any):UpdateTelemetryDisplay(data: any)
        if not data then return end
        statusVel.Text = string.format("Velocidade Angular: %.1f deg/s", data.angularVelocity or 0)
        statusObs.Text = string.format("Linha de Visão: %s", data.isObstructed and "OBSTRUÍDO (Parede)" or "LIVRE")
        statusObs.TextColor3 = data.isObstructed and Color3.fromRGB(240, 80, 80) or Color3.fromRGB(80, 220, 120)
        statusMode.Text = string.format("Modo Cinemático: %s", data.mode or "IDLE")
    end

    return screenGui
end

return DashboardGUI