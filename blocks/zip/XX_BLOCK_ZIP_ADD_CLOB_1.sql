-- XX_BLOCK_ZIP_ADD_CLOB_1.sql
-- Defines: xx_block_zip_add_clob

PROCEDURE xx_block_zip_add_clob IS
  ----------------------------------------------------------------------------
  -- Local variables
  ----------------------------------------------------------------------------
  l_blob          BLOB;

  l_dest_offset   INTEGER := 1;
  l_src_offset    INTEGER := 1;
  l_lang_ctx      INTEGER := DBMS_LOB.DEFAULT_LANG_CTX;
  l_warning       INTEGER;
  l_charset_id    INTEGER;

  l_name_utf8     VARCHAR2(4000);
  l_name_raw      RAW(32767);

  l_uncomp_len    NUMBER;
  l_crc           NUMBER;
  l_local_offset  NUMBER;
  l_dos           NUMBER;
  l_now           DATE := SYSDATE;

  ----------------------------------------------------------------------------
  -- Helpers
  ----------------------------------------------------------------------------
  PROCEDURE fail(p_msg IN VARCHAR2) IS
  BEGIN
    xx_block_log_error('ZIP_ADD_CLOB', p_msg);
    RAISE_APPLICATION_ERROR(-20001, 'ZIP_ADD_CLOB | ' || p_msg);
  END;

  FUNCTION le2(p IN PLS_INTEGER) RETURN RAW IS
    l_raw RAW(4);
  BEGIN
    l_raw := UTL_RAW.CAST_FROM_BINARY_INTEGER(p, UTL_RAW.LITTLE_ENDIAN);
    RETURN UTL_RAW.SUBSTR(l_raw, 1, 2);
  END;

  FUNCTION le4(p IN NUMBER) RETURN RAW IS
  BEGIN
    RETURN UTL_RAW.CAST_FROM_BINARY_INTEGER(TRUNC(p), UTL_RAW.LITTLE_ENDIAN);
  END;

  PROCEDURE blob_append(p_target IN OUT NOCOPY BLOB, p_raw IN RAW) IS
  BEGIN
    DBMS_LOB.WRITEAPPEND(p_target, UTL_RAW.LENGTH(p_raw), p_raw);
  END;

  PROCEDURE blob_append_blob(p_target IN OUT NOCOPY BLOB, p_src IN BLOB) IS
  BEGIN
    IF DBMS_LOB.GETLENGTH(p_src) > 0 THEN
      DBMS_LOB.APPEND(p_target, p_src);
    END IF;
  END;

  FUNCTION dos_datetime(p_dt IN DATE) RETURN NUMBER IS
    l_sec  PLS_INTEGER;
    l_min  PLS_INTEGER;
    l_hour PLS_INTEGER;
    l_day  PLS_INTEGER;
    l_mon  PLS_INTEGER;
    l_year PLS_INTEGER;
    l_time PLS_INTEGER;
    l_date PLS_INTEGER;
  BEGIN
    l_sec  := TRUNC(TO_NUMBER(TO_CHAR(p_dt,'SS')) / 2); -- 2-second resolution
    l_min  := TO_NUMBER(TO_CHAR(p_dt,'MI'));
    l_hour := TO_NUMBER(TO_CHAR(p_dt,'HH24'));
    l_day  := TO_NUMBER(TO_CHAR(p_dt,'DD'));
    l_mon  := TO_NUMBER(TO_CHAR(p_dt,'MM'));
    l_year := TO_NUMBER(TO_CHAR(p_dt,'YYYY')) - 1980;

    l_time := l_sec + (l_min * 32) + (l_hour * 2048);
    l_date := l_day + (l_mon * 32) + (l_year * 512);

    RETURN l_time + (l_date * POWER(2,16));
  END;

  ----------------------------------------------------------------------------
  -- CRC32 implementation (table-driven) WITHOUT BITXOR dependency
  -- Uses global g_crc_tab / g_crc_tab_init from XX_BLOCK_ZIP_DECL_1.sql
  ----------------------------------------------------------------------------
  FUNCTION bxor(a IN NUMBER, b IN NUMBER) RETURN NUMBER IS
    x NUMBER := 0;
    bit NUMBER := 1;
    aa NUMBER := a;
    bb NUMBER := b;
    abit NUMBER;
    bbit NUMBER;
  BEGIN
    FOR i IN 0..31 LOOP
      abit := BITAND(aa, 1);
      bbit := BITAND(bb, 1);
      IF (abit = 1 AND bbit = 0) OR (abit = 0 AND bbit = 1) THEN
        x := x + bit;
      END IF;
      aa := TRUNC(aa / 2);
      bb := TRUNC(bb / 2);
      bit := bit * 2;
    END LOOP;
    RETURN x;
  END;

  PROCEDURE init_crc_tab IS
    l_poly NUMBER := TO_NUMBER('EDB88320','XXXXXXXX');
    l_crc  NUMBER;
  BEGIN
    IF g_crc_tab_init THEN
      RETURN;
    END IF;

    g_crc_tab.DELETE;

    FOR i IN 0..255 LOOP
      l_crc := i;
      FOR j IN 1..8 LOOP
        IF MOD(l_crc,2)=1 THEN
          l_crc := bxor(TRUNC(l_crc/2), l_poly);
        ELSE
          l_crc := TRUNC(l_crc/2);
        END IF;
      END LOOP;
      g_crc_tab(i) := l_crc;
    END LOOP;

    g_crc_tab_init := TRUE;
  END;

  FUNCTION crc32_blob(p_blob IN BLOB) RETURN NUMBER IS
    l_crc   NUMBER := TO_NUMBER('FFFFFFFF','XXXXXXXX');
    l_pos   PLS_INTEGER := 1;
    l_len   PLS_INTEGER := DBMS_LOB.GETLENGTH(p_blob);
    l_chunk RAW(32767);
    l_take  PLS_INTEGER;

    l_byte  PLS_INTEGER;
    l_idx   PLS_INTEGER;
  BEGIN
    init_crc_tab;

    WHILE l_pos <= l_len LOOP
      l_take := LEAST(32767, l_len - l_pos + 1);
      DBMS_LOB.READ(p_blob, l_take, l_pos, l_chunk);

      FOR k IN 1..l_take LOOP
        l_byte := TO_NUMBER(SUBSTR(RAWTOHEX(UTL_RAW.SUBSTR(l_chunk, k, 1)), 1, 2), 'XX');
        l_idx  := bxor(BITAND(l_crc, 255), l_byte);
        l_crc  := bxor(TRUNC(l_crc/256), g_crc_tab(l_idx));
      END LOOP;

      l_pos := l_pos + l_take;
    END LOOP;

    RETURN bxor(l_crc, TO_NUMBER('FFFFFFFF','XXXXXXXX'));
  END;

