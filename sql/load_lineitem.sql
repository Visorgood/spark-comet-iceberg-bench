CREATE NAMESPACE IF NOT EXISTS lake.tpch;
DROP TABLE IF EXISTS lake.tpch.lineitem PURGE;
CREATE TABLE lake.tpch.lineitem
USING iceberg
TBLPROPERTIES ('tpch.scale-factor' = '{scale}')
AS SELECT * FROM parquet.`{parquet_dir}`;
DESCRIBE TABLE lake.tpch.lineitem;
SHOW TBLPROPERTIES lake.tpch.lineitem;
SELECT count(*) AS lineitem_rows FROM lake.tpch.lineitem;
