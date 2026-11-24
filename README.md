# spark-comet-iceberg-bench

Reproduction for the blog post
[Where Spark loses time, and how Comet gets it back](https://viacheslavinozemtsev.io/blog-posts/where-spark-loses-time-and-how-comet-gets-it-back).

The post follows one ordinary ETL step – read an Iceberg table, filter, compute, group by
a key, write an Iceberg table – through Apache Spark alone and through Spark with
[Apache DataFusion Comet](https://github.com/apache/datafusion-comet). This repository
runs that step with Spark alone and with Comet in three configurations, inside one
Docker container, and shows the wall time, task metrics, physical plans and the Spark UI
of each run.

```sql
INSERT INTO lake.tpch.order_revenue
SELECT l_orderkey,
       sum(l_extendedprice * (1 - l_discount)) AS revenue,
       count(*)                                AS lines
FROM   lake.tpch.lineitem
WHERE  l_shipdate >= DATE '1995-01-01'
GROUP  BY l_orderkey
```

This is `sql/insert.sql`. Each run executes it six times in one Spark application, one
warm-up and five measured iterations, each into a freshly emptied target table; the
`comet-fallback` run uses `sql/insert_breaker.sql`, the same statement with one more
condition in the `WHERE`.

## Run it

You need Docker and a checkout of this repository. Build the image once, then one
command generates the data, runs the query, collects the metrics and serves the results:

```bash
git clone https://github.com/Visorgood/spark-comet-iceberg-bench.git
cd spark-comet-iceberg-bench
docker build -t spark-comet-iceberg-bench .
docker run --rm -it --cpus=8 --memory=24g -p 8000:8000 -p 18080:18080 \
  -v spark-comet-bench:/work spark-comet-iceberg-bench
```

This is exactly the run behind the numbers in the blog post: TPC-H scale factor 100,
600 million rows. `--cpus=8 --memory=24g` fixes the size of the container, so the setup
does not depend on how many cores and how much memory your machine has: Spark gets one
executor with 8 cores, 7 GiB of heap and 7 GiB of off-heap memory. On Docker Desktop, first
give Docker at least 10 CPUs and 26 GiB in Settings → Resources, because Docker's virtual
machine needs some for itself, and check the disk limit there: the volume holds two
copies of the 600 million rows (Parquet and Iceberg) plus shuffle files while it runs.

When the run finishes it prints two addresses and keeps running until you press Ctrl+C:

- **http://localhost:8000**, the report: median wall time of each run and its ratio to
  Spark, CPU time of the container, GC and shuffle bytes, a check that all runs produced
  the same result, the plans side by side, CPU flame graphs, and every raw output file.
- **http://localhost:18080**, the Spark History Server: the full Spark UI of every run.

To open them again later without rerunning anything, add `ui` at the end:

```bash
docker run --rm -it -p 8000:8000 -p 18080:18080 -v spark-comet-bench:/work spark-comet-iceberg-bench ui
```

After a `git pull`, run `docker build` again; unchanged steps come from Docker's cache.

### Data size

Pass `SCALE` into the container with `-e` to change the scale factor. A quick check that
everything works takes a few minutes at scale factor 0.1:

```bash
docker run --rm -it --cpus=8 --memory=24g -p 8000:8000 -p 18080:18080 \
  -v spark-comet-bench:/work -e SCALE=0.1 spark-comet-iceberg-bench
```

At SF 0.1 every run must produce 87,632 rows with a revenue sum of 11719954528.9403 and
a lines sum of 342,791. The report shows one scale factor at a time, so pass the same
`-e SCALE=...` to `ui`. On a smaller machine, `--cpus=4 --memory=16g -e SCALE=10` runs the
same comparison at a tenth of the size; its numbers differ from the post's.

## What runs

| Run | Configuration | What to look for in the plan |
| --- | --- | --- |
| `spark` | Spark only | `BatchScan` → `ColumnarToRow`, then `Filter`, `Project`, `HashAggregate`, `Exchange`, `HashAggregate`, `AppendData` |
| `comet-default` | Spark + Comet with Comet's default settings | Comet operators from the scan to the final aggregate, then `CometColumnarToRow` → `AppendData`: iceberg-java writes the files |
| `comet` | Spark + Comet with its native Iceberg write (`spark.comet.write.iceberg.enabled=true`) | Comet operators from scan to write: `CometIcebergNativeScan` … `CometExchange` … `CometIcebergWrite` under `IcebergCommit` |
| `comet-fallback` | `comet` + a data-quality guard in the `WHERE`, `assert_true(l_discount BETWEEN 0.00 AND 0.10) IS NULL`, which Comet does not support | only the scan stays in Comet: `CometIcebergNativeScan` → `CometColumnarToRow`, then Spark's `Filter`, `HashAggregate`, `Exchange`, `HashAggregate` and `IcebergWrite` |

`comet-fallback` shows how far one unsupported expression reaches. Comet runs an
operator natively only when its input is already native, and turns rows back into Arrow
only right above a scan, so everything after the guard runs in Spark, including the
shuffle and the Iceberg write.

`comet-default` is Comet as it comes out of the box. The `comet` and `comet-fallback`
runs also enable Comet's native Iceberg write
(`spark.comet.write.iceberg.enabled=true`, off by default in Comet 1.2); if the `comet`
plan shows `IcebergWrite` instead of `CometIcebergWrite`, the native write was not used
and the EXPLAIN output in the report says why.

Each run is one Spark application with one warm-up and five measured iterations; the
report shows the median wall time and the fastest and slowest iteration. All runs share
the same cluster shape and memory, off-heap included. The exact Spark settings are in
`scripts/lib.sh`.

After the timed runs, `spark` and `comet` run once more under
[async-profiler](https://github.com/async-profiler/async-profiler), each in its own Spark
application, for the CPU flame graphs in the report. Profiling never touches the timed runs.

## What is inside the image

| Component | Version |
| --- | --- |
| Java | 17, Eclipse Temurin on Ubuntu 22.04 |
| Apache Spark | 4.1.3 |
| Apache Iceberg | 1.11.0 |
| Apache DataFusion Comet | 1.2.0 |
| TPC-H generator | `tpchgen-cli` 4.0.0 |
| async-profiler | 4.5 |

Versions are set at the top of the `Dockerfile`; the Spark, Iceberg and Comet downloads
are checked against their published checksums. Eclipse Temurin is the Eclipse Adoptium build of OpenJDK; Docker's
own `openjdk` image is deprecated. Spark is 4.1 rather than 4.2 because Iceberg has no
Spark 4.2 runtime yet. Comet's published jars carry native code for Linux on amd64 and
arm64, so the image runs natively on Apple silicon too.

## Make the numbers meaningful

Docker on macOS and Windows runs in a virtual machine, so absolute times differ from
bare metal. The comparison between runs stays fair because they share the same
container limits, data and settings.

- Keep `--cpus=8 --memory=24g`. With other limits the executor is sized from what the
  container gets (all its CPUs, 30% of its memory as heap and 30% as off-heap), and the
  run prints a note that its numbers are not directly comparable.
- Data stays in the Docker volume `spark-comet-bench`, not in a folder of your machine:
  folders shared from the host are much slower under Docker Desktop.
- Close other heavy applications and stay on power while it runs.

## Spark UI

In the History Server (http://localhost:18080) each run is an application named
`comet-blog-<run>`. Its **SQL / DataFrame** tab lists more queries than the one being
measured: emptying the target table, the plans, and a result check after every iteration.
The INSERTs are the queries named `<run> warmup` and `<run> iter1` to `<run> iter5`; the
warm-up is not counted. Open `<run> iter1`: the graph shows every operator with its metrics, and
**Details** under it shows the plan as text. The report links to the SQL / DataFrame tab of each application.
The applications named `comet-blog-profile-<run>` are the profiled runs.

## Files and debugging

Everything stays in the Docker volume, mounted at `/work` in the container: the
generated Parquet in `data/`, the Iceberg tables in `warehouse/`, Spark event logs in
`spark-events/`, and per-run outputs in `out/sf<scale>/` (also under "Raw files" in the
report). A second run reuses the data.

To look around or rerun a single step, start a shell in the container with the Spark
cluster running; the scripts are in `/bench/scripts`:

```bash
docker run --rm -it --cpus=8 --memory=24g -p 8000:8000 -p 18080:18080 \
  -v spark-comet-bench:/work spark-comet-iceberg-bench shell
```

To free the disk space: `docker volume rm spark-comet-bench` and
`docker image rm spark-comet-iceberg-bench`.

## License

Apache License 2.0, see `LICENSE`.
