-- MAIN: XX_BLOCK_MAIN_FILE_IO_DISPATCH_1
-- PURPOSE:
--   Generic dispatcher MAIN for XX_BLOCK_FILE_IO_* blocks.
--   Accepts an input JSON describing a single file operation and returns a
--   consistent JSON result using the globals populated by the FILE_IO block.
--
-- EXPECTED INPUT JSON (shape):
-- {
--   "op": "GETATTR|READ_TEXT|READ_BINARY|WRITE_TEXT|WRITE_CLOB|WRITE_BLOB|APPEND_TEXT|APPEND_CLOB|APPEND_BLOB|COPY|MOVE|DELETE|READ_BASE64|WRITE_BASE64",
--   "dir": "DBA_DIRECTORY_NAME",
--   "name": "file.ext",
--
--   "text": "for *_TEXT ops (VARCHAR2)",
--   "clob_text": "for *_CLOB ops (CLOB)",
--   "base64": "for *_BLOB or *_BASE64 ops",
--
--   "src_dir": "for COPY/MOVE (optional; defaults to dir)",
--   "src_name": "for COPY/MOVE (optional; defaults to name)",
--   "dst_dir": "for COPY/MOVE (required if dst_name provided; defaults to dir)",
--   "dst_name": "for COPY/MOVE (required)",
--
--   "overwrite": true,
--   "write_mode": "WB|AB"
-- }
--
-- OUTPUTS:
--   l_result_json  CLOB  (set by MAIN)
--   :v_retcode     OUT NUMBER
--   :v_errbuf      OUT VARCHAR2

