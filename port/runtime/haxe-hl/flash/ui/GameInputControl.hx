package flash.ui;

class GameInputControl extends openfl.events.EventDispatcher {
    public var device(default, null):GameInputDevice;
    public var id(default, null):String;
    public var minValue(default, null):Float;
    public var maxValue(default, null):Float;
    public var value(default, null):Float = 0;

    public function new(device:GameInputDevice, id:String, minValue:Float, maxValue:Float) {
        super();
        this.device = device;
        this.id = id;
        this.minValue = minValue;
        this.maxValue = maxValue;
    }

    @:allow(flash.ui.GameInputDevice)
    function set(v:Float):Void {
        value = v;
    }
}
