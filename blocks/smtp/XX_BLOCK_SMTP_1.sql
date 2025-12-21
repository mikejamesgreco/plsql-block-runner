-- BLOCK: XX_BLOCK_SMTP_1
-- PURPOSE:
--   Minimal SMTP helpers built on UTL_SMTP.
--
-- DEFINES:
--   procedure xx_smtp_setup(p_host, p_port, p_timeout)
--   procedure xx_smtp_send_simple(p_from, p_to, p_subject, p_message)
--
-- INPUTS:
--   xx_smtp_setup:
--     p_host     SMTP host (required)
--     p_port     SMTP port (required, NUMBER; will be TRUNC'd)
--     p_timeout  seconds (optional, NUMBER; will be TRUNC'd; default 30)
--
--   xx_smtp_send_simple:
--     p_from     From email address (envelope and From header)
--     p_to       To email address list (comma/semicolon separated supported)
--     p_subject  Subject
--     p_message  Message body (CLOB)
--
-- OUTPUTS:
--   None. Raises on failure.
--
-- SIDE EFFECTS:
--   Sends an SMTP email via network call.
--
-- ERRORS:
--   Raises UTL_SMTP / network exceptions on connect/send failures.
--   Raises -20001 for obvious configuration / validation issues.

  ----------------------------------------------------------------------
  -- Setup / configuration
  ----------------------------------------------------------------------
  PROCEDURE xx_smtp_setup(
    p_host    IN VARCHAR2,
    p_port    IN NUMBER,
    p_timeout IN NUMBER DEFAULT 30
  ) IS
    l_port    PLS_INTEGER;
    l_timeout PLS_INTEGER;
  BEGIN
    IF TRIM(p_host) IS NULL THEN
      RAISE_APPLICATION_ERROR(-20001, 'xx_smtp_setup requires p_host');
    END IF;

    IF p_port IS NULL OR p_port <= 0 THEN
      RAISE_APPLICATION_ERROR(-20001, 'xx_smtp_setup requires p_port > 0');
    END IF;

    l_port := TRUNC(p_port);

    IF p_timeout IS NULL THEN
      l_timeout := 30;
    ELSE
      l_timeout := TRUNC(p_timeout);
      IF l_timeout <= 0 THEN
        l_timeout := 30;
      END IF;
    END IF;

    g_smtp_host    := TRIM(p_host);
    g_smtp_port    := l_port;
    g_smtp_timeout := l_timeout;
  END xx_smtp_setup;


  ----------------------------------------------------------------------
  -- Write a single header line (ensures CRLF)
  ----------------------------------------------------------------------
  PROCEDURE xx_smtp_write_header(
    p_conn IN OUT NOCOPY UTL_SMTP.CONNECTION,
    p_name IN VARCHAR2,
    p_val  IN VARCHAR2
  ) IS
  BEGIN
    UTL_SMTP.WRITE_DATA(p_conn, p_name || ': ' || NVL(p_val, '') || UTL_TCP.CRLF);
  END xx_smtp_write_header;


  ----------------------------------------------------------------------
  -- Dot-stuff per SMTP rules: any line that begins with "." must be prefixed with another "."
  ----------------------------------------------------------------------
  FUNCTION xx_smtp_dot_stuff(p_text IN CLOB) RETURN CLOB IS
    l_out   CLOB;
    l_len   PLS_INTEGER;
    l_pos   PLS_INTEGER := 1;
    l_chunk VARCHAR2(32767);
  BEGIN
    IF p_text IS NULL THEN
      RETURN NULL;
    END IF;

    DBMS_LOB.CREATETEMPORARY(l_out, TRUE);

    l_len := DBMS_LOB.GETLENGTH(p_text);
    WHILE l_pos <= l_len LOOP
      l_chunk := DBMS_LOB.SUBSTR(p_text, 32767, l_pos);
      l_pos   := l_pos + LENGTH(l_chunk);

      -- Replace CRLF "." at start of line and beginning-of-text "."
      l_chunk := REGEXP_REPLACE(l_chunk, '(^|\r\n)\.', '\1..');

      DBMS_LOB.WRITEAPPEND(l_out, LENGTH(l_chunk), l_chunk);
    END LOOP;

    RETURN l_out;
  END xx_smtp_dot_stuff;


  ----------------------------------------------------------------------
  -- Normalize newlines to CRLF (SMTP requires CRLF). We'll treat any LF as newline.
  ----------------------------------------------------------------------
  FUNCTION xx_smtp_normalize_crlf(p_text IN CLOB) RETURN CLOB IS
    l_out   CLOB;
    l_len   PLS_INTEGER;
    l_pos   PLS_INTEGER := 1;
    l_chunk VARCHAR2(32767);
  BEGIN
    IF p_text IS NULL THEN
      RETURN NULL;
    END IF;

    DBMS_LOB.CREATETEMPORARY(l_out, TRUE);

    l_len := DBMS_LOB.GETLENGTH(p_text);
    WHILE l_pos <= l_len LOOP
      l_chunk := DBMS_LOB.SUBSTR(p_text, 32767, l_pos);
      l_pos   := l_pos + LENGTH(l_chunk);

      -- 1) CRLF -> LF
      l_chunk := REPLACE(l_chunk, CHR(13) || CHR(10), CHR(10));
      -- 2) CR -> LF
      l_chunk := REPLACE(l_chunk, CHR(13), CHR(10));
      -- 3) LF -> CRLF
      l_chunk := REPLACE(l_chunk, CHR(10), CHR(13) || CHR(10));

      DBMS_LOB.WRITEAPPEND(l_out, LENGTH(l_chunk), l_chunk);
    END LOOP;

    RETURN l_out;
  END xx_smtp_normalize_crlf;


  ----------------------------------------------------------------------
  -- Send a plain text message (no AUTH, no TLS in this v1)
  ----------------------------------------------------------------------
  PROCEDURE xx_smtp_send_simple(
    p_from    IN VARCHAR2,
    p_to      IN VARCHAR2,
    p_subject IN VARCHAR2,
    p_message IN CLOB
  ) IS
    l_conn      UTL_SMTP.CONNECTION;
    l_conn_open BOOLEAN := FALSE;

    l_body     CLOB;
    l_body2    CLOB;

    l_to_list  VARCHAR2(4000);
    l_token    VARCHAR2(4000);
    l_idx      PLS_INTEGER := 1;

    l_host     VARCHAR2(255);
    l_port     PLS_INTEGER;
  BEGIN
    l_host := g_smtp_host;
    l_port := g_smtp_port;

    IF l_host IS NULL OR l_port IS NULL THEN
      RAISE_APPLICATION_ERROR(-20001, 'SMTP not configured. Call xx_smtp_setup first.');
    END IF;

    IF TRIM(p_from) IS NULL THEN
      RAISE_APPLICATION_ERROR(-20001, 'SMTP send requires p_from');
    END IF;

    IF TRIM(p_to) IS NULL THEN
      RAISE_APPLICATION_ERROR(-20001, 'SMTP send requires p_to');
    END IF;

    -- Connect
    l_conn := UTL_SMTP.OPEN_CONNECTION(
                host       => l_host,
                port       => l_port,
                tx_timeout => g_smtp_timeout
              );
    l_conn_open := TRUE;

    -- Identify ourselves
    UTL_SMTP.HELO(l_conn, l_host);

    -- Envelope
    UTL_SMTP.MAIL(l_conn, TRIM(p_from));

    -- Accept comma/semicolon separated recipients in p_to
    l_to_list := REPLACE(p_to, ';', ',');
    l_to_list := REGEXP_REPLACE(l_to_list, '\s+', ''); -- strip spaces

    l_idx := 1;
    LOOP
      l_token := REGEXP_SUBSTR(l_to_list, '[^,]+', 1, l_idx);
      EXIT WHEN l_token IS NULL;
      UTL_SMTP.RCPT(l_conn, l_token);
      l_idx := l_idx + 1;
    END LOOP;

    -- Data section
    UTL_SMTP.OPEN_DATA(l_conn);

    -- Basic headers
    xx_smtp_write_header(l_conn, 'From',    TRIM(p_from));
    xx_smtp_write_header(l_conn, 'To',      p_to);
    xx_smtp_write_header(l_conn, 'Subject', NVL(p_subject, ''));
    xx_smtp_write_header(l_conn, 'MIME-Version', '1.0');
    xx_smtp_write_header(l_conn, 'Content-Type', 'text/plain; charset=UTF-8');
    xx_smtp_write_header(l_conn, 'Content-Transfer-Encoding', '8bit');

    -- End headers
    UTL_SMTP.WRITE_DATA(l_conn, UTL_TCP.CRLF);

    -- Body: normalize CRLF and dot-stuff
    l_body  := xx_smtp_normalize_crlf(p_message);
    l_body2 := xx_smtp_dot_stuff(l_body);

    -- Write body in chunks (treat NULL body as empty string)
    DECLARE
      l_len   PLS_INTEGER;
      l_pos   PLS_INTEGER := 1;
      l_chunk VARCHAR2(32767);
    BEGIN
      IF l_body2 IS NULL THEN
        l_len := 0;
      ELSE
        l_len := DBMS_LOB.GETLENGTH(l_body2);
      END IF;

      WHILE l_pos <= l_len LOOP
        l_chunk := DBMS_LOB.SUBSTR(l_body2, 32767, l_pos);
        l_pos   := l_pos + LENGTH(l_chunk);
        UTL_SMTP.WRITE_DATA(l_conn, l_chunk);
      END LOOP;
    END;

    -- End-of-data terminator handled by CLOSE_DATA (CRLF.<CRLF>)
    UTL_SMTP.CLOSE_DATA(l_conn);

    -- Quit / close
    UTL_SMTP.QUIT(l_conn);
    l_conn_open := FALSE;

  EXCEPTION
    WHEN OTHERS THEN
      BEGIN
        IF l_conn_open THEN
          UTL_SMTP.QUIT(l_conn);
          l_conn_open := FALSE;
        END IF;
      EXCEPTION
        WHEN OTHERS THEN NULL;
      END;
      RAISE;
  END xx_smtp_send_simple;
