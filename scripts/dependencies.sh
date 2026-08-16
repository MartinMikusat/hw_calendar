#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
LOCK_FILE=${HW_CALENDAR_DEPENDENCY_LOCK:-"$ROOT/dependencies.lock"}
CACHE_BASE=${XDG_CACHE_HOME:-"${HOME:?HOME is not set}/Library/Caches"}
DEPS_DIR=${HW_CALENDAR_DEPS_DIR:-"$CACHE_BASE/hal-wayland/hw_calendar/dependencies"}
SIBLING_ROOT=${HW_CALENDAR_SIBLING_ROOT:-"$ROOT/.."}

fail() {
  printf '[hw_calendar] %s\n' "$1" >&2
  exit 1
}

checksum() {
  local file
  file=$1
  shasum -a 256 "$file" | awk '{print $1}'
}

lock_checksum() {
  checksum "$LOCK_FILE"
}

dependency_set_root() {
  printf '%s/sets/%s\n' "$DEPS_DIR" "$(lock_checksum)"
}

load_lock() {
  [ -f "$LOCK_FILE" ] || fail "missing dependency lock: $LOCK_FILE"

  LOCK_VERSION=
  LLVM_VERSION=
  LLVM_URL=
  LLVM_SHA=
  LLVM_PLATFORM=
  LLVM_CLANG_SHA=
  LLVM_ASAN_SHA=
  ICONOIR_TAG=
  ICONOIR_COMMIT=
  ICONOIR_URL=
  ICONOIR_SHA=
  GIT_COUNT=0
  ICON_FILE_COUNT=0
  seen_git_names=
  seen_icon_files=

  while read -r kind a b c d e extra; do
    case "$kind" in
      ''|'#'*) continue ;;
      lock-version)
        [ -n "$a" ] && [ -z "$b" ] && [ -z "$c" ] &&
          [ -z "$d" ] && [ -z "$e" ] && [ -z "$extra" ] ||
          fail "invalid lock-version entry"
        [ -z "$LOCK_VERSION" ] || fail "duplicate lock-version entry"
        LOCK_VERSION=$a
        ;;
      llvm)
        [ -n "$a" ] && [ -n "$b" ] && [ -n "$c" ] &&
          [ -n "$d" ] && [ -z "$e" ] && [ -z "$extra" ] ||
          fail "invalid LLVM lock entry"
        [ -z "$LLVM_VERSION" ] || fail "duplicate LLVM lock entry"
        LLVM_VERSION=$a
        LLVM_URL=$b
        LLVM_SHA=$c
        LLVM_PLATFORM=$d
        ;;
      llvm-file)
        [ -n "$a" ] && [ -n "$b" ] && [ -z "$c" ] &&
          [ -z "$d" ] && [ -z "$e" ] && [ -z "$extra" ] ||
          fail "invalid LLVM file entry: ${a:-<missing>}"
        case "$a" in
          clang)
            [ -z "$LLVM_CLANG_SHA" ] || fail "duplicate LLVM clang entry"
            LLVM_CLANG_SHA=$b
            ;;
          asan-runtime)
            [ -z "$LLVM_ASAN_SHA" ] || fail "duplicate LLVM ASan runtime entry"
            LLVM_ASAN_SHA=$b
            ;;
          *) fail "unknown LLVM file entry: $a" ;;
        esac
        ;;
      git)
        [ -n "$a" ] && [ -n "$b" ] && [ -n "$c" ] &&
          [ -n "$d" ] && [ -z "$e" ] && [ -z "$extra" ] ||
          fail "invalid git lock entry: ${a:-<missing>}"
        case " $seen_git_names " in
          *" $a "*) fail "duplicate git lock entry: $a" ;;
        esac
        seen_git_names="$seen_git_names $a"
        GIT_COUNT=$((GIT_COUNT + 1))
        ;;
      iconoir)
        [ -n "$a" ] && [ -n "$b" ] && [ -n "$c" ] &&
          [ -n "$d" ] && [ -z "$e" ] && [ -z "$extra" ] ||
          fail "invalid Iconoir lock entry"
        [ -z "$ICONOIR_TAG" ] || fail "duplicate Iconoir lock entry"
        ICONOIR_TAG=$a
        ICONOIR_COMMIT=$b
        ICONOIR_URL=$c
        ICONOIR_SHA=$d
        ;;
      iconoir-file)
        [ -n "$a" ] && [ -n "$b" ] && [ -z "$c" ] &&
          [ -z "$d" ] && [ -z "$e" ] && [ -z "$extra" ] ||
          fail "invalid Iconoir file entry: ${a:-<missing>}"
        case " $seen_icon_files " in
          *" $a "*) fail "duplicate Iconoir file entry: $a" ;;
        esac
        seen_icon_files="$seen_icon_files $a"
        ICON_FILE_COUNT=$((ICON_FILE_COUNT + 1))
        ;;
      *) fail "unknown dependency lock entry: $kind" ;;
    esac
  done < "$LOCK_FILE"

  [ "$LOCK_VERSION" = 2 ] || fail "unsupported dependency lock version: ${LOCK_VERSION:-<missing>}"
  [ -n "$LLVM_VERSION" ] || fail "dependency lock does not contain LLVM"
  [ "$LLVM_PLATFORM" = homebrew-arm64 ] || fail "unsupported LLVM platform: $LLVM_PLATFORM"
  [ -n "$LLVM_CLANG_SHA" ] || fail "dependency lock does not contain the LLVM clang checksum"
  [ -n "$LLVM_ASAN_SHA" ] || fail "dependency lock does not contain the LLVM ASan runtime checksum"
  case "$LLVM_URL" in
    *"sha256:$LLVM_SHA") ;;
    *) fail "LLVM bottle URL and checksum do not match" ;;
  esac
  [ "$GIT_COUNT" -eq 6 ] || fail "dependency lock must contain six sibling repositories"
  [ -n "$ICONOIR_TAG" ] || fail "dependency lock does not contain Iconoir"
  [ "$ICON_FILE_COUNT" -eq 2 ] || fail "dependency lock must contain two Iconoir files"

  for required in \
    hw_odin_matchSorter \
    hw_odin_ipc_localCommand \
    hw_odin_ui_flash \
    hw_odin_ui_commandPalette \
    hw_odin_ui_components \
    hw_odin_ui_framework
  do
    case " $seen_git_names " in
      *" $required "*) ;;
      *) fail "dependency lock does not contain $required" ;;
    esac
  done
}

