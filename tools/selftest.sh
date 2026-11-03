#!/bin/zsh
# Runs the in-app self-test against a fresh store in /tmp. Exit code 0 when every check passed.
set -u
rm -rf ~/Library/Saved\ Application\ State/com.mathieu.am2rlauncherplus.savedState
store=/tmp/AM2RLauncherPlus-self.store
rm -f $store $store-shm $store-wal
rm -rf /tmp/AM2RLauncherPlus-self-data
APP_STORE=$store ~/Applications/AM2RLauncherPlus.app/Contents/MacOS/AM2RLauncherPlus --selftest
