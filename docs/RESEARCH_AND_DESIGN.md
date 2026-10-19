# DEEPHAT SIMULATION SUITE V7 — PESQUISA TÉCNICA & ARQUITETURA DE DESIGN
**Documento de Engenharia de Software e Especificação Técnica**  
*Versão:* 7.0 PRO  
*Ambiente:* Luau / Roblox Studio / Suíte Offline  
*Classificação:* Plataforma de Simulação Cinemática, Diagnósticos e Pesquisa Defensiva  

---

## 1. RESUMO EXECUTIVO & PROBLEMAS ATUAIS IDENTIFICADOS

O projeto **DeepHat Simulation Suite** foi concebido como uma plataforma de pesquisa cinemática, avaliação defensiva de integridade de miras e diagnóstico de anomalias em ambiente de simulação controlada no Roblox Studio. 

Apesar das iterações anteriores, uma análise técnica aprofundada revelou oportunidades críticas de engenharia:
1. **Sensibilidade à Taxa de Atualização (Frame-rate Dependency):** Interpolações lineares (`Lerp`) tradicionais utilizavam um fator fixo $\alpha$ por frame, gerando discrepâncias cinemáticas entre clientes a 30 FPS, 60 FPS, 144 FPS ou taxas variáveis.
2. **Micro-oscilações em Erros Mínimos (Jitter near Deadzone):** Ausência de zona morta (*deadzone*) angular adaptativa resultava em oscilação infinitesimal contínua da câmera ao tentar convergir para o centro exato da parte anatômica do alvo.
3. **Desacoplamento entre Trajetória Balística Visual e Verificação de Colisão:** Em versões anteriores, o feixe do disparo utilizava cálculo instantâneo enquanto a física simulava queda por gravidade sem que os segmentos intermediários do arco verificassem colisões com obstáculos.
4. **Camada de Diagnóstico Heurística Rígida vs. IA Estruturada:** A inteligência artificial de diagnóstico original operava com comparações heurísticas estáticas em bloco único, misturando sintomas, causas raízes confirmadas e hipóteses não testadas.

---

## 2. FONTES CONSULTADAS E NORMAS DE ENGENHARIA

As decisões de engenharia da versão V7 baseiam-se em documentações oficiais e fundamentos consagrados de computação gráfica e física computacional:

