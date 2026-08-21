#!/usr/bin/env bash
#
# Initializes this template into a concrete Python project (POSIX counterpart of
# init.ps1 — use whichever matches your shell; both do the same thing).
#
# Replaces the placeholder tokens in file contents AND in file/folder names, then
# removes the template-only files (TEMPLATE.md, docs/AGENT-INIT-GUIDE.md) and —
# unless --keep-script — both initializers (init.sh and init.ps1).
#
# Two name tokens are stamped:
#   __ProjectName__  — the PyPI distribution / repo name, used verbatim (e.g.
#                      "acme-widgets"). Goes into pyproject `name`, URLs, LICENSE.
#   __PackageName__  — the importable package, DERIVED from the project name
#                      (lowercased, runs of non-alphanumerics -> '_', leading '_'
#                      added if it would start with a digit) — e.g. "Acme.Widgets"
#                      -> "acme_widgets". Names the src/ package dir and the imports.
#
# Usage:
#   bash ./scripts/init.sh --project-name acme-widgets \
#       [--author "Jane Doe"] [--author-email you@example.com] \
#       [--github-owner acme] [--description "Widget toolkit"] \
#       [--year 2026] [--keep-script]

set -euo pipefail

project_name=""
author=""
author_email=""
github_owner=""
description=""
year=""
keep_script=0

die() { echo "error: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --project-name) project_name="${2:-}"; shift 2 ;;
    --author)       author="${2:-}"; shift 2 ;;
    --author-email) author_email="${2:-}"; shift 2 ;;
    --github-owner) github_owner="${2:-}"; shift 2 ;;
    --description)  description="${2:-}"; shift 2 ;;
    --year)         year="${2:-}"; shift 2 ;;
    --keep-script)  keep_script=1; shift ;;
    -h|--help)      sed -n '2,22p' "$0"; exit 0 ;;
    *)              die "unknown argument: $1" ;;
  esac
done

[ -n "$project_name" ] || die "--project-name is required (e.g. --project-name acme-widgets)."

# Validate as a PEP 503 distribution name: ASCII letters, digits, '.', '-', '_',
# starting and ending with an alphanumeric. PyPI normalizes case and separators,
# but an out-of-set character (space, '/', '!', ...) would produce an invalid
# pyproject `name` that won't build — reject it here with a clear message.
case "$project_name" in
  *[!A-Za-z0-9._-]*) die "invalid --project-name '$project_name'. Use ASCII letters, digits, '.', '-', '_' (e.g. acme-widgets)." ;;
esac
case "$project_name" in
  [A-Za-z0-9]*) : ;;
  *) die "invalid --project-name '$project_name'. It must start with a letter or digit (e.g. acme-widgets)." ;;
esac
case "$project_name" in
  *[A-Za-z0-9]) : ;;
  *) die "invalid --project-name '$project_name'. It must end with a letter or digit (e.g. acme-widgets)." ;;
esac

# Derive the importable package name: lowercase, collapse runs of
# non-alphanumerics to '_', trim leading/trailing '_'.
package_name="$(printf '%s' "$project_name" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9]\{1,\}/_/g' -e 's/^_*//' -e 's/_*$//')"
[ -n "$package_name" ] || die "invalid --project-name '$project_name'. It must contain at least one ASCII letter or digit so a Python package name can be derived (e.g. acme-widgets)."
# A Python identifier cannot start with a digit; prefix '_' so the package stays importable.
case "$package_name" in
  [0-9]*) package_name="_$package_name" ;;
esac

# Defaults (mirror init.ps1).
if [ -z "$author" ]; then
  author="$(git config user.name 2>/dev/null || true)"
  [ -n "$author" ] || author="Your Name"
fi
if [ -z "$author_email" ]; then
  author_email="$(git config user.email 2>/dev/null || true)"
  [ -n "$author_email" ] || author_email="you@example.com"
fi
[ -n "$github_owner" ] || github_owner="your-org"
[ -n "$description" ]  || description="TODO: project description"
[ -n "$year" ]         || year="$(date +%Y)"

if ! printf '%s' "$year" | LC_ALL=C grep -Eq '^[0-9]+$'; then
  die "invalid --year '$year'. Use a non-negative number."
fi

# These values are copied into TOML, Markdown, YAML block scalars, and shell
# source. Reject characters that could change any of those contexts before the
# first file is touched. Safe values are kept verbatim in every target format.
assert_safe_metadata() {
  local label=$1 value=$2 unsafe=0
  if printf '%s' "$value" | LC_ALL=C grep -q '[[:cntrl:]"$`\\;&|<>]'; then
    unsafe=1
  fi
  case "$value" in
    *$'\n'*) unsafe=1 ;;
    *"'"*) unsafe=1 ;;
  esac
  [ "$unsafe" -eq 0 ] || die "invalid $label. The value contains a control character, quote, backslash, or shell operator; these values are unsafe in generated TOML/YAML/Markdown/shell contexts."
}

assert_safe_metadata "--author" "$author"
assert_safe_metadata "--author-email" "$author_email"
assert_safe_metadata "--github-owner" "$github_owner"
assert_safe_metadata "--description" "$description"
if ! printf '%s' "$github_owner" | LC_ALL=C grep -Eq '^[A-Za-z0-9]([A-Za-z0-9-]{0,37}[A-Za-z0-9])?$'; then
  die "invalid --github-owner '$github_owner'. Use a GitHub owner name of 1-39 letters, digits, or internal hyphens."
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
self="$script_dir/$(basename "$0")"
sibling_ps1="$script_dir/init.ps1"

