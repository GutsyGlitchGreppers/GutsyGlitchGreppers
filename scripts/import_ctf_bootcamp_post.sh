#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/import_ctf_bootcamp_post.sh <org-path> --session Session0 [--slug session-0-hello-computer] [--date YYYY-MM-DD] [--author "GGG"]

Converts an Org file into a Markdown article in collections/_ctf_bootcamp/
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

title="$(awk 'BEGIN { IGNORECASE = 1 } /^#\+title:/ { sub(/^#\+title:[[:space:]]*/, "", $0); print; exit }' "$org_path")"
if [[ -z "$title" ]]; then
  echo "Could not extract #+title from $org_path" >&2
  exit 1
fi

if [[ -z "$slug" ]]; then
  slug="$(default_slug_from_title "$title")"
fi

mkdir -p collections/_ctf_bootcamp

tmp_markdown="$(mktemp)"
tmp_org="$(mktemp)"
cleanup() {
  rm -f "$tmp_markdown"
  rm -f "$tmp_org"
}
trap cleanup EXIT

# Pandoc drops raw LaTeX environments like \begin{align*}...\end{align*},
# so preserve them with placeholders before conversion and restore afterward.
python3 - "$org_path" "$tmp_org" <<'PY'
import re
import sys
from pathlib import Path

source_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])
text = source_path.read_text()
blocks = []

def store_block(match):
    blocks.append(match.group(0))
    return f"CTFBOOTCAMPLATEXBLOCK{len(blocks) - 1}"

pattern = re.compile(r"\\begin\{([^}]+)\}.*?\\end\{\1\}", re.DOTALL)
rewritten = pattern.sub(store_block, text)

output_path.write_text(rewritten)
PY

pandoc -f org -t gfm --wrap=none "$tmp_org" > "$tmp_markdown"

python3 - "$org_path" "$tmp_markdown" <<'PY'
import re
import sys
from pathlib import Path

source_text = Path(sys.argv[1]).read_text()
markdown_path = Path(sys.argv[2])
markdown = markdown_path.read_text()

blocks = re.findall(r"(\\begin\{([^}]+)\}.*?\\end\{\2\})", source_text, re.DOTALL)
for i, (block, _) in enumerate(blocks):
    math_block = f'<script type="math/tex; mode=display">\n{block}\n</script>'
    markdown = markdown.replace(f"CTFBOOTCAMPLATEXBLOCK{i}", math_block)

markdown_path.write_text(markdown)
PY

# Remove leading blank lines from pandoc output.
perl -0pi -e 's/\A\s+//' "$tmp_markdown"

# Rewrite local image and attachment paths to the existing slide asset paths.
perl -0pi -e 's{!\[(.*?)\]\((?:\./)?img/([^)]+)\)}{![$1](/ctf-bootcamp/'"$session"'/img/$2)}g' "$tmp_markdown"
perl -0pi -e 's{!\[(.*?)\]\((?:\./)?\.attach/([^)]+)\)}{![$1](/ctf-bootcamp/'"$session"'/.attach/$2)}g' "$tmp_markdown"
perl -0pi -e 's{<img\s+src="(?:\./)?img/([^"]+)"[^>]*>}{![](/ctf-bootcamp/'"$session"'/img/$1)}g' "$tmp_markdown"
perl -0pi -e 's{<img\s+src="(?:\./)?\.attach/([^"]+)"[^>]*>}{![](/ctf-bootcamp/'"$session"'/.attach/$1)}g' "$tmp_markdown"

output_path="collections/_ctf_bootcamp/${slug}.md"

{
  printf -- "---\n"
  printf 'layout: post\n'
  printf 'title: "%s"\n' "$(yaml_escape "$title")"
  printf 'author: "%s"\n' "$(yaml_escape "$author")"
  printf 'date: %s\n' "$date_value"
  printf 'comment: false\n'
  printf -- "---\n\n"
  printf 'This article adapts the bootcamp session notes into a readable post. [View the slides](/ctf-bootcamp/%s/).\n\n' "$session"
  cat "$tmp_markdown"
  printf '\n'
} > "$output_path"

printf 'Wrote %s\n' "$output_path"
