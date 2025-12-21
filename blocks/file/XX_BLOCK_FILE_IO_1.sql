-- BLOCK: XX_BLOCK_FILE_IO_1
-- PURPOSE:
--   File I/O helper procedures built on UTL_FILE.
--   Supports reading a text file to a temporary CLOB, and reading any file to a temporary BLOB.
--   Intended as reusable primitives for other blocks (SMTP attachments, ZIP, CSV, JSON, etc.).
--
-- DEFINES:
--   procedure xx_block_file_io_read_to_clob
--   procedure xx_block_file_io_read_to_blob
--
-- INPUTS (implicit via l_inputs_json framework variable):
--   {
--     "file": {
--       "dir":  "<Oracle DIRECTORY name>",
--       "name": "<filename>"
--     }
--   }
--
-- OUTPUTS:
--   Populates / updates the following global state (declared in XX_BLOCK_FILE_IO_DECL_1.sql):
--     - g_file_dir      (directory name used)
--     - g_file_name     (filename used)
--     - g_file_clob     (temporary CLOB containing file contents; read_to_clob)
--     - g_file_blob     (temporary BLOB containing file contents; read_to_blob)
--     - g_file_lines    (number of lines read; read_to_clob only)
--     - g_file_bytes    (approx bytes read/appended)
--
-- SIDE EFFECTS:
--   - Frees and recreates g_file_clob / g_file_blob as temporary LOBs.
--   - Opens and reads a file using UTL_FILE.
--   - Emits log output via xx_block_log_info / xx_block_log_error.
--   - For read_to_clob: appends g_file_newline after each line read.
--
-- ERRORS:
--   - Raises -20001 via fail() for JSON validation failures (missing/NULL file.dir or file.name).
--   - Propagates UTL_FILE and other Oracle errors (e.g. ORA-29283, ORA-29280).
--   - Ensures file handle is closed on exceptions before re-raising.
--
-- NOTES:
--   - read_to_clob is line-oriented using UTL_FILE.GET_LINE (32767 max per line).
--   - read_to_blob is binary-oriented using UTL_FILE.GET_RAW in chunks.

  ----------------------------------------------------------------------
  -- Read a text file into g_file_clob (line oriented)
  ----------------------------------------------------------------------
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

    IF TRIM(l_dir) IS NULL OR TRIM(l_name) IS NULL THEN
      fail('file.dir and file.name are required (null/blank)');
    END IF;

    g_file_dir  := l_dir;
    g_file_name := l_name;

    -- reset CLOB output
    IF g_file_clob IS NOT NULL AND DBMS_LOB.ISTEMPORARY(g_file_clob) = 1 THEN
      DBMS_LOB.FREETEMPORARY(g_file_clob);
    END IF;

    DBMS_LOB.CREATETEMPORARY(g_file_clob, TRUE);
    DBMS_LOB.TRIM(g_file_clob, 0);

    -- reset counters
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
      WHEN NO_DATA_FOUND THEN
        NULL; -- EOF
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
  END xx_block_file_io_read_to_clob;


  ----------------------------------------------------------------------
  -- Read any file into g_file_blob (binary oriented)
  ----------------------------------------------------------------------
  PROCEDURE xx_block_file_io_read_to_blob IS
    l_root     JSON_OBJECT_T;
    l_file_obj JSON_OBJECT_T;

    l_dir      VARCHAR2(200);
    l_name     VARCHAR2(4000);

    l_fh       UTL_FILE.FILE_TYPE;
    l_raw      RAW(32767);
    l_amount   PLS_INTEGER := 32767;

    PROCEDURE fail(p_msg IN VARCHAR2) IS
    BEGIN
      xx_block_log_error('FILE_IO_READ_TO_BLOB', p_msg);
      RAISE_APPLICATION_ERROR(-20001, 'FILE_IO_READ_TO_BLOB | ' || p_msg);
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

    IF TRIM(l_dir) IS NULL OR TRIM(l_name) IS NULL THEN
      fail('file.dir and file.name are required (null/blank)');
    END IF;

    g_file_dir  := l_dir;
    g_file_name := l_name;

    -- reset BLOB output
    IF g_file_blob IS NOT NULL AND DBMS_LOB.ISTEMPORARY(g_file_blob) = 1 THEN
      DBMS_LOB.FREETEMPORARY(g_file_blob);
    END IF;

    DBMS_LOB.CREATETEMPORARY(g_file_blob, TRUE);
    DBMS_LOB.TRIM(g_file_blob, 0);

    -- reset counters (bytes only; lines not applicable)
    g_file_lines := 0;
    g_file_bytes := 0;

    xx_block_log_info('FILE_IO_READ_TO_BLOB', 'Reading '||g_file_name||' from dir='||g_file_dir);

    -- binary read
    l_fh := UTL_FILE.FOPEN(g_file_dir, g_file_name, 'rb', 32767);

    BEGIN
      LOOP
        UTL_FILE.GET_RAW(l_fh, l_raw, l_amount);

        IF l_raw IS NULL OR UTL_RAW.LENGTH(l_raw) = 0 THEN
          EXIT;
        END IF;

        DBMS_LOB.WRITEAPPEND(g_file_blob, UTL_RAW.LENGTH(l_raw), l_raw);
        g_file_bytes := g_file_bytes + UTL_RAW.LENGTH(l_raw);

        -- reset buffer
        l_raw := NULL;
      END LOOP;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        NULL; -- EOF
    END;

    UTL_FILE.FCLOSE(l_fh);

    xx_block_log_info('FILE_IO_READ_TO_BLOB', 'Done. bytes='||g_file_bytes);

  EXCEPTION
    WHEN OTHERS THEN
      BEGIN
        IF UTL_FILE.IS_OPEN(l_fh) THEN
          UTL_FILE.FCLOSE(l_fh);
        END IF;
      EXCEPTION
        WHEN OTHERS THEN NULL;
      END;

      xx_block_log_error('FILE_IO_READ_TO_BLOB', 'Unhandled: '||SQLERRM);
      RAISE;
  END xx_block_file_io_read_to_blob;
