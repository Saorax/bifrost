package port.engine;

class HeapsMain extends hxd.App {
	public static function log(text:String):Void {
		BootLog.log(text);
	}

	static function main():Void {
		BootLog.path = Sys.getEnv("BH_PORT_LOG");
		if (BootLog.path == null || BootLog.path == "") BootLog.path = "bh-port-heaps-boot.txt";
		flash.display.BitmapData.jpegEncoder = NativeJpeg.encode;
		var appDir = Sys.getEnv("BH_PORT_APP_DIR");
		if (appDir != null && appDir != "") port.runtime.services.Launch.configure("application", appDir);
		var storageDir = Sys.getEnv("BH_PORT_STORAGE_DIR");
		if (storageDir != null && storageDir != "") port.runtime.services.Launch.configure("storage", storageDir);
		if (Sys.getEnv("BH_PORT_TRACK_ALLOC") == "1") h3d.impl.MemoryManager.enableTrackAlloc();
		ShaderDiskCache.install(port.runtime.services.Launch.storageDirectory());
		log("boot: start (Heaps engine, application " + port.runtime.services.Launch.applicationDirectory() + ")");
		try new HeapsMain() catch (e:Dynamic) {
			if (!RendererStart.failed(Std.string(e))) throw e;
		}
	}

	var frames = 0;

	public static var stage:flash.display.Stage;

	public static function settingsPath():String {
		return haxe.io.Path.join([port.runtime.services.Launch.storageDirectory(), "engine.json"]);
	}

	function makeStage():Void {
		var window = hxd.Window.getInstance();
		stage = new flash.display.Stage(window, 0);
		Display.start(settingsPath(), function(mode, vsync, monitor) {
			if (window.vsync != vsync) window.vsync = vsync;
			var target = mode == "fullscreen" ? hxd.Window.DisplayMode.Fullscreen
				: mode == "borderless" ? hxd.Window.DisplayMode.Borderless : hxd.Window.DisplayMode.Windowed;
			var screen:Null<Int> = monitor < 0 ? null : monitor;
			if (window.displayMode != target || window.monitor != screen) {
				window.monitor = screen;
				window.displayMode = target;
				#if hlsdl
				if (target == hxd.Window.DisplayMode.Borderless) {
					var size = window.getCurrentDisplaySetting(screen);
					if (size != null && (window.width != size.width || window.height != size.height))
						window.resize(size.width, size.height);
				}
				#end
			}
		});
		stage.onDisplayState = function(state) Display.gameDisplayState(state != flash.display.StageDisplayState.NORMAL);
		var root = new flash.display.MovieClip();
		stage.addChild(root);
		flash.Lib.current = root;
		FrameLoop.root = stage;
		stage.resized(window.width, window.height);
		window.addResizeEvent(function() stage.resized(window.width, window.height));
		windowInput = new WindowInput(stage);
		window.addEventTarget(windowInput.onEvent);
	}

	static var windowInput:WindowInput = null;

	static var frameStartedAt = -1.0;

	public static function startWatchdog():Void {
		var limit = Std.parseFloat(Sys.getEnv("BH_PORT_WATCHDOG"));
		if (Math.isNaN(limit) || limit <= 0) return;
		log("watchdog: armed at " + limit + " s per game frame (exit code 3)");
		sys.thread.Thread.create(function() {
			while (true) {
				Sys.sleep(0.5);
				var started = frameStartedAt;
				if (started >= 0 && Sys.time() - started > limit) {
					BootLog.flush();
					Sys.exit(3);
				}
			}
		});
	}

	override function init():Void {
		makeStage();
		port.runtime.input.Pads.source = HeapsPads.start;
		if (Sys.getEnv("BH_PORT_GPU") != "0") {
			gpu = new GpuStage3D(engine);
			flash.display3D.Context3D.backend = gpu;
			var raster = new port.engine.art.VectorRaster(engine);
			if (Sys.getEnv("BH_PORT_GPU_VECTORS") != "0") flash.display.BitmapData.vectorDrawer = raster.draw;
			if (Sys.getEnv("BH_PORT_GPU_BITMAPS") != "0") port.engine.art.GpuBitmaps.engine = engine;
			if (Sys.getEnv("BH_PORT_DISPLAY") != "0") display = new DisplayRenderer(engine, raster);
		}
		#if port_smoke
		flash.display.BitmapData.onVectorDraw = (source, target, matrix, ct, ms) -> port.runtime.DrawStats.note(source,
			target, matrix, ct, ms);
		DisplayRenderer.onRaster = port.runtime.DrawStats.noteRaster;
		port.runtime.SmokeDriver.shooter = name -> pendingShot = name;
		#end
		var probeMode = Sys.getEnv("BH_PORT_GPU_PROBE");
		if (probeMode == "1" || probeMode == "boot") {
			probe = new GpuProbe();
			log("gpu probe: " + probeMode);
			if (probeMode == "1") return;
		}
		boot();
	}

	var probe:GpuProbe;
	var probeFrames = 0;

