-- MAIN: XX_BLOCK_MAIN_SQL_STATS_1.sql
-- PURPOSE:
--   Generic MAIN to execute an optional PL/SQL snippet and return session stats
--   deltas and optional XPLAN output as JSON.
--
-- INPUTS (inputs_json):
--   {
--     "sql_stats": {
--       "top_n": 25,
--       "include_list": ["consistent gets","physical reads","redo size"],
--       "explain_sql": "select ...",
--       "cursor_sql_id": null,
--       "cursor_child": 0,
--       "xplan_format": "TYPICAL"
--     },
--     "run": {
--       "plsql": "BEGIN ... END;"
--     }
--   }
--
-- OUTPUTS:
--   l_result_json set to a JSON object with:
--     status, elapsed_ms, stats_delta, xplan
--

DECLARE
  l_root          JSON_OBJECT_T;
  l_sql_stats     JSON_OBJECT_T;
  l_run           JSON_OBJECT_T;

  l_top_n         NUMBER;
  l_include_list  CLOB;

  l_explain_sql   CLOB;
  l_cursor_sql_id VARCHAR2(30);
  l_cursor_child  NUMBER;
  l_xplan_format  VARCHAR2(200);

  l_plsql         CLOB;

BEGIN
  l_root := JSON_OBJECT_T.parse(l_inputs_json);

  IF l_root.has('sql_stats') THEN
    l_sql_stats := l_root.get_object('sql_stats');
  ELSE
    l_sql_stats := JSON_OBJECT_T();
  END IF;

  IF l_root.has('run') THEN
    l_run := l_root.get_object('run');
  ELSE
    l_run := JSON_OBJECT_T();
  END IF;

  l_top_n := NULL;
  IF l_sql_stats.has('top_n') THEN
    l_top_n := l_sql_stats.get_number('top_n');
  END IF;

  -- include_list as JSON array text
  l_include_list := NULL;
  IF l_sql_stats.has('include_list') THEN
    DECLARE
      l_arr JSON_ARRAY_T;
    BEGIN
      l_arr := l_sql_stats.get_array('include_list');
      l_include_list := l_arr.to_clob;
    EXCEPTION
      WHEN OTHERS THEN
        l_include_list := NULL;
    END;
  END IF;

  l_explain_sql := NULL;
  IF l_sql_stats.has('explain_sql') THEN
    l_explain_sql := l_sql_stats.get_string('explain_sql');
  END IF;

  l_cursor_sql_id := NULL;
  IF l_sql_stats.has('cursor_sql_id') THEN
    l_cursor_sql_id := l_sql_stats.get_string('cursor_sql_id');
  END IF;

  l_cursor_child := NULL;
  IF l_sql_stats.has('cursor_child') THEN
    l_cursor_child := l_sql_stats.get_number('cursor_child');
  END IF;

  l_xplan_format := NULL;
  IF l_sql_stats.has('xplan_format') THEN
    l_xplan_format := l_sql_stats.get_string('xplan_format');
  END IF;

  l_plsql := NULL;
  IF l_run.has('plsql') THEN
    l_plsql := l_run.get_string('plsql');
  END IF;

  xx_sql_stats_run_plsql_with_stats(
    p_plsql         => l_plsql,
    p_top_n         => l_top_n,
    p_include_list  => l_include_list,
    p_explain_sql   => l_explain_sql,
    p_cursor_sql_id => l_cursor_sql_id,
    p_cursor_child  => l_cursor_child,
    p_xplan_format  => l_xplan_format,
    x_result_json   => l_result_json
  );

EXCEPTION
  WHEN OTHERS THEN
    l_result_json :=
      '{' ||
      '"status":"ERROR",' ||
      '"sqlerrm":"' || REPLACE(REPLACE(SQLERRM,'"','\"'), CHR(10), '\n') || '",' ||
      '"backtrace":"' || REPLACE(REPLACE(dbms_utility.format_error_backtrace,'"','\"'), CHR(10), '\n') || '"' ||
      '}';
END;
