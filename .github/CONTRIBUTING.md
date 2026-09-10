# Contributing to ShotPal

Bug reports, documentation fixes, translations, and focused code improvements are welcome. Use Issues to discuss larger changes before starting. English and Simplified Chinese are welcome in discussions; write commit messages, pull-request descriptions, and release notes in English.

## Submit a change

1. Fork this repository on GitHub.
2. Clone your fork with submodules:

   ```sh
   git clone --recurse-submodules https://github.com/YOUR-USERNAME/ShotPal.git
   cd ShotPal
   git switch Pro1.2
   git switch -c your-change
   ```

3. Make one focused change and follow the project rules in `AGENTS.md`.
4. Run the checks below. Include the results and any untested behavior in your pull request.
5. Push your branch to your fork and open a pull request against **ShotPal:Pro1.2**. The maintainer reviews and merges changes; direct write access is not needed.

## Development setup

App development requires an Apple silicon Mac, macOS 14 or later, and Xcode. The current development environment uses Xcode 26.5. Documentation and the lightweight regression checks do not require Xcode.

The repository includes large runtime binaries. Recognition wheels and the main Whisper transcription model are excluded from Git. For an app build, download the **Complete Developer Package** and `SHA256SUMS.txt` from the repository's Releases page and verify the archive checksum. Extract it outside your checkout, then copy only these two missing resources from the package into the corresponding paths in your checkout:

- `LapianBao/RuntimeTools.bundle/Contents/Resources/Tools/recognition/site-packages/`
- `LapianBao/RuntimeTools.bundle/Contents/Resources/Tools/whisper.cpp/models/ggml-large-v3-turbo-q5_0.bin`

Keep your checkout's source files, manifests, and lockfiles. A package from another version may fail the input checks. As an alternative for recognition dependencies, run `python3 Tools/prepare_recognition_runtime.py` on Apple silicon; this downloads and verifies the pinned wheels and refuses to overwrite an existing installation. Do not commit generated runtime dependencies or model files.

Before building, validate the prepared runtime:

```sh
python3 Tools/check_download_bundle_inputs.py
python3 Tools/check_recognition_bundle_inputs.py
```

Open `LapianBao.xcodeproj` and use the `LapianBao` scheme. For a local development build without the maintainer's signing identity:

```sh
xcodebuild -project LapianBao.xcodeproj -scheme LapianBao \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath .codex-derived/contributor \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build
```

This is a local development build. Distribution signing, notarization, and release publication are handled by the maintainer. Do not include signing certificates, credentials, browser cookies, or private media in contributions.

## Validate your change

For every change:

```sh
python3 Tools/regression_checks.py
git diff --check
```

For Swift changes, also build the app and describe the behavior you tested on your Mac. For localization changes, run `python3 Tools/check_localizations.py` and test both interface languages. For startup or window changes, also run `Tools/check_launch_window.sh`. Follow any additional checks required by `AGENTS.md` for the area you modify.

The pull-request workflow runs lightweight source regression checks. It does not replace a Mac build or manual app testing. First-time external contributions may require the maintainer to approve the workflow run.

## Reporting issues

Use the bug-report form with the app version, macOS version, reproduction steps, expected behavior, and actual behavior. Use the feature-request form for proposed improvements. Share small media samples only when you have permission to share them.

## Third-party components

Preserve dependency licenses and notices. The project includes third-party tools and models with their own license terms; the project's license does not replace those terms. Film footage, music, trademarks, and other third-party demonstration content are not granted under the source-code license.
