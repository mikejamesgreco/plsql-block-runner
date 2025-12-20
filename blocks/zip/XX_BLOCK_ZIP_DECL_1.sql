-- DECL: XX_BLOCK_ZIP_DECL_1.sql
-- PURPOSE:
--   Declare shared state, types, and buffers used by the ZIP builder blocks.
--   This DECL defines the in-memory ZIP assembly model, including entry metadata,
--   binary payload buffers, and CRC32 support structures, with no dependency on
--   APEX or external ZIP utilities.
--
-- NOTES:
--   - This DECL contains only type and variable declarations; no executable
--     logic should appear here.
--   - ZIP construction is stateful and driven by the following block sequence:
--       1) ZIP_BEGIN        – initialize ZIP state and buffers
--       2) ZIP_SET_ENTRY_*  – define entry name/content
--       3) ZIP_ADD_*        – append entry data to ZIP
--       4) ZIP_FINISH       – write central directory and finalize ZIP
--   - g_zip_blob holds the final ZIP binary once ZIP_FINISH completes.
--   - g_zip_cd_blob is an internal staging buffer for Central Directory records.
--   - ZIP entries are tracked in-memory via g_zip_entries to support deferred
--     Central Directory creation.
--   - CRC32 state (g_crc_tab / g_crc_tab_init) is cached across entry additions
--     to avoid recomputing the lookup table for each entry.
--   - This implementation does not support ZIP64; large archives may exceed
--     classic ZIP limits.

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
