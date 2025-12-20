-- DECL: XX_BLOCK_LOG_DECL_1.sql
-- PURPOSE:
--   Declare shared logging state, configuration knobs, and constants used by
--   the block logging framework. These globals control log enablement, log
--   filtering by level, formatting, and optional in-memory capture of log
--   output for later inspection or return to callers.
--
-- NOTES:
--   - This DECL intentionally contains only variables, types, and constants.
--     All executable logging logic is defined in XX_BLOCK_LOG_HELPERS_1.sql.
--   - g_log_enabled and g_log_level may be modified by any BLOCK or MAIN to
--     dynamically control logging verbosity during execution.
--   - g_log_lines and g_log_line_count provide an optional in-memory log buffer;
--     this is useful when MAIN needs to return logs (e.g., as JSON) instead of
--     relying solely on DBMS_OUTPUT.
--   - Log level meanings:
--       0 = ERROR
--       1 = WARN
--       2 = INFO
--       3 = DEBUG
--   - The logging framework assumes this DECL has been included before any
--     logging helper procedures are invoked.

-- knobs (any block can change these)
g_log_enabled  BOOLEAN := TRUE;
g_log_level    PLS_INTEGER := 2;  -- 0=ERROR,1=WARN,2=INFO,3=DEBUG
g_log_prefix   VARCHAR2(200) := 'BLOCK';

-- optional buffer (handy if MAIN wants to return logs in JSON)
TYPE t_log_lines IS TABLE OF VARCHAR2(32767) INDEX BY PLS_INTEGER;
g_log_lines      t_log_lines;
g_log_line_count PLS_INTEGER := 0;

-- “constants”
c_log_error CONSTANT PLS_INTEGER := 0;
c_log_warn  CONSTANT PLS_INTEGER := 1;
c_log_info  CONSTANT PLS_INTEGER := 2;
c_log_debug CONSTANT PLS_INTEGER := 3;
