# 🎯 DeepHat Simulation Suite (v6.0 PRO - Luau / Roblox Studio)

Suíte profissional de controle cinemático vetorial 3D, simulação de comportamento de câmera/mira, diagnósticos em tempo real e benchmarking de detecção de anomalias (Anti-Cheat Performance Rig).

---

## 🚀 Arquitetura & Interface Moderna (Dark Mode + Red Accents)

A suíte conta com um Dashboard de alta precisão inspirado nas melhores interfaces de ferramentas avançadas da comunidade Roblox:
- **Tema:** Dark Mode Fosco (`#0B0C10`, `#14161D`) com detalhes em vermelho carmesim (`#E02B36`).
- **Navegação em 8 Abas Especializadas:**
  1. **📊 Painel Geral (Overview):** Status do motor, ativação mestra, seletor de perfis em cards interativos (`Normal`, `Leve`, `Médio`, `Agressivo`, `Custom`) e métricas instantâneas de telemetria.
  2. **🎥 Câmera & Vetores:** Sliders e campos numéricos bidirecionais sincronizados (FOV, Smoothing Lerp, Velocidade Angular, Tempo de Resposta, Precisão, Frequência e Raio).
  3. **⚡ Simulação:** Modo de mira (`HoldRMB` ou contínuo), Micro-Variações Orgânicas (Perlin Noise Jitter), Intensidade, Velocidade e Curva Hermite Smoothstep.
  4. **👁️ Linha de Visão:** Realce visual (ESP Chams via `Highlight` AlwaysOnTop), Círculo dinâmico de FOV na tela, Predição Balística (Lead Tracking), Checagem de Paredes e Filtro de Equipe.
  5. **🎯 Mapeamento HitBox:** Manequim interativo em wireframe com seleção em tempo real de regiões anatômicas (`Head`, `Torso`, `Arms`, `Legs`).
  6. **🛠️ Diagnósticos:** Feed ao vivo de eventos de telemetria, logs com timestamp e botão para limpar histórico.
  7. **📈 Desempenho:** Monitor de frame-time (ms), FPS em tempo real, medidor de velocidade angular de pico e verificação de overhead.
  8. **⚙️ Configurações:** Exportação e importação de perfis em formato JSON, restauração de padrões e ativação do Watchdog.

- **🛡️ Watchdog Contínuo em Segundo Plano:**
  - Thread silenciosa de monitoramento de integridade que verifica constantemente a presença e sanidade da câmera (prevenindo vetores nulos ou NaNs), validação de limites do `SimConfig` e badge dinâmico de status na barra de título.

---

## 📂 Estrutura Modular dos Arquivos

```
DeepHat_Simulation/
├── ModularSystem/
│   ├── SimConfig.lua                  # Central reativa de estado (Observer Pattern & JSON I/O)
│   ├── DashboardGUI.lua               # Interface moderna com 8 abas, manequim e watchdog
│   ├── SimulationBootstrap.client.lua # Orquestrador do cliente com ciclo RenderStepped
│   ├── InstanceDetector.lua           # Varredura espacial, type guarding & hierarquia de partes
│   ├── VectorTracker.lua              # Álgebra linear, Epsilon Guard (1e-4), Lerp & Predição Lead
│   └── VisualOverlayRenderer.lua      # Gerenciador de memória de Highlights ESP
├── FPS_Client_Tests/
│   ├── AimSimulator.client.lua        # Teste isolado de Snap e Smooth
│   ├── WallhackSimulator.client.lua   # Teste isolado de visada através de paredes
│   └── GUIA_TESTES_FPS.txt            # Documentação dos testes de combate
├── EngineCore.lua                     # Matriz heurística de avaliação e score de suspeita
├── BehaviorSimulator.lua              # Gerador cinemático de dados de movimento e rotação
├── MainTestRunner.lua                 # Runner de testes unitários e de integração
├── StressTestBenchmark.lua            # Benchmark de estresse de 1.000 ciclos matriciais
├── LineOfSightSimulator.lua           # Avaliador de oclusão geométrica via Raycast seguro
├── DeepHat_Standalone.lua             # Build único consolidado v6.0 PRO
├── COMO_USAR.txt                      # Instruções detalhadas para Roblox Studio
└── README.md
```

---

## 🛠️ Como Usar no Roblox Studio

1. **Execução Modular (Recomendada):**
   - Arraste a pasta `ModularSystem` para dentro de `StarterPlayer -> StarterPlayerScripts`.
   - Inicie o jogo no modo Play (`F5`).
   - O painel abrirá automaticamente.
   - Pressione **`[HOME]`** ou **`[RightShift]`** para alternar a exibição da interface.

2. **Execução de Testes Automatizados no Console:**
   - Coloque `MainTestRunner.lua` como Script em `ServerScriptService`.
   - Aperte Run (`F8`) e observe os relatórios detalhados no Output.

3. **Execução de Benchmark de Estresse:**
   - Execute `StressTestBenchmark.lua` na Command Bar ou como Script para verificar a performance computacional em microssegundos.

---

## 📦 Publicação e Git

Para sincronizar suas alterações com o repositório remoto:

```bash
git add .
git commit -m "feat: Upgrade DeepHat v6.0 PRO com 8 abas, watchdog em segundo plano e benchmarks"
git push origin main
```
