-- BLOCK: XX_BLOCK_SMTP_1
-- PURPOSE:
--   SMTP helper procedures built on UTL_SMTP.
--   Supports:
--     - plain text email
--     - email with a single attachment
--     - email with multiple attachments (any MIME type)
--
-- DEFINES:
--   procedure xx_smtp_setup
--   procedure xx_smtp_send_simple
--   procedure xx_smtp_send_with_attachment
--   procedure xx_smtp_send_with_attachments
--
-- INPUTS:
--   xx_smtp_setup:
--     p_host     SMTP host (required)
--     p_port     SMTP port (required, NUMBER; will be TRUNC'd)
--     p_timeout  seconds (optional, NUMBER; will be TRUNC'd; default 30; <=0 -> 30)
--
--   xx_smtp_send_simple:
--     p_from     From email address (envelope and From header)
--     p_to       To email address list (comma/semicolon separated supported)
--     p_subject  Subject
--     p_message  Message body (CLOB)
--
--   xx_smtp_send_with_attachment:
--     p_from              From email address
--     p_to                To email address list
--     p_subject           Subject
--     p_message           Message body (CLOB)
--     p_attachment_name   Filename shown to recipient
--     p_attachment_mime   MIME type (e.g. application/pdf)
--     p_attachment_blob   Attachment payload
--     p_attachment_inline Inline TRUE/FALSE (default FALSE)
--     p_content_id        Optional Content-ID for inline usage (e.g. "logo123")
--
--   xx_smtp_send_with_attachments:
--     p_from         From email address
--     p_to           To email address list
--     p_subject      Subject
--     p_message      Message body (CLOB)
--     p_attachments  0..N attachments (xx_smtp_attachment_tab)
--
-- OUTPUTS:
--   None. Raises on failure.
--
-- SIDE EFFECTS:
--   Sends SMTP email via network call.
--
-- ERRORS:
--   Raises UTL_SMTP / network exceptions on connect/send failures.
--   Raises -20001 for obvious configuration / validation issues.
--
-- LIMITATIONS:
--   - No SMTP AUTH / STARTTLS in this block (server/network must allow relay).
--   - Uses multipart/mixed when attachments exist.
--   - Base64 encoding is chunked and CRLF-delimited.
--   - Dot-stuffing applied to message body.

  ----------------------------------------------------------------------
  -- Forward declarations (prevents "not declared in this scope" if the
  -- block text is ever reordered / partially included by the assembler)
  ----------------------------------------------------------------------
  PROCEDURE xx_smtp_setup(
    p_host    IN VARCHAR2,
    p_port    IN NUMBER,
    p_timeout IN NUMBER DEFAULT 30
  );

  PROCEDURE xx_smtp_send_simple(
    p_from    IN VARCHAR2,
    p_to      IN VARCHAR2,
    p_subject IN VARCHAR2,
    p_message IN CLOB
  );

  PROCEDURE xx_smtp_send_with_attachment(
    p_from              IN VARCHAR2,
    p_to                IN VARCHAR2,
    p_subject           IN VARCHAR2,
    p_message           IN CLOB,
    p_attachment_name   IN VARCHAR2,
    p_attachment_mime   IN VARCHAR2,
    p_attachment_blob   IN BLOB,
    p_attachment_inline IN BOOLEAN DEFAULT FALSE,
    p_content_id        IN VARCHAR2 DEFAULT NULL
  );

  PROCEDURE xx_smtp_send_with_attachments(
    p_from        IN VARCHAR2,
    p_to          IN VARCHAR2,
    p_subject     IN VARCHAR2,
    p_message     IN CLOB,
    p_attachments IN xx_smtp_attachment_tab
  );

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
  -- Write a CLOB to SMTP in chunks (32767 max per call)
  ----------------------------------------------------------------------
  PROCEDURE xx_smtp_write_clob(
    p_conn IN OUT NOCOPY UTL_SMTP.CONNECTION,
    p_text IN CLOB
  ) IS
    l_len   PLS_INTEGER;
    l_pos   PLS_INTEGER := 1;
    l_chunk VARCHAR2(32767);
  BEGIN
    IF p_text IS NULL THEN
      RETURN;
    END IF;

    l_len := DBMS_LOB.GETLENGTH(p_text);
    WHILE l_pos <= l_len LOOP
      l_chunk := DBMS_LOB.SUBSTR(p_text, 32767, l_pos);
      l_pos   := l_pos + LENGTH(l_chunk);
      UTL_SMTP.WRITE_DATA(p_conn, l_chunk);
    END LOOP;
  END xx_smtp_write_clob;


  ----------------------------------------------------------------------
  -- Normalize CR/LF to CRLF (SMTP requires CRLF)
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
  -- Base64 encode a BLOB to CLOB (chunk-safe)
  -- - UTL_ENCODE.BASE64_ENCODE accepts RAW up to 32767 bytes
  -- - Base64 expands 4/3, so keep input <= 24573 bytes (multiple of 3) to stay < 32767 output
  ----------------------------------------------------------------------
  FUNCTION xx_smtp_blob_to_base64(p_blob IN BLOB) RETURN CLOB IS
    c_in_chunk CONSTANT PLS_INTEGER := 24573;
    l_clob     CLOB;
    l_pos      PLS_INTEGER := 1;
    l_len      PLS_INTEGER;
    l_take     PLS_INTEGER;
    l_raw_in   RAW(32767);
    l_raw_out  RAW(32767);
    l_vc_out   VARCHAR2(32767);
  BEGIN
    IF p_blob IS NULL THEN
      RETURN NULL;
    END IF;

    DBMS_LOB.CREATETEMPORARY(l_clob, TRUE);
    l_len := DBMS_LOB.GETLENGTH(p_blob);

    WHILE l_pos <= l_len LOOP
      l_take   := LEAST(c_in_chunk, l_len - l_pos + 1);
      l_raw_in := DBMS_LOB.SUBSTR(p_blob, l_take, l_pos);

      l_raw_out := UTL_ENCODE.BASE64_ENCODE(l_raw_in);
      l_vc_out  := UTL_RAW.CAST_TO_VARCHAR2(l_raw_out);

      DBMS_LOB.WRITEAPPEND(l_clob, LENGTH(l_vc_out), l_vc_out);
      DBMS_LOB.WRITEAPPEND(l_clob, 2, UTL_TCP.CRLF);

      l_pos := l_pos + l_take;
    END LOOP;

    RETURN l_clob;
  END xx_smtp_blob_to_base64;


  ----------------------------------------------------------------------
  -- Simple text email (wrapper)
  ----------------------------------------------------------------------
  PROCEDURE xx_smtp_send_simple(
    p_from    IN VARCHAR2,
    p_to      IN VARCHAR2,
    p_subject IN VARCHAR2,
    p_message IN CLOB
  ) IS
    l_atts xx_smtp_attachment_tab; -- NULL
  BEGIN
    xx_smtp_send_with_attachments(
      p_from        => p_from,
      p_to          => p_to,
      p_subject     => p_subject,
      p_message     => p_message,
      p_attachments => l_atts
    );
  END xx_smtp_send_simple;


  ----------------------------------------------------------------------
  -- Single attachment wrapper
  ----------------------------------------------------------------------
  PROCEDURE xx_smtp_send_with_attachment(
    p_from              IN VARCHAR2,
    p_to                IN VARCHAR2,
    p_subject           IN VARCHAR2,
    p_message           IN CLOB,
    p_attachment_name   IN VARCHAR2,
    p_attachment_mime   IN VARCHAR2,
    p_attachment_blob   IN BLOB,
    p_attachment_inline IN BOOLEAN DEFAULT FALSE,
    p_content_id        IN VARCHAR2 DEFAULT NULL
  ) IS
    l_atts xx_smtp_attachment_tab := xx_smtp_attachment_tab();
    l_rec  xx_smtp_attachment_rec;
  BEGIN
    IF p_attachment_blob IS NOT NULL THEN
      l_rec.file_name    := p_attachment_name;
      l_rec.display_name := NVL(NULLIF(TRIM(p_attachment_name), ''), 'attachment.bin');
      l_rec.mime_type    := NVL(NULLIF(TRIM(p_attachment_mime), ''), 'application/octet-stream');
      l_rec.content      := p_attachment_blob;
      l_rec.inline_flag  := NVL(p_attachment_inline, FALSE);
      l_rec.content_id   := p_content_id;

      l_atts.EXTEND;
      l_atts(l_atts.COUNT) := l_rec;
    END IF;

    xx_smtp_send_with_attachments(
      p_from        => p_from,
      p_to          => p_to,
      p_subject     => p_subject,
      p_message     => p_message,
      p_attachments => l_atts
    );
  END xx_smtp_send_with_attachment;


  ----------------------------------------------------------------------
  -- Send email with 0..N attachments
  ----------------------------------------------------------------------
  PROCEDURE xx_smtp_send_with_attachments(
    p_from        IN VARCHAR2,
    p_to          IN VARCHAR2,
    p_subject     IN VARCHAR2,
    p_message     IN CLOB,
    p_attachments IN xx_smtp_attachment_tab
  ) IS
    l_conn      UTL_SMTP.CONNECTION;
    l_conn_open BOOLEAN := FALSE;

    l_boundary  VARCHAR2(80);
    l_body      CLOB;

    l_to_list   VARCHAR2(4000);
    l_token     VARCHAR2(4000);
    l_idx       PLS_INTEGER := 1;

    l_has_atts  BOOLEAN := FALSE;
    l_att_b64   CLOB;
    l_disp      VARCHAR2(20);

    l_name      VARCHAR2(4000);
    l_mime      VARCHAR2(255);
    l_inline    BOOLEAN;
    l_cid       VARCHAR2(255);
  BEGIN
    IF TRIM(g_smtp_host) IS NULL OR g_smtp_port IS NULL THEN
      RAISE_APPLICATION_ERROR(-20001, 'SMTP not configured. Call xx_smtp_setup first.');
    END IF;

    IF TRIM(p_from) IS NULL THEN
      RAISE_APPLICATION_ERROR(-20001, 'SMTP send requires p_from');
    END IF;

    IF TRIM(p_to) IS NULL THEN
      RAISE_APPLICATION_ERROR(-20001, 'SMTP send requires p_to');
    END IF;

    IF p_attachments IS NOT NULL AND p_attachments.COUNT > 0 THEN
      l_has_atts := TRUE;
    END IF;

    -- Connect
    l_conn := UTL_SMTP.OPEN_CONNECTION(
                host       => g_smtp_host,
                port       => g_smtp_port,
                tx_timeout => g_smtp_timeout
              );
    l_conn_open := TRUE;

    UTL_SMTP.HELO(l_conn, g_smtp_host);
    UTL_SMTP.MAIL(l_conn, TRIM(p_from));

    -- Recipients (comma/semicolon separated)
    l_to_list := REPLACE(p_to, ';', ',');
    l_to_list := REGEXP_REPLACE(l_to_list, '\s+', '');

    l_idx := 1;
    LOOP
      l_token := REGEXP_SUBSTR(l_to_list, '[^,]+', 1, l_idx);
      EXIT WHEN l_token IS NULL;
      UTL_SMTP.RCPT(l_conn, l_token);
      l_idx := l_idx + 1;
    END LOOP;

    UTL_SMTP.OPEN_DATA(l_conn);

    -- Headers
    xx_smtp_write_header(l_conn, 'From',         TRIM(p_from));
    xx_smtp_write_header(l_conn, 'To',           p_to);
    xx_smtp_write_header(l_conn, 'Subject',      NVL(p_subject, ''));
    xx_smtp_write_header(l_conn, 'MIME-Version', '1.0');

    IF NOT l_has_atts THEN
      xx_smtp_write_header(l_conn, 'Content-Type', 'text/plain; charset=UTF-8');
      xx_smtp_write_header(l_conn, 'Content-Transfer-Encoding', '8bit');
      UTL_SMTP.WRITE_DATA(l_conn, UTL_TCP.CRLF);

      l_body := xx_smtp_dot_stuff(xx_smtp_normalize_crlf(p_message));
      xx_smtp_write_clob(l_conn, l_body);

    ELSE
      l_boundary := '----=_XXSMTP_' || DBMS_RANDOM.STRING('X', 24);

      xx_smtp_write_header(
        l_conn,
        'Content-Type',
        'multipart/mixed; boundary="' || l_boundary || '"'
      );
      UTL_SMTP.WRITE_DATA(l_conn, UTL_TCP.CRLF);

      -- Text part
      UTL_SMTP.WRITE_DATA(l_conn, '--' || l_boundary || UTL_TCP.CRLF);
      UTL_SMTP.WRITE_DATA(l_conn, 'Content-Type: text/plain; charset=UTF-8' || UTL_TCP.CRLF);
      UTL_SMTP.WRITE_DATA(l_conn, 'Content-Transfer-Encoding: 8bit' || UTL_TCP.CRLF || UTL_TCP.CRLF);

      l_body := xx_smtp_dot_stuff(xx_smtp_normalize_crlf(p_message));
      xx_smtp_write_clob(l_conn, l_body);
      UTL_SMTP.WRITE_DATA(l_conn, UTL_TCP.CRLF);

      -- Attachment parts
      FOR i IN 1 .. p_attachments.COUNT LOOP
        IF p_attachments(i).content IS NULL THEN
          CONTINUE;
        END IF;

        l_name   := NVL(
                     NULLIF(TRIM(p_attachments(i).display_name), ''),
                     NULLIF(TRIM(p_attachments(i).file_name), '')
                   );
        l_name   := NVL(l_name, 'attachment_' || TO_CHAR(i));  -- <== keep intact (fixes prior truncation)
        l_mime   := NVL(NULLIF(TRIM(p_attachments(i).mime_type), ''), 'application/octet-stream');
        l_inline := NVL(p_attachments(i).inline_flag, FALSE);
        l_cid    := p_attachments(i).content_id;

        l_disp := CASE WHEN l_inline THEN 'inline' ELSE 'attachment' END;

        UTL_SMTP.WRITE_DATA(l_conn, '--' || l_boundary || UTL_TCP.CRLF);
        UTL_SMTP.WRITE_DATA(
          l_conn,
          'Content-Type: ' || l_mime || '; name="' || l_name || '"' || UTL_TCP.CRLF
        );
        UTL_SMTP.WRITE_DATA(
          l_conn,
          'Content-Disposition: ' || l_disp || '; filename="' || l_name || '"' || UTL_TCP.CRLF
        );

        IF l_inline AND TRIM(l_cid) IS NOT NULL THEN
          UTL_SMTP.WRITE_DATA(l_conn, 'Content-ID: <' || TRIM(l_cid) || '>' || UTL_TCP.CRLF);
        END IF;

        UTL_SMTP.WRITE_DATA(l_conn, 'Content-Transfer-Encoding: base64' || UTL_TCP.CRLF || UTL_TCP.CRLF);

        l_att_b64 := xx_smtp_blob_to_base64(p_attachments(i).content);
        xx_smtp_write_clob(l_conn, l_att_b64);

        UTL_SMTP.WRITE_DATA(l_conn, UTL_TCP.CRLF);
      END LOOP;

      -- Close boundary
      UTL_SMTP.WRITE_DATA(l_conn, '--' || l_boundary || '--' || UTL_TCP.CRLF);
    END IF;

    UTL_SMTP.CLOSE_DATA(l_conn);
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
  END xx_smtp_send_with_attachments;
