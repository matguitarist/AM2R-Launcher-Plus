# Butterscotch patches for AM2R

Applied on Butterscotch ea6b651. `all-current.patch` is the full current diff (apply this one).
The numbered files are per-change views and overlap: 0003 repeats the 0002 appkit hunk, 0004 repeats the 0003 vm_builtins hunk.

- 0001 GUI layer sized to the window when the game draws the app surface itself (AM2R HUD)
- 0002 AppKit: map controller Start/Select (gp_start/gp_select)
- 0003 display_get_width/height from the real screen (1.5 fullscreen scaling)
- 0004 sprite_add, sprite_replace, background_add from image files (1.5 palettes in mods/palettes)
- 0005 display_reset loses all surfaces after the frame, like GMS 1.4 (1.5.5 widescreen surface; 0005 lists runner.c/loop.c, the runner.h + vm_builtins.c parts are in all-current.patch)
- 0006 AppKit: BUTTERSCOTCH_GAMEPAD_KEYS="32778=27" makes a controller button also press a key (AM2R opens its pause menu only from Escape). 0006 is the whole appkit.m diff, so it repeats 0002.
- 0007 AppKit: BUTTERSCOTCH_FILTER=scanlines|crt redraws each finished frame through a GLSL filter (BUTTERSCOTCH_FILTER_LINES = game height, 240), and links OpenGL.framework. 0007 is the whole appkit.m + CMakeLists diff, so it repeats 0002 and 0006.
- 0008 Leaving a persistent room keeps its deactivated instances (GMS does; the runner freed them). AM2R deactivates everything off-screen, and its pause menu is a separate room, so each pause deleted off-screen walls and Samus fell through them.
- 0009 The four engine gaps AM2R hits while playing: gamepad_set_vibration (AppKit: Core Haptics on the controller's left/right handles, or the whole controller, links CoreHaptics.framework), surface_save (PNG through the file system; AM2R's pause backdrop `tempscr`), application_get_position (window rect when the game draws the app surface itself, else the letterbox), os_is_paused (true while the window is in the background). 0009 repeats earlier appkit.m and CMakeLists hunks' context only.
