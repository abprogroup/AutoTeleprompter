# Master TODO List: AutoTeleprompter v3

## 🛠️ UI & UX Fixes
- [x] **Recent Activity Bug**: Script appears twice after opening. (STILL REPRODUCING - REQUIRES DEEP FIX)
- [ ] **URGENT: Emulator Hardware Bridge**: Restore Mac Keyboard/Camera/Mic access for testing.
- [ ] **URGENT: Live State Sync**: "Complete History" list must update immediately after delete/save.
- [ ] **Recent Scripts Delete**: Delete button only works after toggle "Show More".
- [ ] **Undo/Redo**: Implement for background colors.
- [ ] **Color Picker Reopen**: Picker must show active color when reopened.
- [ ] **Toolbar "C" Button**: Move to main toolbar (left of TEXT) -> Clear all styles/colors/align.
- [ ] **Splash Screen**: Remove "V3" text under logo.
- [ ] **Style Exposure Bug**: Selecting text exposes raw RTF/style codes.

## 📂 File Picker (picker_test)
- [-] **Faded Files**: Grey out/disable unsupported files - Cant be acheived without a dedicated file picker mvp so I gave up on that.
- [+] **Security Fix**: Remove "last used folder" memory (Android security requirement).
- [+] **Selection Fix**: Tapping supported file does nothing -> Fix selection.
- [-] **Instant Warning**: Popup for unsupported files WITHOUT closing picker - Cant be acheived without a dedicated file picker mvp so I gave up on that.

## 📄 Parser & Encoding Bugs
- [ ] **Stray "0"**: Fix \uc0 parsing bug.
- [ ] **"none" Text**: Fix \ulnone parsing bug.
- [ ] **Hebrew hex escapes**: Fix Windows-1252 mapping (\'96 -> en-dash).
- [ ] **DOCX Logic**: Verify and restore genuine .docx file loading.

---
*Last Updated: 2026-04-06*
