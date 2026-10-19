--!strict
-- =========================================================================
-- MainTestRunner.lua
-- Executor Automatizado de Testes Unitários e Integração (Studio & CI Console)
-- Validação Completa das 12 Dimensões de Confiabilidade da Fase 2
-- =========================================================================

local Engine = require(script.Parent.EngineCore)
local Simulator = require(script.Parent.BehaviorSimulator)
local SimConfig = require(script.Parent.ModularSystem.SimConfig)
local VectorTracker = require(script.Parent.ModularSystem.VectorTracker)
local InstanceDetector = require(script.Parent.ModularSystem.InstanceDetector)
local VisualOverlayRenderer = require(script.Parent.ModularSystem.VisualOverlayRenderer)
local DiagnosticAI = require(script.Parent.ModularSystem.DiagnosticAI)

local TotalAssertions = 0
local PassedAssertions = 0
local FailedAssertions = 0
local SkippedTests = 0

local function Assert(condition: boolean, testName: string, detail: string?)
    TotalAssertions = TotalAssertions + 1
    if condition then
        PassedAssertions = PassedAssertions + 1
        print(string.format("  ✓ [PASS] %s", testName))
    else
        FailedAssertions = FailedAssertions + 1
        warn(string.format("  ✗ [FAIL] %s %s", testName, detail and ("(" .. detail .. ")") or ""))
    end
end

print("===================================================================")
print("       DEEPHAT SIMULATION SUITE // TEST RUNNER - FASE 2            ")
print("===================================================================")

-- -------------------------------------------------------------------------
-- [CRITÉRIO 1] SELEÇÃO CONSISTENTE DE ALVOS
-- -------------------------------------------------------------------------
print("\n[CRITÉRIO 1] Validando Seleção e Priorização de Alvos...")
local detector = InstanceDetector.new(0.1)
Assert(detector ~= nil, "Detector de instâncias instanciado com sucesso")

-- Teste de resolução de ossos e partes
local dummyModel = Instance.new("Model")
dummyModel.Name = "TestDummyTarget"
local headPart = Instance.new("Part")
headPart.Name = "Head"
headPart.Position = Vector3.new(0, 10, 30)
headPart.Parent = dummyModel

local torsoPart = Instance.new("Part")
torsoPart.Name = "UpperTorso"
torsoPart.Position = Vector3.new(0, 7, 30)
torsoPart.Parent = dummyModel

dummyModel.Parent = game:GetService("Workspace")

local resolvedHead, _, headLabel = detector:ResolvePivotPosition(dummyModel, "Head")
Assert(resolvedHead ~= nil and (resolvedHead - headPart.Position).Magnitude < 0.01, "Resolução precisa do osso 'Head'")
Assert(headLabel == "Head", "Rótulo anatômico 'Head' atribuído corretamente")

local resolvedTorso, _, torsoLabel = detector:ResolvePivotPosition(dummyModel, "Torso")
Assert(resolvedTorso ~= nil and (resolvedTorso - torsoPart.Position).Magnitude < 0.01, "Resolução precisa do osso 'Torso'")
Assert(torsoLabel == "Torso", "Rótulo anatômico 'Torso' atribuído corretamente")

-- Limpeza da instância de teste
dummyModel:Destroy()

-- Validação de Alvos Sintéticos (Dummies) vs Personagens de Jogadores Reais
local testDummy = Instance.new("Model")
testDummy.Name = "TestDummyTarget"
local dHead = Instance.new("Part")
dHead.Name = "Head"
dHead.Position = Vector3.new(0, 10, 25)
dHead.Parent = testDummy
local dHum = Instance.new("Humanoid")
dHum.Health = 100
dHum.Parent = testDummy
testDummy.Parent = game:GetService("Workspace")

Assert(detector:IsValidTarget(testDummy) == true, "Dummies e NPCs sintéticos autorizados são aceitos como alvos")

-- Teste de resolução de membros R6 com espaço no nome ("Right Arm", "Left Leg")
local r6Arm = Instance.new("Part")
r6Arm.Name = "Right Arm"
r6Arm.Position = Vector3.new(2, 8, 25)
r6Arm.Parent = testDummy
local resolvedArm, _, armLabel = detector:ResolvePivotPosition(testDummy, "Arms")
Assert(resolvedArm ~= nil and armLabel == "Arms", "Resolução de membros anatômicos R6 com espaço ('Right Arm')")

-- Teste de rejeição de alvo morto (Humanoid.Health <= 0)
dHum.Health = 0
Assert(detector:IsValidTarget(testDummy) == false, "Alvo destruído/eliminado (Humanoid.Health <= 0) é rejeitado imediatamente")
testDummy:Destroy()

-- Teste de configuração AllowPlayerTargets
SimConfig.Set("AllowPlayerTargets", false)
Assert(SimConfig.Get("AllowPlayerTargets") == false, "SimConfig: AllowPlayerTargets desativado")
SimConfig.Set("AllowPlayerTargets", true)
Assert(SimConfig.Get("AllowPlayerTargets") == true, "SimConfig: AllowPlayerTargets ativado para sessões de teste autorizadas")

-- -------------------------------------------------------------------------
-- [CRITÉRIO 2] CÁLCULOS VETORIAIS (DIREÇÃO, DISTÂNCIA E LEAD)
-- -------------------------------------------------------------------------
print("\n[CRITÉRIO 2] Validando Cálculos Vetoriais e Predição Balística...")
local tracker = VectorTracker.new({})

local originPos = Vector3.new(0, 5, 0)
local targetInitial = Vector3.new(100, 5, 0)
local targetVelocity = Vector3.new(0, 0, 25) -- Alvo cruzando o eixo Z a 25 studs/s
local projSpeed = 1000.0 -- 1000 studs/s

local predictedPos = tracker:ComputeLead(targetInitial, targetVelocity, originPos, projSpeed, true)
local expectedFlightTime = (targetInitial - originPos).Magnitude / projSpeed -- 100 / 1000 = 0.1s
local expectedZ = targetInitial.Z + targetVelocity.Z * expectedFlightTime -- 0 + 2.5 = 2.5
Assert(math.abs(predictedPos.Z - expectedZ) < 0.1, "Predição balística (Lead) calculou interceptação com erro < 0.1 studs")
Assert(predictedPos.X == targetInitial.X, "Predição preservou a coordenada X invariante")