	public static var gpu(default, null):GpuStage3D;
	public static var display(default, null):DisplayRenderer;
	var frameDue = false;
	static var gpuInUpdate = Sys.getEnv("BH_PORT_GPU_IN_UPDATE") == "1";

	var lastFrame:h3d.mat.Texture;

	function frameTarget(e:h3d.Engine):h3d.mat.Texture {
		if (lastFrame != null && (lastFrame.width != e.width || lastFrame.height != e.height)) {
			lastFrame.dispose();
			lastFrame = null;
		}
		if (lastFrame == null) {
			lastFrame = new h3d.mat.Texture(e.width, e.height, [Target]);
			lastFrame.filter = Nearest;
			e.pushTarget(lastFrame);
			e.clear(e.backgroundColor != null ? e.backgroundColor : 0xFF000000, 1, 0);
			e.popTarget();
		}
		return lastFrame;
	}

	static var blackCheck = Sys.getEnv("BH_PORT_BLACK_CHECK") == "1";
	var lastReal = -1;
	var blackFrames = 0;

	static function isBlack(pixels:hxd.Pixels):Bool {
		for (gy in 0...18)
			for (gx in 0...32)
				if (pixels.getPixel(Std.int((gx + 0.5) * pixels.width / 32), Std.int((gy + 0.5) * pixels.height / 18)) & 0xFFFFFF != 0)
					return false;
		return true;
	}

	function checkBlack(target:h3d.mat.Texture, rasters:Int):Void {
		var pixels = target.capturePixels();
		var black = isBlack(pixels);
		if (!black) {
			lastReal = frames;
			return;
		}
		if (lastReal < 0) return;
		blackFrames++;
		if (blackFrames <= 200)
			log("black game frame " + frames + " (last real " + lastReal + "), rasters this frame " + rasters + ", "
				+ DisplayRenderer.atlasReport() + ", drawn " + DisplayRenderer.drawn);
	}

	static var keepPresentedOn = Sys.getEnv("BH_PORT_KEEP_PRESENTED") != "0";
	var presented:h3d.mat.Texture;
	var presentedDisposes = 0;
	public static var keptFrames(default, null) = 0;

	function keepPresented(didPresent:Bool):Void {
		if (!keepPresentedOn || gpu == null || lastFrame == null) return;
		if (presented != null && (presented.width != lastFrame.width || presented.height != lastFrame.height
				|| presentedDisposes != flash.display3D.Context3D.disposes)) {
			presented.dispose();
			presented = null;
		}
		if (didPresent) {
			if (presented == null) {
				presented = new h3d.mat.Texture(lastFrame.width, lastFrame.height, [Target]);
				presented.filter = Nearest;
				presentedDisposes = flash.display3D.Context3D.disposes;
			}
			copyTexture(lastFrame, presented);
		} else if (presented != null) {
			copyTexture(presented, lastFrame);
			if (++keptFrames <= 5 || keptFrames % 600 == 0)
				log("frame " + frames + " presented nothing: the last presented picture kept (" + keptFrames + " such frames)");
		}
	}

	function copyTexture(from:h3d.mat.Texture, to:h3d.mat.Texture):Void {
		var e = h3d.Engine.getCurrent();
		var bound = e.getCurrentTarget() == lastFrame;
		if (bound) e.popTarget();
		var entered = port.engine.art.FxContext.enter();
		h3d.pass.Copy.run(from, to);
		port.engine.art.FxContext.leave(entered);
		if (bound) e.pushTarget(lastFrame);
	}

	function showLastFrame(e:h3d.Engine):Void {
		if (lastFrame != null && lastFrame.width == e.width && lastFrame.height == e.height) {
			var entered = port.engine.art.FxContext.enter();
			h3d.pass.Copy.run(lastFrame, null);
			port.engine.art.FxContext.leave(entered);
		}
	}

	var ticks = 0;
	var ticksFrames = 0;

	override function render(e:h3d.Engine):Void {
		ticks++;
		var drawStarted = haxe.Timer.stamp();
		renderTick(e);
		gapDraws += haxe.Timer.stamp() - drawStarted;
		gapTicks++;
		lastTickAt = haxe.Timer.stamp();
	}

	function renderTick(e:h3d.Engine):Void {
		GpuTrim.run(e);
		if (probe != null) {
			if (frameDue) {
				frameDue = false;
				if (Sys.getEnv("BH_PORT_GPU_PROBE") == "boot") runGameFrame();
			}
			probe.draw(e);
			if (++probeFrames % 300 == 0 || probeFrames <= 2) log("gpu probe: " + probeFrames + " frames drawn");
			return;
		}
		if (!frameDue) {
			showLastFrame(e);
			return;
		}
		frameDue = false;
		var shot = shots.get(frames);
		if (shot == null) shot = requestedShot();
		var named = pendingShot;
		if (shot == null && named != null) {
			var dir = Sys.getEnv("BH_PORT_SHOT_DIR");
			shot = (dir != null && dir != "" ? dir : ".") + "/" + named + ".png";
		} else named = null;
		pendingShot = null;
		var target = frameTarget(e);
		e.pushTarget(target);
		e.clear(e.backgroundColor != null ? e.backgroundColor : 0xFF000000, 1, 0);
		var rastersBefore = DisplayRenderer.rasters;
		runGameFrame();
		e.popTarget();
		if (blackCheck) checkBlack(target, DisplayRenderer.rasters - rastersBefore);
		showLastFrame(e);
		if (shot == null) return;
		try {
			var pixels = target.capturePixels();
			if (e.driver.hasFeature(BottomLeftCoords)) pixels.flipY();
			sys.io.File.saveBytes(shot, pixels.toPNG());
			log("shot " + shot + " at frame " + (frames - 1) + (isBlack(pixels) ? " BLACK FRAME" : "") + ": " + gpuState());
		} catch (error:Dynamic) {
			log("shot " + shot + " failed: " + Std.string(error));
		}
		#if port_smoke
		if (named != null) port.runtime.SmokeDriver.shotTaken(named);
		#end
	}

