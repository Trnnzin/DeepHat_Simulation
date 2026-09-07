# 🎯 3D Kinematics & Agent Behavior Simulator (Luau / Roblox)

Módulo avançado de controle cinemático vetorial e simulação de comportamento de câmera/mira para ambientes de testes de detecção de anomalias (Anti-Cheat Benchmarks).

---

## 🚀 Arquitetura Modular & Painel de 3 Colunas

O projeto conta com um Dashboard profissional de alta densidade em **Dark Mode com Red Accents** organizado em 3 colunas funcionais:

1. **Coluna 1 — Vetores e Direção**:
   - Toggle de ativação do módulo.
   - Sliders + Inputs numéricos bidirecionais: Ângulo de Campo (FOV), Coeficiente de Suavização (Smoothing), Velocidade Angular, Tempo de Resposta (ms), Precisão de Trajetória (%), Frequência de Atualização (Hz) e Raio de Atuação (m).
2. **Coluna 2 — Comportamento do Sistema**:
   - Seletor de Perfis rápidos em abas: `[Normal]` `[Leve]` `[Médio]` `[Agressivo]` `[Custom]`.
   - Parâmetros avançados: Frequência de Eventos, Intensidade de Resposta, Velocidade de Deslocamento, Curva de Aceleração, Duração do Ciclo e Agentes Simultâneos.
3. **Coluna 3 — Mapeamento de Coordenadas (HitBox)**:
   - Manequim wireframe com seleção interativa de nós corporais: `Head` (Cabeça), `Torso` (Tronco), `Arms` (Braços) e `Legs` (Pernas).
   - Display de telemetria em tempo real: Velocidade Angular instantânea, Linha de Visão / Oclusão (Raycast), Modo e taxa de quadros (FPS).
4. **Barra Inferior de Controle**:
   - Botões com ações imediatas: `[ ▶ INICIAR TESTE ]`, `[ ⏹ PARAR ]`, `[ ↺ RESETAR ]` e `[ 💾 SALVAR CONFIG ]`.
   - Atalho de teclado: tecla `[HOME]` ou `[RightShift]` para ocultar ou exibir a interface a qualquer momento.

---

## 📂 Estrutura de Arquivos

```
DeepHat_Simulation/
├── ModularSystem/
│   ├── SimConfig.lua                  # Central reativa de parâmetros (Observer Pattern)
│   ├── AdvancedKinematics.lua         # Motor de cinemática vetorial, easing e Perlin noise
│   ├── DashboardGUI.lua               # Interface visual 3-Colunas Dark + Redline
│   └── SimulationBootstrap.client.lua # Orquestrador principal com targeting de ossos
├── CameraController.lua               # Módulo standalone com Target Lock e pcall
├── AdvancedCameraController.lua
├── BehaviorSimulator.lua
├── CameraKinematics.lua
├── DeepHat_Standalone.lua
├── EngineCore.lua
├── LineOfSightSimulator.lua
├── MainTestRunner.lua
├── StressTestBenchmark.lua
├── COMO_USAR.txt
└── README.md
```

---

## 🛠️ Como Usar

1. No **Roblox Studio**, coloque a pasta `ModularSystem` dentro de `StarterPlayerScripts` (ou execute via script runner no executor).
2. O painel visual surgirá centralizado na tela:
   - Clique e arraste o cabeçalho superior para reposicionar a janela livremente.
   - Pressione `HOME` ou `RightShift` para alternar a exibição.
   - Ajuste os parâmetros pelos sliders ou digitando diretamente nos campos numéricos.
   - Selecione a região alvo clicando nos pontos do manequim (Head, Torso, Braços ou Pernas).
   - Clique em **INICIAR TESTE** para iniciar o rastreamento em tempo real.
