package port.engine;

class LoopTimes {
	public static var present:Float = 0;
	public static var events:Float = 0;
	public static var pads:Float = 0;
	public static var presentMax:Float = 0;
	public static var threadEvents:Float = 0;
	public static var sceneEvents:Float = 0;
	public static var engineRender:Float = 0;

	public static inline function addPresent(seconds:Float):Void {
		present += seconds;
		if (seconds > presentMax) presentMax = seconds;
	}
}
