--!strict
-- SimulationBootstrap.client.lua
-- Orquestrador Principal: Integra SimConfig, AdvancedKinematics e DashboardGUI

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera or Workspace:WaitForChild("Camera") :: Camera

-- Importacao dos modulos desacoplados
local SimConfig = require(script.Parent.SimConfig)
local AdvancedKinematics = require(script.Parent.AdvancedKinematics)
local DashboardGUI = require(script.Parent.DashboardGUI)

-- Inicializacao da Interface
DashboardGUI.Create()

-- Inicializacao da Cinematica
local filterInstances: { Instance } = { LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait() }
local KinematicsController = AdvancedKinematics.new(Camera.CFrame, filterInstances)

LocalPlayer.CharacterAdded:Connect(function(char)
    table.clear(filterInstances)
    table.insert(filterInstances, char)
    KinematicsController:SetFilterInstances(filterInstances)
end)

local lastUiUpdate = 0
local lastSnapTime = 0

--[[
    Localizador de Parte/Osso de acordo com a regiao configurada no Dashboard
--]]
local function GetTargetPartFromCharacter(char: Model, region: string): BasePart?
    if region == "Head" then
        return (char:FindFirstChild("Head") or char:FindFirstChild("UpperTorso")) :: BasePart?
    elseif region == "Torso" then
        return (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or char:FindFirstChild("HumanoidRootPart")) :: BasePart?
    elseif region == "Arms" then
        return (char:FindFirstChild("RightUpperArm") or char:FindFirstChild("RightArm") or char:FindFirstChild("LeftUpperArm") or char:FindFirstChild("LeftArm") or char:FindFirstChild("HumanoidRootPart")) :: BasePart?
    elseif region == "Legs" then
        return (char:FindFirstChild("RightLowerLeg") or char:FindFirstChild("RightLeg") or char:FindFirstChild("LeftLowerLeg") or char:FindFirstChild("LeftLeg") or char:FindFirstChild("HumanoidRootPart")) :: BasePart?
    end
    return (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart) :: BasePart?
end

--[[
    Obtem a posicao do alvo mais proximo do centro da tela ou gera um alvo virtual procedural
--]]
local function GetTargetPosition(): Vector3
    local activeRegion = SimConfig.Get("TargetRegion") or "Head"
    local maxRadius = SimConfig.Get("VectorRadius") or 150.0

    local closestPos: Vector3? = nil
    local closestDist = math.huge

    for _, other in ipairs(Players:GetPlayers()) do
        if other ~= LocalPlayer and other.Character and other.Character:FindFirstChild("Humanoid") then
            local humanoid = other.Character.Humanoid :: Humanoid
            if humanoid.Health > 0 then
                local targetPart = GetTargetPartFromCharacter(other.Character, activeRegion)
                if targetPart then
                    local dist = (targetPart.Position - Camera.CFrame.Position).Magnitude
                    if dist <= maxRadius and dist < closestDist then
                        closestDist = dist
                        closestPos = targetPart.Position
                    end
                end
            end
        end
    end

    if closestPos then
        return closestPos
    end

    -- Alvo procedural flutuante se estiver sozinho no mapa (Virtual Test Dummy)
    local t = os.clock() * 0.75
    local center = Camera.CFrame.Position + Camera.CFrame.LookVector * 24
    return center + Vector3.new(math.sin(t) * 10, math.cos(t * 1.4) * 3.5, math.cos(t) * 10)
end

-- Loop de renderizacao contínuo de alta frequencia
local BIND_NAME = "DeepHat_SimulationCameraPipeline"
pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)

RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt: number)
    local success, err = pcall(function()
        local isRunning = SimConfig.Get("SimulationActive")
        local now = os.clock()

        if isRunning then
            local targetPos = GetTargetPosition()
            local snapFreq = (SimConfig.Get("Intensity") or 75) > 85 and 0.15 or 0.02
            local responseTimeSec = (SimConfig.Get("ResponseTime") or 16) / 1000.0

            local telemetry
            if math.random() < snapFreq and (now - lastSnapTime > responseTimeSec) then
                lastSnapTime = now
                telemetry = KinematicsController:StepSnap(targetPos, dt)
            else
                telemetry = KinematicsController:StepSmooth(targetPos, dt)
            end

            -- Aplica orientacao calculada na camera do jogo
            Camera.CFrame = telemetry.cframe

            -- Atualiza display da UI a 15 Hz para zero perda de desempenho
            if (now - lastUiUpdate) >= 0.066 then
                lastUiUpdate = now
                DashboardGUI:UpdateTelemetryDisplay(telemetry)
            end
        else
            if (now - lastUiUpdate) >= 0.2 then
                lastUiUpdate = now
                DashboardGUI:UpdateTelemetryDisplay({
                    angularVelocity = 0,
                    isObstructed = false,
                    mode = "PARADO"
                })
            end
        end
    end)

    if not success then
        warn("[SimulationBootstrap] Erro na atualizacao de frame: " .. tostring(err))
    end
end)

-- Handlers dos Botoes da Barra Inferior
DashboardGUI.OnStartRequested = function()
    SimConfig.Set("SimulationActive", true)
    print("[Simulador] Teste INICIADO // Perfil:", SimConfig.Get("ActiveProfile"), "// Regiao:", SimConfig.Get("TargetRegion"))
end

DashboardGUI.OnStopRequested = function()
    SimConfig.Set("SimulationActive", false)
    pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)
    print("[Simulador] Teste PARADO")
end

DashboardGUI.OnResetRequested = function()
    SimConfig.LoadProfile("Normal")
    print("[Simulador] Parametros resetados para o perfil Normal")
end

DashboardGUI.OnSaveRequested = function()
    local allConfig = SimConfig.GetAll()
    local json = HttpService:JSONEncode(allConfig)
    print("[Simulador] CONFIGURACOES SALVAS (JSON):")
    print(json)
end

print("[System] Dashboard de Simulacao Inicializado com Sucesso.")
