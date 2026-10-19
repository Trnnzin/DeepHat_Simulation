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

return VisualOverlayRenderer
