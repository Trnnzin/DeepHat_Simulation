--!strict
-- CameraKinematics.lua
-- Módulo 1: Cinemática Rotacional de Câmera (Modos Snap e Tracking)

local CameraKinematics = {}
CameraKinematics.__index = CameraKinematics

export type CameraTelemetry = {
    position: Vector3,
    lookVector: Vector3,
    angularVelocityDeg: number,
    angularVelocityRad: number
}

function CameraKinematics.new(initialCFrame: CFrame?)
    local self = setmetatable({}, CameraKinematics)
    self.CFrame = initialCFrame or CFrame.new(Vector3.new(0, 5, 0), Vector3.new(0, 5, 10))
    self.PreviousLookVector = self.CFrame.LookVector
    return self
end

-- Cálculo escalar da taxa de rotação angular entre dois vetores unitários
local function ComputeAngularVelocity(v1: Vector3, v2: Vector3, dt: number): (number, number)
    if dt <= 0 then return 0, 0 end
    
    local dot = math.clamp(v1:Dot(v2), -1.0, 1.0)
    local angleRad = math.acos(dot)
    local angleDeg = math.deg(angleRad)
    
    return (angleDeg / dt), (angleRad / dt)
end

-- Modo 1: Vetor Instantâneo (Snap) - Transição em 1 frame
function CameraKinematics:StepSnap(targetPosition: Vector3, dt: number): CameraTelemetry
    local eyePos = self.CFrame.Position
    local targetRotation = CFrame.lookAt(eyePos, targetPosition)
    
    self.CFrame = targetRotation
    local currentLook = self.CFrame.LookVector
    
    local degPerSec, radPerSec = ComputeAngularVelocity(self.PreviousLookVector, currentLook, dt)
    self.PreviousLookVector = currentLook

    return {
        position = eyePos,
        lookVector = currentLook,
        angularVelocityDeg = degPerSec,
        angularVelocityRad = radPerSec
    }
end

-- Modo 2: Vetor Suave (Tracking) - Interpolação Lerp contínua
function CameraKinematics:StepTracking(targetPosition: Vector3, smoothing: number, dt: number): CameraTelemetry
    local eyePos = self.CFrame.Position
    local targetRotation = CFrame.lookAt(eyePos, targetPosition)
    local alpha = math.clamp(smoothing, 0.001, 1.0)
    
    self.CFrame = self.CFrame:Lerp(targetRotation, alpha)
    local currentLook = self.CFrame.LookVector
    
    local degPerSec, radPerSec = ComputeAngularVelocity(self.PreviousLookVector, currentLook, dt)
    self.PreviousLookVector = currentLook

    return {
        position = eyePos,
        lookVector = currentLook,
        angularVelocityDeg = degPerSec,
        angularVelocityRad = radPerSec
    }
end

return CameraKinematics
