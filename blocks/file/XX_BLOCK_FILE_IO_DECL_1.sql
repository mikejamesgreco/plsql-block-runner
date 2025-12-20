/* XX_BLOCK_FILE_IO_DECL_1.sql
   Shared state for generic file I/O blocks (text -> CLOB)
*/

g_file_dir       VARCHAR2(200);
g_file_name      VARCHAR2(4000);

g_file_clob      CLOB;
g_file_bytes     PLS_INTEGER := 0;
g_file_lines     PLS_INTEGER := 0;

-- Behavior knobs (can be overridden by JSON or other blocks later)
g_file_newline   VARCHAR2(10) := CHR(10);  -- normalize line endings to LF
g_file_max_lines PLS_INTEGER := 0;         -- 0 = unlimited
