package flash.events;

class KeyboardEvent extends flash.events.Event {
	public static var KEY_DOWN:flash.events.EventType<flash.events.KeyboardEvent> = "keyDown";
	public static var KEY_UP:flash.events.EventType<flash.events.KeyboardEvent> = "keyUp";
	public var altKey:Bool;
	public var charCode:Int;
	public var commandKey:Bool;
	public var controlKey:Bool;
	public var ctrlKey:Bool;
	public var keyCode:Int;
	public var keyLocation:flash.ui.KeyLocation;
	public var shiftKey:Bool;
	override public function clone():flash.events.KeyboardEvent {
		return new KeyboardEvent(type, bubbles, cancelable, charCode, keyCode, keyLocation, ctrlKey, altKey, shiftKey,
			controlKey, commandKey);
	}

	override public function toString():String {
		return formatToString("KeyboardEvent", "type", "bubbles", "cancelable", "eventPhase", "charCode", "keyCode",
			"keyLocation", "ctrlKey", "altKey", "shiftKey");
	}

	public function updateAfterEvent():Void {}

	public function new(type:String, bubbles:Bool = false, cancelable:Bool = false, charCodeValue:Int = 0,
			keyCodeValue:Int = 0, ?keyLocationValue:flash.ui.KeyLocation, ctrlKeyValue:Bool = false, altKeyValue:Bool = false,
			shiftKeyValue:Bool = false, controlKeyValue:Bool = false, commandKeyValue:Bool = false) {
		super(type, bubbles, cancelable);
		charCode = charCodeValue;
		keyCode = keyCodeValue;
		keyLocation = keyLocationValue == null ? flash.ui.KeyLocation.STANDARD : keyLocationValue;
		ctrlKey = ctrlKeyValue;
		altKey = altKeyValue;
		shiftKey = shiftKeyValue;
		controlKey = controlKeyValue;
		commandKey = commandKeyValue;
	}
}
