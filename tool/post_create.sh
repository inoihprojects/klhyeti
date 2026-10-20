#!/usr/bin/env bash
# Run straight after `flutter create` (which regenerates the platform
# folders and therefore undoes these each time).
#
#  - sets the user-visible app name to "Klhyeti" rather than "klhyeti"
#  - drops the sample test flutter create adds, which refers to a MyApp
#    class this project doesn't have
#  - asks Android for the INTERNET permission. Pairing and direct sync
#    open connections on the local network, and Android has no narrower
#    permission for that. The app itself refuses any address that isn't a
#    private one (lib/sync/lan_address.dart).
#
# The naming edits are best-effort: if a future Flutter version words
# these files differently, the build still succeeds with the default
# name. The permission is not: without it the Android app could not pair,
# so failing to add it stops the build.
set -u

rm -f test/widget_test.dart

android_manifest=android/app/src/main/AndroidManifest.xml
if [ -f "$android_manifest" ]; then
  sed -i.bak 's/android:label="klhyeti"/android:label="Klhyeti"/' \
    "$android_manifest" && rm -f "$android_manifest.bak"
  if ! grep -q 'android.permission.INTERNET' "$android_manifest"; then
    sed -i.bak 's|^\( *\)<application|\1<uses-permission android:name="android.permission.INTERNET" />\n\1<application|' \
      "$android_manifest" && rm -f "$android_manifest.bak"
  fi
  if ! grep -q 'android.permission.INTERNET' "$android_manifest"; then
    echo "post_create: could not add the INTERNET permission to $android_manifest" >&2
    exit 1
  fi
fi

windows_main=windows/runner/main.cpp
if [ -f "$windows_main" ]; then
  sed -i.bak 's/L"klhyeti"/L"Klhyeti"/' "$windows_main" \
    && rm -f "$windows_main.bak"
fi

linux_app=linux/runner/my_application.cc
if [ -f "$linux_app" ]; then
  sed -i.bak 's/"klhyeti"/"Klhyeti"/g' "$linux_app" \
    && rm -f "$linux_app.bak"
fi

echo "post_create: app name set to Klhyeti, local network permission added"
