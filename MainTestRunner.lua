-- DeepHat Simulation Engine - MAIN TEST RUNNER (Etapa 3)
local Engine = require(script.Parent.EngineCore)
local Simulator = require(script.Parent.BehaviorSimulator)

-- Função auxiliar de cálculo de média (declarada antes para evitar erro de nil em Lua)
local function sessionLogs_avg(logs)
    if not logs or #logs == 0 then return "N/A" end
    local total = 0
    for _, log in ipairs(logs) do 
        total = total + log.score 
    end
    return string.format("%.2f", total / #logs)
end

-- Função Principal para rodar o teste
local function RunTestSession(profileName, iterations)
    local profile = Engine.Profiles[profileName]
    print("\n[Sessao de Teste] Perfil: " .. profileName)
    print("------------------------------------------")

    local sessionLogs = {}

    for i = 1, iterations do
        -- 1. Simula os comportamentos
        local moveData = Simulator:SimulateMovement(profile)
        local aimData = Simulator:SimulateAim(profile)
        local visionData = Simulator:SimulateVision(profile)

        -- 2. Combina os dados para criar um evento de telemetria
        local telemetry = {
            velocity = moveData.velocity,
            isSnap = aimData.isSnap,
            angularVel = aimData.angularVel,
            isWallTracking = visionData.isWallTracking,
            timestamp = os.clock()
        }

        -- 3. Calcula o Score de Suspeita
        local suspicionScore = Engine:CalculateSuspicion(telemetry)

        -- 4. Registra o Log
        table.insert(sessionLogs, {
            score = suspicionScore,
            data = telemetry
        })

        -- Log visual no console para acompanhar o teste
        if i % 5 == 0 then -- Mostra a cada 5 iterações para não poluir
            print(string.format("[Iteracao %d] Score: %d | Vel: %.2f | Snap: %s", 
                i, suspicionScore, telemetry.velocity, tostring(telemetry.isSnap)))
        end
        
        task.wait(0.1) -- Simula o tempo entre frames
    end

    print("------------------------------------------")
    print("[Teste Finalizado] Total de eventos: " .. #sessionLogs)
    return sessionLogs
end

-- --- EXECUÇÃO DOS TESTES ---

-- Teste 1: Jogador Normal (Deve gerar scores baixos)
local normalResults = RunTestSession("NORMAL", 20)

-- Teste 2: Jogador com Comportamento Agressivo (Deve gerar scores altos)
local aggressiveResults = RunTestSession("AGRESSIVO", 20)

print("\n[RESUMO FINAL]")
print("Media de Score Normal: " .. (sessionLogs_avg(normalResults) or "N/A"))
print("Media de Score Agressivo: " .. (sessionLogs_avg(aggressiveResults) or "N/A"))
