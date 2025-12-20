# Security Policy

## Reporting a Vulnerability

If you believe you have found a security vulnerability in PL/SQL Block Runner, please **do not** open a public GitHub Issue.

Instead, report it privately using one of the following:
- GitHub Security Advisories (preferred), or
- Email: mike.james.greco@gmail.com

Please include:
- A clear description of the issue
- Reproduction steps (if possible)
- Impact assessment (what an attacker could do)
- Affected versions / commits

## Supported Versions

We generally support:
- The latest tagged release, and
- The `main` branch (current development)

Older tags may not receive security fixes.

## Security Model & Trust Boundary

PL/SQL Block Runner assembles and executes PL/SQL from files referenced by a `.conf` file. This means:

**Anyone who can modify the `.conf` file or block SQL files in the configured Oracle DIRECTORY can execute arbitrary PL/SQL with the privileges of the account running the driver.**

Treat block directories and configuration files as **trusted code**.

## Deployment Hardening Recommendations

- **Least privilege:** Run the driver using the lowest-privileged database account that can perform the required work.
- **Restrict DIRECTORY access:** Ensure only authorized DBAs/admins can create/modify Oracle DIRECTORY objects and only authorized OS users can modify the underlying filesystem paths.
- **Restrict file write access:** Limit who can place or change `.sql` / `.conf` files in the directory.
- **Avoid secrets in files:** Do not store credentials, tokens, or keys in `.sql`, `.conf`, or sample files. Prefer Oracle Wallet / external secret stores.
- **Be careful with logging:** Do not log sensitive inputs (tokens, passwords). Redact where appropriate.
- **Use allowlists for outbound calls:** If adding REST/HTTP blocks, consider allowlisting destinations and preventing arbitrary URL execution.

## Non-Goals

This repository is open source. SECURITY.md does not attempt to restrict public access to blocks. It documents:
- how to report vulnerabilities, and
- how to deploy and use the framework safely.
