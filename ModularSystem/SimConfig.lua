--!strict
-- SimConfig.lua
-- Modulo 1: Gerenciador Central de Configuracoes com Observer Pattern
-- Suporta todos os parametros de Vetores, Comportamento e Mapeamento de Regioes

local SimConfig = {}
SimConfig.__index = SimConfig

export type ProfileData = {
    -- Coluna 1: Vetores e Direcao
    SimulationActive: boolean,
    FOV: number,                -- Campo de visao angular util (em graus) [10 - 180]
    Smoothing: number,          -- Coeficiente de interpolacao base [0.01 - 1.0]
    AngularVelocity: number,    -- Velocidade angular maxima (graus/segundo) [30 - 720]
    ResponseTime: number,       -- Tempo de resposta simulado (em ms) [0 - 250]
    TrajectoryPrecision: number,-- Precisao da trajetoria [50.0 - 100.0%]
    UpdateFrequency: number,    -- Frequencia de atualizacao (Hz) [10 - 144]
    VectorRadius: number,       -- Raio maximo de atuacao do vetor (em studs/m) [10 - 500]

    -- Coluna 2: Comportamento do Sistema
    ActiveProfile: string,      -- "Normal", "Leve", "Medio", "Agressivo", "Custom"
    EventFrequency: number,     -- Frequencia de geracao de eventos (Hz) [1 - 60]
    Intensity: number,          -- Intensidade geral da resposta [0 - 100%]
    MoveSpeed: number,          -- Velocidade de deslocamento (studs/s) [8 - 40]
    AccelerationCurve: number,  -- Gradiente de aceleracao / Easing exponent [0.2 - 3.0]
    CycleDuration: number,      -- Duracao do ciclo de teste (segundos) [5 - 120]
    SimulatedAgents: number,    -- Numero de agentes simulados concorrentes [1 - 16]

    -- Coluna 3: Mapeamento de Regioes
    TargetRegion: string,       -- "Head", "Torso", "Arms", "Legs"
}

-- Banco de perfis predefinidos
local PROFILES: { [string]: ProfileData } = {
    ["Normal"] = {
        SimulationActive = false,
        FOV = 60.0,
        Smoothing = 0.15,
        AngularVelocity = 180.0,
        ResponseTime = 16,
        TrajectoryPrecision = 98.5,
        UpdateFrequency = 60,
        VectorRadius = 150.0,
        ActiveProfile = "Normal",
        EventFrequency = 20,
        Intensity = 75,
        MoveSpeed = 16.0,
        AccelerationCurve = 1.25,
        CycleDuration = 30,
        SimulatedAgents = 4,
        TargetRegion = "Head"
    },
    ["Leve"] = {
        SimulationActive = false,
        FOV = 40.0,
        Smoothing = 0.28,
        AngularVelocity = 120.0,
        ResponseTime = 30,
        TrajectoryPrecision = 95.0,
        UpdateFrequency = 30,
        VectorRadius = 100.0,
        ActiveProfile = "Leve",
        EventFrequency = 10,
        Intensity = 40,
        MoveSpeed = 12.0,
        AccelerationCurve = 1.0,
        CycleDuration = 20,
        SimulatedAgents = 2,
        TargetRegion = "Torso"
    },
    ["Medio"] = {
        SimulationActive = false,
        FOV = 75.0,
        Smoothing = 0.09,
        AngularVelocity = 280.0,
        ResponseTime = 10,
        TrajectoryPrecision = 90.0,
        UpdateFrequency = 60,
        VectorRadius = 200.0,
        ActiveProfile = "Medio",
        EventFrequency = 30,
        Intensity = 85,
        MoveSpeed = 22.0,
        AccelerationCurve = 1.6,
        CycleDuration = 45,
        SimulatedAgents = 6,
        TargetRegion = "Head"
    },
    ["Agressivo"] = {
        SimulationActive = false,
        FOV = 120.0,
        Smoothing = 0.02,
        AngularVelocity = 540.0,
        ResponseTime = 2,
        TrajectoryPrecision = 80.0,
        UpdateFrequency = 120,
        VectorRadius = 350.0,
        ActiveProfile = "Agressivo",
        EventFrequency = 50,
        Intensity = 100,
        MoveSpeed = 32.0,
        AccelerationCurve = 2.4,
        CycleDuration = 60,
        SimulatedAgents = 10,
        TargetRegion = "Head"
    },
    ["Custom"] = {
        SimulationActive = false,
        FOV = 60.0,
        Smoothing = 0.15,
        AngularVelocity = 180.0,
        ResponseTime = 16,
        TrajectoryPrecision = 98.5,
        UpdateFrequency = 60,
        VectorRadius = 150.0,
        ActiveProfile = "Custom",
        EventFrequency = 20,
        Intensity = 75,
        MoveSpeed = 16.0,
        AccelerationCurve = 1.25,
        CycleDuration = 30,
        SimulatedAgents = 4,
        TargetRegion = "Head"
    }
}

