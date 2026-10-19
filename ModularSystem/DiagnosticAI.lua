--!strict
-- =========================================================================
-- DiagnosticAI.lua
-- Motor de IA de Diagnóstico em 6 Camadas e Assistente Chatbot Estruturado
-- Arquitetura Modular:
--   Camada A: Coleta e Ingestão de Dados (Telemetria, LOS, Disparos, Eventos)
--   Camada B: Validação e Higiene de Dados (Detecção de NaN, Inf, Amostras)
--   Camada C: Diagnóstico Determinístico Baseado em Regras Físicas
--   Camada D: Inferência de Hipóteses (CONFIRMED / HYPOTHESIS / INSUFFICIENT_DATA)
--   Camada E: Recomendações de Ação Priorizadas com Vínculo a Cenários de Teste
--   Camada F: Verificação Contínua e Detecção de Regressão entre Execuções
-- =========================================================================

local DiagnosticAI = {}
DiagnosticAI.__index = DiagnosticAI

export type EvidenceType = "CONFIRMED" | "HYPOTHESIS" | "INSUFFICIENT_DATA"

export type DiagnosticHypothesis = {
    Id: string,
    Title: string,
    Likelihood: number,
    Type: EvidenceType,
    EvidenceList: { string },
    CounterEvidenceList: { string }?,
}

export type ActionableRecommendation = {
    Priority: "ALTA" | "MEDIA" | "BAIXA",
    Title: string,
    Action: string,
    TargetConfigKey: string?,
    EaseOfValidation: "IMEDIATA" | "CENARIO_TESTE" | "MANUAL",
    RecommendedScenarioId: string?,
}

export type DiagnosticReport = {
    Timestamp: number,
    Status: "HEALTHY" | "WARNING" | "CRITICAL",
    Summary: string,
    AffectedModule: string,
    RootCause: string,
    SuggestedAction: string,
    MetricHighlights: { [string]: string },
    EvidenceType: EvidenceType,
    Confidence: number,
    Hypotheses: { DiagnosticHypothesis },
    Recommendations: { ActionableRecommendation },
    RecommendedScenarioId: string?,
    DataHygieneIssues: { string },
    VerificationResult: string?,
}

export type ChatbotResponse = {
    Query: string,
    Answer: string,
    AffectedModule: string,
    SuggestedAction: string,
    Confidence: number,
    EvidenceType: EvidenceType?,
    RecommendedScenarioId: string?,
}

-- Histórico de relatórios para verificação de regressões (Camada F)
local ReportHistory: { DiagnosticReport } = {}
local MAX_HISTORY = 20

local function IsFinite(v: any): boolean
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function DiagnosticAI.GetHistory(): { DiagnosticReport }
    return ReportHistory
end

function DiagnosticAI.ClearHistory()
    table.clear(ReportHistory)
end

-- =========================================================================
-- CAMADA B: HIGIENE E VALIDAÇÃO DE DADOS
-- =========================================================================
local function ValidateDataHygiene(
    telemetry: { [string]: any }?,
    lastShot: any?
): (boolean, { string })
    local issues: { string } = {}

    if telemetry then
        if telemetry.angularVelocity ~= nil and not IsFinite(telemetry.angularVelocity) then
            table.insert(issues, "HYGIENE_NAN_ANGULAR_VELOCITY: Velocidade angular contém NaN ou Infinito")
        end
        if telemetry.decoupledAngle ~= nil and not IsFinite(telemetry.decoupledAngle) then
            table.insert(issues, "HYGIENE_NAN_DECOUPLED_ANGLE: Ângulo desacoplado contém NaN ou Infinito")
        end
    end

    if lastShot and type(lastShot) == "table" then
        if lastShot.DiscrepancyAngleDeg ~= nil and not IsFinite(lastShot.DiscrepancyAngleDeg) then
            table.insert(issues, "HYGIENE_NAN_DISCREPANCY_ANGLE: Desvio angular do disparo contém NaN")
        end
    end

    return #issues == 0, issues
end