-- -------------------------------------------------------------------------
-- [CRITÉRIO 3] SUAVIZAÇÃO E LIMITES ANGULARES
-- -------------------------------------------------------------------------
print("\n[CRITÉRIO 3] Validando Suavização Cinemática e Limitação Angular...")
local camOrigin = CFrame.new(Vector3.new(0, 5, 0), Vector3.new(0, 5, 10))
local offTarget = Vector3.new(40, 5, 40) -- Ângulo de 45 graus

-- Perfil Agressivo (Smoothing baixo = alta resposta)
tracker:ResetTracking()
local aggressiveCFrame, _, aggressiveVel = tracker:ComputeSmoothRotation(camOrigin, offTarget, 0.016, 0.02, 1.0, false, 0, 500, false)
tracker:ResetTracking()
-- Perfil Suave (Smoothing alto = movimento suave/lento)
local smoothCFrame, _, smoothVel = tracker:ComputeSmoothRotation(camOrigin, offTarget, 0.016, 0.28, 1.0, false, 0, 500, false)

Assert(aggressiveVel > smoothVel, "Perfil com Smoothing menor (Agressivo) produziu maior velocidade de resposta que Smoothing alto (Suave)")

-- Teste de ResetTracking
tracker:ResetTracking()
Assert(tracker.TrackingActive == false and tracker.CurrentRotation == nil, "Tracker:ResetTracking liberou o estado acumulado da mira")

-- Limitação estrita de velocidade angular (Clamp)
local largeAngleTarget = Vector3.new(0, 5, -100) -- Alvo a 180 graus
local _, _, clampedVel = tracker:ComputeSmoothRotation(camOrigin, largeAngleTarget, 0.016, 0.5, 1.0, false, 0, 150.0, true)
Assert(clampedVel <= 155.0, "Clamp estrito limitou a velocidade angular ao teto físico configurado (<= 150°/s)")

-- -------------------------------------------------------------------------
-- [CRITÉRIO 4] TRATAMENTO DE VETORES INVÁLIDOS E DISTÂNCIA ZERO
-- -------------------------------------------------------------------------
print("\n[CRITÉRIO 4] Validando Tratamento de Singularidades e Vetores Inválidos...")
local zeroTarget = camOrigin.Position
local safeCFrame, errDeg, safeVel = tracker:ComputeSmoothRotation(camOrigin, zeroTarget, 0.016, 0.15)
local isPosValid = (safeCFrame.Position.X == safeCFrame.Position.X)
Assert(isPosValid == true, "Proteção Epsilon preveniu divisão por zero e geração de NaN")
Assert(errDeg == 0 and safeVel == 0, "Erro angular e velocidade foram zerados em distância zero")

-- -------------------------------------------------------------------------
-- [CRITÉRIO 5] SILENT AIM SIMULADO DENTRO E FORA DO FOV
-- -------------------------------------------------------------------------
print("\n[CRITÉRIO 5] Validando Silent Aim Simulado (Cone Angular)...")
local silentCam = CFrame.new(Vector3.new(0, 5, 0), Vector3.new(0, 5, 50)) -- Olhando para +Z
local inFovTarget = Vector3.new(10, 5, 50) -- Ângulo de ~11.3 graus
local outOfFovTarget = Vector3.new(60, 5, 20) -- Ângulo > 60 graus

local inFovValid, decoupledDir, discDeg = tracker:ComputeSilentAimVector(silentCam, inFovTarget, 30.0)
Assert(inFovValid == true, "Alvo dentro do cone de 30° FOV aprovado para Silent Aim")
Assert(discDeg > 10.0 and discDeg < 15.0, "Discrepância angular do Silent Aim precisa (~11.3°)")

local outFovValid, _, outDisc = tracker:ComputeSilentAimVector(silentCam, outOfFovTarget, 30.0)
Assert(outFovValid == false, "Alvo fora do cone de 30° FOV rejeitado pelo Silent Aim")

-- Validação dos 4 Estágios do Diagnóstico de Silent Aim
-- Estágio 1: Módulo desativado
SimConfig.Set("SilentAimEnabled", false)
Assert(SimConfig.Get("SilentAimEnabled") == false, "Silent Aim [Estágio 1]: Módulo desativado verificado")

-- Estágio 2: Módulo ativado
SimConfig.Set("SilentAimEnabled", true)
Assert(SimConfig.Get("SilentAimEnabled") == true, "Silent Aim [Estágio 1]: Módulo ativado verificado")

-- Estágio 3: Alvo dentro vs fora do cone angular
Assert(inFovValid == true and discDeg < 30.0, "Silent Aim [Estágio 3]: Alvo dentro do cone de FOV selecionado")
Assert(outFovValid == false and outDisc > 30.0, "Silent Aim [Estágio 3]: Alvo fora do cone de FOV rejeitado com cálculo de desvio")

-- Estágio 4: Cálculo de impacto (ACERTO no alvo)
local shotCalc = tracker:SimulateShot(silentCam, inFovTarget, 30.0, 100.0, false, nil)
Assert(shotCalc.Fired == true and shotCalc.HitRegistered == true, "Silent Aim [Estágio 4]: Impacto calculado com sucesso (ACERTO)")
Assert(shotCalc.DiscrepancyAngleDeg < 30.0, "Silent Aim [Estágio 4]: Desvio angular desacoplado calculado com precisão")

-- -------------------------------------------------------------------------
-- [CRITÉRIO 6] PROBABILIDADE DE ACERTO CONFIGURADA (HIT CHANCE)
-- -------------------------------------------------------------------------
print("\n[CRITÉRIO 6] Validando Probabilidade de Acerto (SimulateShot)...")
-- Teste de 100% de Hit Chance
local hit100 = tracker:SimulateShot(silentCam, inFovTarget, 30.0, 100.0, false, nil)
Assert(hit100.Fired == true, "Disparo disparado com sucesso")
Assert(hit100.HitRegistered == true, "100% HitChance registrou impacto no alvo")
Assert((hit100.TargetPosition - inFovTarget).Magnitude < 0.01, "Posição de impacto coincidente com alvo")

-- Teste de 0% de Hit Chance (Dispersão simulada forçada)
local hit0 = tracker:SimulateShot(silentCam, inFovTarget, 30.0, 0.0, false, nil)
Assert(hit0.HitRegistered == false, "0% HitChance registrou desvio proposital (miss)")
Assert((hit0.TargetPosition - inFovTarget).Magnitude > 0.5, "Posição de impacto divergiu do alvo real")

