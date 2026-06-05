![AI Skills for Everyone](author/wildmental-bjpark.png)

# notion-export
> Skill for Cursor, Claude Code, Codex agents

Notion 페이지를 이미지, 파일, 첨부까지 빠짐없이 백업하기 위한 멀티 벤더 Skill입니다. 공개 API나 `getSignedFileUrls` 대신 `token_v2` + `file_token` 기반의 Notion Export zip 경로를 우선 사용하고, Cursor, Claude Code, Codex가 같은 스크립트 정본을 공유합니다.

---

## 핵심 동작

이 스킬의 기본 경로는 `export_with_token_v2.sh`입니다.

```text
token_v2/file_token 로드
→ token_v2 페이지 접근 preflight
→ exportBlock 작업 생성
→ getTasks 폴링
→ token_v2 + file_token + spaceId 컨텍스트로 zip 다운로드
→ notion-exports/ 아래 저장 및 압축 해제
```

`getSignedFileUrls`는 `HTTP 200`을 반환하면서도 `signedUrls`가 비어 있는 실패 모드가 자주 있으므로, 이미지와 첨부가 중요한 백업에서는 먼저 사용하지 않습니다.

---

## 요구 사항

- `bash`
- `python3`
- 대상 Notion 페이지를 열 수 있는 브라우저 세션의 `token_v2`와 `file_token`
- 선택적 OS secret manager
  - macOS: Keychain (`security`)
  - Linux: `secret-tool` (`libsecret` / GNOME Keyring)
  - 그 외: 사용자 확인 후 chmod 600 로컬 파일 fallback

쿠키는 Notion 브라우저 세션 전체 권한을 가진 secret입니다. 채팅에 붙여넣지 말고, 스크립트의 숨김 터미널 입력으로만 전달하세요.

---

## 설치

### Skill 설치

스킬은 개인 범위 또는 프로젝트 범위 중 하나로 설치합니다. 이 배포 repo 전체를 작업 repo에 clone할 필요는 없습니다.

| 도구 | 개인 경로 | 프로젝트 경로 |
|------|-----------|---------------|
| Cursor | `~/.cursor/skills/notion-export/` | `.cursor/skills/notion-export/` |
| Claude Code | `~/.claude/skills/notion-export/` | `.claude/skills/notion-export/` |
| Codex | `~/.agents/skills/notion-export/` | `.agents/skills/notion-export/` |

개인 스킬 설치:

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

프로젝트 스킬은 repo 루트에서 위 경로의 `~/`만 빼고 실행합니다.

설치 후 반영:

| 도구 | 반영 방법 |
|------|-----------|
| Cursor | 스킬이 보이지 않으면 Reload Window |
| Claude Code | 기존 스킬 수정은 live 반영, 새 top-level `.claude/skills/`는 재시작이 필요할 수 있음 |
| Codex | 스킬이 보이지 않으면 Codex 재시작 |

### 스크립트 설치

스크립트는 백업 결과를 저장할 워크스페이스의 `scripts/`에 둡니다. 각 스크립트는 워크스페이스 루트로 이동한 뒤 `notion-exports/` 등에 결과를 씁니다.

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

## 토큰 저장 방식

스크립트는 credentials를 아래 순서로 읽습니다.

```text
1. NOTION_TOKEN_V2 / NOTION_FILE_TOKEN 환경 변수
2. 로컬 secret backend
3. 숨김 터미널 입력
```

`NOTION_SECRET_BACKEND`로 저장 방식을 고를 수 있습니다.

| 값 | 동작 |
|----|------|
| `auto` | 기본값. 사용 가능한 OS secret manager를 자동 선택 |
| `keychain` | macOS Keychain 강제 |
| `secret-tool` | Linux `secret-tool` 강제 |
| `file` | chmod 600 로컬 파일 저장 강제 |
| `none` | 저장하지 않음. 환경 변수 또는 프롬프트만 사용 |

`auto`의 선택 순서:

```text
macOS + security 사용 가능        → keychain
secret-tool 사용 가능             → secret-tool
그 외                             → file
```

기본 secret 이름:

```text
token_v2:    notion-export-token-v2
file_token:  notion-export-file-token
account:     notion-export
```

환경 변수로 이름을 바꿀 수 있습니다.

```bash
NOTION_TOKEN_V2_SERVICE=my-token-service
NOTION_FILE_TOKEN_SERVICE=my-file-service
NOTION_KEYCHAIN_ACCOUNT=my-account
```

