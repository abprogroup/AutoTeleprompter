# MVP Protocol Root: Total Platform Separation

This directory acts as the central architectural nervous system for the AutoTeleprompter project. It maps out the boundaries, contracts, and strict rules for every feature (MVP) within the application.

## 🛡️ The 4-Way MVP Strategy

To completely eliminate the risk of cross-platform regressions (e.g., a Windows bug fix accidentally breaking iOS), the project embraces **Total Platform Separation**. 

Both the codebase and this documentation are physically decoupled into 4 distinct branches:
- `/Platform_Windows/`
- `/Platform_iOS/`
- `/Platform_Android/`
- `/Platform_macOS/`

### How Documentation is Structured
You will not find a single `stt_mvp.md` file in this root directory. Instead, if an AI agent is working on the Windows Speech-to-Text engine, they MUST navigate into `Platform_Windows/` and read the `stt_mvp.md` document located there. 

This guarantees **Zero Cross-Platform Hallucinations**. The agent will only ever see the rules, files, and constraints relevant to the specific platform they are actively editing.

## 📜 MVP Document Structure

Inside each platform directory, every feature has an MVP document (e.g., `Platform_Windows/auth_mvp.md`). Each document strictly defines:

1. **Owned Files**: A comprehensive list of the files that make up this feature.
   - *Shared Contracts*: Files that are identical across all platforms and dictate the core interface.
   - *Platform Specifics*: Files isolated to this specific platform's implementation.
2. **External API**: The exact methods and fields that other components are allowed to call. If it isn't listed here, it is a private internal function.
3. **All Callers**: A mapping of what external features rely on this MVP.
4. **Invariants**: Absolute logical truths and physics rules of the feature that must NEVER be broken.
5. **Forbidden Changes**: Explicit actions that AI agents and developers are barred from doing to prevent known regressions.
6. **Known Fragilities**: Documented weak points, race conditions, or quirks that require extreme caution.

## ⚖️ Zero-Collateral Damage Mandate

When working within an MVP:
- **Never touch files outside the "Owned Files" list** unless specifically requested by the user. 
- **Respect the boundaries.** If the Script Editor MVP states that it does not interact with STT, you must not inject STT dependencies into the Script Editor.
- **Do not guess shared logic.** If you modify a *Shared Contract* file, you must recognize that your change will eventually affect the other 3 platforms when the logic is ported. Exercise extreme surgical precision.
