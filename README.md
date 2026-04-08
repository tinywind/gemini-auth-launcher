# Gemini Auth Launcher

This toolset lets you run Gemini CLI with multiple OAuth credential source files at the same time.

It supports two modes:

1. **Global auth link switch** for one default `~/.gemini` home.
2. **Isolated per-auth launcher** for running multiple Gemini sessions at the same time.

## How isolation works

Gemini stores authentication and session state under `~/.gemini`, resolved from `GEMINI_CLI_HOME`.

This project does not use Codex CLI `auth.json`.

- The default Gemini directory is `~/.gemini`.
- Inside a Gemini home, the OAuth credentials filename is `~/.gemini/oauth_creds.json`.
- The optional account metadata file is `~/.gemini/google_accounts.json`.
- Your source OAuth credentials file can have any basename; the launcher links it into Gemini homes as `oauth_creds.json`.
- Session history, settings, skills, policies, and other Gemini-managed state also live there.

This launcher prepares an isolated `GEMINI_CLI_HOME` per OAuth credentials source file, bootstraps `~/.gemini` into that profile on first use, then runs `gemini` with `GEMINI_CLI_HOME` pointed at the isolated profile root.

## First-use bootstrap behavior

When a profile is created for the first time, the launcher copies your real `~/.gemini` into the profile's isolated `.gemini` directory.

- This preserves your existing Gemini config, skills, policies, and local state layout.
- The copied `oauth_creds.json` and `google_accounts.json` files are removed immediately.
- The profile then links those internal filenames to the selected source auth files.

Later runs for the same OAuth credentials source file reuse the same profile home instead of copying again.

If you create a named profile with `--profile`, that profile remembers its canonical OAuth credentials source path in `profile.json`.
After the first run, you can reuse that profile by name without passing `--cred-file` again.

## Companion `google_accounts.json`

Gemini may also use `google_accounts.json` alongside the internal `oauth_creds.json` filename.

- Pass `--google-accounts <path>` explicitly when you want to manage that file directly.
- If you omit it, the launcher automatically reuses the stored path for an existing named profile.
- On first use, if a sibling file named `google_accounts.json` exists next to the selected OAuth credentials file, the launcher links it automatically.

## No-copy guarantee for auth files

The launcher never copies your source auth files.

- Global mode creates symlinks under `~/.gemini/`
- Isolated mode creates symlinks under `~/.gemini-auth-launcher/profiles/<profile>/gemini-home/.gemini/`
- In both modes, the target filename inside the Gemini home is `oauth_creds.json`, even when the source file uses a different basename.

Your source auth files remain the single source of truth, so refreshed tokens stay centralized.

## Quick start

1. Install the local commands:

   ```bash
   bash ~/IdeaProjects/gemini-auth-launcher/install-bashrc-command.sh
   source ~/.bashrc
   ```

2. Run Gemini with a specific OAuth credentials file:

   ```bash
   gemini-auth --cred-file ~/gemini-auths/work/oauth_creds.json --help
   gemini-auth --cred-file ~/gemini-auths/work/oauth_creds.json -p "Summarize this folder."
   ```

3. Create a reusable named profile:

   ```bash
   gemini-auth --profile work --cred-file ~/gemini-auths/work/oauth_creds.json -p "What changed here?"
   gemini-auth-profile work --cred-file ~/gemini-auths/work/oauth_creds.json -p "What changed here?"
   ```

4. Reuse that named profile later without passing the OAuth path again:

   ```bash
   gemini-auth-profile work
   gemini-auth-home --profile work
   ```

5. Reset that profile when you want a clean start:

   ```bash
   gemini-auth-reset --yes --profile work
   ```

6. Reset every isolated profile at once:

   ```bash
   gemini-auth-reset-all --yes
   ```

## Commands

### 1) Switch the global auth link

```bash
gemini-auth-link --cred-file ~/gemini-auths/work/oauth_creds.json
gemini-auth-link --cred-file ~/gemini-auths/work/oauth_creds.json --google-accounts ~/gemini-auths/work/google_accounts.json
```

This rewires the default auth symlink under `~/.gemini`.

### 2) Run Gemini with an isolated auth home

