package port.engine;

class ReplayViewApp extends HeapsMain {
	static inline var MENU_FRAMES = 30;
	static inline var BOOT_SECONDS = 180;
	static inline var KIND_FRAME = 1;
	static inline var KIND_NOTE = 2;
	static var SPEED_STEPS = 11;
	static inline var END_PAD_MS = 2500;
	static inline var RENDER_W = 1920;
	static inline var RENDER_H = 1080;

	static var replayPath:String;
	static var pipePath:String;
	static var startW = 1280;
	static var startH = 720;

	var out:haxe.io.Output;
	var commands = new sys.thread.Deque<String>();
	var inputs:Array<String> = [];
	var began = haxe.Timer.stamp();
	var phase = 0;
	var menuFrames = 0;
	var acked = true;
	var sentFrame = -1;
	var boxes = false;
	var ended = false;
	var bytes:haxe.io.Bytes;
	var name:String;
	var lastFocused = "";

	public static function start(args:Array<String>):Void {
		if (args.length < 2) {
			Sys.println("usage: hl replay-sim.hl --view <replay file> <pipe> [width height]");
			Sys.exit(2);
		}
		replayPath = args[0];
		pipePath = args[1];
		if (args.length >= 4) {
			var w = Std.parseInt(args[2]), h = Std.parseInt(args[3]);
			if (w != null && h != null && w >= 160 && h >= 90) {
				startW = w;
				startH = h;
			}
		}
		BootLog.path = Sys.getEnv("BH_PORT_LOG");
		if (BootLog.path == null || BootLog.path == "") BootLog.path = "replay-view-boot.txt";
		flash.display.BitmapData.jpegEncoder = NativeJpeg.encode;
		var appDir = Sys.getEnv("BH_PORT_APP_DIR");
		if (appDir != null && appDir != "") port.runtime.services.Launch.configure("application", appDir);
		var storageDir = Sys.getEnv("BH_PORT_STORAGE_DIR");
		if (storageDir != null && storageDir != "") port.runtime.services.Launch.configure("storage", storageDir);
		port.runtime.services.Launch.setArguments([]);
		ShaderDiskCache.install(port.runtime.services.Launch.storageDirectory());
		HeapsMain.log("replay-view: start " + replayPath);
		dx.Window.startHidden = true;
		new ReplayViewApp();
	}

	override function makeStage():Void {
		var window = hxd.Window.getInstance();
		var stage = new flash.display.Stage(window, 0);
		HeapsMain.stage = stage;
		Display.start(HeapsMain.settingsPath());
		stage.onDisplayState = state -> {};
		var root = new flash.display.MovieClip();
		stage.addChild(root);
		flash.Lib.current = root;
		FrameLoop.root = stage;
		stage.resized(window.width, window.height);
		window.addResizeEvent(function() stage.resized(window.width, window.height));
		var input = new WindowInput(stage);
		@:privateAccess HeapsMain.windowInput = input;
		window.addEventTarget(input.onEvent);
	}

	static function hide():Void {
		var dxWindow:dx.Window = @:privateAccess hxd.Window.getInstance().window;
		@:privateAccess dx.Window.winResize(dxWindow.win, 3);
		@:bypassAccessor dxWindow.visible = false;
	}

	override function init():Void {
		hide();
		var window = hxd.Window.getInstance();
		window.vsync = false;
		window.resize(RENDER_W, RENDER_H);
		try {
			out = sys.io.File.write(pipePath, true);
		} catch (e:Dynamic) {
			Sys.println("replay-view: the pipe " + pipePath + " can't be opened: " + e);
			Sys.exit(4);
		}
		try {
			bytes = sys.io.File.getBytes(replayPath);
		} catch (e:Dynamic) {
			fail("the replay can't be read: " + e);
		}
		name = haxe.io.Path.withoutDirectory(replayPath);
		sys.thread.Thread.create(readCommands);
		super.init();
		hide();
		note({state: "starting", width: window.width, height: window.height});
	}

	function readCommands():Void {
		var input = Sys.stdin();
		while (true) {
			var line:String = null;
			try {
				line = input.readLine();
			} catch (e:Dynamic) {
				commands.add("quit");
				return;
			}
			commands.add(StringTools.trim(line));
		}
	}

	override function update(dt:Float):Void {
		#if replay_sim
		port.runtime.As3.fixedTimer = Std.int((haxe.Timer.stamp() - began) * 1000);
		#end
		var c:String;
		while ((c = commands.pop(false)) != null) {
			if (StringTools.startsWith(c, "key ") || StringTools.startsWith(c, "mouse ") || StringTools.startsWith(c, "wheel ") || StringTools.startsWith(c, "char "))
				inputs.push(c);
			else
				command(c);
		}
		while (inputs.length > 0) {
			var next = inputs.shift();
			command(next);
			if (!StringTools.startsWith(next, "mouse move")) break;
		}
		try {
			watch();
		} catch (e:Dynamic) {
			HeapsMain.log("replay-view: " + e);
		}
		super.update(dt);
	}

