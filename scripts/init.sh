#!/usr/bin/env bash
#
# Initializes this template into a concrete Python project. The complete
# transformation is staged and validated before the checkout changes.

set -euo pipefail

project_name=""
author=""
author_email=""
github_owner=""
description=""
year=""
keep_script=0
repo_root=""
transaction_root=""
transaction_active=0
failure_reason=""
temp_paths=()

die() {
  failure_reason="$*"
  printf 'error: %s\n' "$failure_reason" >&2
  exit 1
}

on_exit() {
  local status=$?
  trap - EXIT ERR
  set +e
  if [ "$status" -ne 0 ] && [ "$transaction_active" -eq 1 ]; then
    remove_mutable_tree "$repo_root"
    copy_mutable_tree "$rollback_root" "$repo_root"
    if [ $? -ne 0 ]; then
      failure_reason="${failure_reason:-initialization failed}; rollback failed"
      status=1
    fi
  fi
  for temp in "${temp_paths[@]}"; do rm -f -- "$temp"; done
  if [ -n "$transaction_root" ]; then rm -rf -- "$transaction_root"; fi
  if [ "$status" -ne 0 ]; then
    printf 'error: initialization failed: %s\n' "${failure_reason:-command failed}" >&2
  fi
  exit "$status"
}

trap 'failure_reason="command failed near line $LINENO"' ERR
trap on_exit EXIT

while [ $# -gt 0 ]; do
  case "$1" in
    --project-name) project_name="${2:-}"; shift 2 ;;
    --author) author="${2:-}"; shift 2 ;;
    --author-email) author_email="${2:-}"; shift 2 ;;
    --github-owner) github_owner="${2:-}"; shift 2 ;;
    --description) description="${2:-}"; shift 2 ;;
    --year) year="${2:-}"; shift 2 ;;
    --keep-script) keep_script=1; shift ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ -n "$project_name" ] || die "--project-name is required (e.g. --project-name acme-widgets)."
case "$project_name" in
  *[!A-Za-z0-9._-]*) die "invalid --project-name '$project_name'. Use ASCII letters, digits, '.', '-', '_' (e.g. acme-widgets)." ;;
esac
case "$project_name" in
  [A-Za-z0-9]*) : ;;
  *) die "invalid --project-name '$project_name'. It must start with a letter or digit." ;;
esac
case "$project_name" in
  *[A-Za-z0-9]) : ;;
  *) die "invalid --project-name '$project_name'. It must end with a letter or digit." ;;
esac

package_name="$(printf '%s' "$project_name" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9]\{1,\}/_/g' -e 's/^_*//' -e 's/_*$//')"
[ -n "$package_name" ] || die "invalid --project-name '$project_name'. It cannot derive a package name."
case "$package_name" in [0-9]*) package_name="_$package_name" ;; esac

if [ -z "$author" ]; then author="$(git config user.name 2>/dev/null || true)"; [ -n "$author" ] || author="Your Name"; fi
if [ -z "$author_email" ]; then author_email="$(git config user.email 2>/dev/null || true)"; [ -n "$author_email" ] || author_email="you@example.com"; fi
[ -n "$github_owner" ] || github_owner="your-org"
[ -n "$description" ] || description="TODO: project description"
[ -n "$year" ] || year="$(date +%Y)"

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
self="$script_dir/$(basename "$0")"
sibling_ps1="$script_dir/init.ps1"
claude_template="$repo_root/.claude/settings.json.template"
claude_settings="$repo_root/.claude/settings.json"
docs_dir="$repo_root/docs"

toml_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
project_t="$(toml_escape "$project_name")"
author_t="$(toml_escape "$author")"
author_email_t="$(toml_escape "$author_email")"
owner_t="$(toml_escape "$github_owner")"
desc_t="$(toml_escape "$description")"
year_t="$(toml_escape "$year")"

