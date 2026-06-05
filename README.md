![AI Skills for Everyone](author/wildmental-bjpark.png)

# notion-export
> Skill for Cursor, Claude, Codex agents

**Notion 페이지를 이미지·첨부파일까지 빠짐없이 백업하는 Skill입니다. 공개 API나 파일 단위 서명(`getSignedFileUrls`)이 자꾸 빈 URL을 돌려주는 함정을 피하고, `token_v2` + `file_token` 기반의 재귀 Export zip 경로로 "리소스 완전" 백업을 만듭니다. Cursor, Claude Code, Codex 모두 지원합니다.**

"Notion 페이지를 통째로 백업하자"는 단순해 보이지만, 실제로는 **이미지·파일이 빠진 반쪽 백업**으로 끝나기 쉽습니다. 공개 API는 블록 children 수집에서 느려지거나 멈추고, `getSignedFileUrls`는 `HTTP 200`을 주면서도 `signedUrls`가 비어 있는 경우가 많습니다. 이 스킬은 그 시행착오를 미리 문서화하고, **"먼저 Export zip부터"** 라는 행동 규칙으로 고정합니다.

---

## 이 스킬이 해결하는 것

### 1. "리소스 완전" 백업을 기본 경로로 만든다

이미지·파일·첨부가 중요한 백업에서는 **재귀 Export zip 스크립트를 먼저** 씁니다(`export_with_token_v2.sh`). 페이지 텍스트뿐 아니라 모든 에셋을 한 번의 아카이브로 받습니다.

```
save cookies → token_v2 접근 preflight → exportBlock 작업 enqueue
→ getTasks 폴링 → zip 다운로드(token_v2+file_token) → notion-exports/ 에 압축 해제
```

### 2. 빈 signedUrls 함정을 회피한다

`getSignedFileUrls`로 시작하지 않습니다. `HTTP 200` + 빈 `signedUrls`는 알려진 실패 모드이며, 재시도는 시간 낭비입니다. 스킬은 이를 진단하고 곧바로 Export zip 경로로 전환합니다.

### 3. 세션 쿠키(`token_v2`/`file_token`)를 안전하게 다룬다

- 쿠키는 **숨김 터미널 입력**으로만 수집 (채팅에 붙여넣지 않음)
- macOS Keychain에만 저장(명시적 사용자 확인 후), 로그·커밋 금지
- 대상 페이지를 열 수 있는 **같은 브라우저 프로필/계정**의 쿠키만 사용

### 4. 접근 실패를 곧바로 진단한다

`User cannot access block`이 나오면 `check_token_v2_access.sh`로 `role`/`has_value`/`matches_page`를 확인해 "잘못된 계정/프로필 쿠키"인지 "권한 없음"인지 즉시 구분합니다.

---

## 왜 skill 이 필요한가

| 흔한 시도 | 기대 | 실제 |
|-----------|------|------|
| `getSignedFileUrls`로 파일 서명 | signed URL 확보 | `HTTP 200` + 빈 `signedUrls`, 무한 재시도 |
| 공개 API로 block children 수집 | 이미지·블록 수집 | 장시간 hang / timeout |
| 아무 브라우저 쿠키나 사용 | 페이지 접근 | `User cannot access block` |
| zip URL을 그냥 다운로드 | 아카이브 저장 | `HTTP 403` + HTML (헤더 누락) |
| `token_v2`만으로 다운로드 | 에셋 포함 백업 | `file_token` 누락으로 파일 누락 |
| 페이지 인자 없이 스크립트 실행 | 알아서 백업 | 어떤 페이지인지 불명확 → 이제 인자 **필수** |

이 스킬은 위 패턴을 **"먼저 Export zip → 안전한 쿠키 처리 → 접근 진단 → 검증/보고"** 운영 규칙으로 정리해 둡니다.

---

## 빠른 시작

### 사전 요구사항

- **macOS** (쿠키를 macOS Keychain에 `security` 명령으로 저장)
- `python3`, `bash`
- 대상 페이지를 열 수 있는 **Notion 브라우저 세션** (`token_v2` + `file_token` 출처)
- Cursor, Claude Code, 또는 Codex

### 스킬 설치 (SKILL.md)

