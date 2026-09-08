--!strict
-- SimulationBootstrap.client.lua
-- Orquestrador Principal do Sistema Modular (Ambiente Studio e Cliente)
-- Integração: SimConfig, InstanceDetector, VectorTracker, VisualOverlayRenderer e DashboardGUI

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera or Workspace:WaitForChild("Camera") :: Camera

-- Importação dos Módulos Especializados
local SimConfig = require(script.Parent.SimConfig)
local InstanceDetector = require(script.Parent.InstanceDetector)
local VectorTracker = require(script.Parent.VectorTracker)
local VisualOverlayRenderer = require(script.Parent.VisualOverlayRenderer)
local DashboardGUI = require(script.Parent.DashboardGUI)

-- Inicialização da Interface (com destruição prévia automática)
DashboardGUI.Create()

-- Inicialização dos Controladores
local filterInstances: { Instance } = {}
if LocalPlayer.Character then table.insert(filterInstances, LocalPlayer.Character) end

local Detector = InstanceDetector.new(0.15)
local Tracker = VectorTracker.new(filterInstances)
local Renderer = VisualOverlayRenderer.new()

LocalPlayer.CharacterAdded:Connect(function(char)
    table.clear(filterInstances)
    table.insert(filterInstances, char)
    Tracker:SetFilterInstances(filterInstances)
end)

local BIND_NAME = "DeepHat_ModularSimulationPipeline"
pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)

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

RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt: number)
    local ok, _ = pcall(function()
        local isRunning = SimConfig.Get("SimulationActive")
        local holdToAim = SimConfig.Get("HoldToAim") == true
        local isRmbHeld = isRightMouseDown or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
        local shouldAim = isRunning and (not holdToAim or isRmbHeld)

        local maxRadius = SimConfig.Get("VectorRadius") or 300.0
        local fov = tonumber(SimConfig.Get("FOV")) or 70.0
        local preferredBone = SimConfig.Get("TargetRegion") or "Head"
        local teamCheck = SimConfig.Get("TeamCheck") == true
        local enableESP = SimConfig.Get("EnableESP") == true

        -- Pilar 1: Detecção Universal
        local bestTarget, targetPos, dist, angleDeg, _ = Detector:FindBestCandidate(
            Camera.CFrame.Position,
            Camera.CFrame.LookVector,
            maxRadius,
            fov,
            preferredBone,
            teamCheck
        )

        -- Pilar 3: Realce Visual
        if enableESP and bestTarget then
            local obstructed = Tracker:CheckObstruction(Camera.CFrame.Position, targetPos)
            Renderer:UpdateTargetHighlight(bestTarget, obstructed, true)
        end

        -- Pilar 2: Rotação e Interpolação Segura
        if shouldAim and targetPos and bestTarget then
            local smoothedCFrame, _ = Tracker:ComputeSmoothRotation(
                Camera.CFrame,
                targetPos,
                dt,
                SimConfig.Get("Smoothing") or 0.15
            )
            Camera.CFrame = smoothedCFrame
        end
    end)
end)

print("[DeepHat Modular Engine] Inicializado com sucesso em alta performance!")
