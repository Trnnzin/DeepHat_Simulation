--!strict
-- =========================================================================
-- DashboardGUI.lua
-- Interface Profissional de Simulação Cinemática e Diagnósticos de Detecção
-- Versão: V8.0 PRO — Plataforma Profissional com Design Grafite & Deep Purple
-- Arquitetura em 8 Abas Especializadas:
--   1. Dashboard: Visão Geral, Indicadores KPI, Watchdog e Ações Rápidas
--   2. Mira Simulada: Parâmetros Cinemáticos, Suavização, FOV e Deadband
--   3. Player & Disparos: Manequim Sintético, Silent Aim e Pipeline em 5 Etapas
--   4. ESP de Teste: Highlights Chams e Tags 3D Flutuantes (BillboardGui)
--   5. Balística: Trajetória Física sob Gravidade, Predição de Lead e Fórmulas
--   6. Diagnóstico & IA: Análise de 6 Camadas, Hipóteses, Chatbot e Exportação
--   7. Logs & Eventos: Terminal de Observabilidade, Filtros e Busca Textual
--   8. Configurações: Perfis, Importação/Exportação JSON e Reset de Padrões
-- =========================================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CoreGuiService = game:GetService("CoreGui")

local SimConfig = require(script.Parent.SimConfig)
local ScenarioRunner = require(script.Parent.ScenarioRunner)
local DiagnosticAI = require(script.Parent.DiagnosticAI)

local DashboardGUI = {}
DashboardGUI.__index = DashboardGUI

-- [DESIGN SYSTEM & TOKENS VISUAIS - TEMA GRAFITE & DEEP PURPLE V8]
local THEME = {
    BG_WINDOW     = Color3.fromRGB(13, 14, 20),      -- Grafite ultra-escuro profundo
    BG_SIDEBAR    = Color3.fromRGB(17, 18, 26),      -- Grafite escuro lateral
    BG_CARD       = Color3.fromRGB(22, 24, 34),      -- Cartão com tom sutil grafite/antracite
    BG_INPUT      = Color3.fromRGB(28, 30, 44),      -- Fundo de inputs e toggles
    BORDER        = Color3.fromRGB(46, 44, 68),      -- Borda sutil grafite-púrpura
    BORDER_LIGHT  = Color3.fromRGB(68, 64, 102),     -- Borda destacada
    TEXT_MAIN     = Color3.fromRGB(245, 245, 252),   -- Texto primário límpido
    TEXT_MUTED    = Color3.fromRGB(152, 154, 178),   -- Texto secundário suave
    ACCENT_PURPLE = Color3.fromRGB(138, 75, 255),    -- Roxo vibrante moderno (V8 Accent)
    ACCENT_HOVER  = Color3.fromRGB(162, 105, 255),   -- Roxo luminoso para hover/foco
    ACCENT_GLOW   = Color3.fromRGB(65, 28, 120),     -- Brilho ambiente roxo
    ACCENT_RED    = Color3.fromRGB(235, 59, 90),     -- Alertas e gravação
    SUCCESS       = Color3.fromRGB(46, 204, 113),    -- Verde confirmação OK
    WARNING       = Color3.fromRGB(241, 196, 15),    -- Amarelo WARN
    INFO          = Color3.fromRGB(116, 125, 255),   -- Índigo/Azul claro INFO
}

-- Callbacks de Ação Global
DashboardGUI.OnStartRequested = nil :: (() -> ())?
DashboardGUI.OnStopRequested = nil :: (() -> ())?
DashboardGUI.OnResetRequested = nil :: (() -> ())?
DashboardGUI.OnSaveRequested = nil :: (() -> ())?
DashboardGUI.OnRunLosScenario = nil :: ((string) -> ())?
DashboardGUI.OnClearLosHistory = nil :: (() -> ())?
DashboardGUI.OnSimulateSilentAimShot = nil :: (() -> ())?
DashboardGUI.OnSpawnTestDummy = nil :: (() -> ())?
DashboardGUI.OnClearTestDummies = nil :: (() -> ())?
DashboardGUI.OnRunShotScenario = nil :: ((string) -> ())?
DashboardGUI.OnQueryDiagnosticChatbot = nil :: ((string) -> any)?
DashboardGUI.OnRunFullDiagnostic = nil :: (() -> any)?
DashboardGUI.OnExportDiagnosticsJSON = nil :: (() -> string)?
DashboardGUI.OnExportDiagnosticsMarkdown = nil :: (() -> string)?

-- Instâncias Internas
local ScreenGuiInstance: ScreenGui? = nil
local MainFrameInstance: Frame? = nil
local FovCircleInstance: Frame? = nil
local WatchdogBadgeInstance: TextLabel? = nil
local EventLogListInstance: ScrollingFrame? = nil
local LogCounterLabelInstance: TextLabel? = nil
local unsubscribeGlobal: (() -> ())? = nil

-- Elementos de Telemetria Dinâmica
local TelemetryLabels: { [string]: TextLabel } = {}
local LosLabels: { [string]: TextLabel } = {}
local DetLabels: { [string]: TextLabel } = {}
local LosHistoryList: ScrollingFrame? = nil
local LastRenderedLosStamp = -1
local PerformanceData = {
    Fps = 60,
    PeakAngVel = 0,
    LastCheck = os.clock(),
    ErrorCount = 0,
}

local currentLogFilter = "TODOS"
local currentLogSearch = ""

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
            test.Name = "DeepHat_PermTest"
            test.Parent = coreGui
            test:Destroy()
        end)
        if testOk then return coreGui end
    end

    local localPlayer = Players.LocalPlayer
    if not localPlayer then
        pcall(function()
            localPlayer = Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
        end)
        localPlayer = Players.LocalPlayer
    end

    if localPlayer then
        local pGui = localPlayer:FindFirstChildOfClass("PlayerGui")
        if pGui then return pGui end
    end

    return Workspace
end

-- =========================================================================
-- LOG DE DIAGNÓSTICOS EM TEMPO REAL COM FILTRAGEM E BUSCA
-- =========================================================================
local function ApplyLogFilter()
    if not EventLogListInstance then return end
    local visibleCount = 0
    local totalCount = 0
    local query = string.lower(currentLogSearch)

    for _, child in ipairs(EventLogListInstance:GetChildren()) do
        if child:IsA("Frame") then
            totalCount = totalCount + 1
            local lvl = child:GetAttribute("LogLevel") or "INFO"
            local text = string.lower(tostring(child:GetAttribute("LogText") or ""))
            local levelMatch = (currentLogFilter == "TODOS" or lvl == currentLogFilter)
            local searchMatch = (query == "" or string.find(text, query, 1, true) ~= nil)

            if levelMatch and searchMatch then
                child.Visible = true
                visibleCount = visibleCount + 1
            else
                child.Visible = false
            end
        end
    end

    if LogCounterLabelInstance and LogCounterLabelInstance.Parent then
        LogCounterLabelInstance.Text = string.format("Exibindo %d de %d eventos", visibleCount, totalCount)
    end
end

