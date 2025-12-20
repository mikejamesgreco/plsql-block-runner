-- XX_BLOCK_LOG_1.sql
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
