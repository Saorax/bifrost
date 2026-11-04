package flash.text;

class Font {
	public static function enumerateFonts(enumerateDeviceFonts:Bool = false):Array<flash.text.Font> {
		var out = [];
		var names = [for (k in port.runtime.swf.SwfFonts.layout.keys()) k];
		names.sort(Reflect.compare);
		for (name in names) {
			var data = port.runtime.swf.SwfFonts.layout.get(name);
			var f = new Font(data.name);
			f.fontStyle = data.bold && data.italic ? BOLD_ITALIC : data.bold ? BOLD : data.italic ? ITALIC : REGULAR;
			f.fontType = EMBEDDED;
			out.push(f);
		}
		return out;
	}

	public static function fromBytes(bytes:flash.utils.ByteArray):flash.text.Font return null;

	public static function fromFile(path:String):flash.text.Font return null;

	public static function loadFromBytes(bytes:flash.utils.ByteArray):flash.utils.Future<flash.text.Font> {
		return flash.utils.Future.withValue(null);
	}

	public static function loadFromFile(path:String):flash.utils.Future<flash.text.Font> {
		return flash.utils.Future.withValue(null);
	}

	public static function loadFromName(path:String):flash.utils.Future<flash.text.Font> {
		return flash.utils.Future.withValue(null);
	}

	public static function registerFont(font:Dynamic):Void {}

	public var fontName:String;
	public var fontStyle:flash.text.FontStyle;
	public var fontType:flash.text.FontType;

	public function new(?name:String) {
		fontName = name;
	}
}
