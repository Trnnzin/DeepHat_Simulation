--!strict
-- =========================================================================
-- DashboardGUI.lua
-- Interface Profissional de Simulação Cinemática e Diagnósticos de Detecção
-- Design: 5 Abas Objetivas e Simplificadas (Mira, Silent Aim, Balística, Diagnóstico, Configurações)
-- Conexão Reativa Bidirecional com SimConfig, Suporte a Chatbot IA e Pipeline de 4 Etapas
-- =========================================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CoreGuiService = game:GetService("CoreGui")

local SimConfig = require(script.Parent.SimConfig)
local ScenarioRunner = require(script.Parent.ScenarioRunner)

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
DashboardGUI.OnRunLosScenario = nil :: ((string) -> ())?
DashboardGUI.OnClearLosHistory = nil :: (() -> ())?
DashboardGUI.OnSimulateSilentAimShot = nil :: (() -> ())?
DashboardGUI.OnSpawnTestDummy = nil :: (() -> ())?
DashboardGUI.OnRunShotScenario = nil :: ((string) -> ())?
DashboardGUI.OnQueryDiagnosticChatbot = nil :: ((string) -> any)?
DashboardGUI.OnRunFullDiagnostic = nil :: (() -> any)?

-- Instâncias Internas
local ScreenGuiInstance: ScreenGui? = nil
local MainFrameInstance: Frame? = nil
local FovCircleInstance: Frame? = nil
local WatchdogBadgeInstance: TextLabel? = nil
local EventLogListInstance: ScrollingFrame? = nil
local unsubscribeGlobal: (() -> ())? = nil

-- Elementos de Telemetria Dinâmica
local TelemetryLabels: { [string]: TextLabel } = {}
local LosLabels: { [string]: TextLabel } = {}
local DetLabels: { [string]: TextLabel } = {}
local LosHistoryList: ScrollingFrame? = nil
local LastRenderedLosStamp = -1
local ApplyRuntimeConfig: ((string, any) -> ())? = nil
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
        local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
        if not playerGui then
            pcall(function() playerGui = localPlayer:WaitForChild("PlayerGui", 5) end)
        end
        if playerGui then return playerGui end
    end

    if okCore and coreGui then return coreGui end
    return Workspace
end

-- =========================================================================
-- LOG DE DIAGNÓSTICOS EM TEMPO REAL COM FILTRAGEM MULTI-NÍVEL
-- =========================================================================
local currentLogFilter = "TODOS"

local function ApplyLogFilter()
    if not EventLogListInstance then return end
    for _, child in ipairs(EventLogListInstance:GetChildren()) do
        if child:IsA("Frame") then
            local lvl = child:GetAttribute("LogLevel") or "INFO"
            if currentLogFilter == "TODOS" or lvl == currentLogFilter then
                child.Visible = true
            else
                child.Visible = false
            end
        end
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

    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 20)
    row.BackgroundColor3 = THEME.BG_INPUT
    row.BackgroundTransparency = 0.5
    row:SetAttribute("LogLevel", rowLevel)
    if currentLogFilter ~= "TODOS" and rowLevel ~= currentLogFilter then
        row.Visible = false
    else
        row.Visible = true
    end
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

    local children = EventLogListInstance:GetChildren()
    if #children > 45 then
        for i = 1, #children - 45 do
            if children[i]:IsA("Frame") then children[i]:Destroy() end
        end
    end
    EventLogListInstance.CanvasPosition = Vector2.new(0, 99999)
end

