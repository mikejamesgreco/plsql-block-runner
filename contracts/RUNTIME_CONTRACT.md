# Runtime Contract (v1)

## Driver API
See README.md for signature.

## Bind Variables (Worker)
- :v_inputs_json  IN  CLOB
- :v_result_json  OUT CLOB
- :v_retcode      OUT NUMBER
- :v_errbuf       OUT VARCHAR2(4000)

## Local Bridge Variables
- l_inputs_json  CLOB
- l_result_json  CLOB

## Return Codes
- 0 = Success
- 2 = MAIN exception
- 3 = Framework exception

## Result JSON Rules
- MAIN JSON wins if provided
- Otherwise framework summary JSON is returned
