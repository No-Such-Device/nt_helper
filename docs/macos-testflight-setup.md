# macOS TestFlight Setup Guide

This guide explains how to set up the GitHub Actions workflow to deploy the macOS app to TestFlight.

## Prerequisites

- Apple Developer account with App Store Connect access
- Access to the GitHub repository secrets

## Step 1: Create Certificates

You need two certificates in your `.p12` file (the existing `APPLE_CERTIFICATES` secret):

1. **Apple Distribution** - For signing the app (you may already have this from iOS)
2. **3rd Party Mac Developer Installer** - For signing the `.pkg` installer

### Creating the Installer Certificate

1. Go to [Apple Developer Certificates](https://developer.apple.com/account/resources/certificates/list)
2. Click "+" to create a new certificate
3. Select **"Mac Installer Distribution"** (also called "3rd Party Mac Developer Installer")
4. Follow the CSR instructions
5. Download the certificate and install it in Keychain Access

### Exporting the Combined .p12

1. Open **Keychain Access**
2. Select both certificates:
   - "Apple Distribution: Neal Sanche (KN424RZG26)"
   - "3rd Party Mac Developer Installer: Neal Sanche (KN424RZG26)"
3. Right-click → "Export 2 items..."
4. Save as `.p12` with a password
5. This replaces your existing `APPLE_CERTIFICATES` secret

## Step 2: Create App ID

1. Go to [Identifiers](https://developer.apple.com/account/resources/identifiers/list)
2. Click "+" → "App IDs" → "App"
3. Platform: **macOS**
4. Description: `nt_helper macOS`
5. Bundle ID: `dev.nosuch.ntHelper` (Explicit)
6. Capabilities: Enable only what you need:
   - No special capabilities needed for camera (uses standard AVFoundation)
7. Click "Continue" and "Register"

## Step 3: Create Mac App Store Provisioning Profile

1. Go to [Profiles](https://developer.apple.com/account/resources/profiles/list)
2. Click "+"
3. Select **"Mac App Store Connect"** (under Distribution)
4. Select your macOS App ID (`dev.nosuch.ntHelper`)
5. Select your **Apple Distribution** certificate
6. Name it: `nt_helper Mac App Store`
7. Click "Generate" and download the `.provisionprofile` file

## Step 4: Create App in App Store Connect

Before uploading, you need to create the app in App Store Connect:

1. Go to [App Store Connect](https://appstoreconnect.apple.com/apps)
2. Click "+" → "New App"
3. Platforms: **macOS**
4. Name: `nt_helper` (or your preferred display name)
5. Primary Language: English (or your preference)
6. Bundle ID: Select `dev.nosuch.ntHelper`
7. SKU: `nt_helper_macos` (any unique identifier)
8. User Access: Full Access (or your preference)

## Step 5: Add GitHub Secrets

### New Secret Required

| Secret Name | Description | How to Create |
|-------------|-------------|---------------|
| `MAC_APP_STORE_PROVISIONPROFILE` | Base64-encoded provisioning profile | See below |

### Encoding the Provisioning Profile

```bash
# Encode the provisioning profile to base64
base64 -i ~/Downloads/nt_helper_Mac_App_Store.provisionprofile | pbcopy

# The base64 string is now in your clipboard
```

Then add it to GitHub:
1. Go to your repository → Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Name: `MAC_APP_STORE_PROVISIONPROFILE`
4. Value: Paste the base64 string

### Updating Existing Secret (if needed)

If you created a new combined `.p12` with the installer certificate:

```bash
# Encode the new .p12 file
base64 -i ~/path/to/new_certificates.p12 | pbcopy
```

Update the `APPLE_CERTIFICATES` secret with this new value.

## Step 6: Verify Existing Secrets

These secrets should already exist from iOS deployment:

| Secret | Used For |
|--------|----------|
| `APPLE_CERTIFICATES` | Combined .p12 with distribution + installer certs |
| `APPLE_CERTIFICATES_PASSWORD` | Password for the .p12 file |
| `MACOS_APPLE_ID` | Your Apple ID email |
| `APP_SPECIFIC_PASSWORD` | App-specific password for upload |

## Files Created/Modified

The workflow update created these files:

| File | Purpose |
|------|---------|
| `macos/Runner/AppStore.entitlements` | Sandboxed entitlements for App Store |
| `macos/ExportOptions.plist` | Export options for App Store builds |
| `.github/workflows/tag-build.yml` | Added `macos_testflight` job |

## Running the Build

### Automatic (on tag push)
The macOS TestFlight build runs automatically when the verified version tag is
pushed. Prepare the version on a release branch with `./version`, merge its PR
after CI passes, then verify merged `main` before creating and pushing the exact
tag. Follow [the release procedure](../AGENTS.md#release); the script does not
create tags or bypass branch protection.

### Manual (workflow dispatch)
1. Go to Actions → "Multi-Platform Build"
2. Click "Run workflow"
3. Enter `macos_testflight` in the platforms field (or leave as `all`)

## Troubleshooting

### "No signing identity found"
- Ensure your `.p12` contains both "Apple Distribution" and "3rd Party Mac Developer Installer" certificates
- Verify the certificate names match exactly in the workflow

### "Provisioning profile doesn't match"
- Ensure the bundle ID in the profile matches `dev.nosuch.ntHelper`
- Regenerate the profile if the certificate was recreated

### "App not found in App Store Connect"
- Create the app in App Store Connect before the first upload
- Ensure the bundle ID matches exactly

### Sandbox Issues
The App Store build uses `macos/Runner/AppStore.entitlements` with sandboxing enabled. If you encounter sandbox-related crashes:
1. Test locally with sandbox enabled
2. Ensure all file access uses standard APIs
3. Camera access should work via the `com.apple.security.device.camera` entitlement

## Certificate Identity Names

The workflow uses these exact certificate identity names:
- App signing: `Apple Distribution: Neal Sanche (KN424RZG26)`
- Package signing: `3rd Party Mac Developer Installer: Neal Sanche (KN424RZG26)`

If your certificates have different names, update the workflow accordingly.
