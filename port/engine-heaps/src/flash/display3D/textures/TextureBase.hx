package flash.display3D.textures;

class TextureBase extends flash.events.EventDispatcher {
	public static var __portLive:Int = 0;
	public static var __portLiveBytes:Float = 0;
	public static var __portCreated:Int = 0;
	public static var __portFromBitmap:Int = 0;
	public static var __portDropped:Int = 0;
	public static var __portPackedBytes:Float = 0;
	public var __portPacked:Bool;

	public var width(default, null):Int = 0;
	public var height(default, null):Int = 0;
	public var format(default, null):String;
	public var version(default, null) = 0;
	public var disposed(default, null) = false;
	public static var onDispose:TextureBase -> Void;

	var context:flash.display3D.Context3D;

	public function dispose():Void {
		if (disposed) return;
		disposed = true;
		__portLive--;
		if (onDispose != null) onDispose(this);
	}

	function sized(width:Int, height:Int, format:String):Void {
		this.width = width;
		this.height = height;
		this.format = format;
	}

	function uploaded():Void {
		version++;
	}

	public function new(context:flash.display3D.Context3D) {
		super();
		this.context = context;
		__portCreated++;
		__portLive++;
	}
}