	function watch():Void {
		var core:Dynamic = ScreenManager.owner;
		var news:Dynamic = ScreenManager.var_14958;
		if (news != null && news.isActive == true) news.method_1172(null, 0);
		if (phase == 0) {
			var popup:Dynamic = ScreenManager.var_14057;
			if (popup != null && popup.isActive == true) popup.method_917();
			var now = focused();
			if (now != lastFocused) {
				lastFocused = now;
				note({state: "starting", screen: now, ms: Std.int((haxe.Timer.stamp() - began) * 1000)});
			}
			menuFrames = core != null && Std.isOfType(HeapsMain.gameFocusedScreen(), ScreenMainMenu) ? menuFrames + 1 : 0;
			if (menuFrames >= MENU_FRAMES) load(core);
			else if (haxe.Timer.stamp() - began > BOOT_SECONDS) fail("the game's start-up didn't reach the main menu (focused: " + now + ")");
			return;
		}
		if (phase == 1) {
			if (core != null && core.var_5381 != 0 && hud() != null) {
				phase = 2;
				ended = false;
				inject(new hxd.Event(EFocus));
				if (boxes) setBoxes(true);
				note({state: "playing", start: Std.int(core.var_5381), length: length(), players: Std.int(core.var_7148.length)});
			}
			return;
		}
		if (!ended && Std.isOfType(HeapsMain.gameFocusedScreen(), ScreenMainMenu)) {
			ended = true;
			note({state: "ended"});
		}
	}

	function load(core:Dynamic):Void {
		var data = new flash.utils.ByteArray();
		for (i in 0...bytes.length) data.writeByte(bytes.get(i));
		try {
			data.uncompress();
			Class_329.method_4102(data);
			data.position = 0;
			core.method_2824(name, new BitStream(data, 0));
		} catch (e:Dynamic) {
			fail("the game's reader refused the replay: " + e);
		}
		if (core.var_7148 == null || Std.int(core.var_7148.length) == 0)
			fail("the replay didn't start (another game version, or a mode or map that isn't loaded)");
		phase = 1;
		menuFrames = 0;
	}

	static function hud():Dynamic {
		var h:Dynamic = ScreenManager.var_960;
		return h != null && h.var_5452 != null ? h : null;
	}

	static function length():Int {
		var h = hud();
		var core:Dynamic = ScreenManager.owner;
		return h != null && core != null ? Std.int(Math.max(0, Std.int(h.var_5452.var_13178) + END_PAD_MS - Std.int(core.var_5381))) : 0;
	}

	function command(c:String):Void {
		var parts = c.split(" ");
		var n = (i:Int) -> {
			var v = i < parts.length ? Std.parseFloat(parts[i]) : Math.NaN;
			return Math.isNaN(v) ? 0.0 : v;
		};
		try {
			switch (parts[0]) {
				case "ack":
					acked = true;
				case "size":
					var w = Std.int(n(1)), h = Std.int(n(2));
					if (w >= 160 && h >= 90 && w <= 3840 && h <= 2160) {
						startW = w;
						startH = h;
					}
				case "seek":
					var h = hud();
					if (h != null) h.method_5373(Std.int(ScreenManager.owner.var_5381) + Std.int(Math.max(0, n(1))));
				case "speed":
					var h = hud();
					var i = Std.int(n(1));
					if (h != null && i >= 0 && i < SPEED_STEPS) {
						h.var_12287 = i;
						h.method_3695(true);
					}
				case "boxes":
					boxes = parts[1] == "on";
					if (phase == 2) setBoxes(boxes);
				case "restart":
					if (phase == 2 && ended && Std.isOfType(HeapsMain.gameFocusedScreen(), ScreenMainMenu)) load(ScreenManager.owner);
					else {
						var h = hud();
						if (h != null) h.method_5373(Std.int(ScreenManager.owner.var_5381));
					}
				case "mouse":
					mouse(parts[1], Std.int(n(2)), n(3), n(4));
				case "wheel":
					var e = new hxd.Event(EWheel, n(2), n(3));
					e.wheelDelta = n(1);
					inject(e);
				case "key":
					var e = new hxd.Event(parts[1] == "down" ? EKeyDown : EKeyUp);
					e.keyCode = Std.int(n(2));
					inject(e);
				case "char":
					var e = new hxd.Event(ETextInput);
					e.charCode = Std.int(n(1));
					inject(e);
				case "quit":
					BootLog.flush();
					Sys.exit(0);
				default:
			}
		} catch (e:Dynamic) {
			HeapsMain.log("replay-view: command " + c + " failed: " + e);
		}
	}

