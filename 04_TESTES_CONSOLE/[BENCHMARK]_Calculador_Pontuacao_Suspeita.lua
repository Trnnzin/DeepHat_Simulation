-- DeepHat Simulation Engine - CORE
local Engine = {}

-- Configuração de Perfis de Comportamento
Engine.Profiles = {
    ["NORMAL"] = {
        SpeedMult = 1.0,         -- Velocidade 100%
        AimSmooth = 0.15,        -- Movimento suave
        SnapChance = 0.05,       -- 5% de chance de movimento brusco
        WalltrackProb = 0.0,     -- 0% de chance de seguir através de paredes
        Precision = 0.95         -- 95% de precisão (humana)
    },
    ["AGRESSIVO"] = {
        SpeedMult = 1.5,         -- 50% mais rápido
        AimSmooth = 0.01,        -- Quase instantâneo
        SnapChance = 0.8,        -- 80% de chance de Snap (Aimbot)
        WalltrackProb = 0.7,     -- 70% de chance de seguir através de objetos
        Precision = 0.99         -- 99% de precisão (robótica)
    }
}

-- Calculador de Score de Suspeita (Onde o Anti-Cheat seria validado)
function Engine:CalculateSuspicion(metrics)
    local score = 0
    if metrics.isSnap then score = score + 40 end
    if metrics.isWallTracking then score = score + 30 end
    if metrics.velocity > 22 then score = score + 30 end -- Limite de velocidade
    if metrics.angularVel > 50 then score = score + 20 end
    
    return math.min(score, 100) -- Retorna de 0 a 100
end

return Engine
