-- DECL: XX_BLOCK_SQL_STATS_DECL_1.sql
-- PURPOSE:
--   Declare shared types and global state for session statistics and execution
--   plan capture utilities (SQL stats / explain plan helper block).
--
-- NOTES:
--   - This DECL intentionally contains only variables, types, and constants.
--     All executable logic is defined in XX_BLOCK_SQL_STATS_1.sql.
--   - The block is designed to be resilient when dynamic performance views
--     (V$*) are not accessible. In that case, elapsed time can still be
--     measured and returned, and plan capture attempts will return a
--     descriptive error in the result JSON.
--

  ---------------------------------------------------------------------------
  -- Types
  ---------------------------------------------------------------------------

  SUBTYPE xx_sql_stats_name_t IS VARCHAR2(128);

  TYPE xx_sql_stat_rec IS RECORD(
    name  xx_sql_stats_name_t,
    value NUMBER
  );

  TYPE xx_sql_stat_tab IS TABLE OF xx_sql_stat_rec;

  TYPE xx_sql_stat_map IS TABLE OF NUMBER INDEX BY xx_sql_stats_name_t;

  TYPE xx_sql_xplan_lines_t IS TABLE OF VARCHAR2(4000);

  ---------------------------------------------------------------------------
  -- Globals (snapshot state)
  ---------------------------------------------------------------------------

  g_sql_stats_before    xx_sql_stat_map;
  g_sql_stats_after     xx_sql_stat_map;

  g_sql_stats_have_v    BOOLEAN := TRUE;

  g_sql_stats_t0_ticks  PLS_INTEGER; -- DBMS_UTILITY.GET_TIME ticks (1/100 sec)
  g_sql_stats_t1_ticks  PLS_INTEGER;

  g_sql_stats_tag       VARCHAR2(200);

  ---------------------------------------------------------------------------
  -- Defaults / constants
  ---------------------------------------------------------------------------

  c_sql_stats_default_top_n CONSTANT PLS_INTEGER := 25;

