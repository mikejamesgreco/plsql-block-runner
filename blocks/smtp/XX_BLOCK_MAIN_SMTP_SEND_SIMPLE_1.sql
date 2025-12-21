-- MAIN: XX_BLOCK_MAIN_SMTP_SEND_SIMPLE_1
-- PURPOSE:
--   Send a plain-text email using UTL_SMTP with a single host/port.
--
-- IMPORTANT:
--   MAIN snippet spliced into worker BEGIN..END.
--
-- INPUTS (l_inputs_json):
--   $.smtp.host        (required)
--   $.smtp.port        (required, number)
--   $.smtp.timeout     (optional, number, default 30)
--   $.smtp.auth_type   (optional, default 'NONE')
--   $.smtp.username    (optional; future)
--   $.smtp.password    (optional; future)
--   $.mail.from        (required)
--   $.mail.to          (required)
--   $.mail.subject     (required)
--   $.mail.message     (required)
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

  l_res       JSON_OBJECT_T;

  PROCEDURE ensure_result_clob IS
  BEGIN
    -- Ensure l_result_json is a valid locator, even on failure paths.
    IF l_result_json IS NULL THEN
      DBMS_LOB.CREATETEMPORARY(l_result_json, TRUE);
      DBMS_LOB.TRIM(l_result_json, 0);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      -- If CREATETEMPORARY fails for some reason, leave it NULL and rely on fallback.
      NULL;
  END;

  PROCEDURE set_result_json(p_status IN VARCHAR2, p_msg IN VARCHAR2) IS
  BEGIN
    l_res := JSON_OBJECT_T();
    l_res.PUT('status',  p_status);
    l_res.PUT('message', p_msg);

    -- Convert to CLOB; also ensure a safe locator exists
    ensure_result_clob;

    -- If we got a locator, write/overwrite into it.
    IF l_result_json IS NOT NULL THEN
      -- easiest overwrite: assign (Oracle manages temp LOB)
      l_result_json := l_res.TO_CLOB;
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      -- last-ditch: avoid LOB ops; let outer handler set a literal
      NULL;
  END;

  PROCEDURE fail(p_msg IN VARCHAR2) IS
  BEGIN
    :v_retcode := 2;
    :v_errbuf  := SUBSTR(p_msg, 1, 4000);

    set_result_json('E', p_msg);

    RAISE_APPLICATION_ERROR(-20001, 'MAIN_SMTP_SEND_SIMPLE | ' || p_msg);
  END;

BEGIN
  :v_retcode := 0;
  :v_errbuf  := NULL;

  -- Make sure result CLOB exists early (prevents ORA-22275 on error paths)
  ensure_result_clob;

  IF l_inputs_json IS NULL THEN
    fail('l_inputs_json is NULL');
  END IF;

  -- SMTP config (literal JSON paths)
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

  -- Mail fields
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

  -- This is the one you tripped:
  IF l_message IS NULL OR DBMS_LOB.GETLENGTH(l_message) = 0 THEN
    fail('mail.message is required');
  END IF;

  -- Auth gating (not implemented in this v1)
  IF l_auth_type <> 'NONE' THEN
    fail('smtp.auth_type=' || l_auth_type || ' is not supported yet (use NONE for now)');
  END IF;

  -- Setup + send
  xx_smtp_setup(
    p_host    => l_host,
    p_port    => l_port,
    p_timeout => l_timeout
  );

  xx_smtp_send_simple(
    p_from    => l_from,
    p_to      => l_to,
    p_subject => l_subject,
    p_message => l_message
  );

  -- Success result
  l_res := JSON_OBJECT_T();
  l_res.PUT('status',   'S');
  l_res.PUT('message',  'Email sent');
  l_res.PUT('smtp_host', l_host);
  l_res.PUT('smtp_port', l_port);
  l_res.PUT('auth_type', l_auth_type);
  l_res.PUT('from', l_from);
  l_res.PUT('to',   l_to);
  l_res.PUT('subject', l_subject);

  l_result_json := l_res.TO_CLOB;

EXCEPTION
  WHEN OTHERS THEN
    -- If fail() already set retcode/errbuf, keep it. Otherwise standardize.
    IF :v_retcode IS NULL THEN
      :v_retcode := 2;
    END IF;

    IF :v_errbuf IS NULL THEN
      :v_errbuf := SUBSTR(SQLERRM, 1, 4000);
    END IF;

    -- Ensure result_json is safe (avoid ORA-22275). Use literal fallback if needed.
    BEGIN
      IF l_result_json IS NULL THEN
        l_result_json := '{"status":"E","message":"' ||
                         REPLACE(SUBSTR(:v_errbuf, 1, 3900), '"', '\"') ||
                         '"}';
      END IF;
    EXCEPTION
      WHEN OTHERS THEN
        -- last-ditch fallback: do nothing
        NULL;
    END;

    RAISE;
END;