	static var pendingShot:String = null;

	static var shotRequest:String = Sys.getEnv("BH_PORT_SHOT_REQUEST");
	static var shotRequestChecks = 0;

	static function requestedShot():String {
		if (shotRequest == null || ++shotRequestChecks % 15 != 0 || !sys.FileSystem.exists(shotRequest)) return null;
		try {
			var path = StringTools.trim(sys.io.File.getContent(shotRequest));
			sys.FileSystem.deleteFile(shotRequest);
			return path != "" ? path : null;
		} catch (error:Dynamic) {
			return null;
		}
	}

	static var shots:Map<Int, String> = {
		var map = new Map<Int, String>();
		var spec = Sys.getEnv("BH_PORT_SHOTS");
		if (spec != null) for (item in spec.split(",")) {
			var at = item.lastIndexOf("@");
			if (at > 0) map.set(Std.parseInt(item.substr(at + 1)), item.substr(0, at));
		}
		map;
	};

	public static function gpuState():String {
		return gpu == null ? "no GPU backend" : "game's System.gc collections " + openfl.system.System.collections
			+ " (merged " + openfl.system.System.merged + "), driver trims " + GpuTrim.trims + " in "
			+ Std.int(GpuTrim.trimMs) + " ms, upload flushes " + UploadStats.flushes + "; GPU draws " + gpu.draws + ", skipped " + gpu.skipped
			+ (gpu.lastSkip != null ? " (last: " + gpu.lastSkip + ")" : "") + ", AGAL translations " + port.engine.agal.AgalHxsl.built
			+ "; vector draws " + flash.display.BitmapData.vectorDraws + ", GPU-drawn " + flash.display.BitmapData.vectorDrawn
			+ " (" + port.engine.art.VectorRaster.fillsDrawn + " fills, " + port.engine.art.VectorRaster.strokesDrawn + " strokes in " + Std.int(port.engine.art.VectorRaster.seconds * 1000) + " ms; 4x target pairs made " + port.engine.art.VectorRaster.targetsMade + " (" + port.engine.art.VectorRaster.largeTargetsMade + " over 512 px; " + port.engine.art.VectorRaster.tiledDraws + " draws in " + port.engine.art.VectorRaster.tilesDrawn + " tiles, " + port.engine.art.VectorRaster.fillsOutside + " fills outside, checked " + port.engine.art.VectorRaster.tileChecks + ", differing " + port.engine.art.VectorRaster.tileMismatches + "; " + port.engine.art.VectorRaster.poolFlushes + " dropped for the budget, " + port.engine.art.VectorRaster.poolFits + " draws in a larger pooled pair); onto resident bitmaps " + port.engine.art.VectorRaster.residentDraws + ", read back " + [for (k => v in port.engine.art.VectorRaster.readBackDraws) k + " " + v].join(", ") + ", " + port.engine.art.GpuBitmaps.report() + ", Stage3D uploads from resident " + GpuStage3D.residentUploads + " (targets reused " + GpuStage3D.targetsReused + ")"
				+ ", filtered layers " + port.engine.art.VectorRaster.filteredDraws + ", between frames " + port.engine.art.VectorRaster.betweenFrames + "; not drawn " + [for (k => v in port.engine.art.VectorRaster.notDrawn) k + " " + v].join(", ") + ")"
			+ (display == null ? "" : "; display list " + DisplayRenderer.drawn + " objects, " + DisplayRenderer.rasters
				+ " rasters in " + Std.int(DisplayRenderer.rasterSeconds * 1000) + " ms ("
				+ [for (k => v in DisplayRenderer.rasterReasons) k + " " + v].join(", ") + "; cache hits "
				+ DisplayRenderer.variantHits + "; kept " + Std.int(DisplayRenderer.rasterBytes / 1048576) + " MB, dropped for the budget "
				+ DisplayRenderer.rasterEvicted + "; " + DisplayRenderer.atlasReport() + "), " + DisplayRenderer.textsLaidOut
				+ " text layouts (fonts missing: " + [for (k => v in port.engine.text.TextLayout.missing) k].join(", ") + "; device fonts "
				+ port.runtime.swf.SystemFonts.loaded + " read in " + Std.int(port.runtime.swf.SystemFonts.loadMs) + " ms); "
				+ DisplayRenderer.layersDrawn + " filter/mask layers (" + DisplayRenderer.maskLayers + " shaped masks), " + DisplayRenderer.layersFiltered + " filtered (" + DisplayRenderer.layersGpuFiltered + " on the GPU, checked " + DisplayRenderer.gpuFilterChecks + ", differing " + DisplayRenderer.gpuFilterMismatches + "; on the CPU " + DisplayRenderer.cpuFilterReport() + "; " + DisplayRenderer.spareHits + " kept from an earlier screen) in "
				+ Std.int(DisplayRenderer.filterSeconds * 1000) + " ms; not drawn "
				+ [for (k => v in DisplayRenderer.notDrawn) k + " " + v].join(", "));
	}

