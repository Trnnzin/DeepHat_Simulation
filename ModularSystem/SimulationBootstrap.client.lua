--!strict
-- SimulationBootstrap.client.lua
-- Orquestrador Principal: Integra SimConfig, AdvancedKinematics e DashboardGUI

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera or Workspace:WaitForChild("Camera") :: Camera

-- Importacao dos modulos desacoplados
local SimConfig = require(script.Parent.SimConfig)
local AdvancedKinematics = require(script.Parent.AdvancedKinematics)
local DashboardGUI = require(script.Parent.DashboardGUI)

-- Inicializacao da GUI
DashboardGUI.Create()

-- Inicializacao da Cinematica
local filterInstances: { Instance } = { LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait() }
local KinematicsController = AdvancedKinematics.new(Camera.CFrame, filterInstances)

LocalPlayer.CharacterAdded:Connect(function(char)
    table.clear(filterInstances)
    table.insert(filterInstances, char)
    KinematicsController:SetFilterInstances(filterInstances)
end)

-- Estado do Teste
local isSimulationRunning = false
local simulationConnection: RBXScriptConnection? = nil
local lastSnapTime = 0

-- Funcao utilitaria para obter uma posicao alvo de teste
-- (Se houver outro player no servidor ele foca nele; caso contrario gera um ponto de orbita virtual)
local function GetTargetPosition(): Vector3
    for _, other in ipairs(Players:GetPlayers()) do
        if other ~= LocalPlayer and other.Character and other.Character:FindFirstChild("HumanoidRootPart") then
            local hrp = other.Character.HumanoidRootPart :: BasePart
            return hrp.Position
        end
    end

    -- Alvo procedural flutuante se estiver sozinho no mapa
    local t = os.clock() * 0.8
    local center = Camera.CFrame.Position + Camera.CFrame.LookVector * 25
    return center + Vector3.new(math.sin(t) * 12, math.cos(t * 1.5) * 4, math.cos(t) * 12)
end

-- Handlers dos Botoes da GUI (Arquitetura orientada a eventos)
DashboardGUI.OnStartRequested = function()
    if isSimulationRunning then return end
    isSimulationRunning = true
    print("[Simulador] Teste INICIADO com perfil:", SimConfig.Get("ActiveProfile"))

    simulationConnection = RunService.RenderStepped:Connect(function(dt)
        local targetPos = GetTargetPosition()
        local snapFreq = SimConfig.Get("SnapFrequency") or 0.03
        local reactionTime = SimConfig.Get("ReactionTime") or 0.2
        local now = os.clock()

        local telemetry
        -- Decide estocasticamente se gera um Snap abrupto ou um Smooth Tracking organico
        if math.random() < snapFreq and (now - lastSnapTime > reactionTime) then
            lastSnapTime = now
            telemetry = KinematicsController:StepSnap(targetPos, dt)
        else
            telemetry = KinematicsController:StepSmooth(targetPos, dt)
        end

        -- Aplica a orientacao calculada na camera virtual
        Camera.CFrame = telemetry.cframe

        -- Envia telemetria atualizada para a interface (sem acoplamento direto)
        DashboardGUI:UpdateTelemetryDisplay(telemetry)
    end)
end

DashboardGUI.OnStopRequested = function()
    if not isSimulationRunning then return end
    isSimulationRunning = false
    if simulationConnection then
        simulationConnection:Disconnect()
        simulationConnection = nil
    end
    print("[Simulador] Teste INTERROMPIDO")
    DashboardGUI:UpdateTelemetryDisplay({
        angularVelocity = 0,
        isObstructed = false,
        mode = "PARADO"
    })
end

DashboardGUI.OnResetRequested = function()
    print("[Simulador] Parametros resetados para o padrao Normal")
end