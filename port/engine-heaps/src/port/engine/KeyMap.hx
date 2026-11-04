package port.engine;

class KeyMap {
	static inline var LOC_LEFT = 256;
	static inline var LOC_RIGHT = 512;
	static inline var NUMPAD_ENTER = 108;

	public static inline function keyCode(code:Int):Int {
		var bare = code & 255;
		return bare == NUMPAD_ENTER ? 13 : bare;
	}

	public static function charCode(code:Int, shift:Bool):Int {
		var key = code & 255;
		if (key >= 65 && key <= 90) return shift ? key : key + 32;
		if (key >= 48 && key <= 57) return shift ? ")!@#$%^&*(".charCodeAt(key - 48) : key;
		if (key >= 96 && key <= 105) return key - 48;
		return switch (key) {
			case 32 | 13 | 8 | 9 | 27: key;
			case 108: 13;
			case 46: 127;
			case 106: "*".code;
			case 107: "+".code;
			case 109: "-".code;
			case 110: ".".code;
			case 111: "/".code;
			case 186: shift ? ":".code : ";".code;
			case 187: shift ? "+".code : "=".code;
			case 188: shift ? "<".code : ",".code;
			case 189: shift ? "_".code : "-".code;
			case 190: shift ? ">".code : ".".code;
			case 191: shift ? "?".code : "/".code;
			case 192: shift ? "~".code : "`".code;
			case 219: shift ? "{".code : "[".code;
			case 220: shift ? "|".code : "\\".code;
			case 221: shift ? "}".code : "]".code;
			case 222: shift ? "\"".code : "'".code;
			default: 0;
		}
	}

	public static function keyLocation(code:Int):Int {
		if (code & LOC_LEFT != 0) return 1;
		if (code & LOC_RIGHT != 0) return 2;
		var bare = code & 255;
		return bare >= 96 && bare <= 111 ? 3 : 0;
	}
}