is_excluded() {
  case "$1" in
    */.git|*/.git/*|*/.jj|*/.jj/*|*/.venv|*/.venv/*|*/dist|*/dist/*|*/build|*/build/*|*/__pycache__|*/__pycache__/*) return 0 ;;
    *) return 1 ;;
  esac
}

copy_mutable_tree() {
  local source_root="$1" destination_root="$2" item relative destination
  mkdir -p -- "$destination_root"
  while IFS= read -r -d '' item; do
    is_excluded "$item" && continue
    relative="${item#"$source_root"/}"
    destination="$destination_root/$relative"
    if [ -d "$item" ] && [ ! -L "$item" ]; then mkdir -p -- "$destination"; else mkdir -p -- "$(dirname "$destination")"; cp -p -- "$item" "$destination"; fi
  done < <(find "$source_root" -mindepth 1 -print0)
}

remove_mutable_tree() {
  local root="$1" item
  while IFS= read -r -d '' item; do
    is_excluded "$item" && continue
    if [ -d "$item" ] && [ ! -L "$item" ]; then
      # An excluded child may remain; rmdir intentionally leaves that directory intact.
      rmdir -- "$item" 2>/dev/null || true
    else
      rm -f -- "$item"
    fi
  done < <(find "$root" -mindepth 1 -depth -print0)
}

inject_failure() {
  if [ "${TEMPLATE_INIT_FAIL_AT:-}" = "$1" ]; then die "Injected failure at '$1'."; fi
}

substitute_tokens() {
  awk '
    function repl(s, tok, val,   out, i) {
      out = ""
      while ((i = index(s, tok)) > 0) { out = out substr(s, 1, i - 1) val; s = substr(s, i + length(tok)) }
      return out s
    }
    BEGIN {
      s = ENVIRON["TPL_SRC"]
      s = repl(s, "__ProjectName__", ENVIRON["TPL_PROJECT"])
      s = repl(s, "__PackageName__", ENVIRON["TPL_PACKAGE"])
      s = repl(s, "__Author__", ENVIRON["TPL_AUTHOR"])
      s = repl(s, "__AuthorEmail__", ENVIRON["TPL_AUTHOR_EMAIL"])
      s = repl(s, "__GitHubOwner__", ENVIRON["TPL_OWNER"])
      s = repl(s, "__Description__", ENVIRON["TPL_DESC"])
      s = repl(s, "__Year__", ENVIRON["TPL_YEAR"])
      printf "%s", s
    }'
}

assert_writable() {
  local path="$1" operation="$2"
  if [ -e "$path" ] && [ ! -w "$path" ]; then die "preflight cannot $operation '$path': it is not writable."; fi
  [ -d "$(dirname "$path")" ] || die "preflight cannot $operation '$path': parent directory is missing."
}

echo "==> Initializing template as '$project_name' (package '$package_name')"

declare -a content_paths=() content_values=() rename_sources=() rename_names=()
declare -A rename_source_set=() rename_target_set=()
mapfile -d '' all_files < <(find "$repo_root" -type d \( -name .git -o -name .jj -o -name .venv -o -name dist -o -name build -o -name __pycache__ \) -prune -o -type f -print0)
for file in "${all_files[@]}"; do
  [ "$file" = "$self" ] || [ "$file" = "$sibling_ps1" ] || {
    if ! content="$(cat -- "$file"; printf '\001')"; then die "preflight cannot read '$file'."; fi
    content="${content%$'\001'}"
    case "$file" in
      *.toml) p="$project_t"; a="$author_t"; ae="$author_email_t"; o="$owner_t"; d="$desc_t"; y="$year_t" ;;
      *) p="$project_name"; a="$author"; ae="$author_email"; o="$github_owner"; d="$description"; y="$year" ;;
    esac
    if ! new="$(TPL_SRC="$content" TPL_PROJECT="$p" TPL_PACKAGE="$package_name" TPL_AUTHOR="$a" TPL_AUTHOR_EMAIL="$ae" TPL_OWNER="$o" TPL_DESC="$d" TPL_YEAR="$y" substitute_tokens; printf '\001')"; then die "preflight could not stage '$file'."; fi
    new="${new%$'\001'}"
    if [ "$new" != "$content" ]; then assert_writable "$file" write; content_paths+=("${file#"$repo_root"/}"); content_values+=("$new"); fi
  }
done

while IFS= read -r -d '' item; do
  is_excluded "$item" && continue
  base="$(basename "$item")"
  case "$base" in *__ProjectName__*|*__PackageName__*) ;; *) continue ;; esac
  dir="$(dirname "$item")"
  newbase="${base//__ProjectName__/$project_name}"
  newbase="${newbase//__PackageName__/$package_name}"
  target="$dir/$newbase"
  [ "$target" = "$item" ] && continue
  if [ -n "${rename_target_set[$target]+x}" ]; then die "preflight rename conflict: multiple items target '$target'."; fi
  rename_source_set["$item"]=1; rename_target_set["$target"]="$item"
  rename_sources+=("${item#"$repo_root"/}"); rename_names+=("$newbase")
done < <(find "$repo_root" -depth -print0)

for index in "${!rename_sources[@]}"; do
  source="$repo_root/${rename_sources[$index]}"
  target="$(dirname "$source")/${rename_names[$index]}"
  if [ -e "$target" ] && [ -z "${rename_source_set[$target]+x}" ]; then die "preflight rename conflict: target '$target' already exists."; fi
  [ -d "$(dirname "$target")" ] || die "preflight cannot rename '$source': target directory is missing."
  assert_writable "$source" rename
done

if [ -e "$claude_template" ]; then
  [ ! -e "$claude_settings" ] || die "preflight settings conflict: both '$claude_template' and '$claude_settings' exist."
  assert_writable "$claude_template" "activate settings"
  assert_writable "$claude_settings" "activate settings"
fi
for relative in TEMPLATE.md docs/AGENT-INIT-GUIDE.md; do
  path="$repo_root/$relative"; [ ! -e "$path" ] || assert_writable "$path" remove
done
if [ -d "$docs_dir" ]; then assert_writable "$docs_dir" remove; fi
if [ "$keep_script" -eq 0 ]; then
  [ ! -e "$sibling_ps1" ] || assert_writable "$sibling_ps1" remove
  assert_writable "$self" remove
fi

transaction_id="$(date +%s)-$$"
transaction_root="$(mktemp -d "${TMPDIR:-/tmp}/python-template-init.XXXXXX")"
candidate_root="$transaction_root/candidate"
content_root="$transaction_root/content"
rollback_root="$transaction_root/rollback"
copy_mutable_tree "$repo_root" "$candidate_root"

for index in "${!content_paths[@]}"; do
  candidate="$candidate_root/${content_paths[$index]}"
  mkdir -p -- "$(dirname "$candidate")"
  printf '%s' "${content_values[$index]}" > "$candidate"
  staged="$content_root/${content_paths[$index]}"
  mkdir -p -- "$(dirname "$staged")"
  cp -p -- "$candidate" "$staged"
done
inject_failure content-write

for index in "${!rename_sources[@]}"; do
  candidate="$candidate_root/${rename_sources[$index]}"
  mv -- "$candidate" "$(dirname "$candidate")/${rename_names[$index]}"
done
inject_failure path-rename
candidate_template="$candidate_root/.claude/settings.json.template"
if [ -e "$candidate_template" ]; then mv -- "$candidate_template" "$candidate_root/.claude/settings.json"; fi
inject_failure settings-activation
for relative in TEMPLATE.md docs/AGENT-INIT-GUIDE.md; do rm -f -- "$candidate_root/$relative"; done
rmdir -- "$candidate_root/docs" 2>/dev/null || true
if [ "$keep_script" -eq 0 ]; then rm -f -- "$candidate_root/scripts/init.ps1" "$candidate_root/scripts/init.sh"; fi
inject_failure template-removal

copy_mutable_tree "$repo_root" "$rollback_root"
transaction_active=1
inject_failure apply-content-write
for index in "${!content_paths[@]}"; do
  destination="$repo_root/${content_paths[$index]}"
  temporary="$(dirname "$destination")/.init-$transaction_id-$(basename "$destination").tmp"
  temp_paths+=("$temporary")
  cp -p -- "$content_root/${content_paths[$index]}" "$temporary"
  mv -f -- "$temporary" "$destination"
done
inject_failure apply-path-rename
for index in "${!rename_sources[@]}"; do
  source="$repo_root/${rename_sources[$index]}"
  mv -- "$source" "$(dirname "$source")/${rename_names[$index]}"
  echo "    Renamed $(basename "$source") -> ${rename_names[$index]}"
done
inject_failure apply-settings-activation
if [ -e "$claude_template" ]; then mv -- "$claude_template" "$claude_settings"; echo "    Activated .claude/settings.json"; fi
inject_failure apply-template-removal
rm -f -- "$repo_root/TEMPLATE.md" "$repo_root/docs/AGENT-INIT-GUIDE.md"
rmdir -- "$docs_dir" 2>/dev/null || true
if [ "$keep_script" -eq 0 ]; then rm -f -- "$sibling_ps1" "$self"; fi

transaction_active=0
rm -rf -- "$transaction_root"
transaction_root=""
echo "    Updated contents in ${#content_paths[@]} file(s)."
echo
echo "Done. Next steps:"
echo "  1. uv run pytest"
echo "  2. uv run ruff format --check . && uv run ruff check . && uv run mypy"
echo "  3. Review LICENSE (author/year) and the package metadata in pyproject.toml."
echo "  4. Publishing: add the PYPI_API_TOKEN repo secret, or delete"
echo "     .github/workflows/release.yml and the [project.urls] / packaging metadata."
echo "  5. Replace src/$package_name with your code and delete the sample test, then commit."
