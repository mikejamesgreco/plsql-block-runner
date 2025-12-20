-- XX_BLOCK_CSV_PRINT_1.sql
procedure xx_print_globals_csv is
  l_fields sys.odcivarchar2list;
  l_i      pls_integer;
begin
  xx_log('Printing CSV from globals. Rows='||g_csv_count);

  for r in 1 .. g_csv_count loop
    xx_log('LINE '||g_csv_rows(r).line_no||': '||g_csv_rows(r).raw_line);

    -- default delimiter is comma; can pass a different one later if needed
    l_fields := xx_csv_split_line(g_csv_rows(r).raw_line);

    for l_i in 1 .. l_fields.count loop
      xx_log('  COL '||l_i||': '||nvl(l_fields(l_i), '<NULL>'));
    end loop;
  end loop;

  xx_log('Done printing CSV');
end;
