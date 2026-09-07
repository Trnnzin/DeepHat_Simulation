-- DeepHat FPS Aim Simulator (Para testes de detecção de mira / aceleração angular)
local Player = game.Players.LocalPlayer
local Camera = workspace.CurrentCamera

local Settings = {
    Enabled = true,
    TargetPos = Vector3.new(0, 10, 0), -- Defina a posição do alvo/dummy aqui
    AimType = "SNAP",                  -- "SNAP" (Instantâneo) ou "SMOOTH" (Suave/Tracking)
    Smoothness = 0.1,                  -- Fator de interpolação (0.01 a 1)
}

local function SimulateAim()
    if not Settings.Enabled then return end

    local targetCF = CFrame.new(Camera.CFrame.Position, Settings.TargetPos)

    if Settings.AimType == "SNAP" then
        -- Simula o "Snap" (ajuste instantâneo em 1 frame)
        Camera.CFrame = targetCF
    elseif Settings.AimType == "SMOOTH" then
        -- Simula o "Tracking" com interpolação contínua
        Camera.CFrame = Camera.CFrame:Lerp(targetCF, Settings.Smoothness)
    end
end

-- Loop de execução
task.spawn(function()
    while Settings.Enabled do
        SimulateAim()
        task.wait()
    end
end)

print("[System] Simulador de Mira Ativado. Alvo em: ", Settings.TargetPos)
