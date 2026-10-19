--!strict
-- SimConfig.lua
-- Modulo 1: Gerenciador Central de Configuracoes Reativas (Observer Pattern)
-- Suporta perfis predefinidos, customizacao granular, notificacao de listeners e diagnosticos

local HttpService = game:GetService("HttpService")

local SimConfig = {}
SimConfig.__index = SimConfig

export type ProfileData = {
    -- Estado Geral & Abas
    SimulationActive: boolean,
    AimbotEnabled: boolean,     -- Ativador mestre do sistema de mira cinematica (Aimbot)
    ActiveProfile: string,      -- "Normal", "Leve", "Medio", "Agressivo", "Custom"
    ActiveTab: string,          -- "Overview", "Camera", "Simulation", "Vision", "Hitbox", "Diagnostics", "Performance", "Settings"

    -- Coluna 1 / Aba Camera & Vetores
    FOV: number,                -- Campo de visao angular util (graus) [10 - 180]
    Smoothing: number,          -- Coeficiente de interpolacao base [0.01 - 1.0]
    AngularVelocity: number,    -- Velocidade angular maxima (graus/segundo) [30 - 720]
    ResponseTime: number,       -- Tempo de resposta simulado (ms) [0 - 250]
    TrajectoryPrecision: number,-- Precisao da trajetoria (%) [50.0 - 100.0]
    UpdateFrequency: number,    -- Frequencia de atualizacao (Hz) [10 - 144]
    VectorRadius: number,       -- Raio maximo de atuacao (studs) [10 - 500]

    -- Aba Simulacao & Comportamento
    AimMode: string,            -- "HoldRMB", "Toggle", "AlwaysOn"
    HoldToAim: boolean,
    SimulateJitter: boolean,    -- Inserir micro-variacoes Perlin Noise organicas
    EventFrequency: number,     -- Frequencia de eventos (Hz) [1 - 60]
    Intensity: number,          -- Intensidade geral (%) [0 - 100]
    MoveSpeed: number,          -- Velocidade simulada (studs/s) [8 - 40]
    AccelerationCurve: number,  -- Expoente de curva Smoothstep [0.2 - 3.0]
    CycleDuration: number,      -- Duracao do ciclo de teste (s) [5 - 120]
    SimulatedAgents: number,    -- Agentes concorrentes simulados [1 - 16]

    -- Aba Linha de Visao & ESP
    VisibleOnly: boolean,       -- Rastrear somente se houver linha de visada desobstruida
    EnableESP: boolean,         -- Realce visual via Highlights (AlwaysOnTop)
    ShowFovCircle: boolean,     -- Overlay circular do FOV na tela
    EnableLead: boolean,        -- Predicao balistica (Lead Calculation)
    ProjectileSpeed: number,    -- Velocidade do projetil para calculo de lead (studs/s)
    TeamCheck: boolean,         -- Ignorar companheiros de equipe
    WallOcclusionCheck: boolean,-- Verificacao de oclusao por Raycast

    -- Aba Mapeamento HitBox & Seleção de Alvos
    TargetRegion: string,       -- "Head", "Torso", "Arms", "Legs"
    TargetBone: string,
    TargetPriority: string,     -- "Crosshair", "Distance", "LowestHealth"
    TargetStickiness: number,   -- Tempo de persistência no alvo para evitar jitter de troca (s) [0.0 - 1.0]
    MaxAngularVelocityClamp: boolean, -- Forçar limite estrito de velocidade angular máxima

    -- Simulação de Silent Aim (Vetor de Disparo Desacoplado para Testes de Anti-Cheat)
    SilentAimEnabled: boolean,   -- Simular redirecionamento de projétil sem mover a câmera
    SilentAimFOV: number,       -- Ângulo de ativação do Silent Aim (graus) [5 - 90]
    SilentAimHitChance: number, -- Probabilidade de redirecionamento (%) [0 - 100]
    SilentAimTracer: boolean,   -- Desenhar traçador visual do vetor de disparo desacoplado

    -- Diagnosticos e Seguranca
    WatchdogEnabled: boolean,   -- Verificacao continua de integridade em segundo plano
    DebugLogging: boolean,      -- Exibir logs no console do Studio
}

