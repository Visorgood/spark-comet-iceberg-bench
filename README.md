# spark-comet-iceberg-bench

Reproduction for the blog post *Where Spark loses time, and how Comet gets it back*
(link added on publication).

The post follows one ordinary ETL step — read an Iceberg table, filter, compute, group by
a key, write an Iceberg table — through Apache Spark alone and through Spark with
[Apache DataFusion Comet](https://github.com/apache/datafusion-comet). This repository
runs that step in eight configurations inside one Docker container and shows wall time,
task metrics (CPU, GC, shuffle, spill), the physical plans and the Spark UI of every run.

```sql
INSERT INTO lake.tpch.order_revenue
SELECT l_orderkey,
       sum(l_extendedprice * (1 - l_discount)) AS revenue,
       count(*)                                AS lines
FROM   lake.tpch.lineitem
WHERE  l_shipdate >= DATE '1995-01-01'
GROUP  BY l_orderkey
```

## Run it

You need Docker and a checkout of this repository. Build the image once, then one
command generates the data, runs every configuration, extracts the metrics and serves
the results:

```bash
git clone https://github.com/Visorgood/spark-comet-iceberg-bench.git
cd spark-comet-iceberg-bench
docker build -t spark-comet-iceberg-bench .
docker run --rm -it -p 8000:8000 -p 18080:18080 -v spark-comet-bench:/work spark-comet-iceberg-bench
```

The build downloads Spark, Iceberg, Comet, the TPC-H generator and async-profiler and
checks their checksums (see "What is inside the image"). After a `git pull`, run
`docker build` again; unchanged steps come from Docker's cache.

When the run finishes it prints two addresses and keeps running until you press Ctrl+C:

- **http://localhost:8000**, the report: median wall time per run, ratio to Spark, CPU,
  GC and shuffle bytes, a check that every run produced the same result, plans side by
  side, Comet's fallback notes, and links to the Spark UI of each run.
- **http://localhost:18080**, the Spark History Server: the full Spark UI of every run
  (SQL / DataFrame tab with the plan graph and metrics, stages, executors).

To see the UI again later without rerunning anything, add the `ui` command:

```bash
docker run --rm -it -p 8000:8000 -p 18080:18080 -v spark-comet-bench:/work spark-comet-iceberg-bench ui
```

**Smoke test first.** A small scale factor and two runs, Spark only and Spark + Comet:

```bash
docker run --rm -it -p 8000:8000 -p 18080:18080 -v spark-comet-bench:/work \
  -e SCALE=0.1 -e RUNS="A C" spark-comet-iceberg-bench
```

Every run must report the same result; at SF 0.1 it is 87,632 output rows, a revenue
sum of 11719954528.9403 and a lines sum of 342,791.

## What is inside the image

| Component | Version | Source, checked |
| --- | --- | --- |
| Java | 17 (Eclipse Temurin, Ubuntu 22.04) | base image `eclipse-temurin:17-jdk-jammy` |
| Apache Spark | 4.1.3 (`spark-4.1.3-bin-hadoop3`) | archive.apache.org, SHA-512 |
| Apache Iceberg | 1.11.0 (`iceberg-spark-runtime-4.1_2.13`) | Maven Central, SHA-1 |
| Apache DataFusion Comet | 1.2.0 (`comet-spark-spark4.1_2.13`), will move to 1.3.0 | Maven Central, SHA-1 |
| TPC-H generator | `tpchgen-cli` 4.0.0 | PyPI |
| async-profiler | 4.5 | GitHub release |

Versions are `ARG`s at the top of the `Dockerfile`. Why Spark 4.1 and not 4.2: Iceberg
1.12.0 ships Spark runtimes up to 4.1 only. Comet's published jars carry native code for
Linux amd64 and arm64, which is what the image runs on, including Apple silicon.

Inside the container a one-worker Spark standalone cluster runs on localhost. The data,
the Iceberg tables, the event logs and all outputs live in the Docker volume
`spark-comet-bench`, mounted at `/work`, so a second run skips data generation:

```
/work/data/sf<scale>/lineitem/    generated TPC-H Parquet
/work/warehouse/                  Iceberg tables (Hadoop catalog "lake")
/work/spark-events/               Spark event logs, read by the History Server
/work/out/<machine>/sf<scale>/    per-run outputs (see "Outputs")
/work/report/index.html           the report
```

## Make the numbers meaningful

Docker on macOS and Windows runs in a virtual machine, so the container gets only what
Docker Desktop gives that VM (Settings → Resources). Absolute times differ from bare
metal; the comparison between runs stays fair because every run shares the same
container, data and settings.

- **Memory and CPUs.** The executor is sized from what the container sees: all CPUs,
  30% of memory as heap and 30% as off-heap (Comet's memory; the Spark-only runs get the
  same pool). Give Docker at least 16 GB for SF 10, and much more for SF 100. Override with
  `-e CORES=8 -e EXEC_MEM=8g -e OFFHEAP=8g`.
- **Disk.** Parquet plus the Iceberg copy take about 4 GB at SF 10 and 40 GB at SF 100,
  plus shuffle space while a run is going; Docker Desktop's disk limit applies.
- **Noise.** Close other heavy applications and stay on power while it runs.
- **Volumes, not bind mounts.** Data stays in a named volume on purpose: bind-mounted
  host folders are much slower under Docker Desktop.

## Settings

Pass with `-e NAME=value`:

| Setting | Default | Meaning |
| --- | --- | --- |
| `SCALE` | `10` | TPC-H scale factor: 0.1, 1, 10, 100 are checked against reference row counts |
| `RUNS` | `A A1 AF B C D E F` | configurations to run, see "Run matrix" |
| `WARMUP`, `ITERATIONS` | `1`, `5` | iterations per run, all in one Spark application |
| `CORES`, `EXEC_MEM`, `OFFHEAP`, `DRIVER_MEM` | from the container | executor and driver size |
| `MACHINE_ID` | `docker-<arch>` | name of the results folder |
| `HOST_INFO` | empty | free text saved with the results, e.g. `"MacBook Pro M3 Max 64 GB, Docker 12 CPUs 48 GB"` |
| `PROFILE` | `0` | `1` adds CPU flame graphs of runs A and C |
| `API_DIFF` | `1` | `0` skips the SQL vs DataFrame plan comparison |

## Run matrix

| Run | Configuration | What it isolates |
| --- | --- | --- |
| `A` | Spark only | the baseline |
| `A1` | A + `spark.sql.shuffle.orderIndependentChecksum.enabled=false` | the price of the per-row shuffle checksum Spark computes since 4.1 |
| `AF` | A with `sql/insert_breaker.sql` | the baseline for F |
| `B` | Spark + Comet, Comet defaults | the gain while iceberg-java still writes the files |
| `C` | B + `spark.comet.write.iceberg.enabled=true` | the gain with Arrow batches from file to file |
| `D` | C + `spark.comet.shuffle.mode=jvm` | native shuffle vs JVM columnar shuffle |
| `E` | C + `spark.comet.shuffle.enabled=false` | a Spark shuffle between Comet stages |
| `F` | C with `sql/insert_breaker.sql` | one operator that falls back to Spark, mid-stage |

All runs share the same cluster shape and memory, off-heap included. The breaker query
adds a data-quality guard, `assert_true(l_discount BETWEEN 0.00 AND 0.10)`; Comet lowers
`assert_true` to `RaiseError`, which it does not run natively. The exact Spark arguments
of every run are in `scripts/lib.sh`.

## Check the plans before trusting a number

The report shows each run's plan as it actually ran (after AQE). Expect:

| Run | Expect |
| --- | --- |
| A | `BatchScan` → `ColumnarToRow` → `Filter`, `Project`, `HashAggregate` → `Exchange` → `HashAggregate` → `AppendData` |
| B | `CometIcebergNativeScan`, `CometFilter`, `CometProject`, `CometHashAggregate`, `CometExchange`, then `CometColumnarToRow` before `AppendData` |
| C | as B, but `CometIcebergWrite` under `IcebergCommit`, and no `CometColumnarToRow` |
| D | `CometColumnarExchange` instead of `CometExchange` |
| E | a plain `Exchange` between Comet stages |
| F | a `Filter` without the Comet prefix, with `CometColumnarToRow` before it and `CometSparkRowToColumnar` after it |

If C shows `IcebergWrite` rather than `CometIcebergWrite`, the native write was not
eligible; the reason is in the run's EXPLAIN EXTENDED (in the report) and its `driver.log`.

## Step by step, for debugging

The image's commands run one step at a time against the same volume. Put the command
at the end of the usual line, for example:

```bash
docker run --rm -it -p 8000:8000 -p 18080:18080 -v spark-comet-bench:/work spark-comet-iceberg-bench run A C
```

| Command | What it does |
| --- | --- |
| `all` | everything below in order, then `ui` (the default) |
| `data` | generates `lineitem` and loads it into Iceberg with plain Spark; skipped if already there (`-e FORCE_DATA=1` redoes it) |
| `run A C` | runs the given configurations, then extracts their metrics |
| `metrics` | rereads the event logs: per-iteration metrics, final plans, `summary.csv` |
| `api-diff` | builds the query with SQL and with the PySpark DataFrame API and diffs the plans |
| `profile A C` | CPU flame graphs of the executor (async-profiler, `itimer` mode, no extra privileges) |
| `report` | rebuilds the HTML report |
| `ui` | serves the report and the History Server for earlier runs |
| `export` | copies the curated results to a mounted folder, see "Sharing your results" |
| `shell` | a bash shell in the container with the Spark cluster running |
| `help` | lists the commands |

To watch a run live, add `-p 4040:4040` and open http://localhost:4040 while it runs.

To look at the files in the volume without starting Spark:

```bash
docker run --rm -it -v spark-comet-bench:/work --entrypoint bash spark-comet-iceberg-bench
ls /work
```

To free the disk space when you are done: `docker volume rm spark-comet-bench`, and
`docker image rm spark-comet-iceberg-bench` for the image.

## Outputs

`/work/out/<machine>/sf<scale>/` holds, per run: `wall.csv` (driver-side time and
result check per iteration), `iterations.csv` (task metrics per iteration),
`stages_iter1.csv`, `accumulables_iter1.csv` (every named metric per stage, Comet's
native metrics included), `explain_formatted.txt`, `explain_extended.txt`,
`final_plan_iter1.txt`, `spark_conf.txt` and `driver.log`; plus `summary.csv` with
medians over the measured iterations and ratios to run A, and `api_diff/` and
`profiles/` when those steps ran.

## Spark UI screenshots

In the History Server (http://localhost:18080) choose the application
`comet-blog-<run>`, open the **SQL / DataFrame** tab and the query named `<run> iter1`,
and expand **Details** under the graph. In Chrome, DevTools → Cmd/Ctrl+Shift+P →
"Capture full size screenshot" saves the whole page. The post uses:

| File | What |
| --- | --- |
| `A_sql_plan.png`, `C_sql_plan.png`, `F_sql_plan.png` | SQL tab of `iter1`, with metrics |
| `A_stage_map.png`, `C_stage_map.png` | Stages tab, the map stage of `iter1` |
| `A_executors.png`, `C_executors.png` | Executors tab: GC time, peak memory |

## Sharing your results

Run with a descriptive `MACHINE_ID` and `HOST_INFO`, then from the root of your
checkout:

```bash
docker run --rm -v spark-comet-bench:/work -v "$PWD":/export \
  -e MACHINE_ID=<the same id> -e SCALE=<the same scale> spark-comet-iceberg-bench export
```

This writes `results/<machine-id>/` (summary, per-run metrics and plans, API diff, flame
graphs, machine and version info; the container's host name masked). Add screenshots
to `results/<machine-id>/sf<scale>/screenshots/` and open a pull request. See
`results/README.md`.

## Status

The Python harness (`bench/bench.py`, `bench/metrics.py`, `bench/api_diff.py`) was run
end to end on PySpark 4.1.3 at SF 0.1 with a Parquet source (plain Spark, no Iceberg,
no Comet). The Docker image and the full Iceberg and Comet path will be confirmed by the
author's first runs, published under `results/`.

## License

Apache License 2.0, see `LICENSE`.
