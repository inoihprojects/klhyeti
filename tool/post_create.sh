#!/usr/bin/env bash
# Run straight after `flutter create` (which regenerates the platform
# folders and therefore undoes these each time).
#
#  - sets the user-visible app name to $APP_NAME, or "Klhyeti" if unset,
#    rather than "klhyeti"
#  - drops the sample test flutter create adds, which refers to a MyApp
#    class this project doesn't have
#  - asks Android for the INTERNET permission. Pairing and direct sync
#    open connections on the local network, and Android has no narrower
#    permission for that. The app itself refuses any address that isn't a
#    private one (lib/sync/lan_address.dart).
#  - sets Android up for reminders (lib/data/reminders.dart): permission
#    to restore them after a restart and to deliver them on the minute,
#    the receivers that do both, the status-bar icon, and the library
#    desugaring the notification plugin needs on older Android.
#
# The naming edits are best-effort: if a future Flutter version words
# these files differently, the build still succeeds with the default
# name. The Android setup is not: without it the app could not pair or
# remind, so failing to apply it stops the build.
set -u

name="${APP_NAME:-Klhyeti}"

rm -f test/widget_test.dart

android_manifest=android/app/src/main/AndroidManifest.xml
if [ -f "$android_manifest" ]; then
  sed -i.bak "s/android:label=\"klhyeti\"/android:label=\"$name\"/" \
    "$android_manifest" && rm -f "$android_manifest.bak"
  if ! grep -q 'android.permission.INTERNET' "$android_manifest"; then
    sed -i.bak 's|^\( *\)<application|\1<uses-permission android:name="android.permission.INTERNET" />\n\1<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />\n\1<uses-permission android:name="android.permission.USE_EXACT_ALARM" />\n\1<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" android:maxSdkVersion="32" />\n\1<application|' \
      "$android_manifest" && rm -f "$android_manifest.bak"
  fi
  if ! grep -q 'ScheduledNotificationReceiver' "$android_manifest"; then
    sed -i.bak 's|^\( *\)</application>|\1    <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />\n\1    <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">\n\1        <intent-filter>\n\1            <action android:name="android.intent.action.BOOT_COMPLETED" />\n\1            <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />\n\1            <action android:name="android.intent.action.QUICKBOOT_POWERON" />\n\1            <action android:name="com.htc.intent.action.QUICKBOOT_POWERON" />\n\1        </intent-filter>\n\1    </receiver>\n\1</application>|' \
      "$android_manifest" && rm -f "$android_manifest.bak"
  fi
  for needed in android.permission.INTERNET RECEIVE_BOOT_COMPLETED \
      USE_EXACT_ALARM ScheduledNotificationReceiver \
      ScheduledNotificationBootReceiver; do
    if ! grep -q "$needed" "$android_manifest"; then
      echo "post_create: could not add $needed to $android_manifest" >&2
      exit 1
    fi
  done

  # The reminders' status-bar icon. Only Dart code names it, so it is
  # also marked to be kept when a release build drops unused resources.
  res=android/app/src/main/res
  mkdir -p "$res/drawable" "$res/raw"
  cp assets/icon/icon_notification.png "$res/drawable/ic_notification.png"
  printf '%s\n' '<?xml version="1.0" encoding="utf-8"?>' \
    '<resources xmlns:tools="http://schemas.android.com/tools" tools:keep="@drawable/ic_notification" />' \
    > "$res/raw/keep.xml"

  app_gradle=android/app/build.gradle.kts
  if [ -f "$app_gradle" ] && ! grep -q 'isCoreLibraryDesugaringEnabled' "$app_gradle"; then
    sed -i.bak 's|^\( *\)compileOptions {|\1compileOptions {\n\1    isCoreLibraryDesugaringEnabled = true|' \
      "$app_gradle" && rm -f "$app_gradle.bak"
    printf '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n' \
      >> "$app_gradle"
  fi
  if ! grep -q 'isCoreLibraryDesugaringEnabled = true' "$app_gradle" 2>/dev/null; then
    echo "post_create: could not enable desugaring in $app_gradle" >&2
    exit 1
  fi
fi

windows_main=windows/runner/main.cpp
if [ -f "$windows_main" ]; then
  sed -i.bak "s/L\"klhyeti\"/L\"$name\"/" "$windows_main" \
    && rm -f "$windows_main.bak"
fi

linux_app=linux/runner/my_application.cc
if [ -f "$linux_app" ]; then
  sed -i.bak "s/\"klhyeti\"/\"$name\"/g" "$linux_app" \
    && rm -f "$linux_app.bak"
fi

echo "post_create: app name set to $name, Android set up for sync and reminders"
