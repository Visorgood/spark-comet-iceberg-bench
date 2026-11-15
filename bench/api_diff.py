#!/usr/bin/env python3
"""Show that SQL and the PySpark DataFrame API produce the same physical plan.

Builds the SELECT part of the blog query twice (Spark SQL text and DataFrame
calls), prints both physical plans with expression ids normalised, and a diff.
An empty diff means the choice of API does not change what Spark (and Comet) execute.
"""
import argparse
import difflib
import pathlib
import re

from pyspark.sql import SparkSession
from pyspark.sql import functions as F

SQL = """
SELECT l_orderkey,
       sum(l_extendedprice * (1 - l_discount)) AS revenue,
       count(*)                                AS lines
FROM   {source}
WHERE  l_shipdate >= DATE '1995-01-01'
GROUP  BY l_orderkey
"""


def normalise(plan: str) -> str:
    plan = re.sub(r"#\d+L?", "#N", plan)              # attribute ids
    plan = re.sub(r"plan_id=\d+", "plan_id=N", plan)   # AQE / exchange ids
    plan = re.sub(r"\[id=#?\d+\]", "[id=N]", plan)
    return plan


def physical_plan(df) -> str:
    return df._jdf.queryExecution().executedPlan().toString()


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--source", default="lake.tpch.lineitem")
    p.add_argument("--out", required=True)
    a = p.parse_args()
    out = pathlib.Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    spark = SparkSession.builder.appName("comet-blog-api-diff").getOrCreate()

    sql_df = spark.sql(SQL.format(source=a.source))
    li = spark.table(a.source)
    api_df = (li.where(F.col("l_shipdate") >= F.lit("1995-01-01").cast("date"))
                .groupBy("l_orderkey")
                .agg(F.sum(F.col("l_extendedprice") * (1 - F.col("l_discount"))).alias("revenue"),
                     F.count(F.lit(1)).alias("lines")))

    sql_plan, api_plan = normalise(physical_plan(sql_df)), normalise(physical_plan(api_df))
    (out / "plan_sql.txt").write_text(sql_plan)
    (out / "plan_dataframe.txt").write_text(api_plan)
    diff = "".join(difflib.unified_diff(sql_plan.splitlines(True), api_plan.splitlines(True),
                                        "spark.sql(...)", "DataFrame API"))
    (out / "plan_diff.txt").write_text(diff or "IDENTICAL\n")
    print(sql_plan)
    print("=== diff ===")
    print(diff or "IDENTICAL: SQL and DataFrame API give the same physical plan")
    spark.stop()


if __name__ == "__main__":
    main()