스킬은 **개인** 또는 **프로젝트** 범위 중 하나를 골라 설치합니다. `SKILL.md`는 `curl`로 받습니다. **이 저장소 전체를 작업 repo에 clone하지 마세요.**

| | 개인 스킬 | 프로젝트 스킬 |
|---|----------|--------------|
| **적용 범위** | 내가 여는 모든 프로젝트 | 현재 repo에서만 |
| **경로** | `~/…/skills/notion-export/` | `<repo-root>/.cursor/skills/notion-export/` 등 |
| **Git 영향** | 작업 repo에 파일 추가 없음 | repo에 스킬 파일 commit 가능 (팀 공유) |

| 도구 | 개인 경로 | 프로젝트 경로 |
|------|-----------|---------------|
| Cursor | `~/.cursor/skills/notion-export/` | `.cursor/skills/notion-export/` |
| Claude Code | `~/.claude/skills/notion-export/` | `.claude/skills/notion-export/` |
| Codex | `~/.agents/skills/notion-export/` | `.agents/skills/notion-export/` |

#### 개인 스킬 (권장 — Git repo 무변경)

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

#### 프로젝트 스킬 (프로젝트 경로에 설치)

AI 스킬 설정을 repo에 포함·공유하려는 경우에만 사용하세요. 위 경로의 `~/`를 빼고 repo 루트에서 실행합니다.

### 스크립트 설치 (워크스페이스)

`notion-cli`/`grill-it`과 달리 이 스킬은 **실행 스크립트**가 함께 동작합니다. 스크립트는 백업을 저장할 **워크스페이스**(`<your-workspace>`)의 `scripts/`에 있어야 하며, 각 스크립트는 워크스페이스 루트로 `cd`해 내보낸 결과를 그곳에 저장합니다.

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

> SKILL.md는 **스킬 디렉터리**(`~/.claude/skills/...`)에, 스크립트는 **워크스페이스**(`<your-workspace>/scripts/`)에 — 두 위치가 다릅니다. 에이전트는 SKILL.md 지침에 따라 필요 시 위 명령으로 스크립트를 워크스페이스에 내려받습니다.

#### 설치 후

- **Cursor**: **Reload Window** 한 번
- **Claude Code**: 스킬 수정은 세션 중 live 반영; 세션 시작 후 새 top-level `.claude/skills/`는 재시작 필요할 수 있음
- **Codex**: 스킬이 안 보이면 Codex 재시작

### 사용 방법

Notion 백업/내보내기 작업을 요청하면 Agent가 스킬을 자동으로 적용합니다.

| 도구 | 수동 호출 |
|------|-----------|
| Cursor | `/notion-export` |
| Claude Code | `/notion-export` |
| Codex | `/skills` 또는 `$notion-export` |

**적용되는 요청 예시:**

- "이 Notion 페이지를 이미지·첨부까지 통째로 백업해줘"
- "하위 페이지까지 재귀적으로 export zip으로 받아줘"
- "`getSignedFileUrls`가 빈 URL만 줘서 막혔어, 다른 방법으로 백업해줘"
- "백업이 `User cannot access block`으로 실패해, 원인 진단해줘"

첫 실행 흐름:

```bash
cd <your-workspace>
./scripts/save_notion_export_cookies.sh                 # token_v2 + file_token 저장 (숨김 입력)
./scripts/export_with_token_v2.sh "<Notion URL or page_id>"   # page 인자 필수
```

---

## 핵심 함정 요약

스킬 본문(SKILL.md)에 상세 규칙이 있으며, 아래는 가장 자주 막히는 지점입니다.

### 먼저 Export zip, `getSignedFileUrls`는 나중

`signed_present: 0` / `signed_empty: N` 이 보이면 파일 단위 서명을 포기하고 Export zip으로 전환합니다.

### 쿠키는 같은 계정/프로필에서, 둘 다

`token_v2`와 `file_token`을 **대상 페이지를 열 수 있는 같은 브라우저 프로필/계정**에서 가져옵니다. `file_token`이 빠지면 다운로드가 `HTTP 403`(HTML)로 실패합니다.

### 쿠키는 절대 채팅에 붙여넣지 않기

숨김 터미널 입력으로만 수집하고, 명시적 확인 후 macOS Keychain에만 저장합니다.

### `app.notion.com`만 동작하면 origin 전환

