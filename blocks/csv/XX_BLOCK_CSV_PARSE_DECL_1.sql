-- DECL: XX_BLOCK_CSV_PARSE_DECL_1.sql
-- PURPOSE:
--   Declare shared CSV parsing/printing types and globals used by the CSV blocks.
--   This DECL provides the in-memory “CSV buffer” (rows + count) that is populated
--   by CSV read/load blocks and consumed by CSV parse/print/debug blocks.
--
-- NOTES:
--   - This file must be included in the assembled worker via a DECL= entry and
--     must appear before any BLOCK/MAIN that references these globals.
--   - This DECL intentionally contains only type/variable declarations (no
--     procedures/functions and no executable statements) to keep the worker’s
--     outer DECLARE section valid.
--   - g_csv_dir / g_csv_file are convenience defaults for demos/tests; MAIN or
--     callers may override them prior to invoking CSV read logic.

subtype xx_vc is varchar2(32767);

type xx_csv_row_t is record (
  line_no  pls_integer,
  raw_line xx_vc
);

type xx_csv_table_t is table of xx_csv_row_t index by pls_integer;

-- global "data we read from csv"
g_csv_rows   xx_csv_table_t;
g_csv_count  pls_integer := 0;

-- global csv location (you can change here for demo)
g_csv_dir    varchar2(128) := 'XX_DBADIR_SECURE';
g_csv_file   varchar2(255) := 'sample.csv';
