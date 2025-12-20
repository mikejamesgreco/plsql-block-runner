declare
  -- assembled by XX_ORA_BLOCK_DRIVER
  -- binds expected: :v_retcode, :v_errbuf, :v_inputs_json, :v_result_json

  l_inputs_json  clob;
  l_result_json  clob;

  ------------------------------------------------------------------
  -- DECL: XX_BLOCK_CSV_PARSE_DECL_1.sql
  ------------------------------------------------------------------
  -- XX_BLOCK_CSV_PARSE_DECL_1.sql
  subtype xx_vc is varchar2(32767);
  
  type xx_csv_row_t is record (
    line_no  pls_integer,
    raw_line xx_vc
  );
  
  type xx_csv_table_t is table of xx_csv_row_t index by pls_integer;
  
  -- global "data we read from csv"
  g_csv_rows   xx_csv_table_t;
  g_csv_count  pls_integer := 0;
  
  -- global csv location (you can change here for demo)
  g_csv_dir    varchar2(128) := 'XX_DBADIR_SECURE';
  g_csv_file   varchar2(255) := 'sample.csv';
  
  ------------------------------------------------------------------
  -- BLOCK: XX_BLOCK_LOG_1.sql
  ------------------------------------------------------------------
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
  
  ------------------------------------------------------------------
  -- BLOCK: XX_BLOCK_CSV_PARSE_1.sql
  ------------------------------------------------------------------
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
  
  ------------------------------------------------------------------
  -- BLOCK: XX_BLOCK_CSV_READ_1.sql
  ------------------------------------------------------------------
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
  
  ------------------------------------------------------------------
  -- BLOCK: XX_BLOCK_CSV_PRINT_1.sql
  ------------------------------------------------------------------
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
  
begin
  l_inputs_json := :v_inputs_json;
  begin
    ------------------------------------------------------------------
    -- MAIN: XX_BLOCK_MAIN_PROCESS_CSV_1.sql
    ------------------------------------------------------------------
    -- XX_BLOCK_MAIN_PROCESS_CSV_1.sql
    -- Contract expectations (provided by assembled worker):
    --   l_inputs_json  CLOB  (already set from :v_inputs_json)
    --   l_result_json  CLOB  (set by MAIN; driver copies to :v_result_json)
    --   :v_retcode OUT NUMBER
    --   :v_errbuf  OUT VARCHAR2(4000)
    
    xx_log('MAIN start');
    
    declare
      l_dir     varchar2(128);
      l_file    varchar2(255);
      l_rows    pls_integer := null;
    
      l_err     varchar2(4000);
    begin
      ---------------------------------------------------------------------------
      -- Parse inputs JSON (optional)
      -- Expected shape:
      -- {
      --   "csv": { "dir": "XX_DBADIR_SECURE", "file": "sample.csv" }
      -- }
      ---------------------------------------------------------------------------
      l_dir  := null;
      l_file := null;
    
      if l_inputs_json is not null and dbms_lob.getlength(l_inputs_json) > 0 then
        begin
          -- Using SQL JSON_VALUE so this works without JSON_OBJECT_T dependency
          select json_value(l_inputs_json, '$.csv.dir'  returning varchar2(128)),
                 json_value(l_inputs_json, '$.csv.file' returning varchar2(255))
            into l_dir, l_file
            from dual;
    
          xx_log('inputs_json parsed | csv.dir='||nvl(l_dir,'<NULL>')||
                 ' | csv.file='||nvl(l_file,'<NULL>'));
        exception
          when others then
            l_err := substr(sqlerrm, 1, 4000);
            xx_log('inputs_json parse failed (ignored) | '||l_err);
            -- keep defaults
            l_dir  := null;
            l_file := null;
        end;
      else
        xx_log('inputs_json not provided | using defaults');
      end if;
    
      ---------------------------------------------------------------------------
      -- Apply defaults if inputs missing
      ---------------------------------------------------------------------------
      if l_dir  is not null then g_csv_dir  := l_dir;  end if;
      if l_file is not null then g_csv_file := l_file; end if;
    
      xx_log('CSV location resolved: dir='||g_csv_dir||' file='||g_csv_file);
    
      ---------------------------------------------------------------------------
      -- Do the work
      ---------------------------------------------------------------------------
      xx_read_csv_into_globals(g_csv_dir, g_csv_file);
      xx_print_globals_csv;
    
      l_rows := g_csv_count;
    
      ---------------------------------------------------------------------------
      -- Build result JSON for caller
      ---------------------------------------------------------------------------
      l_result_json :=
          '{'
        || '"status":"S",'
        || '"message":"CSV processed",'
        || '"csv_dir":"'  || replace(g_csv_dir,  '"', '\"')  || '",'
        || '"csv_file":"' || replace(g_csv_file, '"', '\"')  || '",'
        || '"row_count":' || nvl(to_char(l_rows), 'null')
        || '}';
    
      :v_retcode := 0;
      :v_errbuf  := null;
    
      xx_log('MAIN done | row_count='||nvl(to_char(l_rows),'NULL'));
    
    exception
      when others then
        -- MAIN owns the outcome, but the worker wrapper will also catch and set
        -- retcode/errbuf. Still, it's nice to set these explicitly here too.
        :v_retcode := 2;
        :v_errbuf  := 'MAIN: ' || substr(sqlerrm, 1, 3994);
    
        begin
          l_result_json :=
              '{'
            || '"status":"E",'
            || '"message":"' || replace(substr(sqlerrm,1,3500), '"', '\"') || '",'
            || '"csv_dir":"'  || replace(nvl(g_csv_dir,'<NULL>'),  '"', '\"')  || '",'
            || '"csv_file":"' || replace(nvl(g_csv_file,'<NULL>'), '"', '\"')  || '"'
            || '}';
        exception
          when others then
            null;
        end;
    
        xx_log('MAIN failed | '||sqlerrm);
        raise;
    end;
    
    
    :v_result_json := l_result_json;
  exception
    when others then
      :v_retcode := 2;
      :v_errbuf  := 'MAIN: ' || substr(sqlerrm, 1, 3994);
  end;
exception
  when others then
    :v_retcode := 3;
    :v_errbuf  := 'FRAMEWORK: ' || substr(sqlerrm, 1, 3989);
end;

