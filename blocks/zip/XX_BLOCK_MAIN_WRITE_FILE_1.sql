-- MAIN: XX_BLOCK_MAIN_ZIP_WRITE_FILE_1.sql
-- PURPOSE:
--   End-to-end MAIN that:
--     1) reads an input text file into g_file_clob,
--     2) maps that content into ZIP entry globals,
--     3) builds an in-memory ZIP (stored method),
--     4) writes the resulting ZIP BLOB to disk via UTL_FILE.PUT_RAW,
--     5) returns a JSON summary (including bytes written and entry count).
--
-- IMPORTANT:
--   This file is a MAIN *anonymous block snippet*.
--   It is spliced directly into the worker’s outer BEGIN...END block.
--   Do NOT define a standalone procedure/function here.
--   Nested DECLARE...BEGIN...END blocks are allowed (this MAIN is a full anonymous block).
--
-- INPUTS:
--   l_inputs_json  CLOB  (provided by the driver; must not be NULL)
--   Expected shape (minimum):
--     {
--       "file": { "dir": "<ORACLE_DIRECTORY>", "name": "<input_filename>" },
--       "zip":  { "dir": "<ORACLE_DIRECTORY>", "zip_file": "<output_zip_filename>",
--                 "entry_name": "<optional entry name>", "charset": "<optional charset>" }
--     }
--   Notes:
--     - file.dir + file.name are consumed by xx_block_file_io_read_to_clob.
--     - zip.entry_name / zip.charset are optionally consumed by ZIP_SET_ENTRY_FROM_FILE.
--     - zip.dir + zip.zip_file control where the final ZIP is written.
--
-- OUTPUTS:
--   l_result_json  CLOB  (set by MAIN; returned to caller via driver)
--     JSON summary on success, including:
--       status, file_dir, file_name, zip_dir, zip_file, zip_bytes, zip_entries
--   :v_retcode     OUT NUMBER
--     0 = success
--     2 = MAIN error
--   :v_errbuf      OUT VARCHAR2(4000)
--     NULL on success; short message on failure


DECLARE
  l_root     JSON_OBJECT_T;
  l_zip_obj  JSON_OBJECT_T;

  l_dir      VARCHAR2(200);
  l_zip_file VARCHAR2(4000);

  l_fh       UTL_FILE.FILE_TYPE;
  l_len      PLS_INTEGER;
  l_pos      PLS_INTEGER := 1;
  l_take     PLS_INTEGER;
  l_raw      RAW(32767);

  l_res      JSON_OBJECT_T;

  PROCEDURE fail(p_msg IN VARCHAR2) IS
  BEGIN
    xx_block_log_error('MAIN_ZIP_WRITE_FILE', p_msg);
    :v_retcode := 2;
    :v_errbuf  := SUBSTR(p_msg, 1, 4000);
    RAISE_APPLICATION_ERROR(-20001, 'MAIN_ZIP_WRITE_FILE | ' || p_msg);
  END;
BEGIN
  IF l_inputs_json IS NULL THEN
    fail('l_inputs_json is NULL');
  END IF;

  --------------------------------------------------------------------------
  -- Orchestrate the build
  --------------------------------------------------------------------------
  xx_block_file_io_read_to_clob;
  xx_block_zip_set_entry_from_file;

  xx_block_zip_begin;
  xx_block_zip_add_clob;
  xx_block_zip_finish;

  IF g_zip_blob IS NULL THEN
    fail('g_zip_blob is NULL after zip build (unexpected)');
  END IF;

  --------------------------------------------------------------------------
  -- Parse zip output location
  --------------------------------------------------------------------------
  l_root := JSON_OBJECT_T.parse(l_inputs_json);

  IF NOT l_root.has('zip') THEN
    fail('Missing JSON object: zip');
  END IF;

  l_zip_obj := l_root.get_object('zip');

  IF NOT l_zip_obj.has('dir') OR NOT l_zip_obj.has('zip_file') THEN
    fail('zip.dir and zip.zip_file are required');
  END IF;

  l_dir      := l_zip_obj.get_string('dir');
  l_zip_file := l_zip_obj.get_string('zip_file');

  IF l_dir IS NULL OR l_zip_file IS NULL THEN
    fail('zip.dir and zip.zip_file are required (null)');
  END IF;

  --------------------------------------------------------------------------
  -- Write zip blob to disk
  --------------------------------------------------------------------------
  l_len := DBMS_LOB.GETLENGTH(g_zip_blob);

  xx_block_log_info('MAIN_ZIP_WRITE_FILE', 'Writing '||l_zip_file||' to dir='||l_dir||' bytes='||l_len);

  l_fh := UTL_FILE.FOPEN(l_dir, l_zip_file, 'wb', 32767);

  WHILE l_pos <= l_len LOOP
    l_take := LEAST(32767, l_len - l_pos + 1);
    DBMS_LOB.READ(g_zip_blob, l_take, l_pos, l_raw);
    UTL_FILE.PUT_RAW(l_fh, l_raw, TRUE);
    l_pos := l_pos + l_take;
  END LOOP;

  UTL_FILE.FCLOSE(l_fh);

  :v_retcode := 0;
  :v_errbuf  := NULL;

  l_res := JSON_OBJECT_T();
  l_res.put('status', 'S');
  l_res.put('file_dir',  NVL(g_file_dir,''));
  l_res.put('file_name', NVL(g_file_name,''));
  l_res.put('zip_dir',   l_dir);
  l_res.put('zip_file',  l_zip_file);
  l_res.put('zip_bytes', l_len);
  l_res.put('zip_entries', NVL(g_zip_entry_count, 0));

  l_result_json := l_res.to_clob;

EXCEPTION
  WHEN OTHERS THEN
    BEGIN
      IF UTL_FILE.IS_OPEN(l_fh) THEN
        UTL_FILE.FCLOSE(l_fh);
      END IF;
    EXCEPTION
      WHEN OTHERS THEN NULL;
    END;

    IF :v_retcode IS NULL THEN
      :v_retcode := 2;
    END IF;

    IF :v_errbuf IS NULL THEN
      :v_errbuf := SUBSTR(SQLERRM, 1, 4000);
    END IF;

    RAISE;
END;
