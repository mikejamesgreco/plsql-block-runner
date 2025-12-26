-- MAIN: XX_BLOCK_MAIN_HTTP_CALL_1.sql
-- PURPOSE:
--   Generic MAIN that performs a single HTTP / HTTPS REST call using
--   xx_http_call (from XX_BLOCK_HTTP_1.sql).
--
--   Supports:
--     - Standard REST calls (GET / POST / PUT / DELETE / PATCH)
--     - Text bodies (CLOB)
--     - Binary bodies (Base64 → BLOB)
--     - Multipart/form-data requests (optional, backward-compatible)
--
-- EXPECTED INPUT JSON (standard request example):
-- {
--   "request": {
--     "protocol": "https",
--     "host": "postman-echo.com",
--     "port": 443,
--     "path": "/get",
--     "url": null,
--     "verb": "GET",
--     "url_params": { "foo":"bar" },
--     "headers": { "x-demo":"1" },
--     "body_text": null,
--     "body_base64": null,
--     "content_type": null,
--     "resp_mode": "TEXT",
--     "timeout_seconds": 60
--   },
--   "auth": {
--     "type": "NONE",
--     "config": null,
--     "wallet_path": null,
--     "wallet_password": null
--   }
-- }
--
-- OPTIONAL MULTIPART REQUEST FORMAT (multipart/form-data):
--
-- If "multipart" is supplied, MAIN will:
--   - Build a multipart/form-data payload
--   - Generate a boundary automatically
--   - Send the request body as BLOB
--   - Set Content-Type to multipart/form-data with boundary
--
-- Existing fields (body_text / body_base64) are ignored when multipart is used.
--
-- {
--   "request": {
--     "protocol": "https",
--     "host": "postman-echo.com",
--     "port": 443,
--     "path": "/post",
--     "verb": "POST",
--     "headers": { "x-demo":"1" },
--     "resp_mode": "TEXT",
--     "timeout_seconds": 60,
--
--     "multipart": {
--       "parts": [
--         {
--           "name": "metadata",
--           "content_type": "application/json",
--           "text": "{ \"id\": 123, \"type\": \"demo\" }"
--         },
--         {
--           "name": "file",
--           "filename": "example.txt",
--           "content_type": "text/plain",
--           "base64": "SGVsbG8gV29ybGQK"
--         }
--       ]
--     }
--   },
--   "auth": {
--     "type": "NONE",
--     "config": null,
--     "wallet_path": null,
--     "wallet_password": null
--   }
-- }
--
-- NOTES:
--   - Multipart support is optional and fully backward-compatible.
--   - Only one request body mode is used per call:
--       * multipart
--       * OR body_text
--       * OR body_base64
--   - Multipart payloads are constructed as BLOBs for binary safety.

