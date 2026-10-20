#!/usr/bin/env python3
"""Disable only Fluent.Ribbon's host IsolatedStorage-backed automatic UI-state persistence.

Runs against the checked-out official VidCoder source. Intentionally fails closed if no
Fluent.Ribbon controls are found: an upstream UI change requires a new code review.

Usage: python scripts/patch-fluent-ribbon.py upstream [--check]
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path

TAG = re.compile(
    r"<!--.*?-->|<(?P<prefix>[A-Za-z_][\w.-]*):Ribbon(?=[\s/>])(?P<attrs>[^<>]*?)(?P<ending>/?>)",
    re.DOTALL,
)
ATTR = re.compile(r"(?P<lead>\sAutomaticStateManagement\s*=\s*)(?P<quote>['\"])(?P<value>.*?)(?P=quote)", re.DOTALL)
NAMESPACE = re.compile(r"\bxmlns:(?P<prefix>[A-Za-z_][\w.-]*)\s*=\s*(['\"])(?P<url>.*?)\2", re.DOTALL)


def process(path: Path, check: bool) -> int:
    original = path.read_text(encoding="utf-8-sig")
    namespace = {m.group("prefix"): m.group("url") for m in NAMESPACE.finditer(original)}
    count = 0

    def replace(match: re.Match[str]) -> str:
        nonlocal count
        raw = match.group(0)
        if raw.startswith("<!--"):
            return raw
        uri = namespace.get(match.group("prefix"), "")
        if uri != "urn:fluent-ribbon" and not uri.startswith("clr-namespace:Fluent;") and uri != "clr-namespace:Fluent":
            return raw
        count += 1
        attrs = match.group("attrs")
        present = list(ATTR.finditer(attrs))
        if len(present) > 1:
            raise RuntimeError(f"Multiple ribbon state attributes in {path}")
        if check:
            if len(present) != 1 or present[0].group("value").lower() != "false":
                raise RuntimeError(f"Unpatched Fluent.Ribbon state persistence: {path}")
            return raw
        if present:
            attrs = ATTR.sub(lambda m: f'{m.group("lead")}{m.group("quote")}False{m.group("quote")}', attrs)
        else:
            attrs += ' AutomaticStateManagement="False"'
        return f'<{match.group("prefix")}:Ribbon{attrs}{match.group("ending")}'

    updated = TAG.sub(replace, original)
    if count and not check:
        # Confirm the edited XAML is still well-formed, without rewriting its formatting.
        import xml.etree.ElementTree as ET
        try:
            ET.fromstring(updated)
        except ET.ParseError as exc:
            raise RuntimeError(f"Ribbon patch produced invalid XAML XML in {path}: {exc}") from exc
        if updated != original:
            path.write_text(updated, encoding="utf-8")
    if count:
        print(f"{'Checked' if check else 'Patched'} {count} Fluent.Ribbon control(s): {path}")
    return count


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    base = args.source / "VidCoder"
    if not base.is_dir():
        parser.error(f"VidCoder project missing: {base}")
    count = sum(process(p, args.check) for p in sorted(base.rglob("*.xaml")))
    if count == 0:
        raise RuntimeError(
            "No Fluent.Ribbon control was found in VidCoder XAML. Upstream may have "
            "changed the UI; refusing to produce a portable build with unverified state handling."
        )
    print(f"Fluent.Ribbon state persistence disabled/verified on {count} control(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
