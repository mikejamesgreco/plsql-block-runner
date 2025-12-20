-- BLOCK: XX_BLOCK_ZIP_FINISH_1.sql
-- PURPOSE:
--   Finalize the in-memory ZIP archive by generating and appending the
--   Central Directory records for all entries added so far, followed by
--   the End Of Central Directory (EOCD) record. After this block runs,
--   g_zip_blob contains a complete, valid ZIP file suitable for writing
--   to disk or returning to a caller.
--
-- DEFINES:
--   procedure xx_block_zip_finish
--
-- INPUTS:
--   None (direct parameters).
--   Requires the following global ZIP state (declared/populated by other ZIP blocks):
--     - g_zip_open        must be TRUE (ZIP_BEGIN was called and ZIP not yet finished)
--     - g_zip_blob        contains local file headers + file data for entries
--     - g_zip_cd_blob     temporary BLOB buffer for central directory assembly
--     - g_zip_entry_count number of entries recorded
--     - g_zip_entries(...) metadata for each entry (name, crc32, sizes, offsets, timestamps, method)
--
-- OUTPUTS:
--   None (direct parameters).
--   Updates the following global ZIP state:
--     - g_zip_cd_blob   appended with Central Directory File Header (CDFH) records
--     - g_zip_blob      appended with g_zip_cd_blob + EOCD record (final ZIP bytes)
--     - g_zip_open      set to FALSE (ZIP is closed/finalized)
--
-- SIDE EFFECTS:
--   - Appends binary ZIP directory structures to g_zip_cd_blob and g_zip_blob.
--   - Emits log output via xx_block_log_info.
--   - Leaves g_zip_blob containing a finalized ZIP file; no further ZIP_ADD_* calls
--     should be made unless ZIP_BEGIN is called again.
--
-- ERRORS:
--   - Raises -20001 if ZIP is not open (g_zip_open != TRUE).
--   - May propagate standard Oracle errors related to LOB operations, RAW conversion,
--     or memory limits during Central Directory construction and append operations.
--
-- NOTES:
--   - This implementation writes a classic EOCD record (no ZIP64 support).
--     Very large ZIPs (sizes/offsets beyond 32-bit limits) are not supported.
--   - Entry names are encoded as UTF-8 bytes (AL32UTF8 via UTL_I18N.STRING_TO_RAW).
--   - Central Directory offsets and sizes are written in little-endian format.

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