파일 fallback 경로:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/notion-export/cookies.env
```

파일 fallback은 값을 base64로 저장하고 파일 권한을 `600`으로 제한하지만, 암호화 저장은 아닙니다. 그래서 기본적으로 저장 전에 확인을 묻습니다.

```bash
NOTION_SECRET_BACKEND=file ./scripts/save_notion_export_cookies.sh
NOTION_ALLOW_PLAINTEXT_STORE=1 NOTION_SECRET_BACKEND=file ./scripts/save_notion_export_cookies.sh
```

저장을 원하지 않으면:

```bash
NOTION_SECRET_BACKEND=none ./scripts/export_with_token_v2.sh "<Notion URL or page_id>"
```

`export_with_token_v2.sh`가 실행 중 새 쿠키를 입력받은 경우, 기본적으로 저장 여부를 묻습니다. 저장 질문을 끄려면 `NOTION_SAVE_COOKIES=0`을 사용합니다.

```bash
NOTION_SAVE_COOKIES=0 ./scripts/export_with_token_v2.sh "<Notion URL or page_id>"
```

---

## 사용 방법

처음 실행하거나 쿠키를 갱신할 때:

```bash
cd <your-workspace>
./scripts/save_notion_export_cookies.sh
```

Export zip 백업:

```bash
./scripts/export_with_token_v2.sh "<Notion URL or page_id>"
```

페이지 인자를 생략하면 스크립트에 설정된 기본 root page를 사용합니다. 일반적인 백업에서는 대상 페이지 URL 또는 page ID를 명시하는 것을 권장합니다.

Notion origin을 바꿔야 할 때:

```bash
NOTION_API_ORIGIN=https://app.notion.com ./scripts/export_with_token_v2.sh "<Notion URL or page_id>"
```

spaceId를 자동 추론하지 못할 때:

```bash
NOTION_SPACE_ID=<space-id> ./scripts/export_with_token_v2.sh "<Notion URL or page_id>"
```

---

## 쿠키 입력 규칙

`token_v2`와 `file_token`은 같은 브라우저 프로필과 같은 Notion 계정에서 가져와야 합니다. 대상 페이지를 실제로 열 수 있는 세션의 쿠키여야 합니다.

쿠키 값은 아래 형태 모두 입력할 수 있습니다. 스크립트가 필요한 값만 정규화합니다.

```text
<raw-cookie-value>
token_v2=<value>
file_token=<value>
Cookie: token_v2=<value>; file_token=<value>; ...
```

브라우저에서 확인하는 일반 경로:

```text
DevTools → Application → Storage → Cookies
https://www.notion.so 또는 https://app.notion.com
```

---

## 스크립트 구성

| 스크립트 | 역할 |
|----------|------|
| `notion_export_secrets.sh` | OS와 사용자 선택에 따라 secret 저장/조회 backend를 공통 처리 |
| `save_notion_export_cookies.sh` | `token_v2`와 `file_token`을 숨김 입력으로 받아 선택된 backend에 저장 |
| `export_with_token_v2.sh` | 메인 진입점. credential 로드, 접근 preflight, Export zip 실행 |
| `export_notion_zip_token_v2.py` | Notion `exportBlock` 작업 생성, 폴링, zip 다운로드, 압축 해제 |
| `check_token_v2_access.sh` | `token_v2`가 대상 page/block을 읽을 수 있는지 진단 |
| `check_token_v2_block_access.py` | origin별 block 접근 결과를 JSON으로 보고 |
| `check_notion_asset_auth.py` | 레거시 `getSignedFileUrls` 동작 점검 |
| `backup_with_token_v2.sh` | 레거시 Markdown 그래프 백업 진입점 |
| `download_notion_page.py` | 레거시 재귀 Markdown + asset 다운로더 |

---

## 진단

`User cannot access block`이 나오면:

```bash
./scripts/check_token_v2_access.sh "<Notion URL or page_id>"
```

정상 접근 예:

```json
"role": "reader" | "editor",
"has_value": true,
"matches_page": true
```

접근 실패 예:

```json
"role": "none",
"has_value": false,
"root_present": false
```

실패하면 대개 쿠키가 잘못된 브라우저 프로필/계정에서 복사되었거나, 해당 계정에 페이지 권한이 없는 상태입니다.

`HTTP 403` 또는 HTML 응답으로 zip 다운로드가 실패하면 `file_token`을 같은 프로필에서 다시 확인하세요. 다운로드에는 `token_v2`, `file_token`, `X-Notion-Space-Id`, `Referer`가 모두 필요합니다.

---

## 출력 위치

```text
<your-workspace>/
├── scripts/
├── notion-exports/
│   ├── notion-export-<id>-markdown-<ts>.zip
│   └── notion-export-<id>-markdown-<ts>/
├── .notion-cache/          # 레거시 Markdown 경로
├── .notion-assets.json     # 레거시 asset 매니페스트
└── backup-summary.json     # 레거시 요약
```

Export zip 성공 출력은 대략 아래 형태입니다.

```json
{
  "zip": "notion-exports/notion-export-....zip",
  "bytes": 123456,
  "unzipped": "notion-exports/notion-export-..."
}
```

---

## 레거시 Markdown 경로

Export zip 백업을 확보한 뒤, 로컬 Markdown 그래프 처리가 별도로 필요할 때만 사용합니다.

```bash
python3 scripts/download_notion_page.py "<Notion URL or page_id>"
```

이 경로는 `.notion-cache/`, `.notion-assets.json`, `backup-summary.json`을 사용합니다. `file://` 참조나 빈 signed URL이 남을 수 있으므로 리소스 완전 백업 경로로 보지 않습니다.

---

## 완료 보고 기준

Agent는 Export zip 백업 후 아래를 확인해 보고합니다.

- Export zip 경로
- 압축 해제 폴더 경로
- Zip 크기
- 접근 진단 실행 여부
- 남은 수동 단계

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
  secrets=hidden terminal prompts only; never ask user to paste into chat
  credential_order=env vars -> local secret backend -> hidden prompts
  report=zip path, extracted folder, zip bytes, access diagnostics, remaining manual step
```

---

## 라이선스

[MIT License](LICENSE)
