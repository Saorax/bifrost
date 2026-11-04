package port.engine.art;

import haxe.ds.Vector;

class FilterMath {
	public static function kernel(blur:Float):Array<Float> {
		if (blur <= 1) return [1.0];
		var half = blur / 2;
		var n = Math.ceil(half - 0.5);
		var weights = [];
		for (d in -n...n + 1) {
			var lo = Math.max(d - 0.5, -half), hi = Math.min(d + 0.5, half);
			weights.push(hi > lo ? (hi - lo) / blur : 0.0);
		}
		return weights;
	}

	public static function margin(filter:flash.filters.BitmapFilter):Array<Int> {
		inline function reach(blur:Float, quality:Int):Int return (kernel(blur).length >> 1) * (quality < 1 ? 1 : quality);
		if (Std.isOfType(filter, flash.filters.GlowFilter)) {
			var g:flash.filters.GlowFilter = cast filter;
			return g.inner ? [0, 0] : [reach(g.blurX, g.quality), reach(g.blurY, g.quality)];
		}
		if (Std.isOfType(filter, flash.filters.DropShadowFilter)) {
			var s:flash.filters.DropShadowFilter = cast filter;
			if (s.inner) return [0, 0];
			var o = shadowOffset(s);
			return [reach(s.blurX, s.quality) + Math.ceil(Math.abs(o[0])), reach(s.blurY, s.quality) + Math.ceil(Math.abs(o[1]))];
		}
		if (Std.isOfType(filter, flash.filters.BlurFilter)) {
			var b:flash.filters.BlurFilter = cast filter;
			return [reach(b.blurX, b.quality), reach(b.blurY, b.quality)];
		}
		return [0, 0];
	}

	public static function known(filter:flash.filters.BitmapFilter):Bool {
		return Std.isOfType(filter, flash.filters.GlowFilter) || Std.isOfType(filter, flash.filters.DropShadowFilter)
			|| Std.isOfType(filter, flash.filters.BlurFilter) || Std.isOfType(filter, flash.filters.ColorMatrixFilter);
	}

	public static function shadowOffset(s:flash.filters.DropShadowFilter):Array<Float> {
		var radians = s.angle * Math.PI / 180;
		return [Math.cos(radians) * s.distance, Math.sin(radians) * s.distance];
	}

	public static function apply(src:Planes, filter:flash.filters.BitmapFilter):Planes {
		if (Std.isOfType(filter, flash.filters.GlowFilter)) {
			var g:flash.filters.GlowFilter = cast filter;
			return glow(src, g.color, g.alpha, g.blurX, g.blurY, g.strength, g.quality, g.inner, g.knockout);
		}
		if (Std.isOfType(filter, flash.filters.DropShadowFilter)) {
			var s:flash.filters.DropShadowFilter = cast filter;
			var o = shadowOffset(s);
			return glow(src, s.color, s.alpha, s.blurX, s.blurY, s.strength, s.quality, s.inner, s.knockout, o[0], o[1],
				s.hideObject);
		}
		if (Std.isOfType(filter, flash.filters.BlurFilter)) {
			var b:flash.filters.BlurFilter = cast filter;
			return blur(src, b.blurX, b.blurY, b.quality);
		}
		if (Std.isOfType(filter, flash.filters.ColorMatrixFilter)) {
			return colorMatrix(src, (cast filter : flash.filters.ColorMatrixFilter).__values());
		}
		return null;
	}

	public static function pass(plane:Vector<Int>, w:Int, h:Int, weights:Array<Float>, horizontal:Bool):Void {
		var n = weights.length >> 1;
		if (n == 0) return;
		var inner = weights[1], end = weights[0];
		var count = horizontal ? h : w, length = horizontal ? w : h;
		var blur4 = 4 / inner, q = end * 4 / inner;
		var den = Math.round(blur4), endQ = Math.round(q);
		if (Math.abs(blur4 - den) < 1e-9 && Math.abs(q - endQ) < 1e-9 && den > 0) {
			passQuarters(plane, w, h, n, den, endQ, horizontal);
			return;
		}
		var step = horizontal ? 1 : w;
		var line = new Vector<Int>(length);
		for (j in 0...count) {
			var base = horizontal ? j * w : j;
			for (i in 0...length) line[i] = plane[base + i * step];
			var sum = 0;
			for (k in 0...(n < length ? n : length)) sum += line[k];
			for (i in 0...length) {
				var ends = (i - n >= 0 ? line[i - n] : 0) + (i + n < length ? line[i + n] : 0);
				plane[base + i * step] = Std.int(sum * inner + ends * end + 1e-7);
				if (i + n < length) sum += line[i + n];
				if (i - n + 1 >= 0) sum -= line[i - n + 1];
			}
		}
	}

