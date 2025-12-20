-- BLOCK: XX_BLOCK_LOG_1.sql
-- PURPOSE:
--   Provide a simple, standalone logging utility that writes timestamped
--   messages to DBMS_OUTPUT. Intended for lightweight diagnostics, quick
--   testing, or use in environments where the full block logging framework
--   is not required.
--
-- DEFINES:
--   procedure xx_log(p_msg IN VARCHAR2)
--
-- INPUTS:
--   p_msg IN VARCHAR2
--     Message text to log. If NULL, the literal '<NULL>' is logged.
--
-- OUTPUTS:
--   None.
--   Log output is written to DBMS_OUTPUT.
--
-- SIDE EFFECTS:
--   - Writes one or more lines to DBMS_OUTPUT.
--   - Long messages are chunked to avoid DBMS_OUTPUT line-length limits.
--
-- ERRORS:
--   No explicit error handling.
--   May raise standard Oracle errors related to DBMS_OUTPUT if output is
--   disabled or buffer limits are exceeded.

procedure xx_log(p_msg varchar2) is
  l_msg   varchar2(32767);
  l_off   pls_integer := 1;
  l_take  pls_integer;
begin
  l_msg := to_char(systimestamp,'yyyy-mm-dd hh24:mi:ss.ff3') || ' | ' || nvl(p_msg,'<NULL>');

  -- DBMS_OUTPUT has practical line limits; chunk it to be safe
  while l_off <= length(l_msg) loop
    l_take := least(250, length(l_msg) - l_off + 1);
    dbms_output.put_line(substr(l_msg, l_off, l_take));
    l_off := l_off + l_take;
  end loop;
end;
