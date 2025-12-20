# Runtime Contract (v1)

## Driver API
See README.md for signature.


## Snippet Assembly (How the worker is built)

The driver builds a single anonymous PL/SQL worker and splices files into it in this order:

1. Framework declarations (driver-managed variables)
2. `DECL=` snippets (in config order)
3. `BLOCK=` snippets (in config order)
4. `BEGIN`
5. `MAIN=` snippet
6. `END;`

### Implications

- Multiple `DECL=` lines are supported and are concatenated into the same outer `DECLARE` section.
- `BLOCK=` files must be valid in a `DECLARE` section (procedures/functions; no anonymous blocks).
- Only the `MAIN=` snippet executes automatically. If you want a `BLOCK=` routine to run, MAIN must call it.


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
