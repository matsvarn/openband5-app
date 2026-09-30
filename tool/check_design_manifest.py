#!/usr/bin/env python3
"""Validate docs/openband5/design/blocks.json.

Checks JSON shape, unique block paperNode values, usedIn ⊆ screens, and
that implemented file/widget pairs exist in source. This is a source-reference
check only — it does not verify routing or visual acceptance.
"""
from __future__ import annotations

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = ROOT / "docs/openband5/design/blocks.json"

_STATUS_IMPLEMENTED = {None, "implemented"}
_STATUS_PAPER_ONLY = "paper-only"


def _type_decl(name: str) -> re.Pattern[str]:
    # class Foo / enum Foo / mixin Foo / typedef Foo / extension Foo
    return re.compile(
        r"(?:^|\n)[ \t]*(?:abstract\s+|base\s+|final\s+|sealed\s+|mixin\s+)*"
        rf"(?:class|enum|mixin|typedef|extension)\s+{name}\b"
    )


def _callable_decl(name: str) -> re.Pattern[str]:
    # Widget foo( / String foo( / Future<void> foo(
    return re.compile(
        rf"(?:^|\n)[ \t]*(?:static\s+)?[\w.<>,?\[\]\s]+\s+{name}\s*[\(<]"
    )


def resolve_source_file(file_field: str, repo_root: pathlib.Path) -> pathlib.Path:
    """theme.dart → lib/openband/; ui2/... → lib/ui2/...."""
    rel = file_field.replace("\\", "/").lstrip("/")
    if rel.startswith("ui2/"):
        path = repo_root / "lib" / rel
    elif rel.startswith("lib/"):
        path = repo_root / rel
    else:
        path = repo_root / "lib" / "openband" / rel
    return path


def _declares(source: str, name: str) -> bool:
    if not name or not re.fullmatch(r"[_A-Za-z]\w*", name):
        return False
    escaped = re.escape(name)
    if _type_decl(escaped).search(source):
        return True
    if _callable_decl(escaped).search(source):
        return True
    return False


def symbol_in_source(source: str, widget: str) -> bool:
    """Conservative declaration search. Not a Dart parser."""
    parts = [p for p in widget.split(".") if p]
    if not parts:
        return False
    return all(_declares(source, part) for part in parts)


def _is_implemented(status: object, errors: list[str], name: str) -> bool:
    if status in _STATUS_IMPLEMENTED:
        return True
    if status == _STATUS_PAPER_ONLY:
        return False
    errors.append(f"{name}: unknown implementationStatus {status!r}")
    return False


def check_manifest(data: dict, *, repo_root: pathlib.Path) -> list[str]:
    screens = set(data["screens"])
    blocks = data["blocks"]
    names = {b.get("name") for b in blocks}
    errors: list[str] = []
    seen_nodes: dict[object, str] = {}
    for b in blocks:
        name = b.get("name") or "<unnamed>"
        status = b.get("implementationStatus")
        implemented = _is_implemented(status, errors, name)
        for key in ("name", "paperNode"):
            if not b.get(key):
                errors.append(f"{name}: missing {key}")
        if implemented:
            for key in ("widget", "file"):
                if not b.get(key):
                    errors.append(f"{name}: missing {key}")
        node = b.get("paperNode")
        if node in seen_nodes:
            errors.append(
                f"{name}: paperNode {node} already used by {seen_nodes[node]}"
            )
        seen_nodes[node] = name
        for s in b.get("usedIn") or []:
            if s != "*" and s not in screens:
                errors.append(f"{name}: usedIn {s} is not a known screen")
        if "." in name and "variant" not in b and "variants" not in b:
            base = name.split(".")[0]
            if base not in names:
                errors.append(
                    f"{name}: dotted name without variant field or base block {base}"
                )

        file_field = b.get("file")
        widget = b.get("widget")
        if not file_field and not widget:
            continue
        if not file_field:
            errors.append(f"{name}: missing file")
            continue
        path = resolve_source_file(str(file_field), repo_root)
        try:
            path.resolve().relative_to(repo_root.resolve())
        except ValueError:
            errors.append(f"{name}: file {file_field} is outside the repo")
            continue
        if not path.is_file():
            errors.append(f"{name}: file {file_field} does not exist ({path})")
            continue
        if not widget:
            if implemented:
                errors.append(f"{name}: missing widget")
            continue
        source = path.read_text(encoding="utf-8")
        if not symbol_in_source(source, str(widget)):
            errors.append(
                f"{name}: widget {widget} not found in {file_field}"
            )
    return errors


def main() -> int:
    data = json.loads(SRC.read_text(encoding="utf-8"))
    errors = check_manifest(data, repo_root=ROOT)
    if errors:
        print("\n".join(errors))
        return 1
    print(f"ok: {len(data['blocks'])} blocks, {len(data['screens'])} screens")
    return 0


if __name__ == "__main__":
    sys.exit(main())
