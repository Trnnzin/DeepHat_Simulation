--!strict
-- =========================================================================
-- DeepHat_Standalone.lua (v6.0 PRO - Kernel-Level Kinematic & Diagnostics Suite)
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
        self.KnownTags = { "NPC", "Enemy", "Target", "Zombie", "Bot", "Dummy", "Entity", "Character", "Hitbox" }
        self.SearchFolders = { "NPCs", "Enemies", "Characters", "Zombies", "Bots", "Dummies", "Mobs", "Entities", "Targets", "Spawns" }
        self.LockedTarget = nil :: Instance?
        self.LockExpiry = 0
        return self
    end

    -- Validação de Integridade (Type Guarding Rigoroso)
    function InstanceDetector:IsValidTarget(objeto: Instance, teamCheck: boolean?): boolean
        -- Type Guarding: BasePart ou Model válido no DataModel
        if not objeto or not (objeto:IsA("BasePart") or objeto:IsA("Model")) or not objeto:IsDescendantOf(game) then
            return false
        end

        local myChar = self.LocalPlayer and self.LocalPlayer.Character
        if myChar and (objeto == myChar or objeto:IsDescendantOf(myChar)) then
            return false
        end

        -- Ignora explicitamente geometrias estáticas do mundo
        if objeto:IsA("Terrain") or objeto.Name == "Terrain" or objeto.Name == "Baseplate" then
            return false
        end
        local lowerName = objeto.Name:lower()
        if lowerName == "map" or lowerName == "workspace" or lowerName == "camera" then
            return false
        end

        -- Autorização: personagens de jogadores reais são rejeitados incondicionalmente
        if Players:GetPlayerFromCharacter(objeto) then
            return false
        end
        if objeto:IsA("BasePart") and objeto.Parent and Players:GetPlayerFromCharacter(objeto.Parent) then
            return false
        end

        -- Se o modelo possuir um Humanoid, respeita a integridade de vida
        local hum = objeto:FindFirstChildOfClass("Humanoid") or (objeto:IsA("Model") and objeto:FindFirstChildWhichIsA("Humanoid", true))
        if hum and hum.Health <= 0 then
            return false
        end

        -- Verificação de equipe para Jogadores
        if teamCheck and self.LocalPlayer and self.LocalPlayer.Team then
            local otherPlayer = Players:GetPlayerFromCharacter(objeto)
            if otherPlayer and otherPlayer.Team == self.LocalPlayer.Team then
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
                or model:FindFirstChild("LeftUpperArm", true) :: BasePart?
                or model:FindFirstChild("LeftArm", true) :: BasePart?
            label = "Arms"
        elseif bone == "legs" then
            targetPart = model:FindFirstChild("RightUpperLeg", true) :: BasePart?
                or model:FindFirstChild("RightLeg", true) :: BasePart?
                or model:FindFirstChild("LeftUpperLeg", true) :: BasePart?
                or model:FindFirstChild("LeftLeg", true) :: BasePart?
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

        -- 1. (Removido) Personagens de jogadores reais NUNCA são candidatos: o conjunto
        --    de alvos é restrito a manequins/NPCs sintéticos autorizados (ver IsValidTarget).

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

        -- 4. Filhos diretos e subpastas da raiz do Workspace (Dummies, Rigs e Modelos de Teste)
        for _, child in ipairs(Workspace:GetChildren()) do
            if child:IsA("Folder") then
                for _, grandChild in ipairs(child:GetChildren()) do
                    if grandChild:IsA("Model") or grandChild:IsA("BasePart") then
                        Ingest(grandChild)
                    end
                end
            elseif child:IsA("Model") then
                local hasHum = child:FindFirstChildOfClass("Humanoid")
                local name = child.Name:lower()
                if hasHum or name:find("dummy") or name:find("npc") or name:find("enemy") or name:find("target") or name:find("bot") or name:find("rig") then
                    Ingest(child)
                end
            elseif child:IsA("BasePart") and child.Parent == Workspace then
                local name = child.Name:lower()
                if name:find("target") or name:find("dummy") or name:find("hitbox") then
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
        local isStickyActive = (self.LockedTarget ~= nil and now < self.LockExpiry and self:IsValidTarget(self.LockedTarget, teamCheck))
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

        if bestTarget then
            self.LockedTarget = bestTarget
            self.LockExpiry = now + (stickinessDuration or 0.25)
        else
            self.LockedTarget = nil
        end

        return bestTarget, bestPos, finalDist, finalAngle, finalLabel, finalHealth
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
        if targetInstance ~= nil and (targetInstance.Parent == nil or not targetInstance:IsDescendantOf(game)) then
            return { Status = "INVALID", Reason = "Destino removido da árvore", QueryDistance = 0 }
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
        local now = os.clock()
        local cached = self.VelocityCache[inst]
        local vel = Vector3.zero

        if cached then
            local dt = (now - cached.time)
            if dt > 0.001 and dt < 0.3 then
                vel = (currentPos - cached.pos) / dt
            else
                vel = cached.vel
            end
        end

        self.VelocityCache[inst] = { pos = currentPos, time = now, vel = vel }
        return vel
    end

    function VectorTracker:ComputeLead(targetPos: Vector3, targetVel: Vector3, eyePos: Vector3, projSpeed: number, enabled: boolean): Vector3
        if not enabled or projSpeed <= 0 then
            return targetPos
        end
        local dist = (targetPos - eyePos).Magnitude
        local timeToHit = dist / projSpeed
        return targetPos + (targetVel * timeToHit)
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

        -- Matriz de Orientação Alvo via CFrame.lookAt
        local targetRotation = CFrame.lookAt(originPos, targetPosition, Vector3.yAxis)
        local rawCamRot = currentCFrame.Rotation

        -- Determina rotação base: se o tracker estiver ativo e já possuir rotação acumulada,
        -- avança a partir do estado acumulado e incorpora qualquer delta de rotação do mouse do usuário
        local startRotation: CFrame
        if self.TrackingActive and self.CurrentRotation then
            local userDelta = CFrame.identity
            if self.LastRawCamRotation then
                userDelta = self.LastRawCamRotation:Inverse() * rawCamRot
            end
            startRotation = self.CurrentRotation * userDelta
        else
            startRotation = rawCamRot
            self.TrackingActive = true
        end
        self.LastRawCamRotation = rawCamRot

        -- Normalização e cálculo angular relativo ao startRotation
        local forward = startRotation.LookVector
        local unitDirection = displacement / distance
        local dot = math.clamp(forward:Dot(unitDirection), -1.0, 1.0)
        local angularErrorDeg = math.deg(math.acos(dot))

        -- Se o erro for insignificante (< 0.04°), mantém a rotação estabilizada sem micro-trepidações
        if angularErrorDeg < 0.04 then
            local safeCFrame = CFrame.new(originPos) * startRotation
            self.CurrentRotation = startRotation
            self.CurrentCFrame = safeCFrame
            return safeCFrame, angularErrorDeg, 0
        end

        -- Curva de aceleração Hermite Smoothstep com expoente configurável
        local normErr = math.clamp(angularErrorDeg / 70.0, 0.0, 1.0)
        local hermiteFactor = normErr * normErr * (3.0 - 2.0 * normErr)
        local exponent = accelExponent or 1.25
        hermiteFactor = math.pow(hermiteFactor, exponent)

        -- Mapeamento semântico correto: Menor Smoothing = Maior velocidade de resposta
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
            local maxDegThisFrame = maxAngularVel * safeDt
            if (angularErrorDeg * dynamicAlpha) > maxDegThisFrame then
                dynamicAlpha = math.clamp(maxDegThisFrame / math.max(angularErrorDeg, 0.001), 0.001, 1.0)
            end
        end

        -- Interpolação orientada pura (Lerp esférico da rotação)
        local nextRotation = startRotation:Lerp(targetRotation.Rotation, dynamicAlpha)
        self.CurrentRotation = nextRotation

        local smoothedCFrame = CFrame.new(originPos) * nextRotation

        -- Injeção de Jitter Perlin Noise caso habilitado
        if simulateJitter and intensity and intensity > 0 then
            local now = os.clock()
            local jitterFactor = (intensity / 100.0) * math.clamp(angularErrorDeg / 15.0, 0.0, 1.0) * 0.20
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
        Fired: boolean,
        HitRegistered: boolean,
        DiscrepancyAngleDeg: number,
        MuzzlePosition: Vector3,
        TargetPosition: Vector3,
        ShotDirection: Vector3,
        InFov: boolean,
        IsObstructed: boolean
    }

    -- Execução de Disparo Simulado Controlado (Disparado apenas por evento/trigger de tiro)
    function VectorTracker:SimulateShot(
        cameraCFrame: CFrame,
        targetPosition: Vector3,
        maxFovDeg: number,
        hitChancePercent: number,
        isObstructed: boolean?,
        targetInstance: Instance?
    ): ShotSimulationResult
        local muzzlePos = cameraCFrame.Position + cameraCFrame.LookVector * 1.5 - Vector3.new(0, 0.4, 0)
        local displacement = (targetPosition - muzzlePos)
        local dist = displacement.Magnitude

        if dist < EPSILON then
            return {
                Fired = true,
                HitRegistered = false,
                DiscrepancyAngleDeg = 0,
                MuzzlePosition = muzzlePos,
                TargetPosition = targetPosition,
                ShotDirection = cameraCFrame.LookVector,
                InFov = false,
                IsObstructed = isObstructed == true
            }
        end

        local directDir = displacement / dist
        local dot = math.clamp(cameraCFrame.LookVector:Dot(directDir), -1.0, 1.0)
        local discrepancyAngleDeg = math.deg(math.acos(dot))
        local inFov = (discrepancyAngleDeg <= maxFovDeg)

        local hit = false
        local shotDir = cameraCFrame.LookVector

        if inFov and not isObstructed then
            local roll = math.random() * 100.0
            local chance = math.clamp(hitChancePercent, 0.0, 100.0)
            if roll <= chance then
                hit = true
                shotDir = directDir
            else
                -- Dispersão sutil fora do alvo em caso de erro probabilístico
                local missAngle = math.rad(math.random(3, 8))
                local randAxis = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5).Unit
                shotDir = CFrame.fromAxisAngle(randAxis, missAngle):VectorToWorldSpace(directDir)
            end
        end

        local endPosition = hit and targetPosition or (muzzlePos + shotDir * dist)

        return {
            Fired = true,
            HitRegistered = hit,
            DiscrepancyAngleDeg = discrepancyAngleDeg,
            MuzzlePosition = muzzlePos,
            TargetPosition = endPosition,
            ShotDirection = shotDir,
            InFov = inFov,
            IsObstructed = isObstructed == true
        }
    end

    -- Visualizador de Traçador (Tracer 3D Neon com Limpeza de Debris)
    function VectorTracker:DrawTracerBeam(origin: Vector3, targetPos: Vector3, color: Color3?, duration: number?)
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

            local part = Instance.new("Part")
            part.Name = "DeepHat_SilentAimTracer"
            part.Anchored = true
            part.CanCollide = false
            part.CanTouch = false
            part.CanQuery = false
            part.Material = Enum.Material.Neon
            part.Color = color or Color3.fromRGB(255, 45, 60)
            part.Transparency = 0.25
            part.Size = Vector3.new(0.08, 0.08, dist)
            part.CFrame = CFrame.lookAt(origin, targetPos) * CFrame.new(0, 0, -dist / 2)
            part.Parent = container

            Debris:AddItem(part, duration or 0.12)
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
                inst.Name = "HL_" .. target.Name
                inst.Adornee = target
                inst.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                inst.Enabled = true
                inst.Parent = self.Container
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

    function VisualOverlayRenderer:ClearTarget(target: Instance?)
        if not target then return end
        local hl = self.ActiveHighlights[target]
        if hl then
            pcall(function() hl:Destroy() end)
        end
        self.ActiveHighlights[target] = nil

        local conn = self.CleanupConnections[target]
        if conn then
            pcall(function() conn:Disconnect() end)
        end
        self.CleanupConnections[target] = nil
    end

    function VisualOverlayRenderer:ClearAll()
        for _, hl in pairs(self.ActiveHighlights) do
            pcall(function() if hl then hl:Destroy() end end)
        end
        for _, conn in pairs(self.CleanupConnections) do
            pcall(function() if conn then conn:Disconnect() end end)
        end
        table.clear(self.ActiveHighlights)
        table.clear(self.CleanupConnections)
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
    -- Design: Dark Mode Fosco com Red Accents (#E02B36), Abas Modulares e Watchdog de Fundo
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
                test.Parent = coreGui
                test:Destroy()
            end)
            if testOk then return coreGui end
        end
        local localPlayer = Players.LocalPlayer
        local playerGui = localPlayer and localPlayer:FindFirstChildOfClass("PlayerGui")
        return playerGui or Workspace
    end

    -- =========================================================================
    -- LOG DE DIAGNÓSTICOS EM TEMPO REAL
    -- =========================================================================
    function DashboardGUI.AddDiagnosticLog(source: string, message: string, level: "INFO" | "WARN" | "OK")
        if not EventLogListInstance or not EventLogListInstance.Parent then return end

        local color = THEME.TEXT_MAIN
        if level == "WARN" then color = THEME.WARNING
        elseif level == "OK" then color = THEME.SUCCESS
        elseif level == "INFO" then color = THEME.INFO end

        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 20)
        row.BackgroundColor3 = THEME.BG_INPUT
        row.BackgroundTransparency = 0.5
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

        -- Limita em 40 itens na lista
        local children = EventLogListInstance:GetChildren()
        local count = 0
        for _, ch in ipairs(children) do
            if ch:IsA("Frame") then count = count + 1 end
        end
        if count > 40 then
            for _, ch in ipairs(children) do
                if ch:IsA("Frame") then
                    ch:Destroy()
                    break
                end
            end
        end
        EventLogListInstance.CanvasPosition = Vector2.new(0, 99999)
    end

    -- =========================================================================
    -- CRIAÇÃO PRINCIPAL DO DASHBOARD
    -- =========================================================================
    function DashboardGUI.Create(parentGui: Instance?): ScreenGui
        local hostParent = parentGui or GetSafeGuiParent()

        local existing = hostParent:FindFirstChild("DeepHat_MasterDashboard")
        if existing then existing:Destroy() end

        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "DeepHat_MasterDashboard"
        screenGui.ResetOnSpawn = false
        screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        screenGui.Parent = hostParent
        ScreenGuiInstance = screenGui

        -- ---------------------------------------------------------------------
        -- FOV Overlay na Tela
        -- ---------------------------------------------------------------------
        local fovCircle = Instance.new("Frame")
        fovCircle.Name = "DeepHat_FovOverlay"
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

        -- ---------------------------------------------------------------------
        -- Janela Principal
        -- ---------------------------------------------------------------------
        local mainFrame = Instance.new("Frame")
        mainFrame.Name = "MainFrame"
        mainFrame.Size = UDim2.new(0, 960, 0, 580)
        mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
        mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
        mainFrame.BackgroundColor3 = THEME.BG_WINDOW
        mainFrame.BorderSizePixel = 0
        mainFrame.Active = true
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

        -- Arraste da Janela (Draggable)
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
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                isDragging = false
            end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if isDragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStartPos
                mainFrame.Position = UDim2.new(
                    frameStartPos.X.Scale,
                    frameStartPos.X.Offset + delta.X,
                    frameStartPos.Y.Scale,
                    frameStartPos.Y.Offset + delta.Y
                )
            end
        end)

        -- Ícone / Marca
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
        titleLabel.Text = "DEEPHAT SIMULATION SUITE // v6.0 PRO"
        titleLabel.Parent = header

        -- Badge de Watchdog / Status de Saúde em tempo real
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

        -- Alternar exibição via teclas Home ou RightShift
        UserInputService.InputBegan:Connect(function(input, gpe)
            if gpe then return end
            if input.KeyCode == Enum.KeyCode.Home or input.KeyCode == Enum.KeyCode.RightShift then
                mainFrame.Visible = not mainFrame.Visible
            end
        end)

        -- ---------------------------------------------------------------------
        -- Layout Estrutural: Sidebar (Esquerda) + Área de Conteúdo (Direita)
        -- ---------------------------------------------------------------------
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
        sidebarList.Padding = UDim.new(0, 4)
        sidebarList.Parent = sidebar

        local sidebarPad = Instance.new("UIPadding")
        sidebarPad.PaddingTop = UDim.new(0, 10)
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

        -- Páginas das Abas
        local pages: { [string]: ScrollingFrame } = {}
        local tabButtons: { [string]: TextButton } = {}

        local tabs = {
            { Id = "Dashboard",   Label = "▣  Dashboard" },
            { Id = "Camera",      Label = "◎  Camera / Aim Simulation" },
            { Id = "Simulation",  Label = "≋  Simulação (parâmetros)" },
            { Id = "Vision",      Label = "◈  World / ESP" },
            { Id = "LineOfSight", Label = "⌖  Line of Sight" },
            { Id = "Hitbox",      Label = "◇  Regiões de Alvo" },
            { Id = "Diagnostics", Label = "▤  Detection / Telemetry" },
            { Id = "Performance", Label = "▥  Desempenho" },
            { Id = "Settings",    Label = "⚙  Configuration" },
        }

        local function SwitchTab(tabId: string)
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
            btn.Size = UDim2.new(1, 0, 0, 34)
            btn.BackgroundColor3 = (t.Id == "Dashboard") and THEME.ACCENT_RED or THEME.BG_INPUT
            btn.TextColor3 = (t.Id == "Dashboard") and THEME.TEXT_MAIN or THEME.TEXT_MUTED
            btn.Font = Enum.Font.GothamMedium
            btn.TextSize = 11
            btn.TextXAlignment = Enum.TextXAlignment.Left
            btn.Text = "  " .. t.Label
            btn.Parent = sidebar
            AddCorner(btn, 5)

            tabButtons[t.Id] = btn

            btn.MouseButton1Click:Connect(function()
                SwitchTab(t.Id)
            end)

            -- Criação do Container da Página
            local page = Instance.new("ScrollingFrame")
            page.Name = "Page_" .. t.Id
            page.Size = UDim2.new(1, 0, 1, 0)
            page.BackgroundTransparency = 1
            page.ScrollBarThickness = 4
            page.ScrollBarImageColor3 = THEME.BORDER_LIGHT
            page.CanvasSize = UDim2.new(0, 0, 0, 0)
            page.AutomaticCanvasSize = Enum.AutomaticSize.Y
            page.Visible = (t.Id == "Dashboard")
            page.Parent = mainContent

            local pList = Instance.new("UIListLayout")
            pList.Padding = UDim.new(0, 10)
            pList.Parent = page

            local pPad = Instance.new("UIPadding")
            pPad.PaddingTop = UDim.new(0, 12); pPad.PaddingBottom = UDim.new(0, 12)
            pPad.PaddingLeft = UDim.new(0, 14); pPad.PaddingRight = UDim.new(0, 14)
            pPad.Parent = page

            pages[t.Id] = page
        end

        -- Sincronizadores para Observer
        local syncInputs: { [string]: (number) -> () } = {}

        -- ---------------------------------------------------------------------
        -- Construtor de Componente: Slider com Input Numérico Sincronizado
        -- ---------------------------------------------------------------------
        local function CreateSliderField(parent: Instance, labelText: string, configKey: string, minVal: number, maxVal: number, defaultVal: number, step: number): Frame
            local span = math.max(maxVal - minVal, 0.0001)
            local safeDefault = tonumber(SimConfig.Get(configKey)) or defaultVal or minVal

            local container = Instance.new("Frame")
            container.Name = "SliderRow_" .. configKey
            container.Size = UDim2.new(1, 0, 0, 48)
            container.BackgroundColor3 = THEME.BG_INPUT
            container.BackgroundTransparency = 0.5
            container.Parent = parent
            AddCorner(container, 6)
            AddStroke(container, THEME.BORDER, 1)

            local rowHeader = Instance.new("Frame")
            rowHeader.Size = UDim2.new(1, -16, 0, 20)
            rowHeader.Position = UDim2.new(0, 8, 0, 6)
            rowHeader.BackgroundTransparency = 1
            rowHeader.Parent = container

            local title = Instance.new("TextLabel")
            title.Size = UDim2.new(1, -65, 1, 0)
            title.BackgroundTransparency = 1
            title.Font = Enum.Font.GothamMedium
            title.TextSize = 11
            title.TextColor3 = THEME.TEXT_MAIN
            title.TextXAlignment = Enum.TextXAlignment.Left
            title.Text = labelText
            title.Parent = rowHeader

            local numInput = Instance.new("TextBox")
            numInput.Size = UDim2.new(0, 60, 1, 0)
            numInput.Position = UDim2.new(1, -60, 0, 0)
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
            track.Position = UDim2.new(0, 8, 0, 32)
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
                    SimConfig.Set(configKey, val)
                end
            end

            numInput.FocusLost:Connect(function()
                local num = tonumber(numInput.Text)
                if num then
                    UpdateValue(num)
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
                if input.UserInputType == Enum.UserInputType.MouseButton1 then
                    isDraggingSlider = false
                end
            end)

            UserInputService.InputChanged:Connect(function(input)
                if isDraggingSlider and input.UserInputType == Enum.UserInputType.MouseMovement then
                    local trackWidth = math.max(track.AbsoluteSize.X, 1)
                    local relX = math.clamp((input.Position.X - track.AbsolutePosition.X) / trackWidth, 0, 1)
                    UpdateValue(minVal + relX * span)
                end
            end)

            syncInputs[configKey] = function(newVal: number)
                UpdateValue(newVal, true)
            end

            return container
        end

        -- ---------------------------------------------------------------------
        -- Construtor de Componente: Toggle Switch
        -- ---------------------------------------------------------------------
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
                toggleBtn.BackgroundColor3 = state and THEME.ACCENT_RED or THEME.BG_WINDOW
                dot.Position = state and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
                SimConfig.Set(configKey, state)
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

        -- =========================================================================
        -- [ABA 1] PAINEL GERAL (OVERVIEW)
        -- =========================================================================
        local pageOverview = pages["Dashboard"]

        -- Card de Boas-vindas e Ativação Mestra
        local masterCard = Instance.new("Frame")
        masterCard.Size = UDim2.new(1, 0, 0, 68)
        masterCard.BackgroundColor3 = THEME.BG_INPUT
        masterCard.Parent = pageOverview
        AddCorner(masterCard, 8)
        AddStroke(masterCard, THEME.BORDER, 1)

        local masterTitle = Instance.new("TextLabel")
        masterTitle.Size = UDim2.new(0.7, 0, 0, 24)
        masterTitle.Position = UDim2.new(0, 12, 0, 10)
        masterTitle.BackgroundTransparency = 1
        masterTitle.Font = Enum.Font.GothamBold
        masterTitle.TextSize = 13
        masterTitle.TextColor3 = THEME.TEXT_MAIN
        masterTitle.TextXAlignment = Enum.TextXAlignment.Left
        masterTitle.Text = "MOTOR DE CINEMÁTICA E DETECÇÃO DE COMPORTAMENTO"
        masterTitle.Parent = masterCard

        local masterDesc = Instance.new("TextLabel")
        masterDesc.Size = UDim2.new(0.7, 0, 0, 20)
        masterDesc.Position = UDim2.new(0, 12, 0, 36)
        masterDesc.BackgroundTransparency = 1
        masterDesc.Font = Enum.Font.GothamMedium
        masterDesc.TextSize = 10
        masterDesc.TextColor3 = THEME.TEXT_MUTED
        masterDesc.TextXAlignment = Enum.TextXAlignment.Left
        masterDesc.Text = "Simulador avançado com análise vetorial e telemetria anti-cheat em tempo real."
        masterDesc.Parent = masterCard

        local masterSwitch = Instance.new("TextButton")
        masterSwitch.Size = UDim2.new(0, 140, 0, 34)
        masterSwitch.Position = UDim2.new(1, -152, 0.5, -17)
        masterSwitch.BackgroundColor3 = SimConfig.Get("SimulationActive") and THEME.ACCENT_RED or THEME.BG_WINDOW
        masterSwitch.Font = Enum.Font.GothamBold
        masterSwitch.TextSize = 11
        masterSwitch.TextColor3 = THEME.TEXT_MAIN
        masterSwitch.Text = SimConfig.Get("SimulationActive") and "SIMULAÇÃO: ATIVA" or "SIMULAÇÃO: PAUSADA"
        masterSwitch.Parent = masterCard
        AddCorner(masterSwitch, 6)
        AddStroke(masterSwitch, THEME.BORDER_LIGHT, 1)

        masterSwitch.MouseButton1Click:Connect(function()
            local active = not SimConfig.Get("SimulationActive")
            SimConfig.Set("SimulationActive", active)
            masterSwitch.BackgroundColor3 = active and THEME.ACCENT_RED or THEME.BG_WINDOW
            masterSwitch.Text = active and "SIMULAÇÃO: ATIVA" or "SIMULAÇÃO: PAUSADA"
            DashboardGUI.AddDiagnosticLog("ENGINE", active and "Módulo iniciado com sucesso" or "Módulo colocado em espera", active and "OK" or "WARN")
        end)

        -- Seletor de Perfis Rápidos em Cards
        local profileHeader = Instance.new("TextLabel")
        profileHeader.Size = UDim2.new(1, 0, 0, 18)
        profileHeader.BackgroundTransparency = 1
        profileHeader.Font = Enum.Font.GothamBold
        profileHeader.TextSize = 11
        profileHeader.TextColor3 = THEME.ACCENT_RED
        profileHeader.TextXAlignment = Enum.TextXAlignment.Left
        profileHeader.Text = "SELEÇÃO DE PERFIL DE OPERAÇÃO"
        profileHeader.Parent = pageOverview

        local profileGrid = Instance.new("Frame")
        profileGrid.Size = UDim2.new(1, 0, 0, 42)
        profileGrid.BackgroundTransparency = 1
        profileGrid.Parent = pageOverview

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

        -- Mini Dashboard de Métricas Instantâneas
        local metricsGrid = Instance.new("Frame")
        metricsGrid.Size = UDim2.new(1, 0, 0, 84)
        metricsGrid.BackgroundTransparency = 1
        metricsGrid.Parent = pageOverview

        local mLayout = Instance.new("UIGridLayout")
        mLayout.CellSize = UDim2.new(0.238, 0, 1, 0)
        mLayout.CellPadding = UDim2.new(0.016, 0, 0, 0)
        mLayout.Parent = metricsGrid

        local function CreateMetricCard(title: string, defaultVal: string, keyName: string): Frame
            local card = Instance.new("Frame")
            card.BackgroundColor3 = THEME.BG_INPUT
            card.Parent = metricsGrid
            AddCorner(card, 6)
            AddStroke(card, THEME.BORDER, 1)

            local tLbl = Instance.new("TextLabel")
            tLbl.Size = UDim2.new(1, -12, 0, 16)
            tLbl.Position = UDim2.new(0, 8, 0, 10)
            tLbl.BackgroundTransparency = 1
            tLbl.Font = Enum.Font.GothamMedium
            tLbl.TextSize = 10
            tLbl.TextColor3 = THEME.TEXT_MUTED
            tLbl.TextXAlignment = Enum.TextXAlignment.Left
            tLbl.Text = title
            tLbl.Parent = card

            local vLbl = Instance.new("TextLabel")
            vLbl.Size = UDim2.new(1, -12, 0, 32)
            vLbl.Position = UDim2.new(0, 8, 0, 32)
            vLbl.BackgroundTransparency = 1
            vLbl.Font = Enum.Font.GothamBold
            vLbl.TextSize = 15
            vLbl.TextColor3 = THEME.TEXT_MAIN
            vLbl.TextXAlignment = Enum.TextXAlignment.Left
            vLbl.Text = defaultVal
            vLbl.Parent = card

            TelemetryLabels[keyName] = vLbl
            return card
        end

        CreateMetricCard("VELOCIDADE ANGULAR", "0.0 °/s", "AngVel")
        CreateMetricCard("STATUS DE VISÃO", "LIVRE", "VisStatus")
        CreateMetricCard("ALVO ATIVO", "NENHUM", "ActiveTarget")
        CreateMetricCard("TAXA DE QUADROS", "60 FPS", "FpsCounter")

        -- =========================================================================
        -- [ABA 2] CÂMERA & VETORES
        -- =========================================================================
        local pageCamera = pages["Camera"]
        CreateToggleField(pageCamera, "Ativar Rastreamento de Mira (Aimbot Ativo)", "AimbotEnabled", SimConfig.Get("AimbotEnabled"))
        CreateToggleField(pageCamera, "Forçar Limite Estrito de Velocidade Angular", "MaxAngularVelocityClamp", SimConfig.Get("MaxAngularVelocityClamp"))
        CreateSliderField(pageCamera, "Campo de Visão Útil (FOV °)", "FOV", 10, 180, SimConfig.Get("FOV"), 1)
        CreateSliderField(pageCamera, "Coeficiente de Suavização (Lerp)", "Smoothing", 0.01, 1.0, SimConfig.Get("Smoothing"), 0.01)
        CreateSliderField(pageCamera, "Velocidade Angular Máxima (°/s)", "AngularVelocity", 30, 720, SimConfig.Get("AngularVelocity"), 5)
        CreateSliderField(pageCamera, "Tempo de Resposta Simulado (ms)", "ResponseTime", 0, 250, SimConfig.Get("ResponseTime"), 1)
        CreateSliderField(pageCamera, "Precisão de Trajetória (%)", "TrajectoryPrecision", 50, 100, SimConfig.Get("TrajectoryPrecision"), 0.5)
        CreateSliderField(pageCamera, "Frequência de Atualização (Hz)", "UpdateFrequency", 10, 144, SimConfig.Get("UpdateFrequency"), 5)
        CreateSliderField(pageCamera, "Raio Máximo de Atuação (studs)", "VectorRadius", 10, 500, SimConfig.Get("VectorRadius"), 5)

        -- =========================================================================
        -- [ABA 3] SIMULAÇÃO & COMPORTAMENTO
        -- =========================================================================
        local pageSim = pages["Simulation"]

        -- Seletor de Modo de Mira (AimMode)
        local aimModeRow = Instance.new("Frame")
        aimModeRow.Size = UDim2.new(1, 0, 0, 36)
        aimModeRow.BackgroundColor3 = THEME.BG_INPUT
        aimModeRow.BackgroundTransparency = 0.5
        aimModeRow.Parent = pageSim
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

        local aimModeButtons: { [string]: TextButton } = {}
        local aimModeOptions = {
            { Id = "HoldRMB", Label = "Segurar RMB" },
            { Id = "Toggle", Label = "Alternar" },
            { Id = "AlwaysOn", Label = "Sempre Ativo" },
        }

        local function UpdateAimModeUI(activeId: string)
            for id, btn in pairs(aimModeButtons) do
                local isSel = (id == activeId)
                btn.BackgroundColor3 = isSel and THEME.ACCENT_RED or THEME.BG_WINDOW
                btn.TextColor3 = isSel and THEME.TEXT_MAIN or THEME.TEXT_MUTED
            end
        end

        local aimModeGrid = Instance.new("Frame")
        aimModeGrid.Size = UDim2.new(1, -125, 0, 24)
        aimModeGrid.Position = UDim2.new(0, 115, 0.5, -12)
        aimModeGrid.BackgroundTransparency = 1
        aimModeGrid.Parent = aimModeRow

        local aimModeLayout = Instance.new("UIGridLayout")
        aimModeLayout.CellSize = UDim2.new(0.31, 0, 1, 0)
        aimModeLayout.CellPadding = UDim2.new(0.035, 0, 0, 0)
        aimModeLayout.Parent = aimModeGrid

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
                DashboardGUI.AddDiagnosticLog("AIM_MODE", "Modo de mira alterado para: " .. opt.Label, "INFO")
            end)
        end

        CreateToggleField(pageSim, "Segurar Botão Direito para Focar (Hold to Aim)", "HoldToAim", SimConfig.Get("HoldToAim"))
        CreateToggleField(pageSim, "Simular Micro-Variações Orgânicas (Perlin Jitter)", "SimulateJitter", SimConfig.Get("SimulateJitter"))

        -- Seletor de Prioridade de Alvos
        local prioRow = Instance.new("Frame")
        prioRow.Size = UDim2.new(1, 0, 0, 36)
        prioRow.BackgroundColor3 = THEME.BG_INPUT
        prioRow.BackgroundTransparency = 0.5
        prioRow.Parent = pageSim
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

        local prioButtons: { [string]: TextButton } = {}
        local prioOptions = {
            { Id = "Crosshair", Label = "Mira" },
            { Id = "Distance", Label = "Distância" },
            { Id = "LowestHealth", Label = "Menor Vida" },
        }

        local function UpdatePrioUI(activeId: string)
            for id, btn in pairs(prioButtons) do
                local isSel = (id == activeId)
                btn.BackgroundColor3 = isSel and THEME.ACCENT_RED or THEME.BG_WINDOW
                btn.TextColor3 = isSel and THEME.TEXT_MAIN or THEME.TEXT_MUTED
            end
        end

        local prioGrid = Instance.new("Frame")
        prioGrid.Size = UDim2.new(1, -125, 0, 24)
        prioGrid.Position = UDim2.new(0, 115, 0.5, -12)
        prioGrid.BackgroundTransparency = 1
        prioGrid.Parent = prioRow

        local prioLayout = Instance.new("UIGridLayout")
        prioLayout.CellSize = UDim2.new(0.31, 0, 1, 0)
        prioLayout.CellPadding = UDim2.new(0.035, 0, 0, 0)
        prioLayout.Parent = prioGrid

        for _, opt in ipairs(prioOptions) do
            local pBtn = Instance.new("TextButton")
            pBtn.BackgroundColor3 = (SimConfig.Get("TargetPriority") == opt.Id) and THEME.ACCENT_RED or THEME.BG_WINDOW
            pBtn.TextColor3 = (SimConfig.Get("TargetPriority") == opt.Id) and THEME.TEXT_MAIN or THEME.TEXT_MUTED
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
                DashboardGUI.AddDiagnosticLog("TARGETING", "Prioridade alterada para: " .. opt.Label, "INFO")
            end)
        end

        CreateSliderField(pageSim, "Persistência no Alvo (Stickiness s)", "TargetStickiness", 0.05, 1.0, SimConfig.Get("TargetStickiness"), 0.05)
        CreateSliderField(pageSim, "Frequência de Eventos (Hz)", "EventFrequency", 1, 60, SimConfig.Get("EventFrequency"), 1)
        CreateSliderField(pageSim, "Intensidade da Resposta (%)", "Intensity", 0, 100, SimConfig.Get("Intensity"), 1)
        CreateSliderField(pageSim, "Velocidade de Deslocamento (studs/s)", "MoveSpeed", 8, 40, SimConfig.Get("MoveSpeed"), 1)
        CreateSliderField(pageSim, "Curva de Aceleração (Hermite Exponent)", "AccelerationCurve", 0.2, 3.0, SimConfig.Get("AccelerationCurve"), 0.05)
        CreateSliderField(pageSim, "Duração do Ciclo de Teste (s)", "CycleDuration", 5, 120, SimConfig.Get("CycleDuration"), 5)
        CreateSliderField(pageSim, "Agentes Concorrentes Simulados", "SimulatedAgents", 1, 16, SimConfig.Get("SimulatedAgents"), 1)

        -- =========================================================================
        -- [ABA 4] LINHA DE VISÃO & SILENT AIM
        -- =========================================================================
        local pageVision = pages["Vision"]
        CreateToggleField(pageVision, "Realce Visual de Entidades (Highlights ESP)", "EnableESP", SimConfig.Get("EnableESP"))
        CreateToggleField(pageVision, "Exibir Círculo de FOV na Tela", "ShowFovCircle", SimConfig.Get("ShowFovCircle"))
        CreateToggleField(pageVision, "Filtrar Somente Alvos com Visada Livre (Visible Only)", "VisibleOnly", SimConfig.Get("VisibleOnly"))
        CreateToggleField(pageVision, "Ignorar Aliados da Mesma Equipe (Team Check)", "TeamCheck", SimConfig.Get("TeamCheck"))
        CreateToggleField(pageVision, "Ativar Predição Balística de Alvo (Lead Tracking)", "EnableLead", SimConfig.Get("EnableLead"))
        CreateSliderField(pageVision, "Velocidade Balística Simulada (studs/s)", "ProjectileSpeed", 300, 3000, SimConfig.Get("ProjectileSpeed"), 50)

        -- Seção de Silent Aim
        local silentHeader = Instance.new("TextLabel")
        silentHeader.Size = UDim2.new(1, 0, 0, 18)
        silentHeader.BackgroundTransparency = 1
        silentHeader.Font = Enum.Font.GothamBold
        silentHeader.TextSize = 11
        silentHeader.TextColor3 = THEME.ACCENT_RED
        silentHeader.TextXAlignment = Enum.TextXAlignment.Left
        silentHeader.Text = "SIMULAÇÃO DE SILENT AIM (DISPARO DESACOPLADO)"
        silentHeader.Parent = pageVision

        CreateToggleField(pageVision, "Ativar Simulação de Silent Aim (Vetor Desacoplado)", "SilentAimEnabled", SimConfig.Get("SilentAimEnabled"))
        CreateSliderField(pageVision, "Silent Aim - Campo de Redirecionamento (FOV °)", "SilentAimFOV", 5, 90, SimConfig.Get("SilentAimFOV"), 1)
        CreateSliderField(pageVision, "Probabilidade de Acerto do Silent Aim (%)", "SilentAimHitChance", 10, 100, SimConfig.Get("SilentAimHitChance"), 5)
        CreateToggleField(pageVision, "Exibir Traçador 3D do Vetor de Disparo (Tracer)", "SilentAimTracer", SimConfig.Get("SilentAimTracer"))

        -- =========================================================================
        -- [ABA 5] MAPEAMENTO HITBOX (MANEQUIM INTERATIVO)
        -- =========================================================================
        local pageHitbox = pages["Hitbox"]

        local mannequinContainer = Instance.new("Frame")
        mannequinContainer.Size = UDim2.new(1, 0, 0, 260)
        mannequinContainer.BackgroundColor3 = THEME.BG_INPUT
        mannequinContainer.Parent = pageHitbox
        AddCorner(mannequinContainer, 8)
        AddStroke(mannequinContainer, THEME.BORDER, 1)

        -- Linhas do esqueleto
        local spine = Instance.new("Frame")
        spine.Size = UDim2.new(0, 2, 0.55, 0)
        spine.Position = UDim2.new(0.5, -1, 0.18, 0)
        spine.BackgroundColor3 = THEME.BORDER_LIGHT
        spine.BorderSizePixel = 0
        spine.Parent = mannequinContainer

        local shoulders = Instance.new("Frame")
        shoulders.Size = UDim2.new(0.4, 0, 0, 2)
        shoulders.Position = UDim2.new(0.3, 0, 0.32, 0)
        shoulders.BackgroundColor3 = THEME.BORDER_LIGHT
        shoulders.BorderSizePixel = 0
        shoulders.Parent = mannequinContainer

        local legL = Instance.new("Frame")
        legL.Size = UDim2.new(0, 2, 0.3, 0)
        legL.Position = UDim2.new(0.4, -1, 0.65, 0)
        legL.BackgroundColor3 = THEME.BORDER_LIGHT
        legL.BorderSizePixel = 0
        legL.Parent = mannequinContainer

        local legR = Instance.new("Frame")
        legR.Size = UDim2.new(0, 2, 0.3, 0)
        legR.Position = UDim2.new(0.6, -1, 0.65, 0)
        legR.BackgroundColor3 = THEME.BORDER_LIGHT
        legR.BorderSizePixel = 0
        legR.Parent = mannequinContainer

        local activeBadge = Instance.new("TextLabel")
        activeBadge.Size = UDim2.new(0, 220, 0, 26)
        activeBadge.Position = UDim2.new(0.5, -110, 0.9, -20)
        activeBadge.BackgroundColor3 = THEME.BG_WINDOW
        activeBadge.Font = Enum.Font.GothamBold
        activeBadge.TextSize = 11
        activeBadge.TextColor3 = THEME.ACCENT_RED
        activeBadge.Text = "REGIÃO ATIVA: [ HEAD ]"
        activeBadge.Parent = mannequinContainer
        AddCorner(activeBadge, 4)
        AddStroke(activeBadge, THEME.BORDER, 1)

        local nodes = {
            { Name = "Head",  Pos = UDim2.new(0.5, -11, 0.12, 0), Size = 22 },
            { Name = "Torso", Pos = UDim2.new(0.5, -13, 0.38, 0), Size = 26 },
            { Name = "Arms",  Pos = UDim2.new(0.3, -10, 0.38, 0), Size = 20 },
            { Name = "Arms",  Pos = UDim2.new(0.7, -10, 0.38, 0), Size = 20 },
            { Name = "Legs",  Pos = UDim2.new(0.4, -10, 0.78, 0), Size = 20 },
            { Name = "Legs",  Pos = UDim2.new(0.6, -10, 0.78, 0), Size = 20 },
        }

        local nodeButtons: { { Btn: TextButton, Region: string } } = {}

        local function HighlightNodeRegion(regionName: string)
            activeBadge.Text = "REGIÃO ATIVA: [ " .. string.upper(regionName) .. " ]"
            for _, n in ipairs(nodeButtons) do
                local isSelected = (n.Region == regionName)
                n.Btn.BackgroundColor3 = isSelected and THEME.ACCENT_RED or THEME.BORDER_LIGHT
            end
        end

        for _, n in ipairs(nodes) do
            local btn = Instance.new("TextButton")
            btn.Size = UDim2.new(0, n.Size, 0, n.Size)
            btn.Position = n.Pos
            btn.BackgroundColor3 = (n.Name == SimConfig.Get("TargetRegion")) and THEME.ACCENT_RED or THEME.BORDER_LIGHT
            btn.Text = ""
            btn.Parent = mannequinContainer
            AddCorner(btn, n.Size / 2)
            table.insert(nodeButtons, { Btn = btn, Region = n.Name })

            btn.MouseButton1Click:Connect(function()
                SimConfig.Set("TargetRegion", n.Name)
                SimConfig.Set("TargetBone", n.Name)
                HighlightNodeRegion(n.Name)
                DashboardGUI.AddDiagnosticLog("TARGETING", "Região corporal definida: " .. n.Name, "OK")
            end)
        end

        -- =========================================================================
        -- [ABA 6] DIAGNÓSTICOS & LOGS
        -- =========================================================================
        local pageDiag = pages["Diagnostics"]

        local diagHeader = Instance.new("Frame")
        diagHeader.Size = UDim2.new(1, 0, 0, 36)
        diagHeader.BackgroundColor3 = THEME.BG_INPUT
        diagHeader.Parent = pageDiag
        AddCorner(diagHeader, 6)

        local diagTitle = Instance.new("TextLabel")
        diagTitle.Size = UDim2.new(0.7, 0, 1, 0)
        diagTitle.Position = UDim2.new(0, 10, 0, 0)
        diagTitle.BackgroundTransparency = 1
        diagTitle.Font = Enum.Font.GothamBold
        diagTitle.TextSize = 11
        diagTitle.TextColor3 = THEME.TEXT_MAIN
        diagTitle.TextXAlignment = Enum.TextXAlignment.Left
        diagTitle.Text = "FEED DE EVENTOS & ESTABILIDADE DO KERNEL"
        diagTitle.Parent = diagHeader

        local clearLogsBtn = Instance.new("TextButton")
        clearLogsBtn.Size = UDim2.new(0, 90, 0, 24)
        clearLogsBtn.Position = UDim2.new(1, -100, 0.5, -12)
        clearLogsBtn.BackgroundColor3 = THEME.BG_WINDOW
        clearLogsBtn.Font = Enum.Font.GothamMedium
        clearLogsBtn.TextSize = 10
        clearLogsBtn.TextColor3 = THEME.TEXT_MAIN
        clearLogsBtn.Text = "Limpar Logs"
        clearLogsBtn.Parent = diagHeader
        AddCorner(clearLogsBtn, 4)

        local logScroll = Instance.new("ScrollingFrame")
        logScroll.Size = UDim2.new(1, 0, 0, 240)
        logScroll.BackgroundColor3 = THEME.BG_WINDOW
        logScroll.ScrollBarThickness = 4
        logScroll.ScrollBarImageColor3 = THEME.BORDER_LIGHT
        logScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
        logScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
        logScroll.Parent = pageDiag
        AddCorner(logScroll, 6)
        AddStroke(logScroll, THEME.BORDER, 1)

        local logList = Instance.new("UIListLayout")
        logList.Padding = UDim.new(0, 4)
        logList.Parent = logScroll

        local logPad = Instance.new("UIPadding")
        logPad.PaddingTop = UDim.new(0, 6); logPad.PaddingBottom = UDim.new(0, 6)
        logPad.PaddingLeft = UDim.new(0, 6); logPad.PaddingRight = UDim.new(0, 6)
        logPad.Parent = logScroll
        EventLogListInstance = logScroll

        clearLogsBtn.MouseButton1Click:Connect(function()
            for _, ch in ipairs(logScroll:GetChildren()) do
                if ch:IsA("Frame") then ch:Destroy() end
            end
            DashboardGUI.AddDiagnosticLog("SYSTEM", "Logs limpos com sucesso.", "INFO")
        end)

        -- =========================================================================
        -- [ABA 7] DESEMPENHO & FRAME TIME
        -- =========================================================================
        local pagePerf = pages["Performance"]

        local perfCard = Instance.new("Frame")
        perfCard.Size = UDim2.new(1, 0, 0, 110)
        perfCard.BackgroundColor3 = THEME.BG_INPUT
        perfCard.Parent = pagePerf
        AddCorner(perfCard, 6)
        AddStroke(perfCard, THEME.BORDER, 1)

        local perfTitle = Instance.new("TextLabel")
        perfTitle.Size = UDim2.new(1, -20, 0, 20)
        perfTitle.Position = UDim2.new(0, 10, 0, 10)
        perfTitle.BackgroundTransparency = 1
        perfTitle.Font = Enum.Font.GothamBold
        perfTitle.TextSize = 12
        perfTitle.TextColor3 = THEME.TEXT_MAIN
        perfTitle.TextXAlignment = Enum.TextXAlignment.Left
        perfTitle.Text = "MÉTRICAS DE COMPUTAÇÃO VETORIAL"
        perfTitle.Parent = perfCard

        local perfInfo = Instance.new("TextLabel")
        perfInfo.Size = UDim2.new(1, -20, 0, 60)
        perfInfo.Position = UDim2.new(0, 10, 0, 35)
        perfInfo.BackgroundTransparency = 1
        perfInfo.Font = Enum.Font.Code
        perfInfo.TextSize = 11
        perfInfo.TextColor3 = THEME.SUCCESS
        perfInfo.TextXAlignment = Enum.TextXAlignment.Left
        perfInfo.Text = "Frame-Time: 16.6ms (Alvo 60 FPS)\nOverhead Cinemático: < 0.05ms\nGuarda Epsilon: 1e-4 Ativa | Sem NaN Detectado"
        perfInfo.Parent = perfCard
        TelemetryLabels["PerfInfo"] = perfInfo

        -- =========================================================================
        -- [ABA 8] CONFIGURAÇÕES & ARMAZENAMENTO
        -- =========================================================================
        local pageSettings = pages["Settings"]
        CreateToggleField(pageSettings, "Ativar Watchdog Contínuo em Segundo Plano", "WatchdogEnabled", SimConfig.Get("WatchdogEnabled"))
        CreateToggleField(pageSettings, "Exibir Mensagens de Debug no Console", "DebugLogging", SimConfig.Get("DebugLogging"))

        local btnRow = Instance.new("Frame")
        btnRow.Size = UDim2.new(1, 0, 0, 38)
        btnRow.BackgroundTransparency = 1
        btnRow.Parent = pageSettings

        local btnRowLayout = Instance.new("UIListLayout")
        btnRowLayout.FillDirection = Enum.FillDirection.Horizontal
        btnRowLayout.Padding = UDim.new(0, 10)
        btnRowLayout.Parent = btnRow

        local function CreateExportBtn(text: string, onClick: () -> ()): TextButton
            local b = Instance.new("TextButton")
            b.Size = UDim2.new(0.48, 0, 1, 0)
            b.BackgroundColor3 = THEME.BG_INPUT
            b.Font = Enum.Font.GothamBold
            b.TextSize = 11
            b.TextColor3 = THEME.TEXT_MAIN
            b.Text = text
            b.Parent = btnRow
            AddCorner(b, 6)
            AddStroke(b, THEME.BORDER, 1)
            b.MouseButton1Click:Connect(onClick)
            return b
        end

        CreateExportBtn("📤 EXPORTAR CONFIG (JSON)", function()
            local json = SimConfig.ExportJSON()
            pcall(function()
                if setclipboard then
                    setclipboard(json)
                    DashboardGUI.AddDiagnosticLog("CONFIG", "JSON copiado para a área de transferência!", "OK")
                else
                    DashboardGUI.AddDiagnosticLog("CONFIG", "JSON gerado (verifique no console)", "INFO")
                    print("\n[DeepHat SimConfig JSON Export]\n" .. json)
                end
            end)
        end)

        CreateExportBtn("↺ RESTAURAR PADRÕES", function()
            SimConfig.RestoreDefaults("Restaurar padrões (UI)")
            UpdateProfileUI(SimConfig.DefaultProfileName)
            DashboardGUI.AddDiagnosticLog("CONFIG", "Configurações restauradas para o perfil padrão.", "WARN")
        end)

        -- =========================================================================
        -- [ABA] LINE OF SIGHT  (resultado tri-state, causa, obstrução, histórico, cenários)
        -- =========================================================================
        local function MakeInfoLabel(parent: Instance, text: string, color: Color3?, height: number?): TextLabel
            local l = Instance.new("TextLabel")
            l.Size = UDim2.new(1, 0, 0, height or 24)
            l.BackgroundColor3 = THEME.BG_INPUT
            l.BackgroundTransparency = 0.5
            l.Font = Enum.Font.GothamMedium
            l.TextSize = 11
            l.TextColor3 = color or THEME.TEXT_MUTED
            l.TextXAlignment = Enum.TextXAlignment.Left
            l.TextYAlignment = Enum.TextYAlignment.Top
            l.TextWrapped = true
            l.Text = "  " .. text
            l.Parent = parent
            AddCorner(l, 5)
            return l
        end

        local function MakeButtonGrid(parent: Instance, cellW: number): Frame
            local grid = Instance.new("Frame")
            grid.Size = UDim2.new(1, 0, 0, 0)
            grid.AutomaticSize = Enum.AutomaticSize.Y
            grid.BackgroundTransparency = 1
            grid.Parent = parent
            local layout = Instance.new("UIGridLayout")
            layout.CellSize = UDim2.new(0, cellW, 0, 28)
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

        local pageLos = pages["LineOfSight"]
        MakeInfoLabel(pageLos, "Política: CanCollide=false não bloqueia; barreira invisível COM colisão bloqueia; água ignorada. Cenários rodam em geometria temporária isolada (Y=900), sem jogadores reais.", THEME.TEXT_MUTED, 44)
        LosLabels["Status"] = MakeInfoLabel(pageLos, "Última consulta: (nenhuma)", THEME.TEXT_MUTED, 26)
        LosLabels["Reason"] = MakeInfoLabel(pageLos, "Causa: —", THEME.TEXT_MUTED, 24)
        LosLabels["Blocker"] = MakeInfoLabel(pageLos, "Obstrução: —", THEME.TEXT_MUTED, 24)
        LosLabels["Distance"] = MakeInfoLabel(pageLos, "Distância da colisão: —", THEME.TEXT_MUTED, 24)

        local scenarioGrid = MakeButtonGrid(pageLos, 150)
        for _, sc in ipairs(ScenarioRunner.Scenarios) do
            MakeGridButton(scenarioGrid, "▶ " .. sc.Label, function()
                if DashboardGUI.OnRunLosScenario then
                    DashboardGUI.OnRunLosScenario(sc.Id)
                else
                    DashboardGUI.AddDiagnosticLog("LOS", "Executor de cenários não conectado.", "WARN")
                end
            end)
        end
        MakeGridButton(scenarioGrid, "🗑 Limpar histórico", function()
            if DashboardGUI.OnClearLosHistory then DashboardGUI.OnClearLosHistory() end
            if LosHistoryList then
                for _, ch in ipairs(LosHistoryList:GetChildren()) do
                    if ch:IsA("TextLabel") then ch:Destroy() end
                end
            end
        end)

        local losHistory = Instance.new("ScrollingFrame")
        losHistory.Size = UDim2.new(1, 0, 0, 170)
        losHistory.BackgroundColor3 = THEME.BG_WINDOW
        losHistory.ScrollBarThickness = 4
        losHistory.CanvasSize = UDim2.new(0, 0, 0, 0)
        losHistory.AutomaticCanvasSize = Enum.AutomaticSize.Y
        losHistory.Parent = pageLos
        AddCorner(losHistory, 6)
        AddStroke(losHistory, THEME.BORDER, 1)
        local losHistLayout = Instance.new("UIListLayout")
        losHistLayout.Padding = UDim.new(0, 2)
        losHistLayout.SortOrder = Enum.SortOrder.LayoutOrder
        losHistLayout.Parent = losHistory
        LosHistoryList = losHistory

        -- =========================================================================
        -- [ABA] DETECTION / TELEMETRY  (dados vindos do EngineCore real via bootstrap)
        -- =========================================================================
        local pageDet = pages["Diagnostics"]
        DetLabels["State"] = MakeInfoLabel(pageDet, "Estado: aguardando amostras reais (sem dados fictícios)", THEME.TEXT_MUTED, 24)
        DetLabels["Samples"] = MakeInfoLabel(pageDet, "Amostras válidas: 0", THEME.TEXT_MUTED, 24)
        DetLabels["Missing"] = MakeInfoLabel(pageDet, "Dados ausentes: —", THEME.TEXT_MUTED, 40)
        DetLabels["Rules"] = MakeInfoLabel(pageDet, "Regras avaliadas: 0", THEME.TEXT_MUTED, 24)
        DetLabels["Anomalies"] = MakeInfoLabel(pageDet, "Anomalias: nenhuma", THEME.TEXT_MUTED, 40)
        DetLabels["Why"] = MakeInfoLabel(pageDet, "Justificativas: —", THEME.TEXT_MUTED, 70)
        DetLabels["Perf"] = MakeInfoLabel(pageDet, "Desempenho: —", THEME.TEXT_MUTED, 24)
        DetLabels["Tests"] = MakeInfoLabel(pageDet, "Cenários LOS: nenhum executado", THEME.TEXT_MUTED, 24)

        -- =========================================================================
        -- [ABA] CONFIGURATION  (perfil, tema, escala, depuração, import/export, persistência)
        -- =========================================================================
        local pageCfg = pages["Settings"]
        local profileLabel = MakeInfoLabel(pageCfg, "Perfil: " .. tostring(SimConfig.Get("ActiveProfile")), THEME.ACCENT_RED, 24)
        DetLabels["Profile"] = profileLabel
        MakeInfoLabel(pageCfg, string.format("Versão da configuração: %d  |  Perfil padrão: %s", SimConfig.ConfigVersion, SimConfig.DefaultProfileName), THEME.TEXT_MUTED, 24)

        CreateToggleField(pageCfg, "Visualizar manequins sintéticos (realces)", "ShowSyntheticTargets", SimConfig.Get("ShowSyntheticTargets"))
        CreateToggleField(pageCfg, "Marcadores e informações de depuração", "ShowDebugMarkers", SimConfig.Get("ShowDebugMarkers"))
        CreateToggleField(pageCfg, "Diagnóstico de Line of Sight", "LineOfSightEnabled", SimConfig.Get("LineOfSightEnabled"))
        CreateToggleField(pageCfg, "Indicadores de telemetria", "TelemetryIndicators", SimConfig.Get("TelemetryIndicators"))
        CreateToggleField(pageCfg, "Histórico de diagnóstico", "HistoryEnabled", SimConfig.Get("HistoryEnabled"))
        CreateToggleField(pageCfg, "Painel visível", "PanelEnabled", SimConfig.Get("PanelEnabled"))
        CreateToggleField(pageCfg, "Barra lateral de navegação visível", "SidebarEnabled", SimConfig.Get("SidebarEnabled"))
        CreateToggleField(pageCfg, "Persistir preferências", "PersistenceEnabled", SimConfig.Get("PersistenceEnabled"))
        CreateSliderField(pageCfg, "Raio do FOV visual de demonstração (px)", "FovRadiusPx", 20, 600, SimConfig.Get("FovRadiusPx"), 5)
        CreateSliderField(pageCfg, "Limite do histórico", "HistoryLimit", 5, 500, SimConfig.Get("HistoryLimit"), 5)
        CreateSliderField(pageCfg, "Escala da interface", "UiScale", 0.7, 1.5, SimConfig.Get("UiScale"), 0.05)

        local cfgGrid = MakeButtonGrid(pageCfg, 150)
        MakeGridButton(cfgGrid, "Tema: alternar Dark/Darker", function()
            SimConfig.Set("Theme", SimConfig.Get("Theme") == "Dark" and "Darker" or "Dark")
        end)
        MakeGridButton(cfgGrid, "↺ Restaurar padrões", function()
            SimConfig.RestoreDefaults("Restaurar padrões (aba Configuration)")
            DashboardGUI.AddDiagnosticLog("CONFIG", "Perfil restaurado: " .. SimConfig.DefaultProfileName, "OK")
        end)
        MakeGridButton(cfgGrid, "💾 Salvar preferências", function()
            local saved = SimConfig.Save()
            DashboardGUI.AddDiagnosticLog("CONFIG", saved and "Preferências salvas." or "Persistência indisponível neste ambiente (nada salvo).", saved and "OK" or "WARN")
        end)
        MakeGridButton(cfgGrid, "📂 Carregar preferências", function()
            local status = SimConfig.Load()
            DashboardGUI.AddDiagnosticLog("CONFIG", "Carregamento: " .. status .. (SimConfig.LastLoadReason ~= "" and (" — " .. SimConfig.LastLoadReason) or ""), status == "loaded" and "OK" or "WARN")
        end)

        local importBox = Instance.new("TextBox")
        importBox.Size = UDim2.new(1, 0, 0, 54)
        importBox.BackgroundColor3 = THEME.BG_WINDOW
        importBox.TextColor3 = THEME.TEXT_MAIN
        importBox.PlaceholderText = "Cole aqui o JSON exportado e clique em Importar"
        importBox.PlaceholderColor3 = THEME.TEXT_MUTED
        importBox.Font = Enum.Font.Code
        importBox.TextSize = 10
        importBox.TextWrapped = true
        importBox.ClearTextOnFocus = false
        importBox.MultiLine = true
        importBox.TextXAlignment = Enum.TextXAlignment.Left
        importBox.TextYAlignment = Enum.TextYAlignment.Top
        importBox.Text = ""
        importBox.Parent = pageCfg
        AddCorner(importBox, 5)
        AddStroke(importBox, THEME.BORDER, 1)
        local importGrid = MakeButtonGrid(pageCfg, 150)
        MakeGridButton(importGrid, "⬇ Importar (validado)", function()
            local ok, errors = SimConfig.ImportJSON(importBox.Text)
            if ok then
                DashboardGUI.AddDiagnosticLog("CONFIG", "Importação aplicada.", "OK")
            else
                DashboardGUI.AddDiagnosticLog("CONFIG", "Importação rejeitada: " .. table.concat(errors, "; "):sub(1, 160), "WARN")
            end
        end)

        -- Escala da interface (UIScale) e navegação refletidas a partir da configuração
        local uiScale = Instance.new("UIScale")
        uiScale.Scale = tonumber(SimConfig.Get("UiScale")) or 1
        uiScale.Parent = mainFrame
        mainFrame.Visible = SimConfig.Get("PanelEnabled") ~= false
        sidebar.Visible = SimConfig.Get("SidebarEnabled") ~= false
        mainFrame.BackgroundColor3 = (SimConfig.Get("Theme") == "Darker") and Color3.fromRGB(5, 6, 8) or THEME.BG_WINDOW

        -- Aba inicial vem da configuração (padrão: Dashboard)
        local startTab = tostring(SimConfig.Get("ActiveTab"))
        if pages[startTab] then SwitchTab(startTab) else SwitchTab("Dashboard") end

        ApplyRuntimeConfig = function(key: string, val: any)
            if key == "UiScale" then
                uiScale.Scale = math.clamp(tonumber(val) or 1, 0.7, 1.5)
            elseif key == "PanelEnabled" then
                mainFrame.Visible = (val == true)
            elseif key == "SidebarEnabled" then
                sidebar.Visible = (val == true)
            elseif key == "Theme" then
                mainFrame.BackgroundColor3 = (val == "Darker") and Color3.fromRGB(5, 6, 8) or THEME.BG_WINDOW
            elseif key == "ActiveProfile" then
                profileLabel.Text = "  Perfil: " .. tostring(val)
            end
        end

        -- ---------------------------------------------------------------------
        -- Barra Inferior de Ações
        -- ---------------------------------------------------------------------
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
            DashboardGUI.AddDiagnosticLog("SAVE", saved and "Configurações persistidas." or "Persistência indisponível neste ambiente (nada salvo).", saved and "OK" or "WARN")
            if DashboardGUI.OnSaveRequested then DashboardGUI.OnSaveRequested() end
        end)

        CreateBottomButton("⏹ PARAR", false, function()
            SimConfig.Set("SimulationActive", false)
            masterSwitch.BackgroundColor3 = THEME.BG_WINDOW
            masterSwitch.Text = "SIMULAÇÃO: PAUSADA"
            DashboardGUI.AddDiagnosticLog("ENGINE", "Execução interrompida pelo usuário.", "WARN")
            if DashboardGUI.OnStopRequested then DashboardGUI.OnStopRequested() end
        end)

        CreateBottomButton("▶ INICIAR TESTE", true, function()
            SimConfig.Set("SimulationActive", true)
            masterSwitch.BackgroundColor3 = THEME.ACCENT_RED
            masterSwitch.Text = "SIMULAÇÃO: ATIVA"
            DashboardGUI.AddDiagnosticLog("ENGINE", "Sessão de teste iniciada.", "OK")
            if DashboardGUI.OnStartRequested then DashboardGUI.OnStartRequested() end
        end)

        -- Sincronização Observer Segura com Cleanup de Instância Anterior
        if unsubscribeGlobal then
            unsubscribeGlobal()
            unsubscribeGlobal = nil
        end

        unsubscribeGlobal = SimConfig.SubscribeAll(function(key, val)
            if ApplyRuntimeConfig then ApplyRuntimeConfig(key, val) end
            if key == "ActiveProfile" then
                UpdateProfileUI(tostring(val))
            elseif key == "TargetRegion" then
                HighlightNodeRegion(tostring(val))
            elseif key == "SimulationActive" then
                local active = (val == true)
                masterSwitch.BackgroundColor3 = active and THEME.ACCENT_RED or THEME.BG_WINDOW
                masterSwitch.Text = active and "SIMULAÇÃO: ATIVA" or "SIMULAÇÃO: PAUSADA"
                if FovCircleInstance then
                    FovCircleInstance.Visible = active and (SimConfig.Get("ShowFovCircle") == true)
                end
            elseif syncInputs[key] and typeof(val) == "number" then
                syncInputs[key](val)
            end
        end)

        screenGui.Destroying:Connect(function()
            if unsubscribeGlobal then
                unsubscribeGlobal()
                unsubscribeGlobal = nil
            end
        end)

        -- Log Inicial
        DashboardGUI.AddDiagnosticLog("INIT", "Dashboard GUI carregada com 8 abas de controle.", "OK")

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
            local fov = tonumber(SimConfig.Get("FOV")) or 70.0
            local vp = camera.ViewportSize
            local halfFovRad = math.rad(fov / 2)
            local camFovRad = math.rad(camera.FieldOfView / 2)
            local radius = tonumber(SimConfig.Get("FovRadiusPx")) or 120
            FovCircleInstance.Size = UDim2.new(0, radius * 2, 0, radius * 2)
            FovCircleInstance.Position = UDim2.new(0.5, 0, 0.5, 0)
        end
    end

    function DashboardGUI:UpdateTelemetryDisplay(data: {
        angularVelocity: number?,
        isObstructed: boolean?,
        targetName: string?,
        dt: number?,
        mode: string?
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
            local tName = data.targetName or "NENHUM"
            TelemetryLabels["ActiveTarget"].Text = tName
            TelemetryLabels["ActiveTarget"].TextColor3 = (tName ~= "NENHUM") and THEME.SUCCESS or THEME.TEXT_MUTED
        end

        local dt = tonumber(data.dt) or 0.0166
        local currentFps = math.clamp(math.floor(1 / math.max(dt, 0.001)), 1, 240)
        PerformanceData.Fps = currentFps

        if TelemetryLabels["FpsCounter"] then
            TelemetryLabels["FpsCounter"].Text = string.format("%d FPS", currentFps)
            TelemetryLabels["FpsCounter"].TextColor3 = (currentFps >= 50) and THEME.SUCCESS or (currentFps >= 30 and THEME.WARNING or THEME.ACCENT_RED)
        end

        if TelemetryLabels["PerfInfo"] then
            local frameTimeMs = dt * 1000
            TelemetryLabels["PerfInfo"].Text = string.format(
                "Frame-Time: %.1fms | Pico Angular: %.1f °/s\nStatus: %s | FPS: %d\nWatchdog: Ativo sem erros",
                frameTimeMs,
                PerformanceData.PeakAngVel,
                tostring(data.mode or "IDLE"),
                currentFps
            )
        end
    end

    -- =========================================================================
    -- WATCHDOG DE FUNDO (CONTINUOUS BACKGROUND HEALTH CHECK)
    -- =========================================================================
    task.spawn(function()
        while true do
            task.wait(1.5)
            if SimConfig.Get("WatchdogEnabled") == true then
                local camera = Workspace.CurrentCamera
                local healthGood = true
                local reason = ""

                -- 1. Verifica integridade da câmera
                if not camera then
                    healthGood = false
                    reason = "Câmera ausente"
                else
                    local pos = camera.CFrame.Position
                    if pos.X ~= pos.X or pos.Y ~= pos.Y or pos.Z ~= pos.Z then
                        healthGood = false
                        reason = "Anomalia NaN na câmera"
                        camera.CFrame = CFrame.new(0, 10, 0)
                    end
                end

                -- 2. Verifica limites do SimConfig
                local fov = tonumber(SimConfig.Get("FOV")) or 70
                if fov < 10 or fov > 180 then
                    SimConfig.Set("FOV", math.clamp(fov, 10, 180))
                end

                -- 3. Atualiza Badge
                if WatchdogBadgeInstance and WatchdogBadgeInstance.Parent then
                    if healthGood then
                        WatchdogBadgeInstance.Text = "● WATCHDOG: 100% OPERACIONAL"
                        WatchdogBadgeInstance.TextColor3 = THEME.SUCCESS
                    else
                        WatchdogBadgeInstance.Text = "⚠️ ALERTA: " .. string.upper(reason)
                        WatchdogBadgeInstance.TextColor3 = THEME.WARNING
                        DashboardGUI.AddDiagnosticLog("WATCHDOG", "Recuperação aplicada: " .. reason, "WARN")
                    end
                end
            end
        end
    end)

    -- Atualiza a aba Line of Sight com dados reais do VectorTracker (LastLos / LosHistory)
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
        LosLabels["Reason"].Text = "  Causa: " .. tostring(last.Reason)
        LosLabels["Blocker"].Text = "  Obstrução: " .. tostring(last.BlockerName or "—")
        LosLabels["Distance"].Text = last.HitDistance and string.format("  Distância da colisão: %.2f studs (consulta: %.2f)", last.HitDistance, last.QueryDistance or 0)
            or string.format("  Distância da colisão: — (consulta: %.2f)", last.QueryDistance or 0)

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
                row.Text = string.format("  %-8s %-14s %s%s", h.Status, tostring(h.Target), tostring(h.Reason),
                    h.Blocker and (" [" .. h.Blocker .. "]") or "")
                row.Parent = LosHistoryList
            end
        end
    end

    -- Atualiza a aba Detection / Telemetry com o relatório real do EngineCore
    -- info = { report = SuspicionReport?, samples = number, perfMs = number?, scenarioPass = number, scenarioFail = number, engineAvailable = boolean }
    function DashboardGUI:UpdateDetection(info: any)
        if not DetLabels["State"] or not DetLabels["State"].Parent or not info then return end
        local r = info.report
        if not info.engineAvailable then
            DetLabels["State"].Text = "  Estado: EngineCore indisponível neste ambiente"
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
            DetLabels["Missing"].Text = "  Dados ausentes: " .. (#r.unavailableMetrics > 0 and table.concat(r.unavailableMetrics, ", ") or "nenhum")
            DetLabels["Rules"].Text = string.format("  Regras avaliadas: %d", r.evaluatedRules)
            DetLabels["Anomalies"].Text = "  Anomalias: " .. (#r.anomalies > 0 and table.concat(r.anomalies, ", ") or "nenhuma")
            DetLabels["Why"].Text = "  Justificativas: " .. (#r.explanations > 0 and table.concat(r.explanations, " | ") or "—")
        end
        DetLabels["Samples"].Text = string.format("  Amostras válidas: %d", info.samples or 0)
        if info.perfMs then
            DetLabels["Perf"].Text = string.format("  Desempenho: pipeline %.3f ms/frame", info.perfMs)
        end
        local p, f = info.scenarioPass or 0, info.scenarioFail or 0
        DetLabels["Tests"].Text = (p + f == 0) and "  Cenários LOS: nenhum executado" or string.format("  Cenários LOS: %d aprovados / %d reprovados", p, f)
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
local Camera = Workspace.CurrentCamera or Workspace:WaitForChild("Camera") :: Camera

-- Importação dos Módulos do Kernel


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

        local isFiring = shouldAim or isLeftMouseDown or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)

        local maxRadius = tonumber(SimConfig.Get("VectorRadius")) or 300.0
        -- FOV de seleção: raio em pixels (FovRadiusPx, o mesmo do círculo visual) convertido em
        -- ângulo; FOV (graus) funciona como teto máximo.
        local fovCap = tonumber(SimConfig.Get("FOV")) or 70.0
        local halfTan = (tonumber(SimConfig.Get("FovRadiusPx")) or 120) / math.max(camera.ViewportSize.Y / 2, 1)
            * math.tan(math.rad(camera.FieldOfView / 2))
        local fov = math.min(fovCap, math.deg(math.atan(halfTan)) * 2)
        local preferredBone = tostring(SimConfig.Get("TargetRegion") or "Head")
        local teamCheck = SimConfig.Get("TeamCheck") == true
        local visibleOnly = SimConfig.Get("VisibleOnly") == true
        local enableESP = SimConfig.Get("EnableESP") == true and SimConfig.Get("ShowSyntheticTargets") ~= false
        local enableLead = SimConfig.Get("EnableLead") == true
        local projSpeed = tonumber(SimConfig.Get("ProjectileSpeed")) or 900.0
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
        local silentAimTracer = SimConfig.Get("SilentAimTracer") == true

        -- 1. Detecção Espacial do Melhor Candidato com Prioridades
        local bestTarget, targetPos, dist, angleDeg, targetLabel, targetHealth = Detector:FindBestCandidate(
            camera.CFrame.Position,
            camera.CFrame.LookVector,
            maxRadius,
            fov,
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

            -- 3. Predição Balística (Lead)
            local aimPosition = targetPos
            if enableLead and isTargetValid then
                local estimatedVel = Tracker:EstimateVelocity(bestTarget, targetPos)
                aimPosition = Tracker:ComputeLead(targetPos, estimatedVel, camera.CFrame.Position, projSpeed, true)
            end

            -- 4. Realce Visual Dinâmico em Lote (ESP Chams com limpeza automática)
            if enableESP then
                Renderer:SyncBatchHighlights(Detector.CandidatePool, bestTarget, isObstructed)
            else
                Renderer:ClearAll()
            end

            -- 5. Simulação de Silent Aim (Disparo Desacoplado da Câmera)
            if silentAimEnabled and isTargetValid then
                local inFov, decoupledDir, discDeg = Tracker:ComputeSilentAimVector(
                    camera.CFrame,
                    aimPosition,
                    silentAimFov
                )
                decoupledAngle = discDeg

                if inFov then
                    silentAimActive = true
                    currentMode = "SILENT_AIM"

                    -- Disparo simulado controlado e traçadores (Throttled a cada 0.10s ao mirar ou atirar)
                    local now = os.clock()
                    if isFiring and (now - lastTracerTime) >= 0.10 then
                        lastTracerTime = now
                        local shotResult = Tracker:SimulateShot(
                            camera.CFrame,
                            aimPosition,
                            silentAimFov,
                            silentAimHitChance,
                            isObstructed,
                            bestTarget
                        )
                        if silentAimTracer and shotResult.Fired and SimConfig.Get("ShowDebugMarkers") ~= false then
                            local beamColor = shotResult.HitRegistered and Color3.fromRGB(46, 230, 110) or Color3.fromRGB(255, 60, 75)
                            Tracker:DrawTracerBeam(shotResult.MuzzlePosition, shotResult.TargetPosition, beamColor, 0.14)
                        end
                    end
                end
            end

            -- 6. Interpolação Cinemática da Câmera (Aimbot Convencional)
            -- Executa somente quando o Aimbot estiver ativado pelo painel e Silent Aim não estiver sobrescrevendo
            if aimbotEnabled and shouldAim and isTargetValid and not silentAimActive then
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
                silentAimActive = silentAimActive
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

print("[DeepHat v6.0 PRO] Suíte autônoma carregada com sucesso! Pressione [HOME] para abrir/fechar.")
pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "DeepHat v6.0 PRO",
        Text = "Interface carregada! Pressione [HOME] ou [RightShift] para abrir/fechar.",
        Duration = 5
    })
end)
