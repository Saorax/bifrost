package flash.system;

class Capabilities {
	public static var avHardwareDisable:Bool = true;
	public static var cpuArchitecture:String;
	public static var hasAccessibility:Bool = false;
	public static var hasAudio:Bool = true;
	public static var hasAudioEncoder:Bool = false;
	public static var hasEmbeddedVideo:Bool = false;
	public static var hasIME:Bool = false;
	public static var hasMP3:Bool = false;
	public static var hasPrinting:Bool = false;
	public static var hasScreenBroadcast:Bool = false;
	public static var hasScreenPlayback:Bool = false;
	public static var hasStreamingAudio:Bool = false;
	public static var hasStreamingVideo:Bool = false;
	public static var hasTLS:Bool = true;
	public static var hasVideoEncoder:Bool = false;
	public static var isDebugger:Bool = false;
	public static var isEmbeddedInAcrobat:Bool = false;
	public static var localFileReadDisable:Bool = false;
	public static var manufacturer:String;
	public static var maxLevelIDC:Int = 0;
	public static var pixelAspectRatio:Float;
	public static var playerType:String = "Desktop";
	public static var screenColor:String = "color";
	public static var serverString:String = "";
	public static var supports32BitProcesses:Bool = true;
	public static var supports64BitProcesses:Bool = true;
	public static var touchscreenType:flash.system.TouchscreenType;
	public static function hasMultiChannelAudio(type:String):Bool { return cast null; }
	public static var os(get, never):String;
	public static var version(get, never):String;
	public static var screenDPI(get, never):Float;
	public static var screenResolutionX(get, never):Float;
	public static var screenResolutionY(get, never):Float;
	public static var language(get, never):String;

	static function get_os():String {
		var name = Sys.systemName();
		return name == "Windows" ? "Windows 10" : name;
	}

	static function get_version():String {
		return (Sys.systemName() == "Mac" ? "MAC" : Sys.systemName() == "Linux" ? "LNX" : "WIN") + " 9,5,2,0";
	}

	static function get_screenDPI():Float {
		return 72;
	}

	static function monitor():{width:Int, height:Int} {
		var monitors = hxd.Window.getMonitors();
		return monitors.length > 0 ? monitors[0] : {width: 0, height: 0};
	}

	static function get_screenResolutionX():Float {
		return monitor().width;
	}

	static function get_screenResolutionY():Float {
		return monitor().height;
	}

	static function get_language():String {
		return "en";
	}
}
