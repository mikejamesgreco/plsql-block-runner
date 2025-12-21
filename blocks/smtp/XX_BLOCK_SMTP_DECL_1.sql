-- DECL: XX_BLOCK_SMTP_DECL_1
-- PURPOSE:
--   Shared SMTP configuration state for UTL_SMTP helper blocks.
--
-- NOTES:
--   - DECL files must contain declarations only (types/constants/variables).
--   - No executable statements, procedures, or functions.
--   - This block intentionally does NOT store credentials; those remain in MAIN locals.
--
-- PROVIDES:
--   g_smtp_host, g_smtp_port, g_smtp_timeout

  g_smtp_host    VARCHAR2(255);
  g_smtp_port    PLS_INTEGER;
  g_smtp_timeout PLS_INTEGER := 30;