```bash
gemini-auth --cred-file ~/gemini-auths/work/oauth_creds.json
gemini-auth --cred-file ~/gemini-auths/work/oauth_creds.json -p "Summarize this folder."
gemini-auth --profile review --cred-file ~/gemini-auths/work/oauth_creds.json -p "Summarize this folder."
gemini-auth-profile review --cred-file ~/gemini-auths/work/oauth_creds.json -p "Summarize this folder."
```

Each OAuth credentials file path gets its own isolated `GEMINI_CLI_HOME`, so Gemini session state stays separate.

### 3) Print the prepared `GEMINI_CLI_HOME` root for a profile

```bash
gemini-auth-home --cred-file ~/gemini-auths/work/oauth_creds.json
gemini-auth-home --profile review
GEMINI_CLI_HOME="$(gemini-auth-home --profile review)" gemini --help
```

### 4) Reset an existing isolated profile

```bash
gemini-auth-reset --cred-file ~/gemini-auths/work/oauth_creds.json
gemini-auth-reset --yes --cred-file ~/gemini-auths/work/oauth_creds.json
gemini-auth-reset --profile review --yes
```

### 5) Reuse config or shared assets from an existing Gemini home

```bash
gemini-auth --link-config --cred-file ~/gemini-auths/work/oauth_creds.json
gemini-auth --link-config --share-path skills --share-path policies --cred-file ~/gemini-auths/work/oauth_creds.json
gemini-auth --base-home ~/.gemini-team --share-path commands --cred-file ~/gemini-auths/team/oauth_creds.json
```

Shared paths are symlinked into the isolated profile home. This is optional and off by default.

### 6) Reset every isolated profile

```bash
gemini-auth-reset-all
gemini-auth-reset-all --yes
```

## Launcher command syntax

```bash
gemini-auth [--profile <name>] [--cred-file <path>] [--google-accounts <path>] [--base-home <path>] [--link-config] [--share-path <relative-path>]... [--print-home] [--] [gemini args...]
gemini-auth-profile <profile-name> [launcher options] [--] [gemini args...]
gemini-auth-link [--gemini-home <path>] --cred-file <oauth-creds-file> [--google-accounts <google-accounts-file>]
gemini-auth-home [--profile <name>] [--cred-file <path>] [--google-accounts <path>] [--base-home <path>] [--link-config] [--share-path <relative-path>]...
gemini-auth-reset [--profile <name>] [--cred-file <path>] [--yes]
gemini-auth-reset-all [--yes]
```

## Files created by the launcher

```text
~/.gemini-auth-launcher/
└── profiles/
    └── <profile>/
        ├── profile.json
        └── gemini-home/
            └── .gemini/
                ├── oauth_creds.json -> /path/to/your/oauth_creds.json
                ├── google_accounts.json -> /path/to/your/google_accounts.json
                ├── history/
                ├── tmp/
                ├── settings.json
                └── ... Gemini-managed state files ...

~/.local/share/gemini-auth-launcher/
├── profile-common.sh
├── run-with-auth.sh
├── run-with-profile.sh
├── link-global-auth.sh
├── reset-profile.sh
└── reset-all-profiles.sh

~/.local/bin/
├── gemini-auth
├── gemini-auth-profile
├── gemini-auth-link
├── gemini-auth-home
├── gemini-auth-reset
└── gemini-auth-reset-all
```

## Notes

- The isolated mode keeps session state separate because each profile gets its own `GEMINI_CLI_HOME`.
- The first run for a profile copies the current `~/.gemini` into that isolated home before replacing auth files with symlinks.
- Auto-generated profiles are keyed by the canonical OAuth credentials file path.
- Named profiles created with `--profile` remember their OAuth credentials file path and can be reused later without `--cred-file`.
- Passing `--cred-file` to an existing named profile rebinds that profile to the new OAuth credentials file while keeping its existing sessions and local state.
- `gemini-auth-profile` is a convenience wrapper that requires the profile name as the first positional argument.
- The installer copies standalone commands into the user-local command path instead of relying on shell function wrappers.
- `gemini-auth-reset` deletes the isolated profile directory so the next run starts from a fresh bootstrap.
- `gemini-auth-reset-all` deletes every isolated profile directory managed by the launcher.
- `--link-config` links `settings.json` from the base home. Leave it off when you want strict isolation.
- `--share-path` should only be used for files or directories you intentionally want to share.
