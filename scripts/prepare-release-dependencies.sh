#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
LOCK="$ROOT/release-dependencies.lock"
CACHE=${HW_CALENDAR_RELEASE_CACHE:-"$ROOT/build/release-dependencies"}
ARCHIVES="$CACHE/archives"
INSTALL="$CACHE/install"

# shellcheck disable=SC1090
. "$LOCK"

download_verified() {
	url=$1
	sha256=$2
	destination=$3
	if [ ! -f "$destination" ]; then
		partial="$destination.partial"
		curl --fail --location --proto '=https' --tlsv1.2 "$url" --output "$partial"
		actual=$(shasum -a 256 "$partial" | awk '{print $1}')
		if [ "$actual" != "$sha256" ]; then
			echo "[release dependencies] checksum mismatch for $url" >&2
			exit 1
		fi
		mv "$partial" "$destination"
	fi
	actual=$(shasum -a 256 "$destination" | awk '{print $1}')
	if [ "$actual" != "$sha256" ]; then
		echo "[release dependencies] cached checksum mismatch: $destination" >&2
		exit 1
	fi
}

mkdir -p "$ARCHIVES" "$INSTALL"
SPARKLE_ARCHIVE="$ARCHIVES/Sparkle-$SPARKLE_VERSION.tar.xz"
download_verified "$SPARKLE_URL" "$SPARKLE_SHA256" "$SPARKLE_ARCHIVE"
if [ ! -d "$INSTALL/Sparkle/Sparkle.framework" ]; then
	STAGE=$(mktemp -d "${TMPDIR:-/tmp}/hw-calendar-sparkle.XXXXXX")
	trap 'find "$STAGE" -depth -delete' EXIT HUP INT TERM
	tar -xJf "$SPARKLE_ARCHIVE" -C "$STAGE"
	mkdir -p "$INSTALL/Sparkle"
	ditto "$STAGE/Sparkle.framework" "$INSTALL/Sparkle/Sparkle.framework"
	cp "$STAGE/LICENSE" "$INSTALL/Sparkle/LICENSE"
	for tool in generate_appcast generate_keys sign_update; do
		cp "$STAGE/bin/$tool" "$INSTALL/Sparkle/$tool"
		chmod 755 "$INSTALL/Sparkle/$tool"
	done
	find "$STAGE" -depth -delete
	trap - EXIT HUP INT TERM
fi

cp "$LOCK" "$INSTALL/release-dependencies.lock"
printf '[release dependencies] ready: %s\n' "$INSTALL"
