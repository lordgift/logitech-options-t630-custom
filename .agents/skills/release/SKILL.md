---
name: release
description: >-
  Use this skill when the user asks to create a release, bump the version, package/compress the binary or app bundle, tag the git release, or generate release notes for LogiSwipe.
---

# Release Skill

Follow these steps to prepare a new release of **LogiSwipe**: bump the version, build and package the app bundle, compress it for distribution, create a git tag, and write short, easy-to-understand release notes highlighting the main changes.

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

## 3. Commit & Create Git Tag

1. Check `git status -s`. If there are uncommitted changes (such as the version bump in `Support/Info.plist` or release-ready code/docs), stage and commit them before tagging.
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

### Quick Setup
1. Turn off **Logi Options** and its driver extension (**System Settings → General → Login Items & Extensions → Driver Extensions**).
2. Unzip `LogiSwipe-<VERSION>.zip` and move `LogiSwipe.app` to `/Applications` (if blocked by macOS, run `xattr -cr /Applications/LogiSwipe.app` in Terminal).
3. Open **LogiSwipe**, allow **Input Monitoring** and **Accessibility**, then quit and reopen the app.
```

3. Present the generated release notes, the git tag status, and the path to `build/LogiSwipe-<VERSION>.zip` to the user.
