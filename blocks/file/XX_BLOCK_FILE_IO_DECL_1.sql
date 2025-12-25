-- DECL: XX_BLOCK_FILE_IO_DECL_1
-- PURPOSE:
--   Shared file I/O global state for UTL_FILE helper blocks.
--
-- NOTES:
--   - DECL files must contain declarations only (types/constants/variables).
--   - No executable statements, procedures, or functions.
--
-- PROVIDES (globals):
--   Target:
--     g_file_dir, g_file_name, g_file_newline
--   Last read/write outputs:
--     g_file_clob, g_file_blob, g_file_base64
--   Last operation counters:
--     g_file_lines, g_file_bytes
--   Last file attributes:
--     g_file_exists, g_file_length, g_file_block_size, g_file_mtime
--   Last error snapshot:
--     g_file_last_error
--
-- OPTIONAL TYPES:
--   t_vc_tab (table of VARCHAR2 lines)

  ----------------------------------------------------------------------
  -- Target (optional convenience)
  ----------------------------------------------------------------------
  g_file_dir      VARCHAR2(200);
  g_file_name     VARCHAR2(4000);

  -- newline appended for text reads (CLOB); change to CHR(13)||CHR(10) if desired
  g_file_newline  VARCHAR2(2) := CHR(10);

  ----------------------------------------------------------------------
  -- Outputs (last operation)
  ----------------------------------------------------------------------
  g_file_clob     CLOB;
  g_file_blob     BLOB;
  g_file_base64   CLOB;

  ----------------------------------------------------------------------
  -- Counters / metadata (last operation)
  ----------------------------------------------------------------------
  g_file_lines    PLS_INTEGER := 0;
  g_file_bytes    NUMBER      := 0;

  ----------------------------------------------------------------------
  -- File attributes (last fgetattr / derived)
  ----------------------------------------------------------------------
  g_file_exists     BOOLEAN := NULL;
  g_file_length     NUMBER  := NULL;
  g_file_block_size NUMBER  := NULL;
  g_file_mtime      DATE    := NULL;

  ----------------------------------------------------------------------
  -- Last error snapshot (best-effort)
  ----------------------------------------------------------------------
  g_file_last_error VARCHAR2(4000) := NULL;
  -- Alias expected by dispatcher MAIN
  g_file_err        VARCHAR2(4000) := NULL;

  ----------------------------------------------------------------------
  -- Helpers
  ----------------------------------------------------------------------
  TYPE t_vc_tab IS TABLE OF VARCHAR2(32767) INDEX BY PLS_INTEGER;
