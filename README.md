# 🎯 3D Kinematics & Agent Behavior Simulator (Luau / Roblox)

Módulo avançado de controle cinemático vetorial e simulação de comportamento de câmera/mira para ambientes de testes de detecção de anomalias (Anti-Cheat Benchmarks).

---

## 🚀 Arquitetura Modular

O projeto é dividido em 3 camadas desacopladas orientadas a eventos (**Observer Pattern**):

1. **`SimConfig.lua`**: Gerenciador de parâmetros em tempo real (FOV, Smoothing, SpeedMultiplier, TrackingPrecision, SnapFrequency, ReactionTime, Intensity). Suporta perfis pré-definidos (`Normal`, `Leve`, `Médio`, `Agressivo` e `Custom`).
2. **`AdvancedKinematics.lua`**: Motor matemático de cinemática com:
   - **`StepSnap`**: Mudança angular instantânea em 1 frame (pico de velocidade angular para emulação de snapping robótico).
   - **`StepSmooth`**: Interpolação não-linear usando curva sigmoide (*Hermite Smoothstep* $3x^2 - 2x^3$) com ruído procedural de baixa frequência (*Perlin Noise* 2D via `math.noise`) para simular micro-oscilações humanas.
   - **Verificação de Linha de Visão**: Detecção de oclusão geométrica via `RaycastParams` reutilizável (zero Garbage Collection).
3. **`DashboardGUI.lua`**: Interface de usuário moderna e minimalista (Dark Mode Slate/Obsidian) com cantos arredondados (`UICorner`), inputs numéricos, sliders e monitor de telemetria em tempo real.
4. **`SimulationBootstrap.client.lua`**: Script orquestrador que conecta a GUI aos módulos e aplica as transformações na câmera.

---

## 📂 Estrutura de Arquivos

```
DeepHat_Simulation/
├── ModularSystem/
│   ├── SimConfig.lua
│   ├── AdvancedKinematics.lua
│   ├── DashboardGUI.lua
│   └── SimulationBootstrap.client.lua
├── AdvancedCameraController.lua
├── BehaviorSimulator.lua
├── CameraKinematics.lua
├── EngineCore.lua
├── LineOfSightSimulator.lua
├── MainTestRunner.lua
└── StressTestBenchmark.lua
```

---

## 🛠️ Como Usar

1. No **Roblox Studio**, coloque a pasta `ModularSystem` dentro de `StarterPlayerScripts` (ou execute via script runner no ambiente de teste).
2. O painel visual surgirá na tela permitindo:
   - Alternar perfis com um clique.
   - Ajustar sensibilidade, FOV e precisão pelos sliders.
   - Clicar em **INICIAR TESTE** para acionar o tracking cinemático.