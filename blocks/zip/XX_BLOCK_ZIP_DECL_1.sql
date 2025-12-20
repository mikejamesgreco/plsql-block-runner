/* ZIP builder shared state (no APEX dependency) */

TYPE t_zip_entry_rec IS RECORD (
  name_utf8      VARCHAR2(4000),
  crc32          NUMBER,
  comp_size      NUMBER,
  uncomp_size    NUMBER,
  local_offset   NUMBER,
  mod_dos_time   NUMBER,  -- packed DOS time/date as 4 bytes (we store as NUMBER for convenience)
  method         PLS_INTEGER
);

TYPE t_zip_entry_tab IS TABLE OF t_zip_entry_rec INDEX BY PLS_INTEGER;

g_zip_blob         BLOB;        -- final zip being assembled
g_zip_cd_blob      BLOB;        -- central directory records collected
g_zip_entries      t_zip_entry_tab;
g_zip_entry_count  PLS_INTEGER := 0;
g_zip_open         BOOLEAN := FALSE;

-- Inputs for ADD blocks
g_zip_entry_name   VARCHAR2(4000);
g_zip_entry_clob   CLOB;
g_zip_charset      VARCHAR2(30) := 'AL32UTF8';

-------------------------------------------------------------------------------
-- CRC32 table cache (used by ZIP_ADD_CLOB)
-------------------------------------------------------------------------------
TYPE t_crc_tab IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
g_crc_tab      t_crc_tab;
g_crc_tab_init BOOLEAN := FALSE;
