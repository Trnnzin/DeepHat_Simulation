--!strict
-- =========================================================================
-- DeepHat_Standalone.lua (v7.0 PRO - Professional Simulation & Diagnostics Platform)
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

