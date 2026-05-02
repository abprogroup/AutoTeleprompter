# iOS Build Solution for Windows (GitHub Actions)

This plan provides the **best free solution** to build your iPhone app using your current Windows laptop. By using **GitHub Actions**, we can leverage GitHub's cloud-based Mac computers to do the hard work for you.

## User Review Required

> [!IMPORTANT]
> **Authentication Step:** You must perform the "Browser Sign-in" in VS Code after I set this up. I cannot log in to GitHub for you.
> **Signing (IPA):** The build will be a "Release" build but **Not Signed**. You will need to use a tool like **Sideloadly** (Free) on your Windows laptop to install it on your iPhone.

## Proposed Changes

### 🛠️ GitHub Build Pipeline

#### [NEW] [build-ios.yml](file:///c:/Users/AMIT-BAR/AutoTeleprompter/.github/workflows/build-ios.yml)
I will create a "workflow" file. Every time you push code to GitHub:
1. GitHub spins up a Mac in the cloud.
2. It installs Flutter for you.
3. It builds the iOS `.ipa` file.
4. It attaches the file to the "Actions" tab for you to download.

### 🛡️ Local Environment Setup

#### [MODIFY] [README.md](file:///c:/Users/AMIT-BAR/AutoTeleprompter/README.md)
Update the README with instructions on how to use the new build pipeline and where to find the download link.

## Implementation Steps

1. **Verify Git Sync:** Finalize the authentication so you can push your changes.
2. **Setup Workflow:** Create the `.github/workflows/` directory and the `build-ios.yml` file.
3. **Trigger Build:** Commit and push the changes to GitHub.
4. **Verification:** I will monitor the GitHub Actions logs to ensure the build succeeds.

## Open Questions

> [!CAUTION]
> **Do you have a paid Apple Developer account ($99/year)?**
> If **YES**, I can automate the upload to TestFlight.
> If **NO** (which I assume), we will build a "Sideload-ready" app that you can install for free on your own phone using your regular Apple ID.

## Verification Plan

### Automated Tests
- I will check the GitHub repository status to ensure the workflow is detected.

### Manual Verification
- You will go to the **Actions** tab on `https://github.com/abprogroup/AutoTeleprompter`.
- Download the "build-ios" artifact.
- Install it on your iPhone.
