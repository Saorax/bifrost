package flash.events;

class ThrottleEvent extends openfl.events.Event {
    public static inline var THROTTLE = "throttle";

    public var state(default, null):String;
    public var targetFrameRate(default, null):Float;

    public function new(type:String, bubbles:Bool = false, cancelable:Bool = false, state:String = null,
            targetFrameRate:Float = 0) {
        super(type, bubbles, cancelable);
        this.state = state;
        this.targetFrameRate = targetFrameRate;
    }

    override public function clone():openfl.events.Event {
        return new ThrottleEvent(type, bubbles, cancelable, state, targetFrameRate);
    }
}
