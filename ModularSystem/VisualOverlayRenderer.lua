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
    self.ActiveHighlights = setmetatable({}, { __mode = "k" }) :: { [Instance]: Highlight }
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
            for oldTarget, oldHl in pairs(self.ActiveHighlights) do
                if not oldTarget:IsDescendantOf(game) then
                    pcall(function() oldHl:Destroy() end)
                    self.ActiveHighlights[oldTarget] = nil
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

function VisualOverlayRenderer:ClearTarget(target: Instance?)
    if not target then return end
    local hl = self.ActiveHighlights[target]
    if hl then
        pcall(function() hl:Destroy() end)
    end
    self.ActiveHighlights[target] = nil
end

function VisualOverlayRenderer:ClearAll()
    for _, hl in pairs(self.ActiveHighlights) do
        pcall(function() if hl then hl:Destroy() end end)
    end
    table.clear(self.ActiveHighlights)
end

return VisualOverlayRenderer
