set serveroutput on size unlimited
whenever sqlerror exit failure rollback

DECLARE
  l_inputs_json  CLOB;
  l_result_json  CLOB;
  l_retcode      NUMBER;
  l_errbuf       VARCHAR2(4000);

  -- Params (keep these up top so it’s easy to tweak)
  p_blocks_dir   VARCHAR2(200)  := 'XX_DBADIR_SECURE';
  p_conf_file    VARCHAR2(4000) := 'blocks.conf';

  p_dir          VARCHAR2(200)  := 'XX_DBADIR_SECURE';
  p_csv_file     VARCHAR2(4000) := 'sample.csv';
BEGIN
  l_inputs_json :=
    '{'||
    '  "csv": {'||
    '    "dir": "'||p_dir||'",'||
    '    "file": "'||p_csv_file||'"'||
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

  DBMS_OUTPUT.PUT_LINE('retcode='||NVL(TO_CHAR(l_retcode),'NULL'));
  DBMS_OUTPUT.PUT_LINE('errbuf='||NVL(l_errbuf,'<NULL>'));

  IF l_result_json IS NOT NULL THEN
    DBMS_OUTPUT.PUT_LINE('result_json='||DBMS_LOB.SUBSTR(l_result_json, 32767, 1));
  ELSE
    DBMS_OUTPUT.PUT_LINE('result_json=<NULL>');
  END IF;
END;
/
