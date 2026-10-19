--!strict
-- =========================================================================
-- DeepHat_Standalone.lua (v6.0 PRO - Kernel-Level Kinematic & Diagnostics Suite)
-- Motor Autônomo Consolidado para Roblox Studio & Injeção de Cliente
-- Arquitetura: Dark Mode + Red Accents, 8 Abas Funcionais, Watchdog de Fundo,
-- Detecção de Instâncias Universal, Proteção Epsilon (1e-4) e ESP Highlights
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

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera or Workspace:WaitForChild("Camera") :: Camera

-- =========================================================================
-- [1] MÓDULO: SimConfig (Central Reativa com Observer Pattern)
-- =========================================================================
local SimConfig = {}
do
    local PROFILES: { [string]: any } = {
        ["Normal"] = {
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
            TargetRegion = "Head",
            TargetBone = "Head",
            WatchdogEnabled = true,
            DebugLogging = false,
        },
        ["Leve"] = {
            SimulationActive = true,
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
            TargetRegion = "Torso",
            TargetBone = "Torso",
            WatchdogEnabled = true,
            DebugLogging = false,
        },
        ["Medio"] = {
            SimulationActive = true,
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
            TargetRegion = "Head",
            TargetBone = "Head",
            WatchdogEnabled = true,
            DebugLogging = false,
        },
        ["Agressivo"] = {
            SimulationActive = true,
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
            TargetRegion = "Head",
            TargetBone = "Head",
            WatchdogEnabled = true,
            DebugLogging = true,
        },
        ["Custom"] = {
            SimulationActive = true,
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
            TargetRegion = "Head",
            TargetBone = "Head",
            WatchdogEnabled = true,
            DebugLogging = false,
        }
    }

    local CurrentState: { [string]: any } = {}
    for k, v in pairs(PROFILES["Normal"]) do
        CurrentState[k] = v
    end

    local KeyListeners: { [string]: { (any) -> () } } = {}
    local GlobalListeners: { (string, any) -> () } = {}

    function SimConfig.Get(key: string): any
        return CurrentState[key]
    end

    function SimConfig.Set(key: string, value: any, silent: boolean?)
        if CurrentState[key] == value then return end
        CurrentState[key] = value

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
        if not KeyListeners[key] then KeyListeners[key] = {} end
        table.insert(KeyListeners[key], callback)
        return function()
            local list = KeyListeners[key]
            if not list then return end
            local idx = table.find(list, callback)
            if idx then table.remove(list, idx) end
        end
    end

    function SimConfig.SubscribeAll(callback: (string, any) -> ()): () -> ()
        table.insert(GlobalListeners, callback)
        return function()
            local idx = table.find(GlobalListeners, callback)
            if idx then table.remove(GlobalListeners, idx) end
        end
    end

    function SimConfig.LoadProfile(profileName: string)
        local profile = PROFILES[profileName]
        if not profile then return end
        for k, v in pairs(profile) do
            if k ~= "SimulationActive" and k ~= "ActiveTab" then
                CurrentState[k] = v
                SimConfig.Notify(k, v)
            end
        end
    end

    function SimConfig.ExportJSON(): string
        local ok, encoded = pcall(function() return HttpService:JSONEncode(CurrentState) end)
        return ok and encoded or "{}"
    end
end

