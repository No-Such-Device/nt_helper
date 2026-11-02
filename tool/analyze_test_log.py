#!/usr/bin/env python3
"""Print the slowest tests recorded in a Flutter test log."""

from __future__ import annotations

import argparse
import re
from collections import defaultdict
from pathlib import Path

LINE = re.compile(r"^(\d+):(\d+) \+\d+ ~\d+: (.+)$")
TEST_PATH = re.compile(r"^(.*?\.dart): (.+)$")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("log", type=Path)
    parser.add_argument("-n", type=int, default=20)
    args = parser.parse_args()

    spans: dict[str, list[int]] = defaultdict(list)
    for line in args.log.read_text().splitlines():
        match = LINE.match(line)
        if not match:
            continue
        path_match = TEST_PATH.match(match.group(3))
        if not path_match:
            continue
        name = f"{path_match.group(1)}: {path_match.group(2)}"
        seconds = int(match.group(1)) * 60 + int(match.group(2))
        spans[name].append(seconds)

    slowest = sorted(
        ((max(values) - min(values), name) for name, values in spans.items() if len(values) > 1),
        reverse=True,
    )
    for duration, name in slowest[: args.n]:
        print(f"{duration:4d}s  {name}")


if __name__ == "__main__":
    main()
