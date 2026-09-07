--!strict
-- SimConfig.lua
-- Modulo 1: Gerenciador Central de Configuracoes com Observer Pattern

local SimConfig = {}
SimConfig.__index = SimConfig

export type ProfileData = {
    FOV: number,                -- Campo de visao angular util (em graus)
    Smoothing: number,          -- Coeficiente de interpolacao base [0.01 - 0.5]
    SpeedMultiplier: number,    -- Multiplicador geral de velocidade cinetica
    TrackingPrecision: number,  -- Precisao [0.50 - 1.00] (afeta o nivel de jitter)
    SnapFrequency: number,      -- Frequencia/probabilidade de movimentos bruscos [0.0 - 1.0]
    ReactionTime: number,       -- Latencia de resposta simulada (em segundos)
    Intensity: number,          -- Escala geral de intensidade do teste [0.1 - 2.0]
    ActiveProfile: string       -- Nome do perfil ativo
}

-- Banco de perfis predefinidos
local PROFILES: { [string]: ProfileData } = {
    ["Normal"] = {
        FOV = 45.0,
        Smoothing = 0.14,
        SpeedMultiplier = 1.0,
        TrackingPrecision = 0.95,
        SnapFrequency = 0.03,
        ReactionTime = 0.22,
        Intensity = 1.0,
        ActiveProfile = "Normal"
    },
    ["Leve"] = {
        FOV = 30.0,
        Smoothing = 0.25,
        SpeedMultiplier = 0.75,
        TrackingPrecision = 0.98,
        SnapFrequency = 0.00,
        ReactionTime = 0.28,
        Intensity = 0.6,
        ActiveProfile = "Leve"
    },
    ["Medio"] = {
        FOV = 60.0,
        Smoothing = 0.09,
        SpeedMultiplier = 1.4,
        TrackingPrecision = 0.90,
        SnapFrequency = 0.15,
        ReactionTime = 0.15,
        Intensity = 1.3,
        ActiveProfile = "Medio"
    },
    ["Agressivo"] = {
        FOV = 90.0,
        Smoothing = 0.02,
        SpeedMultiplier = 2.2,
        TrackingPrecision = 0.75,
        SnapFrequency = 0.65,
        ReactionTime = 0.05,
        Intensity = 2.0,
        ActiveProfile = "Agressivo"
    },
    ["Custom"] = {
        FOV = 45.0,
        Smoothing = 0.14,
        SpeedMultiplier = 1.0,
        TrackingPrecision = 0.95,
        SnapFrequency = 0.03,
        ReactionTime = 0.20,
        Intensity = 1.0,
        ActiveProfile = "Custom"
    }
}

-- Estado inicial
local CurrentState: ProfileData = {
    FOV = 45.0,
    Smoothing = 0.14,
    SpeedMultiplier = 1.0,
    TrackingPrecision = 0.95,
    SnapFrequency = 0.03,
    ReactionTime = 0.22,
    Intensity = 1.0,
    ActiveProfile = "Normal"
}

-- Estrutura de observadores (Listeners)
local KeyListeners: { [string]: { (any) -> () } } = {}
local GlobalListeners: { (string, any) -> () } = {}

-- Obtem o valor de uma chave
function SimConfig.Get(key: string): any
    return (CurrentState :: any)[key]
end

-- Obtem todas as configuracoes atuais (copia rasa)
function SimConfig.GetAll(): ProfileData
    local clone: any = {}
    for k, v in pairs(CurrentState) do
        clone[k] = v
    end
    return clone
end

-- Define uma configuracao individual e notifica os observadores
function SimConfig.Set(key: string, value: any, silent: boolean?)
    if (CurrentState :: any)[key] == value then
        return
    end

    (CurrentState :: any)[key] = value

    -- Se o usuario alterar um parametro individualmente sem selecionar perfil, muda para Custom
    if key ~= "ActiveProfile" and CurrentState.ActiveProfile ~= "Custom" then
        CurrentState.ActiveProfile = "Custom"
        SimConfig.Notify("ActiveProfile", "Custom")
    end

    if not silent then
        SimConfig.Notify(key, value)
    end
end

-- Notifica observadores inscritos
function SimConfig.Notify(key: string, value: any)
    -- Dispara listeners especificos da chave
    if KeyListeners[key] then
        for _, callback in ipairs(KeyListeners[key]) do
            task.spawn(callback, value)
        end
    end

    -- Dispara listeners globais
    for _, callback in ipairs(GlobalListeners) do
        task.spawn(callback, key, value)
    end
end

-- Inscreve um observador para uma chave especifica
function SimConfig.Subscribe(key: string, callback: (any) -> ()): () -> ()
    if not KeyListeners[key] then
        KeyListeners[key] = {}
    end
    table.insert(KeyListeners[key], callback)

    -- Retorna funcao de cancelamento (unsubscribe)
    return function()
        local list = KeyListeners[key]
        if not list then return end
        local idx = table.find(list, callback)
        if idx then
            table.remove(list, idx)
        end
    end
end

-- Inscreve um observador global que recebe qualquer mudanca
function SimConfig.SubscribeAll(callback: (string, any) -> ()): () -> ()
    table.insert(GlobalListeners, callback)
    return function()
        local idx = table.find(GlobalListeners, callback)
        if idx then
            table.remove(GlobalListeners, idx)
        end
    end
end

-- Carrega um perfil predefinido em bloco
function SimConfig.LoadProfile(profileName: string)
    local profile = PROFILES[profileName]
    if not profile then
        warn(string.format("[SimConfig] Perfil desconhecido: %s", tostring(profileName)))
        return
    end

    for k, v in pairs(profile) do
        (CurrentState :: any)[k] = v
        SimConfig.Notify(k, v)
    end
end

return SimConfig