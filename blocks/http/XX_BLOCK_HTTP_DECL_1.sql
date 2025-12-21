-- DECL: XX_BLOCK_HTTP_DECL_1.sql
-- PURPOSE:
--   Shared HTTP/REST configuration, request/response state, and common types
--   used by the UTL_HTTP helper block(s).
--
-- NOTES:
--   - DECL files must contain declarations only (types/constants/variables).
--   - No executable statements, procedures, or functions.
--   - Authentication secrets are expected to be passed in by MAIN (typically
--     within JSON inputs) and are NOT persisted here beyond the duration of a run.
--
-- PROVIDES:
--   g_http_last_status_code
--   g_http_last_reason_phrase
--   g_http_last_response_headers_json
--   g_http_last_response_clob
--   g_http_last_response_blob
--   g_http_last_error_detail   (UTL_HTTP.get_detailed_sqlerrm snapshot when available)
--   xx_http_header_rec, xx_http_header_tab

  ----------------------------------------------------------------------
  -- Response snapshot (last call)
  ----------------------------------------------------------------------
  g_http_last_status_code           NUMBER;
  g_http_last_reason_phrase         VARCHAR2(4000);
  g_http_last_response_headers_json CLOB;
  g_http_last_response_clob         CLOB;
  g_http_last_response_blob         BLOB;

  ----------------------------------------------------------------------
  -- Error snapshot (last failure)
  ----------------------------------------------------------------------
  g_http_last_error_detail          VARCHAR2(4000);

  ----------------------------------------------------------------------
  -- Simple header collection types (optional use by MAIN/BLOCK)
  ----------------------------------------------------------------------
  TYPE xx_http_header_rec IS RECORD(
    name  VARCHAR2(256),
    value VARCHAR2(4000)
  );

  TYPE xx_http_header_tab IS TABLE OF xx_http_header_rec INDEX BY PLS_INTEGER;
