-- DECL: XX_BLOCK_FILE_IO_DECL_1
-- PURPOSE:
--   Shared file I/O global state for UTL_FILE helper blocks.
--
-- NOTES:
--   - DECL files must contain declarations only (types/constants/variables).
--   - No executable statements, procedures, or functions.
--
-- PROVIDES:
--   g_file_dir, g_file_name, g_file_newline
--   g_file_clob, g_file_blob
--   g_file_lines, g_file_bytes

  g_file_dir      VARCHAR2(200);
  g_file_name     VARCHAR2(4000);

  -- newline appended for text reads (CLOB)
  g_file_newline  VARCHAR2(2) := CHR(10);

  -- outputs
  g_file_clob     CLOB;
  g_file_blob     BLOB;

  -- counters / metadata
  g_file_lines    PLS_INTEGER := 0;
  g_file_bytes    NUMBER      := 0;
