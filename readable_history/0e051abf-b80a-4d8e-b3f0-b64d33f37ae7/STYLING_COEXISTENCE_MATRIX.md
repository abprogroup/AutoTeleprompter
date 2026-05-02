# Styling Coexistence Matrix & Conflict Resolution (v3.9.5.7)

This matrix defines the "Flawless Logic" for every styling combination possible in the editor.

## 1. Category-Based Conflicts (The "Override" Rules)
Categories represent mutually exclusive styles. Applying a new one MUST clean the existing one.

| Applying \ On Top Of | Color | Font | Size | Align/Dir |
| :--- | :--- | :--- | :--- | :--- |
| **Color** | Replace/Merge | Coexist | Coexist | Coexist |
| **Font** | Coexist | Replace | Coexist | Coexist |
| **Size** | Coexist | Coexist | Replace | Coexist |
| **Align/Dir** | Coexist | Coexist | Coexist | Purge All & Replace |

### Action Logic:
- **Purge All**: For Align/Dir, the entire paragraph block is cleared of alignment tags before the new one is applied.
- **Replace/Merge**: For Color/Font/Size, if the selection is *inside* an existing tag, split the tag. if it *overlaps*, strip the overlap.

## 2. Multi-Style Coexistence (The "Additive" Rules)
Additive styles can stack on top of Categories and each other.

| Style | Bold | Italic | Underline | Color/Font/Size |
| :--- | :--- | :--- | :--- | :--- |
| **Bold** | Toggle | Coexist | Coexist | Nested Inside |
| **Italic** | Coexist | Toggle | Coexist | Nested Inside |
| **Underline** | Coexist | Coexist | Toggle | Nested Inside |

### Action Logic:
- **Nesting**: Additive tags should ideally be **inside** category tags to maintain well-formed XML-like structure.
  - *Good*: `[color=red]**Bold**[/color]`
  - *Bad*: `**[color=red]Bold[/color]**` (Harder to parse for color range).

## 3. Boundary Perfection Logic
When applying style `S1` to text already containing `S1`:
1. **Full Wrap**: If selection is exactly the same as `S1`, Toggle OFF.
2. **Expansion**: If selection is adjacent to `S1` with the same value, Merge.
3. **Fragmentation**: If selection is a sub-range of `S1` with a different value, Split `S1` into three pieces: `[S1_pre][S2_selection][S1_post]`.
