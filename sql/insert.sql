INSERT INTO {target}
SELECT l_orderkey,
       sum(l_extendedprice * (1 - l_discount)) AS revenue,
       count(*)                                AS lines
FROM   {source}
WHERE  l_shipdate >= DATE '1995-01-01'
GROUP  BY l_orderkey