	function mouse(kind:String, button:Int, x:Float, y:Float):Void {
		var window = hxd.Window.getInstance();
		@:privateAccess window.curMouseX = Std.int(x);
		@:privateAccess window.curMouseY = Std.int(y);
		var e = new hxd.Event(kind == "down" ? EPush : kind == "up" ? ERelease : EMove, x, y);
		e.button = button;
		inject(e);
	}

	static function inject(e:hxd.Event):Void {
		hxd.Window.getInstance().event(e);
	}

	function setBoxes(on:Bool):Void {
		var core:Dynamic = ScreenManager.owner;
		if (core == null) return;
		if (on) {
			core.method_2374();
			core.method_1651();
		} else {
			core.method_9022();
			core.method_603();
		}
	}

	override function render(e:h3d.Engine):Void {
		super.render(e);
		if (phase != 2 || !acked || frames == sentFrame || lastFrame == null) return;
		sentFrame = frames;
		try {
			var pixels = shrunk(e).capturePixels();
			if (e.driver.hasFeature(BottomLeftCoords)) pixels.flipY();
			var format = switch (pixels.format) {
				case RGBA: 0;
				case BGRA: 1;
				default:
					pixels.convert(RGBA);
					0;
			}
			var core:Dynamic = ScreenManager.owner;
			var h = hud();
			var head = new haxe.io.BytesOutput();
			head.writeString("BRV1");
			head.writeInt32(KIND_FRAME);
			head.writeInt32(pixels.width);
			head.writeInt32(pixels.height);
			head.writeInt32(format);
			head.writeInt32(core != null ? Std.int(Math.max(0, Std.int(core.var_12852) - Std.int(core.var_5381))) : 0);
			head.writeInt32(length());
			head.writeInt32(speedStep(h));
			head.writeInt32((boxes ? 1 : 0) | (ended ? 2 : 0));
			head.writeInt32(HeapsMain.stage.stageWidth);
			head.writeInt32(HeapsMain.stage.stageHeight);
			var size = pixels.width * pixels.height * 4;
			out.write(head.getBytes());
			out.writeFullBytes(pixels.bytes, pixels.offset, size);
			out.flush();
			acked = false;
		} catch (error:Dynamic) {
			HeapsMain.log("replay-view: sending a frame failed: " + error);
			Sys.exit(5);
		}
	}

	static function speedStep(h:Dynamic):Int {
		if (h == null) return -1;
		var mode = Std.int(h.var_2341);
		var modes:Array<Dynamic> = Class_536.var_10474;
		for (i in 0...modes.length)
			if (Std.int(modes[i]) == mode) return i;
		return Std.int(h.var_12287);
	}

	var small:h3d.mat.Texture;

	function shrunk(e:h3d.Engine):h3d.mat.Texture {
		var k = Math.min(1, Math.min(startW / lastFrame.width, startH / lastFrame.height));
		var w = Std.int(Math.max(1, Math.round(lastFrame.width * k))), h = Std.int(Math.max(1, Math.round(lastFrame.height * k)));
		if (w == lastFrame.width && h == lastFrame.height) return lastFrame;
		if (small != null && (small.width != w || small.height != h)) {
			small.dispose();
			small = null;
		}
		if (small == null) small = new h3d.mat.Texture(w, h, [Target]);
		var entered = port.engine.art.FxContext.enter();
		lastFrame.filter = Linear;
		h3d.pass.Copy.run(lastFrame, small);
		lastFrame.filter = Nearest;
		port.engine.art.FxContext.leave(entered);
		return small;
	}

	function note(o:Dynamic):Void {
		try {
			var text = haxe.io.Bytes.ofString(haxe.Json.stringify(o));
			var head = new haxe.io.BytesOutput();
			head.writeString("BRV1");
			head.writeInt32(KIND_NOTE);
			head.writeInt32(text.length);
			out.write(head.getBytes());
			out.write(text);
			out.flush();
		} catch (e:Dynamic) {
			Sys.exit(5);
		}
	}

	function fail(why:String):Void {
		HeapsMain.log("replay-view: " + why);
		if (out != null) note({state: "failed", error: why});
		BootLog.flush();
		Sys.exit(1);
	}

	static function focused():String {
		var s:Dynamic = HeapsMain.gameFocusedScreen();
		if (s == null) return "nothing";
		var c = Type.getClass(s);
		return c == null ? "?" : Type.getClassName(c);
	}
}
