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
if not LocalPlayer then
    pcall(function()
        LocalPlayer = Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    end)
    LocalPlayer = Players.LocalPlayer
end

local Camera = Workspace.CurrentCamera or Workspace:WaitForChild("Camera") :: Camera

-- Importação dos Módulos do Kernel
local SimConfig = require(script.Parent.SimConfig)
local InstanceDetector = require(script.Parent.InstanceDetector)
local VectorTracker = require(script.Parent.VectorTracker)
local VisualOverlayRenderer = require(script.Parent.VisualOverlayRenderer)
local DashboardGUI = require(script.Parent.DashboardGUI)
local ScenarioRunner = require(script.Parent.ScenarioRunner)

-- EngineCore (avaliação defensiva) é opcional e independente da UI: se não existir no
-- ambiente, a aba Detection informa indisponibilidade em vez de inventar dados.
local Engine: any = nil
do
    local okEngine, mod = pcall(function()
        local holder: any = script.Parent.Parent
        local m = holder and holder:FindFirstChild("EngineCore")
        return m and require(m) or nil
    end)
    if okEngine then Engine = mod end
end

-- Configuração: primeira execução aplica "DeepHat Simulation Default"; depois carrega o salvo
-- se válido (câmera/disparo sempre iniciam desligados).
local loadStatus = SimConfig.Load()

-- Inicialização da Interface
print("[DeepHat Bootstrap] Criando interface gráfica...")
local okGui, guiErr = pcall(function()
    return DashboardGUI.Create()
end)
if not okGui then
    warn("[DeepHat Bootstrap FATAL] Erro ao instanciar DashboardGUI: " .. tostring(guiErr))
else
    print("[DeepHat Bootstrap] Interface gráfica criada com sucesso.")
end
DashboardGUI.AddDiagnosticLog("CONFIG", string.format("Perfil: %s (%s)", SimConfig.DefaultProfileName, loadStatus), loadStatus == "restored_defaults" and "WARN" or "INFO")

-- Inicialização dos Subsistemas
local filterInstances: { Instance } = {}
if LocalPlayer and LocalPlayer.Character then
    table.insert(filterInstances, LocalPlayer.Character)
end

local Detector = InstanceDetector.new(0.12) -- 8.3Hz de varredura espacial desacoplada
local Tracker = VectorTracker.new(filterInstances)
local Renderer = VisualOverlayRenderer.new()

-- Tratamento Robusto de Respawn do Personagem e Ferramentas (Armas)
local triggerShotRequested = false
local triggerSource = "Nenhum"
local lastSilentAimLogTime = 0

local function HookCharacterTools(char: Instance?)
    if not char then return end
    local function HookTool(child: Instance)
        if child:IsA("Tool") then
            child.Activated:Connect(function()
                triggerShotRequested = true
                triggerSource = "Tool.Activated (" .. child.Name .. ")"
            end)
        end
    end
    for _, child in ipairs(char:GetChildren()) do
        HookTool(child)
    end
    char.ChildAdded:Connect(HookTool)
end

if LocalPlayer then
    if LocalPlayer.Character then
        HookCharacterTools(LocalPlayer.Character)
    end
    LocalPlayer.CharacterAdded:Connect(function(char)
        table.clear(filterInstances)
        table.insert(filterInstances, char)
        Tracker:SetFilterInstances(filterInstances)
        HookCharacterTools(char)
        DashboardGUI.AddDiagnosticLog("PLAYER", "Personagem recarregado no pipeline de filtros.", "INFO")
    end)
end

