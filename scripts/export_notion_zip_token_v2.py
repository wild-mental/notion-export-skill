#!/usr/bin/env python3
import argparse
import datetime as dt
import hashlib
import importlib.util
import json
import os
import posixpath
import shutil
import sys
import time
import urllib.error
import urllib.request
import uuid
import zipfile
from pathlib import Path
from typing import Dict, Optional


ROOT = Path(__file__).resolve().parents[1]
DOWNLOAD_SCRIPT = ROOT / "scripts" / "download_notion_page.py"
EXPORT_DIR = ROOT / "notion-exports"
API_ORIGIN = os.environ.get("NOTION_API_ORIGIN", "https://www.notion.so").rstrip("/")
MAX_EXTRACT_COMPONENT_BYTES = 160
MAX_EXTRACT_RELATIVE_PATH_BYTES = 700
MIN_EXTRACT_COMPONENT_BYTES = 48


def load_download_module():
    spec = importlib.util.spec_from_file_location("download_notion_page", DOWNLOAD_SCRIPT)
    module = importlib.util.module_from_spec(spec)
    if spec.loader is None:
        raise RuntimeError("Could not load download_notion_page.py")
    spec.loader.exec_module(module)
    return module


def hyphenated_uuid(value: str) -> str:
    return str(uuid.UUID(value))


def infer_space_id(d) -> Optional[str]:
    explicit = os.environ.get("NOTION_SPACE_ID", "").strip()
    if explicit:
        return explicit

    for path in sorted((ROOT / ".notion-cache").glob("*.md")):
        text = path.read_text(encoding="utf-8")
        matches = list(d.IMAGE_RE.finditer(text)) + list(d.FILE_RE.finditer(text))
        for match in matches:
            file_url = match.group(2) if match.re is d.IMAGE_RE else match.group(1)
            try:
                ref = d.parse_image_ref(file_url)
            except Exception:
                continue
            space_id = ref.get("permissionRecord", {}).get("spaceId")
            if space_id:
                return space_id
    return None


def normalize_cookie_value(value: str, name: str) -> str:
    value = value.strip().strip("'\"")
    if value.lower().startswith("cookie:"):
        value = value.split(":", 1)[1].strip()

    prefix = f"{name}="
    for part in value.split(";"):
        part = part.strip()
        if part.startswith(prefix):
            return part.split("=", 1)[1].strip().strip("'\"")

    if value.startswith(prefix):
        return value.split("=", 1)[1].strip().strip("'\"")
    return value


def notion_headers(token_v2: str, file_token: str, space_id: str) -> Dict[str, str]:
    return {
        "Cookie": f"token_v2={token_v2};file_token={file_token}",
        "Content-Type": "application/json",
        "Accept": "application/json",
        "User-Agent": "Mozilla/5.0",
        "X-Notion-Space-Id": space_id,
    }


