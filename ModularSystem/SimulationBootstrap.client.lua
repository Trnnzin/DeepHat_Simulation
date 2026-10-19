--!strict
-- =========================================================================
-- SimulationBootstrap.client.lua
-- Orquestrador Principal do Sistema Modular (Ambiente Studio e Cliente Roblox)
-- Integração Contínua: SimConfig, InstanceDetector, VectorTracker,
--                      VisualOverlayRenderer e DashboardGUI
-- =========================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera or Workspace:WaitForChild("Camera") :: Camera

-- Importação dos Módulos do Kernel
local SimConfig = require(script.Parent.SimConfig)
local InstanceDetector = require(script.Parent.InstanceDetector)
local VectorTracker = require(script.Parent.VectorTracker)
local VisualOverlayRenderer = require(script.Parent.VisualOverlayRenderer)
local DashboardGUI = require(script.Parent.DashboardGUI)

-- Inicialização da Interface
DashboardGUI.Create()

-- Inicialização dos Subsistemas
local filterInstances: { Instance } = {}
if LocalPlayer.Character then
    table.insert(filterInstances, LocalPlayer.Character)
end

local Detector = InstanceDetector.new(0.12) -- 8.3Hz de varredura espacial desacoplada
local Tracker = VectorTracker.new(filterInstances)
local Renderer = VisualOverlayRenderer.new()

-- Tratamento Robusto de Respawn do Personagem
LocalPlayer.CharacterAdded:Connect(function(char)
    table.clear(filterInstances)
    table.insert(filterInstances, char)
    Tracker:SetFilterInstances(filterInstances)
    DashboardGUI.AddDiagnosticLog("PLAYER", "Personagem recarregado no pipeline de filtros.", "INFO")
end)

-- Conexão de Ações do DashboardGUI
DashboardGUI.OnStartRequested = function()
    DashboardGUI.AddDiagnosticLog("PIPELINE", "Sessão de testes ativada com sucesso.", "OK")
end

DashboardGUI.OnStopRequested = function()
    Renderer:ClearAll()
    DashboardGUI.AddDiagnosticLog("PIPELINE", "Sessão parada. Realces limpos.", "WARN")
end

DashboardGUI.OnResetRequested = function()
    Renderer:ClearAll()
    DashboardGUI.AddDiagnosticLog("PIPELINE", "Perfis e realces resetados.", "INFO")
end

-- Gerenciamento de Input para Mira (RMB / MouseButton2)
local isRightMouseDown = false

UserInputService.InputBegan:Connect(function(input, gpe)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        isRightMouseDown = true
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        isRightMouseDown = false
    end
end)

-- Pipeline de Renderização de Alta Frequência (RenderStepped)
local BIND_NAME = "DeepHat_MasterSimulationPipeline"
pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)

local lastTelemetryUpdate = 0

RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt: number)
    local ok, _ = pcall(function()
        local camera = Workspace.CurrentCamera
        if not camera then return end

        local isSimulationActive = SimConfig.Get("SimulationActive") == true
        if not isSimulationActive then
            Renderer:ClearAll()
            DashboardGUI:UpdateTelemetryDisplay({
                angularVelocity = 0,
                isObstructed = false,
                targetName = "PAUSADO",
                dt = dt,
                mode = "PAUSED"
            })
            return
        end

        local holdToAim = SimConfig.Get("HoldToAim") == true
        local isRmbHeld = isRightMouseDown or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
        local shouldAim = (not holdToAim) or isRmbHeld

        local maxRadius = tonumber(SimConfig.Get("VectorRadius")) or 300.0
        local fov = tonumber(SimConfig.Get("FOV")) or 70.0
        local preferredBone = tostring(SimConfig.Get("TargetRegion") or "Head")
        local teamCheck = SimConfig.Get("TeamCheck") == true
        local visibleOnly = SimConfig.Get("VisibleOnly") == true
        local enableESP = SimConfig.Get("EnableESP") == true
        local enableLead = SimConfig.Get("EnableLead") == true
        local projSpeed = tonumber(SimConfig.Get("ProjectileSpeed")) or 900.0
        local smoothing = tonumber(SimConfig.Get("Smoothing")) or 0.15
        local accelExp = tonumber(SimConfig.Get("AccelerationCurve")) or 1.25
        local simulateJitter = SimConfig.Get("SimulateJitter") == true
        local intensity = tonumber(SimConfig.Get("Intensity")) or 75.0

        -- 1. Detecção Espacial do Melhor Candidato
        local bestTarget, targetPos, dist, angleDeg, targetLabel = Detector:FindBestCandidate(
            camera.CFrame.Position,
            camera.CFrame.LookVector,
            maxRadius,
            fov,
            preferredBone,
            teamCheck
        )

        local isObstructed = false
        local targetName = "NENHUM"
        local calculatedAngVel = 0
        local currentMode = "IDLE"

        if bestTarget and targetPos then
            targetName = string.format("%s (%s)", bestTarget.Name, targetLabel)

            -- 2. Verificação de Oclusão Geométrica (Raycast)
            isObstructed = Tracker:CheckObstruction(camera.CFrame.Position, targetPos)

            -- Se configurado para "Somente Visíveis" e houver barreira, descarta mira
            local isTargetValid = true
            if visibleOnly and isObstructed then
                isTargetValid = false
            end

            -- 3. Predição Balística (Lead)
            local aimPosition = targetPos
            if enableLead and isTargetValid then
                local estimatedVel = Tracker:EstimateVelocity(bestTarget, targetPos)
                aimPosition = Tracker:ComputeLead(targetPos, estimatedVel, camera.CFrame.Position, projSpeed, true)
            end

            -- 4. Realce Visual (ESP Chams)
            if enableESP then
                Renderer:UpdateTargetHighlight(bestTarget, isObstructed, true)
            else
                Renderer:ClearAll()
            end

            -- 5. Interpolação Cinemática da Câmera
            if shouldAim and isTargetValid then
                currentMode = "TRACKING"

                -- Verifica se o perfil ativo requer Snap Instantâneo (ex: modo Agressivo de benchmark)
                local isAggressive = (SimConfig.Get("ActiveProfile") == "Agressivo")
                if isAggressive and (SimConfig.Get("Smoothing") or 0.1) <= 0.02 then
                    currentMode = "SNAP"
                    local snapCFrame, _, angVel = Tracker:ComputeSnapRotation(camera.CFrame, aimPosition, dt)
                    camera.CFrame = snapCFrame
                    calculatedAngVel = angVel
                else
                    local smoothedCFrame, _, angVel = Tracker:ComputeSmoothRotation(
                        camera.CFrame,
                        aimPosition,
                        dt,
                        smoothing,
                        accelExp,
                        simulateJitter,
                        intensity
                    )
                    camera.CFrame = smoothedCFrame
                    calculatedAngVel = angVel
                end
            end
        else
            Renderer:ClearAll()
        end

        -- 6. Retroalimentação da Telemetria para o Dashboard (com Throttle de 20Hz)
        local now = os.clock()
        if (now - lastTelemetryUpdate) >= 0.05 then
            lastTelemetryUpdate = now
            DashboardGUI:UpdateTelemetryDisplay({
                angularVelocity = calculatedAngVel,
                isObstructed = isObstructed,
                targetName = targetName,
                dt = dt,
                mode = currentMode
            })
            DashboardGUI:UpdateFovCircle()
        end
    end)
end)

DashboardGUI.AddDiagnosticLog("BOOTSTRAP", "DeepHat Modular Engine ativo em alta fidelidade!", "OK")
print("[DeepHat Modular Engine] Inicializado com sucesso em alta performance!")
