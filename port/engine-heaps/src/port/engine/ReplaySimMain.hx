package port.engine;

class ReplaySimMain {
	static inline var STEP = 16;
	static inline var MENU_FRAMES = 30;
	static inline var BOOT_SECONDS = 180;
	static inline var IDLE_LIMIT = 900;
	static inline var BOOT_FRAME_MS = 20;
	static var bootClock = 0;
	static var ITEM_FIELDS = ["x", "y", "state", "type", "thrownBy"];
	static var HIT_FIELDS = ["x", "y", "rx", "ry", "kind", "by"];
	static var HURT_FIELDS = ["dx", "dy", "rx", "ry"];
	static inline var GROUND_CHECK_COLOR = 559240;
	static inline var NO_OWNER_DISTANCE = 0.5;
	static var CLOCK =#if replay_sim "fixed" #else "pinned" #end;
	static var FIELDS = ["x", "y", "vx", "vy", "left", "state", "damage", "lives", "stunned", "air", "anim", "frame", "power",
		"castFrame", "weapon", "hitBy", "cast", "look"];
	static var LOOK_FIELDS = ["animFile", "animClass", "scale", "weaponSkin", "hideItem"];
	static var looks:Array<Dynamic> = [];
	static var lookIds = new Map<String, Int>();

	static var steps:Array<Dynamic> = [];
	static var failedReads = 0;
	static var BOOT_SLEEP = 0.0;
	static var lastFocused = "";
	static var level:Dynamic = null;
	static var moving:Array<Dynamic> = [];
	static var lastMoving:String = null;
	static var lastHurt:String = null;

	static function main():Void {
		var args = Sys.args();
		if (args.length > 0 && args[0] == "--view") {
			ReplayViewApp.start(args.slice(1));
			return;
		}
		try {
			run();
		} catch (e:Dynamic) {
			Sys.println("replay-sim: stopped by an error: " + e + "\n" + haxe.CallStack.toString(haxe.CallStack.exceptionStack()));
			Sys.exit(3);
		}
	}