-- =========================================================================
-- CONSTRUÇÃO DA INTERFACE PRINCIPAL (5 ABAS OBJETIVAS)
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

    -- Janela Principal
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.new(0, 960, 0, 580)
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
    header.Size = UDim2.new(1, 0, 0, 44)
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
    titleLabel.Text = "DEEPHAT SIMULATION SUITE // v7.0 PRO"
    titleLabel.Parent = header

    -- Badge de Watchdog
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
    sidebar.Size = UDim2.new(0, 190, 1, 0)
    sidebar.BackgroundColor3 = THEME.BG_SIDEBAR
    sidebar.BorderSizePixel = 0
    sidebar.Parent = body
    AddCorner(sidebar, 8)
    AddStroke(sidebar, THEME.BORDER, 1)

    local sidebarList = Instance.new("UIListLayout")
    sidebarList.Padding = UDim.new(0, 6)
    sidebarList.Parent = sidebar

    local sidebarPad = Instance.new("UIPadding")
    sidebarPad.PaddingTop = UDim.new(0, 12)
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

    -- 5 ABAS OBJETIVAS (FASE 5)
    local pages: { [string]: ScrollingFrame } = {}
    local tabButtons: { [string]: TextButton } = {}

    local tabs = {
        { Id = "AimSimulation", Label = "◎  Mira Simulada" },
        { Id = "SilentAim",     Label = "🎯  Disparos Simulados" },
        { Id = "Ballistics",    Label = "⚡  Balística" },
        { Id = "Diagnostics",  Label = "▤  Diagnóstico & IA" },
        { Id = "Settings",     Label = "⚙  Configurações" },
    }

    local function SwitchTab(tabId: string)
        if not pages[tabId] then
            if tabId == "Dashboard" or tabId == "Camera" or tabId == "Simulation" or tabId == "Hitbox" then
                tabId = "AimSimulation"
            elseif tabId == "Vision" then
                tabId = "Ballistics"
            elseif tabId == "LineOfSight" or tabId == "Performance" then
                tabId = "Diagnostics"
            else
                tabId = "AimSimulation"
            end
        end
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
        btn.Size = UDim2.new(1, 0, 0, 36)
        btn.BackgroundColor3 = THEME.BG_INPUT
        btn.TextColor3 = THEME.TEXT_MUTED
        btn.Font = Enum.Font.GothamMedium
        btn.TextSize = 11
        btn.TextXAlignment = Enum.TextXAlignment.Left
        btn.Text = "  " .. t.Label
        btn.Parent = sidebar
        AddCorner(btn, 5)

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
        pList.Padding = UDim.new(0, 10)
        pList.Parent = page

        local pPad = Instance.new("UIPadding")
        pPad.PaddingTop = UDim.new(0, 12); pPad.PaddingBottom = UDim.new(0, 40)
        pPad.PaddingLeft = UDim.new(0, 14); pPad.PaddingRight = UDim.new(0, 14)
        pPad.Parent = page

        pages[t.Id] = page
    end

    local syncInputs: { [string]: (number) -> () } = {}

    -- CONSTRUTOR DE COMPONENTES DE UI
    local function CreateSectionHeader(parent: Instance, title: string): TextLabel
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, 0, 0, 22)
        lbl.BackgroundTransparency = 1
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 11
        lbl.TextColor3 = THEME.ACCENT_RED
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Text = title
        lbl.Parent = parent
        return lbl
    end

    local function CreateSliderField(parent: Instance, labelText: string, configKey: string, minVal: number, maxVal: number, defaultVal: number, step: number, subtitleText: string?): Frame
        local span = math.max(maxVal - minVal, 0.0001)
        local safeDefault = tonumber(SimConfig.Get(configKey)) or defaultVal or minVal
        local height = subtitleText and 54 or 46

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
        title.TextSize = 11
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
            sub.TextSize = 9
            sub.TextColor3 = THEME.TEXT_MUTED
            sub.TextXAlignment = Enum.TextXAlignment.Left
            sub.Text = subtitleText
            sub.Parent = rowHeader
        end

        local numInput = Instance.new("TextBox")
        numInput.Size = UDim2.new(0, 60, 0, 20)
        numInput.Position = UDim2.new(1, -60, 0, 2)
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
        track.Position = UDim2.new(0, 8, 0, subtitleText and 38 or 30)
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
            local ok, err = SimConfig.Set(configKey, state)
            if ok then
                toggleBtn.BackgroundColor3 = state and THEME.ACCENT_RED or THEME.BG_WINDOW
                dot.Position = state and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
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
            toggleBtn.BackgroundColor3 = state and THEME.ACCENT_RED or THEME.BG_WINDOW
            dot.Position = state and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
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
        l.TextWrapped = true
        l.Text = "  " .. text
        l.Parent = parent
        AddCorner(l, 5)
        AddStroke(l, THEME.BORDER, 1)
        return l
    end

    -- =========================================================================
    -- [ABA 1] MIRA SIMULADA (AIM SIMULATION)
    -- =========================================================================
    local pageAim = pages["AimSimulation"]

    -- Card Mestre de Ativação
    local masterCard = Instance.new("Frame")
    masterCard.Size = UDim2.new(1, 0, 0, 60)
    masterCard.BackgroundColor3 = THEME.BG_INPUT
    masterCard.Parent = pageAim
    AddCorner(masterCard, 8)
    AddStroke(masterCard, THEME.BORDER, 1)

    local masterTitle = Instance.new("TextLabel")
    masterTitle.Size = UDim2.new(0.65, 0, 0, 22)
    masterTitle.Position = UDim2.new(0, 12, 0, 8)
    masterTitle.BackgroundTransparency = 1
    masterTitle.Font = Enum.Font.GothamBold
    masterTitle.TextSize = 12
    masterTitle.TextColor3 = THEME.TEXT_MAIN
    masterTitle.TextXAlignment = Enum.TextXAlignment.Left
    masterTitle.Text = "SIMULAÇÃO CINEMÁTICA DE MIRA (AIMBOT)"
    masterTitle.Parent = masterCard

    local masterDesc = Instance.new("TextLabel")
    masterDesc.Size = UDim2.new(0.65, 0, 0, 20)
    masterDesc.Position = UDim2.new(0, 12, 0, 30)
    masterDesc.BackgroundTransparency = 1
    masterDesc.Font = Enum.Font.GothamMedium
    masterDesc.TextSize = 10
    masterDesc.TextColor3 = THEME.TEXT_MUTED
    masterDesc.TextXAlignment = Enum.TextXAlignment.Left
    masterDesc.Text = "Rastreamento preditivo de alvos sintéticos com suavização sem jitter."
    masterDesc.Parent = masterCard

    local masterSwitch = Instance.new("TextButton")
    masterSwitch.Size = UDim2.new(0, 150, 0, 34)
    masterSwitch.Position = UDim2.new(1, -162, 0.5, -17)
    masterSwitch.BackgroundColor3 = SimConfig.Get("SimulationActive") and THEME.ACCENT_RED or THEME.BG_WINDOW
    masterSwitch.Font = Enum.Font.GothamBold
    masterSwitch.TextSize = 11
    masterSwitch.TextColor3 = THEME.TEXT_MAIN
    masterSwitch.Text = SimConfig.Get("SimulationActive") and "SIMULAÇÃO: ATIVA" or "SIMULAÇÃO: PAUSADA"
    masterSwitch.Parent = masterCard
    AddCorner(masterSwitch, 6)
    AddStroke(masterSwitch, THEME.BORDER_LIGHT, 1)
    masterSwitch.MouseButton1Click:Connect(function()
        local nextState = not (SimConfig.Get("SimulationActive") == true)
        SimConfig.Set("SimulationActive", nextState)
        masterSwitch.BackgroundColor3 = nextState and THEME.ACCENT_RED or THEME.BG_WINDOW
        masterSwitch.Text = nextState and "SIMULAÇÃO: ATIVA" or "SIMULAÇÃO: PAUSADA"
        DashboardGUI.AddDiagnosticLog("PIPELINE", nextState and "Simulação ativada." or "Simulação pausada.", nextState and "OK" or "WARN")
    end)

    CreateToggleField(pageAim, "Ativar Rastreamento de Mira (Aimbot Ativo)", "AimbotEnabled", SimConfig.Get("AimbotEnabled"))
    CreateToggleField(pageAim, "Considerar Jogadores como Alvos (Ambiente Autorizado)", "AllowPlayerTargets", SimConfig.Get("AllowPlayerTargets"))
    CreateToggleField(pageAim, "Filtrar Somente Alvos com Visada Livre (Visible Only)", "VisibleOnly", SimConfig.Get("VisibleOnly"))
    CreateToggleField(pageAim, "Ignorar Aliados da Mesma Equipe (Team Check)", "TeamCheck", SimConfig.Get("TeamCheck"))
    CreateToggleField(pageAim, "Exibir Círculo de FOV na Tela", "ShowFovCircle", SimConfig.Get("ShowFovCircle"))
    CreateToggleField(pageAim, "Realce Visual de Entidades (Highlights ESP)", "EnableESP", SimConfig.Get("EnableESP"))

    CreateSectionHeader(pageAim, "PARÂMETROS DE RESPOSTA E ALINHAMENTO CINEMÁTICO")
    CreateSliderField(pageAim, "Campo de Visão (FOV °)", "FOV", 10, 180, SimConfig.Get("FOV"), 1, "Sincronizado opticamente com o retículo circular na tela")
    CreateSliderField(pageAim, "Coeficiente de Suavização (Lerp)", "Smoothing", 0.01, 1.0, SimConfig.Get("Smoothing"), 0.01, "0.01 = Instantâneo/Snap | 1.00 = Ultra Suave/Cinemático")
    CreateSliderField(pageAim, "Velocidade Angular Máxima (°/s)", "AngularVelocity", 30, 1200, SimConfig.Get("AngularVelocity"), 10)
    CreateToggleField(pageAim, "Forçar Limite Estrito de Velocidade Angular (Clamp)", "MaxAngularVelocityClamp", SimConfig.Get("MaxAngularVelocityClamp"))
    CreateSliderField(pageAim, "Raio Máximo de Atuação (studs)", "VectorRadius", 10, 500, SimConfig.Get("VectorRadius"), 5)
    CreateSliderField(pageAim, "Tempo de Resposta Simulado (ms)", "ResponseTime", 0, 250, SimConfig.Get("ResponseTime"), 1)

    CreateSectionHeader(pageAim, "MODOS DE ATIVAÇÃO E PRIORIZAÇÃO DE ALVOS")
    -- Seletor AimMode
    local aimModeRow = Instance.new("Frame")
    aimModeRow.Size = UDim2.new(1, 0, 0, 36)
    aimModeRow.BackgroundColor3 = THEME.BG_INPUT
    aimModeRow.BackgroundTransparency = 0.5
    aimModeRow.Parent = pageAim
    AddCorner(aimModeRow, 6)
    AddStroke(aimModeRow, THEME.BORDER, 1)

    local aimModeLbl = Instance.new("TextLabel")
    aimModeLbl.Size = UDim2.new(0, 110, 1, 0)
    aimModeLbl.Position = UDim2.new(0, 10, 0, 0)
    aimModeLbl.BackgroundTransparency = 1
    aimModeLbl.Font = Enum.Font.GothamMedium
    aimModeLbl.TextSize = 11
    aimModeLbl.TextColor3 = THEME.TEXT_MAIN
    aimModeLbl.TextXAlignment = Enum.TextXAlignment.Left
    aimModeLbl.Text = "Modo de Mira:"
    aimModeLbl.Parent = aimModeRow

    local aimModeGrid = Instance.new("Frame")
    aimModeGrid.Size = UDim2.new(1, -125, 0, 24)
    aimModeGrid.Position = UDim2.new(0, 115, 0.5, -12)
    aimModeGrid.BackgroundTransparency = 1
    aimModeGrid.Parent = aimModeRow

    local aimModeLayout = Instance.new("UIGridLayout")
    aimModeLayout.CellSize = UDim2.new(0.31, 0, 1, 0)
    aimModeLayout.CellPadding = UDim2.new(0.035, 0, 0, 0)
    aimModeLayout.Parent = aimModeGrid

    local aimModeButtons: { [string]: TextButton } = {}
    local aimModeOptions = { { Id = "HoldRMB", Label = "Segurar RMB" }, { Id = "Toggle", Label = "Alternar" }, { Id = "AlwaysOn", Label = "Sempre Ativo" } }
    local function UpdateAimModeUI(activeId: string)
        for id, btn in pairs(aimModeButtons) do
            local isSel = (id == activeId)
            btn.BackgroundColor3 = isSel and THEME.ACCENT_RED or THEME.BG_WINDOW
            btn.TextColor3 = isSel and THEME.TEXT_MAIN or THEME.TEXT_MUTED
        end
    end
    for _, opt in ipairs(aimModeOptions) do
        local aBtn = Instance.new("TextButton")
        local isCurrent = (SimConfig.Get("AimMode") or "HoldRMB") == opt.Id
        aBtn.BackgroundColor3 = isCurrent and THEME.ACCENT_RED or THEME.BG_WINDOW
        aBtn.TextColor3 = isCurrent and THEME.TEXT_MAIN or THEME.TEXT_MUTED
        aBtn.Font = Enum.Font.GothamBold
        aBtn.TextSize = 10
        aBtn.Text = opt.Label
        aBtn.Parent = aimModeGrid
        AddCorner(aBtn, 4)
        AddStroke(aBtn, THEME.BORDER, 1)
        aimModeButtons[opt.Id] = aBtn
        aBtn.MouseButton1Click:Connect(function()
            SimConfig.Set("AimMode", opt.Id)
            UpdateAimModeUI(opt.Id)
            DashboardGUI.AddDiagnosticLog("AIM_MODE", "Modo alterado: " .. opt.Label, "INFO")
        end)
    end

    CreateToggleField(pageAim, "Segurar Botão Direito para Focar (Hold to Aim)", "HoldToAim", SimConfig.Get("HoldToAim"))

    -- Prioridade de Alvos
    local prioRow = Instance.new("Frame")
    prioRow.Size = UDim2.new(1, 0, 0, 36)
    prioRow.BackgroundColor3 = THEME.BG_INPUT
    prioRow.BackgroundTransparency = 0.5
    prioRow.Parent = pageAim
    AddCorner(prioRow, 6)
    AddStroke(prioRow, THEME.BORDER, 1)

    local prioLbl = Instance.new("TextLabel")
    prioLbl.Size = UDim2.new(0, 110, 1, 0)
    prioLbl.Position = UDim2.new(0, 10, 0, 0)
    prioLbl.BackgroundTransparency = 1
    prioLbl.Font = Enum.Font.GothamMedium
    prioLbl.TextSize = 11
    prioLbl.TextColor3 = THEME.TEXT_MAIN
    prioLbl.TextXAlignment = Enum.TextXAlignment.Left
    prioLbl.Text = "Prioridade:"
    prioLbl.Parent = prioRow

    local prioGrid = Instance.new("Frame")
    prioGrid.Size = UDim2.new(1, -125, 0, 24)
    prioGrid.Position = UDim2.new(0, 115, 0.5, -12)
    prioGrid.BackgroundTransparency = 1
    prioGrid.Parent = prioRow

    local prioLayout = Instance.new("UIGridLayout")
    prioLayout.CellSize = UDim2.new(0.31, 0, 1, 0)
    prioLayout.CellPadding = UDim2.new(0.035, 0, 0, 0)
    prioLayout.Parent = prioGrid

    local prioButtons: { [string]: TextButton } = {}
    local prioOptions = { { Id = "Crosshair", Label = "Mira" }, { Id = "Distance", Label = "Distância" }, { Id = "LowestHealth", Label = "Menor Vida" } }
    local function UpdatePrioUI(activeId: string)
        for id, btn in pairs(prioButtons) do
            local isSel = (id == activeId)
            btn.BackgroundColor3 = isSel and THEME.ACCENT_RED or THEME.BG_WINDOW
            btn.TextColor3 = isSel and THEME.TEXT_MAIN or THEME.TEXT_MUTED
        end
    end
    for _, opt in ipairs(prioOptions) do
        local pBtn = Instance.new("TextButton")
        local isCurrent = (SimConfig.Get("TargetPriority") or "Crosshair") == opt.Id
        pBtn.BackgroundColor3 = isCurrent and THEME.ACCENT_RED or THEME.BG_WINDOW
        pBtn.TextColor3 = isCurrent and THEME.TEXT_MAIN or THEME.TEXT_MUTED
        pBtn.Font = Enum.Font.GothamBold
        pBtn.TextSize = 10
        pBtn.Text = opt.Label
        pBtn.Parent = prioGrid
        AddCorner(pBtn, 4)
        AddStroke(pBtn, THEME.BORDER, 1)
        prioButtons[opt.Id] = pBtn
        pBtn.MouseButton1Click:Connect(function()
            SimConfig.Set("TargetPriority", opt.Id)
            UpdatePrioUI(opt.Id)
            DashboardGUI.AddDiagnosticLog("TARGETING", "Prioridade alterada: " .. opt.Label, "INFO")
        end)
    end

    CreateSliderField(pageAim, "Persistência no Alvo (Target Stickiness s)", "TargetStickiness", 0.05, 1.0, SimConfig.Get("TargetStickiness"), 0.05)
    CreateToggleField(pageAim, "Simular Micro-Variações Orgânicas (Perlin Jitter)", "SimulateJitter", SimConfig.Get("SimulateJitter"))
    CreateSliderField(pageAim, "Intensidade do Jitter (%)", "Intensity", 0, 100, SimConfig.Get("Intensity"), 5)
    CreateSliderField(pageAim, "Curva de Aceleração (Hermite Exponent)", "AccelerationCurve", 0.2, 3.0, SimConfig.Get("AccelerationCurve"), 0.05)

    CreateSectionHeader(pageAim, "REGIÃO ANATÔMICA PRIORITÁRIA (HITBOX)")
    local boneRow = Instance.new("Frame")
    boneRow.Size = UDim2.new(1, 0, 0, 36)
    boneRow.BackgroundColor3 = THEME.BG_INPUT
    boneRow.BackgroundTransparency = 0.5
    boneRow.Parent = pageAim
    AddCorner(boneRow, 6)
    AddStroke(boneRow, THEME.BORDER, 1)

    local boneLbl = Instance.new("TextLabel")
    boneLbl.Size = UDim2.new(0, 110, 1, 0)
    boneLbl.Position = UDim2.new(0, 10, 0, 0)
    boneLbl.BackgroundTransparency = 1
    boneLbl.Font = Enum.Font.GothamMedium
    boneLbl.TextSize = 11
    boneLbl.TextColor3 = THEME.TEXT_MAIN
    boneLbl.TextXAlignment = Enum.TextXAlignment.Left
    boneLbl.Text = "Região Ativa:"
    boneLbl.Parent = boneRow

    local boneGrid = Instance.new("Frame")
    boneGrid.Size = UDim2.new(1, -125, 0, 24)
    boneGrid.Position = UDim2.new(0, 115, 0.5, -12)
    boneGrid.BackgroundTransparency = 1
    boneGrid.Parent = boneRow

    local boneLayout = Instance.new("UIGridLayout")
    boneLayout.CellSize = UDim2.new(0.23, 0, 1, 0)
    boneLayout.CellPadding = UDim2.new(0.026, 0, 0, 0)
    boneLayout.Parent = boneGrid

    local boneButtons: { [string]: TextButton } = {}
    local boneOptions = { { Id = "Head", Label = "Cabeça" }, { Id = "Torso", Label = "Tronco" }, { Id = "Arms", Label = "Braços" }, { Id = "Legs", Label = "Pernas" } }
    local function UpdateBoneUI(activeId: string)
        for id, btn in pairs(boneButtons) do
            local isSel = (id == activeId)
            btn.BackgroundColor3 = isSel and THEME.ACCENT_RED or THEME.BG_WINDOW
            btn.TextColor3 = isSel and THEME.TEXT_MAIN or THEME.TEXT_MUTED
        end
    end
    for _, opt in ipairs(boneOptions) do
        local bBtn = Instance.new("TextButton")
        local isCurrent = (SimConfig.Get("TargetRegion") or "Head") == opt.Id
        bBtn.BackgroundColor3 = isCurrent and THEME.ACCENT_RED or THEME.BG_WINDOW
        bBtn.TextColor3 = isCurrent and THEME.TEXT_MAIN or THEME.TEXT_MUTED
        bBtn.Font = Enum.Font.GothamBold
        bBtn.TextSize = 10
        bBtn.Text = opt.Label
        bBtn.Parent = boneGrid
        AddCorner(bBtn, 4)
        AddStroke(bBtn, THEME.BORDER, 1)
        boneButtons[opt.Id] = bBtn
        bBtn.MouseButton1Click:Connect(function()
            SimConfig.Set("TargetRegion", opt.Id)
            UpdateBoneUI(opt.Id)
            DashboardGUI.AddDiagnosticLog("HITBOX", "Região anatômica: " .. opt.Label, "INFO")
        end)
    end

    -- =========================================================================
    -- [ABA 2] DISPAROS SIMULADOS (SILENT AIM)
    -- =========================================================================
    local pageSilent = pages["SilentAim"]

    CreateSectionHeader(pageSilent, "SIMULAÇÃO DE DISPAROS DESACOPLADOS (SILENT AIM)")
    CreateToggleField(pageSilent, "Ativar Simulação de Silent Aim (Vetor Desacoplado)", "SilentAimEnabled", SimConfig.Get("SilentAimEnabled"))
    CreateSliderField(pageSilent, "Silent Aim - Campo de Redirecionamento (FOV °)", "SilentAimFOV", 5, 90, SimConfig.Get("SilentAimFOV"), 1, "Cone angular máximo permitido para redirecionamento do tiro")
    CreateSliderField(pageSilent, "Probabilidade de Acerto do Silent Aim (%)", "SilentAimHitChance", 10, 100, SimConfig.Get("SilentAimHitChance"), 5, "100% = Acerto determinístico | <100% = Dispersão probabilística")
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

    -- Linha 1: Estado do Módulo e Etapa Atual
    local pStatus1 = Instance.new("TextLabel")
    pStatus1.Size = UDim2.new(0.5, -10, 0, 16)
    pStatus1.Position = UDim2.new(0, 8, 0, 44)
    pStatus1.BackgroundTransparency = 1
    pStatus1.Font = Enum.Font.GothamMedium
    pStatus1.TextSize = 10
    pStatus1.TextColor3 = THEME.TEXT_MUTED
    pStatus1.TextXAlignment = Enum.TextXAlignment.Left
    pStatus1.Text = "Módulo: CARREGADO"
    pStatus1.Parent = pipelineCard
    TelemetryLabels["SilentAimStatus"] = pStatus1

    local pCurrentStage = Instance.new("TextLabel")
    pCurrentStage.Size = UDim2.new(0.5, -10, 0, 16)
    pCurrentStage.Position = UDim2.new(0.5, 0, 0, 44)
    pCurrentStage.BackgroundTransparency = 1
    pCurrentStage.Font = Enum.Font.GothamMedium
    pCurrentStage.TextSize = 10
    pCurrentStage.TextColor3 = THEME.INFO
    pCurrentStage.TextXAlignment = Enum.TextXAlignment.Right
    pCurrentStage.Text = "Etapa: PRONTO"
    pCurrentStage.Parent = pipelineCard
    TelemetryLabels["SilentAimStage"] = pCurrentStage

    -- Linha 2: Resultado do Último Disparo
    local pStatus2 = Instance.new("TextLabel")
    pStatus2.Size = UDim2.new(1, -16, 0, 18)
    pStatus2.Position = UDim2.new(0, 8, 0, 64)
    pStatus2.BackgroundTransparency = 1
    pStatus2.Font = Enum.Font.GothamBold
    pStatus2.TextSize = 10.5
    pStatus2.TextColor3 = THEME.TEXT_MUTED
    pStatus2.TextXAlignment = Enum.TextXAlignment.Left
    pStatus2.Text = "Último Disparo: NENHUM DISPARO EFETUADO"
    pStatus2.Parent = pipelineCard
    TelemetryLabels["LastShotStatus"] = pStatus2

    -- Linha 3: Detalhes Físicos / Impacto
    local pDetails = Instance.new("TextLabel")
    pDetails.Size = UDim2.new(1, -16, 0, 16)
    pDetails.Position = UDim2.new(0, 8, 0, 84)
    pDetails.BackgroundTransparency = 1
    pDetails.Font = Enum.Font.Code
    pDetails.TextSize = 9
    pDetails.TextColor3 = THEME.TEXT_MUTED
    pDetails.TextXAlignment = Enum.TextXAlignment.Left
    pDetails.Text = "Impacto: — | Parte: — | Desvio: — | Distância: —"
    pDetails.Parent = pipelineCard
    TelemetryLabels["SilentAimDetails"] = pDetails

    -- Linha 4: Causa da Falha / Diagnóstico
    local pFailureReason = Instance.new("TextLabel")
    pFailureReason.Size = UDim2.new(1, -16, 0, 16)
    pFailureReason.Position = UDim2.new(0, 8, 0, 102)
    pFailureReason.BackgroundTransparency = 1
    pFailureReason.Font = Enum.Font.GothamMedium
    pFailureReason.TextSize = 9
    pFailureReason.TextColor3 = THEME.TEXT_MUTED
    pFailureReason.TextXAlignment = Enum.TextXAlignment.Left
    pFailureReason.Text = "Diagnóstico: Aguardando execução do teste funcional."
    pFailureReason.Parent = pipelineCard
    TelemetryLabels["SilentAimReason"] = pFailureReason

    -- Linha de Ações Principais (Disparo de Teste + Spawn Dummy com Debounce)
    local shotActionRow = Instance.new("Frame")
    shotActionRow.Size = UDim2.new(1, 0, 0, 36)
    shotActionRow.BackgroundTransparency = 1
    shotActionRow.Parent = pageSilent

    local isShotTesting = false
    local testShotBtn = Instance.new("TextButton")
    testShotBtn.Size = UDim2.new(0.68, -4, 1, 0)
    testShotBtn.Position = UDim2.new(0, 0, 0, 0)
    testShotBtn.BackgroundColor3 = THEME.ACCENT_RED
    testShotBtn.TextColor3 = THEME.TEXT_MAIN
    testShotBtn.Font = Enum.Font.GothamBold
    testShotBtn.TextSize = 10.5
    testShotBtn.Text = "🎯 DISPARAR TESTE SILENT AIM (5 ETAPAS)"
    testShotBtn.Parent = shotActionRow
    AddCorner(testShotBtn, 6)
    AddStroke(testShotBtn, THEME.BORDER_LIGHT, 1)

    local spawnDummyBtn = Instance.new("TextButton")
    spawnDummyBtn.Size = UDim2.new(0.32, -4, 1, 0)
    spawnDummyBtn.Position = UDim2.new(0.68, 4, 0, 0)
    spawnDummyBtn.BackgroundColor3 = THEME.BG_INPUT
    spawnDummyBtn.TextColor3 = THEME.TEXT_MAIN
    spawnDummyBtn.Font = Enum.Font.GothamBold
    spawnDummyBtn.TextSize = 10
    spawnDummyBtn.Text = "🤖 SPAWN DUMMY"
    spawnDummyBtn.Parent = shotActionRow
    AddCorner(spawnDummyBtn, 6)
    AddStroke(spawnDummyBtn, THEME.BORDER, 1)

    testShotBtn.MouseButton1Click:Connect(function()
        if isShotTesting then return end
        isShotTesting = true
        testShotBtn.Text = "⏳ EXECUTANDO PIPELINE (5 ETAPAS)..."
        testShotBtn.BackgroundColor3 = THEME.BORDER
        task.defer(function()
            if DashboardGUI.OnSimulateSilentAimShot then
                DashboardGUI.OnSimulateSilentAimShot()
            end
            task.wait(0.35)
            testShotBtn.Text = "🎯 DISPARAR TESTE SILENT AIM (5 ETAPAS)"
            testShotBtn.BackgroundColor3 = THEME.ACCENT_RED
            isShotTesting = false
        end)
    end)

    spawnDummyBtn.MouseButton1Click:Connect(function()
        if DashboardGUI.OnSpawnTestDummy then
            DashboardGUI.OnSpawnTestDummy()
        end
    end)

    -- Grade de Cenários Reproduzíveis de Disparo
    CreateSectionHeader(pageSilent, "CENÁRIOS REPRODUZÍVEIS DE DISPARO (TESTES FUNCIONAIS)")
    local shotScenarioGrid = Instance.new("Frame")
    shotScenarioGrid.Size = UDim2.new(1, 0, 0, 0)
    shotScenarioGrid.AutomaticSize = Enum.AutomaticSize.Y
    shotScenarioGrid.BackgroundTransparency = 1
    shotScenarioGrid.Parent = pageSilent

    local ssgLayout = Instance.new("UIGridLayout")
    ssgLayout.CellSize = UDim2.new(0.485, 0, 0, 28)
    ssgLayout.CellPadding = UDim2.new(0.03, 0, 0, 6)
    ssgLayout.Parent = shotScenarioGrid

    for _, sc in ipairs(ScenarioRunner.ShotScenarios) do
        local scBtn = Instance.new("TextButton")
        scBtn.BackgroundColor3 = THEME.BG_INPUT
        scBtn.Font = Enum.Font.GothamMedium
        scBtn.TextSize = 9.5
        scBtn.TextColor3 = THEME.TEXT_MAIN
        scBtn.Text = "▶ " .. sc.Label
        scBtn.Parent = shotScenarioGrid
        AddCorner(scBtn, 5)
        AddStroke(scBtn, THEME.BORDER, 1)

        scBtn.MouseButton1Click:Connect(function()
            if isShotTesting then return end
            isShotTesting = true
            scBtn.TextColor3 = THEME.INFO
            task.defer(function()
                if DashboardGUI.OnRunShotScenario then
                    DashboardGUI.OnRunShotScenario(sc.Id)
                end
                task.wait(0.35)
                scBtn.TextColor3 = THEME.TEXT_MAIN
                isShotTesting = false
            end)
        end)
    end

    -- =========================================================================
    -- [ABA 3] BALÍSTICA (BALLISTICS & PHYSICS)
    -- =========================================================================
    local pageBallistics = pages["Ballistics"]

    CreateSectionHeader(pageBallistics, "FÍSICA BALÍSTICA E TRAJETÓRIA DE PROJÉTEIS")

    -- Seletor de Modelo Balístico
    local projTypeRow = Instance.new("Frame")
    projTypeRow.Size = UDim2.new(1, 0, 0, 36)
    projTypeRow.BackgroundColor3 = THEME.BG_INPUT
    projTypeRow.BackgroundTransparency = 0.5
    projTypeRow.Parent = pageBallistics
    AddCorner(projTypeRow, 6)
    AddStroke(projTypeRow, THEME.BORDER, 1)

    local projTypeLbl = Instance.new("TextLabel")
    projTypeLbl.Size = UDim2.new(0, 110, 1, 0)
    projTypeLbl.Position = UDim2.new(0, 10, 0, 0)
    projTypeLbl.BackgroundTransparency = 1
    projTypeLbl.Font = Enum.Font.GothamMedium
    projTypeLbl.TextSize = 11
    projTypeLbl.TextColor3 = THEME.TEXT_MAIN
    projTypeLbl.TextXAlignment = Enum.TextXAlignment.Left
    projTypeLbl.Text = "Modelo Balístico:"
    projTypeLbl.Parent = projTypeRow

    local projGrid = Instance.new("Frame")
    projGrid.Size = UDim2.new(1, -125, 0, 24)
    projGrid.Position = UDim2.new(0, 115, 0.5, -12)
    projGrid.BackgroundTransparency = 1
    projGrid.Parent = projTypeRow

    local projLayout = Instance.new("UIGridLayout")
    projLayout.CellSize = UDim2.new(0.48, 0, 1, 0)
    projLayout.CellPadding = UDim2.new(0.04, 0, 0, 0)
    projLayout.Parent = projGrid

    local projButtons: { [string]: TextButton } = {}
    local projOptions = { { Id = "Instant", Label = "Instantâneo (Raycast)" }, { Id = "Physics", Label = "Físico (Gravidade/Arco)" } }
    local function UpdateProjTypeUI(activeId: string)
        for id, btn in pairs(projButtons) do
            local isSel = (id == activeId)
            btn.BackgroundColor3 = isSel and THEME.ACCENT_RED or THEME.BG_WINDOW
            btn.TextColor3 = isSel and THEME.TEXT_MAIN or THEME.TEXT_MUTED
        end
    end
    for _, opt in ipairs(projOptions) do
        local prBtn = Instance.new("TextButton")
        local isCurrent = (SimConfig.Get("ProjectileType") or "Instant") == opt.Id
        prBtn.BackgroundColor3 = isCurrent and THEME.ACCENT_RED or THEME.BG_WINDOW
        prBtn.TextColor3 = isCurrent and THEME.TEXT_MAIN or THEME.TEXT_MUTED
        prBtn.Font = Enum.Font.GothamBold
        prBtn.TextSize = 10
        prBtn.Text = opt.Label
        prBtn.Parent = projGrid
        AddCorner(prBtn, 4)
        AddStroke(prBtn, THEME.BORDER, 1)
        projButtons[opt.Id] = prBtn
        prBtn.MouseButton1Click:Connect(function()
            SimConfig.Set("ProjectileType", opt.Id)
            UpdateProjTypeUI(opt.Id)
            DashboardGUI.AddDiagnosticLog("BALLISTICS", "Modelo balístico: " .. opt.Label, "INFO")
        end)
    end

    CreateSliderField(pageBallistics, "Velocidade Balística Simulada (studs/s)", "ProjectileSpeed", 100, 3000, SimConfig.Get("ProjectileSpeed"), 50)
    CreateSliderField(pageBallistics, "Gravidade de Projétil Físico (studs/s²)", "ProjectileGravity", 0, 500, SimConfig.Get("ProjectileGravity"), 10, "Padrão Roblox = 196.2 studs/s² | Gravidade zero = 0")
    CreateToggleField(pageBallistics, "Compensação de Queda por Gravidade (Bullet Drop)", "ProjectileDropComp", SimConfig.Get("ProjectileDropComp"))
    CreateToggleField(pageBallistics, "Ativar Predição Balística de Alvo (Lead Tracking)", "EnableLead", SimConfig.Get("EnableLead"))

    local ballisticsInfoCard = Instance.new("Frame")
    ballisticsInfoCard.Size = UDim2.new(1, 0, 0, 70)
    ballisticsInfoCard.BackgroundColor3 = THEME.BG_INPUT
    ballisticsInfoCard.Parent = pageBallistics
    AddCorner(ballisticsInfoCard, 6)
    AddStroke(ballisticsInfoCard, THEME.BORDER, 1)

    local bTitle = Instance.new("TextLabel")
    bTitle.Size = UDim2.new(1, -16, 0, 18)
    bTitle.Position = UDim2.new(0, 8, 0, 6)
    bTitle.BackgroundTransparency = 1
    bTitle.Font = Enum.Font.GothamBold
    bTitle.TextSize = 10
    bTitle.TextColor3 = THEME.TEXT_MAIN
    bTitle.TextXAlignment = Enum.TextXAlignment.Left
    bTitle.Text = "TELEMETRIA BALÍSTICA E QUEDA PARABÓLICA:"
    bTitle.Parent = ballisticsInfoCard

    local bDesc = Instance.new("TextLabel")
    bDesc.Size = UDim2.new(1, -16, 0, 36)
    bDesc.Position = UDim2.new(0, 8, 0, 26)
    bDesc.BackgroundTransparency = 1
    bDesc.Font = Enum.Font.Code
    bDesc.TextSize = 9
    bDesc.TextColor3 = THEME.TEXT_MUTED
    bDesc.TextXAlignment = Enum.TextXAlignment.Left
    bDesc.Text = "Fórmula: Delta_Y = 0.5 * g * (d / v0)²  |  Trajetória segmentada em 10 arcos sob aceleração vetorial vertical."
    bDesc.Parent = ballisticsInfoCard

    -- =========================================================================
    -- [ABA 4] DIAGNÓSTICO & ASSISTENTE INTELIGENTE (IA)
    -- =========================================================================
    local pageDiag = pages["Diagnostics"]

    CreateSectionHeader(pageDiag, "AÇÕES DE DIAGNÓSTICO E AUDITORIA DO SISTEMA")

    -- Botões de Ação Global de Diagnóstico
    local diagActionRow = Instance.new("Frame")
    diagActionRow.Size = UDim2.new(1, 0, 0, 34)
    diagActionRow.BackgroundTransparency = 1
    diagActionRow.Parent = pageDiag

    local runDiagBtn = Instance.new("TextButton")
    runDiagBtn.Size = UDim2.new(0.5, -4, 1, 0)
    runDiagBtn.Position = UDim2.new(0, 0, 0, 0)
    runDiagBtn.BackgroundColor3 = THEME.ACCENT_RED
    runDiagBtn.TextColor3 = THEME.TEXT_MAIN
    runDiagBtn.Font = Enum.Font.GothamBold
    runDiagBtn.TextSize = 10.5
    runDiagBtn.Text = "🩺 EXECUTAR DIAGNÓSTICO COMPLETO"
    runDiagBtn.Parent = diagActionRow
    AddCorner(runDiagBtn, 6)
    AddStroke(runDiagBtn, THEME.BORDER_LIGHT, 1)

    local runShotBtn = Instance.new("TextButton")
    runShotBtn.Size = UDim2.new(0.5, -4, 1, 0)
    runShotBtn.Position = UDim2.new(0.5, 4, 0, 0)
    runShotBtn.BackgroundColor3 = THEME.BG_INPUT
    runShotBtn.TextColor3 = THEME.TEXT_MAIN
    runShotBtn.Font = Enum.Font.GothamBold
    runShotBtn.TextSize = 10.5
    runShotBtn.Text = "🎯 TESTAR DISPARO SILENT AIM"
    runShotBtn.Parent = diagActionRow
    AddCorner(runShotBtn, 6)
    AddStroke(runShotBtn, THEME.BORDER, 1)

    -- Card com Status dos Módulos
    local moduleStatusCard = Instance.new("Frame")
    moduleStatusCard.Size = UDim2.new(1, 0, 0, 52)
    moduleStatusCard.BackgroundColor3 = THEME.BG_INPUT
    moduleStatusCard.Parent = pageDiag
    AddCorner(moduleStatusCard, 6)
    AddStroke(moduleStatusCard, THEME.BORDER, 1)

    local msPad = Instance.new("UIPadding")
    msPad.PaddingTop = UDim.new(0, 4)
    msPad.PaddingBottom = UDim.new(0, 4)
    msPad.PaddingLeft = UDim.new(0, 6)
    msPad.PaddingRight = UDim.new(0, 6)
    msPad.Parent = moduleStatusCard

    local msLayout = Instance.new("UIGridLayout")
    msLayout.CellSize = UDim2.new(0.24, 0, 1, 0)
    msLayout.CellPadding = UDim2.new(0.013, 0, 0, 0)
    msLayout.Parent = moduleStatusCard

    local function MakeModuleBadge(modName: string, initialStatus: string, labelKey: string)
        local box = Instance.new("Frame")
        box.BackgroundColor3 = THEME.BG_WINDOW
        box.Parent = moduleStatusCard
        AddCorner(box, 4)
        AddStroke(box, THEME.BORDER, 1)

        local t1 = Instance.new("TextLabel")
        t1.Size = UDim2.new(1, -6, 0, 16)
        t1.Position = UDim2.new(0, 4, 0, 3)
        t1.BackgroundTransparency = 1
        t1.Font = Enum.Font.GothamBold
        t1.TextSize = 9
        t1.TextColor3 = THEME.TEXT_MAIN
        t1.TextXAlignment = Enum.TextXAlignment.Left
        t1.Text = modName
        t1.Parent = box

        local t2 = Instance.new("TextLabel")
        t2.Size = UDim2.new(1, -6, 0, 18)
        t2.Position = UDim2.new(0, 4, 0, 20)
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

    CreateSectionHeader(pageDiag, "ASSISTENTE INTELIGENTE & CHATBOT DE DIAGNÓSTICO")

    -- Chatbot UI Container
    local chatCard = Instance.new("Frame")
    chatCard.Size = UDim2.new(1, 0, 0, 220)
    chatCard.BackgroundColor3 = THEME.BG_INPUT
    chatCard.Parent = pageDiag
    AddCorner(chatCard, 8)
    AddStroke(chatCard, THEME.BORDER, 1)

    -- Botões de Ação Rápida
    local quickBtnGrid = Instance.new("Frame")
    quickBtnGrid.Size = UDim2.new(1, -16, 0, 26)
    quickBtnGrid.Position = UDim2.new(0, 8, 0, 8)
    quickBtnGrid.BackgroundTransparency = 1
    quickBtnGrid.Parent = chatCard

    local qbLayout = Instance.new("UIGridLayout")
    qbLayout.CellSize = UDim2.new(0.24, 0, 1, 0)
    qbLayout.CellPadding = UDim2.new(0.013, 0, 0, 0)
    qbLayout.Parent = quickBtnGrid

    local chatResponseBox = Instance.new("TextLabel")
    chatResponseBox.Size = UDim2.new(1, -16, 0, 120)
    chatResponseBox.Position = UDim2.new(0, 8, 0, 42)
    chatResponseBox.BackgroundColor3 = THEME.BG_WINDOW
    chatResponseBox.Font = Enum.Font.GothamMedium
    chatResponseBox.TextSize = 10
    chatResponseBox.TextColor3 = THEME.TEXT_MAIN
    chatResponseBox.TextXAlignment = Enum.TextXAlignment.Left
    chatResponseBox.TextYAlignment = Enum.TextYAlignment.Top
    chatResponseBox.TextWrapped = true
    chatResponseBox.Text = "  Assistente DeepHat pronto para responder. Selecione um diagnóstico rápido ou faça uma pergunta abaixo."
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

    MakeQuickButton("🔍 Analisar Saúde", "analisar status e erros do simulador")
    MakeQuickButton("🎯 Testar Mira", "por que a mira não foca no alvo?")
    MakeQuickButton("⚡ Testar Balística", "como calibrar gravidade e tempo de voo?")
    MakeQuickButton("🛡️ Verificar Visada", "alvo está bloqueado ou ocluído?")

    runDiagBtn.MouseButton1Click:Connect(function()
        TriggerChatQuery("executar diagnóstico completo e status operacional de todos os módulos")
    end)
    runShotBtn.MouseButton1Click:Connect(function()
        if DashboardGUI.OnSimulateSilentAimShot then
            DashboardGUI.OnSimulateSilentAimShot()
        end
    end)

    -- Input Row do Chatbot
    local chatInputRow = Instance.new("Frame")
    chatInputRow.Size = UDim2.new(1, -16, 0, 32)
    chatInputRow.Position = UDim2.new(0, 8, 1, -40)
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
    chatSendBtn.BackgroundColor3 = THEME.ACCENT_RED
    chatSendBtn.Font = Enum.Font.GothamBold
    chatSendBtn.TextSize = 11
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

    -- Seção de Cenários de Linha de Visada (LOS)
    CreateSectionHeader(pageDiag, "CENÁRIOS DE LINHA DE VISADA (LINE OF SIGHT)")
    LosLabels["Status"] = MakeInfoLabel(pageDiag, "Última consulta: (nenhuma)", THEME.TEXT_MUTED, 24)
    LosLabels["Reason"] = MakeInfoLabel(pageDiag, "Causa: —", THEME.TEXT_MUTED, 22)
    LosLabels["Blocker"] = MakeInfoLabel(pageDiag, "Obstrução: —", THEME.TEXT_MUTED, 22)
    LosLabels["Distance"] = MakeInfoLabel(pageDiag, "Distância da colisão: —", THEME.TEXT_MUTED, 22)

    local function MakeButtonGrid(parent: Instance, cellW: number): Frame
        local grid = Instance.new("Frame")
        grid.Size = UDim2.new(1, 0, 0, 0)
        grid.AutomaticSize = Enum.AutomaticSize.Y
        grid.BackgroundTransparency = 1
        grid.Parent = parent
        local layout = Instance.new("UIGridLayout")
        layout.CellSize = UDim2.new(0, cellW, 0, 26)
        layout.CellPadding = UDim2.new(0, 6, 0, 6)
        layout.Parent = grid
        return grid
    end

    local function MakeGridButton(grid: Instance, text: string, onClick: () -> ())
        local b = Instance.new("TextButton")
        b.BackgroundColor3 = THEME.BG_INPUT
        b.Font = Enum.Font.GothamMedium
        b.TextSize = 10
        b.TextColor3 = THEME.TEXT_MAIN
        b.TextWrapped = true
        b.Text = text
        b.Parent = grid
        AddCorner(b, 5)
        AddStroke(b, THEME.BORDER, 1)
        b.MouseButton1Click:Connect(onClick)
    end

    local scenarioGrid = MakeButtonGrid(pageDiag, 150)
    for _, sc in ipairs(ScenarioRunner.Scenarios) do
        MakeGridButton(scenarioGrid, "▶ " .. sc.Label, function()
            if DashboardGUI.OnRunLosScenario then DashboardGUI.OnRunLosScenario(sc.Id) end
        end)
    end
    MakeGridButton(scenarioGrid, "🗑 Limpar Histórico", function()
        if DashboardGUI.OnClearLosHistory then DashboardGUI.OnClearLosHistory() end
        if LosHistoryList then
            for _, ch in ipairs(LosHistoryList:GetChildren()) do
                if ch:IsA("TextLabel") then ch:Destroy() end
            end
        end
    end)

    local losHistory = Instance.new("ScrollingFrame")
    losHistory.Size = UDim2.new(1, 0, 0, 110)
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

    -- Log de Diagnósticos em Tempo Real com Filtros de Nível
    local logHeaderFrame = Instance.new("Frame")
    logHeaderFrame.Size = UDim2.new(1, 0, 0, 26)
    logHeaderFrame.BackgroundTransparency = 1
    logHeaderFrame.Parent = pageDiag

    local logTitle = Instance.new("TextLabel")
    logTitle.Size = UDim2.new(0, 220, 1, 0)
    logTitle.BackgroundTransparency = 1
    logTitle.Font = Enum.Font.GothamBold
    logTitle.TextSize = 11
    logTitle.TextColor3 = THEME.TEXT_MUTED
    logTitle.TextXAlignment = Enum.TextXAlignment.Left
    logTitle.Text = "LOG DE EVENTOS EM TEMPO REAL"
    logTitle.Parent = logHeaderFrame

    local filterBar = Instance.new("Frame")
    filterBar.Size = UDim2.new(1, -225, 1, 0)
    filterBar.Position = UDim2.new(0, 225, 0, 0)
    filterBar.BackgroundTransparency = 1
    filterBar.Parent = logHeaderFrame

    local filterLayout = Instance.new("UIListLayout")
    filterLayout.FillDirection = Enum.FillDirection.Horizontal
    filterLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    filterLayout.Padding = UDim.new(0, 4)
    filterLayout.Parent = filterBar

    local filterButtons: { [string]: TextButton } = {}
    local filterOptions = { "TODOS", "OK", "INFO", "WARN", "FAIL" }

    local function SetActiveFilter(flt: string)
        currentLogFilter = flt
        for opt, btn in pairs(filterButtons) do
            if opt == flt then
                btn.BackgroundColor3 = THEME.ACCENT_RED
                btn.TextColor3 = THEME.TEXT_MAIN
            else
                btn.BackgroundColor3 = THEME.BG_INPUT
                btn.TextColor3 = THEME.TEXT_MUTED
            end
        end
        ApplyLogFilter()
    end

    for _, opt in ipairs(filterOptions) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 52, 0, 22)
        btn.BackgroundColor3 = (opt == "TODOS") and THEME.ACCENT_RED or THEME.BG_INPUT
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 9
        btn.TextColor3 = (opt == "TODOS") and THEME.TEXT_MAIN or THEME.TEXT_MUTED
        btn.Text = opt
        btn.Parent = filterBar
        AddCorner(btn, 4)
        AddStroke(btn, THEME.BORDER, 1)
        filterButtons[opt] = btn
        btn.MouseButton1Click:Connect(function()
            SetActiveFilter(opt)
        end)
    end

    local eventLogList = Instance.new("ScrollingFrame")
    eventLogList.Size = UDim2.new(1, 0, 0, 120)
    eventLogList.BackgroundColor3 = THEME.BG_WINDOW
    eventLogList.ScrollBarThickness = 4
    eventLogList.CanvasSize = UDim2.new(0, 0, 0, 0)
    eventLogList.AutomaticCanvasSize = Enum.AutomaticSize.Y
    eventLogList.Parent = pageDiag
    AddCorner(eventLogList, 6)
    AddStroke(eventLogList, THEME.BORDER, 1)
    local evListLayout = Instance.new("UIListLayout")
    evListLayout.Padding = UDim.new(0, 2)
    evListLayout.Parent = eventLogList
    EventLogListInstance = eventLogList

    -- =========================================================================
    -- [ABA 5] CONFIGURAÇÕES & PERFIS (SETTINGS)
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

    CreateSectionHeader(pageSettings, "PERSISTÊNCIA E EXPORTAÇÃO JSON")
    local cfgBtnGrid = MakeButtonGrid(pageSettings, 150)
    MakeGridButton(cfgBtnGrid, "💾 Salvar Configuração", function()
        local saved = SimConfig.Save()
        DashboardGUI.AddDiagnosticLog("CONFIG", saved and "Configurações persistidas." or "Persistência indisponível.", saved and "OK" or "WARN")
        if DashboardGUI.OnSaveRequested then DashboardGUI.OnSaveRequested() end
    end)
    MakeGridButton(cfgBtnGrid, "↺ Restaurar Padrões", function()
        SimConfig.RestoreDefaults("Restaurar padrões (Settings)")
        UpdateProfileUI(SimConfig.DefaultProfileName)
        DashboardGUI.AddDiagnosticLog("CONFIG", "Configurações restauradas.", "WARN")
        if DashboardGUI.OnResetRequested then DashboardGUI.OnResetRequested() end
    end)
    MakeGridButton(cfgBtnGrid, "📤 Exportar JSON", function()
        local json = SimConfig.ExportJSON()
        pcall(function()
            if setclipboard then
                setclipboard(json)
                DashboardGUI.AddDiagnosticLog("CONFIG", "JSON copiado para a área de transferência!", "OK")
            else
                DashboardGUI.AddDiagnosticLog("CONFIG", "JSON gerado no console.", "INFO")
                print("\n[DeepHat SimConfig JSON Export]\n" .. json)
            end
        end)
    end)

    local importBox = Instance.new("TextBox")
    importBox.Size = UDim2.new(1, 0, 0, 50)
    importBox.BackgroundColor3 = THEME.BG_WINDOW
    importBox.TextColor3 = THEME.TEXT_MAIN
    importBox.PlaceholderText = "Cole aqui o JSON para importar configurações..."
    importBox.PlaceholderColor3 = THEME.TEXT_MUTED
    importBox.Font = Enum.Font.Code
    importBox.TextSize = 10
    importBox.TextWrapped = true
    importBox.ClearTextOnFocus = false
    importBox.MultiLine = true
    importBox.TextXAlignment = Enum.TextXAlignment.Left
    importBox.TextYAlignment = Enum.TextYAlignment.Top
    importBox.Parent = pageSettings
    AddCorner(importBox, 5)
    AddStroke(importBox, THEME.BORDER, 1)

    local importBtn = Instance.new("TextButton")
    importBtn.Size = UDim2.new(0, 160, 0, 28)
    importBtn.BackgroundColor3 = THEME.BG_INPUT
    importBtn.Font = Enum.Font.GothamBold
    importBtn.TextSize = 10
    importBtn.TextColor3 = THEME.TEXT_MAIN
    importBtn.Text = "⬇ IMPORTAR JSON (VALIDADO)"
    importBtn.Parent = pageSettings
    AddCorner(importBtn, 5)
    AddStroke(importBtn, THEME.BORDER, 1)
    importBtn.MouseButton1Click:Connect(function()
        local ok, errors = SimConfig.ImportJSON(importBox.Text)
        if ok then
            DashboardGUI.AddDiagnosticLog("CONFIG", "Importação validada e aplicada.", "OK")
        else
            DashboardGUI.AddDiagnosticLog("CONFIG", "Importação rejeitada: " .. table.concat(errors, "; "):sub(1, 160), "WARN")
        end
    end)

    -- Aba Inicial
    local startTab = tostring(SimConfig.Get("ActiveTab") or "AimSimulation")
    if pages[startTab] then SwitchTab(startTab) else SwitchTab("AimSimulation") end

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
        masterSwitch.BackgroundColor3 = THEME.ACCENT_RED
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
            masterSwitch.BackgroundColor3 = active and THEME.ACCENT_RED or THEME.BG_WINDOW
            masterSwitch.Text = active and "SIMULAÇÃO: ATIVA" or "SIMULAÇÃO: PAUSADA"
            if FovCircleInstance then
                FovCircleInstance.Visible = active and (SimConfig.Get("ShowFovCircle") == true)
            end
        elseif key == "TargetRegion" then
            UpdateBoneUI(tostring(val))
        elseif syncInputs[key] and typeof(val) == "number" then
            syncInputs[key](val)
        end
    end)

    screenGui.Destroying:Connect(function()
        if unsubscribeGlobal then unsubscribeGlobal(); unsubscribeGlobal = nil end
    end)

    DashboardGUI.AddDiagnosticLog("INIT", "Dashboard GUI carregada com 5 abas otimizadas.", "OK")
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
        local fov = math.clamp(tonumber(SimConfig.Get("FOV")) or 70.0, 5.0, 170.0)
        local vpY = math.max(camera.ViewportSize.Y, 1)
        local camFovRad = math.rad(math.clamp(camera.FieldOfView, 10.0, 120.0) / 2)
        local aimFovRad = math.rad(fov / 2)
        local radius = math.clamp((math.tan(aimFovRad) / math.tan(camFovRad)) * (vpY / 2), 5, vpY)
        FovCircleInstance.Size = UDim2.new(0, radius * 2, 0, radius * 2)
        FovCircleInstance.Position = UDim2.new(0.5, 0, 0.5, 0)
    end
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

    if TelemetryLabels["VisStatus"] then
        local obstructed = (data.isObstructed == true)
        TelemetryLabels["VisStatus"].Text = obstructed and "OBSTRUÍDO" or "LIVRE"
        TelemetryLabels["VisStatus"].TextColor3 = obstructed and THEME.ACCENT_RED or THEME.SUCCESS
    end

    if TelemetryLabels["ActiveTarget"] then
        TelemetryLabels["ActiveTarget"].Text = tostring(data.targetName or "NENHUM")
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

