-- BLOCK: XX_BLOCK_SQL_STATS_1.sql
-- PURPOSE:
--   Provide reusable procedures to capture session-level performance deltas
--   and optional explain plan output for a SQL statement.
--
-- DEFINES:
--   procedure xx_sql_stats_begin
--   procedure xx_sql_stats_end
--   procedure xx_sql_stats_capture_explain
--   procedure xx_sql_stats_capture_cursor
--   procedure xx_sql_stats_build_result_json
--   procedure xx_sql_stats_run_plsql_with_stats
--
-- INPUTS:
--   xx_sql_stats_begin:
--     p_tag        Optional label to include in output.
--     p_force_v$   If TRUE, raise on missing V$ access (default FALSE).
--
--   xx_sql_stats_end:
--     p_top_n        Return only top N stat deltas by absolute value (optional).
--     p_include_list JSON array of stat names to include (optional, CLOB JSON).
--     x_result_json  Output JSON (CLOB).
--
--   xx_sql_stats_capture_explain:
--     p_sql_text     SQL text to EXPLAIN PLAN FOR
--     p_format       DBMS_XPLAN format string (e.g. 'TYPICAL', 'BASIC')
--     x_lines_json   JSON array string of plan lines (CLOB)
--     x_err          Error text if capture fails (VARCHAR2)
--
--   xx_sql_stats_capture_cursor:
--     p_sql_id       SQL_ID to display cursor plan for
--     p_child        child number (nullable -> 0)
--     p_format       DBMS_XPLAN format string (e.g. 'ALLSTATS LAST')
--     x_lines_json   JSON array string of plan lines (CLOB)
--     x_err          Error text if capture fails (VARCHAR2)
--
--   xx_sql_stats_run_plsql_with_stats:
--     p_plsql         PL/SQL block text to EXECUTE IMMEDIATE (nullable).
--     p_top_n         Stats Top N (nullable).
--     p_include_list  JSON array of stat names to include (nullable).
--     p_explain_sql   SQL to EXPLAIN (nullable).
--     p_cursor_sql_id SQL_ID for DISPLAY_CURSOR (nullable).
--     p_cursor_child  Child number (nullable).
--     p_xplan_format  XPLAN format string (nullable).
--     x_result_json   Output JSON (CLOB).
--
-- OUTPUTS:
--   JSON includes elapsed_ms and session stat deltas when available.
--   Plan lines are returned as JSON array of strings when requested.
--
-- SIDE EFFECTS:
--   Uses EXPLAIN PLAN and DBMS_XPLAN. EXPLAIN PLAN writes to PLAN_TABLE.
--
-- ERRORS:
--   All exceptions are captured and returned as JSON in xx_sql_stats_* helpers.
--

  ---------------------------------------------------------------------------
  -- Internal helpers
  ---------------------------------------------------------------------------

  FUNCTION xx_sql_stats_get_sid RETURN NUMBER IS
    l_sid NUMBER;
  BEGIN
    l_sid := TO_NUMBER(sys_context('USERENV','SID'));
    RETURN l_sid;
  EXCEPTION
    WHEN OTHERS THEN
      RETURN NULL;
  END;

  PROCEDURE xx_sql_stats_try_capture(
    p_dest OUT xx_sql_stat_map,
    p_force_v$ IN BOOLEAN DEFAULT FALSE
  ) IS
    l_sid NUMBER := xx_sql_stats_get_sid;
  BEGIN
    p_dest.DELETE;

    IF l_sid IS NULL THEN
      g_sql_stats_have_v := FALSE;
      IF p_force_v$ THEN
        RAISE_APPLICATION_ERROR(-20001, 'SQL_STATS: Unable to resolve USERENV.SID');
      END IF;
      RETURN;
    END IF;

    BEGIN
      FOR r IN (
        SELECT sn.name, ss.value
        FROM v$sesstat ss, v$statname sn
        WHERE ss.statistic# = sn.statistic#
          AND ss.sid = l_sid
      ) LOOP
        p_dest(r.name) := r.value;
      END LOOP;

      g_sql_stats_have_v := TRUE;

    EXCEPTION
      WHEN OTHERS THEN
        g_sql_stats_have_v := FALSE;
        IF p_force_v$ THEN
          RAISE;
        END IF;
    END;

  END;

  FUNCTION xx_sql_stats_json_escape(p_str VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    IF p_str IS NULL THEN
      RETURN NULL;
    END IF;

    RETURN REPLACE(
             REPLACE(
               REPLACE(
                 REPLACE(
                   REPLACE(p_str, '\', '\\')
                 , '"', '\"')
               , CHR(10), '\n')
             , CHR(13), '\r')
           , CHR(9), '\t');
  END;

  FUNCTION xx_sql_stats_map_get(p_map xx_sql_stat_map, p_name VARCHAR2) RETURN NUMBER IS
  BEGIN
    RETURN p_map(p_name);
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RETURN NULL;
  END;

  PROCEDURE xx_sql_stats_begin(
    p_tag       IN VARCHAR2 DEFAULT NULL,
    p_force_v$  IN BOOLEAN  DEFAULT FALSE
  ) IS
  BEGIN
    g_sql_stats_tag      := p_tag;
    g_sql_stats_t0_ticks := dbms_utility.get_time;

    xx_sql_stats_try_capture(g_sql_stats_before, p_force_v$);
  END;

  PROCEDURE xx_sql_stats_end(
    p_top_n        IN  PLS_INTEGER DEFAULT NULL,
    p_include_list IN  CLOB DEFAULT NULL, -- JSON array of stat names
    x_result_json  OUT CLOB
  ) IS
    l_top_n   PLS_INTEGER := NVL(p_top_n, c_sql_stats_default_top_n);
    l_elapsed_ms NUMBER;

    TYPE t_delta_rec IS RECORD(name VARCHAR2(128), delta NUMBER, absd NUMBER);
    TYPE t_delta_tab IS TABLE OF t_delta_rec;

    l_deltas t_delta_tab := t_delta_tab();

    l_json CLOB;

    -- include-list parsing
    l_use_include BOOLEAN := FALSE;
    l_includes sys.odcivarchar2list := sys.odcivarchar2list();

    PROCEDURE parse_include_list IS
      l_arr json_array_t;
      l_val VARCHAR2(4000);
    BEGIN
      IF p_include_list IS NULL THEN
        l_use_include := FALSE;
        RETURN;
      END IF;

      l_arr := json_array_t.parse(p_include_list);
      l_use_include := TRUE;
      l_includes.DELETE;

      FOR i IN 0 .. l_arr.get_size - 1 LOOP
        IF l_arr.get(i).is_string THEN
          l_val := l_arr.get_string(i);
          l_includes.EXTEND;
          l_includes(l_includes.COUNT) := l_val;
        END IF;
      END LOOP;
    EXCEPTION
      WHEN OTHERS THEN
        -- if include list invalid, ignore and fall back to top deltas
        l_use_include := FALSE;
    END;

    FUNCTION is_included(p_name VARCHAR2) RETURN BOOLEAN IS
    BEGIN
      IF NOT l_use_include THEN
        RETURN TRUE;
      END IF;
      FOR i IN 1 .. l_includes.COUNT LOOP
        IF l_includes(i) = p_name THEN
          RETURN TRUE;
        END IF;
      END LOOP;
      RETURN FALSE;
    END;

    PROCEDURE add_delta(p_name VARCHAR2, p_delta NUMBER) IS
      l_rec t_delta_rec;
    BEGIN
      IF p_delta IS NULL THEN
        RETURN;
      END IF;
      IF NOT is_included(p_name) THEN
        RETURN;
      END IF;

      l_rec.name := p_name;
      l_rec.delta := p_delta;
      l_rec.absd := ABS(p_delta);

      l_deltas.EXTEND;
      l_deltas(l_deltas.COUNT) := l_rec;
    END;

    PROCEDURE sort_deltas IS
    BEGIN
      -- simple bubble sort (N is small: stats list filtered to top_n)
      FOR i IN 1 .. l_deltas.COUNT LOOP
        FOR j IN i+1 .. l_deltas.COUNT LOOP
          IF l_deltas(j).absd > l_deltas(i).absd THEN
            DECLARE
              t t_delta_rec;
            BEGIN
              t := l_deltas(i);
              l_deltas(i) := l_deltas(j);
              l_deltas(j) := t;
            END;
          END IF;
        END LOOP;
      END LOOP;
    END;

    PROCEDURE emit_stats_json IS
      l_count PLS_INTEGER := 0;
    BEGIN
      l_json := l_json || '"stats_delta":{';

      IF NOT g_sql_stats_have_v THEN
        l_json := l_json || '"supported":false,"error":"V$ access not available"}';
        RETURN;
      END IF;

      l_json := l_json || '"supported":true';

      IF l_deltas.COUNT > 0 THEN
        l_json := l_json || ',"values":{';
        FOR i IN 1 .. l_deltas.COUNT LOOP
          EXIT WHEN l_count >= l_top_n;

          IF l_deltas(i).delta = 0 THEN
            CONTINUE;
          END IF;

          l_count := l_count + 1;

          IF l_count > 1 THEN
            l_json := l_json || ',';
          END IF;

          l_json := l_json || '"' || xx_sql_stats_json_escape(l_deltas(i).name) || '":' || TO_CHAR(l_deltas(i).delta);
        END LOOP;
        l_json := l_json || '}';
      END IF;

      l_json := l_json || '}';
    END;

  BEGIN
    g_sql_stats_t1_ticks := dbms_utility.get_time;
    l_elapsed_ms := (g_sql_stats_t1_ticks - g_sql_stats_t0_ticks) * 10;

    xx_sql_stats_try_capture(g_sql_stats_after, FALSE);

    parse_include_list;

    -- build deltas
    IF g_sql_stats_have_v THEN
      DECLARE
        l_name xx_sql_stats_name_t;
        l_before NUMBER;
        l_after NUMBER;
        l_delta NUMBER;
      BEGIN
        l_name := g_sql_stats_after.FIRST;
        WHILE l_name IS NOT NULL LOOP
          l_after := g_sql_stats_after(l_name);
          l_before := xx_sql_stats_map_get(g_sql_stats_before, l_name);
          IF l_before IS NULL THEN
            l_delta := l_after;
          ELSE
            l_delta := l_after - l_before;
          END IF;

          add_delta(l_name, l_delta);

          l_name := g_sql_stats_after.NEXT(l_name);
        END LOOP;
      END;
      sort_deltas;
    END IF;

    -- build JSON
    l_json := '{' ||
              '"status":"SUCCESS",' ||
              '"tag":' || CASE WHEN g_sql_stats_tag IS NULL THEN 'null' ELSE '"'||xx_sql_stats_json_escape(g_sql_stats_tag)||'"' END || ',' ||
              '"elapsed_ms":' || TO_CHAR(l_elapsed_ms) || ',';

    emit_stats_json;

    l_json := l_json || '}';

    x_result_json := l_json;

  EXCEPTION
    WHEN OTHERS THEN
      x_result_json :=
        '{' ||
        '"status":"ERROR",' ||
        '"tag":' || CASE WHEN g_sql_stats_tag IS NULL THEN 'null' ELSE '"'||xx_sql_stats_json_escape(g_sql_stats_tag)||'"' END || ',' ||
        '"sqlerrm":"' || xx_sql_stats_json_escape(SQLERRM) || '",' ||
        '"backtrace":"' || xx_sql_stats_json_escape(dbms_utility.format_error_backtrace) || '"' ||
        '}';
  END;

  PROCEDURE xx_sql_stats_capture_explain(
    p_sql_text   IN  CLOB,
    p_format     IN  VARCHAR2 DEFAULT 'TYPICAL',
    x_lines_json OUT CLOB,
    x_err        OUT VARCHAR2
  ) IS
    l_lines CLOB := '[';
    l_first BOOLEAN := TRUE;
    l_fmt   VARCHAR2(200) := NVL(p_format, 'TYPICAL');
  BEGIN
    x_lines_json := NULL;
    x_err := NULL;

    IF p_sql_text IS NULL THEN
      x_err := 'EXPLAIN requested but explain_sql is NULL';
      RETURN;
    END IF;

    BEGIN
      EXECUTE IMMEDIATE 'EXPLAIN PLAN FOR ' || p_sql_text;
    EXCEPTION
      WHEN OTHERS THEN
        x_err := 'EXPLAIN PLAN failed: ' || SQLERRM;
        RETURN;
    END;

    BEGIN
      FOR r IN (
        SELECT plan_table_output AS line
        FROM TABLE(dbms_xplan.display(NULL, NULL, l_fmt))
      ) LOOP
        IF NOT l_first THEN
          l_lines := l_lines || ',';
        END IF;
        l_first := FALSE;
        l_lines := l_lines || '"' || xx_sql_stats_json_escape(r.line) || '"';
      END LOOP;
      l_lines := l_lines || ']';
      x_lines_json := l_lines;
    EXCEPTION
      WHEN OTHERS THEN
        x_err := 'DBMS_XPLAN.DISPLAY failed: ' || SQLERRM;
        RETURN;
    END;

  END;

  PROCEDURE xx_sql_stats_capture_cursor(
    p_sql_id     IN  VARCHAR2,
    p_child      IN  NUMBER DEFAULT 0,
    p_format     IN  VARCHAR2 DEFAULT 'ALLSTATS LAST',
    x_lines_json OUT CLOB,
    x_err        OUT VARCHAR2
  ) IS
    l_lines CLOB := '[';
    l_first BOOLEAN := TRUE;
    l_fmt   VARCHAR2(200) := NVL(p_format, 'ALLSTATS LAST');
    l_child NUMBER := NVL(p_child, 0);
  BEGIN
    x_lines_json := NULL;
    x_err := NULL;

    IF p_sql_id IS NULL THEN
      x_err := 'DISPLAY_CURSOR requested but cursor_sql_id is NULL';
      RETURN;
    END IF;

    BEGIN
      FOR r IN (
        SELECT plan_table_output AS line
        FROM TABLE(dbms_xplan.display_cursor(p_sql_id, l_child, l_fmt))
      ) LOOP
        IF NOT l_first THEN
          l_lines := l_lines || ',';
        END IF;
        l_first := FALSE;
        l_lines := l_lines || '"' || xx_sql_stats_json_escape(r.line) || '"';
      END LOOP;
      l_lines := l_lines || ']';
      x_lines_json := l_lines;
    EXCEPTION
      WHEN OTHERS THEN
        x_err := 'DBMS_XPLAN.DISPLAY_CURSOR failed: ' || SQLERRM;
        RETURN;
    END;

  END;

  PROCEDURE xx_sql_stats_build_result_json(
    p_stats_json     IN  CLOB,
    p_xplan_kind     IN  VARCHAR2,
    p_xplan_lines    IN  CLOB,
    p_xplan_error    IN  VARCHAR2,
    x_result_json    OUT CLOB
  ) IS
    l_json CLOB;
  BEGIN
    -- p_stats_json is already a JSON object like: {"status":"SUCCESS",...}
    -- We'll wrap it with optional xplan content.
    IF p_stats_json IS NULL THEN
      x_result_json := '{"status":"ERROR","sqlerrm":"SQL_STATS: stats json is NULL"}';
      RETURN;
    END IF;

    -- remove trailing }
    l_json := RTRIM(p_stats_json);
    IF SUBSTR(l_json, -1) = '}' THEN
      l_json := SUBSTR(l_json, 1, LENGTH(l_json)-1);
    END IF;

    l_json := l_json || ',';

    l_json := l_json ||
      '"xplan":{' ||
      '"kind":' || CASE WHEN p_xplan_kind IS NULL THEN 'null' ELSE '"'||xx_sql_stats_json_escape(p_xplan_kind)||'"' END || ',' ||
      '"error":' || CASE WHEN p_xplan_error IS NULL THEN 'null' ELSE '"'||xx_sql_stats_json_escape(p_xplan_error)||'"' END || ',' ||
      '"lines":' || CASE WHEN p_xplan_lines IS NULL THEN 'null' ELSE p_xplan_lines END ||
      '}' ||
      '}';

    x_result_json := l_json;
  END;

  PROCEDURE xx_sql_stats_run_plsql_with_stats(
    p_plsql         IN  CLOB DEFAULT NULL,
    p_top_n         IN  NUMBER DEFAULT NULL,
    p_include_list  IN  CLOB DEFAULT NULL,
    p_explain_sql   IN  CLOB DEFAULT NULL,
    p_cursor_sql_id IN  VARCHAR2 DEFAULT NULL,
    p_cursor_child  IN  NUMBER DEFAULT NULL,
    p_xplan_format  IN  VARCHAR2 DEFAULT NULL,
    x_result_json   OUT CLOB
  ) IS
    l_stats_json CLOB;
    l_xplan_kind VARCHAR2(30);
    l_xplan_lines CLOB;
    l_xplan_err  VARCHAR2(4000);
  BEGIN
    xx_sql_stats_begin(p_tag => 'run_plsql_with_stats');

    -- Execute work (optional)
    IF p_plsql IS NOT NULL THEN
      EXECUTE IMMEDIATE p_plsql;
    END IF;

    xx_sql_stats_end(
      p_top_n        => CASE WHEN p_top_n IS NULL THEN NULL ELSE TRUNC(p_top_n) END,
      p_include_list => p_include_list,
      x_result_json  => l_stats_json
    );

    -- Optional plan capture
    l_xplan_kind := NULL;
    l_xplan_lines := NULL;
    l_xplan_err := NULL;

    IF p_explain_sql IS NOT NULL THEN
      l_xplan_kind := 'EXPLAIN';
      xx_sql_stats_capture_explain(
        p_sql_text   => p_explain_sql,
        p_format     => NVL(p_xplan_format, 'TYPICAL'),
        x_lines_json => l_xplan_lines,
        x_err        => l_xplan_err
      );
    ELSIF p_cursor_sql_id IS NOT NULL THEN
      l_xplan_kind := 'CURSOR';
      xx_sql_stats_capture_cursor(
        p_sql_id     => p_cursor_sql_id,
        p_child      => p_cursor_child,
        p_format     => NVL(p_xplan_format, 'ALLSTATS LAST'),
        x_lines_json => l_xplan_lines,
        x_err        => l_xplan_err
      );
    END IF;

    xx_sql_stats_build_result_json(
      p_stats_json  => l_stats_json,
      p_xplan_kind  => l_xplan_kind,
      p_xplan_lines => l_xplan_lines,
      p_xplan_error => l_xplan_err,
      x_result_json => x_result_json
    );

  EXCEPTION
    WHEN OTHERS THEN
      x_result_json :=
        '{' ||
        '"status":"ERROR",' ||
        '"sqlerrm":"' || xx_sql_stats_json_escape(SQLERRM) || '",' ||
        '"backtrace":"' || xx_sql_stats_json_escape(dbms_utility.format_error_backtrace) || '"' ||
        '}';
  END;

