-- XX_BLOCK_ZIP_FINISH_1.sql
-- Defines: xx_block_zip_finish

PROCEDURE xx_block_zip_finish IS

  l_cd_start NUMBER;
  l_cd_size  NUMBER;
  l_name_raw RAW(32767);
  
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

BEGIN
  IF NOT g_zip_open THEN
    RAISE_APPLICATION_ERROR(-20001, 'ZIP_FINISH | ZIP not open');
  END IF;

  -- Build central directory records into g_zip_cd_blob
  FOR i IN 1..g_zip_entry_count LOOP
    l_name_raw := UTL_I18N.STRING_TO_RAW(g_zip_entries(i).name_utf8, 'AL32UTF8');

    blob_append(g_zip_cd_blob, HEXTORAW('504B0102')); -- CDFH signature
    blob_append(g_zip_cd_blob, le2(20)); -- version made by
    blob_append(g_zip_cd_blob, le2(20)); -- version needed
    blob_append(g_zip_cd_blob, le2(0));  -- flags
    blob_append(g_zip_cd_blob, le2(g_zip_entries(i).method));
    blob_append(g_zip_cd_blob, le2(MOD(TRUNC(g_zip_entries(i).mod_dos_time), 65536))); -- time
    blob_append(g_zip_cd_blob, le2(TRUNC(g_zip_entries(i).mod_dos_time / 65536)));     -- date
    blob_append(g_zip_cd_blob, le4(g_zip_entries(i).crc32));
    blob_append(g_zip_cd_blob, le4(g_zip_entries(i).comp_size));
    blob_append(g_zip_cd_blob, le4(g_zip_entries(i).uncomp_size));
    blob_append(g_zip_cd_blob, le2(UTL_RAW.LENGTH(l_name_raw))); -- name len
    blob_append(g_zip_cd_blob, le2(0)); -- extra len
    blob_append(g_zip_cd_blob, le2(0)); -- comment len
    blob_append(g_zip_cd_blob, le2(0)); -- disk #
    blob_append(g_zip_cd_blob, le2(0)); -- internal attrs
    blob_append(g_zip_cd_blob, le4(0)); -- external attrs
    blob_append(g_zip_cd_blob, le4(g_zip_entries(i).local_offset));
    blob_append(g_zip_cd_blob, l_name_raw);
  END LOOP;

  l_cd_start := DBMS_LOB.GETLENGTH(g_zip_blob);
  DBMS_LOB.APPEND(g_zip_blob, g_zip_cd_blob);
  l_cd_size := DBMS_LOB.GETLENGTH(g_zip_cd_blob);

  -- EOCD
  blob_append(g_zip_blob, HEXTORAW('504B0506'));
  blob_append(g_zip_blob, le2(0)); -- disk #
  blob_append(g_zip_blob, le2(0)); -- cd start disk #
  blob_append(g_zip_blob, le2(g_zip_entry_count));
  blob_append(g_zip_blob, le2(g_zip_entry_count));
  blob_append(g_zip_blob, le4(l_cd_size));
  blob_append(g_zip_blob, le4(l_cd_start));
  blob_append(g_zip_blob, le2(0)); -- comment len

  g_zip_open := FALSE;

  xx_block_log_info('ZIP_FINISH', 'ZIP finalized. entries='||g_zip_entry_count||' cd_bytes='||l_cd_size);
END;