DECLARE
  l_in_root      JSON_OBJECT_T;
  l_req_obj      JSON_OBJECT_T;
  l_auth_obj     JSON_OBJECT_T;

  l_protocol     VARCHAR2(10);
  l_host         VARCHAR2(4000);
  l_port         NUMBER;
  l_path         VARCHAR2(4000);
  l_url          VARCHAR2(4000);
  l_verb         VARCHAR2(20);

  l_url_params_json CLOB;
  l_headers_json    CLOB;

  l_body_text    CLOB;
  l_body_b64     CLOB;
  l_body_blob    BLOB;

  l_multipart_parts_json CLOB;
  l_multipart_boundary   VARCHAR2(4000);

  l_content_type VARCHAR2(4000);
  l_resp_mode    VARCHAR2(20);
  l_timeout      NUMBER;

  l_auth_type    VARCHAR2(20);
  l_auth_json    CLOB;
  l_wallet_path  VARCHAR2(4000);
  l_wallet_pwd   VARCHAR2(4000);

  l_status       NUMBER;
  l_reason       VARCHAR2(4000);
  l_resp_headers CLOB;
  l_resp_text    CLOB;
  l_resp_blob    BLOB;

  l_out_root     JSON_OBJECT_T;

  FUNCTION elem_to_clob(p_any JSON_ELEMENT_T) RETURN CLOB IS
    l_c CLOB;
    l_trim VARCHAR2(20);
  BEGIN
    IF p_any IS NULL THEN
      RETURN NULL;
    END IF;

    l_c := p_any.to_clob;

    -- JSON NULL often serializes as literal text "null"
    l_trim := LOWER(TRIM(DBMS_LOB.substr(l_c, 20, 1)));
    IF l_trim = 'null' THEN
      RETURN NULL;
    END IF;

    RETURN l_c;
  EXCEPTION
    WHEN OTHERS THEN
      RETURN NULL;
  END;

  FUNCTION b64_to_blob(p_b64 CLOB) RETURN BLOB IS
    l_clean CLOB;
    l_pos   PLS_INTEGER := 1;
    l_len   PLS_INTEGER;
    l_chunk VARCHAR2(32767);
    l_raw   RAW(32767);
    l_out   BLOB;
  BEGIN
    IF p_b64 IS NULL OR DBMS_LOB.getlength(p_b64) = 0 THEN
      RETURN NULL;
    END IF;

    DBMS_LOB.createtemporary(l_out, TRUE);

    -- strip whitespace/newlines
    DBMS_LOB.createtemporary(l_clean, TRUE);
    l_len := DBMS_LOB.getlength(p_b64);
    WHILE l_pos <= l_len LOOP
      l_chunk := DBMS_LOB.substr(p_b64, LEAST(32767, l_len - l_pos + 1), l_pos);
      l_chunk := REPLACE(REPLACE(REPLACE(l_chunk, CHR(10), ''), CHR(13), ''), ' ', '');
      DBMS_LOB.writeappend(l_clean, LENGTH(l_chunk), l_chunk);
      l_pos := l_pos + 32767;
    END LOOP;

    l_pos := 1;
    l_len := DBMS_LOB.getlength(l_clean);

    -- decode in safe chunks (base64 decode wants multiples of 4; 32000 is usually fine)
    WHILE l_pos <= l_len LOOP
      l_chunk := DBMS_LOB.substr(l_clean, LEAST(32000, l_len - l_pos + 1), l_pos);
      l_raw := UTL_ENCODE.base64_decode(UTL_RAW.cast_to_raw(l_chunk));
      DBMS_LOB.writeappend(l_out, UTL_RAW.length(l_raw), l_raw);
      l_pos := l_pos + 32000;
    END LOOP;

    RETURN l_out;
  END;