# Keep TOML escaping defensive even though the metadata preflight above rejects
# quotes and backslashes. The derived package name is [a-z0-9_] only, so it is safe.
toml_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
project_t="$(toml_escape "$project_name")"
author_t="$(toml_escape "$author")"
author_email_t="$(toml_escape "$author_email")"
owner_t="$(toml_escape "$github_owner")"
desc_t="$(toml_escape "$description")"
year_t="$(toml_escape "$year")"

echo "==> Initializing template as '$project_name' (package '$package_name')"

# Literal, backslash-safe token replacement via awk's ENVIRON (no escape
# processing, unlike bash's ${var//pat/repl} which mangles doubled backslashes).
# The whole file is handled in BEGIN so no record splitting adds/drops a newline.
substitute_tokens() {
  awk '
    function repl(s, tok, val,   out, i) {
      out = ""
      while ((i = index(s, tok)) > 0) {
        out = out substr(s, 1, i - 1) val
        s = substr(s, i + length(tok))
      }
      return out s
    }
    BEGIN {
      s = ENVIRON["TPL_SRC"]
      s = repl(s, "__ProjectName__", ENVIRON["TPL_PROJECT"])
      s = repl(s, "__PackageName__", ENVIRON["TPL_PACKAGE"])
      s = repl(s, "__Author__",      ENVIRON["TPL_AUTHOR"])
      s = repl(s, "__AuthorEmail__", ENVIRON["TPL_AUTHOR_EMAIL"])
      s = repl(s, "__GitHubOwner__", ENVIRON["TPL_OWNER"])
      s = repl(s, "__Description__", ENVIRON["TPL_DESC"])
      s = repl(s, "__Year__",        ENVIRON["TPL_YEAR"])
      printf "%s", s
    }'
}

# 1) Replace tokens in file contents. Both initializers are skipped: they carry
#    the literal token strings as search keys, so substituting inside them would
#    corrupt the sibling script. Build output dirs are pruned.
changed=0
while IFS= read -r -d '' file; do
  case "$file" in
    "$self"|"$sibling_ps1") continue ;;
  esac
  case "$file" in
    *.toml) p=$project_t; a=$author_t; ae=$author_email_t; o=$owner_t; d=$desc_t; y=$year_t ;;
    *)      p=$project_name; a=$author; ae=$author_email; o=$github_owner; d=$description; y=$year ;;
  esac
  # Preserve trailing newlines: append a sentinel before capture, strip it after.
  content="$(cat "$file"; printf x)"; content="${content%x}"
  new="$(TPL_SRC="$content" TPL_PROJECT="$p" TPL_PACKAGE="$package_name" TPL_AUTHOR="$a" \
         TPL_AUTHOR_EMAIL="$ae" TPL_OWNER="$o" TPL_DESC="$d" TPL_YEAR="$y" substitute_tokens; printf x)"
  new="${new%x}"
  if [ "$new" != "$content" ]; then
    printf '%s' "$new" > "$file"
    changed=$((changed + 1))
  fi
done < <(find "$repo_root" -type d \( -name .git -o -name .jj -o -name .venv -o -name dist -o -name build -o -name __pycache__ \) -prune -o -type f -print0)
echo "    Updated contents in $changed file(s)."

# 2) Rename files and folders whose name contains a name token. -depth processes
#    children before parents so a renamed dir doesn't invalidate paths. The src
#    package dir (src/__PackageName__) is the main case.
while IFS= read -r -d '' item; do
  case "$item" in
    */.git/*|*/.jj/*|*/.venv/*) continue ;;
  esac
  dir="$(dirname "$item")"
  base="$(basename "$item")"
  newbase="${base//__ProjectName__/$project_name}"
  newbase="${newbase//__PackageName__/$package_name}"
  if [ "$newbase" != "$base" ]; then
    mv "$item" "$dir/$newbase"
    echo "    Renamed $base -> $newbase"
  fi
done < <(find "$repo_root" -depth \( -name '*__ProjectName__*' -o -name '*__PackageName__*' \) -print0)

# 3) Activate the Claude Code shared settings.
if [ -f "$repo_root/.claude/settings.json.template" ]; then
  mv -f "$repo_root/.claude/settings.json.template" "$repo_root/.claude/settings.json"
  echo "    Activated .claude/settings.json"
fi

# 4) Remove template-only files.
rm -f "$repo_root/TEMPLATE.md" "$repo_root/docs/AGENT-INIT-GUIDE.md"
rmdir "$repo_root/docs" 2>/dev/null || true

echo ""
echo "Done. Next steps:"
echo "  1. uv run pytest"
echo "  2. uv run ruff format --check . && uv run ruff check . && uv run mypy"
echo "  3. Review LICENSE (author/year) and the package metadata in pyproject.toml."
echo "  4. Publishing: add the PYPI_API_TOKEN repo secret, or delete"
echo "     .github/workflows/release.yml and the [project.urls] / packaging metadata."
echo "  5. Replace src/$package_name with your code and delete the sample test, then commit."

# 5) Remove both initializers unless asked to keep them.
if [ "$keep_script" -ne 1 ]; then
  rm -f "$sibling_ps1"
  rm -f "$self"
fi
