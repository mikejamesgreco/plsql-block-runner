-- MAIN: XX_BLOCK_MAIN_SMTP_SEND_MULTI_ATTACH_DIR_1
-- PURPOSE:
--   Send a plain-text email with 0..N attachments, where attachments are read from an Oracle DBA DIRECTORY
--   (UTL_FILE binary mode) via the shared FILE_IO block, and attached using the SMTP helper block.
--
-- IMPORTANT:
--   MAIN snippet spliced into worker BEGIN..END.
--   If you need locals/procs/functions, they MUST be inside this nested DECLARE block.
--
-- PREREQS / ASSUMPTIONS:
--   - SMTP blocks provide:
--       xx_smtp_setup(p_host, p_port, p_timeout)
--       xx_smtp_send_with_attachments(
--         p_from        IN VARCHAR2,
--         p_to          IN VARCHAR2,
--         p_subject     IN VARCHAR2,
--         p_message     IN CLOB,
--         p_attachments IN xx_smtp_attachment_tab
--       )
--     where xx_smtp_attachment_tab / xx_smtp_attachment_rec are types declared in SMTP DECL.
--
--   - FILE_IO blocks provide:
--       procedure xx_block_file_io_read_to_blob;
--     and populate a global temporary BLOB (g_file_blob) using inputs from l_inputs_json:
--       { "file": { "dir": "<DIRECTORY>", "name": "<filename>" } }
--
-- INPUTS (l_inputs_json):
--   $.smtp.host        (required)
--   $.smtp.port        (required, number)
--   $.smtp.timeout     (optional, number, default 30)
--   $.smtp.auth_type   (optional, default 'NONE')
--   $.smtp.username    (optional; future)
--   $.smtp.password    (optional; future)
--
--   $.mail.from        (required)
--   $.mail.to          (required)
--   $.mail.subject     (required)
--   $.mail.message     (required)
--
--   $.attachments.directory    (required if attachments.files provided; DBA directory name)
--   $.attachments.files        (optional array; if omitted/empty, sends without attachments)
--     Each element:
--       file_name   (required; filename in the DBA directory)
--       name        (optional; filename shown to recipient; defaults to file_name)
--       mime        (optional; defaults to application/octet-stream)
--       inline      (optional boolean; defaults false)
--       content_id  (optional; only used when inline=true)
--
-- OUTPUTS:
--   :v_retcode, :v_errbuf, l_result_json