	static function passQuarters(plane:Vector<Int>, w:Int, h:Int, n:Int, den:Int, endQ:Int, horizontal:Bool):Void {
		var count = horizontal ? h : w, length = horizontal ? w : h;
		var step = horizontal ? 1 : w;
		var line = new Vector<Int>(length);
		for (j in 0...count) {
			var base = horizontal ? j * w : j;
			for (i in 0...length) line[i] = plane[base + i * step];
			var sum = 0;
			for (k in 0...(n < length ? n : length)) sum += line[k];
			for (i in 0...length) {
				var ends = (i - n >= 0 ? line[i - n] : 0) + (i + n < length ? line[i + n] : 0);
				plane[base + i * step] = Std.int((sum * 4 + ends * endQ) / den);
				if (i + n < length) sum += line[i + n];
				if (i - n + 1 >= 0) sum -= line[i - n + 1];
			}
		}
	}

	public static function passByTaps(plane:Vector<Int>, w:Int, h:Int, weights:Array<Float>, horizontal:Bool):Void {
		var n = weights.length >> 1;
		if (n == 0) return;
		var count = horizontal ? h : w, length = horizontal ? w : h;
		var line = new Vector<Int>(length);
		for (j in 0...count) {
			for (i in 0...length) line[i] = plane[horizontal ? j * w + i : i * w + j];
			for (i in 0...length) {
				var sum = 0.0;
				var k0 = n - i < 0 ? 0 : n - i, k1 = length - i + n < weights.length ? length - i + n : weights.length;
				for (k in k0...k1) sum += line[i + k - n] * weights[k];
				plane[horizontal ? j * w + i : i * w + j] = Std.int(sum + 1e-7);
			}
		}
	}

	public static function blurPlane(plane:Vector<Int>, w:Int, h:Int, blurX:Float, blurY:Float, quality:Int):Void {
		var kx = kernel(blurX), ky = kernel(blurY);
		for (q in 0...quality) pass(plane, w, h, kx, true);
		for (q in 0...quality) pass(plane, w, h, ky, false);
	}

	public static function glow(src:Planes, color:Int, alpha:Float, blurX:Float, blurY:Float, strength:Float,
			quality:Int, inner:Bool, knockout:Bool, offsetX:Float = 0, offsetY:Float = 0, hideObject:Bool = false):Planes {
		var w = src.w, h = src.h, n = w * h;
		var srcAlpha = src.a;
		var plane = scratch(0, n);
		for (i in 0...n) plane[i] = inner ? 255 - srcAlpha[i] : srcAlpha[i];
		blurPlane(plane, w, h, blurX, blurY, quality);
		if (offsetX != 0 || offsetY != 0) plane = shift(plane, w, h, offsetX, offsetY);
		var alpha8 = Std.int(alpha * 255);
		var gr = (color >> 16) & 0xFF, gg = (color >> 8) & 0xFF, gb = color & 0xFF;
		var out = Planes.take(w, h);
		var gaOf = new Vector<Int>(256), prOf = new Vector<Int>(256), pgOf = new Vector<Int>(256), pbOf = new Vector<Int>(256);
		for (v in 0...256) {
			gaOf[v] = Std.int((Std.int(Math.min(255, v * strength)) * alpha8 + 127) / 255);
			prOf[v] = premul(gr, v);
			pgOf[v] = premul(gg, v);
			pbOf[v] = premul(gb, v);
		}
		for (i in 0...n) {
			var pv = plane[i];
			var ga = pv >= 0 && pv < 256 ? gaOf[pv] : Std.int((Std.int(Math.min(255, pv * strength)) * alpha8 + 127) / 255);
			var sa = srcAlpha[i];
			var spr = src.r[i], spg = src.g[i], spb = src.b[i];
			var oa:Int, orr:Int, og:Int, ob:Int;
			if (inner) {
				if (knockout) {
					oa = Std.int((ga * sa + 127) / 255);
					orr = premul(gr, oa);
					og = premul(gg, oa);
					ob = premul(gb, oa);
				} else {
					var inv = 255 - ga;
					oa = sa;
					orr = Std.int((premul(gr, sa) * ga + spr * inv + 127) / 255);
					og = Std.int((premul(gg, sa) * ga + spg * inv + 127) / 255);
					ob = Std.int((premul(gb, sa) * ga + spb * inv + 127) / 255);
				}
			} else if (knockout) {
				ga = Std.int((ga * (255 - sa) + 127) / 255);
				oa = ga;
				orr = prOf[ga];
				og = pgOf[ga];
				ob = pbOf[ga];
			} else if (hideObject) {
				oa = ga;
				orr = prOf[ga];
				og = pgOf[ga];
				ob = pbOf[ga];
			} else {
				var inv = 256 - sa;
				oa = sa + ((ga * inv) >> 8);
				orr = spr + ((prOf[ga] * inv) >> 8);
				og = spg + ((pgOf[ga] * inv) >> 8);
				ob = spb + ((pbOf[ga] * inv) >> 8);
			}
			if (oa > 255) oa = 255;
			out.a[i] = oa;
			out.r[i] = orr > oa ? oa : orr;
			out.g[i] = og > oa ? oa : og;
			out.b[i] = ob > oa ? oa : ob;
		}
		return out;
	}

