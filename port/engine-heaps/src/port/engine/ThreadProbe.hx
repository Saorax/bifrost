package port.engine;

class ThreadProbe {
	@:hlNative("bhsound", "thread_user_ms") public static function userMs():Float return 0.0;

	@:hlNative("bhsound", "thread_kernel_ms") public static function kernelMs():Float return 0.0;

	@:hlNative("bhsound", "thread_mcycles") public static function mcycles():Float return 0.0;

	@:hlNative("bhsound", "page_faults") public static function pageFaults():Int return 0;

	@:hlNative("bhsound", "stall_start") static function stallStart(thresholdMs:Int):Int return 0;

	@:hlNative("bhsound", "stall_frame") static function stallFrame(begin:Int):Void {}

	@:hlNative("bhsound", "stall_take") static function stallTake():hl.Bytes return null;

	static var started = false;

	public static function frameBegin(thresholdMs:Int):Void {
		if (!started) {
			started = true;
			stallStart(thresholdMs);
		}
		stallFrame(1);
	}

	public static function frameEnd():Void {
		stallFrame(0);
	}

	public static function stalls():String {
		var b = stallTake();
		return b == null ? "" : @:privateAccess String.fromUTF8(b);
	}
}
