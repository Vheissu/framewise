# Editor guide

A condensed version of the built-in help.

## Layout

Menu bar and toolbar across the top (tools on the left; save status, Preview and Export on the right), the layers/scenes/assets panel, the canvas with its document tabs, the properties panel on the right, the timeline below and the status bar at the bottom. Layers carry a label colour that matches their bar in the timeline. Numeric values in the properties panel and timeline header can be dragged sideways to scrub them; Shift steps by ten, and a plain click edits the value as text. Panels resize by dragging their edges; View › Reset Workspace restores the defaults. Layout is remembered per browser, separately from documents.

## Tools

V select, A direct select, P pen, R rectangle, O ellipse, L line, Y polygon, T text, M motion path, H hand, Z zoom. Shift constrains proportions and angles, Alt breaks handle mirroring in direct select. Hold Space over the canvas to pan; Ctrl/Cmd + wheel zooms around the pointer.

Double-click a group to edit inside it. Double-click a path to edit its anchors. Escape backs out of everything in order: dialogs, menus, gestures, tools, isolation, selection.

## Layers

Drag rows to reorder or nest; the drop zone under an expanded group drops inside it. Eye and lock icons toggle visibility and locking. Filter by name or type. The diamond badge marks animated layers.

## Animation

Move the playhead, change a value, and with Auto-Keyframe on a key is recorded. Diamonds next to inspector fields add or remove keys at the playhead without changing the value. K keys every animated property of the selection. Select keys in the timeline to edit their frame, value and easing in the inspector, including a curve editor for Bézier and spring parameters. Comma and period jump between keys.

## Saving

Ctrl/Cmd+S writes a `.framewise` archive. In Chromium browsers it writes back to the file you chose; elsewhere each save is a download. Autosave keeps a copy in the browser every couple of seconds after you stop editing, and the welcome screen offers recovery copies when an autosave is newer than the last file save.
