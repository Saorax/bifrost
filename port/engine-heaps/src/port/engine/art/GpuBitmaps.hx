package port.engine.art;

@:access(flash.display.BitmapData)
class GpuBitmaps {
	public static var engine:h3d.Engine;
	public static var budget = 384 * 1024 * 1024;

	public static var adopted(default, null) = 0;
	public static var syncs(default, null) = 0;
	public static var syncSeconds(default, null) = 0.0;
	public static var evictions(default, null) = 0;
	public static var copies(default, null) = 0;
	public static var clears(default, null) = 0;
	public static var syncReasons(default, null) = new Map<String, Int>();

	static var resident:Array<flash.display.BitmapData> = [];
	static var bytes = 0;
	static var clock = 0;
	static var free = new TexturePool(64, 64);
	static var copyShader:RegionCopy;
	static var copyFx:h3d.pass.ScreenFx<RegionCopy>;

	public static inline function ready():Bool return engine != null && @:privateAccess engine.inRender;

	public static function residentCount():Int return resident.length;

	public static function residentBytes():Int return bytes;

	public static function freeCount():Int return free.count;

	static function alloc(w:Int, h:Int):h3d.mat.Texture {
		var kept = free.take(w, h);
		if (kept != null) return kept;
		var t = new h3d.mat.Texture(w, h, [Target]);
		t.filter = Nearest;
		return t;
	}

	public static function adopt(b:flash.display.BitmapData):h3d.mat.Texture {
		var t = alloc(b.width, b.height);
		if (b.buffer != null) {
			uploadWords(t, b);
			uploads++;
		} else {
			clearTo(t, b.fill);
		}
		b.__gpu = t;
		b.buffer = null;
		resident.push(b);
		bytes += b.width * b.height * 4;
		adopted++;
		touch(b);
		if (bytes > budget) evict(b);
		return t;
	}

	static function uploadWords(t:h3d.mat.Texture, b:flash.display.BitmapData):Void {
		var w = b.width, h = b.height, src = b.buffer;
		var bytes = haxe.io.Bytes.alloc(w * h * 4);
		for (i in 0...w * h) {
			var c = src.getInt32(i * 4);
			var a = (c >>> 24) & 255;
			if (a == 0) continue;
			if (!b.transparent) a = 255;
			inline function pm(v:Int) return a == 255 ? v : Std.int(v * a / 255 + 0.5);
			bytes.set(i * 4, pm(c & 255));
			bytes.set(i * 4 + 1, pm((c >> 8) & 255));
			bytes.set(i * 4 + 2, pm((c >> 16) & 255));
			bytes.set(i * 4 + 3, a);
		}
		var pixels = new hxd.Pixels(w, h, bytes, BGRA);
		if (engine.driver.hasFeature(BottomLeftCoords)) pixels.flipY();
		port.engine.UploadStats.add("gpu bitmap", pixels.width * pixels.height * 4.0);
		t.uploadPixels(pixels);
	}

	public static var uploads(default, null) = 0;

	public static inline function touch(b:flash.display.BitmapData):Void b.__gpuUsed = ++clock;

	static function clearTo(t:h3d.mat.Texture, argb:Int):Void {
		var a = ((argb >>> 24) & 255) / 255;
		engine.pushTarget(t);
		engine.clearF(new h3d.Vector4(((argb >> 16) & 255) / 255 * a, ((argb >> 8) & 255) / 255 * a, (argb & 255) / 255 * a, a));
		engine.popTarget();
	}

	public static function fill(b:flash.display.BitmapData, argb:Int):Void {
		clearTo(b.__gpu, argb);
		clears++;
		touch(b);
	}

	public static function fillRect(b:flash.display.BitmapData, x:Int, y:Int, w:Int, h:Int, argb:Int):Void {
		if (fillFx == null) {
			fillShader = new FillColor();
			fillFx = new h3d.pass.ScreenFx(fillShader);
			fillFx.pass.blend(One, Zero);
		}
		var a = ((argb >>> 24) & 255) / 255;
		fillShader.color.set(((argb >> 16) & 255) / 255 * a, ((argb >> 8) & 255) / 255 * a, (argb & 255) / 255 * a, a);
		engine.pushTarget(b.__gpu);
		engine.setRenderZone(x, engine.driver.hasFeature(BottomLeftCoords) ? b.height - y - h : y, w, h);
		var entered = FxContext.enter();
		fillFx.render();
		FxContext.leave(entered);
		engine.setRenderZone();
		engine.popTarget();
		clears++;
		touch(b);
	}

