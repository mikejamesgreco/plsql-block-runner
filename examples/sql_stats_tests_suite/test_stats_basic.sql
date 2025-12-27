-- PURPOSE:
--   Baseline sanity test for the SQL Stats / Explain Plan block.
--
-- WHAT THIS TEST DOES:
--   - Executes a trivial PL/SQL loop (no SQL statements inside the loop).
--   - Captures session-level statistic deltas and elapsed time.
--   - Verifies that the stats framework itself is functioning correctly.
--
-- HOW TO READ THE RESULTS:
--   elapsed_ms
--     - Wall-clock time for the measured region.
--     - Includes PL/SQL overhead and minimal Oracle internal work.
--     - For this test, very small values are expected.
--
--   stats_delta.supported
--     - TRUE  : schema has access to V$ session statistics.
--     - FALSE : stats collection is unavailable; elapsed_ms is still valid.
--
--   stats_delta.values
--     - Shows *deltas* in session statistics (not absolute totals).
--     - Values reflect Oracle internal activity such as parsing,
--       cursor management, and memory reuse.
--
-- INTERPRETING COMMON STATS:
--   parse count (hard)
--     - Hard parses should be low.
--     - Repeated hard parses across executions can indicate excessive
--       dynamic SQL or missing bind variables.
--
--   consistent gets / db block gets
--     - Logical I/O indicators.
--     - Should be near zero for this test since no SQL work is done.
--     - Large values here in real workloads often indicate full scans
--       or inefficient join plans.
--
--   physical reads
--     - Disk reads.
--     - Any non-zero value in simple logic can be a red flag.
--
--   redo size
--     - Amount of redo generated.
--     - Should be near zero for read-only logic.
--     - Unexpected redo may indicate hidden DML or trigger activity.
--
--   session pga / uga memory
--     - Net memory deltas.
--     - Negative values are normal and indicate memory being released.
--     - Consistently growing memory across runs may indicate leaks.
--
-- WHAT IS *NOT* A PROBLEM HERE:
--   - Small hard parse counts
--   - Small recursive calls
--   - Negative memory deltas
--   - Internal enqueue activity
--
-- xplan SECTION:
--   - xplan is NULL in this test because no EXPLAIN PLAN or
--     DISPLAY_CURSOR was requested.
--   - This is expected behavior.
--
-- EXPECTED OUTCOME:
--   - status = SUCCESS
--   - Very small elapsed_ms
--   - Minimal session stat deltas
--   - No xplan output
--
-- NOTE:
--   This test validates the *measurement infrastructure*, not query
--   performance. Use other tests with real SQL to evaluate plans
--   and performance regressions.

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
  -- Basic stats capture around a simple loop
  l_inputs_json := q'~{
  "sql_stats": {
      "top_n": 15
    },
    "run": {
      "plsql": "BEGIN FOR i IN 1..2000 LOOP NULL; END LOOP; END;"
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
