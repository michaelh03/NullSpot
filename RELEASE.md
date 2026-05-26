# NullSpot Release Process

This document describes how to create and publish a new release of NullSpot.

## Prerequisites

- Xcode installed and working
- **Apple Developer account** (paid, $99/year) configured in Xcode
- GitHub CLI (`gh`) installed and authenticated
- Write access to the `michaelh/homebrew-nullspot` repository

## Release Steps

### 1. Update Version Number

In Xcode:
1. Open the project in Xcode
2. Select the **NullSpot** project in the navigator
3. Select the **NullSpot** target
4. Go to the **General** tab
5. Update the **Version** field (e.g., `1.0`, `1.1`, `2.0`)
6. The **Build** number can stay the same or be incremented

### 2. Commit Your Changes

Make sure all your changes are committed to git:

```bash
git status
git add -A
git commit -m "Prepare for v1.0 release"
```

### 3. Build and Notarize the DMG

```bash
./scripts/create_dmg.sh --notarize
```

This builds `NullSpot` with `xcodebuild`, signs the app with your Developer ID, packages it into a DMG, then submits the DMG to Apple for notarization and staples the ticket. The final artifact lands in `dist/NullSpot-<version>-<build>.dmg`.

Omit `--notarize` for a local-only unsigned DMG.

Requirements:
- `create-dmg` installed (`brew install create-dmg`)
- A valid `Developer ID Application` certificate in your Keychain
- A `notarytool` keychain profile named `notarization-password` (create with `xcrun notarytool store-credentials`)

### 4. Publish the Release

Manually:
1. Create a GitHub Release in `michaelh/nullspot` with the DMG from `dist/`
2. Compute the SHA256: `shasum -a 256 dist/NullSpot-*.dmg`
3. Update the Cask in `../homebrew-nullspot` with the new version, URL, and SHA256
4. Commit and push the tap

### 5. Done!

The release is complete and published. Users can install immediately:

```bash
brew upgrade michaelh/nullspot/nullspot
```

Or for new installations:

```bash
brew install michaelh/nullspot/nullspot
```

## What Gets Released?

- **Archived app**: Optimized for Release (Product → Archive uses Release configuration)
- **Code signing**: Signed with Developer ID Application certificate
- **Notarization**: Notarized by Apple (no Gatekeeper warnings!)
- **Optimizations**: Full compiler optimizations enabled
- **Architecture**: arm64 only (Apple Silicon)
- **ZIP file**: Contains notarized `NullSpot.app` bundle
- **Location**: `michaelh/homebrew-nullspot` releases (NOT the source code repo)

## Replacing an Existing Release

If you need to replace an existing release (e.g., to fix signing issues):

1. Delete the existing release and tag: `gh release delete vX.Y.Z --yes --cleanup-tag --repo michaelh/nullspot`
2. Re-run `./scripts/create_dmg.sh --notarize`
3. Create the GitHub Release again with the freshly notarized DMG

## Verification

The Homebrew formula is automatically updated by the release script. You can verify the release:

```bash
brew upgrade michaelh/nullspot/nullspot
```

Or for new installations:

```bash
brew install michaelh/nullspot/nullspot
```

## Troubleshooting

**`create-dmg: command not found`**
- Install it: `brew install create-dmg`
- Or pass an explicit path: `CREATE_DMG_BIN=/path/to/create-dmg ./scripts/create_dmg.sh`

**`No Developer ID Application certificate found`**
- Install a valid Developer ID Application certificate in your Keychain via Xcode → Settings → Accounts → Manage Certificates
- Or pass it explicitly: `SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/create_dmg.sh --notarize`

**`Keychain profile 'notarization-password' not found`**
- Create it: `xcrun notarytool store-credentials "notarization-password" --apple-id "your@email.com" --team-id "TEAMID"`

**Notarization takes too long**
- Notarization usually takes 2-5 minutes
- The script waits up to 30 minutes; check status at https://developer.apple.com/account if it stalls
- If it fails, the submit log is printed inline — inspect it for details

## Build Configuration Details

### Release Settings

The Release configuration includes:
- **Optimization Level**: `-O` (Optimize for Speed)
- **Whole Module Optimization**: Enabled
- **Architecture**: arm64 only (Apple Silicon)
- **Code Signing**: Automatic with Developer ID
- **Hardened Runtime**: Enabled
- **App Sandbox**: Enabled

### Code Signing and Notarization

The app is:
1. **Signed** with your Developer ID Application certificate
2. **Notarized** by Apple's notary service
3. **Verified** with `spctl` before upload

This ensures users don't see Gatekeeper warnings when opening the app.

### Rust Library Integration

The app links against a Rust library (`libnullspot_rust.a`) that must be:
- Compiled for arm64 architecture
- Located at `build/rust/lib/libnullspot_rust.a`
- Built before creating the Archive

## Notes

- The DMG lands in `dist/` (gitignored — clean up between releases as needed)
- Build output goes to `build/` (gitignored)
- The homebrew tap lives at `../homebrew-nullspot` and is updated manually after publishing the GitHub Release
