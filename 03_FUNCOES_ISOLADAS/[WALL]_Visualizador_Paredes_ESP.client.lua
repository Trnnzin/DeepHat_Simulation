-- DeepHat FPS Wallhack Behavior Simulator (Para testes de pre-aim e visada através de paredes)
local Camera = workspace.CurrentCamera

local Settings = {
    Enabled = true,
    TargetPos = Vector3.new(0, 10, 0), -- Posição do alvo atrás de obstáculo
    DetectionMode = "TRACK_THROUGH_WALL"
}

local function CheckLineOfSight(targetPos)
    local rayOrigin = Camera.CFrame.Position
    local rayDirection = (targetPos - rayOrigin).Unit * 100
    
    local raycastParams = RaycastParams.new()
    if game.Players.LocalPlayer.Character then
        raycastParams.FilterDescendantsInstances = {game.Players.LocalPlayer.Character}
    end
    raycastParams.FilterType = Enum.RaycastFilterMode.Exclude

    local result = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
    return result == nil -- true se não houver colisão no trajeto
end

local function SimulateWallhack()
    if not Settings.Enabled then return end

    local hasVision = CheckLineOfSight(Settings.TargetPos)

    -- Simula a rotação da câmera em direção ao alvo mesmo com oclusão
    Camera.CFrame = CFrame.new(Camera.CFrame.Position, Settings.TargetPos)
end

task.spawn(function()
    while Settings.Enabled do
        SimulateWallhack()
        task.wait()
    end
end)

print("[System] Simulador de Visada Oclusa Ativado. Alvo em: ", Settings.TargetPos)
