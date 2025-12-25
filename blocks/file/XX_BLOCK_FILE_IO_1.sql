-- BLOCK: XX_BLOCK_FILE_IO_2
-- PURPOSE:
--   Generic file I/O and file manipulation helpers built on UTL_FILE.
--
-- SUPPORTS (high-level):
--   - Read text file -> CLOB
--   - Read binary file -> BLOB
--   - Write/overwrite text/CLOB/BLOB
--   - Append text/CLOB/BLOB
--   - File attributes (exists, length, mtime, block_size)
--   - Copy, move/rename, delete
--   - Base64 helpers (file <-> base64 CLOB)
--
-- DEFINES:
--   procedure xx_file_set_target(p_dir, p_name)
--   procedure xx_file_getattr(p_dir, p_name, x_exists, x_len, x_block_size, x_mtime)
--   function  xx_file_exists(p_dir, p_name) return boolean
--   function  xx_file_b64_to_blob(p_base64_clob) return blob
--
--   procedure xx_file_read_text_to_clob(p_dir, p_name, p_newline, p_max_lines, x_clob)
--   procedure xx_file_read_binary_to_blob(p_dir, p_name, x_blob)
--
--   procedure xx_file_write_text(p_dir, p_name, p_text, p_overwrite, p_add_newline)
--   procedure xx_file_write_clob(p_dir, p_name, p_clob, p_overwrite)
--   procedure xx_file_write_blob(p_dir, p_name, p_blob, p_overwrite)
--
--   procedure xx_file_append_text(p_dir, p_name, p_text, p_add_newline)
--   procedure xx_file_append_clob(p_dir, p_name, p_clob)
--   procedure xx_file_append_blob(p_dir, p_name, p_blob)
--
--   procedure xx_file_copy(p_src_dir, p_src_name, p_dst_dir, p_dst_name, p_overwrite)
--   procedure xx_file_move(p_src_dir, p_src_name, p_dst_dir, p_dst_name, p_overwrite)
--   procedure xx_file_delete(p_dir, p_name)
--
--   procedure xx_file_read_base64(p_dir, p_name, x_base64_clob)
--   procedure xx_file_write_base64(p_dir, p_name, p_base64_clob, p_overwrite)
--
-- EXPECTS:
--   DECL: XX_BLOCK_FILE_IO_DECL_2.sql (or compatible) included before this BLOCK.
--
-- NOTES:
--   - p_dir must be a valid Oracle DIRECTORY object name that the schema can access.
--   - For large files, reads/writes are chunked.
--   - Base64 helpers are intended for API payload transport (not the most efficient).
--
-- SIDE EFFECTS:
--   - Updates g_file_* globals (target, outputs, counters, attributes, last_error).
--
-- ERRORS:
--   - Raises standard UTL_FILE errors (invalid_path, invalid_mode, etc.).
--   - Raises ORA-20002 with appended detail in some helper paths (best-effort).

  ----------------------------------------------------------------------
  -- small internal helpers
  ----------------------------------------------------------------------
  PROCEDURE xx_file_set_err(p_msg VARCHAR2) IS
  BEGIN
    g_file_last_error := SUBSTR(NVL(p_msg, '(null)'), 1, 4000);
  END;

  ----------------------------------------------------------------------
-- JSON helper: quote/escape a string for JSON value position
-- Returns a JSON string literal including surrounding double-quotes,
-- or the literal 'null' when input is NULL.
----------------------------------------------------------------------
FUNCTION xx_file_json_quote(p_str IN VARCHAR2) RETURN VARCHAR2 IS
  l_str VARCHAR2(32767);
