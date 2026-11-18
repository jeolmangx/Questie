"""Build a Forever ZIP and record the exact checkout and archive digest."""

import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
from tempfile import TemporaryDirectory
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import build


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args], text=True).strip()


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python3 cli/package-forever.py OUTPUT_DIR")
    if git("status", "--porcelain", "--untracked-files=no"):
        raise SystemExit("Commit the source tree before packaging it.")
    output = Path(sys.argv[1]).resolve()
    output.mkdir(parents=True, exist_ok=True)
    toc_path = ROOT / "Questie_Forever.toc"
    toc = toc_path.read_text()
    version = re.search(r"^## Version: (\d+\.\d+\.\d+)$", toc, re.M)
    if not version:
        raise SystemExit("Expected a numeric version in Questie_Forever.toc.")
    modules = {line.strip().replace("\\", "/") for line in toc.splitlines() if line.strip() and not line.startswith("#")}
    if "Modules/Tracker/TrackerZoneFilter.lua" not in modules:
        raise SystemExit("Forever TOC is missing the zone filter.")
    build.includedExpansions = [key for key, entry in build.EXPANSIONS.items() if entry["flavor"] == "forever"]
    with TemporaryDirectory() as temp:
        folder = Path(temp) / "Questie"
        build.copy_content_to(str(folder))
        # CurseForge and Wago IDs belong to upstream, whose updates would overwrite the fork.
        packaged_toc = folder / toc_path.name
        lines = packaged_toc.read_text().splitlines(keepends=True)
        packaged_toc.write_text("".join(line for line in lines if not line.startswith(("## X-Curse-Project-ID:", "## X-Wago-ID:"))))
        zip_path = Path(shutil.make_archive(str(output / "Questie-forever"), "zip", temp, "Questie"))
    with ZipFile(zip_path) as archive:
        entries = set(archive.namelist())
        required = {"Questie/" + path for path in modules | {"Questie_Forever.toc", "Bindings.xml"}}
        if not required <= entries or archive.testzip() is not None:
            raise SystemExit("Forever ZIP is invalid or omits files referenced by the TOC.")
    metadata = {
        "commit": git("rev-parse", "HEAD"),
        "tree": git("rev-parse", "HEAD^{tree}"),
        "version": version[1],
        "sha256": hashlib.sha256(zip_path.read_bytes()).hexdigest(),
    }
    (output / "candidate.json").write_text(json.dumps(metadata, indent=2) + "\n")


if __name__ == "__main__":
    main()