DECLARE
  l_host      VARCHAR2(255);
  l_port      NUMBER;
  l_timeout   NUMBER;
  l_auth_type VARCHAR2(30);

  l_user      VARCHAR2(512);
  l_pass      VARCHAR2(512);

  l_from      VARCHAR2(512);
  l_to        VARCHAR2(4000);
  l_subject   VARCHAR2(1000);
  l_message   CLOB;

  l_dir_name  VARCHAR2(255);

  l_res       JSON_OBJECT_T;

  -- attachments collection (types from SMTP DECL)
  l_atts      xx_smtp_attachment_tab := xx_smtp_attachment_tab();

  --------------------------------------------------------------------
  -- Result helpers (same pattern as SIMPLE main)
  --------------------------------------------------------------------
  PROCEDURE ensure_result_clob IS
  BEGIN
    IF l_result_json IS NULL THEN
      DBMS_LOB.CREATETEMPORARY(l_result_json, TRUE);
      DBMS_LOB.TRIM(l_result_json, 0);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN NULL;
  END;

  PROCEDURE set_result_json(p_status IN VARCHAR2, p_msg IN VARCHAR2) IS
  BEGIN
    l_res := JSON_OBJECT_T();
    l_res.PUT('status',  p_status);
    l_res.PUT('message', p_msg);

    ensure_result_clob;

    IF l_result_json IS NOT NULL THEN
      l_result_json := l_res.TO_CLOB;
    END IF;
  EXCEPTION
    WHEN OTHERS THEN NULL;
  END;

  PROCEDURE fail(p_msg IN VARCHAR2) IS
  BEGIN
    :v_retcode := 2;
    :v_errbuf  := SUBSTR(p_msg, 1, 4000);

    set_result_json('E', p_msg);

    RAISE_APPLICATION_ERROR(-20001, 'MAIN_SMTP_SEND_MULTI_ATTACH_DIR | ' || p_msg);
  END;

  --------------------------------------------------------------------
  -- Helper: read a file to BLOB via FILE_IO block (which consumes l_inputs_json.file.*)
  -- We temporarily swap l_inputs_json to the minimal JSON FILE_IO expects,
  -- invoke xx_block_file_io_read_to_blob, then copy g_file_blob into a new temp BLOB.
  --------------------------------------------------------------------
  FUNCTION file_io_read_dir_file_to_blob(
    p_dir      IN VARCHAR2,
    p_filename IN VARCHAR2
  ) RETURN BLOB
  IS
    l_saved_inputs_json CLOB;
    l_tmp_inputs_json   CLOB;

    l_out_blob          BLOB;
    l_len               PLS_INTEGER;
  BEGIN
    IF TRIM(p_dir) IS NULL THEN
      RAISE_APPLICATION_ERROR(-20001, 'attachments.directory is required');
    END IF;

    IF TRIM(p_filename) IS NULL THEN
      RAISE_APPLICATION_ERROR(-20001, 'attachments.files[].file_name is required');
    END IF;

    l_saved_inputs_json := l_inputs_json;

    l_tmp_inputs_json :=
      '{'||
      '  "file": {'||
      '    "dir": "'||REPLACE(TRIM(p_dir), '"', '\"')||'",'||
      '    "name": "'||REPLACE(TRIM(p_filename), '"', '\"')||'"'||
      '  }'||
      '}';

    l_inputs_json := l_tmp_inputs_json;
    xx_block_file_io_read_to_blob;
    l_inputs_json := l_saved_inputs_json;

    DBMS_LOB.CREATETEMPORARY(l_out_blob, TRUE);
    DBMS_LOB.TRIM(l_out_blob, 0);

    IF g_file_blob IS NOT NULL THEN
      l_len := DBMS_LOB.GETLENGTH(g_file_blob);
      IF l_len > 0 THEN
        DBMS_LOB.COPY(l_out_blob, g_file_blob, l_len, 1, 1);
      END IF;
    END IF;

    RETURN l_out_blob;

  EXCEPTION
    WHEN OTHERS THEN
      BEGIN
        l_inputs_json := l_saved_inputs_json;
      EXCEPTION
        WHEN OTHERS THEN NULL;
      END;

      BEGIN
        IF l_out_blob IS NOT NULL AND DBMS_LOB.ISTEMPORARY(l_out_blob) = 1 THEN
          DBMS_LOB.FREETEMPORARY(l_out_blob);
        END IF;
      EXCEPTION
        WHEN OTHERS THEN NULL;
      END;

      RAISE;
  END file_io_read_dir_file_to_blob;

