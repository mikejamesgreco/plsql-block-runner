-- MAIN: XX_BLOCK_MAIN_HTTP_POST_JSON_2.sql
-- PURPOSE:
--   Common REST pattern test MAIN:
--     - POST with JSON body (CLOB)
--     - response as TEXT (JSON returned as text)
--   Designed to use the SAME request/auth envelope as XX_BLOCK_MAIN_HTTP_CALL_1.sql
--   but defaults to an HTTP POST JSON test if fields are omitted.
--
-- DEFAULT TARGET (when not provided):
--   http://httpbin.org/post
--
-- EXPECTED INPUT JSON (same envelope as XX_BLOCK_MAIN_HTTP_CALL_1.sql):
-- {
--   "request": {
--     "protocol": "http",
--     "host": "httpbin.org",
--     "port": 80,
--     "path": "/post",
--     "url": null,
--     "verb": "POST",
--     "url_params": { "foo":"bar" },
--     "headers": { "x-demo":"1" },
--     "body_text": "{\"hello\":\"world\"}",
--     "body_base64": null,
--     "content_type": "application/json",
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

    DBMS_LOB.freetemporary(l_clean);
    RETURN l_out;
  EXCEPTION
    WHEN OTHERS THEN
      IF DBMS_LOB.istemporary(l_clean) = 1 THEN
        DBMS_LOB.freetemporary(l_clean);
      END IF;
      IF DBMS_LOB.istemporary(l_out) = 1 THEN
        DBMS_LOB.freetemporary(l_out);
      END IF;
      RETURN NULL;
  END;

BEGIN
  l_in_root := JSON_OBJECT_T.parse(l_inputs_json);

  -- request/auth objects
  l_req_obj  := TREAT(l_in_root.get('request') AS JSON_OBJECT_T);
  l_auth_obj := TREAT(l_in_root.get('auth')    AS JSON_OBJECT_T);

  -- request fields (defaults geared for "POST JSON in/out" over HTTP)
  l_protocol := NVL(l_req_obj.get_string('protocol'), 'http');
  l_host     := NVL(l_req_obj.get_string('host'),     'httpbin.org');
  l_port     := NVL(l_req_obj.get_number('port'),     80);
  l_path     := NVL(l_req_obj.get_string('path'),     '/post');
  l_url      := l_req_obj.get_string('url');
  l_verb     := NVL(l_req_obj.get_string('verb'),     'POST');

  l_url_params_json := elem_to_clob(l_req_obj.get('url_params'));
  l_headers_json    := elem_to_clob(l_req_obj.get('headers'));

  l_body_text    := elem_to_clob(l_req_obj.get('body_text'));
  l_body_b64     := elem_to_clob(l_req_obj.get('body_base64'));
  l_content_type := NVL(l_req_obj.get_string('content_type'), 'application/json');
  l_resp_mode    := NVL(l_req_obj.get_string('resp_mode'),    'TEXT');
  l_timeout      := NVL(l_req_obj.get_number('timeout_seconds'), 60);

  IF l_body_text IS NULL OR DBMS_LOB.getlength(l_body_text) = 0 THEN
    -- default JSON payload if not provided
    l_body_text := '{"hello":"world","source":"XX_BLOCK_MAIN_HTTP_POST_JSON_2"}';
  END IF;

  IF l_body_b64 IS NOT NULL AND DBMS_LOB.getlength(l_body_b64) > 0 THEN
    l_body_blob := b64_to_blob(l_body_b64);
  ELSE
    l_body_blob := NULL;
  END IF;

  -- auth fields (default NONE)
  IF l_auth_obj IS NOT NULL THEN
    l_auth_type   := NVL(l_auth_obj.get_string('type'), 'NONE');
    l_auth_json   := elem_to_clob(l_auth_obj.get('config'));
    l_wallet_path := l_auth_obj.get_string('wallet_path');
    l_wallet_pwd  := l_auth_obj.get_string('wallet_password');
  ELSE
    l_auth_type   := 'NONE';
    l_auth_json   := NULL;
    l_wallet_path := NULL;
    l_wallet_pwd  := NULL;
  END IF;

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

  l_out_root := JSON_OBJECT_T();
  l_out_root.put('status', 'OK');
  l_out_root.put('http_status', l_status);
  l_out_root.put('reason', NVL(l_reason,''));

  BEGIN
    l_out_root.put('response_headers', JSON_ARRAY_T.parse(NVL(l_resp_headers,'[]')));
  EXCEPTION
    WHEN OTHERS THEN
      l_out_root.put('response_headers_parse_error', SQLERRM);
      l_out_root.put('response_headers_raw', NVL(DBMS_LOB.substr(l_resp_headers, 32767, 1), ''));
  END;

  l_out_root.put('response_text', NVL(l_resp_text,''));

  l_result_json := l_out_root.to_clob;
  :v_retcode := 0;
  :v_errbuf  := NULL;

EXCEPTION
  WHEN OTHERS THEN
    l_result_json :=
      '{' ||
      '"status":"ERROR",' ||
      '"sqlerrm":'   || xx_http_json_quote(SQLERRM) || ',' ||
      '"backtrace":' || xx_http_json_quote(DBMS_UTILITY.format_error_backtrace) ||
      '}';

    :v_retcode := 2;
    :v_errbuf  := SUBSTR(SQLERRM, 1, 4000);
END;