-- Watchdog de Fundo
task.spawn(function()
    while true do
        task.wait(1.0)
        local ok, _ = pcall(function()
            local now = os.clock()
            local dt = now - PerformanceData.LastCheck
            PerformanceData.LastCheck = now
            local currentFps = math.clamp(math.round(1 / math.max(dt, 0.001)), 1, 144)
            PerformanceData.Fps = currentFps

            if TelemetryLabels["FpsCounter"] then
                TelemetryLabels["FpsCounter"].Text = string.format("%d FPS", currentFps)
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
                    WatchdogBadgeInstance.Text = "● WATCHDOG: 100% OPERACIONAL"
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
    local status = LosLabels["Status"]
    if not status or not status.Parent then return end
    if not last then
        status.Text = "  Última consulta: (nenhuma)"
        status.TextColor3 = THEME.TEXT_MUTED
        return
    end
    local color = THEME.WARNING
    if last.Status == "VISIBLE" then color = THEME.SUCCESS elseif last.Status == "BLOCKED" then color = THEME.ACCENT_RED end
    status.Text = "  Última consulta: " .. tostring(last.Status)
    status.TextColor3 = color
    if LosLabels["Reason"] then LosLabels["Reason"].Text = "  Causa: " .. tostring(last.Reason) end
    if LosLabels["Blocker"] then LosLabels["Blocker"].Text = "  Obstrução: " .. tostring(last.BlockerName or "—") end
    if LosLabels["Distance"] then
        LosLabels["Distance"].Text = last.HitDistance and string.format("  Distância: %.2f studs (consulta: %.2f)", last.HitDistance, last.QueryDistance or 0)
            or string.format("  Distância: — (consulta: %.2f)", last.QueryDistance or 0)
    end

    if LosHistoryList and history then
        local newest = history[#history]
        local stamp = newest and (newest.Time * 1000 + #history) or 0
        if stamp == LastRenderedLosStamp then return end
        LastRenderedLosStamp = stamp
        for _, ch in ipairs(LosHistoryList:GetChildren()) do
            if ch:IsA("TextLabel") then ch:Destroy() end
        end
        for i = #history, math.max(1, #history - 39), -1 do
            local h = history[i]
            local c = THEME.WARNING
            if h.Status == "VISIBLE" then c = THEME.SUCCESS elseif h.Status == "BLOCKED" then c = THEME.ACCENT_RED end
            local row = Instance.new("TextLabel")
            row.Size = UDim2.new(1, -8, 0, 18)
            row.BackgroundTransparency = 1
            row.Font = Enum.Font.Code
            row.TextSize = 10
            row.TextColor3 = c
            row.TextXAlignment = Enum.TextXAlignment.Left
            row.LayoutOrder = #history - i
            row.Text = string.format("  %-8s %-14s %s%s", h.Status, tostring(h.Target), tostring(h.Reason), h.Blocker and (" [" .. h.Blocker .. "]") or "")
            row.Parent = LosHistoryList
        end
    end
end

function DashboardGUI:UpdateDetection(info: any)
    if not DetLabels["State"] or not DetLabels["State"].Parent or not info then return end
    local r = info.report
    if not info.engineAvailable then
        DetLabels["State"].Text = "  Estado: EngineCore indisponível"
        DetLabels["State"].TextColor3 = THEME.WARNING
    elseif not r then
        DetLabels["State"].Text = "  Estado: aguardando amostras reais"
        DetLabels["State"].TextColor3 = THEME.TEXT_MUTED
    else
        local color = THEME.SUCCESS
        if r.category == "INSUFICIENTE" then color = THEME.WARNING
        elseif r.category ~= "LIMPO" then color = THEME.ACCENT_RED end
        DetLabels["State"].Text = string.format("  Classificação: %s (score %d)", r.category, r.totalScore)
        DetLabels["State"].TextColor3 = color
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
    return MainFrameInstance ~= nil and MainFrameInstance.Visible == true
end

function DashboardGUI.GetScreenGui(): ScreenGui?
    return ScreenGuiInstance
end

return DashboardGUI
