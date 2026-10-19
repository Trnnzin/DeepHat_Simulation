--!strict
-- InstanceDetector.lua
-- Pilar 1: Motor de Detecção de Instâncias de Alta Precisão (Targeting Engine)
-- Type Guarding estrito, Hierarquia Profunda, :GetPivot() e Filtro de Magnitude

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local InstanceDetector = {}
InstanceDetector.__index = InstanceDetector

export type CandidateTarget = {
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
        if self:IsValidTarget(inst, teamCheck) and not seen[inst] then
            seen[inst] = true
            table.insert(newPool, inst)
        end
    end

    -- 1. Jogadores
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= self.LocalPlayer and p.Character then
            Ingest(p.Character)
        end
    end

    -- 2. Pastas estruturadas
    for _, folderName in ipairs(self.SearchFolders) do
        local container = Workspace:FindFirstChild(folderName)
        if container then
            for _, child in ipairs(container:GetChildren()) do
                if child:IsA("Model") or child:IsA("BasePart") then Ingest(child) end
            end
            for _, desc in ipairs(container:GetDescendants()) do
                if desc:IsA("Model") or desc:IsA("BasePart") then Ingest(desc) end
            end
        end
    end

    -- 3. CollectionService Tags
    for _, tag in ipairs(self.KnownTags) do
        local okTagged, taggedList = pcall(function() return CollectionService:GetTagged(tag) end)
        if okTagged and taggedList then
            for _, tagged in ipairs(taggedList) do
                if tagged:IsA("Model") or tagged:IsA("BasePart") then Ingest(tagged) end
            end
        end
    end

    -- 4. Filhos da raiz do Workspace
    for _, child in ipairs(Workspace:GetChildren()) do
        if child:IsA("Model") then
            local hasHum = child:FindFirstChildOfClass("Humanoid")
            local name = child.Name:lower()
            if hasHum or name:find("dummy") or name:find("npc") or name:find("enemy") or name:find("target") or name:find("bot") then
                Ingest(child)
            end
        elseif child:IsA("BasePart") then
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

    for _, obj in ipairs(candidates) do
        local pos, _, label = self:ResolvePivotPosition(obj, preferredBone)
        if pos then
            local displacement = (pos - originPos)
            local dist = displacement.Magnitude

            -- Filtro de Raio
            if dist <= maxRadius and dist >= 0.05 then
                local dir = displacement / dist
                local dot = math.clamp(camLookVector:Dot(dir), -1.0, 1.0)
                local angleDeg = math.deg(math.acos(dot))

                -- Filtro de Campo de Visão (FOV)
                if angleDeg <= maxFovDeg then
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

                    -- Bônus de Stickiness para o alvo atualmente travado (evita alternância errática / flickering)
                    if isStickyActive and obj == self.LockedTarget then
                        score = score * 0.65
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

return InstanceDetector
