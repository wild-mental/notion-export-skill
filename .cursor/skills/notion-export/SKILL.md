---
name: notion-export
description: Resource-complete Notion backup/export using script-based recursive Notion Export zip automation, capturing images, files, and attachments via token_v2 + file_token. Use when backing up, exporting, downloading, archiving, or recursively saving Notion pages with images, files, attachments, or resources, or when the user mentions token_v2, file_token, Notion export zip, file:// image refs, subpages, or empty signedUrls. Always prefer the token_v2 + file_token export scripts over per-file getSignedFileUrls.
---

# Notion Export Skill

Resource-complete Notion backup. The recursive **Export zip** path (`token_v2` + `file_token`)
captures page text *and* every image, file, and attachment in one archive — unlike the
public API or per-file signing, which routinely return empty asset URLs.

## Core Rule

For Notion backups where images, files, attachments, or lesson resources matter,
**use the recursive Export zip scripts first** (`export_with_token_v2.sh`).

Do not start with `getSignedFileUrls`. The known failure mode is `HTTP 200` with empty
`signedUrls`; repeated retries waste time.

## Prerequisites

- **macOS** — cookies are stored in the macOS Keychain via the `security` command.
- `python3` and `bash` on `PATH`.
- A Notion **browser session** that can open the target page (source of `token_v2` + `file_token`).

The scripts run from your **workspace** (the project directory where exports should land)
and expect to live in `<workspace>/scripts/`. Each script `cd`s to the workspace root and
writes exports there.

### Install the scripts into your workspace

If `<workspace>/scripts/` does not already contain the export scripts, fetch the bundled
copies from this skill's repo:

```bash
cd <your-workspace>
mkdir -p scripts
base=https://raw.githubusercontent.com/wild-mental/notion-export-skill/main/scripts
for f in save_notion_export_cookies.sh export_with_token_v2.sh export_notion_zip_token_v2.py \
         check_token_v2_access.sh check_token_v2_block_access.py check_notion_asset_auth.py \
         backup_with_token_v2.sh download_notion_page.py; do
  curl -fsSL "$base/$f" -o "scripts/$f"
done
chmod +x scripts/*.sh scripts/*.py
```

## Standard Command

First-time setup or cookie refresh:

```bash
cd <your-workspace>
./scripts/save_notion_export_cookies.sh
```

This stores `token_v2` and `file_token` in the macOS Keychain:

```text
service: notion-export-token-v2    (token_v2)
service: notion-export-file-token  (file_token)
account: notion-export
```

Then run an export. **The page argument is required** (the scripts no longer assume a
default page):

```bash
cd <your-workspace>
./scripts/export_with_token_v2.sh "<Notion URL or page_id>"
```

The export script reads credentials in this order:

```text
1. NOTION_TOKEN_V2 / NOTION_FILE_TOKEN environment variables
2. macOS Keychain
3. hidden terminal prompts
```

It runs a `token_v2` page-access preflight before creating the export task. If stored
Keychain credentials cannot read the page, it prompts for fresh cookies. If it prompts,
it may ask:

```text
Save/update these cookies in macOS Keychain for future runs? [y/N]:
```

The user must enter cookie values only in their **local terminal**. Never ask them to
paste these secrets into chat.

## Bundled Scripts

| Script | Role |
|--------|------|
| `save_notion_export_cookies.sh` | Store `token_v2` + `file_token` in the macOS Keychain |
| `export_with_token_v2.sh` | Main entry: preflight + recursive export zip |
| `export_notion_zip_token_v2.py` | Enqueue + poll + download + unzip the Notion export |
| `check_token_v2_access.sh` | Diagnose `token_v2` page access |
| `check_token_v2_block_access.py` | Per-origin block-access report |
| `check_notion_asset_auth.py` | Probe legacy `getSignedFileUrls` |
| `backup_with_token_v2.sh` | Legacy markdown-graph backup entry |
| `download_notion_page.py` | Legacy recursive markdown + asset downloader |

Prefer running the workspace `scripts/` copies — they write exports and summaries into the
workspace.

## Cookie Rules

