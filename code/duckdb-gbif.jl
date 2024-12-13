#import Pkg
#Pkg.add("DuckDB")

using DuckDB
# create a new in-memory database
con = DBInterface.connect(DuckDB.DB, ":memory:")

# create a table
DBInterface.execute(con, "INSTALL httpfs;")
DBInterface.execute(con, "LOAD httpfs;")
DBInterface.execute(con, "CREATE OR REPLACE TEMPORARY VIEW gbif AS SELECT * FROM read_parquet('s3://gbif-open-data-us-east-1/occurrence/2023-10-01/occurrence.parquet/**');")
boundingbox = (bottom=41.0, right=-58.501, left=-80.00, top=51.999)

# Note that we can do aribtrary SQL operations, including
# geoparquet spatial queries, with minimal RAM footprint,
# over the full gbif
results = DBInterface.execute(con, 
"SELECT *
FROM gbif
WHERE
  (scientificname = 'Procyon lotor') AND
  (decimallatitude BETWEEN -80.0 AND -58.501) AND
  (decimallongitude BETWEEN 41.0 AND 51.999)")
