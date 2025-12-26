create or replace procedure xx_ora_block_driver(
  p_blocks_dir   in  varchar2,
  p_conf_file    in  varchar2,
  p_inputs_json  in  clob,
  x_retcode      out number,
  x_errbuf       out varchar2,
  x_result_json  out clob
) is
  ---------------------------------------------------------------------------
  -- XX_ORA_BLOCK_DRIVER - Dynamic PL/SQL block assembler/executor
  --
  -- Public API / status contract (reserved retcodes):
  --   0 = Success
  --   2 = MAIN failure (exception raised during MAIN section execution)
  --   3 = FRAMEWORK failure (exception raised outside MAIN section)
  --
  -- NOTE: MAIN OWNS THE OUTCOME:
  --   - On success, MAIN is responsible for setting :v_retcode / :v_errbuf.
  --   - The framework only sets retcode/errbuf when exceptions occur.
  --
  -- Bind variables expected by the constructed worker:
  --   :v_retcode      OUT NUMBER
  --   :v_errbuf       OUT VARCHAR2(4000)
  --   :v_inputs_json  IN  CLOB
  --   :v_result_json  OUT CLOB
  --
  -- Output parameters:
  --   x_retcode     OUT NUMBER
  --   x_errbuf      OUT VARCHAR2
  --   x_result_json OUT CLOB
  ---------------------------------------------------------------------------

  c_nl              constant varchar2(1)   := chr(10);
  c_log_prefix      constant varchar2(30)  := 'DRIVER | ';

  l_conf            clob;
  l_worker          clob;

  l_pos             pls_integer := 1;
  l_line            varchar2(32767);

  l_decl_files      sys.odcivarchar2list := sys.odcivarchar2list();
  l_block_files     sys.odcivarchar2list := sys.odcivarchar2list();
  l_main_file       varchar2(4000);

  v_cursor          integer := null;
  v_status          integer;

  v_errbuf          varchar2(4000);
  v_retcode         number;

  -- MAIN result JSON captured via bind
  v_result_json     clob;

  l_derived_file    varchar2(4000);

  ---------------------------------------------------------------------------
  -- Local helpers
  ---------------------------------------------------------------------------

  procedure log_driver(p_msg varchar2) is
  begin
    dbms_output.put_line(
      c_log_prefix ||
      to_char(systimestamp,'yyyy-mm-dd hh24:mi:ss.ff3') ||
      ' | ' || p_msg
    );
  end;

  function json_escape(p_text varchar2) return varchar2 is
    l_out varchar2(4000);
  begin
    if p_text is null then
      return null;
    end if;

    l_out := p_text;
    l_out := replace(l_out, '\', '\\');
    l_out := replace(l_out, '"', '\"');
    l_out := replace(l_out, chr(10), '\n');
    l_out := replace(l_out, chr(13), '\r');
    l_out := replace(l_out, chr(9),  '\t');

    return substr(l_out, 1, 4000);
  end;

  -- SAFE length check: avoids ORA-22275 if locator is invalid
  function clob_len_safe(p_clob clob) return pls_integer is
  begin
    if p_clob is null then
      return 0;
    end if;
    return dbms_lob.getlength(p_clob);
  exception
    when others then
      return 0;
  end;

  function read_file_to_clob(p_dir varchar2, p_file varchar2) return clob is
    l_fh    utl_file.file_type;
    l_txt   varchar2(32767);
    l_out   clob;
  begin
    dbms_lob.createtemporary(l_out, true);
    l_fh := utl_file.fopen(p_dir, p_file, 'R', 32767);

    loop
      begin
        utl_file.get_line(l_fh, l_txt);
      exception
        when no_data_found then exit;
      end;

      --dbms_lob.writeappend(l_out, length(l_txt), l_txt);
      if l_txt is not null then
        dbms_lob.writeappend(l_out, length(l_txt), l_txt);
      end if;      
      dbms_lob.writeappend(l_out, 1, c_nl);
    end loop;

    utl_file.fclose(l_fh);
    return l_out;

  exception
    when others then
      begin
        if utl_file.is_open(l_fh) then
          utl_file.fclose(l_fh);
        end if;
      exception
        when others then null;
      end;
      raise;
  end;

  procedure append_vc_line(p_clob in out nocopy clob, p_text varchar2) is
  begin
    if p_text is not null then
      dbms_lob.writeappend(p_clob, length(p_text), p_text);
    end if;
    dbms_lob.writeappend(p_clob, 1, c_nl);
  end;

  function next_line(p_clob clob, p_pos in out pls_integer) return varchar2 is
    l_len pls_integer := dbms_lob.getlength(p_clob);
    l_nl  pls_integer;
    l_out varchar2(32767);
  begin
    if p_pos > l_len then
      return null;
    end if;

    l_nl := dbms_lob.instr(p_clob, c_nl, p_pos);

    if l_nl = 0 then
      l_out := dbms_lob.substr(p_clob, l_len - p_pos + 1, p_pos);
      p_pos := l_len + 1;
    else
      l_out := dbms_lob.substr(p_clob, l_nl - p_pos, p_pos);
      p_pos := l_nl + 1;
    end if;

    return rtrim(l_out, chr(13));
  end;

  procedure print_clob(p_title varchar2, p_clob clob) is
    l_pos  pls_integer := 1;
    l_line varchar2(32767);
    l_len  pls_integer := nvl(dbms_lob.getlength(p_clob), 0);
  begin
    dbms_output.put_line('============================================================');
    dbms_output.put_line(p_title || ' (len='||l_len||')');
    dbms_output.put_line('============================================================');

    -- IMPORTANT:
    -- Do NOT exit when l_line is NULL because blank lines come back as '' which is NULL in PL/SQL.
    while l_pos <= l_len loop
      l_line := next_line(p_clob, l_pos);
      dbms_output.put_line(nvl(l_line, '')); -- prints blank line when l_line is NULL
    end loop;

    dbms_output.put_line('============================================================');
  end;
  
  procedure append_file_indented(
    p_target in out nocopy clob,
    p_dir    in varchar2,
    p_file   in varchar2,
    p_indent in varchar2
  ) is
    l_src      clob;
    l_len      pls_integer;
    l_pos      pls_integer := 1;
    l_nl_pos   pls_integer;
    l_seg_len  pls_integer;
    l_take     pls_integer;
    l_chunk    varchar2(32767);
  begin
    l_src := read_file_to_clob(p_dir, p_file);
    l_len := nvl(dbms_lob.getlength(l_src), 0);

    log_driver('loaded file='||p_file||' len='||l_len);

    if p_indent is null then
      -- original fast path: append as-is in 32k chunks
      while l_pos <= l_len loop
        l_take  := least(32767, l_len - l_pos + 1);
        l_chunk := dbms_lob.substr(l_src, l_take, l_pos);
        dbms_lob.writeappend(p_target, length(l_chunk), l_chunk);
        l_pos := l_pos + l_take;
      end loop;

    else
      -- safe path: indent per line without expanding a 32k VARCHAR2
      while l_pos <= l_len loop
        -- find next newline (LF). c_nl is LF in your driver.
        l_nl_pos := dbms_lob.instr(l_src, c_nl, l_pos);

        if l_nl_pos = 0 then
          -- last line (no trailing newline)
          l_seg_len := l_len - l_pos + 1;
        else
          -- include the newline char
          l_seg_len := l_nl_pos - l_pos + 1;
        end if;

        -- write indent
        dbms_lob.writeappend(p_target, length(p_indent), p_indent);

        -- write the line segment in 32k chunks (handles very long lines)
        declare
          l_off pls_integer := 0;
        begin
          while l_off < l_seg_len loop
            l_take  := least(32767, l_seg_len - l_off);
            l_chunk := dbms_lob.substr(l_src, l_take, l_pos + l_off);
            dbms_lob.writeappend(p_target, length(l_chunk), l_chunk);
            l_off := l_off + l_take;
          end loop;
        end;

        l_pos := l_pos + l_seg_len;
      end loop;
    end if;

    dbms_lob.writeappend(p_target, 1, c_nl);
  end;

  procedure write_clob_to_file(
    p_dir  in varchar2,
    p_file in varchar2,
    p_clob in clob
  ) is
    l_fh         utl_file.file_type;
    l_len        pls_integer := nvl(dbms_lob.getlength(p_clob), 0);
    l_off        pls_integer := 1;
    l_take       pls_integer;
    l_chunk      varchar2(32767);
    l_raw        raw(32767);
    l_written_b  number := 0;
    l_iter       pls_integer := 0;
  begin
    log_driver('writing derived worker file (BINARY): dir='||p_dir||' file='||p_file||' chars='||l_len);

    -- BINARY MODE avoids line-size truncation semantics
    l_fh := utl_file.fopen(p_dir, p_file, 'WB', 32767);

    while l_off <= l_len loop
      l_iter := l_iter + 1;

      l_take  := least(32767, l_len - l_off + 1);
      l_chunk := dbms_lob.substr(p_clob, l_take, l_off);

      -- NOTE: for your worker SQL this is fine (ASCII/DB charset text).
      l_raw := utl_raw.cast_to_raw(l_chunk);

      utl_file.put_raw(l_fh, l_raw, true); -- true = autoflush
      l_written_b := l_written_b + utl_raw.length(l_raw);

      -- DEBUG (keep it cheap)
      if l_iter <= 3 or l_off + l_take > l_len - 3 then
        log_driver('WRITE DEBUG bin iter='||l_iter||
                  ' off='||l_off||
                  ' take='||l_take||
                  ' chunk_chars='||length(l_chunk)||
                  ' raw_bytes='||utl_raw.length(l_raw)||
                  ' total_bytes='||l_written_b);
      end if;

      l_off := l_off + l_take;
    end loop;

    utl_file.fclose(l_fh);

    log_driver('derived worker file write complete. iters='||l_iter||' bytes_written='||l_written_b||' chars='||l_len);

  exception
    when others then
      begin
        if utl_file.is_open(l_fh) then
          utl_file.fclose(l_fh);
        end if;
      exception
        when others then null;
      end;
      raise;
  end;

  function conf_to_derived_filename(p_conf varchar2) return varchar2 is
    l_base varchar2(4000);
  begin
    l_base := regexp_replace(p_conf, '^.*[\\/]', '');

    if regexp_like(l_base, '\.conf$', 'i') then
      l_base := regexp_replace(l_base, '\.conf$', '_WORKER.sql', 1, 1, 'i');
    else
      l_base := upper(l_base) || '_WORKER.sql';
    end if;

    return trim(upper(l_base));
  end;

  procedure set_framework_result_json is
    l_json varchar2(4000);
  begin
    l_json :=
      '{'||
      '"component":"XX_ORA_BLOCK_DRIVER",'||
      '"blocks_dir":"'||json_escape(p_blocks_dir)||'",'||
      '"conf_file":"'||json_escape(p_conf_file)||'",'||
      '"worker_file":"'||json_escape(l_derived_file)||'",'||
      '"retcode":'||case when v_retcode is null then 'null' else to_char(v_retcode) end||','||
      '"errbuf":'||case when v_errbuf is null then 'null' else '"'||json_escape(v_errbuf)||'"' end||
      '}';

    dbms_lob.createtemporary(x_result_json, true);
    dbms_lob.writeappend(x_result_json, length(l_json), l_json);

    log_driver('FINAL JSON (framework) | '||l_json);
  end;

  procedure publish_outputs is
  begin
    x_retcode := v_retcode;
    x_errbuf  := v_errbuf;

    -- Prefer MAIN-produced JSON if present, otherwise framework JSON
    if clob_len_safe(v_result_json) > 0 then
      x_result_json := v_result_json;
      log_driver('FINAL JSON (main) | len='||clob_len_safe(x_result_json));
    else
      set_framework_result_json;
    end if;
  end;

  procedure log_final_result is
  begin
    log_driver('FINAL RESULT | retcode='||nvl(to_char(v_retcode),'NULL')||
               ' | errbuf='||nvl(v_errbuf,'<NULL>'));
  end;

begin
  -- ensure OUT params are always initialized
  x_retcode := null;
  x_errbuf  := null;
  x_result_json := null;

  log_driver('starting');
  log_driver('inputs | blocks_dir='||p_blocks_dir||' | conf_file='||p_conf_file||
             ' | inputs_json_len='||nvl(dbms_lob.getlength(p_inputs_json),0));

  ---------------------------------------------------------------------------
  -- 1) Read conf
  ---------------------------------------------------------------------------
  log_driver('read conf | attempting via UTL_FILE...');
  l_conf := read_file_to_clob(p_blocks_dir, p_conf_file);
  log_driver('read conf | OK | len='||dbms_lob.getlength(l_conf));

  ---------------------------------------------------------------------------
  -- 2) Print conf contents
  ---------------------------------------------------------------------------
  print_clob('CONFIG FILE CONTENTS', l_conf);

  ---------------------------------------------------------------------------
  -- 3) Parse conf
  ---------------------------------------------------------------------------
  l_pos := 1;
  loop
    exit when l_pos > dbms_lob.getlength(l_conf);

    l_line := next_line(l_conf, l_pos);

    if l_line is null then
      continue;
    end if;

    l_line := trim(l_line);
    if l_line is null or substr(l_line, 1, 1) = '#' then
      continue;
    end if;

    declare
      l_eq   pls_integer;
      l_key  varchar2(2000);
      l_val  varchar2(4000);
    begin
      l_eq := instr(l_line, '=');
      if l_eq = 0 then
        raise_application_error(-20001, 'Unknown config line (no "="): '||l_line);
      end if;

      l_key := upper(trim(substr(l_line, 1, l_eq - 1)));
      l_val := trim(substr(l_line, l_eq + 1));
      l_key := replace(l_key, chr(65279), '');

      if l_key = 'DECL' then
        l_decl_files.extend;
        l_decl_files(l_decl_files.count) := l_val;
      elsif l_key = 'BLOCK' then
        l_block_files.extend;
        l_block_files(l_block_files.count) := l_val;
      elsif l_key = 'MAIN' then
        l_main_file := l_val;
      else
        raise_application_error(-20001, 'Unknown config key: '||l_key||' line='||l_line);
      end if;
    end;
  end loop;

  log_driver('conf parsed | decl_count='||l_decl_files.count||
             ' | block_count='||l_block_files.count||
             ' | main='||nvl(l_main_file,'<NULL>'));

  if l_main_file is null then
    raise_application_error(-20002, 'MAIN not specified in config');
  end if;

  if l_block_files.count = 0 then
    raise_application_error(-20003, 'No BLOCK entries in config');
  end if;

  ---------------------------------------------------------------------------
  -- 4) Assemble worker
  ---------------------------------------------------------------------------
  log_driver('assemble worker | start');
  dbms_lob.createtemporary(l_worker, true);
  log_driver('assemble worker | temp CLOB created');

  append_vc_line(l_worker, 'declare');
  append_vc_line(l_worker, '  -- assembled by XX_ORA_BLOCK_DRIVER');
  append_vc_line(l_worker, '  -- binds expected: :v_retcode, :v_errbuf, :v_inputs_json, :v_result_json');
  append_vc_line(l_worker, null);

  -- bridge binds into local variables for MAIN/BLOCK use
  append_vc_line(l_worker, '  l_inputs_json  clob;');
  append_vc_line(l_worker, '  l_result_json  clob;');
  append_vc_line(l_worker, null);

  for i in 1 .. l_decl_files.count loop
    log_driver('assemble worker | append DECL '||i||'/'||l_decl_files.count||' | '||l_decl_files(i));
    append_vc_line(l_worker, '  ------------------------------------------------------------------');
    append_vc_line(l_worker, '  -- DECL: '||l_decl_files(i));
    append_vc_line(l_worker, '  ------------------------------------------------------------------');
    append_file_indented(l_worker, p_blocks_dir, l_decl_files(i), '  ');
    log_driver('assemble worker | worker_len='||dbms_lob.getlength(l_worker));
  end loop;

  for i in 1 .. l_block_files.count loop
    log_driver('assemble worker | append BLOCK '||i||'/'||l_block_files.count||' | '||l_block_files(i));
    append_vc_line(l_worker, '  ------------------------------------------------------------------');
    append_vc_line(l_worker, '  -- BLOCK: '||l_block_files(i));
    append_vc_line(l_worker, '  ------------------------------------------------------------------');
    append_file_indented(l_worker, p_blocks_dir, l_block_files(i), '  ');
    log_driver('assemble worker | worker_len='||dbms_lob.getlength(l_worker));
  end loop;

  ---------------------------------------------------------------------------
  -- MAIN wrapper with meaningful retcodes/prefixes
  ---------------------------------------------------------------------------
  log_driver('assemble worker | append MAIN | '||l_main_file);

  append_vc_line(l_worker, 'begin');

  -- bind -> local variable bridge
  append_vc_line(l_worker, '  l_inputs_json := :v_inputs_json;');

  append_vc_line(l_worker, '  begin');
  append_vc_line(l_worker, '    ------------------------------------------------------------------');
  append_vc_line(l_worker, '    -- MAIN: '||l_main_file);
  append_vc_line(l_worker, '    ------------------------------------------------------------------');
  append_file_indented(l_worker, p_blocks_dir, l_main_file, '    ');

  -- local variable -> bind bridge for result
  append_vc_line(l_worker, '    :v_result_json := l_result_json;');

  append_vc_line(l_worker, '  exception');
  append_vc_line(l_worker, '    when others then');
  append_vc_line(l_worker, '      :v_retcode := 2;');
  append_vc_line(l_worker, '      :v_errbuf  := ''MAIN: '' || substr(sqlerrm, 1, 3994);');
  append_vc_line(l_worker, '  end;');

  append_vc_line(l_worker, 'exception');
  append_vc_line(l_worker, '  when others then');
  append_vc_line(l_worker, '    :v_retcode := 3;');
  append_vc_line(l_worker, '    :v_errbuf  := ''FRAMEWORK: '' || substr(sqlerrm, 1, 3989);');
  append_vc_line(l_worker, 'end;');

  log_driver('assemble worker | complete | worker_len='||dbms_lob.getlength(l_worker));

  ---------------------------------------------------------------------------
  -- 4b) Write derived anonymous block to file
  ---------------------------------------------------------------------------
  l_derived_file := conf_to_derived_filename(p_conf_file);
  write_clob_to_file(p_blocks_dir, l_derived_file, l_worker);

  ---------------------------------------------------------------------------
  -- 5) Print worker then execute
  ---------------------------------------------------------------------------
  print_clob('CONSTRUCTED WORKER ANONYMOUS BLOCK', l_worker);

  v_retcode := null;
  v_errbuf  := null;

  -- IMPORTANT FIX:
  -- Pre-initialize v_result_json to a valid temp CLOB locator so that:
  --  - DBMS_SQL has a valid LOB bind buffer
  --  - If MAIN doesn't assign :v_result_json, we still don't get ORA-22275
  dbms_lob.createtemporary(v_result_json, true);
  dbms_lob.trim(v_result_json, 0);

  log_driver('execute worker | via DBMS_SQL');
  v_cursor := dbms_sql.open_cursor;

  begin
    dbms_sql.parse(v_cursor, l_worker, dbms_sql.native);

    -- outputs
    dbms_sql.bind_variable(v_cursor, ':v_retcode', v_retcode);
    dbms_sql.bind_variable(v_cursor, ':v_errbuf',  v_errbuf, 4000);

    -- inputs + result json
    dbms_sql.bind_variable(v_cursor, ':v_inputs_json', p_inputs_json);

    -- bind OUT CLOB using the valid temp locator we created above
    dbms_sql.bind_variable(v_cursor, ':v_result_json', v_result_json);

    v_status := dbms_sql.execute(v_cursor);

    dbms_sql.variable_value(v_cursor, ':v_retcode', v_retcode);
    dbms_sql.variable_value(v_cursor, ':v_errbuf',  v_errbuf);

    -- even if MAIN didn't set it, this won't be an invalid locator now
    dbms_sql.variable_value(v_cursor, ':v_result_json', v_result_json);

  exception
    when others then
      begin dbms_sql.variable_value(v_cursor, ':v_retcode', v_retcode); exception when others then null; end;
      begin dbms_sql.variable_value(v_cursor, ':v_errbuf',  v_errbuf);  exception when others then null; end;
      begin dbms_sql.variable_value(v_cursor, ':v_result_json', v_result_json); exception when others then null; end;
      raise;
  end;

  if v_cursor is not null and dbms_sql.is_open(v_cursor) then
    dbms_sql.close_cursor(v_cursor);
  end if;

  log_final_result;
  publish_outputs;

exception
  when others then
    if v_cursor is not null and dbms_sql.is_open(v_cursor) then
      dbms_sql.close_cursor(v_cursor);
    end if;

    -- failure inside the DRIVER itself
    v_retcode := 3;
    v_errbuf  := 'FRAMEWORK: ' || substr(sqlerrm, 1, 3989);

    log_driver('FAILED | '||sqlerrm);
    log_final_result;

    -- publish OUT params even on failure (caller can inspect)
    v_result_json := null;
    publish_outputs;

    raise;
end;
/
