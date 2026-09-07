local Engine = require(script.Parent.EngineCore) -- Importa a base (ou require(EngineCore))

local Simulator = {}

-- Simula o movimento do jogador (Velocidade e Direção)
function Simulator:SimulateMovement(profile)
    local baseSpeed = 16
    local targetSpeed = baseSpeed * profile.SpeedMult
    
    -- Simula uma aceleração súbita ou constante
    local currentSpeed = targetSpeed + math.random(-2, 2)
    
    return {
        velocity = currentSpeed,
        timestamp = os.clock()
    }
end

-- Simula a mira (Aimbot vs Smooth)
function Simulator:SimulateAim(profile)
    local isSnap = math.random() < profile.SnapChance
    local angularVel = isSnap and math.random(60, 100) or math.random(5, 15)
    
    return {
        isSnap = isSnap,
        angularVel = angularVel,
        timestamp = os.clock()
    }
end

-- Simula a detecção de parede (Wallhack)
function Simulator:SimulateVision(profile)
    -- Simula se o jogador está acompanhando um alvo atrás de uma parede
    local isWallTracking = math.random() < profile.WalltrackProb
    
    return {
        isWallTracking = isWallTracking,
        timestamp = os.clock()
    }
end

return Simulator