	public static function progress():String {
		var app = Type.resolveClass("GameApp");
		var main = app != null ? Reflect.field(app, "mainInstance") : null;
		return "boot: loads " + flash.display.Loader.swfsLoaded + " SWFs (" + port.runtime.swf.SwfSymbols.registered
			+ " symbol classes, parsed in " + Std.int(port.runtime.swf.SwfLibrary.parseMs) + " ms; " + swfParts() + "), "
			+ flash.display.Loader.imagesDecoded + " images decoded, " + flash.display.Loader.imagesStandIn
			+ " as stand-ins; bitmaps " + flash.display.BitmapData.created + " made, " + flash.display.BitmapData.decoded
			+ " decoded, draws " + flash.display.BitmapData.bitmapDraws + " bitmap / " + flash.display.BitmapData.vectorDraws
			+ " vector (E4); boot load set " + bootSetState()
			+ "; game main " + (main != null ? "started" : "not started") + "; focused screen " + focusedScreen()
			+ "; " + (try menuPath(main) catch (e:Dynamic) "menu path: " + Std.string(e)) + "; " + gpuState();
	}

	static function swfParts():String {
		return "inflate " + Std.int(port.runtime.swf.SwfLibrary.inflateMs) + " ms on the main thread, "
			+ Std.int(port.runtime.swf.SwfInflate.workerMs) + " ms for " + port.runtime.swf.SwfInflate.threaded + " SWFs on "
			+ port.runtime.swf.SwfInflate.workers + " workers (waited " + Std.int(port.runtime.swf.SwfInflate.waitMs) + " ms), spill " + Std.int(port.runtime.swf.SwfLibrary.spillMs) + " ms (reads waited "
			+ Std.int(port.runtime.swf.SwfSpill.waitMs) + " ms)";
	}

	public static function archiveFiles():String {
		var loader = Type.resolveClass("ArchiveLoader");
		var files:Dynamic = loader != null ? Reflect.field(loader, "var_5359") : null;
		if (files == null) return "archive files: none";
		var vector:port.runtime.AS3Vector = files;
		var out = [];
		for (i in 0...vector.length) {
			var f:Dynamic = vector.get(i);
			out.push(Reflect.field(f, "fileName") + "/" + Reflect.field(f, "loadSet") + "/" + Reflect.field(f, "var_6640"));
		}
		return "archive files (" + out.length + "): " + out.join(", ") + "; load error " + Reflect.field(loader, "var_3819");
	}

	static function menuPath(main:Dynamic):String {
		var loader = Type.resolveClass("ArchiveLoader");
		var game:Dynamic = main != null ? Reflect.field(main, "game") : null;
		var loading:Dynamic = Reflect.field(Type.resolveClass("ScreenManager"), "var_13477");
		var steam = Type.resolveClass("SteamAir");
		var steamInstance:Dynamic = steam != null ? Reflect.field(steam, "sInstance") : null;
		return "sets loaded " + Std.string(loader != null ? Reflect.field(loader, "loadedSetCount") : null)
			+ ", game steam ready " + Std.string(game != null ? Reflect.field(game, "var_14055") : null)
			+ ", state " + Std.string(game != null ? Reflect.field(game, "var_3595") : null)
			+ ", loading screen menu-asked " + Std.string(loading != null ? Reflect.field(loading, "var_9957") : null)
			+ " timer " + Std.string(loading != null ? Reflect.field(loading, "var_13842") : null)
			+ ", steam " + (steamInstance != null ? "instance" : "none")
			+ ", main menu " + screenState(Reflect.field(Type.resolveClass("ScreenManager"), "var_10617"))
			+ ", loading screen " + screenState(Reflect.field(Type.resolveClass("ScreenManager"), "var_13477"));
	}

	var menuReached = false;

	var timelineAt = -1.0;
	var timelineFrame = 0;
	var timelineGame = 0.0;
	var timelineRender = 0.0;
	var timelineParse = 0.0;
	var timelineSwfs = 0;
	var timelineSets = "";

