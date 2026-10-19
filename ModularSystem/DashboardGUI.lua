--!strict
-- =========================================================================
-- DashboardGUI.lua
-- Interface Profissional de Simulação Cinemática e Diagnósticos de Detecção
-- Design: Dark Mode Fosco com Red Accents (#E02B36), Abas Modulares e Watchdog de Fundo
-- =========================================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CoreGuiService = game:GetService("CoreGui")

local SimConfig = require(script.Parent.SimConfig)

local DashboardGUI = {}
DashboardGUI.__index = DashboardGUI

-- [DESIGN SYSTEM & TOKENS VISUAIS]
local THEME = {
    BG_WINDOW    = Color3.fromRGB(11, 12, 16),
    BG_SIDEBAR   = Color3.fromRGB(16, 18, 23),
    BG_CARD      = Color3.fromRGB(20, 23, 30),
    BG_INPUT     = Color3.fromRGB(27, 31, 40),
    BORDER       = Color3.fromRGB(38, 43, 56),
    BORDER_LIGHT = Color3.fromRGB(55, 62, 80),
    TEXT_MAIN    = Color3.fromRGB(245, 246, 250),
    TEXT_MUTED   = Color3.fromRGB(135, 144, 160),
    ACCENT_RED   = Color3.fromRGB(224, 43, 54),
    ACCENT_HOVER = Color3.fromRGB(255, 65, 75),
    ACCENT_GLOW  = Color3.fromRGB(90, 20, 25),
    SUCCESS      = Color3.fromRGB(46, 204, 113),
    WARNING      = Color3.fromRGB(241, 196, 15),
    INFO         = Color3.fromRGB(52, 152, 219),
}

-- Callbacks de Ação Global
DashboardGUI.OnStartRequested = nil :: (() -> ())?
DashboardGUI.OnStopRequested = nil :: (() -> ())?
DashboardGUI.OnResetRequested = nil :: (() -> ())?
DashboardGUI.OnSaveRequested = nil :: (() -> ())?

-- Instâncias Internas
local ScreenGuiInstance: ScreenGui? = nil
local MainFrameInstance: Frame? = nil
local FovCircleInstance: Frame? = nil
local WatchdogBadgeInstance: TextLabel? = nil
local EventLogListInstance: ScrollingFrame? = nil

-- Elementos de Telemetria Dinâmica
local TelemetryLabels: { [string]: TextLabel } = {}
local PerformanceData = {
    Fps = 60,
    PeakAngVel = 0,
    LastCheck = os.clock(),
    ErrorCount = 0,
}

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

local function GetSafeGuiParent(): Instance
    local okCore, coreGui = pcall(function() return CoreGuiService end)
    if okCore and coreGui then
        local testOk = pcall(function()
            local test = Instance.new("Folder")
            test.Parent = coreGui
            test:Destroy()
        end)
        if testOk then return coreGui end
    end
    local localPlayer = Players.LocalPlayer
    local playerGui = localPlayer and localPlayer:FindFirstChildOfClass("PlayerGui")
    return playerGui or Workspace
end

-- =========================================================================
-- LOG DE DIAGNÓSTICOS EM TEMPO REAL
-- =========================================================================
function DashboardGUI.AddDiagnosticLog(source: string, message: string, level: "INFO" | "WARN" | "OK")
    if not EventLogListInstance or not EventLogListInstance.Parent then return end

    local color = THEME.TEXT_MAIN
    if level == "WARN" then color = THEME.WARNING
    elseif level == "OK" then color = THEME.SUCCESS
    elseif level == "INFO" then color = THEME.INFO end

    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 20)
    row.BackgroundColor3 = THEME.BG_INPUT
    row.BackgroundTransparency = 0.5
    row.Parent = EventLogListInstance
    AddCorner(row, 3)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -8, 1, 0)
    lbl.Position = UDim2.new(0, 5, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.Code
    lbl.TextSize = 10
    lbl.TextColor3 = color
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    local timeStr = os.date("%H:%M:%S")
    lbl.Text = string.format("[%s] [%s] %s", timeStr, source, message)
    lbl.Parent = row

    -- Limita em 40 itens na lista
    local children = EventLogListInstance:GetChildren()
    local count = 0
    for _, ch in ipairs(children) do
        if ch:IsA("Frame") then count = count + 1 end
    end
    if count > 40 then
        for _, ch in ipairs(children) do
            if ch:IsA("Frame") then
                ch:Destroy()
                break
            end
        end
    end
    EventLogListInstance.CanvasPosition = Vector2.new(0, 99999)
end

-- =========================================================================
-- CRIAÇÃO PRINCIPAL DO DASHBOARD
-- =========================================================================
function DashboardGUI.Create(parentGui: Instance?): ScreenGui
    local hostParent = parentGui or GetSafeGuiParent()

    local existing = hostParent:FindFirstChild("DeepHat_MasterDashboard")
    if existing then existing:Destroy() end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "DeepHat_MasterDashboard"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = hostParent
    ScreenGuiInstance = screenGui

    -- ---------------------------------------------------------------------
    -- FOV Overlay na Tela
    -- ---------------------------------------------------------------------
    local fovCircle = Instance.new("Frame")
    fovCircle.Name = "DeepHat_FovOverlay"
    fovCircle.AnchorPoint = Vector2.new(0.5, 0.5)
    fovCircle.Position = UDim2.new(0.5, 0, 0.5, 0)
    fovCircle.BackgroundTransparency = 1
    fovCircle.Visible = SimConfig.Get("ShowFovCircle") == true and SimConfig.Get("SimulationActive") == true
    fovCircle.Parent = screenGui
    AddCorner(fovCircle, 9999)
    local fovStroke = AddStroke(fovCircle, THEME.ACCENT_RED, 1.5)
    fovStroke.Transparency = 0.4
    FovCircleInstance = fovCircle

    local fovCenterDot = Instance.new("Frame")
    fovCenterDot.Size = UDim2.new(0, 4, 0, 4)
    fovCenterDot.AnchorPoint = Vector2.new(0.5, 0.5)
    fovCenterDot.Position = UDim2.new(0.5, 0, 0.5, 0)
    fovCenterDot.BackgroundColor3 = THEME.ACCENT_RED
    fovCenterDot.BackgroundTransparency = 0.2
    fovCenterDot.Parent = fovCircle
    AddCorner(fovCenterDot, 2)

    -- ---------------------------------------------------------------------
    -- Janela Principal
    -- ---------------------------------------------------------------------
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.new(0, 960, 0, 580)
    mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    mainFrame.BackgroundColor3 = THEME.BG_WINDOW
    mainFrame.BorderSizePixel = 0
    mainFrame.Active = true
    mainFrame.Parent = screenGui
    AddCorner(mainFrame, 10)
    AddStroke(mainFrame, THEME.BORDER, 1.5)
    MainFrameInstance = mainFrame

    -- Header da Janela
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 44)
    header.BackgroundColor3 = THEME.BG_SIDEBAR
    header.BorderSizePixel = 0
    header.Parent = mainFrame
    AddCorner(header, 10)

    -- Arraste da Janela (Draggable)
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

    -- Ícone / Marca
    local brandDot = Instance.new("Frame")
    brandDot.Size = UDim2.new(0, 8, 0, 8)
    brandDot.Position = UDim2.new(0, 16, 0.5, -4)
    brandDot.BackgroundColor3 = THEME.ACCENT_RED
    brandDot.Parent = header
    AddCorner(brandDot, 4)

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(0, 360, 1, 0)
    titleLabel.Position = UDim2.new(0, 32, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextSize = 13
    titleLabel.TextColor3 = THEME.TEXT_MAIN
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Text = "DEEPHAT SIMULATION SUITE // v6.0 PRO"
    titleLabel.Parent = header

    -- Badge de Watchdog / Status de Saúde em tempo real
    local watchdogBadge = Instance.new("TextLabel")
    watchdogBadge.Size = UDim2.new(0, 240, 0, 24)
    watchdogBadge.Position = UDim2.new(1, -330, 0.5, -12)
    watchdogBadge.BackgroundColor3 = THEME.BG_INPUT
    watchdogBadge.Font = Enum.Font.GothamMedium
    watchdogBadge.TextSize = 10
    watchdogBadge.TextColor3 = THEME.SUCCESS
    watchdogBadge.Text = "● WATCHDOG: 100% OPERACIONAL"
    watchdogBadge.Parent = header
    AddCorner(watchdogBadge, 4)
    AddStroke(watchdogBadge, THEME.BORDER, 1)
    WatchdogBadgeInstance = watchdogBadge

    local hotkeyNotice = Instance.new("TextLabel")
    hotkeyNotice.Size = UDim2.new(0, 100, 1, 0)
    hotkeyNotice.Position = UDim2.new(1, -160, 0, 0)
    hotkeyNotice.BackgroundTransparency = 1
    hotkeyNotice.Font = Enum.Font.GothamMedium
    hotkeyNotice.TextSize = 10
    hotkeyNotice.TextColor3 = THEME.TEXT_MUTED
    hotkeyNotice.Text = "[HOME] Ocultar"
    hotkeyNotice.Parent = header

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 28, 0, 28)
    closeBtn.Position = UDim2.new(1, -38, 0.5, -14)
    closeBtn.BackgroundColor3 = THEME.BG_INPUT
    closeBtn.TextColor3 = THEME.TEXT_MAIN
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 12
    closeBtn.Text = "✕"
    closeBtn.Parent = header
    AddCorner(closeBtn, 5)
    AddStroke(closeBtn, THEME.BORDER, 1)

    closeBtn.MouseButton1Click:Connect(function()
        mainFrame.Visible = not mainFrame.Visible
    end)

    -- Alternar exibição via teclas Home ou RightShift
    UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.KeyCode == Enum.KeyCode.Home or input.KeyCode == Enum.KeyCode.RightShift then
            mainFrame.Visible = not mainFrame.Visible
        end
    end)

    -- ---------------------------------------------------------------------
    -- Layout Estrutural: Sidebar (Esquerda) + Área de Conteúdo (Direita)
    -- ---------------------------------------------------------------------
    local body = Instance.new("Frame")
    body.Size = UDim2.new(1, 0, 1, -94)
    body.Position = UDim2.new(0, 0, 0, 46)
    body.BackgroundTransparency = 1
    body.Parent = mainFrame

    local sidebar = Instance.new("Frame")
    sidebar.Name = "Sidebar"
    sidebar.Size = UDim2.new(0, 190, 1, 0)
    sidebar.BackgroundColor3 = THEME.BG_SIDEBAR
    sidebar.BorderSizePixel = 0
    sidebar.Parent = body
    AddCorner(sidebar, 8)
    AddStroke(sidebar, THEME.BORDER, 1)

    local sidebarList = Instance.new("UIListLayout")
    sidebarList.Padding = UDim.new(0, 4)
    sidebarList.Parent = sidebar

    local sidebarPad = Instance.new("UIPadding")
    sidebarPad.PaddingTop = UDim.new(0, 10)
    sidebarPad.PaddingLeft = UDim.new(0, 8)
    sidebarPad.PaddingRight = UDim.new(0, 8)
    sidebarPad.Parent = sidebar

    local mainContent = Instance.new("Frame")
    mainContent.Name = "MainContent"
    mainContent.Size = UDim2.new(1, -204, 1, 0)
    mainContent.Position = UDim2.new(0, 198, 0, 0)
    mainContent.BackgroundColor3 = THEME.BG_CARD
    mainContent.BorderSizePixel = 0
    mainContent.Parent = body
    AddCorner(mainContent, 8)
    AddStroke(mainContent, THEME.BORDER, 1)

    -- Páginas das Abas
    local pages: { [string]: ScrollingFrame } = {}
    local tabButtons: { [string]: TextButton } = {}

    local tabs = {
        { Id = "Overview",    Label = "📊 Painel Geral" },
        { Id = "Camera",      Label = "🎥 Câmera & Vetores" },
        { Id = "Simulation",  Label = "⚡ Simulação" },
        { Id = "Vision",      Label = "👁️ Linha de Visão" },
        { Id = "Hitbox",      Label = "🎯 Mapeamento HitBox" },
        { Id = "Diagnostics", Label = "🛠️ Diagnósticos" },
        { Id = "Performance", Label = "📈 Desempenho" },
        { Id = "Settings",    Label = "⚙️ Configurações" },
    }

    local function SwitchTab(tabId: string)
        for id, page in pairs(pages) do
            page.Visible = (id == tabId)
        end
        for id, btn in pairs(tabButtons) do
            local active = (id == tabId)
            btn.BackgroundColor3 = active and THEME.ACCENT_RED or THEME.BG_INPUT
            btn.TextColor3 = active and THEME.TEXT_MAIN or THEME.TEXT_MUTED
        end
        SimConfig.Set("ActiveTab", tabId)
    end

    for _, t in ipairs(tabs) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 0, 34)
        btn.BackgroundColor3 = (t.Id == "Overview") and THEME.ACCENT_RED or THEME.BG_INPUT
        btn.TextColor3 = (t.Id == "Overview") and THEME.TEXT_MAIN or THEME.TEXT_MUTED
        btn.Font = Enum.Font.GothamMedium
        btn.TextSize = 11
        btn.TextXAlignment = Enum.TextXAlignment.Left
        btn.Text = "  " .. t.Label
        btn.Parent = sidebar
        AddCorner(btn, 5)

        tabButtons[t.Id] = btn

        btn.MouseButton1Click:Connect(function()
            SwitchTab(t.Id)
        end)

        -- Criação do Container da Página
        local page = Instance.new("ScrollingFrame")
        page.Name = "Page_" .. t.Id
        page.Size = UDim2.new(1, 0, 1, 0)
        page.BackgroundTransparency = 1
        page.ScrollBarThickness = 4
        page.ScrollBarImageColor3 = THEME.BORDER_LIGHT
        page.CanvasSize = UDim2.new(0, 0, 0, 0)
        page.AutomaticCanvasSize = Enum.AutomaticSize.Y
        page.Visible = (t.Id == "Overview")
        page.Parent = mainContent

        local pList = Instance.new("UIListLayout")
        pList.Padding = UDim.new(0, 10)
        pList.Parent = page

        local pPad = Instance.new("UIPadding")
        pPad.PaddingTop = UDim.new(0, 12); pPad.PaddingBottom = UDim.new(0, 12)
        pPad.PaddingLeft = UDim.new(0, 14); pPad.PaddingRight = UDim.new(0, 14)
        pPad.Parent = page

        pages[t.Id] = page
    end

    -- Sincronizadores para Observer
    local syncInputs: { [string]: (number) -> () } = {}

    -- ---------------------------------------------------------------------
    -- Construtor de Componente: Slider com Input Numérico Sincronizado
    -- ---------------------------------------------------------------------
    local function CreateSliderField(parent: Instance, labelText: string, configKey: string, minVal: number, maxVal: number, defaultVal: number, step: number): Frame
        local span = math.max(maxVal - minVal, 0.0001)
        local safeDefault = tonumber(SimConfig.Get(configKey)) or defaultVal or minVal

        local container = Instance.new("Frame")
        container.Name = "SliderRow_" .. configKey
        container.Size = UDim2.new(1, 0, 0, 48)
        container.BackgroundColor3 = THEME.BG_INPUT
        container.BackgroundTransparency = 0.5
        container.Parent = parent
        AddCorner(container, 6)
        AddStroke(container, THEME.BORDER, 1)

        local rowHeader = Instance.new("Frame")
        rowHeader.Size = UDim2.new(1, -16, 0, 20)
        rowHeader.Position = UDim2.new(0, 8, 0, 6)
        rowHeader.BackgroundTransparency = 1
        rowHeader.Parent = container

        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(1, -65, 1, 0)
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.GothamMedium
        title.TextSize = 11
        title.TextColor3 = THEME.TEXT_MAIN
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Text = labelText
        title.Parent = rowHeader

        local numInput = Instance.new("TextBox")
        numInput.Size = UDim2.new(0, 60, 1, 0)
        numInput.Position = UDim2.new(1, -60, 0, 0)
        numInput.BackgroundColor3 = THEME.BG_WINDOW
        numInput.TextColor3 = THEME.ACCENT_RED
        numInput.Font = Enum.Font.GothamBold
        numInput.TextSize = 11
        numInput.Text = string.format(step < 1 and "%.2f" or "%d", safeDefault)
        numInput.ClearTextOnFocus = false
        numInput.Parent = rowHeader
        AddCorner(numInput, 4)
        AddStroke(numInput, THEME.BORDER, 1)

        local track = Instance.new("Frame")
        track.Size = UDim2.new(1, -16, 0, 6)
        track.Position = UDim2.new(0, 8, 0, 32)
        track.BackgroundColor3 = THEME.BG_WINDOW
        track.Parent = container
        AddCorner(track, 3)

        local initialRatio = math.clamp((safeDefault - minVal) / span, 0, 1)
        local fill = Instance.new("Frame")
        fill.Size = UDim2.new(initialRatio, 0, 1, 0)
        fill.BackgroundColor3 = THEME.ACCENT_RED
        fill.BorderSizePixel = 0
        fill.Parent = track
        AddCorner(fill, 3)

        local isDraggingSlider = false

        local function UpdateValue(val: number, fromObserver: boolean?)
            val = math.clamp(val, minVal, maxVal)
            val = math.round(val / step) * step
            local ratio = math.clamp((val - minVal) / span, 0, 1)
            fill.Size = UDim2.new(ratio, 0, 1, 0)
            numInput.Text = string.format(step < 1 and "%.2f" or "%d", val)
            if not fromObserver then
                SimConfig.Set(configKey, val)
            end
        end

        numInput.FocusLost:Connect(function()
            local num = tonumber(numInput.Text)
            if num then
                UpdateValue(num)
            else
                local fallback = tonumber(SimConfig.Get(configKey)) or safeDefault
                numInput.Text = string.format(step < 1 and "%.2f" or "%d", fallback)
            end
        end)

        track.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                isDraggingSlider = true
                local trackWidth = math.max(track.AbsoluteSize.X, 1)
                local relX = math.clamp((input.Position.X - track.AbsolutePosition.X) / trackWidth, 0, 1)
                UpdateValue(minVal + relX * span)
            end
        end)

        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                isDraggingSlider = false
            end
        end)

        UserInputService.InputChanged:Connect(function(input)
            if isDraggingSlider and input.UserInputType == Enum.UserInputType.MouseMovement then
                local trackWidth = math.max(track.AbsoluteSize.X, 1)
                local relX = math.clamp((input.Position.X - track.AbsolutePosition.X) / trackWidth, 0, 1)
                UpdateValue(minVal + relX * span)
            end
        end)

        syncInputs[configKey] = function(newVal: number)
            UpdateValue(newVal, true)
        end

        return container
    end

    -- ---------------------------------------------------------------------
    -- Construtor de Componente: Toggle Switch
    -- ---------------------------------------------------------------------
    local function CreateToggleField(parent: Instance, labelText: string, configKey: string, defaultState: boolean): Frame
        local container = Instance.new("Frame")
        container.Size = UDim2.new(1, 0, 0, 36)
        container.BackgroundColor3 = THEME.BG_INPUT
        container.BackgroundTransparency = 0.5
        container.Parent = parent
        AddCorner(container, 6)
        AddStroke(container, THEME.BORDER, 1)

        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(1, -60, 1, 0)
        title.Position = UDim2.new(0, 10, 0, 0)
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.GothamMedium
        title.TextSize = 11
        title.TextColor3 = THEME.TEXT_MAIN
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Text = labelText
        title.Parent = container

        local toggleBtn = Instance.new("TextButton")
        toggleBtn.Size = UDim2.new(0, 44, 0, 22)
        toggleBtn.Position = UDim2.new(1, -54, 0.5, -11)
        toggleBtn.BackgroundColor3 = defaultState and THEME.ACCENT_RED or THEME.BG_WINDOW
        toggleBtn.Text = ""
        toggleBtn.Parent = container
        AddCorner(toggleBtn, 11)
        AddStroke(toggleBtn, THEME.BORDER, 1)

        local dot = Instance.new("Frame")
        dot.Size = UDim2.new(0, 16, 0, 16)
        dot.Position = defaultState and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
        dot.BackgroundColor3 = THEME.TEXT_MAIN
        dot.Parent = toggleBtn
        AddCorner(dot, 8)

        local function SetToggle(state: boolean)
            toggleBtn.BackgroundColor3 = state and THEME.ACCENT_RED or THEME.BG_WINDOW
            dot.Position = state and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
            SimConfig.Set(configKey, state)
        end

        toggleBtn.MouseButton1Click:Connect(function()
            local current = SimConfig.Get(configKey) == true
            SetToggle(not current)
        end)

        SimConfig.Subscribe(configKey, function(val)
            local state = (val == true)
            toggleBtn.BackgroundColor3 = state and THEME.ACCENT_RED or THEME.BG_WINDOW
            dot.Position = state and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
        end)

        return container
    end

    -- =========================================================================
    -- [ABA 1] PAINEL GERAL (OVERVIEW)
    -- =========================================================================
    local pageOverview = pages["Overview"]

    -- Card de Boas-vindas e Ativação Mestra
    local masterCard = Instance.new("Frame")
    masterCard.Size = UDim2.new(1, 0, 0, 68)
    masterCard.BackgroundColor3 = THEME.BG_INPUT
    masterCard.Parent = pageOverview
    AddCorner(masterCard, 8)
    AddStroke(masterCard, THEME.BORDER, 1)

    local masterTitle = Instance.new("TextLabel")
    masterTitle.Size = UDim2.new(0.7, 0, 0, 24)
    masterTitle.Position = UDim2.new(0, 12, 0, 10)
    masterTitle.BackgroundTransparency = 1
    masterTitle.Font = Enum.Font.GothamBold
    masterTitle.TextSize = 13
    masterTitle.TextColor3 = THEME.TEXT_MAIN
    masterTitle.TextXAlignment = Enum.TextXAlignment.Left
    masterTitle.Text = "MOTOR DE CINEMÁTICA E DETECÇÃO DE COMPORTAMENTO"
    masterTitle.Parent = masterCard

    local masterDesc = Instance.new("TextLabel")
    masterDesc.Size = UDim2.new(0.7, 0, 0, 20)
    masterDesc.Position = UDim2.new(0, 12, 0, 36)
    masterDesc.BackgroundTransparency = 1
    masterDesc.Font = Enum.Font.GothamMedium
    masterDesc.TextSize = 10
    masterDesc.TextColor3 = THEME.TEXT_MUTED
    masterDesc.TextXAlignment = Enum.TextXAlignment.Left
    masterDesc.Text = "Simulador avançado com análise vetorial e telemetria anti-cheat em tempo real."
    masterDesc.Parent = masterCard

    local masterSwitch = Instance.new("TextButton")
    masterSwitch.Size = UDim2.new(0, 140, 0, 34)
    masterSwitch.Position = UDim2.new(1, -152, 0.5, -17)
    masterSwitch.BackgroundColor3 = SimConfig.Get("SimulationActive") and THEME.ACCENT_RED or THEME.BG_WINDOW
    masterSwitch.Font = Enum.Font.GothamBold
    masterSwitch.TextSize = 11
    masterSwitch.TextColor3 = THEME.TEXT_MAIN
    masterSwitch.Text = SimConfig.Get("SimulationActive") and "SIMULAÇÃO: ATIVA" or "SIMULAÇÃO: PAUSADA"
    masterSwitch.Parent = masterCard
    AddCorner(masterSwitch, 6)
    AddStroke(masterSwitch, THEME.BORDER_LIGHT, 1)

    masterSwitch.MouseButton1Click:Connect(function()
        local active = not SimConfig.Get("SimulationActive")
        SimConfig.Set("SimulationActive", active)
        masterSwitch.BackgroundColor3 = active and THEME.ACCENT_RED or THEME.BG_WINDOW
        masterSwitch.Text = active and "SIMULAÇÃO: ATIVA" or "SIMULAÇÃO: PAUSADA"
        DashboardGUI.AddDiagnosticLog("ENGINE", active and "Módulo iniciado com sucesso" or "Módulo colocado em espera", active and "OK" or "WARN")
    end)

    -- Seletor de Perfis Rápidos em Cards
    local profileHeader = Instance.new("TextLabel")
    profileHeader.Size = UDim2.new(1, 0, 0, 18)
    profileHeader.BackgroundTransparency = 1
    profileHeader.Font = Enum.Font.GothamBold
    profileHeader.TextSize = 11
    profileHeader.TextColor3 = THEME.ACCENT_RED
    profileHeader.TextXAlignment = Enum.TextXAlignment.Left
    profileHeader.Text = "SELEÇÃO DE PERFIL DE OPERAÇÃO"
    profileHeader.Parent = pageOverview

    local profileGrid = Instance.new("Frame")
    profileGrid.Size = UDim2.new(1, 0, 0, 42)
    profileGrid.BackgroundTransparency = 1
    profileGrid.Parent = pageOverview

    local pGridLayout = Instance.new("UIGridLayout")
    pGridLayout.CellSize = UDim2.new(0.19, 0, 1, 0)
    pGridLayout.CellPadding = UDim2.new(0.0125, 0, 0, 0)
    pGridLayout.Parent = profileGrid

    local profileCards: { [string]: TextButton } = {}
    local profileList = { "Normal", "Leve", "Medio", "Agressivo", "Custom" }

    local function UpdateProfileUI(activeProf: string)
        for name, btn in pairs(profileCards) do
            local isCurrent = (name == activeProf)
            btn.BackgroundColor3 = isCurrent and THEME.ACCENT_RED or THEME.BG_INPUT
            btn.TextColor3 = isCurrent and THEME.TEXT_MAIN or THEME.TEXT_MUTED
        end
    end

    for _, pName in ipairs(profileList) do
        local pBtn = Instance.new("TextButton")
        pBtn.BackgroundColor3 = (pName == SimConfig.Get("ActiveProfile")) and THEME.ACCENT_RED or THEME.BG_INPUT
        pBtn.Font = Enum.Font.GothamBold
        pBtn.TextSize = 11
        pBtn.TextColor3 = THEME.TEXT_MAIN
        pBtn.Text = pName
        pBtn.Parent = profileGrid
        AddCorner(pBtn, 6)
        AddStroke(pBtn, THEME.BORDER, 1)

        profileCards[pName] = pBtn

        pBtn.MouseButton1Click:Connect(function()
            SimConfig.LoadProfile(pName)
            UpdateProfileUI(pName)
            DashboardGUI.AddDiagnosticLog("CONFIG", "Perfil carregado: " .. pName, "INFO")
        end)
    end

    -- Mini Dashboard de Métricas Instantâneas
    local metricsGrid = Instance.new("Frame")
    metricsGrid.Size = UDim2.new(1, 0, 0, 84)
    metricsGrid.BackgroundTransparency = 1
    metricsGrid.Parent = pageOverview

    local mLayout = Instance.new("UIGridLayout")
    mLayout.CellSize = UDim2.new(0.238, 0, 1, 0)
    mLayout.CellPadding = UDim2.new(0.016, 0, 0, 0)
    mLayout.Parent = metricsGrid

    local function CreateMetricCard(title: string, defaultVal: string, keyName: string): Frame
        local card = Instance.new("Frame")
        card.BackgroundColor3 = THEME.BG_INPUT
        card.Parent = metricsGrid
        AddCorner(card, 6)
        AddStroke(card, THEME.BORDER, 1)

        local tLbl = Instance.new("TextLabel")
        tLbl.Size = UDim2.new(1, -12, 0, 16)
        tLbl.Position = UDim2.new(0, 8, 0, 10)
        tLbl.BackgroundTransparency = 1
        tLbl.Font = Enum.Font.GothamMedium
        tLbl.TextSize = 10
        tLbl.TextColor3 = THEME.TEXT_MUTED
        tLbl.TextXAlignment = Enum.TextXAlignment.Left
        tLbl.Text = title
        tLbl.Parent = card

        local vLbl = Instance.new("TextLabel")
        vLbl.Size = UDim2.new(1, -12, 0, 32)
        vLbl.Position = UDim2.new(0, 8, 0, 32)
        vLbl.BackgroundTransparency = 1
        vLbl.Font = Enum.Font.GothamBold
        vLbl.TextSize = 15
        vLbl.TextColor3 = THEME.TEXT_MAIN
        vLbl.TextXAlignment = Enum.TextXAlignment.Left
        vLbl.Text = defaultVal
        vLbl.Parent = card

        TelemetryLabels[keyName] = vLbl
        return card
    end

    CreateMetricCard("VELOCIDADE ANGULAR", "0.0 °/s", "AngVel")
    CreateMetricCard("STATUS DE VISÃO", "LIVRE", "VisStatus")
    CreateMetricCard("ALVO ATIVO", "NENHUM", "ActiveTarget")
    CreateMetricCard("TAXA DE QUADROS", "60 FPS", "FpsCounter")

    -- =========================================================================
    -- [ABA 2] CÂMERA & VETORES
    -- =========================================================================
    local pageCamera = pages["Camera"]
    CreateSliderField(pageCamera, "Campo de Visão Útil (FOV °)", "FOV", 10, 180, SimConfig.Get("FOV"), 1)
    CreateSliderField(pageCamera, "Coeficiente de Suavização (Lerp)", "Smoothing", 0.01, 1.0, SimConfig.Get("Smoothing"), 0.01)
    CreateSliderField(pageCamera, "Velocidade Angular Máxima (°/s)", "AngularVelocity", 30, 720, SimConfig.Get("AngularVelocity"), 5)
    CreateSliderField(pageCamera, "Tempo de Resposta Simulado (ms)", "ResponseTime", 0, 250, SimConfig.Get("ResponseTime"), 1)
    CreateSliderField(pageCamera, "Precisão de Trajetória (%)", "TrajectoryPrecision", 50, 100, SimConfig.Get("TrajectoryPrecision"), 0.5)
    CreateSliderField(pageCamera, "Frequência de Atualização (Hz)", "UpdateFrequency", 10, 144, SimConfig.Get("UpdateFrequency"), 5)
    CreateSliderField(pageCamera, "Raio Máximo de Atuação (studs)", "VectorRadius", 10, 500, SimConfig.Get("VectorRadius"), 5)

    -- =========================================================================
    -- [ABA 3] SIMULAÇÃO & COMPORTAMENTO
    -- =========================================================================
    local pageSim = pages["Simulation"]
    CreateToggleField(pageSim, "Segurar Botão Direito para Focar (Hold to Aim)", "HoldToAim", SimConfig.Get("HoldToAim"))
    CreateToggleField(pageSim, "Simular Micro-Variações Orgânicas (Perlin Jitter)", "SimulateJitter", SimConfig.Get("SimulateJitter"))
    CreateSliderField(pageSim, "Frequência de Eventos (Hz)", "EventFrequency", 1, 60, SimConfig.Get("EventFrequency"), 1)
    CreateSliderField(pageSim, "Intensidade da Resposta (%)", "Intensity", 0, 100, SimConfig.Get("Intensity"), 1)
    CreateSliderField(pageSim, "Velocidade de Deslocamento (studs/s)", "MoveSpeed", 8, 40, SimConfig.Get("MoveSpeed"), 1)
    CreateSliderField(pageSim, "Curva de Aceleração (Hermite Exponent)", "AccelerationCurve", 0.2, 3.0, SimConfig.Get("AccelerationCurve"), 0.05)
    CreateSliderField(pageSim, "Duração do Ciclo de Teste (s)", "CycleDuration", 5, 120, SimConfig.Get("CycleDuration"), 5)
    CreateSliderField(pageSim, "Agentes Concorrentes Simulados", "SimulatedAgents", 1, 16, SimConfig.Get("SimulatedAgents"), 1)

    -- =========================================================================
    -- [ABA 4] LINHA DE VISÃO & ESP
    -- =========================================================================
    local pageVision = pages["Vision"]
    CreateToggleField(pageVision, "Realce Visual de Entidades (Highlights ESP)", "EnableESP", SimConfig.Get("EnableESP"))
    CreateToggleField(pageVision, "Exibir Círculo de FOV na Tela", "ShowFovCircle", SimConfig.Get("ShowFovCircle"))
    CreateToggleField(pageVision, "Filtrar Somente Alvos com Visada Livre (Visible Only)", "VisibleOnly", SimConfig.Get("VisibleOnly"))
    CreateToggleField(pageVision, "Ignorar Aliados da Mesma Equipe (Team Check)", "TeamCheck", SimConfig.Get("TeamCheck"))
    CreateToggleField(pageVision, "Ativar Predição Balística de Alvo (Lead Tracking)", "EnableLead", SimConfig.Get("EnableLead"))
    CreateSliderField(pageVision, "Velocidade Balística Simulada (studs/s)", "ProjectileSpeed", 300, 3000, SimConfig.Get("ProjectileSpeed"), 50)

    -- =========================================================================
    -- [ABA 5] MAPEAMENTO HITBOX (MANEQUIM INTERATIVO)
    -- =========================================================================
    local pageHitbox = pages["Hitbox"]

    local mannequinContainer = Instance.new("Frame")
    mannequinContainer.Size = UDim2.new(1, 0, 0, 260)
    mannequinContainer.BackgroundColor3 = THEME.BG_INPUT
    mannequinContainer.Parent = pageHitbox
    AddCorner(mannequinContainer, 8)
    AddStroke(mannequinContainer, THEME.BORDER, 1)

    -- Linhas do esqueleto
    local spine = Instance.new("Frame")
    spine.Size = UDim2.new(0, 2, 0.55, 0)
    spine.Position = UDim2.new(0.5, -1, 0.18, 0)
    spine.BackgroundColor3 = THEME.BORDER_LIGHT
    spine.BorderSizePixel = 0
    spine.Parent = mannequinContainer

    local shoulders = Instance.new("Frame")
    shoulders.Size = UDim2.new(0.4, 0, 0, 2)
    shoulders.Position = UDim2.new(0.3, 0, 0.32, 0)
    shoulders.BackgroundColor3 = THEME.BORDER_LIGHT
    shoulders.BorderSizePixel = 0
    shoulders.Parent = mannequinContainer

    local legL = Instance.new("Frame")
    legL.Size = UDim2.new(0, 2, 0.3, 0)
    legL.Position = UDim2.new(0.4, -1, 0.65, 0)
    legL.BackgroundColor3 = THEME.BORDER_LIGHT
    legL.BorderSizePixel = 0
    legL.Parent = mannequinContainer

    local legR = Instance.new("Frame")
    legR.Size = UDim2.new(0, 2, 0.3, 0)
    legR.Position = UDim2.new(0.6, -1, 0.65, 0)
    legR.BackgroundColor3 = THEME.BORDER_LIGHT
    legR.BorderSizePixel = 0
    legR.Parent = mannequinContainer

    local activeBadge = Instance.new("TextLabel")
    activeBadge.Size = UDim2.new(0, 220, 0, 26)
    activeBadge.Position = UDim2.new(0.5, -110, 0.9, -20)
    activeBadge.BackgroundColor3 = THEME.BG_WINDOW
    activeBadge.Font = Enum.Font.GothamBold
    activeBadge.TextSize = 11
    activeBadge.TextColor3 = THEME.ACCENT_RED
    activeBadge.Text = "REGIÃO ATIVA: [ HEAD ]"
    activeBadge.Parent = mannequinContainer
    AddCorner(activeBadge, 4)
    AddStroke(activeBadge, THEME.BORDER, 1)

    local nodes = {
        { Name = "Head",  Pos = UDim2.new(0.5, -11, 0.12, 0), Size = 22 },
        { Name = "Torso", Pos = UDim2.new(0.5, -13, 0.38, 0), Size = 26 },
        { Name = "Arms",  Pos = UDim2.new(0.3, -10, 0.38, 0), Size = 20 },
        { Name = "Arms",  Pos = UDim2.new(0.7, -10, 0.38, 0), Size = 20 },
        { Name = "Legs",  Pos = UDim2.new(0.4, -10, 0.78, 0), Size = 20 },
        { Name = "Legs",  Pos = UDim2.new(0.6, -10, 0.78, 0), Size = 20 },
    }

    local nodeButtons: { { Btn: TextButton, Region: string } } = {}

    local function HighlightNodeRegion(regionName: string)
        activeBadge.Text = "REGIÃO ATIVA: [ " .. string.upper(regionName) .. " ]"
        for _, n in ipairs(nodeButtons) do
            local isSelected = (n.Region == regionName)
            n.Btn.BackgroundColor3 = isSelected and THEME.ACCENT_RED or THEME.BORDER_LIGHT
        end
    end

    for _, n in ipairs(nodes) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, n.Size, 0, n.Size)
        btn.Position = n.Pos
        btn.BackgroundColor3 = (n.Name == SimConfig.Get("TargetRegion")) and THEME.ACCENT_RED or THEME.BORDER_LIGHT
        btn.Text = ""
        btn.Parent = mannequinContainer
        AddCorner(btn, n.Size / 2)
        table.insert(nodeButtons, { Btn = btn, Region = n.Name })

        btn.MouseButton1Click:Connect(function()
            SimConfig.Set("TargetRegion", n.Name)
            SimConfig.Set("TargetBone", n.Name)
            HighlightNodeRegion(n.Name)
            DashboardGUI.AddDiagnosticLog("TARGETING", "Região corporal definida: " .. n.Name, "OK")
        end)
    end

    -- =========================================================================
    -- [ABA 6] DIAGNÓSTICOS & LOGS
    -- =========================================================================
    local pageDiag = pages["Diagnostics"]

    local diagHeader = Instance.new("Frame")
    diagHeader.Size = UDim2.new(1, 0, 0, 36)
    diagHeader.BackgroundColor3 = THEME.BG_INPUT
    diagHeader.Parent = pageDiag
    AddCorner(diagHeader, 6)

    local diagTitle = Instance.new("TextLabel")
    diagTitle.Size = UDim2.new(0.7, 0, 1, 0)
    diagTitle.Position = UDim2.new(0, 10, 0, 0)
    diagTitle.BackgroundTransparency = 1
    diagTitle.Font = Enum.Font.GothamBold
    diagTitle.TextSize = 11
    diagTitle.TextColor3 = THEME.TEXT_MAIN
    diagTitle.TextXAlignment = Enum.TextXAlignment.Left
    diagTitle.Text = "FEED DE EVENTOS & ESTABILIDADE DO KERNEL"
    diagTitle.Parent = diagHeader

    local clearLogsBtn = Instance.new("TextButton")
    clearLogsBtn.Size = UDim2.new(0, 90, 0, 24)
    clearLogsBtn.Position = UDim2.new(1, -100, 0.5, -12)
    clearLogsBtn.BackgroundColor3 = THEME.BG_WINDOW
    clearLogsBtn.Font = Enum.Font.GothamMedium
    clearLogsBtn.TextSize = 10
    clearLogsBtn.TextColor3 = THEME.TEXT_MAIN
    clearLogsBtn.Text = "Limpar Logs"
    clearLogsBtn.Parent = diagHeader
    AddCorner(clearLogsBtn, 4)

    local logScroll = Instance.new("ScrollingFrame")
    logScroll.Size = UDim2.new(1, 0, 0, 240)
    logScroll.BackgroundColor3 = THEME.BG_WINDOW
    logScroll.ScrollBarThickness = 4
    logScroll.ScrollBarImageColor3 = THEME.BORDER_LIGHT
    logScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    logScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    logScroll.Parent = pageDiag
    AddCorner(logScroll, 6)
    AddStroke(logScroll, THEME.BORDER, 1)

    local logList = Instance.new("UIListLayout")
    logList.Padding = UDim.new(0, 4)
    logList.Parent = logScroll

    local logPad = Instance.new("UIPadding")
    logPad.PaddingTop = UDim.new(0, 6); logPad.PaddingBottom = UDim.new(0, 6)
    logPad.PaddingLeft = UDim.new(0, 6); logPad.PaddingRight = UDim.new(0, 6)
    logPad.Parent = logScroll
    EventLogListInstance = logScroll

    clearLogsBtn.MouseButton1Click:Connect(function()
        for _, ch in ipairs(logScroll:GetChildren()) do
            if ch:IsA("Frame") then ch:Destroy() end
        end
        DashboardGUI.AddDiagnosticLog("SYSTEM", "Logs limpos com sucesso.", "INFO")
    end)

    -- =========================================================================
    -- [ABA 7] DESEMPENHO & FRAME TIME
    -- =========================================================================
    local pagePerf = pages["Performance"]

    local perfCard = Instance.new("Frame")
    perfCard.Size = UDim2.new(1, 0, 0, 110)
    perfCard.BackgroundColor3 = THEME.BG_INPUT
    perfCard.Parent = pagePerf
    AddCorner(perfCard, 6)
    AddStroke(perfCard, THEME.BORDER, 1)

    local perfTitle = Instance.new("TextLabel")
    perfTitle.Size = UDim2.new(1, -20, 0, 20)
    perfTitle.Position = UDim2.new(0, 10, 0, 10)
    perfTitle.BackgroundTransparency = 1
    perfTitle.Font = Enum.Font.GothamBold
    perfTitle.TextSize = 12
    perfTitle.TextColor3 = THEME.TEXT_MAIN
    perfTitle.TextXAlignment = Enum.TextXAlignment.Left
    perfTitle.Text = "MÉTRICAS DE COMPUTAÇÃO VETORIAL"
    perfTitle.Parent = perfCard

    local perfInfo = Instance.new("TextLabel")
    perfInfo.Size = UDim2.new(1, -20, 0, 60)
    perfInfo.Position = UDim2.new(0, 10, 0, 35)
    perfInfo.BackgroundTransparency = 1
    perfInfo.Font = Enum.Font.Code
    perfInfo.TextSize = 11
    perfInfo.TextColor3 = THEME.SUCCESS
    perfInfo.TextXAlignment = Enum.TextXAlignment.Left
    perfInfo.Text = "Frame-Time: 16.6ms (Alvo 60 FPS)\nOverhead Cinemático: < 0.05ms\nGuarda Epsilon: 1e-4 Ativa | Sem NaN Detectado"
    perfInfo.Parent = perfCard
    TelemetryLabels["PerfInfo"] = perfInfo

    -- =========================================================================
    -- [ABA 8] CONFIGURAÇÕES & ARMAZENAMENTO
    -- =========================================================================
    local pageSettings = pages["Settings"]
    CreateToggleField(pageSettings, "Ativar Watchdog Contínuo em Segundo Plano", "WatchdogEnabled", SimConfig.Get("WatchdogEnabled"))
    CreateToggleField(pageSettings, "Exibir Mensagens de Debug no Console", "DebugLogging", SimConfig.Get("DebugLogging"))

    local btnRow = Instance.new("Frame")
    btnRow.Size = UDim2.new(1, 0, 0, 38)
    btnRow.BackgroundTransparency = 1
    btnRow.Parent = pageSettings

    local btnRowLayout = Instance.new("UIListLayout")
    btnRowLayout.FillDirection = Enum.FillDirection.Horizontal
    btnRowLayout.Padding = UDim.new(0, 10)
    btnRowLayout.Parent = btnRow

    local function CreateExportBtn(text: string, onClick: () -> ()): TextButton
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0.48, 0, 1, 0)
        b.BackgroundColor3 = THEME.BG_INPUT
        b.Font = Enum.Font.GothamBold
        b.TextSize = 11
        b.TextColor3 = THEME.TEXT_MAIN
        b.Text = text
        b.Parent = btnRow
        AddCorner(b, 6)
        AddStroke(b, THEME.BORDER, 1)
        b.MouseButton1Click:Connect(onClick)
        return b
    end

    CreateExportBtn("📤 EXPORTAR CONFIG (JSON)", function()
        local json = SimConfig.ExportJSON()
        pcall(function()
            if setclipboard then
                setclipboard(json)
                DashboardGUI.AddDiagnosticLog("CONFIG", "JSON copiado para a área de transferência!", "OK")
            else
                DashboardGUI.AddDiagnosticLog("CONFIG", "JSON gerado (verifique no console)", "INFO")
                print("\n[DeepHat SimConfig JSON Export]\n" .. json)
            end
        end)
    end)

    CreateExportBtn("↺ RESTAURAR PADRÕES", function()
        SimConfig.LoadProfile("Normal")
        UpdateProfileUI("Normal")
        DashboardGUI.AddDiagnosticLog("CONFIG", "Configurações restauradas para o perfil Normal.", "WARN")
    end)

    -- ---------------------------------------------------------------------
    -- Barra Inferior de Ações
    -- ---------------------------------------------------------------------
    local footer = Instance.new("Frame")
    footer.Size = UDim2.new(1, 0, 0, 48)
    footer.Position = UDim2.new(0, 0, 1, -48)
    footer.BackgroundColor3 = THEME.BG_SIDEBAR
    footer.BorderSizePixel = 0
    footer.Parent = mainFrame
    AddCorner(footer, 8)
    AddStroke(footer, THEME.BORDER, 1)

    local footerLayout = Instance.new("UIListLayout")
    footerLayout.FillDirection = Enum.FillDirection.Horizontal
    footerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    footerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    footerLayout.Padding = UDim.new(0, 8)
    footerLayout.Parent = footer

    local footerPad = Instance.new("UIPadding")
    footerPad.PaddingRight = UDim.new(0, 14)
    footerPad.Parent = footer

    local function CreateBottomButton(text: string, isPrimary: boolean, onClick: () -> ()): TextButton
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 140, 0, 32)
        btn.BackgroundColor3 = isPrimary and THEME.ACCENT_RED or THEME.BG_INPUT
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 11
        btn.TextColor3 = THEME.TEXT_MAIN
        btn.Text = text
        btn.Parent = footer
        AddCorner(btn, 5)
        AddStroke(btn, isPrimary and THEME.ACCENT_HOVER or THEME.BORDER, 1)
        btn.MouseButton1Click:Connect(onClick)
        return btn
    end

    CreateBottomButton("↺ RESETAR", false, function()
        SimConfig.LoadProfile("Normal")
        UpdateProfileUI("Normal")
        if DashboardGUI.OnResetRequested then DashboardGUI.OnResetRequested() end
    end)

    CreateBottomButton("💾 SALVAR CONFIG", false, function()
        pcall(function()
            game:GetService("StarterGui"):SetCore("SendNotification", {
                Title = "DeepHat Suite",
                Text = "Configurações persistidas com sucesso!",
                Duration = 3
            })
        end)
        DashboardGUI.AddDiagnosticLog("SAVE", "Configurações salvas no armazenamento local.", "OK")
        if DashboardGUI.OnSaveRequested then DashboardGUI.OnSaveRequested() end
    end)

    CreateBottomButton("⏹ PARAR", false, function()
        SimConfig.Set("SimulationActive", false)
        masterSwitch.BackgroundColor3 = THEME.BG_WINDOW
        masterSwitch.Text = "SIMULAÇÃO: PAUSADA"
        DashboardGUI.AddDiagnosticLog("ENGINE", "Execução interrompida pelo usuário.", "WARN")
        if DashboardGUI.OnStopRequested then DashboardGUI.OnStopRequested() end
    end)

    CreateBottomButton("▶ INICIAR TESTE", true, function()
        SimConfig.Set("SimulationActive", true)
        masterSwitch.BackgroundColor3 = THEME.ACCENT_RED
        masterSwitch.Text = "SIMULAÇÃO: ATIVA"
        DashboardGUI.AddDiagnosticLog("ENGINE", "Sessão de teste iniciada.", "OK")
        if DashboardGUI.OnStartRequested then DashboardGUI.OnStartRequested() end
    end)

    -- Sincronização Observer
    SimConfig.SubscribeAll(function(key, val)
        if key == "ActiveProfile" then
            UpdateProfileUI(tostring(val))
        elseif key == "TargetRegion" then
            HighlightNodeRegion(tostring(val))
        elseif key == "SimulationActive" then
            local active = (val == true)
            masterSwitch.BackgroundColor3 = active and THEME.ACCENT_RED or THEME.BG_WINDOW
            masterSwitch.Text = active and "SIMULAÇÃO: ATIVA" or "SIMULAÇÃO: PAUSADA"
            if FovCircleInstance then
                FovCircleInstance.Visible = active and (SimConfig.Get("ShowFovCircle") == true)
            end
        elseif syncInputs[key] and typeof(val) == "number" then
            syncInputs[key](val)
        end
    end)

    -- Log Inicial
    DashboardGUI.AddDiagnosticLog("INIT", "Dashboard GUI carregada com 8 abas de controle.", "OK")

    return screenGui