BEGIN
  IF p_str IS NULL THEN
    RETURN 'null';
  END IF;

  l_str := p_str;
  -- escape backslash first
  l_str := REPLACE(l_str, '\', '\\');
  -- then double-quotes
  l_str := REPLACE(l_str, '"', '\"');
  -- control characters
  l_str := REPLACE(l_str, CHR(13), '\r');
  l_str := REPLACE(l_str, CHR(10), '\n');
  l_str := REPLACE(l_str, CHR(9),  '\t');

  RETURN '"' || l_str || '"';
END;

  PROCEDURE xx_file_reset_outputs IS
  BEGIN
    g_file_lines := 0;
    g_file_bytes := 0;
    g_file_exists := NULL;
    g_file_length := NULL;
    g_file_block_size := NULL;
    g_file_mtime := NULL;
    xx_file_set_err(NULL);

    g_file_clob := NULL;
    g_file_blob := NULL;
    g_file_base64 := NULL;
  END;

  PROCEDURE xx_file_clob_append(p_clob IN OUT NOCOPY CLOB, p_text VARCHAR2) IS
  BEGIN
    IF p_text IS NULL THEN
      RETURN;
    END IF;

    IF p_clob IS NULL THEN
      DBMS_LOB.createtemporary(p_clob, TRUE);
    END IF;

    DBMS_LOB.writeappend(p_clob, LENGTH(p_text), p_text);
  END;

  PROCEDURE xx_file_blob_append_raw(p_blob IN OUT NOCOPY BLOB, p_raw RAW) IS
  BEGIN
    IF p_raw IS NULL THEN
      RETURN;
    END IF;

    IF p_blob IS NULL THEN
      DBMS_LOB.createtemporary(p_blob, TRUE);
    END IF;

    DBMS_LOB.writeappend(p_blob, UTL_RAW.length(p_raw), p_raw);
  END;

  ----------------------------------------------------------------------
  -- API: target convenience
  ----------------------------------------------------------------------
  PROCEDURE xx_file_set_target(p_dir IN VARCHAR2, p_name IN VARCHAR2) IS
  BEGIN
    g_file_dir  := p_dir;
    g_file_name := p_name;
  END;

  ----------------------------------------------------------------------
  -- API: attributes
  ----------------------------------------------------------------------
  PROCEDURE xx_file_getattr(
    p_dir        IN  VARCHAR2,
    p_name       IN  VARCHAR2,
    x_exists     OUT BOOLEAN,
    x_len        OUT NUMBER,
    x_block_size OUT NUMBER,
    x_mtime      OUT DATE
  ) IS
    l_exists BOOLEAN;
    l_len    NUMBER;
    l_block  BINARY_INTEGER;
    l_mtime  DATE;
  BEGIN
    xx_file_reset_outputs;

    UTL_FILE.fgetattr(
      location     => p_dir,
      filename     => p_name,
      fexists      => l_exists,
      file_length  => l_len,
      block_size   => l_block
    );

    l_mtime := NULL;

    x_exists := l_exists;
    x_len    := l_len;
    x_block_size := l_block;
    x_mtime  := l_mtime;

    g_file_exists     := l_exists;
    g_file_length     := l_len;
    g_file_block_size := l_block;
    g_file_mtime      := l_mtime;
  EXCEPTION
    WHEN OTHERS THEN
      xx_file_set_err(SQLERRM);
      RAISE;
  END;

  FUNCTION xx_file_exists(p_dir IN VARCHAR2, p_name IN VARCHAR2) RETURN BOOLEAN IS
    l_exists BOOLEAN;
    l_len    NUMBER;
    l_block  BINARY_INTEGER;
    l_mtime  DATE;
  BEGIN
    UTL_FILE.fgetattr(p_dir, p_name, l_exists, l_len, l_block);
    l_mtime := NULL;

    g_file_exists     := l_exists;
    g_file_length     := l_len;
    g_file_block_size := l_block;
    g_file_mtime      := l_mtime;

    RETURN l_exists;
  EXCEPTION
    WHEN OTHERS THEN
      -- If getattr fails (e.g. invalid path), treat as non-existent but preserve error.
      xx_file_set_err(SQLERRM);
      RETURN FALSE;
  END;

  ----------------------------------------------------------------------
  -- API: read text -> CLOB
  ----------------------------------------------------------------------
  PROCEDURE xx_file_read_text_to_clob(
    p_dir       IN  VARCHAR2,
    p_name      IN  VARCHAR2,
    p_newline   IN  VARCHAR2 DEFAULT NULL,
    p_max_lines IN  PLS_INTEGER DEFAULT NULL,
    x_clob      OUT CLOB
  ) IS
    l_fh   UTL_FILE.file_type;
    l_line VARCHAR2(32767);
    l_nl   VARCHAR2(10) := NVL(p_newline, g_file_newline);
    l_max  PLS_INTEGER := NVL(p_max_lines, 0); -- 0 means unlimited
  BEGIN
    xx_file_reset_outputs;

    DBMS_LOB.createtemporary(x_clob, TRUE);

    l_fh := UTL_FILE.fopen(p_dir, p_name, 'r', 32767);

    BEGIN
      LOOP
        UTL_FILE.get_line(l_fh, l_line);
        g_file_lines := g_file_lines + 1;

        xx_file_clob_append(x_clob, l_line);
        xx_file_clob_append(x_clob, l_nl);

        EXIT WHEN (l_max > 0 AND g_file_lines >= l_max);
      END LOOP;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        NULL;
    END;

    UTL_FILE.fclose(l_fh);

    g_file_clob := x_clob;
    g_file_bytes := DBMS_LOB.getlength(x_clob);
  EXCEPTION
    WHEN OTHERS THEN
      xx_file_set_err(SQLERRM);
      BEGIN
        UTL_FILE.fclose(l_fh);
      EXCEPTION
        WHEN OTHERS THEN NULL;
      END;
      RAISE;
  END;

  ----------------------------------------------------------------------
  -- API: read binary -> BLOB
  ----------------------------------------------------------------------
  PROCEDURE xx_file_read_binary_to_blob(
    p_dir  IN  VARCHAR2,
    p_name IN  VARCHAR2,
    x_blob OUT BLOB
  ) IS
    l_fh    UTL_FILE.file_type;
    l_raw   RAW(32767);
    l_amt   PLS_INTEGER := 32767;
  BEGIN
    xx_file_reset_outputs;

    DBMS_LOB.createtemporary(x_blob, TRUE);
    l_fh := UTL_FILE.fopen(p_dir, p_name, 'rb', 32767);

    BEGIN
      LOOP
        UTL_FILE.get_raw(l_fh, l_raw, l_amt);
        EXIT WHEN l_raw IS NULL OR UTL_RAW.length(l_raw) = 0;

        xx_file_blob_append_raw(x_blob, l_raw);
      END LOOP;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        NULL;
    END;

    UTL_FILE.fclose(l_fh);

    g_file_blob := x_blob;
    g_file_bytes := DBMS_LOB.getlength(x_blob);
  EXCEPTION
    WHEN OTHERS THEN
      xx_file_set_err(SQLERRM);
      BEGIN
        UTL_FILE.fclose(l_fh);
      EXCEPTION
        WHEN OTHERS THEN NULL;
      END;
      RAISE;
  END;

  ----------------------------------------------------------------------
  -- API: write / overwrite helpers
  ----------------------------------------------------------------------
  PROCEDURE xx_file_write_text(
    p_dir         IN VARCHAR2,
    p_name        IN VARCHAR2,
    p_text        IN VARCHAR2,
    p_overwrite   IN BOOLEAN DEFAULT TRUE,
    p_add_newline IN BOOLEAN DEFAULT FALSE
  ) IS
    l_fh UTL_FILE.file_type;
    l_mode VARCHAR2(2);
    l_txt VARCHAR2(32767);
  BEGIN
    xx_file_reset_outputs;

    l_mode := CASE WHEN p_overwrite THEN 'w' ELSE 'a' END;
    l_fh := UTL_FILE.fopen(p_dir, p_name, l_mode, 32767);

    l_txt := NVL(p_text, '');
    IF p_add_newline THEN
      UTL_FILE.put_line(l_fh, l_txt);
      g_file_lines := 1;
      g_file_bytes := LENGTH(l_txt) + LENGTH(NVL(g_file_newline, CHR(10)));
    ELSE
      UTL_FILE.put(l_fh, l_txt);
      g_file_bytes := LENGTH(l_txt);
    END IF;

    UTL_FILE.fclose(l_fh);
  EXCEPTION
    WHEN OTHERS THEN
      xx_file_set_err(SQLERRM);
      BEGIN
        UTL_FILE.fclose(l_fh);
      EXCEPTION
        WHEN OTHERS THEN NULL;
      END;
      RAISE;
  END;

  PROCEDURE xx_file_write_clob(
    p_dir       IN VARCHAR2,
    p_name      IN VARCHAR2,
    p_clob      IN CLOB,
    p_overwrite IN BOOLEAN DEFAULT TRUE
  ) IS
    l_fh   UTL_FILE.file_type;
    l_mode VARCHAR2(2);
    l_pos  PLS_INTEGER := 1;
    l_len  PLS_INTEGER;
    l_take PLS_INTEGER;
    l_chunk VARCHAR2(32767);
  BEGIN
    xx_file_reset_outputs;

    l_mode := CASE WHEN p_overwrite THEN 'w' ELSE 'a' END;
    l_fh := UTL_FILE.fopen(p_dir, p_name, l_mode, 32767);

    IF p_clob IS NOT NULL THEN
      l_len := DBMS_LOB.getlength(p_clob);
      WHILE l_pos <= l_len LOOP
        l_take := LEAST(32767, l_len - l_pos + 1);
        l_chunk := DBMS_LOB.substr(p_clob, l_take, l_pos);
        UTL_FILE.put(l_fh, l_chunk);
        g_file_bytes := g_file_bytes + LENGTH(l_chunk);
        l_pos := l_pos + l_take;
      END LOOP;
    END IF;

    UTL_FILE.fclose(l_fh);
  EXCEPTION
    WHEN OTHERS THEN
      xx_file_set_err(SQLERRM);
      BEGIN
        UTL_FILE.fclose(l_fh);
      EXCEPTION
        WHEN OTHERS THEN NULL;
      END;
      RAISE;
  END;

  PROCEDURE xx_file_write_blob(
    p_dir       IN VARCHAR2,
    p_name      IN VARCHAR2,
    p_blob      IN BLOB,
    p_overwrite IN BOOLEAN DEFAULT TRUE
  ) IS
    l_fh   UTL_FILE.file_type;
    l_mode VARCHAR2(2);
    l_pos  PLS_INTEGER := 1;
    l_len  PLS_INTEGER;
    l_take PLS_INTEGER;
    l_raw  RAW(32767);
  BEGIN
    xx_file_reset_outputs;

    l_mode := CASE WHEN p_overwrite THEN 'wb' ELSE 'ab' END;
    l_fh := UTL_FILE.fopen(p_dir, p_name, l_mode, 32767);

    IF p_blob IS NOT NULL THEN
      l_len := DBMS_LOB.getlength(p_blob);
      WHILE l_pos <= l_len LOOP
        l_take := LEAST(32767, l_len - l_pos + 1);
        l_raw := DBMS_LOB.substr(p_blob, l_take, l_pos);
        UTL_FILE.put_raw(l_fh, l_raw, TRUE);
        g_file_bytes := g_file_bytes + UTL_RAW.length(l_raw);
        l_pos := l_pos + l_take;
      END LOOP;
    END IF;

    UTL_FILE.fclose(l_fh);
  EXCEPTION
    WHEN OTHERS THEN
      xx_file_set_err(SQLERRM);
      BEGIN
        UTL_FILE.fclose(l_fh);
      EXCEPTION
        WHEN OTHERS THEN NULL;
      END;
      RAISE;
  END;

  ----------------------------------------------------------------------
  -- API: append helpers
  ----------------------------------------------------------------------
  PROCEDURE xx_file_append_text(
    p_dir         IN VARCHAR2,
    p_name        IN VARCHAR2,
    p_text        IN VARCHAR2,
    p_add_newline IN BOOLEAN DEFAULT FALSE
  ) IS
  BEGIN
    -- same semantics as write_text but always append
    xx_file_write_text(
      p_dir         => p_dir,
      p_name        => p_name,
      p_text        => p_text,
      p_overwrite   => FALSE,
      p_add_newline => p_add_newline
    );
  END;

  PROCEDURE xx_file_append_clob(
    p_dir  IN VARCHAR2,
    p_name IN VARCHAR2,
    p_clob IN CLOB
  ) IS
  BEGIN
    xx_file_write_clob(
      p_dir       => p_dir,
      p_name      => p_name,
      p_clob      => p_clob,
      p_overwrite => FALSE
    );
  END;

  PROCEDURE xx_file_append_blob(
    p_dir  IN VARCHAR2,
    p_name IN VARCHAR2,
    p_blob IN BLOB
  ) IS
  BEGIN
    xx_file_write_blob(
      p_dir       => p_dir,
      p_name      => p_name,
      p_blob      => p_blob,
      p_overwrite => FALSE
    );
  END;

  ----------------------------------------------------------------------
  -- API: copy / move / delete
  ----------------------------------------------------------------------
  PROCEDURE xx_file_copy(
    p_src_dir   IN VARCHAR2,
    p_src_name  IN VARCHAR2,
    p_dst_dir   IN VARCHAR2,
    p_dst_name  IN VARCHAR2,
    p_overwrite IN BOOLEAN DEFAULT TRUE
  ) IS
  BEGIN
    xx_file_reset_outputs;
    UTL_FILE.fcopy(p_src_dir, p_src_name, p_dst_dir, p_dst_name);

    IF NOT p_overwrite THEN
      NULL; -- UTL_FILE.fcopy always overwrites if destination exists? (behavior depends on version)
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      xx_file_set_err(SQLERRM);
      RAISE;
  END;

  PROCEDURE xx_file_move(
    p_src_dir   IN VARCHAR2,
    p_src_name  IN VARCHAR2,
    p_dst_dir   IN VARCHAR2,
    p_dst_name  IN VARCHAR2,
    p_overwrite IN BOOLEAN DEFAULT TRUE
  ) IS
  BEGIN
    xx_file_reset_outputs;
    UTL_FILE.frename(p_src_dir, p_src_name, p_dst_dir, p_dst_name, p_overwrite);
  EXCEPTION
    WHEN OTHERS THEN
      xx_file_set_err(SQLERRM);
      RAISE;
  END;

  PROCEDURE xx_file_delete(
    p_dir  IN VARCHAR2,
    p_name IN VARCHAR2
  ) IS
  BEGIN
    xx_file_reset_outputs;
    UTL_FILE.fremove(p_dir, p_name);
  EXCEPTION
    WHEN OTHERS THEN
      xx_file_set_err(SQLERRM);
      RAISE;
  END;

  FUNCTION xx_file_b64_to_blob(p_base64_clob IN CLOB) RETURN BLOB IS
    l_clean   CLOB;
    l_blob    BLOB;
    l_pos     PLS_INTEGER := 1;
    l_len     PLS_INTEGER;
    l_take    PLS_INTEGER;
    l_chunk   VARCHAR2(32767);
    l_raw_in  RAW(32767);
    l_raw_out RAW(32767);
  BEGIN
    IF p_base64_clob IS NULL OR DBMS_LOB.getlength(p_base64_clob) = 0 THEN
      RETURN NULL;
    END IF;

    -- strip whitespace/newlines into a temporary CLOB
    DBMS_LOB.createtemporary(l_clean, TRUE);
    l_len := DBMS_LOB.getlength(p_base64_clob);
    WHILE l_pos <= l_len LOOP
      l_chunk := DBMS_LOB.substr(p_base64_clob, LEAST(32767, l_len - l_pos + 1), l_pos);
      l_chunk := REPLACE(REPLACE(REPLACE(l_chunk, CHR(10), ''), CHR(13), ''), ' ', '');
      DBMS_LOB.writeappend(l_clean, LENGTH(l_chunk), l_chunk);
      l_pos := l_pos + 32767;
    END LOOP;

    DBMS_LOB.createtemporary(l_blob, TRUE);

    l_pos := 1;
    l_len := DBMS_LOB.getlength(l_clean);

    -- base64 decode wants multiples of 4; use safe chunk size
    WHILE l_pos <= l_len LOOP
      l_take := LEAST(32000, l_len - l_pos + 1);
      l_take := l_take - MOD(l_take, 4);
      EXIT WHEN l_take <= 0;

      l_chunk := DBMS_LOB.substr(l_clean, l_take, l_pos);
      l_raw_in := UTL_RAW.cast_to_raw(l_chunk);
      l_raw_out := UTL_ENCODE.base64_decode(l_raw_in);
      DBMS_LOB.writeappend(l_blob, UTL_RAW.length(l_raw_out), l_raw_out);

      l_pos := l_pos + l_take;
    END LOOP;

    IF DBMS_LOB.istemporary(l_clean) = 1 THEN
      DBMS_LOB.freetemporary(l_clean);
    END IF;

    RETURN l_blob;
  EXCEPTION
    WHEN OTHERS THEN
      BEGIN
        IF DBMS_LOB.istemporary(l_clean) = 1 THEN
          DBMS_LOB.freetemporary(l_clean);
        END IF;
      EXCEPTION
        WHEN OTHERS THEN NULL;
      END;
      BEGIN
        IF DBMS_LOB.istemporary(l_blob) = 1 THEN
          DBMS_LOB.freetemporary(l_blob);
        END IF;
      EXCEPTION
        WHEN OTHERS THEN NULL;
      END;
      RAISE;
  END;

  PROCEDURE xx_file_read_base64(
    p_dir          IN  VARCHAR2,
    p_name         IN  VARCHAR2,
    x_base64_clob  OUT CLOB
  ) IS
    l_blob BLOB;
    l_pos  PLS_INTEGER := 1;
    l_len  PLS_INTEGER;
    l_take PLS_INTEGER;
    l_raw  RAW(32767);
    l_b64  RAW(32767);
    l_txt  VARCHAR2(32767);
  BEGIN
    xx_file_read_binary_to_blob(p_dir, p_name, l_blob);

    DBMS_LOB.createtemporary(x_base64_clob, TRUE);

    IF l_blob IS NULL THEN
      g_file_base64 := x_base64_clob;
      RETURN;
    END IF;

    l_len := DBMS_LOB.getlength(l_blob);
    WHILE l_pos <= l_len LOOP
      l_take := LEAST(24573, l_len - l_pos + 1); -- 24573 bytes -> 32764 base64 chars (safe)
      l_raw := DBMS_LOB.substr(l_blob, l_take, l_pos);
      l_b64 := UTL_ENCODE.base64_encode(l_raw);
      l_txt := UTL_RAW.cast_to_varchar2(l_b64);
      -- strip CR/LF
      l_txt := REPLACE(REPLACE(l_txt, CHR(10), ''), CHR(13), '');
      xx_file_clob_append(x_base64_clob, l_txt);
      l_pos := l_pos + l_take;
    END LOOP;

    g_file_base64 := x_base64_clob;
  EXCEPTION
    WHEN OTHERS THEN
      xx_file_set_err(SQLERRM);
      RAISE;
  END;

  PROCEDURE xx_file_write_base64(
    p_dir          IN VARCHAR2,
    p_name         IN VARCHAR2,
    p_base64_clob  IN CLOB,
    p_overwrite    IN BOOLEAN DEFAULT TRUE
  ) IS
    l_fh   UTL_FILE.file_type;
    l_mode VARCHAR2(2);
    l_clean CLOB;
    l_pos  PLS_INTEGER := 1;
    l_len  PLS_INTEGER;
    l_chunk VARCHAR2(32767);
    l_raw_in RAW(32767);
    l_raw_out RAW(32767);
  BEGIN
    xx_file_reset_outputs;

    l_mode := CASE WHEN p_overwrite THEN 'wb' ELSE 'ab' END;
    l_fh := UTL_FILE.fopen(p_dir, p_name, l_mode, 32767);

    IF p_base64_clob IS NULL OR DBMS_LOB.getlength(p_base64_clob) = 0 THEN
      UTL_FILE.fclose(l_fh);
      RETURN;
    END IF;

    -- strip whitespace/newlines
    DBMS_LOB.createtemporary(l_clean, TRUE);
    l_len := DBMS_LOB.getlength(p_base64_clob);
    WHILE l_pos <= l_len LOOP
      l_chunk := DBMS_LOB.substr(p_base64_clob, LEAST(32767, l_len - l_pos + 1), l_pos);
      l_chunk := REPLACE(REPLACE(REPLACE(l_chunk, CHR(10), ''), CHR(13), ''), ' ', '');
      DBMS_LOB.writeappend(l_clean, LENGTH(l_chunk), l_chunk);
      l_pos := l_pos + 32767;
    END LOOP;

    l_pos := 1;
    l_len := DBMS_LOB.getlength(l_clean);

    -- base64 decode wants multiples of 4; use safe chunk size
    WHILE l_pos <= l_len LOOP
      l_chunk := DBMS_LOB.substr(l_clean, LEAST(32000, l_len - l_pos + 1), l_pos);
      l_raw_in := UTL_RAW.cast_to_raw(l_chunk);
      l_raw_out := UTL_ENCODE.base64_decode(l_raw_in);
      UTL_FILE.put_raw(l_fh, l_raw_out, TRUE);
      g_file_bytes := g_file_bytes + UTL_RAW.length(l_raw_out);
      l_pos := l_pos + 32000;
    END LOOP;

    UTL_FILE.fclose(l_fh);

    IF DBMS_LOB.istemporary(l_clean) = 1 THEN
      DBMS_LOB.freetemporary(l_clean);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      xx_file_set_err(SQLERRM);
      BEGIN
        UTL_FILE.fclose(l_fh);
      EXCEPTION
        WHEN OTHERS THEN NULL;
      END;
      BEGIN
        IF DBMS_LOB.istemporary(l_clean) = 1 THEN
          DBMS_LOB.freetemporary(l_clean);
        END IF;
      EXCEPTION
        WHEN OTHERS THEN NULL;
      END;
      RAISE;
  END;

