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

-- =========================================================================
-- PERFIL PADRÃO Único: "DeepHat Simulation Default"
-- Fonte única dos valores iniciais. Segurança: automação de câmera e simulação de
-- disparos iniciam DESATIVADAS; nada age só porque o painel foi aberto.
-- =========================================================================
local DEFAULT_NAME = "DeepHat Simulation Default"
local CONFIG_VERSION = 1
local DEFAULT_PROFILE: any = {}
for k, v in pairs(PROFILES["Normal"]) do DEFAULT_PROFILE[k] = v end
local DEFAULT_OVERRIDES: any = {
    ActiveProfile = DEFAULT_NAME,
    ActiveTab = "Dashboard",
    SimulationActive = true,       -- pipeline de diagnóstico ligado; não move câmera por si só
    AimbotEnabled = false,         -- automação de câmera: DESATIVADA
    SilentAimEnabled = false,      -- simulação de disparo: DESATIVADA
    Smoothing = 0.15,              -- [0.01-1.0]; menor = resposta mais rápida (documentado em VectorTracker)
    ShowFovCircle = true,
    FovRadiusPx = 120,             -- raio do FOV visual de demonstração (px) [20-600]
    ShowSyntheticTargets = true,
    ShowDebugMarkers = true,
    LineOfSightEnabled = true,
    TelemetryIndicators = true,
    HistoryEnabled = true,
    HistoryLimit = 50,             -- [5-500]
    Theme = "Dark",
    AccentRed = true,
    UiScale = 1.0,                 -- [0.7-1.5]
    PanelEnabled = true,
    SidebarEnabled = true,
    PersistenceEnabled = true,
    ConfigVersion = CONFIG_VERSION,
}
for k, v in pairs(DEFAULT_OVERRIDES) do DEFAULT_PROFILE[k] = v end
PROFILES[DEFAULT_NAME] = DEFAULT_PROFILE

-- Esquema de validação: tipo + faixa/enum. Chaves fora do esquema são rejeitadas.
local SCHEMA: { [string]: any } = {
    SimulationActive = { t = "boolean" }, AimbotEnabled = { t = "boolean" },
    ActiveProfile = { t = "string" },
    ActiveTab = { t = "string" },
    FOV = { t = "number", min = 10, max = 180 }, Smoothing = { t = "number", min = 0.01, max = 1.0 },
    AngularVelocity = { t = "number", min = 30, max = 1200 }, ResponseTime = { t = "number", min = 0, max = 250 },
    TrajectoryPrecision = { t = "number", min = 50, max = 100 }, UpdateFrequency = { t = "number", min = 10, max = 144 },
    VectorRadius = { t = "number", min = 10, max = 500 },
    AimMode = { t = "string", enum = { "HoldRMB", "Toggle", "AlwaysOn" } }, HoldToAim = { t = "boolean" },
    SimulateJitter = { t = "boolean" }, EventFrequency = { t = "number", min = 1, max = 60 },
    Intensity = { t = "number", min = 0, max = 100 }, MoveSpeed = { t = "number", min = 8, max = 40 },
    AccelerationCurve = { t = "number", min = 0.2, max = 3.0 }, CycleDuration = { t = "number", min = 5, max = 120 },
    SimulatedAgents = { t = "number", min = 1, max = 16 },
    VisibleOnly = { t = "boolean" }, EnableESP = { t = "boolean" }, ShowFovCircle = { t = "boolean" },
    EnableLead = { t = "boolean" }, ProjectileSpeed = { t = "number", min = 10, max = 5000 },
    TeamCheck = { t = "boolean" }, WallOcclusionCheck = { t = "boolean" },
    TargetRegion = { t = "string", enum = { "Head", "Torso", "Arms", "Legs" } },
    TargetBone = { t = "string" },
    TargetPriority = { t = "string", enum = { "Crosshair", "Distance", "LowestHealth" } },
    TargetStickiness = { t = "number", min = 0, max = 1 }, MaxAngularVelocityClamp = { t = "boolean" },
    SilentAimEnabled = { t = "boolean" }, SilentAimFOV = { t = "number", min = 5, max = 90 },
    SilentAimHitChance = { t = "number", min = 0, max = 100 }, SilentAimTracer = { t = "boolean" },
    WatchdogEnabled = { t = "boolean" }, DebugLogging = { t = "boolean" },
    FovRadiusPx = { t = "number", min = 20, max = 600 }, ShowSyntheticTargets = { t = "boolean" },
    ShowDebugMarkers = { t = "boolean" }, LineOfSightEnabled = { t = "boolean" },
    TelemetryIndicators = { t = "boolean" }, HistoryEnabled = { t = "boolean" },
    HistoryLimit = { t = "number", min = 5, max = 500 }, Theme = { t = "string", enum = { "Dark", "Darker" } },
    AccentRed = { t = "boolean" }, UiScale = { t = "number", min = 0.7, max = 1.5 },
    PanelEnabled = { t = "boolean" }, SidebarEnabled = { t = "boolean" },
    PersistenceEnabled = { t = "boolean" }, ConfigVersion = { t = "number", min = 1, max = 1000 },
}

