# PL/SQL Block Runner

**Composable, configuration-driven execution for PL/SQL pipelines**

PL/SQL Block Runner is a lightweight, Oracle-native framework that assembles and executes ordered PL/SQL *blocks* from a simple `.conf` file. It enables teams to build reusable, auditable, and maintainable pipelines using small SQL files instead of monolithic procedures.

Any workload that can be expressed in PL/SQL—file processing, integrations, transformations, validations, or orchestration—can be implemented using this framework.

This project is designed for real-world Oracle environments, including EBS, Fusion integrations, file-based pipelines, CSV import/export, and long-lived enterprise batch logic.

---


## Block Types and Assembly Model

This project treats each `.sql` file as a *snippet* that gets **spliced** into a generated worker (`*_WORKER.sql`) by the driver.

The driver generates one anonymous PL/SQL block shaped like:

```plsql
DECLARE
  -- framework vars (l_inputs_json, l_result_json, etc.)

  -- DECL snippets (from DECL= lines, in order)

  -- BLOCK snippets (from BLOCK= lines, in order)
BEGIN
  -- MAIN snippet (from MAIN= line)
END;
```

That assembly model drives the rules below.

### `DECL=` files (declarations only)

`DECL=` snippets are inserted into the **outer `DECLARE` section**. For long-term sanity, keep them limited to:

- types
- constants
- variables (shared “globals” for the worker, typically prefixed `g_`)

Avoid putting procedure/function bodies in `DECL=` files (it *can* work in some cases, but it makes ordering fragile and harder to review).

**Template:**

```plsql
/* XX_BLOCK_SOMETHING_DECL_1.sql
   Purpose: shared state for ... 
*/
TYPE t_something IS RECORD (...);
g_something t_something;
```

### `BLOCK=` files (procedures/functions only)

`BLOCK=` snippets are also inserted into the **outer `DECLARE` section**, so they must be “declare-section friendly”.

✅ Allowed:

- `PROCEDURE ... IS/AS ... BEGIN ... END;`
- `FUNCTION ... RETURN ... IS/AS ... BEGIN ... END;`

❌ Not allowed at top-level of a `BLOCK=` snippet:

- `DECLARE ... BEGIN ... END;` (anonymous blocks)
- a bare `BEGIN ... END;`
- free-floating executable statements outside a procedure/function

**Template:**

```plsql
/* XX_BLOCK_THING_DO_1.sql
   Defines: xx_block_thing_do
   Depends on: XX_BLOCK_THING_DECL_1.sql
*/
PROCEDURE xx_block_thing_do IS
BEGIN
  -- work here
END;
```

### `MAIN=` file (executed statements)

`MAIN=` is inserted into the **outer `BEGIN ... END;`** and is what actually runs.

- This is where you orchestrate calls to your `BLOCK=` procedures/functions.
- A nested `DECLARE ... BEGIN ... END;` inside MAIN is fine (it’s just a nested statement block).

**Template:**

```plsql
DECLARE
  -- local vars for MAIN
BEGIN
  -- call block procedures in order
  -- set :v_retcode, :v_errbuf, l_result_json
END;
```

### Minimizing shared state

Prefer passing state via local variables + parameters, but because snippets are spliced together,
some shared state is unavoidable. When you need shared state:

- declare it in a dedicated `*_DECL_*.sql` file
- prefix worker-level shared variables with `g_`
- keep “input” variables separate from “output” variables (e.g., `g_zip_entry_name` vs `g_zip_blob`)

## Why This Exists

Oracle teams frequently struggle with:

- Large, fragile PL/SQL procedures
- Copy/paste batch logic across concurrent programs
- Hard-coded execution paths
- Poor reuse and low visibility
- Difficult audits and upgrades

PL/SQL Block Runner solves this by introducing **explicit composition**:

> *Many small blocks, one predictable driver.*

---

## Key Concepts

### Driver
The driver is the only entry point you execute directly. It:

- Reads a configuration file
- Loads block source files from a directory
- Assembles a single anonymous PL/SQL worker
- Binds inputs and outputs
- Executes the worker
- Owns framework-level error handling

The driver is intentionally thin and contains no business logic.

### Configuration File (`.conf`)
A `.conf` file defines *what runs* and *in what order*.

```ini
DECL=XX_BLOCK_CSV_PARSE_DECL_1.sql
BLOCK=XX_BLOCK_LOG_1.sql
BLOCK=XX_BLOCK_CSV_PARSE_1.sql
BLOCK=XX_BLOCK_CSV_READ_1.sql
BLOCK=XX_BLOCK_CSV_PRINT_1.sql
MAIN=XX_BLOCK_MAIN_PROCESS_CSV_1.sql
```

Rules:
- Order matters
- Exactly one `MAIN` block is required
- Zero or many `DECL` blocks are allowed
- One or more `BLOCK` entries are required

### Block Types
- **DECL** – shared types, records, and globals
- **BLOCK** – small, single-purpose processing steps
- **MAIN** – owns inputs, outputs, and success/failure

---

## Runtime Contract (Quick Summary)

Public driver API:

```plsql
procedure xx_ora_block_driver(
  p_blocks_dir   in  varchar2,
  p_conf_file    in  varchar2,
  p_inputs_json  in  clob,
  x_retcode      out number,
  x_errbuf       out varchar2,
  x_result_json  out clob
);
```

- `p_inputs_json` – caller-supplied JSON request
- `x_retcode / x_errbuf` – canonical execution outcome
- `x_result_json` – MAIN-produced JSON payload, or framework summary

See `contracts/RUNTIME_CONTRACT.md` for the full, versioned contract.

---

## Quick Start

```sql
declare
  l_inputs clob := '{"csv":{"dir":"XXG_DBADIR_SECURE","file":"sample.csv"}}';
  l_json   clob;
  l_rc     number;
  l_eb     varchar2(4000);
begin
  xx_ora_block_driver(
    p_blocks_dir  => 'XX_DBADIR_SECURE',
    p_conf_file   => 'XX_BLOCK_TEMPLATE_PRINT_CSV_1.conf',
    p_inputs_json => l_inputs,
    x_retcode     => l_rc,
    x_errbuf      => l_eb,
    x_result_json => l_json
  );

  dbms_output.put_line('retcode='||l_rc||' errbuf='||nvl(l_eb,'<null>'));
  dbms_output.put_line(dbms_lob.substr(l_json, 32767, 1));
end;
/
```

---

## Repository Structure

```
plsql-block-runner/
├── driver/              # Core execution engine
├── blocks/              # Reusable block library
│   ├── csv/
│   ├── log/
│   └── _templates/
├── contracts/           # Runtime & contribution contracts
├── examples/            # Runnable end-to-end examples
├── CONTRIBUTING.md
└── README.md
```

---

## Roadmap

### v1.0 (current)
- Stable driver and runtime contract
- CSV processing example
- Logging and parsing blocks
- Templates and contribution rules

### v1.1
- Standard result JSON conventions (optional)
- Per-block timing metrics
- Control flags (`dry_run`, `max_rows`, `debug`)

### v1.2
- File archive/move/delete blocks
- REST invocation blocks
- JSON helper and validation blocks

---

## Contributing

Contributions are welcome and encouraged.

Please read `CONTRIBUTING.md` before submitting blocks or changes.

---

## License

Apache 2.0
