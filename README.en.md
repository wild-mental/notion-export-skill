![AI Skills for Everyone](author/wildmental-bjpark.png)

# notion-export
> Skill for Cursor, Claude Code, Codex agents

**Language / 언어:** [한국어](README.md) · [English](README.en.md)

A multi-vendor Skill for backing up Notion pages completely, including images, files, and attachments. Instead of the public API or `getSignedFileUrls`, it prefers the Notion Export zip path based on `token_v2` + `file_token`, and Cursor, Claude Code, and Codex share the same canonical scripts.

---

## Core behavior

The default path of this skill is `export_with_token_v2.sh`.

```text
load token_v2/file_token
→ preflight token_v2 page access
→ create exportBlock task
→ poll getTasks
→ download zip with token_v2 + file_token + spaceId context
→ save under notion-exports/ and safely unzip
```

`getSignedFileUrls` often has a failure mode where it returns `HTTP 200` while `signedUrls` is empty, so it is not used first for backups where images and attachments matter.

---

## Requirements

- `bash`
- `python3`
- `token_v2` and `file_token` from a browser session that can open the target Notion page
- Optional OS secret manager
  - macOS: Keychain (`security`)
  - Linux: `secret-tool` (`libsecret` / GNOME Keyring)
  - Other: chmod 600 local file fallback after user confirmation

Cookies are secrets that hold full permissions of the Notion browser session. Do not paste them into chat; pass them only through the hidden terminal input of the save script.

---

## Installation

### Installing the Skill

Install the skill in either personal scope or project scope. You do not need to clone this entire distribution repo into your working repo.

| Tool | Personal path | Project path |
|------|-----------|---------------|
| Cursor | `~/.cursor/skills/notion-export/` | `.cursor/skills/notion-export/` |
| Claude Code | `~/.claude/skills/notion-export/` | `.claude/skills/notion-export/` |
| Codex | `~/.agents/skills/notion-export/` | `.agents/skills/notion-export/` |

Install personal skill:

```bash
# Cursor
mkdir -p ~/.cursor/skills/notion-export
curl -fsSL https://raw.githubusercontent.com/wild-mental/notion-export-skill/main/.cursor/skills/notion-export/SKILL.md \
  -o ~/.cursor/skills/notion-export/SKILL.md

# Claude Code
mkdir -p ~/.claude/skills/notion-export
curl -fsSL https://raw.githubusercontent.com/wild-mental/notion-export-skill/main/.claude/skills/notion-export/SKILL.md \
  -o ~/.claude/skills/notion-export/SKILL.md

# Codex
mkdir -p ~/.agents/skills/notion-export
curl -fsSL https://raw.githubusercontent.com/wild-mental/notion-export-skill/main/.agents/skills/notion-export/SKILL.md \
  -o ~/.agents/skills/notion-export/SKILL.md
```

For project skills, run the same commands from the repo root, just omitting the `~/` from the paths above.

Applying after install:

| Tool | How to apply |
|------|-----------|
| Cursor | Reload Window if the skill does not appear |
| Claude Code | Edits to existing skills apply live; a new top-level `.claude/skills/` may require a restart |
| Codex | Restart Codex if the skill does not appear |

### Installing the scripts

Place the scripts in the `scripts/` directory of the workspace where backups will be stored. Each script moves to the workspace root and then writes results to `notion-exports/` and the like.

```bash
cd <your-workspace>
mkdir -p scripts
base=https://raw.githubusercontent.com/wild-mental/notion-export-skill/main/scripts
for f in notion_export_secrets.sh save_notion_export_cookies.sh export_with_token_v2.sh \
         export_notion_zip_token_v2.py check_token_v2_access.sh \
         check_token_v2_block_access.py check_notion_asset_auth.py \
         backup_with_token_v2.sh download_notion_page.py; do
  curl -fsSL "$base/$f" -o "scripts/$f"
done
chmod +x scripts/*.sh scripts/*.py
```

---

## Token storage

`export_with_token_v2.sh` first checks whether `token_v2` and `file_token` can be retrieved before the main work.

```text
1. NOTION_TOKEN_V2 / NOTION_FILE_TOKEN environment variables
2. local secret backend
```

If either of the two tokens cannot be retrieved, it exits without starting the export. In that case, instead of pasting cookies into chat, the user runs the save script below directly in a local terminal and then runs the export again.

```bash
./scripts/save_notion_export_cookies.sh
```

You can choose the storage method with `NOTION_SECRET_BACKEND`.

