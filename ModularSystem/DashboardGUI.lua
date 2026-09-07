--!strict
--[[
    ============================================================================
    MODULO: DashboardGUI
    DESIGN: UI/UX Dark Theme Minimalista com Red Accents (Alta Densidade)
    ARQUITETURA: 3 Colunas + Observer Pattern integrado com SimConfig
    ============================================================================
--]]

local SimConfig = require(script.Parent.SimConfig)

local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local DashboardGUI = {}
DashboardGUI.__index = DashboardGUI

-- [PALETA DE DESIGN TOKENS]
local THEME = {
    BG_MAIN = Color3.fromRGB(13, 14, 17),
    BG_PANEL = Color3.fromRGB(20, 22, 27),
    BG_INPUT = Color3.fromRGB(26, 29, 36),
    BORDER = Color3.fromRGB(38, 42, 53),
    TEXT_MAIN = Color3.fromRGB(237, 237, 237),
    TEXT_MUTED = Color3.fromRGB(125, 132, 148),
    ACCENT_RED = Color3.fromRGB(224, 43, 54),
    ACCENT_HOVER = Color3.fromRGB(255, 77, 88),
    SUCCESS = Color3.fromRGB(46, 204, 113),
}

-- Callbacks publicos para o orquestrador (Bootstrap)
DashboardGUI.OnStartRequested = nil :: (() -> ())?
DashboardGUI.OnStopRequested = nil :: (() -> ())?
DashboardGUI.OnResetRequested = nil :: (() -> ())?
DashboardGUI.OnSaveRequested = nil :: (() -> ())?

