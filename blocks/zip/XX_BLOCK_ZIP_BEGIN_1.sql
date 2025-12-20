-- XX_BLOCK_ZIP_BEGIN_1.sql
-- Defines: xx_block_zip_begin

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