-- =========================================================================
-- [2] MÓDULO: InstanceDetector (Detecção Universal de Entidades)
-- =========================================================================
local InstanceDetector = {}
InstanceDetector.__index = InstanceDetector
do
    function InstanceDetector.new(scanInterval: number?)
        local self = setmetatable({}, InstanceDetector)
        self.ScanInterval = scanInterval or 0.12
        self.LastScanTime = 0
        self.CandidatePool = {} :: { Instance }
        self.KnownTags = { "NPC", "Enemy", "Target", "Zombie", "Bot", "Dummy", "Entity", "Character", "Hitbox" }
        self.SearchFolders = { "NPCs", "Enemies", "Characters", "Zombies", "Bots", "Dummies", "Entities", "Targets" }
        return self
    end

    function InstanceDetector:IsValidTarget(objeto: Instance, teamCheck: boolean?): boolean
        if not objeto or not (objeto:IsA("BasePart") or objeto:IsA("Model")) or not objeto:IsDescendantOf(game) then
            return false
        end
        local myChar = LocalPlayer and LocalPlayer.Character
        if myChar and (objeto == myChar or objeto:IsDescendantOf(myChar)) then
            return false
        end
        if objeto:IsA("Terrain") or objeto.Name == "Terrain" or objeto.Name == "Baseplate" then
            return false
        end
        local hum = objeto:FindFirstChildOfClass("Humanoid") or (objeto:IsA("Model") and objeto:FindFirstChildWhichIsA("Humanoid", true))
        if hum and hum.Health <= 0 then
            return false
        end
        if teamCheck and LocalPlayer and LocalPlayer.Team then
            local otherPlayer = Players:GetPlayerFromCharacter(objeto)
            if otherPlayer and otherPlayer.Team == LocalPlayer.Team then
                return false
            end
        end
        return true
    end

    function InstanceDetector:ResolvePivotPosition(objeto: Instance, preferredBone: string?): (Vector3?, BasePart?, string)
        if not self:IsValidTarget(objeto) then
            return nil, nil, "None"
        end
        if objeto:IsA("BasePart") then
            return objeto.Position, objeto, objeto.Name
        end

        local model = objeto :: Model
        local bone = string.lower(preferredBone or "head")
        local targetPart: BasePart? = nil
        local label = "Pivot"

        if bone == "head" then
            targetPart = model:FindFirstChild("Head", true) :: BasePart? or model:FindFirstChild("head", true) :: BasePart?
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
            label = "Arms"
        elseif bone == "legs" then
            targetPart = model:FindFirstChild("RightUpperLeg", true) :: BasePart?
                or model:FindFirstChild("RightLeg", true) :: BasePart?
                or model:FindFirstChild("LeftUpperLeg", true) :: BasePart?
            label = "Legs"
        end

        if not targetPart then
            targetPart = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart", true) :: BasePart? or model:FindFirstChildWhichIsA("BasePart", true)
            if targetPart then label = targetPart.Name end
        end

        if targetPart then
            return targetPart.Position, targetPart, label
        end

        local ok, pivot = pcall(function() return model:GetPivot() end)
        if ok and pivot then return pivot.Position, nil, "Pivot" end
        return nil, nil, "None"
    end

    function InstanceDetector:ScanCandidates(teamCheck: boolean?): { Instance }
        local now = os.clock()
        if (now - self.LastScanTime < self.ScanInterval) and #self.CandidatePool > 0 then
            return self.CandidatePool
        end
        self.LastScanTime = now
        local newPool: { Instance } = {}
        local seen: { [Instance]: boolean } = {}

        local function Ingest(inst: Instance)
            if self:IsValidTarget(inst, teamCheck) and not seen[inst] then
                seen[inst] = true
                table.insert(newPool, inst)
            end
        end

        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character then Ingest(p.Character) end
        end

        for _, folderName in ipairs(self.SearchFolders) do
            local container = Workspace:FindFirstChild(folderName)
            if container then
                for _, child in ipairs(container:GetChildren()) do
                    if child:IsA("Model") or child:IsA("BasePart") then Ingest(child) end
                end
            end
        end

        for _, tag in ipairs(self.KnownTags) do
            local okTagged, taggedList = pcall(function() return CollectionService:GetTagged(tag) end)
            if okTagged and taggedList then
                for _, tagged in ipairs(taggedList) do
                    if tagged:IsA("Model") or tagged:IsA("BasePart") then Ingest(tagged) end
                end
            end
        end

        for _, child in ipairs(Workspace:GetChildren()) do
            if child:IsA("Model") then
                local hasHum = child:FindFirstChildOfClass("Humanoid")
                local name = child.Name:lower()
                if hasHum or name:find("dummy") or name:find("npc") or name:find("enemy") or name:find("bot") then
                    Ingest(child)
                end
            end
        end

        self.CandidatePool = newPool
        return self.CandidatePool
    end

    function InstanceDetector:FindBestCandidate(
        originPos: Vector3,
        camLookVector: Vector3,
        maxRadius: number,
        maxFovDeg: number,
        preferredBone: string?,
        teamCheck: boolean?
    ): (Instance?, Vector3?, number, number, string)
        local candidates = self:ScanCandidates(teamCheck)
        local bestTarget: Instance? = nil
        local bestPos: Vector3? = nil
        local bestAngle = maxFovDeg
        local bestDist = maxRadius
        local bestLabel = "None"

        for _, obj in ipairs(candidates) do
            local pos, _, label = self:ResolvePivotPosition(obj, preferredBone)
            if pos then
                local displacement = (pos - originPos)
                local dist = displacement.Magnitude
                if dist <= maxRadius and dist >= 0.05 then
                    local dir = displacement / dist
                    local dot = math.clamp(camLookVector:Dot(dir), -1.0, 1.0)
                    local angleDeg = math.deg(math.acos(dot))
                    if angleDeg <= bestAngle then
                        bestAngle = angleDeg
                        bestTarget = obj
                        bestPos = pos
                        bestDist = dist
                        bestLabel = label
                    end
                end
            end
        end

        return bestTarget, bestPos, bestDist, bestAngle, bestLabel
    end
