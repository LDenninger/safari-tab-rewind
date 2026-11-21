# Releasing TabRewind

GitHub Actions builds and checks a universal macOS app on pull requests and pushes to main. Each run has a ZIP and SHA-256 checksum in its workflow artifacts. Pushing a version tag publishes those files to GitHub Releases. Public releases also include GitHub build provenance.

1. Update `CFBundleShortVersionString` and increment `CFBundleVersion` in `Info.plist`.
2. Merge the change into main and check that the macOS build passes.
3. Tag that commit with the version in `Info.plist` and push the tag. For example:

   ```sh
   git tag -a v0.4.0 -m "TabRewind 0.4.0"
   git push origin v0.4.0
   ```

The release job checks that the tag matches the version, the ZIP contains both architectures, the app's code signature validates, and the ZIP matches its checksum.

## Apple signing and notarization

With no Apple credentials, tagged builds use an ad hoc signature. For Gatekeeper-compatible distribution, configure these GitHub Actions repository secrets before tagging:

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE_P12_BASE64` | Base64-encoded PKCS#12 export of a Developer ID Application certificate and its private key |
| `MACOS_CERTIFICATE_PASSWORD` | Password for the PKCS#12 export |
| `APPLE_NOTARY_KEY_P8_BASE64` | Base64-encoded App Store Connect team API key |
| `APPLE_NOTARY_KEY_ID` | API key ID |
| `APPLE_NOTARY_ISSUER_ID` | App Store Connect API issuer ID |

The workflow imports the signing identity into a temporary keychain, submits the build to Apple, and staples the notarization ticket before packaging. A partial configuration or failed notarization stops the release. [Apple's notarization guide](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

## Verify a public download

```sh
shasum -a 256 -c TabRewind-v0.4.0-macos-universal.zip.sha256
gh attestation verify TabRewind-v0.4.0-macos-universal.zip --repo LDenninger/safari-tab-rewind
```
