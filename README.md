# spark-comet-iceberg-bench

Reproduction scripts for the blog post *Where Spark loses time, and how Comet gets it back*
(link added on publication).

The post follows one ordinary ETL step — read an Iceberg table, filter, compute, group by
a key, write an Iceberg table — through Apache Spark alone and through Spark with
[Apache DataFusion Comet](https://github.com/apache/datafusion-comet). This repository
runs that step in eight configurations and collects everything the post relies on:
wall time, task metrics (CPU, GC, shuffle, spill), physical plans, Spark UI screenshots
and CPU flame graphs. Anyone with a laptop can rerun it and compare.

```sql
INSERT INTO lake.tpch.order_revenue
SELECT l_orderkey,
       sum(l_extendedprice * (1 - l_discount)) AS revenue,
       count(*)                                AS lines
FROM   lake.tpch.lineitem
WHERE  l_shipdate >= DATE '1995-01-01'
GROUP  BY l_orderkey
```

## Pinned versions

| Component | Version | Where it is set |
| --- | --- | --- |
| Apache Spark | 4.1.3 (`spark-4.1.3-bin-hadoop3`) | `env.sh` |
| Apache Iceberg | 1.11.0 (`iceberg-spark-runtime-4.1_2.13`) | `env.sh` |
| Apache DataFusion Comet | commit `460129c` of `main` (14 Nov 2026); will move to the 1.3.0 release | `env.sh`: `COMET_REF`, `COMET_RELEASE` |
| TPC-H generator | `tpchgen-cli` 4.0.0 | `env.sh` |
| Java | 17 or 21 | your machine |

Why Spark 4.1 and not 4.2: Iceberg 1.12.0 ships Spark runtimes up to 4.1 only.

## Requirements

- macOS or Linux, `bash`, `curl`, `git`, Python 3.9+ (standard library only), Java 17 or 21.
- `tpchgen-cli` 4.0.0: `cargo install tpchgen-cli --version 4.0.0 --locked`
  or `pipx install tpchgen-cli==4.0.0`.
- A Rust toolchain ([rustup](https://rustup.rs)) to build Comet. Published Comet jars are
  Linux-only, so macOS always builds from source; Linux can skip the build once
  `COMET_RELEASE` is set to a release.
- Memory: the defaults give the executor 16 GB of heap and 16 GB of off-heap memory, as
  Comet's own macOS benchmarking guide does. On a 32 GB machine set
  `EXEC_MEM=8g OFFHEAP=8g WORKER_MEM=20g` in `env.local.sh`.
- Disk: each copy of `lineitem` (Parquet, then Iceberg) takes about 2 GB at SF 10 and
  20 GB at SF 100, plus shuffle space.

## What each script does on your machine

Every script is meant to be run from the repository root with `bash scripts/<name>.sh`
after `source ./env.sh`. Nothing is installed system-wide: downloads and builds go to
`deps/`, data to `data/` and `warehouse/`, raw outputs to `out/` and `spark-events/`.
All of these are ignored by git.

| Script | What it does |
| --- | --- |
| `00_setup.sh` | Checks Java, Python, curl, git and `tpchgen-cli`. Downloads Spark into `deps/` and checks its SHA-512. Gets Comet: a jar you point to, the published jar (Linux, with `COMET_RELEASE`), or a release build from source in `deps/` (`COMET_REF` or the release source). Writes `out/<machine>/versions.txt`. |
| `05_machine_info.sh` | Read-only. Writes OS, CPU, cores, memory, power source and executor size to `out/<machine>/machine.txt`. |
| `01_cluster.sh start\|stop` | Starts or stops a one-worker Spark standalone cluster and the History Server, all on localhost (ports 7077, 8080, 8081, 18080). |
| `02_generate.sh` | Generates `lineitem` as Parquet in `data/sf<scale>/`. |
| `03_load_iceberg.sh` | Loads it into the Iceberg table `lake.tpch.lineitem` in `warehouse/` with plain Spark, prints the schema and checks the row count against the TPC-H reference. |
| `10_run.sh <run>` | One configuration: 1 warm-up + 5 measured iterations in one Spark application. Recreates the target table before every iteration and checks the result after it. |
| `11_run_all.sh` | All runs, then `20_metrics.sh`. `RUNS="A C"` limits it to a subset. |
| `20_metrics.sh` | Reads the event logs and writes per-iteration metrics, final plans and `summary.csv`. Spark is not needed. |
| `30_api_diff.sh` | Builds the query with SQL and with the PySpark DataFrame API and diffs the two physical plans. |
| `40_profile.sh <run>` | CPU flame graph of the executor with async-profiler (download it yourself into `deps/async-profiler`). |
| `50_publish.sh` | Copies the curated outputs into `results/<machine>/sf<scale>/` for committing, with your home path and host name masked. |

## Quick start: a smoke test at SF 0.1

```bash
git clone https://github.com/Visorgood/spark-comet-iceberg-bench.git
cd spark-comet-iceberg-bench
cp env.local.sh.example env.local.sh      # optional: MACHINE_ID, cores, memory, existing installs
source ./env.sh
bash scripts/00_setup.sh
bash scripts/05_machine_info.sh
bash scripts/01_cluster.sh start
export SCALE=0.1
bash scripts/02_generate.sh
bash scripts/03_load_iceberg.sh
RUNS="A C" bash scripts/11_run_all.sh
```

Every run must report the same result. At SF 0.1 it is 87,632 output rows, a revenue
sum of 11719954528.9403 and a lines sum of 342,791.

## Full reproduction

```bash
source ./env.sh
export SCALE=10                  # check everything here first; then repeat with SCALE=100
bash scripts/02_generate.sh
bash scripts/03_load_iceberg.sh
bash scripts/11_run_all.sh       # runs A A1 AF B C D E F, then the metrics
bash scripts/30_api_diff.sh
bash scripts/40_profile.sh A
bash scripts/40_profile.sh C
# take the Spark UI screenshots (below) into out/<machine>/sf<scale>/screenshots/
bash scripts/50_publish.sh
bash scripts/01_cluster.sh stop
```

On a laptop, close other heavy applications and stay on power: macOS cannot pin Spark
to performance cores, so background load is the main source of noise.

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
| `G` | A and C under async-profiler | where the CPU time goes |

All runs share the same cluster shape and memory, off-heap included: Comet needs an
off-heap pool, so the Spark-only runs get the same one. The breaker query adds a
data-quality guard, `assert_true(l_discount BETWEEN 0.00 AND 0.10)`; Comet lowers
`assert_true` to `RaiseError`, which it does not run natively.

## Check the plans before trusting a number

Look at `out/<machine>/sf<scale>/<run>/final_plan_iter1.txt`, the plan as it actually ran:

| Run | Expect |
| --- | --- |
| A | `BatchScan` → `ColumnarToRow` → `Filter`, `Project`, `HashAggregate` → `Exchange` → `HashAggregate` → `AppendData` |
| B | `CometIcebergNativeScan`, `CometFilter`, `CometProject`, `CometHashAggregate`, `CometExchange`, then `CometColumnarToRow` before `AppendData` |
| C | as B, but `CometIcebergWrite` under `IcebergCommit`, and no `CometColumnarToRow` |
| D | `CometColumnarExchange` instead of `CometExchange` |
| E | a plain `Exchange` between Comet stages |
| F | a `Filter` without the Comet prefix, with `CometColumnarToRow` before it and `CometSparkRowToColumnar` after it |

If C shows `IcebergWrite` rather than `CometIcebergWrite`, the native write was not
eligible; the reason is in `explain_extended.txt` and in `driver.log`.

## Outputs

`out/<machine>/sf<scale>/` (not committed) holds, per run: `wall.csv`,
`iterations.csv`, `stages_iter1.csv`, `accumulables_iter1.csv` (every named metric
per stage, Comet's native metrics included), `explain_formatted.txt`,
`explain_extended.txt`, `final_plan_iter1.txt`, `spark_conf.txt` and `driver.log`;
plus `summary.csv` with medians over the measured iterations and ratios to run A.
`results/` holds the published subset; see `results/README.md`.

## Spark UI screenshots

Open the History Server at http://localhost:18080, choose the application
`comet-blog-<run>`, open the **SQL / DataFrame** tab and the query named `<run> iter1`,
and expand **Details** under the graph. In Chrome, DevTools → Cmd/Ctrl+Shift+P →
"Capture full size screenshot" saves the whole page. Save into
`out/<machine>/sf<scale>/screenshots/`:

| File | What |
| --- | --- |
| `A_sql_plan.png`, `C_sql_plan.png`, `F_sql_plan.png` | SQL tab of `iter1`, with metrics |
| `A_stage_map.png`, `C_stage_map.png` | Stages tab, the map stage of `iter1` |
| `A_executors.png`, `C_executors.png` | Executors tab: GC time, peak memory |

## Flame graphs

Unpack the async-profiler release for your OS from
https://github.com/async-profiler/async-profiler/releases into `deps/async-profiler`
(or set `ASPROF_HOME`). `bash scripts/40_profile.sh A` and `... C` write
`out/<machine>/sf<scale>/profiles/<run>/flame-cpu-<pid>.html`, covering the executor's
whole life: one warm-up and two iterations.

## Sharing your results

Run the full sequence with a descriptive `MACHINE_ID` in `env.local.sh`, then
`bash scripts/50_publish.sh` and open a pull request with `results/<machine-id>/`.

## Status

The Python harness (`bench/bench.py`, `bench/metrics.py`, `bench/api_diff.py`) was run
end to end on PySpark 4.1.3 at SF 0.1 with a Parquet source (plain Spark, no Iceberg,
no Comet). The full Iceberg and Comet path will be confirmed by the author's first runs,
published under `results/`.

## License

Apache License 2.0, see `LICENSE`.
