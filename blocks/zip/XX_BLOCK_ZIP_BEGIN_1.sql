-- BLOCK: XX_BLOCK_ZIP_BEGIN_1.sql
-- PURPOSE:
--   Initialize ZIP builder state for a new in-memory ZIP archive. This block
--   allocates fresh temporary BLOBs for the ZIP payload and central directory,
--   clears any prior entry metadata, and marks the ZIP as open for subsequent
--   entry additions (ZIP_ADD_*).
--
-- DEFINES:
--   procedure xx_block_zip_begin
--
-- INPUTS:
--   None (direct parameters).
--   Uses and validates the following global ZIP state (declared in XX_BLOCK_ZIP_DECL_1.sql):
--     - g_zip_open
--
-- OUTPUTS:
--   None (direct parameters).
--   Initializes / resets the following global ZIP state:
--     - g_zip_blob         (temporary BLOB; created fresh)
--     - g_zip_cd_blob      (temporary BLOB; created fresh)
--     - g_zip_entry_count  (set to 0)
--     - g_zip_entries      (cleared)
--     - g_zip_open         (set to TRUE)
--
-- SIDE EFFECTS:
--   - Frees any prior temporary ZIP LOBs (g_zip_blob, g_zip_cd_blob) if present.
--   - Allocates new temporary LOBs via DBMS_LOB.CREATETEMPORARY.
--   - Emits log output via xx_block_log_info.
--
-- ERRORS:
--   - Raises -20001 if a ZIP session is already open (g_zip_open = TRUE).
--   - May propagate standard Oracle errors related to temporary LOB management.


PROCEDURE xx_block_zip_begin IS
BEGIN
  IF g_zip_open THEN
    RAISE_APPLICATION_ERROR(-20001, 'ZIP_BEGIN | ZIP already open');
  END IF;

  -- If caller reuses the worker, clean up any previous temp LOBs
  IF g_zip_blob IS NOT NULL AND DBMS_LOB.ISTEMPORARY(g_zip_blob) = 1 THEN
    DBMS_LOB.FREETEMPORARY(g_zip_blob);
  END IF;

  IF g_zip_cd_blob IS NOT NULL AND DBMS_LOB.ISTEMPORARY(g_zip_cd_blob) = 1 THEN
    DBMS_LOB.FREETEMPORARY(g_zip_cd_blob);
  END IF;

  DBMS_LOB.CREATETEMPORARY(g_zip_blob, TRUE);
  DBMS_LOB.CREATETEMPORARY(g_zip_cd_blob, TRUE);

  g_zip_entry_count := 0;
  g_zip_entries.DELETE;

  g_zip_open := TRUE;

  xx_block_log_info('ZIP_BEGIN', 'Initialized ZIP builder (stored method v1)');
END;
