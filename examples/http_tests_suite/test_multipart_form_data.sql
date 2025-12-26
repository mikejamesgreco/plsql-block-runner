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

BEGIN
  -- Multipart/form-data POST to httpbin.org/post
  -- Uses request.multipart_parts so MAIN builds the multipart payload and sets content_type/binary body.
  l_inputs_json := q'~{
  "request": {
    "protocol": "http",
    "host": "httpbin.org",
    "port": 80,
    "path": "/post",
    "url": null,
    "verb": "POST",
    "url_params": {
      "suite": "multipart"
    },
    "headers": {
      "x-demo": "multipart-form-data-1"
    },
    "multipart_parts": [
      { "name": "field1", "content_type": "text/plain", "text": "hello world" },
      { "name": "metadata", "content_type": "application/json", "text": "{\"a\":1,\"b\":\"two\"}" },
      { "name": "file1", "filename": "hello.txt", "content_type": "text/plain", "base64": "SGVsbG8gZnJvbSBQTC9TUUwhCg==" }
    ],
    "multipart_boundary": null,
    "body_text": null,
    "body_base64": null,
    "content_type": null,
    "resp_mode": "TEXT",
    "timeout_seconds": 60
  },
  "auth": {
    "type": "NONE",
    "config": null,
    "wallet_path": null,
    "wallet_password": null
  }
}~';

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

    DECLARE
      l_pretty CLOB;
    BEGIN
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
    END;
  END IF;

END;
/