def post_json(endpoint: str, payload: dict, token_v2: str, file_token: str, space_id: str) -> dict:
    req = urllib.request.Request(
        f"{API_ORIGIN}/api/v3/{endpoint}",
        data=json.dumps(payload).encode("utf-8"),
        headers=notion_headers(token_v2, file_token, space_id),
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            return json.load(response)
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", "replace")[:1000]
        raise RuntimeError(f"{API_ORIGIN}/api/v3/{endpoint} failed: HTTP {exc.code}: {body}") from exc


def find_first_export_url(value) -> Optional[str]:
    if isinstance(value, dict):
        preferred_keys = ("exportURL", "exportUrl", "url")
        for key in preferred_keys:
            item = value.get(key)
            if isinstance(item, str) and item.startswith(("http://", "https://")):
                return item
        for item in value.values():
            found = find_first_export_url(item)
            if found:
                return found
    elif isinstance(value, list):
        for item in value:
            found = find_first_export_url(item)
            if found:
                return found
    elif isinstance(value, str):
        if value.startswith(("http://", "https://")) and ".zip" in value:
            return value
    return None


def enqueue_export(page_id: str, space_id: str, token_v2: str, file_token: str, export_type: str) -> str:
    payload = {
        "task": {
            "eventName": "exportBlock",
            "request": {
                "block": {
                    "id": hyphenated_uuid(page_id),
                },
                "recursive": True,
                "shouldExportComments": False,
                "exportOptions": {
                    "exportType": export_type,
                    "timeZone": "Asia/Seoul",
                    "locale": "ko-KR",
                    "collectionViewExportType": "all",
                    "preferredViewMap": {},
                },
            },
        }
    }
    body = post_json("enqueueTask", payload, token_v2, file_token, space_id)
    task_id = body.get("taskId") or body.get("id")
    if not task_id:
        raise RuntimeError(f"Could not find taskId in enqueueTask response: {body}")
    return task_id


def wait_for_export_url(
    task_id: str,
    space_id: str,
    token_v2: str,
    file_token: str,
    timeout_seconds: int,
) -> str:
    deadline = time.monotonic() + timeout_seconds
    last_body = None
    while time.monotonic() < deadline:
        body = post_json("getTasks", {"taskIds": [task_id]}, token_v2, file_token, space_id)
        last_body = body
        export_url = find_first_export_url(body)
        if export_url:
            return export_url

        task = None
        if isinstance(body.get("results"), list):
            task = next((item for item in body["results"] if item.get("id") == task_id), None)
        state = task.get("state") if isinstance(task, dict) else None
        if state not in {"in_progress", "not_started", None}:
            raise RuntimeError(
                "Export task failed: "
                + json.dumps(body, ensure_ascii=False)[:1000]
            )

        print("waiting for Notion export task ...", file=sys.stderr)
        time.sleep(3)

    raise TimeoutError(
        "Timed out waiting for Notion export URL. Last response: "
        + json.dumps(last_body, ensure_ascii=False)[:1000]
    )


def download_url(url: str, dest: Path, token_v2: str, file_token: str, space_id: str) -> None:
    headers = {
        "User-Agent": "Mozilla/5.0",
        "Referer": "https://www.notion.so/",
    }
    if "notion.so/" in url:
        headers["Cookie"] = f"token_v2={token_v2};file_token={file_token}"
        headers["X-Notion-Space-Id"] = space_id
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=600) as response:
            dest.write_bytes(response.read())
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", "replace")[:1000]
        raise RuntimeError(f"Download failed: HTTP {exc.code}: {body}") from exc


def byte_len(value: str) -> int:
    return len(value.encode("utf-8"))


def utf8_prefix(value: str, max_bytes: int) -> str:
    output = []
    used = 0
    for char in value:
        size = len(char.encode("utf-8"))
        if used + size > max_bytes:
            break
        output.append(char)
        used += size
    return "".join(output)


def shorten_component(component: str, max_bytes: int, preserve_suffix: bool) -> str:
    component = component.replace("\x00", "_")
    if byte_len(component) <= max_bytes:
        return component

    digest = hashlib.sha1(component.encode("utf-8")).hexdigest()[:10]
    suffix = Path(component).suffix if preserve_suffix else ""
    if suffix and byte_len(suffix) > min(40, max_bytes - byte_len(digest)):
        suffix = ""

    marker = f"-{digest}"
    budget = max_bytes - byte_len(marker) - byte_len(suffix)
    if budget < 1:
        return f"{digest}{suffix}"

    stem = component[:-len(suffix)] if suffix else component
    prefix = utf8_prefix(stem, budget).rstrip(" ._-")
    if not prefix:
        prefix = "item"
    return f"{prefix}{marker}{suffix}"


def zip_member_parts(member_name: str) -> list:
    name = member_name.replace("\\", "/")
    first_part = name.split("/", 1)[0]
    if name.startswith("/") or (len(first_part) == 2 and first_part[1] == ":" and first_part[0].isalpha()):
        raise RuntimeError(f"Refusing to extract unsafe zip member path: {member_name}")

    normalized = posixpath.normpath(name)
    parts = [part for part in normalized.split("/") if part not in {"", "."}]
    if not parts or any(part == ".." for part in parts):
        raise RuntimeError(f"Refusing to extract unsafe zip member path: {member_name}")
    return parts


def safe_zip_parts(member_name: str, is_dir: bool) -> tuple:
    raw_parts = zip_member_parts(member_name)
    last_index = len(raw_parts) - 1
    safe_parts = [
        shorten_component(
            part,
            MAX_EXTRACT_COMPONENT_BYTES,
            preserve_suffix=(index == last_index and not is_dir),
        )
        for index, part in enumerate(raw_parts)
    ]

    while byte_len("/".join(safe_parts)) > MAX_EXTRACT_RELATIVE_PATH_BYTES:
        candidates = [
            (byte_len(part), index)
            for index, part in enumerate(safe_parts)
            if byte_len(part) > MIN_EXTRACT_COMPONENT_BYTES
        ]
        if not candidates:
            raise RuntimeError(f"Could not shorten zip member path enough: {member_name}")

        current_bytes, index = max(candidates)
        overflow = byte_len("/".join(safe_parts)) - MAX_EXTRACT_RELATIVE_PATH_BYTES
        next_limit = max(
            MIN_EXTRACT_COMPONENT_BYTES,
            current_bytes - min(current_bytes - MIN_EXTRACT_COMPONENT_BYTES, overflow + 8),
        )
        safe_parts[index] = shorten_component(
            raw_parts[index],
            next_limit,
            preserve_suffix=(index == last_index and not is_dir),
        )

    return raw_parts, safe_parts


