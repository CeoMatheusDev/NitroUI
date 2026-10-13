# Publishing NitroUI to GitHub

## Create a repository

Create a new **empty** GitHub repository named `nitro_ui` (do not pre-create a README, license, or `.gitignore`). Choose public or private as appropriate.

## Initialize and publish

From this directory:

```sh
git init -b main
git add .
git commit -m "chore: prepare NitroUI 0.1.0 for GitHub"
git remote add origin git@github.com:YOUR_USERNAME/nitro_ui.git
git push -u origin main
```

Replace `YOUR_USERNAME` with your GitHub username and ensure SSH authentication is configured. Alternatively use the HTTPS repository URL shown by GitHub.

## CI

`.github/workflows/ci.yml` attempts to install Zig 0.17.0, check formatting and run unit tests on pushes and pull requests. **This workflow has not been executed.** If the exact compiler release is not available to the setup action, CI will fail at installation; adjust only after verifying the actual release source.

## Important pre-publication checks

- `build.zig.zon` still has a **placeholder fingerprint** (`0x0000000000000000`); resolve it with the exact Zig 0.17.0 package tooling before treating the package as validated.
- The source has **not** been compiled or tested with Zig 0.17.0.
- No license is included: choose and add a license explicitly before inviting external contributions or reuse.
- No release or version tag has been created. Version remains `0.1.0`.
