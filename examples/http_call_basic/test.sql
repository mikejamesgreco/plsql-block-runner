set serveroutput on size unlimited
whenever sqlerror exit failure rollback

DECLARE
  l_inputs_json  CLOB;
  l_result_json  CLOB;
  l_retcode      NUMBER;
  l_errbuf       VARCHAR2(4000);

  -- Driver config
  p_blocks_dir   VARCHAR2(200)  := 'XX_DBADIR_SECURE';
  p_conf_file    VARCHAR2(4000) := 'blocks.conf';

  -- Request params (public echo service) (https)
  /*
  p_protocol     VARCHAR2(10)   := 'https';
  p_host         VARCHAR2(4000) := 'postman-echo.com';
  p_port         NUMBER         := 443;
  p_path         VARCHAR2(4000) := '/get';
  p_verb         VARCHAR2(20)   := 'GET';

  -- if you have no cert in wallet for https test, then you might see this error:
  --
  --result_json_len=197
  --{
  --  "status" : "ERROR",
  --  "sqlerrm" : "ORA-20002: ORA-29273: HTTP request failed | ORA-29024: Certificate validation failure",
  --  "backtrace" : "ORA-06512: at line 1121\nORA-06512: at line 1288\n"
  --}

  */
  
  -- Request params (public echo service) (http only, no cert required)
  p_protocol     VARCHAR2(10)   := 'http';
  p_host         VARCHAR2(4000) := 'postman-echo.com';
  p_port         NUMBER         := 80;
  p_path         VARCHAR2(4000) := '/get';
  p_verb         VARCHAR2(20)   := 'GET';

BEGIN
  l_inputs_json :=
    '{'||
    '  "request": {'||
    '    "protocol": "'||p_protocol||'",'||
    '    "host": "'||p_host||'",'||
    '    "port": '||TO_CHAR(p_port)||','||
    '    "path": "'||p_path||'",'||
    '    "url": null,'||
    '    "verb": "'||p_verb||'",'||
    '    "url_params": {'||
    '      "foo": "bar",'||
    '      "hello": "world"'||
    '    },'||
    '    "headers": {'||
    '      "x-demo": "1"'||
    '    },'||
    '    "body_text": null,'||
    '    "body_base64": null,'||
    '    "content_type": null,'||
    '    "resp_mode": "TEXT",'||
    '    "timeout_seconds": 60'||
    '  },'||
    '  "auth": {'||
    '    "type": "NONE",'||
    '    "config": null,'||
    '    "wallet_path": null,'||
    '    "wallet_password": null'||
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
  dbms_output.put_line('errbuf='||NVL(l_errbuf,'<null>'));

  IF l_result_json IS NOT NULL THEN
    dbms_output.put_line('result_json_len='||dbms_lob.getlength(l_result_json));

    --dbms_output.put_line(dbms_lob.substr(l_result_json, 32767, 1));

    DECLARE
      l_pretty CLOB;
    BEGIN
      -- Pretty-print JSON result (works with CLOB JSON text)
      BEGIN
        SELECT JSON_SERIALIZE(l_result_json RETURNING CLOB PRETTY)
        INTO   l_pretty
        FROM   dual;
      EXCEPTION
        WHEN OTHERS THEN
          -- If JSON_SERIALIZE/PRETTY isn't supported in this DB version, fall back
          l_pretty := l_result_json;
      END;
    
      dbms_output.put_line('result_json_len='||dbms_lob.getlength(l_pretty));
    
      -- print in chunks so DBMS_OUTPUT doesn’t truncate
      DECLARE
        l_pos PLS_INTEGER := 1;
        l_len PLS_INTEGER := dbms_lob.getlength(l_pretty);
        l_take PLS_INTEGER;
      BEGIN
        WHILE l_pos <= l_len LOOP
          l_take := LEAST(32767, l_len - l_pos + 1);
          dbms_output.put_line(dbms_lob.substr(l_pretty, l_take, l_pos));
          l_pos := l_pos + l_take;
        END LOOP;
      END;
    END;
    
  END IF;

END;
/
