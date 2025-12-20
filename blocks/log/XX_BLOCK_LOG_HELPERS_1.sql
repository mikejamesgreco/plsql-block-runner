-- BLOCK: XX_BLOCK_LOG_HELPERS_1.sql
-- PURPOSE:
--   Provide the logging API used by block-based workers. This block defines
--   helper functions and procedures that format, filter, and emit log messages
--   based on configured log level and enablement flags.
--
--   These helpers are intended to be used by other BLOCK and MAIN files after
--   logging globals have been declared via XX_BLOCK_LOG_DECL_1.sql.
--
-- DEFINES:
--   function  xx_block_log_level_name(p_level IN PLS_INTEGER) RETURN VARCHAR2
--
--   procedure xx_block_log_log(
--     p_tag   IN VARCHAR2,
--     p_msg   IN VARCHAR2,
--     p_level IN PLS_INTEGER DEFAULT c_log_info
--   )
--
--   procedure xx_block_log_error(p_tag IN VARCHAR2, p_msg IN VARCHAR2)
--   procedure xx_block_log_warn (p_tag IN VARCHAR2, p_msg IN VARCHAR2)
--   procedure xx_block_log_info (p_tag IN VARCHAR2, p_msg IN VARCHAR2)
--   procedure xx_block_log_debug(p_tag IN VARCHAR2, p_msg IN VARCHAR2)
--
--   procedure xx_block_log_clob(
--     p_tag   IN VARCHAR2,
--     p_msg   IN CLOB,
--     p_level IN PLS_INTEGER DEFAULT c_log_debug,
--     p_chunk IN PLS_INTEGER DEFAULT 3000,
--     p_max   IN PLS_INTEGER DEFAULT 10
--   )
--
-- INPUTS:
--   Logging behavior is controlled via the following globals
--   (declared in XX_BLOCK_LOG_DECL_1.sql):
--     - g_log_enabled   (BOOLEAN)
--     - g_log_level     (PLS_INTEGER)
--     - g_log_prefix    (VARCHAR2)
--
-- OUTPUTS:
--   None (direct parameters).
--   Log output is written to:
--     - DBMS_OUTPUT
--     - g_log_lines(...) in-memory buffer
--
-- SIDE EFFECTS:
--   - Writes formatted log lines to DBMS_OUTPUT.
--   - Appends log lines to the global log buffer (g_log_lines).
--   - Increments g_log_line_count.
--
-- ERRORS:
--   No explicit error handling.
--   May raise standard Oracle errors related to DBMS_OUTPUT or LOB access
--   (e.g. buffer limits, invalid CLOB operations).
--
-- NOTES:
--   - Log filtering is performed before formatting based on g_log_level.
--   - Tag values are truncated to 60 characters.
--   - CLOB logging is chunked and capped to avoid excessive output.


FUNCTION xx_block_log_level_name(p_level IN PLS_INTEGER) RETURN VARCHAR2 IS
BEGIN
  RETURN CASE p_level
    WHEN c_log_error THEN 'ERROR'
    WHEN c_log_warn  THEN 'WARN'
    WHEN c_log_info  THEN 'INFO'
    WHEN c_log_debug THEN 'DEBUG'
    ELSE 'INFO'
  END;
END;

PROCEDURE xx_block_log_emit(p_line IN VARCHAR2) IS
BEGIN
  DBMS_OUTPUT.PUT_LINE(p_line);

  g_log_line_count := g_log_line_count + 1;
  g_log_lines(g_log_line_count) := SUBSTR(p_line, 1, 32767);
END;

PROCEDURE xx_block_log_log(
  p_tag   IN VARCHAR2,
  p_msg   IN VARCHAR2,
  p_level IN PLS_INTEGER DEFAULT c_log_info
) IS
  l_ts   VARCHAR2(30);
  l_tag  VARCHAR2(60);
BEGIN
  IF NOT g_log_enabled THEN
    RETURN;
  END IF;

  IF p_level > g_log_level THEN
    RETURN;
  END IF;

  l_ts  := TO_CHAR(SYSTIMESTAMP, 'YYYY-MM-DD HH24:MI:SS.FF3');
  l_tag := SUBSTR(NVL(p_tag,'GEN'), 1, 60);

  xx_block_log_emit(
    g_log_prefix || ' | ' ||
    l_ts || ' | ' ||
    xx_block_log_level_name(p_level) || ' | ' ||
    l_tag || ' | ' ||
    NVL(p_msg,'(null)')
  );
END;

PROCEDURE xx_block_log_error(p_tag IN VARCHAR2, p_msg IN VARCHAR2) IS
BEGIN
  xx_block_log_log(p_tag, p_msg, c_log_error);
END;

PROCEDURE xx_block_log_warn(p_tag IN VARCHAR2, p_msg IN VARCHAR2) IS
BEGIN
  xx_block_log_log(p_tag, p_msg, c_log_warn);
END;

PROCEDURE xx_block_log_info(p_tag IN VARCHAR2, p_msg IN VARCHAR2) IS
BEGIN
  xx_block_log_log(p_tag, p_msg, c_log_info);
END;

PROCEDURE xx_block_log_debug(p_tag IN VARCHAR2, p_msg IN VARCHAR2) IS
BEGIN
  xx_block_log_log(p_tag, p_msg, c_log_debug);
END;

PROCEDURE xx_block_log_clob(
  p_tag   IN VARCHAR2,
  p_msg   IN CLOB,
  p_level IN PLS_INTEGER DEFAULT c_log_debug,
  p_chunk IN PLS_INTEGER DEFAULT 3000,
  p_max   IN PLS_INTEGER DEFAULT 10
) IS
  l_len  PLS_INTEGER;
  l_pos  PLS_INTEGER := 1;
  l_take PLS_INTEGER;
  l_i    PLS_INTEGER := 0;
BEGIN
  IF p_msg IS NULL THEN
    xx_block_log_log(p_tag, '(null clob)', p_level);
    RETURN;
  END IF;

  l_len := DBMS_LOB.GETLENGTH(p_msg);

  WHILE l_pos <= l_len LOOP
    l_i := l_i + 1;
    EXIT WHEN l_i > NVL(p_max, 10);

    l_take := LEAST(NVL(p_chunk, 3000), l_len - l_pos + 1);
    xx_block_log_log(p_tag, DBMS_LOB.SUBSTR(p_msg, l_take, l_pos), p_level);
    l_pos := l_pos + l_take;
  END LOOP;

  IF l_pos <= l_len THEN
    xx_block_log_log(p_tag, '... (clob truncated after '||p_max||' chunks)', p_level);
  END IF;
END;
