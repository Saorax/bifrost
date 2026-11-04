package flash.display;

@:access(flash.geom.Rectangle)
class BitmapData implements flash.display.IBitmapDrawable {
	public static var created(default, null):Int = 0;
	public static var decoded(default, null):Int = 0;
	public static var vectorDraws(default, null):Int = 0;
	public static var vectorDrawn(default, null):Int = 0;
	public static var vectorDrawer:(flash.display.BitmapData, flash.display.DisplayObject, flash.geom.Matrix,
		flash.geom.ColorTransform, flash.geom.Rectangle) -> Bool;
	public static var bitmapDraws(default, null):Int = 0;
	public static var onVectorDraw:(flash.display.IBitmapDrawable, flash.display.BitmapData, flash.geom.Matrix,
		flash.geom.ColorTransform, Float) -> Void;

	public static function fromBase64(base64:String, type:String):flash.display.BitmapData {
		return decode(haxe.crypto.Base64.decode(base64));
	}

	public static function fromBytes(bytes:flash.utils.ByteArray, ?rawAlpha:flash.utils.ByteArray):flash.display.BitmapData {
		if (bytes == null) return null;
		var data = haxe.io.Bytes.alloc(bytes.length);
		for (i in 0...bytes.length) data.set(i, bytes[i]);
		var bitmap = decode(data);
		if (bitmap != null && rawAlpha != null) {
			var n = bitmap.width * bitmap.height;
			for (i in 0...n) if (i < rawAlpha.length) {
				var p = bitmap.pixels.getInt32(i * 4);
				bitmap.pixels.setInt32(i * 4, (rawAlpha[i] << 24) | (p & 0xFFFFFF));
			}
		}
		return bitmap;
	}

	public static function fromFile(path:String):flash.display.BitmapData {
		try return decode(sys.io.File.getBytes(path)) catch (e:Dynamic) return null;
	}

	public static function fromImage(image:Dynamic, transparent:Bool = true):flash.display.BitmapData return null;

	public static function fromTexture(texture:flash.display3D.textures.TextureBase):flash.display.BitmapData return null;

	public static function loadFromBase64(base64:String, type:String):flash.utils.Future<flash.display.BitmapData> {
		return flash.utils.Future.withValue(fromBase64(base64, type));
	}

	public static function loadFromBytes(bytes:flash.utils.ByteArray, ?rawAlpha:flash.utils.ByteArray):flash.utils.Future<flash.display.BitmapData> {
		return flash.utils.Future.withValue(fromBytes(bytes, rawAlpha));
	}

	public static function loadFromFile(path:String):flash.utils.Future<flash.display.BitmapData> {
		return flash.utils.Future.withValue(fromFile(path));
	}

	public static function imageKind(bytes:haxe.io.Bytes):String {
		if (bytes == null || bytes.length < 8) return null;
		if (bytes.get(0) == 0x89 && bytes.get(1) == "P".code && bytes.get(2) == "N".code && bytes.get(3) == "G".code)
			return "png";
		if (bytes.get(0) == 0xFF && bytes.get(1) == 0xD8) return "jpg";
		return null;
	}

	public static function decode(bytes:haxe.io.Bytes):flash.display.BitmapData {
		var kind = imageKind(bytes);
		if (kind == null) return null;
		var size = kind == "png" ? pngSize(bytes) : jpegSize(bytes);
		if (size == null || size.width <= 0 || size.height <= 0) return null;
		var w = size.width, h = size.height;
		var out = haxe.io.Bytes.alloc(w * h * 4);
		var ok = kind == "png"
			? hl.Format.decodePNG(bytes.getData(), bytes.length, out.getData(), w, h, w * 4, hl.Format.PixelFormat.BGRA, 0)
			: hl.Format.decodeJPG(bytes.getData(), bytes.length, out.getData(), w, h, w * 4, hl.Format.PixelFormat.BGRA, 0);
		if (!ok) return null;
		return fromDecoded(w, h, out);
	}

	public static function fromDecoded(w:Int, h:Int, pixels:haxe.io.Bytes):flash.display.BitmapData {
		var bitmap = new flash.display.BitmapData(w, h, true, 0);
		bitmap.pixels = pixels;
		decoded++;
		return bitmap;
	}

	public static function imageSize(bytes:haxe.io.Bytes):{width:Int, height:Int} {
		var kind = imageKind(bytes);
		if (kind == null) return null;
		var size = kind == "png" ? pngSize(bytes) : jpegSize(bytes);
		return size == null || size.width <= 0 || size.height <= 0 ? null : size;
	}