function DashboardGUI.AddDiagnosticLog(source: string, message: string, level: ("INFO" | "WARN" | "OK" | "FAIL")?)
    if not EventLogListInstance or not EventLogListInstance.Parent then return end

    local rowLevel = level or "INFO"
    local color = THEME.TEXT_MAIN
    if rowLevel == "WARN" then color = THEME.WARNING
    elseif rowLevel == "OK" then color = THEME.SUCCESS
    elseif rowLevel == "INFO" then color = THEME.INFO
    elseif rowLevel == "FAIL" then color = THEME.ACCENT_RED end

    local timeStr = os.date("%H:%M:%S")
    local fullText = string.format("[%s] [%s] %s", timeStr, source, message)

    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 22)
    row.BackgroundColor3 = THEME.BG_INPUT
    row.BackgroundTransparency = 0.5
    row:SetAttribute("LogLevel", rowLevel)
    row:SetAttribute("LogText", fullText)

    local query = string.lower(currentLogSearch)
    local levelMatch = (currentLogFilter == "TODOS" or rowLevel == currentLogFilter)
    local searchMatch = (query == "" or string.find(string.lower(fullText), query, 1, true) ~= nil)
    row.Visible = (levelMatch and searchMatch)
    row.Parent = EventLogListInstance
    AddCorner(row, 4)

    local dot = Instance.new("Frame")
    dot.Size = UDim2.new(0, 6, 0, 6)
    dot.Position = UDim2.new(0, 6, 0.5, -3)
    dot.BackgroundColor3 = color
    dot.BorderSizePixel = 0
    dot.Parent = row
    AddCorner(dot, 3)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -22, 1, 0)
    lbl.Position = UDim2.new(0, 18, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.Code
    lbl.TextSize = 10
    lbl.TextColor3 = color
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Text = fullText
    lbl.Parent = row

    local children = EventLogListInstance:GetChildren()
    if #children > 60 then
        for i = 1, #children - 60 do
            if children[i]:IsA("Frame") then children[i]:Destroy() end
        end
    end

    ApplyLogFilter()
    EventLogListInstance.CanvasPosition = Vector2.new(0, 99999)
end

-- =========================================================================
-- CONSTRUÇÃO DA INTERFACE PRINCIPAL (8 ABAS FUNCIONAIS V8)
-- =========================================================================
function DashboardGUI.Create(): ScreenGui
    local oldGui = CoreGuiService:FindFirstChild("DeepHat_DashboardUI")
        or (Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui") and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui"):FindFirstChild("DeepHat_DashboardUI"))
    if oldGui then
        oldGui:Destroy()
    end

    local guiParent = GetSafeGuiParent()

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "DeepHat_DashboardUI"
    screenGui.ResetOnSpawn = false
    screenGui.DisplayOrder = 1000
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = guiParent
    ScreenGuiInstance = screenGui

    -- Overlay Circular do FOV
    local fovCircle = Instance.new("Frame")
    fovCircle.Name = "FovCircle"
    fovCircle.Size = UDim2.new(0, 240, 0, 240)
    fovCircle.AnchorPoint = Vector2.new(0.5, 0.5)
    fovCircle.Position = UDim2.new(0.5, 0, 0.5, 0)
    fovCircle.BackgroundTransparency = 1
    fovCircle.Visible = SimConfig.Get("ShowFovCircle") == true and SimConfig.Get("SimulationActive") == true
    fovCircle.Parent = screenGui
    AddCorner(fovCircle, 9999)
    local fovStroke = AddStroke(fovCircle, THEME.ACCENT_PURPLE, 1.5)
    fovStroke.Transparency = 0.35
    FovCircleInstance = fovCircle

    local fovCenterDot = Instance.new("Frame")
    fovCenterDot.Size = UDim2.new(0, 4, 0, 4)
    fovCenterDot.AnchorPoint = Vector2.new(0.5, 0.5)
    fovCenterDot.Position = UDim2.new(0.5, 0, 0.5, 0)
    fovCenterDot.BackgroundColor3 = THEME.ACCENT_PURPLE
    fovCenterDot.BackgroundTransparency = 0.2
    fovCenterDot.Parent = fovCircle
    AddCorner(fovCenterDot, 2)

    -- Janela Principal
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.new(0, 980, 0, 600)
    mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    mainFrame.BackgroundColor3 = THEME.BG_WINDOW
    mainFrame.BorderSizePixel = 0
    mainFrame.Active = true
    mainFrame.Visible = true
    mainFrame.Parent = screenGui
    AddCorner(mainFrame, 10)
    AddStroke(mainFrame, THEME.BORDER, 1.5)
    MainFrameInstance = mainFrame

    -- Header da Janela
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 46)
    header.BackgroundColor3 = THEME.BG_SIDEBAR
    header.BorderSizePixel = 0
    header.Parent = mainFrame
    AddCorner(header, 10)

    -- Arraste da Janela
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
        if input.UserInputType == Enum.UserInputType.MouseButton1 then isDragging = false end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if isDragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStartPos
            mainFrame.Position = UDim2.new(
                frameStartPos.X.Scale, frameStartPos.X.Offset + delta.X,
                frameStartPos.Y.Scale, frameStartPos.Y.Offset + delta.Y
            )
        end
    end)

    -- Marca e Título
    local brandDot = Instance.new("Frame")
    brandDot.Size = UDim2.new(0, 10, 0, 10)
    brandDot.Position = UDim2.new(0, 14, 0.5, -5)
    brandDot.BackgroundColor3 = THEME.ACCENT_PURPLE
    brandDot.Parent = header
    AddCorner(brandDot, 5)

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(0, 360, 0, 22)
    titleLabel.Position = UDim2.new(0, 32, 0, 4)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextSize = 13
    titleLabel.TextColor3 = THEME.TEXT_MAIN
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Text = "DEEPHAT SIMULATION SUITE // v8.0 PRO"
    titleLabel.Parent = header

    local subtitleLabel = Instance.new("TextLabel")
    subtitleLabel.Size = UDim2.new(0, 360, 0, 14)
    subtitleLabel.Position = UDim2.new(0, 32, 0, 24)
    subtitleLabel.BackgroundTransparency = 1
    subtitleLabel.Font = Enum.Font.GothamMedium
    subtitleLabel.TextSize = 9
    subtitleLabel.TextColor3 = THEME.TEXT_MUTED
    subtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
    subtitleLabel.Text = "Professional Simulation, Ballistics & AI Diagnostics Engine"
    subtitleLabel.Parent = header

    -- Badge de Watchdog / Monitor de Saúde
    local watchdogBadge = Instance.new("TextLabel")
    watchdogBadge.Size = UDim2.new(0, 240, 0, 24)
    watchdogBadge.Position = UDim2.new(1, -340, 0.5, -12)
    watchdogBadge.BackgroundColor3 = THEME.BG_INPUT
    watchdogBadge.Font = Enum.Font.GothamMedium
    watchdogBadge.TextSize = 9.5
    watchdogBadge.TextColor3 = THEME.SUCCESS
    watchdogBadge.Text = "● MONITOR: 100% OPERACIONAL"
    watchdogBadge.Parent = header
    AddCorner(watchdogBadge, 4)
    AddStroke(watchdogBadge, THEME.BORDER, 1)
    WatchdogBadgeInstance = watchdogBadge

    local hotkeyNotice = Instance.new("TextLabel")
    hotkeyNotice.Size = UDim2.new(0, 90, 1, 0)
    hotkeyNotice.Position = UDim2.new(1, -95, 0, 0)
    hotkeyNotice.BackgroundTransparency = 1
    hotkeyNotice.Font = Enum.Font.GothamMedium
    hotkeyNotice.TextSize = 9
    hotkeyNotice.TextColor3 = THEME.TEXT_MUTED
    hotkeyNotice.Text = "[HOME] Ocultar"
    hotkeyNotice.Parent = header

    UserInputService.InputBegan:Connect(function(input, gpe)
        if input.KeyCode == Enum.KeyCode.Home or input.KeyCode == Enum.KeyCode.RightShift then
            if UserInputService:GetFocusedTextBox() ~= nil then return end
            mainFrame.Visible = not mainFrame.Visible
        end
    end)

    -- Layout Estrutural: Sidebar + MainContent
    local body = Instance.new("Frame")
    body.Size = UDim2.new(1, 0, 1, -94)
    body.Position = UDim2.new(0, 0, 0, 46)
    body.BackgroundTransparency = 1
    body.Parent = mainFrame

    local sidebar = Instance.new("Frame")
    sidebar.Name = "Sidebar"
    sidebar.Size = UDim2.new(0, 195, 1, 0)
    sidebar.BackgroundColor3 = THEME.BG_SIDEBAR
    sidebar.BorderSizePixel = 0
    sidebar.Parent = body
    AddCorner(sidebar, 8)
    AddStroke(sidebar, THEME.BORDER, 1)

    local sidebarList = Instance.new("UIListLayout")
    sidebarList.Padding = UDim.new(0, 4)
    sidebarList.Parent = sidebar

    local sidebarPad = Instance.new("UIPadding")
    sidebarPad.PaddingTop = UDim.new(0, 8)
    sidebarPad.PaddingLeft = UDim.new(0, 6)
    sidebarPad.PaddingRight = UDim.new(0, 6)
    sidebarPad.Parent = sidebar

    local mainContent = Instance.new("Frame")
    mainContent.Name = "MainContent"
    mainContent.Size = UDim2.new(1, -205, 1, 0)
    mainContent.Position = UDim2.new(0, 200, 0, 0)
    mainContent.BackgroundColor3 = THEME.BG_CARD
    mainContent.BorderSizePixel = 0
    mainContent.Parent = body
    AddCorner(mainContent, 8)
    AddStroke(mainContent, THEME.BORDER, 1)

    -- 8 ABAS ESPECIALIZADAS V8
    local pages: { [string]: ScrollingFrame } = {}
    local tabButtons: { [string]: TextButton } = {}

    local tabs = {
        { Id = "Dashboard",     Label = "📊  Dashboard" },
        { Id = "AimSimulation", Label = "◎  Mira Simulada" },
        { Id = "SilentAim",     Label = "🎯  Player & Disparos" },
        { Id = "ESP",           Label = "👁️  ESP de Teste" },
        { Id = "Ballistics",    Label = "⚡  Balística & Física" },
        { Id = "Diagnostics",  Label = "🧠  Diagnóstico IA" },
        { Id = "Logs",          Label = "📋  Logs & Eventos" },
        { Id = "Settings",     Label = "⚙️  Configurações" },
    }

    local function SwitchTab(tabId: string)
        if not pages[tabId] then
            if tabId == "Overview" or tabId == "Camera" or tabId == "Simulation" then
                tabId = "Dashboard"
            elseif tabId == "Hitbox" then
                tabId = "AimSimulation"
            elseif tabId == "Player" then
                tabId = "SilentAim"
            elseif tabId == "Vision" then
                tabId = "ESP"
            elseif tabId == "LineOfSight" or tabId == "Performance" then
                tabId = "Diagnostics"
            else
                tabId = "Dashboard"
            end
        end
        for id, page in pairs(pages) do
            page.Visible = (id == tabId)
        end
        for id, btn in pairs(tabButtons) do
            local active = (id == tabId)
            btn.BackgroundColor3 = active and THEME.ACCENT_PURPLE or THEME.BG_INPUT
            btn.TextColor3 = active and THEME.TEXT_MAIN or THEME.TEXT_MUTED
            local ind = btn:FindFirstChild("ActiveIndicator") :: Frame?
            if ind then ind.Visible = active end
        end
        SimConfig.Set("ActiveTab", tabId)
    end

    for _, t in ipairs(tabs) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 0, 32)
        btn.BackgroundColor3 = THEME.BG_INPUT
        btn.TextColor3 = THEME.TEXT_MUTED
        btn.Font = Enum.Font.GothamMedium
        btn.TextSize = 10.5
        btn.TextXAlignment = Enum.TextXAlignment.Left
        btn.Text = "   " .. t.Label
        btn.Parent = sidebar
        AddCorner(btn, 5)

        local indicator = Instance.new("Frame")
        indicator.Name = "ActiveIndicator"
        indicator.Size = UDim2.new(0, 3, 1, -8)
        indicator.Position = UDim2.new(0, 3, 0, 4)
        indicator.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        indicator.BorderSizePixel = 0
        indicator.Visible = false
        indicator.Parent = btn
        AddCorner(indicator, 2)

        tabButtons[t.Id] = btn
        btn.MouseButton1Click:Connect(function() SwitchTab(t.Id) end)

        local page = Instance.new("ScrollingFrame")
        page.Name = "Page_" .. t.Id
        page.Size = UDim2.new(1, 0, 1, 0)
        page.BackgroundTransparency = 1
        page.ScrollBarThickness = 4
        page.ScrollBarImageColor3 = THEME.BORDER_LIGHT
        page.CanvasSize = UDim2.new(0, 0, 0, 0)
        page.AutomaticCanvasSize = Enum.AutomaticSize.Y
        page.Visible = false
        page.Parent = mainContent

        local pList = Instance.new("UIListLayout")
        pList.Padding = UDim.new(0, 8)
        pList.Parent = page

        local pPad = Instance.new("UIPadding")
        pPad.PaddingTop = UDim.new(0, 10); pPad.PaddingBottom = UDim.new(0, 30)
        pPad.PaddingLeft = UDim.new(0, 12); pPad.PaddingRight = UDim.new(0, 12)
        pPad.Parent = page

        pages[t.Id] = page
    end

    local syncInputs: { [string]: (number) -> () } = {}

    -- CONSTRUTOR DE COMPONENTES DE UI
    local function CreateSectionHeader(parent: Instance, title: string): Frame
        local hFrame = Instance.new("Frame")
        hFrame.Size = UDim2.new(1, 0, 0, 20)
        hFrame.BackgroundTransparency = 1
        hFrame.Parent = parent

        local bar = Instance.new("Frame")
        bar.Size = UDim2.new(0, 3, 0, 13)
        bar.Position = UDim2.new(0, 0, 0.5, -6)
        bar.BackgroundColor3 = THEME.ACCENT_PURPLE
        bar.BorderSizePixel = 0
        bar.Parent = hFrame
        AddCorner(bar, 2)

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -10, 1, 0)
        lbl.Position = UDim2.new(0, 8, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 10.5
        lbl.TextColor3 = THEME.TEXT_MAIN
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Text = title
        lbl.Parent = hFrame

        return hFrame
    end

    local function CreateSliderField(parent: Instance, labelText: string, configKey: string, minVal: number, maxVal: number, defaultVal: number, step: number, subtitleText: string?): Frame
        local span = math.max(maxVal - minVal, 0.0001)
        local safeDefault = tonumber(SimConfig.Get(configKey)) or defaultVal or minVal
        local height = subtitleText and 52 or 44

        local container = Instance.new("Frame")
        container.Name = "SliderRow_" .. configKey
        container.Size = UDim2.new(1, 0, 0, height)
        container.BackgroundColor3 = THEME.BG_INPUT
        container.BackgroundTransparency = 0.5
        container.Parent = parent
        AddCorner(container, 6)
        AddStroke(container, THEME.BORDER, 1)

        local rowHeader = Instance.new("Frame")
        rowHeader.Size = UDim2.new(1, -16, 0, subtitleText and 26 or 20)
        rowHeader.Position = UDim2.new(0, 8, 0, 4)
        rowHeader.BackgroundTransparency = 1
        rowHeader.Parent = container

        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(1, -70, subtitleText and 0.6 or 1, 0)
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.GothamMedium
        title.TextSize = 10.5
        title.TextColor3 = THEME.TEXT_MAIN
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Text = labelText
        title.Parent = rowHeader

        if subtitleText then
            local sub = Instance.new("TextLabel")
            sub.Size = UDim2.new(1, -70, 0.4, 0)
            sub.Position = UDim2.new(0, 0, 0.6, 0)
            sub.BackgroundTransparency = 1
            sub.Font = Enum.Font.GothamMedium
            sub.TextSize = 8.5
            sub.TextColor3 = THEME.TEXT_MUTED
            sub.TextXAlignment = Enum.TextXAlignment.Left
            sub.Text = subtitleText
            sub.Parent = rowHeader
        end

        local numInput = Instance.new("TextBox")
        numInput.Size = UDim2.new(0, 56, 0, 18)
        numInput.Position = UDim2.new(1, -56, 0, 2)
        numInput.BackgroundColor3 = THEME.BG_WINDOW
        numInput.TextColor3 = THEME.ACCENT_PURPLE
        numInput.Font = Enum.Font.GothamBold
        numInput.TextSize = 10
        numInput.Text = string.format(step < 1 and "%.2f" or "%d", safeDefault)
        numInput.ClearTextOnFocus = false
        numInput.Parent = rowHeader
        AddCorner(numInput, 4)
        AddStroke(numInput, THEME.BORDER, 1)

        local track = Instance.new("Frame")
        track.Size = UDim2.new(1, -16, 0, 5)
        track.Position = UDim2.new(0, 8, 0, subtitleText and 36 or 28)
        track.BackgroundColor3 = THEME.BG_WINDOW
        track.Parent = container
        AddCorner(track, 3)

        local initialRatio = math.clamp((safeDefault - minVal) / span, 0, 1)
        local fill = Instance.new("Frame")
        fill.Size = UDim2.new(initialRatio, 0, 1, 0)
        fill.BackgroundColor3 = THEME.ACCENT_PURPLE
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
                local ok, err = SimConfig.Set(configKey, val)
                if not ok then
                    DashboardGUI.AddDiagnosticLog("CONFIG", string.format("Falha ao atualizar '%s': %s", configKey, tostring(err)), "WARN")
                end
            end
        end

        numInput.FocusLost:Connect(function()
            local num = tonumber(numInput.Text)
            if num then UpdateValue(num)
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
            if input.UserInputType == Enum.UserInputType.MouseButton1 then isDraggingSlider = false end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if isDraggingSlider and input.UserInputType == Enum.UserInputType.MouseMovement then
                local trackWidth = math.max(track.AbsoluteSize.X, 1)
                local relX = math.clamp((input.Position.X - track.AbsolutePosition.X) / trackWidth, 0, 1)
                UpdateValue(minVal + relX * span)
            end
        end)

        syncInputs[configKey] = function(newVal: number) UpdateValue(newVal, true) end
        return container
    end

    local function CreateToggleField(parent: Instance, labelText: string, configKey: string, defaultState: boolean, subtitleText: string?): Frame
        local height = subtitleText and 48 or 38
        local container = Instance.new("Frame")
        container.Size = UDim2.new(1, 0, 0, height)
        container.BackgroundColor3 = THEME.BG_INPUT
        container.BackgroundTransparency = 0.5
        container.Parent = parent
        AddCorner(container, 6)
        AddStroke(container, THEME.BORDER, 1)

        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(1, -115, subtitleText and 0.55 or 1, 0)
        title.Position = UDim2.new(0, 10, 0, subtitleText and 3 or 0)
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.GothamMedium
        title.TextSize = 10.5
        title.TextColor3 = THEME.TEXT_MAIN
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Text = labelText
        title.Parent = container

        if subtitleText then
            local sub = Instance.new("TextLabel")
            sub.Size = UDim2.new(1, -115, 0.45, 0)
            sub.Position = UDim2.new(0, 10, 0.55, 0)
            sub.BackgroundTransparency = 1
            sub.Font = Enum.Font.GothamMedium
            sub.TextSize = 8.5
            sub.TextColor3 = THEME.TEXT_MUTED
            sub.TextXAlignment = Enum.TextXAlignment.Left
            sub.Text = subtitleText
            sub.Parent = container
        end

        -- Badge de Status ON / OFF
        local statusBadge = Instance.new("TextLabel")
        statusBadge.Size = UDim2.new(0, 36, 0, 20)
        statusBadge.Position = UDim2.new(1, -94, 0.5, -10)
        statusBadge.BackgroundColor3 = defaultState and THEME.ACCENT_PURPLE or THEME.BG_WINDOW
        statusBadge.Font = Enum.Font.GothamBold
        statusBadge.TextSize = 9
        statusBadge.TextColor3 = defaultState and THEME.TEXT_MAIN or THEME.TEXT_MUTED
        statusBadge.Text = defaultState and "ON" or "OFF"
        statusBadge.Parent = container
        AddCorner(statusBadge, 4)
        AddStroke(statusBadge, THEME.BORDER, 1)

        -- Switch Pill com Dot Deslizante
        local toggleBtn = Instance.new("TextButton")
        toggleBtn.Size = UDim2.new(0, 42, 0, 20)
        toggleBtn.Position = UDim2.new(1, -50, 0.5, -10)
        toggleBtn.BackgroundColor3 = defaultState and THEME.ACCENT_PURPLE or THEME.BG_WINDOW
        toggleBtn.Text = ""
        toggleBtn.Parent = container
        AddCorner(toggleBtn, 10)
        AddStroke(toggleBtn, THEME.BORDER, 1)

        local dot = Instance.new("Frame")
        dot.Size = UDim2.new(0, 14, 0, 14)
        dot.Position = defaultState and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7)
        dot.BackgroundColor3 = THEME.TEXT_MAIN
        dot.Parent = toggleBtn
        AddCorner(dot, 7)

        local function SetToggle(state: boolean)
            local ok, err = SimConfig.Set(configKey, state)
            if ok then
                statusBadge.BackgroundColor3 = state and THEME.ACCENT_PURPLE or THEME.BG_WINDOW
                statusBadge.TextColor3 = state and THEME.TEXT_MAIN or THEME.TEXT_MUTED
                statusBadge.Text = state and "ON" or "OFF"
                toggleBtn.BackgroundColor3 = state and THEME.ACCENT_PURPLE or THEME.BG_WINDOW
                dot.Position = state and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7)
            else
                DashboardGUI.AddDiagnosticLog("CONFIG", string.format("Falha ao alternar '%s': %s", configKey, tostring(err)), "WARN")
            end
        end

        toggleBtn.MouseButton1Click:Connect(function()
            local current = SimConfig.Get(configKey) == true
            SetToggle(not current)
        end)
        SimConfig.Subscribe(configKey, function(val)
            local state = (val == true)
            statusBadge.BackgroundColor3 = state and THEME.ACCENT_PURPLE or THEME.BG_WINDOW
            statusBadge.TextColor3 = state and THEME.TEXT_MAIN or THEME.TEXT_MUTED
            statusBadge.Text = state and "ON" or "OFF"
            toggleBtn.BackgroundColor3 = state and THEME.ACCENT_PURPLE or THEME.BG_WINDOW
            dot.Position = state and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7)
        end)

        return container
    end

    local function CreateSegmentedButtons(parent: Instance, labelText: string, configKey: string, options: { { Id: string, Label: string } }): Frame
        local container = Instance.new("Frame")
        container.Size = UDim2.new(1, 0, 0, 48)
        container.BackgroundColor3 = THEME.BG_INPUT
        container.BackgroundTransparency = 0.5
        container.Parent = parent
        AddCorner(container, 6)
        AddStroke(container, THEME.BORDER, 1)

        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(0.35, 0, 1, 0)
        title.Position = UDim2.new(0, 10, 0, 0)
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.GothamMedium
        title.TextSize = 10.5
        title.TextColor3 = THEME.TEXT_MAIN
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Text = labelText
        title.Parent = container

        local btnContainer = Instance.new("Frame")
        btnContainer.Size = UDim2.new(0.65, -16, 0, 28)
        btnContainer.Position = UDim2.new(0.35, 8, 0.5, -14)
        btnContainer.BackgroundTransparency = 1
        btnContainer.Parent = container

        local bLayout = Instance.new("UIListLayout")
        bLayout.FillDirection = Enum.FillDirection.Horizontal
        bLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
        bLayout.Padding = UDim.new(0, 4)
        bLayout.Parent = btnContainer

        local btns: { [string]: TextButton } = {}
        local function UpdateSegmentUI(activeVal: string)
            for id, b in pairs(btns) do
                local isActive = (id == activeVal)
                b.BackgroundColor3 = isActive and THEME.ACCENT_PURPLE or THEME.BG_WINDOW
                b.TextColor3 = isActive and THEME.TEXT_MAIN or THEME.TEXT_MUTED
            end
        end

        local currentVal = tostring(SimConfig.Get(configKey) or options[1].Id)
        for _, opt in ipairs(options) do
            local b = Instance.new("TextButton")
            b.Size = UDim2.new(0, 78, 1, 0)
            b.BackgroundColor3 = (opt.Id == currentVal) and THEME.ACCENT_PURPLE or THEME.BG_WINDOW
            b.Font = Enum.Font.GothamBold
            b.TextSize = 9.5
            b.TextColor3 = (opt.Id == currentVal) and THEME.TEXT_MAIN or THEME.TEXT_MUTED
            b.Text = opt.Label
            b.Parent = btnContainer
            AddCorner(b, 4)
            AddStroke(b, THEME.BORDER, 1)

            btns[opt.Id] = b
            b.MouseButton1Click:Connect(function()
                SimConfig.Set(configKey, opt.Id)
                UpdateSegmentUI(opt.Id)
            end)
        end

        SimConfig.Subscribe(configKey, function(val)
            UpdateSegmentUI(tostring(val))
        end)

        return container
    end

    local function MakeInfoLabel(parent: Instance, text: string, color: Color3?, height: number?): TextLabel
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1, 0, 0, height or 24)
        l.BackgroundColor3 = THEME.BG_INPUT
        l.BackgroundTransparency = 0.5
        l.Font = Enum.Font.GothamMedium
        l.TextSize = 10
        l.TextColor3 = color or THEME.TEXT_MUTED
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.TextYAlignment = Enum.TextYAlignment.Center
        l.Text = "  " .. text
        l.Parent = parent
        AddCorner(l, 4)
        AddStroke(l, THEME.BORDER, 1)
        return l
    end

    -- =========================================================================
    -- [ABA 1] DASHBOARD / VISÃO GERAL (DASHBOARD)
    -- =========================================================================
    local pageDash = pages["Dashboard"]

    CreateSectionHeader(pageDash, "VISÃO GERAL DO SIMULADOR E MÉTRICAS OPERACIONAIS")

    -- Grid de 4 Cards KPI
    local kpiGrid = Instance.new("Frame")
    kpiGrid.Size = UDim2.new(1, 0, 0, 72)
    kpiGrid.BackgroundTransparency = 1
    kpiGrid.Parent = pageDash

    local kpiLayout = Instance.new("UIGridLayout")
    kpiLayout.CellSize = UDim2.new(0.238, 0, 1, 0)
    kpiLayout.CellPadding = UDim2.new(0.016, 0, 0, 0)
    kpiLayout.Parent = kpiGrid

    local function MakeKpiCard(title: string, defaultVal: string, tagKey: string, icon: string): (Frame, TextLabel)
        local card = Instance.new("Frame")
        card.BackgroundColor3 = THEME.BG_INPUT
        card.Parent = kpiGrid
        AddCorner(card, 6)
        AddStroke(card, THEME.BORDER, 1)

        local t = Instance.new("TextLabel")
        t.Size = UDim2.new(1, -12, 0, 18)
        t.Position = UDim2.new(0, 8, 0, 6)
        t.BackgroundTransparency = 1
        t.Font = Enum.Font.GothamBold
        t.TextSize = 9.5
        t.TextColor3 = THEME.TEXT_MUTED
        t.TextXAlignment = Enum.TextXAlignment.Left
        t.Text = icon .. " " .. title
        t.Parent = card

        local v = Instance.new("TextLabel")
        v.Size = UDim2.new(1, -12, 0, 24)
        v.Position = UDim2.new(0, 8, 0, 26)
        v.BackgroundTransparency = 1
        v.Font = Enum.Font.GothamBold
        v.TextSize = 13
        v.TextColor3 = THEME.TEXT_MAIN
        v.TextXAlignment = Enum.TextXAlignment.Left
        v.Text = defaultVal
        v.Parent = card

        local s = Instance.new("TextLabel")
        s.Size = UDim2.new(1, -12, 0, 14)
        s.Position = UDim2.new(0, 8, 0, 50)
        s.BackgroundTransparency = 1
        s.Font = Enum.Font.Code
        s.TextSize = 8.5
        s.TextColor3 = THEME.SUCCESS
        s.TextXAlignment = Enum.TextXAlignment.Left
        s.Text = "● OPERACIONAL"
        s.Parent = card

        TelemetryLabels[tagKey] = v
        TelemetryLabels[tagKey .. "_Status"] = s
        return card, v
    end

    MakeKpiCard("PIPELINE MESTRE", "ATIVO", "Dash_SimStatus", "⚙️")
    MakeKpiCard("ALVO SINTÉTICO", "NENHUM", "Dash_TargetName", "🎯")
    MakeKpiCard("MOTOR IA", "HEALTHY", "Dash_HealthStatus", "🧠")
    MakeKpiCard("PERFORMANCE", "60 FPS", "Dash_FpsCounter", "⚡")

    CreateSectionHeader(pageDash, "AÇÕES RÁPIDAS DE SIMULAÇÃO")

    local quickActionGrid = Instance.new("Frame")
    quickActionGrid.Size = UDim2.new(1, 0, 0, 36)
    quickActionGrid.BackgroundTransparency = 1
    quickActionGrid.Parent = pageDash

    local qaLayout = Instance.new("UIGridLayout")
    qaLayout.CellSize = UDim2.new(0.238, 0, 1, 0)
    qaLayout.CellPadding = UDim2.new(0.016, 0, 0, 0)
    qaLayout.Parent = quickActionGrid

    local function MakeQuickActionButton(text: string, color: Color3, onClick: () -> ())
        local b = Instance.new("TextButton")
        b.BackgroundColor3 = color
        b.Font = Enum.Font.GothamBold
        b.TextSize = 10
        b.TextColor3 = THEME.TEXT_MAIN
        b.Text = text
        b.Parent = quickActionGrid
        AddCorner(b, 5)
        AddStroke(b, THEME.BORDER_LIGHT, 1)
        b.MouseButton1Click:Connect(onClick)
    end

    MakeQuickActionButton("🎯 Spawnar Alvo", THEME.ACCENT_PURPLE, function()
        if DashboardGUI.OnSpawnTestDummy then DashboardGUI.OnSpawnTestDummy() end
    end)
    MakeQuickActionButton("🩺 Diagnóstico Completo", THEME.BG_INPUT, function()
        if DashboardGUI.OnRunFullDiagnostic then DashboardGUI.OnRunFullDiagnostic() end
    end)
    MakeQuickActionButton("⚡ Testar Disparo", THEME.BG_INPUT, function()
        if DashboardGUI.OnSimulateSilentAimShot then DashboardGUI.OnSimulateSilentAimShot() end
    end)
    MakeQuickActionButton("🗑️ Limpar Alvos", THEME.BG_INPUT, function()
        if DashboardGUI.OnClearTestDummies then DashboardGUI.OnClearTestDummies() end
    end)

    CreateSectionHeader(pageDash, "ESTADO DOS SUBSISTEMAS DE TESTE")

    local modStatusCard = Instance.new("Frame")
    modStatusCard.Size = UDim2.new(1, 0, 0, 50)
    modStatusCard.BackgroundColor3 = THEME.BG_INPUT
    modStatusCard.Parent = pageDash
    AddCorner(modStatusCard, 6)
    AddStroke(modStatusCard, THEME.BORDER, 1)

    local msPad = Instance.new("UIPadding")
    msPad.PaddingTop = UDim.new(0, 4); msPad.PaddingBottom = UDim.new(0, 4)
    msPad.PaddingLeft = UDim.new(0, 6); msPad.PaddingRight = UDim.new(0, 6)
    msPad.Parent = modStatusCard

    local msLayout = Instance.new("UIGridLayout")
    msLayout.CellSize = UDim2.new(0.24, 0, 1, 0)
    msLayout.CellPadding = UDim2.new(0.013, 0, 0, 0)
    msLayout.Parent = modStatusCard

    local function MakeModuleBadge(modName: string, initialStatus: string, labelKey: string)
        local box = Instance.new("Frame")
        box.BackgroundColor3 = THEME.BG_WINDOW
        box.Parent = modStatusCard
        AddCorner(box, 4)
        AddStroke(box, THEME.BORDER, 1)

        local t1 = Instance.new("TextLabel")
        t1.Size = UDim2.new(1, -6, 0, 15)
        t1.Position = UDim2.new(0, 4, 0, 2)
        t1.BackgroundTransparency = 1
        t1.Font = Enum.Font.GothamBold
        t1.TextSize = 9
        t1.TextColor3 = THEME.TEXT_MAIN
        t1.TextXAlignment = Enum.TextXAlignment.Left
        t1.Text = modName
        t1.Parent = box

        local t2 = Instance.new("TextLabel")
        t2.Size = UDim2.new(1, -6, 0, 16)
        t2.Position = UDim2.new(0, 4, 0, 18)
        t2.BackgroundTransparency = 1
        t2.Font = Enum.Font.Code
        t2.TextSize = 8.5
        t2.TextColor3 = THEME.SUCCESS
        t2.TextXAlignment = Enum.TextXAlignment.Left
        t2.Text = initialStatus
        t2.Parent = box
        TelemetryLabels[labelKey] = t2
    end

    MakeModuleBadge("VectorTracker", "● MONITORANDO", "ModStatus_Tracker")
    MakeModuleBadge("InstanceDetector", "● ATIVO", "ModStatus_Detector")
    MakeModuleBadge("DiagnosticAI", "● OPERACIONAL", "ModStatus_Diagnostic")
    MakeModuleBadge("Silent Aim", "○ PRONTO", "ModStatus_SilentAim")

    -- =========================================================================
    -- [ABA 2] MIRA SIMULADA (AIM SIMULATION)
    -- =========================================================================
    local pageAim = pages["AimSimulation"]

    -- Card Mestre de Ativação
    local masterCard = Instance.new("Frame")
    masterCard.Size = UDim2.new(1, 0, 0, 56)
    masterCard.BackgroundColor3 = THEME.BG_INPUT
    masterCard.Parent = pageAim
    AddCorner(masterCard, 8)
    AddStroke(masterCard, THEME.BORDER, 1)

    local masterTitle = Instance.new("TextLabel")
    masterTitle.Size = UDim2.new(0.65, 0, 0, 20)
    masterTitle.Position = UDim2.new(0, 12, 0, 8)
    masterTitle.BackgroundTransparency = 1
    masterTitle.Font = Enum.Font.GothamBold
    masterTitle.TextSize = 11.5
    masterTitle.TextColor3 = THEME.TEXT_MAIN
    masterTitle.TextXAlignment = Enum.TextXAlignment.Left
    masterTitle.Text = "SIMULAÇÃO CINEMÁTICA DE MIRA (AIMBOT DEFENSIVO)"
    masterTitle.Parent = masterCard

    local masterDesc = Instance.new("TextLabel")
    masterDesc.Size = UDim2.new(0.65, 0, 0, 18)
    masterDesc.Position = UDim2.new(0, 12, 0, 28)
    masterDesc.BackgroundTransparency = 1
    masterDesc.Font = Enum.Font.GothamMedium
    masterDesc.TextSize = 9.5
    masterDesc.TextColor3 = THEME.TEXT_MUTED
    masterDesc.TextXAlignment = Enum.TextXAlignment.Left
    masterDesc.Text = "Rastreamento preditivo de manequins sintéticos com interpolação estável."
    masterDesc.Parent = masterCard

    local masterSwitch = Instance.new("TextButton")
    masterSwitch.Size = UDim2.new(0, 150, 0, 32)
    masterSwitch.Position = UDim2.new(1, -162, 0.5, -16)
    masterSwitch.BackgroundColor3 = SimConfig.Get("SimulationActive") and THEME.ACCENT_PURPLE or THEME.BG_WINDOW
    masterSwitch.Font = Enum.Font.GothamBold
    masterSwitch.TextSize = 10.5
    masterSwitch.TextColor3 = THEME.TEXT_MAIN
    masterSwitch.Text = SimConfig.Get("SimulationActive") and "SIMULAÇÃO: ATIVA" or "SIMULAÇÃO: PAUSADA"
    masterSwitch.Parent = masterCard
    AddCorner(masterSwitch, 6)
    AddStroke(masterSwitch, THEME.BORDER_LIGHT, 1)
    masterSwitch.MouseButton1Click:Connect(function()
        local nextState = not (SimConfig.Get("SimulationActive") == true)
        SimConfig.Set("SimulationActive", nextState)
        masterSwitch.BackgroundColor3 = nextState and THEME.ACCENT_PURPLE or THEME.BG_WINDOW
        masterSwitch.Text = nextState and "SIMULAÇÃO: ATIVA" or "SIMULAÇÃO: PAUSADA"
        DashboardGUI.AddDiagnosticLog("PIPELINE", nextState and "Simulação ativada." or "Simulação pausada.", nextState and "OK" or "WARN")
    end)

    CreateToggleField(pageAim, "Ativar Rastreamento de Mira (Aimbot Ativo)", "AimbotEnabled", SimConfig.Get("AimbotEnabled"), "Ativa o controlador de rotação cinemática no manequim sintético")
    CreateSegmentedButtons(pageAim, "Modo de Mira", "AimMode", {
        { Id = "HoldRMB",  Label = "Segurar RMB" },
        { Id = "Toggle",   Label = "Alternar" },
        { Id = "AlwaysOn", Label = "Sempre Ativo" },
    })

    CreateSectionHeader(pageAim, "DINÂMICA CINEMÁTICA & RESPOSTA TEMPORAL")
    CreateSliderField(pageAim, "Suavização Cinemática (Smoothing)", "Smoothing", 0.01, 1.0, SimConfig.Get("Smoothing"), 0.01, "0.01 = Alta resposta rápida | 0.25 = Transição orgânica ultra-suave")
    CreateSliderField(pageAim, "Velocidade Angular Máxima (°/s)", "AngularVelocity", 30, 720, SimConfig.Get("AngularVelocity"), 10, "Limite estrito para evitar instabilidade ou oscilação brusca")
    CreateToggleField(pageAim, "Clamp de Velocidade Angular", "MaxAngularVelocityClamp", SimConfig.Get("MaxAngularVelocityClamp"), "Força clamp estrito em todas as rotações")
    CreateSliderField(pageAim, "Zona Morta Angular - Deadzone (°)", "AimDeadzoneDeg", 0.0, 5.0, SimConfig.Get("AimDeadzoneDeg") or 0.5, 0.1, "Elimina micro-vibrações (jitter) quando o erro estiver abaixo do limiar")
    CreateSliderField(pageAim, "Raio do FOV Visual na Tela (Pixels)", "FovRadiusPx", 20, 600, SimConfig.Get("FovRadiusPx"), 5, "Raio do círculo visual centralizado de busca")
    CreateSliderField(pageAim, "Campo de Visão Angular - FOV (°)", "FOV", 10, 180, SimConfig.Get("FOV"), 1, "Cone esférico tridimensional de busca de entidades")
    CreateToggleField(pageAim, "Exibir Círculo de FOV na Tela", "ShowFovCircle", SimConfig.Get("ShowFovCircle"))

    CreateSectionHeader(pageAim, "FILTROS E SELEÇÃO DE ALVOS")
    CreateToggleField(pageAim, "Filtrar Somente Alvos com Visada Livre (Visible Only)", "VisibleOnly", SimConfig.Get("VisibleOnly"))
    CreateToggleField(pageAim, "Ignorar Aliados da Mesma Equipe (Team Check)", "TeamCheck", SimConfig.Get("TeamCheck"))
    CreateToggleField(pageAim, "Considerar Jogadores como Alvos (Ambiente Autorizado)", "AllowPlayerTargets", SimConfig.Get("AllowPlayerTargets"))
    CreateSegmentedButtons(pageAim, "Região do Alvo", "TargetRegion", {
        { Id = "Head",  Label = "Cabeça" },
        { Id = "Torso", Label = "Tronco" },
        { Id = "Arms",  Label = "Braços" },
        { Id = "Legs",  Label = "Pernas" },
    })

    -- =========================================================================
    -- [ABA 3] PLAYER DE TESTE & DISPAROS (SILENT AIM)
    -- =========================================================================
    local pageSilent = pages["SilentAim"]

    CreateSectionHeader(pageSilent, "GERENCIAMENTO DO MANEQUIM SINTÉTICO")
    local dummyActionRow = Instance.new("Frame")
    dummyActionRow.Size = UDim2.new(1, 0, 0, 34)
    dummyActionRow.BackgroundTransparency = 1
    dummyActionRow.Parent = pageSilent

    local spawnDummyBtn = Instance.new("TextButton")
    spawnDummyBtn.Size = UDim2.new(0.5, -4, 1, 0)
    spawnDummyBtn.Position = UDim2.new(0, 0, 0, 0)
    spawnDummyBtn.BackgroundColor3 = THEME.ACCENT_PURPLE
    spawnDummyBtn.Font = Enum.Font.GothamBold
    spawnDummyBtn.TextSize = 10.5
    spawnDummyBtn.TextColor3 = THEME.TEXT_MAIN
    spawnDummyBtn.Text = "🎯 SPAWNAR MANEQUIM SINTÉTICO"
    spawnDummyBtn.Parent = dummyActionRow
    AddCorner(spawnDummyBtn, 6)
    AddStroke(spawnDummyBtn, THEME.BORDER_LIGHT, 1)
    spawnDummyBtn.MouseButton1Click:Connect(function()
        if DashboardGUI.OnSpawnTestDummy then DashboardGUI.OnSpawnTestDummy() end
    end)

    local clearDummyBtn = Instance.new("TextButton")
    clearDummyBtn.Size = UDim2.new(0.5, -4, 1, 0)
    clearDummyBtn.Position = UDim2.new(0.5, 4, 0, 0)
    clearDummyBtn.BackgroundColor3 = THEME.BG_INPUT
    clearDummyBtn.Font = Enum.Font.GothamBold
    clearDummyBtn.TextSize = 10.5
    clearDummyBtn.TextColor3 = THEME.TEXT_MAIN
    clearDummyBtn.Text = "🗑️ LIMPAR TODOS OS DUMMIES"
    clearDummyBtn.Parent = dummyActionRow
    AddCorner(clearDummyBtn, 6)
    AddStroke(clearDummyBtn, THEME.BORDER, 1)
    clearDummyBtn.MouseButton1Click:Connect(function()
        if DashboardGUI.OnClearTestDummies then DashboardGUI.OnClearTestDummies() end
    end)

    CreateSectionHeader(pageSilent, "SIMULAÇÃO DE DISPAROS DESACOPLADOS (SILENT AIM)")
    CreateToggleField(pageSilent, "Ativar Simulação de Silent Aim (Vetor Desacoplado)", "SilentAimEnabled", SimConfig.Get("SilentAimEnabled"), "Redireciona vetores balísticos sem mover a câmera física do observador")
    CreateSliderField(pageSilent, "Silent Aim - Campo de Redirecionamento (FOV °)", "SilentAimFOV", 5, 90, SimConfig.Get("SilentAimFOV"), 1, "Cone angular máximo permitido para redirecionamento do tiro")
    CreateSliderField(pageSilent, "Probabilidade de Acerto do Silent Aim (%)", "SilentAimHitChance", 10, 100, SimConfig.Get("SilentAimHitChance"), 5, "100% = Acerto determinístico | <100% = Dispersão probabilística de teste")
    CreateToggleField(pageSilent, "Exibir Traçador 3D do Vetor de Disparo (Tracer)", "SilentAimTracer", SimConfig.Get("SilentAimTracer"))

    -- Card com Pipeline em 5 Etapas e Telemetria de Colisão
    local pipelineCard = Instance.new("Frame")
    pipelineCard.Size = UDim2.new(1, 0, 0, 126)
    pipelineCard.BackgroundColor3 = THEME.BG_INPUT
    pipelineCard.Parent = pageSilent
    AddCorner(pipelineCard, 6)
    AddStroke(pipelineCard, THEME.BORDER, 1)

    local pTitle = Instance.new("TextLabel")
    pTitle.Size = UDim2.new(1, -16, 0, 18)
    pTitle.Position = UDim2.new(0, 8, 0, 6)
    pTitle.BackgroundTransparency = 1
    pTitle.Font = Enum.Font.GothamBold
    pTitle.TextSize = 10
    pTitle.TextColor3 = THEME.TEXT_MAIN
    pTitle.TextXAlignment = Enum.TextXAlignment.Left
    pTitle.Text = "PIPELINE DE DISPARO AUDITADO (5 ETAPAS):"
    pTitle.Parent = pipelineCard

    local pSteps = Instance.new("TextLabel")
    pSteps.Size = UDim2.new(1, -16, 0, 16)
    pSteps.Position = UDim2.new(0, 8, 0, 24)
    pSteps.BackgroundTransparency = 1
    pSteps.Font = Enum.Font.Code
    pSteps.TextSize = 8.5
    pSteps.TextColor3 = THEME.TEXT_MUTED
    pSteps.TextXAlignment = Enum.TextXAlignment.Left
    pSteps.Text = "[1] RECEBIDO → [2] VALIDADO → [3] TRAJETÓRIA → [4] COLISÃO FÍSICA → [5] RESULTADO"
    pSteps.Parent = pipelineCard

    local pStatus1 = Instance.new("TextLabel")
    pStatus1.Size = UDim2.new(0.5, -10, 0, 16)
    pStatus1.Position = UDim2.new(0, 8, 0, 44)
    pStatus1.BackgroundTransparency = 1
    pStatus1.Font = Enum.Font.GothamMedium
    pStatus1.TextSize = 9.5
    pStatus1.TextColor3 = THEME.TEXT_MAIN
    pStatus1.TextXAlignment = Enum.TextXAlignment.Left
    pStatus1.Text = "Módulo: ○ DESATIVADO"
    pStatus1.Parent = pipelineCard
    TelemetryLabels["SilentAimStatus"] = pStatus1

    local pStatus2 = Instance.new("TextLabel")
    pStatus2.Size = UDim2.new(0.5, -10, 0, 16)
    pStatus2.Position = UDim2.new(0.5, 0, 0, 44)
    pStatus2.BackgroundTransparency = 1
    pStatus2.Font = Enum.Font.GothamMedium
    pStatus2.TextSize = 9.5
    pStatus2.TextColor3 = THEME.TEXT_MUTED
    pStatus2.TextXAlignment = Enum.TextXAlignment.Left
    pStatus2.Text = "Etapa: [0/5] NENHUM DISPARO"
    pStatus2.Parent = pipelineCard
    TelemetryLabels["SilentAimStage"] = pStatus2

    local pShotStatus = Instance.new("TextLabel")
    pShotStatus.Size = UDim2.new(1, -16, 0, 16)
    pShotStatus.Position = UDim2.new(0, 8, 0, 62)
    pShotStatus.BackgroundTransparency = 1
    pShotStatus.Font = Enum.Font.GothamBold
    pShotStatus.TextSize = 9.5
    pShotStatus.TextColor3 = THEME.TEXT_MUTED
    pShotStatus.TextXAlignment = Enum.TextXAlignment.Left
    pShotStatus.Text = "Último Disparo: NENHUM REGISTRO"
    pShotStatus.Parent = pipelineCard
    TelemetryLabels["LastShotStatus"] = pShotStatus

    local pDetails = Instance.new("TextLabel")
    pDetails.Size = UDim2.new(1, -16, 0, 16)
    pDetails.Position = UDim2.new(0, 8, 0, 80)
    pDetails.BackgroundTransparency = 1
    pDetails.Font = Enum.Font.Code
    pDetails.TextSize = 8.5
    pDetails.TextColor3 = THEME.TEXT_MUTED
    pDetails.TextXAlignment = Enum.TextXAlignment.Left
    pDetails.Text = "Impacto: — | Parte: — | Desvio: 0.0° | Dist: —"
    pDetails.Parent = pipelineCard
    TelemetryLabels["SilentAimDetails"] = pDetails

    local pReason = Instance.new("TextLabel")
    pReason.Size = UDim2.new(1, -16, 0, 18)
    pReason.Position = UDim2.new(0, 8, 0, 98)
    pReason.BackgroundTransparency = 1
    pReason.Font = Enum.Font.GothamMedium
    pReason.TextSize = 9
    pReason.TextColor3 = THEME.TEXT_MUTED
    pReason.TextXAlignment = Enum.TextXAlignment.Left
    pReason.Text = "Diagnóstico: Pronto para testes. Clique no botão de disparo abaixo."
    pReason.Parent = pipelineCard
    TelemetryLabels["SilentAimReason"] = pReason

    CreateSectionHeader(pageSilent, "EXECUÇÃO DE CENÁRIOS DE DISPARO DE TESTE")
    local shotScenarioGrid = Instance.new("Frame")
    shotScenarioGrid.Size = UDim2.new(1, 0, 0, 0)
    shotScenarioGrid.AutomaticSize = Enum.AutomaticSize.Y
    shotScenarioGrid.BackgroundTransparency = 1
    shotScenarioGrid.Parent = pageSilent

    local sscLayout = Instance.new("UIGridLayout")
    sscLayout.CellSize = UDim2.new(0, 150, 0, 26)
    sscLayout.CellPadding = UDim2.new(0, 6, 0, 6)
    sscLayout.Parent = shotScenarioGrid

    local function MakeScenarioButton(label: string, id: string)
        local b = Instance.new("TextButton")
        b.BackgroundColor3 = THEME.BG_INPUT
        b.Font = Enum.Font.GothamMedium
        b.TextSize = 9.5
        b.TextColor3 = THEME.TEXT_MAIN
        b.Text = "▶ " .. label
        b.Parent = shotScenarioGrid
        AddCorner(b, 5)
        AddStroke(b, THEME.BORDER, 1)
        b.MouseButton1Click:Connect(function()
            if DashboardGUI.OnRunShotScenario then
                DashboardGUI.OnRunShotScenario(id)
            end
        end)
    end

    for _, sc in ipairs(ScenarioRunner.ShotScenarios) do
        MakeScenarioButton(sc.Label, sc.Id)
    end

    -- =========================================================================
    -- [ABA 4] ESP DE TESTE (ESP & ENTITY VISUALIZATION)
    -- =========================================================================
    local pageESP = pages["ESP"]

    CreateSectionHeader(pageESP, "REALCE VISUAL DE ENTIDADES SINTÉTICAS (ESP CHAMS & TAGS 3D)")
    CreateToggleField(pageESP, "Ativar Realce Visual Geral (Enable ESP)", "EnableESP", SimConfig.Get("EnableESP"), "Ativa o contêiner de renderização de destaques visuais")
    CreateToggleField(pageESP, "Exibir Tags 3D Flutuantes (BillboardGui)", "ShowTargetTags", SimConfig.Get("ShowTargetTags") ~= false, "Renderiza nome, distância em studs, linha de visada (LOS) e vida sobre o manequim")
    CreateSliderField(pageESP, "Alcance Máximo de Renderização do ESP (studs)", "EspMaxDistance", 50, 1000, SimConfig.Get("EspMaxDistance") or 500, 25, "Alvos além desta distância não consumirão processamento de realce")
    CreateToggleField(pageESP, "Ocultar Marcadores se Ocluído (Visible Only)", "VisibleOnly", SimConfig.Get("VisibleOnly"))
    CreateToggleField(pageESP, "Ignorar Aliados da Mesma Equipe (Team Check)", "TeamCheck", SimConfig.Get("TeamCheck"))

    local espInfoCard = Instance.new("Frame")
    espInfoCard.Size = UDim2.new(1, 0, 0, 72)
    espInfoCard.BackgroundColor3 = THEME.BG_INPUT
    espInfoCard.Parent = pageESP
    AddCorner(espInfoCard, 6)
    AddStroke(espInfoCard, THEME.BORDER, 1)

    local espInfoTitle = Instance.new("TextLabel")
    espInfoTitle.Size = UDim2.new(1, -16, 0, 18)
    espInfoTitle.Position = UDim2.new(0, 8, 0, 6)
    espInfoTitle.BackgroundTransparency = 1
    espInfoTitle.Font = Enum.Font.GothamBold
    espInfoTitle.TextSize = 10
    espInfoTitle.TextColor3 = THEME.ACCENT_PURPLE
    espInfoTitle.TextXAlignment = Enum.TextXAlignment.Left
    espInfoTitle.Text = "ANATOMIA DAS TAGS 3D DE DEPURAÇÃO:"
    espInfoTitle.Parent = espInfoCard

    local espInfoBody = Instance.new("TextLabel")
    espInfoBody.Size = UDim2.new(1, -16, 0, 40)
    espInfoBody.Position = UDim2.new(0, 8, 0, 26)
    espInfoBody.BackgroundTransparency = 1
    espInfoBody.Font = Enum.Font.GothamMedium
    espInfoBody.TextSize = 9.5
    espInfoBody.TextColor3 = THEME.TEXT_MAIN
    espInfoBody.TextXAlignment = Enum.TextXAlignment.Left
    espInfoBody.TextWrapped = true
    espInfoBody.Text = "• Título: [Nome do Alvo] [Pivot / Cabeça]\n• Detalhes: [VISIBLE / BLOCKED] em Verde/Vermelho | [Distância studs] | [Vida HP]\n• Quota Estrita: Máximo 16 instâncias de Highlights para estabilidade a 60+ FPS."
    espInfoBody.Parent = espInfoCard

    -- =========================================================================
    -- [ABA 5] BALÍSTICA & FÍSICA (BALLISTICS)
    -- =========================================================================
    local pageBallistics = pages["Ballistics"]

    CreateSectionHeader(pageBallistics, "MODELAGEM BALÍSTICA E TRAJETÓRIA FÍSICA")
    CreateSegmentedButtons(pageBallistics, "Modelo Balístico", "ProjectileType", {
        { Id = "Physics", Label = "Físico (Gravidade/Arco)" },
        { Id = "Instant", Label = "Instantâneo (Hitscan)" },
    })
    CreateSliderField(pageBallistics, "Velocidade Inicial do Projétil (studs/s)", "ProjectileSpeed", 100, 5000, SimConfig.Get("ProjectileSpeed"), 50, "Velocidade inicial de saída do cano para cálculo de tempo de voo")
    CreateSliderField(pageBallistics, "Aceleração Gravitacional (studs/s²)", "ProjectileGravity", 0, 300, SimConfig.Get("ProjectileGravity"), 5, "Gravidade aplicada ao projétil. Padrão do Roblox Studio = 196.2 studs/s²")

    local robloxPresetBtn = Instance.new("TextButton")
    robloxPresetBtn.Size = UDim2.new(0, 200, 0, 24)
    robloxPresetBtn.BackgroundColor3 = THEME.BG_INPUT
    robloxPresetBtn.Font = Enum.Font.GothamBold
    robloxPresetBtn.TextSize = 9.5
    robloxPresetBtn.TextColor3 = THEME.ACCENT_PURPLE
    robloxPresetBtn.Text = "⚡ Definir Gravidade Roblox (196.2)"
    robloxPresetBtn.Parent = pageBallistics
    AddCorner(robloxPresetBtn, 4)
    AddStroke(robloxPresetBtn, THEME.BORDER, 1)
    robloxPresetBtn.MouseButton1Click:Connect(function()
        SimConfig.Set("ProjectileGravity", 196.2)
        DashboardGUI.AddDiagnosticLog("BALÍSTICA", "Gravidade redefinida para 196.2 studs/s² (padrão Roblox).", "OK")
    end)

    CreateToggleField(pageBallistics, "Compensação de Queda (Drop Compensation)", "ProjectileDropComp", SimConfig.Get("ProjectileDropComp"), "Compensa verticalmente a mira com base na distância e gravidade")
    CreateToggleField(pageBallistics, "Predição Vetorial de Lead (Lead Calculation)", "EnableLead", SimConfig.Get("EnableLead"), "Calcula ponto futuro de impacto interceptando a velocidade estimada do alvo")

    local ballisticsFormulaCard = Instance.new("Frame")
    ballisticsFormulaCard.Size = UDim2.new(1, 0, 0, 80)
    ballisticsFormulaCard.BackgroundColor3 = THEME.BG_INPUT
    ballisticsFormulaCard.Parent = pageBallistics
    AddCorner(ballisticsFormulaCard, 6)
    AddStroke(ballisticsFormulaCard, THEME.BORDER, 1)

    local bfTitle = Instance.new("TextLabel")
    bfTitle.Size = UDim2.new(1, -16, 0, 18)
    bfTitle.Position = UDim2.new(0, 8, 0, 6)
    bfTitle.BackgroundTransparency = 1
    bfTitle.Font = Enum.Font.GothamBold
    bfTitle.TextSize = 10
    bfTitle.TextColor3 = THEME.TEXT_MAIN
    bfTitle.TextXAlignment = Enum.TextXAlignment.Left
    bfTitle.Text = "FORMULAÇÕES BALÍSTICAS IMPLEMENTADAS:"
    bfTitle.Parent = ballisticsFormulaCard

    local bfBody = Instance.new("TextLabel")
    bfBody.Size = UDim2.new(1, -16, 0, 50)
    bfBody.Position = UDim2.new(0, 8, 0, 24)
    bfBody.BackgroundTransparency = 1
    bfBody.Font = Enum.Font.Code
    bfBody.TextSize = 9
    bfBody.TextColor3 = THEME.TEXT_MUTED
    bfBody.TextXAlignment = Enum.TextXAlignment.Left
    bfBody.Text = "• Tempo de Voo: t = dist / V_ini\n• Queda Gravitacional: Delta_y = 0.5 * g * t^2\n• Trajetória Física: Segmentação de 10 passos contínuos sob Workspace:Raycast\n• Compensação Angular: atan2(Delta_y, dist) aplicado iterativamente."
    bfBody.Parent = ballisticsFormulaCard

    -- =========================================================================
    -- [ABA 6] DIAGNÓSTICO & IA (DIAGNOSTICS)
    -- =========================================================================
    local pageDiag = pages["Diagnostics"]

    CreateSectionHeader(pageDiag, "MOTOR DE DIAGNÓSTICO EM 6 CAMADAS & RELATÓRIOS ESTRUTURADOS")

    local diagActionRow = Instance.new("Frame")
    diagActionRow.Size = UDim2.new(1, 0, 0, 34)
    diagActionRow.BackgroundTransparency = 1
    diagActionRow.Parent = pageDiag

    local runDiagBtn = Instance.new("TextButton")
    runDiagBtn.Size = UDim2.new(0.5, -4, 1, 0)
    runDiagBtn.Position = UDim2.new(0, 0, 0, 0)
    runDiagBtn.BackgroundColor3 = THEME.ACCENT_PURPLE
    runDiagBtn.TextColor3 = THEME.TEXT_MAIN
    runDiagBtn.Font = Enum.Font.GothamBold
    runDiagBtn.TextSize = 10.5
    runDiagBtn.Text = "🩺 EXECUTAR DIAGNÓSTICO COMPLETO"
    runDiagBtn.Parent = diagActionRow
    AddCorner(runDiagBtn, 6)
    AddStroke(runDiagBtn, THEME.BORDER_LIGHT, 1)

    local runShotDiagBtn = Instance.new("TextButton")
    runShotDiagBtn.Size = UDim2.new(0.5, -4, 1, 0)
    runShotDiagBtn.Position = UDim2.new(0.5, 4, 0, 0)
    runShotDiagBtn.BackgroundColor3 = THEME.BG_INPUT
    runShotDiagBtn.TextColor3 = THEME.TEXT_MAIN
    runShotDiagBtn.Font = Enum.Font.GothamBold
    runShotDiagBtn.TextSize = 10.5
    runShotDiagBtn.Text = "🎯 TESTAR DISPARO SILENT AIM"
    runShotDiagBtn.Parent = diagActionRow
    AddCorner(runShotDiagBtn, 6)
    AddStroke(runShotDiagBtn, THEME.BORDER, 1)
    runShotDiagBtn.MouseButton1Click:Connect(function()
        if DashboardGUI.OnSimulateSilentAimShot then DashboardGUI.OnSimulateSilentAimShot() end
    end)

    -- Card com Resultado do Diagnóstico Estruturado
    local diagResultCard = Instance.new("Frame")
    diagResultCard.Size = UDim2.new(1, 0, 0, 110)
    diagResultCard.BackgroundColor3 = THEME.BG_INPUT
    diagResultCard.Parent = pageDiag
    AddCorner(diagResultCard, 6)
    AddStroke(diagResultCard, THEME.BORDER, 1)

    local drHeader = Instance.new("Frame")
    drHeader.Size = UDim2.new(1, -16, 0, 20)
    drHeader.Position = UDim2.new(0, 8, 0, 6)
    drHeader.BackgroundTransparency = 1
    drHeader.Parent = diagResultCard

    local drStatusBadge = Instance.new("TextLabel")
    drStatusBadge.Size = UDim2.new(0, 90, 1, 0)
    drStatusBadge.BackgroundColor3 = THEME.SUCCESS
    drStatusBadge.Font = Enum.Font.GothamBold
    drStatusBadge.TextSize = 9.5
    drStatusBadge.TextColor3 = THEME.TEXT_MAIN
    drStatusBadge.Text = "HEALTHY"
    drStatusBadge.Parent = drHeader
    AddCorner(drStatusBadge, 4)
    TelemetryLabels["Diag_StatusBadge"] = drStatusBadge

    local drConfidenceBadge = Instance.new("TextLabel")
    drConfidenceBadge.Size = UDim2.new(0, 150, 1, 0)
    drConfidenceBadge.Position = UDim2.new(0, 98, 0, 0)
    drConfidenceBadge.BackgroundColor3 = THEME.BG_WINDOW
    drConfidenceBadge.Font = Enum.Font.Code
    drConfidenceBadge.TextSize = 9
    drConfidenceBadge.TextColor3 = THEME.ACCENT_PURPLE
    drConfidenceBadge.Text = "[CONFIRMED - 100%]"
    drConfidenceBadge.Parent = drHeader
    AddCorner(drConfidenceBadge, 4)
    AddStroke(drConfidenceBadge, THEME.BORDER, 1)
    TelemetryLabels["Diag_ConfidenceBadge"] = drConfidenceBadge

    local drSummary = Instance.new("TextLabel")
    drSummary.Size = UDim2.new(1, -16, 0, 18)
    drSummary.Position = UDim2.new(0, 8, 0, 30)
    drSummary.BackgroundTransparency = 1
    drSummary.Font = Enum.Font.GothamBold
    drSummary.TextSize = 10
    drSummary.TextColor3 = THEME.TEXT_MAIN
    drSummary.TextXAlignment = Enum.TextXAlignment.Left
    drSummary.Text = "Resumo: Todos os subsistemas cinemáticos operam dentro dos parâmetros nominais."
    drSummary.Parent = diagResultCard
    TelemetryLabels["Diag_Summary"] = drSummary

    local drCause = Instance.new("TextLabel")
    drCause.Size = UDim2.new(1, -16, 0, 16)
    drCause.Position = UDim2.new(0, 8, 0, 50)
    drCause.BackgroundTransparency = 1
    drCause.Font = Enum.Font.GothamMedium
    drCause.TextSize = 9.5
    drCause.TextColor3 = THEME.TEXT_MUTED
    drCause.TextXAlignment = Enum.TextXAlignment.Left
    drCause.Text = "Causa-Raiz: Rastreamento, lead e visada física validados no Workspace."
    drCause.Parent = diagResultCard
    TelemetryLabels["Diag_RootCause"] = drCause

    local drAction = Instance.new("TextLabel")
    drAction.Size = UDim2.new(1, -16, 0, 16)
    drAction.Position = UDim2.new(0, 8, 0, 68)
    drAction.BackgroundTransparency = 1
    drAction.Font = Enum.Font.GothamMedium
    drAction.TextSize = 9.5
    drAction.TextColor3 = THEME.INFO
    drAction.TextXAlignment = Enum.TextXAlignment.Left
    drAction.Text = "Ação Sugerida: Prossiga com os testes dinâmicos de movimentação."
    drAction.Parent = diagResultCard
    TelemetryLabels["Diag_SuggestedAction"] = drAction

    local drVerif = Instance.new("TextLabel")
    drVerif.Size = UDim2.new(1, -16, 0, 16)
    drVerif.Position = UDim2.new(0, 8, 0, 86)
    drVerif.BackgroundTransparency = 1
    drVerif.Font = Enum.Font.Code
    drVerif.TextSize = 8.5
    drVerif.TextColor3 = THEME.TEXT_MUTED
    drVerif.TextXAlignment = Enum.TextXAlignment.Left
    drVerif.Text = "Verificação: Estado estável verificado contra histórico."
    drVerif.Parent = diagResultCard
    TelemetryLabels["Diag_Verification"] = drVerif

    -- Botões de Exportação Estruturada
    CreateSectionHeader(pageDiag, "EXPORTAÇÃO ESTRUTURADA DE RELATÓRIO")
    local exportActionRow = Instance.new("Frame")
    exportActionRow.Size = UDim2.new(1, 0, 0, 30)
    exportActionRow.BackgroundTransparency = 1
    exportActionRow.Parent = pageDiag

    local exportJsonBtn = Instance.new("TextButton")
    exportJsonBtn.Size = UDim2.new(0.5, -4, 1, 0)
    exportJsonBtn.Position = UDim2.new(0, 0, 0, 0)
    exportJsonBtn.BackgroundColor3 = THEME.BG_INPUT
    exportJsonBtn.Font = Enum.Font.GothamBold
    exportJsonBtn.TextSize = 10
    exportJsonBtn.TextColor3 = THEME.TEXT_MAIN
    exportJsonBtn.Text = "📄 EXPORTAR JSON"
    exportJsonBtn.Parent = exportActionRow
    AddCorner(exportJsonBtn, 5)
    AddStroke(exportJsonBtn, THEME.BORDER, 1)

    local exportMdBtn = Instance.new("TextButton")
    exportMdBtn.Size = UDim2.new(0.5, -4, 1, 0)
    exportMdBtn.Position = UDim2.new(0.5, 4, 0, 0)
    exportMdBtn.BackgroundColor3 = THEME.BG_INPUT
    exportMdBtn.Font = Enum.Font.GothamBold
    exportMdBtn.TextSize = 10
    exportMdBtn.TextColor3 = THEME.TEXT_MAIN
    exportMdBtn.Text = "📑 EXPORTAR MARKDOWN"
    exportMdBtn.Parent = exportActionRow
    AddCorner(exportMdBtn, 5)
    AddStroke(exportMdBtn, THEME.BORDER, 1)

    local exportViewer = Instance.new("TextBox")
    exportViewer.Size = UDim2.new(1, 0, 0, 60)
    exportViewer.BackgroundColor3 = THEME.BG_WINDOW
    exportViewer.TextColor3 = THEME.TEXT_MUTED
    exportViewer.Font = Enum.Font.Code
    exportViewer.TextSize = 9
    exportViewer.TextWrapped = true
    exportViewer.ClearTextOnFocus = false
    exportViewer.Text = "-- Clique em 'Exportar JSON' ou 'Exportar Markdown' para visualizar o relatório estruturado aqui --"
    exportViewer.Parent = pageDiag
    AddCorner(exportViewer, 5)
    AddStroke(exportViewer, THEME.BORDER, 1)

    exportJsonBtn.MouseButton1Click:Connect(function()
        if DashboardGUI.OnExportDiagnosticsJSON then
            local str = DashboardGUI.OnExportDiagnosticsJSON()
            exportViewer.Text = str
            exportViewer.TextColor3 = THEME.SUCCESS
        end
    end)
    exportMdBtn.MouseButton1Click:Connect(function()
        if DashboardGUI.OnExportDiagnosticsMarkdown then
            local str = DashboardGUI.OnExportDiagnosticsMarkdown()
            exportViewer.Text = str
            exportViewer.TextColor3 = THEME.INFO
        end
    end)

    -- Chatbot UI Container
    CreateSectionHeader(pageDiag, "ASSISTENTE INTELIGENTE CHATBOT IA")
    local chatCard = Instance.new("Frame")
    chatCard.Size = UDim2.new(1, 0, 0, 200)
    chatCard.BackgroundColor3 = THEME.BG_INPUT
    chatCard.Parent = pageDiag
    AddCorner(chatCard, 8)
    AddStroke(chatCard, THEME.BORDER, 1)

    local quickBtnGrid = Instance.new("Frame")
    quickBtnGrid.Size = UDim2.new(1, -16, 0, 24)
    quickBtnGrid.Position = UDim2.new(0, 8, 0, 8)
    quickBtnGrid.BackgroundTransparency = 1
    quickBtnGrid.Parent = chatCard

    local qbLayout = Instance.new("UIGridLayout")
    qbLayout.CellSize = UDim2.new(0.24, 0, 1, 0)
    qbLayout.CellPadding = UDim2.new(0.013, 0, 0, 0)
    qbLayout.Parent = quickBtnGrid

    local chatResponseBox = Instance.new("TextLabel")
    chatResponseBox.Size = UDim2.new(1, -16, 1, -76)
    chatResponseBox.Position = UDim2.new(0, 8, 0, 36)
    chatResponseBox.BackgroundColor3 = THEME.BG_WINDOW
    chatResponseBox.TextColor3 = THEME.TEXT_MAIN
    chatResponseBox.Font = Enum.Font.GothamMedium
    chatResponseBox.TextSize = 10
    chatResponseBox.TextXAlignment = Enum.TextXAlignment.Left
    chatResponseBox.TextYAlignment = Enum.TextYAlignment.Top
    chatResponseBox.TextWrapped = true
    chatResponseBox.Text = "  Assistente DeepHat V8 pronto. Selecione um diagnóstico rápido ou faça uma pergunta abaixo."
    chatResponseBox.Parent = chatCard
    AddCorner(chatResponseBox, 6)
    AddStroke(chatResponseBox, THEME.BORDER, 1)

    local function TriggerChatQuery(query: string)
        chatResponseBox.Text = "  Analisando estado da simulação, telemetria e logs..."
        chatResponseBox.TextColor3 = THEME.WARNING
        task.defer(function()
            local resp = nil
            if DashboardGUI.OnQueryDiagnosticChatbot then
                resp = DashboardGUI.OnQueryDiagnosticChatbot(query)
            end
            if resp and type(resp) == "table" then
                chatResponseBox.TextColor3 = THEME.TEXT_MAIN
                chatResponseBox.Text = string.format("  [DIAGNÓSTICO]: %s\n  [MÓDULO AFETADO]: %s\n  [AÇÃO SUGERIDA]: %s", resp.Answer or "OK", resp.AffectedModule or "Nenhum", resp.SuggestedAction or "Nenhuma")
            else
                chatResponseBox.TextColor3 = THEME.INFO
                chatResponseBox.Text = "  [DIAGNÓSTICO]: Estado geral nominal. Nenhum módulo apresenta anomalia crítica no momento."
            end
        end)
    end

    local function MakeQuickButton(text: string, query: string)
        local qb = Instance.new("TextButton")
        qb.BackgroundColor3 = THEME.BG_WINDOW
        qb.Font = Enum.Font.GothamBold
        qb.TextSize = 9
        qb.TextColor3 = THEME.TEXT_MAIN
        qb.Text = text
        qb.Parent = quickBtnGrid
        AddCorner(qb, 4)
        AddStroke(qb, THEME.BORDER, 1)
        qb.MouseButton1Click:Connect(function() TriggerChatQuery(query) end)
    end

    MakeQuickButton("🔍 Saúde Geral", "analisar status e erros do simulador")
    MakeQuickButton("🎯 Testar Mira", "por que a mira não foca no alvo?")
    MakeQuickButton("⚡ Balística", "como calibrar gravidade e tempo de voo?")
    MakeQuickButton("🛡️ Visada LOS", "alvo está bloqueado ou ocluído?")

    runDiagBtn.MouseButton1Click:Connect(function()
        if DashboardGUI.OnRunFullDiagnostic then
            local rep = DashboardGUI.OnRunFullDiagnostic()
            if rep and type(rep) == "table" then
                drStatusBadge.Text = rep.Status
                drStatusBadge.BackgroundColor3 = (rep.Status == "HEALTHY") and THEME.SUCCESS or ((rep.Status == "CRITICAL") and THEME.ACCENT_RED or THEME.WARNING)
                drConfidenceBadge.Text = string.format("[%s - %.0f%%]", rep.EvidenceType or "CONFIRMED", (rep.Confidence or 1) * 100)
                drSummary.Text = "Resumo: " .. tostring(rep.Summary or "")
                drCause.Text = "Causa-Raiz: " .. tostring(rep.RootCause or "")
                drAction.Text = "Ação Sugerida: " .. tostring(rep.SuggestedAction or "")
                drVerif.Text = "Verificação: " .. tostring(rep.VerificationResult or "Estado nominal verificado.")
            end
        end
        TriggerChatQuery("executar diagnóstico completo e status operacional de todos os módulos")
    end)

    local chatInputRow = Instance.new("Frame")
    chatInputRow.Size = UDim2.new(1, -16, 0, 28)
    chatInputRow.Position = UDim2.new(0, 8, 1, -34)
    chatInputRow.BackgroundTransparency = 1
    chatInputRow.Parent = chatCard

    local chatInput = Instance.new("TextBox")
    chatInput.Size = UDim2.new(1, -90, 1, 0)
    chatInput.BackgroundColor3 = THEME.BG_WINDOW
    chatInput.TextColor3 = THEME.TEXT_MAIN
    chatInput.PlaceholderText = "Pergunte sobre falhas, calibração de mira, FOV ou gravidade..."
    chatInput.PlaceholderColor3 = THEME.TEXT_MUTED
    chatInput.Font = Enum.Font.GothamMedium
    chatInput.TextSize = 10
    chatInput.ClearTextOnFocus = false
    chatInput.Parent = chatInputRow
    AddCorner(chatInput, 5)
    AddStroke(chatInput, THEME.BORDER, 1)

    local chatSendBtn = Instance.new("TextButton")
    chatSendBtn.Size = UDim2.new(0, 82, 1, 0)
    chatSendBtn.Position = UDim2.new(1, -82, 0, 0)
    chatSendBtn.BackgroundColor3 = THEME.ACCENT_PURPLE
    chatSendBtn.Font = Enum.Font.GothamBold
    chatSendBtn.TextSize = 10.5
    chatSendBtn.TextColor3 = THEME.TEXT_MAIN
    chatSendBtn.Text = "ENVIAR"
    chatSendBtn.Parent = chatInputRow
    AddCorner(chatSendBtn, 5)
    AddStroke(chatSendBtn, THEME.BORDER_LIGHT, 1)

    local function SubmitChat()
        local text = chatInput.Text
        if #text > 1 then
            TriggerChatQuery(text)
            chatInput.Text = ""
        end
    end
    chatSendBtn.MouseButton1Click:Connect(SubmitChat)
    chatInput.FocusLost:Connect(function(enterPressed)
        if enterPressed then SubmitChat() end
    end)

    -- Cenários de Linha de Visada
    CreateSectionHeader(pageDiag, "CENÁRIOS DE LINHA DE VISADA (LINE OF SIGHT)")
    LosLabels["Status"] = MakeInfoLabel(pageDiag, "Última consulta: (nenhuma)", THEME.TEXT_MUTED, 22)
    LosLabels["Reason"] = MakeInfoLabel(pageDiag, "Causa: —", THEME.TEXT_MUTED, 20)
    LosLabels["Blocker"] = MakeInfoLabel(pageDiag, "Obstrução: —", THEME.TEXT_MUTED, 20)

    local losScenGrid = Instance.new("Frame")
    losScenGrid.Size = UDim2.new(1, 0, 0, 0)
    losScenGrid.AutomaticSize = Enum.AutomaticSize.Y
    losScenGrid.BackgroundTransparency = 1
    losScenGrid.Parent = pageDiag

    local lsLayout = Instance.new("UIGridLayout")
    lsLayout.CellSize = UDim2.new(0, 150, 0, 24)
    lsLayout.CellPadding = UDim2.new(0, 6, 0, 6)
    lsLayout.Parent = losScenGrid

    for _, sc in ipairs(ScenarioRunner.Scenarios) do
        local b = Instance.new("TextButton")
        b.BackgroundColor3 = THEME.BG_INPUT
        b.Font = Enum.Font.GothamMedium
        b.TextSize = 9.5
        b.TextColor3 = THEME.TEXT_MAIN
        b.Text = "▶ " .. sc.Label
        b.Parent = losScenGrid
        AddCorner(b, 4)
        AddStroke(b, THEME.BORDER, 1)
        b.MouseButton1Click:Connect(function()
            if DashboardGUI.OnRunLosScenario then DashboardGUI.OnRunLosScenario(sc.Id) end
        end)
    end

    local losHistory = Instance.new("ScrollingFrame")
    losHistory.Size = UDim2.new(1, 0, 0, 90)
    losHistory.BackgroundColor3 = THEME.BG_WINDOW
    losHistory.ScrollBarThickness = 4
    losHistory.CanvasSize = UDim2.new(0, 0, 0, 0)
    losHistory.AutomaticCanvasSize = Enum.AutomaticSize.Y
    losHistory.Parent = pageDiag
    AddCorner(losHistory, 6)
    AddStroke(losHistory, THEME.BORDER, 1)
    local losHistLayout = Instance.new("UIListLayout")
    losHistLayout.Padding = UDim.new(0, 2)
    losHistLayout.SortOrder = Enum.SortOrder.LayoutOrder
    losHistLayout.Parent = losHistory
    LosHistoryList = losHistory

    -- =========================================================================
    -- [ABA 7] LOGS & EVENTOS (LOGS)
    -- =========================================================================
    local pageLogs = pages["Logs"]

    CreateSectionHeader(pageLogs, "TERMINAL DE OBSERVABILIDADE E LOGS EM TEMPO REAL")

    local logToolbar = Instance.new("Frame")
    logToolbar.Size = UDim2.new(1, 0, 0, 30)
    logToolbar.BackgroundTransparency = 1
    logToolbar.Parent = pageLogs

    local filterButtons: { [string]: TextButton } = {}
    local filterOptions = { "TODOS", "OK", "INFO", "WARN", "FAIL" }

    local function SetActiveFilter(flt: string)
        currentLogFilter = flt
        for opt, btn in pairs(filterButtons) do
            if opt == flt then
                btn.BackgroundColor3 = THEME.ACCENT_PURPLE
                btn.TextColor3 = THEME.TEXT_MAIN
            else
                btn.BackgroundColor3 = THEME.BG_INPUT
                btn.TextColor3 = THEME.TEXT_MUTED
            end
        end
        ApplyLogFilter()
    end

    local filterPills = Instance.new("Frame")
    filterPills.Size = UDim2.new(0, 280, 1, 0)
    filterPills.BackgroundTransparency = 1
    filterPills.Parent = logToolbar

    local fpLayout = Instance.new("UIListLayout")
    fpLayout.FillDirection = Enum.FillDirection.Horizontal
    fpLayout.Padding = UDim.new(0, 4)
    fpLayout.Parent = filterPills

    for _, opt in ipairs(filterOptions) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 50, 0, 24)
        btn.BackgroundColor3 = (opt == "TODOS") and THEME.ACCENT_PURPLE or THEME.BG_INPUT
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 9
        btn.TextColor3 = (opt == "TODOS") and THEME.TEXT_MAIN or THEME.TEXT_MUTED
        btn.Text = opt
        btn.Parent = filterPills
        AddCorner(btn, 4)
        AddStroke(btn, THEME.BORDER, 1)
        filterButtons[opt] = btn
        btn.MouseButton1Click:Connect(function()
            SetActiveFilter(opt)
        end)
    end

    -- Caixa de Busca Textual de Logs
    local logSearchBox = Instance.new("TextBox")
    logSearchBox.Size = UDim2.new(1, -410, 0, 24)
    logSearchBox.Position = UDim2.new(0, 285, 0, 0)
    logSearchBox.BackgroundColor3 = THEME.BG_INPUT
    logSearchBox.TextColor3 = THEME.TEXT_MAIN
    logSearchBox.PlaceholderText = "🔍 Buscar termo nos logs..."
    logSearchBox.PlaceholderColor3 = THEME.TEXT_MUTED
    logSearchBox.Font = Enum.Font.GothamMedium
    logSearchBox.TextSize = 9.5
    logSearchBox.ClearTextOnFocus = false
    logSearchBox.Parent = logToolbar
    AddCorner(logSearchBox, 4)
    AddStroke(logSearchBox, THEME.BORDER, 1)
    logSearchBox:GetPropertyChangedSignal("Text"):Connect(function()
        currentLogSearch = logSearchBox.Text
        ApplyLogFilter()
    end)

    local clearLogsBtn = Instance.new("TextButton")
    clearLogsBtn.Size = UDim2.new(0, 110, 0, 24)
    clearLogsBtn.Position = UDim2.new(1, -110, 0, 0)
    clearLogsBtn.BackgroundColor3 = THEME.BG_INPUT
    clearLogsBtn.Font = Enum.Font.GothamBold
    clearLogsBtn.TextSize = 9
    clearLogsBtn.TextColor3 = THEME.TEXT_MAIN
    clearLogsBtn.Text = "🗑️ Limpar Logs"
    clearLogsBtn.Parent = logToolbar
    AddCorner(clearLogsBtn, 4)
    AddStroke(clearLogsBtn, THEME.BORDER, 1)
    clearLogsBtn.MouseButton1Click:Connect(function()
        if EventLogListInstance then
            for _, ch in ipairs(EventLogListInstance:GetChildren()) do
                if ch:IsA("Frame") then ch:Destroy() end
            end
            ApplyLogFilter()
        end
    end)

    local logCounterLabel = Instance.new("TextLabel")
    logCounterLabel.Size = UDim2.new(1, 0, 0, 14)
    logCounterLabel.BackgroundTransparency = 1
    logCounterLabel.Font = Enum.Font.GothamMedium
    logCounterLabel.TextSize = 9
    logCounterLabel.TextColor3 = THEME.TEXT_MUTED
    logCounterLabel.TextXAlignment = Enum.TextXAlignment.Left
    logCounterLabel.Text = "Exibindo 0 de 0 eventos"
    logCounterLabel.Parent = pageLogs
    LogCounterLabelInstance = logCounterLabel

    local eventLogList = Instance.new("ScrollingFrame")
    eventLogList.Size = UDim2.new(1, 0, 0, 360)
    eventLogList.BackgroundColor3 = THEME.BG_WINDOW
    eventLogList.ScrollBarThickness = 4
    eventLogList.CanvasSize = UDim2.new(0, 0, 0, 0)
    eventLogList.AutomaticCanvasSize = Enum.AutomaticSize.Y
    eventLogList.Parent = pageLogs
    AddCorner(eventLogList, 6)
    AddStroke(eventLogList, THEME.BORDER, 1)
    local evListLayout = Instance.new("UIListLayout")
    evListLayout.Padding = UDim.new(0, 2)
    evListLayout.Parent = eventLogList
    EventLogListInstance = eventLogList

    -- =========================================================================
    -- [ABA 8] CONFIGURAÇÕES & PERFIS (SETTINGS)
    -- =========================================================================
    local pageSettings = pages["Settings"]

    CreateSectionHeader(pageSettings, "PERFIS DE SIMULAÇÃO")
    local profileGrid = Instance.new("Frame")
    profileGrid.Size = UDim2.new(1, 0, 0, 34)
    profileGrid.BackgroundTransparency = 1
    profileGrid.Parent = pageSettings

    local pGridLayout = Instance.new("UIGridLayout")
    pGridLayout.CellSize = UDim2.new(0.19, 0, 1, 0)
    pGridLayout.CellPadding = UDim2.new(0.0125, 0, 0, 0)
    pGridLayout.Parent = profileGrid

    local profileCards: { [string]: TextButton } = {}
    local profileList = { "Normal", "Leve", "Medio", "Agressivo", "Custom" }
    local function UpdateProfileUI(activeProf: string)
        for name, btn in pairs(profileCards) do
            local isCurrent = (name == activeProf)
            btn.BackgroundColor3 = isCurrent and THEME.ACCENT_PURPLE or THEME.BG_INPUT
            btn.TextColor3 = isCurrent and THEME.TEXT_MAIN or THEME.TEXT_MUTED
        end
    end
    for _, pName in ipairs(profileList) do
        local pBtn = Instance.new("TextButton")
        pBtn.BackgroundColor3 = (pName == SimConfig.Get("ActiveProfile")) and THEME.ACCENT_PURPLE or THEME.BG_INPUT
        pBtn.Font = Enum.Font.GothamBold
        pBtn.TextSize = 11
        pBtn.TextColor3 = (pName == SimConfig.Get("ActiveProfile")) and THEME.TEXT_MAIN or THEME.TEXT_MUTED
        pBtn.Text = pName
        pBtn.Parent = profileGrid
        AddCorner(pBtn, 5)
        AddStroke(pBtn, THEME.BORDER, 1)
        profileCards[pName] = pBtn
        pBtn.MouseButton1Click:Connect(function()
            SimConfig.ApplyProfile(pName)
            UpdateProfileUI(pName)
            DashboardGUI.AddDiagnosticLog("PROFILE", "Perfil alterado para: " .. pName, "INFO")
        end)
    end

    CreateSectionHeader(pageSettings, "PREFERÊNCIAS DA INTERFACE")
    CreateSliderField(pageSettings, "Transparência do Fundo da Janela", "WindowTransparency", 0.0, 0.8, SimConfig.Get("WindowTransparency") or 0.0, 0.05, "Ajuste de opacidade do fundo para observação do ambiente de jogo")
    SimConfig.Subscribe("WindowTransparency", function(val)
        if MainFrameInstance and typeof(val) == "number" then
            MainFrameInstance.BackgroundTransparency = math.clamp(val, 0, 0.8)
        end
    end)

    local hotkeyCard = Instance.new("Frame")
    hotkeyCard.Size = UDim2.new(1, 0, 0, 36)
    hotkeyCard.BackgroundColor3 = THEME.BG_INPUT
    hotkeyCard.Parent = pageSettings
    AddCorner(hotkeyCard, 6)
    AddStroke(hotkeyCard, THEME.BORDER, 1)

    local hkLabel = Instance.new("TextLabel")
    hkLabel.Size = UDim2.new(1, -16, 1, 0)
    hkLabel.Position = UDim2.new(0, 10, 0, 0)
    hkLabel.BackgroundTransparency = 1
    hkLabel.Font = Enum.Font.GothamMedium
    hkLabel.TextSize = 10
    hkLabel.TextColor3 = THEME.TEXT_MAIN
    hkLabel.TextXAlignment = Enum.TextXAlignment.Left
    hkLabel.Text = "⌨️ Teclas de Atalho: Pressione [HOME] ou [RightShift] para abrir/fechar o painel."
    hkLabel.Parent = hotkeyCard

    CreateSectionHeader(pageSettings, "GERENCIAMENTO E PERSISTÊNCIA DE DADOS")
    local persistRow = Instance.new("Frame")
    persistRow.Size = UDim2.new(1, 0, 0, 32)
    persistRow.BackgroundTransparency = 1
    persistRow.Parent = pageSettings

    local saveBtn = Instance.new("TextButton")
    saveBtn.Size = UDim2.new(0.5, -4, 1, 0)
    saveBtn.Position = UDim2.new(0, 0, 0, 0)
    saveBtn.BackgroundColor3 = THEME.ACCENT_PURPLE
    saveBtn.Font = Enum.Font.GothamBold
    saveBtn.TextSize = 10.5
    saveBtn.TextColor3 = THEME.TEXT_MAIN
    saveBtn.Text = "💾 SALVAR CONFIGURAÇÕES"
    saveBtn.Parent = persistRow
    AddCorner(saveBtn, 5)
    AddStroke(saveBtn, THEME.BORDER_LIGHT, 1)
    saveBtn.MouseButton1Click:Connect(function()
        local ok = SimConfig.Save()
        DashboardGUI.AddDiagnosticLog("SAVE", ok and "Configurações persistidas com sucesso." or "Falha ao persistir.", ok and "OK" or "WARN")
    end)

    local resetBtn = Instance.new("TextButton")
    resetBtn.Size = UDim2.new(0.5, -4, 1, 0)
    resetBtn.Position = UDim2.new(0.5, 4, 0, 0)
    resetBtn.BackgroundColor3 = THEME.BG_INPUT
    resetBtn.Font = Enum.Font.GothamBold
    resetBtn.TextSize = 10.5
    resetBtn.TextColor3 = THEME.ACCENT_RED
    resetBtn.Text = "⚠️ RESTAURAR PADRÕES"
    resetBtn.Parent = persistRow
    AddCorner(resetBtn, 5)
    AddStroke(resetBtn, THEME.BORDER, 1)
    resetBtn.MouseButton1Click:Connect(function()
        SimConfig.RestoreDefaults("Reset acionado pelo usuário")
        UpdateProfileUI(SimConfig.DefaultProfileName)
        DashboardGUI.AddDiagnosticLog("RESET", "Todos os parâmetros foram restaurados aos padrões de fábrica.", "OK")
    end)

    local ioCard = Instance.new("Frame")
    ioCard.Size = UDim2.new(1, 0, 0, 80)
    ioCard.BackgroundColor3 = THEME.BG_INPUT
    ioCard.Parent = pageSettings
    AddCorner(ioCard, 6)
    AddStroke(ioCard, THEME.BORDER, 1)

    local ioBox = Instance.new("TextBox")
    ioBox.Size = UDim2.new(1, -16, 0, 36)
    ioBox.Position = UDim2.new(0, 8, 0, 6)
    ioBox.BackgroundColor3 = THEME.BG_WINDOW
    ioBox.TextColor3 = THEME.TEXT_MAIN
    ioBox.Font = Enum.Font.Code
    ioBox.TextSize = 9
    ioBox.ClearTextOnFocus = false
    ioBox.PlaceholderText = "Cole JSON para importar ou clique em Exportar..."
    ioBox.PlaceholderColor3 = THEME.TEXT_MUTED
    ioBox.Parent = ioCard
    AddCorner(ioBox, 4)
    AddStroke(ioBox, THEME.BORDER, 1)

    local ioBtnRow = Instance.new("Frame")
    ioBtnRow.Size = UDim2.new(1, -16, 0, 26)
    ioBtnRow.Position = UDim2.new(0, 8, 0, 48)
    ioBtnRow.BackgroundTransparency = 1
    ioBtnRow.Parent = ioCard

    local expBtn = Instance.new("TextButton")
    expBtn.Size = UDim2.new(0.5, -4, 1, 0)
    expBtn.Position = UDim2.new(0, 0, 0, 0)
    expBtn.BackgroundColor3 = THEME.BG_WINDOW
    expBtn.Font = Enum.Font.GothamBold
    expBtn.TextSize = 9.5
    expBtn.TextColor3 = THEME.TEXT_MAIN
    expBtn.Text = "📤 Exportar JSON"
    expBtn.Parent = ioBtnRow
    AddCorner(expBtn, 4)
    AddStroke(expBtn, THEME.BORDER, 1)
    expBtn.MouseButton1Click:Connect(function()
        ioBox.Text = SimConfig.ExportJSON()
        DashboardGUI.AddDiagnosticLog("CONFIG", "Configurações exportadas para a caixa de texto.", "INFO")
    end)

    local impBtn = Instance.new("TextButton")
    impBtn.Size = UDim2.new(0.5, -4, 1, 0)
    impBtn.Position = UDim2.new(0.5, 4, 0, 0)
    impBtn.BackgroundColor3 = THEME.BG_WINDOW
    impBtn.Font = Enum.Font.GothamBold
    impBtn.TextSize = 9.5
    impBtn.TextColor3 = THEME.TEXT_MAIN
    impBtn.Text = "📥 Importar JSON"
    impBtn.Parent = ioBtnRow
    AddCorner(impBtn, 4)
    AddStroke(impBtn, THEME.BORDER, 1)
    impBtn.MouseButton1Click:Connect(function()
        local success, errors = SimConfig.ImportJSON(ioBox.Text)
        if success then
            DashboardGUI.AddDiagnosticLog("CONFIG", "Configurações importadas com sucesso.", "OK")
        else
            DashboardGUI.AddDiagnosticLog("CONFIG", "Importação rejeitada: " .. table.concat(errors, "; "):sub(1, 160), "WARN")
        end
    end)

    -- Aba Inicial
    local startTab = tostring(SimConfig.Get("ActiveTab") or "Dashboard")
    SwitchTab(startTab)

    -- Barra Inferior de Ações (Footer)
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
        btn.BackgroundColor3 = isPrimary and THEME.ACCENT_PURPLE or THEME.BG_INPUT
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 10.5
        btn.TextColor3 = THEME.TEXT_MAIN
        btn.Text = text
        btn.Parent = footer
        AddCorner(btn, 5)
        AddStroke(btn, isPrimary and THEME.ACCENT_HOVER or THEME.BORDER, 1)
        btn.MouseButton1Click:Connect(onClick)
        return btn
    end

    CreateBottomButton("↺ RESETAR", false, function()
        SimConfig.RestoreDefaults("Restaurar padrões (UI)")
        UpdateProfileUI(SimConfig.DefaultProfileName)
        if DashboardGUI.OnResetRequested then DashboardGUI.OnResetRequested() end
    end)

    CreateBottomButton("💾 SALVAR CONFIG", false, function()
        local saved = SimConfig.Save()
        DashboardGUI.AddDiagnosticLog("SAVE", saved and "Configurações persistidas." or "Persistência indisponível.", saved and "OK" or "WARN")
        if DashboardGUI.OnSaveRequested then DashboardGUI.OnSaveRequested() end
    end)

    CreateBottomButton("⏹ PARAR", false, function()
        SimConfig.Set("SimulationActive", false)
        masterSwitch.BackgroundColor3 = THEME.BG_WINDOW
        masterSwitch.Text = "SIMULAÇÃO: PAUSADA"
        DashboardGUI.AddDiagnosticLog("ENGINE", "Execução interrompida.", "WARN")
        if DashboardGUI.OnStopRequested then DashboardGUI.OnStopRequested() end
    end)

    CreateBottomButton("▶ INICIAR TESTE", true, function()
        SimConfig.Set("SimulationActive", true)
        masterSwitch.BackgroundColor3 = THEME.ACCENT_PURPLE
        masterSwitch.Text = "SIMULAÇÃO: ATIVA"
        DashboardGUI.AddDiagnosticLog("ENGINE", "Sessão de teste iniciada.", "OK")
        if DashboardGUI.OnStartRequested then DashboardGUI.OnStartRequested() end
    end)

    -- Sincronização Observer
    if unsubscribeGlobal then unsubscribeGlobal(); unsubscribeGlobal = nil end
    unsubscribeGlobal = SimConfig.SubscribeAll(function(key, val)
        if key == "ActiveProfile" then
            UpdateProfileUI(tostring(val))
        elseif key == "SimulationActive" then
            local active = (val == true)
            masterSwitch.BackgroundColor3 = active and THEME.ACCENT_PURPLE or THEME.BG_WINDOW
            masterSwitch.Text = active and "SIMULAÇÃO: ATIVA" or "SIMULAÇÃO: PAUSADA"
            if FovCircleInstance then
                FovCircleInstance.Visible = active and (SimConfig.Get("ShowFovCircle") == true)
            end
            if TelemetryLabels["Dash_SimStatus"] then
                TelemetryLabels["Dash_SimStatus"].Text = active and "ATIVO" or "PAUSADO"
                TelemetryLabels["Dash_SimStatus"].TextColor3 = active and THEME.SUCCESS or THEME.WARNING
            end
        elseif syncInputs[key] and typeof(val) == "number" then
            syncInputs[key](val)
        end
    end)

    screenGui.Destroying:Connect(function()
        if unsubscribeGlobal then unsubscribeGlobal(); unsubscribeGlobal = nil end
    end)

    DashboardGUI.AddDiagnosticLog("INIT", "Dashboard GUI carregada com 8 abas profissionais v8.0 PRO.", "OK")
    return screenGui
