# Project Instructions

- This project uses a Nix `devShell`; keep project-specific runtimes and development tools in `flake.nix`.
- Commit `flake.lock` and do not depend on globally installed language runtimes.
- Inspect `.envrc` before approving it with `direnv allow`.
- Check `just --list` and existing project documentation before inventing new commands.
- Keep changes focused and run the relevant project checks before considering work complete.
- Add only important, non-obvious project-specific conventions to this file.
