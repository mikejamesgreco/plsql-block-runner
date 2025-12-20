-- XX_BLOCK_CSV_PARSE_1.sql
function xx_csv_split_line(
  p_line  in varchar2,
  p_delim in varchar2 default ','
) return sys.odcivarchar2list
is
  l_out        sys.odcivarchar2list := sys.odcivarchar2list();
  l_buf        varchar2(32767) := '';
  l_in_quotes  boolean := false;
  l_i          pls_integer := 1;
  l_ch         varchar2(1);
  l_next       varchar2(1);
  l_delim      varchar2(1) := substr(nvl(p_delim, ','), 1, 1);
begin
  if p_line is null then
    l_out.extend;
    l_out(1) := null;
    return l_out;
  end if;

  while l_i <= length(p_line) loop
    l_ch := substr(p_line, l_i, 1);

    if l_in_quotes then
      if l_ch = '"' then
        l_next := case when l_i < length(p_line) then substr(p_line, l_i+1, 1) end;

        -- Escaped quote inside quoted field: ""
        if l_next = '"' then
          l_buf := l_buf || '"';
          l_i := l_i + 2;
          continue;
        else
          l_in_quotes := false;
          l_i := l_i + 1;
          continue;
        end if;
      else
        l_buf := l_buf || l_ch;
        l_i := l_i + 1;
        continue;
      end if;

    else
      if l_ch = '"' then
        l_in_quotes := true;
        l_i := l_i + 1;
        continue;

      elsif l_ch = l_delim then
        l_out.extend;
        l_out(l_out.count) := l_buf;
        l_buf := '';
        l_i := l_i + 1;
        continue;

      else
        l_buf := l_buf || l_ch;
        l_i := l_i + 1;
        continue;
      end if;
    end if;
  end loop;

  -- last field
  l_out.extend;
  l_out(l_out.count) := l_buf;

  return l_out;
end;