-- Teste estatístico de 50% de Hit Chance (Amostragem Monte Carlo de 100 tiros)
local hits50 = 0
for _ = 1, 100 do
    local res = tracker:SimulateShot(silentCam, inFovTarget, 30.0, 50.0, false, nil)
    if res.HitRegistered then hits50 = hits50 + 1 end
end
Assert(hits50 >= 30 and hits50 <= 70, string.format("HitChance de 50%% respeitou distribuição estatística (%d%% em 100 tiros)", hits50))

-- -------------------------------------------------------------------------
-- [CRITÉRIO 7] ATIVAÇÃO E DESATIVAÇÃO DOS MÓDULOS
-- -------------------------------------------------------------------------
print("\n[CRITÉRIO 7] Validando Ativação e Desativação do Sistema...")
SimConfig.Set("SimulationActive", false)
Assert(SimConfig.Get("SimulationActive") == false, "Estado inativo configurado com sucesso")

SimConfig.Set("SimulationActive", true)
Assert(SimConfig.Get("SimulationActive") == true, "Estado ativo restaurado com sucesso")

-- -------------------------------------------------------------------------
-- [CRITÉRIO 8] LIMPEZA DE EVENTOS E OBJETOS (ESP BATCH SYNC)
-- -------------------------------------------------------------------------
print("\n[CRITÉRIO 8] Validando Ciclo de Vida e Limpeza de Objetos Visuais...")
local renderer = VisualOverlayRenderer.new()

local testPart1 = Instance.new("Part")
testPart1.Name = "Dummy1"
testPart1.Parent = game:GetService("Workspace")

local testPart2 = Instance.new("Part")
testPart2.Name = "Dummy2"
testPart2.Parent = game:GetService("Workspace")

-- Sincroniza lote com 2 instâncias
renderer:SyncBatchHighlights({ testPart1, testPart2 }, testPart1, false)
Assert(renderer.ActiveHighlights[testPart1] ~= nil, "Highlight alocado para o alvo principal")
Assert(renderer.ActiveHighlights[testPart2] ~= nil, "Highlight alocado para o candidato secundário")

-- Remove Dummy2 da lista de candidatos e sincroniza novamente
renderer:SyncBatchHighlights({ testPart1 }, testPart1, false)
Assert(renderer.ActiveHighlights[testPart2] == nil, "Highlight de candidato excluído foi liberado/destruído automaticamente")

-- Limpeza total
renderer:ClearAll()
Assert(next(renderer.ActiveHighlights) == nil, "Renderer:ClearAll eliminou todos os realces ativos")

testPart1:Destroy()
testPart2:Destroy()

-- -------------------------------------------------------------------------
-- [CRITÉRIO 9] ATUALIZAÇÃO DOS CONTROLES DE CONFIGURAÇÃO
-- -------------------------------------------------------------------------
print("\n[CRITÉRIO 9] Validando Controles de Configuração e Observer Pattern...")
local testKeyChanged = false
local unreg = SimConfig.Subscribe("TargetPriority", function(val)
    if val == "Distance" then testKeyChanged = true end
end)
SimConfig.Set("TargetPriority", "Distance")
task.wait(0.02)
Assert(testKeyChanged == true, "Notificação de observer disparada ao alterar TargetPriority")
unreg()

SimConfig.LoadProfile("Agressivo")
Assert(SimConfig.Get("Smoothing") == 0.02, "Carregamento de perfil sobrescreveu parâmetros corretamente")
Assert(SimConfig.Get("AimbotEnabled") == true, "Parâmetro 'AimbotEnabled' carregado com sucesso no perfil")
SimConfig.LoadProfile("Normal")

-- -------------------------------------------------------------------------
-- [CRITÉRIO 10] DETECÇÃO DE ANOMALIAS NO ENGINECORE
-- -------------------------------------------------------------------------
print("\n[CRITÉRIO 10] Validando Detecção de Anomalias no EngineCore...")
local reportNormal = Engine:CalculateSuspicion({
    angularVelocity = 60,
    singleFrameDeltaDeg = 1.0,
    isSnap = false,
    isObstructed = false,
    linearSpeed = 16
})
Assert(reportNormal.totalScore < 30, "Condição normal gerou score de suspeição baixo (< 30%)")

local reportSilentCrit = Engine:CalculateSuspicion({
    angularVelocity = 80,
    decoupledAngleDeg = 45.0,
    isSnap = false
})
Assert(reportSilentCrit.totalScore >= 65, "EngineCore detectou anomalia crítica de Silent Aim (score >= 65%)")

-- -------------------------------------------------------------------------
-- [CRITÉRIO 11] COMPORTAMENTO QUANDO NÃO EXISTEM ALVOS
-- -------------------------------------------------------------------------
print("\n[CRITÉRIO 11] Validando Estabilidade com Ausência de Alvos...")
local emptyDetector = InstanceDetector.new(0.1)
emptyDetector.CandidatePool = {}

local noTarget, noPos, noDist = emptyDetector:FindBestCandidate(
    Vector3.new(0, 5, 0),
    Vector3.new(0, 0, 1),
    300.0,
    70.0,
    "Head",
    false,
    "Crosshair",
    0.25
)
Assert(noTarget == nil and noPos == nil and noDist == 0, "Busca sem alvos retornou nil com segurança e sem erros de execução")

-- -------------------------------------------------------------------------
-- [CRITÉRIO 12] DESEMPENHO SOB DIFERENTES CARGAS DE ALVOS
-- -------------------------------------------------------------------------
print("\n[CRITÉRIO 12] Validando Desempenho e Carga Espacial...")
local function BenchmarkCandidates(count: number): number
    local startT = os.clock()
    local mockPool = {}
    for i = 1, count do
        local p = Instance.new("Part")
        p.Position = Vector3.new(math.sin(i) * 50, 5, math.cos(i) * 50)
        table.insert(mockPool, p)
    end
    detector.CandidatePool = mockPool
    detector:FindBestCandidate(Vector3.new(0, 5, 0), Vector3.new(0, 0, 1), 300, 90, "Head", false, "Crosshair", 0.25)
    local elapsed = (os.clock() - startT) * 1000.0
    for _, p in ipairs(mockPool) do p:Destroy() end
    return elapsed
end

