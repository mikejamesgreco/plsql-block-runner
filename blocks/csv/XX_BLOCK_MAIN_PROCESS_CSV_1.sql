-- MAIN: XX_BLOCK_MAIN_PROCESS_CSV_1.sql
-- PURPOSE:
--   Example MAIN that drives the CSV demo end-to-end:
--     - resolve CSV directory/filename from optional inputs JSON (or defaults)
--     - read the CSV file into global buffers
--     - print the CSV contents/columns for inspection
--     - return a small result JSON summary to the caller
--
-- IMPORTANT:
--   This file is a MAIN *anonymous block snippet*.
--   It is spliced directly into the worker’s outer BEGIN...END block.
--   Do NOT define a procedure/function here.
--   Nested DECLARE...BEGIN...END blocks are allowed (and used below).
--
-- INPUTS:
--   l_inputs_json  CLOB  (provided by the driver; may be NULL/empty)
--   Expected shape (optional):
--     { "csv": { "dir": "<ORACLE_DIRECTORY>", "file": "<filename>" } }
--
-- OUTPUTS:
--   l_result_json  CLOB  (set by MAIN; returned to caller via driver)
--   :v_retcode     OUT NUMBER
--     0 = success
--     2 = MAIN error
--   :v_errbuf      OUT VARCHAR2(4000)
--     NULL on success; short message on failure
--
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

