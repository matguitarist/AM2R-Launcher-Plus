// Engine checks for the builtins AM2R calls (patch 0013 and later). Injected into initroom's
// creation code of a scratch copy of the game by tools/engine-check.sh; never shipped.
// Each check prints CHECK PASS or CHECK FAIL with its name; the script counts them.
var ok, f, t, s, a, b;

random_set_seed(12345);
ok = random_get_seed() == 12345;
show_debug_message("CHECK " + (ok ? "PASS" : "FAIL") + " random_get_seed returns the seed set: " + string(random_get_seed()));

randomize();
s = random_get_seed();
show_debug_message("CHECK " + (s != 0 ? "PASS" : "FAIL") + " randomize picks a seed random_get_seed returns: " + string(s));

random_set_seed(s); a = irandom(1000000); b = irandom(1000000);
random_set_seed(s);
ok = irandom(1000000) == a && irandom(1000000) == b;
show_debug_message("CHECK " + (ok ? "PASS" : "FAIL") + " the same seed gives the same numbers");

io_clear();
show_debug_message("CHECK PASS io_clear runs");

ok = is_real(joystick_zpos(1)) && is_real(joystick_rpos(1)) && is_real(joystick_upos(1)) && is_real(joystick_vpos(1));
show_debug_message("CHECK " + (ok ? "PASS" : "FAIL") + " joystick z/r/u/v return numbers");

f = file_text_open_write("enginecheck_append.txt"); file_text_write_string(f, "one"); file_text_close(f);
f = file_text_open_append("enginecheck_append.txt"); file_text_write_string(f, "two"); file_text_close(f);
f = file_text_open_read("enginecheck_append.txt"); s = file_text_read_string(f); file_text_close(f);
show_debug_message("CHECK " + (s == "onetwo" ? "PASS" : "FAIL") + " file_text_open_append keeps the old text: " + s);

t = tile_add(tlRescueTeam, 0, 0, 32, 32, 205, 624, 90);
tile_set_scale(t, -1, 1);
show_debug_message("CHECK " + (tile_exists(t) ? "PASS" : "FAIL") + " tile_set_scale keeps the tile");

ok = get_integer("x", 7) == 7 && get_string("x", "d") == "d";
show_debug_message("CHECK " + (ok ? "PASS" : "FAIL") + " get_integer and get_string return the default");

show_message("engine check");
show_message_async("engine check");
os_powersave_enable(false);
texture_set_interpolation_ext(0, 1);
show_debug_message("CHECK PASS dialogs and no-ops run");

a = background_get_width(bgAM2RTitle);
background_replace(bgAM2RTitle, "icon.png", 0, 0);
b = background_get_width(bgAM2RTitle);
show_debug_message("CHECK " + (b != a && b > 0 ? "PASS" : "FAIL") + " background_replace loads the new image: " + string(a) + " -> " + string(b));