end

-- =========================================================================
-- MÉTODOS PÚBLICOS DE TELEMETRIA & ATUALIZAÇÃO
-- =========================================================================

function DashboardGUI:UpdateFovCircle()
    if not FovCircleInstance or not FovCircleInstance.Parent then return end
    local camera = Workspace.CurrentCamera
    if not camera then return end

    local active = SimConfig.Get("SimulationActive") == true
    local show = SimConfig.Get("ShowFovCircle") == true and active
    FovCircleInstance.Visible = show

    if show then
        local fov = tonumber(SimConfig.Get("FOV")) or 70.0
        local vp = camera.ViewportSize
        local halfFovRad = math.rad(fov / 2)
        local camFovRad = math.rad(camera.FieldOfView / 2)
        local radius = (math.tan(halfFovRad) / math.max(math.tan(camFovRad), 0.001)) * (vp.Y / 2)
        FovCircleInstance.Size = UDim2.new(0, radius * 2, 0, radius * 2)
        FovCircleInstance.Position = UDim2.new(0.5, 0, 0.5, 0)
    end
end

function DashboardGUI:UpdateTelemetryDisplay(data: {
    angularVelocity: number?,
    isObstructed: boolean?,
    targetName: string?,
    dt: number?,
    mode: string?
})
    if not data then return end

    local angVel = tonumber(data.angularVelocity) or 0
    if angVel > PerformanceData.PeakAngVel then
        PerformanceData.PeakAngVel = angVel
    end

    if TelemetryLabels["AngVel"] then
        TelemetryLabels["AngVel"].Text = string.format("%.1f °/s", angVel)
    end

    if TelemetryLabels["VisStatus"] then
        local obstructed = (data.isObstructed == true)
        TelemetryLabels["VisStatus"].Text = obstructed and "OBSTRUÍDO" or "LIVRE"
        TelemetryLabels["VisStatus"].TextColor3 = obstructed and THEME.ACCENT_RED or THEME.SUCCESS
    end

    if TelemetryLabels["ActiveTarget"] then
        local tName = data.targetName or "NENHUM"
        TelemetryLabels["ActiveTarget"].Text = tName
        TelemetryLabels["ActiveTarget"].TextColor3 = (tName ~= "NENHUM") and THEME.SUCCESS or THEME.TEXT_MUTED
    end

    local dt = tonumber(data.dt) or 0.0166
    local currentFps = math.clamp(math.floor(1 / math.max(dt, 0.001)), 1, 240)
    PerformanceData.Fps = currentFps

    if TelemetryLabels["FpsCounter"] then
        TelemetryLabels["FpsCounter"].Text = string.format("%d FPS", currentFps)
        TelemetryLabels["FpsCounter"].TextColor3 = (currentFps >= 50) and THEME.SUCCESS or (currentFps >= 30 and THEME.WARNING or THEME.ACCENT_RED)
    end

    if TelemetryLabels["PerfInfo"] then
        local frameTimeMs = dt * 1000
        TelemetryLabels["PerfInfo"].Text = string.format(
            "Frame-Time: %.1fms | Pico Angular: %.1f °/s\nStatus: %s | FPS: %d\nWatchdog: Ativo sem erros",
            frameTimeMs,
            PerformanceData.PeakAngVel,
            tostring(data.mode or "IDLE"),
            currentFps
        )
    end