	static function run():Void {
		var args = Sys.args();
		if (args.length < 2) {
			Sys.println("usage: hl replay-sim.hl <replay file> <output .jsonl>");
			Sys.exit(2);
		}
		var replayPath = args[0];
		var outPath = args[1];
		var name = haxe.io.Path.withoutDirectory(replayPath);
		port.runtime.services.Launch.setArguments([]);
		BootLog.path = Sys.getEnv("BH_PORT_LOG");
		if (BootLog.path == null || BootLog.path == "") BootLog.path = "replay-sim-boot.txt";
		var appDir = Sys.getEnv("BH_PORT_APP_DIR");
		if (appDir != null && appDir != "") port.runtime.services.Launch.configure("application", appDir);
		var storageDir = Sys.getEnv("BH_PORT_STORAGE_DIR");
		if (storageDir != null && storageDir != "") port.runtime.services.Launch.configure("storage", storageDir);
		Sys.putEnv("BH_PORT_NO_SOUND", "1");
		var bytes:haxe.io.Bytes = null;
		try {
			bytes = sys.io.File.getBytes(replayPath);
		} catch (e:Dynamic) {
			fail(outPath, name, "the replay can't be read: " + e);
		}
		var began = haxe.Timer.stamp();
		var stage = new flash.display.Stage(null, 0);
		Display.start(HeapsMain.settingsPath());
		var root = new flash.display.MovieClip();
		stage.addChild(root);
		flash.Lib.current = root;
		FrameLoop.root = stage;
		stage.resized(1920, 1080);
		HeapsMain.stage = stage;
		HeapsMain.boot();

		var frame = 0;
		var menuFrames = 0;
		var phase = 0;
		var virtualMs = 0.0;
		var lastTime = -1.0;
		var idle = 0;
		var bootMs = 0.0;
		var simStart = 0.0;
		var startTime = 0.0;
		var players:Array<Dynamic> = null;
		while (true) {
			if (phase == 2) {
				virtualMs += STEP;
				#if replay_sim
				port.runtime.As3.fixedTimer = Std.int(virtualMs);
				#else
				@:privateAccess port.runtime.As3.timerBase = haxe.Timer.stamp() - virtualMs / 1000;
				#end
			}
			#if replay_sim
			else {
				bootClock = Std.int(Math.max(bootClock + BOOT_FRAME_MS, (haxe.Timer.stamp() - began) * 1000));
				port.runtime.As3.fixedTimer = bootClock;
			}
			#end
			HeapsMain.gameFrame(frame++);
			var core:Dynamic = ScreenManager.owner;
			if (phase == 0) {
				var popup:Dynamic = ScreenManager.var_14057;
				if (popup != null && popup.isActive == true) popup.method_917();
				menuFrames = core != null && Std.isOfType(HeapsMain.gameFocusedScreen(), ScreenMainMenu) ? menuFrames + 1 : 0;
				if (menuFrames >= MENU_FRAMES) {
					bootMs = (haxe.Timer.stamp() - began) * 1000;
					var data = new flash.utils.ByteArray();
					for (i in 0...bytes.length) data.writeByte(bytes.get(i));
					try {
						data.uncompress();
						Class_329.method_4102(data);
						data.position = 0;
						core.method_2824(name, new BitStream(data, 0));
					} catch (e:Dynamic) {
						fail(outPath, name, "the game's reader refused the replay: " + e);
					}
					if (core.var_7148 == null || Std.int(core.var_7148.length) == 0)
						fail(outPath, name, "the replay didn't start (another game version, or a mode or map that isn't loaded)");
					showBoxes(core);
					phase = 1;
				} else if (haxe.Timer.stamp() - began > BOOT_SECONDS) {
					fail(outPath, name, "the game's start-up didn't reach the main menu (focused: " + focused() + ")");
				} else {
					var now = focused();
					if (now != lastFocused) {
						lastFocused = now;
						Sys.println("replay-sim: start-up frame " + frame + ", " + Std.int((haxe.Timer.stamp() - began) * 1000) + " ms, focused " + now);
					}
					if (BOOT_SLEEP > 0) Sys.sleep(BOOT_SLEEP);
				}
				continue;
			}
			if (phase == 1) {
				virtualMs = port.runtime.As3.getTimer();
				simStart = haxe.Timer.stamp();
				phase = 2;
				continue;
			}
			var time:Float = core.var_14052;
			if (players == null && core.var_5381 != 0) {
				startTime = core.var_5381;
				players = describe(core.var_7148);
				level = describeLevel(core);
				showBoxes(core);
			}
			if (time != lastTime) {
				if (time < lastTime) {
					while (steps.length > 0 && steps[steps.length - 1].t >= time) steps.pop();
					rewindDodges(time);
					lastMoving = null;
					lastHurt = null;
				}
				lastTime = time;
				idle = 0;
				record(core, time);
			} else if (++idle > IDLE_LIMIT) {
				break;
			}
			if ((Std.int(core.var_3645) & 2048) != 0) break;
		}
		if (players == null) players = describe(ScreenManager.owner.var_7148);
		if (level == null) level = describeLevel(ScreenManager.owner);
		var lines = [haxe.Json.stringify({format: "bifrost-replay-frames", version: 1, replay: name, step: STEP, start: startTime,
			end: lastTime, fields: FIELDS, itemFields: ITEM_FIELDS, hitFields: HIT_FIELDS, hurtFields: HURT_FIELDS, lookFields: LOOK_FIELDS,
			looks: looks, players: players, level: level, source: "replay-sim", clock: CLOCK})];
		for (s in steps) lines.push(haxe.Json.stringify(s));
		var ev = events();
		var stats:Dynamic = null;
		try {
			stats = matchStats(ScreenManager.owner);
		} catch (e:Dynamic) {
			stats = {error: Std.string(e)};
		}
		lines.push(haxe.Json.stringify({steps: steps.length, events: ev, failedReads: failedReads, bootMs: Std.int(bootMs),
			simMs: Std.int((haxe.Timer.stamp() - simStart) * 1000), stats: stats}));
		write(outPath, lines.join("\n") + "\n");
		Sys.println("replay-sim: " + name + ": " + steps.length + " steps, " + ev.length + " events, start-up " + Std.int(bootMs) + " ms, simulation "
			+ Std.int((haxe.Timer.stamp() - simStart) * 1000) + " ms");
		Sys.exit(0);
	}

