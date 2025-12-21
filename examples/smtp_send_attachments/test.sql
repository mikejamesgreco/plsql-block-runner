-- test_multi_attach.sql
set serveroutput on size unlimited
whenever sqlerror exit failure rollback

DECLARE
  l_inputs_json  CLOB;
  l_result_json  CLOB;
  l_retcode      NUMBER;
  l_errbuf       VARCHAR2(4000);

  -- Params (easy to tweak)
  p_blocks_dir   VARCHAR2(200)  := 'XX_DBADIR_SECURE';
  p_conf_file    VARCHAR2(4000) := 'blocks.conf';

  -- SMTP params
  p_smtp_host    VARCHAR2(255)  := 'outgoingmail.gentex.com';
  p_smtp_port    NUMBER         := 25;
  p_smtp_timeout NUMBER         := 30;
  p_auth_type    VARCHAR2(30)   := 'NONE';

  -- Mail params
  p_mail_from    VARCHAR2(512)  := 'do-not-reply@gentex.com';
  p_mail_to      VARCHAR2(4000) := 'mike.greco@gentex.com';
  p_mail_subject VARCHAR2(1000) := 'PLSQL Block Runner SMTP Multi-Attach Test';
  p_mail_message VARCHAR2(4000) := 'Hello from xx_ora_block_driver!  This email includes attachments.';

  -- Attachments
  p_att_dir      VARCHAR2(255)  := 'XX_DBADIR_SECURE'; -- DBA DIRECTORY name
BEGIN
  ---------------------------------------------------------------------------
  -- Build inputs JSON using JSON_OBJECT_T to avoid escaping/quoting problems
  ---------------------------------------------------------------------------
  DECLARE
    l_root   JSON_OBJECT_T := JSON_OBJECT_T();
    l_smtp   JSON_OBJECT_T := JSON_OBJECT_T();
    l_mail   JSON_OBJECT_T := JSON_OBJECT_T();
    l_atts   JSON_OBJECT_T := JSON_OBJECT_T();
    l_files  JSON_ARRAY_T  := JSON_ARRAY_T();

    l_f1 JSON_OBJECT_T := JSON_OBJECT_T();
    l_f2 JSON_OBJECT_T := JSON_OBJECT_T();
  BEGIN
    -- smtp
    l_smtp.put('host',      p_smtp_host);
    l_smtp.put('port',      p_smtp_port);
    l_smtp.put('timeout',   p_smtp_timeout);
    l_smtp.put('auth_type', p_auth_type);

    -- mail
    l_mail.put('from',    p_mail_from);
    l_mail.put('to',      p_mail_to);
    l_mail.put('subject', p_mail_subject);
    l_mail.put('message', p_mail_message);

    -- attachments (0..N)
    l_atts.put('directory', p_att_dir);

    -- Attachment #1
    l_f1.put('file_name', 'sample1.pdf');                 -- file in DBA dir
    l_f1.put('name',      'Sample One.pdf');              -- shown to recipient (optional)
    l_f1.put('mime',      'application/pdf');             -- optional
    l_f1.put('inline',    false);                         -- optional
    l_files.append(l_f1);

    -- Attachment #2
    l_f2.put('file_name', 'sample2.zip');
    l_f2.put('name',      'Sample Two.zip');
    l_f2.put('mime',      'application/zip');
    l_f2.put('inline',    false);
    l_files.append(l_f2);

    l_atts.put('files', l_files);

    -- root
    l_root.put('smtp',        l_smtp);
    l_root.put('mail',        l_mail);
    l_root.put('attachments', l_atts);

    l_inputs_json := l_root.to_clob;
  END;

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
