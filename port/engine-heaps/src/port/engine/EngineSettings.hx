package port.engine;

class EngineSettings {
	public static final RENDERERS = ["dx11", "dx12", "vulkan"];
	public static final DISPLAY_MODES = ["game", "windowed", "borderless", "fullscreen"];

	public var renderer:String = "dx11";
	public var displayMode:String = "game";
	public var vsync:Bool = true;
	public var monitor:Int = -1;

	public function new() {}

	public function copy():EngineSettings {
		var s = new EngineSettings();
		s.renderer = renderer;
		s.displayMode = displayMode;
		s.vsync = vsync;
		s.monitor = monitor;
		return s;
	}

	public static function parse(text:Null<String>):EngineSettings {
		var s = new EngineSettings();
		if (text == null) return s;
		var data:Dynamic = try haxe.Json.parse(text) catch (_:Dynamic) null;
		if (data == null || Type.typeof(data) != TObject) return s;
		var renderer:Dynamic = Reflect.field(data, "renderer");
		if (Std.isOfType(renderer, String) && RENDERERS.indexOf(renderer) >= 0) s.renderer = renderer;
		var mode:Dynamic = Reflect.field(data, "displayMode");
		if (Std.isOfType(mode, String) && DISPLAY_MODES.indexOf(mode) >= 0) s.displayMode = mode;
		var vsync:Dynamic = Reflect.field(data, "vsync");
		if (Std.isOfType(vsync, Bool)) s.vsync = vsync;
		var monitor:Dynamic = Reflect.field(data, "monitor");
		if (Std.isOfType(monitor, Int) && (monitor : Int) >= -1) s.monitor = monitor;
		return s;
	}

	public function toJson():String {
		return haxe.Json.stringify({renderer: renderer, displayMode: displayMode, vsync: vsync, monitor: monitor}, null, "  ");
	}

	public static function load(path:String):EngineSettings {
		return parse(try sys.io.File.getContent(path) catch (_:Dynamic) null);
	}

	public function save(path:String):Bool {
		try {
			var dir = haxe.io.Path.directory(path);
			if (dir != "" && !sys.FileSystem.exists(dir)) sys.FileSystem.createDirectory(dir);
			sys.io.File.saveContent(path, toJson());
			return true;
		} catch (_:Dynamic) {
			return false;
		}
	}
}
