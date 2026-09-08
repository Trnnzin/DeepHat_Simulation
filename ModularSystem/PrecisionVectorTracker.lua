--!strict
-- PrecisionVectorTracker.lua
-- Framework de Rastreamento de Vetores de Alta Precisão (Álgebra Linear e Geometria 3D)
-- Arquitetura de Produção: Desacoplamento, Proteção Epsilon, Interpolação Independente de FPS e Tolerância a Falhas

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local PrecisionVectorTracker = {}
PrecisionVectorTracker.__index = PrecisionVectorTracker

-- Constante de Guarda Epsilon: Evita singularidade matemática e vetores indefinidos (NaN)
local EPSILON_THRESHOLD = 1e-4

export type TrackerConfig = {
    MaxTrackingRadius: number,     -- Raio euclidiano máximo (studs)
    AngularResponsiveness: number, -- Coeficiente de rigidez angular (lambda para decaimento exponencial)
    SmoothingAlpha: number,        -- Coeficiente de amortecimento base [0.01 a 1.0]
    AllowOccludedTargets: boolean, -- Ignorar oclusão por raycast
    ExecutionPriority: number?     -- Prioridade RenderStepped (Enum.RenderPriority)
}

function PrecisionVectorTracker.new(config: TrackerConfig?)
    local self = setmetatable({}, PrecisionVectorTracker)

    self.Config = config or {
        MaxTrackingRadius = 300.0,
        AngularResponsiveness = 18.0,
        SmoothingAlpha = 0.20,
        AllowOccludedTargets = false,
        ExecutionPriority = Enum.RenderPriority.Camera.Value + 1
    }

    self.ActiveTargetInstance = nil :: Instance?
    self.CurrentOrientation = CFrame.identity
    self.IsRunning = false
    self.PipelineName = nil :: string?
    self.Camera = Workspace.CurrentCamera or Workspace:WaitForChild("Camera") :: Camera

    -- Parâmetros de oclusão (Raycasting)
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.IgnoreWater = true
    self.RayParams = rayParams

    return self
end

-- =========================================================================
-- [1] MOTOR DE DETECÇÃO E INTEGRIDADE DE INSTÂNCIAS (Targeting Engine)
-- =========================================================================

function PrecisionVectorTracker:ExtractPositionSafe(inst: Instance?): (boolean, Vector3?)
    if not inst or not inst:IsDescendantOf(game) then
        return false, nil
    end

    -- Caso 1: Objeto é uma BasePart física
    if inst:IsA("BasePart") then
        return true, inst.Position
    end

    -- Caso 2: Objeto é um Model (hierarquia composta com ou sem PrimaryPart)
    if inst:IsA("Model") then
        local hum = inst:FindFirstChildOfClass("Humanoid") or inst:FindFirstChildWhichIsA("Humanoid", true)
        if hum and hum.Health <= 0 then
            return false, nil
        end

        local ok, pivot = pcall(function() return inst:GetPivot() end)
        if ok and pivot then
            return true, pivot.Position
        end
    end

    return false, nil
end

function PrecisionVectorTracker:FindOptimalCandidate(originPos: Vector3, candidates: { Instance }): (Instance?, Vector3?, number)
    local bestTarget: Instance? = nil
    local bestPos: Vector3? = nil
    local minDistance = self.Config.MaxTrackingRadius

    for _, candidate in ipairs(candidates) do
        local isValid, pos = self:ExtractPositionSafe(candidate)
        if isValid and pos then
            local displacement = (pos - originPos)
            local dist = displacement.Magnitude

            if dist <= minDistance and dist >= EPSILON_THRESHOLD then
                local isVisible = true
                if not self.Config.AllowOccludedTargets then
                    local raycastResult = Workspace:Raycast(originPos, (displacement / dist) * dist, self.RayParams)
                    if raycastResult and not raycastResult.Instance:IsDescendantOf(candidate) then
                        isVisible = false
                    end
                end

                if isVisible then
                    minDistance = dist
                    bestTarget = candidate
                    bestPos = pos
                end
            end
        end
    end

    return bestTarget, bestPos, minDistance