	function bootTimeline(now:Float, game:Float, render:Float):Void {
		if (menuReached || frames < 1) return;
		timelineGame += game;
		timelineRender += render;
		if (timelineAt < 0) {
			timelineAt = now;
			timelineFrame = frames;
		}
		var loader = Type.resolveClass("ArchiveLoader");
		var sets = Std.string(loader != null ? Reflect.field(loader, "loadedSetCount") : null);
		var changed = sets != timelineSets;
		if (!changed && now - timelineAt < 1) return;
		var parse = port.runtime.swf.SwfLibrary.parseMs - timelineParse, swfs = flash.display.Loader.swfsLoaded - timelineSwfs;
		var app = Type.resolveClass("GameApp");
		var main = app != null ? Reflect.field(app, "mainInstance") : null;
		log("boot-time: " + Std.int((now - firstFrameAt) * 1000) + " ms, frame " + frames + (changed ? " (load sets done " + sets + ")" : "")
			+ ": " + (frames - timelineFrame) + " frames in " + ms(now - timelineAt) + " ms (game " + ms(timelineGame) + ", render "
			+ ms(timelineRender) + ", between frames " + ms(now - timelineAt - timelineGame - timelineRender) + "), " + swfs
			+ " SWFs parsed in " + Std.int(parse) + " ms, " + swfParts() + ", files " + ms(flash.filesystem.FileStream.ioSeconds) + " ms so far; "
			+ (try menuPath(main) catch (e:Dynamic) "menu path: " + Std.string(e)));
		timelineAt = now;
		timelineFrame = frames;
		timelineGame = 0;
		timelineRender = 0;
		timelineParse = port.runtime.swf.SwfLibrary.parseMs;
		timelineSwfs = flash.display.Loader.swfsLoaded;
		timelineSets = sets;
	}

	function menuCheck(now:Float):Void {
		var manager = Type.resolveClass("ScreenManager");
		var menu:Dynamic = manager != null ? Reflect.field(manager, "var_10617") : null;
		if (menu == null || Reflect.getProperty(menu, "isActive") != true) return;
		menuReached = true;
		log("boot: main menu reached at frame " + frames + ", " + Std.int((now - firstFrameAt) * 1000)
			+ " ms after the first frame (focused " + focusedScreen() + ")");
	}

	static function screenState(screen:Dynamic):String {
		if (screen == null) return "null";
		return "active " + Std.string(Reflect.getProperty(screen, "isActive")) + " focus mode " + Std.string(Reflect.field(screen, "var_10316"));
	}

	static function focusedScreen():String {
		var base = Type.resolveClass("ScreenBase");
		var screen:Dynamic = base != null ? Reflect.field(base, "focusedScreen") : null;
		return screen != null ? Type.getClassName(Type.getClass(screen)) : "none";
	}

	static function bootSetState():String {
		var app = Type.resolveClass("GameApp"), loader = Type.resolveClass("ArchiveLoader");
		var set:String = app != null ? Reflect.field(app, "bootLoadSet") : null;
		if (set == null || loader == null) return "unknown";
		var loaded = Reflect.callMethod(loader, Reflect.field(loader, "isLoadSetLoaded"), [set]);
		return "\"" + set + "\" " + (loaded == true ? "loaded" : "loading");
	}

	public static function boot():Void {
		flash.utils.ByteArray.defaultEndian = flash.utils.Endian.BIG_ENDIAN;
		var started = Sys.time();
		startWatchdog();
		port.runtime.services.BuiltinExtensions.registerAll();
		if (Sys.getEnv("BH_PORT_NO_SOUND") != "1"
			&& port.runtime.services.Extensions.registered().indexOf("SoundEngineExtension") < 0) {
			port.runtime.services.NativeExtension.log = log;
			port.runtime.services.Extensions.register("SoundEngineExtension", (_) -> port.runtime.services.NativeExtension.open(
				port.runtime.services.Launch.applicationDirectory(), "SoundEngineExtension", "SoundEngineExtInitializer",
				"SoundEngineExtFinalizer"));
		}
		port.runtime.services.BuiltinExtensions.refreshRate = function():Int {
			var pinned = Std.parseInt(Sys.getEnv("BH_PORT_REFRESH_RATE") ?? "");
			var rate = pinned != null && pinned > 0 ? pinned : try {
				var mode = hxd.Window.getInstance().getCurrentDisplaySetting();
				mode != null && mode.framerate > 0 ? mode.framerate : 60;
			} catch (_:Dynamic) 60;
			log("display refresh rate for the game: " + rate + " Hz" + (pinned != null && pinned > 0 ? " (BH_PORT_REFRESH_RATE)" : ""));
			return rate;
		};
		port.runtime.net.NetGuard.log = log;
		UncaughtErrors.log = log;
		port.runtime.SmokeDriver.start(stage);
		#if port_smoke
		if (port.runtime.SmokeDriver.shooter == null) port.runtime.SmokeDriver.shooter = port.runtime.SmokeDriver.shotTaken;
		#end
		try {
			BootDocument.staticInit();
			GameApp.forceOffline = true;
			DnaTelemetry.dnaDisabled = true;
			GameApp.main();
		} catch (error:Dynamic) {
			log("uncaught in GameApp.main: " + Std.string(error) + "\n"
				+ haxe.CallStack.toString(haxe.CallStack.exceptionStack()));
		}
		log("boot: GameApp.main returned after " + Std.int((Sys.time() - started) * 1000) + " ms");
	}