- `token_v2` and `file_token` are full browser-session secrets.
- Collect them only through hidden terminal prompts.
- Do not print, log, or commit them.
- Store them only in the macOS Keychain after explicit user action/confirmation.
- Use cookies from the same browser profile and Notion account that can open the target page.
- If copied as `token_v2=...`, `file_token=...`, or from a full `Cookie:` header, the scripts
  normalize the value.

Cookie lookup:

1. Open the target Notion page in the browser account with access.
2. Open DevTools: `Cmd + Option + I`.
3. Go to `Application > Storage > Cookies`.
4. Check `https://www.notion.so` and `https://app.notion.com`.
5. Copy `token_v2`.
6. Copy `file_token` from the same browser profile/account.

## Access Diagnostic

If export fails with `User cannot access block`, verify the browser session:

```bash
cd <your-workspace>
./scripts/check_token_v2_access.sh "<Notion URL or page_id>"
```

Good result:

```json
"role": "reader" | "editor",
"has_value": true,
"matches_page": true
```

Bad result:

```json
"role": "none",
"has_value": false,
"root_present": false
```

If bad, the user copied cookies from the wrong account/profile, or the account does not have
access to the page.

If only `app.notion.com` works, retry export with:

```bash
NOTION_API_ORIGIN=https://app.notion.com ./scripts/export_with_token_v2.sh "<Notion URL or page_id>"
```

## Export Flow

The main export script:

1. Normalizes the Notion page URL/page ID to a 32-char page ID.
2. Uses `token_v2 + file_token`.
3. Enqueues a Notion internal `exportBlock` task.
4. Polls `getTasks` until an export zip URL appears.
5. Downloads the zip with `token_v2 + file_token`, `X-Notion-Space-Id`, and `Referer`.
6. Saves and unzips under `notion-exports/`.

Expected success output:

```json
{
  "zip": "notion-exports/notion-export-....zip",
  "bytes": 123456,
  "unzipped": "notion-exports/notion-export-..."
}
```

## Common Failures

### `signed_present: 0`, `signed_empty: 20`

Old per-file signing is failing:

```json
{
  "ok": false,
  "tested": 20,
  "http_200": 20,
  "signed_present": 0,
  "signed_empty": 20
}
```

Switch to Export zip. Do not keep retrying `getSignedFileUrls`.

### `User cannot access block`

Run `check_token_v2_access.sh`. If role is `none`, get cookies from the correct browser
account/profile. If Keychain cookies are stale, refresh them:

```bash
./scripts/save_notion_export_cookies.sh
```

### Zip download `HTTP 403` with HTML

The export task completed, but the download context was invalid. Re-check `file_token` from
the same profile/account as `token_v2`. The downloader must send:

```text
Cookie: token_v2=...;file_token=...
X-Notion-Space-Id: <space-id>
Referer: https://www.notion.so/
```

### `file_token` missing

Refresh the target Notion page, then re-check cookies on both `www.notion.so` and
`app.notion.com`.

### `Could not infer spaceId`

Set `NOTION_SPACE_ID` explicitly and retry:

```bash
NOTION_SPACE_ID=<space-id> ./scripts/export_with_token_v2.sh "<Notion URL or page_id>"
```

## Legacy Markdown Path

Use only after a resource-complete export is secured, or when the user explicitly wants
local Markdown graph processing:

```bash
python3 scripts/download_notion_page.py "<Notion URL or page_id>"
```

Known behavior:

- `.notion-cache/<page_id>.md` avoids re-fetching pages.
- `.notion-assets.json` records `source -> local file` after successful asset downloads.
- Re-runs skip existing non-empty asset files.
- `file://` refs and empty signed URLs mean this path is **not** resource-complete.

## Reporting

For export zip backups, report:

```text
- Export zip path
- Extracted folder path
- Zip size
- Whether access diagnostics were needed
- Any remaining manual step
```

## 스킬 발견 (Cursor)

| 위치 | 경로 |
|------|------|
| 프로젝트 | `.cursor/skills/notion-export/SKILL.md` |
| 개인 | `~/.cursor/skills/notion-export/SKILL.md` |

개인 스킬 `~/.cursor/skills/` 생성 후 UI에 안 보이면 **Reload Window** 필요.
수동 호출: `/notion-export`.
