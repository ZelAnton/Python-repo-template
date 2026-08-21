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
temporary_path=""
cleanup_failure_injected=0

die() {
  failure_reason="$*"
  printf 'error: %s\n' "$failure_reason" >&2
  exit 1
}

on_exit() {
  local status=$? rollback_status=0 cleanup_status=0 cleanup_message=""
  trap - EXIT ERR
  set +e
  if [ "$status" -eq 0 ] && [ "$transaction_active" -eq 1 ]; then
    if ! cleanup_transaction "$transaction_root"; then
      status=1
      failure_reason="${failure_reason:-staging cleanup failed}"
    fi
  fi
  if [ "$status" -ne 0 ] && [ "$transaction_active" -eq 1 ]; then
    if ! remove_mutable_tree "$repo_root"; then rollback_status=1; fi
    if ! copy_mutable_tree "$rollback_root" "$repo_root"; then rollback_status=1; fi
  fi
  if [ -n "$transaction_root" ]; then
    if ! cleanup_transaction "$transaction_root"; then
      cleanup_status=1
      cleanup_message="staging directory '$transaction_root' could not be removed"
    fi
  fi
  if [ -n "$temporary_path" ] && [ -e "$temporary_path" ] && ! rm -f "$temporary_path"; then
    cleanup_status=1
    cleanup_message="temporary file '$temporary_path' could not be removed"
  fi
  if [ "$rollback_status" -ne 0 ]; then
    status=1
    failure_reason="${failure_reason:-initialization failed}; rollback failed"
  fi
  if [ "$cleanup_status" -ne 0 ]; then
    status=1
    failure_reason="${failure_reason:-initialization failed}; $cleanup_message"
  fi
  if [ "$status" -ne 0 ]; then
    printf 'error: initialization failed: %s\n' "${failure_reason:-command failed}" >&2
    if [ -n "$transaction_root" ]; then
      printf 'error: staging artifact remains at: %s\n' "$transaction_root" >&2
    fi
  fi
  exit "$status"
}

trap 'failure_reason="command failed near line $LINENO"' ERR
trap on_exit EXIT

require_option_value() {
  local option="$1"
  [ "$#" -ge 2 ] || die "$option requires a value."
  case "$2" in
    -)
      ;;
    '- '*|'---'|'- - -')
      # Let the metadata preflight report Markdown block syntax for descriptions.
      ;;
    -*) die "$option requires a value." ;;
  esac
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project-name)
      require_option_value "$@"
      project_name="$2"
      shift 2
      ;;
    --author)
      require_option_value "$@"
      author="$2"
      shift 2
      ;;
    --author-email)
      require_option_value "$@"
      author_email="$2"
      shift 2
      ;;
    --github-owner)
      require_option_value "$@"
      github_owner="$2"
      shift 2
      ;;
    --description)
      require_option_value "$@"
      description="$2"
      shift 2
      ;;
    --year)
      require_option_value "$@"
      year="$2"
      shift 2
      ;;
    --keep-script)  keep_script=1; shift ;;
    -h|--help)      sed -n '2,22p' "$0"; exit 0 ;;
    *)              die "unknown argument: $1" ;;
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

if ! printf '%s' "$year" | LC_ALL=C grep -Eq '^[0-9]+$'; then
  die "invalid --year '$year'. Use a non-negative number."
fi