	static function focused():String {
		var s:Dynamic = HeapsMain.gameFocusedScreen();
		if (s == null) return "nothing";
		var c = Type.getClass(s);
		return c == null ? "?" : Type.getClassName(c);
	}

	static function record(core:Dynamic, time:Float):Void {
		var list:Dynamic = core.var_7148;
		var n = Std.int(list.length);
		var ids = new Map<Int, Int>();
		for (i in 0...n) {
			var p:Dynamic = port.runtime.As3.index(list, i);
			if (p != null) ids.set(Std.int(p.var_11517), i);
		}
		var row:Array<Dynamic> = [];
		for (i in 0...n) row.push(read(port.runtime.As3.index(list, i), ids));
		var step:Dynamic = {t: time, p: row};
		var items = readItems(core, ids);
		if (items.length > 0) step.i = items;
		readBoxes(core, list, n, step);
		if (moving.length > 0) {
			var now = [for (l in moving) lineCoords(l)];
			var text = haxe.Json.stringify(now);
			if (text != lastMoving) {
				lastMoving = text;
				step.d = now;
			}
		}
		steps.push(step);
		for (i in 0...n) noteDodge(port.runtime.As3.index(list, i), i, time);
	}

	static var dodgeSeen = new Map<Int, Int>();
	static var dodgeTimes = new Map<Int, Array<Array<Float>>>();

	static function noteDodge(p:Dynamic, i:Int, time:Float):Void {
		var s:Dynamic = p != null ? p.var_3185 : null;
		if (s == null) return;
		var count = Std.int(s.var_39) + Std.int(s.var_3329);
		var before = dodgeSeen.get(i);
		dodgeSeen.set(i, count);
		if (before == null || count <= before) return;
		var input:Dynamic = p.var_10154;
		var bits = input != null ? Std.int(port.runtime.As3.toUInt(input.var_13264)) : 0;
		var row = (bits & 1) != 0 ? 0 : ((bits & 2) != 0 ? 2 : 1);
		var col = (bits & 4) != 0 ? 0 : ((bits & 8) != 0 ? 2 : 1);
		if (!dodgeTimes.exists(i)) dodgeTimes.set(i, []);
		dodgeTimes.get(i).push([time, row * 3 + col]);
	}

	static function rewindDodges(time:Float):Void {
		for (times in dodgeTimes)
			while (times.length > 0 && times[times.length - 1][0] >= time) times.pop();
		dodgeSeen = new Map<Int, Int>();
	}

	static function dodgeGrid(i:Int):Array<Int> {
		var out = [for (_ in 0...9) 0];
		var times = dodgeTimes.get(i);
		if (times != null) for (t in times) out[Std.int(t[1])]++;
		return out;
	}

	static function readItems(core:Dynamic, ids:Map<Int, Int>):Array<Dynamic> {
		var out:Array<Dynamic> = [];
		try {
			var manager:Dynamic = core.var_14491;
			var list:Dynamic = manager != null ? manager.var_6940 : null;
			if (list == null) return out;
			for (i in 0...Std.int(list.length)) {
				var w:Dynamic = port.runtime.As3.index(list, i);
				if (w == null) continue;
				var state = Std.int(w.var_2074);
				if (state == 7) continue;
				var type:Dynamic = w.var_3100;
				var by = ids.get(Std.int(w.var_1243));
				out.push([round(w.method_344()), round(w.method_4398()), state, type != null ? Std.string(type.var_13080) : null, by != null ? by : -1]);
			}
		} catch (e:Dynamic) {
			if (++failedReads <= 3) Sys.println("replay-sim: reading the items failed: " + e);
		}
		return out;
	}

