## Releasing (notarized)

CopyCopy releases should be **Developer ID signed**, **notarized**, and **stapled**, so users don’t see the Gatekeeper warning (“Apple could not verify…”).

### Local release (manual)

1) Build the app bundle:

```bash
./build.sh
```

2) Notarize + staple (requires a Developer ID Application cert in your keychain):

```bash
export APP_IDENTITY='Developer ID Application: Your Name (TEAMID)'
./scripts/sign_and_notarize.sh
```

3) Package the stapled app for distribution:

```bash
TAG="v$(source ./version.env && echo "$VERSION")"
ASSET="CopyCopy-${TAG}-macos.zip"
ditto --norsrc -c -k --keepParent "dist/CopyCopy.app" "$ASSET"
shasum -a 256 "$ASSET" > "$ASSET.sha256"
```

### Notarization credentials

`scripts/sign_and_notarize.sh` supports either:

- **Keychain profile** (simplest locally):
  - Create once:
    - `xcrun notarytool store-credentials "copycopy-notary" --apple-id "<AppleID>" --team-id "<TEAMID>" --password "<app-specific-password>"`
  - Use:
    - `export NOTARYTOOL_KEYCHAIN_PROFILE="copycopy-notary"`

- **App Store Connect API key** (best for CI):
  - `APP_STORE_CONNECT_API_KEY_P8` (contents of the `.p8`, `\n` escaped is OK)
  - `APP_STORE_CONNECT_KEY_ID`
  - `APP_STORE_CONNECT_ISSUER_ID`

### GitHub Actions (Release workflow)

To produce notarized release assets on `release.published`, set these repository secrets:

- `APP_IDENTITY`: `Developer ID Application: … (TEAMID)`
- `MACOS_CERT_P12_BASE64`: base64 of your exported Developer ID `.p12`
- `MACOS_CERT_PASSWORD`: password for the `.p12`
- `HOMEBREW_TAP_TOKEN`: GitHub token with write access to `mpuig/homebrew-copycopy`
- Notarization (pick one approach):
  - `NOTARYTOOL_KEYCHAIN_PROFILE` (if you set up a profile in CI), or
  - `APP_STORE_CONNECT_API_KEY_P8`, `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`

### Homebrew cask

On `release.published`, `.github/workflows/release.yml` uploads the macOS zip asset and then updates `mpuig/homebrew-copycopy` by bumping `Casks/copycopy.rb` to the release version and SHA-256 checksum. The release tag should use the `vX.Y.Z` format because the cask stores `X.Y.Z` and downloads `CopyCopy-vX.Y.Z-macos.zip`.
