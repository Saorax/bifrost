package port.engine;

class NativeJpeg {
	@:hlNative("bhsound", "jpeg_encode") static function encodeWords(words:hl.Bytes, stride:Int, x:Int, y:Int, width:Int,
		height:Int, quality:Int, out:hl.Bytes, cap:Int):Int return -1;

	public static function encode(words:haxe.io.Bytes, stride:Int, x:Int, y:Int, w:Int, h:Int, quality:Int):haxe.io.Bytes {
		var cap = w * h * 3 + 65536;
		var out = haxe.io.Bytes.alloc(cap);
		var size = encodeWords(words, stride, x, y, w, h, quality < 1 ? 1 : (quality > 100 ? 100 : quality), out, cap);
		return size > 0 ? out.sub(0, size) : null;
	}
}
