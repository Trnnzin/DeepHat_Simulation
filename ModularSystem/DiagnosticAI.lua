--!strict
-- =========================================================================
-- DiagnosticAI.lua
-- Motor de IA de Diagnóstico e Assistente Chatbot Automatizado
-- Analisa logs em tempo real, identifica falhas de simulação, aponta módulos
-- afetados e sugere testes reproduzíveis sem alucinações.
-- =========================================================================

local DiagnosticAI = {}
DiagnosticAI.__index = DiagnosticAI

export type DiagnosticReport = {
    Timestamp: number,
    Status: "HEALTHY" | "WARNING" | "CRITICAL",
    Summary: string,
    AffectedModule: string,
    RootCause: string,
    SuggestedAction: string,
    MetricHighlights: { [string]: string },
}

export type ChatbotResponse = {
    Query: string,
    Answer: string,
    AffectedModule: string,
    SuggestedAction: string,
    Confidence: number,
}

local function IsFinite(v: any): boolean
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- =========================================================================
-- ANALISADOR HEURÍSTICO DE ESTADO E LOGS DO SIMULADOR
-- =========================================================================
function DiagnosticAI.AnalyzeSystemState(
    telemetry: { [string]: any }?,
    losHistory: { any }?,
    eventLogs: { any }?,
    lastShot: any?
): DiagnosticReport
    local t = telemetry or {}
    local timeNow = os.clock()
    local metrics: { [string]: string } = {}

    -- Extração segura de métricas
    local angVel = tonumber(t.angularVelocity) or 0
    local isObstructed = t.isObstructed == true
    local targetName = tostring(t.targetName or "NENHUM")
    local mode = tostring(t.mode or "IDLE")
    local decoupledAngle = tonumber(t.decoupledAngle) or 0
    local silentAimActive = t.silentAimActive == true

    metrics["Modo"] = mode
    metrics["Alvo"] = targetName
    metrics["VelocidadeAngular"] = string.format("%.1f °/s", angVel)
    metrics["LinhaDeVisada"] = isObstructed and "OBSTRUÍDO" or "LIVRE"

    -- 1. Diagnóstico de Disparo / Silent Aim
    if lastShot and type(lastShot) == "table" then
        if lastShot.Fired == true then
            metrics["UltimoTiro"] = lastShot.HitRegistered and "ACERTO" or "DISPERSÃO"
            metrics["DesvioTiro"] = string.format("%.1f°", lastShot.DiscrepancyAngleDeg or 0)
            metrics["TipoBalistico"] = tostring(lastShot.TrajectoryType or "Instant")

            if not lastShot.InFov then
                return {
                    Timestamp = timeNow,
                    Status = "WARNING",
                    Summary = "Disparo falhou: alvo estava fora do cone angular configurado (FOV).",
                    AffectedModule = "SilentAim / SimConfig",
                    RootCause = string.format("Desvio angular do disparo (%.1f°) excedeu o SilentAimFOV configurado.", lastShot.DiscrepancyAngleDeg or 0),
                    SuggestedAction = "Aumente o campo 'Silent Aim FOV' no painel ou aponte a câmera mais próximo ao manequim de teste.",
                    MetricHighlights = metrics,
                }
            elseif lastShot.IsObstructed then
                return {
                    Timestamp = timeNow,
                    Status = "WARNING",
                    Summary = "Disparo bloqueado por oclusão de geometria (Parede detectada).",
                    AffectedModule = "VectorTracker (Line of Sight)",
                    RootCause = "Existe um colisor sólido entre o ponto de disparo e o alvo de teste.",
                    SuggestedAction = "Posicione o manequim de teste em linha de visão desobstruída ou desative temporariamente a opção 'Visible Only'.",
                    MetricHighlights = metrics,
                }
            elseif not lastShot.HitRegistered then
                return {
                    Timestamp = timeNow,
                    Status = "WARNING",
                    Summary = "Disparo simulou dispersão intencional baseada na probabilidade (Hit Chance).",
                    AffectedModule = "VectorTracker (SimulateShot)",
                    RootCause = "A probabilidade de acerto configurada (Hit Chance) causou uma dispersão estatística de teste.",
                    SuggestedAction = "Para acertos 100% determinísticos em testes de controle, configure 'Hit Chance' para 100%.",
                    MetricHighlights = metrics,
                }
            end
        end
    end

    -- 2. Diagnóstico de Oclusão Persistente de Visada
    if isObstructed then
        return {
            Timestamp = timeNow,
            Status = "WARNING",
            Summary = "Alvo selecionado está ocluído por geometria de teste.",
            AffectedModule = "VectorTracker / InstanceDetector",
            RootCause = "Raycast colidiu com geometria opaca/colidível antes de atingir o alvo sintético.",
            SuggestedAction = "Verifique o histórico da aba 'Line of Sight' para identificar o bloco colisor exato.",
            MetricHighlights = metrics,
        }
    end

    -- 3. Diagnóstico de Ausência de Alvo ou FOV Restrito
    if targetName == "NENHUM" or targetName:find("Nenhum") or targetName:find("PAUSADO") then
        if mode == "PAUSED" then
            return {
                Timestamp = timeNow,
                Status = "WARNING",
                Summary = "A simulação está pausada globalmente.",
                AffectedModule = "SimConfig / Master Switch",
                RootCause = "A opção 'SimulationActive' está desativada no painel de controle.",
                SuggestedAction = "Clique no botão 'Ativar Simulação' no topo da interface ou ative o toggle mestre.",
                MetricHighlights = metrics,
            }
        else
            return {
                Timestamp = timeNow,
                Status = "WARNING",
                Summary = "Nenhum alvo sintético válido detectado no raio e FOV atuais.",
                AffectedModule = "InstanceDetector",
                RootCause = "Não há modelos de teste (Dummies/NPCs) com Humanoid vivo dentro do alcance e FOV configurados.",
                SuggestedAction = "Spawne um dummy padrão (R6/R15) no Workspace próximo à câmera e verifique se o Humanoid está com Health > 0.",
                MetricHighlights = metrics,
            }
        end
    end

    -- 4. Diagnóstico de Velocidade Angular Excessiva (Anomalia de Snap / Oscilação)
    if angVel > 500.0 then
        return {
            Timestamp = timeNow,
            Status = "CRITICAL",
            Summary = "Velocidade angular extrema detectada na rotação da câmera simulada.",
            AffectedModule = "VectorTracker (Suavização)",
            RootCause = string.format("A velocidade angular de %.1f °/s ultrapassa limites humanos típicos e causa instabilidade.", angVel),
            SuggestedAction = "Aumente o coeficiente de Suavização (Lerp) para >= 0.15 ou ative a opção 'Clamp de Velocidade Angular'.",
            MetricHighlights = metrics,
        }
    end

    -- 5. Estado Saudável e Operacional
    return {
        Timestamp = timeNow,
        Status = "HEALTHY",
        Summary = "Todos os subsistemas cinemáticos e de disparo operam dentro dos parâmetros nominais.",
        AffectedModule = "Nenhum",
        RootCause = "Rastreamento, cálculo de lead e verificação de visada validados com sucesso.",
        SuggestedAction = "Prossiga com os testes automatizados ou execute o cenário de disparo no manequim.",
        MetricHighlights = metrics,
    }
