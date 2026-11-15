#!/usr/bin/env python3
"""Build the HTML report served on port 8000 from the outputs in $WORK/out.

One page: machine and versions, a table of runs (median wall time, ratio to Spark,
CPU, GC, shuffle bytes, result check), bars of wall time, plans side by side for the
comparisons the blog post makes, Comet's fallback reasons, the SQL vs DataFrame diff,
links to the Spark UI of every run and to the flame graphs. Standard library only.
"""
import csv
import html
import os
import pathlib
import shutil

DESCRIPTIONS = {
    "A": "Spark only: the baseline",
    "A1": "Spark only, per-row shuffle checksum off",
    "AF": "Spark only, with the assert_true guard (baseline for F)",
    "B": "Spark + Comet, defaults: iceberg-java writes the files",
    "C": "Spark + Comet, native Iceberg write: Arrow from file to file",
    "D": "C with Comet's JVM columnar shuffle",
    "E": "C with Spark's shuffle between Comet stages",
    "F": "C with the assert_true guard: one fallback mid-stage",
}
ORDER = ["A", "A1", "AF", "B", "C", "D", "E", "F"]
COMPARISONS = [("A", "C", "Spark vs Comet end to end"),
               ("B", "C", "Comet: iceberg-java writer vs native write"),
               ("C", "F", "Comet: without and with a fallback mid-stage")]
CSS = """
body{font:14px/1.45 -apple-system,Segoe UI,Helvetica,Arial,sans-serif;margin:24px auto;max-width:1200px;padding:0 16px;color:#1f2328}
h1{font-size:22px}h2{font-size:17px;margin-top:32px;border-bottom:1px solid #d0d7de;padding-bottom:4px}
table{border-collapse:collapse;width:100%}th,td{border-bottom:1px solid #eaeef2;padding:6px 8px;text-align:right}
th:first-child,td:first-child,td.l{text-align:left}th{background:#f6f8fa}
.bar{background:#0969da;height:10px;border-radius:2px}.bar.spark{background:#9a6700}
pre{background:#f6f8fa;padding:10px;overflow:auto;font-size:12px;line-height:1.35}
.cols{display:grid;grid-template-columns:1fr 1fr;gap:12px}.muted{color:#656d76}
.ok{color:#1a7f37}.bad{color:#cf222e}details{margin:6px 0}
"""


def read_csv(path):
    if not path.is_file():
        return []
    with open(path) as f:
        return list(csv.DictReader(f))


def text(path, default=""):
    return path.read_text() if path.is_file() else default


def plan_tree(plan: str) -> str:
    """The operator tree at the top of a formatted plan (up to the first blank line)."""
    lines = []
    for line in plan.splitlines():
        if not line.strip() and lines:
            break
        lines.append(line)
    return "\n".join(lines)


def num(v, digits=2):
    try:
        return f"{float(v):,.{digits}f}"
    except (TypeError, ValueError):
        return ""


