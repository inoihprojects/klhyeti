# Releasing klhyeti

## Version numbers

The version is the `version:` line in `pubspec.yaml`, e.g. `0.1.0+4`:

- `0.1.0` is the version people see. klhyeti follows
  [Semantic Versioning](https://semver.org): while it's below 1.0 the data
  and sync format may still change. Bump the middle number for a batch of
  new features (`0.1.0` → `0.2.0`) and the last number for fixes only
  (`0.1.0` → `0.1.1`). 1.0 means "stable: updates won't break your data."
- `+4` is the build number. Android uses it to tell that an APK is newer
  than the one installed, so it must go up by one on **every** release.

## Publishing a release

1. Change `version:` in `pubspec.yaml`, then commit and push it in GitHub
   Desktop as usual.
2. In GitHub Desktop, choose **Repository** → **Open in Git Bash** (or
   **Open in Command Prompt**).
3. Type these two lines, with `v` plus the version without the build
   number:

   ```
   git tag v0.1.0
   git push origin v0.1.0
   ```

Don't use GitHub Desktop's **Create Tag…**. It makes an *annotated* tag,
which records this computer's timezone; `git tag` with nothing else makes
a plain one that records nothing.

The build then runs as usual and, because of the tag, also creates a
**Release** on the repo's Releases page with the APKs, the Windows zip, the
Linux tarball and a `SHA256SUMS.txt` attached. It refuses to publish if the
tag doesn't match `pubspec.yaml`, or if the signing key isn't set up.

## The Android signing key (one-time setup)

Android only installs an update if it's signed with the same key as the
installed version. Without a permanent key, every build is signed with a
new throwaway key and you'd have to uninstall (losing your events) to
update. Set this up once:

### 1. Create the key

On Arch (`sudo pacman -S jdk-openjdk` first if `keytool` isn't found):

```
keytool -genkeypair -keystore klhyeti-release.jks -storetype PKCS12 \
  -keyalg RSA -keysize 4096 -validity 10000 -alias klhyeti -dname "CN=klhyeti"
```

On Windows, install Java first (`winget install Microsoft.OpenJDK.21` in
PowerShell, then open a new PowerShell window), then run the same command
as one line without the `\`.

It asks for a password. Pick a strong one and write it down.

### 2. Back it up — seriously

Keep `klhyeti-release.jks` and its password somewhere safe and **outside
this repository** (a password manager, an encrypted USB stick). If you lose
it, no future version can ever update an installed klhyeti; everyone would
have to uninstall and reinstall. Never commit it to Git.

### 3. Give it to GitHub

Turn the key file into text:

- Arch: `base64 -w0 klhyeti-release.jks > key.txt`
- Windows PowerShell:
  `[Convert]::ToBase64String([IO.File]::ReadAllBytes("klhyeti-release.jks")) | Set-Content key.txt`

Then on github.com, open the repo → **Settings** → **Secrets and
variables** → **Actions** → **New repository secret**, and add three:

| Name | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | the whole contents of `key.txt` |
| `ANDROID_KEYSTORE_PASSWORD` | the password you chose |
| `ANDROID_KEY_ALIAS` | `klhyeti` |

Delete `key.txt` afterwards. Secrets can't be read back from GitHub, only
used by the build, so the backup from step 2 is your only copy.

From the next push on, the Android job's log shows the key's certificate
fingerprint instead of a "throwaway debug key" warning.
