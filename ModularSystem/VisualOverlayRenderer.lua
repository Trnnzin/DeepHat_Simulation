--!strict
-- VisualOverlayRenderer.lua
-- Pilar 3: Renderização de Realce (UI & Overlay Engine)
-- Highlights com DepthMode AlwaysOnTop, Preservação de Camadas de Z-Index e Quota de Memória

local CoreGuiService = game:GetService("CoreGui")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local VisualOverlayRenderer = {}
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

return VisualOverlayRenderer
