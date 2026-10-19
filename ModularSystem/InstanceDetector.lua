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

return InstanceDetector
