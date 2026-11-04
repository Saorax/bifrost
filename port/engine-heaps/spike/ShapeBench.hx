class ParityShader extends h3d.shader.ScreenShader {
	static var SRC = {
		function fragment() {
			pixelColor = vec4(1, 1, 1, 1);
		}
	};
}

class CoverShader extends h3d.shader.ScreenShader {
	static var SRC = {
		@param var mask : Sampler2D;
		@param var color : Vec4;
		@const var kind : Int;
		@param var ramp : Sampler2D;
		@param var row : Float;
		@param var inv : Vec4;
		@param var invT : Vec2;
		@param var focal : Float;
		@param var spread : Int;
		@param var big : Float;
		@param var offset : Vec2;
		function fragment() {
			if( mask.get(calculatedUV).r < 0.5 ) discard;
			if( kind == 0 ) {
				pixelColor = color;
			} else {
				var p = calculatedUV * big / 4 - offset;
				var g = vec2(inv.x * p.x + inv.z * p.y + invT.x, inv.y * p.x + inv.w * p.y + invT.y);
				var t = 0.;
				if( kind == 1 ) {
					t = (g.x + 819.2) / 1638.4;
				} else {
					var f = vec2(focal * 819.2, 0);
					var d = g - f;
					var dd = dot(d, d);
					if( dd > 1e-6 ) {
						var fd = dot(f, d);
						var s = (-fd + sqrt(max(0., fd * fd - dd * (dot(f, f) - 819.2 * 819.2)))) / dd;
						t = 1 / s;
					}
				}
				if( spread == 0 ) t = clamp(t, 0., 1.);
				else if( spread == 2 ) t = fract(t);
				else {
					t = mod(t, 2.);
					if( t > 1 ) t = 2 - t;
				}
				var c = ramp.get(vec2((floor(min(t * 256, 255.)) + 0.5) / 256, row));
				pixelColor = vec4(c.rgb * c.a, c.a);
			}
		}
	};
}

class DownShader extends h3d.shader.ScreenShader {
	static var SRC = {
		@param var source : Sampler2D;
		@param var texel : Float;
		function fragment() {
			var sum = vec4(0, 0, 0, 0);
			for( j in 0...4 )
				for( i in 0...4 )
					sum += source.get(calculatedUV + vec2(float(i) - 1.5, float(j) - 1.5) * texel);
			pixelColor = vec4(sum.rgb / 16, floor(sum.a * 255 / 16 + 0.001) / 255);
		}
	};
}

class ClearShader extends h3d.shader.ScreenShader {
	static var SRC = {
		function fragment() {
			pixelColor = vec4(0, 0, 0, 0);
		}
	};
}

class Range extends h3d.prim.Primitive {
	public var source:h3d.Buffer;
	public var start = 0;
	public var count = 0;

	public function new() {}

	override function triCount()
		return count;

	override function render(engine:h3d.Engine) {
		if (count > 0)
			engine.renderTriBuffer(source, start, count);
	}
}

private typedef Path = {cmds:Array<Int>, data:Array<Float>};
private typedef Fill = {color:Int, alpha:Float, paths:Array<Path>, start:Int, count:Int, x0:Float, y0:Float, x1:Float,
	y1:Float, ?grad:Grad};
private typedef Grad = {radial:Bool, spread:Int, focal:Float, inv:Array<Float>, row:Int, ramp:Array<Int>};
private typedef Shape = {fills:Array<Fill>};
private typedef Symbol = {name:String, w:Int, h:Int, shapes:Array<Shape>};

class ShapeBench extends hxd.App {
	static inline var BIG = 1024;
	static inline var SMALL = 256;

	var done = false;

	static function main() {
		new ShapeBench();
	}

	override function render(e:h3d.Engine) {
		if (done)
			return;
		done = true;
		try {
			bench(e);
		} catch (error:Dynamic) {
			Sys.println("error: " + Std.string(error) + "\n" + haxe.CallStack.toString(haxe.CallStack.exceptionStack()));
		}
		hxd.System.exit();
	}

	static function ramp(ratios:Array<Float>, colours:Array<Int>, alphas:Array<Float>, linear:Bool):Array<Int> {
		return port.engine.art.GradientRamp.build(ratios, colours, alphas, linear);
	}

	static var grads:Array<Grad> = [];
	static var offsetX = 0.0;
	static var offsetY = 0.0;

