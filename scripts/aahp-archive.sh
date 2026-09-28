#!/usr/bin/env bash
# aahp-archive.sh - Rotate and verify AAHP LOG.md archive integrity.
#
# Usage:
#   aahp-archive.sh [path] [--keep N] [--verify | --reindex]
#
# Default flow: keep the 10 newest LOG.md entries. Entries older than the
# 10th entry are moved automatically into LOG-ARCHIVE.md.
#
# Entry boundary: a log entry starts at a Markdown H2 whose text begins with
# "[YYYY-MM-DD]", for example: ## [2026-06-26] Agent: Work summary
#
# LOG-ARCHIVE.index.json records one SHA-256 per archived entry, and --verify
# fails when an indexed entry is no longer in LOG-ARCHIVE.md byte for byte. That
# is the tamper evidence, and it makes a deliberate edit of an archived entry (a
# redaction, README Section 1.3) fail too until the index records it.
#
# --reindex is that recording step. Rotation only ever ADDS index entries, so
# before it existed the only way to record a redaction was to recompute the
# digest by hand and edit the JSON. It rewrites the index from LOG-ARCHIVE.md as
# it is now, one entry per archived entry, and never runs silently: it prints
# every hash it drops and every hash it records, with the entry title, so the
# change a reviewer approves is the change that was made. It accepts ANY edit,
# including one nobody meant to make, which is why the output and the index diff
# belong in the same reviewed change as the archive edit. Nothing changed means
# nothing is written. It writes only the index, never LOG.md or LOG-ARCHIVE.md.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_aahp-lib.sh
source "$SCRIPT_DIR/_aahp-lib.sh"
PYTHON_CMD="$(aahp_python_cmd)"
[ -n "$PYTHON_CMD" ] || { echo "Error: python is required for archive operations." >&2; exit 1; }

PROJECT_ROOT="."
KEEP=10
VERIFY_ONLY=false
REINDEX=false

if [ $# -gt 0 ] && [[ ! "$1" == --* ]]; then
    PROJECT_ROOT="$1"
    shift
fi
while [ $# -gt 0 ]; do
    case "$1" in
        --keep) KEEP="$2"; shift 2 ;;
        --verify) VERIFY_ONLY=true; shift ;;
        --reindex) REINDEX=true; shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done
if [ "$VERIFY_ONLY" = true ] && [ "$REINDEX" = true ]; then
    echo "Error: --verify checks the index and --reindex rewrites it; pass one of them." >&2
    exit 1
fi

cd "$PROJECT_ROOT" || { echo "Error: cannot cd into project root: $PROJECT_ROOT" >&2; exit 1; }
HANDOFF_DIR=".ai/handoff"
LOG="$HANDOFF_DIR/LOG.md"
ARCHIVE="$HANDOFF_DIR/LOG-ARCHIVE.md"
INDEX="$HANDOFF_DIR/LOG-ARCHIVE.index.json"

"$PYTHON_CMD" - "$LOG" "$ARCHIVE" "$INDEX" "$KEEP" "$VERIFY_ONLY" "$REINDEX" <<'PY'
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
reindex = sys.argv[6].lower() == 'true'
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
        entry_text = ''.join(lines[start:end]).rstrip()
        while entry_text.endswith('---'):
            entry_text = entry_text[:-3].rstrip()
        entries.append(entry_text)
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

def render_entries(entries):
    return '\n\n---\n\n'.join(entry.strip() for entry in entries if entry.strip())

if keep < 1:
    raise SystemExit('--keep must be >= 1')
if not log_path.exists() and not reindex:
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

if reindex:
    # Runs BEFORE the missing-entry check below: an index that no longer matches
    # the archive is the state this step exists to resolve.
    if not archive_path.exists():
        raise SystemExit(f'{archive_path} not found; there is no archive to reindex')
    new_entries = [{'sha256': digest(entry), 'title': title(entry)} for entry in archive_entries]
    if new_entries == index_entries:
        print(f'LOG archive reindex: {index_path} already records the {len(new_entries)} '
              f'entries of {archive_path}; nothing written')
        raise SystemExit(0)
    new_hashes = {entry['sha256'] for entry in new_entries}
    old_hashes = set(indexed_hashes)
    dropped = [entry for entry in index_entries if entry.get('sha256') not in new_hashes]
    recorded = [entry for entry in new_entries if entry['sha256'] not in old_hashes]
    unchanged = len(new_entries) - len(recorded)
    write_index(index_path, new_entries)
    print(f'LOG archive reindex: rewrote {index_path} from {archive_path} ({len(new_entries)} entries).')
    for entry in dropped:
        print(f"  - dropped  {str(entry.get('sha256'))[:12]}  {entry.get('title', '(untitled)')}")
    for entry in recorded:
        print(f"  + recorded {entry['sha256'][:12]}  {entry['title']}")
    if not dropped and not recorded:
        print('  (no hash changed: only the order or the titles in the index did)')
    print(f'  {unchanged} archived entr{"y" if unchanged == 1 else "ies"} unchanged.')
    print('  --reindex accepts LOG-ARCHIVE.md as it is now, including an edit nobody meant to make.')
    print('  Review the lines above and commit the index in the same change as the archive edit.')
    raise SystemExit(0)

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
    archive_body = render_entries(missing + archive_entries)
    archive_path.write_text(archive_preamble.rstrip() + '\n\n' + archive_body + '\n', encoding='utf-8', newline='\n')
    known = {entry.get('sha256') for entry in index_entries}
    new_index_entries = []
    for entry in missing:
        h = digest(entry)
        if h not in known:
            new_index_entries.append({'sha256': h, 'title': title(entry)})
    write_index(index_path, new_index_entries + index_entries)

log_body = render_entries(keep_entries)
log_path.write_text(log_preamble.rstrip() + '\n\n' + log_body + '\n', encoding='utf-8', newline='\n')
# Verify postcondition.
_, post_log = split_doc(read(log_path))
_, post_archive = split_doc(read(archive_path))
post_hashes = {digest(entry) for entry in post_archive}
missing_after = [digest(entry) for entry in move_entries if digest(entry) not in post_hashes]
if len(post_log) > keep or missing_after:
    raise SystemExit('archive postcondition failed: rotated entries were not fully preserved')
print(f'LOG archive rotated: kept {len(post_log)} active entries, archived {len(missing)} new older entries')
PY
