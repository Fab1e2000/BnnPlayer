# BananaPlayer v1.0 Packaging

## Build and package

Run from project root:

```bash
bash scripts/package_macos_app.sh 1.0.0 1.0
```

Arguments:

- First argument: `CFBundleVersion` (default `1.0.0`)
- Second argument: `CFBundleShortVersionString` (default `1.0`)

Generated artifacts:

- `dist/BananaPlayer.app`
- `dist/BananaPlayer-<version>-macos.zip`

Packaging now automatically generates a minimal banana icon and embeds it into the app bundle (`Contents/Resources/AppIcon.icns`).

## Optional signing and notarization

For public distribution, sign and notarize before publishing.

Example flow (replace placeholders):

```bash
codesign --deep --force --options runtime --sign "Developer ID Application: YOUR_NAME" dist/BananaPlayer.app
xcrun notarytool submit dist/BananaPlayer-1.0.0-macos.zip --apple-id "APPLE_ID" --team-id "TEAM_ID" --password "APP_SPECIFIC_PASSWORD" --wait
xcrun stapler staple dist/BananaPlayer.app
```