def unique_collision_path(path: Path) -> Path:
    if not path.exists():
        return path

    suffix = path.suffix
    stem = path.name[:-len(suffix)] if suffix else path.name
    digest = hashlib.sha1(str(path).encode("utf-8")).hexdigest()[:8]
    for index in range(2, 1000):
        candidate = path.with_name(f"{stem}-{digest}-{index}{suffix}")
        if not candidate.exists():
            return candidate
    raise RuntimeError(f"Could not create a unique extracted path for: {path}")


def unzip(zip_path: Path) -> tuple:
    out_dir = zip_path.with_suffix("")
    out_dir.mkdir(parents=True, exist_ok=True)
    renamed_entries = 0
    extracted_files = 0

    with zipfile.ZipFile(zip_path) as archive:
        for info in archive.infolist():
            if info.filename.endswith("/") and not info.is_dir():
                continue

            raw_parts, safe_parts = safe_zip_parts(info.filename, info.is_dir())
            if raw_parts != safe_parts:
                renamed_entries += 1

            target = out_dir.joinpath(*safe_parts)
            if info.is_dir():
                target.mkdir(parents=True, exist_ok=True)
                continue

            target.parent.mkdir(parents=True, exist_ok=True)
            if target.exists():
                target = unique_collision_path(target)
                renamed_entries += 1

            with archive.open(info) as source, target.open("wb") as dest:
                shutil.copyfileobj(source, dest)
            extracted_files += 1

    return out_dir, renamed_entries, extracted_files


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Request a Notion recursive export zip with token_v2.",
        usage='%(prog)s "<Notion URL or page_id>" [--type {markdown,html,pdf}] [--timeout TIMEOUT] [--no-unzip]',
    )
    parser.add_argument("page", metavar="PAGE", help="Notion page URL or page ID")
    parser.add_argument("--type", choices=("markdown", "html", "pdf"), default="markdown")
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument("--no-unzip", action="store_true")
    args = parser.parse_args()

    d = load_download_module()
    try:
        page_id = d.normalize_page_id(args.page)
    except ValueError as exc:
        parser.error(str(exc))

    token_v2 = d.normalize_token_v2(os.environ.get("NOTION_TOKEN_V2", ""))
    file_token = normalize_cookie_value(os.environ.get("NOTION_FILE_TOKEN", ""), "file_token")
    if not token_v2:
        raise SystemExit("NOTION_TOKEN_V2 is empty")
    if not file_token:
        raise SystemExit("NOTION_FILE_TOKEN is empty")

    space_id = infer_space_id(d)
    if not space_id:
        raise SystemExit("Could not infer spaceId. Set NOTION_SPACE_ID and retry.")

    print(f"enqueue Notion export: page={page_id} space={space_id} type={args.type}", file=sys.stderr)
    task_id = enqueue_export(page_id, space_id, token_v2, file_token, args.type)
    print(f"export task id: {task_id}", file=sys.stderr)
    export_url = wait_for_export_url(task_id, space_id, token_v2, file_token, args.timeout)

    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    timestamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    zip_path = EXPORT_DIR / f"notion-export-{page_id[:12]}-{args.type}-{timestamp}.zip"
    print(f"downloading export zip to {zip_path.relative_to(ROOT)}", file=sys.stderr)
    download_url(export_url, zip_path, token_v2, file_token, space_id)

    result = {
        "zip": zip_path.relative_to(ROOT).as_posix(),
        "bytes": zip_path.stat().st_size,
    }
    if not args.no_unzip:
        out_dir, renamed_entries, extracted_files = unzip(zip_path)
        result["unzipped"] = out_dir.relative_to(ROOT).as_posix()
        result["extracted_files"] = extracted_files
        result["renamed_entries"] = renamed_entries

    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
