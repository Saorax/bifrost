package port.engine;

class Inflate {
	public static function run(src:haxe.io.Bytes, windowBits:Int):haxe.io.Bytes {
		var u = new haxe.zip.Uncompress(windowBits);
		var tmp = haxe.io.Bytes.alloc(1 << 16);
		var out = new haxe.io.BytesBuffer();
		var pos = 0;
		u.setFlushMode(haxe.zip.FlushMode.SYNC);
		try {
			while (true) {
				var r = u.execute(src, pos, tmp, 0);
				out.addBytes(tmp, 0, r.write);
				pos += r.read;
				if (r.done) break;
				if (r.read == 0 && r.write == 0) throw "truncated stream";
			}
		} catch (e:Dynamic) {
			u.close();
			throw new flash.errors.IOError("Error #2058: There was an error decompressing the data.");
		}
		u.close();
		return out.getBytes();
	}
}
