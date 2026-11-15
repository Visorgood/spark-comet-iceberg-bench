DROP TABLE IF EXISTS {target} PURGE;
CREATE TABLE {target} (
  l_orderkey BIGINT,
  revenue    DECIMAL(38,4),
  lines      BIGINT
) USING iceberg
