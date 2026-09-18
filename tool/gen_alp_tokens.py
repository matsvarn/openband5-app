#!/usr/bin/env python3
"""Generate lib/openband/alp_tokens.dart from docs/openband5/design/tokens.json."""
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = ROOT / "docs/openband5/design/tokens.json"
DST = ROOT / "lib/openband/alp_tokens.dart"


def camel(name: str, prefix: str) -> str:
    parts = name[len(prefix):].split("-")
    head = parts[0]
    if head[0].isdigit():
        head = "s" + head
    return head + "".join(p.capitalize() for p in parts[1:])


def px(value: str) -> str:
    return re.sub(r"px$", "", value)


def main() -> None:
    data = json.loads(SRC.read_text())
    src = data["source"]
    tokens = data["tokens"]
    out = [
        "// GENERATED from docs/openband5/design/tokens.json",
        f"// (Paper file {src['paperFileId']}, hash {src['tokensContentHash']}).",
        "// Do not edit; run tool/gen_alp_tokens.py.",
        "import 'dart:ui';",
        "",
    ]

    def section(cls: str, prefix: str, ttype: str, render):
        out.append(f"abstract final class {cls} {{")
        for t in tokens:
            if t["type"] == ttype and t["name"].startswith(prefix):
                if t.get("description"):
                    out.append(f"  /// {t['description']}")
                out.append(f"  {render(camel(t['name'], prefix), t['value'])}")
        out.append("}")
        out.append("")

    section("AlpColor", "--color-alp-", "color",
            lambda n, v: f"static const Color {n} = Color(0xFF{v[1:].upper()});")
    section("AlpText", "--text-alp-", "fontSize",
            lambda n, v: f"static const double {n} = {px(v)};")
    section("AlpSpace", "--spacing-", "spacing",
            lambda n, v: f"static const double {n} = {px(v)};")
    section("AlpRadius", "--radius-alp-", "radius",
            lambda n, v: f"static const double {n} = {px(v)};")

    fonts = {t["name"]: t["value"] for t in tokens if t["type"] == "fontFamily"}
    out += [
        "abstract final class AlpFont {",
        f"  static const String sans = '{fonts['--font-sans']}';",
        f"  static const String display = '{fonts['--font-alp-display']}';",
        "}",
        "",
    ]
    DST.write_text("\n".join(out))
    print(f"wrote {DST.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
