package flash.events;

class Event {
	public static var ACTIVATE:flash.events.EventType<flash.events.Event> = "activate";
	public static var ADDED:flash.events.EventType<flash.events.Event> = "added";
	public static var ADDED_TO_STAGE:flash.events.EventType<flash.events.Event> = "addedToStage";
	public static var CANCEL:flash.events.EventType<flash.events.Event> = "cancel";
	public static var CHANGE:flash.events.EventType<flash.events.Event> = "change";
	public static var CLEAR:flash.events.EventType<flash.events.Event> = "clear";
	public static var CLOSING:flash.events.EventType<flash.events.Event> = "closing";
	public static var CLOSE:flash.events.EventType<flash.events.Event> = "close";
	public static var COMPLETE:flash.events.EventType<flash.events.Event> = "complete";
	public static var CONNECT:flash.events.EventType<flash.events.Event> = "connect";
	public static var CONTEXT3D_CREATE:flash.events.EventType<flash.events.Event> = "context3DCreate";
	public static var COPY:flash.events.EventType<flash.events.Event> = "copy";
	public static var CUT:flash.events.EventType<flash.events.Event> = "cut";
	public static var DEACTIVATE:flash.events.EventType<flash.events.Event> = "deactivate";
	public static var ENTER_FRAME:flash.events.EventType<flash.events.Event> = "enterFrame";
	public static var EXIT_FRAME:flash.events.EventType<flash.events.Event> = "exitFrame";
	public static var EXITING:flash.events.EventType<flash.events.Event> = "exiting";
	public static var FRAME_CONSTRUCTED:flash.events.EventType<flash.events.Event> = "frameConstructed";
	public static var FRAME_LABEL:flash.events.EventType<flash.events.Event> = "frameLabel";
	public static var FULLSCREEN:flash.events.EventType<flash.events.Event> = "fullScreen";
	public static var ID3:flash.events.EventType<flash.events.Event> = "id3";
	public static var INIT:flash.events.EventType<flash.events.Event> = "init";
	public static var MOUSE_LEAVE:flash.events.EventType<flash.events.Event> = "mouseLeave";
	public static var OPEN:flash.events.EventType<flash.events.Event> = "open";
	public static var PASTE:flash.events.EventType<flash.events.Event> = "paste";
	public static var REMOVED:flash.events.EventType<flash.events.Event> = "removed";
	public static var REMOVED_FROM_STAGE:flash.events.EventType<flash.events.Event> = "removedFromStage";
	public static var RENDER:flash.events.EventType<flash.events.Event> = "render";
	public static var RESIZE:flash.events.EventType<flash.events.Event> = "resize";
	public static var SCROLL:flash.events.EventType<flash.events.Event> = "scroll";
	public static var SELECT:flash.events.EventType<flash.events.Event> = "select";
	public static var SELECT_ALL:flash.events.EventType<flash.events.Event> = "selectAll";
	public static var SOUND_COMPLETE:flash.events.EventType<flash.events.Event> = "soundComplete";
	public static var TAB_CHILDREN_CHANGE:flash.events.EventType<flash.events.Event> = "tabChildrenChange";
	public static var TAB_ENABLED_CHANGE:flash.events.EventType<flash.events.Event> = "tabEnabledChange";
	public static var TAB_INDEX_CHANGE:flash.events.EventType<flash.events.Event> = "tabIndexChange";
	public static var TEXTURE_READY:flash.events.EventType<flash.events.Event> = "textureReady";
	public static var UNLOAD:flash.events.EventType<flash.events.Event> = "unload";
	public var bubbles:Bool;
	public var cancelable:Bool;
	public var currentTarget:flash.utils.Object;
	public var eventPhase:flash.events.EventPhase;
	public var target:flash.utils.Object;
	public var type:String;
	@:noCompletion public var __stopped = false;
	@:noCompletion public var __stoppedNow = false;
	@:noCompletion public var __broadcast = false;
	@:noCompletion public var __prevented = false;

	public function clone():flash.events.Event {
		return new Event(type, bubbles, cancelable);
	}

	public function formatToString(className:String, args:haxe.Rest<String>):String {
		var parts = [for (name in args) name + "=" + quoted(Reflect.getProperty(this, name))];
		return "[" + className + (parts.length > 0 ? " " + parts.join(" ") : "") + "]";
	}

	static function quoted(value:Dynamic):String {
		return Std.isOfType(value, String) ? '"' + value + '"' : Std.string(value);
	}

	public function isDefaultPrevented():Bool {
		return __prevented;
	}

	public function preventDefault():Void {
		if (cancelable) __prevented = true;
	}

	public function stopImmediatePropagation():Void {
		__stopped = true;
		__stoppedNow = true;
	}

	public function stopPropagation():Void {
		__stopped = true;
	}

	public function toString():String {
		return formatToString("Event", "type", "bubbles", "cancelable", "eventPhase");
	}

	public function new(type:String, bubbles:Bool = false, cancelable:Bool = false) {
		this.type = type;
		this.bubbles = bubbles;
		this.cancelable = cancelable;
		eventPhase = flash.events.EventPhase.AT_TARGET;
	}
}