local PROFILES: { [string]: ProfileData } = {
    ["Normal"] = {
        SimulationActive = true,
        AimbotEnabled = true,
        ActiveProfile = "Normal",
        ActiveTab = "Overview",
        FOV = 70.0,
        Smoothing = 0.15,
        AngularVelocity = 240.0,
        ResponseTime = 16,
        TrajectoryPrecision = 98.5,
        UpdateFrequency = 60,
        VectorRadius = 300.0,
        AimMode = "HoldRMB",
        HoldToAim = true,
        SimulateJitter = true,
        EventFrequency = 20,
        Intensity = 75,
        MoveSpeed = 16.0,
        AccelerationCurve = 1.25,
        CycleDuration = 30,
        SimulatedAgents = 4,
        VisibleOnly = false,
        EnableESP = true,
        ShowFovCircle = true,
        EnableLead = true,
        ProjectileSpeed = 900.0,
        TeamCheck = false,
        WallOcclusionCheck = true,
        TargetRegion = "Head",
        TargetBone = "Head",
        TargetPriority = "Crosshair",
        TargetStickiness = 0.25,
        MaxAngularVelocityClamp = true,
        SilentAimEnabled = false,
        SilentAimFOV = 35.0,
        SilentAimHitChance = 100.0,
        SilentAimTracer = true,
        WatchdogEnabled = true,
        DebugLogging = false,
    },
    ["Leve"] = {
        SimulationActive = true,
        AimbotEnabled = true,
        ActiveProfile = "Leve",
        ActiveTab = "Overview",
        FOV = 45.0,
        Smoothing = 0.28,
        AngularVelocity = 140.0,
        ResponseTime = 30,
        TrajectoryPrecision = 95.0,
        UpdateFrequency = 30,
        VectorRadius = 180.0,
        AimMode = "HoldRMB",
        HoldToAim = true,
        SimulateJitter = true,
        EventFrequency = 10,
        Intensity = 40,
        MoveSpeed = 12.0,
        AccelerationCurve = 1.0,
        CycleDuration = 20,
        SimulatedAgents = 2,
        VisibleOnly = true,
        EnableESP = true,
        ShowFovCircle = true,
        EnableLead = false,
        ProjectileSpeed = 800.0,
        TeamCheck = true,
        WallOcclusionCheck = true,
        TargetRegion = "Torso",
        TargetBone = "Torso",
        TargetPriority = "Crosshair",
        TargetStickiness = 0.35,
        MaxAngularVelocityClamp = true,
        SilentAimEnabled = false,
        SilentAimFOV = 20.0,
        SilentAimHitChance = 80.0,
        SilentAimTracer = true,
        WatchdogEnabled = true,
        DebugLogging = false,
    },
    ["Medio"] = {
        SimulationActive = true,
        AimbotEnabled = true,
        ActiveProfile = "Medio",
        ActiveTab = "Overview",
        FOV = 85.0,
        Smoothing = 0.10,
        AngularVelocity = 340.0,
        ResponseTime = 10,
        TrajectoryPrecision = 92.0,
        UpdateFrequency = 60,
        VectorRadius = 350.0,
        AimMode = "HoldRMB",
        HoldToAim = true,
        SimulateJitter = true,
        EventFrequency = 30,
        Intensity = 85,
        MoveSpeed = 22.0,
        AccelerationCurve = 1.6,
        CycleDuration = 45,
        SimulatedAgents = 6,
        VisibleOnly = false,
        EnableESP = true,
        ShowFovCircle = true,
        EnableLead = true,
        ProjectileSpeed = 1000.0,
        TeamCheck = false,
        WallOcclusionCheck = true,
        TargetRegion = "Head",
        TargetBone = "Head",
        TargetPriority = "Crosshair",
        TargetStickiness = 0.20,
        MaxAngularVelocityClamp = true,
        SilentAimEnabled = false,
        SilentAimFOV = 40.0,
        SilentAimHitChance = 95.0,
        SilentAimTracer = true,
        WatchdogEnabled = true,
        DebugLogging = false,
    },
    ["Agressivo"] = {
        SimulationActive = true,
        AimbotEnabled = true,
        ActiveProfile = "Agressivo",
        ActiveTab = "Overview",
        FOV = 120.0,
        Smoothing = 0.02,
        AngularVelocity = 600.0,
        ResponseTime = 2,
        TrajectoryPrecision = 80.0,
        UpdateFrequency = 120,
        VectorRadius = 500.0,
        AimMode = "HoldRMB",
        HoldToAim = true,
        SimulateJitter = false,
        EventFrequency = 50,
        Intensity = 100,
        MoveSpeed = 32.0,
        AccelerationCurve = 2.4,
        CycleDuration = 60,
        SimulatedAgents = 10,
        VisibleOnly = false,
        EnableESP = true,
        ShowFovCircle = true,
        EnableLead = true,
        ProjectileSpeed = 1200.0,
        TeamCheck = false,
        WallOcclusionCheck = true,
        TargetRegion = "Head",
        TargetBone = "Head",
        TargetPriority = "Crosshair",
        TargetStickiness = 0.10,
        MaxAngularVelocityClamp = false,
        SilentAimEnabled = true,
        SilentAimFOV = 60.0,
        SilentAimHitChance = 100.0,
        SilentAimTracer = true,
        WatchdogEnabled = true,
        DebugLogging = true,
    },
    ["Custom"] = {
        SimulationActive = true,
        AimbotEnabled = true,
        ActiveProfile = "Custom",
        ActiveTab = "Overview",
        FOV = 70.0,
        Smoothing = 0.15,
        AngularVelocity = 240.0,
        ResponseTime = 16,
        TrajectoryPrecision = 98.5,
        UpdateFrequency = 60,
        VectorRadius = 300.0,
        AimMode = "HoldRMB",
        HoldToAim = true,
        SimulateJitter = true,
        EventFrequency = 20,
        Intensity = 75,
        MoveSpeed = 16.0,
        AccelerationCurve = 1.25,
        CycleDuration = 30,
        SimulatedAgents = 4,
        VisibleOnly = false,
        EnableESP = true,
        ShowFovCircle = true,
        EnableLead = true,
        ProjectileSpeed = 900.0,
        TeamCheck = false,
        WallOcclusionCheck = true,
        TargetRegion = "Head",
        TargetBone = "Head",
        TargetPriority = "Crosshair",
        TargetStickiness = 0.25,
        MaxAngularVelocityClamp = true,
        SilentAimEnabled = false,
        SilentAimFOV = 35.0,
        SilentAimHitChance = 100.0,
        SilentAimTracer = true,
        WatchdogEnabled = true,
        DebugLogging = false,
    }
}