-- Estado em memória: cópia do perfil padrão (sem duplicar valores em outro lugar)
local CurrentState: any = {}
for k, v in pairs(DEFAULT_PROFILE) do CurrentState[k] = v end

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
    if SCHEMA[key] ~= nil then
        local okV, why = SimConfig.ValidateValue(key, value)
        if not okV then
            warn("[SimConfig] Valor rejeitado: " .. tostring(why))
            return
        end
    end
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

local function LegacyImportJSON(jsonStr: string): boolean
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

-- =========================================================================
-- PERFIL PADRÃO, VALIDAÇÃO E PERSISTÊNCIA
-- =========================================================================
SimConfig.DefaultProfileName = DEFAULT_NAME
SimConfig.ConfigVersion = CONFIG_VERSION
SimConfig.LastLoadStatus = "none"   -- "first_run" | "loaded" | "restored_defaults" | "none"
SimConfig.LastLoadReason = ""
SimConfig.DiagnosticLog = {} :: { string }

local function LogReason(msg: string)
    table.insert(SimConfig.DiagnosticLog, msg)
    if #SimConfig.DiagnosticLog > 50 then table.remove(SimConfig.DiagnosticLog, 1) end
    warn("[SimConfig] " .. msg)
end

function SimConfig.GetDefaults(): any
    local c: any = {}
    for k, v in pairs(DEFAULT_PROFILE) do c[k] = v end
    return c
end

-- Valida um valor isolado. Retorna (ok, motivo)
function SimConfig.ValidateValue(key: string, value: any): (boolean, string?)
    local rule = SCHEMA[key]
    if not rule then return false, "chave desconhecida: " .. tostring(key) end
    if type(value) ~= rule.t then
        return false, string.format("%s: esperado %s, recebido %s", key, rule.t, type(value))
    end
    if rule.t == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            return false, key .. ": número não finito"
        end
        if (rule.min and value < rule.min) or (rule.max and value > rule.max) then
            return false, string.format("%s: %s fora da faixa [%s, %s]", key, tostring(value), tostring(rule.min), tostring(rule.max))
        end
    end
    if rule.enum and not table.find(rule.enum, value) then
        return false, string.format("%s: valor '%s' não permitido", key, tostring(value))
    end
    return true, nil
end

-- Valida uma tabela inteira. Retorna (limpa, erros). Qualquer erro => importação rejeitada pelo chamador.
function SimConfig.Validate(data: any): (any, { string })
    local errors: { string } = {}
    local clean: any = {}
    if type(data) ~= "table" then
        return clean, { "configuração não é uma tabela" }
    end
    if type(data.ConfigVersion) ~= "number" then
        table.insert(errors, "ConfigVersion ausente")
    elseif data.ConfigVersion ~= CONFIG_VERSION then
        table.insert(errors, string.format("versão incompatível: %s (esperada %d)", tostring(data.ConfigVersion), CONFIG_VERSION))
    end
    for k, v in pairs(data) do
        local ok, why = SimConfig.ValidateValue(k, v)
        if ok then clean[k] = v else table.insert(errors, why :: string) end
    end
    -- Segurança: perfis importados/persistidos nunca ligam automação de câmera ou disparo sozinhos
    -- no primeiro carregamento; o usuário inicia explicitamente. (Aplicado em Load, não em Import manual.)
    return clean, errors
