-- PURPOSE:
--   This test captures:
--     - session-level statistic deltas for a unit of work, and
--     - the *actual runtime execution plan* for a previously executed SQL
--       statement using DBMS_XPLAN.DISPLAY_CURSOR.
--
-- IMPORTANT DIFFERENCE FROM EXPLAIN PLAN:
--   - DISPLAY_CURSOR shows the plan that was *actually used at runtime*.
--   - It can include real row counts (A-Rows) when ALLSTATS LAST is available.
--   - This is the preferred method for diagnosing performance regressions.
--
-- HOW THIS TEST WORKS:
--   1) The PL/SQL block in run.plsql executes a SQL statement so that a cursor
--      exists in the shared pool.
--   2) sql_stats.cursor_sql_id identifies *which* cursor to inspect.
--   3) DBMS_XPLAN.DISPLAY_CURSOR is used to fetch the runtime plan.
--
-- NOTE:
--   DISPLAY_CURSOR does NOT execute SQL.
--   It inspects a cursor that already exists in the shared pool.
--
-- ---------------------------------------------------------------------------
-- HOW TO USE THIS TEST
-- ---------------------------------------------------------------------------
--
-- STEP 1: Run this test ONCE as-is (with the placeholder SQL_ID).
--         This verifies the framework executes correctly.
--         The DISPLAY_CURSOR step will fail gracefully with an error message.
--
-- STEP 2: Find the SQL_ID for the statement you want to inspect.
--         Immediately after running the test, execute the following query
--         in the SAME schema:
--
--   SELECT sql_id,
--          child_number,
--          executions,
--          last_active_time,
--          sql_text
--   FROM   v$sql
--   WHERE  sql_text = 'SELECT COUNT(*) FROM ALL_OBJECTS'
--   ORDER  BY last_active_time DESC;
--
--   If the exact match does not appear (PL/SQL wraps SQL internally),
--   use a broader search:
--
--   SELECT sql_id,
--          child_number,
--          executions,
--          last_active_time,
--          sql_text
--   FROM   v$sql
--   WHERE  UPPER(sql_text) LIKE '%COUNT(*)%'
--   AND    UPPER(sql_text) LIKE '%ALL_OBJECTS%'
--   ORDER  BY last_active_time DESC;
--
-- STEP 3: Replace the placeholder values:
--         - cursor_sql_id  -> SQL_ID from the query above
--         - cursor_child   -> CHILD_NUMBER from the same row
--
-- STEP 4: Re-run this test.
--         The xplan section should now include:
--           - Plan hash value
--           - Operation tree
--           - A-Rows vs E-Rows (when ALLSTATS LAST is available)
--
-- ---------------------------------------------------------------------------
-- HOW TO READ THE RESULT
-- ---------------------------------------------------------------------------
--
--   xplan.kind
--     - "CURSOR" indicates runtime plan inspection (expected here).
--
--   xplan.lines
--     - Formatted DBMS_XPLAN output.
--     - Look for:
--         * A-Rows vs E-Rows mismatches (optimizer misestimation)
--         * Unexpected FULL TABLE SCANs
--         * Join order changes
--         * Plan hash changes between runs
--
-- COMMON FAILURE MODES (NOT BLOCK ERRORS):
--   - ORA- errors in xplan.error usually mean:
--       * insufficient privileges on V$SQL
--       * cursor aged out of shared pool
--       * SQL_ID does not belong to this session/schema
--
-- EXPECTED OUTCOME:
--   - status = SUCCESS
--   - stats_delta populated (if V$ access exists)
--   - xplan populated after SQL_ID replacement
--
-- REQUIRED PRIVILEGES (Non-Prod):
--   This test uses DBMS_XPLAN.DISPLAY_CURSOR and session statistics.
--   The following read-only access is required for the executing schema
--   (replace <SCHEMA> with the schema running the test):
--
--   Minimal grants:
--     GRANT SELECT ON V_$SESSTAT TO <SCHEMA>;
--     GRANT SELECT ON V_$STATNAME TO <SCHEMA>;
--     GRANT SELECT ON V_$SQL TO <SCHEMA>;
--     GRANT SELECT ON V_$SQL_PLAN TO <SCHEMA>;
--     GRANT SELECT ON V_$SQL_PLAN_STATISTICS_ALL TO <SCHEMA>;
--     GRANT SELECT ON V_$SESSION TO <SCHEMA>;
--     GRANT SELECT ON V_$INSTANCE TO <SCHEMA>;
--
--   Alternative (broader, simpler):
--     GRANT SELECT_CATALOG_ROLE TO <SCHEMA>;
--
--   Notes:
--     - Read-only access only
--     - Intended for non-production environments
--     - Required to inspect SQL_IDs, session stats, and runtime execution plans


set serveroutput on size unlimited
whenever sqlerror exit failure rollback
set define off

DECLARE
  l_inputs_json  CLOB;
  l_result_json  CLOB;
  l_retcode      NUMBER;
  l_errbuf       VARCHAR2(4000);

  -- Driver config
  p_blocks_dir   VARCHAR2(200)  := 'XX_DBADIR_SECURE';
  p_conf_file    VARCHAR2(4000) := 'blocks.conf';

BEGIN
  -- DISPLAY_CURSOR example (requires SQL_ID) - placeholder
  l_inputs_json := q'~{
    "sql_stats": {
      "top_n": 25,
      "cursor_sql_id": "__REPLACE_WITH_SQL_ID__",
      "cursor_child": 0,
      "xplan_format": "ALLSTATS LAST"
    },
    "run": {
      "plsql": "DECLARE l_cnt NUMBER; BEGIN SELECT COUNT(*) INTO l_cnt FROM ALL_OBJECTS; END;"
    }
  }~';

  xx_ora_block_driver(
    p_blocks_dir   => p_blocks_dir,
    p_conf_file    => p_conf_file,
    p_inputs_json  => l_inputs_json,
    x_retcode      => l_retcode,
    x_errbuf       => l_errbuf,
    x_result_json  => l_result_json
  );

  dbms_output.put_line('retcode='||l_retcode);
  dbms_output.put_line('errbuf='||NVL(l_errbuf,'<null>'));

  IF l_result_json IS NOT NULL THEN
    dbms_output.put_line('result_json_len='||dbms_lob.getlength(l_result_json));

    DECLARE
      l_pretty CLOB;
    BEGIN
      BEGIN
        -- Prefer JSON_SERIALIZE over JSON(...) wrapper for broad DB compatibility
        SELECT json_serialize(l_result_json RETURNING CLOB PRETTY)
        INTO l_pretty
        FROM dual;
      EXCEPTION
        WHEN OTHERS THEN
          l_pretty := l_result_json;
      END;

      dbms_output.put_line('pretty_json_len='||dbms_lob.getlength(l_pretty));

      DECLARE
        l_pos  PLS_INTEGER := 1;
        l_len  PLS_INTEGER := dbms_lob.getlength(l_pretty);
        l_take PLS_INTEGER;
      BEGIN
        WHILE l_pos <= l_len LOOP
          l_take := LEAST(30000, l_len - l_pos + 1);
          dbms_output.put_line(dbms_lob.substr(l_pretty, l_take, l_pos));
          l_pos := l_pos + l_take;
        END LOOP;
      END;
    END;
  END IF;

END;
/
