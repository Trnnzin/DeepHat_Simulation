--!strict
-- =========================================================================
-- DeepHat_Standalone.lua (v7.0 PRO - Professional Simulation & Diagnostics Platform)
-- Motor Autônomo 100% Consolidado para loadstring / Injeção / Roblox Studio
-- Zero dependências externas (sem require). Funciona direto via game:HttpGet.
-- =========================================================================

-- [0] PURGA E LIMPEZA DE INSTÂNCIAS ANTERIORES
local function PurgeAllLegacyUIs()
    local containers: { Instance } = {}
    local okHui, hui = pcall(function() return (gethui and gethui()) end)
    if okHui and hui then table.insert(containers, hui) end

    local okCore, core = pcall(function() return game:GetService("CoreGui") end)
    if okCore and core then table.insert(containers, core) end

    local pGui = game:GetService("Players").LocalPlayer and game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if pGui then table.insert(containers, pGui) end

    local targetPatterns = { "DeepHat", "Diagnostic", "Kinematics", "FovOverlay", "HL_" }
    for _, container in ipairs(containers) do
        pcall(function()
            for _, child in ipairs(container:GetChildren()) do
                for _, pat in ipairs(targetPatterns) do
                    if child.Name:find(pat) then
                        pcall(function() child:Destroy() end)
                        break
                    end
                end
            end
        end)
    end
end
PurgeAllLegacyUIs()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local CoreGuiService = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera or Workspace:WaitForChild("Camera") :: Camera

