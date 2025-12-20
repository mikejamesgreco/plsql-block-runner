# Contributing to PL/SQL Block Runner

Thank you for your interest in contributing.

This project aims to provide a **shared, reusable block ecosystem** for PL/SQL batch and integration workflows. To keep the library usable and consistent, contributions must follow a few rules.

---

## What You Can Contribute

- New reusable BLOCKs (preferred)
- DECL blocks for shared data structures
- Example pipelines
- Documentation improvements
- Bug fixes

---

## Where Files Go

- `blocks/<category>/` — reusable blocks
- `blocks/_templates/` — reference templates (do not modify)
- `examples/` — runnable end-to-end pipelines
- `contracts/` — documentation only

---

## Block Requirements

Every block **must** include a header comment describing:

- Purpose
- Inputs (variables read)
- Outputs (variables written)
- Side effects (files, tables, commits, network calls)
- Error behavior

Example:

```sql
-- BLOCK: csv_read
-- PURPOSE: Reads a CSV file into global memory
-- INPUTS:
--   g_csv_dir
--   g_csv_file
-- OUTPUTS:
--   g_csv_rows
-- SIDE EFFECTS:
--   File I/O via UTL_FILE
-- ERRORS:
--   Raises on file read failure
```

---

## Design Principles

- Keep blocks small and single-purpose
- Avoid hard-coded environment values
- Do not commit inside generic blocks
- Log meaningful progress
- Respect the runtime contract

---

## Examples Required

If you add or change a block, you must:
- Update an existing example **or**
- Add a new example under `examples/`

---

## Pull Request Checklist

- [ ] Block header comment present
- [ ] Follows block style guide
- [ ] No environment-specific values or secrets
- [ ] Example added or updated
- [ ] Documentation updated if needed

---

## License

By contributing, you agree that your contributions will be licensed under the Apache 2.0 License.
