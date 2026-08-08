#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SIBLING_ROOT=${HW_CALENDAR_SIBLING_ROOT:-"$ROOT/.."}
DEPS_DIR=$("$ROOT/scripts/dependencies.sh" path cache)
REPORT_DIR="$DEPS_DIR/reports"
RUN_ID=$(date '+%Y-%m-%d-%H%M%S')
REPORT="$REPORT_DIR/$RUN_ID.log"
LATEST_REPORT="$REPORT_DIR/latest.log"
mkdir -p "$REPORT_DIR"

run_update() (
set -eu
TEMP_ROOT=
WORKTREE=

cleanup() {
  if [ -n "$WORKTREE" ] && [ -d "$WORKTREE" ]; then
    git -C "$ROOT" worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true
  fi
  if [ -n "$TEMP_ROOT" ] && [ -d "$TEMP_ROOT" ]; then
    find "$TEMP_ROOT" -depth -delete
  fi
}
trap cleanup EXIT HUP INT TERM

TEMP_ROOT=$(mktemp -d "$DEPS_DIR/.update.XXXXXX")
WORKTREE="$TEMP_ROOT/worktree"
BASE_COMMIT=$(git -C "$ROOT" rev-parse refs/heads/main)
git -C "$ROOT" worktree add --quiet --detach "$WORKTREE" "$BASE_COMMIT"
BASE_LOCK="$TEMP_ROOT/dependencies.lock"
cp "$WORKTREE/dependencies.lock" "$BASE_LOCK"
BASE_LOCK_VERSION=$(awk '$1 == "lock-version" {print $2; exit}' "$BASE_LOCK")
[ "$BASE_LOCK_VERSION" = 2 ] || {
  echo '[dependency-update] local main does not contain dependency lock format 2' >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    printf '[dependency-update] missing required command: %s\n' "$1" >&2
    exit 1
  }
}

for command_name in brew curl git jq shasum tar; do
  require_command "$command_name"
done

checksum() {
  shasum -a 256 "$1" | awk '{print $1}'
}

tag_commit() {
  local repository tag commit
  repository=$1
  tag=$2
  commit=$(git ls-remote "$repository" "refs/tags/$tag^{}" 2>/dev/null | awk 'NR == 1 {print $1}')
  if [ -z "$commit" ]; then
    commit=$(git ls-remote "$repository" "refs/tags/$tag" 2>/dev/null | awk 'NR == 1 {print $1}')
  fi
  [ -n "$commit" ] || return 1
  printf '%s\n' "$commit"
}

ODIN_RELEASES="$TEMP_ROOT/odin-releases.json"
curl -fsSL --retry 3 \
  'https://api.github.com/repos/odin-lang/Odin/releases?per_page=20' \
  -o "$ODIN_RELEASES"
ODIN_TAG=$(jq -r '[.[] | select(.draft == false and .prerelease == false and (.tag_name | test("^dev-[0-9]{4}-[0-9]{2}[a-z]*$")))][0].tag_name // empty' "$ODIN_RELEASES")
[ -n "$ODIN_TAG" ] || {
  echo '[dependency-update] no official Odin monthly release was found' >&2
  exit 1
}
ODIN_ASSET="odin-macos-arm64-$ODIN_TAG.tar.gz"
ODIN_URL=$(jq -r --arg tag "$ODIN_TAG" --arg asset "$ODIN_ASSET" \
  '.[] | select(.tag_name == $tag) | .assets[] | select(.name == $asset) | .browser_download_url' \
  "$ODIN_RELEASES")