check_llvm() {
  local llvm_config clang asan_runtime actual_version
  llvm_config=/opt/homebrew/opt/llvm/bin/llvm-config
  clang=/opt/homebrew/opt/llvm/bin/clang
  [ -x "$llvm_config" ] || fail "locked Homebrew LLVM is not installed; run brew install llvm"
  [ -x "$clang" ] || fail "locked Homebrew Clang is not installed"
  asan_runtime=$($clang --print-resource-dir 2>/dev/null)/lib/darwin/libclang_rt.asan_osx_dynamic.dylib
  actual_version=$($llvm_config --version)
  [ "$actual_version" = "$LLVM_VERSION" ] ||
    fail "Homebrew LLVM version mismatch: expected $LLVM_VERSION, found $actual_version"
  [ "$(checksum "$clang")" = "$LLVM_CLANG_SHA" ] || fail "locked Homebrew Clang checksum mismatch"
  [ -f "$asan_runtime" ] || fail "locked Homebrew ASan runtime is not installed"
  [ "$(checksum "$asan_runtime")" = "$LLVM_ASAN_SHA" ] ||
    fail "locked Homebrew ASan runtime checksum mismatch"
}

repository_set_is_valid() {
  local set_root kind name expected_url branch expected_revision extra
  local repository actual_url actual_revision
  set_root=$(dependency_set_root)
  while read -r kind name expected_url branch expected_revision extra; do
    [ "$kind" = git ] || continue
    [ -z "$extra" ] || fail "invalid git lock entry: $name"
    repository="$set_root/$name"
    git -C "$repository" rev-parse --git-dir >/dev/null 2>&1 || return 1
    actual_url=$(git -C "$repository" remote get-url origin 2>/dev/null || true)
    actual_revision=$(git -C "$repository" rev-parse HEAD)
    [ "$actual_url" = "$expected_url" ] || return 1
    [ "$actual_revision" = "$expected_revision" ] || return 1
    [ -z "$(git -C "$repository" status --porcelain)" ] || return 1
  done < "$LOCK_FILE"
}

