-- XX_BLOCK_FILE_IO_READ_TO_CLOB_1.sql
-- Defines: xx_block_file_io_read_to_clob
-- Requires shared vars from XX_BLOCK_FILE_IO_DECL_1.sql and log helpers.

PROCEDURE xx_block_file_io_read_to_clob IS
  l_root     JSON_OBJECT_T;
  l_file_obj JSON_OBJECT_T;

  l_dir      VARCHAR2(200);
  l_name     VARCHAR2(4000);

  l_fh       UTL_FILE.FILE_TYPE;
  l_line     VARCHAR2(32767);

  PROCEDURE fail(p_msg IN VARCHAR2) IS
  BEGIN
    xx_block_log_error('FILE_IO_READ_TO_CLOB', p_msg);
    RAISE_APPLICATION_ERROR(-20001, 'FILE_IO_READ_TO_CLOB | ' || p_msg);
  END;
BEGIN
  IF l_inputs_json IS NULL THEN
    fail('l_inputs_json is NULL');
  END IF;

  l_root := JSON_OBJECT_T.parse(l_inputs_json);

  IF NOT l_root.has('file') THEN
    fail('Missing JSON object: file');
  END IF;

  l_file_obj := l_root.get_object('file');

  IF NOT l_file_obj.has('dir') OR NOT l_file_obj.has('name') THEN
    fail('file.dir and file.name are required');
  END IF;

  l_dir  := l_file_obj.get_string('dir');
  l_name := l_file_obj.get_string('name');

  IF l_dir IS NULL OR l_name IS NULL THEN
    fail('file.dir and file.name are required (null)');
  END IF;

  g_file_dir  := l_dir;
  g_file_name := l_name;

  IF g_file_clob IS NOT NULL AND DBMS_LOB.ISTEMPORARY(g_file_clob) = 1 THEN
    DBMS_LOB.FREETEMPORARY(g_file_clob);
  END IF;

  DBMS_LOB.CREATETEMPORARY(g_file_clob, TRUE);
  g_file_bytes := 0;
  g_file_lines := 0;

  xx_block_log_info('FILE_IO_READ_TO_CLOB', 'Reading '||g_file_name||' from dir='||g_file_dir);

  l_fh := UTL_FILE.FOPEN(g_file_dir, g_file_name, 'r', 32767);

  BEGIN
    LOOP
      UTL_FILE.GET_LINE(l_fh, l_line);

      g_file_lines := g_file_lines + 1;

      DBMS_LOB.WRITEAPPEND(g_file_clob, LENGTH(l_line), l_line);
      DBMS_LOB.WRITEAPPEND(g_file_clob, LENGTH(g_file_newline), g_file_newline);

      g_file_bytes := g_file_bytes + LENGTH(l_line) + LENGTH(g_file_newline);
    END LOOP;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN NULL; -- EOF
  END;

  UTL_FILE.FCLOSE(l_fh);

  xx_block_log_info('FILE_IO_READ_TO_CLOB', 'Done. lines='||g_file_lines||', bytes='||g_file_bytes);

EXCEPTION
  WHEN OTHERS THEN
    BEGIN
      IF UTL_FILE.IS_OPEN(l_fh) THEN
        UTL_FILE.FCLOSE(l_fh);
      END IF;
    EXCEPTION
      WHEN OTHERS THEN NULL;
    END;
    xx_block_log_error('FILE_IO_READ_TO_CLOB', 'Unhandled: '||SQLERRM);
    RAISE;
END;