	static function showBoxes(core:Dynamic):Void {
		try {
			core.method_2374();
			core.method_1651();
		} catch (e:Dynamic) {
			if (++failedReads <= 3) Sys.println("replay-sim: switching the boxes on failed: " + e);
		}
	}

	static function readBoxes(core:Dynamic, list:Dynamic, n:Int, step:Dynamic):Void {
		try {
			var centres:Array<Array<Float>> = [];
			var hurt:Array<Dynamic> = [];
			var anyHurt = false;
			for (i in 0...n) {
				var p:Dynamic = port.runtime.As3.index(list, i);
				var phys:Dynamic = p != null ? p.var_3693 : null;
				centres.push(phys != null ? [(phys.method_112(p.var_5184) : Float), (phys.method_112(p.var_9604) : Float)] : null);
				var b = p != null ? capsule(p.var_6919) : null;
				if (b != null) {
					anyHurt = true;
					b[0] = round(b[0] - p.method_344());
					b[1] = round(b[1] - p.method_4398());
				}
				hurt.push(b);
			}
			if (anyHurt) {
				var text = haxe.Json.stringify(hurt);
				if (text != lastHurt) {
					lastHurt = text;
					step.u = hurt;
				}
			}
			var clips:Dynamic = core.var_336;
			if (clips == null) return;
			var used = Std.int(Math.min(Std.int(core.var_11695), Std.int(clips.length)));
			var hits:Array<Dynamic> = [];
			for (i in 0...used) {
				var clip:flash.display.MovieClip = port.runtime.As3.index(clips, i);
				var b = capsule(clip);
				if (b == null) continue;
				var g = clip.graphics;
				var color = g.fills.length > 0 && g.fills[0].paint != null ? g.fills[0].paint.color : 0;
				b.push(color == GROUND_CHECK_COLOR ? 1 : 0);
				var by = -1;
				for (k in 0...centres.length) {
					var c = centres[k];
					if (c != null && Math.abs(c[0] - clip.x) < NO_OWNER_DISTANCE && Math.abs(c[1] - clip.y) < NO_OWNER_DISTANCE) {
						by = k;
						break;
					}
				}
				b.push(by);
				hits.push(b);
			}
			if (hits.length > 0) step.h = hits;
		} catch (e:Dynamic) {
			if (++failedReads <= 3) Sys.println("replay-sim: reading the boxes failed: " + e);
		}
	}

	static function capsule(clip:flash.display.MovieClip):Array<Dynamic> {
		if (clip == null) return null;
		var b = clip.graphics.bounds;
		if (b == null || (b.width <= 0 && b.height <= 0)) return null;
		var sx = clip.scaleX < 0 ? -1.0 : 1.0;
		return [round(clip.x + sx * (b.x + b.width / 2)), round(clip.y + b.y + b.height / 2), round(b.width / 2), round(b.height / 2)];
	}

	static function describeLevel(core:Dynamic):Dynamic {
		var out:Dynamic = {};
		try {
			var lvl:Dynamic = core.var_14856;
			var type:Dynamic = lvl != null ? lvl.var_259 : null;
			if (type != null) {
				out.name = Std.string(type.var_5251);
				out.kill = [Std.int(type.var_15329), Std.int(type.var_10761), Std.int(type.var_9302), Std.int(type.var_10452)];
			}
			var cam:Dynamic = lvl != null ? lvl.var_5920 : null;
			if (cam != null) out.camera = [round(cam.x), round(cam.y), round(cam.width), round(cam.height)];
			var coll:Dynamic = core.var_13834;
			if (coll != null) {
				out.lines = lineList(coll.var_7821, false);
				out.moving = lineList(coll.var_8586, true);
			}
		} catch (e:Dynamic) {
			out.error = Std.string(e);
		}
		return out;
	}