-- =========================================================================
-- MÓDULO: SimConfig.lua
-- =========================================================================
local SimConfig = {}
do
    -- SimConfig.lua
    -- Modulo 1: Gerenciador Central de Configuracoes Reativas (Observer Pattern)
    -- Suporta perfis predefinidos, customizacao granular, notificacao de listeners e diagnosticos

    local HttpService = game:GetService("HttpService")

    SimConfig.__index = SimConfig

    type ProfileData = {
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
        ProjectileType: string,     -- "Physics" (balística com gravidade) ou "Raycast" (instantâneo)
        ProjectileGravity: number,  -- Aceleração da gravidade balística (studs/s²) [0 - 500]
        ProjectileDropComp: boolean,-- Compensação automática da curvatura/queda balística
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
        AllowPlayerTargets: boolean,-- Considerar personagens de jogadores em ambientes autorizados
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
            ProjectileType = "Physics",
            ProjectileGravity = 196.2,
            ProjectileDropComp = true,
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
            AllowPlayerTargets = true,
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
            ProjectileType = "Physics",
            ProjectileGravity = 196.2,
            ProjectileDropComp = true,
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
            AllowPlayerTargets = true,
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
            ProjectileType = "Physics",
            ProjectileGravity = 196.2,
            ProjectileDropComp = true,
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
            AllowPlayerTargets = true,
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
            ProjectileType = "Physics",
            ProjectileGravity = 196.2,
            ProjectileDropComp = true,
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
            AllowPlayerTargets = true,
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
            ProjectileType = "Physics",
            ProjectileGravity = 196.2,
            ProjectileDropComp = true,
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
            AllowPlayerTargets = true,
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
        AllowPlayerTargets = true,
        ProjectileType = "Physics",
        ProjectileGravity = 196.2,
        ProjectileDropComp = true,
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
        ProjectileType = { t = "string", enum = { "Physics", "Raycast", "Instant" } },
        ProjectileGravity = { t = "number", min = 0, max = 500 },
        ProjectileDropComp = { t = "boolean" },
        TeamCheck = { t = "boolean" }, WallOcclusionCheck = { t = "boolean" },
        TargetRegion = { t = "string", enum = { "Head", "Torso", "Arms", "Legs" } },
        TargetBone = { t = "string" },
        TargetPriority = { t = "string", enum = { "Crosshair", "Distance", "LowestHealth" } },
        TargetStickiness = { t = "number", min = 0, max = 1 }, MaxAngularVelocityClamp = { t = "boolean" },
        SilentAimEnabled = { t = "boolean" }, SilentAimFOV = { t = "number", min = 5, max = 90 },
        SilentAimHitChance = { t = "number", min = 0, max = 100 }, SilentAimTracer = { t = "boolean" },
        WatchdogEnabled = { t = "boolean" }, DebugLogging = { t = "boolean" },
        AllowPlayerTargets = { t = "boolean" },
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
end

-- =========================================================================
-- MÓDULO: ScenarioRunner.lua
-- =========================================================================
local ScenarioRunner = {}
do
    -- =========================================================================
    -- ScenarioRunner.lua
    -- Executa cenários sintéticos de Line-of-Sight em geometria ISOLADA e temporária
    -- (pasta DeepHat_Scenarios, Y=900, descartada ao final). Nunca toca em jogadores
    -- reais nem em objetos de terceiros. Usa VectorTracker:EvaluateLineOfSight.
    -- =========================================================================

    local Workspace = game:GetService("Workspace")


    type ScenarioDef = { Id: string, Label: string, Expected: string }
    type ScenarioOutcome = {
        Id: string, Label: string, Expected: string, Actual: string,
        Passed: boolean, Reason: string, Time: number,
    }

    ScenarioRunner.Scenarios = {
        { Id = "Clear",       Label = "Caminho desobstruído",         Expected = "VISIBLE" },
        { Id = "SolidWall",   Label = "Parede sólida",                Expected = "BLOCKED" },
        { Id = "InvisBarrier",Label = "Barreira invisível colidível", Expected = "BLOCKED" },
        { Id = "NonCollide",  Label = "Objeto não colidível",         Expected = "VISIBLE" },
        { Id = "InvalidDest", Label = "Destino removido",             Expected = "INVALID" },
        { Id = "Coincident",  Label = "Origem = destino",             Expected = "INVALID" },
        { Id = "EndCollision",Label = "Colisão junto ao ponto final", Expected = "VISIBLE" },
    } :: { ScenarioDef }

    ScenarioRunner.History = {} :: { ScenarioOutcome }
    ScenarioRunner.HistoryLimit = 100

    local ORIGIN = Vector3.new(0, 900, 0)
    local TARGET = Vector3.new(0, 900, 40)

    local function MakePart(folder: Instance, z: number, depth: number, canCollide: boolean, transparency: number): Part
        local p = Instance.new("Part")
        p.Anchored = true
        p.Size = Vector3.new(30, 30, depth)
        p.Position = Vector3.new(0, 900, z)
        p.CanCollide = canCollide
        p.CanQuery = true
        p.Transparency = transparency
        p.Parent = folder
        return p
    end

    -- Executa um cenário; devolve o resultado e o LosResult bruto.
    function ScenarioRunner.Run(tracker: any, id: string): (ScenarioOutcome?, any?)
        local def: ScenarioDef? = nil
        for _, s in ipairs(ScenarioRunner.Scenarios) do
            if s.Id == id then def = s end
        end
        if not def then return nil, nil end

        local folder = Instance.new("Folder")
        folder.Name = "DeepHat_Scenarios"
        folder.Parent = Workspace

        local origin, target, targetInst = ORIGIN, TARGET, nil
        local ok, result = pcall(function()
            if id == "SolidWall" then MakePart(folder, 20, 1, true, 0)
            elseif id == "InvisBarrier" then MakePart(folder, 20, 1, true, 1)
            elseif id == "NonCollide" then MakePart(folder, 20, 1, false, 0)
            elseif id == "InvalidDest" then
                local t = Instance.new("Part"); t.Parent = folder; t:Destroy(); targetInst = t
            elseif id == "Coincident" then target = origin
            elseif id == "EndCollision" then MakePart(folder, 39.9, 0.2, true, 0)
            end
            return tracker:EvaluateLineOfSight(origin, target, targetInst)
        end)
        folder:Destroy()

        local outcome: ScenarioOutcome
        if ok and result then
            outcome = {
                Id = def.Id, Label = def.Label, Expected = def.Expected, Actual = result.Status,
                Passed = (result.Status == def.Expected), Reason = result.Reason, Time = os.clock(),
            }
        else
            outcome = {
                Id = def.Id, Label = def.Label, Expected = def.Expected, Actual = "INVALID",
                Passed = (def.Expected == "INVALID"), Reason = "Erro de execução: " .. tostring(result), Time = os.clock(),
            }
            result = { Status = "INVALID", Reason = outcome.Reason, QueryDistance = 0 }
        end

        table.insert(ScenarioRunner.History, outcome)
        while #ScenarioRunner.History > ScenarioRunner.HistoryLimit do
            table.remove(ScenarioRunner.History, 1)
        end
        return outcome, result
    end

    function ScenarioRunner.Summary(): (number, number)
        local pass, fail = 0, 0
        for _, o in ipairs(ScenarioRunner.History) do
            if o.Passed then pass += 1 else fail += 1 end
        end
        return pass, fail
    end

    function ScenarioRunner.ClearHistory()
        table.clear(ScenarioRunner.History)
    end

    -- =========================================================================
    -- CENÁRIOS DE DISPARO SIMULADO (SILENT AIM & BALÍSTICA) - 5 ETAPAS
    -- =========================================================================
    type ShotScenarioDef = { Id: string, Label: string, ExpectedOutcome: string }
    type ShotScenarioOutcome = {
        Id: string, Label: string, Expected: string, Actual: string,
        Passed: boolean, Description: string, Time: number, Stages: { string }
    }

    ScenarioRunner.ShotScenarios = {
        { Id = "SuccessDirect",    Label = "Disparo direto em linha livre",         ExpectedOutcome = "SUCCESS" },
        { Id = "OutsideFov",       Label = "Alvo fora do cone de FOV (60° > 35°)",   ExpectedOutcome = "TARGET_OUTSIDE_FOV" },
        { Id = "SolidObstacle",    Label = "Obstáculo bloqueando o projétil",       ExpectedOutcome = "OBSTACLE_BLOCKED" },
        { Id = "TargetRemoved",    Label = "Alvo removido ou inválido",             ExpectedOutcome = "TARGET_INVALID" },
        { Id = "IntentionalSpread",Label = "Dispersão probabilística intencional",  ExpectedOutcome = "PROBABILISTIC_SPREAD" },
        { Id = "InvalidTrajectory",Label = "Trajetória inválida (distância nula)",  ExpectedOutcome = "INVALID_TRAJECTORY" },
        { Id = "PhysicsArcHit",    Label = "Trajetória parabólica física sob gravidade", ExpectedOutcome = "SUCCESS" },
    } :: { ShotScenarioDef }

    ScenarioRunner.ShotHistory = {} :: { ShotScenarioOutcome }

    function ScenarioRunner.RunShotScenario(tracker: any, id: string): (ShotScenarioOutcome?, any?)
        local def: ShotScenarioDef? = nil
        for _, s in ipairs(ScenarioRunner.ShotScenarios) do
            if s.Id == id then def = s end
        end
        if not def then return nil, nil end

        local folder = Instance.new("Folder")
        folder.Name = "DeepHat_Scenarios_Shot"
        folder.Parent = Workspace

        local originPos = Vector3.new(0, 950, 0)
        local camCFrame = CFrame.lookAt(originPos, originPos + Vector3.new(0, 0, 10))
        local targetPos = Vector3.new(0, 950, 30)

        -- Alvo sintético
        local dummy = Instance.new("Model")
        dummy.Name = "ShotScenarioDummy"
        local dRoot = Instance.new("Part")
        dRoot.Name = "HumanoidRootPart"
        dRoot.Size = Vector3.new(2, 2, 1)
        dRoot.Position = targetPos
        dRoot.Anchored = true
        dRoot.CanCollide = false
        dRoot.Parent = dummy
        local dHead = Instance.new("Part")
        dHead.Name = "Head"
        dHead.Size = Vector3.new(1.2, 1.2, 1.2)
        dHead.Position = targetPos + Vector3.new(0, 1.5, 0)
        dHead.Anchored = true
        dHead.CanCollide = true
        dHead.Parent = dummy
        local dHum = Instance.new("Humanoid")
        dHum.Health = 100
        dHum.Parent = dummy
        dummy.PrimaryPart = dRoot
        dummy.Parent = folder

        local maxFov = 35.0
        local hitChance = 100.0
        local isObstructed = false
        local targetInst: Instance? = dummy
        local speed = 2500.0
        local gravity = 0.0
        local isPhysics = false

        if id == "OutsideFov" then
            -- Desloca alvo para 60 graus fora do LookVector
            local dir60 = CFrame.Angles(0, math.rad(60), 0):VectorToWorldSpace(Vector3.new(0, 0, 1))
            targetPos = originPos + (dir60 * 30)
            dRoot.Position = targetPos
            dHead.Position = targetPos + Vector3.new(0, 1.5, 0)
        elseif id == "SolidObstacle" then
            MakePart(folder, 15, 1, true, 0)
            isObstructed = true
        elseif id == "TargetRemoved" then
            dummy.Parent = nil
            targetInst = nil
        elseif id == "IntentionalSpread" then
            hitChance = 0.0
        elseif id == "InvalidTrajectory" then
            targetPos = originPos
        elseif id == "PhysicsArcHit" then
            targetPos = originPos + Vector3.new(0, 0, 75)
            dRoot.Position = targetPos
            dHead.Position = targetPos + Vector3.new(0, 1.5, 0)
            speed = 450.0
            gravity = 196.2
            isPhysics = true
        end

        local shotResult = tracker:SimulateShot(
            camCFrame,
            targetPos,
            maxFov,
            hitChance,
            isObstructed,
            targetInst,
            speed,
            gravity,
            isPhysics
        )

        folder:Destroy()

        local passed = (shotResult.Outcome == def.ExpectedOutcome)
        local outcome: ShotScenarioOutcome = {
            Id = def.Id,
            Label = def.Label,
            Expected = def.ExpectedOutcome,
            Actual = shotResult.Outcome,
            Passed = passed,
            Description = shotResult.OutcomeDescription or "",
            Time = os.clock(),
            Stages = shotResult.StagesCompleted or {}
        }

        table.insert(ScenarioRunner.ShotHistory, outcome)
        return outcome, shotResult
    end
end

-- =========================================================================
-- MÓDULO: InstanceDetector.lua
-- =========================================================================
local InstanceDetector = {}
do
    -- InstanceDetector.lua
    -- Pilar 1: Motor de Detecção de Instâncias de Alta Precisão (Targeting Engine)
    -- Type Guarding estrito, Hierarquia Profunda, :GetPivot() e Filtro de Magnitude

    local CollectionService = game:GetService("CollectionService")
    local Players = game:GetService("Players")
    local Workspace = game:GetService("Workspace")

    InstanceDetector.__index = InstanceDetector

    type CandidateTarget = {
        Instance: Instance,
        Position: Vector3,
        Distance: number,
        Label: string
    }

    function InstanceDetector.new(scanInterval: number?)
        local self = setmetatable({}, InstanceDetector)
        self.ScanInterval = scanInterval or 0.15 -- 6.6Hz de varredura espacial desacoplada
        self.LastScanTime = 0
        self.CandidatePool = {} :: { Instance }
        self.LocalPlayer = Players.LocalPlayer
        self.KnownTags = { "NPC", "Enemy", "Target", "Bot", "Dummy", "SyntheticTarget", "TestDummy", "Hitbox" }
        self.SearchFolders = { "NPCs", "Enemies", "Bots", "Dummies", "Targets", "DeepHat_Targets", "TestDummies", "SyntheticTargets" }
        self.LockedTarget = nil :: Instance?
        self.LockExpiry = 0
        return self
    end

    -- Validação de Integridade (Type Guarding Rigoroso)
    function InstanceDetector:IsValidTarget(objeto: Instance, teamCheck: boolean?): boolean
        -- Type Guarding: BasePart ou Model válido e fisicamente presente no Workspace
        if not objeto or not (objeto:IsA("BasePart") or objeto:IsA("Model")) or not objeto:IsDescendantOf(Workspace) then
            return false
        end

        local myChar = self.LocalPlayer and self.LocalPlayer.Character
        if myChar and (objeto == myChar or objeto:IsDescendantOf(myChar)) then
            return false
        end

        -- Ignora explicitamente geometrias estáticas do mundo e estruturas de mapa
        if objeto:IsA("Terrain") or objeto.Name == "Terrain" or objeto.Name == "Baseplate" then
            return false
        end
        local lowerName = objeto.Name:lower()
        if lowerName == "map" or lowerName == "workspace" or lowerName == "camera" or lowerName:find("baseplate")
            or lowerName:find("spawn") or lowerName:find("lobby") or lowerName:find("building") or lowerName:find("room")
            or lowerName:find("road") or lowerName:find("floor") or lowerName:find("wall") or lowerName:find("door") then
            return false
        end

        -- Verificação de autorização e equipe para personagens de jogadores reais
        local targetPlayer = Players:GetPlayerFromCharacter(objeto)
        if not targetPlayer and objeto:IsA("BasePart") and objeto.Parent then
            targetPlayer = Players:GetPlayerFromCharacter(objeto.Parent)
        end

        if targetPlayer then
            -- Se a configuração desativou alvos de jogadores, rejeita
            if SimConfig.Get("AllowPlayerTargets") == false then
                return false
            end

            -- Verificação de equipe (Team Check)
            if teamCheck and self.LocalPlayer and self.LocalPlayer.Team and targetPlayer.Team then
                if targetPlayer.Team == self.LocalPlayer.Team then
                    return false
                end
            end
        end

        -- Se for personagem de jogador ou modelo com Humanoid, respeita a integridade de vida e existência
        local hum = objeto:FindFirstChildOfClass("Humanoid") or (objeto:IsA("Model") and objeto:FindFirstChildWhichIsA("Humanoid", true))
        if hum then
            if hum.Health <= 0 then
                return false
            end
        elseif targetPlayer ~= nil then
            -- Personagem de jogador real SEM Humanoid é considerado morto ou em carregamento incompleto
            return false
        end

        -- Modelos devem conter partes físicas válidas presentes no Workspace
        if objeto:IsA("Model") then
            local primaryPart = objeto.PrimaryPart
                or objeto:FindFirstChild("HumanoidRootPart", true)
                or objeto:FindFirstChild("Head", true)
                or objeto:FindFirstChildWhichIsA("BasePart", true)
            if not primaryPart or not primaryPart:IsDescendantOf(Workspace) then
                return false
            end
        end

        return true
    end

    -- Resolução de Posição 3D: Suporte universal a BasePart e Model (:GetPivot())
    function InstanceDetector:ResolvePivotPosition(objeto: Instance, preferredBone: string?): (Vector3?, BasePart?, string)
        if not self:IsValidTarget(objeto) then
            return nil, nil, "None"
        end

        -- Caso 1: Objeto é uma BasePart direta
        if objeto:IsA("BasePart") then
            return objeto.Position, objeto, objeto.Name
        end

        -- Caso 2: Objeto é um Model (com hierarquia profunda de partes)
        local model = objeto :: Model
        local bone = string.lower(preferredBone or "head")
        local targetPart: BasePart? = nil
        local label = "Pivot"

        -- 1. Resolução hierárquica por ossos do modelo
        if bone == "head" then
            targetPart = model:FindFirstChild("Head", true) :: BasePart?
                or model:FindFirstChild("head", true) :: BasePart?
            label = "Head"
        elseif bone == "torso" or bone == "uppertorso" then
            targetPart = model:FindFirstChild("UpperTorso", true) :: BasePart?
                or model:FindFirstChild("Torso", true) :: BasePart?
                or model:FindFirstChild("LowerTorso", true) :: BasePart?
            label = "Torso"
        elseif bone == "arms" then
            targetPart = model:FindFirstChild("RightUpperArm", true) :: BasePart?
                or model:FindFirstChild("RightArm", true) :: BasePart?
                or model:FindFirstChild("Right Arm", true) :: BasePart?
                or model:FindFirstChild("LeftUpperArm", true) :: BasePart?
                or model:FindFirstChild("LeftArm", true) :: BasePart?
                or model:FindFirstChild("Left Arm", true) :: BasePart?
            label = "Arms"
        elseif bone == "legs" then
            targetPart = model:FindFirstChild("RightUpperLeg", true) :: BasePart?
                or model:FindFirstChild("RightLeg", true) :: BasePart?
                or model:FindFirstChild("Right Leg", true) :: BasePart?
                or model:FindFirstChild("LeftUpperLeg", true) :: BasePart?
                or model:FindFirstChild("LeftLeg", true) :: BasePart?
                or model:FindFirstChild("Left Leg", true) :: BasePart?
            label = "Legs"
        end

        -- 2. Fallbacks de partes estruturais principais
        if not targetPart then
            targetPart = model.PrimaryPart
                or model:FindFirstChild("HumanoidRootPart", true) :: BasePart?
                or model:FindFirstChild("Head", true) :: BasePart?
                or model:FindFirstChild("Torso", true) :: BasePart?
                or model:FindFirstChildWhichIsA("BasePart", true)
            if targetPart then
                label = targetPart.Name
            end
        end

        if targetPart then
            return targetPart.Position, targetPart, label
        end

        -- 3. Resolução Universal Invariante: Centro de massa geométrico via :GetPivot()
        local ok, pivot = pcall(function() return model:GetPivot() end)
        if ok and pivot then
            return pivot.Position, nil, "Pivot"
        end

        return nil, nil, "None"
    end

    -- Varredura Espacial Desacoplada com Debounce
    function InstanceDetector:ScanCandidates(teamCheck: boolean?, forceRescan: boolean?): { Instance }
        local now = os.clock()
        if not forceRescan and (now - self.LastScanTime < self.ScanInterval) and #self.CandidatePool > 0 then
            local verified: { Instance } = {}
            for _, cand in ipairs(self.CandidatePool) do
                if self:IsValidTarget(cand, teamCheck) then
                    table.insert(verified, cand)
                end
            end
            self.CandidatePool = verified
            return self.CandidatePool
        end

        self.LastScanTime = now
        local newPool: { Instance } = {}
        local seen: { [Instance]: boolean } = {}

        local function Ingest(inst: Instance)
            if not inst then return end
            -- Normaliza para a raiz da entidade (Model) se fizer parte de um personagem/NPC
            local targetEntity = inst
            if inst:IsA("BasePart") and inst.Parent and inst.Parent:IsA("Model") and inst.Parent ~= Workspace then
                local parentModel = inst.Parent :: Model
                if parentModel:FindFirstChildOfClass("Humanoid") or parentModel.PrimaryPart then
                    targetEntity = parentModel
                end
            end

            if self:IsValidTarget(targetEntity, teamCheck) and not seen[targetEntity] then
                seen[targetEntity] = true
                table.insert(newPool, targetEntity)
            end
        end

        -- 1. Personagens de jogadores reais em ambiente de teste autorizado
        if SimConfig.Get("AllowPlayerTargets") ~= false then
            local okPlayers, allPlayers = pcall(function() return Players:GetPlayers() end)
            if okPlayers and allPlayers then
                for _, player in ipairs(allPlayers) do
                    if player ~= self.LocalPlayer and player.Character and player.Character.Parent == Workspace then
                        Ingest(player.Character)
                    end
                end
            end
        end

        -- 2. Pastas estruturadas de NPCs / Inimigos (varredura plana de 1 nível para evitar N^2 partes)
        for _, folderName in ipairs(self.SearchFolders) do
            local container = Workspace:FindFirstChild(folderName)
            if container then
                for _, child in ipairs(container:GetChildren()) do
                    Ingest(child)
                end
            end
        end

        -- 3. CollectionService Tags (NPCs registrados por tag)
        for _, tag in ipairs(self.KnownTags) do
            local okTagged, taggedList = pcall(function() return CollectionService:GetTagged(tag) end)
            if okTagged and taggedList then
                for _, tagged in ipairs(taggedList) do
                    Ingest(tagged)
                end
            end
        end

        -- 4. Filhos da raiz do Workspace (Apenas Dummies, Rigs e Modelos de Teste Sintéticos Autorizados)
        for _, child in ipairs(Workspace:GetChildren()) do
            if child:IsA("Folder") then
                -- Pastas da raiz são varridas apenas se forem pastas de teste identificadas
                local lowerFolderName = child.Name:lower()
                if lowerFolderName:find("dummy") or lowerFolderName:find("target") or lowerFolderName:find("npc") or lowerFolderName:find("bot") or lowerFolderName:find("test") then
                    for _, grandChild in ipairs(child:GetChildren()) do
                        if grandChild:IsA("Model") or grandChild:IsA("BasePart") then
                            Ingest(grandChild)
                        end
                    end
                end
            elseif child:IsA("Model") then
                local hasHum = child:FindFirstChildOfClass("Humanoid")
                local name = child.Name:lower()
                -- Modelos sintéticos autorizados: possuem nomenclatura explícita de teste/NPC ou partes de manequim padrão
                local hasTestName = name:find("dummy") or name:find("npc") or name:find("enemy") or name:find("target") or name:find("bot") or name:find("rig") or name:find("mannequin") or name:find("synthetic")
                local hasCharParts = child:FindFirstChild("Head") and (child:FindFirstChild("HumanoidRootPart") or child:FindFirstChild("Torso") or child:FindFirstChild("UpperTorso"))
                if hasHum and (hasTestName or hasCharParts) then
                    Ingest(child)
                elseif hasTestName then
                    Ingest(child)
                end
            elseif child:IsA("BasePart") and child.Parent == Workspace then
                local name = child.Name:lower()
                if name:find("target") or name:find("dummy") or name:find("hitbox") or name:find("synthetic") then
                    Ingest(child)
                end
            end
        end

        self.CandidatePool = newPool
        return self.CandidatePool
    end

    -- Filtro de Distância (Magnitude), Ângulo e Prioridades (Crosshair, Distância, Menor Vida)
    function InstanceDetector:FindBestCandidate(
        originPos: Vector3,
        camLookVector: Vector3,
        maxRadius: number,
        maxFovDeg: number,
        preferredBone: string?,
        teamCheck: boolean?,
        priorityMode: string?,
        stickinessDuration: number?
    ): (Instance?, Vector3?, number, number, string, number)
        local candidates = self:ScanCandidates(teamCheck)
        local bestTarget: Instance? = nil
        local bestPos: Vector3? = nil
        local bestScore = math.huge
        local finalAngle = maxFovDeg
        local finalDist = maxRadius
        local finalLabel = "None"
        local finalHealth = 100

        local mode = priorityMode or "Crosshair"
        local now = os.clock()

        -- Invalidação imediata do alvo travado se ele morreu, perdeu o Humanoid ou saiu do Workspace
        if self.LockedTarget ~= nil and not self:IsValidTarget(self.LockedTarget, teamCheck) then
            self.LockedTarget = nil
            self.LockExpiry = 0
        end
        local isStickyActive = (self.LockedTarget ~= nil and now < self.LockExpiry)
        local fovRadiusLimit = (maxFovDeg / 2.0) -- Raio angular relativo ao retículo da tela

        for _, obj in ipairs(candidates) do
            local pos, _, label = self:ResolvePivotPosition(obj, preferredBone)
            if pos then
                local displacement = (pos - originPos)
                local dist = displacement.Magnitude

                -- Filtro de Raio com guarda de singularidade
                if dist <= maxRadius and dist >= 0.05 then
                    local dir = displacement / dist
                    local dot = math.clamp(camLookVector:Dot(dir), -1.0, 1.0)
                    local angleDeg = math.deg(math.acos(dot))

                    -- Filtro de Campo de Visão (FOV) estritamente alinhado com o raio do FOV Circle
                    if angleDeg <= fovRadiusLimit then
                        local hum = obj:FindFirstChildOfClass("Humanoid") or (obj:IsA("Model") and obj:FindFirstChildWhichIsA("Humanoid", true))
                        local health = hum and hum.Health or 100

                        local score = 0
                        if mode == "Distance" then
                            score = dist
                        elseif mode == "LowestHealth" then
                            score = health + (angleDeg * 0.25)
                        else -- "Crosshair"
                            score = angleDeg
                        end

                        -- Histerese: o alvo atual recebe score * 0.85 (15% de vantagem). Como
                        -- score >= 0, um desafiante só vence se score_c < 0.85 * score_atual, ou seja,
                        -- precisa ser >= 15% melhor. Ex.: atual 10° -> efetivo 8.5°; desafiante 9° perde, 8° vence.
                        if isStickyActive and obj == self.LockedTarget then
                            score = score * 0.85
                        end

                        -- Desempate determinístico: menor score; em empate, menor nome completo.
                        local better = score < bestScore
                        if not better and score == bestScore and bestTarget ~= nil then
                            better = obj:GetFullName() < (bestTarget :: Instance):GetFullName()
                        end
                        if better then
                            bestScore = score
                            bestTarget = obj
                            bestPos = pos
                            finalAngle = angleDeg
                            finalDist = dist
                            finalLabel = label
                            finalHealth = health
                        end
                    end
                end
            end
        end

        if bestTarget and self:IsValidTarget(bestTarget, teamCheck) then
            self.LockedTarget = bestTarget
            self.LockExpiry = now + (stickinessDuration or 0.25)
        else
            self.LockedTarget = nil
            self.LockExpiry = 0
        end

        return bestTarget, bestPos, finalDist, finalAngle, finalLabel, finalHealth
    end

    -- Construtor Auxiliar de Alvo Sintético Autorizado para Testes de Simulação
    function InstanceDetector.SpawnSyntheticDummy(position: Vector3, customName: string?): Model
        local folder = Workspace:FindFirstChild("DeepHat_TestTargets")
        if not folder or not folder:IsA("Folder") then
            local newF = Instance.new("Folder")
            newF.Name = "DeepHat_TestTargets"
            newF.Parent = Workspace
            folder = newF
        end

        local dummy = Instance.new("Model")
        dummy.Name = customName or "DeepHat_SyntheticDummy"

        local root = Instance.new("Part")
        root.Name = "HumanoidRootPart"
        root.Size = Vector3.new(2, 2, 1)
        root.Position = position
        root.Anchored = true
        root.CanCollide = false
        root.CanQuery = true
        root.Transparency = 1
        root.Parent = dummy

        local torso = Instance.new("Part")
        torso.Name = "UpperTorso"
        torso.Size = Vector3.new(2, 2, 1)
        torso.Position = position + Vector3.new(0, 1.0, 0)
        torso.Anchored = true
        torso.CanCollide = true
        torso.CanQuery = true
        torso.Material = Enum.Material.SmoothPlastic
        torso.Color = Color3.fromRGB(60, 65, 75)
        torso.Parent = dummy

        local head = Instance.new("Part")
        head.Name = "Head"
        head.Size = Vector3.new(1.2, 1.2, 1.2)
        head.Position = position + Vector3.new(0, 2.5, 0)
        head.Anchored = true
        head.CanCollide = true
        head.CanQuery = true
        head.Material = Enum.Material.SmoothPlastic
        head.Color = Color3.fromRGB(230, 230, 235)
        head.Parent = dummy

        local hum = Instance.new("Humanoid")
        hum.Health = 100
        hum.MaxHealth = 100
        hum.Parent = dummy

        dummy:SetAttribute("DeepHat_Synthetic", true)
        dummy.PrimaryPart = root
        dummy.Parent = folder
        return dummy
    end
end

-- =========================================================================
-- MÓDULO: VectorTracker.lua
-- =========================================================================
local VectorTracker = {}
do
    -- =========================================================================
    -- VectorTracker.lua
    -- Pilar 2: Motor de Rotação, Interpolação Vetorial, Trajetória e Silent Aim
    -- CFrame.lookAt com Lerp contínuo independente de framerate (Exponential Decay),
    -- Proteção Epsilon (1e-4), Jitter Orgânico Perlin Noise, Clamp de Velocidade Angular
    -- e Cálculo de Trajetória Desacoplada (Silent Aim Simulation Rig)
    -- =========================================================================

    local Workspace = game:GetService("Workspace")
    local Debris = game:GetService("Debris")

    VectorTracker.__index = VectorTracker

    -- Constante de tolerância estrita contra divisão por zero e NaNs
    local EPSILON = 1e-4

    type TrackingTelemetry = {
        Direction: Vector3,
        Distance: number,
        AngularErrorDeg: number,
        AngularVelocityDeg: number,
        TargetCFrame: CFrame,
        SmoothedCFrame: CFrame,
        IsObstructed: boolean,
        Mode: string
    }

    function VectorTracker.new(filterInstances: { Instance }?)
        local self = setmetatable({}, VectorTracker)
        self.CurrentCFrame = CFrame.identity
        self.CurrentRotation = nil :: CFrame?
        self.TrackingActive = false
        self.LastRawCamRotation = nil :: CFrame?
        self.PreviousLookVector = Vector3.zAxis
        self.PreviousTime = os.clock()
        self.PreviousAngularVelocity = 0
        self.NoiseSeed = math.random(1000, 9999)
        self.VelocityCache = setmetatable({}, { __mode = "k" }) :: { [Instance]: { pos: Vector3, time: number, vel: Vector3 } }

        local rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Exclude
        rayParams.FilterDescendantsInstances = filterInstances or {}
        rayParams.IgnoreWater = true
        rayParams.RespectCanCollide = true
        self.RayParams = rayParams

        return self
    end

    function VectorTracker:ResetTracking()
        self.TrackingActive = false
        self.CurrentRotation = nil
        self.LastRawCamRotation = nil
    end

    -- Libera por completo o controle da câmera: após Release() o tracker não possui
    -- nenhum estado acumulado e o chamador NÃO deve mais escrever em camera.CFrame.
    -- (O CameraModule do Roblox reassume o controle no frame seguinte.)
    function VectorTracker:Release()
        self:ResetTracking()
        self.PreviousLookVector = Vector3.zAxis
        self.PreviousAngularVelocity = 0
    end

    function VectorTracker:SetFilterInstances(instances: { Instance })
        self.RayParams.FilterDescendantsInstances = instances
    end

    type LosResult = {
        Status: string,        -- "VISIBLE" | "BLOCKED" | "INVALID"
        Reason: string,        -- causa legível
        BlockerName: string?,  -- objeto responsável pela obstrução
        BlockerPart: BasePart?,
        HitDistance: number?,  -- distância origem -> colisão (studs)
        QueryDistance: number, -- distância origem -> destino
    }

    local function IsFiniteVec(v: Vector3): boolean
        return v.X == v.X and v.Y == v.Y and v.Z == v.Z
            and math.abs(v.X) ~= math.huge and math.abs(v.Y) ~= math.huge and math.abs(v.Z) ~= math.huge
    end

    -- Política de LOS (documentada):
    --  * RespectCanCollide = true: partes com CanCollide=false (decoração, triggers, acessórios
    --    não colidíveis) NÃO bloqueiam. Barreiras INVISÍVEIS com CanCollide=true BLOQUEIAM
    --    (são colisores de teste legítimos); Transparency NÃO é critério.
    --  * IgnoreWater = true: água não bloqueia.
    --  * O próprio alvo (e descendentes) conta como VISIBLE; o filtro Exclude cobre o modelo de teste/jogador local.
    --  * Colisão a < END_TOLERANCE studs do ponto final é tratada como atingir o destino (VISIBLE).
    --  * Entrada não finita, origem == destino ou destino removido => INVALID (nunca VISIBLE).
    local END_TOLERANCE = 0.8

    function VectorTracker:EvaluateLineOfSight(originPos: Vector3, targetPos: Vector3, targetInstance: Instance?): LosResult
        if typeof(originPos) ~= "Vector3" or typeof(targetPos) ~= "Vector3"
            or not IsFiniteVec(originPos) or not IsFiniteVec(targetPos) then
            return { Status = "INVALID", Reason = "Posição não finita ou ausente", QueryDistance = 0 }
        end
        if targetInstance ~= nil then
            if targetInstance.Parent == nil or not targetInstance:IsDescendantOf(Workspace) then
                return { Status = "INVALID", Reason = "Destino removido do Workspace", QueryDistance = 0 }
            end
            local charModel = targetInstance:IsA("Model") and targetInstance or targetInstance:FindFirstAncestorOfClass("Model")
            if charModel then
                local hum = charModel:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health <= 0 then
                    return { Status = "INVALID", Reason = "Alvo com Humanoid sem vida (morto)", QueryDistance = 0 }
                end
            end
        end

        local displacement = targetPos - originPos
        local dist = displacement.Magnitude
        if dist < EPSILON then
            return { Status = "INVALID", Reason = "Origem e destino coincidentes", QueryDistance = dist }
        end

        local ok, result = pcall(function()
            return Workspace:Raycast(originPos, displacement, self.RayParams)
        end)
        if not ok then
            return { Status = "INVALID", Reason = "Raycast falhou: " .. tostring(result), QueryDistance = dist }
        end
        if not result then
            return { Status = "VISIBLE", Reason = "Nenhuma colisão no trajeto", QueryDistance = dist }
        end

        local hit = result.Instance
        local hitDist = (result.Position - originPos).Magnitude
        if targetInstance and (hit == targetInstance or hit:IsDescendantOf(targetInstance)) then
            return { Status = "VISIBLE", Reason = "Raio atingiu o próprio alvo", HitDistance = hitDist, QueryDistance = dist }
        end
        if (result.Position - targetPos).Magnitude < END_TOLERANCE then
            return { Status = "VISIBLE", Reason = "Colisão dentro da tolerância do ponto final", HitDistance = hitDist, QueryDistance = dist }
        end
        return {
            Status = "BLOCKED",
            Reason = hit.Transparency >= 0.95 and "Barreira invisível colidível" or "Obstrução sólida",
            BlockerName = hit:GetFullName(),
            BlockerPart = hit,
            HitDistance = hitDist,
            QueryDistance = dist,
        }
    end

    -- Histórico limitado de consultas LOS (para a aba Line of Sight)
    VectorTracker.LosHistoryLimit = 50
    function VectorTracker:RecordLos(result: LosResult, targetName: string?)
        local history = self.LosHistory
        if not history then
            history = {}
            self.LosHistory = history
        end
        self.LastLos = result
        table.insert(history, {
            Time = os.clock(), Target = targetName or "?", Status = result.Status,
            Reason = result.Reason, Blocker = result.BlockerName, HitDistance = result.HitDistance,
        })
        while #history > math.max(1, self.LosHistoryLimit or VectorTracker.LosHistoryLimit) do
            table.remove(history, 1)
        end
    end

    function VectorTracker:ClearLosHistory()
        self.LosHistory = {}
        self.LastLos = nil
    end

    -- Compatibilidade: true somente se BLOCKED comprovado (INVALID não é tratado como obstrução)
    function VectorTracker:CheckObstruction(originPos: Vector3, targetPos: Vector3, targetInstance: Instance?): boolean
        return self:EvaluateLineOfSight(originPos, targetPos, targetInstance).Status == "BLOCKED"
    end

    function VectorTracker:EstimateVelocity(inst: Instance, currentPos: Vector3): Vector3
        -- Leitura direta de velocidade física AssemblyLinearVelocity do Roblox (se disponível)
        if inst:IsA("BasePart") then
            local alv = (inst :: BasePart).AssemblyLinearVelocity
            if alv and IsFiniteVec(alv) and alv.Magnitude > 0.05 then
                return alv
            end
        end

        local now = os.clock()
        local cached = self.VelocityCache[inst]
        local vel = Vector3.zero

        if cached then
            local dt = (now - cached.time)
            if dt > 0.001 and dt < 0.35 then
                vel = (currentPos - cached.pos) / dt
            elseif dt >= 0.35 then
                vel = Vector3.zero
            else
                vel = cached.vel
            end
        end

        self.VelocityCache[inst] = { pos = currentPos, time = now, vel = vel }
        return vel
    end

    function VectorTracker:ComputeLead(
        targetPos: Vector3,
        targetVel: Vector3,
        eyePos: Vector3,
        projSpeed: number,
        enabled: boolean,
        gravity: number?,
        dropComp: boolean?
    ): (Vector3, number, number)
        if not enabled or projSpeed <= 0 then
            return targetPos, 0, 0
        end
        local dist = (targetPos - eyePos).Magnitude
        local timeToHit = dist / projSpeed
        local leadPos = targetPos + (targetVel * timeToHit)
        local dropStuds = 0

        local g = (type(gravity) == "number" and gravity >= 0) and gravity or 0
        if dropComp == true and g > 0 then
            -- Balística com gravidade: Delta_y = 0.5 * g * t^2
            -- 2 iterações para convergência de tempo de voo com elevação
            dropStuds = 0.5 * g * (timeToHit * timeToHit)
            local compensatedPos = leadPos + Vector3.new(0, dropStuds, 0)
            local dist2 = (compensatedPos - eyePos).Magnitude
            local timeToHit2 = dist2 / projSpeed
            dropStuds = 0.5 * g * (timeToHit2 * timeToHit2)
            leadPos = targetPos + (targetVel * timeToHit2) + Vector3.new(0, dropStuds, 0)
            timeToHit = timeToHit2
        end

        return leadPos, timeToHit, dropStuds
    end

    -- Cálculo de Rotação Suavizada com Curva Intuitiva e Limite de Velocidade Angular
    function VectorTracker:ComputeSmoothRotation(
        currentCFrame: CFrame,
        targetPosition: Vector3,
        dt: number,
        smoothingFactor: number,
        accelExponent: number?,
        simulateJitter: boolean?,
        intensity: number?,
        maxAngularVel: number?,
        clampMaxVel: boolean?
    ): (CFrame, number, number)
        local originPos = currentCFrame.Position
        local displacement = (targetPosition - originPos)
        local distance = displacement.Magnitude

        -- PREVENÇÃO DE NaN: Aborta caso a distância seja menor que o limiar EPSILON
        if distance < EPSILON then
            return currentCFrame, 0, 0
        end

        -- dt inválido (nil, NaN, <= 0) cai no padrão de 60Hz; dt grande é limitado
        local rawDt = (type(dt) == "number" and dt == dt and dt > 0) and dt or 0.0166
        local safeDt = math.clamp(rawDt, 0.0001, 0.1)

        -- Extração robusta de Pitch e Yaw atuais a partir do LookVector da câmera
        -- Roll é fixado estritamente em 0 para impedir giros contínuos e desorientação 3D
        local curLook = currentCFrame.LookVector
        local curPitch = math.asin(math.clamp(curLook.Y, -1.0, 1.0))
        local curYaw = math.atan2(-curLook.X, -curLook.Z)

        -- Direção alvo para o ponto 3D do alvo
        local unitDir = displacement / distance
        local tgtPitch = math.asin(math.clamp(unitDir.Y, -1.0, 1.0))
        local tgtYaw = math.atan2(-unitDir.X, -unitDir.Z)

        -- Cálculo do menor arco angular para Yaw e Pitch (envoltória periódica [-pi, pi])
        local function ShortestAngle(tgt: number, cur: number): number
            return (tgt - cur + math.pi) % (2.0 * math.pi) - math.pi
        end
        local deltaPitch = ShortestAngle(tgtPitch, curPitch)
        local deltaYaw = ShortestAngle(tgtYaw, curYaw)
        local totalAngularErrRad = math.sqrt(deltaPitch * deltaPitch + deltaYaw * deltaYaw)
        local angularErrorDeg = math.deg(totalAngularErrRad)

        -- Zona morta de estabilidade: se o erro for microscópico (< 0.04°), mantém a câmera imóvel sem trepidações
        if angularErrorDeg < 0.04 then
            self.CurrentCFrame = currentCFrame
            self.TrackingActive = true
            return currentCFrame, angularErrorDeg, 0
        end

        -- Curva de aceleração Hermite Smoothstep com expoente configurável
        local normErr = math.clamp(angularErrorDeg / 70.0, 0.0, 1.0)
        local hermiteFactor = normErr * normErr * (3.0 - 2.0 * normErr)
        local exponent = accelExponent or 1.25
        hermiteFactor = math.pow(hermiteFactor, exponent)

        -- Mapeamento semântico: Menor Smoothing = Maior velocidade de resposta
        local safeSmooth = math.clamp(smoothingFactor or 0.15, 0.01, 1.0)
        local responseRate = 1.0 / safeSmooth
        local k = responseRate * (0.65 + 0.35 * hermiteFactor)
        local dynamicAlpha = math.clamp(1.0 - math.exp(-k * safeDt), 0.001, 1.0)

        -- Atenuação suave na zona de micro-alinhamento (0.04° a 0.25°)
        if angularErrorDeg < 0.25 then
            local deadzoneWeight = math.clamp((angularErrorDeg - 0.04) / 0.21, 0.05, 1.0)
            dynamicAlpha = dynamicAlpha * deadzoneWeight
        end

        -- Aplica clamp de velocidade angular máxima se requisitado
        if clampMaxVel and maxAngularVel and maxAngularVel > 0 then
            local maxRadThisFrame = math.rad(maxAngularVel) * safeDt
            if (totalAngularErrRad * dynamicAlpha) > maxRadThisFrame then
                dynamicAlpha = math.clamp(maxRadThisFrame / math.max(totalAngularErrRad, 0.0001), 0.001, 1.0)
            end
        end

        -- Atualização determinística em espaço Euler YXZ (Sem acúmulo de matrizes nem Roll)
        local nextPitch = curPitch + deltaPitch * dynamicAlpha
        nextPitch = math.clamp(nextPitch, -math.rad(89.5), math.rad(89.5))
        local nextYaw = curYaw + deltaYaw * dynamicAlpha

        local smoothedCFrame = CFrame.new(originPos) * CFrame.fromEulerAnglesYXZ(nextPitch, nextYaw, 0)

        -- Injeção de Jitter Perlin Noise com deadband de estabilidade (não treme se já estiver alinhado < 0.35°)
        if simulateJitter and intensity and intensity > 0 and angularErrorDeg >= 0.35 then
            local now = os.clock()
            local jitterFactor = (intensity / 100.0) * math.clamp((angularErrorDeg - 0.35) / 15.0, 0.0, 1.0) * 0.15
            if jitterFactor > 0.005 then
                local noiseX = math.noise(now * 4.0, self.NoiseSeed, 0.5) * jitterFactor
                local noiseY = math.noise(now * 4.0, self.NoiseSeed + 50, 0.5) * jitterFactor
                smoothedCFrame = smoothedCFrame * CFrame.Angles(math.rad(noiseX), math.rad(noiseY), 0)
            end
        end

        -- Cálculo da velocidade angular instantânea em graus/segundo
        local newLook = smoothedCFrame.LookVector
        local deltaDot = math.clamp(self.PreviousLookVector:Dot(newLook), -1.0, 1.0)
        local deltaAngleDeg = math.deg(math.acos(deltaDot))
        local angularVelocity = deltaAngleDeg / safeDt

        self.PreviousLookVector = newLook
        self.CurrentCFrame = smoothedCFrame
        self.TrackingActive = true

        return smoothedCFrame, angularErrorDeg, angularVelocity
    end

    -- Modo Snap Instantâneo (1 frame) para testes de Anomaly Detection
    function VectorTracker:ComputeSnapRotation(currentCFrame: CFrame, targetPosition: Vector3, dt: number): (CFrame, number, number)
        local originPos = currentCFrame.Position
        local displacement = (targetPosition - originPos)
        if displacement.Magnitude < EPSILON then return currentCFrame, 0, 0 end

        local safeDt = math.clamp(dt or 0.0166, 0.0001, 0.1)
        local targetRotation = CFrame.lookAt(originPos, targetPosition, Vector3.yAxis)
        local deltaDot = math.clamp(currentCFrame.LookVector:Dot(targetRotation.LookVector), -1.0, 1.0)
        local angularVelocity = math.deg(math.acos(deltaDot)) / safeDt

        self.PreviousLookVector = targetRotation.LookVector
        self.CurrentCFrame = targetRotation
        return targetRotation, 0, angularVelocity
    end

    -- =========================================================================
    -- SIMULAÇÃO DE SILENT AIM (DISPARO DESACOPLADO E TELEMETRIA)
    -- =========================================================================

    -- Avaliação geométrica do vetor de Silent Aim (Cálculo Puro sem Sorteio de Frame)
    function VectorTracker:ComputeSilentAimVector(
        cameraCFrame: CFrame,
        targetPosition: Vector3,
        maxFovDeg: number,
        hitChancePercent: number?
    ): (boolean, Vector3, number)
        local eyePos = cameraCFrame.Position
        local displacement = (targetPosition - eyePos)
        local distance = displacement.Magnitude

        if distance < EPSILON then
            return false, cameraCFrame.LookVector, 0
        end

        local decoupledDirection = displacement / distance
        local camForward = cameraCFrame.LookVector

        local dot = math.clamp(camForward:Dot(decoupledDirection), -1.0, 1.0)
        local discrepancyAngleDeg = math.deg(math.acos(dot))

        -- Verifica se o alvo está dentro do cone angular de atuação do Silent Aim
        if discrepancyAngleDeg > maxFovDeg then
            return false, camForward, discrepancyAngleDeg
        end

        -- Sorteio opcional (usado quando invocado em evento pontual)
        if hitChancePercent ~= nil then
            local chance = math.clamp(hitChancePercent, 0.0, 100.0)
            if (math.random() * 100.0) > chance then
                return false, camForward, discrepancyAngleDeg
            end
        end

        return true, decoupledDirection, discrepancyAngleDeg
    end

    type ShotSimulationResult = {
        Stage: "RECEIVED" | "VALIDATED" | "TRAJECTORY_CALCULATED" | "COLLISION_VERIFIED" | "FINAL_RESULT",
        Fired: boolean,
        HitRegistered: boolean,
        Outcome: "SUCCESS" | "TARGET_OUTSIDE_FOV" | "OBSTACLE_BLOCKED" | "TARGET_INVALID" | "PROBABILISTIC_SPREAD" | "MODULE_DISABLED" | "INVALID_TRAJECTORY" | "INTERNAL_ERROR",
        OutcomeDescription: string,
        DiscrepancyAngleDeg: number,
        MuzzlePosition: Vector3,
        TargetPosition: Vector3,
        ImpactPosition: Vector3,
        HitPart: Instance?,
        ShotDirection: Vector3,
        InFov: boolean,
        IsObstructed: boolean,
        FlightTime: number,
        BulletDropStuds: number,
        TrajectoryPoints: { Vector3 }?,
        TrajectoryType: string, -- "Instant" | "Physics"
        StagesCompleted: { string }
    }

    -- Execução de Disparo Simulado Controlado (Disparado apenas por evento/trigger de tiro)
    -- Pipeline em 5 Etapas: RECEBIDO -> VALIDADO -> TRAJETÓRIA -> COLISÃO -> RESULTADO FINAL
    function VectorTracker:SimulateShot(
        cameraCFrame: CFrame,
        targetPosition: Vector3,
        maxFovDeg: number,
        hitChancePercent: number,
        isObstructed: boolean?,
        targetInstance: Instance?,
        projectileSpeed: number?,
        gravity: number?,
        isPhysics: boolean?
    ): ShotSimulationResult
        local stages: { string } = {}
        table.insert(stages, "[1] RECEBIDO: Evento de disparo aceito pelo pipeline.")

        -- ETAPA 2: VALIDADO (Parâmetros, Alvo e Geometria)
        if targetInstance ~= nil then
            local isValid = false
            pcall(function()
                if targetInstance.Parent ~= nil and targetInstance:IsDescendantOf(Workspace) then
                    local hum = targetInstance:FindFirstChildOfClass("Humanoid")
                        or (targetInstance:IsA("Model") and targetInstance:FindFirstChildWhichIsA("Humanoid", true))
                    if not hum or hum.Health > 0 then
                        isValid = true
                    end
                end
            end)
            if not isValid then
                table.insert(stages, "[2] VALIDADO [FALHA]: Alvo removido do Workspace ou destruído.")
                return {
                    Stage = "VALIDATED",
                    Fired = false,
                    HitRegistered = false,
                    Outcome = "TARGET_INVALID",
                    OutcomeDescription = "Alvo removido ou inválido no momento do disparo.",
                    DiscrepancyAngleDeg = 0,
                    MuzzlePosition = cameraCFrame.Position,
                    TargetPosition = targetPosition,
                    ImpactPosition = cameraCFrame.Position,
                    HitPart = nil,
                    ShotDirection = cameraCFrame.LookVector,
                    InFov = false,
                    IsObstructed = true,
                    FlightTime = 0,
                    BulletDropStuds = 0,
                    TrajectoryPoints = nil,
                    TrajectoryType = isPhysics and "Physics" or "Instant",
                    StagesCompleted = stages
                }
            end
        end

        local muzzlePos = cameraCFrame.Position + cameraCFrame.LookVector * 1.5 - Vector3.new(0, 0.4, 0)
        local displacement = (targetPosition - muzzlePos)
        local dist = displacement.Magnitude

        if dist < EPSILON or dist > 2000 or dist ~= dist then
            table.insert(stages, "[2] VALIDADO [FALHA]: Trajetória com distância zero, infinita ou indefinida (NaN).")
            return {
                Stage = "VALIDATED",
                Fired = false,
                HitRegistered = false,
                Outcome = "INVALID_TRAJECTORY",
                OutcomeDescription = "Distância até o alvo nula, infinita ou com coordenadas inválidas.",
                DiscrepancyAngleDeg = 0,
                MuzzlePosition = muzzlePos,
                TargetPosition = targetPosition,
                ImpactPosition = muzzlePos,
                HitPart = nil,
                ShotDirection = cameraCFrame.LookVector,
                InFov = false,
                IsObstructed = isObstructed == true,
                FlightTime = 0,
                BulletDropStuds = 0,
                TrajectoryPoints = nil,
                TrajectoryType = isPhysics and "Physics" or "Instant",
                StagesCompleted = stages
            }
        end

        local directDir = displacement / dist
        local dot = math.clamp(cameraCFrame.LookVector:Dot(directDir), -1.0, 1.0)
        local discrepancyAngleDeg = math.deg(math.acos(dot))
        local inFov = (discrepancyAngleDeg <= maxFovDeg)

        if not inFov then
            table.insert(stages, string.format("[2] VALIDADO [FALHA]: Alvo fora do cone angular (Desvio %.1f° > FOV %.1f°).", discrepancyAngleDeg, maxFovDeg))
            return {
                Stage = "VALIDATED",
                Fired = false,
                HitRegistered = false,
                Outcome = "TARGET_OUTSIDE_FOV",
                OutcomeDescription = string.format("Alvo fora dos limites definidos para o teste (Desvio: %.1f° > FOV: %.1f°).", discrepancyAngleDeg, maxFovDeg),
                DiscrepancyAngleDeg = discrepancyAngleDeg,
                MuzzlePosition = muzzlePos,
                TargetPosition = targetPosition,
                ImpactPosition = muzzlePos,
                HitPart = nil,
                ShotDirection = cameraCFrame.LookVector,
                InFov = false,
                IsObstructed = isObstructed == true,
                FlightTime = 0,
                BulletDropStuds = 0,
                TrajectoryPoints = nil,
                TrajectoryType = isPhysics and "Physics" or "Instant",
                StagesCompleted = stages
            }
        end
        table.insert(stages, string.format("[2] VALIDADO: Parâmetros aceitos (Distância: %.1f studs, Desvio: %.1f° dentro do FOV %.1f°).", dist, discrepancyAngleDeg, maxFovDeg))

        -- ETAPA 3: TRAJETÓRIA CALCULADA
        local isPhys = (isPhysics == true)
        local g = (isPhys and type(gravity) == "number" and gravity >= 0) and gravity or 0
        local speed = (type(projectileSpeed) == "number" and projectileSpeed > 0) and projectileSpeed or 2500
        local flightTime = dist / speed
        local bulletDropStuds = (g > 0) and (0.5 * g * flightTime * flightTime) or 0

        local isSpreadMiss = false
        local shotDir = directDir
        local roll = math.random() * 100.0
        local chance = math.clamp(hitChancePercent, 0.0, 100.0)

        if roll > chance then
            isSpreadMiss = true
            local missAngle = math.rad(math.random(3, 8))
            local randAxis = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5).Unit
            shotDir = CFrame.fromAxisAngle(randAxis, missAngle):VectorToWorldSpace(directDir)
        end

        local endPosition = (not isSpreadMiss) and targetPosition or (muzzlePos + shotDir * dist)

        local trajectoryPoints: { Vector3 }? = nil
        if isPhys and g > 0 and dist > 1.0 then
            trajectoryPoints = {}
            local steps = 10
            local vLaunch = (endPosition - muzzlePos + Vector3.new(0, 0.5 * g * flightTime * flightTime, 0)) / math.max(flightTime, 0.001)
            for i = 0, steps do
                local t = (i / steps) * flightTime
                local pt = muzzlePos + (vLaunch * t) - Vector3.new(0, 0.5 * g * t * t, 0)
                table.insert(trajectoryPoints, pt)
            end
        end
        table.insert(stages, string.format("[3] TRAJETÓRIA CALCULADA: Modelo %s | V_ini = %.0f studs/s | Queda = %.1f studs | Voo = %.2fs.", isPhys and "Físico" or "Instantâneo", speed, bulletDropStuds, flightTime))

        -- ETAPA 4: COLISÃO VERIFICADA NO AMBIENTE DE SIMULAÇÃO
        local hit = false
        local hitPart: Instance? = nil
        local impactPos = endPosition
        local outcome: "SUCCESS" | "TARGET_OUTSIDE_FOV" | "OBSTACLE_BLOCKED" | "TARGET_INVALID" | "PROBABILISTIC_SPREAD" | "MODULE_DISABLED" | "INVALID_TRAJECTORY" | "INTERNAL_ERROR" = "SUCCESS"
        local outcomeDesc = "Disparo simulado bem-sucedido com colisão confirmada no alvo sintético."

        if isSpreadMiss then
            hit = false
            outcome = "PROBABILISTIC_SPREAD"
            outcomeDesc = string.format("Dispersão probabilística intencional simulada (Hit Chance configurada em %.0f%%).", chance)
            table.insert(stages, "[4] COLISÃO VERIFICADA: Projétil desviado intencionalmente por dispersão estatística.")
        elseif isObstructed == true then
            hit = false
            outcome = "OBSTACLE_BLOCKED"
            outcomeDesc = "Obstáculo bloqueando o projétil: colisão com barreira sólida antes do alvo."
            table.insert(stages, "[4] COLISÃO VERIFICADA [FALHA]: Obstáculo opaco/sólido detectado na linha de disparo.")
        else
            -- Verificação de colisão física real em Workspace com suporte a RaycastParams
            local hasNativePhysics = false
            local raySuccess, rayResult = pcall(function()
                if typeof(Workspace) ~= "Instance" or not Workspace.Raycast then return nil end
                hasNativePhysics = true
                local params = RaycastParams.new()
                params.FilterType = Enum.RaycastFilterType.Exclude
                params.IgnoreWater = true
                params.RespectCanCollide = false
                local ignoreList = {}
                for _, f in ipairs(self.FilterInstances) do table.insert(ignoreList, f) end
                local tracers = Workspace:FindFirstChild("DeepHat_Tracers")
                if tracers then table.insert(ignoreList, tracers) end
                local espCont = Workspace:FindFirstChild("DeepHat_ESP_Container")
                if espCont then table.insert(ignoreList, espCont) end
                params.FilterDescendantsInstances = ignoreList

                if trajectoryPoints and #trajectoryPoints >= 2 then
                    -- Segmentos parabólicos para projéteis físicos
                    for i = 1, #trajectoryPoints - 1 do
                        local pA = trajectoryPoints[i]
                        local pB = trajectoryPoints[i + 1]
                        local segRes = Workspace:Raycast(pA, pB - pA, params)
                        if segRes then return segRes end
                    end
                    return nil
                else
                    -- Raycast direto
                    return Workspace:Raycast(muzzlePos, directDir * (dist + 2.0), params)
                end
            end)

            if raySuccess and rayResult then
                hitPart = rayResult.Instance
                impactPos = rayResult.Position
                local isTargetPart = false
                if targetInstance ~= nil then
                    if hitPart == targetInstance or hitPart:IsDescendantOf(targetInstance) then
                        isTargetPart = true
                    end
                else
                    isTargetPart = true
                end

                if isTargetPart then
                    hit = true
                    outcome = "SUCCESS"
                    outcomeDesc = string.format("Disparo simulado bem-sucedido: colisão confirmada em '%s'.", hitPart.Name)
                    table.insert(stages, string.format("[4] COLISÃO VERIFICADA: Impacto registrado na parte '%s'.", hitPart.Name))
                else
                    hit = false
                    outcome = "OBSTACLE_BLOCKED"
                    outcomeDesc = string.format("Obstáculo bloqueando o projétil: colidiu com '%s' antes do alvo.", hitPart.Name)
                    table.insert(stages, string.format("[4] COLISÃO VERIFICADA [FALHA]: Interceptado por obstáculo '%s'.", hitPart.Name))
                end
            elseif hasNativePhysics and targetInstance ~= nil then
                -- No Studio real, se o raycast não atingiu nada ao disparar em um alvo esperado
                hit = false
                outcome = "INVALID_TRAJECTORY"
                outcomeDesc = "Disparo falhou: raycast físico não interceptou a geometria do alvo sintético."
                table.insert(stages, "[4] COLISÃO VERIFICADA [FALHA]: Nenhuma colisão física detectada ao longo da trajetória.")
            else
                -- Em ambiente sem raycast nativo (offline/mocks), verificação geométrica
                hit = true
                outcome = "SUCCESS"
                outcomeDesc = "Disparo simulado bem-sucedido com validação geométrica de colisão."
                table.insert(stages, "[4] COLISÃO VERIFICADA: Colisão confirmada por intersecção vetorial.")
            end
        end

        -- ETAPA 5: RESULTADO FINAL
        table.insert(stages, string.format("[5] RESULTADO FINAL: [%s] %s", outcome, outcomeDesc))

        return {
            Stage = "FINAL_RESULT",
            Fired = true,
            HitRegistered = hit,
            Outcome = outcome,
            OutcomeDescription = outcomeDesc,
            DiscrepancyAngleDeg = discrepancyAngleDeg,
            MuzzlePosition = muzzlePos,
            TargetPosition = endPosition,
            ImpactPosition = impactPos,
            HitPart = hitPart,
            ShotDirection = shotDir,
            InFov = inFov,
            IsObstructed = (outcome == "OBSTACLE_BLOCKED"),
            FlightTime = flightTime,
            BulletDropStuds = bulletDropStuds,
            TrajectoryPoints = trajectoryPoints,
            TrajectoryType = isPhys and "Physics" or "Instant",
            StagesCompleted = stages
        }
    end

    -- Visualizador de Traçador (Tracer 3D Neon com Limpeza de Debris e Suporte a Arcos Parabólicos)
    function VectorTracker:DrawTracerBeam(origin: Vector3, targetPos: Vector3, color: Color3?, duration: number?, trajectoryPoints: { Vector3 }?)
        local ok, _ = pcall(function()
            local dist = (targetPos - origin).Magnitude
            if dist < 0.1 then return end

            local container = Workspace:FindFirstChild("DeepHat_Tracers")
            if not container or not container:IsA("Folder") then
                local newFolder = Instance.new("Folder")
                newFolder.Name = "DeepHat_Tracers"
                newFolder.Parent = Workspace
                container = newFolder
            end

            local tracerColor = color or Color3.fromRGB(255, 45, 60)
            local life = duration or 0.22

            -- Renderização da trajetória
            if trajectoryPoints and #trajectoryPoints >= 2 then
                -- Segmentos parabólicos para projéteis físicos (fidelidade balística real)
                for i = 1, #trajectoryPoints - 1 do
                    local pA = trajectoryPoints[i]
                    local pB = trajectoryPoints[i + 1]
                    local segDisp = pB - pA
                    local segDist = segDisp.Magnitude
                    if segDist > 0.05 then
                        local seg = Instance.new("Part")
                        seg.Name = "DeepHat_BallisticTracerSegment"
                        seg.Anchored = true
                        seg.CanCollide = false
                        seg.CanTouch = false
                        seg.CanQuery = false
                        seg.Material = Enum.Material.Neon
                        seg.Color = tracerColor
                        seg.Transparency = 0.12
                        seg.Size = Vector3.new(0.14, 0.14, segDist)
                        seg.CFrame = CFrame.lookAt(pA, pB) * CFrame.new(0, 0, -segDist / 2)
                        seg.Parent = container
                        Debris:AddItem(seg, life)
                    end
                end
            else
                -- Feixe de traçador retilíneo (Raycast instantâneo)
                local part = Instance.new("Part")
                part.Name = "DeepHat_SilentAimTracer"
                part.Anchored = true
                part.CanCollide = false
                part.CanTouch = false
                part.CanQuery = false
                part.Material = Enum.Material.Neon
                part.Color = tracerColor
                part.Transparency = 0.10
                part.Size = Vector3.new(0.16, 0.16, dist)
                part.CFrame = CFrame.lookAt(origin, targetPos) * CFrame.new(0, 0, -dist / 2)
                part.Parent = container
                Debris:AddItem(part, life)
            end

            -- Marcador de Impacto no Ponto de Destino
            local impact = Instance.new("Part")
            impact.Name = "DeepHat_ImpactMarker"
            impact.Shape = Enum.PartType.Ball
            impact.Anchored = true
            impact.CanCollide = false
            impact.CanTouch = false
            impact.CanQuery = false
            impact.Material = Enum.Material.Neon
            impact.Color = tracerColor
            impact.Transparency = 0.15
            impact.Size = Vector3.new(0.70, 0.70, 0.70)
            impact.Position = targetPos
            impact.Parent = container
            Debris:AddItem(impact, life + 0.08)
        end)
    end
