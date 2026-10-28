---
name: release
description: >-
  Use this skill when the user asks to create a release, bump the version, package/compress the binary or app bundle, tag the git release, generate release notes, or publish a GitHub release for LogiSwipe.
---

# Release Skill

Follow these steps to prepare a new release of **LogiSwipe**: bump the version, build and package the app bundle, compress it for distribution, create a git tag, write short, easy-to-understand release notes highlighting the main changes, and publish it as a GitHub release.

## 1. Determine the Target Version

1. Read `Support/Info.plist` to check the current `CFBundleShortVersionString` (e.g., `2.0`) and `CFBundleVersion` (e.g., `1`).
2. Check existing git tags (`git tag -l`) to see the last released version.
3. If the user specified a target version (e.g., `2.0` or `2.1`), use that. Reset `CFBundleVersion` to `1` for a new version (or increment it if rebuilding the same version).

## 2. Bump Version & Build Release Archive

Run the release build script [release.sh](./scripts/release.sh) with the target version:

```sh
./.agents/skills/release/scripts/release.sh <VERSION>
```

What this script does:
1. Updates `CFBundleShortVersionString` and `CFBundleVersion` in `Support/Info.plist`.
2. Runs `swift build -c release`.
3. Assembles `build/LogiSwipe.app` (`Contents/MacOS/LogiSwipe` and `Contents/Info.plist`).
4. Signs `build/LogiSwipe.app` with `SIGN_IDENTITY`, defaulting to the "LogiSwipe Self-Signed" keychain identity when present (so users keep their permissions across updates), else ad-hoc `-`. Never sign with the company team `D82BAQ85JN`.
5. Compresses `build/LogiSwipe.app` into `build/LogiSwipe-<VERSION>.zip` using `ditto -c -k --keepParent` (preserves macOS bundle metadata and code signature).

Verify that `build/LogiSwipe-<VERSION>.zip` exists and check its size.

## 2b. Update the README Screenshot

`docs/settings.png` is the settings panel shown in the README. Refresh it with Orca's computer use so it shows the new version and settings:

1. Install and relaunch the new build, so the panel shows `<VERSION>`:
   ```sh
   ./build.sh && pkill -x LogiSwipe; sleep 1; open /Applications/LogiSwipe.app
   ```
2. Orca can't click the menu bar icon, so tell the user to click the LogiSwipe icon in the menu bar and leave the panel open. Then, in the same turn, wait up to 5 s for the panel and copy Orca's screenshot of it:
   ```sh
   pid=$(pgrep -x LogiSwipe)
   for i in 1 2 3 4 5; do
     shot=$(orca computer get-app-state --app pid:$pid --json 2>/dev/null \
       | python3 -c 'import json, sys; r = json.load(sys.stdin).get("result") or {}; print((r.get("screenshot") or {}).get("path", ""))')
     [ -n "$shot" ] && cp "$shot" docs/settings.png && echo "wrote docs/settings.png" && break
     sleep 1
   done
   ```
   Until the panel opens, `get-app-state` fails with `window_not_found`. If nothing was written, ask the user to open the panel again and rerun it.
3. Look at `docs/settings.png` to check it shows the whole panel with the new version, then commit it with the version bump in step 3.

## 3. Commit & Create Git Tag

1. Check `git status -s`. If there are uncommitted changes (such as the version bump in `Support/Info.plist`, `docs/settings.png`, or release-ready code/docs), stage and commit them before tagging.
2. Create an annotated git tag for `<VERSION>`:
   ```sh
   git tag -a <VERSION> -m "Release <VERSION>"
   ```
   (If the tag already exists and is being updated prior to pushing, use `git tag -f -a <VERSION> -m "Release <VERSION>"`.)

## 4. Generate Short, Easy-to-Read Release Notes

1. Inspect commits since the previous tag:
   ```sh
   git log <PREV_TAG>..HEAD --oneline
   ```
   (If no previous tag exists, inspect `git log --oneline`).
2. Create `build/RELEASE_NOTES-<VERSION>.md`. Keep it **short, simple, and easy for anyone to understand at a glance**—focus only on the major highlights that matter to users, with no technical jargon or commit hashes:

```markdown
## LogiSwipe <VERSION>

<1 short sentence summarizing the release.>

### Highlights
- **<Big Feature 1>**: <Short, simple 1-line explanation>
- **<Big Feature 2>**: <Short, simple 1-line explanation>
```

Don't add a setup or installation section; the README covers that.

## 5. Push & Publish the GitHub Release

1. Check that the GitHub CLI is installed and logged in:
   ```sh
   gh auth status
   ```
   If `gh` is missing, install it with `brew install gh`. If it is not logged in, ask the user to run `! gh auth login` themselves (it needs a browser) and wait for them before continuing.
2. Push `main` and the tag (commit straight to `main`; this repo doesn't use feature branches):
   ```sh
   git push origin main <VERSION>
   ```
3. Create the release with the zip attached and the release notes as its body:
   ```sh
   gh release create <VERSION> build/LogiSwipe-<VERSION>.zip --title "LogiSwipe <VERSION>" --notes-file build/RELEASE_NOTES-<VERSION>.md --verify-tag
   ```
   If the release already exists (rebuilding the same version), replace the zip and notes instead:
   ```sh
   gh release upload <VERSION> build/LogiSwipe-<VERSION>.zip --clobber
   gh release edit <VERSION> --title "LogiSwipe <VERSION>" --notes-file build/RELEASE_NOTES-<VERSION>.md
   ```
4. Confirm it is the latest release and the zip is attached:
   ```sh
   gh release list -L 3
   gh release view <VERSION> --json assets -q '.assets[].name'
   ```
5. Present the release URL, the release notes, and the path to `build/LogiSwipe-<VERSION>.zip` to the user.
