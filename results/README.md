# Results

One folder per machine, one subfolder per TPC-H scale factor, written by the image's
`export` command:

```bash
docker run --rm -v spark-comet-bench:/work -v "$PWD":/export \
  -e MACHINE_ID=<the id used for the run> -e SCALE=<scale> \
  ghcr.io/visorgood/spark-comet-iceberg-bench export
```

```
results/<machine-id>/
  machine.txt            CPU and memory visible to the container, HOST_INFO, executor size
  versions.txt           Spark, Iceberg, Comet, tpchgen-cli, Java, async-profiler
  sf<scale>/
    summary.csv          medians over the measured iterations, per run, and ratios to run A
    <run>/               A, A1, AF, B, C, D, E, F
      wall.csv           driver-side time and result check per iteration
      iterations.csv     task metrics per iteration (CPU, GC, shuffle, spill, stage times, peak memory)
      stages_iter1.csv   per-stage metrics of the first measured iteration
      accumulables_iter1.csv  every named metric per stage, Comet's native metrics included
      explain_formatted.txt, explain_extended.txt   plans before the run (Comet fallback reasons)
      final_plan_iter1.txt    the plan as it actually ran (after AQE)
      spark_conf.txt     the full Spark configuration of the run
    api_diff/            SQL vs DataFrame API plans and their diff
    profiles/            CPU flame graphs (runs A and C, when run with PROFILE=1)
    screenshots/         Spark UI screenshots
```

Every run of the same scale factor must report the same result in `summary.csv`
(row count / sum of revenue / sum of lines); a mismatch means something is wrong.

To add your machine, run the benchmark with a descriptive `MACHINE_ID` and `HOST_INFO`,
export, and open a pull request with your `results/<machine-id>/` folder.
