-- XX_BLOCK_ZIP_SET_ENTRY_FROM_FILE_1.sql
-- Defines: xx_block_zip_set_entry_from_file

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