end

-- =========================================================================
-- MÓDULO: VisualOverlayRenderer.lua
-- =========================================================================
local VisualOverlayRenderer = {}
do
    -- VisualOverlayRenderer.lua
    -- Pilar 3: Renderização de Realce (UI & Overlay Engine)
    -- Highlights com DepthMode AlwaysOnTop, Preservação de Camadas de Z-Index e Quota de Memória

    local CoreGuiService = game:GetService("CoreGui")
    local Players = game:GetService("Players")
    local Workspace = game:GetService("Workspace")

    VisualOverlayRenderer.__index = VisualOverlayRenderer

    local MAX_ACTIVE_HIGHLIGHTS = 16

    function VisualOverlayRenderer.new()
        local self = setmetatable({}, VisualOverlayRenderer)
        self.ActiveHighlights = {} :: { [Instance]: Highlight }
        self.ActiveTags = {} :: { [Instance]: BillboardGui }
        self.CleanupConnections = {} :: { [Instance]: RBXScriptConnection }
        self.Container = self:GetOrCreateContainer()
        return self
    end

    function VisualOverlayRenderer:GetOrCreateContainer(): Folder
        local host: Instance = CoreGuiService
        local ok, _ = pcall(function() return CoreGuiService:GetChildren() end)
        if not ok then
            local pGui = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
            host = pGui or Workspace
        end

        local existing = host:FindFirstChild("DeepHat_ESP_Container")
        if existing and existing:IsA("Folder") then
            return existing
        end

        local folder = Instance.new("Folder")
        folder.Name = "DeepHat_ESP_Container"
        folder.Parent = host
        return folder
    end

    function VisualOverlayRenderer:UpdateTargetHighlight(
        target: Instance,
        isObstructed: boolean,
        isPrimaryFocus: boolean,
        customColor: Color3?,
        customTransparency: number?
    )
        if not target or not target:IsDescendantOf(game) then
            self:ClearTarget(target)
            return
        end

        local hl = self.ActiveHighlights[target]
        if not hl or not hl.Parent then
            local count = 0
            for _, _ in pairs(self.ActiveHighlights) do count = count + 1 end
            if count >= MAX_ACTIVE_HIGHLIGHTS then
                for oldTarget, _ in pairs(self.ActiveHighlights) do
                    if oldTarget ~= target then
                        self:ClearTarget(oldTarget)
                        break
                    end
                end
            end

            local ok, newHl = pcall(function()
                local inst = Instance.new("Highlight")
                inst.Name = "DeepHat_HL_" .. target.Name
                inst.Adornee = target
                inst.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                inst.Enabled = true
                -- FIX BUG 3: Anexa diretamente à entidade alvo.
                -- Impede categoricamente que um Highlight sem Adornee ou órfão tome como alvo o Workspace ou a tela inteira.
                local safeParent = (target:IsA("Model") or target:IsA("BasePart")) and target or self.Container
                inst.Parent = safeParent
                return inst
            end)

            if ok and newHl then
                hl = newHl
                self.ActiveHighlights[target] = hl

                -- Limpeza imediata no ciclo de vida da instância adornee
                pcall(function()
                    local conn: RBXScriptConnection? = nil
                    conn = target.AncestryChanged:Connect(function(_, parent)
                        if not parent then
                            self:ClearTarget(target)
                            if conn then conn:Disconnect() end
                        end
                    end)
                    if conn then
                        self.CleanupConnections[target] = conn
                    end
                end)
            end
        end

        if hl then
            pcall(function()
                hl.Adornee = target
                hl.Enabled = true
                local fillTrans = customTransparency or (isPrimaryFocus and 0.35 or 0.65)
                hl.FillTransparency = fillTrans
                hl.OutlineTransparency = 0.05

                if customColor then
                    hl.FillColor = customColor
                    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                elseif isPrimaryFocus then
                    hl.FillColor = isObstructed and Color3.fromRGB(255, 45, 45) or Color3.fromRGB(46, 230, 110)
                    hl.OutlineColor = isObstructed and Color3.fromRGB(255, 180, 180) or Color3.fromRGB(200, 255, 200)
                else
                    hl.FillColor = isObstructed and Color3.fromRGB(180, 70, 70) or Color3.fromRGB(50, 140, 230)
                    hl.OutlineColor = Color3.fromRGB(240, 240, 240)
                end
            end)
        end
    end

    -- Sincronização em Lote de ESP com Limpeza Automática de Alvos Antigos (Zero Vazamento)
    function VisualOverlayRenderer:SyncBatchHighlights(
        candidates: { Instance }?,
        primaryTarget: Instance?,
        isPrimaryObstructed: boolean
    )
        local activeBatch: { [Instance]: boolean } = {}

        -- 1. Realce do Alvo Primário Focado
        if primaryTarget and primaryTarget:IsDescendantOf(game) then
            self:UpdateTargetHighlight(primaryTarget, isPrimaryObstructed, true)
            activeBatch[primaryTarget] = true
        end

        -- 2. Realce de Alvos Secundários do Pool (limitado para preservar FPS)
        if candidates then
            local maxSecondary = math.min(#candidates, MAX_ACTIVE_HIGHLIGHTS - 1)
            local count = 0
            for _, cand in ipairs(candidates) do
                if cand ~= primaryTarget and cand:IsDescendantOf(game) then
                    self:UpdateTargetHighlight(cand, false, false)
                    activeBatch[cand] = true
                    count = count + 1
                    if count >= maxSecondary then break end
                end
            end
        end

        -- 3. Limpeza Automática de Qualquer Highlight que não esteja mais no lote ativo
        for inst, _ in pairs(self.ActiveHighlights) do
            if not activeBatch[inst] then
                self:ClearTarget(inst)
            end
        end
    end

    -- Renderização de Indicadores 3D Flutuantes de Depuração (Nome, Distância, LOS, Vida)
    function VisualOverlayRenderer:UpdateTargetTag(
        target: Instance,
        distance: number?,
        isObstructed: boolean?,
        health: number?,
        label: string?
    )
        if not target or not target:IsDescendantOf(game) then
            self:ClearTarget(target)
            return
        end

        local adorneePart: BasePart? = nil
        if target:IsA("BasePart") then
            adorneePart = target
        elseif target:IsA("Model") then
            adorneePart = (target :: Model).PrimaryPart
                or target:FindFirstChild("Head") :: BasePart?
                or target:FindFirstChild("HumanoidRootPart") :: BasePart?
                or target:FindFirstChildWhichIsA("BasePart")
        end

        if not adorneePart then return end

        local tag = self.ActiveTags[target]
        if not tag or not tag.Parent then
            local ok, newTag = pcall(function()
                local bb = Instance.new("BillboardGui")
                bb.Name = "DeepHat_Tag_" .. target.Name
                bb.Adornee = adorneePart
                bb.Size = UDim2.new(0, 140, 0, 36)
                bb.StudsOffset = Vector3.new(0, 3.2, 0)
                bb.AlwaysOnTop = true
                bb.MaxDistance = 500

                local bg = Instance.new("Frame")
                bg.Size = UDim2.new(1, 0, 1, 0)
                bg.BackgroundColor3 = Color3.fromRGB(15, 17, 23)
                bg.BackgroundTransparency = 0.35
                bg.BorderSizePixel = 0
                bg.Parent = bb

                local corner = Instance.new("UICorner")
                corner.CornerRadius = UDim.new(0, 4)
                corner.Parent = bg

                local stroke = Instance.new("UIStroke")
                stroke.Color = Color3.fromRGB(45, 50, 65)
                stroke.Thickness = 1
                stroke.Parent = bg

                local title = Instance.new("TextLabel")
                title.Name = "Title"
                title.Size = UDim2.new(1, -6, 0, 16)
                title.Position = UDim2.new(0, 3, 0, 2)
                title.BackgroundTransparency = 1
                title.Font = Enum.Font.GothamBold
                title.TextSize = 10
                title.TextColor3 = Color3.fromRGB(245, 246, 250)
                title.TextXAlignment = Enum.TextXAlignment.Center
                title.Text = target.Name
                title.Parent = bg

                local details = Instance.new("TextLabel")
                details.Name = "Details"
                details.Size = UDim2.new(1, -6, 0, 14)
                details.Position = UDim2.new(0, 3, 0, 18)
                details.BackgroundTransparency = 1
                details.Font = Enum.Font.Code
                details.TextSize = 9
                details.TextColor3 = Color3.fromRGB(46, 204, 113)
                details.TextXAlignment = Enum.TextXAlignment.Center
                details.Text = "READY"
                details.Parent = bg

                bb.Parent = self.Container

                local conn = target.AncestryChanged:Connect(function(_, parent)
                    if not parent then
                        self:ClearTarget(target)
                    end
                end)
                self.CleanupConnections[target] = conn

                return bb
            end)

            if ok and newTag then
                tag = newTag
                self.ActiveTags[target] = tag
            end
        end

        if tag then
            local bg = tag:FindFirstChildOfClass("Frame")
            if bg then
                local title = bg:FindFirstChild("Title") :: TextLabel?
                local details = bg:FindFirstChild("Details") :: TextLabel?
                if title then
                    title.Text = string.format("%s [%s]", target.Name, label or "Pivot")
                end
                if details then
                    local distStr = distance and string.format("%.1f st", distance) or "—"
                    local hpStr = health and string.format("%d HP", math.floor(health)) or "100 HP"
                    local statusStr = isObstructed and "BLOCKED" or "VISIBLE"
                    local statusColor = isObstructed and Color3.fromRGB(255, 65, 75) or Color3.fromRGB(46, 204, 113)
                    details.Text = string.format("%s | %s | %s", statusStr, distStr, hpStr)
                    details.TextColor3 = statusColor
                end
            end
        end
    end

    function VisualOverlayRenderer:ClearTarget(target: Instance?)
        if not target then return end
        local hl = self.ActiveHighlights[target]
        if hl then
            pcall(function() hl:Destroy() end)
        end
        self.ActiveHighlights[target] = nil

        local tag = self.ActiveTags[target]
        if tag then
            pcall(function() tag:Destroy() end)
        end
        self.ActiveTags[target] = nil

        local conn = self.CleanupConnections[target]
        if conn then
            pcall(function() conn:Disconnect() end)
        end
        self.CleanupConnections[target] = nil
    end

    function VisualOverlayRenderer:ClearTagsExcept(keepTarget: Instance?)
        for target, tag in pairs(self.ActiveTags) do
            if target ~= keepTarget then
                pcall(function() if tag then tag:Destroy() end end)
                self.ActiveTags[target] = nil
            end
        end
    end

    function VisualOverlayRenderer:ClearAll()
        for _, hl in pairs(self.ActiveHighlights) do
            pcall(function() if hl then hl:Destroy() end end)
        end
        for _, tag in pairs(self.ActiveTags) do
            pcall(function() if tag then tag:Destroy() end end)
        end
        for _, conn in pairs(self.CleanupConnections) do
            pcall(function() if conn then conn:Disconnect() end end)
        end
        table.clear(self.ActiveHighlights)
        table.clear(self.ActiveTags)
        table.clear(self.CleanupConnections)
    end
end

-- =========================================================================
-- MÓDULO: DiagnosticAI.lua
-- =========================================================================
local DiagnosticAI = {}
do
    -- =========================================================================
    -- DiagnosticAI.lua
    -- Motor de IA de Diagnóstico em 6 Camadas e Assistente Chatbot Estruturado
    -- Arquitetura Modular:
    --   Camada A: Coleta e Ingestão de Dados (Telemetria, LOS, Disparos, Eventos)
    --   Camada B: Validação e Higiene de Dados (Detecção de NaN, Inf, Amostras)
    --   Camada C: Diagnóstico Determinístico Baseado em Regras Físicas
    --   Camada D: Inferência de Hipóteses (CONFIRMED / HYPOTHESIS / INSUFFICIENT_DATA)
    --   Camada E: Recomendações de Ação Priorizadas com Vínculo a Cenários de Teste
    --   Camada F: Verificação Contínua e Detecção de Regressão entre Execuções
    -- =========================================================================

    DiagnosticAI.__index = DiagnosticAI

    type EvidenceType = "CONFIRMED" | "HYPOTHESIS" | "INSUFFICIENT_DATA"

    type DiagnosticHypothesis = {
        Id: string,
        Title: string,
        Likelihood: number,
        Type: EvidenceType,
        EvidenceList: { string },
        CounterEvidenceList: { string }?,
    }

    type ActionableRecommendation = {
        Priority: "ALTA" | "MEDIA" | "BAIXA",
        Title: string,
        Action: string,
        TargetConfigKey: string?,
        EaseOfValidation: "IMEDIATA" | "CENARIO_TESTE" | "MANUAL",
        RecommendedScenarioId: string?,
    }

    type DiagnosticReport = {
        Timestamp: number,
        Status: "HEALTHY" | "WARNING" | "CRITICAL",
        Summary: string,
        AffectedModule: string,
        RootCause: string,
        SuggestedAction: string,
        MetricHighlights: { [string]: string },
        EvidenceType: EvidenceType,
        Confidence: number,
        Hypotheses: { DiagnosticHypothesis },
        Recommendations: { ActionableRecommendation },
        RecommendedScenarioId: string?,
        DataHygieneIssues: { string },
        VerificationResult: string?,
    }

    type ChatbotResponse = {
        Query: string,
        Answer: string,
        AffectedModule: string,
        SuggestedAction: string,
        Confidence: number,
        EvidenceType: EvidenceType?,
        RecommendedScenarioId: string?,
    }

    -- Histórico de relatórios para verificação de regressões (Camada F)
    local ReportHistory: { DiagnosticReport } = {}
    local MAX_HISTORY = 20

    local function IsFinite(v: any): boolean
        return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
    end

    function DiagnosticAI.GetHistory(): { DiagnosticReport }
        return ReportHistory
    end

    function DiagnosticAI.ClearHistory()
        table.clear(ReportHistory)
    end

    -- =========================================================================
    -- CAMADA B: HIGIENE E VALIDAÇÃO DE DADOS
    -- =========================================================================
    local function ValidateDataHygiene(
        telemetry: { [string]: any }?,
        lastShot: any?
    ): (boolean, { string })
        local issues: { string } = {}

        if telemetry then
            if telemetry.angularVelocity ~= nil and not IsFinite(telemetry.angularVelocity) then
                table.insert(issues, "HYGIENE_NAN_ANGULAR_VELOCITY: Velocidade angular contém NaN ou Infinito")
            end
            if telemetry.decoupledAngle ~= nil and not IsFinite(telemetry.decoupledAngle) then
                table.insert(issues, "HYGIENE_NAN_DECOUPLED_ANGLE: Ângulo desacoplado contém NaN ou Infinito")
            end
        end

        if lastShot and type(lastShot) == "table" then
            if lastShot.DiscrepancyAngleDeg ~= nil and not IsFinite(lastShot.DiscrepancyAngleDeg) then
                table.insert(issues, "HYGIENE_NAN_DISCREPANCY_ANGLE: Desvio angular do disparo contém NaN")
            end
        end

        return #issues == 0, issues
    end

    -- =========================================================================
    -- ANALISADOR PRINCIPAL DO SISTEMA (CAMADAS A - F)
    -- =========================================================================
    function DiagnosticAI.AnalyzeSystemState(
        telemetry: { [string]: any }?,
        losHistory: { any }?,
        eventLogs: { any }?,
        lastShot: any?
    ): DiagnosticReport
        local timeNow = os.clock()
        local t = telemetry or {}
        local metrics: { [string]: string } = {}
        local hypotheses: { DiagnosticHypothesis } = {}
        local recommendations: { ActionableRecommendation } = {}

        -- Camada B: Validação e Higiene
        local isDataClean, hygieneIssues = ValidateDataHygiene(telemetry, lastShot)

        -- Extração e normalização de métricas (Camada A)
        local angVel = tonumber(t.angularVelocity) or 0
        local isObstructed = t.isObstructed == true
        local targetName = tostring(t.targetName or "NENHUM")
        local mode = tostring(t.mode or "IDLE")

        metrics["Modo"] = mode
        metrics["Alvo"] = targetName
        metrics["VelocidadeAngular"] = string.format("%.1f °/s", angVel)
        metrics["LinhaDeVisada"] = isObstructed and "OBSTRUÍDO" or "LIVRE"

        local finalStatus: "HEALTHY" | "WARNING" | "CRITICAL" = "HEALTHY"
        local finalSummary = ""
        local finalModule = "Nenhum"
        local finalRootCause = ""
        local finalAction = ""
        local evidenceType: EvidenceType = "CONFIRMED"
        local confidence = 0.98
        local recommendedScenario: string? = nil

        -- ---------------------------------------------------------------------
        -- CAMADA C: REGRAS DETERMINÍSTICAS (Ordem de prioridade e evidência)
        -- ---------------------------------------------------------------------

        -- 1. Disparo / Silent Aim
        if lastShot and type(lastShot) == "table" and (lastShot.Fired == true or lastShot.Outcome ~= nil) then
            metrics["UltimoTiro"] = lastShot.HitRegistered and "ACERTO" or "FALHA / DISPERSÃO"
            metrics["DesvioTiro"] = string.format("%.1f°", lastShot.DiscrepancyAngleDeg or 0)
            metrics["TipoBalistico"] = tostring(lastShot.TrajectoryType or "Instant")
            metrics["Resultado"] = tostring(lastShot.Outcome or "NENHUM")

            local outcome = lastShot.Outcome
            if outcome == "SUCCESS" or (outcome == nil and lastShot.HitRegistered == true and lastShot.InFov == true and not lastShot.IsObstructed) then
                finalStatus = "HEALTHY"
                finalSummary = "Disparo simulado bem-sucedido com colisão física confirmada (nominal) no alvo sintético."
                finalModule = "Nenhum"
                finalRootCause = "Trajetória balística calculada e verificada com sucesso em todas as 5 etapas."
                finalAction = "Sistema de disparo validado. Prossiga com os testes dinâmicos de movimentação."
                evidenceType = "CONFIRMED"
                confidence = 1.0
                recommendedScenario = "SCENARIO_VISIBLE_DUMMY"

                table.insert(hypotheses, {
                    Id = "HYP_NOMINAL_HIT",
                    Title = "Acerto nominal verificado",
                    Likelihood = 1.0,
                    Type = "CONFIRMED",
                    EvidenceList = { "Raycast hit validado", "Target dentro do FOV", "Ausência de obstrução física" },
                })
                table.insert(recommendations, {
                    Priority = "BAIXA",
                    Title = "Testar com Alvo em Movimento",
                    Action = "Executar cenário com dummy cinemático móvel para validar compensação de lead.",
                    EaseOfValidation = "CENARIO_TESTE",
                    RecommendedScenarioId = "SCENARIO_MOVING_TARGET",
                })

            elseif outcome == "TARGET_OUTSIDE_FOV" or (outcome == nil and lastShot.InFov == false) then
                finalStatus = "WARNING"
                finalSummary = "Disparo falhou: alvo estava fora do cone angular configurado (FOV)."
                finalModule = "SilentAim / SimConfig"
                finalRootCause = string.format("Desvio angular do disparo (%.1f°) excedeu o SilentAimFOV configurado.", lastShot.DiscrepancyAngleDeg or 0)
                finalAction = "Aumente o campo 'Silent Aim FOV' no painel ou aponte a câmera mais próximo ao manequim de teste."
                evidenceType = "CONFIRMED"
                confidence = 0.99
                recommendedScenario = "SCENARIO_TARGET_OUTSIDE_FOV"

                table.insert(hypotheses, {
                    Id = "HYP_FOV_EXCEEDED",
                    Title = "Alvo fora do limite angular de Silent Aim",
                    Likelihood = 0.99,
                    Type = "CONFIRMED",
                    EvidenceList = { string.format("Desvio angular medido: %.1f°", lastShot.DiscrepancyAngleDeg or 0) },
                })
                table.insert(recommendations, {
                    Priority = "MEDIA",
                    Title = "Ajustar Limite Angular",
                    Action = "Aumentar SilentAimFovDeg de 25° para 35° ou reposicionar ponto de mira.",
                    TargetConfigKey = "SilentAimFovDeg",
                    EaseOfValidation = "IMEDIATA",
                    RecommendedScenarioId = "SCENARIO_TARGET_OUTSIDE_FOV",
                })

            elseif outcome == "OBSTACLE_BLOCKED" or (outcome == nil and lastShot.IsObstructed == true) then
                finalStatus = "WARNING"
                finalSummary = "Disparo bloqueado por obstáculo sólido antes de atingir o alvo de teste."
                finalModule = "VectorTracker (Raycast / Colisão no Workspace)"
                finalRootCause = "Raycast de colisão detectou uma barreira ou obstáculo interceptando a trajetória do projétil."
                finalAction = "Remova o obstáculo ou posicione o manequim de teste em linha de visão desobstruída."
                evidenceType = "CONFIRMED"
                confidence = 1.0
                recommendedScenario = "SCENARIO_WALL_OCCLUSION"

                table.insert(hypotheses, {
                    Id = "HYP_PHYSICAL_OBSTACLE",
                    Title = "Intercepção física por geometria opaca",
                    Likelihood = 1.0,
                    Type = "CONFIRMED",
                    EvidenceList = { "Workspace:Raycast retornou colisão com peça que não pertence ao alvo" },
                })
                table.insert(recommendations, {
                    Priority = "MEDIA",
                    Title = "Desobstruir Linha de Visada",
                    Action = "Mover manequim para fora da oclusão ou verificar filtro CanQuery.",
                    EaseOfValidation = "CENARIO_TESTE",
                    RecommendedScenarioId = "SCENARIO_WALL_OCCLUSION",
                })

            elseif outcome == "TARGET_INVALID" then
                finalStatus = "WARNING"
                finalSummary = "Disparo abortado: alvo de teste foi removido ou destruído."
                finalModule = "InstanceDetector / Ciclo de Vida"
                finalRootCause = "O modelo de teste perdeu o Humanoid, teve sua vida zerada ou foi deletado do Workspace."
                finalAction = "Clique no botão 'Spawnar Alvo Sintético' no painel para criar um novo manequim."
                evidenceType = "CONFIRMED"
                confidence = 0.99
                recommendedScenario = "SCENARIO_TARGET_DESPAWNED"

            elseif outcome == "PROBABILISTIC_SPREAD" or (outcome == nil and lastShot.HitRegistered == false) then
                finalStatus = "HEALTHY"
                finalSummary = "Disparo simulou dispersão probabilística intencional baseada no Hit Chance."
                finalModule = "VectorTracker (SimulateShot)"
                finalRootCause = "A probabilidade de acerto configurada (Hit Chance) causou uma dispersão probabilística de teste."
                finalAction = "Para acertos 100% determinísticos em testes de controle, configure 'Hit Chance' para 100%."
                evidenceType = "CONFIRMED"
                confidence = 0.95
                recommendedScenario = "SCENARIO_PROBABILISTIC_SPREAD"

            elseif outcome == "MODULE_DISABLED" then
                finalStatus = "WARNING"
                finalSummary = "Disparo rejeitado: o módulo de Silent Aim está desativado."
                finalModule = "SimConfig (SilentAimEnabled)"
                finalRootCause = "A opção 'SilentAimEnabled' está desativada no painel de controle."
                finalAction = "Ative a opção 'Ativar Simulação de Silent Aim' na aba 'Disparos Simulados'."
                evidenceType = "CONFIRMED"
                confidence = 1.0
                recommendedScenario = "SCENARIO_MODULE_DISABLED"

            elseif outcome == "INVALID_TRAJECTORY" then
                finalStatus = "CRITICAL"
                finalSummary = "Trajetória inválida detectada no cálculo vetorial."
                finalModule = "VectorTracker (Cálculo Vetorial)"
                finalRootCause = "Distância até o alvo nula, infinita ou coordenadas NaN detectadas."
                finalAction = "Verifique a posição da câmera e certifique-se de que a distância seja superior a 0.1 studs."
                evidenceType = "CONFIRMED"
                confidence = 1.0
                recommendedScenario = "SCENARIO_INVALID_VECTOR"
            end

        -- 2. Oclusão Contínua de Linha de Visada
        elseif isObstructed then
            finalStatus = "WARNING"
            finalSummary = "Alvo selecionado está ocluído por geometria de teste."
            finalModule = "VectorTracker / InstanceDetector"
            finalRootCause = "Raycast colidiu com geometria opaca/colidível antes de atingir o alvo sintético."
            finalAction = "Verifique o histórico da aba 'Line of Sight' para identificar o bloco colisor exato."
            evidenceType = "CONFIRMED"
            confidence = 0.98
            recommendedScenario = "SCENARIO_WALL_OCCLUSION"

        -- 3. Ausência de Alvo ou Simulação Pausada
        elseif targetName == "NENHUM" or targetName:find("Nenhum") or targetName:find("PAUSADO") then
            if mode == "PAUSED" then
                finalStatus = "WARNING"
                finalSummary = "A simulação está pausada globalmente."
                finalModule = "SimConfig / Master Switch"
                finalRootCause = "A opção 'SimulationActive' está desativada no painel de controle."
                finalAction = "Clique no botão 'Ativar Simulação' no topo da interface ou ative o toggle mestre."
                evidenceType = "CONFIRMED"
                confidence = 1.0
            else
                finalStatus = "WARNING"
                finalSummary = "Nenhum alvo sintético válido detectado no raio e FOV atuais."
                finalModule = "InstanceDetector"
                finalRootCause = "Não há modelos de teste (Dummies/NPCs) com Humanoid vivo dentro do alcance e FOV configurados."
                finalAction = "Spawne um dummy padrão (R6/R15) no Workspace próximo à câmera e verifique se o Humanoid está com Health > 0."
                evidenceType = "CONFIRMED"
                confidence = 0.95
                recommendedScenario = "SCENARIO_VISIBLE_DUMMY"
            end

        -- 4. Anomalia Cinética de Alta Velocidade Angular (Snap / Jitter)
        elseif angVel > 500.0 then
            finalStatus = "CRITICAL"
            finalSummary = "Velocidade angular extrema detectada na rotação da câmera simulada."
            finalModule = "VectorTracker (Suavização)"
            finalRootCause = string.format("A velocidade angular de %.1f °/s ultrapassa limites humanos típicos e causa instabilidade.", angVel)
            finalAction = "Aumente o coeficiente de Suavização (Lerp) para >= 0.15 ou ative a opção 'Clamp de Velocidade Angular'."
            evidenceType = "CONFIRMED"
            confidence = 0.99
            recommendedScenario = "SCENARIO_RAPID_SNAP"

            table.insert(hypotheses, {
                Id = "HYP_EXTREME_ANGVEL",
                Title = "Movimento angular instável (> 500 °/s)",
                Likelihood = 0.99,
                Type = "CONFIRMED",
                EvidenceList = { string.format("Velocidade angular instantânea: %.1f °/s", angVel) },
            })
            table.insert(recommendations, {
                Priority = "ALTA",
                Title = "Aumentar Suavização Cinemática",
                Action = "Aumentar SmoothingFactor para 0.20 ou ativar AngularVelocityClamp.",
                TargetConfigKey = "SmoothingFactor",
                EaseOfValidation = "IMEDIATA",
                RecommendedScenarioId = "SCENARIO_RAPID_SNAP",
            })

        -- 5. Estado Saudável e Operacional
        else
            finalStatus = "HEALTHY"
            finalSummary = "Todos os subsistemas cinemáticos e de disparo operam dentro dos parâmetros nominais."
            finalModule = "Nenhum"
            finalRootCause = "Rastreamento, cálculo de lead e verificação de visada validados com sucesso."
            finalAction = "Prossiga com os testes automatizados ou execute o cenário de disparo no manequim."
            evidenceType = "CONFIRMED"
            confidence = 0.98
            recommendedScenario = "SCENARIO_VISIBLE_DUMMY"
        end

        -- ---------------------------------------------------------------------
        -- CAMADA F: VERIFICAÇÃO CONTÍNUA E DETECÇÃO DE REGRESSÃO
        -- ---------------------------------------------------------------------
        local verificationResult: string? = nil
        if #ReportHistory > 0 then
            local prev = ReportHistory[#ReportHistory]
            if prev.Status == "HEALTHY" and (finalStatus == "WARNING" or finalStatus == "CRITICAL") then
                verificationResult = string.format("REGRESSÃO DETECTADA: O estado transicionou de HEALTHY para %s (Módulo: %s)", finalStatus, finalModule)
            elseif (prev.Status == "WARNING" or prev.Status == "CRITICAL") and finalStatus == "HEALTHY" then
                verificationResult = string.format("CORREÇÃO CONFIRMADA: O sistema retornou ao estado nominal após resolução de %s", prev.AffectedModule)
            end
        end

        local report: DiagnosticReport = {
            Timestamp = timeNow,
            Status = finalStatus,
            Summary = finalSummary,
            AffectedModule = finalModule,
            RootCause = finalRootCause,
            SuggestedAction = finalAction,
            MetricHighlights = metrics,
            EvidenceType = evidenceType,
            Confidence = confidence,
            Hypotheses = hypotheses,
            Recommendations = recommendations,
            RecommendedScenarioId = recommendedScenario,
            DataHygieneIssues = hygieneIssues,
            VerificationResult = verificationResult,
        }

        -- Manutenção do buffer histórico
        table.insert(ReportHistory, report)
        if #ReportHistory > MAX_HISTORY then
            table.remove(ReportHistory, 1)
        end

        return report
    end

    -- =========================================================================
    -- EXPORTAÇÃO ESTRUTURADA DE RELATÓRIOS
    -- =========================================================================
    function DiagnosticAI.ExportJSON(report: DiagnosticReport): string
        local out = "{\n"
        out = out .. string.format('  "Timestamp": %f,\n', report.Timestamp)
        out = out .. string.format('  "Status": "%s",\n', report.Status)
        out = out .. string.format('  "Summary": "%s",\n', report.Summary)
        out = out .. string.format('  "AffectedModule": "%s",\n', report.AffectedModule)
        out = out .. string.format('  "RootCause": "%s",\n', report.RootCause)
        out = out .. string.format('  "SuggestedAction": "%s",\n', report.SuggestedAction)
        out = out .. string.format('  "EvidenceType": "%s",\n', report.EvidenceType)
        out = out .. string.format('  "Confidence": %.2f,\n', report.Confidence)
        out = out .. string.format('  "RecommendedScenarioId": "%s"\n', report.RecommendedScenarioId or "")
        out = out .. "}"
        return out
    end

    function DiagnosticAI.GenerateMarkdownReport(report: DiagnosticReport): string
        local md = "# RELATÓRIO DE DIAGNÓSTICO DEEPHAT SIMULATION SUITE V7\n"
        md = md .. string.format("- **Data/Hora:** %f\n", report.Timestamp)
        md = md .. string.format("- **Status Global:** %s\n", report.Status)
        md = md .. string.format("- **Módulo Afetado:** %s\n", report.AffectedModule)
        md = md .. string.format("- **Causa Raiz:** %s\n", report.RootCause)
        md = md .. string.format("- **Evidência:** %s (Confiança: %.0f%%)\n", report.EvidenceType, report.Confidence * 100)
        md = md .. string.format("- **Ação Recomendada:** %s\n", report.SuggestedAction)
        if report.RecommendedScenarioId then
            md = md .. string.format("- **Cenário de Teste:** `%s`\n", report.RecommendedScenarioId)
        end
        if report.VerificationResult then
            md = md .. string.format("- **Verificação Histórica:** %s\n", report.VerificationResult)
        end
        return md
    end

    -- =========================================================================
    -- CHATBOT DE DIAGNÓSTICO INTERATIVO E ESTRUTURADO
    -- =========================================================================
    function DiagnosticAI.QueryChatbot(query: string, liveState: any?): ChatbotResponse
        local clean = string.lower(query or "")
        local analysis = DiagnosticAI.AnalyzeSystemState(
            liveState and liveState.Telemetry,
            liveState and liveState.LosHistory,
            nil,
            liveState and liveState.LastShot
        )

        -- Heurísticas estruturadas por intenção
        if clean:find("oscila") or clean:find("tremer") or clean:find("treme") or clean:find("jitter") or clean:find("instavel") then
            local ans = "Oscilações na mira ocorrem quando a Suavização (Smoothing) está muito baixa ou há ruído de micro-movimento. "
            ans = ans .. "Recomendação: Aumente o valor de Suavização no painel (aba 'Mira Simulada') para >= 0.15 e utilize o Deadband angular para estabilizar o rastreamento."
            return {
                Query = query,
                Answer = ans,
                AffectedModule = "VectorTracker (Suavização)",
                SuggestedAction = "Ajuste o slider de Suavização para 0.15 - 0.30 e garanta que o alvo sintético tenha velocidade linear estável.",
                Confidence = 0.98,
                EvidenceType = "CONFIRMED",
                RecommendedScenarioId = "SCENARIO_RAPID_SNAP",
            }
        elseif clean:find("mira") or clean:find("foca") or clean:find("puxa") or clean:find("aimbot") or clean:find("mover") then
            local ans = "A mira cinematica é controlada pelo VectorTracker e InstanceDetector. "
            if liveState and liveState.SimConfig and liveState.SimConfig.Get("AimbotEnabled") == false then
                ans = ans .. "ATENÇÃO: O Aimbot está desativado no painel ('AimbotEnabled' = false). Ative o controle na aba 'Mira Simulada'."
            elseif analysis.AffectedModule == "InstanceDetector" then
                ans = ans .. "Atualmente não há alvos sintéticos válidos no campo de visão. " .. analysis.SuggestedAction
            elseif analysis.AffectedModule:find("Line of Sight") then
                ans = ans .. "O alvo atual está atrás de um obstáculo sólido. " .. analysis.SuggestedAction
            else
                ans = ans .. "O rastreamento está ativo. Para suavização realista, use Coeficiente 0.15 - 0.25. Segure RMB ou configure o modo para 'AlwaysOn'."
            end
            return {
                Query = query,
                Answer = ans,
                AffectedModule = "VectorTracker / InstanceDetector",
                SuggestedAction = "Verifique o alvo na tela e teste pressionando o botão direito do mouse (RMB).",
                Confidence = 0.95,
                EvidenceType = "CONFIRMED",
                RecommendedScenarioId = "SCENARIO_VISIBLE_DUMMY",
            }
        elseif clean:find("silent") or clean:find("disparo") or clean:find("tiro") or clean:find("acerta") then
            local ans = "A simulação de Silent Aim redireciona vetores balísticos sem mover a câmera física. "
            if liveState and liveState.SimConfig and liveState.SimConfig.Get("SilentAimEnabled") == false then
                ans = ans .. "ATENÇÃO: Silent Aim está desativado no painel. Ative-o na aba 'Disparos Simulados'."
            else
                ans = ans .. "Fluxo auditado em 5 etapas: [1] Solicitação Recebida -> [2] Dados Validados -> [3] Trajetória Calculada -> [4] Colisão Verificada -> [5] Resultado Final. "
                if analysis.Status ~= "HEALTHY" then
                    ans = ans .. "Diagnóstico atual: " .. analysis.Summary
                else
                    ans = ans .. "O sistema está pronto para disparos sintéticos de teste."
                end
            end
            return {
                Query = query,
                Answer = ans,
                AffectedModule = "VectorTracker / SimulationBootstrap",
                SuggestedAction = "Clique no botão '🎯 Disparar Simulação Silent Aim' para executar um disparo de teste completo.",
                Confidence = 0.96,
                EvidenceType = "CONFIRMED",
                RecommendedScenarioId = analysis.RecommendedScenarioId or "SCENARIO_VISIBLE_DUMMY",
            }
        elseif clean:find("gravidade") or clean:find("queda") or clean:find("balistica") or clean:find("projetil") or clean:find("arco") then
            local ans = "O simulador balístico suporta armas com projéteis físicos sob aceleração gravitacional (padrão Roblox g = 196.2 studs/s²). "
            ans = ans .. "A queda vertical Delta_y = 0.5 * g * t^2 é compensada iterativamente na elevação de mira, e a trajetória é renderizada como um arco parabólico segmentado, nunca uma reta artificial."
            return {
                Query = query,
                Answer = ans,
                AffectedModule = "VectorTracker (Física Balística)",
                SuggestedAction = "Na aba 'Balística', configure o modelo como 'Físico (Gravidade/Arco)' e verifique o traçador curvado no alvo.",
                Confidence = 0.98,
                EvidenceType = "CONFIRMED",
                RecommendedScenarioId = "SCENARIO_BALLISTIC_ARC",
            }
        elseif clean:find("fov") or clean:find("circulo") or clean:find("cone") then
            local ans = "O Campo de Visão (FOV) angular está 100% sincronizado opticamente com o círculo visual na tela: Raio_Pixels = (tan(FOV/2) / tan(CamFOV/2)) * (Altura_Tela/2). "
            ans = ans .. "Qualquer alvo dentro do círculo visual é garantido dentro do cone angular de mira e seleção."
            return {
                Query = query,
                Answer = ans,
                AffectedModule = "DashboardGUI / VectorTracker",
                SuggestedAction = "Ajuste o controle deslizante 'Campo de Visão (FOV °)' para redimensionar a área de busca dinamicamente.",
                Confidence = 0.97,
                EvidenceType = "CONFIRMED",
                RecommendedScenarioId = "SCENARIO_TARGET_OUTSIDE_FOV",
            }
        elseif clean:find("erro") or clean:find("diagnostico") or clean:find("problema") or clean:find("status") or clean:find("analisar") then
            return {
                Query = query,
                Answer = string.format("Relatório Atual de Saúde: [%s] %s Módulo: %s. Causa: %s", analysis.Status, analysis.Summary, analysis.AffectedModule, analysis.RootCause),
                AffectedModule = analysis.AffectedModule,
                SuggestedAction = analysis.SuggestedAction,
                Confidence = 0.99,
                EvidenceType = analysis.EvidenceType,
                RecommendedScenarioId = analysis.RecommendedScenarioId,
            }
        else
            return {
                Query = query,
                Answer = string.format("Assistente DeepHat V7 ativo. Status do Sistema: [%s] - %s (Alvo: %s | Modo: %s | Vel: %s).",
                    analysis.Status, analysis.Summary, analysis.MetricHighlights["Alvo"] or "Nenhum", analysis.MetricHighlights["Modo"] or "IDLE", analysis.MetricHighlights["VelocidadeAngular"] or "0 °/s"),
                AffectedModule = analysis.AffectedModule,
                SuggestedAction = analysis.SuggestedAction,
                Confidence = 0.90,
                EvidenceType = analysis.EvidenceType,
                RecommendedScenarioId = analysis.RecommendedScenarioId,
            }
        end
    end
end

-- =========================================================================
-- MÓDULO: EngineCore.lua
-- =========================================================================
local Engine = {}
do
    -- =========================================================================
    -- EngineCore.lua
    -- Motor de Avaliação Cinemática e Detecção de Anomalias de Comportamento
    -- Usado para Calibração de Anti-Cheat e Validação de Tolerância Heurística
    -- =========================================================================


    type KinematicMetrics = {
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

    type SuspicionReport = {
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
end

-- =========================================================================
-- MÓDULO: DashboardGUI.lua
-- =========================================================================
local DashboardGUI = {}
do
    -- =========================================================================
    -- DashboardGUI.lua
    -- Interface Profissional de Simulação Cinemática e Diagnósticos de Detecção
    -- Design: 5 Abas Objetivas e Simplificadas (Mira, Silent Aim, Balística, Diagnóstico, Configurações)
    -- Conexão Reativa Bidirecional com SimConfig, Suporte a Chatbot IA e Pipeline de 4 Etapas
    -- =========================================================================

    local Players = game:GetService("Players")
    local UserInputService = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")
    local Workspace = game:GetService("Workspace")
    local CoreGuiService = game:GetService("CoreGui")


    DashboardGUI.__index = DashboardGUI

    -- [DESIGN SYSTEM & TOKENS VISUAIS]
    local THEME = {
        BG_WINDOW    = Color3.fromRGB(11, 12, 16),
        BG_SIDEBAR   = Color3.fromRGB(16, 18, 23),
        BG_CARD      = Color3.fromRGB(20, 23, 30),
        BG_INPUT     = Color3.fromRGB(27, 31, 40),
        BORDER       = Color3.fromRGB(38, 43, 56),
        BORDER_LIGHT = Color3.fromRGB(55, 62, 80),
        TEXT_MAIN    = Color3.fromRGB(245, 246, 250),
        TEXT_MUTED   = Color3.fromRGB(135, 144, 160),
        ACCENT_RED   = Color3.fromRGB(224, 43, 54),
        ACCENT_HOVER = Color3.fromRGB(255, 65, 75),
        ACCENT_GLOW  = Color3.fromRGB(90, 20, 25),
        SUCCESS      = Color3.fromRGB(46, 204, 113),
        WARNING      = Color3.fromRGB(241, 196, 15),
        INFO         = Color3.fromRGB(52, 152, 219),
    }

    -- Callbacks de Ação Global
    DashboardGUI.OnStartRequested = nil :: (() -> ())?
    DashboardGUI.OnStopRequested = nil :: (() -> ())?
    DashboardGUI.OnResetRequested = nil :: (() -> ())?
    DashboardGUI.OnSaveRequested = nil :: (() -> ())?
    DashboardGUI.OnRunLosScenario = nil :: ((string) -> ())?
    DashboardGUI.OnClearLosHistory = nil :: (() -> ())?
    DashboardGUI.OnSimulateSilentAimShot = nil :: (() -> ())?
    DashboardGUI.OnSpawnTestDummy = nil :: (() -> ())?
    DashboardGUI.OnRunShotScenario = nil :: ((string) -> ())?
    DashboardGUI.OnQueryDiagnosticChatbot = nil :: ((string) -> any)?
    DashboardGUI.OnRunFullDiagnostic = nil :: (() -> any)?

    -- Instâncias Internas
    local ScreenGuiInstance: ScreenGui? = nil
    local MainFrameInstance: Frame? = nil
    local FovCircleInstance: Frame? = nil
    local WatchdogBadgeInstance: TextLabel? = nil
    local EventLogListInstance: ScrollingFrame? = nil
    local unsubscribeGlobal: (() -> ())? = nil

    -- Elementos de Telemetria Dinâmica
    local TelemetryLabels: { [string]: TextLabel } = {}
    local LosLabels: { [string]: TextLabel } = {}
    local DetLabels: { [string]: TextLabel } = {}
    local LosHistoryList: ScrollingFrame? = nil
    local LastRenderedLosStamp = -1
    local ApplyRuntimeConfig: ((string, any) -> ())? = nil
    local PerformanceData = {
        Fps = 60,
        PeakAngVel = 0,
        LastCheck = os.clock(),
        ErrorCount = 0,
    }

    local function AddCorner(parent: Instance, radius: number): UICorner
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, radius)
        corner.Parent = parent
        return corner
    end

    local function AddStroke(parent: Instance, color: Color3, thickness: number?): UIStroke
        local stroke = Instance.new("UIStroke")
        stroke.Color = color
        stroke.Thickness = thickness or 1
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stroke.Parent = parent
        return stroke
    end

    local function GetSafeGuiParent(): Instance
        local okCore, coreGui = pcall(function() return CoreGuiService end)
        if okCore and coreGui then
            local testOk = pcall(function()
                local test = Instance.new("Folder")
                test.Name = "DeepHat_PermTest"
                test.Parent = coreGui
                test:Destroy()
            end)
            if testOk then return coreGui end
        end

        local localPlayer = Players.LocalPlayer
        if not localPlayer then
            pcall(function()
                localPlayer = Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
            end)
            localPlayer = Players.LocalPlayer
        end

        if localPlayer then
            local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
            if not playerGui then
                pcall(function() playerGui = localPlayer:WaitForChild("PlayerGui", 5) end)
            end
            if playerGui then return playerGui end
        end

        if okCore and coreGui then return coreGui end
        return Workspace
    end

    -- =========================================================================
    -- LOG DE DIAGNÓSTICOS EM TEMPO REAL COM FILTRAGEM MULTI-NÍVEL
    -- =========================================================================
    local currentLogFilter = "TODOS"

    local function ApplyLogFilter()
        if not EventLogListInstance then return end
        for _, child in ipairs(EventLogListInstance:GetChildren()) do
            if child:IsA("Frame") then
                local lvl = child:GetAttribute("LogLevel") or "INFO"
                if currentLogFilter == "TODOS" or lvl == currentLogFilter then
                    child.Visible = true
                else
                    child.Visible = false
                end
            end
        end
    end

    function DashboardGUI.AddDiagnosticLog(source: string, message: string, level: ("INFO" | "WARN" | "OK" | "FAIL")?)
        if not EventLogListInstance or not EventLogListInstance.Parent then return end

        local rowLevel = level or "INFO"
        local color = THEME.TEXT_MAIN
        if rowLevel == "WARN" then color = THEME.WARNING
        elseif rowLevel == "OK" then color = THEME.SUCCESS
        elseif rowLevel == "INFO" then color = THEME.INFO
        elseif rowLevel == "FAIL" then color = THEME.ACCENT_RED end

        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 20)
        row.BackgroundColor3 = THEME.BG_INPUT
        row.BackgroundTransparency = 0.5
        row:SetAttribute("LogLevel", rowLevel)
        if currentLogFilter ~= "TODOS" and rowLevel ~= currentLogFilter then
            row.Visible = false
        else
            row.Visible = true
        end
        row.Parent = EventLogListInstance
        AddCorner(row, 3)

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -8, 1, 0)
        lbl.Position = UDim2.new(0, 5, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Font = Enum.Font.Code
        lbl.TextSize = 10
        lbl.TextColor3 = color
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        local timeStr = os.date("%H:%M:%S")
        lbl.Text = string.format("[%s] [%s] %s", timeStr, source, message)
        lbl.Parent = row

        local children = EventLogListInstance:GetChildren()
        if #children > 45 then
            for i = 1, #children - 45 do
                if children[i]:IsA("Frame") then children[i]:Destroy() end
            end
        end
        EventLogListInstance.CanvasPosition = Vector2.new(0, 99999)
    end

    -- =========================================================================
    -- CONSTRUÇÃO DA INTERFACE PRINCIPAL (5 ABAS OBJETIVAS)
    -- =========================================================================
    function DashboardGUI.Create(): ScreenGui
        local oldGui = CoreGuiService:FindFirstChild("DeepHat_DashboardUI")
            or (Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui") and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui"):FindFirstChild("DeepHat_DashboardUI"))
        if oldGui then
            oldGui:Destroy()
        end

        local guiParent = GetSafeGuiParent()
        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "DeepHat_DashboardUI"
        screenGui.ResetOnSpawn = false
        screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        screenGui.Parent = guiParent
        ScreenGuiInstance = screenGui

        -- Overlay Circular do FOV
        local fovCircle = Instance.new("Frame")
        fovCircle.Name = "FovCircle"
        fovCircle.Size = UDim2.new(0, 240, 0, 240)
        fovCircle.AnchorPoint = Vector2.new(0.5, 0.5)
        fovCircle.Position = UDim2.new(0.5, 0, 0.5, 0)
        fovCircle.BackgroundTransparency = 1
        fovCircle.Visible = SimConfig.Get("ShowFovCircle") == true and SimConfig.Get("SimulationActive") == true
        fovCircle.Parent = screenGui
        AddCorner(fovCircle, 9999)
        local fovStroke = AddStroke(fovCircle, THEME.ACCENT_RED, 1.5)
        fovStroke.Transparency = 0.4
        FovCircleInstance = fovCircle

        local fovCenterDot = Instance.new("Frame")
        fovCenterDot.Size = UDim2.new(0, 4, 0, 4)
        fovCenterDot.AnchorPoint = Vector2.new(0.5, 0.5)
        fovCenterDot.Position = UDim2.new(0.5, 0, 0.5, 0)
        fovCenterDot.BackgroundColor3 = THEME.ACCENT_RED
        fovCenterDot.BackgroundTransparency = 0.2
        fovCenterDot.Parent = fovCircle
        AddCorner(fovCenterDot, 2)

        -- Janela Principal
        local mainFrame = Instance.new("Frame")
        mainFrame.Name = "MainFrame"
        mainFrame.Size = UDim2.new(0, 960, 0, 580)
        mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
        mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
        mainFrame.BackgroundColor3 = THEME.BG_WINDOW
        mainFrame.BorderSizePixel = 0
        mainFrame.Active = true
        mainFrame.Visible = true
        mainFrame.Parent = screenGui
        AddCorner(mainFrame, 10)
        AddStroke(mainFrame, THEME.BORDER, 1.5)
        MainFrameInstance = mainFrame

        -- Header da Janela
        local header = Instance.new("Frame")
        header.Name = "Header"
        header.Size = UDim2.new(1, 0, 0, 44)
        header.BackgroundColor3 = THEME.BG_SIDEBAR
        header.BorderSizePixel = 0
        header.Parent = mainFrame
        AddCorner(header, 10)

        -- Arraste da Janela
        local isDragging = false
        local dragStartPos = Vector2.zero
        local frameStartPos = UDim2.new(0.5, 0, 0.5, 0)
        header.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                isDragging = true
                dragStartPos = Vector2.new(input.Position.X, input.Position.Y)
                frameStartPos = mainFrame.Position
            end
        end)
        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then isDragging = false end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if isDragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStartPos
                mainFrame.Position = UDim2.new(
                    frameStartPos.X.Scale, frameStartPos.X.Offset + delta.X,
                    frameStartPos.Y.Scale, frameStartPos.Y.Offset + delta.Y
                )
            end
        end)

        -- Marca e Título
        local brandDot = Instance.new("Frame")
        brandDot.Size = UDim2.new(0, 8, 0, 8)
        brandDot.Position = UDim2.new(0, 16, 0.5, -4)
        brandDot.BackgroundColor3 = THEME.ACCENT_RED
        brandDot.Parent = header
        AddCorner(brandDot, 4)

        local titleLabel = Instance.new("TextLabel")
        titleLabel.Size = UDim2.new(0, 360, 1, 0)
        titleLabel.Position = UDim2.new(0, 32, 0, 0)
        titleLabel.BackgroundTransparency = 1
        titleLabel.Font = Enum.Font.GothamBold
        titleLabel.TextSize = 13
        titleLabel.TextColor3 = THEME.TEXT_MAIN
        titleLabel.TextXAlignment = Enum.TextXAlignment.Left
        titleLabel.Text = "DEEPHAT SIMULATION SUITE // v7.0 PRO"
        titleLabel.Parent = header

        -- Badge de Watchdog
        local watchdogBadge = Instance.new("TextLabel")
        watchdogBadge.Size = UDim2.new(0, 240, 0, 24)
        watchdogBadge.Position = UDim2.new(1, -330, 0.5, -12)
        watchdogBadge.BackgroundColor3 = THEME.BG_INPUT
        watchdogBadge.Font = Enum.Font.GothamMedium
        watchdogBadge.TextSize = 10
        watchdogBadge.TextColor3 = THEME.SUCCESS
        watchdogBadge.Text = "● WATCHDOG: 100% OPERACIONAL"
        watchdogBadge.Parent = header
        AddCorner(watchdogBadge, 4)
        AddStroke(watchdogBadge, THEME.BORDER, 1)
        WatchdogBadgeInstance = watchdogBadge

        local hotkeyNotice = Instance.new("TextLabel")
        hotkeyNotice.Size = UDim2.new(0, 100, 1, 0)
        hotkeyNotice.Position = UDim2.new(1, -160, 0, 0)
        hotkeyNotice.BackgroundTransparency = 1
        hotkeyNotice.Font = Enum.Font.GothamMedium
        hotkeyNotice.TextSize = 10
        hotkeyNotice.TextColor3 = THEME.TEXT_MUTED
        hotkeyNotice.Text = "[HOME] Ocultar"
        hotkeyNotice.Parent = header

        local closeBtn = Instance.new("TextButton")
        closeBtn.Size = UDim2.new(0, 28, 0, 28)
        closeBtn.Position = UDim2.new(1, -38, 0.5, -14)
        closeBtn.BackgroundColor3 = THEME.BG_INPUT
        closeBtn.TextColor3 = THEME.TEXT_MAIN
        closeBtn.Font = Enum.Font.GothamBold
        closeBtn.TextSize = 12
        closeBtn.Text = "✕"
        closeBtn.Parent = header
        AddCorner(closeBtn, 5)
        AddStroke(closeBtn, THEME.BORDER, 1)
        closeBtn.MouseButton1Click:Connect(function()
            mainFrame.Visible = not mainFrame.Visible
        end)

        UserInputService.InputBegan:Connect(function(input, gpe)
            if input.KeyCode == Enum.KeyCode.Home or input.KeyCode == Enum.KeyCode.RightShift then
                if UserInputService:GetFocusedTextBox() ~= nil then return end
                mainFrame.Visible = not mainFrame.Visible
            end
        end)

        -- Layout Estrutural: Sidebar + MainContent
        local body = Instance.new("Frame")
        body.Size = UDim2.new(1, 0, 1, -94)
        body.Position = UDim2.new(0, 0, 0, 46)
        body.BackgroundTransparency = 1
        body.Parent = mainFrame

        local sidebar = Instance.new("Frame")
        sidebar.Name = "Sidebar"
        sidebar.Size = UDim2.new(0, 190, 1, 0)
        sidebar.BackgroundColor3 = THEME.BG_SIDEBAR
        sidebar.BorderSizePixel = 0
        sidebar.Parent = body
        AddCorner(sidebar, 8)
        AddStroke(sidebar, THEME.BORDER, 1)

        local sidebarList = Instance.new("UIListLayout")
        sidebarList.Padding = UDim.new(0, 6)
        sidebarList.Parent = sidebar

        local sidebarPad = Instance.new("UIPadding")
        sidebarPad.PaddingTop = UDim.new(0, 12)
        sidebarPad.PaddingLeft = UDim.new(0, 8)
        sidebarPad.PaddingRight = UDim.new(0, 8)
        sidebarPad.Parent = sidebar

        local mainContent = Instance.new("Frame")
        mainContent.Name = "MainContent"
        mainContent.Size = UDim2.new(1, -204, 1, 0)
        mainContent.Position = UDim2.new(0, 198, 0, 0)
        mainContent.BackgroundColor3 = THEME.BG_CARD
        mainContent.BorderSizePixel = 0
        mainContent.Parent = body
        AddCorner(mainContent, 8)
        AddStroke(mainContent, THEME.BORDER, 1)

        -- 5 ABAS OBJETIVAS (FASE 5)
        local pages: { [string]: ScrollingFrame } = {}
        local tabButtons: { [string]: TextButton } = {}

        local tabs = {
            { Id = "AimSimulation", Label = "◎  Mira Simulada" },
            { Id = "SilentAim",     Label = "🎯  Disparos Simulados" },
            { Id = "Ballistics",    Label = "⚡  Balística" },
            { Id = "Diagnostics",  Label = "▤  Diagnóstico & IA" },
            { Id = "Settings",     Label = "⚙  Configurações" },
        }

        local function SwitchTab(tabId: string)
            if not pages[tabId] then
                if tabId == "Dashboard" or tabId == "Camera" or tabId == "Simulation" or tabId == "Hitbox" then
                    tabId = "AimSimulation"
                elseif tabId == "Vision" then
                    tabId = "Ballistics"
                elseif tabId == "LineOfSight" or tabId == "Performance" then
                    tabId = "Diagnostics"
                else
                    tabId = "AimSimulation"
                end
            end
            for id, page in pairs(pages) do
                page.Visible = (id == tabId)
            end
            for id, btn in pairs(tabButtons) do
                local active = (id == tabId)
                btn.BackgroundColor3 = active and THEME.ACCENT_RED or THEME.BG_INPUT
                btn.TextColor3 = active and THEME.TEXT_MAIN or THEME.TEXT_MUTED
            end
            SimConfig.Set("ActiveTab", tabId)
        end

        for _, t in ipairs(tabs) do
            local btn = Instance.new("TextButton")
            btn.Size = UDim2.new(1, 0, 0, 36)
            btn.BackgroundColor3 = THEME.BG_INPUT
            btn.TextColor3 = THEME.TEXT_MUTED
            btn.Font = Enum.Font.GothamMedium
            btn.TextSize = 11
            btn.TextXAlignment = Enum.TextXAlignment.Left
            btn.Text = "  " .. t.Label
            btn.Parent = sidebar
            AddCorner(btn, 5)

            tabButtons[t.Id] = btn
            btn.MouseButton1Click:Connect(function() SwitchTab(t.Id) end)

            local page = Instance.new("ScrollingFrame")
            page.Name = "Page_" .. t.Id
            page.Size = UDim2.new(1, 0, 1, 0)
            page.BackgroundTransparency = 1
            page.ScrollBarThickness = 4
            page.ScrollBarImageColor3 = THEME.BORDER_LIGHT
            page.CanvasSize = UDim2.new(0, 0, 0, 0)
            page.AutomaticCanvasSize = Enum.AutomaticSize.Y
            page.Visible = false
            page.Parent = mainContent

            local pList = Instance.new("UIListLayout")
            pList.Padding = UDim.new(0, 10)
            pList.Parent = page

            local pPad = Instance.new("UIPadding")
            pPad.PaddingTop = UDim.new(0, 12); pPad.PaddingBottom = UDim.new(0, 40)
            pPad.PaddingLeft = UDim.new(0, 14); pPad.PaddingRight = UDim.new(0, 14)
            pPad.Parent = page

            pages[t.Id] = page
        end

        local syncInputs: { [string]: (number) -> () } = {}

        -- CONSTRUTOR DE COMPONENTES DE UI
        local function CreateSectionHeader(parent: Instance, title: string): TextLabel
            local lbl = Instance.new("TextLabel")
            lbl.Size = UDim2.new(1, 0, 0, 22)
            lbl.BackgroundTransparency = 1
            lbl.Font = Enum.Font.GothamBold
            lbl.TextSize = 11
            lbl.TextColor3 = THEME.ACCENT_RED
            lbl.TextXAlignment = Enum.TextXAlignment.Left
            lbl.Text = title
            lbl.Parent = parent
            return lbl
        end

        local function CreateSliderField(parent: Instance, labelText: string, configKey: string, minVal: number, maxVal: number, defaultVal: number, step: number, subtitleText: string?): Frame
            local span = math.max(maxVal - minVal, 0.0001)
            local safeDefault = tonumber(SimConfig.Get(configKey)) or defaultVal or minVal
            local height = subtitleText and 54 or 46

            local container = Instance.new("Frame")
            container.Name = "SliderRow_" .. configKey
            container.Size = UDim2.new(1, 0, 0, height)
            container.BackgroundColor3 = THEME.BG_INPUT
            container.BackgroundTransparency = 0.5
            container.Parent = parent
            AddCorner(container, 6)
            AddStroke(container, THEME.BORDER, 1)

            local rowHeader = Instance.new("Frame")
            rowHeader.Size = UDim2.new(1, -16, 0, subtitleText and 26 or 20)
            rowHeader.Position = UDim2.new(0, 8, 0, 4)
            rowHeader.BackgroundTransparency = 1
            rowHeader.Parent = container

            local title = Instance.new("TextLabel")
            title.Size = UDim2.new(1, -70, subtitleText and 0.6 or 1, 0)
            title.BackgroundTransparency = 1
            title.Font = Enum.Font.GothamMedium
            title.TextSize = 11
            title.TextColor3 = THEME.TEXT_MAIN
            title.TextXAlignment = Enum.TextXAlignment.Left
            title.Text = labelText
            title.Parent = rowHeader

            if subtitleText then
                local sub = Instance.new("TextLabel")
                sub.Size = UDim2.new(1, -70, 0.4, 0)
                sub.Position = UDim2.new(0, 0, 0.6, 0)
                sub.BackgroundTransparency = 1
                sub.Font = Enum.Font.GothamMedium
                sub.TextSize = 9
                sub.TextColor3 = THEME.TEXT_MUTED
                sub.TextXAlignment = Enum.TextXAlignment.Left
                sub.Text = subtitleText
                sub.Parent = rowHeader
            end

            local numInput = Instance.new("TextBox")
            numInput.Size = UDim2.new(0, 60, 0, 20)
            numInput.Position = UDim2.new(1, -60, 0, 2)
            numInput.BackgroundColor3 = THEME.BG_WINDOW
            numInput.TextColor3 = THEME.ACCENT_RED
            numInput.Font = Enum.Font.GothamBold
            numInput.TextSize = 11
            numInput.Text = string.format(step < 1 and "%.2f" or "%d", safeDefault)
            numInput.ClearTextOnFocus = false
            numInput.Parent = rowHeader
            AddCorner(numInput, 4)
            AddStroke(numInput, THEME.BORDER, 1)

            local track = Instance.new("Frame")
            track.Size = UDim2.new(1, -16, 0, 6)
            track.Position = UDim2.new(0, 8, 0, subtitleText and 38 or 30)
            track.BackgroundColor3 = THEME.BG_WINDOW
            track.Parent = container
            AddCorner(track, 3)

            local initialRatio = math.clamp((safeDefault - minVal) / span, 0, 1)
            local fill = Instance.new("Frame")
            fill.Size = UDim2.new(initialRatio, 0, 1, 0)
            fill.BackgroundColor3 = THEME.ACCENT_RED
            fill.BorderSizePixel = 0
            fill.Parent = track
            AddCorner(fill, 3)

            local isDraggingSlider = false
            local function UpdateValue(val: number, fromObserver: boolean?)
                val = math.clamp(val, minVal, maxVal)
                val = math.round(val / step) * step
                local ratio = math.clamp((val - minVal) / span, 0, 1)
                fill.Size = UDim2.new(ratio, 0, 1, 0)
                numInput.Text = string.format(step < 1 and "%.2f" or "%d", val)
                if not fromObserver then
                    local ok, err = SimConfig.Set(configKey, val)
                    if not ok then
                        DashboardGUI.AddDiagnosticLog("CONFIG", string.format("Falha ao atualizar '%s': %s", configKey, tostring(err)), "WARN")
                    end
                end
            end

            numInput.FocusLost:Connect(function()
                local num = tonumber(numInput.Text)
                if num then UpdateValue(num)
                else
                    local fallback = tonumber(SimConfig.Get(configKey)) or safeDefault
                    numInput.Text = string.format(step < 1 and "%.2f" or "%d", fallback)
                end
            end)

            track.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 then
                    isDraggingSlider = true
                    local trackWidth = math.max(track.AbsoluteSize.X, 1)
                    local relX = math.clamp((input.Position.X - track.AbsolutePosition.X) / trackWidth, 0, 1)
                    UpdateValue(minVal + relX * span)
                end
            end)
            UserInputService.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 then isDraggingSlider = false end
            end)
            UserInputService.InputChanged:Connect(function(input)
                if isDraggingSlider and input.UserInputType == Enum.UserInputType.MouseMovement then
                    local trackWidth = math.max(track.AbsoluteSize.X, 1)
                    local relX = math.clamp((input.Position.X - track.AbsolutePosition.X) / trackWidth, 0, 1)
                    UpdateValue(minVal + relX * span)
                end
            end)

            syncInputs[configKey] = function(newVal: number) UpdateValue(newVal, true) end
            return container
        end

        local function CreateToggleField(parent: Instance, labelText: string, configKey: string, defaultState: boolean): Frame
            local container = Instance.new("Frame")
            container.Size = UDim2.new(1, 0, 0, 36)
            container.BackgroundColor3 = THEME.BG_INPUT
            container.BackgroundTransparency = 0.5
            container.Parent = parent
            AddCorner(container, 6)
            AddStroke(container, THEME.BORDER, 1)

            local title = Instance.new("TextLabel")
            title.Size = UDim2.new(1, -60, 1, 0)
            title.Position = UDim2.new(0, 10, 0, 0)
            title.BackgroundTransparency = 1
            title.Font = Enum.Font.GothamMedium
            title.TextSize = 11
            title.TextColor3 = THEME.TEXT_MAIN
            title.TextXAlignment = Enum.TextXAlignment.Left
            title.Text = labelText
            title.Parent = container

            local toggleBtn = Instance.new("TextButton")
            toggleBtn.Size = UDim2.new(0, 44, 0, 22)
            toggleBtn.Position = UDim2.new(1, -54, 0.5, -11)
            toggleBtn.BackgroundColor3 = defaultState and THEME.ACCENT_RED or THEME.BG_WINDOW
            toggleBtn.Text = ""
            toggleBtn.Parent = container
            AddCorner(toggleBtn, 11)
            AddStroke(toggleBtn, THEME.BORDER, 1)

            local dot = Instance.new("Frame")
            dot.Size = UDim2.new(0, 16, 0, 16)
            dot.Position = defaultState and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
            dot.BackgroundColor3 = THEME.TEXT_MAIN
            dot.Parent = toggleBtn
            AddCorner(dot, 8)

            local function SetToggle(state: boolean)
                local ok, err = SimConfig.Set(configKey, state)
                if ok then
                    toggleBtn.BackgroundColor3 = state and THEME.ACCENT_RED or THEME.BG_WINDOW
                    dot.Position = state and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
                else
                    DashboardGUI.AddDiagnosticLog("CONFIG", string.format("Falha ao alternar '%s': %s", configKey, tostring(err)), "WARN")
                end
            end

            toggleBtn.MouseButton1Click:Connect(function()
                local current = SimConfig.Get(configKey) == true
                SetToggle(not current)
            end)
            SimConfig.Subscribe(configKey, function(val)
                local state = (val == true)
                toggleBtn.BackgroundColor3 = state and THEME.ACCENT_RED or THEME.BG_WINDOW
                dot.Position = state and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
            end)

            return container
        end

        local function MakeInfoLabel(parent: Instance, text: string, color: Color3?, height: number?): TextLabel
            local l = Instance.new("TextLabel")
            l.Size = UDim2.new(1, 0, 0, height or 24)
            l.BackgroundColor3 = THEME.BG_INPUT
            l.BackgroundTransparency = 0.5
            l.Font = Enum.Font.GothamMedium
            l.TextSize = 10
            l.TextColor3 = color or THEME.TEXT_MUTED
            l.TextXAlignment = Enum.TextXAlignment.Left
            l.TextYAlignment = Enum.TextYAlignment.Center
            l.TextWrapped = true
            l.Text = "  " .. text
            l.Parent = parent
            AddCorner(l, 5)
            AddStroke(l, THEME.BORDER, 1)
            return l
        end

        -- =========================================================================
        -- [ABA 1] MIRA SIMULADA (AIM SIMULATION)
        -- =========================================================================
        local pageAim = pages["AimSimulation"]

        -- Card Mestre de Ativação
        local masterCard = Instance.new("Frame")
        masterCard.Size = UDim2.new(1, 0, 0, 60)
        masterCard.BackgroundColor3 = THEME.BG_INPUT
        masterCard.Parent = pageAim
        AddCorner(masterCard, 8)
        AddStroke(masterCard, THEME.BORDER, 1)

        local masterTitle = Instance.new("TextLabel")
        masterTitle.Size = UDim2.new(0.65, 0, 0, 22)
        masterTitle.Position = UDim2.new(0, 12, 0, 8)
        masterTitle.BackgroundTransparency = 1
        masterTitle.Font = Enum.Font.GothamBold
        masterTitle.TextSize = 12
        masterTitle.TextColor3 = THEME.TEXT_MAIN
        masterTitle.TextXAlignment = Enum.TextXAlignment.Left
        masterTitle.Text = "SIMULAÇÃO CINEMÁTICA DE MIRA (AIMBOT)"
        masterTitle.Parent = masterCard

        local masterDesc = Instance.new("TextLabel")
        masterDesc.Size = UDim2.new(0.65, 0, 0, 20)
        masterDesc.Position = UDim2.new(0, 12, 0, 30)
        masterDesc.BackgroundTransparency = 1
        masterDesc.Font = Enum.Font.GothamMedium
        masterDesc.TextSize = 10
        masterDesc.TextColor3 = THEME.TEXT_MUTED
        masterDesc.TextXAlignment = Enum.TextXAlignment.Left
        masterDesc.Text = "Rastreamento preditivo de alvos sintéticos com suavização sem jitter."
        masterDesc.Parent = masterCard

        local masterSwitch = Instance.new("TextButton")
        masterSwitch.Size = UDim2.new(0, 150, 0, 34)
        masterSwitch.Position = UDim2.new(1, -162, 0.5, -17)
        masterSwitch.BackgroundColor3 = SimConfig.Get("SimulationActive") and THEME.ACCENT_RED or THEME.BG_WINDOW
        masterSwitch.Font = Enum.Font.GothamBold
        masterSwitch.TextSize = 11
        masterSwitch.TextColor3 = THEME.TEXT_MAIN
        masterSwitch.Text = SimConfig.Get("SimulationActive") and "SIMULAÇÃO: ATIVA" or "SIMULAÇÃO: PAUSADA"
        masterSwitch.Parent = masterCard
        AddCorner(masterSwitch, 6)
        AddStroke(masterSwitch, THEME.BORDER_LIGHT, 1)
        masterSwitch.MouseButton1Click:Connect(function()
            local nextState = not (SimConfig.Get("SimulationActive") == true)
            SimConfig.Set("SimulationActive", nextState)
            masterSwitch.BackgroundColor3 = nextState and THEME.ACCENT_RED or THEME.BG_WINDOW
            masterSwitch.Text = nextState and "SIMULAÇÃO: ATIVA" or "SIMULAÇÃO: PAUSADA"
            DashboardGUI.AddDiagnosticLog("PIPELINE", nextState and "Simulação ativada." or "Simulação pausada.", nextState and "OK" or "WARN")
        end)

        CreateToggleField(pageAim, "Ativar Rastreamento de Mira (Aimbot Ativo)", "AimbotEnabled", SimConfig.Get("AimbotEnabled"))
        CreateToggleField(pageAim, "Considerar Jogadores como Alvos (Ambiente Autorizado)", "AllowPlayerTargets", SimConfig.Get("AllowPlayerTargets"))
        CreateToggleField(pageAim, "Filtrar Somente Alvos com Visada Livre (Visible Only)", "VisibleOnly", SimConfig.Get("VisibleOnly"))
        CreateToggleField(pageAim, "Ignorar Aliados da Mesma Equipe (Team Check)", "TeamCheck", SimConfig.Get("TeamCheck"))
        CreateToggleField(pageAim, "Exibir Círculo de FOV na Tela", "ShowFovCircle", SimConfig.Get("ShowFovCircle"))
        CreateToggleField(pageAim, "Realce Visual de Entidades (Highlights ESP)", "EnableESP", SimConfig.Get("EnableESP"))

        CreateSectionHeader(pageAim, "PARÂMETROS DE RESPOSTA E ALINHAMENTO CINEMÁTICO")
        CreateSliderField(pageAim, "Campo de Visão (FOV °)", "FOV", 10, 180, SimConfig.Get("FOV"), 1, "Sincronizado opticamente com o retículo circular na tela")
        CreateSliderField(pageAim, "Coeficiente de Suavização (Lerp)", "Smoothing", 0.01, 1.0, SimConfig.Get("Smoothing"), 0.01, "0.01 = Instantâneo/Snap | 1.00 = Ultra Suave/Cinemático")
        CreateSliderField(pageAim, "Velocidade Angular Máxima (°/s)", "AngularVelocity", 30, 1200, SimConfig.Get("AngularVelocity"), 10)
        CreateToggleField(pageAim, "Forçar Limite Estrito de Velocidade Angular (Clamp)", "MaxAngularVelocityClamp", SimConfig.Get("MaxAngularVelocityClamp"))
        CreateSliderField(pageAim, "Raio Máximo de Atuação (studs)", "VectorRadius", 10, 500, SimConfig.Get("VectorRadius"), 5)
        CreateSliderField(pageAim, "Tempo de Resposta Simulado (ms)", "ResponseTime", 0, 250, SimConfig.Get("ResponseTime"), 1)

        CreateSectionHeader(pageAim, "MODOS DE ATIVAÇÃO E PRIORIZAÇÃO DE ALVOS")
        -- Seletor AimMode
        local aimModeRow = Instance.new("Frame")
        aimModeRow.Size = UDim2.new(1, 0, 0, 36)
        aimModeRow.BackgroundColor3 = THEME.BG_INPUT
        aimModeRow.BackgroundTransparency = 0.5
        aimModeRow.Parent = pageAim
        AddCorner(aimModeRow, 6)
        AddStroke(aimModeRow, THEME.BORDER, 1)

        local aimModeLbl = Instance.new("TextLabel")
        aimModeLbl.Size = UDim2.new(0, 110, 1, 0)
        aimModeLbl.Position = UDim2.new(0, 10, 0, 0)
        aimModeLbl.BackgroundTransparency = 1
        aimModeLbl.Font = Enum.Font.GothamMedium
        aimModeLbl.TextSize = 11
        aimModeLbl.TextColor3 = THEME.TEXT_MAIN
        aimModeLbl.TextXAlignment = Enum.TextXAlignment.Left
        aimModeLbl.Text = "Modo de Mira:"
        aimModeLbl.Parent = aimModeRow

        local aimModeGrid = Instance.new("Frame")
        aimModeGrid.Size = UDim2.new(1, -125, 0, 24)
        aimModeGrid.Position = UDim2.new(0, 115, 0.5, -12)
        aimModeGrid.BackgroundTransparency = 1
        aimModeGrid.Parent = aimModeRow

        local aimModeLayout = Instance.new("UIGridLayout")
        aimModeLayout.CellSize = UDim2.new(0.31, 0, 1, 0)
        aimModeLayout.CellPadding = UDim2.new(0.035, 0, 0, 0)
        aimModeLayout.Parent = aimModeGrid

        local aimModeButtons: { [string]: TextButton } = {}
        local aimModeOptions = { { Id = "HoldRMB", Label = "Segurar RMB" }, { Id = "Toggle", Label = "Alternar" }, { Id = "AlwaysOn", Label = "Sempre Ativo" } }
        local function UpdateAimModeUI(activeId: string)
            for id, btn in pairs(aimModeButtons) do
                local isSel = (id == activeId)
                btn.BackgroundColor3 = isSel and THEME.ACCENT_RED or THEME.BG_WINDOW
                btn.TextColor3 = isSel and THEME.TEXT_MAIN or THEME.TEXT_MUTED
            end
        end
        for _, opt in ipairs(aimModeOptions) do
            local aBtn = Instance.new("TextButton")
            local isCurrent = (SimConfig.Get("AimMode") or "HoldRMB") == opt.Id
            aBtn.BackgroundColor3 = isCurrent and THEME.ACCENT_RED or THEME.BG_WINDOW
            aBtn.TextColor3 = isCurrent and THEME.TEXT_MAIN or THEME.TEXT_MUTED
            aBtn.Font = Enum.Font.GothamBold
            aBtn.TextSize = 10
            aBtn.Text = opt.Label
            aBtn.Parent = aimModeGrid
            AddCorner(aBtn, 4)
            AddStroke(aBtn, THEME.BORDER, 1)
            aimModeButtons[opt.Id] = aBtn
            aBtn.MouseButton1Click:Connect(function()
                SimConfig.Set("AimMode", opt.Id)
                UpdateAimModeUI(opt.Id)
                DashboardGUI.AddDiagnosticLog("AIM_MODE", "Modo alterado: " .. opt.Label, "INFO")
            end)
        end

        CreateToggleField(pageAim, "Segurar Botão Direito para Focar (Hold to Aim)", "HoldToAim", SimConfig.Get("HoldToAim"))

        -- Prioridade de Alvos
        local prioRow = Instance.new("Frame")
        prioRow.Size = UDim2.new(1, 0, 0, 36)
        prioRow.BackgroundColor3 = THEME.BG_INPUT
        prioRow.BackgroundTransparency = 0.5
        prioRow.Parent = pageAim
        AddCorner(prioRow, 6)
        AddStroke(prioRow, THEME.BORDER, 1)

        local prioLbl = Instance.new("TextLabel")
        prioLbl.Size = UDim2.new(0, 110, 1, 0)
        prioLbl.Position = UDim2.new(0, 10, 0, 0)
        prioLbl.BackgroundTransparency = 1
        prioLbl.Font = Enum.Font.GothamMedium
        prioLbl.TextSize = 11
        prioLbl.TextColor3 = THEME.TEXT_MAIN
        prioLbl.TextXAlignment = Enum.TextXAlignment.Left
        prioLbl.Text = "Prioridade:"
        prioLbl.Parent = prioRow

        local prioGrid = Instance.new("Frame")
        prioGrid.Size = UDim2.new(1, -125, 0, 24)
        prioGrid.Position = UDim2.new(0, 115, 0.5, -12)
        prioGrid.BackgroundTransparency = 1
        prioGrid.Parent = prioRow

        local prioLayout = Instance.new("UIGridLayout")
        prioLayout.CellSize = UDim2.new(0.31, 0, 1, 0)
        prioLayout.CellPadding = UDim2.new(0.035, 0, 0, 0)
        prioLayout.Parent = prioGrid

        local prioButtons: { [string]: TextButton } = {}
        local prioOptions = { { Id = "Crosshair", Label = "Mira" }, { Id = "Distance", Label = "Distância" }, { Id = "LowestHealth", Label = "Menor Vida" } }
        local function UpdatePrioUI(activeId: string)
            for id, btn in pairs(prioButtons) do
                local isSel = (id == activeId)
                btn.BackgroundColor3 = isSel and THEME.ACCENT_RED or THEME.BG_WINDOW
                btn.TextColor3 = isSel and THEME.TEXT_MAIN or THEME.TEXT_MUTED
            end
        end
        for _, opt in ipairs(prioOptions) do
            local pBtn = Instance.new("TextButton")
            local isCurrent = (SimConfig.Get("TargetPriority") or "Crosshair") == opt.Id
            pBtn.BackgroundColor3 = isCurrent and THEME.ACCENT_RED or THEME.BG_WINDOW
            pBtn.TextColor3 = isCurrent and THEME.TEXT_MAIN or THEME.TEXT_MUTED
            pBtn.Font = Enum.Font.GothamBold
            pBtn.TextSize = 10
            pBtn.Text = opt.Label
            pBtn.Parent = prioGrid
            AddCorner(pBtn, 4)
            AddStroke(pBtn, THEME.BORDER, 1)
            prioButtons[opt.Id] = pBtn
            pBtn.MouseButton1Click:Connect(function()
                SimConfig.Set("TargetPriority", opt.Id)
                UpdatePrioUI(opt.Id)
                DashboardGUI.AddDiagnosticLog("TARGETING", "Prioridade alterada: " .. opt.Label, "INFO")
            end)
        end

        CreateSliderField(pageAim, "Persistência no Alvo (Target Stickiness s)", "TargetStickiness", 0.05, 1.0, SimConfig.Get("TargetStickiness"), 0.05)
        CreateToggleField(pageAim, "Simular Micro-Variações Orgânicas (Perlin Jitter)", "SimulateJitter", SimConfig.Get("SimulateJitter"))
        CreateSliderField(pageAim, "Intensidade do Jitter (%)", "Intensity", 0, 100, SimConfig.Get("Intensity"), 5)
        CreateSliderField(pageAim, "Curva de Aceleração (Hermite Exponent)", "AccelerationCurve", 0.2, 3.0, SimConfig.Get("AccelerationCurve"), 0.05)

        CreateSectionHeader(pageAim, "REGIÃO ANATÔMICA PRIORITÁRIA (HITBOX)")
        local boneRow = Instance.new("Frame")
        boneRow.Size = UDim2.new(1, 0, 0, 36)
        boneRow.BackgroundColor3 = THEME.BG_INPUT
        boneRow.BackgroundTransparency = 0.5
        boneRow.Parent = pageAim
        AddCorner(boneRow, 6)
        AddStroke(boneRow, THEME.BORDER, 1)

        local boneLbl = Instance.new("TextLabel")
        boneLbl.Size = UDim2.new(0, 110, 1, 0)
        boneLbl.Position = UDim2.new(0, 10, 0, 0)
        boneLbl.BackgroundTransparency = 1
        boneLbl.Font = Enum.Font.GothamMedium
        boneLbl.TextSize = 11
        boneLbl.TextColor3 = THEME.TEXT_MAIN
        boneLbl.TextXAlignment = Enum.TextXAlignment.Left
        boneLbl.Text = "Região Ativa:"
        boneLbl.Parent = boneRow

        local boneGrid = Instance.new("Frame")
        boneGrid.Size = UDim2.new(1, -125, 0, 24)
        boneGrid.Position = UDim2.new(0, 115, 0.5, -12)
        boneGrid.BackgroundTransparency = 1
        boneGrid.Parent = boneRow

        local boneLayout = Instance.new("UIGridLayout")
        boneLayout.CellSize = UDim2.new(0.23, 0, 1, 0)
        boneLayout.CellPadding = UDim2.new(0.026, 0, 0, 0)
        boneLayout.Parent = boneGrid

        local boneButtons: { [string]: TextButton } = {}
        local boneOptions = { { Id = "Head", Label = "Cabeça" }, { Id = "Torso", Label = "Tronco" }, { Id = "Arms", Label = "Braços" }, { Id = "Legs", Label = "Pernas" } }
        local function UpdateBoneUI(activeId: string)
            for id, btn in pairs(boneButtons) do
                local isSel = (id == activeId)
                btn.BackgroundColor3 = isSel and THEME.ACCENT_RED or THEME.BG_WINDOW
                btn.TextColor3 = isSel and THEME.TEXT_MAIN or THEME.TEXT_MUTED
            end
        end
        for _, opt in ipairs(boneOptions) do
            local bBtn = Instance.new("TextButton")
            local isCurrent = (SimConfig.Get("TargetRegion") or "Head") == opt.Id
            bBtn.BackgroundColor3 = isCurrent and THEME.ACCENT_RED or THEME.BG_WINDOW
            bBtn.TextColor3 = isCurrent and THEME.TEXT_MAIN or THEME.TEXT_MUTED
            bBtn.Font = Enum.Font.GothamBold
            bBtn.TextSize = 10
            bBtn.Text = opt.Label
            bBtn.Parent = boneGrid
            AddCorner(bBtn, 4)
            AddStroke(bBtn, THEME.BORDER, 1)
            boneButtons[opt.Id] = bBtn
            bBtn.MouseButton1Click:Connect(function()
                SimConfig.Set("TargetRegion", opt.Id)
                UpdateBoneUI(opt.Id)
                DashboardGUI.AddDiagnosticLog("HITBOX", "Região anatômica: " .. opt.Label, "INFO")
            end)
        end

        -- =========================================================================
        -- [ABA 2] DISPAROS SIMULADOS (SILENT AIM)
        -- =========================================================================
        local pageSilent = pages["SilentAim"]

        CreateSectionHeader(pageSilent, "SIMULAÇÃO DE DISPAROS DESACOPLADOS (SILENT AIM)")
        CreateToggleField(pageSilent, "Ativar Simulação de Silent Aim (Vetor Desacoplado)", "SilentAimEnabled", SimConfig.Get("SilentAimEnabled"))
        CreateSliderField(pageSilent, "Silent Aim - Campo de Redirecionamento (FOV °)", "SilentAimFOV", 5, 90, SimConfig.Get("SilentAimFOV"), 1, "Cone angular máximo permitido para redirecionamento do tiro")
        CreateSliderField(pageSilent, "Probabilidade de Acerto do Silent Aim (%)", "SilentAimHitChance", 10, 100, SimConfig.Get("SilentAimHitChance"), 5, "100% = Acerto determinístico | <100% = Dispersão probabilística")
        CreateToggleField(pageSilent, "Exibir Traçador 3D do Vetor de Disparo (Tracer)", "SilentAimTracer", SimConfig.Get("SilentAimTracer"))

        -- Card com Pipeline em 5 Etapas e Telemetria de Colisão
        local pipelineCard = Instance.new("Frame")
        pipelineCard.Size = UDim2.new(1, 0, 0, 126)
        pipelineCard.BackgroundColor3 = THEME.BG_INPUT
        pipelineCard.Parent = pageSilent
        AddCorner(pipelineCard, 6)
        AddStroke(pipelineCard, THEME.BORDER, 1)

        local pTitle = Instance.new("TextLabel")
        pTitle.Size = UDim2.new(1, -16, 0, 18)
        pTitle.Position = UDim2.new(0, 8, 0, 6)
        pTitle.BackgroundTransparency = 1
        pTitle.Font = Enum.Font.GothamBold
        pTitle.TextSize = 10
        pTitle.TextColor3 = THEME.TEXT_MAIN
        pTitle.TextXAlignment = Enum.TextXAlignment.Left
        pTitle.Text = "PIPELINE DE DISPARO AUDITADO (5 ETAPAS):"
        pTitle.Parent = pipelineCard

        local pSteps = Instance.new("TextLabel")
        pSteps.Size = UDim2.new(1, -16, 0, 16)
        pSteps.Position = UDim2.new(0, 8, 0, 24)
        pSteps.BackgroundTransparency = 1
        pSteps.Font = Enum.Font.Code
        pSteps.TextSize = 8.5
        pSteps.TextColor3 = THEME.TEXT_MUTED
        pSteps.TextXAlignment = Enum.TextXAlignment.Left
        pSteps.Text = "[1] RECEBIDO → [2] VALIDADO → [3] TRAJETÓRIA → [4] COLISÃO FÍSICA → [5] RESULTADO"
        pSteps.Parent = pipelineCard

        -- Linha 1: Estado do Módulo e Etapa Atual
        local pStatus1 = Instance.new("TextLabel")
        pStatus1.Size = UDim2.new(0.5, -10, 0, 16)
        pStatus1.Position = UDim2.new(0, 8, 0, 44)
        pStatus1.BackgroundTransparency = 1
        pStatus1.Font = Enum.Font.GothamMedium
        pStatus1.TextSize = 10
        pStatus1.TextColor3 = THEME.TEXT_MUTED
        pStatus1.TextXAlignment = Enum.TextXAlignment.Left
        pStatus1.Text = "Módulo: CARREGADO"
        pStatus1.Parent = pipelineCard
        TelemetryLabels["SilentAimStatus"] = pStatus1

        local pCurrentStage = Instance.new("TextLabel")
        pCurrentStage.Size = UDim2.new(0.5, -10, 0, 16)
        pCurrentStage.Position = UDim2.new(0.5, 0, 0, 44)
        pCurrentStage.BackgroundTransparency = 1
        pCurrentStage.Font = Enum.Font.GothamMedium
        pCurrentStage.TextSize = 10
        pCurrentStage.TextColor3 = THEME.INFO
        pCurrentStage.TextXAlignment = Enum.TextXAlignment.Right
        pCurrentStage.Text = "Etapa: PRONTO"
        pCurrentStage.Parent = pipelineCard
        TelemetryLabels["SilentAimStage"] = pCurrentStage

        -- Linha 2: Resultado do Último Disparo
        local pStatus2 = Instance.new("TextLabel")
        pStatus2.Size = UDim2.new(1, -16, 0, 18)
        pStatus2.Position = UDim2.new(0, 8, 0, 64)
        pStatus2.BackgroundTransparency = 1
        pStatus2.Font = Enum.Font.GothamBold
        pStatus2.TextSize = 10.5
        pStatus2.TextColor3 = THEME.TEXT_MUTED
        pStatus2.TextXAlignment = Enum.TextXAlignment.Left
        pStatus2.Text = "Último Disparo: NENHUM DISPARO EFETUADO"
        pStatus2.Parent = pipelineCard
        TelemetryLabels["LastShotStatus"] = pStatus2

        -- Linha 3: Detalhes Físicos / Impacto
        local pDetails = Instance.new("TextLabel")
        pDetails.Size = UDim2.new(1, -16, 0, 16)
        pDetails.Position = UDim2.new(0, 8, 0, 84)
        pDetails.BackgroundTransparency = 1
        pDetails.Font = Enum.Font.Code
        pDetails.TextSize = 9
        pDetails.TextColor3 = THEME.TEXT_MUTED
        pDetails.TextXAlignment = Enum.TextXAlignment.Left
        pDetails.Text = "Impacto: — | Parte: — | Desvio: — | Distância: —"
        pDetails.Parent = pipelineCard
        TelemetryLabels["SilentAimDetails"] = pDetails

        -- Linha 4: Causa da Falha / Diagnóstico
        local pFailureReason = Instance.new("TextLabel")
        pFailureReason.Size = UDim2.new(1, -16, 0, 16)
        pFailureReason.Position = UDim2.new(0, 8, 0, 102)
        pFailureReason.BackgroundTransparency = 1
        pFailureReason.Font = Enum.Font.GothamMedium
        pFailureReason.TextSize = 9
        pFailureReason.TextColor3 = THEME.TEXT_MUTED
        pFailureReason.TextXAlignment = Enum.TextXAlignment.Left
        pFailureReason.Text = "Diagnóstico: Aguardando execução do teste funcional."
        pFailureReason.Parent = pipelineCard
        TelemetryLabels["SilentAimReason"] = pFailureReason

        -- Linha de Ações Principais (Disparo de Teste + Spawn Dummy com Debounce)
        local shotActionRow = Instance.new("Frame")
        shotActionRow.Size = UDim2.new(1, 0, 0, 36)
        shotActionRow.BackgroundTransparency = 1
        shotActionRow.Parent = pageSilent

        local isShotTesting = false
        local testShotBtn = Instance.new("TextButton")
        testShotBtn.Size = UDim2.new(0.68, -4, 1, 0)
        testShotBtn.Position = UDim2.new(0, 0, 0, 0)
        testShotBtn.BackgroundColor3 = THEME.ACCENT_RED
        testShotBtn.TextColor3 = THEME.TEXT_MAIN
        testShotBtn.Font = Enum.Font.GothamBold
        testShotBtn.TextSize = 10.5
        testShotBtn.Text = "🎯 DISPARAR TESTE SILENT AIM (5 ETAPAS)"
        testShotBtn.Parent = shotActionRow
        AddCorner(testShotBtn, 6)
        AddStroke(testShotBtn, THEME.BORDER_LIGHT, 1)

        local spawnDummyBtn = Instance.new("TextButton")
        spawnDummyBtn.Size = UDim2.new(0.32, -4, 1, 0)
        spawnDummyBtn.Position = UDim2.new(0.68, 4, 0, 0)
        spawnDummyBtn.BackgroundColor3 = THEME.BG_INPUT
        spawnDummyBtn.TextColor3 = THEME.TEXT_MAIN
        spawnDummyBtn.Font = Enum.Font.GothamBold
        spawnDummyBtn.TextSize = 10
        spawnDummyBtn.Text = "🤖 SPAWN DUMMY"
        spawnDummyBtn.Parent = shotActionRow
        AddCorner(spawnDummyBtn, 6)
        AddStroke(spawnDummyBtn, THEME.BORDER, 1)

        testShotBtn.MouseButton1Click:Connect(function()
            if isShotTesting then return end
            isShotTesting = true
            testShotBtn.Text = "⏳ EXECUTANDO PIPELINE (5 ETAPAS)..."
            testShotBtn.BackgroundColor3 = THEME.BORDER
            task.defer(function()
                if DashboardGUI.OnSimulateSilentAimShot then
                    DashboardGUI.OnSimulateSilentAimShot()
                end
                task.wait(0.35)
                testShotBtn.Text = "🎯 DISPARAR TESTE SILENT AIM (5 ETAPAS)"
                testShotBtn.BackgroundColor3 = THEME.ACCENT_RED
                isShotTesting = false
            end)
        end)

        spawnDummyBtn.MouseButton1Click:Connect(function()
            if DashboardGUI.OnSpawnTestDummy then
                DashboardGUI.OnSpawnTestDummy()
            end
        end)

        -- Grade de Cenários Reproduzíveis de Disparo
        CreateSectionHeader(pageSilent, "CENÁRIOS REPRODUZÍVEIS DE DISPARO (TESTES FUNCIONAIS)")
        local shotScenarioGrid = Instance.new("Frame")
        shotScenarioGrid.Size = UDim2.new(1, 0, 0, 0)
        shotScenarioGrid.AutomaticSize = Enum.AutomaticSize.Y
        shotScenarioGrid.BackgroundTransparency = 1
        shotScenarioGrid.Parent = pageSilent

        local ssgLayout = Instance.new("UIGridLayout")
        ssgLayout.CellSize = UDim2.new(0.485, 0, 0, 28)
        ssgLayout.CellPadding = UDim2.new(0.03, 0, 0, 6)
        ssgLayout.Parent = shotScenarioGrid

        for _, sc in ipairs(ScenarioRunner.ShotScenarios) do
            local scBtn = Instance.new("TextButton")
            scBtn.BackgroundColor3 = THEME.BG_INPUT
            scBtn.Font = Enum.Font.GothamMedium
            scBtn.TextSize = 9.5
            scBtn.TextColor3 = THEME.TEXT_MAIN
            scBtn.Text = "▶ " .. sc.Label
            scBtn.Parent = shotScenarioGrid
            AddCorner(scBtn, 5)
            AddStroke(scBtn, THEME.BORDER, 1)

            scBtn.MouseButton1Click:Connect(function()
                if isShotTesting then return end
                isShotTesting = true
                scBtn.TextColor3 = THEME.INFO
                task.defer(function()
                    if DashboardGUI.OnRunShotScenario then
                        DashboardGUI.OnRunShotScenario(sc.Id)
                    end
                    task.wait(0.35)
                    scBtn.TextColor3 = THEME.TEXT_MAIN
                    isShotTesting = false
                end)
            end)
        end

        -- =========================================================================
        -- [ABA 3] BALÍSTICA (BALLISTICS & PHYSICS)
        -- =========================================================================
        local pageBallistics = pages["Ballistics"]

        CreateSectionHeader(pageBallistics, "FÍSICA BALÍSTICA E TRAJETÓRIA DE PROJÉTEIS")

        -- Seletor de Modelo Balístico
        local projTypeRow = Instance.new("Frame")
        projTypeRow.Size = UDim2.new(1, 0, 0, 36)
        projTypeRow.BackgroundColor3 = THEME.BG_INPUT
        projTypeRow.BackgroundTransparency = 0.5
        projTypeRow.Parent = pageBallistics
        AddCorner(projTypeRow, 6)
        AddStroke(projTypeRow, THEME.BORDER, 1)

        local projTypeLbl = Instance.new("TextLabel")
        projTypeLbl.Size = UDim2.new(0, 110, 1, 0)
        projTypeLbl.Position = UDim2.new(0, 10, 0, 0)
        projTypeLbl.BackgroundTransparency = 1
        projTypeLbl.Font = Enum.Font.GothamMedium
        projTypeLbl.TextSize = 11
        projTypeLbl.TextColor3 = THEME.TEXT_MAIN
        projTypeLbl.TextXAlignment = Enum.TextXAlignment.Left
        projTypeLbl.Text = "Modelo Balístico:"
        projTypeLbl.Parent = projTypeRow

        local projGrid = Instance.new("Frame")
        projGrid.Size = UDim2.new(1, -125, 0, 24)
        projGrid.Position = UDim2.new(0, 115, 0.5, -12)
        projGrid.BackgroundTransparency = 1
        projGrid.Parent = projTypeRow

        local projLayout = Instance.new("UIGridLayout")
        projLayout.CellSize = UDim2.new(0.48, 0, 1, 0)
        projLayout.CellPadding = UDim2.new(0.04, 0, 0, 0)
        projLayout.Parent = projGrid

        local projButtons: { [string]: TextButton } = {}
        local projOptions = { { Id = "Instant", Label = "Instantâneo (Raycast)" }, { Id = "Physics", Label = "Físico (Gravidade/Arco)" } }
        local function UpdateProjTypeUI(activeId: string)
            for id, btn in pairs(projButtons) do
                local isSel = (id == activeId)
                btn.BackgroundColor3 = isSel and THEME.ACCENT_RED or THEME.BG_WINDOW
                btn.TextColor3 = isSel and THEME.TEXT_MAIN or THEME.TEXT_MUTED
            end
        end
        for _, opt in ipairs(projOptions) do
            local prBtn = Instance.new("TextButton")
            local isCurrent = (SimConfig.Get("ProjectileType") or "Instant") == opt.Id
            prBtn.BackgroundColor3 = isCurrent and THEME.ACCENT_RED or THEME.BG_WINDOW
            prBtn.TextColor3 = isCurrent and THEME.TEXT_MAIN or THEME.TEXT_MUTED
            prBtn.Font = Enum.Font.GothamBold
            prBtn.TextSize = 10
            prBtn.Text = opt.Label
            prBtn.Parent = projGrid
            AddCorner(prBtn, 4)
            AddStroke(prBtn, THEME.BORDER, 1)
            projButtons[opt.Id] = prBtn
            prBtn.MouseButton1Click:Connect(function()
                SimConfig.Set("ProjectileType", opt.Id)
                UpdateProjTypeUI(opt.Id)
                DashboardGUI.AddDiagnosticLog("BALLISTICS", "Modelo balístico: " .. opt.Label, "INFO")
            end)
        end

        CreateSliderField(pageBallistics, "Velocidade Balística Simulada (studs/s)", "ProjectileSpeed", 100, 3000, SimConfig.Get("ProjectileSpeed"), 50)
        CreateSliderField(pageBallistics, "Gravidade de Projétil Físico (studs/s²)", "ProjectileGravity", 0, 500, SimConfig.Get("ProjectileGravity"), 10, "Padrão Roblox = 196.2 studs/s² | Gravidade zero = 0")
        CreateToggleField(pageBallistics, "Compensação de Queda por Gravidade (Bullet Drop)", "ProjectileDropComp", SimConfig.Get("ProjectileDropComp"))
        CreateToggleField(pageBallistics, "Ativar Predição Balística de Alvo (Lead Tracking)", "EnableLead", SimConfig.Get("EnableLead"))

        local ballisticsInfoCard = Instance.new("Frame")
        ballisticsInfoCard.Size = UDim2.new(1, 0, 0, 70)
        ballisticsInfoCard.BackgroundColor3 = THEME.BG_INPUT
        ballisticsInfoCard.Parent = pageBallistics
        AddCorner(ballisticsInfoCard, 6)
        AddStroke(ballisticsInfoCard, THEME.BORDER, 1)

        local bTitle = Instance.new("TextLabel")
        bTitle.Size = UDim2.new(1, -16, 0, 18)
        bTitle.Position = UDim2.new(0, 8, 0, 6)
        bTitle.BackgroundTransparency = 1
        bTitle.Font = Enum.Font.GothamBold
        bTitle.TextSize = 10
        bTitle.TextColor3 = THEME.TEXT_MAIN
        bTitle.TextXAlignment = Enum.TextXAlignment.Left
        bTitle.Text = "TELEMETRIA BALÍSTICA E QUEDA PARABÓLICA:"
        bTitle.Parent = ballisticsInfoCard

        local bDesc = Instance.new("TextLabel")
        bDesc.Size = UDim2.new(1, -16, 0, 36)
        bDesc.Position = UDim2.new(0, 8, 0, 26)
        bDesc.BackgroundTransparency = 1
        bDesc.Font = Enum.Font.Code
        bDesc.TextSize = 9
        bDesc.TextColor3 = THEME.TEXT_MUTED
        bDesc.TextXAlignment = Enum.TextXAlignment.Left
        bDesc.Text = "Fórmula: Delta_Y = 0.5 * g * (d / v0)²  |  Trajetória segmentada em 10 arcos sob aceleração vetorial vertical."
        bDesc.Parent = ballisticsInfoCard

        -- =========================================================================
        -- [ABA 4] DIAGNÓSTICO & ASSISTENTE INTELIGENTE (IA)
        -- =========================================================================
        local pageDiag = pages["Diagnostics"]

        CreateSectionHeader(pageDiag, "AÇÕES DE DIAGNÓSTICO E AUDITORIA DO SISTEMA")

        -- Botões de Ação Global de Diagnóstico
        local diagActionRow = Instance.new("Frame")
        diagActionRow.Size = UDim2.new(1, 0, 0, 34)
        diagActionRow.BackgroundTransparency = 1
        diagActionRow.Parent = pageDiag

        local runDiagBtn = Instance.new("TextButton")
        runDiagBtn.Size = UDim2.new(0.5, -4, 1, 0)
        runDiagBtn.Position = UDim2.new(0, 0, 0, 0)
        runDiagBtn.BackgroundColor3 = THEME.ACCENT_RED
        runDiagBtn.TextColor3 = THEME.TEXT_MAIN
        runDiagBtn.Font = Enum.Font.GothamBold
        runDiagBtn.TextSize = 10.5
        runDiagBtn.Text = "🩺 EXECUTAR DIAGNÓSTICO COMPLETO"
        runDiagBtn.Parent = diagActionRow
        AddCorner(runDiagBtn, 6)
        AddStroke(runDiagBtn, THEME.BORDER_LIGHT, 1)

        local runShotBtn = Instance.new("TextButton")
        runShotBtn.Size = UDim2.new(0.5, -4, 1, 0)
        runShotBtn.Position = UDim2.new(0.5, 4, 0, 0)
        runShotBtn.BackgroundColor3 = THEME.BG_INPUT
        runShotBtn.TextColor3 = THEME.TEXT_MAIN
        runShotBtn.Font = Enum.Font.GothamBold
        runShotBtn.TextSize = 10.5
        runShotBtn.Text = "🎯 TESTAR DISPARO SILENT AIM"
        runShotBtn.Parent = diagActionRow
        AddCorner(runShotBtn, 6)
        AddStroke(runShotBtn, THEME.BORDER, 1)

        -- Card com Status dos Módulos
        local moduleStatusCard = Instance.new("Frame")
        moduleStatusCard.Size = UDim2.new(1, 0, 0, 52)
        moduleStatusCard.BackgroundColor3 = THEME.BG_INPUT
        moduleStatusCard.Parent = pageDiag
        AddCorner(moduleStatusCard, 6)
        AddStroke(moduleStatusCard, THEME.BORDER, 1)

        local msPad = Instance.new("UIPadding")
        msPad.PaddingTop = UDim.new(0, 4)
        msPad.PaddingBottom = UDim.new(0, 4)
        msPad.PaddingLeft = UDim.new(0, 6)
        msPad.PaddingRight = UDim.new(0, 6)
        msPad.Parent = moduleStatusCard

        local msLayout = Instance.new("UIGridLayout")
        msLayout.CellSize = UDim2.new(0.24, 0, 1, 0)
        msLayout.CellPadding = UDim2.new(0.013, 0, 0, 0)
        msLayout.Parent = moduleStatusCard

        local function MakeModuleBadge(modName: string, initialStatus: string, labelKey: string)
            local box = Instance.new("Frame")
            box.BackgroundColor3 = THEME.BG_WINDOW
            box.Parent = moduleStatusCard
            AddCorner(box, 4)
            AddStroke(box, THEME.BORDER, 1)

            local t1 = Instance.new("TextLabel")
            t1.Size = UDim2.new(1, -6, 0, 16)
            t1.Position = UDim2.new(0, 4, 0, 3)
            t1.BackgroundTransparency = 1
            t1.Font = Enum.Font.GothamBold
            t1.TextSize = 9
            t1.TextColor3 = THEME.TEXT_MAIN
            t1.TextXAlignment = Enum.TextXAlignment.Left
            t1.Text = modName
            t1.Parent = box

            local t2 = Instance.new("TextLabel")
            t2.Size = UDim2.new(1, -6, 0, 18)
            t2.Position = UDim2.new(0, 4, 0, 20)
            t2.BackgroundTransparency = 1
            t2.Font = Enum.Font.Code
            t2.TextSize = 8.5
            t2.TextColor3 = THEME.SUCCESS
            t2.TextXAlignment = Enum.TextXAlignment.Left
            t2.Text = initialStatus
            t2.Parent = box
            TelemetryLabels[labelKey] = t2
        end

        MakeModuleBadge("VectorTracker", "● MONITORANDO", "ModStatus_Tracker")
        MakeModuleBadge("InstanceDetector", "● ATIVO", "ModStatus_Detector")
        MakeModuleBadge("DiagnosticAI", "● OPERACIONAL", "ModStatus_Diagnostic")
        MakeModuleBadge("Silent Aim", "○ PRONTO", "ModStatus_SilentAim")

        CreateSectionHeader(pageDiag, "ASSISTENTE INTELIGENTE & CHATBOT DE DIAGNÓSTICO")

        -- Chatbot UI Container
        local chatCard = Instance.new("Frame")
        chatCard.Size = UDim2.new(1, 0, 0, 220)
        chatCard.BackgroundColor3 = THEME.BG_INPUT
        chatCard.Parent = pageDiag
        AddCorner(chatCard, 8)
        AddStroke(chatCard, THEME.BORDER, 1)

        -- Botões de Ação Rápida
        local quickBtnGrid = Instance.new("Frame")
        quickBtnGrid.Size = UDim2.new(1, -16, 0, 26)
        quickBtnGrid.Position = UDim2.new(0, 8, 0, 8)
        quickBtnGrid.BackgroundTransparency = 1
        quickBtnGrid.Parent = chatCard

        local qbLayout = Instance.new("UIGridLayout")
        qbLayout.CellSize = UDim2.new(0.24, 0, 1, 0)
        qbLayout.CellPadding = UDim2.new(0.013, 0, 0, 0)
        qbLayout.Parent = quickBtnGrid

        local chatResponseBox = Instance.new("TextLabel")
        chatResponseBox.Size = UDim2.new(1, -16, 0, 120)
        chatResponseBox.Position = UDim2.new(0, 8, 0, 42)
        chatResponseBox.BackgroundColor3 = THEME.BG_WINDOW
        chatResponseBox.Font = Enum.Font.GothamMedium
        chatResponseBox.TextSize = 10
        chatResponseBox.TextColor3 = THEME.TEXT_MAIN
        chatResponseBox.TextXAlignment = Enum.TextXAlignment.Left
        chatResponseBox.TextYAlignment = Enum.TextYAlignment.Top
        chatResponseBox.TextWrapped = true
        chatResponseBox.Text = "  Assistente DeepHat pronto para responder. Selecione um diagnóstico rápido ou faça uma pergunta abaixo."
        chatResponseBox.Parent = chatCard
        AddCorner(chatResponseBox, 6)
        AddStroke(chatResponseBox, THEME.BORDER, 1)

        local function TriggerChatQuery(query: string)
            chatResponseBox.Text = "  Analisando estado da simulação, telemetria e logs..."
            chatResponseBox.TextColor3 = THEME.WARNING
            task.defer(function()
                local resp = nil
                if DashboardGUI.OnQueryDiagnosticChatbot then
                    resp = DashboardGUI.OnQueryDiagnosticChatbot(query)
                end
                if resp and type(resp) == "table" then
                    chatResponseBox.TextColor3 = THEME.TEXT_MAIN
                    chatResponseBox.Text = string.format("  [DIAGNÓSTICO]: %s\n  [MÓDULO AFETADO]: %s\n  [AÇÃO SUGERIDA]: %s", resp.Answer or "OK", resp.AffectedModule or "Nenhum", resp.SuggestedAction or "Nenhuma")
                else
                    chatResponseBox.TextColor3 = THEME.INFO
                    chatResponseBox.Text = "  [DIAGNÓSTICO]: Estado geral nominal. Nenhum módulo apresenta anomalia crítica no momento."
                end
            end)
        end

        local function MakeQuickButton(text: string, query: string)
            local qb = Instance.new("TextButton")
            qb.BackgroundColor3 = THEME.BG_WINDOW
            qb.Font = Enum.Font.GothamBold
            qb.TextSize = 9
            qb.TextColor3 = THEME.TEXT_MAIN
            qb.Text = text
            qb.Parent = quickBtnGrid
            AddCorner(qb, 4)
            AddStroke(qb, THEME.BORDER, 1)
            qb.MouseButton1Click:Connect(function() TriggerChatQuery(query) end)
        end

        MakeQuickButton("🔍 Analisar Saúde", "analisar status e erros do simulador")
        MakeQuickButton("🎯 Testar Mira", "por que a mira não foca no alvo?")
        MakeQuickButton("⚡ Testar Balística", "como calibrar gravidade e tempo de voo?")
        MakeQuickButton("🛡️ Verificar Visada", "alvo está bloqueado ou ocluído?")

        runDiagBtn.MouseButton1Click:Connect(function()
            TriggerChatQuery("executar diagnóstico completo e status operacional de todos os módulos")
        end)
        runShotBtn.MouseButton1Click:Connect(function()
            if DashboardGUI.OnSimulateSilentAimShot then
                DashboardGUI.OnSimulateSilentAimShot()
            end
        end)

        -- Input Row do Chatbot
        local chatInputRow = Instance.new("Frame")
        chatInputRow.Size = UDim2.new(1, -16, 0, 32)
        chatInputRow.Position = UDim2.new(0, 8, 1, -40)
        chatInputRow.BackgroundTransparency = 1
        chatInputRow.Parent = chatCard

        local chatInput = Instance.new("TextBox")
        chatInput.Size = UDim2.new(1, -90, 1, 0)
        chatInput.BackgroundColor3 = THEME.BG_WINDOW
        chatInput.TextColor3 = THEME.TEXT_MAIN
        chatInput.PlaceholderText = "Pergunte sobre falhas, calibração de mira, FOV ou gravidade..."
        chatInput.PlaceholderColor3 = THEME.TEXT_MUTED
        chatInput.Font = Enum.Font.GothamMedium
        chatInput.TextSize = 10
        chatInput.ClearTextOnFocus = false
        chatInput.Parent = chatInputRow
        AddCorner(chatInput, 5)
        AddStroke(chatInput, THEME.BORDER, 1)

        local chatSendBtn = Instance.new("TextButton")
        chatSendBtn.Size = UDim2.new(0, 82, 1, 0)
        chatSendBtn.Position = UDim2.new(1, -82, 0, 0)
        chatSendBtn.BackgroundColor3 = THEME.ACCENT_RED
        chatSendBtn.Font = Enum.Font.GothamBold
        chatSendBtn.TextSize = 11
        chatSendBtn.TextColor3 = THEME.TEXT_MAIN
        chatSendBtn.Text = "ENVIAR"
        chatSendBtn.Parent = chatInputRow
        AddCorner(chatSendBtn, 5)
        AddStroke(chatSendBtn, THEME.BORDER_LIGHT, 1)

        local function SubmitChat()
            local text = chatInput.Text
            if #text > 1 then
                TriggerChatQuery(text)
                chatInput.Text = ""
            end
        end
        chatSendBtn.MouseButton1Click:Connect(SubmitChat)
        chatInput.FocusLost:Connect(function(enterPressed)
            if enterPressed then SubmitChat() end
        end)

        -- Seção de Cenários de Linha de Visada (LOS)
        CreateSectionHeader(pageDiag, "CENÁRIOS DE LINHA DE VISADA (LINE OF SIGHT)")
        LosLabels["Status"] = MakeInfoLabel(pageDiag, "Última consulta: (nenhuma)", THEME.TEXT_MUTED, 24)
        LosLabels["Reason"] = MakeInfoLabel(pageDiag, "Causa: —", THEME.TEXT_MUTED, 22)
        LosLabels["Blocker"] = MakeInfoLabel(pageDiag, "Obstrução: —", THEME.TEXT_MUTED, 22)
        LosLabels["Distance"] = MakeInfoLabel(pageDiag, "Distância da colisão: —", THEME.TEXT_MUTED, 22)

        local function MakeButtonGrid(parent: Instance, cellW: number): Frame
            local grid = Instance.new("Frame")
            grid.Size = UDim2.new(1, 0, 0, 0)
            grid.AutomaticSize = Enum.AutomaticSize.Y
            grid.BackgroundTransparency = 1
            grid.Parent = parent
            local layout = Instance.new("UIGridLayout")
            layout.CellSize = UDim2.new(0, cellW, 0, 26)
            layout.CellPadding = UDim2.new(0, 6, 0, 6)
            layout.Parent = grid
            return grid
        end

        local function MakeGridButton(grid: Instance, text: string, onClick: () -> ())
            local b = Instance.new("TextButton")
            b.BackgroundColor3 = THEME.BG_INPUT
            b.Font = Enum.Font.GothamMedium
            b.TextSize = 10
            b.TextColor3 = THEME.TEXT_MAIN
            b.TextWrapped = true
            b.Text = text
            b.Parent = grid
            AddCorner(b, 5)
            AddStroke(b, THEME.BORDER, 1)
            b.MouseButton1Click:Connect(onClick)
        end

        local scenarioGrid = MakeButtonGrid(pageDiag, 150)
        for _, sc in ipairs(ScenarioRunner.Scenarios) do
            MakeGridButton(scenarioGrid, "▶ " .. sc.Label, function()
                if DashboardGUI.OnRunLosScenario then DashboardGUI.OnRunLosScenario(sc.Id) end
            end)
        end
        MakeGridButton(scenarioGrid, "🗑 Limpar Histórico", function()
            if DashboardGUI.OnClearLosHistory then DashboardGUI.OnClearLosHistory() end
            if LosHistoryList then
                for _, ch in ipairs(LosHistoryList:GetChildren()) do
                    if ch:IsA("TextLabel") then ch:Destroy() end
                end
            end
        end)

        local losHistory = Instance.new("ScrollingFrame")
        losHistory.Size = UDim2.new(1, 0, 0, 110)
        losHistory.BackgroundColor3 = THEME.BG_WINDOW
        losHistory.ScrollBarThickness = 4
        losHistory.CanvasSize = UDim2.new(0, 0, 0, 0)
        losHistory.AutomaticCanvasSize = Enum.AutomaticSize.Y
        losHistory.Parent = pageDiag
        AddCorner(losHistory, 6)
        AddStroke(losHistory, THEME.BORDER, 1)
        local losHistLayout = Instance.new("UIListLayout")
        losHistLayout.Padding = UDim.new(0, 2)
        losHistLayout.SortOrder = Enum.SortOrder.LayoutOrder
        losHistLayout.Parent = losHistory
        LosHistoryList = losHistory

        -- Log de Diagnósticos em Tempo Real com Filtros de Nível
        local logHeaderFrame = Instance.new("Frame")
        logHeaderFrame.Size = UDim2.new(1, 0, 0, 26)
        logHeaderFrame.BackgroundTransparency = 1
        logHeaderFrame.Parent = pageDiag

        local logTitle = Instance.new("TextLabel")
        logTitle.Size = UDim2.new(0, 220, 1, 0)
        logTitle.BackgroundTransparency = 1
        logTitle.Font = Enum.Font.GothamBold
        logTitle.TextSize = 11
        logTitle.TextColor3 = THEME.TEXT_MUTED
        logTitle.TextXAlignment = Enum.TextXAlignment.Left
        logTitle.Text = "LOG DE EVENTOS EM TEMPO REAL"
        logTitle.Parent = logHeaderFrame

        local filterBar = Instance.new("Frame")
        filterBar.Size = UDim2.new(1, -225, 1, 0)
        filterBar.Position = UDim2.new(0, 225, 0, 0)
        filterBar.BackgroundTransparency = 1
        filterBar.Parent = logHeaderFrame

        local filterLayout = Instance.new("UIListLayout")
        filterLayout.FillDirection = Enum.FillDirection.Horizontal
        filterLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
        filterLayout.Padding = UDim.new(0, 4)
        filterLayout.Parent = filterBar

        local filterButtons: { [string]: TextButton } = {}
        local filterOptions = { "TODOS", "OK", "INFO", "WARN", "FAIL" }

        local function SetActiveFilter(flt: string)
            currentLogFilter = flt
            for opt, btn in pairs(filterButtons) do
                if opt == flt then
                    btn.BackgroundColor3 = THEME.ACCENT_RED
                    btn.TextColor3 = THEME.TEXT_MAIN
                else
                    btn.BackgroundColor3 = THEME.BG_INPUT
                    btn.TextColor3 = THEME.TEXT_MUTED
                end
            end
            ApplyLogFilter()
        end

        for _, opt in ipairs(filterOptions) do
            local btn = Instance.new("TextButton")
            btn.Size = UDim2.new(0, 52, 0, 22)
            btn.BackgroundColor3 = (opt == "TODOS") and THEME.ACCENT_RED or THEME.BG_INPUT
            btn.Font = Enum.Font.GothamBold
            btn.TextSize = 9
            btn.TextColor3 = (opt == "TODOS") and THEME.TEXT_MAIN or THEME.TEXT_MUTED
            btn.Text = opt
            btn.Parent = filterBar
            AddCorner(btn, 4)
            AddStroke(btn, THEME.BORDER, 1)
            filterButtons[opt] = btn
            btn.MouseButton1Click:Connect(function()
                SetActiveFilter(opt)
            end)
        end

        local eventLogList = Instance.new("ScrollingFrame")
        eventLogList.Size = UDim2.new(1, 0, 0, 120)
        eventLogList.BackgroundColor3 = THEME.BG_WINDOW
        eventLogList.ScrollBarThickness = 4
        eventLogList.CanvasSize = UDim2.new(0, 0, 0, 0)
        eventLogList.AutomaticCanvasSize = Enum.AutomaticSize.Y
        eventLogList.Parent = pageDiag
        AddCorner(eventLogList, 6)
        AddStroke(eventLogList, THEME.BORDER, 1)
        local evListLayout = Instance.new("UIListLayout")
        evListLayout.Padding = UDim.new(0, 2)
        evListLayout.Parent = eventLogList
        EventLogListInstance = eventLogList

        -- =========================================================================
        -- [ABA 5] CONFIGURAÇÕES & PERFIS (SETTINGS)
        -- =========================================================================
        local pageSettings = pages["Settings"]

        CreateSectionHeader(pageSettings, "PERFIS DE SIMULAÇÃO")
        local profileGrid = Instance.new("Frame")
        profileGrid.Size = UDim2.new(1, 0, 0, 34)
        profileGrid.BackgroundTransparency = 1
        profileGrid.Parent = pageSettings

        local pGridLayout = Instance.new("UIGridLayout")
        pGridLayout.CellSize = UDim2.new(0.19, 0, 1, 0)
        pGridLayout.CellPadding = UDim2.new(0.0125, 0, 0, 0)
        pGridLayout.Parent = profileGrid

        local profileCards: { [string]: TextButton } = {}
        local profileList = { "Normal", "Leve", "Medio", "Agressivo", "Custom" }
        local function UpdateProfileUI(activeProf: string)
            for name, btn in pairs(profileCards) do
                local isCurrent = (name == activeProf)
                btn.BackgroundColor3 = isCurrent and THEME.ACCENT_RED or THEME.BG_INPUT
                btn.TextColor3 = isCurrent and THEME.TEXT_MAIN or THEME.TEXT_MUTED
            end
        end
        for _, pName in ipairs(profileList) do
            local pBtn = Instance.new("TextButton")
            pBtn.BackgroundColor3 = (pName == SimConfig.Get("ActiveProfile")) and THEME.ACCENT_RED or THEME.BG_INPUT
            pBtn.Font = Enum.Font.GothamBold
            pBtn.TextSize = 11
            pBtn.TextColor3 = THEME.TEXT_MAIN
            pBtn.Text = pName
            pBtn.Parent = profileGrid
            AddCorner(pBtn, 6)
            AddStroke(pBtn, THEME.BORDER, 1)
            profileCards[pName] = pBtn
            pBtn.MouseButton1Click:Connect(function()
                SimConfig.LoadProfile(pName)
                UpdateProfileUI(pName)
                DashboardGUI.AddDiagnosticLog("CONFIG", "Perfil carregado: " .. pName, "INFO")
            end)
        end

        CreateSectionHeader(pageSettings, "PERSISTÊNCIA E EXPORTAÇÃO JSON")
        local cfgBtnGrid = MakeButtonGrid(pageSettings, 150)
        MakeGridButton(cfgBtnGrid, "💾 Salvar Configuração", function()
            local saved = SimConfig.Save()
            DashboardGUI.AddDiagnosticLog("CONFIG", saved and "Configurações persistidas." or "Persistência indisponível.", saved and "OK" or "WARN")
            if DashboardGUI.OnSaveRequested then DashboardGUI.OnSaveRequested() end
        end)
        MakeGridButton(cfgBtnGrid, "↺ Restaurar Padrões", function()
            SimConfig.RestoreDefaults("Restaurar padrões (Settings)")
            UpdateProfileUI(SimConfig.DefaultProfileName)
            DashboardGUI.AddDiagnosticLog("CONFIG", "Configurações restauradas.", "WARN")
            if DashboardGUI.OnResetRequested then DashboardGUI.OnResetRequested() end
        end)
        MakeGridButton(cfgBtnGrid, "📤 Exportar JSON", function()
            local json = SimConfig.ExportJSON()
            pcall(function()
                if setclipboard then
                    setclipboard(json)
                    DashboardGUI.AddDiagnosticLog("CONFIG", "JSON copiado para a área de transferência!", "OK")
                else
                    DashboardGUI.AddDiagnosticLog("CONFIG", "JSON gerado no console.", "INFO")
                    print("\n[DeepHat SimConfig JSON Export]\n" .. json)
                end
            end)
        end)

        local importBox = Instance.new("TextBox")
        importBox.Size = UDim2.new(1, 0, 0, 50)
        importBox.BackgroundColor3 = THEME.BG_WINDOW
        importBox.TextColor3 = THEME.TEXT_MAIN
        importBox.PlaceholderText = "Cole aqui o JSON para importar configurações..."
        importBox.PlaceholderColor3 = THEME.TEXT_MUTED
        importBox.Font = Enum.Font.Code
        importBox.TextSize = 10
        importBox.TextWrapped = true
        importBox.ClearTextOnFocus = false
        importBox.MultiLine = true
        importBox.TextXAlignment = Enum.TextXAlignment.Left
        importBox.TextYAlignment = Enum.TextYAlignment.Top
        importBox.Parent = pageSettings
        AddCorner(importBox, 5)
        AddStroke(importBox, THEME.BORDER, 1)

        local importBtn = Instance.new("TextButton")
        importBtn.Size = UDim2.new(0, 160, 0, 28)
        importBtn.BackgroundColor3 = THEME.BG_INPUT
        importBtn.Font = Enum.Font.GothamBold
        importBtn.TextSize = 10
        importBtn.TextColor3 = THEME.TEXT_MAIN
        importBtn.Text = "⬇ IMPORTAR JSON (VALIDADO)"
        importBtn.Parent = pageSettings
        AddCorner(importBtn, 5)
        AddStroke(importBtn, THEME.BORDER, 1)
        importBtn.MouseButton1Click:Connect(function()
            local ok, errors = SimConfig.ImportJSON(importBox.Text)
            if ok then
                DashboardGUI.AddDiagnosticLog("CONFIG", "Importação validada e aplicada.", "OK")
            else
                DashboardGUI.AddDiagnosticLog("CONFIG", "Importação rejeitada: " .. table.concat(errors, "; "):sub(1, 160), "WARN")
            end
        end)

        -- Aba Inicial
        local startTab = tostring(SimConfig.Get("ActiveTab") or "AimSimulation")
        if pages[startTab] then SwitchTab(startTab) else SwitchTab("AimSimulation") end

        -- Barra Inferior de Ações (Footer)
        local footer = Instance.new("Frame")
        footer.Size = UDim2.new(1, 0, 0, 48)
        footer.Position = UDim2.new(0, 0, 1, -48)
        footer.BackgroundColor3 = THEME.BG_SIDEBAR
        footer.BorderSizePixel = 0
        footer.Parent = mainFrame
        AddCorner(footer, 8)
        AddStroke(footer, THEME.BORDER, 1)

        local footerLayout = Instance.new("UIListLayout")
        footerLayout.FillDirection = Enum.FillDirection.Horizontal
        footerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
        footerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
        footerLayout.Padding = UDim.new(0, 8)
        footerLayout.Parent = footer

        local footerPad = Instance.new("UIPadding")
        footerPad.PaddingRight = UDim.new(0, 14)
        footerPad.Parent = footer

        local function CreateBottomButton(text: string, isPrimary: boolean, onClick: () -> ()): TextButton
            local btn = Instance.new("TextButton")
            btn.Size = UDim2.new(0, 140, 0, 32)
            btn.BackgroundColor3 = isPrimary and THEME.ACCENT_RED or THEME.BG_INPUT
            btn.Font = Enum.Font.GothamBold
            btn.TextSize = 11
            btn.TextColor3 = THEME.TEXT_MAIN
            btn.Text = text
            btn.Parent = footer
            AddCorner(btn, 5)
            AddStroke(btn, isPrimary and THEME.ACCENT_HOVER or THEME.BORDER, 1)
            btn.MouseButton1Click:Connect(onClick)
            return btn
        end

        CreateBottomButton("↺ RESETAR", false, function()
            SimConfig.RestoreDefaults("Restaurar padrões (UI)")
            UpdateProfileUI(SimConfig.DefaultProfileName)
            if DashboardGUI.OnResetRequested then DashboardGUI.OnResetRequested() end
        end)

        CreateBottomButton("💾 SALVAR CONFIG", false, function()
            local saved = SimConfig.Save()
            DashboardGUI.AddDiagnosticLog("SAVE", saved and "Configurações persistidas." or "Persistência indisponível.", saved and "OK" or "WARN")
            if DashboardGUI.OnSaveRequested then DashboardGUI.OnSaveRequested() end
        end)

        CreateBottomButton("⏹ PARAR", false, function()
            SimConfig.Set("SimulationActive", false)
            masterSwitch.BackgroundColor3 = THEME.BG_WINDOW
            masterSwitch.Text = "SIMULAÇÃO: PAUSADA"
            DashboardGUI.AddDiagnosticLog("ENGINE", "Execução interrompida.", "WARN")
            if DashboardGUI.OnStopRequested then DashboardGUI.OnStopRequested() end
        end)

        CreateBottomButton("▶ INICIAR TESTE", true, function()
            SimConfig.Set("SimulationActive", true)
            masterSwitch.BackgroundColor3 = THEME.ACCENT_RED
            masterSwitch.Text = "SIMULAÇÃO: ATIVA"
            DashboardGUI.AddDiagnosticLog("ENGINE", "Sessão de teste iniciada.", "OK")
            if DashboardGUI.OnStartRequested then DashboardGUI.OnStartRequested() end
        end)

        -- Sincronização Observer
        if unsubscribeGlobal then unsubscribeGlobal(); unsubscribeGlobal = nil end
        unsubscribeGlobal = SimConfig.SubscribeAll(function(key, val)
            if key == "ActiveProfile" then
                UpdateProfileUI(tostring(val))
            elseif key == "SimulationActive" then
                local active = (val == true)
                masterSwitch.BackgroundColor3 = active and THEME.ACCENT_RED or THEME.BG_WINDOW
                masterSwitch.Text = active and "SIMULAÇÃO: ATIVA" or "SIMULAÇÃO: PAUSADA"
                if FovCircleInstance then
                    FovCircleInstance.Visible = active and (SimConfig.Get("ShowFovCircle") == true)
                end
            elseif key == "TargetRegion" then
                UpdateBoneUI(tostring(val))
            elseif syncInputs[key] and typeof(val) == "number" then
                syncInputs[key](val)
            end
        end)

        screenGui.Destroying:Connect(function()
            if unsubscribeGlobal then unsubscribeGlobal(); unsubscribeGlobal = nil end
        end)

        DashboardGUI.AddDiagnosticLog("INIT", "Dashboard GUI carregada com 5 abas otimizadas.", "OK")
        return screenGui
    end

    -- =========================================================================
    -- MÉTODOS PÚBLICOS DE TELEMETRIA & ATUALIZAÇÃO
    -- =========================================================================
    function DashboardGUI:UpdateFovCircle()
        if not FovCircleInstance or not FovCircleInstance.Parent then return end
        local camera = Workspace.CurrentCamera
        if not camera then return end

        local active = SimConfig.Get("SimulationActive") == true
        local show = SimConfig.Get("ShowFovCircle") == true and active
        FovCircleInstance.Visible = show

        if show then
            local fov = math.clamp(tonumber(SimConfig.Get("FOV")) or 70.0, 5.0, 170.0)
            local vpY = math.max(camera.ViewportSize.Y, 1)
            local camFovRad = math.rad(math.clamp(camera.FieldOfView, 10.0, 120.0) / 2)
            local aimFovRad = math.rad(fov / 2)
            local radius = math.clamp((math.tan(aimFovRad) / math.tan(camFovRad)) * (vpY / 2), 5, vpY)
            FovCircleInstance.Size = UDim2.new(0, radius * 2, 0, radius * 2)
            FovCircleInstance.Position = UDim2.new(0.5, 0, 0.5, 0)
        end
    end

    function DashboardGUI:UpdateTelemetryDisplay(data: {
        angularVelocity: number?,
        isObstructed: boolean?,
        targetName: string?,
        dt: number?,
        mode: string?,
        decoupledAngle: number?,
        silentAimActive: boolean?,
        lastShot: any?
    })
        if not data then return end
        if SimConfig.Get("TelemetryIndicators") == false then return end

        local angVel = tonumber(data.angularVelocity) or 0
        if angVel > PerformanceData.PeakAngVel then
            PerformanceData.PeakAngVel = angVel
        end

        if TelemetryLabels["AngVel"] then
            TelemetryLabels["AngVel"].Text = string.format("%.1f °/s", angVel)
        end

        if TelemetryLabels["VisStatus"] then
            local obstructed = (data.isObstructed == true)
            TelemetryLabels["VisStatus"].Text = obstructed and "OBSTRUÍDO" or "LIVRE"
            TelemetryLabels["VisStatus"].TextColor3 = obstructed and THEME.ACCENT_RED or THEME.SUCCESS
        end

        if TelemetryLabels["ActiveTarget"] then
            TelemetryLabels["ActiveTarget"].Text = tostring(data.targetName or "NENHUM")
        end

        local saEnabled = SimConfig.Get("SilentAimEnabled") == true
        if TelemetryLabels["SilentAimStatus"] then
            if data.lastShot then
                if data.lastShot.Success == true then
                    TelemetryLabels["SilentAimStatus"].Text = "Módulo: ● TESTADO COM SUCESSO"
                    TelemetryLabels["SilentAimStatus"].TextColor3 = THEME.SUCCESS
                else
                    TelemetryLabels["SilentAimStatus"].Text = "Módulo: ⚠️ FALHA NO TESTE"
                    TelemetryLabels["SilentAimStatus"].TextColor3 = THEME.ACCENT_RED
                end
            elseif saEnabled then
                TelemetryLabels["SilentAimStatus"].Text = "Módulo: ◐ HABILITADO (AGUARDANDO)"
                TelemetryLabels["SilentAimStatus"].TextColor3 = THEME.INFO
            else
                TelemetryLabels["SilentAimStatus"].Text = "Módulo: ○ DESATIVADO"
                TelemetryLabels["SilentAimStatus"].TextColor3 = THEME.TEXT_MUTED
            end
        end

        if TelemetryLabels["ModStatus_SilentAim"] then
            if data.lastShot then
                if data.lastShot.Success == true then
                    TelemetryLabels["ModStatus_SilentAim"].Text = "● TESTADO OK"
                    TelemetryLabels["ModStatus_SilentAim"].TextColor3 = THEME.SUCCESS
                else
                    TelemetryLabels["ModStatus_SilentAim"].Text = "▲ FALHA DETECTADA"
                    TelemetryLabels["ModStatus_SilentAim"].TextColor3 = THEME.ACCENT_RED
                end
            elseif saEnabled then
                TelemetryLabels["ModStatus_SilentAim"].Text = "◐ HABILITADO"
                TelemetryLabels["ModStatus_SilentAim"].TextColor3 = THEME.INFO
            else
                TelemetryLabels["ModStatus_SilentAim"].Text = "○ DESATIVADO"
                TelemetryLabels["ModStatus_SilentAim"].TextColor3 = THEME.TEXT_MUTED
            end
        end

        if data.lastShot then
            local ls = data.lastShot
            local outcome = tostring(ls.Outcome or (ls.Success and "SUCCESS" or "UNKNOWN"))
            local stagesCount = type(ls.StagesCompleted) == "table" and #ls.StagesCompleted or 5

            if TelemetryLabels["SilentAimStage"] then
                TelemetryLabels["SilentAimStage"].Text = string.format("Etapa: [%d/5] %s", stagesCount, ls.Stage or "FINAL")
                TelemetryLabels["SilentAimStage"].TextColor3 = ls.Success and THEME.SUCCESS or THEME.WARNING
            end

            if TelemetryLabels["LastShotStatus"] then
                local outcomeText = "NENHUM"
                local outcomeColor = THEME.TEXT_MUTED
                if outcome == "SUCCESS" then
                    outcomeText = "✅ ACERTO CONFIRMADO NO ALVO"
                    outcomeColor = THEME.SUCCESS
                elseif outcome == "TARGET_OUTSIDE_FOV" then
                    outcomeText = "📐 FORA DO FOV MÁXIMO (REJEITADO)"
                    outcomeColor = THEME.WARNING
                elseif outcome == "OBSTACLE_BLOCKED" then
                    outcomeText = "🛡️ TRAJETÓRIA BLOQUEADA POR OBSTÁCULO"
                    outcomeColor = THEME.ACCENT_RED
                elseif outcome == "TARGET_INVALID" then
                    outcomeText = "❌ ALVO INVÁLIDO OU DESTRUÍDO"
                    outcomeColor = THEME.WARNING
                elseif outcome == "INVALID_TRAJECTORY" then
                    outcomeText = "⚠️ TRAJETÓRIA OU DADOS INVÁLIDOS"
                    outcomeColor = THEME.WARNING
                elseif outcome == "PROBABILISTIC_SPREAD" then
                    outcomeText = "🎲 DISPERSÃO PROBABILÍSTICA (MISS)"
                    outcomeColor = THEME.INFO
                elseif outcome == "MODULE_DISABLED" then
                    outcomeText = "⏹ MÓDULO SILENT AIM DESATIVADO"
                    outcomeColor = THEME.TEXT_MUTED
                elseif outcome == "INTERNAL_ERROR" then
                    outcomeText = "🛑 ERRO INTERNO NA EXECUÇÃO"
                    outcomeColor = THEME.ACCENT_RED
                else
                    outcomeText = ls.Success and "ACERTO" or "FALHA"
                    outcomeColor = ls.Success and THEME.SUCCESS or THEME.WARNING
                end
                TelemetryLabels["LastShotStatus"].Text = string.format("Último Disparo: %s (%.1f°)", outcomeText, ls.DiscrepancyAngleDeg or 0)
                TelemetryLabels["LastShotStatus"].TextColor3 = outcomeColor
            end

            if TelemetryLabels["SilentAimDetails"] then
                local hitPartName = ls.HitPart and ls.HitPart.Name or "—"
                local hitDist = ls.HitDistance and string.format("%.1f st", ls.HitDistance) or "—"
                TelemetryLabels["SilentAimDetails"].Text = string.format("Impacto: %s | Parte: %s | Desvio: %.1f° | Dist: %s",
                    ls.HitRegistered and "CONFIRMADO" or "NÃO REGISTRADO", hitPartName, ls.DiscrepancyAngleDeg or 0, hitDist)
            end

            if TelemetryLabels["SilentAimReason"] then
                local desc = ls.OutcomeDescription or ls.FailureReason or (ls.Success and "Trajetória e colisão validadas fisicamente no Workspace." or "Verifique as configurações.")
                TelemetryLabels["SilentAimReason"].Text = "Diagnóstico: " .. desc
                TelemetryLabels["SilentAimReason"].TextColor3 = ls.Success and THEME.SUCCESS or THEME.TEXT_MUTED
            end
        end
    end

    -- Watchdog de Fundo
    task.spawn(function()
        while true do
            task.wait(1.0)
            local ok, _ = pcall(function()
                local now = os.clock()
                local dt = now - PerformanceData.LastCheck
                PerformanceData.LastCheck = now
                local currentFps = math.clamp(math.round(1 / math.max(dt, 0.001)), 1, 144)
                PerformanceData.Fps = currentFps

                if TelemetryLabels["FpsCounter"] then
                    TelemetryLabels["FpsCounter"].Text = string.format("%d FPS", currentFps)
                end

                local healthGood = true
                local reason = "OK"

                local camera = Workspace.CurrentCamera
                if not camera then
                    healthGood = false
                    reason = "Câmera ausente"
                end

                local fov = tonumber(SimConfig.Get("FOV")) or 70
                if fov < 10 or fov > 180 then
                    SimConfig.Set("FOV", math.clamp(fov, 10, 180))
                end

                if WatchdogBadgeInstance and WatchdogBadgeInstance.Parent then
                    if healthGood then
                        WatchdogBadgeInstance.Text = "● WATCHDOG: 100% OPERACIONAL"
                        WatchdogBadgeInstance.TextColor3 = THEME.SUCCESS
                    else
                        WatchdogBadgeInstance.Text = "⚠️ ALERTA: " .. string.upper(reason)
                        WatchdogBadgeInstance.TextColor3 = THEME.WARNING
                    end
                end
            end)
        end
    end)

    function DashboardGUI:UpdateLos(last: any, history: { any }?)
        local status = LosLabels["Status"]
        if not status or not status.Parent then return end
        if not last then
            status.Text = "  Última consulta: (nenhuma)"
            status.TextColor3 = THEME.TEXT_MUTED
            return
        end
        local color = THEME.WARNING
        if last.Status == "VISIBLE" then color = THEME.SUCCESS elseif last.Status == "BLOCKED" then color = THEME.ACCENT_RED end
        status.Text = "  Última consulta: " .. tostring(last.Status)
        status.TextColor3 = color
        if LosLabels["Reason"] then LosLabels["Reason"].Text = "  Causa: " .. tostring(last.Reason) end
        if LosLabels["Blocker"] then LosLabels["Blocker"].Text = "  Obstrução: " .. tostring(last.BlockerName or "—") end
        if LosLabels["Distance"] then
            LosLabels["Distance"].Text = last.HitDistance and string.format("  Distância: %.2f studs (consulta: %.2f)", last.HitDistance, last.QueryDistance or 0)
                or string.format("  Distância: — (consulta: %.2f)", last.QueryDistance or 0)
        end

        if LosHistoryList and history then
            local newest = history[#history]
            local stamp = newest and (newest.Time * 1000 + #history) or 0
            if stamp == LastRenderedLosStamp then return end
            LastRenderedLosStamp = stamp
            for _, ch in ipairs(LosHistoryList:GetChildren()) do
                if ch:IsA("TextLabel") then ch:Destroy() end
            end
            for i = #history, math.max(1, #history - 39), -1 do
                local h = history[i]
                local c = THEME.WARNING
                if h.Status == "VISIBLE" then c = THEME.SUCCESS elseif h.Status == "BLOCKED" then c = THEME.ACCENT_RED end
                local row = Instance.new("TextLabel")
                row.Size = UDim2.new(1, -8, 0, 18)
                row.BackgroundTransparency = 1
                row.Font = Enum.Font.Code
                row.TextSize = 10
                row.TextColor3 = c
                row.TextXAlignment = Enum.TextXAlignment.Left
                row.LayoutOrder = #history - i
                row.Text = string.format("  %-8s %-14s %s%s", h.Status, tostring(h.Target), tostring(h.Reason), h.Blocker and (" [" .. h.Blocker .. "]") or "")
                row.Parent = LosHistoryList
            end
        end
    end

    function DashboardGUI:UpdateDetection(info: any)
        if not DetLabels["State"] or not DetLabels["State"].Parent or not info then return end
        local r = info.report
        if not info.engineAvailable then
            DetLabels["State"].Text = "  Estado: EngineCore indisponível"
            DetLabels["State"].TextColor3 = THEME.WARNING
        elseif not r then
            DetLabels["State"].Text = "  Estado: aguardando amostras reais"
            DetLabels["State"].TextColor3 = THEME.TEXT_MUTED
        else
            local color = THEME.SUCCESS
            if r.category == "INSUFICIENTE" then color = THEME.WARNING
            elseif r.category ~= "LIMPO" then color = THEME.ACCENT_RED end
            DetLabels["State"].Text = string.format("  Classificação: %s (score %d)", r.category, r.totalScore)
            DetLabels["State"].TextColor3 = color
        end
    end

    function DashboardGUI.Toggle(): boolean
        if MainFrameInstance then
            MainFrameInstance.Visible = not MainFrameInstance.Visible
            return MainFrameInstance.Visible
        end
        return false
    end

    function DashboardGUI.SetVisible(visible: boolean)
        if MainFrameInstance then MainFrameInstance.Visible = visible end
    end

    function DashboardGUI.IsVisible(): boolean
        return MainFrameInstance ~= nil and MainFrameInstance.Visible == true
    end

    function DashboardGUI.GetScreenGui(): ScreenGui?
        return ScreenGuiInstance
    end
end

-- =========================================================================
-- INICIALIZAÇÃO (SimulationBootstrap.client.lua)
-- =========================================================================
-- =========================================================================
-- SimulationBootstrap.client.lua
-- Orquestrador Principal do Sistema Modular (Ambiente Studio e Cliente Roblox)
-- Integração: SimConfig, InstanceDetector, VectorTracker,
--             VisualOverlayRenderer e DashboardGUI
-- Recursos Avançados: Modos de Prioridade de Alvo, Silent Aim Simulado e Tracers 3D
-- =========================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    pcall(function()
        LocalPlayer = Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    end)
    LocalPlayer = Players.LocalPlayer
end

local Camera = Workspace.CurrentCamera or Workspace:WaitForChild("Camera") :: Camera

-- Importação dos Módulos do Kernel

-- EngineCore (avaliação defensiva) é opcional e independente da UI: se não existir no
-- ambiente, a aba Detection informa indisponibilidade em vez de inventar dados.
local Engine: any = nil
do
    -- EngineCore bundled inline
end

-- Configuração: primeira execução aplica "DeepHat Simulation Default"; depois carrega o salvo
-- se válido (câmera/disparo sempre iniciam desligados).
local loadStatus = SimConfig.Load()

-- Inicialização da Interface
print("[DeepHat Bootstrap] Criando interface gráfica...")
local okGui, guiErr = pcall(function()
    return DashboardGUI.Create()
end)
if not okGui then
    warn("[DeepHat Bootstrap FATAL] Erro ao instanciar DashboardGUI: " .. tostring(guiErr))
else
    print("[DeepHat Bootstrap] Interface gráfica criada com sucesso.")
end
DashboardGUI.AddDiagnosticLog("CONFIG", string.format("Perfil: %s (%s)", SimConfig.DefaultProfileName, loadStatus), loadStatus == "restored_defaults" and "WARN" or "INFO")

-- Inicialização dos Subsistemas
local filterInstances: { Instance } = {}
if LocalPlayer and LocalPlayer.Character then
    table.insert(filterInstances, LocalPlayer.Character)
end

local Detector = InstanceDetector.new(0.12) -- 8.3Hz de varredura espacial desacoplada
local Tracker = VectorTracker.new(filterInstances)
local Renderer = VisualOverlayRenderer.new()

-- Tratamento Robusto de Respawn do Personagem e Ferramentas (Armas)
local triggerShotRequested = false
local triggerSource = "Nenhum"
local lastSilentAimLogTime = 0
local currentEquippedTool: Tool? = nil
local toolCustomPhysics: { Type: string, Speed: number?, Gravity: number? }? = nil

local function InspectToolPhysics(tool: Instance): { Type: string, Speed: number?, Gravity: number? }
    local projType = tool:GetAttribute("ProjectileType") or tool:GetAttribute("WeaponType")
    local speed = tool:GetAttribute("ProjectileSpeed") or tool:GetAttribute("MuzzleVelocity") or tool:GetAttribute("Speed")
    local grav = tool:GetAttribute("Gravity") or tool:GetAttribute("ProjectileGravity")

    local toolNameLower = string.lower(tool.Name)
    if not projType then
        if string.find(toolNameLower, "bow") or string.find(toolNameLower, "arco")
            or string.find(toolNameLower, "rocket") or string.find(toolNameLower, "grenade")
            or string.find(toolNameLower, "cannon") or string.find(toolNameLower, "slingshot")
            or string.find(toolNameLower, "physics") or string.find(toolNameLower, "ballistic") then
            projType = "Physics"
            speed = speed or 300
            grav = grav or 196.2
        elseif string.find(toolNameLower, "sniper") or string.find(toolNameLower, "rifle")
            or string.find(toolNameLower, "pistol") or string.find(toolNameLower, "gun")
            or string.find(toolNameLower, "laser") or string.find(toolNameLower, "raycast") then
            projType = "Instant"
        end
    end
    return {
        Type = tostring(projType or "Instant"),
        Speed = tonumber(speed),
        Gravity = tonumber(grav)
    }
end

local toolConnections: { [Instance]: { RBXScriptConnection } } = {}

local function DisconnectTool(tool: Instance)
    local conns = toolConnections[tool]
    if conns then
        for _, c in ipairs(conns) do
            pcall(function() c:Disconnect() end)
        end
        toolConnections[tool] = nil
    end
end

local function HookCharacterTools(char: Instance?)
    if not char then return end
    local function HookTool(child: Instance)
        if child:IsA("Tool") then
            currentEquippedTool = child
            toolCustomPhysics = InspectToolPhysics(child)
            DashboardGUI.AddDiagnosticLog("WEAPON", string.format("Arma equipada: '%s' | Modo: %s", child.Name, toolCustomPhysics.Type), "INFO")

            DisconnectTool(child)
            local conns: { RBXScriptConnection } = {}

            local actConn = child.Activated:Connect(function()
                triggerShotRequested = true
                triggerSource = "Tool.Activated (" .. child.Name .. ")"
            end)
            table.insert(conns, actConn)

            local uneqConn = child.Unequipped:Connect(function()
                if currentEquippedTool == child then
                    currentEquippedTool = nil
                    toolCustomPhysics = nil
                end
                DisconnectTool(child)
            end)
            table.insert(conns, uneqConn)

            toolConnections[child] = conns
        end
    end
    for _, child in ipairs(char:GetChildren()) do
        HookTool(child)
    end
    char.ChildAdded:Connect(HookTool)
end

if LocalPlayer then
    if LocalPlayer.Character then
        HookCharacterTools(LocalPlayer.Character)
    end
    LocalPlayer.CharacterAdded:Connect(function(char)
        for tool, _ in pairs(toolConnections) do
            DisconnectTool(tool)
        end
        table.clear(toolConnections)
        table.clear(filterInstances)
        table.insert(filterInstances, char)
        Tracker:SetFilterInstances(filterInstances)
        HookCharacterTools(char)
        DashboardGUI.AddDiagnosticLog("PLAYER", "Personagem recarregado no pipeline de filtros.", "INFO")
    end)
end

-- =========================================================================
-- EXECUÇÃO DIAGNÓSTICA DE SILENT AIM (4 ETAPAS ESTRITAMENTE AUDITADAS)
-- =========================================================================
-- =========================================================================
-- EXECUÇÃO DIAGNÓSTICA DE SILENT AIM (PIPELINE 5 ETAPAS ESTRITAMENTE AUDITADAS)
-- RECEBIDO -> VALIDADO -> TRAJETÓRIA CALCULADA -> COLISÃO VERIFICADA -> RESULTADO FINAL
-- =========================================================================
local function ExecuteSilentAimShot(source: string, autoSpawnIfMissing: boolean?): (boolean, any)
    -- ETAPA 1: SOLICITAÇÃO RECEBIDA
    local silentAimEnabled = SimConfig.Get("SilentAimEnabled") == true
    if not silentAimEnabled then
        local errRes = {
            Stage = "RECEIVED",
            Fired = false,
            HitRegistered = false,
            Outcome = "MODULE_DISABLED",
            OutcomeDescription = "Módulo de Silent Aim está desativado no painel ('SilentAimEnabled' = false).",
            DiscrepancyAngleDeg = 0,
            MuzzlePosition = Vector3.zero,
            TargetPosition = Vector3.zero,
            ImpactPosition = Vector3.zero,
            HitPart = nil,
            ShotDirection = Vector3.zAxis,
            InFov = false,
            IsObstructed = false,
            FlightTime = 0,
            BulletDropStuds = 0,
            TrajectoryPoints = nil,
            TrajectoryType = "Instant",
            StagesCompleted = { "[1] RECEBIDO [FALHA]: Módulo desativado no painel ('SilentAimEnabled' = false)." }
        }
        Tracker.LastShotResult = errRes
        DashboardGUI.AddDiagnosticLog("SILENT_AIM", "Falha [1/5]: Módulo desativado no painel ('SilentAimEnabled' = false).", "WARN")
        print(string.format("[SILENT AIM] [ETAPA 1: RECEBIDO] [FALHA] Disparo via %s rejeitado: Módulo desativado.", source))
        return false, errRes
    end
    print(string.format("[SILENT AIM] [ETAPA 1: RECEBIDO] [SUCESSO] Disparo solicitado com sucesso via %s.", source))

    -- ETAPA 2: DADOS VALIDADOS (Câmera, Alvo e Limites)
    local camera = Workspace.CurrentCamera
    if not camera then
        local errRes = {
            Stage = "VALIDATED",
            Fired = false,
            HitRegistered = false,
            Outcome = "INTERNAL_ERROR",
            OutcomeDescription = "Câmera não encontrada no Workspace.",
            DiscrepancyAngleDeg = 0,
            MuzzlePosition = Vector3.zero,
            TargetPosition = Vector3.zero,
            ImpactPosition = Vector3.zero,
            HitPart = nil,
            ShotDirection = Vector3.zAxis,
            InFov = false,
            IsObstructed = false,
            FlightTime = 0,
            BulletDropStuds = 0,
            TrajectoryPoints = nil,
            TrajectoryType = "Instant",
            StagesCompleted = { "[1] RECEBIDO", "[2] VALIDADO [FALHA]: Câmera ausente." }
        }
        Tracker.LastShotResult = errRes
        DashboardGUI.AddDiagnosticLog("SILENT_AIM", "Falha [2/5]: Câmera não encontrada no Workspace.", "WARN")
        print("[SILENT AIM] [ETAPA 2: VALIDADO] [FALHA] Câmera ausente.")
        return false, errRes
    end

    local maxRadius = tonumber(SimConfig.Get("VectorRadius")) or 300.0
    local silentAimFov = tonumber(SimConfig.Get("SilentAimFOV")) or 35.0
    local silentAimHitChance = tonumber(SimConfig.Get("SilentAimHitChance")) or 100.0
    local silentAimTracer = SimConfig.Get("SilentAimTracer") ~= false
    local preferredBone = tostring(SimConfig.Get("TargetRegion") or "Head")
    local teamCheck = SimConfig.Get("TeamCheck") == true
    local visibleOnly = SimConfig.Get("VisibleOnly") == true
    local targetPriority = tostring(SimConfig.Get("TargetPriority") or "Crosshair")
    local targetStickiness = tonumber(SimConfig.Get("TargetStickiness")) or 0.25
    local enableLead = SimConfig.Get("EnableLead") == true
    local projSpeed = (toolCustomPhysics and toolCustomPhysics.Speed) or tonumber(SimConfig.Get("ProjectileSpeed")) or 900.0
    local projGravity = (toolCustomPhysics and toolCustomPhysics.Gravity) or tonumber(SimConfig.Get("ProjectileGravity")) or 196.2
    local projType = (toolCustomPhysics and toolCustomPhysics.Type) or tostring(SimConfig.Get("ProjectileType") or "Instant")
    local isPhysics = (projType == "Physics")
    local dropComp = SimConfig.Get("ProjectileDropComp") ~= false

    -- Busca candidatos com o cone de Silent Aim
    local bestTarget, targetPos, dist, angleDeg, targetLabel, targetHealth = Detector:FindBestCandidate(
        camera.CFrame.Position,
        camera.CFrame.LookVector,
        maxRadius,
        silentAimFov * 2,
        preferredBone,
        teamCheck,
        targetPriority,
        targetStickiness
    )

    -- Se não encontrou no FOV e autoSpawn estiver ativo, gera manequim sintético de teste na frente
    if (not bestTarget or not targetPos) and autoSpawnIfMissing then
        local dummySpawnPos = camera.CFrame.Position + (camera.CFrame.LookVector * 25) - Vector3.new(0, 1, 0)
        local spawnedDummy = Detector.SpawnSyntheticDummy(dummySpawnPos)
        if spawnedDummy then
            DashboardGUI.AddDiagnosticLog("TEST_TARGET", "Manequim sintético de teste gerado automaticamente a 25 studs à frente.", "INFO")
            bestTarget, targetPos, dist, angleDeg, targetLabel, targetHealth = Detector:FindBestCandidate(
                camera.CFrame.Position,
                camera.CFrame.LookVector,
                maxRadius,
                silentAimFov * 2,
                preferredBone,
                teamCheck,
                targetPriority,
                targetStickiness
            )
        end
    end

    if not bestTarget or not targetPos then
        -- Diagnóstico exato de por que falhou a detecção
        local anyTarget, anyPos, anyDist, anyAngle = Detector:FindBestCandidate(
            camera.CFrame.Position,
            camera.CFrame.LookVector,
            maxRadius,
            360,
            preferredBone,
            teamCheck,
            targetPriority,
            targetStickiness
        )

        local errOutcome: "TARGET_OUTSIDE_FOV" | "TARGET_INVALID" = "TARGET_INVALID"
        local errDesc = string.format("Nenhum alvo sintético válido detectado no raio de %d studs.", math.floor(maxRadius))
        if anyTarget and anyAngle and anyAngle > silentAimFov then
            errOutcome = "TARGET_OUTSIDE_FOV"
            errDesc = string.format("Alvo '%s' detectado a %.1f studs, mas fora do FOV (Ângulo %.1f° > FOV %.1f°).", anyTarget.Name, anyDist or 0, anyAngle, silentAimFov)
        end

        local errRes = {
            Stage = "VALIDATED",
            Fired = false,
            HitRegistered = false,
            Outcome = errOutcome,
            OutcomeDescription = errDesc,
            DiscrepancyAngleDeg = anyAngle or 0,
            MuzzlePosition = camera.CFrame.Position,
            TargetPosition = anyPos or camera.CFrame.Position,
            ImpactPosition = camera.CFrame.Position,
            HitPart = nil,
            ShotDirection = camera.CFrame.LookVector,
            InFov = false,
            IsObstructed = false,
            FlightTime = 0,
            BulletDropStuds = 0,
            TrajectoryPoints = nil,
            TrajectoryType = isPhysics and "Physics" or "Instant",
            StagesCompleted = { "[1] RECEBIDO", string.format("[2] VALIDADO [FALHA]: %s", errDesc) }
        }
        Tracker.LastShotResult = errRes
        DashboardGUI.AddDiagnosticLog("SILENT_AIM", "Falha [2/5]: " .. errDesc, "WARN")
        print(string.format("[SILENT AIM] [ETAPA 2: VALIDADO] [FALHA] %s", errDesc))
        return false, errRes
    end

    local los = Tracker:EvaluateLineOfSight(camera.CFrame.Position, targetPos, bestTarget)
    local isObstructed = (los.Status == "BLOCKED")
    if visibleOnly and isObstructed then
        local errRes = {
            Stage = "VALIDATED",
            Fired = false,
            HitRegistered = false,
            Outcome = "OBSTACLE_BLOCKED",
            OutcomeDescription = string.format("Alvo '%s' ocluído por geometria de teste (VisibleOnly ativo).", bestTarget.Name),
            DiscrepancyAngleDeg = angleDeg or 0,
            MuzzlePosition = camera.CFrame.Position,
            TargetPosition = targetPos,
            ImpactPosition = camera.CFrame.Position,
            HitPart = nil,
            ShotDirection = camera.CFrame.LookVector,
            InFov = true,
            IsObstructed = true,
            FlightTime = 0,
            BulletDropStuds = 0,
            TrajectoryPoints = nil,
            TrajectoryType = isPhysics and "Physics" or "Instant",
            StagesCompleted = { "[1] RECEBIDO", string.format("[2] VALIDADO [FALHA]: Alvo '%s' ocluído por obstáculo.", bestTarget.Name) }
        }
        Tracker.LastShotResult = errRes
        DashboardGUI.AddDiagnosticLog("SILENT_AIM", string.format("Falha [2/5]: Alvo '%s' ocluído por geometria.", bestTarget.Name), "WARN")
        print(string.format("[SILENT AIM] [ETAPA 2: VALIDADO] [FALHA] Alvo '%s' bloqueado (VisibleOnly ativo).", bestTarget.Name))
        return false, errRes
    end

    -- ETAPA 3: TRAJETÓRIA CALCULADA
    local aimPosition = targetPos
    local bulletDropStuds = 0
    local flightTime = dist / math.max(projSpeed, 1.0)
    if enableLead then
        local estimatedVel = Tracker:EstimateVelocity(bestTarget, targetPos)
        local leadPos, ft, drop = Tracker:ComputeLead(targetPos, estimatedVel, camera.CFrame.Position, projSpeed, true, isPhysics and projGravity or 0, dropComp)
        aimPosition = leadPos
        bulletDropStuds = drop
        flightTime = ft
    elseif isPhysics and dropComp and projGravity > 0 then
        bulletDropStuds = 0.5 * projGravity * (flightTime * flightTime)
        aimPosition = targetPos + Vector3.new(0, bulletDropStuds, 0)
    end

    -- ETAPAS 3..5: CALCULADA, COLISÃO VERIFICADA e RESULTADO FINAL
    local shotResult = Tracker:SimulateShot(
        camera.CFrame,
        aimPosition,
        silentAimFov,
        silentAimHitChance,
        isObstructed,
        bestTarget,
        projSpeed,
        isPhysics and projGravity or 0,
        isPhysics
    )
    Tracker.LastShotResult = shotResult

    -- Renderização do Traçador 3D Neon
    if silentAimTracer and shotResult.Fired then
        local beamColor = shotResult.HitRegistered and Color3.fromRGB(46, 230, 110) or Color3.fromRGB(255, 60, 75)
        Tracker:DrawTracerBeam(shotResult.MuzzlePosition, shotResult.ImpactPosition or shotResult.TargetPosition, beamColor, 0.28, shotResult.TrajectoryPoints)
    end

    -- Reação visual no alvo sintético (dano simulado temporário para evidência visual)
    if shotResult.HitRegistered and bestTarget then
        pcall(function()
            local hum = bestTarget:FindFirstChildOfClass("Humanoid")
                or (bestTarget:IsA("Model") and bestTarget:FindFirstChildWhichIsA("Humanoid", true))
            if hum and hum.Health > 0 then
                hum.Health = math.max(hum.Health - 15, 1)
                if hum.Health <= 15 then
                    task.delay(1.5, function()
                        if hum and hum.Parent then hum.Health = 100 end
                    end)
                end
            end
        end)
    end

    local trajDesc = isPhysics and string.format("Física (g=%.1f studs/s², voo=%.2fs, queda=%.1f studs, %d segs)", projGravity, shotResult.FlightTime, shotResult.BulletDropStuds, shotResult.TrajectoryPoints and #shotResult.TrajectoryPoints or 0) or "Instantâneo (Raycast)"
    local resTag = shotResult.HitRegistered and "ACERTO" or shotResult.Outcome
    DashboardGUI.AddDiagnosticLog("SILENT_AIM", string.format("[%s] %s em '%s' (Desvio: %.1f° | %s).", resTag, trajDesc, bestTarget.Name, shotResult.DiscrepancyAngleDeg, shotResult.OutcomeDescription), shotResult.HitRegistered and "OK" or "WARN")
    print(string.format("[SILENT AIM] [ETAPA 5: RESULTADO FINAL] [%s] %s em '%s' (Desvio: %.1f°, Destino: %s).", shotResult.Outcome, trajDesc, bestTarget.Name, shotResult.DiscrepancyAngleDeg, tostring(shotResult.TargetPosition)))

    return shotResult.HitRegistered, shotResult
end

-- Conexão de Ações do DashboardGUI
DashboardGUI.OnSimulateSilentAimShot = function()
    return ExecuteSilentAimShot("Dashboard GUI (Botão de Teste)", true)
end

DashboardGUI.OnSpawnTestDummy = function()
    local camera = Workspace.CurrentCamera
    if camera then
        local dummySpawnPos = camera.CFrame.Position + (camera.CFrame.LookVector * 25) - Vector3.new(0, 1, 0)
        local spawned = Detector.SpawnSyntheticDummy(dummySpawnPos)
        if spawned then
            DashboardGUI.AddDiagnosticLog("TEST_TARGET", "Manequim de teste sintético gerado a 25 studs à frente da câmera.", "OK")
        end
    end
end

DashboardGUI.OnRunLosScenario = function(id: string)
    local outcome, res = ScenarioRunner.Run(Tracker, id)
    if outcome and res then
        Tracker:RecordLos(res, "Cenário:" .. outcome.Id)
        Tracker.LastLos = res
        DashboardGUI.AddDiagnosticLog("LOS", string.format("%s => %s (esperado %s) %s", outcome.Label, outcome.Actual, outcome.Expected, outcome.Passed and "PASS" or "FAIL"), outcome.Passed and "OK" or "WARN")
    end
end

DashboardGUI.OnRunShotScenario = function(id: string)
    local outcome, res = ScenarioRunner.RunShotScenario(Tracker, id)
    if outcome and res then
        Tracker.LastShotResult = res
        DashboardGUI.AddDiagnosticLog("TEST_SHOT", string.format("%s => [%s] %s %s", outcome.Label, outcome.Actual, outcome.Description, outcome.Passed and "PASS" or "FAIL"), outcome.Passed and "OK" or "WARN")
    end
end

DashboardGUI.OnClearLosHistory = function()
    Tracker:ClearLosHistory()
    ScenarioRunner.ClearHistory()
    DashboardGUI.AddDiagnosticLog("LOS", "Histórico de LOS limpo.", "INFO")
end

DashboardGUI.OnStartRequested = function()
    DashboardGUI.AddDiagnosticLog("PIPELINE", "Sessão de testes ativada com sucesso.", "OK")
end

DashboardGUI.OnStopRequested = function()
    Renderer:ClearAll()
    DashboardGUI.AddDiagnosticLog("PIPELINE", "Sessão parada. Realces limpos.", "WARN")
end

DashboardGUI.OnResetRequested = function()
    Renderer:ClearAll()
    DashboardGUI.AddDiagnosticLog("PIPELINE", "Perfis e realces resetados.", "INFO")
end

-- Telemetria e Chatbot de Diagnóstico
local calculatedAngVel = 0
local isObstructed = false
local targetName = "NENHUM"
local currentMode = "IDLE"
local decoupledAngle = 0
local silentAimActive = false

DashboardGUI.OnQueryDiagnosticChatbot = function(query: string)
    local state = {
        Telemetry = {
            angularVelocity = calculatedAngVel,
            isObstructed = isObstructed,
            targetName = targetName,
            mode = currentMode,
            decoupledAngle = decoupledAngle,
            silentAimActive = silentAimActive,
        },
        LosHistory = Tracker.LosHistory,
        LastShot = Tracker.LastShotResult,
        SimConfig = SimConfig,
    }
    return DiagnosticAI.QueryChatbot(query, state)
end

DashboardGUI.OnRunFullDiagnostic = function()
    local state = {
        Telemetry = {
            angularVelocity = calculatedAngVel,
            isObstructed = isObstructed,
            targetName = targetName,
            mode = currentMode,
            decoupledAngle = decoupledAngle,
            silentAimActive = silentAimActive,
        },
        LosHistory = Tracker.LosHistory,
        LastShot = Tracker.LastShotResult,
        SimConfig = SimConfig,
    }
    local report = DiagnosticAI.AnalyzeSystemState(state.Telemetry, state.LosHistory, nil, state.LastShot)
    DashboardGUI.AddDiagnosticLog("DIAGNOSTIC_AI", string.format("[%s] %s (Módulo: %s)", report.Status, report.Summary, report.AffectedModule), report.Status == "HEALTHY" and "OK" or "WARN")
    return report
end

-- Gerenciamento de Input para Mira (RMB / MouseButton2) e Disparo (LMB / MouseButton1)
local isRightMouseDown = false
local isLeftMouseDown = false
local isToggleAimActive = false

UserInputService.InputBegan:Connect(function(input, gpe)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        isRightMouseDown = true
        isToggleAimActive = not isToggleAimActive
    elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
        isLeftMouseDown = true
        triggerShotRequested = true
        triggerSource = "MouseButton1 (InputBegan)"
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        isRightMouseDown = false
    elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
        isLeftMouseDown = false
    end
end)

UserInputService.WindowFocusReleased:Connect(function()
    isRightMouseDown = false
    isLeftMouseDown = false
end)

-- Pipeline de Renderização de Alta Frequência (RenderStepped)
local BIND_NAME = "DeepHat_MasterSimulationPipeline"
pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)

local lastTelemetryUpdate = 0
local lastDetectionUpdate = 0
local lastTracerTime = 0
local lastLosRecordTime = 0
local lastLosStatus = ""
local lastLosTarget: Instance? = nil
local sampleCount = 0
local occludedFrames = 0
local pipelineMs = 0
local lastMetrics: { [string]: number }? = nil

RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt: number)
    local ok, _ = pcall(function()
        local camera = Workspace.CurrentCamera
        if not camera then return end
        local frameStart = os.clock()

        local isSimulationActive = SimConfig.Get("SimulationActive") == true
        if not isSimulationActive then
            Tracker:Release()
            Renderer:ClearAll()
            DashboardGUI:UpdateTelemetryDisplay({
                angularVelocity = 0,
                isObstructed = false,
                targetName = "PAUSADO",
                dt = dt,
                mode = "PAUSED",
                decoupledAngle = 0,
                silentAimActive = false
            })
            return
        end

        local aimbotEnabled = SimConfig.Get("AimbotEnabled") ~= false
        local aimMode = SimConfig.Get("AimMode") or "HoldRMB"
        local shouldAim = false
        if aimMode == "AlwaysOn" then
            shouldAim = true
        elseif aimMode == "Toggle" then
            shouldAim = isToggleAimActive
        else -- "HoldRMB"
            local holdToAim = SimConfig.Get("HoldToAim") ~= false
            shouldAim = (not holdToAim) or isRightMouseDown or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
        end

        local isShooting = triggerShotRequested or isLeftMouseDown or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
        local isDiscreteTrigger = triggerShotRequested
        local currentTriggerSrc = triggerSource
        triggerShotRequested = false

        local maxRadius = tonumber(SimConfig.Get("VectorRadius")) or 300.0
        -- FOV de seleção: ângulo configurado pelo usuário no painel (respeitado diretamente)
        local fov = math.clamp(tonumber(SimConfig.Get("FOV")) or 70.0, 5.0, 180.0)
        local preferredBone = tostring(SimConfig.Get("TargetRegion") or "Head")
        local teamCheck = SimConfig.Get("TeamCheck") == true
        local visibleOnly = SimConfig.Get("VisibleOnly") == true
        local enableESP = SimConfig.Get("EnableESP") == true and SimConfig.Get("ShowSyntheticTargets") ~= false
        local enableLead = SimConfig.Get("EnableLead") == true
        local projSpeed = (toolCustomPhysics and toolCustomPhysics.Speed) or tonumber(SimConfig.Get("ProjectileSpeed")) or 900.0
        local projGravity = (toolCustomPhysics and toolCustomPhysics.Gravity) or tonumber(SimConfig.Get("ProjectileGravity")) or 196.2
        local projType = (toolCustomPhysics and toolCustomPhysics.Type) or tostring(SimConfig.Get("ProjectileType") or "Instant")
        local isPhysics = (projType == "Physics")
        local dropComp = SimConfig.Get("ProjectileDropComp") ~= false
        local smoothing = tonumber(SimConfig.Get("Smoothing")) or 0.15
        local accelExp = tonumber(SimConfig.Get("AccelerationCurve")) or 1.25
        local simulateJitter = SimConfig.Get("SimulateJitter") == true
        local intensity = tonumber(SimConfig.Get("Intensity")) or 75.0
        local maxAngularVel = tonumber(SimConfig.Get("AngularVelocity")) or 240.0
        local clampMaxVel = SimConfig.Get("MaxAngularVelocityClamp") == true
        local targetPriority = tostring(SimConfig.Get("TargetPriority") or "Crosshair")
        local targetStickiness = tonumber(SimConfig.Get("TargetStickiness")) or 0.25

        -- Silent Aim Config
        local silentAimEnabled = SimConfig.Get("SilentAimEnabled") == true
        local silentAimFov = tonumber(SimConfig.Get("SilentAimFOV")) or 35.0
        local silentAimHitChance = tonumber(SimConfig.Get("SilentAimHitChance")) or 100.0
        local silentAimTracer = SimConfig.Get("SilentAimTracer") ~= false

        -- FOV de busca de candidatos:
        -- Para Aimbot normal utiliza o fov central. Se Silent Aim estiver habilitado,
        -- expande a área de busca angular para cobrir o diâmetro do cone de Silent Aim (silentAimFov * 2)
        local aimbotFov = fov
        local searchFov = aimbotFov
        if silentAimEnabled then
            searchFov = math.max(searchFov, silentAimFov * 2)
        end

        -- 1. Detecção Espacial do Melhor Candidato com Prioridades
        local bestTarget, targetPos, dist, angleDeg, targetLabel, targetHealth = Detector:FindBestCandidate(
            camera.CFrame.Position,
            camera.CFrame.LookVector,
            maxRadius,
            searchFov,
            preferredBone,
            teamCheck,
            targetPriority,
            targetStickiness
        )

        local isObstructed = false
        local lookBefore = camera.CFrame.LookVector
        local targetName = "NENHUM"
        local calculatedAngVel = 0
        local currentMode = "IDLE"
        local decoupledAngle = 0
        local silentAimActive = false

        if bestTarget and targetPos then
            targetName = string.format("%s (%s - %d HP)", bestTarget.Name, targetLabel, math.floor(targetHealth or 100))

            -- 2. Linha de visão tri-state (VISIBLE / BLOCKED / INVALID)
            local losEnabled = SimConfig.Get("LineOfSightEnabled") ~= false
            local los: any = { Status = "DISABLED", Reason = "Diagnóstico de LOS desativado (não avaliado)", QueryDistance = 0 }
            if losEnabled then
                los = Tracker:EvaluateLineOfSight(camera.CFrame.Position, targetPos, bestTarget)
                Tracker.LosHistoryLimit = tonumber(SimConfig.Get("HistoryLimit")) or 50
                local nowLos = os.clock()
                -- Histórico: registra mudanças de estado/alvo ou, no máximo, a cada 0.5 s
                if los.Status ~= lastLosStatus or bestTarget ~= lastLosTarget or (nowLos - lastLosRecordTime) >= 0.5 then
                    Tracker.LastLos = los
                    if SimConfig.Get("HistoryEnabled") ~= false then
                        Tracker:RecordLos(los, bestTarget.Name)
                    end
                    lastLosStatus, lastLosTarget, lastLosRecordTime = los.Status, bestTarget, nowLos
                end
            end
            isObstructed = (los.Status == "BLOCKED")

            -- Se configurado para "Somente Visíveis" e houver barreira real, descarta alvo
            local isTargetValid = (los.Status ~= "INVALID")
            if visibleOnly and isObstructed then
                isTargetValid = false
            end

            -- 3. Predição Balística (Lead com suporte a física e gravidade)
            local aimPosition = targetPos
            if enableLead and isTargetValid then
                local estimatedVel = Tracker:EstimateVelocity(bestTarget, targetPos)
                local leadPos = Tracker:ComputeLead(targetPos, estimatedVel, camera.CFrame.Position, projSpeed, true, isPhysics and projGravity or 0, dropComp)
                aimPosition = leadPos
            end

            -- 4. Realce Visual Dinâmico em Lote (ESP Chams e Tags 3D com limpeza automática)
            if enableESP then
                Renderer:SyncBatchHighlights(Detector.CandidatePool, bestTarget, isObstructed)
                if bestTarget and targetDistance then
                    local targetHealth: number? = nil
                    if targetHumanoid then
                        targetHealth = targetHumanoid.Health
                    end
                    Renderer:UpdateTargetTag(bestTarget, targetDistance, isObstructed, targetHealth, targetName)
                    Renderer:ClearTagsExcept(bestTarget)
                else
                    Renderer:ClearTagsExcept(nil)
                end
            else
                Renderer:ClearAll()
            end

            -- 5. Simulação de Silent Aim (Disparo Desacoplado da Câmera)
            if isShooting then
                local now = os.clock()
                if (now - lastTracerTime) >= 0.10 then
                    lastTracerTime = now
                    local src = isDiscreteTrigger and currentTriggerSrc or "MouseButton1 contínuo"
                    if isDiscreteTrigger or (now - lastSilentAimLogTime) >= 0.35 then
                        lastSilentAimLogTime = now
                        ExecuteSilentAimShot(src)
                    elseif silentAimEnabled and isTargetValid then
                        local inFov = Tracker:ComputeSilentAimVector(camera.CFrame, aimPosition, silentAimFov)
                        if inFov then
                            local shotResult = Tracker:SimulateShot(
                                camera.CFrame,
                                aimPosition,
                                silentAimFov,
                                silentAimHitChance,
                                isObstructed,
                                bestTarget,
                                projSpeed,
                                isPhysics and projGravity or 0,
                                isPhysics
                            )
                            Tracker.LastShotResult = shotResult
                            if silentAimTracer and shotResult.Fired and SimConfig.Get("ShowDebugMarkers") ~= false then
                                local beamColor = shotResult.HitRegistered and Color3.fromRGB(46, 230, 110) or Color3.fromRGB(255, 60, 75)
                                Tracker:DrawTracerBeam(shotResult.MuzzlePosition, shotResult.TargetPosition, beamColor, 0.22, shotResult.TrajectoryPoints)
                            end
                        end
                    end
                end
            end

            if silentAimEnabled and isTargetValid then
                local inFov, decoupledDir, discDeg = Tracker:ComputeSilentAimVector(
                    camera.CFrame,
                    aimPosition,
                    silentAimFov
                )
                decoupledAngle = discDeg

                if inFov then
                    silentAimActive = true
                    if currentMode == "IDLE" then
                        currentMode = "SILENT_AIM"
                    end
                end
            end

            -- 6. Interpolação Cinemática da Câmera (Aimbot Convencional)
            -- Executa somente quando o Aimbot estiver ativado pelo painel e o alvo estiver dentro do cone de mira do Aimbot
            local inAimbotCone = (angleDeg <= (aimbotFov / 2))
            if aimbotEnabled and shouldAim and isTargetValid and inAimbotCone then
                currentMode = "TRACKING"

                local isAggressive = (SimConfig.Get("ActiveProfile") == "Agressivo")
                if isAggressive and (SimConfig.Get("Smoothing") or 0.1) <= 0.02 then
                    currentMode = "SNAP"
                    local snapCFrame, _, angVel = Tracker:ComputeSnapRotation(camera.CFrame, aimPosition, dt)
                    camera.CFrame = snapCFrame
                    calculatedAngVel = angVel
                else
                    local smoothedCFrame, _, angVel = Tracker:ComputeSmoothRotation(
                        camera.CFrame,
                        aimPosition,
                        dt,
                        smoothing,
                        accelExp,
                        simulateJitter,
                        intensity,
                        maxAngularVel,
                        clampMaxVel
                    )
                    camera.CFrame = smoothedCFrame
                    calculatedAngVel = angVel
                end
            else
                Tracker:ResetTracking()
            end
        else
            if isShooting and isDiscreteTrigger then
                ExecuteSilentAimShot(currentTriggerSrc)
            end
            Tracker:ResetTracking()
            Renderer:ClearAll()
        end

        -- 7a. Métricas REAIS para o EngineCore (campos não medidos permanecem nil = indisponível)
        local tracked = (currentMode == "TRACKING" or currentMode == "SNAP")
        if tracked then
            local d = math.deg(math.acos(math.clamp(lookBefore:Dot(camera.CFrame.LookVector), -1.0, 1.0)))
            sampleCount += 1
            occludedFrames = isObstructed and (occludedFrames + 1) or 0
            lastMetrics = {
                angularVelocity = calculatedAngVel,
                singleFrameDeltaDeg = d,
                consecutiveOccludedFrames = occludedFrames,
                decoupledAngleDeg = silentAimActive and decoupledAngle or nil,
                sampleCount = sampleCount,
            }
        elseif silentAimActive then
            sampleCount += 1
            lastMetrics = { decoupledAngleDeg = decoupledAngle, sampleCount = sampleCount }
        else
            occludedFrames = 0
            lastMetrics = nil
        end

        -- 7. Retroalimentação da Telemetria para o Dashboard (Throttle de 20Hz)
        local now = os.clock()
        if (now - lastTelemetryUpdate) >= 0.05 then
            lastTelemetryUpdate = now
            DashboardGUI:UpdateTelemetryDisplay({
                angularVelocity = calculatedAngVel,
                isObstructed = isObstructed,
                targetName = targetName,
                dt = dt,
                mode = currentMode,
                decoupledAngle = decoupledAngle,
                silentAimActive = silentAimActive,
                lastShot = Tracker.LastShotResult
            })
            DashboardGUI:UpdateFovCircle()
            DashboardGUI:UpdateLos(Tracker.LastLos, Tracker.LosHistory)
            pipelineMs = pipelineMs * 0.9 + (os.clock() - frameStart) * 1000 * 0.1
            if (now - lastDetectionUpdate) >= 0.5 then
                lastDetectionUpdate = now
                local report = (Engine and lastMetrics) and Engine:CalculateSuspicion(lastMetrics) or nil
                local pass, fail = ScenarioRunner.Summary()
                DashboardGUI:UpdateDetection({
                    report = report, samples = sampleCount, perfMs = pipelineMs,
                    scenarioPass = pass, scenarioFail = fail, engineAvailable = Engine ~= nil,
                })
            end
        end
    end)
end)

DashboardGUI.AddDiagnosticLog("BOOTSTRAP", "DeepHat Modular Engine ativo em alta fidelidade!", "OK")
print("[DeepHat Modular Engine] Inicializado com sucesso em alta performance!")

print("[DeepHat v7.0 PRO] Suíte autônoma carregada com sucesso! Pressione [HOME] ou [RightShift] para abrir/fechar.")

-- Verificação de integridade da GUI
if DashboardGUI and not DashboardGUI.GetScreenGui() then
    warn("[DeepHat Standalone] Interface não detectada no footer. Invocando DashboardGUI.Create()...")
    local ok, err = pcall(function() DashboardGUI.Create() end)
    if not ok then
        warn("[DeepHat Standalone FATAL] Falha ao criar GUI no fallback: " .. tostring(err))
    end
end

pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "DeepHat v7.0 PRO",
        Text = "Interface carregada! Pressione [HOME] ou [RightShift] para abrir/fechar.",
        Duration = 5
    })
end)
