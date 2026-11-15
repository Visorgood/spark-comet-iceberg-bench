#!/usr/bin/env python3
"""Turn Spark event logs from bench.py runs into CSV tables and final plans.

Reads, for every run directory under --results (one per run id, written by
bench.py), the event log of that application from --events, and finds the SQL
executions whose description is "<run> <label>". For each it sums the task
metrics of all stages that ran for it and writes:

  <run>/iterations.csv     one row per iteration (warmup + measured)
  <run>/stages_iter1.csv   one row per stage of the first measured iteration
  <run>/accumulables_iter1.csv  every named accumulator per stage (Comet metrics too)
  <run>/final_plan_iter1.txt    the final (post-AQE) physical plan of iter1
  summary.csv              per run: medians over measured iterations, and ratios to the spark run

Standard library only. Event logs must be uncompressed and not rolled
(spark.eventLog.compress=false, spark.eventLog.rolling.enabled=false).
"""
import argparse
import csv
import json
import pathlib
import re
import statistics

TASK_METRICS = {
    # column name: (accumulator name, scale to apply)
    "executor_run_s": ("internal.metrics.executorRunTime", 1e-3),
    "executor_cpu_s": ("internal.metrics.executorCpuTime", 1e-9),
    "jvm_gc_s": ("internal.metrics.jvmGCTime", 1e-3),
    "input_records": ("internal.metrics.input.recordsRead", 1),
    "input_bytes": ("internal.metrics.input.bytesRead", 1),
    "shuffle_write_bytes": ("internal.metrics.shuffle.write.bytesWritten", 1),
    "shuffle_write_records": ("internal.metrics.shuffle.write.recordsWritten", 1),
    "shuffle_write_time_s": ("internal.metrics.shuffle.write.writeTime", 1e-9),
    "shuffle_fetch_wait_s": ("internal.metrics.shuffle.read.fetchWaitTime", 1e-3),
    "shuffle_read_records": ("internal.metrics.shuffle.read.recordsRead", 1),
    "spill_memory_bytes": ("internal.metrics.memoryBytesSpilled", 1),
    "spill_disk_bytes": ("internal.metrics.diskBytesSpilled", 1),
    "output_records": ("internal.metrics.output.recordsWritten", 1),
    "output_bytes": ("internal.metrics.output.bytesWritten", 1),
}
PEAK_METRICS = ["JVMHeapMemory", "JVMOffHeapMemory", "OnHeapExecutionMemory", "OffHeapExecutionMemory"]
SUMMARY_COLS = ["wall_s", "executor_cpu_s", "jvm_gc_s", "shuffle_write_bytes", "shuffle_write_time_s",
                "spill_disk_bytes", "map_stage_s", "reduce_stage_s", "peak_JVMHeapMemory",
                "peak_OffHeapExecutionMemory"]


def as_number(v):
    try:
        return int(v)
    except (TypeError, ValueError):
        try:
            return float(v)
        except (TypeError, ValueError):
            return None


def find_event_log(events: pathlib.Path, app_id: str) -> pathlib.Path:
    for name in (app_id, app_id + ".inprogress"):
        if (events / name).is_file():
            return events / name
    hits = sorted(events.glob(app_id + "*"))
    if hits and hits[0].is_file():
        return hits[0]
    raise FileNotFoundError(f"no plain event log for {app_id} in {events} "
                            f"(rolled or compressed logs are not supported)")


def parse(log: pathlib.Path):
    execs, plans, exec_parent, job_exec, job_stages, stages, peaks = {}, {}, {}, {}, {}, {}, {}
    with open(log) as f:
        for line in f:
            e = json.loads(line)
            kind = e.get("Event", "")
            if kind.endswith("SparkListenerSQLExecutionStart"):
                eid = e["executionId"]
                execs[eid] = {"description": e.get("description", ""), "start": e["time"], "end": None}
                exec_parent[eid] = e.get("rootExecutionId", eid)
                plans[eid] = e.get("physicalPlanDescription", "")
            elif kind.endswith("SparkListenerSQLAdaptiveExecutionUpdate"):
                plans[e["executionId"]] = e.get("physicalPlanDescription", plans.get(e["executionId"], ""))
            elif kind.endswith("SparkListenerSQLExecutionEnd"):
                if e["executionId"] in execs:
                    execs[e["executionId"]]["end"] = e["time"]
            elif kind == "SparkListenerJobStart":
                props = e.get("Properties") or {}
                if "spark.sql.execution.id" in props:
                    job_exec[e["Job ID"]] = int(props["spark.sql.execution.id"])
                    job_stages[e["Job ID"]] = e.get("Stage IDs", [])
            elif kind == "SparkListenerStageCompleted":
                info = e["Stage Info"]
                key = (info["Stage ID"], info.get("Stage Attempt ID", 0))
                accs = {}
                for acc in info.get("Accumulables", []):
                    if acc.get("Name") is not None:
                        accs[acc["Name"]] = acc.get("Value")
                stages[key] = {
                    "stage_id": info["Stage ID"], "attempt": info.get("Stage Attempt ID", 0),
                    "name": info.get("Stage Name", ""), "tasks": info.get("Number of Tasks"),
                    "submitted": info.get("Submission Time"), "completed": info.get("Completion Time"),
                    "skipped": info.get("Submission Time") is None, "accs": accs,
                }
            elif kind == "SparkListenerStageExecutorMetrics":
                key = (e["Stage ID"], e.get("Stage Attempt ID", 0))
                m = e.get("Executor Metrics", {})
                cur = peaks.setdefault(key, {})
                for name in PEAK_METRICS:
                    if name in m:
                        cur[name] = max(cur.get(name, 0), m[name])
    return execs, plans, exec_parent, job_exec, job_stages, stages, peaks


