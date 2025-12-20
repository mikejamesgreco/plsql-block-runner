-- BLOCK: XX_BLOCK_ZIP_SET_ENTRY_FROM_FILE_1.sql
-- PURPOSE:
--   Bridge block that prepares ZIP entry globals from the results of a prior
--   file-read operation. This block maps the file content already loaded into
--   g_file_clob (via FILE_IO_READ_TO_CLOB) into the ZIP entry inputs expected
--   by ZIP_ADD_CLOB, and determines the ZIP entry name and optional charset
--   from inputs JSON.
--
-- DEFINES:
--   procedure xx_block_zip_set_entry_from_file
--
-- INPUTS:
--   None (direct parameters).
--   Requires the following global state to be present:
--     - g_file_clob   (file contents; must not be NULL)
--     - g_file_name   (default entry name if not overridden)
--   Optionally reads configuration from l_inputs_json (framework variable):
--     - zip.entry_name  (override name inside the ZIP)
--     - zip.charset     (override g_zip_charset for CLOB->BLOB conversion)
--     - file.name       (used only as a fallback for entry naming)
--
-- OUTPUTS:
--   None (direct parameters).
--   Sets the following global ZIP input state for subsequent ZIP_ADD_CLOB:
--     - g_zip_entry_name  (resolved ZIP entry name)
--     - g_zip_entry_clob  (points at g_file_clob)
--   May also update:
--     - g_zip_charset     (if zip.charset is supplied)
--
-- SIDE EFFECTS:
--   - Modifies ZIP-related globals used by ZIP_ADD_CLOB.
--   - Emits log output via xx_block_log_info / xx_block_log_error.
--
-- ERRORS:
--   - Raises -20001 if g_file_clob is NULL (indicating the file read did not run
--     or did not populate the expected global).
--   - May propagate standard Oracle JSON parsing errors if l_inputs_json is not
--     valid JSON when provided.
--
-- NOTES:
--   - Name precedence:
--       1) zip.entry_name (if present)
--       2) file.name (if present)
--       3) g_file_name (from the file read block)
--       4) fallback literal 'file.txt'
--   - This block does not create or modify ZIP bytes; it only prepares inputs
--     for the subsequent ZIP_ADD_CLOB call.

PROCEDURE xx_block_zip_set_entry_from_file IS
  l_root    JSON_OBJECT_T;
  l_zip     JSON_OBJECT_T;
  l_file    JSON_OBJECT_T;

  l_entry_name VARCHAR2(4000);
BEGIN
  IF g_file_clob IS NULL THEN
    xx_block_log_error('ZIP_SET_ENTRY_FROM_FILE', 'g_file_clob is NULL (file read did not populate it)');
    RAISE_APPLICATION_ERROR(-20001, 'ZIP_SET_ENTRY_FROM_FILE | g_file_clob is NULL');
  END IF;

  l_entry_name := g_file_name;

  IF l_inputs_json IS NOT NULL THEN
    l_root := JSON_OBJECT_T.parse(l_inputs_json);

    IF l_root.has('file') THEN
      l_file := l_root.get_object('file');
      IF l_file.has('name') THEN
        l_entry_name := NVL(l_entry_name, l_file.get_string('name'));
      END IF;
    END IF;

    IF l_root.has('zip') THEN
      l_zip := l_root.get_object('zip');

      IF l_zip.has('entry_name') THEN
        l_entry_name := l_zip.get_string('entry_name');
      END IF;

      IF l_zip.has('charset') THEN
        g_zip_charset := l_zip.get_string('charset');
      END IF;
    END IF;
  END IF;

  g_zip_entry_name := NVL(l_entry_name, 'file.txt');
  g_zip_entry_clob := g_file_clob;

  xx_block_log_info('ZIP_SET_ENTRY_FROM_FILE', 'zip_entry_name='||g_zip_entry_name);
END;
