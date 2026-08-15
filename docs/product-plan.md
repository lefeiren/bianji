# 边记 Product Plan

## Goal

Build a native macOS screen annotation tool for fast desktop marking during demos, meetings, teaching, screen recordings, and debugging.

## Competitor Notes

Similar tools usually provide:

- full-screen transparent annotation overlay
- floating toolbar or menu bar control
- pen, highlighter, line, arrow, rectangle, oval, and text tools
- color picker and stroke width
- undo, clear, and keyboard shortcuts
- auto-fade / auto-erase annotations
- cursor highlight and click effects
- spotlight / zoom focus
- whiteboard mode
- screenshot export with annotations
- works during Zoom, Meet, Keynote, PowerPoint, OBS, and screen sharing

Examples reviewed:

- Presentify
- DemoPro
- Scribbble
- DrawPen
- Screen Annotations
- Annotate open-source macOS project
- annotation-overlay open-source project

## V1 Scope

Implemented:

- native macOS AppKit app
- transparent full-screen overlay across all detected screens
- macOS menu bar controls
- Chinese UI
- macOS menu bar status item
- custom macOS app icon
- launches in idle mode and only starts drawing after a tool is selected
- overlay is mouse-through while idle
- low-level mouse event tap was removed after stability issues
- current safe build uses normal AppKit overlay mouse capture
- overlay uses the visible screen frame so the macOS menu bar remains clickable
- pen, line, arrow, rectangle, and oval tools
- preset colors and system color picker
- stroke width picker
- custom pen cursor while annotation mode is active
- undo
- clear
- pause drawing
- Esc to pause drawing
- Cmd+Z to undo
- Cmd+K to clear annotations
- right-click to clear annotations while annotation mode is active
- [ and ] to decrease/increase stroke width
- number shortcuts 1-5 for tool selection

## V2 Candidates

Highest value next:

1. Text tool
2. Toggle annotation mode so clicks can pass through to underlying apps
3. Global hotkey to show/hide overlay
4. Screenshot export with annotations
5. Auto-fade drawings after a configurable duration
6. Cursor highlight and click pulse

Later:

1. Whiteboard mode
2. Spotlight / dim-background focus tool
3. Zoom lens
4. Preset color palette
5. Save/load annotation sessions
6. Packaged `.app` with icon

## Technical Direction

Use native Swift + AppKit.

Reasoning:

- transparent overlay windows are first-class on macOS
- lower latency than Electron
- better control over multi-screen windows, event handling, and global hotkeys
- easier future path to a signed `.app`

Current run command:

```bash
swift run ScreenMarker
```
