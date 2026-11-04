package flash.events;

class GameInputEvent extends openfl.events.Event {
    public static inline var DEVICE_ADDED = "deviceAdded";
    public static inline var DEVICE_REMOVED = "deviceRemoved";
    public static inline var DEVICE_UNUSABLE = "deviceUnusable";

    public var device(default, null):flash.ui.GameInputDevice;

    public function new(type:String, bubbles:Bool = false, cancelable:Bool = false, ?device:flash.ui.GameInputDevice) {
        super(type, bubbles, cancelable);
        this.device = device;
    }

    override public function clone():openfl.events.Event {
        return new GameInputEvent(type, bubbles, cancelable, device);
    }
}
