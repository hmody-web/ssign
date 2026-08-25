# Third-party components

Sign is designed to resolve these packages through Swift Package Manager at build time:

- zsign-ios / zsign signing engine — MIT-licensed upstream project.
- ZIPFoundation — MIT-licensed ZIP library.

Review and preserve the upstream license files when distributing a compiled build.

The optional semi-local OTA installer uses the public HTTPS manifest generator documented by ForgeSign (`https://api.palera.in/genPlist`) while the IPA itself is streamed from `127.0.0.1`. This external endpoint is not part of Sign and may change or become unavailable; signing/export does not depend on it.
