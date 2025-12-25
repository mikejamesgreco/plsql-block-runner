set serveroutput on size unlimited
whenever sqlerror exit failure rollback
set define off

DECLARE
  l_inputs_json  CLOB;
  l_result_json  CLOB;
  l_retcode      NUMBER;
  l_errbuf       VARCHAR2(4000);

  -- Driver config
  p_blocks_dir   VARCHAR2(200)  := 'XX_DBADIR_SECURE';
  p_conf_file    VARCHAR2(4000) := 'blocks.conf';

  PROCEDURE run_case(p_inputs CLOB) IS
    l_pretty CLOB;
  BEGIN
    l_inputs_json := p_inputs;

    xx_ora_block_driver(
      p_blocks_dir   => p_blocks_dir,
      p_conf_file    => p_conf_file,
      p_inputs_json  => l_inputs_json,
      x_retcode      => l_retcode,
      x_errbuf       => l_errbuf,
      x_result_json  => l_result_json
    );

    dbms_output.put_line('retcode='||l_retcode);
    dbms_output.put_line('errbuf='||NVL(l_errbuf,'<null>'));

    IF l_result_json IS NOT NULL THEN
      dbms_output.put_line('result_json_len='||dbms_lob.getlength(l_result_json));

      BEGIN
        SELECT JSON_SERIALIZE(l_result_json RETURNING CLOB PRETTY)
        INTO   l_pretty
        FROM   dual;
      EXCEPTION
        WHEN OTHERS THEN
          l_pretty := l_result_json;
      END;

      dbms_output.put_line('pretty_json_len='||dbms_lob.getlength(l_pretty));

      DECLARE
        l_pos  PLS_INTEGER := 1;
        l_len  PLS_INTEGER := dbms_lob.getlength(l_pretty);
        l_take PLS_INTEGER;
      BEGIN
        WHILE l_pos <= l_len LOOP
          l_take := LEAST(32767, l_len - l_pos + 1);
          dbms_output.put_line(dbms_lob.substr(l_pretty, l_take, l_pos));
          l_pos := l_pos + l_take;
        END LOOP;
      END;
    END IF;

    dbms_output.put_line('------------------------------------------------------------');
  END;

BEGIN

  -- Setup: create source file
  declare
    l_f utl_file.file_type;
  begin
    l_f := utl_file.fopen('XX_DBADIR_SECURE', 'ut_copy_src.txt', 'w', 32767);
    utl_file.put_line(l_f, 'copy me');
    utl_file.fclose(l_f);
  end;
  
  run_case(q'~{
    "op": "COPY",
    "src_dir": "XX_DBADIR_SECURE",
    "src_name": "ut_copy_src.txt",
    "dst_dir": "XX_DBADIR_SECURE",
    "dst_name": "ut_copy_dst.txt",
    "overwrite": true
  }~');
  
  run_case(q'~{
    "op": "GETATTR",
    "dir": "XX_DBADIR_SECURE",
    "name": "ut_copy_dst.txt"
  }~');
  
  run_case(q'~{
    "op": "READ_TEXT",
    "dir": "XX_DBADIR_SECURE",
    "name": "ut_copy_dst.txt"
  }~');
  
  run_case(q'~{
    "op": "DELETE",
    "dir": "XX_DBADIR_SECURE",
    "name": "ut_copy_src.txt"
  }~');
  
  run_case(q'~{
    "op": "DELETE",
    "dir": "XX_DBADIR_SECURE",
    "name": "ut_copy_dst.txt"
  }~');

END;
/