-- Estado inicial ativo
local CurrentState: ProfileData = {
    SimulationActive = false,
    FOV = 60.0,
    Smoothing = 0.15,
    AngularVelocity = 180.0,
    ResponseTime = 16,
    TrajectoryPrecision = 98.5,
    UpdateFrequency = 60,
    VectorRadius = 150.0,
    ActiveProfile = "Normal",
    EventFrequency = 20,
    Intensity = 75,
    MoveSpeed = 16.0,
    AccelerationCurve = 1.25,
    CycleDuration = 30,
    SimulatedAgents = 4,
    TargetRegion = "Head"
}

-- Observadores (Observer Pattern)
local KeyListeners: { [string]: { (any) -> () } } = {}
local GlobalListeners: { (string, any) -> () } = {}

function SimConfig.Get(key: string): any
    return (CurrentState :: any)[key]
end

function SimConfig.GetAll(): ProfileData
    local clone: any = {}
    for k, v in pairs(CurrentState) do
        clone[k] = v
    end
    return clone
end

function SimConfig.Set(key: string, value: any, silent: boolean?)
    if (CurrentState :: any)[key] == value then
        return
    end

    (CurrentState :: any)[key] = value

    -- Se o usuario alterar um parametro individualmente sem selecionar perfil, muda para Custom
    if key ~= "ActiveProfile" and key ~= "SimulationActive" and CurrentState.ActiveProfile ~= "Custom" then
        CurrentState.ActiveProfile = "Custom"
        SimConfig.Notify("ActiveProfile", "Custom")
    end

    if not silent then
        SimConfig.Notify(key, value)
    end
end

function SimConfig.Notify(key: string, value: any)
    if KeyListeners[key] then
        for _, callback in ipairs(KeyListeners[key]) do
            task.spawn(callback, value)
        end
    end

    for _, callback in ipairs(GlobalListeners) do
        task.spawn(callback, key, value)
    end
end

function SimConfig.Subscribe(key: string, callback: (any) -> ()): () -> ()
    if not KeyListeners[key] then
        KeyListeners[key] = {}
    end
    table.insert(KeyListeners[key], callback)

    return function()
        local list = KeyListeners[key]
        if not list then return end
        local idx = table.find(list, callback)
        if idx then
            table.remove(list, idx)
        end
    end
end

function SimConfig.SubscribeAll(callback: (string, any) -> ()): () -> ()
    table.insert(GlobalListeners, callback)
    return function()
        local idx = table.find(GlobalListeners, callback)
        if idx then
            table.remove(GlobalListeners, idx)
        end
    end
end

function SimConfig.LoadProfile(profileName: string)
    local profile = PROFILES[profileName]
    if not profile then
        warn(string.format("[SimConfig] Perfil desconhecido: %s", tostring(profileName)))
        return
    end

    for k, v in pairs(profile) do
        if k ~= "SimulationActive" then -- Preserva o estado de ativacao
            (CurrentState :: any)[k] = v
            SimConfig.Notify(k, v)
        end
    end
end

return SimConfig
