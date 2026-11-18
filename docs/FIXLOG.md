# Fix log

## 2026-11-18 Metroids took no damage from missiles

Symptom: in the native engine, missiles fired at an Alpha Metroid exploded on it but its health never went down, so Metroid fights couldn't be won.
Cause: Butterscotch runs collision events in object order, so the missile's own "hit oMAlpha" event runs first and destroys it. The engine then skipped the destroyed missile, so the Metroid's "hit oMissile" event, which deals the damage, never ran. GameMaker 1.4 keeps a destroyed instance in the collision pass until it ends.
Fix: engine patch 0015: `dispatchCollisionEvents` counts passes and `collidesInThisPass` keeps an instance destroyed during the current pass (GMS 1.x games only). Step 3 of `tools/engine-check.sh` fires a missile into an Alpha Metroid and checks it loses 10 health with one explosion.
Rule: When the engine disagrees with GameMaker 1.4, take the game's own code as the spec: if the game only works one way (here, damage dealt by the second of two collision events), the engine must behave that way, whatever order or cleanup looks cleaner. Check each engine change by playing the mechanic in a scratch copy of the game, not only by the builtin list.