	static var trace = Sys.getEnv("BH_PORT_TRACE") == "1";

	public static function gameFrame(index:Int):Void {
		frameStartedAt = Sys.time();
		currentFrame = index;
		if (FrameLoop.onError == null) FrameLoop.onError = (error, stack, where) -> frameError(currentFrame, error, stack, " [in " + where + "]");
		try {
			if (index == injectError) {
				try throw "TypeError: Error #1009: Cannot access a property or method of a null object reference. (BH_PORT_INJECT_ERROR)"
				catch (injected:Dynamic) frameError(index, injected, haxe.CallStack.toString(haxe.CallStack.exceptionStack()), " [injected]");
			}
			if (index >= throwFrom && index <= throwTo)
				throw "TypeError: Error #1009: Cannot access a property or method of a null object reference. (BH_PORT_THROW_FRAMES)";
			if (trace) log("frame " + index + ": pump");
			port.runtime.services.Pump.tick();
			if (trace) log("frame " + index + ": events");
			FrameLoop.frame();
			if (trace) log("frame " + index + ": done");
		} catch (error:Dynamic) {
			frameError(index, error, haxe.CallStack.toString(haxe.CallStack.exceptionStack()), "");
		}
		frameStartedAt = -1;
	}

	static var currentFrame = 0;

	static var throwFrom = -1;
	static var throwTo = -2;
	static var throwFramesParsed = {
		var spec = Sys.getEnv("BH_PORT_THROW_FRAMES") ?? "";
		var parts = spec.split("-");
		if (parts.length == 2 && Std.parseInt(parts[0]) != null && Std.parseInt(parts[1]) != null) {
			throwFrom = Std.parseInt(parts[0]);
			throwTo = Std.parseInt(parts[1]);
		}
		true;
	};

	static var injectError:Int = {
		var v = Std.parseInt(Sys.getEnv("BH_PORT_INJECT_ERROR") ?? "");
		v == null ? -1 : v;
	};

	static function frameError(index:Int, error:Dynamic, stack:String, where:String):Void {
		++uncaught;
		if (uncaught <= 20)
			log("uncaught in frame " + index + ": " + Std.string(error) + where + "\n" + stack);
		else if (uncaught <= 200 || uncaught % 600 == 0)
			log("uncaught in frame " + index + ": " + Std.string(error) + where + " (uncaught errors so far: " + uncaught + ")");
		if (uncaught == stopAfterErrors) {
			log("boot: stopped after " + uncaught + " uncaught errors (BH_PORT_STOP_AFTER_ERRORS)");
			log(progress());
			BootLog.flush();
			Sys.exit(5);
		}
		UncaughtErrors.dispatch(error);
	}

	public static var uncaught(default, null) = 0;

	static var stopAfterErrors:Int = {
		var v = Std.parseInt(Sys.getEnv("BH_PORT_STOP_AFTER_ERRORS"));
		v == null ? -1 : v;
	};

	var pacer = new FramePacer();
	var pacing = Sys.getEnv("BH_PORT_NO_PACING") != "1";
	var firstFrameAt = 0.0;

	static var displaySteps:Array<String> = {
		var steps = Sys.getEnv("BH_PORT_DISPLAY_TEST");
		steps == null || steps == "" ? [] : steps.split(",");
	};
	var displayStep = 0;

	function displayTest(window:hxd.Window):Void {
		if (displayStep >= displaySteps.length * 2 || frames < 120) return;
		if (frames % 60 != 0) return;
		var step = displaySteps[displayStep >> 1];
		if (displayStep & 1 == 0) {
			var started = Sys.time();
			var ok = step.indexOf("vsync") == 0 ? Display.setVsync(step == "vsync1", false)
				: step.indexOf("monitor") == 0 ? Display.setMonitor(Std.parseInt(step.substr(7)), false)
				: Display.setDisplayMode(step, false);
			log("display test: " + step + (ok ? "" : " (refused)") + " applied in " + Std.int((Sys.time() - started) * 1000)
				+ " ms");
		} else {
			log("display test: after " + step + ": window " + Std.string(window.displayMode) + " " + window.width + "x"
				+ window.height + ", vsync " + window.vsync + ", monitor " + window.currentMonitorIndex + ", stage "
				+ stage.stageWidth + "x" + stage.stageHeight);
		}
		displayStep++;
	}

	var fastTicks = 0;
	var lastTickAt = -1.0;
	public static var throttledTicks(default, null) = 0;
	static inline var OCCLUDED_TICKS = 100;
	static var idleThrottle = Sys.getEnv("BH_PORT_IDLE_THROTTLE") != "0";

	var nextPresentAt = -1.0;
	static var displayHz = 0;

	function presentCap():Float {
		if (!hxd.Window.getInstance().vsync) return stage.frameRate;
		return refreshHz();
	}

