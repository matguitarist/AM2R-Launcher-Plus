# Butterscotch patches for AM2R

Applied on Butterscotch ea6b651. `all-current.patch` is the full current diff (apply this one).
The numbered files are per-change views and overlap: 0003 repeats the 0002 appkit hunk, 0004 repeats the 0003 vm_builtins hunk.

- 0001 GUI layer sized to the window when the game draws the app surface itself (AM2R HUD)
- 0002 AppKit: map controller Start/Select (gp_start/gp_select)
- 0003 display_get_width/height from the real screen (1.5 fullscreen scaling)
- 0004 sprite_add, sprite_replace, background_add from image files (1.5 palettes in mods/palettes)
- 0005 display_reset loses all surfaces after the frame, like GMS 1.4 (1.5.5 widescreen surface; 0005 lists runner.c/loop.c, the runner.h + vm_builtins.c parts are in all-current.patch)
