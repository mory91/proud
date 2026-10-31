# Design System

`proud.html` is the interactive implementation reference for the Neovim UI. It preserves the compact terminal rhythm and side-by-side review composition from `design.html` while applying the Proud name and commands.

## Tokens

| Token | Value | Use |
| --- | --- | --- |
| Terminal | `#101828` | Main editor surface |
| Panel | `#1D2939` | Tabs, statusline, side panels |
| Border | `#344054` | Dividers and quiet panels |
| Accent | `#7F56D9` | Active tab, selection, focused border |
| Accent text | `#B692F6` | Commands, headings, key references |
| Text | `#EAECF0` | Primary terminal text |
| Muted | `#98A2B3` | Metadata and secondary actions |
| Success | `#DCFAE6` / `#0FAEA0` | Additions, passing checks |
| Danger | `#FEE4E2` / `#F04438` | Deletions and failures |
| Warning | `#F79009` | Unresolved threads and requested changes |

## Typography

- UI and terminal content use `ui-monospace`, `SF Mono`, Menlo, or Consolas at 13px / 20px.
- The outer design browser uses system sans-serif for screen navigation only.
- Review layouts use fixed monospace columns so line numbers, signs, and side-by-side source remain stable.

## Layout

- The logical Neovim viewport is 1440 x 900.
- Tabline height is 28px, statusline height is 24px, and command line height is 22px.
- Large panels use 8px radius and one-pixel borders.
- The browser uses a 640px pull request list beside the preview.
- Review screens use a full-file code pane with inline deletion/addition color and independent file/thread panes.