	function refreshHz():Int {
		if (displayHz <= 0) displayHz = try {
			var mode = hxd.Window.getInstance().getCurrentDisplaySetting();
			mode != null && mode.framerate > 0 ? mode.framerate : 60;
		} catch (_:Dynamic) 60;
		return displayHz;
	}

	override function update(dt:Float):Void {
		var now = haxe.Timer.stamp();
		if (lastTickAt >= 0) InputTiming.presented(now - lastTickAt, now);
		if (lastTickAt >= 0) fastTicks = now - lastTickAt < 0.001 ? fastTicks + 1 : 0;
		var due = !pacing || pacer.due(now, stage.frameRate);
		if (!due && idleThrottle && pacing) {
			var interval = 1 / Math.max(25, presentCap());
			if (nextPresentAt < 0 || now - nextPresentAt > 0.05) nextPresentAt = now;
			nextPresentAt += interval;
			while (!due && (now = haxe.Timer.stamp()) < nextPresentAt - 0.0005) {
				Sys.sleep(0);
				due = pacer.due(now, stage.frameRate);
			}
		}
		if (!due && idleThrottle && fastTicks > OCCLUDED_TICKS && hxd.Window.getInstance().vsync) {
			throttledTicks++;
			var limit = now + 0.05;
			while (!due && (now = haxe.Timer.stamp()) < limit) {
				Sys.sleep(0);
				due = pacer.due(now, stage.frameRate);
			}
		}
		if (!due) return;
		if (gpu != null && !gpuInUpdate) {
			frameDue = true;
			return;
		}
		runGameFrame();
	}

	static var longFrameMs = {
		var n = Std.parseFloat(Sys.getEnv("BH_PORT_LONG_FRAME_MS"));
		Math.isNaN(n) ? 0.0 : n;
	};

	#if bh_port_gc_marks
	@:hlNative("std", "gc_mark_stats") static function gcMarkStats(count:hl.Ref<Float>, seconds:hl.Ref<Float>):Void {}

	static function gcMarks(marks:Float, markS:Float):String {
		var nowMarks = 0.0, nowS = 0.0;
		gcMarkStats(nowMarks, nowS);
		return ", collections " + Std.int(nowMarks - marks) + " in " + Std.string(Math.round((nowS - markS) * 10000) / 10) + " ms";
	}
	#else
	static inline function gcMarks(marks:Float, markS:Float):String return "";
	#end

	var gapFrameAt = -1.0;
	var gapFrameOwn = 0.0;
	var gapDraws = 0.0;
	var gapTicks = 0;
	var gapPresent = 0.0;
	var gapEvents = 0.0;
	var gapPads = 0.0;
	var gapThread = 0.0;
	var gapScene = 0.0;
	var gapRender = 0.0;

	function logLongGap(now:Float):Void {
		if (longFrameMs > 0 && gapFrameAt >= 0 && (now - gapFrameAt) * 1000 > longFrameMs
				&& (now - gapFrameAt) > gapFrameOwn * 2) {
			var present = LoopTimes.present - gapPresent, events = LoopTimes.events - gapEvents, pads = LoopTimes.pads - gapPads;
			var thread = LoopTimes.threadEvents - gapThread, scene = LoopTimes.sceneEvents - gapScene;
			var engineRender = LoopTimes.engineRender - gapRender;
			var rest = (now - gapFrameAt) - gapFrameOwn - engineRender - present - events - thread - scene;
			log("long gap before frame " + frames + ": " + ms(now - gapFrameAt) + " ms: last frame " + ms(gapFrameOwn)
				+ ", engine.render " + ms(engineRender) + " (draws " + ms(gapDraws) + ") in " + gapTicks + " ticks, present "
				+ ms(present) + " (longest " + ms(LoopTimes.presentMax) + "), window events " + ms(events)
				+ ", thread events " + ms(thread) + " (pads " + ms(pads) + "), scene events " + ms(scene) + ", rest " + ms(rest));
		}
		gapFrameAt = now;
		gapDraws = 0;
		gapTicks = 0;
		gapPresent = LoopTimes.present;
		gapEvents = LoopTimes.events;
		gapPads = LoopTimes.pads;
		gapThread = LoopTimes.threadEvents;
		gapScene = LoopTimes.sceneEvents;
		gapRender = LoopTimes.engineRender;
		LoopTimes.presentMax = 0;
	}

	static function ms(s:Float):String {
		return Std.string(Math.round(s * 10000) / 10);
	}

