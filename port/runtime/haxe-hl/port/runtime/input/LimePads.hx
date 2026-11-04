package port.runtime.input;

import lime.ui.Gamepad;

class LimePads {
	public static function start(connected:(pad:PadHandle, announce:Bool) -> Void):Void {
		for (gamepad in Gamepad.devices) connected(handle(gamepad), false);
		Gamepad.onConnect.add(function(gamepad) connected(handle(gamepad), true));
	}

	static function handle(gamepad:Gamepad):PadHandle {
		var pad = new PadHandle(gamepad.id, gamepad.name);
		gamepad.onButtonDown.add(function(button) pad.onButton(buttonName(button), true));
		gamepad.onButtonUp.add(function(button) pad.onButton(buttonName(button), false));
		gamepad.onAxisMove.add(function(axis, value) pad.onAxis(axisName(axis), value));
		gamepad.onDisconnect.add(function() pad.onDisconnect());
		return pad;
	}

	static function buttonName(button:lime.ui.GamepadButton):Null<String> {
		return switch (button) {
			case A: "A";
			case B: "B";
			case X: "X";
			case Y: "Y";
			case LEFT_SHOULDER: "LEFT_SHOULDER";
			case RIGHT_SHOULDER: "RIGHT_SHOULDER";
			case BACK: "BACK";
			case START: "START";
			case LEFT_STICK: "LEFT_STICK";
			case RIGHT_STICK: "RIGHT_STICK";
			case DPAD_UP: "DPAD_UP";
			case DPAD_DOWN: "DPAD_DOWN";
			case DPAD_LEFT: "DPAD_LEFT";
			case DPAD_RIGHT: "DPAD_RIGHT";
			default: null;
		}
	}

	static function axisName(axis:lime.ui.GamepadAxis):Null<String> {
		return switch (axis) {
			case LEFT_X: "LEFT_X";
			case LEFT_Y: "LEFT_Y";
			case RIGHT_X: "RIGHT_X";
			case RIGHT_Y: "RIGHT_Y";
			case TRIGGER_LEFT: "TRIGGER_LEFT";
			case TRIGGER_RIGHT: "TRIGGER_RIGHT";
			default: null;
		}
	}
}