	static var fillShader:FillColor;
	static var fillFx:h3d.pass.ScreenFx<FillColor>;

	public static function sync(b:flash.display.BitmapData, why:String):Void {
		var t = b.__gpu;
		if (t == null) return;
		var started = haxe.Timer.stamp();
		syncs++;
		syncReasons.set(why, (syncReasons.exists(why) ? syncReasons.get(why) : 0) + 1);
		var w = b.width, h = b.height;
		var words = haxe.io.Bytes.alloc(w * h * 4);
		var pixels = t.capturePixels();
		pixels.convert(BGRA);
		var src = pixels.bytes, stride = pixels.width * 4;
		for (y in 0...h) for (x in 0...w) {
			var o = pixels.offset + y * stride + x * 4;
			var a = src.get(o + 3);
			if (a == 0) continue;
			inline function straight(v:Int) return v >= a ? 255 : Std.int(v * 255 / a + 0.5);
			words.setInt32((y * w + x) * 4, (a << 24) | (straight(src.get(o + 2)) << 16) | (straight(src.get(o + 1)) << 8)
				| straight(src.get(o)));
		}
		leave(b);
		b.buffer = words;
		b.__version = flash.display.BitmapData.__nextVersion();
		syncSeconds += haxe.Timer.stamp() - started;
	}

	public static function release(b:flash.display.BitmapData):Void {
		if (b.__gpu == null) return;
		leave(b);
	}

	static function leave(b:flash.display.BitmapData):Void {
		var t = b.__gpu;
		b.__gpu = null;
		resident.remove(b);
		bytes -= b.width * b.height * 4;
		free.put(t);
	}

	public static function cloneInto(b:flash.display.BitmapData, copy:flash.display.BitmapData):Void {
		var t = alloc(b.width, b.height);
		region(b.__gpu, t, 1, 1);
		copy.__gpu = t;
		copy.buffer = null;
		resident.push(copy);
		bytes += b.width * b.height * 4;
		touch(b);
		touch(copy);
		copies++;
		if (bytes > budget) evict(copy);
	}

	public static function region(src:h3d.mat.Texture, dst:h3d.mat.Texture, sx:Float, sy:Float):Void {
		if (copyFx == null) {
			copyShader = new RegionCopy();
			copyFx = new h3d.pass.ScreenFx(copyShader);
			copyFx.pass.blend(One, Zero);
		}
		var filter = src.filter;
		src.filter = Nearest;
		copyShader.source = src;
		copyShader.scale.set(sx, sy);
		engine.pushTarget(dst);
		var entered = FxContext.enter();
		copyFx.render();
		FxContext.leave(entered);
		engine.popTarget();
		src.filter = filter;
	}

	static function evict(keep:flash.display.BitmapData):Void {
		var order = resident.copy();
		order.sort((a, b) -> a.__gpuUsed - b.__gpuUsed);
		for (b in order) {
			if (bytes <= budget - (budget >> 2)) break;
			if (b == keep) continue;
			evictions++;
			sync(b, "evicted");
		}
	}

	public static function report():String {
		return "resident " + resident.length + " (" + Std.int(bytes / 1048576) + " MB), adopted " + adopted + " (" + uploads + " from CPU words), cleared "
			+ clears + ", GPU copies " + copies + ", read back " + syncs + " in " + Std.int(syncSeconds * 1000) + " ms ("
			+ [for (k => v in syncReasons) k + " " + v].join(", ") + "), evicted " + evictions;
	}
}

private class FillColor extends h3d.shader.ScreenShader {
	static var SRC = {
		@param var color : Vec4;
		function fragment() {
			pixelColor = color;
		}
	};
}

private class RegionCopy extends h3d.shader.ScreenShader {
	static var SRC = {
		@param var source : Sampler2D;
		@param var scale : Vec2;
		function fragment() {
			pixelColor = source.get(calculatedUV * scale);
		}
	};
}
