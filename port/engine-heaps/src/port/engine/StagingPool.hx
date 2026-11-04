package port.engine;

#if (hldx && !dx12)
class StagingPool {
	public static var enabled = Sys.getEnv("BH_PORT_STAGING_POOL") != "0";
	static var BUDGET = {
		var mb = Std.parseInt(Sys.getEnv("BH_PORT_STAGING_POOL_MB"));
		(mb == null || mb <= 0 ? 48 : mb) * 1024.0 * 1024;
	};
	static var free:Array<Entry> = [];
	static var busy:Array<Entry> = [];
	static var bytes = 0.0;
	static var clock = 0;
	public static var made(default, null) = 0;
	public static var reused(default, null) = 0;

	static function side(n:Int):Int {
		var s = 64;
		while (s < n) s <<= 1;
		return s;
	}

	public static function get(desc:dx.Driver.Texture2dDesc, bpp:Int):dx.Resource {
		if (!enabled) {
			made++;
			return dx.Driver.createTexture2d(desc);
		}
		var best:Entry = null;
		for (e in free)
			if (e.format == desc.format && e.w >= desc.width && e.h >= desc.height && (best == null || e.w * e.h < best.w * best.h))
				best = e;
		if (best != null) {
			free.remove(best);
			busy.push(best);
			reused++;
			return best.res;
		}
		var w = side(desc.width), h = side(desc.height);
		var size = new dx.Driver.Texture2dDesc();
		size.width = w;
		size.height = h;
		size.access = desc.access;
		size.usage = desc.usage;
		size.format = desc.format;
		var res = dx.Driver.createTexture2d(size);
		if (res == null) return null;
		made++;
		var e = new Entry(res, w, h, desc.format, w * h * bpp);
		busy.push(e);
		bytes += e.bytes;
		return res;
	}

	public static function put(res:dx.Resource):Void {
		if (!enabled) {
			res.release();
			return;
		}
		var e:Entry = null;
		for (b in busy) if (b.res == res) e = b;
		if (e == null) {
			res.release();
			return;
		}
		busy.remove(e);
		e.used = ++clock;
		free.push(e);
		while (bytes > BUDGET && free.length > 0) {
			var oldest = free[0];
			for (f in free) if (f.used < oldest.used) oldest = f;
			free.remove(oldest);
			bytes -= oldest.bytes;
			oldest.res.release();
		}
	}

	public static var dynamicBuffers = Sys.getEnv("BH_PORT_DYNAMIC_BUFFERS") == "1";

	public static function mapBuffer(res:dx.Resource, data:hl.Bytes, startByte:Int, count:Int):Void {
		var ptr = res.map(0, startByte == 0 ? WriteDiscard : WriteNoOverwrite, true, null);
		if (ptr == null) throw "Can't map buffer";
		ptr.blit(startByte, data, 0, count);
		res.unmap(0);
	}

	public static function census():String {
		return "staging made " + made + ", reused " + reused + ", kept " + free.length + " ("
			+ Std.string(Math.round(bytes / 104857.6) / 10) + " MB)";
	}
}

private class Entry {
	public var res:dx.Resource;
	public var w:Int;
	public var h:Int;
	public var format:dx.Format;
	public var bytes:Float;
	public var used = 0;

	public function new(res, w, h, format, bytes) {
		this.res = res;
		this.w = w;
		this.h = h;
		this.format = format;
		this.bytes = bytes;
	}
}
#else
class StagingPool {
	public static function census():String return "staging: not DX11";
}
#end
