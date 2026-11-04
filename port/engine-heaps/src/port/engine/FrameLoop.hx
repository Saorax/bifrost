package port.engine;

class FrameLoop {
	public static var BROADCAST = ["enterFrame", "frameConstructed", "exitFrame", "render", "activate", "deactivate"];

	static var listening:Map<String, Array<flash.events.EventDispatcher>> = new Map();
	static var invalidated = false;

	public static function listen(target:flash.events.EventDispatcher, type:String):Void {
		var list = listening.get(type);
		if (list == null) listening.set(type, list = []);
		if (list.indexOf(target) < 0) list.push(target);
	}

	public static function invalidate():Void {
		invalidated = true;
	}

	public static function frame():Void {
		broadcast("enterFrame");
		timers();
		broadcast("frameConstructed");
		broadcast("exitFrame");
		advance();
		if (invalidated) {
			invalidated = false;
			broadcast("render");
		}
	}

	public static var root:flash.display.DisplayObject;

	static var lastAdvance = -1.0;

	public static function advance():Void {
		if (root == null) return;
		var now = haxe.Timer.stamp();
		var delta = lastAdvance < 0 ? 0 : Std.int((now - lastAdvance) * 1000);
		lastAdvance = now;
		@:privateAccess root.__advance(delta);
	}

	public static function timers():Void {
		#if target.threaded
		sys.thread.Thread.current().events.progress();
		#else
		@:privateAccess haxe.EntryPoint.processEvents();
		#end
	}

	public static var onError:(error:Dynamic, stack:String, where:String) -> Void = null;

	static function broadcast(type:String):Void {
		var list = listening.get(type);
		if (list == null) return;
		for (target in list.copy()) {
			if (!target.hasEventListener(type)) continue;
			var event = new flash.events.Event(type);
			event.__broadcast = true;
			if (onError == null) {
				target.dispatchEvent(event);
				continue;
			}
			try {
				target.dispatchEvent(event);
			} catch (error:Dynamic) {
				onError(error, haxe.CallStack.toString(haxe.CallStack.exceptionStack()), type + " of " + Type.getClassName(Type.getClass(target)));
			}
		}
	}
}
