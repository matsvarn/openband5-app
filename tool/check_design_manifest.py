#!/usr/bin/env python3
"""Validate docs/openband5/design/blocks.json."""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = ROOT / "docs/openband5/design/blocks.json"


def main() -> int:
    data = json.loads(SRC.read_text())
    screens = set(data["screens"])
    blocks = data["blocks"]
    names = {b.get("name") for b in blocks}
    errors = []
    seen_nodes = {}
    for b in blocks:
        name = b.get("name", "<unnamed>")
        for key in ("name", "paperNode", "widget", "file"):
            if not b.get(key):
                errors.append(f"{name}: missing {key}")
        node = b.get("paperNode")
        if node in seen_nodes:
            errors.append(f"{name}: paperNode {node} already used by {seen_nodes[node]}")
        seen_nodes[node] = name
        for s in b.get("usedIn", []):
            if s != "*" and s not in screens:
                errors.append(f"{name}: usedIn {s} is not a known screen")
        if "." in name and "variant" not in b and "variants" not in b:
            base = name.split(".")[0]
            if base not in names:
                errors.append(f"{name}: dotted name without variant field or base block {base}")
    if errors:
        print("\n".join(errors))
        return 1
    print(f"ok: {len(blocks)} blocks, {len(screens)} screens")
    return 0


if __name__ == "__main__":
    sys.exit(main())
