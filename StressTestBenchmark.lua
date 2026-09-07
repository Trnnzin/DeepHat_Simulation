--!strict
-- StressTestBenchmark.lua
-- Script integrador para teste de estresse de câmera e oclusão

local CameraKinematics = require(script.Parent.CameraKinematics)
local LineOfSightSimulator = require(script.Parent.LineOfSightSimulator)

-- Inicialização dos subsistemas
local camera = CameraKinematics.new(CFrame.new(Vector3.new(0, 5, 0), Vector3.new(0, 5, 10)))
local los = LineOfSightSimulator.new()

-- Define alvos de teste (um direto e outro com geometria oclusa simulada)
local targets = {
    Vector3.new(40, 5, 15),
    Vector3.new(-35, 8, -25),
    Vector3.new(0, 20, 50)
}

print("===================================================================")
print("       BENCHMARK DE DETECÇÃO DE CINEMÁTICA E OCLUSÃO 3D            ")
print("===================================================================")

-- Bateria 1: Teste com Vetor Instantâneo (Snap)
print("\n[FASE 1] Executando 5 testes em Modo INSTANTÂNEO (Snap)...")
for i = 1, 5 do
    local target = targets[(i % #targets) + 1]
    local dt = 1/60 -- Tempo equivalente a 1 frame (60 FPS)

    local camData = camera:StepSnap(target, dt)
    local losData = los:EvaluateLineOfSight(camData.position, target)

    print(string.format("[SNAP #%d] Vel Angular: %8.2f deg/s | Obstruído: %-5s | Distância: %.1fm",
        i, camData.angularVelocityDeg, tostring(losData.isObstructed), losData.distance))

    task.wait(0.1)
end

-- Bateria 2: Teste com Vetor Suave (Tracking / Lerp)
print("\n[FASE 2] Executando 15 iterações de RASTREAMENTO SUAVE (Tracking)...")
local activeTarget = targets[1]
for i = 1, 15 do
    local dt = 1/60
    local camData = camera:StepTracking(activeTarget, 0.12, dt)
    local losData = los:EvaluateLineOfSight(camData.position, activeTarget)

    if i % 3 == 0 then
        print(string.format("[TRACKING #%02d] Vel Angular: %8.2f deg/s | Obstruído: %-5s | Distância: %.1fm",
            i, camData.angularVelocityDeg, tostring(losData.isObstructed), losData.distance))
    end

    task.wait(0.05) -- Frequência de 20 Hz
end

print("\n===================================================================")
print("✓ Benchmark finalizado com sucesso. Dados prontos para telemetria.")
print("===================================================================")
