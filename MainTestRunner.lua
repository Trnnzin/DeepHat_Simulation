--!strict
-- =========================================================================
-- MainTestRunner.lua
-- Executor Automatizado de Testes Unitários e Integração (Studio & CI Console)
-- Validação: SimConfig, VectorTracker, EngineCore, Tolerâncias e Anomalias
-- =========================================================================

local Engine = require(script.Parent.EngineCore)
local Simulator = require(script.Parent.BehaviorSimulator)
local SimConfig = require(script.Parent.ModularSystem.SimConfig)
local VectorTracker = require(script.Parent.ModularSystem.VectorTracker)

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
print("       DEEPHAT SIMULATION SUITE // AUTOMATED TEST RUNNER           ")
print("===================================================================")

-- -------------------------------------------------------------------------
-- [TEST SUITE 1] VALIDAÇÃO DO SIMCONFIG (OBSERVER & PERSISTÊNCIA)
-- -------------------------------------------------------------------------
print("\n[SUITE 1] Validando SimConfig e Observer Pattern...")

local initialFov = SimConfig.Get("FOV")
Assert(typeof(initialFov) == "number", "SimConfig.Get('FOV') retorna número válido")

local observerFired = false
local unsubscribe = SimConfig.Subscribe("Smoothing", function(newVal)
    if newVal == 0.42 then
        observerFired = true
    end
end)

SimConfig.Set("Smoothing", 0.42)
task.wait(0.05) -- aguarda task.spawn do observer
Assert(observerFired == true, "Observer de chave específica notificado com sucesso")
unsubscribe()

SimConfig.LoadProfile("Agressivo")
Assert(SimConfig.Get("ActiveProfile") == "Agressivo", "Carregamento do perfil 'Agressivo'")
Assert(SimConfig.Get("Smoothing") == 0.02, "Parâmetro 'Smoothing' atualizado pelo perfil")

-- Teste de Exportação / Importação JSON
local exportedJson = SimConfig.ExportJSON()
Assert(#exportedJson > 20, "Exportação JSON gerou payload válido")

local importOk = SimConfig.ImportJSON(exportedJson)
Assert(importOk == true, "Importação JSON desserializada com sucesso")

-- Restaura perfil Normal
SimConfig.LoadProfile("Normal")

-- -------------------------------------------------------------------------
-- [TEST SUITE 2] VALIDAÇÃO MATEMÁTICA DO VECTORTRACKER (GUARDA EPSILON & LERP)
-- -------------------------------------------------------------------------
print("\n[SUITE 2] Validando VectorTracker (Álgebra Linear & Prevenção de NaN)...")

local tracker = VectorTracker.new({})

-- 1. Teste de Epsilon (origem igual ao destino)
local eyePos = Vector3.new(0, 5, 0)
local originCFrame = CFrame.new(eyePos, eyePos + Vector3.new(0, 0, 10))
local safeCFrame, errDeg, angVel = tracker:ComputeSmoothRotation(originCFrame, eyePos, 0.016, 0.15)
local isPosValid = (safeCFrame.Position.X == safeCFrame.Position.X) -- Checa por NaN
Assert(isPosValid == true, "Guarda Epsilon impediu vetor indefinido/NaN em distância zero")
Assert(errDeg == 0, "Erro angular zero quando origem == destino")

-- 2. Teste de Rotação Suavizada em Alvo Real
local targetPos = Vector3.new(50, 5, 50)
local smoothedCFrame, rotError, calculatedVel = tracker:ComputeSmoothRotation(originCFrame, targetPos, 0.016, 0.15)
Assert(smoothedCFrame.Position == eyePos, "Preservação da posição do olho da câmera durante rotação")
Assert(rotError > 0 and rotError <= 180, "Cálculo preciso do erro angular")
Assert(calculatedVel > 0, "Cálculo não-nulo de velocidade angular instantânea")

-- 3. Teste de Rotação Snap Instantânea
local snapCFrame, _, snapVel = tracker:ComputeSnapRotation(originCFrame, targetPos, 0.016)
local snapLook = snapCFrame.LookVector
local targetDir = (targetPos - eyePos).Unit
local dot = snapLook:Dot(targetDir)
Assert(math.abs(dot - 1.0) < 0.001, "Modo Snap alinhou o LookVector perfeitamente em 1 frame")
Assert(snapVel > 1000, "Modo Snap gerou velocidade angular compatível com rotação brusca")

-- 4. Teste de Predição Balística (Lead Tracking)
local targetInitial = Vector3.new(100, 0, 0)
local targetVelocity = Vector3.new(0, 0, 20)
local predictedPos = tracker:ComputeLead(targetInitial, targetVelocity, Vector3.zero, 1000, true)
Assert(predictedPos.Z > targetInitial.Z, "Predição balística antecipou o vetor de deslocamento do alvo")

-- -------------------------------------------------------------------------
-- [TEST SUITE 3] SESSÃO DE TESTES CONTROLADA (DETECÇÃO DE ANOMALIAS)
-- -------------------------------------------------------------------------
print("\n[SUITE 3] Executando Sessões de Teste Controladas de Comportamento...")

local function RunControlledSession(profileKey: string, iterations: number)
    local prof = Engine.Profiles[profileKey]
    local totalScore = 0
    local streak = 0

    for _ = 1, iterations do
        local mData = Simulator:SimulateMovement(prof)
        local aData = Simulator:SimulateAim(prof, 0.016)
        local vData = Simulator:SimulateVision(prof, streak)
        streak = vData.consecutiveOccluded

        local report = Engine:CalculateSuspicion({
            angularVelocity = aData.angularVel,
            singleFrameDeltaDeg = aData.deltaAngleDeg,
            isSnap = aData.isSnap,
            isObstructed = vData.isWallTracking,
            consecutiveOccludedFrames = vData.consecutiveOccluded,
            linearSpeed = mData.velocity
        })

        totalScore = totalScore + report.totalScore
    end

    return totalScore / iterations
end

local avgNormal = RunControlledSession("NORMAL", 25)
print(string.format("  Média de Suspeita (Perfil NORMAL): %.1f%%", avgNormal))
Assert(avgNormal < 40.0, "Perfil Normal gerou score médio de suspeita baixo (< 40%)")

local avgAgressivo = RunControlledSession("AGRESSIVO", 25)
print(string.format("  Média de Suspeita (Perfil AGRESSIVO): %.1f%%", avgAgressivo))
Assert(avgAgressivo > 65.0, "Perfil Agressivo disparou alertas heurísticos de anomalia (> 65%)")

-- -------------------------------------------------------------------------
-- RESUMO FINAL
-- -------------------------------------------------------------------------
print("\n===================================================================")
print(string.format("TESTES CONCLUÍDOS: %d | APROVADOS: %d | REPROVADOS: %d", TotalAssertions, PassedAssertions, FailedAssertions))
if FailedAssertions == 0 then
    print("STATUS GERAL: [ ✓ SISTEMA 100% OPERACIONAL E HOMOLOGADO ]")
else
    warn("STATUS GERAL: [ ✗ FALHAS DETECTADAS - REVISE O LOG ACIMA ]")
end
print("===================================================================")
