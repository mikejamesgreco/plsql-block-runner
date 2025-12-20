/* XX_BLOCK_LOG_DECL_1.sql
   Logging state only (vars/types/constants).
   Helpers are defined in XX_BLOCK_LOG_HELPERS_1.sql
*/

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