| Domínio | Fonte Oficial / Referência | Tópico Aplicado |
| :--- | :--- | :--- |
| **Colisão e Trajetórias** | [Roblox Creator Hub — Raycasting](https://create.roblox.com/docs/workspace/raycasting) | `workspace:Raycast`, `RaycastParams`, `Enum.RaycastFilterType.Exclude`, `CollisionGroup`, `RespectCanCollide` e `CanQuery`. |
| **Linguagem & Tipagem** | [Roblox Creator Hub — Luau](https://create.roblox.com/docs/luau) & [Type Checking](https://create.roblox.com/docs/luau/type-checking) | Análise estrita (`!strict`), união de tipos (`type`), enums discriminados, isolamento e validação de contratos de API. |
| **Ciclo de Execução** | [Roblox Creator Hub — RunService](https://create.roblox.com/docs/reference/engine/classes/RunService) | `BindToRenderStep` com `Enum.RenderPriority.Camera.Value + 1`, `Heartbeat` e desacoplamento de amostragem temporal. |
| **Verificação no Studio** | [Roblox Creator Hub — Testing Modes](https://create.roblox.com/docs/studio/testing-modes) & [TestService](https://create.roblox.com/docs/reference/engine/classes/TestService) | Metodologia de testes determinísticos em 3 níveis (Offline, Integração e Studio). |
| **Cinemática & Matemática 3D** | *Game Physics Engine Development* (Ian Millington) | Integração temporal semi-implícita de Euler, desacoplamento angular, compensação balística preditiva e interpolação exponencial contínua. |
| **Observabilidade de Sistemas** | *Site Reliability Engineering* (Google SRE Books) | Telemetria estruturada, rastreamento de estados, logs estratificados em 4 níveis (`OK`, `INFO`, `WARN`, `FAIL`) e isolamento de falhas. |

---

## 3. CONCEITOS TÉCNICOS FUNDAMENTAIS & FORMULAÇÕES MATEMÁTICAS

### 3.1 Interpolação Temporal Independente de Framerate (Exponential Smoothing)
Em vez da interpolação clássica $x_{t} = \text{lerp}(x_0, x_1, \alpha)$ que varia com o framerate, a equação diferencial de convergência suave é formulada como:
$$\alpha_{\text{temporal}} = 1 - e^{-\lambda \cdot \Delta t}$$
Onde $\lambda$ representa a constante de taxa de convergência e $\Delta t$ é o tempo decorrido no frame fornecido pelo `RunService`. Essa formulação garante convergência idêntica em qualquer taxa de quadros (30 FPS a 240 FPS).

### 3.2 Controle de Câmera Euler YXZ e Prevenção de Roll
Para impedir o efeito colateral conhecido como *camera spin* e rotações indesejadas de inclinação lateral (*roll*), toda rotação da câmera é decomposta em:
$$C_{\text{final}} = \text{CFrame.fromEulerAnglesYXZ}(\text{pitch}, \text{yaw}, 0)$$
O componente de rotação em $Z$ é fixado estritamente em zero radianos.

### 3.3 Estimativa de Velocidade com Filtragem de Ruído (Moving Average com Rejeição de Outliers)
Para estimar o vetor velocidade $\vec{v}_{\text{alvo}}$ de manequins móveis com ruído espacial de rede ou quantização de posição:
$$\vec{v}_{\text{bruta}} = \frac{\vec{p}_t - \vec{p}_{t-1}}{\Delta t}$$
$$\vec{v}_{\text{filtrada}} = \beta \cdot \vec{v}_{t-1} + (1 - \beta) \cdot \vec{v}_{\text{bruta}}$$
Com descarte automático (*clamping/reset*) caso $\|\vec{v}_{\text{bruta}}\| > v_{\text{max}}$, prevenindo saltos resultantes de respawn ou teletransporte.

### 3.4 Modelo Balístico Parabólico e Compensação de Queda
Para projéteis balísticos sujeitos à aceleração gravitacional constante $\vec{g} = (0, -g, 0)$:
$$\vec{p}(t) = \vec{p}_0 + \vec{v}_0 t + \frac{1}{2} \vec{g} t^2$$
O tempo estimado de impacto no alvo estacionário a uma distância $d = \|\vec{p}_{\text{alvo}} - \vec{p}_0\|$ com velocidade inicial $v_0$ é:
$$t_{\text{voo}} \approx \frac{d}{v_0}$$
A compensação de elevação de mira (*lead / bullet drop compensation*) para neutralizar a gravidade é:
$$\vec{p}_{\text{mira}} = \vec{p}_{\text{alvo}} - \frac{1}{2} \vec{g} \cdot (t_{\text{voo}})^2 = \vec{p}_{\text{alvo}} + \left(0, \frac{1}{2} g t_{\text{voo}}^2, 0\right)$$

### 3.5 Verificação de Colisão Física Multi-Segmentada
Em vez de um único raio reto que ignora a curvatura parabólica, a trajetória balística de duração $T$ é discretizada em $N$ segmentos temporais ($N \ge 10$). Para cada intervalo $[t_i, t_{i+1}]$:
$$\Delta \vec{p}_i = \vec{p}(t_{i+1}) - \vec{p}(t_i)$$
Executa-se `Workspace:Raycast(\vec{p}(t_i), \Delta \vec{p}_i, \text{params})`. Caso ocorra colisão, a simulação registra o ponto exato de impacto e a identidade física do obstáculo interceptador.

---

## 4. COMPARAÇÃO DE ABORDAGENS TÉCNICAS

| Componente | Abordagem Antiga / Inadequada | Abordagem V7 Adotada | Justificativa Técnica |
| :--- | :--- | :--- | :--- |
| **Mira Cinemática** | `Lerp(cam, target, smooth)` estático por frame. | Suavização exponencial com `1 - exp(-lambda * dt)`, deadzone e clamp angular. | Independência total de framerate e ausência de jitter em repouso. |
| **Gatilho de Teste** | Dependente de alvo pré-travado na tela. | Pipeline autônomo com verificação em 5 etapas e spawn automático sob demanda. | Permite testes reproduzíveis em qualquer mapa ou baseplate vazia. |
| **Silent Aim** | Cálculo probabilístico matemático em memória (`math.random`). | Verificação física via `Workspace:Raycast` com inspeção de geometria e peças. | Resultados verificáveis; diferencia acerto de colisão contra paredes. |
| **Balística** | Trajetória puramente cosmética via feixe único. | Arcos parabólicos segmentados em 10 sub-raycasts com gravidade real. | Fidelidade física estrita entre simulação matemática e colisão observada. |
| **Diagnóstico IA** | Bloco heurístico rígido de `if/else` com respostas textuais soltas. | Arquitetura em 6 camadas: Coleta, Validação, Regras, Inferência, Recomendações e Verificação. | Separação formal entre sintomas observados, fatos comprovados e hipóteses. |
| **Interface** | Labels estáticos e controles sem estado de bloqueio. | Componentes reativos, debounce em ações de teste, indicadores de 4 estados e rolagem adaptativa. | Previne condições de corrida, cliques concorrentes e cortes em telas menores. |

---

## 5. ARQUITETURA EM 6 CAMADAS DO NOVO MOTOR DE IA DE DIAGNÓSTICO (`DiagnosticAI`)

```
   ┌────────────────────────────────────────────────────────┐
   │         CAMADA A: COLETA E INGESTÃO DE TELEMETRIA       │
   │   (Logs, telemetria angular, histórico LOS, disparos)   │
   └───────────────────────────┬────────────────────────────┘
                               ▼
   ┌────────────────────────────────────────────────────────┐
   │         CAMADA B: HIGIENE E VALIDAÇÃO DE DADOS         │
   │    (Verificação de NaN, Inf, amostras mínimas, nils)    │
   └───────────────────────────┬────────────────────────────┘
                               ▼
   ┌────────────────────────────────────────────────────────┐
   │       CAMADA C: DIAGNÓSTICO DETERMINÍSTICO (REGRAS)    │
   │  (Associação verificada de evidências a causas raízes) │
   └───────────────────────────┬────────────────────────────┘
                               ▼
   ┌────────────────────────────────────────────────────────┐
   │   CAMADA D: ANÁLISE ESTRUTURADA DE HIPÓTESES & IA      │
   │  (Avaliação de confiança, árvore de decisão de falha)  │
   └───────────────────────────┬────────────────────────────┘
                               ▼
   ┌────────────────────────────────────────────────────────┐
   │        CAMADA E: RECOMENDAÇÕES PRIORIZADAS             │
   │  (Ações prescritivas classificadas por impacto/esforço)│
   └───────────────────────────┬────────────────────────────┘
                               ▼
   ┌────────────────────────────────────────────────────────┐
   │         CAMADA F: VERIFICAÇÃO AUTOMATIZADA             │
   │   (Execução de contraprovas e cenários reproduzíveis)  │
   └────────────────────────────────────────────────────────┘
```

1. **Camada A — Ingestão:** Recebe o snapshot de telemetria da engine (`angularVelocity`, `targetName`, `dt`), histórico de linha de visada (`LosHistory`), logs operacionais e estrutura completa do último disparo (`lastShot`).
2. **Camada B — Validação:** Invalida números complexos, `0/0` (NaN), infinitos e descarta amostras insuficientes, retornando `INSUFICIENTE` em vez de gerar diagnósticos fictícios.
3. **Camada C — Regras Determinísticas:** Mapeia padrões comprovados (ex: `Outcome == "OBSTACLE_BLOCKED"` $\implies$ obstáculo físico; `angularVelocity > 500` $\implies$ ganho de suavização instável).
4. **Camada D — Análise de Hipóteses:** Classifica conclusões entre:
   * **CONFIRMADO:** Apoiado por evidência direta e contraprova de teste.
   * **HIPÓTESE:** Possível fator correlacionado sem evidência definitiva.
   * **INCONCLUSIVO:** Dados insuficientes para atribuição causal.
5. **Camada E — Recomendações Priorizadas:** Fornece passos objetivos (ex: "Ajustar SilentAimFOV para 45°", "Reposicionar manequim sintético").
6. **Camada F — Verificação:** Conecta-se diretamente aos cenários automatizados do `ScenarioRunner`, permitindo testar a eficácia da ação sugerida.

---

## 6. CRITÉRIOS DE VALIDAÇÃO E LIMITAÇÕES CONHECIDAS

### 6.1 Critérios de Validação Objetiva
* **Precisão Balística:** O desvio entre o ponto de impacto simulado e o alvo não deve exceder 0.1 studs quando `HitChance == 100%` em linha de visada livre.
* **Estabilidade Angular:** Ausência de inclinação lateral (*roll zero*) comprovada numericamente em loop fechado de 60 quadros.
* **Isolamento de Alvos:** O sistema só deve interagir com modelos com a tag de conformidade `DeepHat_Synthetic` ou devidamente autorizados.

### 6.2 Limitações Conhecidas
* **Ambiente CLI sem Instância de Workspace:** Em testes puramente offline executados via executável `luau.exe`, serviços de física espacial como `Workspace:Raycast` utilizam mocks matemáticos determinísticos estruturados em `tests_offline/mocks.lua`. A verificação física espacial completa deve ser validada no Roblox Studio.
