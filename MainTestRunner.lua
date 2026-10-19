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

local TotalAssertions = 0
local PassedAssertions = 0
local FailedAssertions = 0

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
-- RESUMO FINAL
-- -------------------------------------------------------------------------
print("\n===================================================================")
print(string.format("TESTES CONCLUÍDOS: %d | APROVADOS: %d | REPROVADOS: %d", TotalAssertions, PassedAssertions, FailedAssertions))
if FailedAssertions == 0 then
    print("STATUS GERAL: [ ✓ TODOS OS 12 CRITÉRIOS APROVADOS COM 100% DE SUCESSO ]")
else
    warn("STATUS GERAL: [ ✗ FALHAS DETECTADAS - REVISE O LOG ACIMA ]")
end
print("===================================================================")
