--!strict
-- DeepHat FPS Aim Simulator (Target Lock & Cinematic Camera Tracking)
-- Otimizado para alta frequencia com RenderStepped, protecao contra divisao por zero e pcall.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera or Workspace:WaitForChild("Camera") :: Camera

local Settings = {
    Enabled = true,
    TargetPos = Vector3.new(0, 10, 0), -- Posicao do alvo padrao
    AimType = "SMOOTH",                -- "SNAP" (Instantaneo) ou "SMOOTH" (Suave/Tracking)
    Smoothness = 0.15,                 -- Fator de suavidade (0.01 a 1.0)
    EpsilonDistance = 0.001,           -- Distancia minima para evitar divisao por zero (NaN)
}

local function ProcessAimStep(dt: number)
    if not Settings.Enabled or not Camera then
        return
    end

    local cameraPos = Camera.CFrame.Position
    local targetPos = Settings.TargetPos
    local offset = targetPos - cameraPos

    -- Protecao contra divisao por zero e NaN
    if offset.Magnitude < Settings.EpsilonDistance then
        return
    end

    local desiredCFrame = CFrame.lookAt(cameraPos, targetPos)

    if Settings.AimType == "SNAP" then
        Camera.CFrame = desiredCFrame
    elseif Settings.AimType == "SMOOTH" then
        -- Interpolacao independente de taxa de quadros (frame-rate independent lerp)
        local clampedWeight = math.clamp(Settings.Smoothness, 0.01, 1.0)
        local alpha = 1 - math.exp(-clampedWeight * (dt * 60) * 10)
        Camera.CFrame = Camera.CFrame:Lerp(desiredCFrame, alpha)
    end
end

-- Loop de renderizacao de alta frequencia seguro
local connection
connection = RunService.RenderStepped:Connect(function(dt: number)
    local success, err = pcall(ProcessAimStep, dt)
    if not success then
        warn("[AimSimulator] Erro na atualizacao de orientacao: " .. tostring(err))
    end
end)

print("[System] Simulador de Mira Otimizado Ativado. Alvo em:", Settings.TargetPos)
