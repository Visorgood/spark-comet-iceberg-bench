#!/usr/bin/env python3
"""Run the blog query several times in one Spark application.

For each iteration: recreate the empty target table, run the INSERT under a job
description "<run> <label>" (metrics.py finds it in the event log by that name),
time it on the driver, measure the CPU time the whole container used meanwhile
(Comet runs native plans on its own threads, which Spark's task CPU metric misses),
then check the result so every run can be compared.
Before the loop it saves EXPLAIN FORMATTED and EXPLAIN EXTENDED of the INSERT.
"""
import argparse
import csv
import pathlib
import time

from pyspark.sql import SparkSession


def statements(path, **subst):
    """Read a SQL file, substitute {placeholders}, drop '--' comment lines, split on ';'."""
    text = pathlib.Path(path).read_text().format(**subst)
    lines = [line for line in text.splitlines() if not line.strip().startswith("--")]
    return [s.strip() for s in "\n".join(lines).split(";") if s.strip()]


def container_cpu_s():
    """CPU seconds used so far by every process in this container (cgroup v2), or None."""
    try:
        with open("/sys/fs/cgroup/cpu.stat") as f:
            for line in f:
                key, value = line.split()
                if key == "usage_usec":
                    return int(value) / 1e6
    except OSError:
        pass
    return None


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--run", required=True)
    p.add_argument("--query", required=True, help="SQL file with the INSERT; {source} and {target} are substituted")
    p.add_argument("--create", required=True, help="SQL file that (re)creates the empty target table")
    p.add_argument("--source", default="lake.tpch.lineitem")
    p.add_argument("--target", default="lake.tpch.order_revenue")
    p.add_argument("--warmup", type=int, default=1)
    p.add_argument("--iterations", type=int, default=5)
    p.add_argument("--out", required=True)
    a = p.parse_args()

    out = pathlib.Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    spark = SparkSession.builder.appName(f"comet-blog-{a.run}").getOrCreate()
    sc = spark.sparkContext

    (insert,) = statements(a.query, source=a.source, target=a.target)
    create = statements(a.create, target=a.target)

    (out / "app_id.txt").write_text(sc.applicationId + "\n")
    conf = sorted(sc.getConf().getAll())
    (out / "spark_conf.txt").write_text(f"spark.version={spark.version}\n" + "".join(f"{k}={v}\n" for k, v in conf))

    for stmt in create:
        spark.sql(stmt)
    for mode in ("FORMATTED", "EXTENDED"):
        plan = spark.sql(f"EXPLAIN {mode} {insert}").collect()[0][0]
        (out / f"explain_{mode.lower()}.txt").write_text(plan)

    rows = []
    for i in range(a.warmup + a.iterations):
        label = "warmup" if i < a.warmup else f"iter{i - a.warmup + 1}"
        for stmt in create:
            spark.sql(stmt)
        sc.setLocalProperty("spark.job.description", f"{a.run} {label}")
        cpu0, t0 = container_cpu_s(), time.perf_counter()
        spark.sql(insert)
        wall = time.perf_counter() - t0
        cpu1 = container_cpu_s()
        sc.setLocalProperty("spark.job.description", None)
        chk = spark.sql(
            f"SELECT count(*) AS n, sum(revenue) AS revenue, sum(lines) AS lines FROM {a.target}").first()
        row = {"run": a.run, "label": label, "wall_s": round(wall, 3),
               "cpu_s": round(cpu1 - cpu0, 3) if cpu0 is not None and cpu1 is not None else "",
               "out_rows": chk["n"], "sum_revenue": str(chk["revenue"]), "sum_lines": chk["lines"]}
        rows.append(row)
        print(f"[bench] {row}", flush=True)

    with open(out / "wall.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    spark.stop()


if __name__ == "__main__":
    main()