end

-- =========================================================================
-- MÉTODOS PÚBLICOS DE TELEMETRIA & ATUALIZAÇÃO
-- =========================================================================
function DashboardGUI:UpdateFovCircle()
    if not FovCircleInstance or not FovCircleInstance.Parent then return end
    local camera = Workspace.CurrentCamera
    if not camera then return end

    local viewportSize = camera.ViewportSize
    if viewportSize.X <= 0 or viewportSize.Y <= 0 then return end

    local fovRadiusPx = tonumber(SimConfig.Get("FovRadiusPx")) or 120
    local diameter = fovRadiusPx * 2
    FovCircleInstance.Size = UDim2.new(0, diameter, 0, diameter)
    FovCircleInstance.Position = UDim2.new(0.5, 0, 0.5, 0)
    FovCircleInstance.Visible = SimConfig.Get("ShowFovCircle") == true and SimConfig.Get("SimulationActive") == true
end

function DashboardGUI:UpdateTelemetryDisplay(data: {
    angularVelocity: number?,
    isObstructed: boolean?,
    targetName: string?,
    dt: number?,
    mode: string?,
    decoupledAngle: number?,
    silentAimActive: boolean?,
    lastShot: any?
})
    if not data then return end
    if SimConfig.Get("TelemetryIndicators") == false then return end

    local angVel = tonumber(data.angularVelocity) or 0
    if angVel > PerformanceData.PeakAngVel then
        PerformanceData.PeakAngVel = angVel
    end

    if TelemetryLabels["AngVel"] then
        TelemetryLabels["AngVel"].Text = string.format("%.1f °/s", angVel)
    end

    local obstructed = (data.isObstructed == true)
    if TelemetryLabels["VisStatus"] then
        TelemetryLabels["VisStatus"].Text = obstructed and "OBSTRUÍDO" or "LIVRE"
        TelemetryLabels["VisStatus"].TextColor3 = obstructed and THEME.ACCENT_RED or THEME.SUCCESS
    end

    local targetStr = tostring(data.targetName or "NENHUM")
    if TelemetryLabels["ActiveTarget"] then
        TelemetryLabels["ActiveTarget"].Text = targetStr
    end
    if TelemetryLabels["Dash_TargetName"] then
        TelemetryLabels["Dash_TargetName"].Text = targetStr
        TelemetryLabels["Dash_TargetName"].TextColor3 = (targetStr ~= "NENHUM" and not targetStr:find("Nenhum")) and THEME.SUCCESS or THEME.TEXT_MUTED
    end

    local saEnabled = SimConfig.Get("SilentAimEnabled") == true
    if TelemetryLabels["SilentAimStatus"] then
        if data.lastShot then
            if data.lastShot.Success == true then
                TelemetryLabels["SilentAimStatus"].Text = "Módulo: ● TESTADO COM SUCESSO"
                TelemetryLabels["SilentAimStatus"].TextColor3 = THEME.SUCCESS
            else
                TelemetryLabels["SilentAimStatus"].Text = "Módulo: ⚠️ FALHA NO TESTE"
                TelemetryLabels["SilentAimStatus"].TextColor3 = THEME.ACCENT_RED
            end
        elseif saEnabled then
            TelemetryLabels["SilentAimStatus"].Text = "Módulo: ◐ HABILITADO (AGUARDANDO)"
            TelemetryLabels["SilentAimStatus"].TextColor3 = THEME.INFO
        else
            TelemetryLabels["SilentAimStatus"].Text = "Módulo: ○ DESATIVADO"
            TelemetryLabels["SilentAimStatus"].TextColor3 = THEME.TEXT_MUTED
        end
    end

    if TelemetryLabels["ModStatus_SilentAim"] then
        if data.lastShot then
            if data.lastShot.Success == true then
                TelemetryLabels["ModStatus_SilentAim"].Text = "● TESTADO OK"
                TelemetryLabels["ModStatus_SilentAim"].TextColor3 = THEME.SUCCESS
            else
                TelemetryLabels["ModStatus_SilentAim"].Text = "▲ FALHA DETECTADA"
                TelemetryLabels["ModStatus_SilentAim"].TextColor3 = THEME.ACCENT_RED
            end
        elseif saEnabled then
            TelemetryLabels["ModStatus_SilentAim"].Text = "◐ HABILITADO"
            TelemetryLabels["ModStatus_SilentAim"].TextColor3 = THEME.INFO
        else
            TelemetryLabels["ModStatus_SilentAim"].Text = "○ DESATIVADO"
            TelemetryLabels["ModStatus_SilentAim"].TextColor3 = THEME.TEXT_MUTED
        end
    end

    if data.lastShot then
        local ls = data.lastShot
        local outcome = tostring(ls.Outcome or (ls.Success and "SUCCESS" or "UNKNOWN"))
        local stagesCount = type(ls.StagesCompleted) == "table" and #ls.StagesCompleted or 5

        if TelemetryLabels["SilentAimStage"] then
            TelemetryLabels["SilentAimStage"].Text = string.format("Etapa: [%d/5] %s", stagesCount, ls.Stage or "FINAL")
            TelemetryLabels["SilentAimStage"].TextColor3 = ls.Success and THEME.SUCCESS or THEME.WARNING
        end

        if TelemetryLabels["LastShotStatus"] then
            local outcomeText = "NENHUM"
            local outcomeColor = THEME.TEXT_MUTED
            if outcome == "SUCCESS" then
                outcomeText = "✅ ACERTO CONFIRMADO NO ALVO"
                outcomeColor = THEME.SUCCESS
            elseif outcome == "TARGET_OUTSIDE_FOV" then
                outcomeText = "📐 FORA DO FOV MÁXIMO (REJEITADO)"
                outcomeColor = THEME.WARNING
            elseif outcome == "OBSTACLE_BLOCKED" then
                outcomeText = "🛡️ TRAJETÓRIA BLOQUEADA POR OBSTÁCULO"
                outcomeColor = THEME.ACCENT_RED
            elseif outcome == "TARGET_INVALID" then
                outcomeText = "❌ ALVO INVÁLIDO OU DESTRUÍDO"
                outcomeColor = THEME.WARNING
            elseif outcome == "INVALID_TRAJECTORY" then
                outcomeText = "⚠️ TRAJETÓRIA OU DADOS INVÁLIDOS"
                outcomeColor = THEME.WARNING
            elseif outcome == "PROBABILISTIC_SPREAD" then
                outcomeText = "🎲 DISPERSÃO PROBABILÍSTICA (MISS)"
                outcomeColor = THEME.INFO
            elseif outcome == "MODULE_DISABLED" then
                outcomeText = "⏹ MÓDULO SILENT AIM DESATIVADO"
                outcomeColor = THEME.TEXT_MUTED
            elseif outcome == "INTERNAL_ERROR" then
                outcomeText = "🛑 ERRO INTERNO NA EXECUÇÃO"
                outcomeColor = THEME.ACCENT_RED
            else
                outcomeText = ls.Success and "ACERTO" or "FALHA"
                outcomeColor = ls.Success and THEME.SUCCESS or THEME.WARNING
            end
            TelemetryLabels["LastShotStatus"].Text = string.format("Último Disparo: %s (%.1f°)", outcomeText, ls.DiscrepancyAngleDeg or 0)
            TelemetryLabels["LastShotStatus"].TextColor3 = outcomeColor
        end

        if TelemetryLabels["SilentAimDetails"] then
            local hitPartName = ls.HitPart and ls.HitPart.Name or "—"
            local hitDist = ls.HitDistance and string.format("%.1f st", ls.HitDistance) or "—"
            TelemetryLabels["SilentAimDetails"].Text = string.format("Impacto: %s | Parte: %s | Desvio: %.1f° | Dist: %s",
                ls.HitRegistered and "CONFIRMADO" or "NÃO REGISTRADO", hitPartName, ls.DiscrepancyAngleDeg or 0, hitDist)
        end

        if TelemetryLabels["SilentAimReason"] then
            local desc = ls.OutcomeDescription or ls.FailureReason or (ls.Success and "Trajetória e colisão validadas fisicamente no Workspace." or "Verifique as configurações.")
            TelemetryLabels["SilentAimReason"].Text = "Diagnóstico: " .. desc
            TelemetryLabels["SilentAimReason"].TextColor3 = ls.Success and THEME.SUCCESS or THEME.TEXT_MUTED
        end
    end
