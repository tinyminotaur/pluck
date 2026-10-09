#!/usr/bin/env python3
"""Rename the project in one pass (code, targets, bundle id, defaults keys, docs, scripts, workflows).

    scripts/rename-project.py --name Twang [--slug twang] [--bundle co.tinyminotaur.twang] [--dry-run]

What it does
  * Pluck -> <Name>, PLUCK -> <NAME>, pluck -> <slug>   (whole project, text files only)
  * com.pluck.app -> <bundle>, tinyminotaur/pluck -> tinyminotaur/<slug>
  * renames every file and folder whose name contains Pluck / pluck
  * leaves docs/research/ and CHANGELOG history untouched
After running: build and test, rename the GitHub repo (GitHub redirects the old URL), and re-grant
Accessibility once (the bundle id changed). User settings reset because the defaults keys change.
"""
import argparse, os, re, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SKIP_DIRS = {".git", ".build", "build", "dist", "signing", ".swiftpm", "research"}
TEXT_EXT = {".swift", ".md", ".json", ".plist", ".sh", ".py", ".yml", ".yaml", ".txt", ".entitlements", ""}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", required=True, help="Display name, e.g. Twang")
    ap.add_argument("--slug", help="lowercase id for keys/urls (default: name lowercased)")
    ap.add_argument("--bundle", help="bundle id (default: co.tinyminotaur.<slug>)")
    ap.add_argument("--keep-repo-url", action="store_true", help="leave github.com/tinyminotaur/pluck links alone (use until the GitHub repo is renamed; GitHub redirects after)")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    if not re.fullmatch(r"[A-Z][A-Za-z0-9]+", a.name):
        sys.exit("--name must be CamelCase letters/digits, e.g. Twang")
    name, slug = a.name, (a.slug or a.name.lower())
    bundle = a.bundle or f"co.tinyminotaur.{slug}"
    upper = slug.upper()

    # Ordered, most specific first.
    KEEP = "\u0000KEEPREPO\u0000"
    subs = [
        ("com.pluck.app", bundle),
        ("tinyminotaur/pluck", KEEP if a.keep_repo_url else f"tinyminotaur/{slug}"),
        ("Pluck", name),
        ("PLUCK", upper),
        ("pluck", slug),
    ]
    changed, renamed, warnings = [], [], []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in filenames:
            path = os.path.join(dirpath, fn)
            if os.path.splitext(fn)[1] not in TEXT_EXT or os.path.islink(path):
                continue
            if os.path.relpath(path, ROOT) in ("CHANGELOG.md", "scripts/rename-project.py"):
                continue
            try:
                s = open(path, encoding="utf-8").read()
            except (UnicodeDecodeError, OSError):
                continue
            t = s
            for old, new in subs:
                t = t.replace(old, new)
            t = t.replace(KEEP, "tinyminotaur/pluck")
            if t != s:
                if re.search(rf"\b{slug}(ed|ing|s)\b", t):
                    warnings.append(os.path.relpath(path, ROOT))
                changed.append(os.path.relpath(path, ROOT))
                if not a.dry_run:
                    open(path, "w", encoding="utf-8").write(t)

    # Rename files, then directories, deepest first.
    paths = []
    for dirpath, dirnames, filenames in os.walk(ROOT, topdown=False):
        if any(p in SKIP_DIRS for p in os.path.relpath(dirpath, ROOT).split(os.sep)):
            continue
        for n in filenames + dirnames:
            if re.search(r"pluck", n, re.I):
                paths.append(os.path.join(dirpath, n))
    for p in paths:
        base = os.path.basename(p)
        nb = base.replace("Pluck", name).replace("PLUCK", upper).replace("pluck", slug)
        if nb != base:
            renamed.append((os.path.relpath(p, ROOT), nb))
            if not a.dry_run:
                subprocess.run(["git", "mv", p, os.path.join(os.path.dirname(p), nb)], cwd=ROOT, check=False)
    print(f"{'Would change' if a.dry_run else 'Changed'} {len(changed)} files, rename {len(renamed)} paths.")
    for r in renamed[:40]:
        print("  mv", r[0], "->", r[1])
    for w in warnings:
        print("  check wording (old word may have been an English verb) in", w)
    leftovers = subprocess.run(["grep", "-rIil", "pluck", "--exclude-dir=.git", "--exclude-dir=.build",
                                "--exclude-dir=research", "--exclude=CHANGELOG.md", "--exclude=rename-project.py", "."],
                               cwd=ROOT, capture_output=True, text=True).stdout.split()
    if leftovers and not a.dry_run:
        print("Files still mentioning the old name:", *leftovers[:20])

if __name__ == "__main__":
    main()
