# Master TODO List: AutoTeleprompter v3.5.3 Hardened

## 🛠️ UI & UX Fixes
- [x] **v3.5.x Hardening**: Implement Persistence Guard, Surgical Mirrors, Task Timer, and /logit Protocol.
- [x] **Recent Activity Bug**: Script appears twice after opening. (STILL REPRODUCING - REQUIRES DEEP FIX)
- [x] **URGENT: Live State Sync**: "Complete History" list must update immediately after delete/save. (FIXED in v3.5.1)
- [x] **BUG: Recent Activity Timer**: 500ms timer only works if file is *changed*; should activate 500ms after *open*. (FIXED in v3.5.3)
- [ ] **BUG: Style Regression**: Text alignment and paragraph spacing ignored in the script prompting screen.
- [ ] **URGENT: Emulator Hardware Bridge**: Restore Mac Keyboard/Camera/Mic access for testing.
- [ ] **Recent Scripts Delete**: Delete button only works after toggle "Show More".
- [ ] **Undo/Redo**: Implement for background colors.
- [ ] **Color Picker Reopen**: Picker must show active color when reopened.
- [ ] **Toolbar "C" Button**: Move to main toolbar (left of TEXT) -> Clear all styles/colors/align.
- [ ] **Splash Screen**: Remove "V3" text under logo.
- [ ] **Style Exposure Bug**: Selecting text exposes raw RTF/style codes.

## 📂 File Picker (picker_test)
- [-] **Faded Files**: Grey out/disable unsupported files.
- [+] **Security Fix**: Remove "last used folder" memory (Android requirement).
- [+] **Selection Fix**: Tapping supported file does nothing -> Fix selection.
- [-] **Instant Warning**: Popup for unsupported files WITHOUT closing picker.

## 📄 Parser & Encoding Bugs
- [ ] **Stray "0"**: Fix \uc0 parsing bug.
- [ ] **"none" Text**: Fix \ulnone parsing bug.
- [ ] **Hebrew hex escapes**: Fix Windows-1252 mapping (\'96 -> en-dash).
- [ ] **DOCX Logic**: Verify and restore genuine .docx file loading.

---
*Last Updated: 2026-04-07 (v3.5.3 Deployment)*