| Value | Behavior |
|----|------|
| `auto` | Default. Automatically selects an available OS secret manager |
| `keychain` | Force macOS Keychain |
| `secret-tool` | Force Linux `secret-tool` |
| `file` | Force chmod 600 local file storage |
| `none` | Do not store. Both environment variables are required when running export |

Selection order for `auto`:

```text
macOS + security available        → keychain
secret-tool available             → secret-tool
otherwise                         → file
```

Default secret names:

```text
token_v2:    notion-export-token-v2
file_token:  notion-export-file-token
account:     notion-export
```

You can change the names with environment variables.

```bash
NOTION_TOKEN_V2_SERVICE=my-token-service
NOTION_FILE_TOKEN_SERVICE=my-file-service
NOTION_KEYCHAIN_ACCOUNT=my-account
```

File fallback path:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/notion-export/cookies.env
```

The file fallback stores values as base64 and restricts file permissions to `600`, but it is not encrypted storage. So by default it asks for confirmation before storing.

```bash
NOTION_SECRET_BACKEND=file ./scripts/save_notion_export_cookies.sh
NOTION_ALLOW_PLAINTEXT_STORE=1 NOTION_SECRET_BACKEND=file ./scripts/save_notion_export_cookies.sh
```

To run once without storing, pass both environment variables.

```bash
NOTION_SECRET_BACKEND=none NOTION_TOKEN_V2=<token_v2> NOTION_FILE_TOKEN=<file_token> ./scripts/export_with_token_v2.sh "<Notion URL or page_id>"
```

---

## Usage

When running for the first time or refreshing cookies:

```bash
cd <your-workspace>
./scripts/save_notion_export_cookies.sh
```

Export zip backup:

```bash
./scripts/export_with_token_v2.sh "<Notion URL or page_id>"
```

The page argument is required. You must pass a Notion URL, a 32-character page ID, or a hyphenated UUID-format page ID.

When you need to change the Notion origin:

```bash
NOTION_API_ORIGIN=https://app.notion.com ./scripts/export_with_token_v2.sh "<Notion URL or page_id>"
```

When spaceId cannot be inferred automatically:

```bash
NOTION_SPACE_ID=<space-id> ./scripts/export_with_token_v2.sh "<Notion URL or page_id>"
```

---

## Cookie input rules

`token_v2` and `file_token` must come from the same browser profile and the same Notion account. They must be cookies from a session that can actually open the target page.

You can enter the cookie value in any of the forms below. The script normalizes only the values it needs.

```text
<raw-cookie-value>
token_v2=<value>
file_token=<value>
Cookie: token_v2=<value>; file_token=<value>; ...
```

Typical path to find them in the browser:

```text
DevTools → Application → Storage → Cookies
https://www.notion.so or https://app.notion.com
```

---

## Script layout

| Script | Role |
|----------|------|
| `notion_export_secrets.sh` | Common handling of the secret store/retrieve backend based on OS and user choice |
| `save_notion_export_cookies.sh` | Receives `token_v2` and `file_token` via hidden input and stores them in the selected backend |
| `export_with_token_v2.sh` | Main entry point. Loads credentials, preflights access, runs Export zip |
| `export_notion_zip_token_v2.py` | Creates the Notion `exportBlock` task, polls, downloads the zip, and safely unzips based on URL-decode/NFC |
| `check_token_v2_access.sh` | Diagnoses whether `token_v2` can read the target page/block |
| `check_token_v2_block_access.py` | Reports block access results per origin as JSON |
| `check_notion_asset_auth.py` | Checks the legacy `getSignedFileUrls` behavior |
| `backup_with_token_v2.sh` | Legacy Markdown graph backup entry point |
| `download_notion_page.py` | Legacy recursive Markdown + asset downloader |

---

## Diagnostics

If `User cannot access block` appears:

```bash
./scripts/check_token_v2_access.sh "<Notion URL or page_id>"
```

Example of normal access:

```json
"role": "reader" | "editor",
"has_value": true,
"matches_page": true
```

Example of access failure:

```json
"role": "none",
"has_value": false,
"root_present": false
```

Failures usually mean the cookies were copied from the wrong browser profile/account, or that the account does not have permission for the page.

If the zip download fails with `HTTP 403` or an HTML response, re-check `file_token` from the same profile. The download needs all of `token_v2`, `file_token`, `X-Notion-Space-Id`, and `Referer`.

---

## Output location

```text
<your-workspace>/
├── scripts/
├── notion-exports/
│   ├── notion-export-<id>-markdown-<ts>.zip
│   └── notion-export-<id>-markdown-<ts>/
├── .notion-cache/          # legacy Markdown path
├── .notion-assets.json     # legacy asset manifest
└── backup-summary.json     # legacy summary
```

A successful Export zip output looks roughly like this:

```json
{
  "zip": "notion-exports/notion-export-....zip",
  "bytes": 123456,
  "unzipped": "notion-exports/notion-export-...",
  "unzip": {
    "extracted_files": 42,
    "normalized_paths": 3,
    "shortened_paths": 1,
    "collisions": 0,
    "rewritten_links": 2
  }
}
```

During unzip, paths inside the zip are repeatedly URL-decoded and then normalized to Unicode NFC. If a filename component exceeds the `NOTION_EXPORT_MAX_FILENAME_BYTES` limit (default 240 bytes), or a relative path exceeds the `NOTION_EXPORT_MAX_RELATIVE_PATH_BYTES` limit (default 700 bytes), it is shortened by UTF-8 bytes and a hash of the original name is appended. The original zip is preserved as-is.

Local links inside Markdown files are corrected to match the actual extracted paths, and instead of a percent-encoded URL target, they are written as an angle-bracket local path in the form `[text](<actual Korean path/file.md>)`. This is so that resolvers that do not URL-decode local link targets, such as Cursor Markdown Preview, can still find the extracted files.

To safely re-extract a zip that was already downloaded:

```bash
python3 scripts/export_notion_zip_token_v2.py --unzip-only notion-exports/notion-export-....zip --out-dir notion-exports/notion-export-...-safe
```

---

## Legacy Markdown path

Use only when, after securing an Export zip backup, you separately need local Markdown graph processing.

```bash
python3 scripts/download_notion_page.py "<Notion URL or page_id>"
```

This path uses `.notion-cache/`, `.notion-assets.json`, and `backup-summary.json`. Because `file://` references or empty signed URLs may remain, it is not considered a resource-complete backup path.