DECLARE
  l_in      JSON_OBJECT_T;
  l_op      VARCHAR2(50);

  l_dir     VARCHAR2(200);
  l_name    VARCHAR2(4000);

  l_src_dir VARCHAR2(200);
  l_src_name VARCHAR2(4000);
  l_dst_dir VARCHAR2(200);
  l_dst_name VARCHAR2(4000);

  l_text    VARCHAR2(32767);
  l_clob    CLOB;
  l_b64     CLOB;
  l_blob    BLOB;

  l_overwrite BOOLEAN := TRUE;
  l_write_mode VARCHAR2(10);

  l_out JSON_OBJECT_T;

  FUNCTION get_string(p_obj JSON_OBJECT_T, p_key VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    IF p_obj IS NULL OR p_key IS NULL OR NOT p_obj.has(p_key) THEN
      RETURN NULL;
    END IF;
    RETURN p_obj.get_string(p_key);
  EXCEPTION
    WHEN OTHERS THEN
      RETURN NULL;
  END;

  FUNCTION get_bool(p_obj JSON_OBJECT_T, p_key VARCHAR2, p_default BOOLEAN) RETURN BOOLEAN IS
  BEGIN
    IF p_obj IS NULL OR p_key IS NULL OR NOT p_obj.has(p_key) THEN
      RETURN p_default;
    END IF;
    RETURN CASE LOWER(get_string(p_obj, p_key))
      WHEN 'true'  THEN TRUE
      WHEN 'false' THEN FALSE
      ELSE p_default
    END;
  EXCEPTION
    WHEN OTHERS THEN
      RETURN p_default;
  END;

  FUNCTION elem_to_clob(p_any JSON_ELEMENT_T) RETURN CLOB IS
    l_c CLOB;
    l_trim VARCHAR2(20);
  BEGIN
    IF p_any IS NULL THEN
      RETURN NULL;
    END IF;

    l_c := p_any.to_clob;

    l_trim := LOWER(TRIM(DBMS_LOB.substr(l_c, 20, 1)));
    IF l_trim = 'null' THEN
      RETURN NULL;
    END IF;

    RETURN l_c;
  EXCEPTION
    WHEN OTHERS THEN
      RETURN NULL;
  END;

BEGIN
  l_in := JSON_OBJECT_T.parse(l_inputs_json);

  l_op   := UPPER(TRIM(NVL(get_string(l_in, 'op'), get_string(l_in, 'operation'))));

  l_dir  := get_string(l_in, 'dir');
  l_name := get_string(l_in, 'name');

  l_src_dir  := NVL(get_string(l_in, 'src_dir'), l_dir);
  l_src_name := NVL(get_string(l_in, 'src_name'), l_name);

  l_dst_dir  := NVL(get_string(l_in, 'dst_dir'), l_dir);
  l_dst_name := get_string(l_in, 'dst_name');

  l_text := get_string(l_in, 'text');
  l_clob := elem_to_clob(l_in.get('clob_text'));
  l_b64  := elem_to_clob(l_in.get('base64'));

  l_overwrite := get_bool(l_in, 'overwrite', TRUE);
  l_write_mode := get_string(l_in, 'write_mode');

  -- route
  
  -- set target for convenience (response echoes these globals)
  xx_file_set_target(l_dir, l_name);
  IF l_op IN ('GETATTR') THEN
    xx_file_getattr(
      p_dir        => l_dir,
      p_name       => l_name,
      x_exists     => g_file_exists,
      x_len        => g_file_length,
      x_block_size => g_file_block_size,
      x_mtime      => g_file_mtime
    );

  ELSIF l_op IN ('READ_TEXT','READ_TEXT_TO_CLOB') THEN
    xx_file_read_text_to_clob(
      p_dir  => l_dir,
      p_name => l_name,
      x_clob => l_clob
    );

  ELSIF l_op IN ('READ_BINARY','READ_BINARY_TO_BLOB') THEN
    xx_file_read_binary_to_blob(
      p_dir  => l_dir,
      p_name => l_name,
      x_blob => l_blob
    );

  ELSIF l_op IN ('WRITE_TEXT') THEN
    xx_file_write_text(
      p_dir       => l_dir,
      p_name      => l_name,
      p_text      => l_text,
      p_overwrite => l_overwrite
    );

  ELSIF l_op IN ('WRITE_CLOB') THEN
    xx_file_write_clob(
      p_dir       => l_dir,
      p_name      => l_name,
      p_clob      => l_clob,
      p_overwrite => l_overwrite
    );

  ELSIF l_op IN ('WRITE_BLOB') THEN
    l_blob := xx_file_b64_to_blob(l_b64);
    xx_file_write_blob(
      p_dir       => l_dir,
      p_name      => l_name,
      p_blob      => l_blob,
      p_overwrite => l_overwrite
    );

  ELSIF l_op IN ('APPEND_TEXT') THEN
    xx_file_append_text(
      p_dir      => l_dir,
      p_name => l_name,
      p_text     => l_text
    );

  ELSIF l_op IN ('APPEND_CLOB') THEN
    xx_file_append_clob(
      p_dir      => l_dir,
      p_name => l_name,
      p_clob => l_clob
    );

  ELSIF l_op IN ('APPEND_BLOB') THEN
    l_blob := xx_file_b64_to_blob(l_b64);
    xx_file_append_blob(
      p_dir      => l_dir,
      p_name => l_name,
      p_blob => l_blob
    );

  ELSIF l_op IN ('COPY') THEN
    xx_file_copy(
      p_src_dir  => l_src_dir,
      p_src_name => l_src_name,
      p_dst_dir  => l_dst_dir,
      p_dst_name => l_dst_name,
      p_overwrite => l_overwrite
    );

  ELSIF l_op IN ('MOVE') THEN
    xx_file_move(
      p_src_dir  => l_src_dir,
      p_src_name => l_src_name,
      p_dst_dir  => l_dst_dir,
      p_dst_name => l_dst_name,
      p_overwrite => l_overwrite
    );

  ELSIF l_op IN ('DELETE','REMOVE') THEN
    xx_file_delete(p_dir => l_dir, p_name => l_name);

  ELSIF l_op IN ('READ_BASE64') THEN
    xx_file_read_base64(p_dir => l_dir, p_name => l_name, x_base64_clob => l_b64);

  ELSIF l_op IN ('WRITE_BASE64') THEN
    xx_file_write_base64(
      p_dir       => l_dir,
      p_name      => l_name,
      p_base64_clob => l_b64,
      p_overwrite => l_overwrite
    );

  ELSE
    RAISE_APPLICATION_ERROR(-20001, 'Unsupported op='||NVL(l_op,'(null)'));
  END IF;

  -- Build response
  l_out := JSON_OBJECT_T();
  l_out.put('status', 'OK');
  l_out.put('op', NVL(l_op,''));

  l_out.put('file_dir', NVL(g_file_dir,''));
  l_out.put('file_name', NVL(g_file_name,''));

  l_out.put('exists', CASE WHEN g_file_exists THEN 'Y' ELSE 'N' END);

  IF g_file_length IS NOT NULL THEN
    l_out.put('length', g_file_length);
  END IF;

  IF g_file_block_size IS NOT NULL THEN
    l_out.put('block_size', g_file_block_size);
  END IF;

  IF g_file_mtime IS NOT NULL THEN
    l_out.put('mtime', TO_CHAR(g_file_mtime, 'YYYY-MM-DD HH24:MI:SS'));
  END IF;

  IF g_file_lines IS NOT NULL THEN
    l_out.put('lines', g_file_lines);
  END IF;

  IF g_file_bytes IS NOT NULL THEN
    l_out.put('bytes', g_file_bytes);
  END IF;

  IF g_file_last_error IS NOT NULL THEN
    l_out.put('file_err', g_file_last_error);
  END IF;

  -- include small payloads for convenience
  IF g_file_clob IS NOT NULL AND DBMS_LOB.getlength(g_file_clob) <= 32767 THEN
    l_out.put('clob_text', DBMS_LOB.substr(g_file_clob, 32767, 1));
  ELSIF g_file_clob IS NOT NULL THEN
    l_out.put('clob_len', DBMS_LOB.getlength(g_file_clob));
  END IF;

  IF g_file_base64 IS NOT NULL AND DBMS_LOB.getlength(g_file_base64) <= 32767 THEN
    l_out.put('base64', DBMS_LOB.substr(g_file_base64, 32767, 1));
  ELSIF g_file_base64 IS NOT NULL THEN
    l_out.put('base64_len', DBMS_LOB.getlength(g_file_base64));
  END IF;

  l_result_json := l_out.to_clob;
  :v_retcode := 0;
  :v_errbuf := NULL;

EXCEPTION
  WHEN OTHERS THEN
    l_result_json :=
      '{'||
      '"status":"ERROR",'||
      '"sqlerrm":'    || xx_file_json_quote(SQLERRM) || ','||
      '"backtrace":'  || xx_file_json_quote(DBMS_UTILITY.format_error_backtrace) ||
      '}';

    :v_retcode := 2;
    :v_errbuf  := SUBSTR(SQLERRM, 1, 4000);
END;