	public static function blur(src:Planes, blurX:Float, blurY:Float, quality:Int):Planes {
		var out = src.copy();
		for (p in [out.a, out.r, out.g, out.b]) blurPlane(p, out.w, out.h, blurX, blurY, quality);
		for (i in 0...out.w * out.h) {
			var a = out.a[i];
			if (out.r[i] > a) out.r[i] = a;
			if (out.g[i] > a) out.g[i] = a;
			if (out.b[i] > a) out.b[i] = a;
		}
		return out;
	}

	public static function fixedMatrix(m:Array<Float>):Array<Float> {
		return [for (v in m) Math.ffloor(v * 65536 + 0.5)];
	}

	public static function colorMatrix(src:Planes, m:Array<Float>):Planes {
		var out = Planes.take(src.w, src.h);
		var q = fixedMatrix(m);
		for (i in 0...src.w * src.h) {
			var a = src.a[i];
			var r = unpremul(src.r[i], a), g = unpremul(src.g[i], a), b = unpremul(src.b[i], a);
			inline function row(k:Int):Int {
				var v = Math.ffloor((q[k] * r + q[k + 1] * g + q[k + 2] * b + q[k + 3] * a + q[k + 4]) / 65536);
				return v <= 0 ? 0 : v >= 255 ? 255 : Std.int(v);
			}
			var na = row(15);
			out.a[i] = na;
			out.r[i] = premul(row(0), na);
			out.g[i] = premul(row(5), na);
			out.b[i] = premul(row(10), na);
		}
		return out;
	}

	static function shift(plane:Vector<Int>, w:Int, h:Int, dx:Float, dy:Float):Vector<Int> {
		var ix = Math.floor(dx), iy = Math.floor(dy);
		var fx = dx - ix, fy = dy - iy;
		inline function at(x:Int, y:Int):Int return x >= 0 && y >= 0 && x < w && y < h ? plane[y * w + x] : 0;
		var out = scratch(plane == scratchInts[1] ? 0 : 1, w * h);
		for (y in 0...h) for (x in 0...w) {
			var sx = x - ix, sy = y - iy;
			var v = at(sx, sy) * (1 - fx) * (1 - fy) + at(sx - 1, sy) * fx * (1 - fy) + at(sx, sy - 1) * (1 - fx) * fy
				+ at(sx - 1, sy - 1) * fx * fy;
			out[y * w + x] = Std.int(v + 1e-7);
		}
		return out;
	}

	public static inline function premul(c:Int, a:Int):Int {
		return Std.int((c * a + 127) / 255);
	}

	public static inline function unpremul(c:Int, a:Int):Int {
		if (a == 0) return 0;
		var v = Std.int((c * 255 + (a >> 1)) / a);
		return v > 255 ? 255 : v;
	}

