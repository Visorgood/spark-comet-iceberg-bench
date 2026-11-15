# Figures

The images in the blog post *Where Spark loses time, and how Comet gets it back*, with their sources.

Measured with Spark 4.1.3, Iceberg 1.11.0 and Comet 1.2.0, at TPC-H scale factor 100, in a container with
8 CPUs and 24 GB (the main command in the top-level README).

| # | File | What it shows | Source |
| --- | --- | --- | --- |
| 1 | `01-spark-plan.png` | Plain Spark plan, per-row steps highlighted | `01-spark-plan.svg` |
| 2 | `02-spark-ui-spark.png` | Spark UI, SQL tab: the `spark` run | Screenshots of the History Server, stitched |
| 3 | `03-spark-data-journey.png` | Four rows from source file to target file, without Comet | `03-spark-data-journey.svg` |
| 4 | `04-comet-plan.png` | Spark + Comet plan, Arrow batches end to end | `04-comet-plan.svg` |
| 5 | `05-spark-ui-comet.png` | Spark UI, SQL tab: the `comet` run | Screenshots of the History Server, stitched |
| 6 | `06-comet-data-journey.png` | The same four rows, with Comet | `06-comet-data-journey.svg` |
| 7 | `07-flamegraph-spark.png` | CPU flame graph of the executor, `spark` run | `07-flamegraph-spark.html` |
| 8 | `08-flamegraph-comet.png` | CPU flame graph of the executor, `comet` run | `08-flamegraph-comet.html` |
| 9 | `09-fallback-plan.png` | One unsupported expression sends the rest of the job to Spark | `09-fallback-plan.svg` |
| 10 | `10-spark-ui-comet-fallback.png` | Spark UI, SQL tab: the `comet-fallback` run | Screenshots of the History Server, stitched |

## Diagrams (1, 3, 4, 6, 9)

The SVG is the source. Edit it, then render the PNG at 2x:

```bash
brew install librsvg
brew install --cask font-inter font-ibm-plex-mono
rsvg-convert -z 2 01-spark-plan.svg -o 01-spark-plan.png
```

Without the two fonts installed, the PNG falls back to another font and some lines may run longer.

Palette:

| Role | Colour |
| --- | --- |
| Background | `#FBF8F2` |
| Spark, rows, work per row | `#C27A0E` |
| Comet, Arrow, work per batch in Rust | `#0F7F72` |
| Files and tables | `#EFE8DA` |
| Lines and arrows | `#7A7368` |
| Stage frames, dashed lines | `#CFC7B8` |
| Text | `#1E1C19` |
| Secondary text | `#6B6459` |

Text is Inter; data values in the data-journey diagrams are IBM Plex Mono.

## Screenshots (2, 5, 10)

History Server at http://localhost:18080 (the `ui` command in the top-level README), application of each run,
SQL / DataFrame tab, the query with the description `<run> iter1` (the first timed iteration).

## Flame graphs (7, 8)

`40_profile.sh` writes them to `out/sf100/profiles/<run>/flame-<pid>.html` in the `spark-comet-iceberg-bench`
volume. The HTML here is that file; the PNG is a screenshot of its full view in a browser.

## After a new Comet release

Re-run, then check:

- 4 and 6: operator names, batch size, and the default of `spark.comet.write.iceberg.enabled` (false in 1.2.0).
- 9: whether the job still leaves Comet at `CometColumnarToRow` above the scan. If Comet runs `assert_true`
  natively, the example needs another unsupported expression. Update the times in the note.
- 2, 5, 7, 8, 10: new screenshots and flame graphs.