BEGIN
  ----------------------------------------------------------------------------
  -- Guards
  ----------------------------------------------------------------------------
  IF NOT g_zip_open THEN
    fail('ZIP is not open. Call ZIP_BEGIN first.');
  END IF;

  IF g_zip_entry_name IS NULL THEN
    fail('g_zip_entry_name is NULL');
  END IF;

  IF g_zip_entry_clob IS NULL THEN
    fail('g_zip_entry_clob is NULL');
  END IF;

  ----------------------------------------------------------------------------
  -- Normalize name + encode filename as UTF-8
  ----------------------------------------------------------------------------
  l_name_utf8 := REGEXP_REPLACE(g_zip_entry_name, '^[\/]+', '');
  l_name_raw  := UTL_I18N.STRING_TO_RAW(l_name_utf8, 'AL32UTF8');

  ----------------------------------------------------------------------------
  -- Convert CLOB -> BLOB (content encoding)
  ----------------------------------------------------------------------------
  l_charset_id := NLS_CHARSET_ID(NVL(g_zip_charset, 'AL32UTF8'));
  IF l_charset_id = 0 THEN
    fail('Unknown charset in g_zip_charset=' || g_zip_charset);
  END IF;

  DBMS_LOB.CREATETEMPORARY(l_blob, TRUE);

  DBMS_LOB.CONVERTTOBLOB(
    dest_lob     => l_blob,
    src_clob     => g_zip_entry_clob,
    amount       => DBMS_LOB.LOBMAXSIZE,
    dest_offset  => l_dest_offset,
    src_offset   => l_src_offset,
    blob_csid    => l_charset_id,
    lang_context => l_lang_ctx,
    warning      => l_warning
  );

  ----------------------------------------------------------------------------
  -- Compute sizes + CRC32
  ----------------------------------------------------------------------------
  l_uncomp_len   := DBMS_LOB.GETLENGTH(l_blob);
  l_crc          := crc32_blob(l_blob);
  l_local_offset := DBMS_LOB.GETLENGTH(g_zip_blob);
  l_dos          := dos_datetime(l_now);

  ----------------------------------------------------------------------------
  -- Local File Header (stored method 0)
  ----------------------------------------------------------------------------
  blob_append(g_zip_blob, HEXTORAW('504B0304'));
  blob_append(g_zip_blob, le2(20));
  blob_append(g_zip_blob, le2(0));
  blob_append(g_zip_blob, le2(0));
  blob_append(g_zip_blob, le2(MOD(TRUNC(l_dos), 65536)));
  blob_append(g_zip_blob, le2(TRUNC(l_dos / 65536)));
  blob_append(g_zip_blob, le4(l_crc));
  blob_append(g_zip_blob, le4(l_uncomp_len));
  blob_append(g_zip_blob, le4(l_uncomp_len));
  blob_append(g_zip_blob, le2(UTL_RAW.LENGTH(l_name_raw)));
  blob_append(g_zip_blob, le2(0));
  blob_append(g_zip_blob, l_name_raw);
  blob_append_blob(g_zip_blob, l_blob);

  ----------------------------------------------------------------------------
  -- Record entry for central directory
  ----------------------------------------------------------------------------
  g_zip_entry_count := g_zip_entry_count + 1;

  g_zip_entries(g_zip_entry_count).name_utf8    := l_name_utf8;
  g_zip_entries(g_zip_entry_count).crc32        := l_crc;
  g_zip_entries(g_zip_entry_count).comp_size    := l_uncomp_len;
  g_zip_entries(g_zip_entry_count).uncomp_size  := l_uncomp_len;
  g_zip_entries(g_zip_entry_count).local_offset := l_local_offset;
  g_zip_entries(g_zip_entry_count).mod_dos_time := l_dos;
  g_zip_entries(g_zip_entry_count).method       := 0;

  xx_block_log_info('ZIP_ADD_CLOB', 'Added '||l_name_utf8||' bytes='||l_uncomp_len);

  ----------------------------------------------------------------------------
  -- Cleanup temp content blob
  ----------------------------------------------------------------------------
  IF DBMS_LOB.ISTEMPORARY(l_blob) = 1 THEN
    DBMS_LOB.FREETEMPORARY(l_blob);
  END IF;
END;
