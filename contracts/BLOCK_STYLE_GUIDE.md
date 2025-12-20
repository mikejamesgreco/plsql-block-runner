# Block Style Guide


## Structural Rules (Important)

Because the driver **splices** snippets into a single generated anonymous worker, each file must match its role:

- **DECL snippets** (`DECL=`): declarations only (types/constants/variables).  
  Recommended: *no* procedure/function bodies in `DECL=` files.
- **BLOCK snippets** (`BLOCK=`): define **procedures/functions only**.  
  Do **not** start a block file with `DECLARE` or `BEGIN`.
- **MAIN snippet** (`MAIN=`): the executable driver logic. This is where you call your block procedures.  
  A nested `DECLARE ... BEGIN ... END;` inside MAIN is OK.

If a `BLOCK=` file contains a top-level `DECLARE ... BEGIN ... END;`, the worker will fail to compile with
`PLS-00103: Encountered the symbol "DECLARE" ...` because the outer worker is still in its `DECLARE` section.

## Naming Conventions

- Worker-level shared variables: prefix with `g_` (declared in `*_DECL_*.sql`)
- Block entry points: prefix with `xx_block_` (e.g., `xx_block_zip_add_clob`)
- Keep filenames versioned: `..._1.sql`, `..._2.sql`, etc. when behavior changes

All blocks must include a header comment describing:
- Purpose
- Inputs
- Outputs
- Side effects
- Error behavior

Blocks should:
- Be small and single-purpose
- Avoid hardcoded environment values
- Log meaningful progress