#!/usr/bin/env bash
# deploy_tablet.sh — Build, deploy, seed, and launch FlowTV on a Fire HD 10 tablet.
#
# Usage:  bash scripts/deploy_tablet.sh
#
# Prerequisites:
#   - Flutter SDK on PATH
#   - ADB at $LOCALAPPDATA/Android/Sdk/platform-tools
#   - Fire HD 10 connected via USB with serial GN434J024192023F
#   - sqlite3 CLI on PATH (ships with Git-for-Windows / MSYS2)

set -euo pipefail

# Prevent MSYS/Git-Bash from mangling /sdcard paths
export MSYS_NO_PATHCONV=1

###############################################################################
# Config
###############################################################################
SERIAL="GN434J024192023F"
ADB="$LOCALAPPDATA/Android/Sdk/platform-tools/adb"
PKG="io.github.tregula501.flowtv"

# DB lives under getApplicationDocumentsDirectory() => /data/data/$PKG/app_flutter/flowtv/flowtv.db
DEVICE_DB_DIR="/data/data/$PKG/app_flutter/flowtv"
DEVICE_DB="$DEVICE_DB_DIR/flowtv.db"

# Playlist to inject
PL_NAME="MyBunny Sports"
PL_URL="https://tv123.me/iptv/890448/REDACTED/sports"
PL_EPG="https://epg.mybunny.tv/ipt/890448/REDACTED/sports"
PL_TYPE="m3u"
BUFFER_SECONDS=3

# Temp directory on host for pulling/pushing the DB
TMPDIR_HOST="$(mktemp -d)"
# Windows-style path for Python (MSYS paths don't work with Python's sqlite3)
TMPDIR_WIN="$(cygpath -w "$TMPDIR_HOST" 2>/dev/null || echo "$TMPDIR_HOST")"
LOCAL_DB="$TMPDIR_HOST/flowtv.db"

adb() { "$ADB" -s "$SERIAL" "$@"; }

cleanup() { rm -rf "$TMPDIR_HOST"; }
trap cleanup EXIT

###############################################################################
# 1. Build debug APK
###############################################################################
echo "==> Building debug APK..."
flutter build apk --debug

APK="build/app/outputs/flutter-apk/app-debug.apk"
if [[ ! -f "$APK" ]]; then
  echo "ERROR: APK not found at $APK" >&2
  exit 1
fi
echo "    APK ready: $APK"

###############################################################################
# 2. Force-stop and uninstall existing app
###############################################################################
echo "==> Force-stopping $PKG..."
adb shell "am force-stop $PKG" || true

echo "==> Uninstalling $PKG..."
adb uninstall "$PKG" 2>/dev/null || true

###############################################################################
# 3. Install fresh APK
###############################################################################
echo "==> Installing APK..."
adb install -r "$APK"
echo "    Installed."

###############################################################################
# 4. Launch app, wait for DB creation, then stop it
###############################################################################
echo "==> Launching app to create database..."
adb shell "am start -n $PKG/.MainActivity"

echo "    Waiting for DB file..."
for i in $(seq 1 30); do
  if adb shell "run-as $PKG test -f app_flutter/flowtv/flowtv.db && echo OK" 2>/dev/null | grep -q OK; then
    echo "    DB exists after ~${i}s."
    break
  fi
  if [[ $i -eq 30 ]]; then
    echo "ERROR: DB not created after 30s." >&2
    exit 1
  fi
  sleep 1
done

# Give the app a moment to finish migration and write default settings
sleep 3

echo "==> Stopping app..."
adb shell "am force-stop $PKG"
sleep 1

###############################################################################
# 5. Pull DB, inject playlist, push DB back
###############################################################################
echo "==> Pulling database via hex encoding..."
# Use xxd hex pipe through run-as — direct cp to /sdcard is denied on Fire tablets.
# Also pull WAL/SHM to get pending transactions.
for dbf in flowtv.db flowtv.db-wal flowtv.db-shm; do
  adb shell "run-as $PKG xxd -p app_flutter/flowtv/$dbf 2>/dev/null" > "$TMPDIR_HOST/${dbf}.hex" || true
done

# Reconstruct DB from hex
python -c "
import os, sys
tmpdir = sys.argv[1]
for f in ['flowtv.db', 'flowtv.db-wal', 'flowtv.db-shm']:
    hex_path = os.path.join(tmpdir, f + '.hex')
    out_path = os.path.join(tmpdir, f)
    try:
        with open(hex_path, 'r') as hf:
            hd = hf.read().replace('\n','').replace('\r','').strip()
        if hd:
            with open(out_path, 'wb') as of: of.write(bytes.fromhex(hd))
    except: pass
" "$TMPDIR_WIN"

echo "==> Injecting playlist into database..."
NOW_EPOCH=$(date +%s)

python -c "
import sqlite3, sys, os
db = os.path.join(sys.argv[1], 'flowtv.db')
conn = sqlite3.connect(db)
c = conn.cursor()
count = c.execute('SELECT count(*) FROM playlists').fetchone()[0]
if count == 0:
    c.execute('''INSERT INTO playlists (name, url, epg_url, type, last_refresh, channel_count, is_active, created_at, sort_order) VALUES (?,?,?,?,?,?,?,?,?)''',
        ('$PL_NAME','$PL_URL','$PL_EPG','$PL_TYPE',None,0,1,int(sys.argv[2]),0))
    print(f'    Inserted playlist: $PL_NAME')
else:
    c.execute('UPDATE playlists SET last_refresh = NULL, channel_count = 0')
    print(f'    Reset {count} playlist(s) for auto-refresh')
c.execute('UPDATE app_settings SET buffer_seconds = $BUFFER_SECONDS WHERE id = 1')
conn.commit(); conn.close()
" "$TMPDIR_WIN" "$NOW_EPOCH"

echo "    channel_count=0, last_refresh=NULL => app will auto-refresh on launch"

echo "==> Pushing database back to device..."
# Convert to hex, push to /sdcard, pipe through run-as xxd -r -p
python -c "
import os, sys
db = os.path.join(sys.argv[1], 'flowtv.db')
hex_path = os.path.join(sys.argv[1], 'push.hex')
with open(db, 'rb') as f: data = f.read()
with open(hex_path, 'w') as f: f.write(data.hex())
print(f'    DB: {len(data)} bytes')
" "$TMPDIR_WIN"

adb push "$TMPDIR_WIN\\push.hex" /sdcard/flowtv_push.hex
adb shell "cat /sdcard/flowtv_push.hex | run-as $PKG sh -c 'xxd -r -p > app_flutter/flowtv/flowtv.db && rm -f app_flutter/flowtv/flowtv.db-wal app_flutter/flowtv/flowtv.db-shm'"
adb shell "rm -f /sdcard/flowtv_push.hex"

###############################################################################
# 6. Launch app — it will auto-refresh the empty playlist and fetch EPG
###############################################################################
echo "==> Launching app (final)..."
adb shell "am start -n $PKG/.MainActivity"

echo ""
echo "=== DEPLOY COMPLETE ==="
echo ""
echo "What happens on launch:"
echo "  1. App detects active playlist with 0 channels => auto-refreshes playlist"
echo "     (downloads & parses the M3U, populates channels table)"
echo "  2. EPG auto-refresh fires (in-memory lastUpdate is null on fresh start)"
echo "     => fetches EPG from $PL_EPG"
echo "  3. Buffer is set to ${BUFFER_SECONDS}s"
echo ""
echo "No touch/intent needed — everything triggers automatically."
