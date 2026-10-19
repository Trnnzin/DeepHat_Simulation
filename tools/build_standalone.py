#!/usr/bin/env python3
"""
Gera DeepHat_Standalone.lua a partir dos módulos reais (fonte única da verdade).

Uso (a partir da raiz do repositório):   python tools/build_standalone.py

Transformações aplicadas a cada módulo:
  * remove `--!strict` e `local X = require(script.Parent.Y)` (os módulos viram locals do mesmo chunk)
  * hoista `local Nome = {}` para fora e envolve o corpo em `do ... end`
  * remove o `return Nome` final
  * `export type` -> `type` (export só é válido no topo de um ModuleScript)
O bootstrap é anexado por último (sem requires; EngineCore inline em vez da busca por FindFirstChild).
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODULES = [
    ("SimConfig", ROOT / "ModularSystem" / "SimConfig.lua"),
    ("ScenarioRunner", ROOT / "ModularSystem" / "ScenarioRunner.lua"),
    ("InstanceDetector", ROOT / "ModularSystem" / "InstanceDetector.lua"),
    ("VectorTracker", ROOT / "ModularSystem" / "VectorTracker.lua"),
    ("VisualOverlayRenderer", ROOT / "ModularSystem" / "VisualOverlayRenderer.lua"),
    ("Engine", ROOT / "EngineCore.lua"),
    ("DashboardGUI", ROOT / "ModularSystem" / "DashboardGUI.lua"),
]
BOOTSTRAP = ROOT / "ModularSystem" / "SimulationBootstrap.client.lua"
HEADER = ROOT / "tools" / "standalone_header.lua"
FOOTER = ROOT / "tools" / "standalone_footer.lua"
OUT = ROOT / "DeepHat_Standalone.lua"


def read(p: Path) -> str:
    return p.read_text(encoding="utf-8-sig").replace("\r\n", "\n").replace("\r", "\n")


def strip_common(src: str) -> str:
    src = re.sub(r"^--!strict[ \t]*\n", "", src)
    src = re.sub(r"^local \w+ = require\(script\.Parent\.\w+\)[ \t]*\n", "", src, flags=re.M)
    src = re.sub(r"^export type ", "type ", src, flags=re.M)
    return src


def wrap_module(name: str, path: Path) -> str:
    src = strip_common(read(path))
    decl = re.search(r"^local (\w+) = \{\}[ \t]*\n", src, flags=re.M)
    if not decl:
        raise SystemExit(f"{path.name}: 'local <Nome> = {{}}' não encontrado")
    table_name = decl.group(1)
    src = src[: decl.start()] + src[decl.end():]
    src = re.sub(r"^return %s[ \t]*\n?\s*$" % re.escape(table_name), "", src.rstrip() + "\n", flags=re.M)
    # Engine: o nome local no standalone é `Engine` (igual ao bootstrap)
    out_name = name
    if table_name != out_name:
        src = re.sub(r"\b%s\b" % re.escape(table_name), out_name, src)
    banner = f"-- {'=' * 73}\n-- MÓDULO: {path.name}\n-- {'=' * 73}\n"
    body = "\n".join(("    " + ln if ln.strip() else ln) for ln in src.strip("\n").split("\n"))
    return f"{banner}local {out_name} = {{}}\ndo\n{body}\nend\n"


def bootstrap_body() -> str:
    src = strip_common(read(BOOTSTRAP))
    # EngineCore já está inline no standalone
    src = re.sub(r"-- EngineCore \(avalia.*?\n\s*end\nend\n", "", src, flags=re.S, count=1)
    if "script.Parent" in src:
        raise SystemExit("bootstrap ainda referencia script.Parent após as transformações")
    return f"-- {'=' * 73}\n-- INICIALIZAÇÃO (SimulationBootstrap.client.lua)\n-- {'=' * 73}\n" + src


def main() -> int:
    parts = [read(HEADER).rstrip("\n") + "\n\n"]
    for name, path in MODULES:
        parts.append(wrap_module(name, path) + "\n")
    parts.append(bootstrap_body().rstrip("\n") + "\n\n")
    parts.append(read(FOOTER))
    text = "".join(parts).replace("\n", "\r\n")
    OUT.write_bytes(text.encode("utf-8"))
    print(f"Gerado {OUT.name}: {len(text.splitlines())} linhas")
    return 0


if __name__ == "__main__":
    sys.exit(main())