end

function SimConfig.RestoreDefaults(reason: string?)
    for k, v in pairs(DEFAULT_PROFILE) do
        (CurrentState :: any)[k] = v
        SimConfig.Notify(k, v)
    end
    if reason then LogReason("Padrões restaurados: " .. reason) end
end

function SimConfig.ExportJSON(): string
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(CurrentState)
    end)
    return ok and encoded or "{}"
end

-- Importação validada e atômica: se houver QUALQUER erro nada é aplicado. Retorna (ok, erros)
function SimConfig.ImportJSON(jsonStr: string): (boolean, { string })
    local ok, data = pcall(function() return HttpService:JSONDecode(jsonStr) end)
    if not ok then return false, { "JSON inválido" } end
    local clean, errors = SimConfig.Validate(data)
    if #errors > 0 then return false, errors end
    for k, v in pairs(clean) do
        if (CurrentState :: any)[k] ~= v then
            (CurrentState :: any)[k] = v
            SimConfig.Notify(k, v)
        end
    end
    return true, {}
end

-- Armazenamento injetável (testes usam um adaptador em memória). Padrão: arquivo local do
-- executor quando existir; caso contrário, sem persistência (registrado, não silencioso).
local STORE_FILE = "DeepHat_Simulation_Config.json"
local Storage: any = {
    read = function(): string?
        local rf = (getfenv and (getfenv() :: any).readfile) or nil
        local isf = (getfenv and (getfenv() :: any).isfile) or nil
        if rf and isf then
            local okE, exists = pcall(isf, STORE_FILE)
            if okE and exists then
                local okR, content = pcall(rf, STORE_FILE)
                if okR then return content end
            end
        end
        return nil
    end,
    write = function(content: string): boolean
        local wf = (getfenv and (getfenv() :: any).writefile) or nil
        if not wf then return false end
        return (pcall(wf, STORE_FILE, content))
    end,
}

function SimConfig.SetStorage(adapter: any)
    Storage = adapter
end

function SimConfig.Save(): boolean
    if CurrentState.PersistenceEnabled ~= true then return false end
    local okW = Storage.write(SimConfig.ExportJSON())
    if not okW then LogReason("Persistência indisponível: configuração não salva") end
    return okW
end

-- Primeira execução: aplica padrões. Demais: carrega o salvo se válido; senão, restaura padrões
-- e registra o motivo. Automação de câmera e disparo sempre voltam DESLIGADAS ao carregar.
function SimConfig.Load(): string
    local raw = Storage.read()
    if raw == nil or raw == "" then
        SimConfig.RestoreDefaults()
        SimConfig.LastLoadStatus, SimConfig.LastLoadReason = "first_run", "nenhuma configuração salva"
        return "first_run"
    end
    local ok, data = pcall(function() return HttpService:JSONDecode(raw) end)
    local errors: { string } = {}
    local clean: any = nil
    if not ok then
        errors = { "JSON corrompido" }
    else
        clean, errors = SimConfig.Validate(data)
    end
    if #errors > 0 then
        SimConfig.RestoreDefaults(table.concat(errors, "; "))
        SimConfig.LastLoadStatus, SimConfig.LastLoadReason = "restored_defaults", table.concat(errors, "; ")
        return "restored_defaults"
    end
    for k, v in pairs(clean) do
        (CurrentState :: any)[k] = v
        SimConfig.Notify(k, v)
    end
    for _, k in ipairs({ "AimbotEnabled", "SilentAimEnabled" }) do
        (CurrentState :: any)[k] = false
        SimConfig.Notify(k, false)
    end
    SimConfig.LastLoadStatus, SimConfig.LastLoadReason = "loaded", ""
    return "loaded"
end

return SimConfig

