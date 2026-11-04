package port.engine.art;

class GpuFilters {
	var engine:h3d.Engine;
	var planeShader = new PlaneShader();
	var passShader = new PassShader();
	var glowShader = new GlowShader();
	var matrixShader = new MatrixShader();
	var planeFx:h3d.pass.ScreenFx<PlaneShader>;
	var passFx:h3d.pass.ScreenFx<PassShader>;
	var glowFx:h3d.pass.ScreenFx<GlowShader>;
	var matrixFx:h3d.pass.ScreenFx<MatrixShader>;
	var table:h3d.mat.Texture;
	var tableBytes = haxe.io.Bytes.alloc(256 * 4);

	static var matrices = Sys.getEnv("BH_PORT_GPU_MATRICES") != "0";

	public static var layers(default, null) = 0;
	public static var passes(default, null) = 0;

	public function new(engine:h3d.Engine) {
		this.engine = engine;
		planeFx = new h3d.pass.ScreenFx(planeShader);
		passFx = new h3d.pass.ScreenFx(passShader);
		glowFx = new h3d.pass.ScreenFx(glowShader);
		matrixFx = new h3d.pass.ScreenFx(matrixShader);
		for (p in [planeFx.pass, passFx.pass, glowFx.pass, matrixFx.pass]) p.blend(One, Zero);
		table = new h3d.mat.Texture(256, 1);
		table.filter = Nearest;
	}

	static function quarters(blur:Float):Array<Int> {
		var weights = FilterMath.kernel(blur);
		var n = weights.length >> 1;
		if (n == 0) return [0, 1, 0];
		var inner = weights[1], end = weights[0];
		var blur4 = 4 / inner, q = end * 4 / inner;
		var den = Math.round(blur4), endQ = Math.round(q);
		return Math.abs(blur4 - den) < 1e-9 && Math.abs(q - endQ) < 1e-9 && den > 0 ? [n, den, endQ] : null;
	}

	public static function describe(f:flash.filters.BitmapFilter):String {
		if (Std.isOfType(f, flash.filters.GlowFilter)) {
			var g:flash.filters.GlowFilter = cast f;
			return "(" + g.blurX + "x" + g.blurY + " q" + g.quality + (quarters(g.blurX) == null || quarters(g.blurY) == null ? " not quarters" : "") + ")";
		}
		if (Std.isOfType(f, flash.filters.DropShadowFilter)) {
			var d:flash.filters.DropShadowFilter = cast f;
			return "(" + d.blurX + "x" + d.blurY + " q" + d.quality + " d" + d.distance + " a" + d.angle + (d.inner ? " inner" : "")
				+ (d.knockout ? " knockout" : "") + (d.hideObject ? " hide" : "") + ")";
		}
		return "";
	}

	public static function supported(filters:Array<flash.filters.BitmapFilter>):Bool {
		for (f in filters) {
			if (matrices && Type.getClass(f) == flash.filters.ColorMatrixFilter
				&& matrixFits((cast f : flash.filters.ColorMatrixFilter).__values())) continue;
			if (Type.getClass(f) != flash.filters.GlowFilter) return false;
			var g:flash.filters.GlowFilter = cast f;
			if (quarters(g.blurX) == null || quarters(g.blurY) == null) return false;
		}
		return true;
	}

	public function apply(source:h3d.mat.Texture, w:Int, h:Int, filters:Array<flash.filters.BitmapFilter>,
			out:h3d.mat.Texture, borrow:(Int, Int) -> h3d.mat.Texture, ?giveBack:h3d.mat.Texture -> Void):Void {
		var a = borrow(w, h), b = borrow(w, h);
		var scratch = [a, b];
		var src = source;
		for (i in 0...filters.length) {
			var dest = i == filters.length - 1 ? out : borrow(w, h);
			if (dest != out) scratch.push(dest);
			if (Std.isOfType(filters[i], flash.filters.ColorMatrixFilter))
				matrix(src, (cast filters[i] : flash.filters.ColorMatrixFilter).__values(), dest);
			else
				glow(src, w, h, cast filters[i], a, b, dest);
			src = dest;
		}
		if (giveBack != null) for (t in scratch) giveBack(t);
		layers++;
	}

	function render<T:h3d.shader.ScreenShader>(fx:h3d.pass.ScreenFx<T>, target:h3d.mat.Texture):Void {
		engine.pushTarget(target);
		fx.render();
		engine.popTarget();
	}

