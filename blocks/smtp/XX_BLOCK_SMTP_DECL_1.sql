-- DECL: XX_BLOCK_SMTP_DECL_1
-- PURPOSE:
--   Shared SMTP configuration and attachment types for UTL_SMTP helper blocks.
--
-- NOTES:
--   - DECL files must contain declarations only (types/constants/variables).
--   - No executable statements, procedures, or functions.
--   - This block intentionally does NOT store credentials; those remain in MAIN locals.
--
-- PROVIDES:
--   g_smtp_host, g_smtp_port, g_smtp_timeout
--   xx_smtp_attachment_rec, xx_smtp_attachment_tab

  ----------------------------------------------------------------------
  -- SMTP configuration
  ----------------------------------------------------------------------
  g_smtp_host    VARCHAR2(255);
  g_smtp_port    PLS_INTEGER;
  g_smtp_timeout PLS_INTEGER := 30;

  ----------------------------------------------------------------------
  -- Attachment support (0..N)
  --
  -- file_name     : the source filename (e.g. from DBA directory)
  -- display_name  : the filename shown to recipient (defaults to file_name)
  -- mime_type     : e.g. application/pdf (defaults to application/octet-stream)
  -- content       : attachment payload as BLOB (must be populated by MAIN)
  -- inline_flag   : TRUE for inline, FALSE for attachment
  -- content_id    : optional Content-ID (used when inline; referenced as <cid>)
  ----------------------------------------------------------------------
  TYPE xx_smtp_attachment_rec IS RECORD (
    file_name     VARCHAR2(4000),
    display_name  VARCHAR2(4000),
    mime_type     VARCHAR2(255),
    content       BLOB,
    inline_flag   BOOLEAN,
    content_id    VARCHAR2(255)
  );

  -- Nested table so callers can use EXTEND / COUNT / (i) indexing
  TYPE xx_smtp_attachment_tab IS TABLE OF xx_smtp_attachment_rec;
