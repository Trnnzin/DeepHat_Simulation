--!strict
-- =========================================================================
-- BehaviorSimulator.lua
-- Gerador Controlado de Telemetria Cinemática para Testes de Anti-Cheat
-- =========================================================================

local Engine = require(script.Parent.EngineCore)

local Simulator = {}

export type SimulationProfile = {
    SpeedMult: number,
    AimSmooth: number,
    SnapChance: number,
    WalltrackProb: number,
    Precision: number,
    MaxExpectedAngVel: number?
}

-- Simula cinemática de movimento linear
function Simulator:SimulateMovement(profile: SimulationProfile)
    local baseSpeed = 16.0
    local targetSpeed = baseSpeed * profile.SpeedMult
    local noise = (math.random() * 4.0 - 2.0)
    local currentSpeed = math.max(targetSpeed + noise, 0)

    return {
        velocity = currentSpeed,
        timestamp = os.clock()
    }
end

-- Simula cinemática de rotação angular da mira
function Simulator:SimulateAim(profile: SimulationProfile, dt: number?)
    local safeDt = dt or 0.0166
    local isSnap = (math.random() < profile.SnapChance)

    local deltaAngle = 0
    local angularVel = 0

    if isSnap then
        -- Rotação instantânea de grande amplitude (40° a 110° em 1 frame)
        deltaAngle = math.random(40, 110)
        angularVel = deltaAngle / safeDt
    else
        -- Rotação suave controlada humana (2° a 8° por frame, interpolada)
        deltaAngle = math.random(2, 8) + (math.random() * 0.5)
        angularVel = deltaAngle / safeDt
    end

    return {
        isSnap = isSnap,
        deltaAngleDeg = deltaAngle,
        angularVel = angularVel,
        timestamp = os.clock()
    }
end

-- Simula linha de visão e persistência de rastreamento através de obstáculos
function Simulator:SimulateVision(profile: SimulationProfile, currentOccludedStreak: number?)
    local isWallTracking = (math.random() < profile.WalltrackProb)
    local streak = currentOccludedStreak or 0
    if isWallTracking then
        streak = streak + 1
    else
        streak = 0
    end

    return {
        isWallTracking = isWallTracking,
        consecutiveOccluded = streak,
        timestamp = os.clock()
    }
end

return Simulator
