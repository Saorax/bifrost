package port.engine;

import port.runtime.input.PadHandle;

class HeapsPads {
	static final BUTTONS = ["A", "B", "X", "Y", "LEFT_SHOULDER", "RIGHT_SHOULDER", "BACK", "START", "LEFT_STICK",
		"RIGHT_STICK", "DPAD_UP", "DPAD_DOWN", "DPAD_LEFT", "DPAD_RIGHT"];
	static final AXES = ["LEFT_X", "LEFT_Y", "RIGHT_X", "RIGHT_Y", "TRIGGER_LEFT", "TRIGGER_RIGHT"];

	static var pads:Array<{pad:hxd.Pad, handle:PadHandle, last:Array<Float>, changedAt:Float}> = [];

	public static function start(connected:(pad:PadHandle, announce:Bool) -> Void):Void {
		var starting = true;
		flash.ui.GameInputDevice.onRead = function() {
			if (InputTiming.waitingForRead) InputTiming.gameRead(haxe.Timer.stamp());
		};
		hxd.Pad.wait(function(pad) {
			var handle = new PadHandle(pad.index, pad.name);
			var entry = {pad: pad, handle: handle, last: [for (_ in 0...BUTTONS.length + AXES.length) 0.0], changedAt: -1.0};
			pads.push(entry);
			BootLog.log("input: pad " + pad.index + " connected" + (starting ? " (at start)" : "") + ": " + pad.name);
			pad.onDisconnect = function() {
				BootLog.log("input: pad " + pad.index + " disconnected: " + pad.name);
				pads.remove(entry);
				handle.onDisconnect();
			};
			connected(handle, !starting);
		});
		@:privateAccess hxd.Pad.syncPads();
		starting = false;
	}

	static function index(config:hxd.Pad.PadConfig, name:String):Int {
		return switch (name) {
			case "A": config.A;
			case "B": config.B;
			case "X": config.X;
			case "Y": config.Y;
			case "LEFT_SHOULDER": config.LB;
			case "RIGHT_SHOULDER": config.RB;
			case "BACK": config.back;
			case "START": config.start;
			case "LEFT_STICK": config.analogClick;
			case "RIGHT_STICK": config.ranalogClick;
			case "DPAD_UP": config.dpadUp;
			case "DPAD_DOWN": config.dpadDown;
			case "DPAD_LEFT": config.dpadLeft;
			case "DPAD_RIGHT": config.dpadRight;
			case "LEFT_X": config.analogX;
			case "LEFT_Y": config.analogY;
			case "RIGHT_X": config.ranalogX;
			case "RIGHT_Y": config.ranalogY;
			case "TRIGGER_LEFT": config.LT;
			case "TRIGGER_RIGHT": config.RT;
			default: -1;
		}
	}

	static inline function side(v:Float):Int {
		return v >= 0.5 ? 1 : v <= -0.5 ? -1 : 0;
	}

	public static function poll():Void {
		for (entry in pads.copy()) {
			var pad = entry.pad, config = entry.pad.config;
			var changed = false;
			for (i in 0...BUTTONS.length) {
				var at = index(config, BUTTONS[i]);
				var down = at >= 0 && pad.buttons[at] == true ? 1.0 : 0.0;
				if (down != entry.last[i]) {
					changed = true;
					entry.last[i] = down;
					if (WindowInput.logInput)
						BootLog.log("input: pad " + pad.index + " " + BUTTONS[i] + (down == 1 ? " down" : " up"));
					entry.handle.onButton(BUTTONS[i], down == 1);
				}
			}
			for (j in 0...AXES.length) {
				var at = index(config, AXES[j]);
				var value:Float = at >= 0 && at < pad.values.length ? pad.values[at] : 0;
				if (Math.isNaN(value)) value = 0;
				if (AXES[j] == "LEFT_Y" || AXES[j] == "RIGHT_Y") value = -value;
				var k = BUTTONS.length + j;
				if (value != entry.last[k]) {
					changed = true;
					var before = entry.last[k];
					if (WindowInput.logInput && side(value) != side(before))
						BootLog.log("input: pad " + pad.index + " " + AXES[j] + " " + (Math.round(value * 100) / 100));
					entry.last[k] = value;
					entry.handle.onAxis(AXES[j], value);
				}
			}
			if (changed) entry.changedAt = InputTiming.padChanged(entry.changedAt, pad.name, haxe.Timer.stamp());
		}
	}
}
