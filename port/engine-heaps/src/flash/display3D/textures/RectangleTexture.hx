package flash.display3D.textures;

class RectangleTexture extends flash.display3D.textures.TextureBase {
	public var source(default, null):flash.display.BitmapData;
	public static var gpuUpload:(RectangleTexture, flash.display.BitmapData) -> Bool;
	public var bytes(default, null):haxe.io.Bytes;

	public function uploadFromBitmapData(source:flash.display.BitmapData):Void {
		if (source == null) throw new flash.errors.Error("Error #2007: Parameter source must be non-null.", 2007);
		if (this.source != null) this.source.dispose();
		this.source = null;
		bytes = null;
		flash.display3D.textures.TextureBase.__portFromBitmap++;
		uploaded();
		if (source.__gpu != null && gpuUpload != null && gpuUpload(this, source)) return;
		this.source = source.clone();
	}

	public function uploadFromByteArray(data:flash.utils.ByteArray, byteArrayOffset:UInt):Void {
		var length = width * height * 4;
		bytes = haxe.io.Bytes.alloc(length);
		for (i in 0...length) bytes.set(i, data[byteArrayOffset + i]);
		if (source != null) source.dispose();
		source = null;
		uploaded();
	}

	public function uploadFromTypedArray(data:Dynamic):Void {}

	public function new(context:flash.display3D.Context3D, width:Int, height:Int, format:String, optimizeForRenderToTexture:Bool) {
		super(context);
		sized(width, height, format);
	}
}
