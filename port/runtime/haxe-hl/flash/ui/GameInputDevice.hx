package flash.ui;

import port.runtime.input.PadHandle;

class GameInputDevice extends openfl.events.EventDispatcher {
    public static inline var XINPUT_NAME = "Xbox 360 Controller (XInput STANDARD GAMEPAD)";
    public static inline var DUALSENSE_NAME = "DualSense Wireless Controller";
    public static inline var DUALSHOCK4_NAME = "Wireless Controller";

    public var enabled:Bool = false;
    public var sampleInterval:Int = 0;
    public var id(default, null):String;
    public var name(default, null):String;
    public var numControls(get, never):Int;

    var controls:Array<GameInputControl> = [];
    var pad:PadHandle;
    var playStation:Bool;

    static final XINPUT_BUTTONS = [
        "A" => "BUTTON_4", "B" => "BUTTON_5", "X" => "BUTTON_6",
        "Y" => "BUTTON_7", "LEFT_SHOULDER" => "BUTTON_8",
        "RIGHT_SHOULDER" => "BUTTON_9", "BACK" => "BUTTON_12",
        "START" => "BUTTON_13", "LEFT_STICK" => "BUTTON_14",
        "RIGHT_STICK" => "BUTTON_15", "DPAD_UP" => "BUTTON_16",
        "DPAD_DOWN" => "BUTTON_17", "DPAD_LEFT" => "BUTTON_18",
        "DPAD_RIGHT" => "BUTTON_19"
    ];
    static final PLAYSTATION_BUTTONS = [
        "A" => "BUTTON_11", "B" => "BUTTON_12", "X" => "BUTTON_10",
        "Y" => "BUTTON_13", "LEFT_SHOULDER" => "BUTTON_14",
        "RIGHT_SHOULDER" => "BUTTON_15", "BACK" => "BUTTON_23",
        "START" => "BUTTON_19", "LEFT_STICK" => "BUTTON_20",
        "RIGHT_STICK" => "BUTTON_21", "DPAD_UP" => "BUTTON_6",
        "DPAD_DOWN" => "BUTTON_7", "DPAD_LEFT" => "BUTTON_8",
        "DPAD_RIGHT" => "BUTTON_9"
    ];

    public static function airName(padName:String):String {
        var n = padName == null ? "" : padName.toUpperCase();
        if (n.indexOf("PS5") >= 0 || n.indexOf("DUALSENSE") >= 0) return DUALSENSE_NAME;
        if (n.indexOf("PS4") >= 0 || n.indexOf("DUALSHOCK") >= 0) return DUALSHOCK4_NAME;
        return XINPUT_NAME;
    }

    @:allow(flash.ui.GameInput)
    function new(pad:PadHandle, ?testName:String) {
        super();
        this.pad = pad;
        id = pad != null ? "port-gamepad-" + pad.id : "port-virtual-pad-" + (++virtualPads);
        name = pad != null ? airName(pad.name) : testName;
        playStation = name != XINPUT_NAME;
        if (playStation) {
            for (i in 0...6) controls.push(new GameInputControl(this, "AXIS_" + i, -1, 1));
            for (i in 6...24) controls.push(new GameInputControl(this, "BUTTON_" + i, 0, 1));
        } else {
            for (i in 0...4) controls.push(new GameInputControl(this, "AXIS_" + i, -1, 1));
            for (i in 4...20) controls.push(new GameInputControl(this, "BUTTON_" + i, 0, 1));
        }
        if (pad == null) return;
        var buttons = playStation ? PLAYSTATION_BUTTONS : XINPUT_BUTTONS;
        pad.onButton = function(button, down) set(buttons.get(button), down ? 1 : 0);
        pad.onAxis = function(axis, value) {
            if (playStation) {
                switch (axis) {
                    case "LEFT_X": set("AXIS_0", value);
                    case "LEFT_Y": set("AXIS_1", value);
                    case "RIGHT_X": set("AXIS_2", value);
                    case "RIGHT_Y": set("AXIS_5", value);
                    case "TRIGGER_LEFT": set("BUTTON_16", value >= 0.25 ? 1 : 0);
                    case "TRIGGER_RIGHT": set("BUTTON_17", value >= 0.25 ? 1 : 0);
                    default:
                }
            } else {
                switch (axis) {
                    case "LEFT_X": set("AXIS_0", value);
                    case "LEFT_Y": set("AXIS_1", -value);
                    case "RIGHT_X": set("AXIS_2", value);
                    case "RIGHT_Y": set("AXIS_3", -value);
                    case "TRIGGER_LEFT": set("BUTTON_10", value < 0 ? 0 : value);
                    case "TRIGGER_RIGHT": set("BUTTON_11", value < 0 ? 0 : value);
                    default:
                }
            }
        };
    }

    function set(controlId:String, value:Float):Void {
        if (controlId == null) return;
        for (control in controls) {
            if (control.id == controlId) {
                if (control.value == value) return;
                @:privateAccess control.set(value);
                if (cachedIds != null && cachedIds.indexOf(controlId) >= 0) record();
                return;
            }
        }
    }

    static var virtualPads = 0;

    public var samplesRead(default, null):Int = 0;

    function get_numControls():Int return controls.length;

    public function getControlAt(i:Int):GameInputControl {
        return i >= 0 && i < controls.length ? controls[i] : null;
    }

    var cachedIds:Array<String> = null;
    var cachedControls:Array<GameInputControl> = [];
    var maxSamples = 0;
    var samples:Array<Array<Float>> = [];
    var spare:Array<Array<Float>> = [];

    function record():Void {
        var sample = spare.length > 0 ? spare.pop() : [];
        sample.resize(0);
        for (control in cachedControls) sample.push(control.value);
        samples.push(sample);
        while (samples.length > maxSamples && samples.length > 1) spare.push(samples.shift());
    }

    public function startCachingSamples(numSamples:Int, controls:Vector<String>):Void {
        var store:port.runtime.AS3Vector = cast controls;
        cachedIds = [for (item in store.data) Std.string(item)];
        cachedControls = [];
        for (controlId in cachedIds) {
            var found:GameInputControl = null;
            for (control in this.controls) if (control.id == controlId) found = control;
            cachedControls.push(found != null ? found : new GameInputControl(this, controlId, 0, 1));
        }
        maxSamples = numSamples > 0 ? numSamples : 1;
        samples = [];
    }

    public function stopCachingSamples():Void {
        cachedIds = null;
        cachedControls = [];
        samples = [];
    }

    public function getCachedSamples(data:openfl.utils.ByteArray, append:Bool = false):Int {
        if (cachedIds == null || data == null) return 0;
        samplesRead++;
        record();
        var start = append ? data.length : 0;
        if (!append) data.length = 0;
        data.position = start;
        for (sample in samples) for (value in sample) data.writeDouble(value);
        data.position = start;
        var count = samples.length;
        for (sample in samples) spare.push(sample);
        samples.resize(0);
        return count;
    }
}
