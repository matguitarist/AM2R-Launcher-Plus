# Fix log

## 2026-11-19 Moving the data folder took the database with it

Symptom: after Settings › General › Move… from the default location, the next launch showed no profiles: the database had moved to the new folder with the data, and the app opened a new, empty one in Application Support.
Cause: the database (`AM2RLauncherPlus.store`, `-shm`, `-wal`) and the default data folder are the same folder, `~/Library/Application Support/AM2RLauncherPlus`, and `FolderMove.move` moved the whole folder while the app had the database open. `Store.url` never follows the move. Test runs didn't show it: there the data folder is `<store>-data`, beside the store, not around it.
Fix: `FolderMove.move(_:into:keeping:)` leaves the top-level items named in `keeping`, and `AppModel.moveDataFolder` passes `FolderMove.databaseFiles(store:in:)`. Moving into an existing folder is allowed when none of the moved items is in it, so moving back to the default folder (which still holds the database) works. Settings' size leaves the database out.
Rule: When a folder the player can move also holds something the app keeps elsewhere by a fixed path (the database, a lock, an open log), name those files and leave them behind, and make the test layout match the real one: a test setup that puts them apart hides the bug.

## 2026-11-18 Metroids took no damage from missiles

Symptom: in the native engine, missiles fired at an Alpha Metroid exploded on it but its health never went down, so Metroid fights couldn't be won.
Cause: Butterscotch runs collision events in object order, so the missile's own "hit oMAlpha" event runs first and destroys it. The engine then skipped the destroyed missile, so the Metroid's "hit oMissile" event, which deals the damage, never ran. GameMaker 1.4 keeps a destroyed instance in the collision pass until it ends.
Fix: engine patch 0015: `dispatchCollisionEvents` counts passes and `collidesInThisPass` keeps an instance destroyed during the current pass (GMS 1.x games only). Step 3 of `tools/engine-check.sh` fires a missile into an Alpha Metroid and checks it loses 10 health with one explosion.
Rule: When the engine disagrees with GameMaker 1.4, take the game's own code as the spec: if the game only works one way (here, damage dealt by the second of two collision events), the engine must behave that way, whatever order or cleanup looks cleaner. Check each engine change by playing the mechanic in a scratch copy of the game, not only by the builtin list.
