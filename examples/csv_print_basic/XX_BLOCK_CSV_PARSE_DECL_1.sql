-- XX_BLOCK_CSV_PARSE_DECL_1.sql
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
