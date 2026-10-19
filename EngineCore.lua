--!strict
-- =========================================================================
-- EngineCore.lua
-- Motor de Avaliação Cinemática e Detecção de Anomalias de Comportamento
-- Usado para Calibração de Anti-Cheat e Validação de Tolerância Heurística
-- =========================================================================

local Engine = {}

export type KinematicMetrics = {
    angularVelocity: number,       -- Velocidade angular (°/s)
    singleFrameDeltaDeg: number?,  -- Variação angular no último frame (graus)
    isSnap: boolean?,              -- Rotação instantânea
    isObstructed: boolean?,        -- Linha de visada bloqueada
    targetDistance: number?,       -- Distância até o alvo (studs)
    consecutiveOccludedFrames: number?, -- Frames seguidos mirando através da parede
    accelerationJitter: number?,   -- Desvio padrão de aceleração
    linearSpeed: number?,          -- Velocidade linear (studs/s)
    decoupledAngleDeg: number?,    -- Discrepância entre LookVector da câmera e vetor do projétil (Silent Aim)
}

export type SuspicionReport = {
    totalScore: number,            -- 0 a 100%
    category: string,              -- "LIMPO", "SUSPEITO", "ANOMALIA_CRITICA"
    flaggedRules: { string },
}

-- Perfis de Teste para Simulação Controlada
Engine.Profiles = {
    ["NORMAL"] = {
        SpeedMult = 1.0,
        AimSmooth = 0.15,
        SnapChance = 0.02,
        WalltrackProb = 0.0,
        Precision = 0.95,
        MaxExpectedAngVel = 260.0
    },
    ["LEVE"] = {
        SpeedMult = 0.8,
        AimSmooth = 0.28,
        SnapChance = 0.0,
        WalltrackProb = 0.0,
        Precision = 0.90,
        MaxExpectedAngVel = 180.0
    },
    ["AGRESSIVO"] = {
        SpeedMult = 1.6,
        AimSmooth = 0.01,
        SnapChance = 0.85,
        WalltrackProb = 0.65,
        Precision = 0.99,
        MaxExpectedAngVel = 1200.0
    }
}

-- Matriz de Avaliação de Suspeita Baseada em Física
function Engine:CalculateSuspicion(metrics: KinematicMetrics): SuspicionReport
    local score = 0
    local flags: { string } = {}

    -- 1. Detecção de Snap Instantâneo (Variação Angular Anômala em 1 Frame)
    local delta = metrics.singleFrameDeltaDeg or (metrics.isSnap and 45 or 0)
    if delta > 30.0 then
        score = score + 45
        table.insert(flags, string.format("ANOMALIA_SNAP (Delta: %.1f°)", delta))
    elseif delta > 18.0 then
        score = score + 20
        table.insert(flags, string.format("ROTACAO_SUBITA (Delta: %.1f°)", delta))
    end

    -- 2. Limiar de Velocidade Angular Física
    local angVel = metrics.angularVelocity or 0
    if angVel > 800.0 then
        score = score + 35
        table.insert(flags, string.format("VELOCIDADE_SUPERHUMANA (%.1f °/s)", angVel))
    elseif angVel > 450.0 then
        score = score + 15
        table.insert(flags, string.format("VELOCIDADE_ELEVADA (%.1f °/s)", angVel))
    end

    -- 3. Detecção de Mira Através de Oclusão (Wallhack / Pre-Aim)
    local occludedFrames = metrics.consecutiveOccludedFrames or (metrics.isObstructed and 10 or 0)
    if occludedFrames >= 15 then
        score = score + 40
        table.insert(flags, string.format("TRACKING_OCLUSO_PERSISTENTE (%d frames)", occludedFrames))
    elseif occludedFrames >= 5 then
        score = score + 20
        table.insert(flags, "VISADA_OBSTRUIDA")
    end

    -- 4. Detecção de Velocidade Linear (Speedhack)
    local linSpeed = metrics.linearSpeed or 16
    if linSpeed > 28.0 then
        score = score + 30
        table.insert(flags, string.format("DESLOCAMENTO_ANOMALO (%.1f studs/s)", linSpeed))
    end

    -- 5. Detecção de Silent Aim (Vetor de Disparo Desacoplado da Orientação da Câmera)
    local decoupledAngle = metrics.decoupledAngleDeg or 0
    if decoupledAngle > 35.0 then
        score = score + 65
        table.insert(flags, string.format("SILENT_AIM_CRITICO (Discrepância: %.1f°)", decoupledAngle))
    elseif decoupledAngle > 15.0 then
        score = score + 45
        table.insert(flags, string.format("DISCREPANCIA_SILENT_AIM (Discrepância: %.1f°)", decoupledAngle))
    end

    local finalScore = math.clamp(score, 0, 100)
    local category = "LIMPO"
    if finalScore >= 75 then
        category = "ANOMALIA_CRITICA"
    elseif finalScore >= 40 then
        category = "SUSPEITO"
    end

    return {
        totalScore = finalScore,
        category = category,
        flaggedRules = flags
    }
end

return Engine