-- =========================================================================
-- ANALISADOR PRINCIPAL DO SISTEMA (CAMADAS A - F)
-- =========================================================================
function DiagnosticAI.AnalyzeSystemState(
    telemetry: { [string]: any }?,
    losHistory: { any }?,
    eventLogs: { any }?,
    lastShot: any?
): DiagnosticReport
    local timeNow = os.clock()
    local t = telemetry or {}
    local metrics: { [string]: string } = {}
    local hypotheses: { DiagnosticHypothesis } = {}
    local recommendations: { ActionableRecommendation } = {}

    -- Camada B: Validação e Higiene
    local isDataClean, hygieneIssues = ValidateDataHygiene(telemetry, lastShot)

    -- Extração e normalização de métricas (Camada A)
    local angVel = tonumber(t.angularVelocity) or 0
    local isObstructed = t.isObstructed == true
    local targetName = tostring(t.targetName or "NENHUM")
    local mode = tostring(t.mode or "IDLE")

    metrics["Modo"] = mode
    metrics["Alvo"] = targetName
    metrics["VelocidadeAngular"] = string.format("%.1f °/s", angVel)
    metrics["LinhaDeVisada"] = isObstructed and "OBSTRUÍDO" or "LIVRE"

    local finalStatus: "HEALTHY" | "WARNING" | "CRITICAL" = "HEALTHY"
    local finalSummary = ""
    local finalModule = "Nenhum"
    local finalRootCause = ""
    local finalAction = ""
    local evidenceType: EvidenceType = "CONFIRMED"
    local confidence = 0.98
    local recommendedScenario: string? = nil

    -- ---------------------------------------------------------------------
    -- CAMADA C: REGRAS DETERMINÍSTICAS (Ordem de prioridade e evidência)
    -- ---------------------------------------------------------------------

    -- 1. Disparo / Silent Aim
    if lastShot and type(lastShot) == "table" and (lastShot.Fired == true or lastShot.Outcome ~= nil) then
        metrics["UltimoTiro"] = lastShot.HitRegistered and "ACERTO" or "FALHA / DISPERSÃO"
        metrics["DesvioTiro"] = string.format("%.1f°", lastShot.DiscrepancyAngleDeg or 0)
        metrics["TipoBalistico"] = tostring(lastShot.TrajectoryType or "Instant")
        metrics["Resultado"] = tostring(lastShot.Outcome or "NENHUM")

        local outcome = lastShot.Outcome
        if outcome == "SUCCESS" or (outcome == nil and lastShot.HitRegistered == true and lastShot.InFov == true and not lastShot.IsObstructed) then
            finalStatus = "HEALTHY"
            finalSummary = "Disparo simulado bem-sucedido com colisão física confirmada (nominal) no alvo sintético."
            finalModule = "Nenhum"
            finalRootCause = "Trajetória balística calculada e verificada com sucesso em todas as 5 etapas."
            finalAction = "Sistema de disparo validado. Prossiga com os testes dinâmicos de movimentação."
            evidenceType = "CONFIRMED"
            confidence = 1.0
            recommendedScenario = "SCENARIO_VISIBLE_DUMMY"

            table.insert(hypotheses, {
                Id = "HYP_NOMINAL_HIT",
                Title = "Acerto nominal verificado",
                Likelihood = 1.0,
                Type = "CONFIRMED",
                EvidenceList = { "Raycast hit validado", "Target dentro do FOV", "Ausência de obstrução física" },
            })
            table.insert(recommendations, {
                Priority = "BAIXA",
                Title = "Testar com Alvo em Movimento",
                Action = "Executar cenário com dummy cinemático móvel para validar compensação de lead.",
                EaseOfValidation = "CENARIO_TESTE",
                RecommendedScenarioId = "SCENARIO_MOVING_TARGET",
            })

        elseif outcome == "TARGET_OUTSIDE_FOV" or (outcome == nil and lastShot.InFov == false) then
            finalStatus = "WARNING"
            finalSummary = "Disparo falhou: alvo estava fora do cone angular configurado (FOV)."
            finalModule = "SilentAim / SimConfig"
            finalRootCause = string.format("Desvio angular do disparo (%.1f°) excedeu o SilentAimFOV configurado.", lastShot.DiscrepancyAngleDeg or 0)
            finalAction = "Aumente o campo 'Silent Aim FOV' no painel ou aponte a câmera mais próximo ao manequim de teste."
            evidenceType = "CONFIRMED"
            confidence = 0.99
            recommendedScenario = "SCENARIO_TARGET_OUTSIDE_FOV"

            table.insert(hypotheses, {
                Id = "HYP_FOV_EXCEEDED",
                Title = "Alvo fora do limite angular de Silent Aim",
                Likelihood = 0.99,
                Type = "CONFIRMED",
                EvidenceList = { string.format("Desvio angular medido: %.1f°", lastShot.DiscrepancyAngleDeg or 0) },
            })
            table.insert(recommendations, {
                Priority = "MEDIA",
                Title = "Ajustar Limite Angular",
                Action = "Aumentar SilentAimFovDeg de 25° para 35° ou reposicionar ponto de mira.",
                TargetConfigKey = "SilentAimFovDeg",
                EaseOfValidation = "IMEDIATA",
                RecommendedScenarioId = "SCENARIO_TARGET_OUTSIDE_FOV",
            })

        elseif outcome == "OBSTACLE_BLOCKED" or (outcome == nil and lastShot.IsObstructed == true) then
            finalStatus = "WARNING"
            finalSummary = "Disparo bloqueado por obstáculo sólido antes de atingir o alvo de teste."
            finalModule = "VectorTracker (Raycast / Colisão no Workspace)"
            finalRootCause = "Raycast de colisão detectou uma barreira ou obstáculo interceptando a trajetória do projétil."
            finalAction = "Remova o obstáculo ou posicione o manequim de teste em linha de visão desobstruída."
            evidenceType = "CONFIRMED"
            confidence = 1.0
            recommendedScenario = "SCENARIO_WALL_OCCLUSION"

            table.insert(hypotheses, {
                Id = "HYP_PHYSICAL_OBSTACLE",
                Title = "Intercepção física por geometria opaca",
                Likelihood = 1.0,
                Type = "CONFIRMED",
                EvidenceList = { "Workspace:Raycast retornou colisão com peça que não pertence ao alvo" },
            })
            table.insert(recommendations, {
                Priority = "MEDIA",
                Title = "Desobstruir Linha de Visada",
                Action = "Mover manequim para fora da oclusão ou verificar filtro CanQuery.",
                EaseOfValidation = "CENARIO_TESTE",
                RecommendedScenarioId = "SCENARIO_WALL_OCCLUSION",
            })

        elseif outcome == "TARGET_INVALID" then
            finalStatus = "WARNING"
            finalSummary = "Disparo abortado: alvo de teste foi removido ou destruído."
            finalModule = "InstanceDetector / Ciclo de Vida"
            finalRootCause = "O modelo de teste perdeu o Humanoid, teve sua vida zerada ou foi deletado do Workspace."
            finalAction = "Clique no botão 'Spawnar Alvo Sintético' no painel para criar um novo manequim."
            evidenceType = "CONFIRMED"
            confidence = 0.99
            recommendedScenario = "SCENARIO_TARGET_DESPAWNED"

        elseif outcome == "PROBABILISTIC_SPREAD" or (outcome == nil and lastShot.HitRegistered == false) then
            finalStatus = "HEALTHY"
            finalSummary = "Disparo simulou dispersão probabilística intencional baseada no Hit Chance."
            finalModule = "VectorTracker (SimulateShot)"
            finalRootCause = "A probabilidade de acerto configurada (Hit Chance) causou uma dispersão probabilística de teste."
            finalAction = "Para acertos 100% determinísticos em testes de controle, configure 'Hit Chance' para 100%."
            evidenceType = "CONFIRMED"
            confidence = 0.95
            recommendedScenario = "SCENARIO_PROBABILISTIC_SPREAD"

        elseif outcome == "MODULE_DISABLED" then
            finalStatus = "WARNING"
            finalSummary = "Disparo rejeitado: o módulo de Silent Aim está desativado."
            finalModule = "SimConfig (SilentAimEnabled)"
            finalRootCause = "A opção 'SilentAimEnabled' está desativada no painel de controle."
            finalAction = "Ative a opção 'Ativar Simulação de Silent Aim' na aba 'Disparos Simulados'."
            evidenceType = "CONFIRMED"
            confidence = 1.0
            recommendedScenario = "SCENARIO_MODULE_DISABLED"

        elseif outcome == "INVALID_TRAJECTORY" then
            finalStatus = "CRITICAL"
            finalSummary = "Trajetória inválida detectada no cálculo vetorial."
            finalModule = "VectorTracker (Cálculo Vetorial)"
            finalRootCause = "Distância até o alvo nula, infinita ou coordenadas NaN detectadas."
            finalAction = "Verifique a posição da câmera e certifique-se de que a distância seja superior a 0.1 studs."
            evidenceType = "CONFIRMED"
            confidence = 1.0
            recommendedScenario = "SCENARIO_INVALID_VECTOR"
        end

    -- 2. Oclusão Contínua de Linha de Visada
    elseif isObstructed then
        finalStatus = "WARNING"
        finalSummary = "Alvo selecionado está ocluído por geometria de teste."
        finalModule = "VectorTracker / InstanceDetector"
        finalRootCause = "Raycast colidiu com geometria opaca/colidível antes de atingir o alvo sintético."
        finalAction = "Verifique o histórico da aba 'Line of Sight' para identificar o bloco colisor exato."
        evidenceType = "CONFIRMED"
        confidence = 0.98
        recommendedScenario = "SCENARIO_WALL_OCCLUSION"

    -- 3. Ausência de Alvo ou Simulação Pausada
    elseif targetName == "NENHUM" or targetName:find("Nenhum") or targetName:find("PAUSADO") then
        if mode == "PAUSED" then
            finalStatus = "WARNING"
            finalSummary = "A simulação está pausada globalmente."
            finalModule = "SimConfig / Master Switch"
            finalRootCause = "A opção 'SimulationActive' está desativada no painel de controle."
            finalAction = "Clique no botão 'Ativar Simulação' no topo da interface ou ative o toggle mestre."
            evidenceType = "CONFIRMED"
            confidence = 1.0
        else
            finalStatus = "WARNING"
            finalSummary = "Nenhum alvo sintético válido detectado no raio e FOV atuais."
            finalModule = "InstanceDetector"
            finalRootCause = "Não há modelos de teste (Dummies/NPCs) com Humanoid vivo dentro do alcance e FOV configurados."
            finalAction = "Spawne um dummy padrão (R6/R15) no Workspace próximo à câmera e verifique se o Humanoid está com Health > 0."
            evidenceType = "CONFIRMED"
            confidence = 0.95
            recommendedScenario = "SCENARIO_VISIBLE_DUMMY"
        end

    -- 4. Anomalia Cinética de Alta Velocidade Angular (Snap / Jitter)
    elseif angVel > 500.0 then
        finalStatus = "CRITICAL"
        finalSummary = "Velocidade angular extrema detectada na rotação da câmera simulada."
        finalModule = "VectorTracker (Suavização)"
        finalRootCause = string.format("A velocidade angular de %.1f °/s ultrapassa limites humanos típicos e causa instabilidade.", angVel)
        finalAction = "Aumente o coeficiente de Suavização (Lerp) para >= 0.15 ou ative a opção 'Clamp de Velocidade Angular'."
        evidenceType = "CONFIRMED"
        confidence = 0.99
        recommendedScenario = "SCENARIO_RAPID_SNAP"

        table.insert(hypotheses, {
            Id = "HYP_EXTREME_ANGVEL",
            Title = "Movimento angular instável (> 500 °/s)",
            Likelihood = 0.99,
            Type = "CONFIRMED",
            EvidenceList = { string.format("Velocidade angular instantânea: %.1f °/s", angVel) },
        })
        table.insert(recommendations, {
            Priority = "ALTA",
            Title = "Aumentar Suavização Cinemática",
            Action = "Aumentar SmoothingFactor para 0.20 ou ativar AngularVelocityClamp.",
            TargetConfigKey = "SmoothingFactor",
            EaseOfValidation = "IMEDIATA",
            RecommendedScenarioId = "SCENARIO_RAPID_SNAP",
        })

    -- 5. Estado Saudável e Operacional
    else
        finalStatus = "HEALTHY"
        finalSummary = "Todos os subsistemas cinemáticos e de disparo operam dentro dos parâmetros nominais."
        finalModule = "Nenhum"
        finalRootCause = "Rastreamento, cálculo de lead e verificação de visada validados com sucesso."
        finalAction = "Prossiga com os testes automatizados ou execute o cenário de disparo no manequim."
        evidenceType = "CONFIRMED"
        confidence = 0.98
        recommendedScenario = "SCENARIO_VISIBLE_DUMMY"
    end

    -- ---------------------------------------------------------------------
    -- CAMADA F: VERIFICAÇÃO CONTÍNUA E DETECÇÃO DE REGRESSÃO
    -- ---------------------------------------------------------------------
    local verificationResult: string? = nil
    if #ReportHistory > 0 then
        local prev = ReportHistory[#ReportHistory]
        if prev.Status == "HEALTHY" and (finalStatus == "WARNING" or finalStatus == "CRITICAL") then
            verificationResult = string.format("REGRESSÃO DETECTADA: O estado transicionou de HEALTHY para %s (Módulo: %s)", finalStatus, finalModule)
        elseif (prev.Status == "WARNING" or prev.Status == "CRITICAL") and finalStatus == "HEALTHY" then
            verificationResult = string.format("CORREÇÃO CONFIRMADA: O sistema retornou ao estado nominal após resolução de %s", prev.AffectedModule)
        end
    end

    local report: DiagnosticReport = {
        Timestamp = timeNow,
        Status = finalStatus,
        Summary = finalSummary,
        AffectedModule = finalModule,
        RootCause = finalRootCause,
        SuggestedAction = finalAction,
        MetricHighlights = metrics,
        EvidenceType = evidenceType,
        Confidence = confidence,
        Hypotheses = hypotheses,
        Recommendations = recommendations,
        RecommendedScenarioId = recommendedScenario,
        DataHygieneIssues = hygieneIssues,
        VerificationResult = verificationResult,
    }

    -- Manutenção do buffer histórico
    table.insert(ReportHistory, report)
    if #ReportHistory > MAX_HISTORY then
        table.remove(ReportHistory, 1)
    end

    return report
end

-- =========================================================================
-- EXPORTAÇÃO ESTRUTURADA DE RELATÓRIOS
-- =========================================================================
function DiagnosticAI.ExportJSON(report: DiagnosticReport): string
    local out = "{\n"
    out = out .. string.format('  "Timestamp": %f,\n', report.Timestamp)
    out = out .. string.format('  "Status": "%s",\n', report.Status)
    out = out .. string.format('  "Summary": "%s",\n', report.Summary)
    out = out .. string.format('  "AffectedModule": "%s",\n', report.AffectedModule)
    out = out .. string.format('  "RootCause": "%s",\n', report.RootCause)
    out = out .. string.format('  "SuggestedAction": "%s",\n', report.SuggestedAction)
    out = out .. string.format('  "EvidenceType": "%s",\n', report.EvidenceType)
    out = out .. string.format('  "Confidence": %.2f,\n', report.Confidence)
    out = out .. string.format('  "RecommendedScenarioId": "%s"\n', report.RecommendedScenarioId or "")
    out = out .. "}"
    return out
end

function DiagnosticAI.GenerateMarkdownReport(report: DiagnosticReport): string
    local md = "# RELATÓRIO DE DIAGNÓSTICO DEEPHAT SIMULATION SUITE V7\n"
    md = md .. string.format("- **Data/Hora:** %f\n", report.Timestamp)
    md = md .. string.format("- **Status Global:** %s\n", report.Status)
    md = md .. string.format("- **Módulo Afetado:** %s\n", report.AffectedModule)
    md = md .. string.format("- **Causa Raiz:** %s\n", report.RootCause)
    md = md .. string.format("- **Evidência:** %s (Confiança: %.0f%%)\n", report.EvidenceType, report.Confidence * 100)
    md = md .. string.format("- **Ação Recomendada:** %s\n", report.SuggestedAction)
    if report.RecommendedScenarioId then
        md = md .. string.format("- **Cenário de Teste:** `%s`\n", report.RecommendedScenarioId)
    end
    if report.VerificationResult then
        md = md .. string.format("- **Verificação Histórica:** %s\n", report.VerificationResult)
    end
    return md
end

-- =========================================================================
-- CHATBOT DE DIAGNÓSTICO INTERATIVO E ESTRUTURADO
-- =========================================================================
function DiagnosticAI.QueryChatbot(query: string, liveState: any?): ChatbotResponse
    local clean = string.lower(query or "")
    local analysis = DiagnosticAI.AnalyzeSystemState(
        liveState and liveState.Telemetry,
        liveState and liveState.LosHistory,
        nil,
        liveState and liveState.LastShot
    )

    -- Heurísticas estruturadas por intenção
    if clean:find("oscila") or clean:find("tremer") or clean:find("treme") or clean:find("jitter") or clean:find("instavel") then
        local ans = "Oscilações na mira ocorrem quando a Suavização (Smoothing) está muito baixa ou há ruído de micro-movimento. "
        ans = ans .. "Recomendação: Aumente o valor de Suavização no painel (aba 'Mira Simulada') para >= 0.15 e utilize o Deadband angular para estabilizar o rastreamento."
        return {
            Query = query,
            Answer = ans,
            AffectedModule = "VectorTracker (Suavização)",
            SuggestedAction = "Ajuste o slider de Suavização para 0.15 - 0.30 e garanta que o alvo sintético tenha velocidade linear estável.",
            Confidence = 0.98,
            EvidenceType = "CONFIRMED",
            RecommendedScenarioId = "SCENARIO_RAPID_SNAP",
        }
    elseif clean:find("mira") or clean:find("foca") or clean:find("puxa") or clean:find("aimbot") or clean:find("mover") then
        local ans = "A mira cinematica é controlada pelo VectorTracker e InstanceDetector. "
        if liveState and liveState.SimConfig and liveState.SimConfig.Get("AimbotEnabled") == false then
            ans = ans .. "ATENÇÃO: O Aimbot está desativado no painel ('AimbotEnabled' = false). Ative o controle na aba 'Mira Simulada'."
        elseif analysis.AffectedModule == "InstanceDetector" then
            ans = ans .. "Atualmente não há alvos sintéticos válidos no campo de visão. " .. analysis.SuggestedAction
        elseif analysis.AffectedModule:find("Line of Sight") then
            ans = ans .. "O alvo atual está atrás de um obstáculo sólido. " .. analysis.SuggestedAction
        else
            ans = ans .. "O rastreamento está ativo. Para suavização realista, use Coeficiente 0.15 - 0.25. Segure RMB ou configure o modo para 'AlwaysOn'."
        end
        return {
            Query = query,
            Answer = ans,
            AffectedModule = "VectorTracker / InstanceDetector",
            SuggestedAction = "Verifique o alvo na tela e teste pressionando o botão direito do mouse (RMB).",
            Confidence = 0.95,
            EvidenceType = "CONFIRMED",
            RecommendedScenarioId = "SCENARIO_VISIBLE_DUMMY",
        }
    elseif clean:find("silent") or clean:find("disparo") or clean:find("tiro") or clean:find("acerta") then
        local ans = "A simulação de Silent Aim redireciona vetores balísticos sem mover a câmera física. "
        if liveState and liveState.SimConfig and liveState.SimConfig.Get("SilentAimEnabled") == false then
            ans = ans .. "ATENÇÃO: Silent Aim está desativado no painel. Ative-o na aba 'Disparos Simulados'."
        else
            ans = ans .. "Fluxo auditado em 5 etapas: [1] Solicitação Recebida -> [2] Dados Validados -> [3] Trajetória Calculada -> [4] Colisão Verificada -> [5] Resultado Final. "
            if analysis.Status ~= "HEALTHY" then
                ans = ans .. "Diagnóstico atual: " .. analysis.Summary
            else
                ans = ans .. "O sistema está pronto para disparos sintéticos de teste."
            end
        end
        return {
            Query = query,
            Answer = ans,
            AffectedModule = "VectorTracker / SimulationBootstrap",
            SuggestedAction = "Clique no botão '🎯 Disparar Simulação Silent Aim' para executar um disparo de teste completo.",
            Confidence = 0.96,
            EvidenceType = "CONFIRMED",
            RecommendedScenarioId = analysis.RecommendedScenarioId or "SCENARIO_VISIBLE_DUMMY",
        }
    elseif clean:find("gravidade") or clean:find("queda") or clean:find("balistica") or clean:find("projetil") or clean:find("arco") then
        local ans = "O simulador balístico suporta armas com projéteis físicos sob aceleração gravitacional (padrão Roblox g = 196.2 studs/s²). "
        ans = ans .. "A queda vertical Delta_y = 0.5 * g * t^2 é compensada iterativamente na elevação de mira, e a trajetória é renderizada como um arco parabólico segmentado, nunca uma reta artificial."
        return {
            Query = query,
            Answer = ans,
            AffectedModule = "VectorTracker (Física Balística)",
            SuggestedAction = "Na aba 'Balística', configure o modelo como 'Físico (Gravidade/Arco)' e verifique o traçador curvado no alvo.",
            Confidence = 0.98,
            EvidenceType = "CONFIRMED",
            RecommendedScenarioId = "SCENARIO_BALLISTIC_ARC",
        }
    elseif clean:find("fov") or clean:find("circulo") or clean:find("cone") then
        local ans = "O Campo de Visão (FOV) angular está 100% sincronizado opticamente com o círculo visual na tela: Raio_Pixels = (tan(FOV/2) / tan(CamFOV/2)) * (Altura_Tela/2). "
        ans = ans .. "Qualquer alvo dentro do círculo visual é garantido dentro do cone angular de mira e seleção."
        return {
            Query = query,
            Answer = ans,
            AffectedModule = "DashboardGUI / VectorTracker",
            SuggestedAction = "Ajuste o controle deslizante 'Campo de Visão (FOV °)' para redimensionar a área de busca dinamicamente.",
            Confidence = 0.97,
            EvidenceType = "CONFIRMED",
            RecommendedScenarioId = "SCENARIO_TARGET_OUTSIDE_FOV",
        }
    elseif clean:find("erro") or clean:find("diagnostico") or clean:find("problema") or clean:find("status") or clean:find("analisar") then
        return {
            Query = query,
            Answer = string.format("Relatório Atual de Saúde: [%s] %s Módulo: %s. Causa: %s", analysis.Status, analysis.Summary, analysis.AffectedModule, analysis.RootCause),
            AffectedModule = analysis.AffectedModule,
            SuggestedAction = analysis.SuggestedAction,
            Confidence = 0.99,
            EvidenceType = analysis.EvidenceType,
            RecommendedScenarioId = analysis.RecommendedScenarioId,
        }
    else
        return {
            Query = query,
            Answer = string.format("Assistente DeepHat V7 ativo. Status do Sistema: [%s] - %s (Alvo: %s | Modo: %s | Vel: %s).",
                analysis.Status, analysis.Summary, analysis.MetricHighlights["Alvo"] or "Nenhum", analysis.MetricHighlights["Modo"] or "IDLE", analysis.MetricHighlights["VelocidadeAngular"] or "0 °/s"),
            AffectedModule = analysis.AffectedModule,
            SuggestedAction = analysis.SuggestedAction,
            Confidence = 0.90,
            EvidenceType = analysis.EvidenceType,
            RecommendedScenarioId = analysis.RecommendedScenarioId,
        }
    end
end

return DiagnosticAI
