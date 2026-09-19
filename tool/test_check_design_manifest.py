#!/usr/bin/env python3
"""Temporary-tree tests for tool/check_design_manifest.py."""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from check_design_manifest import check_manifest, resolve_source_file


def _write(root: Path, rel: str, text: str) -> None:
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def _manifest(blocks: list[dict], screens: dict[str, str] | None = None) -> dict:
    return {
        "screens": screens or {"S-1": "Screen one"},
        "blocks": blocks,
    }


def _block(**overrides) -> dict:
    block = {
        "name": "OBThing",
        "paperNode": "N-1",
        "widget": "Thing",
        "file": "theme.dart",
        "usedIn": ["S-1"],
    }
    block.update(overrides)
    return block


class CheckDesignManifestTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        _write(
            self.root,
            "lib/openband/theme.dart",
            "class Thing extends StatelessWidget {}\n",
        )

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_known_valid(self) -> None:
        errors = check_manifest(_manifest([_block()]), repo_root=self.root)
        self.assertEqual(errors, [])

    def test_missing_file(self) -> None:
        errors = check_manifest(
            _manifest([_block(file="missing.dart")]),
            repo_root=self.root,
        )
        self.assertTrue(any("does not exist" in e for e in errors), errors)

    def test_missing_symbol(self) -> None:
        errors = check_manifest(
            _manifest([_block(widget="PhantomClass")]),
            repo_root=self.root,
        )
        self.assertTrue(any("not found" in e for e in errors), errors)

    def test_explicit_paper_only(self) -> None:
        errors = check_manifest(
            _manifest(
                [
                    _block(
                        name="OBCardRow",
                        paperNode="N-paper",
                        widget=None,
                        file=None,
                        implementationStatus="paper-only",
                    )
                ]
            ),
            repo_root=self.root,
        )
        self.assertEqual(errors, [])

    def test_unknown_used_in(self) -> None:
        errors = check_manifest(
            _manifest([_block(usedIn=["NOPE-0"])]),
            repo_root=self.root,
        )
        self.assertTrue(any("usedIn NOPE-0" in e for e in errors), errors)

    def test_duplicate_node(self) -> None:
        errors = check_manifest(
            _manifest(
                [
                    _block(),
                    _block(name="OBOther", widget="Thing", paperNode="N-1"),
                ]
            ),
            repo_root=self.root,
        )
        self.assertTrue(any("already used" in e for e in errors), errors)

    def test_ui2_file_resolver(self) -> None:
        _write(
            self.root,
            "lib/ui2/app_shell.dart",
            "class AppShell extends StatefulWidget {}\n",
        )
        path = resolve_source_file("ui2/app_shell.dart", self.root)
        self.assertEqual(path, self.root / "lib/ui2/app_shell.dart")
        errors = check_manifest(
            _manifest(
                [_block(file="ui2/app_shell.dart", widget="AppShell")]
            ),
            repo_root=self.root,
        )
        self.assertEqual(errors, [])

    def test_absent_status_is_implemented(self) -> None:
        errors = check_manifest(
            _manifest([_block()]),
            repo_root=self.root,
        )
        self.assertEqual(errors, [])
        missing = check_manifest(
            _manifest([_block(file=None, widget=None)]),
            repo_root=self.root,
        )
        self.assertTrue(any("missing" in e for e in missing), missing)

    def test_paper_only_phantom_file_fails(self) -> None:
        errors = check_manifest(
            _manifest(
                [
                    _block(
                        file="overview/customize.dart",
                        widget=None,
                        implementationStatus="paper-only",
                    )
                ]
            ),
            repo_root=self.root,
        )
        self.assertTrue(any("does not exist" in e for e in errors), errors)

    def test_unknown_status_fails(self) -> None:
        errors = check_manifest(
            _manifest([_block(implementationStatus="planned")]),
            repo_root=self.root,
        )
        self.assertTrue(any("unknown implementationStatus" in e for e in errors), errors)


if __name__ == "__main__":
    unittest.main()
