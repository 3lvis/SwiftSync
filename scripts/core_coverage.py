#!/usr/bin/env python3
"""Self-hosted code-coverage evaluation + regression gate for the SwiftSync library.

Reads the llvm-cov JSON that `swift test --enable-code-coverage --show-codecov-path` produces and acts
only on the public library at SwiftSync/Sources/SwiftSync — the demo packages are out of scope. No
third-party service: it's the toolchain's own coverage data plus this script, mirroring how the warnings,
perf, and format gates are in-repo too.

Subcommands:
  evaluate --head H.json
      Print a per-file + total line-coverage table (and a GitHub step summary). Never fails.
  patch --head H.json --diff-base <ref>
      Fail if any line *added* in this diff (under SwiftSync/Sources/SwiftSync) is an executable line
      that no test covers. The gate that bites: you can't add untested core code. Escape hatch: a
      trailing `// coverage:ignore` on the line.
  compare --head H.json --base B.json
      Fail if core total line coverage dropped vs base by more than EPSILON (a no-decrease ratchet, not
      an absolute target).
"""

import argparse
import json
import os
import re
import subprocess
import sys

CORE = "/SwiftSync/Sources/SwiftSync/"
EPSILON = 0.5  # percentage points of noise tolerance for the no-decrease gate


def core_files(path):
    data = json.load(open(path))
    return [f for f in data["data"][0]["files"] if CORE in f["filename"]]


def short(filename):
    return filename.split(CORE, 1)[1]


def line_coverage(file_obj):
    """line number -> covered? for executable lines (those with a region entry)."""
    executable, covered = {}, {}
    for line, _col, count, has_count, is_region, *_ in file_obj["segments"]:
        if not (has_count and is_region):
            continue
        executable[line] = True
        covered[line] = covered.get(line, False) or count > 0
    return covered  # keys are exactly the executable lines


def core_total(files):
    total = sum(f["summary"]["lines"]["count"] for f in files)
    hit = sum(f["summary"]["lines"]["covered"] for f in files)
    return hit, total, (100.0 * hit / total if total else 100.0)


def emit_summary(text):
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if path:
        with open(path, "a") as fh:
            fh.write(text + "\n")


def cmd_evaluate(args):
    files = sorted(core_files(args.head), key=lambda f: f["filename"])
    lines = ["| file | covered/lines | % |", "|---|---:|---:|"]
    print(f"{'file':40} {'cov/lines':>12} {'%':>7}")
    for f in files:
        s = f["summary"]["lines"]
        ratio = f"{s['covered']}/{s['count']}"
        print(f"{short(f['filename']):40} {ratio:>12} {s['percent']:6.1f}%")
        lines.append(f"| {short(f['filename'])} | {s['covered']}/{s['count']} | {s['percent']:.1f}% |")
    hit, total, pct = core_total(files)
    print("-" * 62)
    print(f"{'TOTAL (SwiftSync/Sources/SwiftSync)':40} {f'{hit}/{total}':>12} {pct:6.1f}%")
    lines.append(f"| **TOTAL** | **{hit}/{total}** | **{pct:.1f}%** |")
    emit_summary("### Core coverage — SwiftSync/Sources\n\n" + "\n".join(lines))
    return 0


def added_lines(diff_base):
    """{repo-relative path: {added line numbers}} for SwiftSync/Sources/SwiftSync swift files."""
    out = subprocess.run(
        ["git", "diff", "--unified=0", diff_base, "--", "SwiftSync/Sources/SwiftSync"],
        capture_output=True, text=True, check=True).stdout
    result, path, new_line = {}, None, 0
    for raw in out.splitlines():
        if raw.startswith("+++ b/"):
            path = raw[6:]
            result.setdefault(path, set())
        elif raw.startswith("@@"):
            m = re.search(r"\+(\d+)(?:,(\d+))?", raw)
            new_line = int(m.group(1))
        elif raw.startswith("+") and not raw.startswith("+++"):
            if path and path.endswith(".swift"):
                result[path].add(new_line)
            new_line += 1
    return {p: ls for p, ls in result.items() if ls}


def cmd_patch(args):
    cov_by_file = {short(f["filename"]): line_coverage(f) for f in core_files(args.head)}
    violations = []
    for path, lines in added_lines(args.diff_base).items():
        rel = path.split(CORE, 1)[1] if CORE in path else os.path.basename(path)
        covered = cov_by_file.get(rel)
        if covered is None:
            continue  # a new file with no coverage data yet, or not a library file
        source = open(path).read().splitlines()
        for ln in sorted(lines):
            if ln not in covered or covered[ln]:
                continue  # not executable, or already covered
            text = source[ln - 1] if ln - 1 < len(source) else ""
            if "coverage:ignore" in text:
                continue
            violations.append(f"{path}:{ln}: {text.strip()}")
    if violations:
        print("::error::New SwiftSync core lines are not covered by any test:")
        for v in violations:
            print(f"  {v}")
        print("Add a test, or annotate the line with `// coverage:ignore` if intentionally untestable.")
        return 1
    print("Patch coverage OK: every added SwiftSync core line is tested.")
    return 0


def cmd_compare(args):
    _, _, head_pct = core_total(core_files(args.head))
    _, _, base_pct = core_total(core_files(args.base))
    delta = head_pct - base_pct
    print(f"core coverage: base {base_pct:.1f}% -> head {head_pct:.1f}% ({delta:+.1f}pp)")
    if delta < -EPSILON:
        print(f"::error::SwiftSync core coverage dropped {-delta:.1f}pp (> {EPSILON}pp). "
              "Add tests for the code that lost coverage.")
        return 1
    return 0


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)
    e = sub.add_parser("evaluate"); e.add_argument("--head", required=True); e.set_defaults(fn=cmd_evaluate)
    p = sub.add_parser("patch"); p.add_argument("--head", required=True); p.add_argument("--diff-base", required=True); p.set_defaults(fn=cmd_patch)
    c = sub.add_parser("compare"); c.add_argument("--head", required=True); c.add_argument("--base", required=True); c.set_defaults(fn=cmd_compare)
    args = parser.parse_args()
    sys.exit(args.fn(args))


if __name__ == "__main__":
    main()
