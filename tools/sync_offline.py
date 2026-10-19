import os

prefix = 'local __m = require("../mocks"); local game, task, warn, typeof = __m.game, __m.task, __m.warn, __m.typeof\n\n'
mods = ['EngineCore.lua', 'SimConfig.lua', 'DiagnosticAI.lua']
for m in mods:
    src_path = os.path.join('ModularSystem', m)
    if not os.path.exists(src_path):
        src_path = m
    if os.path.exists(src_path):
        with open(src_path, 'r', encoding='utf-8') as f:
            content = f.read()
        dst_path = os.path.join('tests_offline', '_gen', m)
        with open(dst_path, 'w', encoding='utf-8') as f:
            f.write(prefix + content)
        print(f"Synced {m} to tests_offline/_gen/")
