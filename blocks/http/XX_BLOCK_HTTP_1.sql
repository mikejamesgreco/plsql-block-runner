-- BLOCK: XX_BLOCK_HTTP_1.sql
-- PURPOSE:
--   Generic REST/HTTP client helper built on UTL_HTTP.
--
-- SUPPORTS:
--   - HTTP and HTTPS (wallet optional/required depending on target)
--   - Verbs: GET, POST, PUT, PATCH, DELETE, HEAD (any string accepted)
--   - URL query parameters (provided as JSON)
--   - Request headers (provided as JSON)
--   - Request body as CLOB (text) or BLOB (binary)
--   - Response body as CLOB (text) or BLOB (binary)
--   - Auth: NONE, BASIC, OAUTH (client credentials)
--
-- IMPORTANT LIMITATIONS / NOTES:
--   - HTTPS certificate validation depends on the Oracle wallet you provide.
--   - This block does not persist secrets; auth config is passed in by MAIN.
--   - OAuth implementation is "client_credentials" token retrieval; extend as needed.
--
-- DEFINES:
--   procedure xx_http_call
--
-- INPUTS (xx_http_call):
--   p_protocol            'http' or 'https' (default 'https')
--   p_host                host name or IP (required unless p_url is supplied)
--   p_port                optional port (NULL -> default 80/443)
--   p_path                path like '/api/v1/items' (optional if p_url supplied)
--   p_url                 full URL (optional; if supplied it overrides protocol/host/port/path)
--   p_verb                HTTP method (GET/POST/PUT/PATCH/DELETE/...)
--   p_auth_type           'NONE' | 'BASIC' | 'OAUTH'
--   p_auth_json           CLOB JSON auth config (structure depends on auth type; see below)
--   p_wallet_path         wallet path (e.g. 'file:/.../wallet') optional
--   p_wallet_password     wallet password optional
--   p_url_params_json     CLOB JSON of query params (object or array of {name,value})
--   p_headers_json        CLOB JSON of headers (object or array of {name,value})
--   p_body_clob           request body text (optional)
--   p_body_blob           request body binary (optional)
--   p_req_content_type    request Content-Type (optional; default based on body)
--   p_resp_mode           'TEXT' or 'BINARY' (default 'TEXT')
--   p_timeout_seconds     UTL_HTTP transfer timeout (default 60)
--
-- OUTPUTS (xx_http_call):
--   x_status_code         HTTP status code
--   x_reason_phrase       reason phrase
--   x_response_headers_json  JSON array of {name,value}
--   x_response_clob       response body as CLOB (TEXT mode)
--   x_response_blob       response body as BLOB (BINARY mode)
--
-- AUTH JSON SHAPES:
--   BASIC:
--     { "username":"...", "password":"..." }
--
--   OAUTH (client_credentials):
--     {
--       "token_url":"https://.../oauth2/token",
--       "client_id":"...",
--       "client_secret":"...",
--       "scope":"optional scope string",
--       "audience":"optional",
--       "extra_form_params": { "k":"v", ... }   -- optional
--     }
--
-- WALLET:
--   - wallet_path/password can be passed via p_wallet_* or inside p_auth_json:
--       { "wallet_path":"file:/...", "wallet_password":"..." , ... }
--   - p_wallet_* wins if provided.

  ----------------------------------------------------------------------
  -- helpers
  ----------------------------------------------------------------------

  FUNCTION xx_http_norm(p_in VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    RETURN UPPER(TRIM(p_in));
  END;

  PROCEDURE xx_http_clob_append(p_clob IN OUT NOCOPY CLOB, p_text VARCHAR2) IS
  BEGIN
    IF p_text IS NULL THEN
      RETURN;
    END IF;

    IF p_clob IS NULL THEN
      DBMS_LOB.createtemporary(p_clob, TRUE);
    END IF;

    DBMS_LOB.writeappend(p_clob, LENGTH(p_text), p_text);
  END;

  PROCEDURE xx_http_blob_append_raw(p_blob IN OUT NOCOPY BLOB, p_raw RAW) IS
  BEGIN
    IF p_raw IS NULL THEN
      RETURN;
    END IF;

    IF p_blob IS NULL THEN
      DBMS_LOB.createtemporary(p_blob, TRUE);
    END IF;

    DBMS_LOB.writeappend(p_blob, UTL_RAW.length(p_raw), p_raw);
  END;

  FUNCTION xx_http_escape(p_value VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    RETURN UTL_URL.escape(NVL(p_value,''), TRUE);
  END;

  FUNCTION xx_http_b64(p_raw RAW) RETURN VARCHAR2 IS
    l_b64 RAW(32767);
    l_out VARCHAR2(32767);
  BEGIN
    IF p_raw IS NULL THEN
      RETURN NULL;
    END IF;

    l_b64 := UTL_ENCODE.base64_encode(p_raw);
    l_out := UTL_RAW.cast_to_varchar2(l_b64);

    -- remove CR/LF inserted by encoder
    l_out := REPLACE(REPLACE(l_out, CHR(10), ''), CHR(13), '');
    RETURN l_out;
  END;

  FUNCTION xx_http_get_json_string(p_obj JSON_OBJECT_T, p_key VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    IF p_obj IS NULL OR p_key IS NULL OR NOT p_obj.has(p_key) THEN
      RETURN NULL;
    END IF;
    RETURN p_obj.get_string(p_key);
  EXCEPTION
    WHEN OTHERS THEN
      RETURN NULL;
  END;

  ----------------------------------------------------------------------
  -- Build query string from JSON
  -- Accepts:
  --   object: {"a":"1","b":"2"}
  --   array : [{"name":"a","value":"1"},{"name":"b","value":"2"}]
  ----------------------------------------------------------------------
  FUNCTION xx_http_build_query(p_params_json CLOB) RETURN VARCHAR2 IS
    l_obj  JSON_OBJECT_T;
    l_arr  JSON_ARRAY_T;
    l_q    VARCHAR2(32767);
    l_sep  VARCHAR2(1) := '?';
    l_k    VARCHAR2(4000);
    l_v    VARCHAR2(4000);
    l_pair VARCHAR2(32767);
  BEGIN
    IF p_params_json IS NULL OR DBMS_LOB.getlength(p_params_json) = 0 THEN
      RETURN NULL;
    END IF;

    -- Try object form first
    BEGIN
      l_obj := JSON_OBJECT_T.parse(p_params_json);
      DECLARE
        l_keys JSON_KEY_LIST;
      BEGIN
        l_keys := l_obj.get_keys;
        FOR i IN 1 .. l_keys.count LOOP
          l_k := l_keys(i);
          BEGIN
            l_v := l_obj.get_string(l_k);
          EXCEPTION
            WHEN OTHERS THEN
              l_v := l_obj.get(l_k).to_string;
          END;

          l_pair := l_sep || xx_http_escape(l_k) || '=' || xx_http_escape(l_v);
          l_q := NVL(l_q,'') || l_pair;
          l_sep := '&';
        END LOOP;
      END;

      RETURN l_q;
    EXCEPTION
      WHEN OTHERS THEN
        NULL;
    END;

    -- Fallback: array form
    l_arr := JSON_ARRAY_T.parse(p_params_json);
    FOR i IN 0 .. l_arr.get_size - 1 LOOP
      DECLARE
        l_item JSON_OBJECT_T := TREAT(l_arr.get(i) AS JSON_OBJECT_T);
      BEGIN
        l_k := xx_http_get_json_string(l_item, 'name');
        l_v := xx_http_get_json_string(l_item, 'value');

        IF l_k IS NOT NULL THEN
          l_pair := l_sep || xx_http_escape(l_k) || '=' || xx_http_escape(l_v);
          l_q := NVL(l_q,'') || l_pair;
          l_sep := '&';
        END IF;
      END;
    END LOOP;

    RETURN l_q;
  EXCEPTION
    WHEN OTHERS THEN
      RETURN NULL;
  END;

  ----------------------------------------------------------------------
  -- Apply headers from JSON
  -- Accepts:
  --   object: {"Header":"Value"}
  --   array : [{"name":"Header","value":"Value"}]
  ----------------------------------------------------------------------
  PROCEDURE xx_http_apply_headers(
    p_req          IN OUT NOCOPY UTL_HTTP.req,
    p_headers_json IN CLOB
  ) IS
    l_obj JSON_OBJECT_T;
    l_arr JSON_ARRAY_T;
    l_k   VARCHAR2(256);
    l_v   VARCHAR2(4000);
  BEGIN
    IF p_headers_json IS NULL OR DBMS_LOB.getlength(p_headers_json) = 0 THEN
      RETURN;
    END IF;

    -- object form
    BEGIN
      l_obj := JSON_OBJECT_T.parse(p_headers_json);
      DECLARE
        l_keys JSON_KEY_LIST;
      BEGIN
        l_keys := l_obj.get_keys;
        FOR i IN 1 .. l_keys.count LOOP
          l_k := l_keys(i);
          BEGIN
            l_v := l_obj.get_string(l_k);
          EXCEPTION
            WHEN OTHERS THEN
              l_v := l_obj.get(l_k).to_string;
          END;
          UTL_HTTP.set_header(p_req, l_k, NVL(l_v,''));
        END LOOP;
      END;
      RETURN;
    EXCEPTION
      WHEN OTHERS THEN
        NULL;
    END;

    -- array form
    l_arr := JSON_ARRAY_T.parse(p_headers_json);
    FOR i IN 0 .. l_arr.get_size - 1 LOOP
      DECLARE
        l_item JSON_OBJECT_T := TREAT(l_arr.get(i) AS JSON_OBJECT_T);
      BEGIN
        l_k := xx_http_get_json_string(l_item, 'name');
        l_v := xx_http_get_json_string(l_item, 'value');
        IF l_k IS NOT NULL THEN
          UTL_HTTP.set_header(p_req, l_k, NVL(l_v,''));
        END IF;
      END;
    END LOOP;
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END;

  ----------------------------------------------------------------------
  -- Wallet selection (p_wallet_* overrides auth_json fields)
  ----------------------------------------------------------------------
  FUNCTION xx_http_get_wallet_path(p_auth_json CLOB, p_wallet_path VARCHAR2) RETURN VARCHAR2 IS
    l_obj JSON_OBJECT_T;
  BEGIN
    IF p_wallet_path IS NOT NULL THEN
      RETURN p_wallet_path;
    END IF;

    IF p_auth_json IS NULL THEN
      RETURN NULL;
    END IF;

    l_obj := JSON_OBJECT_T.parse(p_auth_json);
    RETURN xx_http_get_json_string(l_obj, 'wallet_path');
  EXCEPTION
    WHEN OTHERS THEN
      RETURN NULL;
  END;

  FUNCTION xx_http_get_wallet_password(p_auth_json CLOB, p_wallet_password VARCHAR2) RETURN VARCHAR2 IS
    l_obj JSON_OBJECT_T;
  BEGIN
    IF p_wallet_password IS NOT NULL THEN
      RETURN p_wallet_password;
    END IF;

    IF p_auth_json IS NULL THEN
      RETURN NULL;
    END IF;

    l_obj := JSON_OBJECT_T.parse(p_auth_json);
    RETURN xx_http_get_json_string(l_obj, 'wallet_password');
  EXCEPTION
    WHEN OTHERS THEN
      RETURN NULL;
  END;

  ----------------------------------------------------------------------
  -- Basic auth header: {"username":"...","password":"..."}
  ----------------------------------------------------------------------
  FUNCTION xx_http_basic_auth_header(p_auth_json CLOB) RETURN VARCHAR2 IS
    l_obj  JSON_OBJECT_T;
    l_user VARCHAR2(4000);
    l_pass VARCHAR2(4000);
    l_raw  RAW(32767);
  BEGIN
    IF p_auth_json IS NULL OR DBMS_LOB.getlength(p_auth_json) = 0 THEN
      RETURN NULL;
    END IF;

    l_obj  := JSON_OBJECT_T.parse(p_auth_json);
    l_user := xx_http_get_json_string(l_obj, 'username');
    l_pass := xx_http_get_json_string(l_obj, 'password');

    l_raw := UTL_RAW.cast_to_raw(NVL(l_user,'') || ':' || NVL(l_pass,''));
    RETURN 'Basic ' || xx_http_b64(l_raw);
  EXCEPTION
    WHEN OTHERS THEN
      RETURN NULL;
  END;

  ----------------------------------------------------------------------
  -- OAuth token retrieval (client_credentials)
  ----------------------------------------------------------------------
  FUNCTION xx_http_oauth_token(
    p_auth_json        CLOB,
    p_wallet_path      VARCHAR2,
    p_wallet_password  VARCHAR2,
    p_timeout_seconds  PLS_INTEGER
  ) RETURN VARCHAR2 IS
    l_obj           JSON_OBJECT_T;
    l_token_url     VARCHAR2(4000);
    l_client_id     VARCHAR2(4000);
    l_client_secret VARCHAR2(4000);
    l_scope         VARCHAR2(4000);
    l_audience      VARCHAR2(4000);

    l_form      CLOB;
    l_req       UTL_HTTP.req;
    l_resp      UTL_HTTP.resp;
    l_status    NUMBER;
    l_buf       VARCHAR2(32767);
    l_resp_clob CLOB;
    l_token     VARCHAR2(4000);
  BEGIN
    IF p_auth_json IS NULL OR DBMS_LOB.getlength(p_auth_json) = 0 THEN
      RETURN NULL;
    END IF;

    l_obj := JSON_OBJECT_T.parse(p_auth_json);
    l_token_url     := xx_http_get_json_string(l_obj, 'token_url');
    l_client_id     := xx_http_get_json_string(l_obj, 'client_id');
    l_client_secret := xx_http_get_json_string(l_obj, 'client_secret');
    l_scope         := xx_http_get_json_string(l_obj, 'scope');
    l_audience      := xx_http_get_json_string(l_obj, 'audience');

    IF l_token_url IS NULL THEN
      RETURN NULL;
    END IF;

    -- Wallet for HTTPS token call too
    IF LOWER(SUBSTR(l_token_url,1,5)) = 'https' AND p_wallet_path IS NOT NULL THEN
      UTL_HTTP.set_wallet(p_wallet_path, p_wallet_password);
    END IF;

    UTL_HTTP.set_transfer_timeout(NVL(p_timeout_seconds,60));

    DBMS_LOB.createtemporary(l_form, TRUE);
    xx_http_clob_append(l_form, 'grant_type=client_credentials');

    IF l_scope IS NOT NULL THEN
      xx_http_clob_append(l_form, '&scope=' || xx_http_escape(l_scope));
    END IF;

    IF l_audience IS NOT NULL THEN
      xx_http_clob_append(l_form, '&audience=' || xx_http_escape(l_audience));
    END IF;

    -- extra_form_params (optional)
    BEGIN
      IF l_obj.has('extra_form_params') THEN
        DECLARE
          l_extra JSON_OBJECT_T := TREAT(l_obj.get('extra_form_params') AS JSON_OBJECT_T);
          l_keys  JSON_KEY_LIST;
          l_k     VARCHAR2(4000);
          l_v     VARCHAR2(4000);
        BEGIN
          l_keys := l_extra.get_keys;
          FOR i IN 1 .. l_keys.count LOOP
            l_k := l_keys(i);
            BEGIN
              l_v := l_extra.get_string(l_k);
            EXCEPTION
              WHEN OTHERS THEN
                l_v := l_extra.get(l_k).to_string;
            END;
            xx_http_clob_append(l_form, '&' || xx_http_escape(l_k) || '=' || xx_http_escape(l_v));
          END LOOP;
        END;
      END IF;
    EXCEPTION
      WHEN OTHERS THEN
        NULL;
    END;

    l_req := UTL_HTTP.begin_request(l_token_url, 'POST', 'HTTP/1.1');

    -- Common pattern: client_id/secret via HTTP Basic
    IF l_client_id IS NOT NULL OR l_client_secret IS NOT NULL THEN
      UTL_HTTP.set_header(
        l_req,
        'Authorization',
        'Basic ' || xx_http_b64(UTL_RAW.cast_to_raw(NVL(l_client_id,'') || ':' || NVL(l_client_secret,'')))
      );
    END IF;

    UTL_HTTP.set_header(l_req, 'Content-Type', 'application/x-www-form-urlencoded');
    UTL_HTTP.set_header(l_req, 'Accept', 'application/json');
    UTL_HTTP.set_header(l_req, 'Content-Length', TO_CHAR(DBMS_LOB.getlength(l_form)));

    -- write body
    DECLARE
      l_pos   PLS_INTEGER := 1;
      l_len   PLS_INTEGER := DBMS_LOB.getlength(l_form);
      l_take  PLS_INTEGER;
      l_chunk VARCHAR2(32767);
    BEGIN
      WHILE l_pos <= l_len LOOP
        l_take := LEAST(32767, l_len - l_pos + 1);
        l_chunk := DBMS_LOB.substr(l_form, l_take, l_pos);
        UTL_HTTP.write_text(l_req, l_chunk);
        l_pos := l_pos + l_take;
      END LOOP;
    END;

    l_resp := UTL_HTTP.get_response(l_req);
    l_status := l_resp.status_code;

    DBMS_LOB.createtemporary(l_resp_clob, TRUE);
    BEGIN
      LOOP
        UTL_HTTP.read_text(l_resp, l_buf, 32767);
        xx_http_clob_append(l_resp_clob, l_buf);
      END LOOP;
    EXCEPTION
      WHEN UTL_HTTP.end_of_body THEN
        NULL;
    END;

    UTL_HTTP.end_response(l_resp);

    IF l_status < 200 OR l_status >= 300 THEN
      RETURN NULL;
    END IF;

    BEGIN
      DECLARE
        l_tok_obj JSON_OBJECT_T := JSON_OBJECT_T.parse(l_resp_clob);
      BEGIN
        l_token := xx_http_get_json_string(l_tok_obj, 'access_token');
      END;
    EXCEPTION
      WHEN OTHERS THEN
        l_token := NULL;
    END;

    RETURN l_token;

  EXCEPTION
    WHEN OTHERS THEN
      BEGIN
        UTL_HTTP.end_response(l_resp);
      EXCEPTION
        WHEN OTHERS THEN NULL;
      END;
      RETURN NULL;
  END;

  ----------------------------------------------------------------------
  -- Minimal JSON quoting helper
  ----------------------------------------------------------------------
  FUNCTION xx_http_json_quote(p_str VARCHAR2) RETURN VARCHAR2 IS
    l_s VARCHAR2(32767);
  BEGIN
    IF p_str IS NULL THEN
      RETURN '""';
    END IF;

    l_s := p_str;

    -- UTL_HTTP header values can legally contain folded lines / control chars
    -- (e.g., Set-Cookie values with CR/LF). JSON strings cannot contain raw
    -- control characters, so strip or escape them here.
    FOR i IN 0 .. 31 LOOP
      IF i IN (9,10,13) THEN
        NULL; -- handled below as \t, \n, \r
      ELSE
        l_s := REPLACE(l_s, CHR(i), ' ');
      END IF;
    END LOOP;

    -- JSON escaping
    l_s := REPLACE(l_s, '\', '\\');
    l_s := REPLACE(l_s, '"', '\"');
    l_s := REPLACE(l_s, CHR(10), '\n');
    l_s := REPLACE(l_s, CHR(13), '\r');
    l_s := REPLACE(l_s, CHR(9),  '\t');

    RETURN '"' || l_s || '"';
  END;

  ----------------------------------------------------------------------
  -- Convert response headers to JSON array.
  -- IMPORTANT: get_header_count/get_header expect resp IN OUT.
  ----------------------------------------------------------------------
  FUNCTION xx_http_headers_to_json(p_resp IN OUT NOCOPY UTL_HTTP.resp) RETURN CLOB IS
    l_out   CLOB;
    l_cnt   PLS_INTEGER;
    l_name  VARCHAR2(256);
    l_value VARCHAR2(4000);
  BEGIN
    DBMS_LOB.createtemporary(l_out, TRUE);
    xx_http_clob_append(l_out, '[');

    l_cnt := UTL_HTTP.get_header_count(p_resp);

    FOR i IN 1 .. l_cnt LOOP
      UTL_HTTP.get_header(p_resp, i, l_name, l_value);
      IF i > 1 THEN
        xx_http_clob_append(l_out, ',');
      END IF;

      xx_http_clob_append(
        l_out,
        '{"name":' || xx_http_json_quote(l_name) || ',"value":' || xx_http_json_quote(l_value) || '}'
      );
    END LOOP;

    xx_http_clob_append(l_out, ']');
    RETURN l_out;
  EXCEPTION
    WHEN OTHERS THEN
      -- never return an empty/invalid JSON value; callers may parse this
      BEGIN
        IF l_out IS NULL THEN
          DBMS_LOB.createtemporary(l_out, TRUE);
        END IF;
        -- If we partially wrote, discard and replace with []
        DBMS_LOB.trim(l_out, 0);
        xx_http_clob_append(l_out, '[]');
        RETURN l_out;
      EXCEPTION
        WHEN OTHERS THEN
         RETURN NULL;
      END;
    END;
  ----------------------------------------------------------------------
  -- Write request body helpers
  ----------------------------------------------------------------------
  PROCEDURE xx_http_write_body_clob(p_req IN OUT NOCOPY UTL_HTTP.req, p_body CLOB) IS
    l_pos   PLS_INTEGER := 1;
    l_len   PLS_INTEGER;
    l_take  PLS_INTEGER;
    l_chunk VARCHAR2(32767);
  BEGIN
    IF p_body IS NULL THEN
      RETURN;
    END IF;

    l_len := DBMS_LOB.getlength(p_body);
    WHILE l_pos <= l_len LOOP
      l_take := LEAST(32767, l_len - l_pos + 1);
      l_chunk := DBMS_LOB.substr(p_body, l_take, l_pos);
      UTL_HTTP.write_text(p_req, l_chunk);
      l_pos := l_pos + l_take;
    END LOOP;
  END;

  PROCEDURE xx_http_write_body_blob(p_req IN OUT NOCOPY UTL_HTTP.req, p_body BLOB) IS
    l_pos  PLS_INTEGER := 1;
    l_len  PLS_INTEGER;
    l_take PLS_INTEGER;
    l_raw  RAW(32767);
  BEGIN
    IF p_body IS NULL THEN
      RETURN;
    END IF;

    l_len := DBMS_LOB.getlength(p_body);
    WHILE l_pos <= l_len LOOP
      l_take := LEAST(32767, l_len - l_pos + 1);
      l_raw := DBMS_LOB.substr(p_body, l_take, l_pos);
      UTL_HTTP.write_raw(p_req, l_raw);
      l_pos := l_pos + l_take;
    END LOOP;
  END;

  ----------------------------------------------------------------------
  -- main procedure
  ----------------------------------------------------------------------
  PROCEDURE xx_http_call(
    p_protocol               IN  VARCHAR2 DEFAULT 'https',
    p_host                   IN  VARCHAR2 DEFAULT NULL,
    p_port                   IN  NUMBER   DEFAULT NULL,
    p_path                   IN  VARCHAR2 DEFAULT NULL,
    p_url                    IN  VARCHAR2 DEFAULT NULL,
    p_verb                   IN  VARCHAR2 DEFAULT 'GET',
    p_auth_type              IN  VARCHAR2 DEFAULT 'NONE',
    p_auth_json              IN  CLOB     DEFAULT NULL,
    p_wallet_path            IN  VARCHAR2 DEFAULT NULL,
    p_wallet_password        IN  VARCHAR2 DEFAULT NULL,
    p_url_params_json        IN  CLOB     DEFAULT NULL,
    p_headers_json           IN  CLOB     DEFAULT NULL,
    p_body_clob              IN  CLOB     DEFAULT NULL,
    p_body_blob              IN  BLOB     DEFAULT NULL,
    p_req_content_type       IN  VARCHAR2 DEFAULT NULL,
    p_resp_mode              IN  VARCHAR2 DEFAULT 'TEXT',
    p_timeout_seconds        IN  NUMBER   DEFAULT 60,
    x_status_code            OUT NUMBER,
    x_reason_phrase          OUT VARCHAR2,
    x_response_headers_json  OUT CLOB,
    x_response_clob          OUT CLOB,
    x_response_blob          OUT BLOB
  ) IS
    l_protocol     VARCHAR2(10) := LOWER(NVL(p_protocol,'https'));
    l_verb         VARCHAR2(30) := xx_http_norm(NVL(p_verb,'GET'));
    l_auth         VARCHAR2(30) := xx_http_norm(NVL(p_auth_type,'NONE'));

    l_url          VARCHAR2(4000);
    l_port_str     VARCHAR2(20);
    l_path         VARCHAR2(4000);
    l_query        VARCHAR2(32767);

    l_wallet_path  VARCHAR2(4000);
    l_wallet_pwd   VARCHAR2(4000);

    l_req          UTL_HTTP.req;
    l_resp         UTL_HTTP.resp;

    l_status       NUMBER;
    l_reason       VARCHAR2(4000);

    l_resp_clob    CLOB;
    l_resp_blob    BLOB;

    l_buf_txt      VARCHAR2(32767);
    l_buf_raw      RAW(32767);

    l_has_body     BOOLEAN := (p_body_blob IS NOT NULL)
                          OR (p_body_clob IS NOT NULL AND DBMS_LOB.getlength(p_body_clob) > 0);

    l_content_type VARCHAR2(4000);
    l_accept       VARCHAR2(4000);

    l_auth_header  VARCHAR2(4000);
    l_token        VARCHAR2(4000);
  BEGIN
    -- reset globals snapshot
    g_http_last_status_code := NULL;
    g_http_last_reason_phrase := NULL;
    g_http_last_response_headers_json := NULL;
    g_http_last_response_clob := NULL;
    g_http_last_response_blob := NULL;
    g_http_last_error_detail := NULL;


    -- build URL
    IF p_url IS NOT NULL THEN
      l_url := p_url;
    ELSE
      IF p_host IS NULL THEN
        RAISE_APPLICATION_ERROR(-20001, 'xx_http_call: host is required when p_url is not provided');
      END IF;

      IF p_port IS NULL THEN
        l_port_str := NULL;
      ELSE
        l_port_str := ':' || TO_CHAR(TRUNC(p_port));
      END IF;

      l_path := NVL(p_path,'/');
      IF SUBSTR(l_path,1,1) <> '/' THEN
        l_path := '/' || l_path;
      END IF;

      l_url := l_protocol || '://' || p_host || NVL(l_port_str,'') || l_path;
    END IF;

    l_query := xx_http_build_query(p_url_params_json);
    IF l_query IS NOT NULL THEN
      l_url := l_url || l_query;
    END IF;

    -- wallet selection
    l_wallet_path := xx_http_get_wallet_path(p_auth_json, p_wallet_path);
    l_wallet_pwd  := xx_http_get_wallet_password(p_auth_json, p_wallet_password);

    IF l_protocol = 'https' AND l_wallet_path IS NOT NULL THEN
      UTL_HTTP.set_wallet(l_wallet_path, l_wallet_pwd);
    END IF;

    UTL_HTTP.set_transfer_timeout(TRUNC(NVL(p_timeout_seconds,60)));

    l_req := UTL_HTTP.begin_request(l_url, l_verb, 'HTTP/1.1');

    -- defaults
    UTL_HTTP.set_header(l_req, 'User-Agent', 'XX_BLOCK_HTTP_1 (UTL_HTTP)');
    UTL_HTTP.set_header(l_req, 'Connection', 'close');

    -- apply caller headers
    xx_http_apply_headers(l_req, p_headers_json);

    -- Accept header (caller can override via p_headers_json)
    IF xx_http_norm(p_resp_mode) = 'BINARY' THEN
      l_accept := '*/*';
    ELSE
      l_accept := 'application/json, text/plain, */*';
    END IF;
    BEGIN
      UTL_HTTP.set_header(l_req, 'Accept', l_accept);
    EXCEPTION
      WHEN OTHERS THEN NULL;
    END;

    -- auth
    IF l_auth = 'BASIC' THEN
      l_auth_header := xx_http_basic_auth_header(p_auth_json);
      IF l_auth_header IS NOT NULL THEN
        UTL_HTTP.set_header(l_req, 'Authorization', l_auth_header);
      END IF;
    ELSIF l_auth = 'OAUTH' THEN
      l_token := xx_http_oauth_token(p_auth_json, l_wallet_path, l_wallet_pwd, TRUNC(NVL(p_timeout_seconds,60)));
      IF l_token IS NOT NULL THEN
        UTL_HTTP.set_header(l_req, 'Authorization', 'Bearer ' || l_token);
      END IF;
    END IF;

    -- body headers
    IF l_has_body THEN
      IF p_req_content_type IS NOT NULL THEN
        l_content_type := p_req_content_type;
      ELSE
        l_content_type := CASE
          WHEN p_body_blob IS NOT NULL THEN 'application/octet-stream'
          ELSE 'application/json'
        END;
      END IF;

      UTL_HTTP.set_header(l_req, 'Content-Type', l_content_type);

      IF p_body_blob IS NOT NULL THEN
        UTL_HTTP.set_header(l_req, 'Content-Length', TO_CHAR(DBMS_LOB.getlength(p_body_blob)));
      ELSE
        UTL_HTTP.set_header(l_req, 'Content-Length', TO_CHAR(DBMS_LOB.getlength(p_body_clob)));
      END IF;
    END IF;

    -- write body (allowed for any verb)
    IF p_body_blob IS NOT NULL THEN
      xx_http_write_body_blob(l_req, p_body_blob);
    ELSIF p_body_clob IS NOT NULL AND DBMS_LOB.getlength(p_body_clob) > 0 THEN
      xx_http_write_body_clob(l_req, p_body_clob);
    END IF;

    -- response
    l_resp := UTL_HTTP.get_response(l_req);
    l_status := l_resp.status_code;
    l_reason := l_resp.reason_phrase;

    x_status_code := l_status;
    x_reason_phrase := l_reason;

    x_response_headers_json := xx_http_headers_to_json(l_resp);
      IF x_response_headers_json IS NULL OR DBMS_LOB.getlength(x_response_headers_json) = 0 THEN
        x_response_headers_json := '[]';
      END IF;
    IF xx_http_norm(p_resp_mode) = 'BINARY' THEN
      DBMS_LOB.createtemporary(l_resp_blob, TRUE);
      BEGIN
        LOOP
          UTL_HTTP.read_raw(l_resp, l_buf_raw, 32767);
          xx_http_blob_append_raw(l_resp_blob, l_buf_raw);
        END LOOP;
      EXCEPTION
        WHEN UTL_HTTP.end_of_body THEN
          NULL;
      END;

      x_response_blob := l_resp_blob;
      x_response_clob := NULL;
    ELSE
      DBMS_LOB.createtemporary(l_resp_clob, TRUE);
      BEGIN
        LOOP
          UTL_HTTP.read_text(l_resp, l_buf_txt, 32767);
          xx_http_clob_append(l_resp_clob, l_buf_txt);
        END LOOP;
      EXCEPTION
        WHEN UTL_HTTP.end_of_body THEN
          NULL;
      END;

      x_response_clob := l_resp_clob;
      x_response_blob := NULL;
    END IF;

    UTL_HTTP.end_response(l_resp);

    -- snapshot globals
    g_http_last_status_code := x_status_code;
    g_http_last_reason_phrase := x_reason_phrase;
    g_http_last_response_headers_json := x_response_headers_json;
    g_http_last_response_clob := x_response_clob;
    g_http_last_response_blob := x_response_blob;

EXCEPTION
  WHEN OTHERS THEN
    DECLARE
      l_detail VARCHAR2(4000);
      l_msg    VARCHAR2(4000);
    BEGIN
      -- close response if it exists
      BEGIN
        UTL_HTTP.end_response(l_resp);
      EXCEPTION
        WHEN OTHERS THEN NULL;
      END;

      -- try to get the real underlying error (ACL/cert/DNS/etc.)
      BEGIN
        l_detail := UTL_HTTP.get_detailed_sqlerrm;
      EXCEPTION
        WHEN OTHERS THEN
          l_detail := NULL;
      END;

      g_http_last_error_detail := l_detail;

      -- also clear "success" snapshots (optional but nice)
      g_http_last_status_code := NULL;
      g_http_last_reason_phrase := NULL;
      g_http_last_response_headers_json := NULL;
      g_http_last_response_clob := NULL;
      g_http_last_response_blob := NULL;

      -- IMPORTANT:
      -- re-raise with detail appended so ANY MAIN that returns SQLERRM will include it
      l_msg := SQLERRM;
      IF l_detail IS NOT NULL AND LENGTH(TRIM(l_detail)) > 0 THEN
        l_msg := l_msg || ' | ' || l_detail;
      END IF;

      RAISE_APPLICATION_ERROR(-20002, SUBSTR(l_msg, 1, 4000));
    END;
END xx_http_call;

