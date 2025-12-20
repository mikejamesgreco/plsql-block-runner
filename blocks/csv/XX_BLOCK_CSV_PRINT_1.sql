-- BLOCK: XX_BLOCK_CSV_PRINT_1.sql
-- PURPOSE:
--   Diagnostic helper block that prints CSV content stored in global CSV
--   structures to the configured logging mechanism. Intended for debugging
--   and validation of CSV parsing and ingestion logic during development
--   or troubleshooting.
--
-- DEFINES:
--   procedure xx_print_globals_csv
--
-- INPUTS:
--   None (direct parameters).
--   This block relies on the following global state having been populated
--   by prior CSV parsing / loading blocks:
--     - g_csv_count
--     - g_csv_rows(...)
--
-- OUTPUTS:
--   None.
--   Output is emitted via xx_log calls for human inspection.
--
-- SIDE EFFECTS:
--   - Writes log output (one log line per CSV row and column).
--   - No file, table, or external system modifications.
--
-- ERRORS:
--   No explicit error handling.
--   May raise standard Oracle errors if required globals are uninitialized,
--   such as:
--     - ORA-06530 (reference to uninitialized composite)
--     - ORA-06531 (collection is uninitialized)
--   Callers are expected to ensure CSV globals are populated before invoking
--   this block.

procedure xx_print_globals_csv is
  l_fields sys.odcivarchar2list;
  l_i      pls_integer;
begin
  xx_log('Printing CSV from globals. Rows='||g_csv_count);

  for r in 1 .. g_csv_count loop
    xx_log('LINE '||g_csv_rows(r).line_no||': '||g_csv_rows(r).raw_line);

    -- default delimiter is comma; can pass a different one later if needed
    l_fields := xx_csv_split_line(g_csv_rows(r).raw_line);

    for l_i in 1 .. l_fields.count loop
      xx_log('  COL '||l_i||': '||nvl(l_fields(l_i), '<NULL>'));
    end loop;
  end loop;

  xx_log('Done printing CSV');
end;
