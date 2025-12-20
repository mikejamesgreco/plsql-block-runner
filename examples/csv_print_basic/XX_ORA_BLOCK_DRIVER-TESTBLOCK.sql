set serveroutput on size unlimited;

declare
  l_inputs_json clob;
  l_result_json clob;
  l_retcode     number;
  l_errbuf      varchar2(4000);
begin
  l_inputs_json := '{
    "csv": { "dir": "XX_DBADIR_SECURE", "file": "sample.csv" }
  }';

  xx_ora_block_driver(
    p_blocks_dir   => 'XX_DBADIR_SECURE',
    p_conf_file    => 'XX_BLOCK_TEMPLATE_PRINT_CSV_1.conf',
    p_inputs_json  => l_inputs_json,
    x_retcode      => l_retcode,
    x_errbuf       => l_errbuf,
    x_result_json  => l_result_json
  );

  dbms_output.put_line('CALLER retcode='||nvl(to_char(l_retcode),'NULL'));
  dbms_output.put_line('CALLER errbuf='||nvl(l_errbuf,'<NULL>'));

  dbms_output.put_line('CALLER json:');
  dbms_output.put_line(dbms_lob.substr(l_result_json, 32767, 1));
end;
/
