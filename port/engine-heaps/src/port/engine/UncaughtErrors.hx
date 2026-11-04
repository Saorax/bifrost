package port.engine;

class UncaughtErrors {
	public static var log:String->Void = null;

	public static var dispatched(default, null) = 0;

	static var inside = false;

	public static var enabled = #if sys Sys.getEnv("BH_PORT_UNCAUGHT_EVENTS") != "0" #else true #end;

	public static function dispatch(error:Dynamic):Void {
		if (inside || !enabled) return;
		var target = flash.display.DisplayObject.rootLoaderInfo.uncaughtErrorEvents;
		if (target == null || !target.hasEventListener(flash.events.UncaughtErrorEvent.UNCAUGHT_ERROR)) return;
		inside = true;
		try {
			var value:Dynamic = try port.runtime.As3.catchError(error) catch (thrown:Dynamic) thrown;
			dispatched++;
			target.dispatchEvent(new flash.events.UncaughtErrorEvent(flash.events.UncaughtErrorEvent.UNCAUGHT_ERROR, true, true,
				value));
		} catch (failed:Dynamic) {
			if (log != null) log("an uncaught error's handler threw: " + Std.string(failed));
		}
		inside = false;
	}
}
