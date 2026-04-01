#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/import_ctf_bootcamp_post.sh <org-path> --session Session0 [--slug session-0-hello-computer] [--date YYYY-MM-DD] [--author "GGG"]

Converts an Org file into an HTML article in collections/_ctf_bootcamp/
and inserts a link to the existing slide deck under /ctf-bootcamp/<SessionN>/.
EOF
}

yaml_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

default_slug_from_title() {
  local title_value="$1"
  local session_slug
  local suffix

  session_slug="$(printf '%s' "$title_value" | sed -En 's/.*[[:space:]]S([0-9]+):.*/session-\1/p' | head -n 1)"
  suffix="$(printf '%s' "$title_value" | sed -En 's/.*[[:space:]]S[0-9]+:[[:space:]]*(.*)$/\1/p' | head -n 1)"

  if [[ -n "$session_slug" && -n "$suffix" ]]; then
    printf '%s\n' "$(slugify "$session_slug $suffix")"
  else
    printf '%s\n' "$(slugify "$title_value")"
  fi
}

org_path=""
session=""
slug=""
date_value="$(date +%F)"
author="GGG"

while (($# > 0)); do
  case "$1" in
    --session)
      session="${2:-}"
      shift 2
      ;;
    --slug)
      slug="${2:-}"
      shift 2
      ;;
    --date)
      date_value="${2:-}"
      shift 2
      ;;
    --author)
      author="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -z "$org_path" ]]; then
        org_path="$1"
      else
        echo "Unexpected argument: $1" >&2
        usage >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$org_path" || -z "$session" ]]; then
  usage >&2
  exit 1
fi

if [[ ! -f "$org_path" ]]; then
  echo "Org file not found: $org_path" >&2
  exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

org_dir="$(cd "$(dirname "$org_path")" && pwd)"
session_index="ctf-bootcamp/${session}/index.html"
if [[ ! -f "$session_index" ]]; then
  echo "Missing slide deck for session: $session_index" >&2
  exit 1
fi

source_attach_dir="${org_dir}/.attach"
target_attach_dir="ctf-bootcamp/${session}/img/attach"
rm -rf "$target_attach_dir"
if [[ -d "$source_attach_dir" ]]; then
  mkdir -p "$target_attach_dir"
  python3 - "$source_attach_dir" "$target_attach_dir" <<'PY'
import shutil
import sys
from pathlib import Path

source = Path(sys.argv[1])
target = Path(sys.argv[2])

for path in source.rglob("*"):
    relative = path.relative_to(source)
    parts = list(relative.parts)
    if path.is_file() and parts:
        parts[-1] = parts[-1].lstrip("_") or parts[-1]
    destination = target.joinpath(*parts)
    if path.is_dir():
        destination.mkdir(parents=True, exist_ok=True)
    else:
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, destination)
PY
fi

title="$(awk 'BEGIN { IGNORECASE = 1 } /^#\+title:/ { sub(/^#\+title:[[:space:]]*/, "", $0); print; exit }' "$org_path")"
if [[ -z "$title" ]]; then
  echo "Could not extract #+title from $org_path" >&2
  exit 1
fi

if [[ -z "$slug" ]]; then
  slug="$(default_slug_from_title "$title")"
fi

mkdir -p collections/_ctf_bootcamp

tmp_org="$(mktemp)"
tmp_html="$(mktemp)"
cleanup() {
  rm -f "$tmp_org" "$tmp_html"
}
trap cleanup EXIT

python3 - "$org_path" "$tmp_org" <<'PY'
import re
import sys
from pathlib import Path

source_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])
text = source_path.read_text()

math_envs = {
    "align",
    "align*",
    "equation",
    "equation*",
    "gather",
    "gather*",
    "multline",
    "multline*",
}

blocks = []

def replace_math(match):
    env = match.group(1)
    if env not in math_envs:
        return match.group(0)
    blocks.append(match.group(0))
    return f"CTFBOOTCAMPMATHBLOCK{len(blocks) - 1}"

rewritten = re.sub(r"\\begin\{([^}]+)\}.*?\\end\{\1\}", replace_math, text, flags=re.DOTALL)
output_path.write_text(rewritten)
PY

pandoc -f org -t html --no-highlight "$tmp_org" > "$tmp_html"

python3 - "$org_path" "$tmp_html" "$session" <<'PY'
import re
import sys
from pathlib import Path

source_text = Path(sys.argv[1]).read_text()
html_path = Path(sys.argv[2])
session = sys.argv[3]
html = html_path.read_text()

math_envs = {
    "align",
    "align*",
    "equation",
    "equation*",
    "gather",
    "gather*",
    "multline",
    "multline*",
}

def collect_math_blocks(text):
    matches = []
    for match in re.finditer(r"\\begin\{([^}]+)\}.*?\\end\{\1\}", text, flags=re.DOTALL):
        if match.group(1) in math_envs:
            matches.append(match.group(0))
    return matches

for i, block in enumerate(collect_math_blocks(source_text)):
    replacement = f'<script type="math/tex; mode=display">\n{block}\n</script>'
    html = html.replace(f"<p>CTFBOOTCAMPMATHBLOCK{i}</p>", replacement)
    html = html.replace(f"CTFBOOTCAMPMATHBLOCK{i}", replacement)

html = re.sub(r'src="(?:\./)?img/([^"]+)"', rf'src="/ctf-bootcamp/{session}/img/\1"', html)

def rewrite_attach_src(match):
    path = match.group(1)
    parts = path.split("/")
    if parts:
        parts[-1] = parts[-1].lstrip("_") or parts[-1]
    return f'src="/ctf-bootcamp/{session}/img/attach/' + "/".join(parts) + '"'

html = re.sub(r'src="(?:\./)?\.attach/([^"]+)"', rewrite_attach_src, html)
html = re.sub(r'\sstyle="[^"]*"', '', html)
html = re.sub(r'<p>\s*(<img[^>]+>)\s*</p>', r'\1', html)

html_path.write_text(html.strip() + "\n")
PY

output_path="collections/_ctf_bootcamp/${slug}.html"
markdown_path="collections/_ctf_bootcamp/${slug}.md"
rm -f "$markdown_path"

{
  printf -- "---\n"
  printf 'layout: post\n'
  printf 'title: "%s"\n' "$(yaml_escape "$title")"
  printf 'author: "%s"\n' "$(yaml_escape "$author")"
  printf 'date: %s\n' "$date_value"
  printf 'comment: false\n'
  printf -- "---\n\n"
  printf '<p>This article adapts the bootcamp session notes into a readable post. <a href="/ctf-bootcamp/%s/">View the slides</a>.</p>\n\n' "$session"
  cat "$tmp_html"
  printf '\n'
} > "$output_path"

printf 'Wrote %s\n' "$output_path"