---

## Completion report criteria

After the Export zip backup, the agent checks and reports the following.

- Export zip path
- Extracted folder path
- Zip size
- Unzip statistics (`normalized_paths`, `shortened_paths`, `rewritten_links`)
- Whether access diagnostics were run
- Remaining manual steps

---

## For LLMs

<!-- install-only; operational rules live in SKILL.md after install -->

```text
skill=notion-export
repo=https://github.com/wild-mental/notion-export-skill
install.method=curl-only
platform=multi-os

flow:
  1. ask scope: personal skill (~) or project skill (./)
  2. ask tools: Cursor / Claude Code / Codex
  3. install SKILL.md for selected tool(s)+scope
  4. install scripts into workspace scripts/; include notion_export_secrets.sh
  5. run exports from workspace scripts/

scope.user.paths:
  cursor=~/.cursor/skills/notion-export/SKILL.md
  claude=~/.claude/skills/notion-export/SKILL.md
  codex=~/.agents/skills/notion-export/SKILL.md

scope.project.paths:
  cursor=.cursor/skills/notion-export/SKILL.md
  claude=.claude/skills/notion-export/SKILL.md
  codex=.agents/skills/notion-export/SKILL.md

scripts.fetch=cd <workspace> && mkdir -p scripts && base=https://raw.githubusercontent.com/wild-mental/notion-export-skill/main/scripts && for f in notion_export_secrets.sh save_notion_export_cookies.sh export_with_token_v2.sh export_notion_zip_token_v2.py check_token_v2_access.sh check_token_v2_block_access.py check_notion_asset_auth.py backup_with_token_v2.sh download_notion_page.py; do curl -fsSL "$base/$f" -o "scripts/$f"; done && chmod +x scripts/*.sh scripts/*.py

invoke.cursor=/notion-export
invoke.claude=/notion-export
invoke.codex=/skills|$notion-export

secret_backend:
  auto=macOS Keychain when security exists; Linux secret-tool when available; otherwise chmod 600 file fallback after confirmation
  keychain=force macOS Keychain
  secret-tool=force Linux secret-tool
  file=force local file fallback
  none=never save

contract:
  prefer=token_v2 + file_token recursive Export zip
  avoid=getSignedFileUrls first
  secrets=save script hidden terminal prompts only; never ask user to paste into chat
  credential_order=env vars -> local secret backend; if missing, tell user to run save_notion_export_cookies.sh
  report=zip path, extracted folder, zip bytes, access diagnostics, remaining manual step
```

---

## License

[MIT License](LICENSE)
