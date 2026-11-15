-- Same job plus a data-quality guard. Comet does not run assert_true natively
-- (it lowers to RaiseError, which falls back), so the Filter returns to Spark.
INSERT INTO {target}
SELECT l_orderkey,
       sum(l_extendedprice * (1 - l_discount)) AS revenue,
       count(*)                                AS lines
FROM   {source}
WHERE  l_shipdate >= DATE '1995-01-01'
  AND  assert_true(l_discount BETWEEN 0.00 AND 0.10) IS NULL
GROUP  BY l_orderkey