	static function pngSize(b:haxe.io.Bytes):{width:Int, height:Int} {
		if (b.length < 24) return null;
		inline function be(p:Int) return (b.get(p) << 24) | (b.get(p + 1) << 16) | (b.get(p + 2) << 8) | b.get(p + 3);
		return {width: be(16), height: be(20)};
	}

	static function jpegSize(b:haxe.io.Bytes):{width:Int, height:Int} {
		var p = 2;
		while (p + 9 < b.length) {
			if (b.get(p) != 0xFF) {
				p++;
				continue;
			}
			var marker = b.get(p + 1);
			if (marker == 0xFF) {
				p++;
				continue;
			}
			if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
				p += 2;
				continue;
			}
			var length = (b.get(p + 2) << 8) | b.get(p + 3);
			if (marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC)
				return {height: (b.get(p + 5) << 8) | b.get(p + 6), width: (b.get(p + 7) << 8) | b.get(p + 8)};
			p += 2 + length;
		}
		return null;
	}

	public var height:Int;
	public var image:Dynamic;
	public var readable:Bool;
	public var rect:flash.geom.Rectangle;
	public var transparent:Bool;
	public var width:Int;
	public var __portShared:Bool;

	@:noCompletion var fill:Int = 0;
	@:noCompletion var buffer:haxe.io.Bytes;
	@:noCompletion public var __version:Int = __nextVersion();
	static var versionClock = 0;

	@:noCompletion public static inline function __nextVersion():Int return ++versionClock;
	@:noCompletion public var pixels(get, set):haxe.io.Bytes;
	@:noCompletion public var __gpu:h3d.mat.Texture;
	@:noCompletion public var __gpuUsed:Int = 0;
	@:noCompletion public var __pixelsBy:String;
	static var tracePixels = Sys.getEnv("BH_PORT_TRACE_PIXELS") == "1";

	static function caller():String {
		var out = [];
		for (item in haxe.CallStack.callStack()) {
			if (out.length >= 4) break;
			var s = StringTools.trim(haxe.CallStack.toString([item]).split("\n").join(" "));
			if (s.indexOf("BitmapData") < 0 && s.indexOf("CallStack") < 0) out.push(s);
		}
		return out.join(" < ");
	}

	public function new(width:Int, height:Int, transparent:Bool = true, fillColor:UInt = 0xFFFFFFFF) {
		this.transparent = transparent;
		width = width < 0 ? 0 : width;
		height = height < 0 ? 0 : height;
		this.width = width;
		this.height = height;
		rect = new flash.geom.Rectangle(0, 0, width, height);
		if (width > 0 && height > 0) {
			var color:Int = fillColor;
			if (transparent) {
				if ((color & 0xFF000000) == 0) color = 0;
			} else {
				color = 0xFF000000 | (color & 0xFFFFFF);
			}
			fill = color;
			readable = true;
		}
		created++;
	}

	function get_pixels():haxe.io.Bytes {
		if (__gpu != null) port.engine.art.GpuBitmaps.sync(this, "pixels");
		__version = __nextVersion();
		if (buffer == null && width > 0 && height > 0) {
			if (tracePixels) __pixelsBy = caller();
			buffer = haxe.io.Bytes.alloc(width * height * 4);
			if (fill != 0) for (i in 0...width * height) buffer.setInt32(i * 4, fill);
		}
		return buffer;
	}

	function set_pixels(value:haxe.io.Bytes):haxe.io.Bytes {
		if (__gpu != null) port.engine.art.GpuBitmaps.release(this);
		if (tracePixels) __pixelsBy = "set: " + caller();
		__version = __nextVersion();
		return buffer = value;
	}

	@:noCompletion public function __hasPixels():Bool {
		if (__gpu != null) port.engine.art.GpuBitmaps.sync(this, "hasPixels");
		return buffer != null;
	}

	inline function valid():Bool {
		if (__gpu != null) port.engine.art.GpuBitmaps.sync(this, "cpu");
		return readable && width > 0 && height > 0;
	}

	inline function word(x:Int, y:Int):Int {
		if (__gpu != null) port.engine.art.GpuBitmaps.sync(this, "read");
		return buffer == null ? fill : buffer.getInt32((y * width + x) * 4);
	}

	inline function put(x:Int, y:Int, value:Int):Void pixels.setInt32((y * width + x) * 4, value);

	inline function opaque(value:Int):Int return transparent ? value : (0xFF000000 | (value & 0xFFFFFF));

	public function applyFilter(sourceBitmapData:flash.display.BitmapData, sourceRect:flash.geom.Rectangle, destPoint:flash.geom.Point, filter:flash.filters.BitmapFilter):Void {
		if (sourceBitmapData == null || sourceRect == null || destPoint == null || filter == null
			|| !port.engine.art.FilterMath.known(filter) || !valid() || !sourceBitmapData.valid()) {
			copyPixels(sourceBitmapData, sourceRect, destPoint);
			return;
		}
		var w = Std.int(sourceRect.width), h = Std.int(sourceRect.height);
		if (w <= 0 || h <= 0) return;
		if (sourceBitmapData.__gpu != null) port.engine.art.GpuBitmaps.sync(sourceBitmapData, "applyFilter");
		var src = port.engine.art.FilterMath.fromWords(sourceBitmapData.buffer, sourceBitmapData.width,
			sourceBitmapData.height, Std.int(sourceRect.x), Std.int(sourceRect.y), w, h, sourceBitmapData.fill);
		var out = port.engine.art.FilterMath.apply(src, filter);
		if (!transparent) for (i in 0...w * h) {
			out.a[i] = 255;
		}
		port.engine.art.FilterMath.toWords(out, pixels, width, height, Std.int(destPoint.x), Std.int(destPoint.y));
		port.engine.art.FilterMath.Planes.release(src);
		port.engine.art.FilterMath.Planes.release(out);
	}

	public function clone():flash.display.BitmapData {
		var copy = new flash.display.BitmapData(width, height, transparent, 0);
		if (__gpu != null && readable && port.engine.art.GpuBitmaps.ready()) {
			copy.fill = fill;
			port.engine.art.GpuBitmaps.cloneInto(this, copy);
			return copy;
		}
		if (!valid()) {
			copy.readable = readable;
			return copy;
		}
		copy.fill = fill;
		if (buffer != null) copy.buffer = buffer.sub(0, buffer.length);
		if (tracePixels && buffer != null) copy.__pixelsBy = "clone: " + caller();
		return copy;
	}

	public function colorTransform(rect:flash.geom.Rectangle, colorTransform:flash.geom.ColorTransform):Void {
		if (!valid() || colorTransform == null) return;
		var r = clip(rect);
		if (r == null) return;
		for (y in r.y...r.bottom) for (x in r.x...r.right) put(x, y, opaque(transformColor(word(x, y), colorTransform)));
	}

	static inline function channel(value:Float):Int {
		var v = Std.int(value);
		return v < 0 ? 0 : (v > 255 ? 255 : v);
	}

	static function transformColor(c:Int, t:flash.geom.ColorTransform):Int {
		var a = channel(((c >>> 24) & 0xFF) * t.alphaMultiplier + t.alphaOffset);
		var r = channel(((c >> 16) & 0xFF) * t.redMultiplier + t.redOffset);
		var g = channel(((c >> 8) & 0xFF) * t.greenMultiplier + t.greenOffset);
		var b = channel((c & 0xFF) * t.blueMultiplier + t.blueOffset);
		return (a << 24) | (r << 16) | (g << 8) | b;
	}

	public function compare(otherBitmapData:flash.display.BitmapData):Dynamic {
		if (otherBitmapData == this) return 0;
		if (otherBitmapData == null || !valid()) return -1;
		if (width != otherBitmapData.width) return -3;
		if (height != otherBitmapData.height) return -4;
		var same = true;
		for (y in 0...height) for (x in 0...width) if (word(x, y) != otherBitmapData.word(x, y)) same = false;
		if (same) return 0;
		var diff = new flash.display.BitmapData(width, height, true, 0);
		for (y in 0...height) for (x in 0...width) {
			var a = word(x, y), b = otherBitmapData.word(x, y);
			if (a == b) continue;
			if (a & 0xFFFFFF != b & 0xFFFFFF) {
				inline function d(shift:Int) return ((((a >> shift) & 0xFF) - ((b >> shift) & 0xFF)) & 0xFF) << shift;
				diff.put(x, y, 0xFF000000 | d(16) | d(8) | d(0));
			} else {
				diff.put(x, y, ((((a >>> 24) - (b >>> 24)) & 0xFF) << 24) | 0xFFFFFF);
			}
		}
		return diff;
	}

	public function copyChannel(sourceBitmapData:flash.display.BitmapData, sourceRect:flash.geom.Rectangle, destPoint:flash.geom.Point, sourceChannel:flash.display.BitmapDataChannel, destChannel:flash.display.BitmapDataChannel):Void {
		if (!valid() || sourceBitmapData == null || !sourceBitmapData.valid()) return;
		var from = shiftOf(cast sourceChannel), to = shiftOf(cast destChannel);
		if (from < 0 || to < 0) return;
		blit(sourceBitmapData, sourceRect, destPoint, function(src:Int, dst:Int) {
			return (dst & ~(0xFF << to)) | (((src >>> from) & 0xFF) << to);
		});
	}

	static function shiftOf(channel:Int):Int {
		return switch (channel) {
			case 1: 16;
			case 2: 8;
			case 4: 0;
			case 8: 24;
			default: -1;
		}
	}

	public function copyPixels(sourceBitmapData:flash.display.BitmapData, sourceRect:flash.geom.Rectangle, destPoint:flash.geom.Point, ?alphaBitmapData:flash.display.BitmapData, ?alphaPoint:flash.geom.Point, mergeAlpha:Bool = false):Void {
		if (!valid() || sourceBitmapData == null || !sourceBitmapData.valid() || sourceRect == null || destPoint == null) return;
		var ax = 0, ay = 0;
		if (alphaBitmapData != null) {
			ax = (alphaPoint != null ? Std.int(alphaPoint.x) : 0) - Std.int(sourceRect.x);
			ay = (alphaPoint != null ? Std.int(alphaPoint.y) : 0) - Std.int(sourceRect.y);
		}
		var merge = mergeAlpha && transparent;
		blitAt(sourceBitmapData, sourceRect, destPoint, function(src:Int, dst:Int, sx:Int, sy:Int) {
			if (alphaBitmapData != null) {
				var mx = sx + ax, my = sy + ay;
				var m = (mx >= 0 && my >= 0 && mx < alphaBitmapData.width && my < alphaBitmapData.height)
					? alphaBitmapData.word(mx, my) >>> 24 : 0;
				src = (Std.int(((src >>> 24) * m + 127) / 255) << 24) | (src & 0xFFFFFF);
			}
			return merge ? over(src, dst) : src;
		});
	}

	static function over(src:Int, dst:Int):Int {
		var sa = (src >>> 24) & 0xFF;
		if (sa == 255) return src;
		if (sa == 0) return dst;
		var da = (dst >>> 24) & 0xFF;
		var oa = sa + Std.int(da * (255 - sa) / 255);
		if (oa == 0) return 0;
		inline function mix(shift:Int):Int {
			var s = (src >> shift) & 0xFF, d = (dst >> shift) & 0xFF;
			return Std.int((s * sa + d * da * (255 - sa) / 255) / oa) & 0xFF;
		}
		return (oa << 24) | (mix(16) << 16) | (mix(8) << 8) | mix(0);
	}

	function blit(source:flash.display.BitmapData, sourceRect:flash.geom.Rectangle, destPoint:flash.geom.Point, op:Int->Int->Int):Void {
		blitAt(source, sourceRect, destPoint, function(src, dst, _, _) return op(src, dst));
	}

	function blitAt(source:flash.display.BitmapData, sourceRect:flash.geom.Rectangle, destPoint:flash.geom.Point, op:Int->Int->Int->Int->Int):Void {
		var sx0 = Std.int(sourceRect.x), sy0 = Std.int(sourceRect.y);
		var w = Std.int(sourceRect.width), h = Std.int(sourceRect.height);
		var dx0 = Std.int(destPoint.x), dy0 = Std.int(destPoint.y);
		if (sx0 < 0) { w += sx0; dx0 -= sx0; sx0 = 0; }
		if (sy0 < 0) { h += sy0; dy0 -= sy0; sy0 = 0; }
		if (dx0 < 0) { w += dx0; sx0 -= dx0; dx0 = 0; }
		if (dy0 < 0) { h += dy0; sy0 -= dy0; dy0 = 0; }
		if (sx0 + w > source.width) w = source.width - sx0;
		if (sy0 + h > source.height) h = source.height - sy0;
		if (dx0 + w > width) w = width - dx0;
		if (dy0 + h > height) h = height - dy0;
		if (w <= 0 || h <= 0) return;
		var copy = source == this ? clone() : source;
		for (y in 0...h) for (x in 0...w) {
			var sx = sx0 + x, sy = sy0 + y;
			put(dx0 + x, dy0 + y, opaque(op(copy.word(sx, sy), word(dx0 + x, dy0 + y), sx, sy)));
		}
	}

	public function dispose():Void {
		if (__gpu != null) port.engine.art.GpuBitmaps.release(this);
		buffer = null;
		image = null;
		width = 0;
		height = 0;
		rect = null;
		readable = false;
	}

	public function disposeImage():Void {}

	public function draw(source:flash.display.IBitmapDrawable, ?matrix:flash.geom.Matrix, ?colorTransform:flash.geom.ColorTransform, ?blendMode:flash.display.BlendMode, ?clipRect:flash.geom.Rectangle, smoothing:Bool = false):Void {
		if (!readable || width <= 0 || height <= 0 || source == null) return;
		var bitmap:flash.display.BitmapData = null;
		var m = matrix != null ? matrix.clone() : new flash.geom.Matrix();
		if (Std.isOfType(source, flash.display.BitmapData)) {
			bitmap = cast source;
		} else if (Std.isOfType(source, flash.display.Bitmap)) {
			bitmap = (cast source : flash.display.Bitmap).bitmapData;
		}
		if (bitmap == null) {
			if (Std.isOfType(source, flash.display.Bitmap)) return;
			vectorDraws++;
			var started = haxe.Timer.stamp();
			if (vectorDrawer != null && Std.isOfType(source, flash.display.DisplayObject)
				&& vectorDrawer(this, cast source, m, colorTransform, clipRect)) vectorDrawn++;
			if (onVectorDraw != null) onVectorDraw(source, this, matrix, colorTransform, (haxe.Timer.stamp() - started) * 1000);
			return;
		}
		if (!bitmap.valid()) return;
		bitmapDraws++;
		var bounds = new flash.geom.Rectangle();
		new flash.geom.Rectangle(0, 0, bitmap.width, bitmap.height).__transform(bounds, m);
		var r = clip(bounds);
		if (r != null && clipRect != null) r = r.intersect(clip(clipRect));
		if (r == null) return;
		var inverse = m.clone();
		inverse.invert();
		var copy = bitmap == this ? clone() : bitmap;
		for (y in r.y...r.bottom) for (x in r.x...r.right) {
			var px = x + 0.5, py = y + 0.5;
			var sx = Math.floor(inverse.a * px + inverse.c * py + inverse.tx);
			var sy = Math.floor(inverse.b * px + inverse.d * py + inverse.ty);
			if (sx < 0 || sy < 0 || sx >= copy.width || sy >= copy.height) continue;
			var c = copy.word(sx, sy);
			if (colorTransform != null) c = transformColor(c, colorTransform);
			put(x, y, opaque(over(c, word(x, y))));
		}
	}

	public function drawWithQuality(source:flash.display.IBitmapDrawable, ?matrix:flash.geom.Matrix, ?colorTransform:flash.geom.ColorTransform, ?blendMode:flash.display.BlendMode, ?clipRect:flash.geom.Rectangle, smoothing:Bool = false, ?quality:flash.display.StageQuality):Void {
		draw(source, matrix, colorTransform, blendMode, clipRect, smoothing);
	}

	public function encode(rect:flash.geom.Rectangle, compressor:flash.utils.Object, ?byteArray:flash.utils.ByteArray):flash.utils.ByteArray {
		if (!valid()) return null;
		var r = clip(rect != null ? rect : this.rect);
		if (r == null) return null;
		var w = r.right - r.x, h = r.bottom - r.y;
		#if hl
		if (Std.isOfType(compressor, JPEGEncoderOptions)) {
			var jpeg = nativeJpeg(r, w, h, (cast compressor : JPEGEncoderOptions).quality);
			if (jpeg != null) {
				var target = byteArray != null ? byteArray : new flash.utils.ByteArray();
				target.writeBytes(flash.utils.ByteArray.fromBytes(jpeg));
				return target;
			}
		}
		#end
		var pixels = haxe.io.Bytes.alloc(w * (h + 8) * 4);
		var p = 0;
		for (y in r.y...r.bottom) for (x in r.x...r.right) {
			var c = opaque(word(x, y));
			pixels.set(p++, (c >>> 24) & 0xFF);
			pixels.set(p++, (c >> 16) & 0xFF);
			pixels.set(p++, (c >> 8) & 0xFF);
			pixels.set(p++, c & 0xFF);
		}
		var out = new haxe.io.BytesOutput();
		if (Std.isOfType(compressor, PNGEncoderOptions)) {
			var fast = (cast compressor : PNGEncoderOptions).fastCompression;
			new format.png.Writer(out).write(format.png.Tools.build32ARGB(w, h, pixels, fast ? 1 : 9));
		} else if (Std.isOfType(compressor, JPEGEncoderOptions)) {
			var quality = (cast compressor : JPEGEncoderOptions).quality;
			new format.jpg.Writer(out).write({width: w, height: h, quality: quality, pixels: pixels});
		} else {
			return null;
		}
		var bytes = out.getBytes();
		var target = byteArray != null ? byteArray : new flash.utils.ByteArray();
		target.writeBytes(flash.utils.ByteArray.fromBytes(bytes));
		return target;
	}

	#if hl
	public static var jpegEncoder:Null<(haxe.io.Bytes, Int, Int, Int, Int, Int, Int) -> haxe.io.Bytes> = null;

	function nativeJpeg(r:Clip, w:Int, h:Int, quality:Int):haxe.io.Bytes {
		if (jpegEncoder == null) return null;
		if (__gpu != null) port.engine.art.GpuBitmaps.sync(this, "read");
		if (buffer == null) return null;
		return jpegEncoder(buffer, width, r.x, r.y, w, h, quality);
	}
	#end

	public function fillRect(rect:flash.geom.Rectangle, color:Int):Void {
		if (!readable || width <= 0 || height <= 0) return;
		var r = clip(rect);
		if (r == null) return;
		var value = opaque(color);
		if (r.x == 0 && r.y == 0 && r.right == width && r.bottom == height) {
			__version = __nextVersion();
			fill = value;
			if (__gpu != null && port.engine.art.GpuBitmaps.ready()) {
				port.engine.art.GpuBitmaps.fill(this, value);
				return;
			}
			if (__gpu != null) port.engine.art.GpuBitmaps.release(this);
			buffer = null;
			return;
		}
		if (__gpu == null && buffer == null && value == fill) return;
		if (__gpu != null && port.engine.art.GpuBitmaps.ready()) {
			__version = __nextVersion();
			port.engine.art.GpuBitmaps.fillRect(this, r.x, r.y, r.right - r.x, r.bottom - r.y, value);
			return;
		}
		if (!valid()) return;
		for (y in r.y...r.bottom) for (x in r.x...r.right) put(x, y, value);
	}

	public function floodFill(x:Int, y:Int, color:Int):Void {
		if (!valid() || x < 0 || y < 0 || x >= width || y >= height) return;
		var target = word(x, y), value = opaque(color);
		if (target == value) return;
		var stack = [x, y];
		while (stack.length > 0) {
			var py = stack.pop(), px = stack.pop();
			if (px < 0 || py < 0 || px >= width || py >= height || word(px, py) != target) continue;
			put(px, py, value);
			stack.push(px + 1); stack.push(py);
			stack.push(px - 1); stack.push(py);
			stack.push(px); stack.push(py + 1);
			stack.push(px); stack.push(py - 1);
		}
	}

	public function generateFilterRect(sourceRect:flash.geom.Rectangle, filter:flash.filters.BitmapFilter):flash.geom.Rectangle {
		return sourceRect.clone();
	}

	public function getIndexBuffer(context:flash.display3D.Context3D, ?scale9Grid:flash.geom.Rectangle):flash.display3D.IndexBuffer3D return null;

	public function getVertexBuffer(context:flash.display3D.Context3D, ?scale9Grid:flash.geom.Rectangle, ?targetObject:flash.display.DisplayObject):flash.display3D.VertexBuffer3D return null;

	public function getColorBoundsRect(mask:Int, color:Int, findColor:Bool = true):flash.geom.Rectangle {
		if (!readable) return new flash.geom.Rectangle(0, 0, width, height);
		if (!transparent || ((mask >> 24) & 0xFF) > 0) {
			if ((color >>> 24) & 0xFF == 0) color = 0;
		}
		if (!transparent) {
			color |= 0xFF000000;
			mask |= 0xFF000000;
		}
		inline function hit(x:Int, y:Int):Bool {
			var p = word(x, y) & mask;
			return findColor ? p == color : p != color;
		}
		var left = width + 1, right = 0, top = height + 1, bottom = 0;
		var found = false;
		for (x in 0...width) {
			for (y in 0...height) if (hit(x, y)) { left = x; found = true; break; }
			if (found) break;
		}
		found = false;
		for (i in 0...width) {
			var x = width - 1 - i;
			for (y in 0...height) if (hit(x, y)) { if (x > right) right = x; found = true; break; }
			if (found) break;
		}
		found = false;
		for (y in 0...height) {
			for (x in 0...width) if (hit(x, y)) { top = y; found = true; break; }
			if (found) break;
		}
		found = false;
		for (i in 0...height) {
			var y = height - 1 - i;
			for (x in 0...width) if (hit(x, y)) { if (y > bottom) bottom = y; found = true; break; }
			if (found) break;
		}
		var w = right - left, h = bottom - top;
		if (w > 0) w++;
		if (h > 0) h++;
		if (w < 0) w = 0;
		if (h < 0) h = 0;
		if (left == right) w = 1;
		if (top == bottom) h = 1;
		if (left > width) left = 0;
		if (top > height) top = 0;
		return new flash.geom.Rectangle(left, top, w, h);
	}

	public function getPixel(x:Int, y:Int):Int {
		if (!valid() || x < 0 || y < 0 || x >= width || y >= height) return 0;
		return word(x, y) & 0xFFFFFF;
	}

	public function getPixel32(x:Int, y:Int):Int {
		if (!valid() || x < 0 || y < 0 || x >= width || y >= height) return 0;
		return opaque(word(x, y));
	}

	public function getPixels(rect:flash.geom.Rectangle):flash.utils.ByteArray {
		var out = new flash.utils.ByteArray();
		out.endian = flash.utils.Endian.BIG_ENDIAN;
		if (!valid()) return out;
		var r = clip(rect);
		if (r == null) return out;
		for (y in r.y...r.bottom) for (x in r.x...r.right) out.writeUnsignedInt(opaque(word(x, y)));
		out.position = 0;
		return out;
	}

	public function getSurface():Dynamic return null;

	public function getTexture(context:flash.display3D.Context3D):flash.display3D.textures.TextureBase return null;

	public function getVector(rect:flash.geom.Rectangle):openfl.Vector<UInt> {
		var out:Array<UInt> = [];
		if (valid()) {
			var r = clip(rect);
			if (r != null) for (y in r.y...r.bottom) for (x in r.x...r.right) out.push(opaque(word(x, y)));
		}
		return out;
	}

	public function histogram(?hRect:flash.geom.Rectangle):Array<Array<Int>> {
		var result = [for (_ in 0...4) [for (_ in 0...256) 0]];
		if (!valid()) return result;
		var r = clip(hRect != null ? hRect : rect);
		if (r == null) return result;
		for (y in r.y...r.bottom) for (x in r.x...r.right) {
			var c = opaque(word(x, y));
			result[0][(c >> 16) & 0xFF]++;
			result[1][(c >> 8) & 0xFF]++;
			result[2][c & 0xFF]++;
			result[3][(c >>> 24) & 0xFF]++;
		}
		return result;
	}

	public function hitTest(firstPoint:flash.geom.Point, firstAlphaThreshold:Int, secondObject:flash.utils.Object, ?secondBitmapDataPoint:flash.geom.Point, secondAlphaThreshold:Int = 1):Bool {
		if (!valid() || firstPoint == null) return false;
		if (Std.isOfType(secondObject, flash.geom.Point)) {
			var p:flash.geom.Point = cast secondObject;
			var x = Std.int(p.x - firstPoint.x), y = Std.int(p.y - firstPoint.y);
			if (x < 0 || y < 0 || x >= width || y >= height) return false;
			return (opaque(word(x, y)) >>> 24) >= firstAlphaThreshold;
		}
		if (Std.isOfType(secondObject, flash.geom.Rectangle)) {
			var r:flash.geom.Rectangle = (cast secondObject : flash.geom.Rectangle).clone();
			r.offset(-firstPoint.x, -firstPoint.y);
			var c = clip(r);
			if (c == null) return false;
			for (y in c.y...c.bottom) for (x in c.x...c.right) if ((opaque(word(x, y)) >>> 24) >= firstAlphaThreshold) return true;
			return false;
		}
		return false;
	}

	public function lock():Void {}

	public function merge(sourceBitmapData:flash.display.BitmapData, sourceRect:flash.geom.Rectangle, destPoint:flash.geom.Point, redMultiplier:UInt, greenMultiplier:UInt, blueMultiplier:UInt, alphaMultiplier:UInt):Void {
		if (!valid() || sourceBitmapData == null || !sourceBitmapData.valid()) return;
		var mult:Array<Int> = [blueMultiplier, greenMultiplier, redMultiplier, alphaMultiplier];
		blit(sourceBitmapData, sourceRect, destPoint, function(src:Int, dst:Int) {
			var out = 0;
			for (k in 0...4) {
				var shift = k * 8, s = (src >>> shift) & 0xFF, d = (dst >>> shift) & 0xFF;
				out |= (((s * mult[k] + d * (256 - mult[k])) >> 8) & 0xFF) << shift;
			}
			return out;
		});
	}

	public function noise(randomSeed:Int, low:Int = 0, high:Int = 255, channelOptions:Int = 7, grayScale:Bool = false):Void {}

	public function paletteMap(sourceBitmapData:flash.display.BitmapData, sourceRect:flash.geom.Rectangle, destPoint:flash.geom.Point, ?redArray:Array<Int>, ?greenArray:Array<Int>, ?blueArray:Array<Int>, ?alphaArray:Array<Int>):Void {
		if (!valid() || sourceBitmapData == null || !sourceBitmapData.valid()) return;
		blit(sourceBitmapData, sourceRect, destPoint, function(src:Int, dst:Int) {
			inline function map(table:Array<Int>, shift:Int):Int {
				var v = (src >>> shift) & 0xFF;
				return table != null ? table[v] : v << shift;
			}
			return map(redArray, 16) + map(greenArray, 8) + map(blueArray, 0) + map(alphaArray, 24);
		});
	}

	public function perlinNoise(baseX:Float, baseY:Float, numOctaves:UInt, randomSeed:Int, stitch:Bool, fractalNoise:Bool, channelOptions:UInt = 7, grayScale:Bool = false, ?offsets:Array<flash.geom.Point>):Void {}

	public function scroll(x:Int, y:Int):Void {
		if (!valid()) return;
		var copy = clone();
		copyPixels(copy, copy.rect, new flash.geom.Point(x, y));
	}

	public function setPixel(x:Int, y:Int, color:Int):Void {
		if (!valid() || x < 0 || y < 0 || x >= width || y >= height) return;
		put(x, y, (word(x, y) & 0xFF000000) | (color & 0xFFFFFF));
	}

	public function setPixel32(x:Int, y:Int, color:Int):Void {
		if (!valid() || x < 0 || y < 0 || x >= width || y >= height) return;
		put(x, y, opaque(color));
	}

	public function setPixels(rect:flash.geom.Rectangle, byteArray:flash.utils.ByteArray):Void {
		if (!valid() || byteArray == null) return;
		var r = clip(rect);
		if (r == null) return;
		for (y in r.y...r.bottom) for (x in r.x...r.right) {
			if (byteArray.bytesAvailable < 4) return;
			put(x, y, opaque(byteArray.readUnsignedInt()));
		}
	}

	public function setVector(rect:flash.geom.Rectangle, inputVector:openfl.Vector<UInt>):Void {
		if (!valid() || inputVector == null) return;
		var r = clip(rect);
		if (r == null) return;
		var i = 0;
		for (y in r.y...r.bottom) for (x in r.x...r.right) {
			if (i >= inputVector.length) return;
			put(x, y, opaque(inputVector[i++]));
		}
	}

	public function threshold(sourceBitmapData:flash.display.BitmapData, sourceRect:flash.geom.Rectangle, destPoint:flash.geom.Point, operation:String, threshold:Int, color:Int = 0x00000000, mask:Int = 0xFFFFFFFF, copySource:Bool = false):Int {
		if (!valid() || sourceBitmapData == null || !sourceBitmapData.valid()) return 0;
		var count = 0;
		var t = threshold & mask;
		inline function u(v:Int):Float return v < 0 ? v + 4294967296.0 : v;
		blit(sourceBitmapData, sourceRect, destPoint, function(src:Int, dst:Int) {
			var v = u(src & mask), tt = u(t);
			var pass = switch (operation) {
				case "<": v < tt;
				case "<=": v <= tt;
				case ">": v > tt;
				case ">=": v >= tt;
				case "==": v == tt;
				case "!=": v != tt;
				default: false;
			}
			if (pass) {
				count++;
				return color;
			}
			return copySource ? src : dst;
		});
		return count;
	}

	public function unlock(?changeRect:flash.geom.Rectangle):Void {}

	function clip(rect:flash.geom.Rectangle):Clip {
		if (rect == null) return new Clip(0, 0, width, height);
		var x0 = Std.int(Math.max(0, Math.floor(rect.x))), y0 = Std.int(Math.max(0, Math.floor(rect.y)));
		var x1 = Std.int(Math.min(width, Math.ceil(rect.x + rect.width)));
		var y1 = Std.int(Math.min(height, Math.ceil(rect.y + rect.height)));
		return x1 > x0 && y1 > y0 ? new Clip(x0, y0, x1, y1) : null;
	}
}

@:noCompletion private class Clip {
	public var x:Int;
	public var y:Int;
	public var right:Int;
	public var bottom:Int;

	public function new(x:Int, y:Int, right:Int, bottom:Int) {
		this.x = x;
		this.y = y;
		this.right = right;
		this.bottom = bottom;
	}

	public function intersect(other:Clip):Clip {
		if (other == null) return null;
		var x0 = x > other.x ? x : other.x, y0 = y > other.y ? y : other.y;
		var x1 = right < other.right ? right : other.right, y1 = bottom < other.bottom ? bottom : other.bottom;
		return x1 > x0 && y1 > y0 ? new Clip(x0, y0, x1, y1) : null;
	}
}
