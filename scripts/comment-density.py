#!/usr/bin/env python3
"""comment-density.py — measure and gate comment volume in a diff.

Backs `rules/knowledge-layering.md` § "Anti-pattern: a comment written for the
reviewer", whose volume claim was measured but shipped without a tool. It
reports cohort medians over a revision range, grouped by the `Co-Authored-By`
trailer. That covers the volume half of the section's success measure; the
"unchanged A/B/C/D distribution" half needs a hand pass — this tool classifies
nothing.

**There is deliberately no gate.** Three designs were calibrated against a
generation known to be concise, and all three died: per-commit on either of two
thresholds (catching 80-96% of the verbose cohort cost 52-79% false flags),
per-commit on both (false flags down to 12-22%, but detection down to 32-48%),
and per-block (the two cohorts share a median block of 3.0 lines, so no
threshold separates them). A gate at those rates teaches its reader to ignore
it. Do not re-add one without re-running that control — `--dump` emits the
per-commit rows it needs, and the numbers are in `docs/claim-verification.md`
§ "A comment written for the reviewer".

Counting rule (stated so the figure is reproducible, not so it is exact): only
lines whose first non-blank character opens a comment are counted, and a
"block" is a run of consecutive such lines *within one hunk*. It errs in both
directions — a trailing comment after code is missed, pushing the ratio down;
a full-line `//` inside a multiline string is counted, pushing it up — but the
first is far commoner, so it predominantly under-reports.

Usage:
  comment-density.py <range> [--repo DIR] [--by-model] [--min-added N]
"""

import argparse
import re
import statistics
import subprocess
import sys
from collections import defaultdict

# Full-line comment openers by extension. Block-comment continuation lines
# (` * …`) count too — they are the same authored prose.
LINE_MARKERS = {
    "//": {".swift", ".js", ".jsx", ".ts", ".tsx", ".go", ".java", ".kt",
           ".c", ".h", ".cc", ".cpp", ".hpp", ".rs", ".scala", ".dart"},
    "#": {".py", ".rb", ".sh", ".bash", ".zsh", ".yml", ".yaml", ".toml"},
}
BLOCK_OPEN = re.compile(r"^(/\*|\*|\"\"\"|'''|=begin)")

TEST_PATH = re.compile(r"(^|/)(tests?|spec|__tests__)/|[Tt]ests?\.\w+$|_test\.\w+$")


def markers_for(path):
    ext = path[path.rfind("."):] if "." in path else ""
    return [m for m, exts in LINE_MARKERS.items() if ext in exts]


def is_comment(line, markers):
    s = line.strip()
    if not s:
        return False
    return any(s.startswith(m) for m in markers) or bool(BLOCK_OPEN.match(s))


def git(repo, *args):
    return subprocess.run(["git", "-C", repo, *args],
                          capture_output=True, text=True, check=True).stdout


def commit_stats(repo, sha, include_tests):
    """Return (code_lines, comment_lines, block_sizes) over the commit's added lines."""
    diff = git(repo, "show", "--unified=0", "--format=", "--no-color", sha)
    code = comment = 0
    blocks, run, markers = [], 0, []
    for line in diff.splitlines():
        # A hunk header ends any run: under --unified=0 the next hunk is a
        # non-adjacent part of the file, so carrying `run` across one would
        # merge unrelated comments into a single oversized pseudo-block.
        if line.startswith("+++ b/") or line.startswith("@@"):
            if run:
                blocks.append(run)
                run = 0
            if line.startswith("@@"):
                continue
            path = line[6:]
            markers = [] if (not include_tests and TEST_PATH.search(path)) else markers_for(path)
            continue
        if not line.startswith("+") or line.startswith("+++") or not markers:
            continue
        body = line[1:]
        if is_comment(body, markers):
            comment += 1
            run += 1
        else:
            if run:
                blocks.append(run)
                run = 0
            if body.strip():
                code += 1
    if run:
        blocks.append(run)
    return code, comment, blocks


def model_of(repo, sha):
    trailer = git(repo, "show", "-s",
                  "--format=%(trailers:key=Co-Authored-By,valueonly)", sha)
    m = re.search(r"(Claude [\w.]+ [\d.]+)", trailer)
    return m.group(1) if m else "unknown"


def collect(repo, rev_range, include_tests, min_added):
    shas = git(repo, "rev-list", "--no-merges", rev_range).split()
    rows = []
    for sha in shas:
        code, comment, blocks = commit_stats(repo, sha, include_tests)
        if code + comment < min_added:
            continue
        rows.append({
            "sha": sha[:9],
            "code": code,
            "comment": comment,
            "ratio": comment / (code + comment),
            "blocks": len(blocks),
            "per_block": statistics.mean(blocks) if blocks else 0.0,
            "max_block": max(blocks) if blocks else 0,
        })
    return rows


def summarize(label, rows):
    if not rows:
        print(f"{label:<24} (no commits met the threshold)")
        return
    med = lambda k: statistics.median(r[k] for r in rows)
    print(f"{label:<24} n={len(rows):<4} ratio={med('ratio'):.1%}  "
          f"lines/block={med('per_block'):.1f}  blocks/commit={med('blocks'):.0f}")


def main():
    p = argparse.ArgumentParser(add_help=True)
    p.add_argument("range", help="git revision range, e.g. HEAD~200..HEAD")
    p.add_argument("--repo", default=".")
    p.add_argument("--by-model", action="store_true",
                   help="group by the Co-Authored-By trailer")
    p.add_argument("--include-tests", action="store_true")
    p.add_argument("--min-added", type=int, default=30)
    p.add_argument("--dump", action="store_true",
                   help="one TSV row per commit, so the calibration in the doc "
                        "can be re-run without reimplementing this")
    a = p.parse_args()

    rows = collect(a.repo, a.range, a.include_tests, a.min_added)
    if a.dump:
        print("sha\tmodel\tratio\tblocks\tper_block\tmax_block")
        for r in rows:
            print(f"{r['sha']}\t{model_of(a.repo, r['sha'])}\t{r['ratio']:.4f}\t"
                  f"{r['blocks']}\t{r['per_block']:.2f}\t{r['max_block']}")
        return 0
    if not a.by_model:
        summarize("all", rows)
        return 0
    groups = defaultdict(list)
    for r in rows:
        groups[model_of(a.repo, r["sha"])].append(r)
    for label in sorted(groups, key=lambda k: -len(groups[k])):
        summarize(label, groups[label])
    return 0


if __name__ == "__main__":
    sys.exit(main())