	static function lineList(list:Dynamic, keep:Bool):Array<Dynamic> {
		var out:Array<Dynamic> = [];
		if (list == null) return out;
		for (i in 0...Std.int(list.length)) {
			var l:Dynamic = port.runtime.As3.index(list, i);
			if (l == null) continue;
			var c = lineCoords(l);
			var kind:Dynamic = null;
			try {
				kind = port.runtime.As3.intMap(Class_77.var_270).get(Std.int(l.type));
			} catch (e:Dynamic) {}
			c.push(kind != null ? Std.string(kind) : Std.string(Std.int(l.type)));
			out.push(c);
			if (keep) moving.push(l);
		}
		return out;
	}

	static function lineCoords(l:Dynamic):Array<Dynamic> {
		return [round(l.startX), round(l.startY), round(l.var_166), round(l.var_1862), l.var_8394 == true ? 1 : 0];
	}

	static function read(p:Dynamic, ids:Map<Int, Int>):Array<Dynamic> {
		if (p == null) return null;
		try {
			var combat:Dynamic = p.var_2030;
			var power:Dynamic = combat != null ? combat.var_9352 : null;
			var item:Dynamic = combat != null ? combat.var_4401 : null;
			var gfx:Dynamic = p.var_11982;
			var seq:Dynamic = gfx != null ? gfx.var_143 : null;
			var move:Dynamic = seq != null ? seq.var_7915 : null;
			var type:Dynamic = power != null ? power.var_14457 : null;
			var itemType:Dynamic = item != null ? item.var_3100 : null;
			var hit = ids.get(Std.int(p.var_11390));
			return [
				round(p.method_344()), round(p.method_4398()), round(p.method_7969()), round(p.method_8771()), p.method_7203() ? 1 : 0,
				Std.int(p.var_669), round(p.var_2930), Std.int(p.var_14369), p.method_510() ? 1 : 0, p.method_465() ? 1 : 0,
				move != null ? Std.string(move.var_13447) : null, seq != null ? Std.int(seq.var_6869) : 0,
				type != null ? Std.string(type.var_511) : null, power != null ? round(power.var_2686) : 0,
				itemType != null ? Std.string(itemType.var_13080) : null, hit != null ? hit : -1, power != null ? Std.int(power.var_3206) : -1,
				look(p, move, item)
			];
		} catch (e:Dynamic) {
			if (++failedReads <= 3) Sys.println("replay-sim: reading a player failed: " + e);
		}
		return null;
	}

	static function look(p:Dynamic, move:Dynamic, item:Dynamic):Int {
		try {
			var def:Dynamic = move != null ? move.var_5408 : null;
			if (def == null) return -1;
			var gfx:Dynamic = p.var_13031;
			var skin:Dynamic = item != null ? item.var_855 : null;
			var row:Array<Dynamic> = [
				Std.string(def.var_7323), Std.string(def.var_4536), gfx != null ? round(gfx.var_12146) : 1,
				skin != null ? Std.string(skin.mWeaponSkinName) : null, p.var_11361 == true ? 1 : 0
			];
			var key = haxe.Json.stringify(row);
			var id = lookIds.get(key);
			if (id == null) {
				id = looks.length;
				looks.push(row);
				lookIds.set(key, id);
			}
			return id;
		} catch (e:Dynamic) {
			if (++failedReads <= 3) Sys.println("replay-sim: reading a player's look failed: " + e);
		}
		return -1;
	}

	static function round(v:Dynamic):Float {
		var n:Float = v;
		return Math.isNaN(n) ? 0 : Math.round(n * 100) / 100;
	}

