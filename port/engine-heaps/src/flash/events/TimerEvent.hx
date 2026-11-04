package flash.events;

class TimerEvent extends flash.events.Event {
	public static var TIMER:flash.events.EventType<flash.events.TimerEvent> = "timer";
	public static var TIMER_COMPLETE:flash.events.EventType<flash.events.TimerEvent> = "timerComplete";

	public function new(type:String, bubbles:Bool = false, cancelable:Bool = false) {
		super(type, bubbles, cancelable);
	}

	override public function clone():flash.events.TimerEvent {
		return new TimerEvent(type, bubbles, cancelable);
	}

	override public function toString():String {
		return formatToString("TimerEvent", "type", "bubbles", "cancelable", "eventPhase");
	}

	public function updateAfterEvent():Void {}
}