end

-- =========================================================================
-- [2] CÁLCULO DE ORIENTAÇÃO DE PRECISÃO (Vector Math & Linear Algebra)
-- =========================================================================

function PrecisionVectorTracker:ComputeOrientationCFrame(originPos: Vector3, targetPos: Vector3): (boolean, Vector3, number, CFrame)
    local displacement = (targetPos - originPos)
    local distance = displacement.Magnitude

    -- GUARDA EPSILON: Previne divisão por zero e indeterminações numéricas (NaN)
    if distance < EPSILON_THRESHOLD then
        return false, Vector3.zero, 0, CFrame.new(originPos)
    end

    -- Normalização segura de vetor unitário no R3
    local unitDirection = displacement / distance

    -- Matriz de Rotação Ortonormal SO(3) alinhando o eixo -Z com unitDirection
    local targetCFrame = CFrame.lookAt(originPos, targetPos, Vector3.yAxis)

    return true, unitDirection, distance, targetCFrame
end

-- =========================================================================
-- [3] CONTROLE DE SUAVIZAÇÃO DINÂMICA (Framerate-Independent Lerp)
-- =========================================================================

function PrecisionVectorTracker:InterpolateOrientation(
    currentCFrame: CFrame,
    targetCFrame: CFrame,
    deltaTime: number
): CFrame
    -- Amortecimento por Decaimento Exponencial Contínuo:
    -- alpha_eff = 1 - e^(-lambda * dt)
    local safeDt = math.clamp(deltaTime, 0.0001, 0.1)
    local lambda = self.Config.AngularResponsiveness * math.clamp(self.Config.SmoothingAlpha, 0.01, 1.0)
    local dynamicAlpha = math.clamp(1.0 - math.exp(-lambda * safeDt), 0.001, 1.0)

    return currentCFrame:Lerp(targetCFrame, dynamicAlpha)
end

-- =========================================================================
-- [4] PIPELINE DE EXECUÇÃO SEGURA (Threading & Protected Call)
-- =========================================================================

function PrecisionVectorTracker:Start(targetSupplier: () -> { Instance })
    if self.IsRunning then return end
    self.IsRunning = true

    local localChar = Players.LocalPlayer and Players.LocalPlayer.Character
    if localChar then
        self.RayParams.FilterDescendantsInstances = { localChar }
    end

    local pipelineName = "PrecisionVectorTracker_" .. tostring(math.random(100000, 999999))
    local priority = self.Config.ExecutionPriority or (Enum.RenderPriority.Camera.Value + 1)

    RunService:BindToRenderStep(pipelineName, priority, function(dt)
        local success, _ = pcall(function()
            if not self.IsRunning then return end
            local camera = self.Camera
            if not camera then return end

            local camCFrame = camera.CFrame
            local originPos = camCFrame.Position

            local candidateList = targetSupplier()
            if not candidateList or #candidateList == 0 then
                return
            end

            local bestInst, targetPos, _ = self:FindOptimalCandidate(originPos, candidateList)
            if not bestInst or not targetPos then
                return
            end

            local valid, _, _, targetRotation = self:ComputeOrientationCFrame(originPos, targetPos)
            if not valid then
                return
            end

            local smoothedCFrame = self:InterpolateOrientation(camCFrame, targetRotation, dt)
            camera.CFrame = smoothedCFrame
            self.CurrentOrientation = smoothedCFrame
            self.ActiveTargetInstance = bestInst
        end)

        if not success then
            self.ActiveTargetInstance = nil
        end
    end)

    self.PipelineName = pipelineName
end

function PrecisionVectorTracker:Stop()
    if not self.IsRunning then return end
    self.IsRunning = false
    if self.PipelineName then
        pcall(function()
            RunService:UnbindFromRenderStep(self.PipelineName)
        end)
        self.PipelineName = nil
    end
    self.ActiveTargetInstance = nil
end

return PrecisionVectorTracker