def main():
    work = pathlib.Path(os.environ.get("WORK", "/work"))
    machine, scale = os.environ["MACHINE_ID"], os.environ["SCALE"]
    out = work / "out" / machine / f"sf{scale}"
    report = pathlib.Path(os.environ.get("REPORT_DIR", work / "report"))
    report.mkdir(parents=True, exist_ok=True)

    summary = {r["run"]: r for r in read_csv(out / "summary.csv")}
    runs = [r for r in ORDER if r in summary]
    parts = [f"<!doctype html><meta charset=utf-8><title>Spark vs Comet, SF {html.escape(scale)}</title>",
             f"<style>{CSS}</style>",
             f"<h1>Spark vs Spark + Comet: Iceberg to Iceberg, TPC-H SF {html.escape(scale)}</h1>"]
    parts.append("<div class=cols><pre>" + html.escape(text(work / "out" / machine / "machine.txt")) +
                 "</pre><pre>" + html.escape(text(work / "out" / machine / "versions.txt")) + "</pre></div>")

    if not runs:
        parts.append("<p>No results yet for this machine and scale factor.</p>")
    else:
        results = {summary[r].get("result") for r in runs}
        check = ("<span class=ok>all runs produced the same result</span>" if len(results) == 1 else
                 "<span class=bad>runs produced different results: " + html.escape(", ".join(map(str, results))) +
                 "</span>")
        longest = max(float(summary[r]["wall_s"] or 0) for r in runs) or 1
        parts.append("<h2>Runs</h2><p>Medians over the measured iterations. " + check + ".</p>")
        parts.append("<table><tr><th>Run</th><th class=l>Configuration</th><th>Wall, s</th><th></th>"
                     "<th>vs A</th><th>Executor CPU, s</th><th>GC, s</th><th>Shuffle written, MB</th>"
                     "<th>Spark UI</th></tr>")
        for r in runs:
            s = summary[r]
            app = text(out / r / "app_id.txt").strip()
            width = 100 * float(s["wall_s"] or 0) / longest
            cls = "bar spark" if r.startswith("A") else "bar"
            mb = num(float(s["shuffle_write_bytes"] or 0) / 1e6, 1) if s.get("shuffle_write_bytes") else ""
            parts.append(
                f"<tr><td><b>{r}</b></td><td class=l>{html.escape(DESCRIPTIONS.get(r, ''))}</td>"
                f"<td>{num(s['wall_s'])}</td><td style='width:160px'><div class='{cls}' style='width:{width:.0f}%'></div></td>"
                f"<td>{num(s.get('wall_s_vs_A'))}</td><td>{num(s.get('executor_cpu_s'))}</td>"
                f"<td>{num(s.get('jvm_gc_s'))}</td><td>{mb}</td>"
                f"<td><a href='http://localhost:18080/history/{html.escape(app)}/SQL/'>open</a></td></tr>")
        parts.append("</table><p class=muted>Spark UI links open the History Server; pick the query named "
                     "'&lt;run&gt; iter1'.</p>")

        parts.append("<h2>Plans side by side</h2>")
        for left, right, title in COMPARISONS:
            if left in runs and right in runs:
                parts.append(f"<h3>{left} vs {right}: {html.escape(title)}</h3><div class=cols>")
                for r in (left, right):
                    parts.append(f"<div><b>{r}</b><pre>" +
                                 html.escape(plan_tree(text(out / r / "final_plan_iter1.txt"))) + "</pre></div>")
                parts.append("</div>")

        parts.append("<h2>Every run: final plan and Comet's notes</h2>")
        for r in runs:
            parts.append(f"<details><summary><b>{r}</b>: {html.escape(DESCRIPTIONS.get(r, ''))}</summary>"
                         "<p>Plan as it ran (after AQE):</p><pre>" +
                         html.escape(text(out / r / "final_plan_iter1.txt")) + "</pre>"
                         "<p>EXPLAIN EXTENDED before the run (Comet fallback reasons, if any):</p><pre>" +
                         html.escape(text(out / r / "explain_extended.txt")) + "</pre></details>")

    diff = out / "api_diff" / "plan_diff.txt"
    if diff.is_file():
        parts.append("<h2>SQL vs DataFrame API</h2><pre>" + html.escape(diff.read_text()) + "</pre>")

    flames = sorted((out / "profiles").glob("*/flame-*.html"))
    if flames:
        (report / "profiles").mkdir(exist_ok=True)
        links = []
        for f in flames:
            name = f"flame-cpu-{f.parent.name}.html"
            shutil.copyfile(f, report / "profiles" / name)
            links.append(f"<li><a href='profiles/{name}'>{f.parent.name}</a></li>")
        parts.append("<h2>CPU flame graphs</h2><ul>" + "".join(links) + "</ul>")

    (report / "index.html").write_text("\n".join(parts))
    print(f"report -> {report / 'index.html'}")


if __name__ == "__main__":
    main()