end

-- =========================================================================
-- [3] MÓDULO: VectorTracker (Cinemática Avançada & Predição)
-- =========================================================================
local VectorTracker = {}
VectorTracker.__index = VectorTracker
do
    local EPSILON = 1e-4

    function VectorTracker.new(filterInstances: { Instance }?)
        local self = setmetatable({}, VectorTracker)
        self.CurrentCFrame = CFrame.identity
        self.PreviousLookVector = Vector3.zAxis
        self.NoiseSeed = math.random(1000, 9999)
        self.VelocityCache = setmetatable({}, { __mode = "k" }) :: { [Instance]: { pos: Vector3, time: number, vel: Vector3 } }

        local rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Exclude
        rayParams.FilterDescendantsInstances = filterInstances or {}
        rayParams.IgnoreWater = true
        self.RayParams = rayParams
        return self
    end

    function VectorTracker:SetFilterInstances(instances: { Instance })
        self.RayParams.FilterDescendantsInstances = instances
    end

    function VectorTracker:CheckObstruction(originPos: Vector3, targetPos: Vector3): boolean
        local displacement = (targetPos - originPos)
        local dist = displacement.Magnitude
        if dist < EPSILON then return false end
        local dir = displacement / dist
        local result = Workspace:Raycast(originPos, dir * dist, self.RayParams)
        return (result ~= nil)
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
        if not enabled or projSpeed <= 0 then return targetPos end
        local dist = (targetPos - eyePos).Magnitude
        return targetPos + (targetVel * (dist / projSpeed))
    end

    function VectorTracker:ComputeSmoothRotation(
        currentCFrame: CFrame,
        targetPosition: Vector3,
        dt: number,
        smoothingFactor: number,
        accelExponent: number?,
        simulateJitter: boolean?,
        intensity: number?
    ): (CFrame, number, number)
        local originPos = currentCFrame.Position
        local displacement = (targetPosition - originPos)
        local distance = displacement.Magnitude
        if distance < EPSILON then return currentCFrame, 0, 0 end

        local safeDt = math.clamp(dt or 0.0166, 0.0001, 0.1)
        local unitDirection = displacement / distance
        local forward = currentCFrame.LookVector
        local dot = math.clamp(forward:Dot(unitDirection), -1.0, 1.0)
        local angularErrorDeg = math.deg(math.acos(dot))

        local targetRotation = CFrame.lookAt(originPos, targetPosition, Vector3.yAxis)

        local normErr = math.clamp(angularErrorDeg / 70.0, 0.0, 1.0)
        local hermiteFactor = normErr * normErr * (3.0 - 2.0 * normErr)
        hermiteFactor = math.pow(hermiteFactor, accelExponent or 1.25)

        local baseAlpha = math.clamp(smoothingFactor or 0.15, 0.005, 1.0)
        local k = (baseAlpha * 26.0) * (0.35 + 0.65 * hermiteFactor)
        local dynamicAlpha = math.clamp(1.0 - math.exp(-k * safeDt), 0.001, 1.0)

        local smoothedCFrame = currentCFrame:Lerp(targetRotation, dynamicAlpha)

        if simulateJitter and intensity and intensity > 0 then
            local now = os.clock()
            local jitterFactor = (intensity / 100.0) * math.clamp(angularErrorDeg / 15.0, 0.0, 1.0) * 0.3
            if jitterFactor > 0.01 then
                local noiseX = math.noise(now * 4.0, self.NoiseSeed, 0.5) * jitterFactor
                local noiseY = math.noise(now * 4.0, self.NoiseSeed + 50, 0.5) * jitterFactor
                smoothedCFrame = smoothedCFrame * CFrame.Angles(math.rad(noiseX), math.rad(noiseY), 0)
            end
        end

        local newLook = smoothedCFrame.LookVector
        local deltaDot = math.clamp(self.PreviousLookVector:Dot(newLook), -1.0, 1.0)
        local deltaAngleDeg = math.deg(math.acos(deltaDot))
        local angularVelocity = deltaAngleDeg / safeDt

        self.PreviousLookVector = newLook
        self.CurrentCFrame = smoothedCFrame
        return smoothedCFrame, angularErrorDeg, angularVelocity
    end

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
end