```bash
NOTION_API_ORIGIN=https://app.notion.com ./scripts/export_with_token_v2.sh "<page>"
```

### spaceId 추론 실패 시 명시

```bash
NOTION_SPACE_ID=<space-id> ./scripts/export_with_token_v2.sh "<page>"
```

---

## 권장 워크스페이스 구조

```
<your-workspace>/
├── scripts/                       # 이 스킬의 실행 스크립트 (위 "스크립트 설치"로 배치)
├── notion-exports/                # Export zip + 압축 해제 결과
│   ├── notion-export-<id>-markdown-<ts>.zip
│   └── notion-export-<id>-markdown-<ts>/
├── .notion-cache/                 # (레거시 마크다운 경로) 페이지 캐시
├── .notion-assets.json            # (레거시) source → local file 매니페스트
└── backup-summary.json            # (레거시) 페이지/이미지/링크 요약
```

---

## 완료 검증 체크리스트

Export zip 백업 후 Agent는 아래를 확인·보고합니다.

- [ ] Export zip 경로
- [ ] 압축 해제 폴더 경로
- [ ] Zip 크기(bytes)
- [ ] 접근 진단(`check_token_v2_access.sh`)이 필요했는지 여부
- [ ] 남은 수동 단계

---

## 스킬 구성

```
.cursor/skills/notion-export/SKILL.md   # Cursor용
.claude/skills/notion-export/SKILL.md   # Claude Code용
.agents/skills/notion-export/SKILL.md   # Codex용
scripts/                                # 3개 벤더가 공유하는 실행 스크립트 (단일 정본)
```

| 스크립트 | 역할 |
|----------|------|
| `save_notion_export_cookies.sh` | `token_v2` + `file_token`를 macOS Keychain에 저장 |
| `export_with_token_v2.sh` | 메인 진입점: 접근 preflight + 재귀 Export zip |
| `export_notion_zip_token_v2.py` | export 작업 enqueue + 폴링 + 다운로드 + 압축 해제 |
| `check_token_v2_access.sh` | `token_v2` 페이지 접근 진단 |
| `check_token_v2_block_access.py` | origin별 block 접근 리포트 |
| `check_notion_asset_auth.py` | 레거시 `getSignedFileUrls` 점검 |
| `backup_with_token_v2.sh` | 레거시 마크다운 그래프 백업 진입점 |
| `download_notion_page.py` | 레거시 재귀 마크다운 + 에셋 다운로더 |

| 섹션 (SKILL.md) | 내용 |
|------|------|
| Core Rule | "먼저 Export zip", 빈 signedUrls 회피 |
| Prerequisites | macOS/Keychain, 워크스페이스 스크립트 설치 |
| Standard Command | 쿠키 저장 → export 실행(페이지 인자 필수) |
| Cookie Rules | 숨김 입력·Keychain·동일 계정/프로필 |
| Access Diagnostic | `role`/`has_value`/`matches_page` 판정 |
| Common Failures | 빈 signedUrls / 접근 불가 / 403 / file_token 누락 / spaceId |
| Legacy Markdown Path | `download_notion_page.py` 동작과 한계 |

---

## 이런 분께 추천합니다

- Notion 페이지를 **이미지·첨부까지 통째로** 백업해야 하는 분
- `getSignedFileUrls`가 빈 URL만 줘서 **반쪽 백업**에 시간을 쓴 분
- 세션 쿠키(`token_v2`/`file_token`)를 **안전하게** 다루며 백업을 자동화하려는 분
- Cursor / Claude Code / Codex 중 무엇을 쓰든 **같은 백업 규칙**을 적용하고 싶은 분

---

## 참고

