"""Copy the upstream migration table and move the fork's slot after it."""

import argparse
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
MIGRATION_PATH = Path("Modules/Migration.lua")
TABLE = re.compile(r"(^local migrationFunctions = \{\n)(.*?)(^\})", re.M | re.S)
SLOT = re.compile(r"^    \[(\d+)\] = function\(", re.M)
FORK = re.compile(r"^    -- BEGIN FORK MIGRATIONS\n.*?^    -- END FORK MIGRATIONS\n", re.M | re.S)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("upstream_ref", help="Fetched upstream release tag or commit")
    args = parser.parse_args()

    path = ROOT / MIGRATION_PATH
    current = path.read_text()
    upstream = subprocess.check_output(
        ["git", "show", f"{args.upstream_ref}:{MIGRATION_PATH.as_posix()}"],
        cwd=ROOT,
        text=True,
    )
    current_table = TABLE.search(current)
    upstream_table = TABLE.search(upstream)
    fork = FORK.search(current_table[2]) if current_table else None
    if not upstream_table or not fork or len(SLOT.findall(fork[0])) != 1:
        parser.error("expected an upstream migration table and one marked fork slot")
    if FORK.search(upstream_table[2]):
        parser.error("the upstream ref already contains fork migrations")

    slots = [int(slot) for slot in SLOT.findall(upstream_table[2])]
    if not slots or slots != list(range(1, len(slots) + 1)):
        parser.error("upstream migration slots must be contiguous and ordered")

    new_slot = len(slots) + 1
    moved_fork = SLOT.sub(f"    [{new_slot}] = function(", fork[0])
    result = current[:current_table.start(2)] + upstream_table[2] + moved_fork + current[current_table.end(2):]
    if result != current:
        path.write_text(result)
    print(f"Fork migration slot: {new_slot}")


if __name__ == "__main__":
    main()
