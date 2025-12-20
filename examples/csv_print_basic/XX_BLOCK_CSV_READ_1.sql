-- XX_BLOCK_CSV_READ_1.sql
procedure xx_read_csv_into_globals(
  p_dir  in varchar2,
  p_file in varchar2
) is
  l_fh     utl_file.file_type;
  l_line   varchar2(32767);
  l_rowno  pls_integer := 0;
begin
  xx_log('Reading CSV into globals: dir='||p_dir||' file='||p_file);

  -- reset globals
  g_csv_rows.delete;
  g_csv_count := 0;

  l_fh := utl_file.fopen(p_dir, p_file, 'R', 32767);

  loop
    begin
      utl_file.get_line(l_fh, l_line);
    exception
      when no_data_found then
        exit;
    end;

    l_rowno := l_rowno + 1;

    -- normalize line endings (UTL_FILE strips LF but CR can appear)
    l_line := rtrim(l_line, chr(13));

    g_csv_count := g_csv_count + 1;
    g_csv_rows(g_csv_count).line_no  := l_rowno;
    g_csv_rows(g_csv_count).raw_line := l_line;
  end loop;

  utl_file.fclose(l_fh);

  xx_log('Read complete. Rows='||g_csv_count);

exception
  when others then
    begin
      if utl_file.is_open(l_fh) then
        utl_file.fclose(l_fh);
      end if;
    exception
      when others then null;
    end;

    xx_log('ERROR in xx_read_csv_into_globals: '||sqlerrm);
    raise;
end;
