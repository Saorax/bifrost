package openfl.system;

class System {
	public static var totalMemory(get, never):Int;
	public static var totalMemoryNumber(get, never):Float;
	public static var useCodePage:Bool = false;
	public static var vmVersion(get, never):String;

	public static var collections(default, null) = 0;

	static function get_totalMemory():Int
		return Std.int(hl.Gc.stats().currentMemory);

	static function get_totalMemoryNumber():Float
		return hl.Gc.stats().currentMemory;

	static function get_vmVersion():String
		return "1.0.0";

	public static function disposeXML(node:Dynamic):Void {}

	public static function exit(code:Int):Void {
		port.engine.BootLog.flush();
		Sys.exit(code);
	}

	public static var merged(default, null) = 0;

	static var lastFrame = -1;

	public static function gc():Void {
		var frame = hxd.Timer.frameCount;
		if (frame == lastFrame) {
			merged++;
			return;
		}
		lastFrame = frame;
		collections++;
		hl.Gc.major();
		port.engine.GpuTrim.request();
		port.engine.ShaderDiskCache.flush();
	}

	public static function pause():Void {}

	public static function resume():Void {}

	public static function setClipboard(string:String):Void {}
}