BEGIN
  :v_retcode := 0;
  :v_errbuf  := NULL;

  ensure_result_clob;

  IF l_inputs_json IS NULL THEN
    fail('l_inputs_json is NULL');
  END IF;

  ----------------------------------------------------------------------
  -- SMTP config
  ----------------------------------------------------------------------
  l_host :=
    JSON_VALUE(l_inputs_json, '$.smtp.host' RETURNING VARCHAR2(4000) NULL ON ERROR);

  l_port :=
    JSON_VALUE(l_inputs_json, '$.smtp.port' RETURNING NUMBER NULL ON ERROR);

  l_timeout :=
    NVL(JSON_VALUE(l_inputs_json, '$.smtp.timeout' RETURNING NUMBER NULL ON ERROR), 30);

  l_auth_type :=
    NVL(
      UPPER(TRIM(JSON_VALUE(l_inputs_json, '$.smtp.auth_type' RETURNING VARCHAR2(4000) NULL ON ERROR))),
      'NONE'
    );

  -- future fields (do not log)
  l_user :=
    JSON_VALUE(l_inputs_json, '$.smtp.username' RETURNING VARCHAR2(4000) NULL ON ERROR);

  l_pass :=
    JSON_VALUE(l_inputs_json, '$.smtp.password' RETURNING VARCHAR2(4000) NULL ON ERROR);

  IF TRIM(l_host) IS NULL THEN
    fail('smtp.host is required');
  END IF;

  IF l_port IS NULL OR l_port <= 0 THEN
    fail('smtp.port is required and must be > 0');
  END IF;

  IF l_auth_type <> 'NONE' THEN
    fail('smtp.auth_type=' || l_auth_type || ' is not supported yet (use NONE for now)');
  END IF;

  ----------------------------------------------------------------------
  -- Mail fields
  ----------------------------------------------------------------------
  l_from :=
    JSON_VALUE(l_inputs_json, '$.mail.from' RETURNING VARCHAR2(4000) NULL ON ERROR);

  l_to :=
    JSON_VALUE(l_inputs_json, '$.mail.to' RETURNING VARCHAR2(4000) NULL ON ERROR);

  l_subject :=
    JSON_VALUE(l_inputs_json, '$.mail.subject' RETURNING VARCHAR2(4000) NULL ON ERROR);

  SELECT JSON_VALUE(l_inputs_json, '$.mail.message' RETURNING CLOB NULL ON ERROR)
    INTO l_message
    FROM dual;

  IF TRIM(l_from) IS NULL THEN
    fail('mail.from is required');
  END IF;

  IF TRIM(l_to) IS NULL THEN
    fail('mail.to is required');
  END IF;

  IF TRIM(l_subject) IS NULL THEN
    fail('mail.subject is required');
  END IF;

  IF l_message IS NULL OR DBMS_LOB.GETLENGTH(l_message) = 0 THEN
    fail('mail.message is required');
  END IF;

  ----------------------------------------------------------------------
  -- Attachments: directory + files[]
  ----------------------------------------------------------------------
  l_dir_name :=
    JSON_VALUE(l_inputs_json, '$.attachments.directory' RETURNING VARCHAR2(4000) NULL ON ERROR);

  FOR r IN (
    SELECT
      jt.file_name,
      jt.name,
      jt.mime,
      jt.inline_flag,
      jt.content_id
    FROM JSON_TABLE(
           l_inputs_json,
           '$.attachments.files[*]'
           COLUMNS
             file_name   VARCHAR2(4000) PATH '$.file_name',
             name        VARCHAR2(4000) PATH '$.name',
             mime        VARCHAR2(4000) PATH '$.mime',
             inline_flag VARCHAR2(20)   PATH '$.inline',
             content_id  VARCHAR2(255)  PATH '$.content_id'
         ) jt
  ) LOOP
    DECLARE
      l_rec  xx_smtp_attachment_rec;
      l_blob BLOB;
    BEGIN
      IF TRIM(r.file_name) IS NULL THEN
        fail('attachments.files[].file_name is required');
      END IF;

      IF TRIM(l_dir_name) IS NULL THEN
        fail('attachments.directory is required when attachments.files is provided');
      END IF;

      l_rec.file_name    := TRIM(r.file_name);
      l_rec.display_name := NVL(NULLIF(TRIM(r.name), ''), l_rec.file_name);
      l_rec.mime_type    := NVL(NULLIF(TRIM(r.mime), ''), 'application/octet-stream');
      l_rec.inline_flag  :=
        CASE
          WHEN LOWER(TRIM(r.inline_flag)) IN ('true','1','y','yes') THEN TRUE
          ELSE FALSE
        END;
      l_rec.content_id := r.content_id;

      -- Read via FILE_IO block (returns a new temp BLOB)
      l_blob := file_io_read_dir_file_to_blob(TRIM(l_dir_name), l_rec.file_name);
      l_rec.content := l_blob;

      l_atts.EXTEND;
      l_atts(l_atts.COUNT) := l_rec;
    END;
  END LOOP;

  ----------------------------------------------------------------------
  -- Setup + send
  ----------------------------------------------------------------------
  xx_smtp_setup(
    p_host    => l_host,
    p_port    => l_port,
    p_timeout => l_timeout
  );

  xx_smtp_send_with_attachments(
    p_from        => l_from,
    p_to          => l_to,
    p_subject     => l_subject,
    p_message     => l_message,
    p_attachments => l_atts
  );

  ----------------------------------------------------------------------
  -- Success result
  ----------------------------------------------------------------------
  l_res := JSON_OBJECT_T();
  l_res.PUT('status',    'S');
  l_res.PUT('message',   'Email sent');
  l_res.PUT('smtp_host', l_host);
  l_res.PUT('smtp_port', l_port);
  l_res.PUT('auth_type', l_auth_type);
  l_res.PUT('from',      l_from);
  l_res.PUT('to',        l_to);
  l_res.PUT('subject',   l_subject);
  l_res.PUT('attachment_count', l_atts.COUNT);
  IF l_dir_name IS NOT NULL THEN
    l_res.PUT('attachments_directory', l_dir_name);
  END IF;

  l_result_json := l_res.TO_CLOB;

EXCEPTION
  WHEN OTHERS THEN
    IF :v_retcode IS NULL THEN
      :v_retcode := 2;
    END IF;

    IF :v_errbuf IS NULL THEN
      :v_errbuf := SUBSTR(SQLERRM, 1, 4000);
    END IF;

    BEGIN
      IF l_result_json IS NULL THEN
        l_result_json := '{"status":"E","message":"' ||
                         REPLACE(SUBSTR(:v_errbuf, 1, 3900), '"', '\"') ||
                         '"}';
      END IF;
    EXCEPTION
      WHEN OTHERS THEN NULL;
    END;

    RAISE;
END;
