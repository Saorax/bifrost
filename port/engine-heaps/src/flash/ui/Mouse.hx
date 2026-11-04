package flash.ui;

class Mouse {
	public static var supportsCursor(default, null):Bool = true;
	public static var supportsNativeCursor(default, null):Bool = true;
	public static var cursor:String = "auto";

	public static function hide():Void {
		#if hl
		hxd.System.setCursor(Hide);
		#end
	}

	public static function show():Void {
		#if hl
		hxd.System.setCursor(Default);
		#end
	}
}
