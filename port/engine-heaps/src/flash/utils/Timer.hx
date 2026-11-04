package flash.utils;

class Timer extends flash.events.EventDispatcher {
	public var currentCount(default, null):Int = 0;
	public var delay(default, set):Float;
	public var repeatCount:Int;
	public var running(default, null):Bool = false;

	var timer:haxe.Timer;

	public function new(delay:Float, repeatCount:Int = 0) {
		super();
		if (Math.isNaN(delay) || delay < 0) throw new flash.errors.Error("The delay specified is negative or not a finite number.", 2066);
		this.delay = delay;
		this.repeatCount = repeatCount;
	}

	function set_delay(value:Float):Float {
		delay = value;
		if (running) {
			stop();
			start();
		}
		return value;
	}

	public function start():Void {
		if (running) return;
		running = true;
		timer = new haxe.Timer(Std.int(Math.max(1, delay)));
		timer.run = tick;
	}

	public function stop():Void {
		running = false;
		if (timer != null) {
			timer.stop();
			timer = null;
		}
	}

	public function reset():Void {
		stop();
		currentCount = 0;
	}

	function tick():Void {
		if (!running) return;
		currentCount++;
		var complete = repeatCount > 0 && currentCount >= repeatCount;
		if (complete) stop();
		dispatchEvent(new flash.events.TimerEvent(flash.events.TimerEvent.TIMER));
		if (complete) dispatchEvent(new flash.events.TimerEvent(flash.events.TimerEvent.TIMER_COMPLETE));
	}
}