	static function parse(text:String):Array<Symbol> {
		var symbols:Array<Symbol> = [];
		var current:Symbol = null;
		var skip = false;
		var envDx = Sys.getEnv("BH_HEAPS_DX"), envDy = Sys.getEnv("BH_HEAPS_DY");
		var dx = envDx == null ? -0.0625 : Std.parseFloat(envDx), dy = envDy == null ? 0.0 : Std.parseFloat(envDy);
		offsetX = dx;
		offsetY = dy;
		for (line in text.split("\n")) {
			var parts = line.split(" ");
			switch (parts[0]) {
				case "S":
					current = {name: parts[1], w: Std.parseInt(parts[2]), h: Std.parseInt(parts[3]), shapes: []};
					skip = current.w < 3;
					symbols.push(current);
				case "U":
					skip = true;
				case "H":
					if (!skip)
						current.shapes.push({fills: []});
				case "F":
					if (!skip)
						current.shapes[current.shapes.length - 1].fills.push({color: Std.parseInt("0x" + parts[1]),
							alpha: Std.parseFloat(parts[2]), paths: [], start: 0, count: 0, x0: 0, y0: 0, x1: 0, y1: 0});
				case "G":
					if (!skip) {
						var m = [for (v in parts[8].split(",")) Std.parseFloat(v)];
						var det = m[0] * m[3] - m[1] * m[2];
						var inv = det == 0 ? [0.0, 0, 0, 0, 0, 0] : [m[3] / det, -m[1] / det, -m[2] / det, m[0] / det,
							(m[2] * m[5] - m[3] * m[4]) / det, (m[1] * m[4] - m[0] * m[5]) / det];
						var g:Grad = {radial: parts[1] == "r", spread: parts[2] == "reflect" ? 1 : parts[2] == "repeat" ? 2 : 0,
							focal: Std.parseFloat(parts[4]), inv: inv, row: grads.length,
							ramp: ramp([for (v in parts[5].split(",")) Std.parseFloat(v)],
								[for (v in parts[6].split(",")) Std.parseInt("0x" + v)],
								[for (v in parts[7].split(",")) Std.parseFloat(v)], parts[3] == "linearRGB")};
						grads.push(g);
						current.shapes[current.shapes.length - 1].fills.push({color: 0, alpha: 1, paths: [], start: 0,
							count: 0, x0: 0, y0: 0, x1: 0, y1: 0, grad: g});
					}
				case "P":
					if (!skip) {
						var shape = current.shapes[current.shapes.length - 1];
						var fill = shape.fills[shape.fills.length - 1];
						if (fill != null) {
							var data = [for (s in parts[3].split(",")) Std.parseFloat(s)];
							for (k in 0...data.length)
								data[k] = (data[k] + (k & 1 == 0 ? dx : dy)) * 4;
							fill.paths.push({cmds: [for (s in parts[2].split(",")) Std.parseInt(s)], data: data});
						}
					}
				default:
			}
			if (skip && current != null && parts[0] == "U")
				current.shapes = null;
		}
		return [for (s in symbols) if (s.shapes != null && s.w >= 3) s];
	}

	static function fans(fill:Fill, v:hxd.FloatBuffer):Int {
		var f = new port.engine.art.PathFans();
		for (path in fill.paths)
			f.add([for (c in path.cmds) c], path.data);
		f.flush();
		var t = f.triangles;
		var i = 0;
		while (i < t.length) {
			v.push(t[i] * (2 / BIG) - 1);
			v.push(1 - t[i + 1] * (2 / BIG));
			v.push(0);
			v.push(0);
			i += 2;
		}
		var empty = f.x1 < f.x0;
		fill.x0 = empty ? 1e9 : f.x0;
		fill.y0 = empty ? 1e9 : f.y0;
		fill.x1 = empty ? -1e9 : f.x1;
		fill.y1 = empty ? -1e9 : f.y1;
		return f.count;
	}

	static function quad(v:hxd.FloatBuffer, x0:Float, y0:Float, x1:Float, y1:Float, size:Float) {
		for (p in [[x0, y0], [x1, y0], [x1, y1], [x0, y0], [x1, y1], [x0, y1]]) {
			v.push(p[0] / size * 2 - 1);
			v.push(1 - p[1] / size * 2);
			v.push(p[0] / size);
			v.push(p[1] / size);
		}
	}