	function matrix(src:h3d.mat.Texture, m:Array<Float>, dest:h3d.mat.Texture):Void {
		src.filter = Nearest;
		var q = FilterMath.fixedMatrix(m);
		var hi = [for (v in q) Math.ffloor(v / 256)];
		var lo = [for (i in 0...20) q[i] - hi[i] * 256];
		var sh = matrixShader;
		sh.source = src;
		for (part in 0...2) {
			var v = part == 0 ? hi : lo;
			(part == 0 ? sh.hiR : sh.loR).set(v[0], v[1], v[2], v[3]);
			(part == 0 ? sh.hiG : sh.loG).set(v[5], v[6], v[7], v[8]);
			(part == 0 ? sh.hiB : sh.loB).set(v[10], v[11], v[12], v[13]);
			(part == 0 ? sh.hiA : sh.loA).set(v[15], v[16], v[17], v[18]);
			(part == 0 ? sh.hiOff : sh.loOff).set(v[4], v[9], v[14], v[19]);
		}
		render(matrixFx, dest);
	}

	static function matrixFits(m:Array<Float>):Bool {
		for (i in 0...20) if (Math.abs(m[i]) > (i % 5 == 4 ? 4096 : 16)) return false;
		return true;
	}

	function glow(src:h3d.mat.Texture, w:Int, h:Int, g:flash.filters.GlowFilter, a:h3d.mat.Texture, b:h3d.mat.Texture,
			dest:h3d.mat.Texture):Void {
		for (t in [src, a, b, dest]) t.filter = Nearest;
		planeShader.source = src;
		planeShader.inner = g.inner;
		render(planeFx, a);
		var cur = a, other = b;
		passShader.size.set(w, h);
		for (horizontal in [true, false]) {
			var k = quarters(horizontal ? g.blurX : g.blurY);
			if (k[0] == 0) continue;
			passShader.N = k[0];
			passShader.den = k[1];
			passShader.endQ = k[2];
			passShader.dir.set(horizontal ? 1 : 0, horizontal ? 0 : 1);
			for (q in 0...g.quality) {
				passShader.source = cur;
				render(passFx, other);
				var t = cur;
				cur = other;
				other = t;
				passes++;
			}
		}
		var alpha8 = Std.int(g.alpha * 255);
		for (v in 0...256) {
			var ga = Std.int((Std.int(Math.min(255, v * g.strength)) * alpha8 + 127) / 255);
			tableBytes.setInt32(v * 4, ga | 0xFF000000);
		}
		table.uploadPixels(new hxd.Pixels(256, 1, tableBytes, RGBA));
		glowShader.source = src;
		glowShader.plane = cur;
		glowShader.table = table;
		var c = g.color;
		glowShader.color.set((c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF);
		glowShader.inner = g.inner;
		glowShader.knockout = g.knockout;
		render(glowFx, dest);
	}
}

private class PlaneShader extends h3d.shader.ScreenShader {
	static var SRC = {
		@param var source : Sampler2D;
		@const var inner : Bool;
		function fragment() {
			var v = floor(source.get(calculatedUV).a * 255.0 + 0.5);
			if( inner ) v = 255.0 - v;
			pixelColor = vec4(v / 255.0, 0, 0, 1);
		}
	};
}

private class PassShader extends h3d.shader.ScreenShader {
	static var SRC = {
		@param var source : Sampler2D;
		@param var size : Vec2;
		@param var dir : Vec2;
		@const var N : Int;
		@param var den : Float;
		@param var endQ : Float;
		function value(p : Vec2) : Float {
			var v = floor(source.get(p / size).r * 255.0 + 0.5);
			return (p.x > 0.0 && p.y > 0.0 && p.x < size.x && p.y < size.y) ? v : 0.0;
		}
		function idiv(a : Float, d : Float) : Float {
			var q = floor(a / d);
			if( q * d > a ) q -= 1.0;
			if( (q + 1.0) * d <= a ) q += 1.0;
			return q;
		}
		function fragment() {
			var p = floor(calculatedUV * size) + vec2(0.5);
			var sum = 0.0;
			@unroll for( k in -N + 1...N ) sum += value(p + dir * float(k));
			var ends = value(p - dir * float(N)) + value(p + dir * float(N));
			pixelColor = vec4(idiv(sum * 4.0 + ends * endQ, den) / 255.0, 0, 0, 1);
		}
	};
}

private class GlowShader extends h3d.shader.ScreenShader {
	static var SRC = {
		@param var source : Sampler2D;
		@param var plane : Sampler2D;
		@param var table : Sampler2D;
		@param var color : Vec3;
		@const var inner : Bool;
		@const var knockout : Bool;
		function idiv(a : Float, d : Float) : Float {
			var q = floor(a / d);
			if( q * d > a ) q -= 1.0;
			if( (q + 1.0) * d <= a ) q += 1.0;
			return q;
		}
		function premul(c : Float, a : Float) : Float {
			return idiv(c * a + 127.0, 255.0);
		}
		function fragment() {
			var s = floor(source.get(calculatedUV) * 255.0 + vec4(0.5));
			var pv = floor(plane.get(calculatedUV).r * 255.0 + 0.5);
			var ga = floor(table.get(vec2((pv + 0.5) / 256.0, 0.5)).r * 255.0 + 0.5);
			var sa = s.a;
			var oa = 0.0;
			var orr = 0.0;
			var og = 0.0;
			var ob = 0.0;
			if( inner ) {
				if( knockout ) {
					oa = idiv(ga * sa + 127.0, 255.0);
					orr = premul(color.r, oa);
					og = premul(color.g, oa);
					ob = premul(color.b, oa);
				} else {
					var inv = 255.0 - ga;
					oa = sa;
					orr = idiv(premul(color.r, sa) * ga + s.r * inv + 127.0, 255.0);
					og = idiv(premul(color.g, sa) * ga + s.g * inv + 127.0, 255.0);
					ob = idiv(premul(color.b, sa) * ga + s.b * inv + 127.0, 255.0);
				}
			} else if( knockout ) {
				var gk = idiv(ga * (255.0 - sa) + 127.0, 255.0);
				oa = gk;
				orr = premul(color.r, gk);
				og = premul(color.g, gk);
				ob = premul(color.b, gk);
			} else {
				var inv = 256.0 - sa;
				oa = sa + floor(ga * inv / 256.0);
				orr = s.r + floor(premul(color.r, ga) * inv / 256.0);
				og = s.g + floor(premul(color.g, ga) * inv / 256.0);
				ob = s.b + floor(premul(color.b, ga) * inv / 256.0);
			}
			oa = min(oa, 255.0);
			pixelColor = vec4(min(orr, oa), min(og, oa), min(ob, oa), oa) / 255.0;
		}
	};
}

private class MatrixShader extends h3d.shader.ScreenShader {
	static var SRC = {
		@param var source : Sampler2D;
		@param var hiR : Vec4;
		@param var hiG : Vec4;
		@param var hiB : Vec4;
		@param var hiA : Vec4;
		@param var hiOff : Vec4;
		@param var loR : Vec4;
		@param var loG : Vec4;
		@param var loB : Vec4;
		@param var loA : Vec4;
		@param var loOff : Vec4;
		function idiv(a : Float, d : Float) : Float {
			var q = floor(a / d);
			if( q * d > a ) q -= 1.0;
			if( (q + 1.0) * d <= a ) q += 1.0;
			return q;
		}
		function unpremul(c : Float, a : Float) : Float {
			return a == 0.0 ? 0.0 : min(255.0, idiv(c * 255.0 + floor(a * 0.5), a));
		}
		function premul(c : Float, a : Float) : Float {
			return idiv(c * a + 127.0, 255.0);
		}
		function row(hi : Vec4, lo : Vec4, hiOff : Float, loOff : Float, c : Vec4) : Float {
			var h = hi.x * c.x + hi.y * c.y + hi.z * c.z + hi.w * c.w + hiOff;
			var l = lo.x * c.x + lo.y * c.y + lo.z * c.z + lo.w * c.w + loOff;
			var u = h + floor(l / 256.0);
			return clamp(floor(u / 256.0), 0.0, 255.0);
		}
		function fragment() {
			var s = floor(source.get(calculatedUV) * 255.0 + vec4(0.5));
			var a = s.a;
			var c = vec4(unpremul(s.r, a), unpremul(s.g, a), unpremul(s.b, a), a);
			var na = row(hiA, loA, hiOff.w, loOff.w, c);
			var nr = premul(row(hiR, loR, hiOff.x, loOff.x, c), na);
			var ng = premul(row(hiG, loG, hiOff.y, loOff.y, c), na);
			var nb = premul(row(hiB, loB, hiOff.z, loOff.z, c), na);
			pixelColor = vec4(nr, ng, nb, na) / 255.0;
		}
	};
}
