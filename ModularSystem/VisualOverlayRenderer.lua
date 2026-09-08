--!strict
-- VisualOverlayRenderer.lua
-- Módulo 3: Sistema de Realce Visual (Highlights) e Gestão de Quota
-- Implementa: Isolamento em CoreGui, DepthMode AlwaysOnTop, Preservação de Transparência e Quota Maxima de Highlights

local CoreGuiService = game:GetService("CoreGui")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local VisualOverlayRenderer = {}
VisualOverlayRenderer.__index = VisualOverlayRenderer

-- Limite máximo de highlights ativos para não estourar a cota da engine Roblox (31 max)
local MAX_ACTIVE_HIGHLIGHTS = 16

function VisualOverlayRenderer.new()
    local self = setmetatable({}, VisualOverlayRenderer)
    self.ActiveHighlights = setmetatable({}, { __mode = "k" }) :: { [Model]: Highlight }
    self.Container = self:GetOrCreateContainer()
    return self
end

function VisualOverlayRenderer:GetOrCreateContainer(): Folder
    local host: Instance = CoreGuiService
    pcall(function()
        local test = CoreGuiService.Name
    end)
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

function VisualOverlayRenderer:GetOrCreateHighlight(model: Model): Highlight?
    if not model or not model:IsDescendantOf(game) then
        return nil
    end

    local hl = self.ActiveHighlights[model]
    if hl and hl.Parent then
        return hl
    end

    local count = 0
    for _, _ in pairs(self.ActiveHighlights) do
        count = count + 1
    end

    -- Gestão de Cota: Se exceder o limite seguro, recicla instâncias distantes
    if count >= MAX_ACTIVE_HIGHLIGHTS then
        for oldModel, oldHl in pairs(self.ActiveHighlights) do
            if not oldModel:IsDescendantOf(game) then
                pcall(function() oldHl:Destroy() end)
                self.ActiveHighlights[oldModel] = nil
                break
            end
        end
    end

    local success, newHl = pcall(function()
        local inst = Instance.new("Highlight")
        inst.Name = "HL_" .. model.Name
        inst.Adornee = model
        inst.FillTransparency = 0.55
        inst.OutlineTransparency = 0.05
        inst.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        inst.Enabled = true
        inst.Parent = self.Container
        return inst
    end)

    if success and newHl then
        self.ActiveHighlights[model] = newHl
        return newHl
    end

    return nil
end

-- Atualiza propriedades visuais sem quebrar transparência do modelo
function VisualOverlayRenderer:UpdateTargetHighlight(model: Model, isObstructed: boolean, isPrimaryFocus: boolean)
    if not model or not model:IsDescendantOf(game) then
        self:ClearTarget(model)
        return
    end

    local hl = self:GetOrCreateHighlight(model)
    if not hl then return end

    pcall(function()
        hl.Adornee = model
        hl.Enabled = true

        if isPrimaryFocus then
            -- Alvo Primário Focado: Verde Neon Brilhante (Visível) ou Vermelho Vivo (Obstruído)
            if isObstructed then
                hl.FillColor = Color3.fromRGB(255, 45, 45)
                hl.OutlineColor = Color3.fromRGB(255, 200, 200)
            else
                hl.FillColor = Color3.fromRGB(46, 230, 110)
                hl.OutlineColor = Color3.fromRGB(220, 255, 220)
            end
            hl.FillTransparency = 0.35
            hl.OutlineTransparency = 0.02
        else
            -- Entidades secundárias no campo de visão: Azul/Ciano (Visível) ou Vermelho Suave (Atrás de Parede)
            if isObstructed then
                hl.FillColor = Color3.fromRGB(180, 70, 70)
                hl.OutlineColor = Color3.fromRGB(220, 220, 220)
            else
                hl.FillColor = Color3.fromRGB(50, 140, 230)
                hl.OutlineColor = Color3.fromRGB(240, 240, 240)
            end
            hl.FillTransparency = 0.65
            hl.OutlineTransparency = 0.20
        end
    end)
end

function VisualOverlayRenderer:ClearTarget(model: Model?)
    if not model then return end
    pcall(function()
        local hl = self.ActiveHighlights[model]
        if hl then
            pcall(function() hl:Destroy() end)
        end
        self.ActiveHighlights[model] = nil
    end)
end

function VisualOverlayRenderer:ClearAll()
    for model, hl in pairs(self.ActiveHighlights) do
        pcall(function()
            if hl then hl:Destroy() end
        end)
    end
    table.clear(self.ActiveHighlights)
end

return VisualOverlayRenderer