check_repositories() {
  repository_set_is_valid || fail "locked repository set is missing or invalid; run ./scripts/dependencies.sh sync"
}

check_iconoir() {
  local kind name expected_sha extra file actual_sha
  while read -r kind name expected_sha extra; do
    [ "$kind" = iconoir-file ] || continue
    [ -z "$extra" ] || fail "invalid Iconoir file entry: $name"
    file="$ROOT/resources/icons/iconoir/$name"
    [ -f "$file" ] || fail "missing bundled Iconoir file: $name"
    actual_sha=$(checksum "$file")
    [ "$actual_sha" = "$expected_sha" ] || fail "Iconoir checksum mismatch: $name"
  done < "$LOCK_FILE"
  [ -f "$ROOT/resources/holidays/sk.json" ] || fail "missing bundled Slovak holiday data"
}

check_dependencies() {
  load_lock
  hw-odin toolchain doctor >/dev/null || fail "global Odin toolchain is unavailable"
  check_llvm
  check_repositories
  check_iconoir
  printf '[hw_calendar] dependencies match lock %s\n' "$(lock_checksum)"
}

download_locked_file() {
  local download_url download_sha download_target temporary actual_sha
  download_url=$1
  download_sha=$2
  download_target=$3
  if [ -f "$download_target" ] && [ "$(checksum "$download_target")" = "$download_sha" ]; then
    return
  fi
  temporary="$download_target.part.$$"
  if ! curl -fL --retry 3 --output "$temporary" "$download_url"; then
    rm -f "$temporary"
    fail "could not download: $download_url"
  fi
  actual_sha=$(checksum "$temporary")
  if [ "$actual_sha" != "$download_sha" ]; then
    rm -f "$temporary"
    fail "download checksum mismatch: $download_url"
  fi
  mv "$temporary" "$download_target"
}

sync_repository_set() {
  local target temporary kind name expected_url branch revision extra
  local source_repository clone_source
  target=$(dependency_set_root)
  if [ -d "$target" ]; then
    if repository_set_is_valid; then
      return
    fi
    find "$target" -depth -delete
  fi

  SYNC_TEMP_SET=$(mktemp -d "$DEPS_DIR/sets/.set.XXXXXX")
  temporary=$SYNC_TEMP_SET
  while read -r kind name expected_url branch revision extra; do
    [ "$kind" = git ] || continue
    [ -z "$extra" ] || fail "invalid git lock entry: $name"
    source_repository="$SIBLING_ROOT/$name"
    if git -C "$source_repository" cat-file -e "$revision^{commit}" >/dev/null 2>&1; then
      clone_source=$source_repository
    else
      clone_source=$expected_url
    fi
    if ! git clone --quiet --no-checkout "$clone_source" "$temporary/$name"; then
      fail "could not clone dependency: $name"
    fi
    git -C "$temporary/$name" remote set-url origin "$expected_url"
    if ! git -C "$temporary/$name" cat-file -e "$revision^{commit}" >/dev/null 2>&1; then
      git -C "$temporary/$name" fetch --quiet origin "$revision"
    fi
    git -C "$temporary/$name" checkout --quiet --detach "$revision"
  done < "$LOCK_FILE"
  mv "$temporary" "$target"
  SYNC_TEMP_SET=
}

cleanup_sync() {
  if [ -n "${SYNC_TEMP_SET:-}" ] && [ -d "$SYNC_TEMP_SET" ]; then
    find "$SYNC_TEMP_SET" -depth -delete
  fi
  if [ -n "${SYNC_LOCK_DIR:-}" ] && [ -f "$SYNC_LOCK_DIR/pid" ] &&
     [ "$(cat "$SYNC_LOCK_DIR/pid" 2>/dev/null || true)" = "$$" ]; then
    rm -f "$SYNC_LOCK_DIR/pid"
    rmdir "$SYNC_LOCK_DIR" 2>/dev/null || true
  fi
}