-- Estado em memoria inicial
local CurrentState: ProfileData = {
    SimulationActive = true,
    ActiveProfile = "Normal",
    ActiveTab = "Overview",
    FOV = 70.0,
    Smoothing = 0.15,
    AngularVelocity = 240.0,
    ResponseTime = 16,
    TrajectoryPrecision = 98.5,
    UpdateFrequency = 60,
    VectorRadius = 300.0,
    AimMode = "HoldRMB",
    HoldToAim = true,
    SimulateJitter = true,
    EventFrequency = 20,
    Intensity = 75,
    MoveSpeed = 16.0,
    AccelerationCurve = 1.25,
    CycleDuration = 30,
    SimulatedAgents = 4,
    VisibleOnly = false,
    EnableESP = true,
    ShowFovCircle = true,
    EnableLead = true,
    ProjectileSpeed = 900.0,
    TeamCheck = false,
    WallOcclusionCheck = true,
    TargetRegion = "Head",
    TargetBone = "Head",
    TargetPriority = "Crosshair",
    TargetStickiness = 0.25,
    MaxAngularVelocityClamp = true,
    SilentAimEnabled = false,
    SilentAimFOV = 35.0,
    SilentAimHitChance = 100.0,
    SilentAimTracer = true,
    WatchdogEnabled = true,
    DebugLogging = false,
}

-- Observadores
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
    if key ~= "ActiveProfile" and key ~= "SimulationActive" and key ~= "ActiveTab" and CurrentState.ActiveProfile ~= "Custom" then
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
        if k ~= "SimulationActive" and k ~= "ActiveTab" then
            (CurrentState :: any)[k] = v
            SimConfig.Notify(k, v)
        end
    end
end

function SimConfig.ExportJSON(): string
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(CurrentState)
    end)
    return ok and encoded or "{}"
end

function SimConfig.ImportJSON(jsonStr: string): boolean
    local ok, data = pcall(function()
        return HttpService:JSONDecode(jsonStr)
    end)
    if ok and typeof(data) == "table" then
        for k, v in pairs(data) do
            if (CurrentState :: any)[k] ~= nil then
                SimConfig.Set(k, v)
            end
        end
        return true
    end
    return false
end

return SimConfig

