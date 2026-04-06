#!/usr/bin/env python3

import argparse
import datetime as dt
import re
import subprocess
import sys
import tempfile
from pathlib import Path


MATH_ENVS = {
    "align",
    "align*",
    "equation",
    "equation*",
    "gather",
    "gather*",
    "multline",
    "multline*",
}


def yaml_escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", value.lower())
    return slug.strip("-")


def default_slug_from_title(title: str) -> str:
    session_match = re.search(r"\sS([0-9]+):", title)
    suffix_match = re.search(r"\sS[0-9]+:\s*(.*)$", title)
    if session_match and suffix_match:
        return slugify(f"session-{session_match.group(1)} {suffix_match.group(1)}")
    return slugify(title)


def extract_title(org_text: str, org_path: Path) -> str:
    match = re.search(r"(?im)^#\+title:\s*(.+)$", org_text)
    if not match:
        raise SystemExit(f"Could not extract #+title from {org_path}")
    return match.group(1).strip()


def preserve_math_blocks(org_text: str) -> tuple[str, list[str]]:
    blocks: list[str] = []

    def replace_math(match: re.Match[str]) -> str:
        env = match.group(1)
        if env not in MATH_ENVS:
            return match.group(0)
        blocks.append(match.group(0))
        return f"CTFBOOTCAMPMATHBLOCK{len(blocks) - 1}"

    rewritten = re.sub(
        r"\\begin\{([^}]+)\}.*?\\end\{\1\}",
        replace_math,
        org_text,
        flags=re.DOTALL,
    )
    return rewritten, blocks


def run_pandoc(org_text: str) -> str:
    with tempfile.NamedTemporaryFile("w+", suffix=".org", delete=False) as tmp_org:
        tmp_org.write(org_text)
        tmp_org.flush()
        tmp_org_path = Path(tmp_org.name)

    try:
        result = subprocess.run(
            ["pandoc", "-f", "org", "-t", "html", "--no-highlight", str(tmp_org_path)],
            check=True,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError as exc:
        raise SystemExit("pandoc is required but was not found in PATH") from exc
    except subprocess.CalledProcessError as exc:
        stderr = exc.stderr.strip()
        if stderr:
            raise SystemExit(f"pandoc failed:\n{stderr}") from exc
        raise SystemExit("pandoc failed") from exc
    finally:
        tmp_org_path.unlink(missing_ok=True)

    return result.stdout


def rewrite_html(html: str, math_blocks: list[str], session: str) -> tuple[str, list[str]]:
    for index, block in enumerate(math_blocks):
        replacement = f'<script type="math/tex; mode=display">\n{block}\n</script>'
        html = html.replace(f"<p>CTFBOOTCAMPMATHBLOCK{index}</p>", replacement)
        html = html.replace(f"CTFBOOTCAMPMATHBLOCK{index}", replacement)

    html = re.sub(r'src="(?:\./)?img/([^"]+)"', rf'src="/ctf-bootcamp/{session}/img/\1"', html)

    broken_attach_refs: list[str] = []

    def strip_attach_src(match: re.Match[str]) -> str:
        broken_attach_refs.append(match.group(1))
        return 'src="" data-missing-attach="true"'

    def strip_attach_href(match: re.Match[str]) -> str:
        broken_attach_refs.append(match.group(1))
        return 'href="#" data-missing-attach="true"'

    html = re.sub(r'src="(?:\./)?\.attach/([^"]+)"', strip_attach_src, html)
    html = re.sub(r'href="(?:\./)?\.attach/([^"]+)"', strip_attach_href, html)
    html = re.sub(r"<img[^>]*data-missing-attach=\"true\"[^>]*>\s*", "", html)
    html = re.sub(r"<a[^>]*data-missing-attach=\"true\"[^>]*>.*?</a>", "", html, flags=re.DOTALL)
    html = re.sub(r"\sstyle=\"[^\"]*\"", "", html)
    html = re.sub(r"<p>\s*(<img[^>]+>)\s*</p>", r"\1", html)

    return html.strip() + "\n", broken_attach_refs


def write_output(repo_root: Path, slug: str, title: str, author: str, date_value: str, session: str, html: str) -> Path:
    output_dir = repo_root / "collections" / "_ctf_bootcamp"
    output_dir.mkdir(parents=True, exist_ok=True)

    output_path = output_dir / f"{slug}.html"
    markdown_path = output_dir / f"{slug}.md"
    markdown_path.unlink(missing_ok=True)

    frontmatter = "\n".join(
        [
            "---",
            "layout: post",
            f'title: "{yaml_escape(title)}"',
            f'author: "{yaml_escape(author)}"',
            f"date: {date_value}",
            "comment: false",
            "---",
            "",
            f'<p>This article adapts the bootcamp session notes into a readable post. <a href="/ctf-bootcamp/{session}/">View the slides</a>.</p>',
            "",
        ]
    )

    output_path.write_text(frontmatter + html + "\n")
    return output_path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="scripts/import_ctf_bootcamp_post.py",
        description=(
            "Converts an Org file into an HTML article in collections/_ctf_bootcamp/ "
            "and inserts a link to the existing slide deck under /ctf-bootcamp/<SessionN>/."
        ),
    )
    parser.add_argument("org_path")
    parser.add_argument("--session", required=True)
    parser.add_argument("--slug")
    parser.add_argument("--date", dest="date_value")
    parser.add_argument("--author", default="GGG")
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    org_path = Path(args.org_path).expanduser().resolve()
    if not org_path.is_file():
        raise SystemExit(f"Org file not found: {org_path}")

    repo_root = Path(__file__).resolve().parent.parent
    session_index = repo_root / "ctf-bootcamp" / args.session / "index.html"
    if not session_index.is_file():
        raise SystemExit(f"Missing slide deck for session: {session_index.relative_to(repo_root)}")

    org_text = org_path.read_text()
    title = extract_title(org_text, org_path)
    slug = args.slug or default_slug_from_title(title)
    date_value = args.date_value or dt.date.today().isoformat()

    prepared_org, math_blocks = preserve_math_blocks(org_text)
    html = run_pandoc(prepared_org)
    html, broken_attach_refs = rewrite_html(html, math_blocks, args.session)
    output_path = write_output(repo_root, slug, title, args.author, date_value, args.session, html)

    if broken_attach_refs:
        for ref in dict.fromkeys(broken_attach_refs):
            print(f"warning: omitted .attach reference: {ref}", file=sys.stderr)

    print(f"Wrote {output_path.relative_to(repo_root)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
