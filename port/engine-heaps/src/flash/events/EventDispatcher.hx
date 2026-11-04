package flash.events;

class EventDispatcher implements flash.events.IEventDispatcher {
	@:noCompletion var __target:IEventDispatcher;
	@:noCompletion var __listeners:Map<String, Array<Listener>>;

	public function new(?target:flash.events.IEventDispatcher) {
		__target = target;
	}

	public function addEventListener<T>(type:flash.events.EventType<T>, listener:T -> Void, useCapture:Bool = false,
			priority:Int = 0, useWeakReference:Bool = false):Void {
		if (listener == null) return;
		if (port.engine.FrameLoop.BROADCAST.indexOf(type) >= 0 && Std.isOfType(this, flash.display.DisplayObject))
			port.engine.FrameLoop.listen(this, type);
		var capture = useCapture;
		if (__listeners == null) __listeners = new Map();
		var list = __listeners.get(type);
		if (list == null) __listeners.set(type, list = []);
		for (l in list) if (l.capture == capture && same(l.call, listener)) return;
		var entry = new Listener(cast listener, capture, priority);
		var at = list.length;
		while (at > 0 && list[at - 1].priority < entry.priority) at--;
		var next = list.copy();
		next.insert(at, entry);
		__listeners.set(type, next);
	}

	static function same(a:Dynamic, b:Dynamic):Bool {
		return Reflect.compareMethods(a, b) #if hl || Reflect.compare(a, b) == 0 #end;
	}

	public function removeEventListener<T>(type:flash.events.EventType<T>, listener:T -> Void, useCapture:Bool = false):Void {
		var list = __listeners == null ? null : __listeners.get(type);
		if (list == null) return;
		var capture = useCapture;
		for (i in 0...list.length) {
			if (list[i].capture == capture && same(list[i].call, listener)) {
				var next = list.copy();
				next.splice(i, 1);
				__listeners.set(type, next);
				return;
			}
		}
	}

	public function dispatchEvent(event:flash.events.Event):Bool {
		if (event.target != null) event = event.clone();
		event.target = __target != null ? __target : this;
		var path:Array<EventDispatcher> = null;
		if (Std.isOfType(this, flash.display.DisplayObject)) {
			var up:flash.display.DisplayObject = (cast this : flash.display.DisplayObject).parent;
			if (!event.bubbles) {
				var u = up;
				while (u != null && (u.__listeners == null || !u.__listeners.exists(event.type))) u = u.parent;
				if (u == null) up = null;
			}
			while (up != null) {
				if (path == null) path = [];
				path.push(up);
				up = up.parent;
			}
		}
		if (path != null) {
			event.eventPhase = flash.events.EventPhase.CAPTURING_PHASE;
			var i = path.length;
			while (i-- > 0) {
				path[i].__invoke(event, true);
				if (event.__stopped) return !event.isDefaultPrevented();
			}
		}
		event.eventPhase = flash.events.EventPhase.AT_TARGET;
		__invoke(event, false);
		if (path != null && event.bubbles && !event.__stopped) {
			event.eventPhase = flash.events.EventPhase.BUBBLING_PHASE;
			for (node in path) {
				node.__invoke(event, false);
				if (event.__stopped) break;
			}
		}
		return !event.isDefaultPrevented();
	}

	@:noCompletion public function __invoke(event:flash.events.Event, capture:Bool):Bool {
		var list = __listeners == null ? null : __listeners.get(event.type);
		if (list == null) return true;
		event.currentTarget = __target != null ? __target : this;
		for (l in list) {
			if (l.capture != capture) continue;
			if (event.__broadcast && __listeners.get(event.type).indexOf(l) < 0) continue;
			l.call(event);
			if (event.__stoppedNow) return false;
		}
		return true;
	}

	public function hasEventListener(type:String):Bool {
		var list = __listeners == null ? null : __listeners.get(type);
		return list != null && list.length > 0;
	}

	public function toString():String {
		return "[object " + Type.getClassName(Type.getClass(this)).split(".").pop() + "]";
	}

	public function willTrigger(type:String):Bool {
		return hasEventListener(type);
	}
}

private class Listener {
	public var call:(Dynamic) -> Void;
	public var capture:Bool;
	public var priority:Int;

	public function new(call:(Dynamic) -> Void, capture:Bool, priority:Int) {
		this.call = call;
		this.capture = capture;
		this.priority = priority;
	}
}
