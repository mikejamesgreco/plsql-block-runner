-- PURPOSE
--   This test validates that:
--     1) the Block Runner framework can assemble/execute the worker, and
--     2) the SQL Stats block can:
--         - measure elapsed time for a unit of work, and
--         - capture session statistics deltas (when V$ access is available), and
--         - return an EXPLAIN PLAN for a provided SQL statement.
--
-- QUICK START
--   1) Run as-is once to verify your setup works end-to-end.
--   2) Then replace:
--        - sql_stats.explain_sql  (the statement you want an EXPLAIN PLAN for)
--      Optionally also replace:
--        - run.plsql              (the unit of work you want to measure)
--
-- WHAT THIS TEST DOES
--   - The "run.plsql" snippet executes a simple query:
--       SELECT COUNT(*) FROM ALL_OBJECTS
--     This is just a safe baseline that works on most databases.
--
--   - The "sql_stats.explain_sql" string is sent to:
--       EXPLAIN PLAN FOR <sql_stats.explain_sql>
--     and the resulting plan is returned as text lines via DBMS_XPLAN.
--
-- IMPORTANT: EXPLAIN PLAN vs RUNTIME PLAN
--   - EXPLAIN PLAN is the optimizer's estimated plan shape.
--   - It does NOT prove the plan was actually used at runtime.
--   - If you need the *actual* plan for a specific execution, use the
--     DISPLAY_CURSOR mode test (requires SQL_ID, privileges, and the cursor
--     still present in shared pool).
--
-- HOW TO READ THE JSON RESULT
--   status
--     - SUCCESS means the block executed and returned JSON normally.
--
--   elapsed_ms
--     - Wall-clock time of the measured region (run.plsql + stats overhead).
--     - For real comparisons, run multiple times with the same inputs.
--
--   stats_delta.supported
--     - TRUE  : this schema can read session stats (V$SESSTAT/V$STATNAME).
--     - FALSE : you'll still get elapsed_ms, but "values" may be absent.
--
--   stats_delta.values
--     - Deltas (changes) in selected session stats during the measured region.
--     - Most useful when comparing versions of the same workload.
--
--   xplan.kind
--     - "EXPLAIN" when explain_sql is provided (this test).
--
--   xplan.lines
--     - The formatted plan text (DBMS_XPLAN output).
--     - Look here for plan-shape changes (INDEX RANGE SCAN vs FULL SCAN, etc.).
--
-- WHAT IS "GOOD" vs "BAD" (RULES OF THUMB)
--   Good signs (generally):
--     - consistent gets stays stable or decreases between versions
--     - physical reads stays near zero for small lookups / cached workloads
--     - parse count (hard) is low after warm-up (ideally 0 in repeated runs)
--     - elapsed_ms is stable and scales with the work performed
--
--   Red flags (investigate if you see these in real workloads):
--     - consistent gets increases significantly without a functional change
--     - physical reads appears or spikes (disk I/O) for small queries
--     - parse count (hard) increases every run (dynamic SQL / missing binds)
--     - redo size is high in code you believe is read-only (unexpected DML)
--     - elapsed_ms spikes while logical I/O stays flat (locking/waits)
--
-- CUSTOMIZATION TIPS
--   - Replace explain_sql with the statement you want to inspect:
--       "explain_sql": "SELECT ... FROM ... WHERE ..."
--
--   - Keep explain_sql as a single SQL statement (no trailing semicolon).
--   - If your statement uses bind variables, EXPLAIN PLAN may not reflect
--     bind-peeking behavior; consider DISPLAY_CURSOR for runtime inspection.
--
--   - Replace run.plsql with the exact block you want to measure:
--       "plsql": "BEGIN <your code>; END;"
--
--   - For meaningful comparisons:
--       - run each scenario multiple times
--       - ignore the first run if caching/parsing effects matter
--
-- REQUIREMENTS / SETUP
--   - p_blocks_dir must point to an Oracle DIRECTORY containing blocks.conf and
--     all referenced block files.
--   - EXPLAIN PLAN must be permitted (PLAN_TABLE available/accessible).
--   - Optional: V$ session stats access if you want stats_delta.values.

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

  -- Capture stats + EXPLAIN PLAN for COUNT(*) from ALL_OBJECTS
  l_inputs_json := q'~{
  "sql_stats": {
    "top_n": 25,
    "include_list": [
      "consistent gets",
      "physical reads",
      "redo size",
      "parse count (hard)",
      "parse count (total)",
      "CPU used by this session"
    ],
      "explain_sql": "SELECT COUNT(*) FROM ALL_OBJECTS",
      "xplan_format": "TYPICAL"
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
        SELECT json_serialize(json(l_result_json) RETURNING CLOB PRETTY)
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