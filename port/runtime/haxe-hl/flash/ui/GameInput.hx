package flash.ui;

import flash.events.GameInputEvent;
import port.runtime.input.Pads;

class GameInput extends openfl.events.EventDispatcher {
    public static var isSupported(default, null):Bool = true;
    public static var numDevices(get, never):Int;

    static var devices:Array<GameInputDevice> = null;
    static var instances:Array<GameInput> = [];

    public function new() {
        super();
        start();
        instances.push(this);
    }

    static function start():Void {
        if (devices != null) return;
        devices = [];
        if (Pads.source != null) Pads.source(add);
    }

    static function add(pad:port.runtime.input.PadHandle, announce:Bool):Void {
        var device = new GameInputDevice(pad);
        devices.push(device);
        pad.onDisconnect = function() {
            devices.remove(device);
            for (input in instances) input.dispatchEvent(new GameInputEvent(GameInputEvent.DEVICE_REMOVED, false, false, device));
        };
        if (announce) {
            for (input in instances) input.dispatchEvent(new GameInputEvent(GameInputEvent.DEVICE_ADDED, false, false, device));
        }
    }

    static function get_numDevices():Int {
        start();
        return devices.length;
    }

    public static function getDeviceAt(index:Int):GameInputDevice {
        start();
        return index >= 0 && index < devices.length ? devices[index] : null;
    }
}
