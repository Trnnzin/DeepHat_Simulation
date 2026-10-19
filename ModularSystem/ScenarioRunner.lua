--!strict
-- =========================================================================
-- ScenarioRunner.lua
-- Executa cenários sintéticos de Line-of-Sight em geometria ISOLADA e temporária
-- (pasta DeepHat_Scenarios, Y=900, descartada ao final). Nunca toca em jogadores
-- reais nem em objetos de terceiros. Usa VectorTracker:EvaluateLineOfSight.
-- =========================================================================

local Workspace = game:GetService("Workspace")

local ScenarioRunner = {}

export type ScenarioDef = { Id: string, Label: string, Expected: string }
export type ScenarioOutcome = {
    Id: string, Label: string, Expected: string, Actual: string,
    Passed: boolean, Reason: string, Time: number,
}

ScenarioRunner.Scenarios = {
    { Id = "Clear",       Label = "Caminho desobstruído",         Expected = "VISIBLE" },
    { Id = "SolidWall",   Label = "Parede sólida",                Expected = "BLOCKED" },
    { Id = "InvisBarrier",Label = "Barreira invisível colidível", Expected = "BLOCKED" },
    { Id = "NonCollide",  Label = "Objeto não colidível",         Expected = "VISIBLE" },
    { Id = "InvalidDest", Label = "Destino removido",             Expected = "INVALID" },
    { Id = "Coincident",  Label = "Origem = destino",             Expected = "INVALID" },
    { Id = "EndCollision",Label = "Colisão junto ao ponto final", Expected = "VISIBLE" },
} :: { ScenarioDef }

ScenarioRunner.History = {} :: { ScenarioOutcome }
ScenarioRunner.HistoryLimit = 100

local ORIGIN = Vector3.new(0, 900, 0)
local TARGET = Vector3.new(0, 900, 40)

local function MakePart(folder: Instance, z: number, depth: number, canCollide: boolean, transparency: number): Part
    local p = Instance.new("Part")
    p.Anchored = true
    p.Size = Vector3.new(30, 30, depth)
    p.Position = Vector3.new(0, 900, z)
    p.CanCollide = canCollide
    p.CanQuery = true
    p.Transparency = transparency
    p.Parent = folder
    return p
end

-- Executa um cenário; devolve o resultado e o LosResult bruto.
function ScenarioRunner.Run(tracker: any, id: string): (ScenarioOutcome?, any?)
    local def: ScenarioDef? = nil
    for _, s in ipairs(ScenarioRunner.Scenarios) do
        if s.Id == id then def = s end
    end
    if not def then return nil, nil end

    local folder = Instance.new("Folder")
    folder.Name = "DeepHat_Scenarios"
    folder.Parent = Workspace

    local origin, target, targetInst = ORIGIN, TARGET, nil
    local ok, result = pcall(function()
        if id == "SolidWall" then MakePart(folder, 20, 1, true, 0)
        elseif id == "InvisBarrier" then MakePart(folder, 20, 1, true, 1)
        elseif id == "NonCollide" then MakePart(folder, 20, 1, false, 0)
        elseif id == "InvalidDest" then
            local t = Instance.new("Part"); t.Parent = folder; t:Destroy(); targetInst = t
        elseif id == "Coincident" then target = origin
        elseif id == "EndCollision" then MakePart(folder, 39.9, 0.2, true, 0)
        end
        return tracker:EvaluateLineOfSight(origin, target, targetInst)
    end)
    folder:Destroy()

    local outcome: ScenarioOutcome
    if ok and result then
        outcome = {
            Id = def.Id, Label = def.Label, Expected = def.Expected, Actual = result.Status,
            Passed = (result.Status == def.Expected), Reason = result.Reason, Time = os.clock(),
        }
    else
        outcome = {
            Id = def.Id, Label = def.Label, Expected = def.Expected, Actual = "INVALID",
            Passed = (def.Expected == "INVALID"), Reason = "Erro de execução: " .. tostring(result), Time = os.clock(),
        }
        result = { Status = "INVALID", Reason = outcome.Reason, QueryDistance = 0 }
    end

    table.insert(ScenarioRunner.History, outcome)
    while #ScenarioRunner.History > ScenarioRunner.HistoryLimit do
        table.remove(ScenarioRunner.History, 1)
    end
    return outcome, result
end

function ScenarioRunner.Summary(): (number, number)
    local pass, fail = 0, 0
    for _, o in ipairs(ScenarioRunner.History) do
        if o.Passed then pass += 1 else fail += 1 end
    end
    return pass, fail
end

function ScenarioRunner.ClearHistory()
    table.clear(ScenarioRunner.History)
end

return ScenarioRunner
