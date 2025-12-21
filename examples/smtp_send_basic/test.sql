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

  -- SMTP params
  p_smtp_host    VARCHAR2(255)  := 'YOUR_SMTP_HOST_HERE';
  p_smtp_port    NUMBER         := 25;
  p_smtp_timeout NUMBER         := 30;
  p_auth_type    VARCHAR2(30)   := 'NONE';

  -- Mail params
  p_mail_from    VARCHAR2(512)  := 'from@example.com';
  p_mail_to      VARCHAR2(4000) := 'to@example.com';
  p_mail_subject VARCHAR2(1000) := 'PLSQL Block Runner SMTP Test';
  p_mail_message VARCHAR2(4000) := 'Hello from xx_ora_block_driver!';
BEGIN
  l_inputs_json :=
    '{'|| 
    '  "smtp": {'||
    '    "host": "'||p_smtp_host||'",'||
    '    "port": '||p_smtp_port||','||
    '    "timeout": '||p_smtp_timeout||','||
    '    "auth_type": "'||p_auth_type||'"'||
    '  },'||
    '  "mail": {'||
    '    "from": "'||p_mail_from||'",'||
    '    "to": "'||p_mail_to||'",'||
    '    "subject": "'||REPLACE(p_mail_subject,'"','\"')||'",'||
    '    "message": "'||REPLACE(p_mail_message,'"','\"')||'"'||
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
    DBMS_OUTPUT.PUT_LINE(
      'result_json='||DBMS_LOB.SUBSTR(l_result_json, 32767, 1)
    );
  ELSE
    DBMS_OUTPUT.PUT_LINE('result_json=<NULL>');
  END IF;
END;
/
