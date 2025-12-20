-- DECL: XX_BLOCK_FILE_IO_DECL_1.sql
-- PURPOSE:
--   Declare shared state for generic file I/O blocks that read text files
--   into memory as CLOBs. These globals are populated by file-read blocks
--   and consumed by downstream processing blocks (e.g. ZIP entry creation,
--   CSV parsing, content inspection).
--
-- NOTES:
--   - This DECL contains only variable declarations and configuration knobs.
--     No executable logic, procedures, or functions should appear here.
--   - g_file_clob is expected to be managed as a temporary CLOB by file I/O
--     blocks; callers should not assume it is persistent across worker runs.
--   - g_file_bytes and g_file_lines are informational counters only and are
--     approximate (character-based, not physical byte counts).
--   - g_file_newline controls how line breaks are normalized when reading
--     files; default is LF (CHR(10)).
--   - g_file_max_lines is reserved for future use (0 = unlimited).

g_file_dir       VARCHAR2(200);
g_file_name      VARCHAR2(4000);

g_file_clob      CLOB;
g_file_bytes     PLS_INTEGER := 0;
g_file_lines     PLS_INTEGER := 0;

-- Behavior knobs (can be overridden by JSON or other blocks later)
g_file_newline   VARCHAR2(10) := CHR(10);  -- normalize line endings to LF
g_file_max_lines PLS_INTEGER := 0;         -- 0 = unlimited
