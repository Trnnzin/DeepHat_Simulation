--!strict
-- =========================================================================
-- SimulationBootstrap.client.lua
-- Orquestrador Principal do Sistema Modular (Ambiente Studio e Cliente Roblox)
-- Integração: SimConfig, InstanceDetector, VectorTracker,
--             VisualOverlayRenderer e DashboardGUI
-- Recursos Avançados: Modos de Prioridade de Alvo, Silent Aim Simulado e Tracers 3D
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

-- Gerenciamento de Input para Mira (RMB / MouseButton2) com Suporte a Modos
local isRightMouseDown = false
local isToggleAimActive = false

UserInputService.InputBegan:Connect(function(input, gpe)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        isRightMouseDown = true
        isToggleAimActive = not isToggleAimActive
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        isRightMouseDown = false
    end
end)

UserInputService.WindowFocusReleased:Connect(function()
    isRightMouseDown = false
end)

-- Pipeline de Renderização de Alta Frequência (RenderStepped)
local BIND_NAME = "DeepHat_MasterSimulationPipeline"
pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)

local lastTelemetryUpdate = 0
local lastTracerTime = 0

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
                mode = "PAUSED",
                decoupledAngle = 0,
                silentAimActive = false
            })
            return
        end

        local aimMode = SimConfig.Get("AimMode") or "HoldRMB"
        local shouldAim = false
        if aimMode == "AlwaysOn" then
            shouldAim = true
        elseif aimMode == "Toggle" then
            shouldAim = isToggleAimActive
        else -- "HoldRMB"
            local holdToAim = SimConfig.Get("HoldToAim") ~= false
            shouldAim = (not holdToAim) or isRightMouseDown or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
        end

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
        local maxAngularVel = tonumber(SimConfig.Get("AngularVelocity")) or 240.0
        local clampMaxVel = SimConfig.Get("MaxAngularVelocityClamp") == true
        local targetPriority = tostring(SimConfig.Get("TargetPriority") or "Crosshair")
        local targetStickiness = tonumber(SimConfig.Get("TargetStickiness")) or 0.25

        -- Silent Aim Config
        local silentAimEnabled = SimConfig.Get("SilentAimEnabled") == true
        local silentAimFov = tonumber(SimConfig.Get("SilentAimFOV")) or 35.0
        local silentAimHitChance = tonumber(SimConfig.Get("SilentAimHitChance")) or 100.0
        local silentAimTracer = SimConfig.Get("SilentAimTracer") == true

        -- 1. Detecção Espacial do Melhor Candidato com Prioridades
        local bestTarget, targetPos, dist, angleDeg, targetLabel, targetHealth = Detector:FindBestCandidate(
            camera.CFrame.Position,
            camera.CFrame.LookVector,
            maxRadius,
            fov,
            preferredBone,
            teamCheck,
            targetPriority,
            targetStickiness
        )

        local isObstructed = false
        local targetName = "NENHUM"
        local calculatedAngVel = 0
        local currentMode = "IDLE"
        local decoupledAngle = 0
        local silentAimActive = false

        if bestTarget and targetPos then
            targetName = string.format("%s (%s - %d HP)", bestTarget.Name, targetLabel, math.floor(targetHealth or 100))

            -- 2. Verificação de Oclusão Geométrica (Ignorando o próprio alvo)
            isObstructed = Tracker:CheckObstruction(camera.CFrame.Position, targetPos, bestTarget)

            -- Se configurado para "Somente Visíveis" e houver barreira real, descarta alvo
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

            -- 4. Realce Visual Dinâmico em Lote (ESP Chams com limpeza automática)
            if enableESP then
                Renderer:SyncBatchHighlights(Detector.CandidatePool, bestTarget, isObstructed)
            else
                Renderer:ClearAll()
            end

            -- 5. Simulação de Silent Aim (Disparo Desacoplado da Câmera)
            if silentAimEnabled and isTargetValid then
                local inFov, decoupledDir, discDeg = Tracker:ComputeSilentAimVector(
                    camera.CFrame,
                    aimPosition,
                    silentAimFov
                )
                decoupledAngle = discDeg

                if inFov then
                    silentAimActive = true
                    currentMode = "SILENT_AIM"

                    -- Disparo simulado controlado e traçadores (Throttled a cada 0.10s)
                    local now = os.clock()
                    if shouldAim and (now - lastTracerTime) >= 0.10 then
                        lastTracerTime = now
                        local shotResult = Tracker:SimulateShot(
                            camera.CFrame,
                            aimPosition,
                            silentAimFov,
                            silentAimHitChance,
                            isObstructed,
                            bestTarget
                        )
                        if silentAimTracer and shotResult.Fired then
                            local beamColor = shotResult.HitRegistered and Color3.fromRGB(46, 230, 110) or Color3.fromRGB(255, 60, 75)
                            Tracker:DrawTracerBeam(shotResult.MuzzlePosition, shotResult.TargetPosition, beamColor, 0.14)
                        end
                    end
                end
            end

            -- 6. Interpolação Cinemática da Câmera (Aimbot Convencional)
            -- Executa somente quando Silent Aim estiver desativado para preservar os dois modos
            if shouldAim and isTargetValid and not silentAimEnabled then
                currentMode = "TRACKING"

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
                        intensity,
                        maxAngularVel,
                        clampMaxVel
                    )
                    camera.CFrame = smoothedCFrame
                    calculatedAngVel = angVel
                end
            end
        else
            Renderer:ClearAll()
        end

        -- 7. Retroalimentação da Telemetria para o Dashboard (Throttle de 20Hz)
        local now = os.clock()
        if (now - lastTelemetryUpdate) >= 0.05 then
            lastTelemetryUpdate = now
            DashboardGUI:UpdateTelemetryDisplay({
                angularVelocity = calculatedAngVel,
                isObstructed = isObstructed,
                targetName = targetName,
                dt = dt,
                mode = currentMode,
                decoupledAngle = decoupledAngle,
                silentAimActive = silentAimActive
            })
            DashboardGUI:UpdateFovCircle()
        end
    end)
end)

DashboardGUI.AddDiagnosticLog("BOOTSTRAP", "DeepHat Modular Engine ativo em alta fidelidade!", "OK")
print("[DeepHat Modular Engine] Inicializado com sucesso em alta performance!")