[ -n "$ODIN_URL" ] || {
  printf '[dependency-update] Odin release %s has no macOS ARM64 archive\n' "$ODIN_TAG" >&2
  exit 1
}
ODIN_COMMIT=$(tag_commit https://github.com/odin-lang/Odin.git "$ODIN_TAG")
ODIN_SHA=$(jq -r --arg tag "$ODIN_TAG" --arg asset "$ODIN_ASSET" \
  '.[] | select(.tag_name == $tag) | .assets[] | select(.name == $asset) | .digest // empty' \
  "$ODIN_RELEASES" | sed 's/^sha256://')
mkdir -p "$DEPS_DIR/downloads"
if [ -n "$ODIN_SHA" ]; then
  ODIN_ARCHIVE="$DEPS_DIR/downloads/odin-$ODIN_TAG-$ODIN_SHA.tar.gz"
  if [ ! -f "$ODIN_ARCHIVE" ] || [ "$(checksum "$ODIN_ARCHIVE")" != "$ODIN_SHA" ]; then
    ODIN_DOWNLOAD="$TEMP_ROOT/$ODIN_ASSET"
    curl -fL --retry 3 -o "$ODIN_DOWNLOAD" "$ODIN_URL"
    [ "$(checksum "$ODIN_DOWNLOAD")" = "$ODIN_SHA" ] || {
      echo '[dependency-update] Odin archive checksum mismatch' >&2
      exit 1
    }
    mv "$ODIN_DOWNLOAD" "$ODIN_ARCHIVE"
  fi
else
  ODIN_ARCHIVE="$TEMP_ROOT/$ODIN_ASSET"
  curl -fL --retry 3 -o "$ODIN_ARCHIVE" "$ODIN_URL"
  ODIN_SHA=$(checksum "$ODIN_ARCHIVE")
fi
ODIN_EXTRACT="$TEMP_ROOT/odin"
mkdir -p "$ODIN_EXTRACT"
tar -xzf "$ODIN_ARCHIVE" -C "$ODIN_EXTRACT"
ODIN_ROOT=$(find "$ODIN_EXTRACT" -mindepth 1 -maxdepth 1 -type d -print -quit)
[ -n "$ODIN_ROOT" ] && [ -x "$ODIN_ROOT/odin" ] || {
  echo '[dependency-update] Odin archive has an invalid layout' >&2
  exit 1
}
ODIN_BINARY_SHORT=$("$ODIN_ROOT/odin" version | sed -n 's/.*:\([0-9a-f][0-9a-f]*\)$/\1/p')
[ -n "$ODIN_BINARY_SHORT" ] || {
  echo '[dependency-update] Odin binary does not report its source commit' >&2
  exit 1
}
ODIN_BINARY_METADATA="$TEMP_ROOT/odin-binary-commit.json"
curl -fsSL --retry 3 \
  "https://api.github.com/repos/odin-lang/Odin/commits/$ODIN_BINARY_SHORT" \
  -o "$ODIN_BINARY_METADATA"
ODIN_BINARY_COMMIT=$(jq -r '.sha // empty' "$ODIN_BINARY_METADATA")
[ -n "$ODIN_BINARY_COMMIT" ] || {
  echo '[dependency-update] Odin binary commit does not resolve in the official repository' >&2
  exit 1
}

LLVM_FORMULA="$TEMP_ROOT/llvm-formula.json"
brew info --json=v2 llvm > "$LLVM_FORMULA"
LLVM_VERSION=$(jq -r '.formulae[0].versions.stable // empty' "$LLVM_FORMULA")
LLVM_URL=$(jq -r '.formulae[0].bottle.stable.files | to_entries[0].value.url // empty' "$LLVM_FORMULA")
LLVM_SHA=$(jq -r '.formulae[0].bottle.stable.files | to_entries[0].value.sha256 // empty' "$LLVM_FORMULA")
[ -n "$LLVM_VERSION" ] && [ -n "$LLVM_URL" ] && [ -n "$LLVM_SHA" ] || {
  echo '[dependency-update] Homebrew did not report a stable ARM64 LLVM bottle' >&2
  exit 1
}
LLVM_CONFIG=/opt/homebrew/opt/llvm/bin/llvm-config
LLVM_CLANG=/opt/homebrew/opt/llvm/bin/clang
[ -x "$LLVM_CONFIG" ] && [ -x "$LLVM_CLANG" ] &&
  [ "$($LLVM_CONFIG --version)" = "$LLVM_VERSION" ] || {
  printf '[dependency-update] install Homebrew LLVM %s before validating its files\n' "$LLVM_VERSION" >&2
  exit 1
}
LLVM_ASAN=$($LLVM_CLANG --print-resource-dir 2>/dev/null)/lib/darwin/libclang_rt.asan_osx_dynamic.dylib
[ -x "$LLVM_CLANG" ] && [ -f "$LLVM_ASAN" ] || {
  echo '[dependency-update] the installed Homebrew LLVM is incomplete' >&2
  exit 1
}
LLVM_CLANG_SHA=$(checksum "$LLVM_CLANG")
LLVM_ASAN_SHA=$(checksum "$LLVM_ASAN")

ICONOIR_RELEASE="$TEMP_ROOT/iconoir-release.json"
curl -fsSL --retry 3 \
  'https://api.github.com/repos/iconoir-icons/iconoir/releases/latest' \
  -o "$ICONOIR_RELEASE"
ICONOIR_TAG=$(jq -r 'select(.draft == false and .prerelease == false) | .tag_name // empty' "$ICONOIR_RELEASE")
[ -n "$ICONOIR_TAG" ] || {
  echo '[dependency-update] no stable Iconoir release was found' >&2
  exit 1
}
ICONOIR_COMMIT=$(tag_commit https://github.com/iconoir-icons/iconoir.git "$ICONOIR_TAG")
ICONOIR_URL="https://github.com/iconoir-icons/iconoir/archive/refs/tags/$ICONOIR_TAG.tar.gz"
ICON_TARGET="$WORKTREE/resources/icons/iconoir"
CURRENT_ICONOIR_TAG=$(awk '$1 == "iconoir" {print $2; exit}' "$BASE_LOCK")
ICONOIR_ARCHIVE="$TEMP_ROOT/iconoir-$ICONOIR_TAG.tar.gz"
curl -fL --retry 3 -o "$ICONOIR_ARCHIVE" "$ICONOIR_URL"
ICONOIR_SHA=$(checksum "$ICONOIR_ARCHIVE")
if [ "$ICONOIR_TAG" = "$CURRENT_ICONOIR_TAG" ]; then
  CURRENT_ICONOIR_COMMIT=$(awk '$1 == "iconoir" {print $3; exit}' "$BASE_LOCK")
  CURRENT_ICONOIR_SHA=$(awk '$1 == "iconoir" {print $5; exit}' "$BASE_LOCK")
  [ "$ICONOIR_COMMIT" = "$CURRENT_ICONOIR_COMMIT" ] &&
    [ "$ICONOIR_SHA" = "$CURRENT_ICONOIR_SHA" ] || {
      printf '[dependency-update] Iconoir tag %s changed after it was locked\n' "$ICONOIR_TAG" >&2
      exit 1
    }
fi
ICONOIR_EXTRACT="$TEMP_ROOT/iconoir"
mkdir -p "$ICONOIR_EXTRACT"
tar -xzf "$ICONOIR_ARCHIVE" -C "$ICONOIR_EXTRACT"
ICONOIR_ROOT=$(find "$ICONOIR_EXTRACT" -mindepth 1 -maxdepth 1 -type d -print -quit)
[ -n "$ICONOIR_ROOT" ] || {
  echo '[dependency-update] Iconoir archive has an invalid layout' >&2
  exit 1
}
for name in maximize.svg minus.svg settings.svg xmark.svg; do
  cp "$ICONOIR_ROOT/icons/regular/$name" "$ICON_TARGET/$name"
done
cp "$ICONOIR_ROOT/LICENSE" "$ICON_TARGET/LICENSE"

CANDIDATE_LOCK="$WORKTREE/dependencies.lock"
{
  printf '# hw_calendar dependency lock, format 2.\n'
  printf 'lock-version 2\n\n'
  printf '# Official Odin monthly release for macOS ARM64.\n'
  printf 'odin %s %s %s %s macos-arm64\n' \
    "$ODIN_TAG" "$ODIN_COMMIT" "$ODIN_URL" "$ODIN_SHA"
  printf 'odin-binary %s\n\n' "$ODIN_BINARY_COMMIT"
  printf 'llvm %s %s %s homebrew-arm64\n\n' \
    "$LLVM_VERSION" "$LLVM_URL" "$LLVM_SHA"
  printf 'llvm-file clang %s\n' "$LLVM_CLANG_SHA"
  printf 'llvm-file asan-runtime %s\n\n' "$LLVM_ASAN_SHA"
  printf '# Sibling repository, tracked branch, and tested commit.\n'
  while read -r kind name url branch locked_revision extra; do
    [ "$kind" = git ] || continue
    revision=$(git ls-remote "$url" "refs/heads/$branch" 2>/dev/null | awk 'NR == 1 {print $1}')
    [ -n "$revision" ] || {
      printf '[dependency-update] could not resolve remote %s branch %s\n' "$name" "$branch" >&2
      exit 1
    }
    printf 'git %s %s %s %s\n' "$name" "$url" "$branch" "$revision"
  done < "$BASE_LOCK"
  printf '\n# Bundled Iconoir release and file checksums.\n'
  printf 'iconoir %s %s %s %s\n' \
    "$ICONOIR_TAG" "$ICONOIR_COMMIT" "$ICONOIR_URL" "$ICONOIR_SHA"
  for name in maximize.svg minus.svg settings.svg xmark.svg LICENSE; do
    printf 'iconoir-file %s %s\n' "$name" "$(checksum "$ICON_TARGET/$name")"
  done
} > "$CANDIDATE_LOCK"

sed -i '' -E \
  "s/^- Iconoir Regular .*/- Iconoir Regular ${ICONOIR_TAG#v} at commit \`$ICONOIR_COMMIT\`/" \
  "$WORKTREE/README.md"
sed -i '' -E \
  "s#^- Source: <https://github.com/iconoir-icons/iconoir/tree/[^>]*/icons/regular>#- Source: <https://github.com/iconoir-icons/iconoir/tree/$ICONOIR_TAG/icons/regular>#" \
  "$WORKTREE/README.md"
sed -i '' -E \
  "s/^- Archive SHA-256: .*/- Archive SHA-256: \`$ICONOIR_SHA\`/" \
  "$WORKTREE/README.md"

if git -C "$WORKTREE" diff --quiet; then
  printf '[dependency-update] no dependency changes from %s\n' "$BASE_COMMIT"
  printf 'odin: %s %s\n' "$ODIN_TAG" "$ODIN_COMMIT"
  printf 'llvm: %s %s\n' "$LLVM_VERSION" "$LLVM_SHA"
  printf 'iconoir: %s %s\n' "$ICONOIR_TAG" "$ICONOIR_COMMIT"
  exit 0
fi

CANDIDATE_SHA=$(checksum "$CANDIDATE_LOCK")
for existing_branch in $(git -C "$ROOT" for-each-ref \
  --format='%(refname:short)' 'refs/heads/chore/dependency-update-*')
do
  existing_sha=$(git -C "$ROOT" show "$existing_branch:dependencies.lock" 2>/dev/null |
    shasum -a 256 | awk '{print $1}')
  if [ "$existing_sha" = "$CANDIDATE_SHA" ]; then
    printf '[dependency-update] candidate already exists on local branch %s\n' "$existing_branch"
    printf 'lock: %s\n' "$CANDIDATE_SHA"
    exit 0
  fi
done

printf '[dependency-update] validating candidate from %s\n' "$BASE_COMMIT"
printf 'odin: %s %s\n' "$ODIN_TAG" "$ODIN_COMMIT"
printf 'llvm: %s %s\n' "$LLVM_VERSION" "$LLVM_SHA"
printf 'iconoir: %s %s\n' "$ICONOIR_TAG" "$ICONOIR_COMMIT"

if ! env \
  HW_CALENDAR_DEPENDENCY_LOCK="$WORKTREE/dependencies.lock" \
  HW_CALENDAR_SIBLING_ROOT="$SIBLING_ROOT" \
  "$WORKTREE/scripts/dependencies.sh" sync ||
   ! env \
  HW_CALENDAR_DEPENDENCY_LOCK="$WORKTREE/dependencies.lock" \
  HW_CALENDAR_SIBLING_ROOT="$SIBLING_ROOT" \
  "$WORKTREE/scripts/dependency-validation.sh"
then
  printf '[dependency-update] candidate failed; main and the lock are unchanged\n'
  exit 1
fi

BRANCH="chore/dependency-update-$(date '+%Y-%m-%d')"
if git -C "$ROOT" show-ref --verify --quiet "refs/heads/$BRANCH"; then
  BRANCH="$BRANCH-$RUN_ID"
fi
git -C "$WORKTREE" switch --quiet -c "$BRANCH"
git -C "$WORKTREE" add dependencies.lock README.md resources/icons/iconoir
git -C "$WORKTREE" commit --quiet -m 'chore(deps): update locked dependencies'
printf '[dependency-update] created local branch %s\n' "$BRANCH"
)

result=0
run_update > "$REPORT" 2>&1 || result=$?
cp "$REPORT" "$LATEST_REPORT"
cat "$REPORT"
exit "$result"
