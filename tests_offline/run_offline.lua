-- Offline (fora do Roblox) harness: executa SOMENTE lógica pura de EngineCore e SimConfig
-- com um mock mínimo de `game`/HttpService. NÃO substitui MainTestRunner no Studio.
-- Uso:  luau.exe tests_offline/run_offline.lua   (a partir da raiz do repositório)

local passed, failed = 0, 0
local function check(cond, name)
    if cond then passed += 1; print("  [PASS] " .. name)
    else failed += 1; print("  [FAIL] " .. name) end
end

local Engine = require("./_gen/EngineCore")
local SimConfig = require("./_gen/SimConfig")

print("\n== EngineCore ==")
local rep = Engine:CalculateSuspicion({ angularVelocity = 900 })
check(rep.anomalies == rep.flaggedRules, "anomalies é alias de flaggedRules")
check(#rep.explanations == #rep.flaggedRules and #rep.explanations > 0, "explicação por regra acionada")
check(table.find(rep.unavailableMetrics, "linearSpeed") ~= nil, "telemetria ausente listada (linearSpeed)")
local z = Engine:CalculateSuspicion({ angularVelocity = 0, linearSpeed = 0, decoupledAngleDeg = 0, singleFrameDeltaDeg = 0, consecutiveOccludedFrames = 0 })
check(z.category == "LIMPO" and #z.unavailableMetrics == 0, "zero medido != ausente")
check(Engine:CalculateSuspicion({}).category == "INSUFICIENTE", "sem métricas => INSUFICIENTE")
check(Engine:CalculateSuspicion({ angularVelocity = 900, sampleCount = 2 }).category == "INSUFICIENTE", "amostra < mínimo => INSUFICIENTE")
check(Engine:CalculateSuspicion({ angularVelocity = 0 / 0 }).evaluatedRules == 0, "NaN tratado como inválido")
check(Engine:CalculateSuspicion({ angularVelocity = 80, decoupledAngleDeg = 45.0, isSnap = false }).totalScore >= 65, "silent aim crítico >= 65")
check(Engine:CalculateSuspicion({ angularVelocity = 60, singleFrameDeltaDeg = 1, isSnap = false, isObstructed = false, linearSpeed = 16 }).totalScore < 30, "condição normal < 30")
local b1, b2 = Engine:CalculateSuspicion({ angularVelocity = 450 }), Engine:CalculateSuspicion({ angularVelocity = 450.0001 })
check(b1.totalScore == 0 and b2.totalScore == 15, "limite 450: exclusivo (450 -> 0, 450.0001 -> 15)")

print("\n== SimConfig ==")
local mem = nil
SimConfig.SetStorage({ read = function() return mem end, write = function(c) mem = c; return true end })
SimConfig.RestoreDefaults()
local d = SimConfig.GetDefaults()
check(d.ActiveProfile == "DeepHat Simulation Default", "nome do perfil padrão")
check(d.AimbotEnabled == false and d.SilentAimEnabled == false, "automação e disparo desativados por padrão")
check(d.FovRadiusPx == 120 and d.ActiveTab == "Dashboard" and d.LineOfSightEnabled == true and d.Theme == "Dark", "valores iniciais")
SimConfig.Set("FovRadiusPx", 99999)
check(SimConfig.Get("FovRadiusPx") == 120, "Set rejeita fora da faixa")
SimConfig.Set("FovRadiusPx", "abc")
check(SimConfig.Get("FovRadiusPx") == 120, "Set rejeita tipo errado")
SimConfig.Set("FovRadiusPx", 200)
check(SimConfig.Get("FovRadiusPx") == 200, "Set aceita válido")
check(SimConfig.Save() == true, "Save via adaptador")
SimConfig.RestoreDefaults()
check(SimConfig.Get("FovRadiusPx") == 120, "RestoreDefaults restaura")
check(SimConfig.Load() == "loaded" and SimConfig.Get("FovRadiusPx") == 200, "Load restaura preferência salva")
check(SimConfig.Get("AimbotEnabled") == false, "Load mantém automação desligada")
mem = "{ nope"
check(SimConfig.Load() == "restored_defaults" and SimConfig.LastLoadReason ~= "", "corrompido => padrões + motivo")
mem = nil
check(SimConfig.Load() == "first_run", "sem dados => first_run")
local ok, errs = SimConfig.ImportJSON('{"ConfigVersion":99,"FovRadiusPx":150}')
check(ok == false and #errs > 0 and SimConfig.Get("FovRadiusPx") == 120, "import incompatível rejeitado e atômico")
check(SimConfig.ImportJSON('{"ConfigVersion":1,"FovRadiusPx":150}') == true and SimConfig.Get("FovRadiusPx") == 150, "import válido")
local ok2 = SimConfig.ImportJSON('{"ConfigVersion":1,"FovRadiusPx":150,"Inexistente":1}')
check(ok2 == false, "import com chave desconhecida rejeitado")
local seen = 0
local un = SimConfig.Subscribe("FovRadiusPx", function() seen += 1 end)
SimConfig.Set("FovRadiusPx", 160)
check(seen == 1, "observer notificado")
un()
SimConfig.Set("ProjectileType", "Physics")
check(SimConfig.Get("ProjectileType") == "Physics", "SimConfig ProjectileType aceita Physics")
SimConfig.Set("ProjectileGravity", 196.2)
check(math.abs(SimConfig.Get("ProjectileGravity") - 196.2) < 0.001, "SimConfig ProjectileGravity aceita 196.2")
SimConfig.Set("ProjectileDropComp", true)
check(SimConfig.Get("ProjectileDropComp") == true, "SimConfig ProjectileDropComp aceita true")

print("\n== DiagnosticAI ==")
local DiagnosticAI = require("./_gen/DiagnosticAI")
local repHealthy = DiagnosticAI.AnalyzeSystemState({ angularVelocity = 100, mode = "AIMBOT", targetName = "Dummy" })
check(repHealthy.Status == "HEALTHY", "DiagnosticAI: estado nominal retorna HEALTHY")

local repCrit = DiagnosticAI.AnalyzeSystemState({ angularVelocity = 700, mode = "AIMBOT", targetName = "Dummy1" })
check(repCrit.Status == "CRITICAL" and repCrit.AffectedModule:find("VectorTracker") ~= nil, "DiagnosticAI: velocidade angular extrema retorna CRITICAL")

local repShotMiss = DiagnosticAI.AnalyzeSystemState(nil, nil, nil, { Fired = true, InFov = false, DiscrepancyAngleDeg = 45 })
check(repShotMiss.Status == "WARNING" and repShotMiss.AffectedModule:find("SilentAim") ~= nil, "DiagnosticAI: tiro fora de FOV aponta SilentAim")

local chatJitter = DiagnosticAI.QueryChatbot("Por que a mira está oscilando?")
check(chatJitter.Answer:find("Suavização") ~= nil, "Chatbot: pergunta sobre oscilação sugere suavização")

local chatBallistics = DiagnosticAI.QueryChatbot("como funciona a gravidade e o arco balistico?")
check(chatBallistics.Answer:find("196.2") ~= nil, "Chatbot: pergunta balística menciona gravidade 196.2")

print(string.format("\nOFFLINE: %d aprovados, %d reprovados", passed, failed))
if failed > 0 then error("falhas") end