sync_dependencies() {
  local existing_pid
  load_lock
  mkdir -p "$DEPS_DIR/downloads" "$DEPS_DIR/sets"
  SYNC_LOCK_DIR="$DEPS_DIR/.sync-lock"
  SYNC_TEMP_SET=
  if ! mkdir "$SYNC_LOCK_DIR" 2>/dev/null; then
    existing_pid=$(cat "$SYNC_LOCK_DIR/pid" 2>/dev/null || true)
    case "$existing_pid" in
      ''|*[!0-9]*) ;;
      *)
        if kill -0 "$existing_pid" 2>/dev/null; then
          fail "another dependency synchronization is running: $SYNC_LOCK_DIR"
        fi
        ;;
    esac
    rm -f "$SYNC_LOCK_DIR/pid"
    rmdir "$SYNC_LOCK_DIR" 2>/dev/null || fail "invalid dependency synchronization lock: $SYNC_LOCK_DIR"
    mkdir "$SYNC_LOCK_DIR" || fail "could not acquire dependency synchronization lock: $SYNC_LOCK_DIR"
  fi
  printf '%s\n' "$$" > "$SYNC_LOCK_DIR/pid"
  trap cleanup_sync EXIT HUP INT TERM
  sync_repository_set
  rm "$SYNC_LOCK_DIR/pid"
  rmdir "$SYNC_LOCK_DIR"
  SYNC_LOCK_DIR=
  trap - EXIT HUP INT TERM
  check_dependencies
}

print_path() {
  local name
  load_lock
  case "${1:-}" in
    llvm-bin) printf '%s\n' /opt/homebrew/opt/llvm/bin ;;
    cache) printf '%s\n' "$DEPS_DIR" ;;
    repo)
      name=${2:-}
      case " $seen_git_names " in
        *" $name "*) printf '%s/%s\n' "$(dependency_set_root)" "$name" ;;
        *) fail "unknown dependency repository: ${name:-<missing>}" ;;
      esac
      ;;
    *) fail "usage: ./scripts/dependencies.sh path [llvm-bin|cache|repo NAME]" ;;
  esac
}

doctor_dependencies() {
  local sdk_version
  load_lock
  printf 'architecture: %s\n' "$(uname -m)"
  if command -v xcodebuild >/dev/null 2>&1; then
    xcodebuild -version | sed 's/^/xcode: /'
  else
    printf 'xcode: missing\n'
  fi
  if sdk_version=$(xcrun --show-sdk-version 2>/dev/null); then
    printf 'macos-sdk: %s\n' "$sdk_version"
  else
    printf 'macos-sdk: missing\n'
  fi
  if xcrun metal -help >/dev/null 2>&1; then
    printf 'metal-toolchain: available\n'
  else
    printf 'metal-toolchain: missing (required for release builds)\n'
  fi
  printf 'odin: %s\n' "$(hw-odin version | awk '{print $NF}')"
  if [ -x /opt/homebrew/opt/llvm/bin/llvm-config ]; then
    printf 'llvm: %s (locked %s)\n' \
      "$(/opt/homebrew/opt/llvm/bin/llvm-config --version)" "$LLVM_VERSION"
  else
    printf 'llvm: missing (locked %s)\n' "$LLVM_VERSION"
  fi
  printf 'dependency-cache: %s\n' "$DEPS_DIR"
  printf 'lock: %s\n' "$(lock_checksum)"
}

case "${1:-check}" in
  check) check_dependencies ;;
  sync) sync_dependencies ;;
  doctor) doctor_dependencies ;;
  update-candidate) exec "$ROOT/scripts/dependency-update.sh" ;;
  path) shift; print_path "$@" ;;
  *)
    echo "usage: ./scripts/dependencies.sh [check|sync|doctor|update-candidate|path]" >&2
    exit 2
    ;;
esac
