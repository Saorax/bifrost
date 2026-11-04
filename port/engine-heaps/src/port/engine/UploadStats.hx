package port.engine;

class UploadStats {
	static var counts = new Map<String, Int>();
	static var bytes = new Map<String, Float>();
	public static var totalBytes(default, null) = 0.0;
	public static var totalCount(default, null) = 0;

	static var flushBytes = {
		var v = Sys.getEnv("BH_PORT_UPLOAD_FLUSH_MB");
		v == null ? 0.0 : Std.parseFloat(v) * 1048576;
	};
	static var sinceFlush = 0.0;
	public static var flushes(default, null) = 0;

	public static inline function add(place:String, n:Float):Void {
		counts.set(place, (counts.exists(place) ? counts.get(place) : 0) + 1);
		bytes.set(place, (bytes.exists(place) ? bytes.get(place) : 0.0) + n);
		totalBytes += n;
		totalCount++;
		if (flushBytes > 0 && (sinceFlush += n) >= flushBytes) flush();
	}

	static function flush():Void {
		sinceFlush = 0;
		#if (hldx && !dx12)
		var driver = Std.downcast(h3d.Engine.getCurrent().driver, h3d.impl.DirectXDriver);
		if (driver != null && @:privateAccess driver.portFlush() > 0) flushes++;
		#end
	}

	public static function take(top:Int):String {
		var keys = [for (k in bytes.keys()) k];
		keys.sort((a, b) -> bytes.get(b) > bytes.get(a) ? 1 : bytes.get(b) < bytes.get(a) ? -1 : 0);
		var mb = (b:Float) -> Std.string(Math.round(b / 104857.6) / 10);
		var out = "uploads " + totalCount + " (" + mb(totalBytes) + " MB): "
			+ [for (k in keys.slice(0, top)) k + " x" + counts.get(k) + " " + mb(bytes.get(k)) + " MB"].join(", ");
		counts = new Map();
		bytes = new Map();
		totalBytes = 0;
		totalCount = 0;
		return out;
	}
}
