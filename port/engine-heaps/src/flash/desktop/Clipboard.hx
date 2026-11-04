package flash.desktop;

class Clipboard {
	public static var generalClipboard(default, null):Clipboard = new Clipboard(true);

	var system:Bool;
	var data = new Map<String, Dynamic>();

	public var formats(get, never):Array<openfl.desktop.ClipboardFormats>;

	public function new(system = false) {
		this.system = system;
	}

	static inline function isText(format:openfl.desktop.ClipboardFormats):Bool
		return format == openfl.desktop.ClipboardFormats.TEXT_FORMAT;

	static inline function key(format:openfl.desktop.ClipboardFormats):String
		return format == null ? "" : (cast format : String);

	function get_formats():Array<openfl.desktop.ClipboardFormats> {
		var out:Array<openfl.desktop.ClipboardFormats> = [for (k in data.keys()) cast k];
		if (system && !data.exists(key(openfl.desktop.ClipboardFormats.TEXT_FORMAT)) && systemText() != null)
			out.push(openfl.desktop.ClipboardFormats.TEXT_FORMAT);
		return out;
	}

	function systemText():String {
		var t = hxd.System.getClipboardText();
		return t == null || t == "" ? null : t;
	}

	public function clear():Void {
		data.clear();
		if (system) hxd.System.setClipboardText("");
	}

	public function clearData(format:openfl.desktop.ClipboardFormats):Void {
		data.remove(key(format));
		if (system && isText(format)) hxd.System.setClipboardText("");
	}

	public function getData(format:openfl.desktop.ClipboardFormats, ?transferMode:flash.desktop.ClipboardTransferMode):flash.utils.Object {
		if (system && isText(format)) return systemText();
		return data.get(key(format));
	}

	public function hasFormat(format:openfl.desktop.ClipboardFormats):Bool {
		if (system && isText(format)) return systemText() != null;
		return data.exists(key(format));
	}

	public function setData(format:openfl.desktop.ClipboardFormats, data:flash.utils.Object, serializable:Bool = true):Bool {
		if (system && isText(format)) return hxd.System.setClipboardText(data == null ? "" : Std.string(data));
		this.data.set(key(format), data);
		return true;
	}

	public function setDataHandler(format:openfl.desktop.ClipboardFormats, handler:() -> Dynamic, serializable:Bool = true):Bool {
		return setData(format, handler());
	}
}
