set serveroutput on size unlimited
whenever sqlerror exit failure rollback

DECLARE
  l_inputs_json  CLOB;
  l_result_json  CLOB;
  l_retcode      NUMBER;
  l_errbuf       VARCHAR2(4000);

  p_blocks_dir   VARCHAR2(200) := 'XX_DBADIR_SECURE';
  p_conf_file    VARCHAR2(4000) := 'blocks.conf';

  p_dir          VARCHAR2(200) := 'XX_DBADIR_SECURE';
  p_input_file   VARCHAR2(4000) := 'sample.csv';
  p_zip_file     VARCHAR2(4000) := 'sample.zip';
BEGIN
  l_inputs_json :=
    '{'||
    '  "file": {'||
    '    "dir": "'||p_dir||'",'||
    '    "name": "'||p_input_file||'"'||
    '  },'||
    '  "zip": {'||
    '    "dir": "'||p_dir||'",'||
    '    "zip_file": "'||p_zip_file||'",'||
    '    "entry_name": "'||p_input_file||'",'||
    '    "charset": "AL32UTF8"'||
    '  }'||
    '}';

  xx_ora_block_driver(
    p_blocks_dir   => p_blocks_dir,
    p_conf_file    => p_conf_file,
    p_inputs_json  => l_inputs_json,
    x_retcode      => l_retcode,
    x_errbuf       => l_errbuf,
    x_result_json  => l_result_json
  );

  dbms_output.put_line('retcode='||l_retcode);
  dbms_output.put_line('errbuf='||l_errbuf);

  IF l_result_json IS NOT NULL THEN
    dbms_output.put_line('result_json='||dbms_lob.substr(l_result_json, 32767, 1));
  END IF;
END;
/
