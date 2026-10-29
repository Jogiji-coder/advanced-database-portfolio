"""Parses evidence/04_constraint_tests_output.txt into a pass/fail table (Markdown)."""
import os, re
here = os.path.dirname(os.path.abspath(__file__))
log = open(os.path.join(here, "..", "evidence", "04_constraint_tests_output.txt")).read().split("\n")
rows, current = [], None
for line in log:
    m = re.match(r"TEST (\d+) \[expect (\w+)\] (.*)", line)
    if m:
        current = list(m.groups())
    m2 = re.match(r"\s+-> SQLSTATE (\w+)", line)
    if m2 and current:
        num, exp, desc = current
        got = m2.group(1)
        rows.append((num, desc, exp, got, "PASS" if exp == got else "FAIL"))
        current = None
passed = sum(r[4] == "PASS" for r in rows)
out = [f"**Constraint test suite: {passed}/{len(rows)} tests behaved as expected.**", "",
       "| # | What is attempted | Expected SQLSTATE | Actual | Result |", "|---|---|---|---|---|"]
out += [f"| {n} | {d.replace('|','/')} | `{e}` | `{g}` | {r} |" for n, d, e, g, r in rows]
path = os.path.join(here, "..", "evidence", "constraint_test_summary.md")
open(path, "w").write("\n".join(out) + "\n")
print(f"{passed}/{len(rows)} passed -> {path}")
