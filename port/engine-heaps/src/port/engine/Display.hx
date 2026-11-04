package port.engine;

class Display {
	public static var renderer(default, null):String = runningRenderer();

	static function runningRenderer():String {
		#if dx12
		return "dx12";
		#elseif hldx
		try {
			for (dir in [haxe.io.Path.directory(Sys.programPath()), Sys.getCwd()])
				if (dir != null && dir != "" && sys.FileSystem.exists(haxe.io.Path.join([dir, "d3d11.dll"])))
					return "vulkan";
		} catch (e:Dynamic) {}
		return "dx11";
		#elseif hlsdl
		return "opengl";
		#else
		return "none";
		#end
	}

	public static var settings(default, null):EngineSettings = new EngineSettings();

	public static var applier:Null<(mode:String, vsync:Bool, monitor:Int) -> Void> = null;

	static var path:Null<String> = null;
	static var saved:EngineSettings = new EngineSettings();
	static var gameFullScreen = false;

	public static function start(settingsPath:Null<String>, ?apply:(mode:String, vsync:Bool, monitor:Int) -> Void):Void {
		path = settingsPath;
		saved = settingsPath == null ? new EngineSettings() : EngineSettings.load(settingsPath);
		settings = saved.copy();
		applier = apply;
		gameFullScreen = false;
		applyNow();
	}

	public static function effectiveMode():String {
		if (settings.displayMode != "game") return settings.displayMode;
		return gameFullScreen ? "borderless" : "windowed";
	}

	public static function gameDisplayState(fullScreen:Bool):Void {
		if (fullScreen == gameFullScreen) return;
		gameFullScreen = fullScreen;
		if (settings.displayMode == "game") applyNow();
	}

	public static function setDisplayMode(mode:String, persist:Bool = true):Bool {
		if (EngineSettings.DISPLAY_MODES.indexOf(mode) < 0) return false;
		return change(s -> s.displayMode = mode, persist);
	}

	public static function setVsync(on:Bool, persist:Bool = true):Bool {
		return change(s -> s.vsync = on, persist);
	}

	public static function setMonitor(index:Int, persist:Bool = true):Bool {
		if (index < -1) return false;
		return change(s -> s.monitor = index, persist);
	}

	public static function setRenderer(name:String, persist:Bool = true):Bool {
		if (EngineSettings.RENDERERS.indexOf(name) < 0) return false;
		settings.renderer = name;
		if (persist) {
			saved.renderer = name;
			if (path != null) saved.save(path);
		}
		return true;
	}

	static function change(set:EngineSettings->Void, persist:Bool):Bool {
		set(settings);
		if (persist) {
			set(saved);
			if (path != null) saved.save(path);
		}
		applyNow();
		return true;
	}

	static function applyNow():Void {
		if (applier != null) applier(effectiveMode(), settings.vsync, settings.monitor);
	}
}