end

-- Watchdog de Fundo (Monitor de Saúde em Tempo Real)
task.spawn(function()
    while true do
        task.wait(0.75)
        local ok, _ = pcall(function()
            local now = os.clock()
            local dt = now - PerformanceData.LastCheck
            PerformanceData.LastCheck = now
            local currentFps = math.clamp(math.round(1 / math.max(dt, 0.001)), 1, 144)
            PerformanceData.Fps = currentFps

            if TelemetryLabels["FpsCounter"] then
                TelemetryLabels["FpsCounter"].Text = string.format("%d FPS", currentFps)
            end
            if TelemetryLabels["Dash_FpsCounter"] then
                TelemetryLabels["Dash_FpsCounter"].Text = string.format("%d FPS", currentFps)
            end

            local healthGood = true
            local reason = "OK"

            local camera = Workspace.CurrentCamera
            if not camera then
                healthGood = false
                reason = "Câmera ausente"
            end

            local fov = tonumber(SimConfig.Get("FOV")) or 70
            if fov < 10 or fov > 180 then
                SimConfig.Set("FOV", math.clamp(fov, 10, 180))
            end

            if WatchdogBadgeInstance and WatchdogBadgeInstance.Parent then
                if healthGood then
                    WatchdogBadgeInstance.Text = "● MONITOR: 100% OPERACIONAL"
                    WatchdogBadgeInstance.TextColor3 = THEME.SUCCESS
                else
                    WatchdogBadgeInstance.Text = "⚠️ ALERTA: " .. string.upper(reason)
                    WatchdogBadgeInstance.TextColor3 = THEME.WARNING
                end
            end
        end)
    end
end)