-- =========================================================================
-- [4] MÓDULO: VisualOverlayRenderer (Realce ESP Chams)
-- =========================================================================
local VisualOverlayRenderer = {}
VisualOverlayRenderer.__index = VisualOverlayRenderer
do
    local MAX_ACTIVE_HIGHLIGHTS = 16

    function VisualOverlayRenderer.new()
        local self = setmetatable({}, VisualOverlayRenderer)
        self.ActiveHighlights = setmetatable({}, { __mode = "k" }) :: { [Instance]: Highlight }
        self.Container = self:GetOrCreateContainer()
        return self
    end

    function VisualOverlayRenderer:GetOrCreateContainer(): Folder
        local host: Instance = CoreGuiService
        local ok, _ = pcall(function() return CoreGuiService:GetChildren() end)
        if not ok then
            local pGui = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
            host = pGui or Workspace
        end
        local existing = host:FindFirstChild("DeepHat_ESP_Container")
        if existing and existing:IsA("Folder") then return existing end

        local folder = Instance.new("Folder")
        folder.Name = "DeepHat_ESP_Container"
        folder.Parent = host
        return folder
    end

    function VisualOverlayRenderer:UpdateTargetHighlight(target: Instance, isObstructed: boolean, isPrimary: boolean)
        if not target or not target:IsDescendantOf(game) then
            self:ClearTarget(target)
            return
        end

        local hl = self.ActiveHighlights[target]
        if not hl or not hl.Parent then
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
            end
        end

        if hl then
            pcall(function()
                hl.Adornee = target
                hl.Enabled = true
                hl.FillTransparency = isPrimary and 0.35 or 0.65
                hl.OutlineTransparency = 0.05
                hl.FillColor = isObstructed and Color3.fromRGB(240, 50, 50) or Color3.fromRGB(46, 230, 110)
                hl.OutlineColor = isObstructed and Color3.fromRGB(255, 180, 180) or Color3.fromRGB(200, 255, 200)
            end)
        end
    end

    function VisualOverlayRenderer:ClearTarget(target: Instance?)
        if not target then return end
        local hl = self.ActiveHighlights[target]
        if hl then pcall(function() hl:Destroy() end) end
        self.ActiveHighlights[target] = nil
    end

    function VisualOverlayRenderer:ClearAll()
        for _, hl in pairs(self.ActiveHighlights) do
            pcall(function() if hl then hl:Destroy() end end)
        end
        table.clear(self.ActiveHighlights)
    end
end

-- =========================================================================
-- [5] INICIALIZAÇÃO DA INTERFACE MODERNA E LOOP DE EXECUÇÃO
-- =========================================================================
local DashboardGUI = require(script.Parent.ModularSystem.DashboardGUI)
DashboardGUI.Create()

local filterInstances: { Instance } = {}
if LocalPlayer.Character then table.insert(filterInstances, LocalPlayer.Character) end

