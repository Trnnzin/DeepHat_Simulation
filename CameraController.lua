--!strict
--[[
    ============================================================================
    MODULO: CameraController (Target Lock System)
    DESCRICAO: Sistema de orientacao cinematica de camera com interpolacao suave,
               protecao contra vetores nulos (NaN) e tolerancia a falhas em tempo real.
    ============================================================================
--]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CameraController = {}
CameraController.__index = CameraController

-- [CONSTANTES DE ENGENHARIA]
local EPSILON_DISTANCE: number = 0.001 -- Distancia minima para evitar divisao por zero (NaN)
local DEFAULT_WEIGHT: number = 0.15     -- Fator de suavidade padrao (0.01 = muito suave, 1.0 = instantaneo)

export type TargetType = BasePart | Model | Vector3 | nil

export type CameraControllerType = {
    Camera: Camera,
    Target: TargetType,
    Weight: number,
    IsActive: boolean,
    Connection: RBXScriptConnection?,
    SetTarget: (self: any, newTarget: TargetType) -> (),
    SetWeight: (self: any, newWeight: number) -> (),
    SetActive: (self: any, active: boolean) -> (),
    Toggle: (self: any) -> boolean,
    Destroy: (self: any) -> (),
}

--[[
    Inicializa uma nova instancia do controlador de camera.
--]]
function CameraController.new(camera: Camera?): CameraControllerType
    local self = setmetatable({}, CameraController)

    self.Camera = camera or Workspace.CurrentCamera
    self.Target = nil
    self.Weight = DEFAULT_WEIGHT
    self.IsActive = false
    self.Connection = nil

    self:_startRenderLoop()

    return (self :: any)
end

--[[
    Extrai a posicao global (Vector3) de forma segura a partir de multiplos tipos de alvos.
--]]
local function getTargetPosition(target: TargetType): Vector3?
    if not target then
        return nil
    end

    if typeof(target) == "Vector3" then
        return target
    elseif typeof(target) == "Instance" then
        if target:IsA("BasePart") then
            return target.Position
        elseif target:IsA("Model") then
            local primary = target.PrimaryPart
            if primary then
                return primary.Position
            end
            return target:GetPivot().Position
        end
    end

    return nil
end

--[[
    Executa a etapa de fisica/rotacao para um frame individual.
    Retorna imediatamente se os parametros de seguranca nao forem atendidos.
--]]
local function processCameraStep(camera: Camera, target: TargetType, weight: number, dt: number)
    -- 1. Verificacoes de integridade de instancias
    if not camera or not target then
        return
    end

    local targetPos = getTargetPosition(target)
    if not targetPos then
        return
    end

    local cameraCFrame = camera.CFrame
    local cameraPos = cameraCFrame.Position

    -- 2. Vetor de deslocamento e guarda contra divisao por zero (Epsilon check)
    local offset = targetPos - cameraPos
    if offset.Magnitude < EPSILON_DISTANCE then
        return
    end

    -- 3. Calculo da orientacao ideal pura (CFrame.lookAt)
    local desiredCFrame = CFrame.lookAt(cameraPos, targetPos)

    -- 4. Normalizacao da suavidade com compensacao de DeltaTime (Frame-rate Independent Lerp)
    local clampedWeight = math.clamp(weight, 0.0, 1.0)
    local alpha = 1 - math.exp(-clampedWeight * (dt * 60) * 10)

    -- 5. Aplicacao da Interpolacao Linear (Lerp)
    camera.CFrame = cameraCFrame:Lerp(desiredCFrame, alpha)
end

--[[
    Loop de renderizacao de alta frequencia (RenderStepped).
    Encapsulado com pcall para isolamento estrito contra travamentos de thread.
--]]
function CameraController:_startRenderLoop()
    if self.Connection then
        self.Connection:Disconnect()
    end

    self.Connection = RunService.RenderStepped:Connect(function(dt: number)
        if not self.IsActive then
            return
        end

        -- Otimizacao e Seguranca: Encapsulamento em Protected Call
        local success, err = pcall(processCameraStep, self.Camera, self.Target, self.Weight, dt)
        if not success then
            warn("[CameraController] Erro no processamento de orientacao: " .. tostring(err))
        end
    end)
end

--[[
    Define o alvo dinamico do rastreamento.
--]]
function CameraController:SetTarget(newTarget: TargetType)
    self.Target = newTarget
end

--[[
    Ajusta a taxa de suavidade (0.01 a 1.0).
--]]
function CameraController:SetWeight(newWeight: number)
    self.Weight = math.clamp(newWeight, 0.0, 1.0)
end

--[[
    Ativa ou desativa o estado do sistema (Toggle/State Management).
--]]
function CameraController:SetActive(active: boolean)
    self.IsActive = active
end

--[[
    Inverte o estado atual do sistema e retorna o novo estado.
--]]
function CameraController:Toggle(): boolean
    self.IsActive = not self.IsActive
    return self.IsActive
end

--[[
    Limpa conexoes ativas para prevenir memory leaks.
--]]
function CameraController:Destroy()
    if self.Connection then
        self.Connection:Disconnect()
        self.Connection = nil
    end
    self.Target = nil
    self.IsActive = false
end

return CameraController