	static function describe(list:Dynamic):Array<Dynamic> {
		var out:Array<Dynamic> = [];
		if (list == null) return out;
		for (i in 0...Std.int(list.length)) {
			var p:Dynamic = port.runtime.As3.index(list, i);
			var o:Dynamic = {index: i};
			try {
				o.name = p.var_6401 != null ? Std.string(p.var_6401.var_15008) : Std.string(p.var_4811);
				o.team = Std.int(p.var_3592);
				var heroes:Dynamic = p.var_12992;
				var hero:Dynamic = null;
				if (heroes != null && Std.int(heroes.length) > 0)
					hero = HeroType.var_1291[Std.int(port.runtime.As3.index(heroes, 0).var_12011) & 0xFFFF];
				o.legend = hero != null ? Std.string(hero.mDisplayName) : "";
				o.hero = hero != null ? Std.string(hero.mHeroName) : "";
				var costume:Dynamic = p.var_109;
				var scheme:Dynamic = p.var_14633;
				var skin1:Dynamic = p.mWeaponSkin1;
				var skin2:Dynamic = p.mWeaponSkin2;
				o.costume = costume != null ? Std.string(costume.mCostumeName) : null;
				o.colorScheme = scheme != null ? Std.string(scheme.mColorSchemeName) : null;
				o.weaponSkins = [skin1 != null ? Std.string(skin1.mWeaponSkinName) : null, skin2 != null ? Std.string(skin2.mWeaponSkinName) : null];
			} catch (e:Dynamic) {
				o.error = Std.string(e);
			}
			out.push(o);
		}
		return out;
	}

	static function events():Array<Dynamic> {
		var out:Array<Dynamic> = [];
		var damage = new Map<Int, Float>();
		var state = new Map<Int, Int>();
		for (s in steps) {
			var row:Array<Dynamic> = s.p;
			for (i in 0...row.length) {
				var v:Array<Dynamic> = row[i];
				if (v == null) continue;
				var d:Float = v[6];
				var st:Int = v[5];
				if (damage.exists(i) && d > damage.get(i)) out.push({e: "hit", t: s.t, p: i, damage: round(d - damage.get(i)), by: v[15]});
				if (state.exists(i) && st != state.get(i)) {
					var was = state.get(i);
					if (st == 3 && (was == 0 || was == 5 || was == 6)) out.push({e: "ko", t: s.t, p: i, by: v[15]});
					else if ((st == 0 || st == 5) && (was == 3 || was == 4)) out.push({e: "spawn", t: s.t, p: i});
					else if (st == 7) out.push({e: "out", t: s.t, p: i});
				}
				damage.set(i, d);
				state.set(i, st);
			}
		}
		return out;
	}

	static inline var STATS_BUCKET = 16;