def root_of(eid, exec_parent):
    seen = set()
    while exec_parent.get(eid, eid) != eid and eid not in seen:
        seen.add(eid)
        eid = exec_parent[eid]
    return eid


def iteration_metrics(run, execs, plans, exec_parent, job_exec, job_stages, stages, peaks):
    pattern = re.compile(rf"^{re.escape(run)} (warmup|iter\d+)$")
    roots = {eid: pattern.match(x["description"].strip()).group(1)
             for eid, x in execs.items() if pattern.match(x["description"].strip())}
    out = {}
    for root, label in roots.items():
        stage_ids = set()
        for job, eid in job_exec.items():
            if root_of(eid, exec_parent) == root:
                stage_ids.update(job_stages.get(job, []))
        st = [s for (sid, _), s in stages.items() if sid in stage_ids and not s["skipped"]]
        row = {"label": label, "execution_id": root,
               "sql_wall_s": round((execs[root]["end"] - execs[root]["start"]) / 1000, 3)
               if execs[root]["end"] else None,
               "stages": len(st)}
        for col, (acc, scale) in TASK_METRICS.items():
            total = sum((as_number(s["accs"].get(acc)) or 0) for s in st)
            row[col] = round(total * scale, 3) if scale != 1 else total
        map_st = [s for s in st if (as_number(s["accs"].get(TASK_METRICS["shuffle_write_bytes"][0])) or 0) > 0]
        red_st = [s for s in st if s not in map_st]
        dur = lambda ss: round(sum((s["completed"] - s["submitted"]) for s in ss) / 1000, 3) if ss else 0
        row["map_stage_s"], row["reduce_stage_s"] = dur(map_st), dur(red_st)
        for name in PEAK_METRICS:
            vals = [peaks.get((s["stage_id"], s["attempt"]), {}).get(name) for s in st]
            vals = [v for v in vals if v is not None]
            row[f"peak_{name}"] = max(vals) if vals else None
        out[label] = (row, st, plans.get(root, ""))
    return out


def write_csv(path, rows):
    if not rows:
        return
    cols = []
    for r in rows:
        cols += [c for c in r if c not in cols]
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--events", required=True)
    p.add_argument("--results", required=True)
    a = p.parse_args()
    events, results = pathlib.Path(a.events), pathlib.Path(a.results)
    summary = []
    for run_dir in sorted(d for d in results.iterdir() if (d / "app_id.txt").is_file()):
        run = run_dir.name
        app_id = (run_dir / "app_id.txt").read_text().strip()
        parsed = parse(find_event_log(events, app_id))
        its = iteration_metrics(run, *parsed)
        if not its:
            print(f"{run}: no executions named '{run} <label>' in the event log of {app_id}")
            continue
        wall = {}
        if (run_dir / "wall.csv").is_file():
            with open(run_dir / "wall.csv") as f:
                wall = {r["label"]: r for r in csv.DictReader(f)}
        rows = []
        for label in sorted(its, key=lambda l: (l != "warmup", int(l[4:]) if l.startswith("iter") else 0)):
            row = {"run": run, **its[label][0]}
            if label in wall:
                row["wall_s"] = float(wall[label]["wall_s"])
                row["result"] = f'{wall[label]["out_rows"]}/{wall[label]["sum_revenue"]}/{wall[label]["sum_lines"]}'
            rows.append(row)
        write_csv(run_dir / "iterations.csv", rows)
        if "iter1" in its:
            _, st, plan = its["iter1"]
            write_csv(run_dir / "stages_iter1.csv", [
                {"stage_id": s["stage_id"], "name": s["name"][:80], "tasks": s["tasks"],
                 "duration_s": round((s["completed"] - s["submitted"]) / 1000, 3),
                 **{c: s["accs"].get(acc) for c, (acc, _) in TASK_METRICS.items()}} for s in st])
            write_csv(run_dir / "accumulables_iter1.csv", [
                {"stage_id": s["stage_id"], "name": k, "value": v}
                for s in st for k, v in sorted(s["accs"].items())])
            (run_dir / "final_plan_iter1.txt").write_text(plan)
        measured = [r for r in rows if r["label"].startswith("iter")]
        if measured:
            s = {"run": run, "iterations": len(measured),
                 "result": measured[0].get("result")}
            for col in SUMMARY_COLS:
                vals = [r[col] for r in measured if r.get(col) is not None]
                s[col] = round(statistics.median(vals), 3) if vals else None
            summary.append(s)
        print(f"{run}: {len(rows)} executions -> {run_dir}/iterations.csv")
    base = next((s for s in summary if s["run"] == "spark"), None)
    if base:
        for s in summary:
            for col in ("wall_s", "executor_cpu_s", "jvm_gc_s", "shuffle_write_bytes"):
                if base.get(col) and s.get(col) is not None:
                    s[f"{col}_vs_spark"] = round(s[col] / base[col], 3)
    write_csv(results / "summary.csv", summary)
    if summary:
        print(f"summary -> {results / 'summary.csv'}")
        results_set = {s["result"] for s in summary}
        print("results identical across runs" if len(results_set) == 1 else
              f"WARNING: runs produced different results: {results_set}")


if __name__ == "__main__":
    main()