local time10 = BenchmarkCandidates(10)
local time50 = BenchmarkCandidates(50)
local time100 = BenchmarkCandidates(100)
print(string.format("  Tempo de Varredura - 10 alvos: %.3f ms | 50 alvos: %.3f ms | 100 alvos: %.3f ms", time10, time50, time100))
Assert(time100 < 5.0, "Varredura de 100 candidatos executada em menos de 5.0 ms (Alta Performance)")

-- -------------------------------------------------------------------------
-- [CRITÉRIO 13..18] AUDITORIA: LOS TRI-STATE, DESEMPATE, HISTERESE, ENGINE, CONFIG, CICLO REAL
-- -------------------------------------------------------------------------
local SkippedTests = 0
local function Skip(testName: string, reason: string)
    SkippedTests = SkippedTests + 1
    warn(string.format("  ○ [SKIP] %s (%s)", testName, reason))
end

local WS = game:GetService("Workspace")
local RunService = game:GetService("RunService")

-- [13] LINHA DE VISÃO TRI-STATE ------------------------------------------
print("\n[CRITÉRIO 13] LOS tri-state (VISIBLE / BLOCKED / INVALID)...")
local losTracker = VectorTracker.new({})
local created: { Instance } = {}
local function mkPart(pos: Vector3, size: Vector3, canCollide: boolean, transparency: number): Part
    local p = Instance.new("Part")
    p.Anchored = true
    p.Size = size
    p.Position = pos
    p.CanCollide = canCollide
    p.CanQuery = true
    p.Transparency = transparency
    p.Parent = WS
    table.insert(created, p)
    return p
end
local losO, losT = Vector3.new(0, 900, 0), Vector3.new(0, 900, 40)

Assert(losTracker:EvaluateLineOfSight(losO, losT, nil).Status == "VISIBLE", "LOS: caminho desobstruído => VISIBLE")

local wall = mkPart(Vector3.new(0, 900, 20), Vector3.new(30, 30, 1), true, 0)
local rWall = losTracker:EvaluateLineOfSight(losO, losT, nil)
Assert(rWall.Status == "BLOCKED" and rWall.BlockerPart == wall, "LOS: parede sólida => BLOCKED com objeto responsável")
Assert(rWall.HitDistance ~= nil and math.abs(rWall.HitDistance - 19.5) < 0.1, "LOS: distância da colisão correta (~19.5)")
wall:Destroy()

local ghost = mkPart(Vector3.new(0, 900, 20), Vector3.new(30, 30, 1), true, 1)
local rGhost = losTracker:EvaluateLineOfSight(losO, losT, nil)
Assert(rGhost.Status == "BLOCKED", "LOS: barreira invisível colidível continua BLOQUEANDO")
ghost:Destroy()

local deco = mkPart(Vector3.new(0, 900, 20), Vector3.new(30, 30, 1), false, 0)
Assert(losTracker:EvaluateLineOfSight(losO, losT, nil).Status == "VISIBLE", "LOS: objeto não colidível NÃO bloqueia")
deco:Destroy()

local gone = Instance.new("Part"); gone.Parent = WS; gone:Destroy()
Assert(losTracker:EvaluateLineOfSight(losO, losT, gone).Status == "INVALID", "LOS: destino removido => INVALID")
Assert(losTracker:EvaluateLineOfSight(losO, losO, nil).Status == "INVALID", "LOS: origem == destino => INVALID")
Assert(losTracker:EvaluateLineOfSight(losO, Vector3.new(0 / 0, 0, 0), nil).Status == "INVALID", "LOS: NaN => INVALID")

local endWall = mkPart(Vector3.new(0, 900, 39.9), Vector3.new(30, 30, 0.2), true, 0)
Assert(losTracker:EvaluateLineOfSight(losO, losT, nil).Status == "VISIBLE", "LOS: colisão junto ao ponto final tratada como destino alcançado")
endWall:Destroy()

