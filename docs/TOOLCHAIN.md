# Toolchain (pinned)

- Godot: 4.6.3 stable (Compatibility renderer), Linux x86_64 headless in CI
- Export templates: 4.6.3.stable (from godotengine/godot-builds)
- JDK: Temurin 17 (docs recommend 17)
- Android SDK: platform-tools 35+, build-tools 35.0.1, platform android-35, cmdline-tools latest
- Release (gradle) only: CMake 3.10.2.4988404, NDK 28.1.13356709
- Source: Godot "Exporting for Android" docs (stable)
- Version lives in `.github/actions/setup-godot/action.yml` (default `godot-version`) and
  `config/features` in `project.godot`; bump both together.

## Workflows
- `test.yml`: PRs run GUT headless (skips if `tests/` or `addons/gut` missing)
- `build-apk.yml`: push to `main`/`v*` tag/manual -> debug APK artifact
  `dust-bones-debug-<short-sha>.apk`; tag `v*` + secrets -> signed release APK + AAB on a GitHub Release
- Debug keystore is generated in CI and cached (stable signature across builds)

## Secrets (release only, never committed)
- `KEYSTORE_BASE64`: base64 of the release keystore
- `KEYSTORE_PASSWORD`: keystore + key password (Godot needs them equal)
- `KEY_ALIAS`: key alias