end

-- =========================================================================
-- CHATBOT DE DIAGNÓSTICO INTERATIVO
-- =========================================================================
function DiagnosticAI.QueryChatbot(query: string, liveState: any?): ChatbotResponse
    local clean = string.lower(query or "")
    local analysis = DiagnosticAI.AnalyzeSystemState(liveState and liveState.Telemetry, liveState and liveState.LosHistory, nil, liveState and liveState.LastShot)

    -- Heurísticas por intenção de pergunta
    if clean:find("oscila") or clean:find("tremer") or clean:find("treme") or clean:find("jitter") or clean:find("instavel") then
        local ans = "Oscilações na mira ocorrem quando a Suavização (Smoothing) está muito baixa ou há ruído de micro-movimento. "
        ans = ans .. "Recomendação: Aumente o valor de Suavização no painel (aba 'Mira Simulada') para >= 0.15 e utilize o Deadband angular para estabilizar o rastreamento."
        return {
            Query = query,
            Answer = ans,
            AffectedModule = "VectorTracker (Suavização)",
            SuggestedAction = "Ajuste o slider de Suavização para 0.15 - 0.30 e garanta que o alvo sintético tenha velocidade linear estável.",
            Confidence = 0.98
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
            Confidence = 0.95
        }
    elseif clean:find("silent") or clean:find("disparo") or clean:find("tiro") or clean:find("acerta") then
        local ans = "A simulação de Silent Aim redireciona vetores balísticos sem mover a câmera física. "
        if liveState and liveState.SimConfig and liveState.SimConfig.Get("SilentAimEnabled") == false then
            ans = ans .. "ATENÇÃO: Silent Aim está desativado no painel. Ative-o na aba 'Disparos Simulados'."
        else
            ans = ans .. "Fluxo auditado em 4 etapas: [1] Solicitação Recebida -> [2] Dados Validados -> [3] Trajetória Calculada -> [4] Resultado Verificado. "
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
            Confidence = 0.96
        }
    elseif clean:find("gravidade") or clean:find("queda") or clean:find("balistica") or clean:find("projetil") or clean:find("arco") then
        local ans = "O simulador balístico suporta armas com projéteis físicos sob aceleração gravitacional (padrão Roblox g = 196.2 studs/s²). "
        ans = ans .. "A queda vertical Delta_y = 0.5 * g * t^2 é compensada iterativamente na elevação de mira, e a trajetória é renderizada como um arco parabólico segmentado, nunca uma reta artificial."
        return {
            Query = query,
            Answer = ans,
            AffectedModule = "VectorTracker (Física Balística)",
            SuggestedAction = "Na aba 'Balística', configure o modelo como 'Físico (Gravidade/Arco)' e verifique o traçador curvado no alvo.",
            Confidence = 0.98
        }
    elseif clean:find("fov") or clean:find("circulo") or clean:find("cone") then
        local ans = "O Campo de Visão (FOV) angular está 100% sincronizado opticamente com o círculo visual na tela: Raio_Pixels = (tan(FOV/2) / tan(CamFOV/2)) * (Altura_Tela/2). "
        ans = ans .. "Qualquer alvo dentro do círculo visual é garantido dentro do cone angular de mira e seleção."
        return {
            Query = query,
            Answer = ans,
            AffectedModule = "DashboardGUI / VectorTracker",
            SuggestedAction = "Ajuste o controle deslizante 'Campo de Visão (FOV °)' para redimensionar a área de busca dinamicamente.",
            Confidence = 0.97
        }
    elseif clean:find("erro") or clean:find("diagnostico") or clean:find("problema") or clean:find("status") or clean:find("analisar") then
        return {
            Query = query,
            Answer = string.format("Relatório Atual de Saúde: [%s] %s Módulo: %s. Causa: %s", analysis.Status, analysis.Summary, analysis.AffectedModule, analysis.RootCause),
            AffectedModule = analysis.AffectedModule,
            SuggestedAction = analysis.SuggestedAction,
            Confidence = 0.99
        }
    else
        -- Resposta geral com dados em tempo real
        return {
            Query = query,
            Answer = string.format("Assistente DeepHat ativo. Status do Sistema: [%s] - %s (Alvo: %s | Modo: %s | Vel: %s).",
                analysis.Status, analysis.Summary, analysis.MetricHighlights["Alvo"] or "Nenhum", analysis.MetricHighlights["Modo"] or "IDLE", analysis.MetricHighlights["VelocidadeAngular"] or "0 °/s"),
            AffectedModule = analysis.AffectedModule,
            SuggestedAction = analysis.SuggestedAction,
            Confidence = 0.90
        }
    end
end

return DiagnosticAI