- Notion Export(zip) 및 `token_v2`는 Notion 내부(비공식) 동작에 의존합니다. 개인/팀 백업 용도로만 사용하세요.
- Cursor Agent Skills: [Creating Skills](https://docs.cursor.com)
- Claude Code Skills: [Extend Claude with skills](https://docs.anthropic.com/en/docs/claude-code/skills)
- Codex Agent Skills: [Agent Skills](https://developers.openai.com/codex/skills/)

---

## For LLMs

<!-- install-only; operational rules live in SKILL.md — load skill after install -->

```
skill=notion-export
repo=https://github.com/wild-mental/notion-export-skill
install.method=curl-only  # never clone this repo into user's project
platform=macOS-only  # cookies stored in macOS Keychain via `security`

flow:
  1. ask scope: "개인 스킬(~/, 모든 프로젝트) vs 프로젝트 스킬(./, 현재 repo만) 중 어디에 설치할까요?"
  2. ask tools: "Cursor / Claude Code / Codex 중 어떤 도구에 설치할까요?" (복수 선택 가능)
  3. install SKILL.md for the chosen tool(s)+scope (curl commands below)
  4. install scripts into the user's workspace (scripts.fetch below) — required for export to run
  5. post_install steps; then load SKILL.md — do not infer rules from README

scope.user.paths:
  cursor=~/.cursor/skills/notion-export/SKILL.md
  claude=~/.claude/skills/notion-export/SKILL.md
  codex=~/.agents/skills/notion-export/SKILL.md

scope.project.paths:
  cursor=.cursor/skills/notion-export/SKILL.md
  claude=.claude/skills/notion-export/SKILL.md
  codex=.agents/skills/notion-export/SKILL.md

install.user.cursor=mkdir -p ~/.cursor/skills/notion-export && curl -fsSL https://raw.githubusercontent.com/wild-mental/notion-export-skill/main/.cursor/skills/notion-export/SKILL.md -o ~/.cursor/skills/notion-export/SKILL.md
install.user.claude=mkdir -p ~/.claude/skills/notion-export && curl -fsSL https://raw.githubusercontent.com/wild-mental/notion-export-skill/main/.claude/skills/notion-export/SKILL.md -o ~/.claude/skills/notion-export/SKILL.md
install.user.codex=mkdir -p ~/.agents/skills/notion-export && curl -fsSL https://raw.githubusercontent.com/wild-mental/notion-export-skill/main/.agents/skills/notion-export/SKILL.md -o ~/.agents/skills/notion-export/SKILL.md

install.project.cursor=mkdir -p .cursor/skills/notion-export && curl -fsSL https://raw.githubusercontent.com/wild-mental/notion-export-skill/main/.cursor/skills/notion-export/SKILL.md -o .cursor/skills/notion-export/SKILL.md
install.project.claude=mkdir -p .claude/skills/notion-export && curl -fsSL https://raw.githubusercontent.com/wild-mental/notion-export-skill/main/.claude/skills/notion-export/SKILL.md -o .claude/skills/notion-export/SKILL.md
install.project.codex=mkdir -p .agents/skills/notion-export && curl -fsSL https://raw.githubusercontent.com/wild-mental/notion-export-skill/main/.agents/skills/notion-export/SKILL.md -o .agents/skills/notion-export/SKILL.md

scripts.fetch=cd <workspace> && mkdir -p scripts && base=https://raw.githubusercontent.com/wild-mental/notion-export-skill/main/scripts && for f in save_notion_export_cookies.sh export_with_token_v2.sh export_notion_zip_token_v2.py check_token_v2_access.sh check_token_v2_block_access.py check_notion_asset_auth.py backup_with_token_v2.sh download_notion_page.py; do curl -fsSL "$base/$f" -o "scripts/$f"; done && chmod +x scripts/*.sh scripts/*.py
scripts.note=SKILL.md installs to the skills dir; scripts install to the user's WORKSPACE/scripts/. exports land in the workspace.

invoke.cursor=/notion-export
invoke.claude=/notion-export
invoke.codex=/skills|$notion-export

post_install.cursor=Reload Window
post_install.claude=live reload; restart if new top-level .claude/skills/ after session start
post_install.codex=restart if skill not detected

contract:
  prefer=token_v2 + file_token recursive Export zip (export_with_token_v2.sh)
  avoid=getSignedFileUrls first (HTTP 200 + empty signedUrls is the known failure mode)
  page_arg=required (scripts no longer assume a default page)
  secrets=[token_v2, file_token]
  secret_handling=hidden terminal prompts only; macOS Keychain after explicit confirm; never print/log/commit; never ask user to paste into chat
  keychain=service notion-export-token-v2 / notion-export-file-token, account notion-export
  diagnose_access=check_token_v2_access.sh -> role/has_value/matches_page
  report=[zip path, unzipped folder, zip bytes, whether access diagnostics were needed, remaining manual step]
```

---

## 라이선스

[MIT License](LICENSE)