-- Utilitarios de construcao
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
    local hostParent = parentGui or (RunService:IsStudio() and Players.LocalPlayer:WaitForChild("PlayerGui") or CoreGui)

    
    -- Purga completa de qualquer interface legada para evitar sobreposicoes ou Z-Index issues
    local function PurgeAllLegacyUIs()
        local containers = {}
        pcall(function() table.insert(containers, game:GetService("CoreGui")) end)
        local pGui = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if pGui then table.insert(containers, pGui) end

        local targetNames = {
            "DiagnosticSimulationDashboard",
            "KinematicsSimulationDashboard",
            "DeepHat_GUI",
            "FovCircleOverlay"
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

    local existing = hostParent:FindFirstChild("DiagnosticSimulationDashboard")
    if existing then existing:Destroy() end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "DiagnosticSimulationDashboard"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.DisplayOrder = 9999
    screenGui.Parent = hostParent

    -- Janela Principal (Compacta, 3 Colunas, Draggable)
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.new(0, 860, 0, 530)
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
    title.Size = UDim2.new(0.7, 0, 1, 0)
    title.Position = UDim2.new(0, 14, 0, 0)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.TextSize = 12
    title.TextColor3 = THEME.TEXT_MAIN
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Text = "SIMULATION DIAGNOSTICS // VIRTUAL TEST RIG [CONTROL UNIT]"
    title.Parent = header

    local hotkeyNotice = Instance.new("TextLabel")
    hotkeyNotice.Size = UDim2.new(0, 140, 1, 0)
    hotkeyNotice.Position = UDim2.new(1, -190, 0, 0)
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
        Componente de Slider com Input Numerico Sincronizado
    --]]
    local function CreateSliderField(parent: Instance, labelText: string, configKey: string, minVal: number, maxVal: number, defaultVal: number, step: number): Frame
        local container = Instance.new("Frame")
        container.Size = UDim2.new(1, 0, 0, 44)
        container.BackgroundTransparency = 1
        container.Parent = parent

        local headerRow = Instance.new("Frame")
        headerRow.Size = UDim2.new(1, 0, 0, 20)
        headerRow.BackgroundTransparency = 1
        headerRow.Parent = container

        local titleLabel = Instance.new("TextLabel")
        titleLabel.Size = UDim2.new(0.65, 0, 1, 0)
        titleLabel.BackgroundTransparency = 1
        titleLabel.Font = Enum.Font.GothamMedium
        titleLabel.TextSize = 11
        titleLabel.TextColor3 = THEME.TEXT_MAIN
        titleLabel.TextXAlignment = Enum.TextXAlignment.Left
        titleLabel.Text = labelText
        titleLabel.Parent = headerRow

        local inputBox = Instance.new("TextBox")
        inputBox.Size = UDim2.new(0.35, 0, 1, 0)
        inputBox.BackgroundColor3 = THEME.BG_INPUT
        inputBox.TextColor3 = THEME.ACCENT_RED
        inputBox.Font = Enum.Font.GothamBold
        inputBox.TextSize = 11
        inputBox.Text = string.format(step < 1 and "%.2f" or "%d", defaultVal)
        inputBox.ClearTextOnFocus = false
        inputBox.Parent = headerRow
        AddCorner(inputBox, 4)
        AddStroke(inputBox, THEME.BORDER, 1)

        local track = Instance.new("Frame")
        track.Size = UDim2.new(1, 0, 0, 6)
        track.Position = UDim2.new(0, 0, 0, 28)
        track.BackgroundColor3 = THEME.BG_INPUT
        track.Parent = container
        AddCorner(track, 3)

        local progress = Instance.new("Frame")
        local initialRatio = math.clamp((defaultVal - minVal) / (maxVal - minVal), 0, 1)
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
            val = math.clamp(val, minVal, maxVal)
            val = math.round(val / step) * step
            local ratio = math.clamp((val - minVal) / (maxVal - minVal), 0, 1)
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
                inputBox.Text = string.format(step < 1 and "%.2f" or "%d", SimConfig.Get(configKey) or defaultVal)
            end
        end)

        track.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                isSliderDragging = true
                local relX = math.clamp((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
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
                local relX = math.clamp((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
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
    col1.BackgroundColor3 = THEME.BG_PANEL
    col1.ScrollBarThickness = 3
    col1.ScrollBarImageColor3 = THEME.BORDER
    col1.CanvasSize = UDim2.new(0, 0, 0, 390)
    col1.Parent = contentArea
    AddCorner(col1, 6)
    AddStroke(col1, THEME.BORDER, 1)

    local list1 = Instance.new("UIListLayout")
    list1.Padding = UDim.new(0, 6)
    list1.Parent = col1

    local pad1 = Instance.new("UIPadding")
    pad1.PaddingTop = UDim.new(0, 10); pad1.PaddingLeft = UDim.new(0, 10); pad1.PaddingRight = UDim.new(0, 10)
    pad1.Parent = col1

    local col1Title = Instance.new("TextLabel")
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
    end)

    CreateSliderField(col1, "Ângulo de Campo (FOV °)", "FOV", 10, 180, SimConfig.Get("FOV"), 1)
    CreateSliderField(col1, "Coeficiente de Suavização", "Smoothing", 0.01, 1.0, SimConfig.Get("Smoothing"), 0.01)
    CreateSliderField(col1, "Velocidade Rotação (°/s)", "AngularVelocity", 30, 720, SimConfig.Get("AngularVelocity"), 5)
    CreateSliderField(col1, "Tempo de Resposta (ms)", "ResponseTime", 0, 250, SimConfig.Get("ResponseTime"), 1)
    CreateSliderField(col1, "Precisão de Trajetória (%)", "TrajectoryPrecision", 50, 100, SimConfig.Get("TrajectoryPrecision"), 0.5)
    CreateSliderField(col1, "Frequência Atualização (Hz)", "UpdateFrequency", 10, 144, SimConfig.Get("UpdateFrequency"), 5)
    CreateSliderField(col1, "Raio de Atuação (m)", "VectorRadius", 10, 500, SimConfig.Get("VectorRadius"), 5)

    -- =========================================================================
    -- COLUNA 2: Parametros de Comportamento do Sistema
    -- =========================================================================
    local col2 = Instance.new("ScrollingFrame")
    col2.BackgroundColor3 = THEME.BG_PANEL
    col2.ScrollBarThickness = 3
    col2.ScrollBarImageColor3 = THEME.BORDER
    col2.CanvasSize = UDim2.new(0, 0, 0, 390)
    col2.Parent = contentArea
    AddCorner(col2, 6)
    AddStroke(col2, THEME.BORDER, 1)

    local list2 = Instance.new("UIListLayout")
    list2.Padding = UDim.new(0, 6)
    list2.Parent = col2

    local pad2 = Instance.new("UIPadding")
    pad2.PaddingTop = UDim.new(0, 10); pad2.PaddingLeft = UDim.new(0, 10); pad2.PaddingRight = UDim.new(0, 10)
    pad2.Parent = col2

    local col2Title = Instance.new("TextLabel")
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

    CreateSliderField(col2, "Frequência de Eventos (Hz)", "EventFrequency", 1, 60, SimConfig.Get("EventFrequency"), 1)
    CreateSliderField(col2, "Intensidade de Resposta (%)", "Intensity", 0, 100, SimConfig.Get("Intensity"), 1)
    CreateSliderField(col2, "Velocidade Deslocamento", "MoveSpeed", 8, 40, SimConfig.Get("MoveSpeed"), 1)
    CreateSliderField(col2, "Gradiente de Aceleração", "AccelerationCurve", 0.2, 3.0, SimConfig.Get("AccelerationCurve"), 0.05)
    CreateSliderField(col2, "Duração do Ciclo (s)", "CycleDuration", 5, 120, SimConfig.Get("CycleDuration"), 5)
    CreateSliderField(col2, "Agentes Simultâneos", "SimulatedAgents", 1, 16, SimConfig.Get("SimulatedAgents"), 1)

    -- =========================================================================
    -- COLUNA 3: Mapeamento de Regioes (HitBox Coords) & Telemetria
    -- =========================================================================
    local col3 = Instance.new("Frame")
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
    dummyCanvas.Size = UDim2.new(1, -20, 0.55, 0)
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
    activeRegionBadge.Position = UDim2.new(0, 10, 0.55, 38)
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

    CreateActionButton("↺ RESETAR", false, function()
        SimConfig.LoadProfile("Normal")
        UpdateProfileHighlights("Normal")
        if DashboardGUI.OnResetRequested then
            DashboardGUI.OnResetRequested()
        end
    end)

    CreateActionButton("💾 SALVAR CONFIG", false, function()
        if DashboardGUI.OnSaveRequested then
            DashboardGUI.OnSaveRequested()
        end
    end)

    CreateActionButton("⏹ PARAR", false, function()
        SimConfig.Set("SimulationActive", false)
        toggleBtn.BackgroundColor3 = THEME.BG_INPUT
        toggleDot.Position = UDim2.new(0, 3, 0.5, -7)
        if DashboardGUI.OnStopRequested then
            DashboardGUI.OnStopRequested()
        end
    end)

    CreateActionButton("▶ INICIAR TESTE", true, function()
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
        elseif syncInputs[key] and typeof(val) == "number" then
            syncInputs[key].UpdateRatio(val)
        end
    end)

    -- Funcao publica para atualizar os dados de telemetria
    function DashboardGUI:UpdateTelemetryDisplay(data: any)
        if not data then return end
        teleVel.Text = string.format("VELOCIDADE ANGULAR: %.1f °/s", data.angularVelocity or 0)
        teleObs.Text = string.format("LINHA DE VISÃO: %s", data.isObstructed and "OBSTRUÍDO (PAREDE)" or "LIVRE")
        teleObs.TextColor3 = data.isObstructed and Color3.fromRGB(240, 80, 80) or THEME.SUCCESS
        teleMode.Text = string.format("MODO: %s", data.mode or "IDLE")
        local fps = math.floor(1 / ((RunService.RenderStepped:Wait()) or 0.016))
        teleFps.Text = string.format("STATUS DO ENGINE: %d FPS", fps)
    end

    return screenGui
end

return DashboardGUI