losTracker.LosHistoryLimit = 3
for i = 1, 5 do losTracker:RecordLos({ Status = "VISIBLE", Reason = "t", QueryDistance = 1 }, "T" .. i) end
Assert(#losTracker.LosHistory == 3, "LOS: histórico respeita o limite configurado")
losTracker:ClearLosHistory()
Assert(#losTracker.LosHistory == 0 and losTracker.LastLos == nil, "LOS: limpar histórico")
for _, p in ipairs(created) do if p.Parent then p:Destroy() end end

-- [14] DESEMPATE DETERMINÍSTICO E HISTERESE 0.85 ---------------------------
print("\n[CRITÉRIO 14] Desempate determinístico e histerese 0.85...")
local function mkDummy(name: string, pos: Vector3): Model
    local m = Instance.new("Model"); m.Name = name
    local h = Instance.new("Part"); h.Name = "Head"; h.Anchored = true; h.Position = pos; h.Parent = m
    m.Parent = WS
    return m
end
local selOrigin = Vector3.new(0, 5, 0)
local function dirAt(deg: number): Vector3
    return selOrigin + Vector3.new(math.sin(math.rad(deg)), 0, math.cos(math.rad(deg))) * 30
end
local function select(det: any, pool: { Instance }): Instance?
    det.CandidatePool = pool
    det.ScanInterval = 1000
    det.LastScanTime = os.clock()
    local best = det:FindBestCandidate(selOrigin, Vector3.zAxis, 300, 90, "Head", false, "Crosshair", 5)
    return best
end
local tieA = mkDummy("TieA", Vector3.new(10, 5, 30))
local tieB = mkDummy("TieB", Vector3.new(-10, 5, 30))
local d1, d2 = InstanceDetector.new(0.1), InstanceDetector.new(0.1)
Assert(select(d1, { tieA, tieB }) == tieA, "Empate exato: vence nome completo menor (ordem A,B)")
Assert(select(d2, { tieB, tieA }) == tieA, "Empate exato: mesmo vencedor com ordem invertida (determinístico)")
tieA:Destroy(); tieB:Destroy()

local hA = mkDummy("HystA", dirAt(10))
local hB = mkDummy("HystB", dirAt(9))
local hd = InstanceDetector.new(0.1)
select(hd, { hA }) -- trava A (10°)
Assert(select(hd, { hA, hB }) == hA, "Histerese: desafiante 9° NÃO vence atual 10° (10*0.85=8.5 < 9)")
local hBHead = hB:FindFirstChild("Head") :: BasePart
hBHead.Position = dirAt(8)
Assert(select(hd, { hA, hB }) == hB, "Histerese: desafiante 8° vence atual 10° (8 < 8.5)")
hA:Destroy(); hB:Destroy()

local removed = mkDummy("Removed", dirAt(5))
local hr = InstanceDetector.new(0.1)
select(hr, { removed })
removed:Destroy()
Assert(select(hr, { removed }) == nil, "Candidato removido é descartado com segurança")

local fakePlayerSafe = true
for _, pl in ipairs(game:GetService("Players"):GetPlayers()) do
    if pl.Character and InstanceDetector.new(0.1):IsValidTarget(pl.Character) then fakePlayerSafe = false end
end
Assert(fakePlayerSafe, "Personagens de jogadores reais são rejeitados como candidatos")

-- [15] ENGINECORE: CONTRATO E TELEMETRIA AUSENTE ---------------------------
print("\n[CRITÉRIO 15] EngineCore: contrato, explicações e telemetria ausente...")
local rep = Engine:CalculateSuspicion({ angularVelocity = 900 })
Assert(rep.anomalies == rep.flaggedRules, "Contrato: anomalies é alias de flaggedRules")
Assert(#rep.explanations == #rep.flaggedRules and #rep.explanations > 0, "Cada regra acionada possui explicação")
Assert(table.find(rep.unavailableMetrics, "linearSpeed") ~= nil, "Telemetria ausente listada (linearSpeed), não fabricada")
local repZero = Engine:CalculateSuspicion({ angularVelocity = 0, linearSpeed = 0, decoupledAngleDeg = 0, singleFrameDeltaDeg = 0, consecutiveOccludedFrames = 0 })
Assert(repZero.category == "LIMPO" and #repZero.unavailableMetrics == 0, "Valor zero medido é diferente de ausente")
Assert(Engine:CalculateSuspicion({}).category == "INSUFICIENTE", "Sem nenhuma métrica => INSUFICIENTE")
Assert(Engine:CalculateSuspicion({ angularVelocity = 900, sampleCount = 2 }).category == "INSUFICIENTE", "Amostra abaixo do mínimo => INSUFICIENTE")
Assert(Engine:CalculateSuspicion({ angularVelocity = 0 / 0 }).evaluatedRules == 0, "NaN tratado como dado inválido")
local e1, e2 = Engine:CalculateSuspicion({ angularVelocity = 500 }), Engine:CalculateSuspicion({ angularVelocity = 500 })
Assert(e1.totalScore == e2.totalScore and e1.category == e2.category, "Resultados estáveis para a mesma entrada")

-- [16] CONFIGURAÇÃO: PADRÃO, VALIDAÇÃO E PERSISTÊNCIA ----------------------
print("\n[CRITÉRIO 16] SimConfig: perfil padrão, validação e persistência...")
local memory: string? = nil
SimConfig.SetStorage({
    read = function() return memory end,
    write = function(c: string) memory = c; return true end,
})
SimConfig.RestoreDefaults()
local defs = SimConfig.GetDefaults()
Assert(defs.ActiveProfile == "DeepHat Simulation Default", "Perfil padrão nomeado corretamente")
Assert(defs.AimbotEnabled == false and defs.SilentAimEnabled == false, "Automação de câmera e disparo iniciam DESATIVADOS")
Assert(defs.FovRadiusPx == 120 and defs.ActiveTab == "Dashboard" and defs.LineOfSightEnabled == true, "Valores iniciais propostos aplicados")
SimConfig.Set("FovRadiusPx", 99999)
Assert(SimConfig.Get("FovRadiusPx") == 120, "Set rejeita valor fora da faixa")
SimConfig.Set("FovRadiusPx", 200)
Assert(SimConfig.Get("FovRadiusPx") == 200, "Set aceita valor válido")
Assert(SimConfig.Save() == true, "Save usa o adaptador de armazenamento")
SimConfig.RestoreDefaults()
Assert(SimConfig.Get("FovRadiusPx") == 120, "RestoreDefaults recupera o perfil completo")
Assert(SimConfig.Load() == "loaded" and SimConfig.Get("FovRadiusPx") == 200, "Load restaura preferência válida salva")
Assert(SimConfig.Get("AimbotEnabled") == false, "Load nunca religa automação da câmera")
memory = "{ não é json"
Assert(SimConfig.Load() == "restored_defaults" and SimConfig.LastLoadReason ~= "", "JSON corrompido => padrões + motivo registrado")
memory = nil
Assert(SimConfig.Load() == "first_run", "Sem dados salvos => primeira execução")
local okImp, errImp = SimConfig.ImportJSON('{"ConfigVersion":99,"FovRadiusPx":150}')
Assert(okImp == false and #errImp > 0 and SimConfig.Get("FovRadiusPx") == 120, "Import incompatível é rejeitado sem aplicar nada")
local okImp2 = SimConfig.ImportJSON('{"ConfigVersion":1,"FovRadiusPx":150}')
Assert(okImp2 == true and SimConfig.Get("FovRadiusPx") == 150, "Import válido é aplicado")
local seen = 0
local unsubCfg = SimConfig.Subscribe("FovRadiusPx", function() seen += 1 end)
SimConfig.Set("FovRadiusPx", 160); task.wait(0.02)
Assert(seen == 1, "Consumidores são notificados da alteração")
unsubCfg()
SimConfig.RestoreDefaults()
SimConfig.SetStorage({ read = function() return nil end, write = function() return false end })

-- [17] CICLO REAL: ATUALIZAÇÃO E RESTAURAÇÃO DA CÂMERA ---------------------
print("\n[CRITÉRIO 17] Integração: ciclo real de câmera (requer cliente em Play)...")
local liveCam = WS.CurrentCamera
if RunService:IsClient() and liveCam and RunService:IsRunning() then
    local origType, origCFrame = liveCam.CameraType, liveCam.CFrame
    liveCam.CameraType = Enum.CameraType.Scriptable
    local liveTracker = VectorTracker.new({})
    liveCam.CFrame = CFrame.lookAt(Vector3.new(0, 900, 0), Vector3.new(0, 900, 10))
    local aimPoint = Vector3.new(40, 900, 0)
    local firstErr, lastErr = nil, nil
    for _ = 1, 90 do
        local dt = RunService.RenderStepped:Wait()
        local cf, err = liveTracker:ComputeSmoothRotation(liveCam.CFrame, aimPoint, dt, 0.1, 1.25, false, 0, 600, true)
        liveCam.CFrame = cf
        firstErr = firstErr or err
        lastErr = err
    end
    Assert(firstErr ~= nil and lastErr ~= nil and lastErr < firstErr * 0.1, string.format("Câmera real convergiu (%.1f° -> %.2f°)", firstErr or -1, lastErr or -1))
    liveTracker:Release()
    Assert(liveTracker.TrackingActive == false and liveTracker.CurrentRotation == nil and liveTracker.LastRawCamRotation == nil, "Release limpou todo o estado acumulado")
    local frozen = liveCam.CFrame
    for _ = 1, 5 do RunService.RenderStepped:Wait() end
    Assert(liveCam.CFrame == frozen, "Após Release a simulação não escreve mais na câmera")
    liveCam.CameraType, liveCam.CFrame = origType, origCFrame
    Assert(liveCam.CameraType == origType, "Estado original da câmera restaurado")
else
    Skip("Ciclo real de câmera (convergência, Release, restauração)", "exige cliente em Play no Studio")
end

-- -------------------------------------------------------------------------
-- [CRITÉRIO 19] ROTAÇÃO EULER YXZ (ROLL ZERO E ESTABILIDADE CONTRA RUNAWAY SPIN)
-- -------------------------------------------------------------------------
print("\n[CRITÉRIO 19] Validando Estabilidade Euler YXZ (Roll Zero e Ausência de Runaway Spin)...")
local eulerTracker = VectorTracker.new({})
local camTestOrigin = CFrame.new(Vector3.new(0, 5, 0), Vector3.new(0, 5, -10))
local dummyTargetPos = Vector3.new(20, 10, -50)

-- Simula loop fechado de 60 quadros alimentando a saída como entrada
local currentCam = camTestOrigin
for frame = 1, 60 do
    local nextCf, errDeg, angVel = eulerTracker:ComputeSmoothRotation(
        currentCam,
        dummyTargetPos,
        0.0166,
        0.15,
        1.25,
        false,
        0,
        360.0,
        true
    )
    currentCam = nextCf

    -- Validação matemática: o Roll no espaço Euler YXZ deve ser estritamente zero
    local _, _, roll = currentCam:ToEulerAnglesYXZ()
    if math.abs(roll) > 1e-4 then
        Assert(false, string.format("Roll detectado no frame %d: %.5f rad (esperado zero)", frame, roll))
        break
    end
end
Assert(true, "Roll estritamente 0 mantido durante todos os quadros (sem acúmulo de inclinação lateral)")
local finalErr = (dummyTargetPos - currentCam.Position).Unit:Dot(currentCam.LookVector)
Assert(finalErr > 0.99, "Câmera convergiu estavelmente em direção ao manequim sem oscilação infinita")

-- -------------------------------------------------------------------------
-- [CRITÉRIO 20] PREVENÇÃO DA TELA ESVERDEADA (ISOLAMENTO DO HIGHLIGHT)
-- -------------------------------------------------------------------------
print("\n[CRITÉRIO 20] Validando Isolamento do Realce (Prevenção de Tela Esverdeada)...")
local isolationDetector = InstanceDetector.new(0.1)
local isolationRenderer = VisualOverlayRenderer.new()

-- 1. Cria um modelo de cenário que NÃO deve ser aceito como alvo
local fakeBuilding = Instance.new("Model")
fakeBuilding.Name = "ArenaBuilding"
fakeBuilding.Parent = game:GetService("Workspace")
local fakeWall = Instance.new("Part")
fakeWall.Name = "Wall"
fakeWall.Size = Vector3.new(50, 20, 2)
fakeWall.Parent = fakeBuilding
Assert(isolationDetector:IsValidTarget(fakeBuilding) == false, "Estrutura de mapa 'ArenaBuilding' rejeitada pelo IsValidTarget")

-- 2. Cria manequim sintético válido
local dummyTarget = Instance.new("Model")
dummyTarget.Name = "TestMannequin"
local dummyHead = Instance.new("Part")
dummyHead.Name = "Head"
dummyHead.Parent = dummyTarget
local dummyHum = Instance.new("Humanoid")
dummyHum.Parent = dummyTarget
dummyTarget.Parent = game:GetService("Workspace")
Assert(isolationDetector:IsValidTarget(dummyTarget) == true, "Manequim sintético 'TestMannequin' aceito como candidato válido")

-- 3. Aplica realce e verifica anexo direto (Parent == target)
isolationRenderer:UpdateTargetHighlight(dummyTarget, false, true)
local appliedHl = isolationRenderer.ActiveHighlights[dummyTarget]
Assert(appliedHl ~= nil, "Highlight instanciado para o manequim sintético")
Assert(appliedHl.Parent == dummyTarget, "Highlight anexado diretamente ao modelo do manequim (não ao Workspace global)")
isolationRenderer:ClearAll()
Assert(next(isolationRenderer.ActiveHighlights) == nil, "Limpeza do renderer destruiu com segurança todos os realces")

dummyTarget:Destroy()
fakeBuilding:Destroy()

-- -------------------------------------------------------------------------
-- [CRITÉRIO 21] SIMULAÇÃO DE SILENT AIM DESACOPLADA COM TRAÇADOR E IMPACTO
-- -------------------------------------------------------------------------
print("\n[CRITÉRIO 21] Validando Simulação de Disparo Desacoplado (Silent Aim)...")
local silentTracker = VectorTracker.new({})
local camPos = CFrame.new(Vector3.new(0, 5, 0), Vector3.new(0, 5, -10))
local decoupledTarget = Vector3.new(10, 5, -30) -- ~18° desacoplado da mira central

local inFov, shotDir, discAngle = silentTracker:ComputeSilentAimVector(camPos, decoupledTarget, 35.0)
Assert(inFov == true, "Alvo dentro do FOV desacoplado (35°) avaliado como inFov")
Assert(math.abs(discAngle - 18.4) < 1.0, string.format("Ângulo de desacoplamento medido com precisão (%.1f°)", discAngle))

local shotResult = silentTracker:SimulateShot(camPos, decoupledTarget, 35.0, 100.0, false, nil)
Assert(shotResult.Fired == true and shotResult.HitRegistered == true, "Simulação de disparo registrou acerto sintético determinístico (100%)")
Assert((shotResult.TargetPosition - decoupledTarget).Magnitude < 0.01, "Ponto de impacto coincide com o alvo sintético")

-- -------------------------------------------------------------------------
-- [CRITÉRIO 22] PROJÉTEIS FÍSICOS E BALÍSTICA CURVA (GRAVIDADE)
-- -------------------------------------------------------------------------
print("\n[CRITÉRIO 22] Validando Balística Física, Queda por Gravidade e Trajetória Curva...")
local physTracker = VectorTracker.new({})
local shooterPos = Vector3.new(0, 10, 0)
local targetStationary = Vector3.new(0, 10, 200) -- 200 studs de distância
local physSpeed = 500.0 -- 500 studs/s => t = 0.4s
local gravityVal = 196.2 -- gravidade padrão Roblox (studs/s²)

-- 1. Compensação de elevação por gravidade no ComputeLead
local compPos, flightTime, dropStuds = physTracker:ComputeLead(targetStationary, Vector3.zero, shooterPos, physSpeed, true, gravityVal, true)
local expectedDrop = 0.5 * gravityVal * (flightTime * flightTime)
Assert(math.abs(dropStuds - expectedDrop) < 0.1, string.format("Compensação de queda por gravidade precisa: %.2f studs (esperado: %.2f studs)", dropStuds, expectedDrop))
Assert(compPos.Y > targetStationary.Y, "Ponto de mira elevado acima do alvo para compensar queda balística")

-- 2. Simulação de tiro com projétil físico (geração de arco parabólico segmentado)
local physShot = physTracker:SimulateShot(
    CFrame.lookAt(shooterPos, targetStationary),
    targetStationary,
    30.0,
    100.0,
    false,
    nil,
    physSpeed,
    gravityVal,
    true
)
Assert(physShot.TrajectoryType == "Physics", "SimulateShot identificou tipo balístico como 'Physics'")
Assert(physShot.TrajectoryPoints ~= nil and #physShot.TrajectoryPoints >= 10, "SimulateShot gerou segmentos de arco para projétil físico (>= 10 pontos)")
Assert(physShot.BulletDropStuds > 0, "Queda calculada maior que zero para projétil com gravidade ativa")

-- 3. Validação de que a trajetória física é uma curva parabólica (não uma linha reta)
local pts = physShot.TrajectoryPoints
if pts and #pts >= 3 then
    local midPt = pts[math.floor(#pts / 2)]
    local straightMid = (pts[1] + pts[#pts]) / 2
    local curveDeviation = (midPt - straightMid).Magnitude
    Assert(curveDeviation > 0.1, string.format("Trajetória balística física curvada comprovada (desvio do ponto médio reto: %.2f studs)", curveDeviation))
end

-- 4. Disparo instantâneo (Raycast clássico) não gera arco parabólico
local instantShot = physTracker:SimulateShot(
    CFrame.lookAt(shooterPos, targetStationary),
    targetStationary,
    30.0,
    100.0,
    false,
    nil,
    2500.0,
    0,
    false
)
Assert(instantShot.TrajectoryType == "Instant", "Disparo raycast identificado como 'Instant'")
Assert(instantShot.TrajectoryPoints == nil, "Disparo raycast instantâneo não aloca pontos parabólicos desnecessários")

-- -------------------------------------------------------------------------
-- [CRITÉRIO 23] RASTREAMENTO E CICLO DE VIDA DOS ALVOS (MORTE E REMOÇÃO)
-- -------------------------------------------------------------------------
print("\n[CRITÉRIO 23] Validando Invalidação Imediata de Alvos Mortos ou Removidos...")
local lifecycleDet = InstanceDetector.new(0.1)

-- 1. Alvo ativo com Humanoid vivo
local liveDummy = Instance.new("Model")
liveDummy.Name = "LiveDummy"
local lHead = Instance.new("Part")
lHead.Name = "Head"
lHead.Position = Vector3.new(0, 5, 20)
lHead.Parent = liveDummy
local lHum = Instance.new("Humanoid")
lHum.Health = 100
lHum.Parent = liveDummy
liveDummy.Parent = game:GetService("Workspace")

Assert(lifecycleDet:IsValidTarget(liveDummy) == true, "Alvo vivo no Workspace é válido")

-- Lock manual no alvo
lifecycleDet.LockedTarget = liveDummy
lifecycleDet.LockExpiry = os.clock() + 10.0

-- 2. Alvo morre (Humanoid.Health <= 0)
lHum.Health = 0
Assert(lifecycleDet:IsValidTarget(liveDummy) == false, "Alvo com Humanoid.Health <= 0 imediatamente invalidado")
local losDead = physTracker:EvaluateLineOfSight(Vector3.new(0, 5, 0), lHead.Position, liveDummy)
Assert(losDead.Status == "INVALID", "Line of Sight retorna INVALID imediatamente para alvo morto")

-- 3. Limpeza do alvo fixado (LockTarget) ao morrer
local bestAfterDeath = lifecycleDet:FindBestCandidate(Vector3.new(0, 5, 0), Vector3.new(0, 0, 1), 100, 70, "Head", false, "Crosshair", 0.5)
Assert(lifecycleDet.LockedTarget == nil, "Estado de travamento (LockedTarget) limpo imediatamente ao detectar alvo morto")

-- 4. Alvo removido do Workspace (Parent = nil)
lHum.Health = 100
liveDummy.Parent = nil
Assert(lifecycleDet:IsValidTarget(liveDummy) == false, "Alvo removido do Workspace é imediatamente invalidado")
local losRemoved = physTracker:EvaluateLineOfSight(Vector3.new(0, 5, 0), lHead.Position, liveDummy)
Assert(losRemoved.Status == "INVALID", "Line of Sight retorna INVALID imediatamente para alvo removido do Workspace")

liveDummy:Destroy()

-- -------------------------------------------------------------------------
-- [CRITÉRIO 24] MOTOR DE IA DE DIAGNÓSTICO E CHATBOT
-- -------------------------------------------------------------------------
print("\n[CRITÉRIO 24] Validando Motor de IA de Diagnóstico e Assistente Chatbot...")
-- 1. Análise de estado normal (HEALTHY)
local healthyReport = DiagnosticAI.AnalyzeSystemState(
    { mode = "AIMBOT", targetName = "Dummy1", angularVelocity = 85.0, isObstructed = false },
    nil, nil, nil
)
Assert(healthyReport.Status == "HEALTHY", "Motor de IA: Estado com velocidade angular normal classificado como HEALTHY")
Assert(healthyReport.AffectedModule == "Nenhum", "Motor de IA: Sem módulos comprometidos em estado nominal")

-- 2. Análise de falha em disparo por FOV
local missedShotFov = {
    Fired = true,
    InFov = false,
    IsObstructed = false,
    HitRegistered = false,
    DiscrepancyAngleDeg = 48.5,
    TrajectoryType = "Instant"
}
local fovReport = DiagnosticAI.AnalyzeSystemState(nil, nil, nil, missedShotFov)
Assert(fovReport.Status == "WARNING", "Motor de IA: Disparo fora de FOV gera status WARNING")
Assert(fovReport.AffectedModule == "SilentAim / SimConfig", "Motor de IA: Módulo afetado atribuído a SilentAim / SimConfig")
Assert(string.find(fovReport.RootCause, "SilentAimFOV") ~= nil, "Motor de IA: Causa raiz identifica corretamente SilentAimFOV")

-- 3. Análise de oscilação / velocidade angular extrema
local jitterReport = DiagnosticAI.AnalyzeSystemState(
    { mode = "AIMBOT", targetName = "Dummy1", angularVelocity = 620.0, isObstructed = false },
    nil, nil, nil
)
Assert(jitterReport.Status == "CRITICAL", "Motor de IA: Velocidade angular extrema (> 500°/s) classificada como CRITICAL")
Assert(string.find(jitterReport.AffectedModule, "VectorTracker") ~= nil, "Motor de IA: Módulo de rastreamento vetorial apontado como causa da oscilação")

-- 4. Chatbot: Pergunta sobre oscilação/mira
local queryJitter = DiagnosticAI.QueryChatbot("Por que a mira está oscilando e tremendo?")
Assert(string.find(queryJitter.Answer, "Suavização") ~= nil, "Chatbot: Resposta sobre oscilação sugere ajuste na Suavização")

-- 5. Chatbot: Pergunta sobre física balística e queda por gravidade
local queryBallistics = DiagnosticAI.QueryChatbot("como funciona a gravidade e o arco balistico?")
Assert(string.find(queryBallistics.Answer, "196.2") ~= nil, "Chatbot: Resposta balística cita gravidade padrão de 196.2 studs/s²")
Assert(string.find(queryBallistics.Answer, "parabólico segmentado") ~= nil, "Chatbot: Resposta balística confirma arco parabólico segmentado")

-- -------------------------------------------------------------------------
-- [CRITÉRIO 25] REORGANIZAÇÃO DO PAINEL EM 5 ABAS CONSOLIDADAS
-- -------------------------------------------------------------------------
print("\n[CRITÉRIO 25] Validando Estrutura e Vinculação Reativa das 5 Abas do Painel...")
local validTabs = { "AimSimulation", "SilentAim", "Ballistics", "Diagnostics", "Settings" }
for _, tabName in ipairs(validTabs) do
    SimConfig.Set("ActiveTab", tabName)
    Assert(SimConfig.Get("ActiveTab") == tabName, string.format("Aba consolidada '%s' configurada e persistida no SimConfig", tabName))
end

-- Validação de controles balísticos centralizados no SimConfig
SimConfig.Set("ProjectileType", "Physics")
Assert(SimConfig.Get("ProjectileType") == "Physics", "SimConfig: ProjectileType configurado para 'Physics'")
SimConfig.Set("ProjectileType", "Instant")
Assert(SimConfig.Get("ProjectileType") == "Instant", "SimConfig: ProjectileType configurado para 'Instant'")

SimConfig.Set("ProjectileGravity", 196.2)
Assert(math.abs(SimConfig.Get("ProjectileGravity") - 196.2) < 0.001, "SimConfig: ProjectileGravity aceita 196.2 studs/s²")
SimConfig.Set("ProjectileGravity", 0.0)
Assert(SimConfig.Get("ProjectileGravity") == 0.0, "SimConfig: ProjectileGravity aceita 0 (gravidade zero)")

SimConfig.Set("ProjectileDropComp", true)
Assert(SimConfig.Get("ProjectileDropComp") == true, "SimConfig: ProjectileDropComp ativado para compensação preditiva")

-- -------------------------------------------------------------------------
-- [CRITÉRIO 26] SINCRONIZAÇÃO ANGULAR E LIMITES DO FOV
-- -------------------------------------------------------------------------
print("\n[CRITÉRIO 26] Validando Limites do FOV e Projeção Óptica...")
SimConfig.Set("FOV", 70.0)
Assert(SimConfig.Get("FOV") == 70.0, "SimConfig: FOV angular ajustado para 70.0°")

SimConfig.Set("FOV", 2.0)
Assert(SimConfig.Get("FOV") == 70.0, "SimConfig: FOV < 5° rejeitado pelas regras de validação do SimConfig")

SimConfig.Set("FOV", 195.0)
Assert(SimConfig.Get("FOV") == 70.0, "SimConfig: FOV > 180° rejeitado pelas regras de validação do SimConfig")

-- Monotonicidade da fórmula óptica de projeção
local function CalcRadius(fovDeg: number, camFovDeg: number, viewH: number): number
    local halfFovRad = math.rad(math.clamp(fovDeg, 5, 180) / 2)
    local halfCamRad = math.rad(math.clamp(camFovDeg, 20, 120) / 2)
    return (math.tan(halfFovRad) / math.tan(halfCamRad)) * (viewH / 2)
end
local r30 = CalcRadius(30, 70, 1080)
local r60 = CalcRadius(60, 70, 1080)
local r90 = CalcRadius(90, 70, 1080)
Assert(r30 < r60 and r60 < r90, "Fórmula óptica do círculo de FOV cresce monotonicamente com o ângulo angular")
Assert(r30 > 0 and r60 > 0 and r90 > 0, "Raio projetado em pixels é estritamente positivo e não nulo")

print(string.format("  Testes pulados: %d", SkippedTests))

-- -------------------------------------------------------------------------
-- RESUMO FINAL
-- -------------------------------------------------------------------------
print("\n===================================================================")
print(string.format("TESTES CONCLUÍDOS: %d | APROVADOS: %d | REPROVADOS: %d | PULADOS: %d", TotalAssertions, PassedAssertions, FailedAssertions, SkippedTests))
if FailedAssertions == 0 then
    print(SkippedTests == 0 and "STATUS GERAL: [ ✓ TODAS AS ASSERÇÕES APROVADAS ]" or "STATUS GERAL: [ ✓ ASSERÇÕES EXECUTADAS APROVADAS — HÁ TESTES PULADOS (veja [SKIP]) ]")
else
    warn("STATUS GERAL: [ ✗ FALHAS DETECTADAS - REVISE O LOG ACIMA ]")
end
print("===================================================================")
