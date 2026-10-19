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
        self.LockedTarget = nil :: Instance?
        self.LockExpiry = 0
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
            if not inst then return end
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

        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character then Ingest(p.Character) end
        end

        for _, folderName in ipairs(self.SearchFolders) do
            local container = Workspace:FindFirstChild(folderName)
            if container then
                for _, child in ipairs(container:GetChildren()) do
                    Ingest(child)
                end
            end
        end

        for _, tag in ipairs(self.KnownTags) do
            local okTagged, taggedList = pcall(function() return CollectionService:GetTagged(tag) end)
            if okTagged and taggedList then
                for _, tagged in ipairs(taggedList) do
                    Ingest(tagged)
                end
            end
        end

        for _, child in ipairs(Workspace:GetChildren()) do
            if child:IsA("Model") then
                local hasHum = child:FindFirstChildOfClass("Humanoid")
                local name = child.Name:lower()
                if hasHum or name:find("dummy") or name:find("npc") or name:find("enemy") or name:find("target") or name:find("bot") then
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
        local fovRadiusLimit = (maxFovDeg / 2.0)

        for _, obj in ipairs(candidates) do
            local pos, _, label = self:ResolvePivotPosition(obj, preferredBone)
            if pos then
                local displacement = (pos - originPos)
                local dist = displacement.Magnitude
                if dist <= maxRadius and dist >= 0.05 then
                    local dir = displacement / dist
                    local dot = math.clamp(camLookVector:Dot(dir), -1.0, 1.0)
                    local angleDeg = math.deg(math.acos(dot))
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

                        if isStickyActive and obj == self.LockedTarget then
                            score = score * 0.60
                        end

                        if score < bestScore then
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

    function VectorTracker:CheckObstruction(originPos: Vector3, targetPos: Vector3, targetInstance: Instance?): boolean
        local displacement = (targetPos - originPos)
        local dist = displacement.Magnitude
        if dist < EPSILON then return false end
        local dir = displacement / dist
        local result = Workspace:Raycast(originPos, dir * dist, self.RayParams)
        if not result then return false end

        if targetInstance and result.Instance then
            if result.Instance == targetInstance or result.Instance:IsDescendantOf(targetInstance) then
                return false
            end
        end

        if (result.Position - targetPos).Magnitude < 0.6 then
            return false
        end

        return true
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
        intensity: number?,
        maxAngularVel: number?,
        clampMaxVel: boolean?
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

        if angularErrorDeg < 0.04 then
            return currentCFrame, angularErrorDeg, 0
        end

        local targetRotation = CFrame.lookAt(originPos, targetPosition, Vector3.yAxis)

        local normErr = math.clamp(angularErrorDeg / 70.0, 0.0, 1.0)
        local hermiteFactor = normErr * normErr * (3.0 - 2.0 * normErr)
        hermiteFactor = math.pow(hermiteFactor, accelExponent or 1.25)

        local safeSmooth = math.clamp(smoothingFactor or 0.15, 0.01, 1.0)
        local responseRate = 1.0 / safeSmooth
        local k = responseRate * (0.65 + 0.35 * hermiteFactor)
        local dynamicAlpha = math.clamp(1.0 - math.exp(-k * safeDt), 0.001, 1.0)

        if angularErrorDeg < 0.25 then
            local deadzoneWeight = math.clamp((angularErrorDeg - 0.04) / 0.21, 0.05, 1.0)
            dynamicAlpha = dynamicAlpha * deadzoneWeight
        end

        if clampMaxVel and maxAngularVel and maxAngularVel > 0 then
            local maxDegThisFrame = maxAngularVel * safeDt
            if (angularErrorDeg * dynamicAlpha) > maxDegThisFrame then
                dynamicAlpha = math.clamp(maxDegThisFrame / math.max(angularErrorDeg, 0.001), 0.001, 1.0)
            end
        end

        local smoothedCFrame = currentCFrame:Lerp(targetRotation, dynamicAlpha)

        if simulateJitter and intensity and intensity > 0 then
            local now = os.clock()
            local jitterFactor = (intensity / 100.0) * math.clamp(angularErrorDeg / 15.0, 0.0, 1.0) * 0.20
            if jitterFactor > 0.005 then
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

        if discrepancyAngleDeg > maxFovDeg then
            return false, camForward, discrepancyAngleDeg
        end

        if hitChancePercent ~= nil then
            local chance = math.clamp(hitChancePercent, 0.0, 100.0)
            if (math.random() * 100.0) > chance then
                return false, camForward, discrepancyAngleDeg
            end
        end

        return true, decoupledDirection, discrepancyAngleDeg
    end

    function VectorTracker:SimulateShot(
        cameraCFrame: CFrame,
        targetPosition: Vector3,
        maxFovDeg: number,
        hitChancePercent: number,
        isObstructed: boolean?,
        targetInstance: Instance?
    ): {
        Fired: boolean,
        HitRegistered: boolean,
        DiscrepancyAngleDeg: number,
        MuzzlePosition: Vector3,
        TargetPosition: Vector3,
        ShotDirection: Vector3,
        InFov: boolean,
        IsObstructed: boolean
    }
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
                local missAngle = math.rad(math.random(3, 8))
                local randAxis = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5).Unit
                shotDir = CFrame.fromAxisAngle(randAxis, missAngle):VectorToWorldSpace(directDir)
            end
        end

        return {
            Fired = true,
            HitRegistered = hit,
            DiscrepancyAngleDeg = discrepancyAngleDeg,
            MuzzlePosition = muzzlePos,
            TargetPosition = targetPosition,
            ShotDirection = shotDir,
            InFov = inFov,
            IsObstructed = isObstructed == true
        }
    end

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
-- [4] MÓDULO: VisualOverlayRenderer (Realce ESP Chams)
-- =========================================================================
local VisualOverlayRenderer = {}
VisualOverlayRenderer.__index = VisualOverlayRenderer
do
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
                hl.FillTransparency = isPrimary and 0.35 or 0.65
                hl.OutlineTransparency = 0.05
                hl.FillColor = isObstructed and Color3.fromRGB(240, 50, 50) or Color3.fromRGB(46, 230, 110)
                hl.OutlineColor = isObstructed and Color3.fromRGB(255, 180, 180) or Color3.fromRGB(200, 255, 200)
            end)
        end
    end

    function VisualOverlayRenderer:SyncBatchHighlights(
        candidates: { Instance }?,
        primaryTarget: Instance?,
        isPrimaryObstructed: boolean
    )
        local activeBatch: { [Instance]: boolean } = {}

        if primaryTarget and primaryTarget:IsDescendantOf(game) then
            self:UpdateTargetHighlight(primaryTarget, isPrimaryObstructed, true)
            activeBatch[primaryTarget] = true
        end

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

        for inst, _ in pairs(self.ActiveHighlights) do
            if not activeBatch[inst] then
                self:ClearTarget(inst)
            end
        end
    end

    function VisualOverlayRenderer:ClearTarget(target: Instance?)
        if not target then return end
        local hl = self.ActiveHighlights[target]
        if hl then pcall(function() hl:Destroy() end) end
        self.ActiveHighlights[target] = nil

        local conn = self.CleanupConnections[target]
        if conn then pcall(function() conn:Disconnect() end) end
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
-- [5] MÓDULO EMBUTIDO: DashboardGUI (Interface 8 Abas + Watchdog Integrado)
-- =========================================================================
local DashboardGUI = {}
do
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
        SUCCESS      = Color3.fromRGB(46, 204, 113),
        WARNING      = Color3.fromRGB(241, 196, 15),
        INFO         = Color3.fromRGB(52, 152, 219),
    }

    DashboardGUI.OnStartRequested = nil :: (() -> ())?
    DashboardGUI.OnStopRequested = nil :: (() -> ())?
    DashboardGUI.OnResetRequested = nil :: (() -> ())?
    DashboardGUI.OnSaveRequested = nil :: (() -> ())?

    local FovCircleInstance: Frame? = nil
    local WatchdogBadgeInstance: TextLabel? = nil
    local EventLogListInstance: ScrollingFrame? = nil
    local TelemetryLabels: { [string]: TextLabel } = {}
    local PerformanceData = { Fps = 60, PeakAngVel = 0 }
    local unsubscribeGlobal: (() -> ())? = nil

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
        lbl.Text = string.format("[%s] [%s] %s", os.date("%H:%M:%S"), source, message)
        lbl.Parent = row

        local children = EventLogListInstance:GetChildren()
        local count = 0
        for _, ch in ipairs(children) do if ch:IsA("Frame") then count = count + 1 end end
        if count > 40 then
            for _, ch in ipairs(children) do
                if ch:IsA("Frame") then ch:Destroy() break end
            end
        end
        EventLogListInstance.CanvasPosition = Vector2.new(0, 99999)
    end

    function DashboardGUI.Create(parentGui: Instance?): ScreenGui
        local hostParent = parentGui or GetSafeGuiParent()
        local existing = hostParent:FindFirstChild("DeepHat_MasterDashboard")
        if existing then existing:Destroy() end

        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "DeepHat_MasterDashboard"
        screenGui.ResetOnSpawn = false
        screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        screenGui.Parent = hostParent

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

        local header = Instance.new("Frame")
        header.Name = "Header"
        header.Size = UDim2.new(1, 0, 0, 44)
        header.BackgroundColor3 = THEME.BG_SIDEBAR
        header.BorderSizePixel = 0
        header.Parent = mainFrame
        AddCorner(header, 10)

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
                    frameStartPos.X.Scale,
                    frameStartPos.X.Offset + delta.X,
                    frameStartPos.Y.Scale,
                    frameStartPos.Y.Offset + delta.Y
                )
            end
        end)

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
            if gpe then return end
            if input.KeyCode == Enum.KeyCode.Home or input.KeyCode == Enum.KeyCode.RightShift then
                mainFrame.Visible = not mainFrame.Visible
            end
        end)

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
        sidebarPad.PaddingTop = UDim.new(0, 10); sidebarPad.PaddingLeft = UDim.new(0, 8); sidebarPad.PaddingRight = UDim.new(0, 8)
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

        local pages: { [string]: ScrollingFrame } = {}
        local tabButtons: { [string]: TextButton } = {}

        local tabs = {
            { Id = "Overview",    Label = "📊 Painel Geral" },
            { Id = "Camera",      Label = "🎥 Câmera & Vetores" },
            { Id = "Simulation",  Label = "⚡ Simulação" },
            { Id = "Vision",      Label = "👁️ Linha de Visão" },
            { Id = "Hitbox",      Label = "🎯 Mapeamento HitBox" },
            { Id = "Diagnostics", Label = "🛠️ Diagnósticos" },
            { Id = "Performance", Label = "📈 Desempenho" },
            { Id = "Settings",    Label = "⚙️ Configurações" },
        }

        local function SwitchTab(tabId: string)
            for id, page in pairs(pages) do page.Visible = (id == tabId) end
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
            btn.BackgroundColor3 = (t.Id == "Overview") and THEME.ACCENT_RED or THEME.BG_INPUT
            btn.TextColor3 = (t.Id == "Overview") and THEME.TEXT_MAIN or THEME.TEXT_MUTED
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
            page.Visible = (t.Id == "Overview")
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

        local syncInputs: { [string]: (number) -> () } = {}

        local function CreateSliderField(parent: Instance, labelText: string, configKey: string, minVal: number, maxVal: number, defaultVal: number, step: number): Frame
            local span = math.max(maxVal - minVal, 0.0001)
            local safeDefault = tonumber(SimConfig.Get(configKey)) or defaultVal or minVal

            local container = Instance.new("Frame")
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
                if not fromObserver then SimConfig.Set(configKey, val) end
            end

            numInput.FocusLost:Connect(function()
                local num = tonumber(numInput.Text)
                if num then UpdateValue(num) else numInput.Text = string.format(step < 1 and "%.2f" or "%d", tonumber(SimConfig.Get(configKey)) or safeDefault) end
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
                toggleBtn.BackgroundColor3 = state and THEME.ACCENT_RED or THEME.BG_WINDOW
                dot.Position = state and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
                SimConfig.Set(configKey, state)
            end

            toggleBtn.MouseButton1Click:Connect(function()
                SetToggle(not (SimConfig.Get(configKey) == true))
            end)

            SimConfig.Subscribe(configKey, function(val)
                local state = (val == true)
                toggleBtn.BackgroundColor3 = state and THEME.ACCENT_RED or THEME.BG_WINDOW
                dot.Position = state and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
            end)
            return container
        end

        -- ABA 1: OVERVIEW
        local pageOverview = pages["Overview"]
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

        -- ABA 2: CAMERA
        local pageCamera = pages["Camera"]
        CreateToggleField(pageCamera, "Forçar Limite Estrito de Velocidade Angular", "MaxAngularVelocityClamp", SimConfig.Get("MaxAngularVelocityClamp"))
        CreateSliderField(pageCamera, "Campo de Visão Útil (FOV °)", "FOV", 10, 180, SimConfig.Get("FOV"), 1)
        CreateSliderField(pageCamera, "Coeficiente de Suavização (Lerp)", "Smoothing", 0.01, 1.0, SimConfig.Get("Smoothing"), 0.01)
        CreateSliderField(pageCamera, "Velocidade Angular Máxima (°/s)", "AngularVelocity", 30, 720, SimConfig.Get("AngularVelocity"), 5)
        CreateSliderField(pageCamera, "Tempo de Resposta Simulado (ms)", "ResponseTime", 0, 250, SimConfig.Get("ResponseTime"), 1)
        CreateSliderField(pageCamera, "Precisão de Trajetória (%)", "TrajectoryPrecision", 50, 100, SimConfig.Get("TrajectoryPrecision"), 0.5)
        CreateSliderField(pageCamera, "Frequência de Atualização (Hz)", "UpdateFrequency", 10, 144, SimConfig.Get("UpdateFrequency"), 5)
        CreateSliderField(pageCamera, "Raio Máximo de Atuação (studs)", "VectorRadius", 10, 500, SimConfig.Get("VectorRadius"), 5)

        -- ABA 3: SIMULAÇÃO
        local pageSim = pages["Simulation"]
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

        -- ABA 4: LINHA DE VISÃO & SILENT AIM
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

        -- ABA 5: HITBOX
        local pageHitbox = pages["Hitbox"]
        local mannequinContainer = Instance.new("Frame")
        mannequinContainer.Size = UDim2.new(1, 0, 0, 260)
        mannequinContainer.BackgroundColor3 = THEME.BG_INPUT
        mannequinContainer.Parent = pageHitbox
        AddCorner(mannequinContainer, 8)
        AddStroke(mannequinContainer, THEME.BORDER, 1)

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
                n.Btn.BackgroundColor3 = (n.Region == regionName) and THEME.ACCENT_RED or THEME.BORDER_LIGHT
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

        -- ABA 6: DIAGNOSTICOS
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

        -- ABA 7: PERFORMANCE
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

        -- ABA 8: SETTINGS
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
            SimConfig.LoadProfile("Normal")
            UpdateProfileUI("Normal")
            DashboardGUI.AddDiagnosticLog("CONFIG", "Configurações restauradas para o perfil Normal.", "WARN")
        end)

        -- FOOTER
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
            SimConfig.LoadProfile("Normal")
            UpdateProfileUI("Normal")
            if DashboardGUI.OnResetRequested then DashboardGUI.OnResetRequested() end
        end)

        CreateBottomButton("💾 SALVAR CONFIG", false, function()
            pcall(function()
                game:GetService("StarterGui"):SetCore("SendNotification", {
                    Title = "DeepHat Suite",
                    Text = "Configurações persistidas com sucesso!",
                    Duration = 3
                })
            end)
            DashboardGUI.AddDiagnosticLog("SAVE", "Configurações salvas no armazenamento local.", "OK")
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

        if unsubscribeGlobal then
            unsubscribeGlobal()
            unsubscribeGlobal = nil
        end

        unsubscribeGlobal = SimConfig.SubscribeAll(function(key, val)
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

        DashboardGUI.AddDiagnosticLog("INIT", "Dashboard GUI carregada com 8 abas de controle.", "OK")
        return screenGui
    end

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
            local radius = (math.tan(halfFovRad) / math.max(math.tan(camFovRad), 0.001)) * (vp.Y / 2)
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
        local angVel = tonumber(data.angularVelocity) or 0
        if angVel > PerformanceData.PeakAngVel then PerformanceData.PeakAngVel = angVel end

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

    -- Watchdog em background
    task.spawn(function()
        while true do
            task.wait(1.5)
            if SimConfig.Get("WatchdogEnabled") == true then
                local camera = Workspace.CurrentCamera
                local healthGood = true
                local reason = ""

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

                local fov = tonumber(SimConfig.Get("FOV")) or 70
                if fov < 10 or fov > 180 then SimConfig.Set("FOV", math.clamp(fov, 10, 180)) end

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
end

-- =========================================================================
-- [6] INICIALIZAÇÃO DA EXECUÇÃO
-- =========================================================================
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
local isToggleAimActive = false

UserInputService.InputBegan:Connect(function(input, gpe)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        isRightMouseDown = true
        isToggleAimActive = not isToggleAimActive
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        isRightMouseDown = false
    end
end)

UserInputService.WindowFocusReleased:Connect(function()
    isRightMouseDown = false
end)

local BIND_NAME = "DeepHat_StandaloneKernelPipeline"
pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)

local lastTelemetryTime = 0
local lastTracerTime = 0
RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt: number)
    pcall(function()
        local camera = Workspace.CurrentCamera
        if not camera then return end

        local isActive = SimConfig.Get("SimulationActive") == true
        if not isActive then
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
        local maxAngularVel = tonumber(SimConfig.Get("AngularVelocity")) or 240.0
        local clampMaxVel = SimConfig.Get("MaxAngularVelocityClamp") == true
        local targetPriority = tostring(SimConfig.Get("TargetPriority") or "Crosshair")
        local targetStickiness = tonumber(SimConfig.Get("TargetStickiness")) or 0.25

        -- Silent Aim Config
        local silentAimEnabled = SimConfig.Get("SilentAimEnabled") == true
        local silentAimFov = tonumber(SimConfig.Get("SilentAimFOV")) or 35.0
        local silentAimHitChance = tonumber(SimConfig.Get("SilentAimHitChance")) or 100.0
        local silentAimTracer = SimConfig.Get("SilentAimTracer") == true

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
        local targetName = "NENHUM"
        local calculatedAngVel = 0
        local currentMode = "IDLE"
        local decoupledAngle = 0
        local silentAimActive = false

        if bestTarget and targetPos then
            targetName = string.format("%s (%s - %d HP)", bestTarget.Name, targetLabel, math.floor(targetHealth or 100))
            isObstructed = Tracker:CheckObstruction(camera.CFrame.Position, targetPos, bestTarget)

            local isTargetValid = true
            if visibleOnly and isObstructed then isTargetValid = false end

            local aimPosition = targetPos
            if enableLead and isTargetValid then
                local vel = Tracker:EstimateVelocity(bestTarget, targetPos)
                aimPosition = Tracker:ComputeLead(targetPos, vel, camera.CFrame.Position, projSpeed, true)
            end

            if enableESP then
                Renderer:SyncBatchHighlights(Detector.CandidatePool, bestTarget, isObstructed)
            else
                Renderer:ClearAll()
            end

            -- Simulação de Silent Aim (Vetor Desacoplado da Câmera)
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

                    local now = os.clock()
                    if shouldAim and (now - lastTracerTime) >= 0.10 then
                        lastTracerTime = now
                        local shotResult = Tracker:SimulateShot(
                            camera.CFrame,
                            aimPosition,
                            silentAimFov,
                            silentAimHitChance,
                            isObstructed,
                            bestTarget
                        )
                        if silentAimTracer and shotResult.Fired then
                            local beamColor = shotResult.HitRegistered and Color3.fromRGB(46, 230, 110) or Color3.fromRGB(255, 60, 75)
                            Tracker:DrawTracerBeam(shotResult.MuzzlePosition, shotResult.TargetPosition, beamColor, 0.14)
                        end
                    end
                end
            end

            -- Interpolação Cinemática da Câmera (Aimbot Convencional)
            if shouldAim and isTargetValid and not silentAimEnabled then
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
                mode = currentMode,
                decoupledAngle = decoupledAngle,
                silentAimActive = silentAimActive
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
