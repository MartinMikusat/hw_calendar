#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
LABEL=com.halwayland.hw-calendar.dependencies
DOMAIN="gui/$(id -u)"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/Hal Wayland/hw_calendar"
LOG_FILE="$LOG_DIR/dependency-update.log"

xml_escape() {
  printf '%s' "$1" | sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g' \
    -e 's/"/\&quot;/g'
}

install_schedule() {
  backup=
  mkdir -p "$(dirname "$PLIST")" "$LOG_DIR"
  escaped_script=$(xml_escape "$ROOT/scripts/dependency-update.sh")
  escaped_root=$(xml_escape "$ROOT")
  escaped_log=$(xml_escape "$LOG_FILE")
  temporary="$PLIST.tmp.$$"
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    printf '%s\n' '<plist version="1.0">' '<dict>'
    printf '%s\n' '  <key>Label</key>' "  <string>$LABEL</string>"
    printf '%s\n' '  <key>ProgramArguments</key>' '<array>'
    printf '%s\n' '    <string>/bin/sh</string>' "    <string>$escaped_script</string>" '</array>'
    printf '%s\n' '  <key>WorkingDirectory</key>' "  <string>$escaped_root</string>"
    printf '%s\n' '  <key>EnvironmentVariables</key>' '<dict>'
    printf '%s\n' '    <key>PATH</key>' '    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>' '</dict>'
    printf '%s\n' '  <key>StartCalendarInterval</key>' '<dict>'
    printf '%s\n' '    <key>Hour</key>' '    <integer>6</integer>'
    printf '%s\n' '    <key>Minute</key>' '    <integer>0</integer>' '</dict>'
    printf '%s\n' '  <key>ProcessType</key>' '  <string>Background</string>'
    printf '%s\n' '  <key>LowPriorityIO</key>' '  <true/>'
    printf '%s\n' '  <key>StandardOutPath</key>' "  <string>$escaped_log</string>"
    printf '%s\n' '  <key>StandardErrorPath</key>' "  <string>$escaped_log</string>"
    printf '%s\n' '</dict>' '</plist>'
  } > "$temporary"
  plutil -lint "$temporary" >/dev/null
  if [ -f "$PLIST" ]; then
    backup="$PLIST.backup.$$"
    cp "$PLIST" "$backup"
  fi
  launchctl bootout "$DOMAIN" "$PLIST" >/dev/null 2>&1 || true
  mv "$temporary" "$PLIST"
  if ! launchctl bootstrap "$DOMAIN" "$PLIST"; then
    rm -f "$PLIST"
    if [ -n "$backup" ]; then
      mv "$backup" "$PLIST"
      launchctl bootstrap "$DOMAIN" "$PLIST" >/dev/null 2>&1 || true
    fi
    printf '[hw_calendar] could not install dependency update schedule\n' >&2
    return 1
  fi
  if [ -n "$backup" ]; then
    rm -f "$backup"
  fi
  printf '[hw_calendar] installed daily dependency update at 06:00: %s\n' "$PLIST"
}

uninstall_schedule() {
  launchctl bootout "$DOMAIN" "$PLIST" >/dev/null 2>&1 || true
  if [ -f "$PLIST" ]; then
    rm "$PLIST"
  fi
  printf '[hw_calendar] removed dependency update schedule: %s\n' "$PLIST"
}

status_schedule() {
  if launchctl print "$DOMAIN/$LABEL"; then
    printf '[hw_calendar] dependency update schedule is loaded\n'
  else
    printf '[hw_calendar] dependency update schedule is not loaded\n'
    exit 1
  fi
}

case "${1:-status}" in
  install) install_schedule ;;
  uninstall) uninstall_schedule ;;
  status) status_schedule ;;
  *)
    echo 'usage: ./scripts/dependency-schedule.sh [install|uninstall|status]' >&2
    exit 2
    ;;
esac
