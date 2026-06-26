#!/usr/bin/env bash
# aahp-archive.sh - Rotate and verify AAHP LOG.md archive integrity.
#
# Usage:
#   aahp-archive.sh [path] [--keep N] [--verify]
#
# Default flow: keep the 10 newest LOG.md entries. Entries older than the
# 10th entry are moved automatically into LOG-ARCHIVE.md.
#
# Entry boundary: a log entry starts at a Markdown H2 whose text begins with
# "[YYYY-MM-DD]", for example: ## [2026-06-26] Agent: Work summary

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_aahp-lib.sh
source "$SCRIPT_DIR/_aahp-lib.sh"
PYTHON_CMD="$(aahp_python_cmd)"
[ -n "$PYTHON_CMD" ] || { echo "Error: python is required for archive operations." >&2; exit 1; }

PROJECT_ROOT="."
KEEP=10
VERIFY_ONLY=false

if [ $# -gt 0 ] && [[ ! "$1" == --* ]]; then
    PROJECT_ROOT="$1"
    shift
fi
while [ $# -gt 0 ]; do
    case "$1" in
        --keep) KEEP="$2"; shift 2 ;;
        --verify) VERIFY_ONLY=true; shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

cd "$PROJECT_ROOT" || { echo "Error: cannot cd into project root: $PROJECT_ROOT" >&2; exit 1; }
HANDOFF_DIR=".ai/handoff"
LOG="$HANDOFF_DIR/LOG.md"
ARCHIVE="$HANDOFF_DIR/LOG-ARCHIVE.md"
INDEX="$HANDOFF_DIR/LOG-ARCHIVE.index.json"

"$PYTHON_CMD" - "$LOG" "$ARCHIVE" "$INDEX" "$KEEP" "$VERIFY_ONLY" <<'PY'
import hashlib
import json
import re
import sys
from pathlib import Path

log_path = Path(sys.argv[1])
archive_path = Path(sys.argv[2])
index_path = Path(sys.argv[3])
keep = int(sys.argv[4])
verify_only = sys.argv[5].lower() == 'true'
entry_re = re.compile(r'^## \[[0-9]{4}-[0-9]{2}-[0-9]{2}\]')

def read(path: Path) -> str:
    return path.read_text(encoding='utf-8') if path.exists() else ''

def split_doc(text: str):
    lines = text.replace('\r\n', '\n').replace('\r', '\n').splitlines(keepends=True)
    starts = [i for i, line in enumerate(lines) if entry_re.match(line)]
    if not starts:
        return ''.join(lines), []
    preamble = ''.join(lines[:starts[0]])
    entries = []
    for index, start in enumerate(starts):
        end = starts[index + 1] if index + 1 < len(starts) else len(lines)
        entries.append(''.join(lines[start:end]).rstrip() + '\n\n')
    return preamble, entries

def digest(entry: str) -> str:
    normalized = entry.replace('\r\n', '\n').replace('\r', '\n').strip() + '\n'
    return hashlib.sha256(normalized.encode('utf-8')).hexdigest()

def title(entry: str) -> str:
    return entry.splitlines()[0].strip() if entry.splitlines() else "(untitled)"

def read_index(path: Path):
    if not path.exists():
        return []
    data = json.loads(path.read_text(encoding='utf-8'))
    if data.get('version') != 1 or not isinstance(data.get('entries'), list):
        raise SystemExit('LOG-ARCHIVE.index.json is malformed')
    return data['entries']

def write_index(path: Path, entries):
    path.write_text(json.dumps({'version': 1, 'entries': entries}, indent=2) + '\n', encoding='utf-8', newline='\n')

if keep < 1:
    raise SystemExit('--keep must be >= 1')
if not log_path.exists():
    raise SystemExit(f'{log_path} not found')

log_preamble, log_entries = split_doc(read(log_path))
archive_text = read(archive_path)
archive_preamble, archive_entries = split_doc(archive_text)
archive_hashes = {digest(entry) for entry in archive_entries}
if len(archive_hashes) != len(archive_entries):
    raise SystemExit('LOG-ARCHIVE.md contains duplicate archived entries')
index_entries = read_index(index_path)
indexed_hashes = [entry.get('sha256') for entry in index_entries]
if len(indexed_hashes) != len(set(indexed_hashes)):
    raise SystemExit('LOG-ARCHIVE.index.json contains duplicate entries')
missing_indexed = [h for h in indexed_hashes if h not in archive_hashes]
if missing_indexed:
    raise SystemExit('LOG-ARCHIVE.md is missing indexed archived entries')
if verify_only:
    if len(log_entries) > keep:
        raise SystemExit(f'LOG.md has {len(log_entries)} entries; archive rotation required to keep {keep}')
    print(f'LOG archive verify passed: LOG.md entries={len(log_entries)}, archived entries={len(archive_entries)}, keep={keep}')
    raise SystemExit(0)

if len(log_entries) <= keep:
    print(f'LOG archive up to date: LOG.md entries={len(log_entries)}, keep={keep}')
    raise SystemExit(0)

keep_entries = log_entries[:keep]
move_entries = log_entries[keep:]
missing = [entry for entry in move_entries if digest(entry) not in archive_hashes]
if missing:
    if not archive_preamble.strip():
        archive_preamble = '# AAHP: Archived Agent Journal\n\n> Older entries rotated from LOG.md. Append-only.\n\n---\n\n'
    archive_body = ''.join(missing + archive_entries)
    archive_path.write_text(archive_preamble.rstrip() + '\n\n' + archive_body, encoding='utf-8', newline='\n')
    known = {entry.get('sha256') for entry in index_entries}
    new_index_entries = []
    for entry in missing:
        h = digest(entry)
        if h not in known:
            new_index_entries.append({'sha256': h, 'title': title(entry)})
    write_index(index_path, new_index_entries + index_entries)

log_path.write_text(log_preamble.rstrip() + '\n\n' + ''.join(keep_entries), encoding='utf-8', newline='\n')
# Verify postcondition.
_, post_log = split_doc(read(log_path))
_, post_archive = split_doc(read(archive_path))
post_hashes = {digest(entry) for entry in post_archive}
missing_after = [digest(entry) for entry in move_entries if digest(entry) not in post_hashes]
if len(post_log) > keep or missing_after:
    raise SystemExit('archive postcondition failed: rotated entries were not fully preserved')
print(f'LOG archive rotated: kept {len(post_log)} active entries, archived {len(missing)} new older entries')
PY