local Detector = InstanceDetector.new(0.12)
local Tracker = VectorTracker.new(filterInstances)
local Renderer = VisualOverlayRenderer.new()

LocalPlayer.CharacterAdded:Connect(function(char)
    table.clear(filterInstances)
    table.insert(filterInstances, char)
    Tracker:SetFilterInstances(filterInstances)
end)

local isRightMouseDown = false
UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then isRightMouseDown = true end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then isRightMouseDown = false end
end)

local BIND_NAME = "DeepHat_StandaloneKernelPipeline"
pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)

local lastTelemetryTime = 0
RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt: number)
    pcall(function()
        local camera = Workspace.CurrentCamera
        if not camera then return end

        local isActive = SimConfig.Get("SimulationActive") == true
        if not isActive then
            Renderer:ClearAll()
            return
        end

        local holdToAim = SimConfig.Get("HoldToAim") == true
        local isRmbHeld = isRightMouseDown or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
        local shouldAim = (not holdToAim) or isRmbHeld

        local maxRadius = tonumber(SimConfig.Get("VectorRadius")) or 300.0
        local fov = tonumber(SimConfig.Get("FOV")) or 70.0
        local preferredBone = tostring(SimConfig.Get("TargetRegion") or "Head")
        local teamCheck = SimConfig.Get("TeamCheck") == true
        local visibleOnly = SimConfig.Get("VisibleOnly") == true
        local enableESP = SimConfig.Get("EnableESP") == true
        local enableLead = SimConfig.Get("EnableLead") == true
        local projSpeed = tonumber(SimConfig.Get("ProjectileSpeed")) or 900.0
        local smoothing = tonumber(SimConfig.Get("Smoothing")) or 0.15
        local accelExp = tonumber(SimConfig.Get("AccelerationCurve")) or 1.25
        local simulateJitter = SimConfig.Get("SimulateJitter") == true
        local intensity = tonumber(SimConfig.Get("Intensity")) or 75.0

        local bestTarget, targetPos, _, _, targetLabel = Detector:FindBestCandidate(
            camera.CFrame.Position,
            camera.CFrame.LookVector,
            maxRadius,
            fov,
            preferredBone,
            teamCheck
        )

        local isObstructed = false
        local targetName = "NENHUM"
        local calculatedAngVel = 0
        local currentMode = "IDLE"

        if bestTarget and targetPos then
            targetName = string.format("%s (%s)", bestTarget.Name, targetLabel)
            isObstructed = Tracker:CheckObstruction(camera.CFrame.Position, targetPos)

            local isTargetValid = true
            if visibleOnly and isObstructed then isTargetValid = false end

            local aimPosition = targetPos
            if enableLead and isTargetValid then
                local vel = Tracker:EstimateVelocity(bestTarget, targetPos)
                aimPosition = Tracker:ComputeLead(targetPos, vel, camera.CFrame.Position, projSpeed, true)
            end

            if enableESP then
                Renderer:UpdateTargetHighlight(bestTarget, isObstructed, true)
            else
                Renderer:ClearAll()
            end

            if shouldAim and isTargetValid then
                currentMode = "TRACKING"
                local smoothedCFrame, _, angVel = Tracker:ComputeSmoothRotation(
                    camera.CFrame,
                    aimPosition,
                    dt,
                    smoothing,
                    accelExp,
                    simulateJitter,
                    intensity
                )
                camera.CFrame = smoothedCFrame
                calculatedAngVel = angVel
            end
        else
            Renderer:ClearAll()
        end

        local now = os.clock()
        if (now - lastTelemetryTime) >= 0.05 then
            lastTelemetryTime = now
            DashboardGUI:UpdateTelemetryDisplay({
                angularVelocity = calculatedAngVel,
                isObstructed = isObstructed,
                targetName = targetName,
                dt = dt,
                mode = currentMode
            })
            DashboardGUI:UpdateFovCircle()
        end
    end)
end)

print("[DeepHat v6.0 PRO] Suíte autônoma carregada com sucesso! Pressione [HOME] para abrir/fechar.")
pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "DeepHat v6.0 PRO",
        Text = "Interface carregada! Pressione [HOME] ou [RightShift] para abrir/fechar.",
        Duration = 5
    })
end)