BEGIN
  l_in_root  := JSON_OBJECT_T.parse(l_inputs_json);
  l_req_obj  := TREAT(l_in_root.get('request') AS JSON_OBJECT_T);
  l_auth_obj := TREAT(l_in_root.get('auth')    AS JSON_OBJECT_T);

  -- request fields
  l_protocol := NVL(CASE WHEN l_req_obj.has('protocol') THEN l_req_obj.get_string('protocol') ELSE NULL END, 'https');
  l_host     := CASE WHEN l_req_obj.has('host') THEN l_req_obj.get_string('host') ELSE NULL END;
  l_port     := CASE WHEN l_req_obj.has('port') THEN l_req_obj.get_number('port') ELSE NULL END;
  l_path     := CASE WHEN l_req_obj.has('path') THEN l_req_obj.get_string('path') ELSE NULL END;
  l_url      := CASE WHEN l_req_obj.has('url')  THEN l_req_obj.get_string('url')  ELSE NULL END;
  l_verb     := NVL(CASE WHEN l_req_obj.has('verb') THEN l_req_obj.get_string('verb') ELSE NULL END, 'GET');

  l_url_params_json := elem_to_clob(l_req_obj.get('url_params'));
  l_headers_json    := elem_to_clob(l_req_obj.get('headers'));

  l_multipart_parts_json := elem_to_clob(l_req_obj.get('multipart_parts'));
  l_multipart_boundary   := CASE WHEN l_req_obj.has('multipart_boundary') THEN l_req_obj.get_string('multipart_boundary') ELSE NULL END;

  IF l_multipart_parts_json IS NOT NULL AND DBMS_LOB.getlength(l_multipart_parts_json) > 0 THEN
    -- Build multipart/form-data payload using HTTP block helper
    xx_http_build_multipart_form_data(
      p_parts_json   => l_multipart_parts_json,
      x_content_type => l_content_type,
      x_body_blob    => l_body_blob,
      p_boundary     => l_multipart_boundary
    );
    l_body_text := NULL;
    l_body_b64  := NULL;
  ELSE
    l_body_text := elem_to_clob(l_req_obj.get('body_text'));
    l_body_b64  := elem_to_clob(l_req_obj.get('body_base64'));
    l_body_blob := b64_to_blob(l_body_b64);
  END IF;

  IF l_content_type IS NULL THEN
    l_content_type := CASE WHEN l_req_obj.has('content_type') THEN l_req_obj.get_string('content_type') ELSE NULL END;
  END IF;
  l_resp_mode    := NVL(CASE WHEN l_req_obj.has('resp_mode') THEN l_req_obj.get_string('resp_mode') ELSE NULL END, 'TEXT');
  l_timeout      := NVL(CASE WHEN l_req_obj.has('timeout_seconds') THEN l_req_obj.get_number('timeout_seconds') ELSE NULL END, 60);

  -- auth fields
  l_auth_type   := NVL(CASE WHEN l_auth_obj.has('type') THEN l_auth_obj.get_string('type') ELSE NULL END, 'NONE');
  l_auth_json   := elem_to_clob(l_auth_obj.get('config'));
  l_wallet_path := CASE WHEN l_auth_obj.has('wallet_path') THEN l_auth_obj.get_string('wallet_path') ELSE NULL END;
  l_wallet_pwd  := CASE WHEN l_auth_obj.has('wallet_password') THEN l_auth_obj.get_string('wallet_password') ELSE NULL END;

  xx_http_call(
    p_protocol              => l_protocol,
    p_host                  => l_host,
    p_port                  => l_port,
    p_path                  => l_path,
    p_url                   => l_url,
    p_verb                  => l_verb,
    p_auth_type             => l_auth_type,
    p_auth_json             => l_auth_json,
    p_wallet_path           => l_wallet_path,
    p_wallet_password       => l_wallet_pwd,
    p_url_params_json       => l_url_params_json,
    p_headers_json          => l_headers_json,
    p_body_clob             => l_body_text,
    p_body_blob             => l_body_blob,
    p_req_content_type      => l_content_type,
    p_resp_mode             => l_resp_mode,
    p_timeout_seconds       => l_timeout,
    x_status_code           => l_status,
    x_reason_phrase         => l_reason,
    x_response_headers_json => l_resp_headers,
    x_response_clob         => l_resp_text,
    x_response_blob         => l_resp_blob
  );

  -- Build output JSON
  l_out_root := JSON_OBJECT_T();
  l_out_root.put('status', 'OK');
  l_out_root.put('http_status', l_status);
  l_out_root.put('reason', NVL(l_reason,''));
  -- response headers: try to parse JSON array; if anything is off, fall back to raw string
  BEGIN
    l_out_root.put('response_headers', JSON_ARRAY_T.parse(NVL(l_resp_headers,'[]')));
  EXCEPTION
    WHEN OTHERS THEN
      l_out_root.put('response_headers_parse_error', SQLERRM);
      l_out_root.put('response_headers_raw', NVL(DBMS_LOB.substr(l_resp_headers, 32767, 1), ''));
  END;
  IF UPPER(l_resp_mode) = 'BINARY' THEN
    l_out_root.put('response_bytes', CASE WHEN l_resp_blob IS NULL THEN 0 ELSE DBMS_LOB.getlength(l_resp_blob) END);
  ELSE
    l_out_root.put('response_text', NVL(l_resp_text,''));
  END IF;

  l_result_json := l_out_root.to_clob;
  :v_retcode := 0;
  :v_errbuf  := NULL;

EXCEPTION
  WHEN OTHERS THEN
    -- No JSON_OBJECT(...) SQL constructor here (avoids PLS-00684 issues)
    l_result_json :=
      '{'||
      '"status":"ERROR",'||
      '"sqlerrm":'    || xx_http_json_quote(SQLERRM) || ','||
      '"backtrace":'  || xx_http_json_quote(DBMS_UTILITY.format_error_backtrace) ||
      '}';

    :v_retcode := 2;
    :v_errbuf  := SUBSTR(SQLERRM, 1, 4000);
END;