-- =========================================================================
-- EXECUÇÃO DIAGNÓSTICA DE SILENT AIM (4 ESTÁGIOS ESTRITAMENTE AUDITADOS)
-- =========================================================================
local function ExecuteSilentAimShot(source: string): (boolean, string)
    -- ESTÁGIO 1: Verificação de Inicialização do Módulo
    local silentAimEnabled = SimConfig.Get("SilentAimEnabled") == true
    if not silentAimEnabled then
        DashboardGUI.AddDiagnosticLog("SILENT_AIM", "Módulo não iniciado / desativado no painel.", "WARN")
        print(string.format("[SILENT AIM] [ESTÁGIO 1: MÓDULO] Disparo recebido via %s, porém o módulo está DESATIVADO no painel (SilentAimEnabled = false).", source))
        return false, "MODULE_DISABLED"
    end

    -- ESTÁGIO 2: Confirmação de Recepção do Disparo
    print(string.format("[SILENT AIM] [ESTÁGIO 2: DISPARO] Disparo recebido com sucesso via %s.", source))

    local camera = Workspace.CurrentCamera
    if not camera then
        DashboardGUI.AddDiagnosticLog("SILENT_AIM", "Câmera ausente.", "WARN")
        print("[SILENT AIM] [ESTÁGIO 3: ALVO] Falha: Câmera não encontrada no Workspace.")
        return false, "NO_CAMERA"
    end

    local maxRadius = tonumber(SimConfig.Get("VectorRadius")) or 300.0
    local silentAimFov = tonumber(SimConfig.Get("SilentAimFOV")) or 35.0
    local silentAimHitChance = tonumber(SimConfig.Get("SilentAimHitChance")) or 100.0
    local silentAimTracer = SimConfig.Get("SilentAimTracer") ~= false
    local preferredBone = tostring(SimConfig.Get("TargetRegion") or "Head")
    local teamCheck = SimConfig.Get("TeamCheck") == true
    local visibleOnly = SimConfig.Get("VisibleOnly") == true
    local targetPriority = tostring(SimConfig.Get("TargetPriority") or "Crosshair")
    local targetStickiness = tonumber(SimConfig.Get("TargetStickiness")) or 0.25
    local enableLead = SimConfig.Get("EnableLead") == true
    local projSpeed = tonumber(SimConfig.Get("ProjectileSpeed")) or 900.0

    -- ESTÁGIO 3: Seleção e Validação do Candidato
    local bestTarget, targetPos, dist, angleDeg, targetLabel, targetHealth = Detector:FindBestCandidate(
        camera.CFrame.Position,
        camera.CFrame.LookVector,
        maxRadius,
        silentAimFov * 2,
        preferredBone,
        teamCheck,
        targetPriority,
        targetStickiness
    )

    if not bestTarget or not targetPos then
        DashboardGUI.AddDiagnosticLog("SILENT_AIM", string.format("Alvo não selecionado (Nenhum candidato em %d studs).", math.floor(maxRadius)), "WARN")
        print(string.format("[SILENT AIM] [ESTÁGIO 3: ALVO] Alvo não selecionado: Nenhum candidato válido encontrado no raio de %d studs.", math.floor(maxRadius)))
        return false, "NO_TARGET_IN_RADIUS"
    end

    -- Verificação de Oclusão (Linha de Visada)
    local los = Tracker:EvaluateLineOfSight(camera.CFrame.Position, targetPos, bestTarget)
    local isObstructed = (los.Status == "BLOCKED")
    if visibleOnly and isObstructed then
        DashboardGUI.AddDiagnosticLog("SILENT_AIM", string.format("Alvo não selecionado: '%s' ocluído por parede.", bestTarget.Name), "WARN")
        print(string.format("[SILENT AIM] [ESTÁGIO 3: ALVO] Alvo não selecionado: '%s' bloqueado por geometria (VisibleOnly ativo).", bestTarget.Name))
        return false, "TARGET_OCCLUDED"
    end

    -- Predição Balística (Lead)
    local aimPosition = targetPos
    if enableLead then
        local estimatedVel = Tracker:EstimateVelocity(bestTarget, targetPos)
        aimPosition = Tracker:ComputeLead(targetPos, estimatedVel, camera.CFrame.Position, projSpeed, true)
    end

    -- Validação do Cone Angular de Silent Aim
    local inFov, decoupledDir, discDeg = Tracker:ComputeSilentAimVector(
        camera.CFrame,
        aimPosition,
        silentAimFov
    )

    if not inFov then
        DashboardGUI.AddDiagnosticLog("SILENT_AIM", string.format("Alvo não selecionado: '%s' fora do cone (%.1f° > %.1f°).", bestTarget.Name, discDeg, silentAimFov), "WARN")
        print(string.format("[SILENT AIM] [ESTÁGIO 3: ALVO] Alvo não selecionado: '%s' fora do cone angular de redirecionamento (desvio %.1f° > FOV %.1f°).", bestTarget.Name, discDeg, silentAimFov))
        return false, "TARGET_OUTSIDE_FOV"
    end

    -- ESTÁGIO 4: Cálculo do Ponto de Impacto e Simulação do Disparo
    local shotResult = Tracker:SimulateShot(
        camera.CFrame,
        aimPosition,
        silentAimFov,
        silentAimHitChance,
        isObstructed,
        bestTarget
    )
    Tracker.LastShotResult = shotResult

    if silentAimTracer and shotResult.Fired then
        local beamColor = shotResult.HitRegistered and Color3.fromRGB(46, 230, 110) or Color3.fromRGB(255, 60, 75)
        Tracker:DrawTracerBeam(shotResult.MuzzlePosition, shotResult.TargetPosition, beamColor, 0.25)
    end

    local resTag = shotResult.HitRegistered and "ACERTO" or "DISPERSÃO"
    DashboardGUI.AddDiagnosticLog("SILENT_AIM", string.format("Impacto calculado: %s em '%s' (Desvio: %.1f°).", resTag, bestTarget.Name, shotResult.DiscrepancyAngleDeg), shotResult.HitRegistered and "OK" or "WARN")
    print(string.format("[SILENT AIM] [ESTÁGIO 4: IMPACTO] Impacto calculado: %s em '%s' (Desvio angular: %.1f°, Destino: %s).", resTag, bestTarget.Name, shotResult.DiscrepancyAngleDeg, tostring(shotResult.TargetPosition)))

    return true, resTag
