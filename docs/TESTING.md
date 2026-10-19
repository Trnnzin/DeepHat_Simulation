# DEEPHAT SIMULATION SUITE V7 — ESTRATÉGIA DE ENGENHARIA DE TESTES
**Diretriz de Testes em Três Níveis, Procedimentos de Reprodução e Matriz de Regressão**  
*Versão:* 7.0 PRO  

---

## 1. PIRÂMIDE DE TESTES EM TRÊS NÍVEIS

A confiabilidade do **DeepHat Simulation Suite** é assegurada por uma pirâmide de testes desacoplada que distingue rigorosamente validações matemáticas offline de execuções com o motor físico real do Roblox Studio:

```
                  ┌──────────────────────┐
                  │       NÍVEL 3        │
                  │   ROBLOX STUDIO      │
                  │ (Raycast físico,     │
                  │  física do motor,    │
                  │  renderização de UI) │
                  └──────────┬───────────┘
                             │
                  ┌──────────┴───────────┐
                  │       NÍVEL 2        │
                  │     INTEGRAÇÃO       │
                  │ (Pipeline 5 etapas,  │
                  │  eventos e reatividade│
                  │   entre subsistemas) │
                  └──────────┬───────────┘
                             │
                  ┌──────────┴───────────┐
                  │       NÍVEL 1        │
                  │   SUÍTE OFFLINE      │
                  │  (Luau standalone,   │
                  │   SimConfig, Euler,  │
                  │  regras e diagnósticos)│
                  └──────────────────────┘
```

---

## 2. NÍVEL 1: TESTES OFFLINE (`tests_offline/run_offline.lua`)

Executados fora do Roblox Studio diretamente via interpretador oficial Luau (`luau.exe`), validando isolamento, parsing de dados, consistência matemática e integridade de memória sem depender de serviços externos.

* **Comando:**
  ```powershell
  .luau_tools\luau.exe tests_offline/run_offline.lua
  ```
* **Escopo de Validação:**
  1. `EngineCore`: Cálculo de suspeição defensiva, tolerâncias de velocidade angular, limites exclusivos, rejeição de NaN.
  2. `SimConfig`: Persistência via adaptadores, restauração atômica, importação e exportação de JSON com validação de schema, observers reativos.
  3. `DiagnosticAI`: Classificação de 8 resultados de disparo (`SUCCESS`, `TARGET_OUTSIDE_FOV`, `OBSTACLE_BLOCKED`, `PROBABILISTIC_SPREAD`, etc.), integridade de hipóteses e respostas determinísticas do chatbot.

---

## 3. NÍVEL 2: TESTES DE INTEGRAÇÃO (`MainTestRunner.lua`)

Valida os contratos entre módulos no ambiente Luau do Roblox Studio, cobrindo 28 critérios formais de aceitação:

* **Critérios [1] a [10]:** Inicialização do SimConfig, sanitização de limites de FOV, exportação/importação e detecção de anomalias cinemáticas.
* **Critérios [11] a [18]:** Rastreamento de instâncias, resolução anatômica de partes (`Head`, `Torso`, etc.), histerese de seleção e invalidação por morte.
* **Critérios [19] a [26]:** Convergência cinemática Euler YXZ (Roll zero), compensação balística preditiva, queda por gravidade ($\Delta Y = \frac{1}{2}gt^2$) e resposta do assistente de IA.
* **Critério [27]:** Pipeline de disparo simulado em 5 etapas executando os 7 cenários reproduzíveis de disparo.
* **Critério [28]:** Automação de instâncias sintéticas (`SpawnSyntheticDummy`) com marcação de segurança `DeepHat_Synthetic`.

---

## 4. NÍVEL 3: TESTES NO ROBLOX STUDIO (PROCEDIMENTO REPRODUZÍVEL)

Para validar a física real do motor Roblox, utilize o seguinte procedimento:

1. **Passo 1 — Carga do Módulo:**
   No Roblox Studio, inicie uma sessão em modo Play e execute via Command Bar:
   ```lua
   loadstring(game:HttpGet("https://raw.githubusercontent.com/Trnnzin/DeepHat_Simulation/main/DeepHat_Standalone.lua"))()
   ```
2. **Passo 2 — Validação de Disparo sem Alvo:**
   * Abra a aba *Disparos Simulados*.
   * Certifique-se de que nenhum alvo esteja à vista.
   * Clique em `🎯 DISPARAR TESTE SILENT AIM`.
   * **Resultado Esperado:** O pipeline transita para a Etapa 2 e relata `TARGET_INVALID` ou `TARGET_OUTSIDE_FOV` com o desvio angular correspondente.
3. **Passo 3 — Validação com Manequim Sintético:**
   * Clique em `🤖 SPAWN DUMMY`. Um manequim será instanciado no Workspace a 35 studs à frente.
   * Clique em `🎯 DISPARAR TESTE SILENT AIM`.
   * **Resultado Esperado:** O feixe traçador atinge a cabeça do dummy, o manequim reage fisicamente com redução de 15 HP e a interface exibe `[5/5] RESULTADO_FINAL` com `● TESTADO COM SUCESSO`.
4. **Passo 4 — Validação com Obstáculo Sólido:**
   * Clique no cenário `▶ Parede Bloqueando`.
   * **Resultado Esperado:** O projétil colide contra a barreira intermediária e o painel exibe `OBSTACLE_BLOCKED` indicando o nome exato da peça interceptora.
5. **Passo 5 — Validação de Balística Curva:**
   * Na aba *Balística*, selecione o modelo *Físico (Gravidade/Arco)*.
   * Configure a gravidade para `196.2` e ative a compensação de queda.
   * Dispare e observe o arco parabólico segmentado em 10 sub-raycasts sobrepostos à geometria.

---

## 5. MATRIZ DE REGRESSÃO

| ID | Cenário | Entrada | Saída Esperada | Status |
| :--- | :--- | :--- | :--- | :--- |
| **REG-01** | Disparo em Alvo Visível | Alvo a 40 studs, FOV 35°, Visada livre | `Outcome = SUCCESS`, colisão física comprovada | **APROVADO** |
| **REG-02** | Disparo com Barreira | Alvo atrás de parede com CanCollide/CanQuery | `Outcome = OBSTACLE_BLOCKED`, `Success = false` | **APROVADO** |
| **REG-03** | Alvo Fora do FOV | Ângulo relativo de 48°, FOV configurado em 35° | `Outcome = TARGET_OUTSIDE_FOV`, parado na Etapa 2 | **APROVADO** |
| **REG-04** | Alvo Removido | Alvo deletado do Workspace antes do impacto | `Outcome = TARGET_INVALID`, parado na Etapa 2 | **APROVADO** |
| **REG-05** | Dispersão Probabilística | `HitChance = 0%`, alvo perfeitamente alinhado | `Outcome = PROBABILISTIC_SPREAD`, `Success = false` | **APROVADO** |
| **REG-06** | Módulo Desligado | `SilentAimEnabled = false` | `Outcome = MODULE_DISABLED`, parado na Etapa 1 | **APROVADO** |
| **REG-07** | Balística com Gravidade | Projétil físico a 200 studs, $g = 196.2$ | Curvatura comprovada com $\Delta Y > 0$ e colisão | **APROVADO** |
| **REG-08** | Invalidação por Morte | Humanoid com Health = 0 durante rastreamento | Alvo deselecionado imediatamente sem travar mira | **APROVADO** |