	static function matchStats(core:Dynamic):Dynamic {
		if (core == null) return null;
		var list:Dynamic = core.var_7148;
		var win:Float = core.var_14568;
		var end:Float = win != 0 ? win : core.var_14052;
		var begin:Float = core.var_5381;
		var players:Array<Dynamic> = [];
		var longest = 0;
		for (i in 0...Std.int(list.length)) {
			var p:Dynamic = port.runtime.As3.index(list, i);
			var s:Dynamic = p != null ? p.var_3185 : null;
			if (s == null || s.var_5895 == null) continue;
			var o:Dynamic = {index: i, dealt: num(s.var_415), taken: num(s.var_7478) + num(s.var_14548), kos: Std.int(s.var_6782),
				falls: Std.int(s.var_8773), sds: Std.int(s.var_4258), dodges: Std.int(s.var_39), airDodges: Std.int(s.var_3329),
				dashes: Std.int(s.var_13527), jumps: Std.int(s.var_11719), air: Std.int(s.var_2497) * STEP, ground: Std.int(s.var_15001) * STEP,
				wall: Std.int(s.var_1025) * STEP, clashes: Std.int(s.var_8326), score: Std.int(p.var_15251), team: Std.int(p.var_3592),
				dodgeGrid: dodgeGrid(i)};
			var damage:Array<Float> = [];
			var seq:Dynamic = s.var_5895;
			var value = 0.0;
			var n = Std.int(seq.length);
			for (k in 0...n) {
				var v:Dynamic = port.runtime.As3.index(seq, k);
				if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) {
					var f:Float = v;
					if (!Math.isNaN(f)) value = f;
				}
				if (k % STATS_BUCKET == STATS_BUCKET - 1 || k == n - 1) damage.push(round(value));
			}
			o.damage = damage;
			if (damage.length > longest) longest = damage.length;
			var attacks = new Map<Int, Dynamic>();
			var damageBy:Dynamic = port.runtime.As3.intMap(s.var_15564).h;
			var it:Dynamic = new haxe.ds.IntMapKeysIterator(damageBy);
			while (port.runtime.As3.toBool(it.hasNext())) {
				var key:Int = Std.int(port.runtime.As3.toUInt(port.runtime.As3.callMember(it, "next", [])));
				attack(attacks, key).damage += num(port.runtime.As3.index(damageBy, key));
			}
			var usesBy:Dynamic = port.runtime.As3.intMap(s.var_1987).h;
			it = new haxe.ds.IntMapKeysIterator(usesBy);
			while (port.runtime.As3.toBool(it.hasNext())) {
				var key:Int = Std.int(port.runtime.As3.toUInt(port.runtime.As3.callMember(it, "next", [])));
				var packed:Int = Std.int(port.runtime.As3.toUInt(port.runtime.As3.index(usesBy, key)));
				var a:Dynamic = attack(attacks, key);
				a.uses += packed & 0x0FFF;
				a.hits += (packed >>> 12) & 0x0FFF;
				a.kos += packed >>> 24;
			}
			var out:Array<Dynamic> = [for (a in attacks) a];
			for (a in out) a.damage = round(a.damage);
			out.sort((x, y) -> x.damage != y.damage ? (y.damage > x.damage ? 1 : -1) : y.hits - x.hits);
			o.attacks = out;
			players.push(o);
		}
		var length:Float = end > begin + 6000 ? end - begin - 6000 : 0;
		return {source: "GameStats", length: Std.int(length), bucket: STATS_BUCKET * STEP, points: longest, players: players};
	}

	static function attack(byKey:Map<Int, Dynamic>, key:Int):Dynamic {
		var k = key & ~(2 | 0x80000000);
		var a = byKey.get(k);
		if (a != null) return a;
		var item:Dynamic = port.runtime.As3.index(ItemType.var_7450, (k >>> 16) & 0x0FFF);
		var name:Dynamic = port.runtime.As3.index(port.runtime.As3.intMap(Class_83.var_5985).h, k & Std.int(Class_83.var_437));
		a = {weapon: item != null ? Std.string(item.var_13080) : "", name: name != null ? Std.string(name) : "?", damage: 0.0, uses: 0, hits: 0, kos: 0};
		byKey.set(k, a);
		return a;
	}

	static function num(v:Dynamic):Float {
		if (v == null) return 0;
		var f:Float = v;
		return Math.isNaN(f) ? 0 : f;
	}

	static function write(path:String, text:String):Void {
		var dir = haxe.io.Path.directory(path);
		if (dir != "" && !sys.FileSystem.exists(dir)) sys.FileSystem.createDirectory(dir);
		sys.io.File.saveContent(path + ".tmp", text);
		if (sys.FileSystem.exists(path)) sys.FileSystem.deleteFile(path);
		sys.FileSystem.rename(path + ".tmp", path);
	}

	static function fail(outPath:String, name:String, why:String):Void {
		Sys.println("replay-sim: " + name + ": " + why);
		try {
			write(outPath, haxe.Json.stringify({format: "bifrost-replay-frames", version: 1, replay: name, error: why}) + "\n");
		} catch (e:Dynamic) {}
		Sys.exit(1);
	}
}