end

-- Conexão de Ações do DashboardGUI
DashboardGUI.OnSimulateSilentAimShot = function()
    ExecuteSilentAimShot("Dashboard GUI (Botão de Teste)")
end

DashboardGUI.OnRunLosScenario = function(id: string)
    local outcome, res = ScenarioRunner.Run(Tracker, id)
    if outcome and res then
        Tracker:RecordLos(res, "Cenário:" .. outcome.Id)
        Tracker.LastLos = res
        DashboardGUI.AddDiagnosticLog("LOS", string.format("%s => %s (esperado %s) %s", outcome.Label, outcome.Actual, outcome.Expected, outcome.Passed and "PASS" or "FAIL"), outcome.Passed and "OK" or "WARN")
    end
end

DashboardGUI.OnClearLosHistory = function()
    Tracker:ClearLosHistory()
    ScenarioRunner.ClearHistory()
    DashboardGUI.AddDiagnosticLog("LOS", "Histórico de LOS limpo.", "INFO")
end

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

-- Gerenciamento de Input para Mira (RMB / MouseButton2) e Disparo (LMB / MouseButton1)
local isRightMouseDown = false
local isLeftMouseDown = false
local isToggleAimActive = false

UserInputService.InputBegan:Connect(function(input, gpe)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        isRightMouseDown = true
        isToggleAimActive = not isToggleAimActive
    elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
        isLeftMouseDown = true
        triggerShotRequested = true
        triggerSource = "MouseButton1 (InputBegan)"
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        isRightMouseDown = false
    elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
        isLeftMouseDown = false
    end
end)

UserInputService.WindowFocusReleased:Connect(function()
    isRightMouseDown = false
    isLeftMouseDown = false
end)

-- Pipeline de Renderização de Alta Frequência (RenderStepped)
local BIND_NAME = "DeepHat_MasterSimulationPipeline"
pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)

local lastTelemetryUpdate = 0
local lastDetectionUpdate = 0
local lastTracerTime = 0
local lastLosRecordTime = 0
local lastLosStatus = ""
local lastLosTarget: Instance? = nil
local sampleCount = 0
local occludedFrames = 0
local pipelineMs = 0
local lastMetrics: { [string]: number }? = nil

RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt: number)
    local ok, _ = pcall(function()
        local camera = Workspace.CurrentCamera
        if not camera then return end
        local frameStart = os.clock()

        local isSimulationActive = SimConfig.Get("SimulationActive") == true
        if not isSimulationActive then
            Tracker:Release()
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

        local aimbotEnabled = SimConfig.Get("AimbotEnabled") ~= false
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

        local isShooting = triggerShotRequested or isLeftMouseDown or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
        local isDiscreteTrigger = triggerShotRequested
        local currentTriggerSrc = triggerSource
        triggerShotRequested = false

        local maxRadius = tonumber(SimConfig.Get("VectorRadius")) or 300.0
        -- FOV de seleção: raio em pixels (FovRadiusPx, o mesmo do círculo visual) convertido em
        -- ângulo; FOV (graus) funciona como teto máximo.
        local fovCap = tonumber(SimConfig.Get("FOV")) or 70.0
        local halfTan = (tonumber(SimConfig.Get("FovRadiusPx")) or 120) / math.max(camera.ViewportSize.Y / 2, 1)
            * math.tan(math.rad(camera.FieldOfView / 2))
        local fov = math.min(fovCap, math.deg(math.atan(halfTan)) * 2)
        local preferredBone = tostring(SimConfig.Get("TargetRegion") or "Head")
        local teamCheck = SimConfig.Get("TeamCheck") == true
        local visibleOnly = SimConfig.Get("VisibleOnly") == true
        local enableESP = SimConfig.Get("EnableESP") == true and SimConfig.Get("ShowSyntheticTargets") ~= false
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
        local silentAimTracer = SimConfig.Get("SilentAimTracer") ~= false

        -- FOV de busca de candidatos:
        -- Para Aimbot normal utiliza o fov central. Se Silent Aim estiver habilitado,
        -- expande a área de busca angular para cobrir o diâmetro do cone de Silent Aim (silentAimFov * 2)
        local aimbotFov = fov
        local searchFov = aimbotFov
        if silentAimEnabled then
            searchFov = math.max(searchFov, silentAimFov * 2)
        end

        -- 1. Detecção Espacial do Melhor Candidato com Prioridades
        local bestTarget, targetPos, dist, angleDeg, targetLabel, targetHealth = Detector:FindBestCandidate(
            camera.CFrame.Position,
            camera.CFrame.LookVector,
            maxRadius,
            searchFov,
            preferredBone,
            teamCheck,
            targetPriority,
            targetStickiness
        )

        local isObstructed = false
        local lookBefore = camera.CFrame.LookVector
        local targetName = "NENHUM"
        local calculatedAngVel = 0
        local currentMode = "IDLE"
        local decoupledAngle = 0
        local silentAimActive = false

        if bestTarget and targetPos then
            targetName = string.format("%s (%s - %d HP)", bestTarget.Name, targetLabel, math.floor(targetHealth or 100))

            -- 2. Linha de visão tri-state (VISIBLE / BLOCKED / INVALID)
            local losEnabled = SimConfig.Get("LineOfSightEnabled") ~= false
            local los: any = { Status = "DISABLED", Reason = "Diagnóstico de LOS desativado (não avaliado)", QueryDistance = 0 }
            if losEnabled then
                los = Tracker:EvaluateLineOfSight(camera.CFrame.Position, targetPos, bestTarget)
                Tracker.LosHistoryLimit = tonumber(SimConfig.Get("HistoryLimit")) or 50
                local nowLos = os.clock()
                -- Histórico: registra mudanças de estado/alvo ou, no máximo, a cada 0.5 s
                if los.Status ~= lastLosStatus or bestTarget ~= lastLosTarget or (nowLos - lastLosRecordTime) >= 0.5 then
                    Tracker.LastLos = los
                    if SimConfig.Get("HistoryEnabled") ~= false then
                        Tracker:RecordLos(los, bestTarget.Name)
                    end
                    lastLosStatus, lastLosTarget, lastLosRecordTime = los.Status, bestTarget, nowLos
                end
            end
            isObstructed = (los.Status == "BLOCKED")

            -- Se configurado para "Somente Visíveis" e houver barreira real, descarta alvo
            local isTargetValid = (los.Status ~= "INVALID")
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
            if isShooting then
                local now = os.clock()
                if (now - lastTracerTime) >= 0.10 then
                    lastTracerTime = now
                    local src = isDiscreteTrigger and currentTriggerSrc or "MouseButton1 contínuo"
                    if isDiscreteTrigger or (now - lastSilentAimLogTime) >= 0.35 then
                        lastSilentAimLogTime = now
                        ExecuteSilentAimShot(src)
                    elseif silentAimEnabled and isTargetValid then
                        local inFov = Tracker:ComputeSilentAimVector(camera.CFrame, aimPosition, silentAimFov)
                        if inFov then
                            local shotResult = Tracker:SimulateShot(
                                camera.CFrame,
                                aimPosition,
                                silentAimFov,
                                silentAimHitChance,
                                isObstructed,
                                bestTarget
                            )
                            Tracker.LastShotResult = shotResult
                            if silentAimTracer and shotResult.Fired and SimConfig.Get("ShowDebugMarkers") ~= false then
                                local beamColor = shotResult.HitRegistered and Color3.fromRGB(46, 230, 110) or Color3.fromRGB(255, 60, 75)
                                Tracker:DrawTracerBeam(shotResult.MuzzlePosition, shotResult.TargetPosition, beamColor, 0.22)
                            end
                        end
                    end
                end
            end

            if silentAimEnabled and isTargetValid then
                local inFov, decoupledDir, discDeg = Tracker:ComputeSilentAimVector(
                    camera.CFrame,
                    aimPosition,
                    silentAimFov
                )
                decoupledAngle = discDeg

                if inFov then
                    silentAimActive = true
                    if currentMode == "IDLE" then
                        currentMode = "SILENT_AIM"
                    end
                end
            end

            -- 6. Interpolação Cinemática da Câmera (Aimbot Convencional)
            -- Executa somente quando o Aimbot estiver ativado pelo painel e o alvo estiver dentro do cone de mira do Aimbot
            local inAimbotCone = (angleDeg <= (aimbotFov / 2))
            if aimbotEnabled and shouldAim and isTargetValid and inAimbotCone then
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
            else
                Tracker:ResetTracking()
            end
        else
            if isShooting and isDiscreteTrigger then
                ExecuteSilentAimShot(currentTriggerSrc)
            end
            Tracker:ResetTracking()
            Renderer:ClearAll()
        end

        -- 7a. Métricas REAIS para o EngineCore (campos não medidos permanecem nil = indisponível)
        local tracked = (currentMode == "TRACKING" or currentMode == "SNAP")
        if tracked then
            local d = math.deg(math.acos(math.clamp(lookBefore:Dot(camera.CFrame.LookVector), -1.0, 1.0)))
            sampleCount += 1
            occludedFrames = isObstructed and (occludedFrames + 1) or 0
            lastMetrics = {
                angularVelocity = calculatedAngVel,
                singleFrameDeltaDeg = d,
                consecutiveOccludedFrames = occludedFrames,
                decoupledAngleDeg = silentAimActive and decoupledAngle or nil,
                sampleCount = sampleCount,
            }
        elseif silentAimActive then
            sampleCount += 1
            lastMetrics = { decoupledAngleDeg = decoupledAngle, sampleCount = sampleCount }
        else
            occludedFrames = 0
            lastMetrics = nil
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
                silentAimActive = silentAimActive,
                lastShot = Tracker.LastShotResult
            })
            DashboardGUI:UpdateFovCircle()
            DashboardGUI:UpdateLos(Tracker.LastLos, Tracker.LosHistory)
            pipelineMs = pipelineMs * 0.9 + (os.clock() - frameStart) * 1000 * 0.1
            if (now - lastDetectionUpdate) >= 0.5 then
                lastDetectionUpdate = now
                local report = (Engine and lastMetrics) and Engine:CalculateSuspicion(lastMetrics) or nil
                local pass, fail = ScenarioRunner.Summary()
                DashboardGUI:UpdateDetection({
                    report = report, samples = sampleCount, perfMs = pipelineMs,
                    scenarioPass = pass, scenarioFail = fail, engineAvailable = Engine ~= nil,
                })
            end
        end
    end)
end)

DashboardGUI.AddDiagnosticLog("BOOTSTRAP", "DeepHat Modular Engine ativo em alta fidelidade!", "OK")
print("[DeepHat Modular Engine] Inicializado com sucesso em alta performance!")
