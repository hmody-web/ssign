# Sign

Flutter iOS app with an on-device native signing bridge.

## What is implemented
- Import and persist IPA / P12 / mobileprovision files.
- Validate P12 password through iOS Security.framework.
- Read IPA metadata.
- Extract IPA with ZIPFoundation.
- Edit Info.plist fields before signing.
- Sign the extracted Payload using zsign-ios (P12 + mobileprovision).
- Repack a new signed IPA into Documents/Signed.
- Export/share signed IPA through iOS share sheet.
- Optional semi-local OTA install: streams the signed IPA from loopback and opens an HTTPS manifest through `itms-services`.

## Native dependencies
The Xcode Runner target includes two Swift Package dependencies:
- https://github.com/zwsn/zsign-ios.git (product: ZSignApple, module: ZSign)
- https://github.com/weichsel/ZIPFoundation.git (product/module: ZIPFoundation)

Run `flutter pub get`, then on macOS open `ios/Runner.xcworkspace` once Xcode resolves packages, or build with your CI.

## iOS install note
Signing/export is fully local. The Install button uses semi-local OTA: the IPA is served from `127.0.0.1`, while the manifest must be trusted HTTPS. The current project uses the public `api.palera.in/genPlist` manifest generator. If that third-party endpoint changes, signing/export still work; only Install needs a replacement HTTPS manifest service.
