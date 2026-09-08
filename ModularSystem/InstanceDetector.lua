--!strict
-- InstanceDetector.lua
-- Módulo 1: Scanner de Instâncias Robusto em Ambientes de Alta Complexidade
-- Implementa: Varredura com Debounce, Resolução de Posição via :GetPivot() e Filtros de Hierarquia

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local InstanceDetector = {}
InstanceDetector.__index = InstanceDetector

export type ResolvedTarget = {
    Position: Vector3,
    Model: Model,
    Part: BasePart?,
    Label: string,
    Distance: number,
    AngularErrorDeg: number,
    IsObstructed: boolean
}

function InstanceDetector.new(scanInterval: number?)
    local self = setmetatable({}, InstanceDetector)
    self.ScanInterval = scanInterval or 0.20 -- 5Hz de varredura topológica (Debounce de Performance)
    self.LastScanTime = 0
    self.CandidatePool = {} :: { Model }
    self.LocalPlayer = Players.LocalPlayer
    self.KnownTags = { "NPC", "Enemy", "Target", "Zombie", "Bot", "Dummy", "Entity", "Character" }
    self.SearchFolders = { "NPCs", "Enemies", "Characters", "Zombies", "Bots", "Dummies", "Mobs", "Entities", "Targets", "Spawns" }
    return self
end

-- Verifica se a instância é válida no grafo de cena e está viva
function InstanceDetector:IsValidTarget(model: Instance, teamCheck: boolean?): (boolean, Humanoid?)
    if not model or not model:IsA("Model") or not model:IsDescendantOf(game) then
        return false, nil
    end

    local myChar = self.LocalPlayer and self.LocalPlayer.Character
    if myChar and (model == myChar or model:IsDescendantOf(myChar)) then
        return false, nil
    end

    -- Requisito Crítico: Alvo deve possuir Humanoid ativo (Ignora geometria estática como Mapa, Prédios ou Chão)
    local hum = model:FindFirstChildOfClass("Humanoid") or model:FindFirstChildWhichIsA("Humanoid", true)
    if not hum or hum.Health <= 0 then
        return false, nil
    end

    -- Verificação de time para Players
    if teamCheck and self.LocalPlayer and self.LocalPlayer.Team then
        local otherPlayer = Players:GetPlayerFromCharacter(model)
        if otherPlayer and otherPlayer.Team == self.LocalPlayer.Team then
            return false, hum
        end
    end

    return true, hum
end

-- Resolução Afim de Posição: Extrai vetor 3D com fallback absoluto em :GetPivot().Position
function InstanceDetector:ResolvePivotPosition(model: Model, preferredBone: string?): (Vector3?, BasePart?, string)
    if not model or not model:IsDescendantOf(game) then
        return nil, nil, "None"
    end

    local bone = string.lower(preferredBone or "head")
    local targetPart: BasePart? = nil
    local label = "Pivot"

    -- 1. Resolução anatômica por prioridade de ossos (R6, R15 e Custom Rigs)
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
        targetPart = model:FindFirstChild("HumanoidRootPart", true) :: BasePart?
            or model:FindFirstChild("Head", true) :: BasePart?
            or model:FindFirstChild("Torso", true) :: BasePart?
            or model.PrimaryPart
            or model:FindFirstChildWhichIsA("BasePart", true)
        if targetPart then
            label = targetPart.Name
        end
    end

    if targetPart then
        return targetPart.Position, targetPart, label
    end

    -- 3. Resolução Universal Invariante: :GetPivot().Position (Garantido para qualquer Model/PVInstance)
    local ok, pivot = pcall(function() return model:GetPivot() end)
    if ok and pivot then
        return pivot.Position, nil, "Pivot"
    end

    return nil, nil, "None"
end

-- Varredura espacial desacoplada com Debounce para ambientes com alta densidade de objetos
function InstanceDetector:ScanCandidates(teamCheck: boolean?, forceRescan: boolean?): { Model }
    local now = os.clock()
    if not forceRescan and (now - self.LastScanTime < self.ScanInterval) and #self.CandidatePool > 0 then
        -- Valida se os candidatos em cache ainda estão no Workspace
        local verifiedPool: { Model } = {}
        for _, candidate in ipairs(self.CandidatePool) do
            local valid = self:IsValidTarget(candidate, teamCheck)
            if valid then
                table.insert(verifiedPool, candidate)
            end
        end
        self.CandidatePool = verifiedPool
        return self.CandidatePool
    end

    self.LastScanTime = now
    local newPool: { Model } = {}
    local seen: { [Model]: boolean } = {}

    local function IngestCandidate(inst: Instance)
        local valid = self:IsValidTarget(inst, teamCheck)
        if valid and not seen[inst :: Model] then
            seen[inst :: Model] = true
            table.insert(newPool, inst :: Model)
        end
    end

    -- 1. Varredura direta de Jogadores ativos
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= self.LocalPlayer and player.Character then
            IngestCandidate(player.Character)
        end
    end

    -- 2. Varredura em pastas estruturadas no Workspace
    for _, folderName in ipairs(self.SearchFolders) do
        local container = Workspace:FindFirstChild(folderName)
        if container then
            for _, child in ipairs(container:GetChildren()) do
                if child:IsA("Model") then
                    IngestCandidate(child)
                end
            end
            for _, desc in ipairs(container:GetDescendants()) do
                if desc:IsA("Model") then
                    IngestCandidate(desc)
                end
            end
        end
    end

    -- 3. Consulta rápida ao CollectionService por Tags de entidades
    for _, tag in ipairs(self.KnownTags) do
        local taggedInstances = CollectionService:GetTagged(tag)
        for _, tagged in ipairs(taggedInstances) do
            if tagged:IsA("Model") then
                IngestCandidate(tagged)
            end
        end
    end

    -- 4. Varredura rasa na raiz do Workspace (filhos diretos)
    for _, child in ipairs(Workspace:GetChildren()) do
        if child:IsA("Model") then
            IngestCandidate(child)
        end
    end

    self.CandidatePool = newPool
    return self.CandidatePool
end

return InstanceDetector
