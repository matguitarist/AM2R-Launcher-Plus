// Metroid fight check (patch 0015). Injected into oCharacter's Draw GUI event of a scratch copy of
// the game by tools/engine-check.sh, then played with play.json; never shipped. Once Samus is in the
// game it puts an Alpha Metroid next to her and fires a missile into it. The missile's own event
// destroys it before the Metroid's event runs; GameMaker 1.4 still hands it to the Metroid, which
// takes the damage. Prints CHECK PASS or CHECK FAIL with its name; the script counts them.
if (!variable_global_exists("ec_t")) global.ec_t = 0;
global.ec_t += 1;
if (global.ec_t == 20) {
    global.ec_a = instance_create(x, y - 20, oMAlpha);
    global.ec_a.myhealth = 100; global.ec_a.starthealth = 100; global.ec_a.givebackhp = 0;
    global.ec_a.myid = 0; global.ec_a.fallondeath = 0;
}
if (global.ec_t == 30) {
    var m;
    m = instance_create(global.ec_a.x - 40, global.ec_a.y + 6, oMissile);
    m.direction = 0; m.speed = 6.4; m.smissile = 0; m.sprite_index = sMissile; m.damage = 20; m.alarm[0] = 1;
    with (m) { trail = instance_create(x, y, oMissileTrail); trail.direction = 0; trail.smissile = 0; trail.fadein_speed = 0.04; }
}
if (global.ec_t == 31) global.ec_expl = 0;
if (global.ec_t > 31 && global.ec_t < 50) global.ec_expl = max(global.ec_expl, instance_number(oMissileExpl));
if (global.ec_t == 50) {
    show_debug_message("CHECK " + (global.ec_a.myhealth == 90 ? "PASS" : "FAIL") + " a missile hurts an Alpha Metroid: health " + string(global.ec_a.myhealth));
    show_debug_message("CHECK " + (global.ec_expl == 1 ? "PASS" : "FAIL") + " the missile explodes once: " + string(global.ec_expl));
    show_debug_message("CHECK " + (instance_number(oMissile) == 0 ? "PASS" : "FAIL") + " the missile is gone");
}
