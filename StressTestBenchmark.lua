--!strict
-- =========================================================================
-- StressTestBenchmark.lua
-- Benchmark de Estresse Cinemático, Oclusão Geométrica e Tolerância a Carga
-- Valida estabilidade sob 1000+ iterações de cálculo matricial e raycasts
-- =========================================================================

local VectorTracker = require(script.Parent.ModularSystem.VectorTracker)
local LineOfSightSimulator = require(script.Parent.LineOfSightSimulator)

local tracker = VectorTracker.new({})
local los = LineOfSightSimulator.new({})

local testTargets = {
    Vector3.new(40, 5, 15),
    Vector3.new(-35, 8, -25),
    Vector3.new(0, 20, 50),
    Vector3.new(120, -10, 80),
    Vector3.new(-80, 15, -120),
}

print("===================================================================")
print("       BENCHMARK DE ESTRESSE CINEMÁTICO E DESEMPENHO (1000 CYCLES)  ")
print("===================================================================")

-- Bateria 1: Stress de Interpolação Lerp e Detecção de NaN
print("\n[FASE 1] Executando 1.000 iterações de Interpolação Contínua...")

local currentCamCFrame = CFrame.new(0, 5, 0)
local nanDetected = false
local totalDurationSec = 0
local peakAngularVelocity = 0

local startTime = os.clock()

for i = 1, 1000 do
    local target = testTargets[(i % #testTargets) + 1]
    local dt = 1 / 60.0

    local newCFrame, errDeg, angVel = tracker:ComputeSmoothRotation(currentCamCFrame, target, dt, 0.15, 1.25, true, 50)
    currentCamCFrame = newCFrame

    if angVel > peakAngularVelocity then
        peakAngularVelocity = angVel
    end

    local pos = currentCamCFrame.Position
    if pos.X ~= pos.X or pos.Y ~= pos.Y or pos.Z ~= pos.Z then
        nanDetected = true
        break
    end
end

local elapsedSec = os.clock() - startTime
local avgMicroSecPerStep = (elapsedSec / 1000) * 1000000

print(string.format("  Tempo total: %.4f s | Tempo médio por ciclo: %.2f µs", elapsedSec, avgMicroSecPerStep))
print(string.format("  Pico de Velocidade Angular: %.1f °/s", peakAngularVelocity))
print(string.format("  Indeterminação Numérica (NaN): %s", nanDetected and "SIM (FALHA!)" or "NÃO (100% SEGURO)"))

-- Bateria 2: Stress de Raycasting de Oclusão (500 Raios)
print("\n[FASE 2] Executando 500 Raycasts de Linha de Visada...")

local rayStartTime = os.clock()
local rayErrors = 0

for i = 1, 500 do
    local origin = currentCamCFrame.Position
    local target = testTargets[(i % #testTargets) + 1]

    local ok, res = pcall(function()
        return los:EvaluateLineOfSight(origin, target)
    end)

    if not ok or not res then
        rayErrors = rayErrors + 1
    end
end

local rayElapsedSec = os.clock() - rayStartTime
local avgRayMicroSec = (rayElapsedSec / 500) * 1000000

print(string.format("  Tempo total: %.4f s | Tempo médio por raycast: %.2f µs", rayElapsedSec, avgRayMicroSec))
print(string.format("  Erros de Execução de Raycast: %d", rayErrors))

-- Bateria 3: Verificação de Recuperação de Vetor Nulo (Epsilon Test)
print("\n[FASE 3] Teste de Singularidade Geométrica (Distância Zero)...")
local zeroOrigin = Vector3.new(10, 20, 30)
local zeroCFrame = CFrame.new(zeroOrigin)
local recoveredCFrame, zeroErr, zeroVel = tracker:ComputeSmoothRotation(zeroCFrame, zeroOrigin, 1/60, 0.2)
local isZeroSafe = (recoveredCFrame.Position == zeroOrigin and zeroErr == 0 and zeroVel == 0)
print(string.format("  Proteção de singularidade em vetor de deslocamento nulo: %s", isZeroSafe and "PASSOU" or "FALHOU"))

print("\n===================================================================")
if not nanDetected and rayErrors == 0 and isZeroSafe then
    print("✓ BENCHMARK CONCLUÍDO COM EXCELÊNCIA TÉCNICA - ZERO ERROS")
else
    warn("✗ BENCHMARK FINALIZADO COM ADVERTÊNCIAS")
end
print("===================================================================")
