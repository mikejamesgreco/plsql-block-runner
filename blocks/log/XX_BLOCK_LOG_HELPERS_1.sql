/* XX_BLOCK_LOG_HELPERS_1.sql
   Local logging routines for the assembled anonymous worker.
   Requires XX_BLOCK_LOG_DECL_1.sql to have already run in DECL section.
*/

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