	public static function fromWords(words:haxe.io.Bytes, stride:Int, rows:Int, x0:Int, y0:Int, w:Int, h:Int,
			fill:Int = 0):Planes {
		var p = Planes.take(w, h);
		for (y in 0...h) {
			var sy = y0 + y;
			if (sy < 0 || sy >= rows) continue;
			for (x in 0...w) {
				var sx = x0 + x;
				if (sx < 0 || sx >= stride) continue;
				var c = words == null ? fill : words.getInt32((sy * stride + sx) * 4);
				var a = (c >>> 24) & 0xFF, i = y * w + x;
				p.a[i] = a;
				p.r[i] = premul((c >> 16) & 0xFF, a);
				p.g[i] = premul((c >> 8) & 0xFF, a);
				p.b[i] = premul(c & 0xFF, a);
			}
		}
		return p;
	}

	public static function toWords(p:Planes, words:haxe.io.Bytes, stride:Int, rows:Int, x0:Int, y0:Int):Void {
		for (y in 0...p.h) {
			var dy = y0 + y;
			if (dy < 0 || dy >= rows) continue;
			for (x in 0...p.w) {
				var dx = x0 + x;
				if (dx < 0 || dx >= stride) continue;
				var i = y * p.w + x, a = p.a[i];
				words.setInt32((dy * stride + dx) * 4, (a << 24) | (unpremul(p.r[i], a) << 16) | (unpremul(p.g[i], a) << 8)
					| unpremul(p.b[i], a));
			}
		}
	}

	public static function fromPremultipliedRGBA(bytes:haxe.io.Bytes, w:Int, h:Int):Planes {
		var p = Planes.take(w, h);
		for (i in 0...w * h) {
			p.r[i] = bytes.get(i * 4);
			p.g[i] = bytes.get(i * 4 + 1);
			p.b[i] = bytes.get(i * 4 + 2);
			p.a[i] = bytes.get(i * 4 + 3);
		}
		return p;
	}

	static var scratchInts:Array<Vector<Int>> = [null, null];

	static function scratch(slot:Int, n:Int):Vector<Int> {
		var v = scratchInts[slot];
		if (v == null || v.length < n) {
			v = new Vector<Int>(n);
			scratchInts[slot] = v;
		}
		return v;
	}

	public static function toPremultipliedRGBA(p:Planes, ?into:haxe.io.Bytes):haxe.io.Bytes {
		var bytes = into != null && into.length >= p.w * p.h * 4 ? into : haxe.io.Bytes.alloc(p.w * p.h * 4);
		for (i in 0...p.w * p.h) {
			bytes.set(i * 4, p.r[i]);
			bytes.set(i * 4 + 1, p.g[i]);
			bytes.set(i * 4 + 2, p.b[i]);
			bytes.set(i * 4 + 3, p.a[i]);
		}
		return bytes;
	}
}

class Planes {
	public var w(default, null):Int;
	public var h(default, null):Int;
	public var a(default, null):Vector<Int>;
	public var r(default, null):Vector<Int>;
	public var g(default, null):Vector<Int>;
	public var b(default, null):Vector<Int>;

	public function new(w:Int, h:Int) {
		this.w = w;
		this.h = h;
		var n = w * h;
		a = new Vector<Int>(n);
		r = new Vector<Int>(n);
		g = new Vector<Int>(n);
		b = new Vector<Int>(n);
		for (i in 0...n) {
			a[i] = 0;
			r[i] = 0;
			g[i] = 0;
			b[i] = 0;
		}
	}

	public static function take(w:Int, h:Int):Planes {
		var n = w * h, best = -1;
		for (i in 0...spare.length) {
			var room = spare[i].a.length;
			if (room >= n && (best < 0 || room < spare[best].a.length)) best = i;
		}
		if (best < 0) return new Planes(w, h);
		var p = spare[best];
		spare.splice(best, 1);
		p.w = w;
		p.h = h;
		for (k in 0...n) {
			p.a[k] = 0;
			p.r[k] = 0;
			p.g[k] = 0;
			p.b[k] = 0;
		}
		return p;
	}

	public static function release(p:Planes):Void {
		if (p == null || p.a.length > SPARE_MAX || spare.indexOf(p) >= 0) return;
		if (spare.length >= SPARE) spare.shift();
		spare.push(p);
	}

	static inline var SPARE = 4;
	static inline var SPARE_MAX = 1 << 18;
	static var spare:Array<Planes> = [];

	public function copy():Planes {
		var c = take(w, h);
		for (i in 0...w * h) {
			c.a[i] = a[i];
			c.r[i] = r[i];
			c.g[i] = g[i];
			c.b[i] = b[i];
		}
		return c;
	}
}