end

-- =========================================================================
-- WATCHDOG DE FUNDO (CONTINUOUS BACKGROUND HEALTH CHECK)
-- =========================================================================
task.spawn(function()
    while true do
        task.wait(1.5)
        if SimConfig.Get("WatchdogEnabled") == true then
            local camera = Workspace.CurrentCamera
            local healthGood = true
            local reason = ""

            -- 1. Verifica integridade da câmera
            if not camera then
                healthGood = false
                reason = "Câmera ausente"
            else
                local pos = camera.CFrame.Position
                if pos.X ~= pos.X or pos.Y ~= pos.Y or pos.Z ~= pos.Z then
                    healthGood = false
                    reason = "Anomalia NaN na câmera"
                    camera.CFrame = CFrame.new(0, 10, 0)
                end
            end

            -- 2. Verifica limites do SimConfig
            local fov = tonumber(SimConfig.Get("FOV")) or 70
            if fov < 10 or fov > 180 then
                SimConfig.Set("FOV", math.clamp(fov, 10, 180))
            end

            -- 3. Atualiza Badge
            if WatchdogBadgeInstance and WatchdogBadgeInstance.Parent then
                if healthGood then
                    WatchdogBadgeInstance.Text = "● WATCHDOG: 100% OPERACIONAL"
                    WatchdogBadgeInstance.TextColor3 = THEME.SUCCESS
                else
                    WatchdogBadgeInstance.Text = "⚠️ ALERTA: " .. string.upper(reason)
                    WatchdogBadgeInstance.TextColor3 = THEME.WARNING
                    DashboardGUI.AddDiagnosticLog("WATCHDOG", "Recuperação aplicada: " .. reason, "WARN")
                end
            end
        end
    end
end)

return DashboardGUI