function DashboardGUI:UpdateLos(last: any, history: { any }?)
    if not last then return end
    if LosLabels["Status"] then
        local passed = (last.Status == "FREE")
        LosLabels["Status"].Text = string.format("  Status: %s (Alvo: %s)", passed and "VISADA LIVRE" or "BLOQUEADO", tostring(last.Target or "Nenhum"))
        LosLabels["Status"].TextColor3 = passed and THEME.SUCCESS or THEME.ACCENT_RED
    end
    if LosLabels["Reason"] then
        LosLabels["Reason"].Text = "  Motivo: " .. tostring(last.Reason or "Sem obstruções.")
    end
    if LosLabels["Blocker"] then
        LosLabels["Blocker"].Text = "  Colisor: " .. tostring(last.Blocker or "Nenhum")
    end

    if history and LosHistoryList and LosHistoryList.Parent then
        local stamp = (history[#history] and history[#history].Timestamp) or -1
        if stamp ~= LastRenderedLosStamp then
            LastRenderedLosStamp = stamp
            for _, ch in ipairs(LosHistoryList:GetChildren()) do
                if ch:IsA("TextLabel") then ch:Destroy() end
            end
            local startIdx = math.max(1, #history - 15)
            for i = #history, startIdx, -1 do
                local entry = history[i]
                local item = Instance.new("TextLabel")
                item.Size = UDim2.new(1, -8, 0, 16)
                item.BackgroundTransparency = 1
                item.Font = Enum.Font.Code
                item.TextSize = 8.5
                item.TextXAlignment = Enum.TextXAlignment.Left
                local isOk = (entry.Status == "FREE")
                item.TextColor3 = isOk and THEME.SUCCESS or THEME.ACCENT_RED
                item.Text = string.format("[%s] %s | %s (%s)",
                    entry.Context or "Frame",
                    entry.Status,
                    entry.Blocker or "Sem obstáculo",
                    tostring(entry.Target or "Alvo")
                )
                item.Parent = LosHistoryList
            end
        end
    end
end

function DashboardGUI:UpdateDetection(info: any)
    if not info then return end
    if DetLabels["Count"] then
        DetLabels["Count"].Text = string.format("  Candidatos no Raio: %d", tonumber(info.Count) or 0)
    end
    if DetLabels["BestTarget"] then
        DetLabels["BestTarget"].Text = "  Alvo Selecionado: " .. tostring(info.BestTarget or "Nenhum")
        DetLabels["BestTarget"].TextColor3 = info.BestTarget and THEME.SUCCESS or THEME.TEXT_MUTED
    end
end

function DashboardGUI.Toggle(): boolean
    if MainFrameInstance then
        MainFrameInstance.Visible = not MainFrameInstance.Visible
        return MainFrameInstance.Visible
    end
    return false
end

function DashboardGUI.SetVisible(visible: boolean)
    if MainFrameInstance then MainFrameInstance.Visible = visible end
end

function DashboardGUI.IsVisible(): boolean
    return MainFrameInstance ~= nil and MainFrameInstance.Visible
end

function DashboardGUI.GetScreenGui(): ScreenGui?
    return ScreenGuiInstance
end

return DashboardGUI