	function runGameFrame():Void {
		var now = haxe.Timer.stamp();
		logLongGap(now);
		var window = hxd.Window.getInstance();
		InputTiming.frame(now, window.vsync);
		if (windowInput != null) windowInput.flush();
		HeapsPads.poll();
		var rasterS = DisplayRenderer.rasterSeconds, rasterN = DisplayRenderer.rasters;
		var filterS = DisplayRenderer.filterSeconds, syncS = port.engine.art.GpuBitmaps.syncSeconds;
		var readS = DisplayRenderer.filterReadSeconds, mathS = DisplayRenderer.filterMathSeconds;
		var layersN = DisplayRenderer.layersFiltered;
		var madeN = DisplayRenderer.targetsMade, madeB = DisplayRenderer.targetBytesMade, pooledN = DisplayRenderer.targetsPooled;
		var allocated = longFrameMs > 0 ? hl.Gc.stats().totalAllocated : 0.0;
		var extensionS = port.runtime.services.Extensions.ExtensionImpl.callSeconds;
		var fileS = flash.filesystem.FileStream.ioSeconds;
		if (longFrameMs > 0) port.runtime.services.Extensions.ExtensionImpl.takeSlowest();
		var collections = openfl.system.System.collections;
		var userMs = 0.0, kernelMs = 0.0, mcycles = 0.0, faults = 0;
		if (longFrameMs > 0) {
			ThreadProbe.frameBegin(Std.int(Math.max(40, longFrameMs / 2)));
			userMs = ThreadProbe.userMs();
			kernelMs = ThreadProbe.kernelMs();
			mcycles = ThreadProbe.mcycles();
			faults = ThreadProbe.pageFaults();
		}
		var marks = 0.0, markS = 0.0;
		#if bh_port_gc_marks
		if (longFrameMs > 0) gcMarkStats(marks, markS);
		#end
		var presentsBefore = flash.display3D.Context3D.presents;
		gameFrame(frames);
		keepPresented(flash.display3D.Context3D.presents != presentsBefore);
		var gameDone = haxe.Timer.stamp();
		if (display != null) display.render(stage);
		InputTiming.rendered();
		gapFrameOwn = haxe.Timer.stamp() - now;
		bootTimeline(now, gameDone - now, haxe.Timer.stamp() - gameDone);
		if (longFrameMs > 0) {
			ThreadProbe.frameEnd();
			var end = haxe.Timer.stamp();
			if ((end - now) * 1000 > longFrameMs) {
				log("long frame " + frames + ": " + ms(end - now) + " ms: game " + ms(gameDone - now) + ", render "
					+ ms(end - gameDone) + " (rasters " + (DisplayRenderer.rasters - rasterN) + " in "
					+ ms(DisplayRenderer.rasterSeconds - rasterS) + ", filters " + (DisplayRenderer.layersFiltered - layersN)
					+ " in " + ms(DisplayRenderer.filterSeconds - filterS) + " (read back "
					+ ms(DisplayRenderer.filterReadSeconds - readS) + ", math " + ms(DisplayRenderer.filterMathSeconds - mathS) + ")"
					+ ", read-backs " + ms(port.engine.art.GpuBitmaps.syncSeconds - syncS) + "; layers "
					+ DisplayRenderer.spareReport() + "; textures made " + (DisplayRenderer.targetsMade - madeN) + " ("
					+ Math.round((DisplayRenderer.targetBytesMade - madeB) / 104857.6) / 10 + " MB), pooled "
					+ (DisplayRenderer.targetsPooled - pooledN) + "), allocated "
					+ Math.round((hl.Gc.stats().totalAllocated - allocated) / 104857.6) / 10 + " MB, game's System.gc "
					+ (openfl.system.System.collections - collections) + gcMarks(marks, markS)
					+ ", extension calls " + ms(port.runtime.services.Extensions.ExtensionImpl.callSeconds - extensionS)
					+ " ms (slowest " + port.runtime.services.Extensions.ExtensionImpl.takeSlowest() + "), files "
					+ ms(flash.filesystem.FileStream.ioSeconds - fileS) + " ms; thread cpu user "
					+ Math.round(ThreadProbe.userMs() - userMs) + " ms, kernel " + Math.round(ThreadProbe.kernelMs() - kernelMs)
					+ " ms, " + Math.round(ThreadProbe.mcycles() - mcycles) + " Mcycles, page faults "
					+ (ThreadProbe.pageFaults() - faults) + "; native stacks " + ThreadProbe.stalls());
			}
		}
		displayTest(window);
		if (++frames == 1) {
			firstFrameAt = now;
			log("boot: first frame (GPU driver " + (h3d.Engine.getCurrent() == null ? "none" : h3d.Engine.getCurrent().driver.getDriverName(true)) + "; adapter " + GpuAdapter.describe() + ")");
			log("display: renderer " + Display.renderer + ", mode " + Display.effectiveMode() + ", vsync " + (window.vsync ? "on" : "off")
				+ ", refresh " + refreshHz() + " Hz");
		} else if (frames == 601) {
			log("boot: 600 frames in " + Std.int((now - firstFrameAt) * 1000) + " ms at frameRate " + stage.frameRate);
			log(progress());
		}
		if (!menuReached) menuCheck(now);
		if (frames % 1200 == 0) {
			log("gpu at frame " + frames + ": ticks per game frame " + Math.round(ticks / Math.max(1, frames - ticksFrames) * 10) / 10
				+ " (idle waits " + throttledTicks + "); " + gpuState() + "; shaders from the cache " + ShaderDiskCache.hits
				+ ", compiled " + ShaderDiskCache.compiled);
			ticks = 0;
			ticksFrames = frames;
			var by = port.engine.art.VectorRaster.readBackReport();
			if (by != "") log("read-back draws' targets got CPU words from: " + by);
		}
	}
}