# These values are copied into TOML, Markdown, YAML block scalars, and shell
# source. Reject characters that could change any of those contexts before the
# first file is touched. Safe values are kept verbatim in every target format.
assert_safe_metadata() {
  local label=$1 value=$2 unsafe=0 markdown_unsafe=0 unicode_status
  if printf '%s' "$value" | has_unsafe_unicode; then
    unsafe=1
  else
    unicode_status=$?
    if [ "$unicode_status" -gt 1 ]; then unsafe=1; fi
  fi
  case "$value" in
    *$'\302\205'*|*$'\342\200\250'*|*$'\342\200\251'*) unsafe=1 ;;
  esac
  case "$value" in
    *$'\n'*|*$'\r'*) unsafe=1 ;;
    *'"'*|*"'"*|*'\'*|*'$'*|*'`'*|*';'*|*'&'*|*'|'*|*'<'*|*'>'*) unsafe=1 ;;
  esac
  if [ "$label" = "--description" ]; then
    case "$value" in
      *'['*|*']'*|*'('*|*')'*|*'#'*|*'*'*|*'_'*|*'~'*)
        unsafe=1
        markdown_unsafe=1
        ;;
      *$'\t'*)
        unsafe=1
        markdown_unsafe=1
        ;;
    esac
    # Description is a standalone README paragraph; reject Markdown block
    # starters before any template file is changed.
    if printf '%s' "$value" | grep -Eq '(^[[:blank:]]{4}|^[[:blank:]]{0,3}([-+*][[:blank:]]+.*|[0-9]{1,9}[.)][[:blank:]]+.*|[-+*]|[0-9]{1,9}[.)]|(-[[:blank:]]*){3,}|(_[[:blank:]]*){3,}|(\*[[:blank:]]*){3,})$)'; then
      unsafe=1
      markdown_unsafe=1
    fi
  fi
  if [ "$unsafe" -ne 0 ]; then
    if [ "$markdown_unsafe" -ne 0 ] && [ "$label" = "--description" ]; then
      die "invalid $label. The value contains unsafe Markdown control syntax; use plain text for the generated README description."
    fi
    die "invalid $label. The value contains a control character, quote, backslash, or shell operator; these values are unsafe in generated TOML/YAML/Markdown/shell contexts."
  fi
}

has_unsafe_unicode() {
  LC_ALL=C awk '
    {
      if ($0 ~ /[\001-\010\013\014\016-\037\177]/ ||
          $0 ~ /\302[\200-\237]/ ||
          $0 ~ /\302\255|\330[\200-\205]|\330\234|\331\235|\334\217/ ||
          $0 ~ /\340\242[\220-\221]|\341\240\216/ ||
          $0 ~ /\342\200[\213-\217]|\342\200[\252-\256]/ ||
          $0 ~ /\342\201[\240-\244]|\342\201[\246-\257]/ ||
          $0 ~ /\357\273\277/) {
        found=1
      }
    }
    END { exit found ? 0 : 1 }
  '
}

assert_safe_metadata "--author" "$author"
assert_safe_metadata "--author-email" "$author_email"
assert_safe_metadata "--github-owner" "$github_owner"
assert_safe_metadata "--description" "$description"
if ! printf '%s' "$github_owner" | LC_ALL=C grep -Eq '^[A-Za-z0-9]([A-Za-z0-9-]{0,37}[A-Za-z0-9])?$'; then
  die "invalid --github-owner '$github_owner'. Use a GitHub owner name of 1-39 letters, digits, or internal hyphens."
fi

if ! printf '%s' "$year" | LC_ALL=C grep -Eq '^[0-9]+$'; then
  die "invalid --year '$year'. Use a non-negative number."
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
self="$script_dir/$(basename "$0")"
sibling_ps1="$script_dir/init.ps1"
claude_template="$repo_root/.claude/settings.json.template"
claude_settings="$repo_root/.claude/settings.json"
docs_dir="$repo_root/docs"

# Keep TOML escaping defensive even though the metadata preflight above rejects
# quotes and backslashes. The derived package name is [a-z0-9_] only, so it is safe.
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
  mkdir -p "$destination_root"
  while IFS= read -r -d '' item; do
    [ "$item" = "$source_root" ] && continue
    is_excluded "$item" && continue
    relative="${item#"$source_root"/}"
    destination="$destination_root/$relative"
    if [ -d "$item" ] && [ ! -L "$item" ]; then mkdir -p "$destination"; else mkdir -p "$(dirname "$destination")"; cp -p "$item" "$destination"; fi
  done < <(find "$source_root" -print0)
}

remove_mutable_tree() {
  local root="$1" item
  while IFS= read -r -d '' item; do
    [ "$item" = "$root" ] && continue
    is_excluded "$item" && continue
    if [ -d "$item" ] && [ ! -L "$item" ]; then
      # An excluded child may remain; preserve that directory, but report any
      # other removal failure to the transaction owner.
      if ! rmdir "$item" 2>/dev/null; then
        local mutable_child=0 child
        while IFS= read -r -d '' child; do
          [ "$child" = "$item" ] && continue
          if ! is_excluded "$child"; then mutable_child=1; break; fi
        done < <(find "$item" -print0)
        if [ "$mutable_child" -ne 0 ]; then return 1; fi
      fi
    else
      rm -f "$item" || return 1
    fi
  done < <(find "$root" -depth -print0)
}

remove_empty_directory() {
  local directory="$1" child has_child=0
  [ -d "$directory" ] || return 0
  if rmdir "$directory" 2>/dev/null; then return 0; fi
  for child in "$directory"/* "$directory"/.[!.]* "$directory"/..?*; do
    if [ -e "$child" ] || [ -L "$child" ]; then has_child=1; break; fi
  done
  [ "$has_child" -ne 0 ]
}

inject_failure() {
  if [ "${TEMPLATE_INIT_FAIL_AT:-}" = "$1" ]; then die "Injected failure at '$1'."; fi
}

cleanup_transaction() {
  local path="$1"
  if [ "${TEMPLATE_INIT_FAIL_AT:-}" = "cleanup" ] && [ "$cleanup_failure_injected" -eq 0 ]; then
    cleanup_failure_injected=1
    failure_reason="Injected failure at 'cleanup'."
    return 1
  fi
  if [ -n "$path" ] && [ -e "$path" ]; then
    if ! rm -rf "$path"; then
      failure_reason="staging cleanup failed for '$path'"
      return 1
    fi
  fi
  if [ -n "$path" ] && [ -e "$path" ]; then
    failure_reason="staging cleanup did not remove '$path'"
    return 1
  fi
  transaction_root=""
  transaction_active=0
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
  local parent="$(dirname "$path")"
  [ -d "$parent" ] || die "preflight cannot $operation '$path': parent directory '$parent' is missing."
  if [ ! -w "$parent" ] || [ ! -x "$parent" ]; then
    die "preflight cannot $operation '$path': parent directory '$parent' is not writable."
  fi
  local probe="$parent/.init-preflight-$$-${RANDOM}"
  if ! (set -C; : > "$probe") 2>/dev/null; then
    die "preflight cannot $operation '$path': parent directory '$parent' rejected a permission probe."
  fi
  if ! rm -f "$probe"; then
    die "preflight cannot $operation '$path': permission probe '$probe' could not be removed."
  fi
  if [ -d "$path" ]; then
    if [ ! -w "$path" ] || [ ! -x "$path" ]; then
      die "preflight cannot $operation '$path': directory is not writable."
    fi
  fi
}

echo "==> Initializing template as '$project_name' (package '$package_name')"

transaction_id="$(date +%s)-$$"
transaction_root="$(mktemp -d "${TMPDIR:-/tmp}/python-template-init.XXXXXX")"
candidate_root="$transaction_root/candidate"
content_root="$transaction_root/content"
rollback_root="$transaction_root/rollback"
rename_plan="$transaction_root/rename-plan"
rename_sources_plan="$transaction_root/rename-sources"
rename_targets_plan="$transaction_root/rename-targets"
: > "$rename_plan"
: > "$rename_sources_plan"
: > "$rename_targets_plan"
mkdir -p "$content_root"
content_count=0

plan_contains() {
  local plan="$1" needle="$2" entry
  while IFS= read -r -d '' entry; do
    [ "$entry" = "$needle" ] && return 0
  done < "$plan"
  return 1
}

# Stage approved content while completing preflight; no checkout file is changed
# until the candidate and rollback trees have been prepared below.
while IFS= read -r -d '' file; do
  [ "$file" = "$self" ] || [ "$file" = "$sibling_ps1" ] || {
    if ! content="$(cat "$file"; producer_status=$?; if [ "$producer_status" -ne 0 ]; then exit "$producer_status"; fi; printf '\001' || exit "$?")"; then
      die "preflight cannot read '$file'."
    fi
    content="${content%$'\001'}"
    case "$file" in
      *.toml) p="$project_t"; a="$author_t"; ae="$author_email_t"; o="$owner_t"; d="$desc_t"; y="$year_t" ;;
      *) p="$project_name"; a="$author"; ae="$author_email"; o="$github_owner"; d="$description"; y="$year" ;;
    esac
    if ! new="$(TPL_SRC="$content" TPL_PROJECT="$p" TPL_PACKAGE="$package_name" TPL_AUTHOR="$a" TPL_AUTHOR_EMAIL="$ae" TPL_OWNER="$o" TPL_DESC="$d" TPL_YEAR="$y" substitute_tokens; producer_status=$?; if [ "$producer_status" -ne 0 ]; then exit "$producer_status"; fi; printf '\001' || exit "$?")"; then
      die "preflight could not stage '$file'."
    fi
    new="${new%$'\001'}"
    if [ "$new" != "$content" ]; then
      assert_writable "$file" write
      relative="${file#"$repo_root"/}"
      staged="$content_root/$relative"
      mkdir -p "$(dirname "$staged")"
      printf '%s' "$new" > "$staged"
      content_count=$((content_count + 1))
    fi
  }
done < <(find "$repo_root" -type d \( -name .git -o -name .jj -o -name .venv -o -name dist -o -name build -o -name __pycache__ \) -prune -o -type f -print0)

while IFS= read -r -d '' item; do
  is_excluded "$item" && continue
  base="$(basename "$item")"
  case "$base" in *__ProjectName__*|*__PackageName__*) ;; *) continue ;; esac
  dir="$(dirname "$item")"
  newbase="${base//__ProjectName__/$project_name}"
  newbase="${newbase//__PackageName__/$package_name}"
  target="$dir/$newbase"
  [ "$target" = "$item" ] && continue
  if plan_contains "$rename_targets_plan" "$target"; then die "preflight rename conflict: multiple items target '$target'."; fi
  printf '%s\0' "$item" >> "$rename_sources_plan"
  printf '%s\0' "$target" >> "$rename_targets_plan"
  printf '%s\0%s\0%s\0' "$item" "$newbase" "$target" >> "$rename_plan"
done < <(find "$repo_root" -depth -print0)

while IFS= read -r -d '' source; do
  IFS= read -r -d '' newbase || die "preflight could not read the rename plan."
  IFS= read -r -d '' target || die "preflight could not read the rename plan."
  if [ -e "$target" ] && ! plan_contains "$rename_sources_plan" "$target"; then die "preflight rename conflict: target '$target' already exists."; fi
  [ -d "$(dirname "$target")" ] || die "preflight cannot rename '$source': target directory is missing."
  assert_writable "$source" rename
  assert_writable "$target" rename
done < "$rename_plan"

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

copy_mutable_tree "$repo_root" "$candidate_root"

while IFS= read -r -d '' staged; do
  relative="${staged#"$content_root"/}"
  candidate="$candidate_root/$relative"
  mkdir -p "$(dirname "$candidate")"
  cp -p "$staged" "$candidate"
done < <(find "$content_root" -type f -print0)
inject_failure content-write

while IFS= read -r -d '' source; do
  IFS= read -r -d '' newbase || die "preflight could not read the rename plan."
  IFS= read -r -d '' target || die "preflight could not read the rename plan."
  relative="${source#"$repo_root"/}"
  candidate="$candidate_root/$relative"
  mv "$candidate" "$(dirname "$candidate")/$newbase"
done < "$rename_plan"
inject_failure path-rename
candidate_template="$candidate_root/.claude/settings.json.template"
if [ -e "$candidate_template" ]; then mv "$candidate_template" "$candidate_root/.claude/settings.json"; fi
inject_failure settings-activation
for relative in TEMPLATE.md docs/AGENT-INIT-GUIDE.md; do rm -f "$candidate_root/$relative"; done
remove_empty_directory "$candidate_root/docs"
if [ "$keep_script" -eq 0 ]; then rm -f "$candidate_root/scripts/init.ps1" "$candidate_root/scripts/init.sh"; fi
inject_failure template-removal

copy_mutable_tree "$repo_root" "$rollback_root"
transaction_active=1
inject_failure apply-content-write
while IFS= read -r -d '' staged; do
  relative="${staged#"$content_root"/}"
  destination="$repo_root/$relative"
  temporary="$(dirname "$destination")/.init-$transaction_id-$(basename "$destination").tmp"
  temporary_path="$temporary"
  cp -p "$staged" "$temporary"
  mv -f "$temporary" "$destination"
  temporary_path=""
done < <(find "$content_root" -type f -print0)
inject_failure apply-path-rename
while IFS= read -r -d '' source; do
  IFS= read -r -d '' newbase || die "preflight could not read the rename plan."
  IFS= read -r -d '' target || die "preflight could not read the rename plan."
  mv "$source" "$(dirname "$source")/$newbase"
  echo "    Renamed $(basename "$source") -> $newbase"
done < "$rename_plan"
inject_failure apply-settings-activation
if [ -e "$claude_template" ]; then mv "$claude_template" "$claude_settings"; echo "    Activated .claude/settings.json"; fi
inject_failure apply-template-removal
rm -f "$repo_root/TEMPLATE.md" "$repo_root/docs/AGENT-INIT-GUIDE.md"
remove_empty_directory "$docs_dir"
if [ "$keep_script" -eq 0 ]; then rm -f "$sibling_ps1" "$self"; fi

if ! cleanup_transaction "$transaction_root"; then
  failure_reason="${failure_reason:-staging cleanup failed}; the transaction will be rolled back"
  exit 1
fi
echo "    Updated contents in $content_count file(s)."
echo
echo "Done. Next steps:"
echo "  1. uv run pytest"
echo "  2. uv run ruff format --check . && uv run ruff check . && uv run mypy"
echo "  3. Review LICENSE (author/year) and the package metadata in pyproject.toml."
echo "  4. Publishing: add the PYPI_API_TOKEN repo secret, or delete"
echo "     .github/workflows/release.yml and the [project.urls] / packaging metadata."
echo "  5. Replace src/$package_name with your code and delete the sample test, then commit."