	function bench(e:h3d.Engine) {
		var symbols = parse(sys.io.File.getContent(Sys.getEnv("BH_HEAPS_SHAPES")));
		var mask = new h3d.mat.Texture(BIG, BIG, [Target]);
		var scratch = new h3d.mat.Texture(BIG, BIG, [Target]);
		var out = new h3d.mat.Texture(SMALL, SMALL, [Target]);
		for (t in [mask, scratch, out]) {
			t.filter = Nearest;
			e.pushTarget(t);
			e.clear(0);
			e.popTarget();
		}
		var rows = Std.int(Math.max(1, grads.length));
		var rampPixels = hxd.Pixels.alloc(256, rows, BGRA);
		for (g in grads)
			for (i in 0...256)
				rampPixels.setPixel(i, g.row, g.ramp[i]);
		var rampTexture = new h3d.mat.Texture(256, rows);
		rampTexture.filter = Nearest;
		rampTexture.uploadPixels(rampPixels);
		var range = new Range();
		var parity = new h3d.pass.ScreenFx(new ParityShader());
		parity.pass.blend(OneMinusDstColor, Zero);
		parity.primitive = range;
		var coverShader = new CoverShader();
		coverShader.mask = mask;
		coverShader.ramp = rampTexture;
		coverShader.big = BIG;
		coverShader.offset.set(offsetX, offsetY);
		var cover = new h3d.pass.ScreenFx(coverShader);
		cover.pass.blend(One, OneMinusSrcAlpha);
		cover.primitive = range;
		var downShader = new DownShader();
		downShader.source = scratch;
		downShader.texel = 1 / BIG;
		var down = new h3d.pass.ScreenFx(downShader);
		down.pass.blend(One, OneMinusSrcAlpha);
		down.primitive = range;
		var clear = new h3d.pass.ScreenFx(new ClearShader());
		clear.pass.blend(One, Zero);
		clear.primitive = range;

		var dumpPath = Sys.getEnv("BH_HEAPS_OUT");
		var lines:Array<String> = [];
		var cpu = 0.0;
		function drawSymbol(s:Symbol):h3d.Buffer {
			var started = haxe.Timer.stamp();
			var v = new hxd.FloatBuffer();
			var tris = 0;
			var shapeQuads:Array<Int> = [];
			for (shape in s.shapes) {
				for (fill in shape.fills) {
					fill.start = tris;
					fill.count = fans(fill, v);
					tris += fill.count;
					quad(v, Math.max(0, Math.floor(fill.x0)), Math.max(0, Math.floor(fill.y0)), Math.ceil(fill.x1),
						Math.ceil(fill.y1), BIG);
					tris += 2;
				}
				shapeQuads.push(tris);
				quad(v, 0, 0, s.w, s.h, SMALL);
				quad(v, 0, 0, s.w * 4, s.h * 4, BIG);
				tris += 4;
			}
			if (tris == 0)
				return null;
			var buffer = h3d.Buffer.ofFloats(v, hxd.BufferFormat.XY_UV);
			range.source = buffer;
			cpu += haxe.Timer.stamp() - started;
			e.pushTarget(out);
			e.clear(0);
			e.popTarget();
			var q = 0;
			var reverse = Sys.getEnv("BH_HEAPS_REVERSE") == "1";
			for (shape in s.shapes) {
				e.pushTarget(mask);
				var order = shape.fills.copy();
				if (reverse)
					order.reverse();
				for (fill in order) {
					range.start = fill.start;
					range.count = fill.count;
					parity.render();
					e.popTarget();
					e.pushTarget(scratch);
					range.start = fill.start + fill.count;
					range.count = 2;
					var g = fill.grad;
					coverShader.kind = g == null ? 0 : g.radial ? 2 : 1;
					if (g != null) {
						coverShader.row = (g.row + 0.5) / rows;
						coverShader.inv.set(g.inv[0], g.inv[1], g.inv[2], g.inv[3]);
						coverShader.invT.set(g.inv[4], g.inv[5]);
						coverShader.focal = g.focal;
						coverShader.spread = g.spread;
					}
					coverShader.color = new h3d.Vector4(((fill.color >> 16) & 255) / 255 * fill.alpha,
						((fill.color >> 8) & 255) / 255 * fill.alpha, (fill.color & 255) / 255 * fill.alpha, fill.alpha);
					cover.render();
					e.popTarget();
					e.pushTarget(mask);
					range.start = fill.start;
					range.count = fill.count;
					parity.render();
				}
				e.popTarget();
				e.pushTarget(out);
				range.start = shapeQuads[q];
				range.count = 2;
				down.render();
				e.popTarget();
				e.pushTarget(scratch);
				range.start = shapeQuads[q] + 2;
				clear.render();
				e.popTarget();
				q++;
			}
			return buffer;
		}

		for (s in symbols) {
			var buffer = drawSymbol(s);
			if (buffer == null)
				continue;
			var pixels = out.capturePixels(0, 0, h2d.col.IBounds.fromValues(0, 0, s.w, s.h));
			var bytes = haxe.io.Bytes.alloc(s.w * s.h * 4);
			for (y in 0...s.h)
				for (x in 0...s.w) {
					var c = pixels.getPixel(x, y);
					var a = (c >>> 24) & 255;
					var o = (y * s.w + x) * 4;
					inline function un(v:Int):Int return a == 0 ? 0 : Std.int(Math.min(255, Math.round(v * 255 / a)));
					bytes.set(o, a);
					bytes.set(o + 1, un((c >> 16) & 255));
					bytes.set(o + 2, un((c >> 8) & 255));
					bytes.set(o + 3, un(c & 255));
				}
			lines.push(s.name + " " + s.w + " " + s.h + " " + haxe.crypto.Base64.encode(bytes));
			buffer.dispose();
		}
		if (dumpPath != null)
			sys.io.File.saveContent(dumpPath, lines.join("\n"));

		cpu = 0;
		var started = haxe.Timer.stamp();
		var buffers = [];
		for (s in symbols) {
			var b = drawSymbol(s);
			if (b != null)
				buffers.push(b);
		}
		out.capturePixels(0, 0, h2d.col.IBounds.fromValues(0, 0, 1, 1));
		var total = haxe.Timer.stamp() - started;
		for (b in buffers)
			b.dispose();
		Sys.println('${symbols.length} symbols on ${Type.getClassName(Type.getClass(e.driver))}: '
			+ '${Std.int(total * 1000)} ms in all, of which flattening and buffers ${Std.int(cpu * 1000)} ms; '
			+ '${lines.length} dumped to $dumpPath');
	}
}
