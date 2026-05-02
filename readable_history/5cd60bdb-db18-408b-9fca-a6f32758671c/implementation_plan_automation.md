# Auto-Download and Prepare iOS App

Since I cannot physically control your Sideloadly app or plug in your iPhone, I will build an **Automation System** that handles everything else for you.

## User Review Required

> [!IMPORTANT]
> **One-Time Handshake:** You will need to run one command (`gh auth login`) once to connect your terminal to GitHub. I will provide the exact command.
> **Manual Step (Drag and Drop):** Sideloadly does not have a "command line," so I cannot click the "Start" button for you. I will download the file to your Desktop and open the folder so you just have to drag it and click.

## Proposed Changes

### 🛠️ Automation Tools

#### [NEW] [Automate-iOS.ps1](file:///c:/Users/AMIT-BAR/AutoTeleprompter/Automate-iOS.ps1)
A PowerShell script that:
1. Watches your GitHub repository for the iOS build to finish.
2. Automatically downloads the `.ipa` file to your **Desktop**.
3. Unzips it and opens the folder.
4. Launches **Sideloadly** for you.

## Implementation Steps

1. **Power Up the Terminal:** Use `winget` to install the **GitHub CLI** (`gh`).
2. **Setup Automation:** Create the `Automate-iOS.ps1` script.
3. **One-Time Login:** Ask you to run the login command.
4. **Run Automation:** Execute the script and wait for the "Ding!" when your file is ready on the Desktop.

## Open Questions

> [!CAUTION]
> **Is your iPhone plugged in?**
> The automation will reach the point where Sideloadly is open and the file is in front of you. You just need to make sure the phone is connected via USB.

## Verification Plan

### Automated Tests
- I will verify that the GitHub CLI is installed and running.
- I will test the script's ability to find your project on GitHub.

### Manual Verification
- You will see the folder move to your Desktop and Sideloadly open automatically.
