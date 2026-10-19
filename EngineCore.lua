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
    category: string,              -- "LIMPO", "SUSPEITO", "ANOMALIA_CRITICA", "INSUFICIENTE"
    flaggedRules: { string },
    anomalies: { string },         -- alias de flaggedRules (mesma tabela) p/ consumidores antigos e novos
    explanations: { string },      -- justificativa de cada regra acionada (limiar e valor medido)
    unavailableMetrics: { string },-- telemetria ausente (NUNCA tratada como zero)
    evaluatedRules: number,        -- regras que puderam ser avaliadas com dados reais
    sampleCount: number?,
}

-- Amostra mínima para classificar; abaixo disso a categoria é "INSUFICIENTE".
Engine.MIN_SAMPLES = 5
-- Limites (fonte única; os testes consultam estes valores)
Engine.Thresholds = {
    SnapCritical = 30.0, SnapSudden = 18.0,
    AngVelSuper = 800.0, AngVelHigh = 450.0,
    OccludedPersistent = 15, OccludedBrief = 5,
    LinearSpeed = 28.0,
    DecoupledCritical = 35.0, DecoupledHigh = 15.0,
    ScoreCritical = 75, ScoreSuspect = 40,
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

-- Matriz de Avaliação de Suspeita Baseada em Física (independente de UI)
-- Campo ausente (nil) => regra NÃO avaliada e listada em unavailableMetrics; 0 => medição válida.
function Engine:CalculateSuspicion(metrics: KinematicMetrics): SuspicionReport
    local T = Engine.Thresholds
    local score = 0
    local flags: { string } = {}
    local why: { string } = {}
    local missing: { string } = {}
    local evaluated = 0
    local m: any = metrics or {}

    local function valid(v: any): boolean
        return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
    end
    local function flag(name: string, pts: number, reason: string)
        score = score + pts
        table.insert(flags, name)
        table.insert(why, string.format("%s: %s (+%d)", name, reason, pts))
    end

    -- 1. Snap instantâneo
    local delta: number? = nil
    if valid(m.singleFrameDeltaDeg) then delta = m.singleFrameDeltaDeg
    elseif m.isSnap ~= nil then delta = m.isSnap and 45 or 0 end
    if delta ~= nil then
        evaluated += 1
        if delta > T.SnapCritical then
            flag("ANOMALIA_SNAP", 45, string.format("delta %.1f° > %.1f°", delta, T.SnapCritical))
        elseif delta > T.SnapSudden then
            flag("ROTACAO_SUBITA", 20, string.format("delta %.1f° > %.1f°", delta, T.SnapSudden))
        end
    else table.insert(missing, "singleFrameDeltaDeg") end

    -- 2. Velocidade angular
    if valid(m.angularVelocity) then
        evaluated += 1
        local v = m.angularVelocity
        if v > T.AngVelSuper then
            flag("VELOCIDADE_SUPERHUMANA", 35, string.format("%.1f °/s > %.1f", v, T.AngVelSuper))
        elseif v > T.AngVelHigh then
            flag("VELOCIDADE_ELEVADA", 15, string.format("%.1f °/s > %.1f", v, T.AngVelHigh))
        end
    else table.insert(missing, "angularVelocity") end

    -- 3. Mira através de oclusão
    local occluded: number? = nil
    if valid(m.consecutiveOccludedFrames) then occluded = m.consecutiveOccludedFrames
    elseif m.isObstructed ~= nil then occluded = m.isObstructed and 10 or 0 end
    if occluded ~= nil then
        evaluated += 1
        if occluded >= T.OccludedPersistent then
            flag("TRACKING_OCLUSO_PERSISTENTE", 40, string.format("%d frames >= %d", occluded, T.OccludedPersistent))
        elseif occluded >= T.OccludedBrief then
            flag("VISADA_OBSTRUIDA", 20, string.format("%d frames >= %d", occluded, T.OccludedBrief))
        end
    else table.insert(missing, "consecutiveOccludedFrames") end

    -- 4. Velocidade linear (sem valor padrão fictício)
    if valid(m.linearSpeed) then
        evaluated += 1
        if m.linearSpeed > T.LinearSpeed then
            flag("DESLOCAMENTO_ANOMALO", 30, string.format("%.1f studs/s > %.1f", m.linearSpeed, T.LinearSpeed))
        end
    else table.insert(missing, "linearSpeed") end

    -- 5. Vetor de disparo desacoplado
    if valid(m.decoupledAngleDeg) then
        evaluated += 1
        local d = m.decoupledAngleDeg
        if d > T.DecoupledCritical then
            flag("SILENT_AIM_CRITICO", 65, string.format("discrepância %.1f° > %.1f°", d, T.DecoupledCritical))
        elseif d > T.DecoupledHigh then
            flag("DISCREPANCIA_SILENT_AIM", 45, string.format("discrepância %.1f° > %.1f°", d, T.DecoupledHigh))
        end
    else table.insert(missing, "decoupledAngleDeg") end

    local finalScore = math.clamp(score, 0, 100)
    local category = "LIMPO"
    local sampleCount = (metrics :: any).sampleCount
    if evaluated == 0 or (valid(sampleCount) and sampleCount < Engine.MIN_SAMPLES) then
        category = "INSUFICIENTE"
    elseif finalScore >= T.ScoreCritical then
        category = "ANOMALIA_CRITICA"
    elseif finalScore >= T.ScoreSuspect then
        category = "SUSPEITO"
    end

    return {
        totalScore = finalScore,
        category = category,
        flaggedRules = flags,
        anomalies = flags,
        explanations = why,
        unavailableMetrics = missing,
        evaluatedRules = evaluated,
        sampleCount = valid(sampleCount) and sampleCount or nil,
    }
end

return Engine
