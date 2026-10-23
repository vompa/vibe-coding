#!/usr/bin/env python3
"""Quick inventory of a codebase as Markdown.

Usage: python3 inventory.py <repo-path> [--max-lines 300]
Prints: project files, lines per folder (top 25), files over the limit,
test files per folder and existing documentation (spec, PRD, ADR, mockups).
Read-only; skips .git, node_modules, bin, obj, dist, build output and binaries.
"""
import collections
import pathlib
import sys

SKIP_DIRS = {".git", "node_modules", "bin", "obj", "dist", "build", "out", ".venv", "venv",
             "__pycache__", "target", ".next", "wwwroot", "coverage"}
CODE_EXT = {".cs", ".ts", ".tsx", ".js", ".jsx", ".vue", ".py", ".java", ".kt", ".go", ".rb",
            ".php", ".rs", ".swift", ".scala", ".fs", ".sql", ".bicep", ".tf", ".svelte"}
PROJECT_FILES = {"package.json", "pyproject.toml", "requirements.txt", "pom.xml", "build.gradle",
                 "go.mod", "Cargo.toml", "Gemfile", "composer.json", "Directory.Build.props",
                 "docker-compose.yml", "compose.yml", "Dockerfile"}
PROJECT_EXT = {".csproj", ".fsproj", ".sln", ".slnx"}
DOC_HINTS = ("spec", "prd", "adr", "architecture", "design", "mockup", "requirements",
             "calibration", "readme", "claude.md", "agents.md")


def is_test(path: pathlib.Path) -> bool:
    s = str(path).lower()
    return any(t in s for t in ("/test", "tests/", ".test.", ".spec.", "_test.", "test_"))


def walk(root: pathlib.Path):
    for p in root.rglob("*"):
        if any(part in SKIP_DIRS for part in p.relative_to(root).parts):
            continue
        if p.is_file():
            yield p


def count_lines(p: pathlib.Path) -> int:
    try:
        with p.open("rb") as f:
            return sum(1 for _ in f)
    except OSError:
        return 0


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    root = pathlib.Path(sys.argv[1]).resolve()
    limit = int(sys.argv[sys.argv.index("--max-lines") + 1]) if "--max-lines" in sys.argv else 300

    projects, docs, big, tests = [], [], [], collections.Counter()
    per_dir = collections.Counter()
    total = files = 0
    for p in walk(root):
        rel = p.relative_to(root)
        if p.name in PROJECT_FILES or p.suffix in PROJECT_EXT:
            projects.append(str(rel))
        low = str(rel).lower()
        if p.suffix in {".md", ".html", ".pdf", ".txt"} and any(h in low for h in DOC_HINTS):
            docs.append(str(rel) if p.suffix == ".pdf" else f"{rel} ({count_lines(p)} lines)")
        if p.suffix not in CODE_EXT:
            continue
        n = count_lines(p)
        files += 1
        total += n
        per_dir[str(rel.parent)] += n
        if is_test(rel):
            tests[str(rel.parent)] += 1
        elif n > limit:
            big.append((n, str(rel)))

    print(f"# Inventory {root.name}\n")
    print(f"Code files: {files}, total lines: {total}\n")
    print("## Projects / build files")
    print("\n".join(f"- {x}" for x in sorted(projects)) or "- none found")
    print("\n## Existing documentation (possible primary source of intent)")
    print("\n".join(f"- {x}" for x in sorted(docs)) or "- none found")
    print("\n## Lines per folder (top 25)")
    for d, n in per_dir.most_common(25):
        print(f"- {d}: {n}")
    print(f"\n## Production files over {limit} lines (legacy candidates)")
    for n, f in sorted(big, reverse=True):
        print(f"- {f}: {n}")
    if not big:
        print("- none")
    print("\n## Test files per folder")
    for d, n in sorted(tests.items()):
        print(f"- {d}: {n}")
    if not tests:
        print("- none found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
