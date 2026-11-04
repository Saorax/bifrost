package port.engine.art;

class PathFans {
	public var triangles(default, null):Array<Float> = [];
	public var x0(default, null) = Math.POSITIVE_INFINITY;
	public var y0(default, null) = Math.POSITIVE_INFINITY;
	public var x1(default, null) = Math.NEGATIVE_INFINITY;
	public var y1(default, null) = Math.NEGATIVE_INFINITY;

	public var tolerance:Float;

	#if hl
	var pts:hl.Bytes = new hl.Bytes(256 * 8);
	var ptsCap = 256;
	#else
	var points:Array<Float> = [];
	#end
	var np = 0;
	var out:Array<Single> = null;
	var sx = 0.0;
	var sy = 0.0;
	var emitted = 0;

	public static var TOLERANCE:Float = {
		var t = Std.parseFloat(Sys.getEnv("BH_PORT_CURVE_TOLERANCE"));
		Math.isNaN(t) || t <= 0 ? 0.05 : t;
	};

	public function new(?tolerance:Float) {
		this.tolerance = tolerance == null ? TOLERANCE : tolerance;
	}

	public function reset():Void {
		triangles.resize(0);
		np = 0;
		x0 = y0 = Math.POSITIVE_INFINITY;
		x1 = y1 = Math.NEGATIVE_INFINITY;
		emitted = 0;
		out = null;
	}

	public function direct(vertices:Array<Single>, sx:Float, sy:Float):Void {
		out = vertices;
		this.sx = sx;
		this.sy = sy;
	}

	public var count(get, never):Int;

	function get_count():Int {
		return out != null ? emitted : Std.int(triangles.length / 6);
	}

	public function add(commands:VectorRecord.PathCommands, data:Array<Float>):Void {
		var d = 0;
		var cx = 0.0, cy = 0.0;
		#if hl
		var db = hl.Bytes.getArray(data), len = data.length;
		inline function rd(i:Int):Float return i < len ? db.getF64(i << 3) : 0.0;
		#else
		inline function rd(i:Int):Float return data[i];
		#end
		for (c in commands) {
			switch ((c:Int)) {
				case 1:
					flush();
					cx = rd(d++);
					cy = rd(d++);
					point(cx, cy);
				case 2:
					cx = rd(d++);
					cy = rd(d++);
					point(cx, cy);
				case 3:
					var qx = rd(d++), qy = rd(d++), ex = rd(d++), ey = rd(d++);
					var n = segments(cx, cy, qx, qy, ex, ey, tolerance);
					for (k in 1...n + 1) {
						var t = k / n, u = 1 - t;
						point(u * u * cx + 2 * u * t * qx + t * t * ex, u * u * cy + 2 * u * t * qy + t * t * ey);
					}
					cx = ex;
					cy = ey;
				case 6:
					var ax = rd(d++), ay = rd(d++), bx = rd(d++), by = rd(d++), ex = rd(d++), ey = rd(d++);
					var n = Std.int(Math.max(segments(cx, cy, ax, ay, bx, by, tolerance),
						segments(ax, ay, bx, by, ex, ey, tolerance)) * 2);
					if (n > 64) n = 64;
					for (k in 1...n + 1) {
						var t = k / n, u = 1 - t;
						point(u * u * u * cx + 3 * u * u * t * ax + 3 * u * t * t * bx + t * t * t * ex,
							u * u * u * cy + 3 * u * u * t * ay + 3 * u * t * t * by + t * t * t * ey);
					}
					cx = ex;
					cy = ey;
				default:
			}
		}
	}

	public function flush():Void {
		var n = np >> 1;
		if (out != null) {
			if (n >= 3) {
				var j = out.length;
				out[j + (n - 2) * 12 - 1] = 0;
				var fx:Single = pt(0) * sx - 1, fy:Single = 1 - pt(1) * sy;
				#if hl
				var b = hl.Bytes.getArray(out), p = j << 2;
				var px:Single = pt(2) * sx - 1, py:Single = 1 - pt(3) * sy;
				for (k in 1...n - 1) {
					var qx:Single = pt(k * 2 + 2) * sx - 1, qy:Single = 1 - pt(k * 2 + 3) * sy;
					b.setF32(p, fx);
					b.setF32(p + 4, fy);
					b.setF32(p + 8, 0);
					b.setF32(p + 12, 0);
					b.setF32(p + 16, px);
					b.setF32(p + 20, py);
					b.setF32(p + 24, 0);
					b.setF32(p + 28, 0);
					b.setF32(p + 32, qx);
					b.setF32(p + 36, qy);
					b.setF32(p + 40, 0);
					b.setF32(p + 44, 0);
					p += 48;
					px = qx;
					py = qy;
				}
				#else
				for (k in 1...n - 1) {
					out[j] = fx;
					out[j + 1] = fy;
					out[j + 2] = 0;
					out[j + 3] = 0;
					out[j + 4] = pt(k * 2) * sx - 1;
					out[j + 5] = 1 - pt(k * 2 + 1) * sy;
					out[j + 6] = 0;
					out[j + 7] = 0;
					out[j + 8] = pt(k * 2 + 2) * sx - 1;
					out[j + 9] = 1 - pt(k * 2 + 3) * sy;
					out[j + 10] = 0;
					out[j + 11] = 0;
					j += 12;
				}
				#end
				emitted += n - 2;
			}
			np = 0;
			return;
		}
		var fx = pt(0), fy = pt(1);
		for (k in 1...n - 1) {
			triangles.push(fx);
			triangles.push(fy);
			triangles.push(pt(k * 2));
			triangles.push(pt(k * 2 + 1));
			triangles.push(pt(k * 2 + 2));
			triangles.push(pt(k * 2 + 3));
		}
		np = 0;
	}

	inline function pt(i:Int):Float {
		#if hl
		return pts.getF64(i << 3);
		#else
		return points[i];
		#end
	}

	#if hl
	function growPoints():Void {
		var cap = ptsCap * 2;
		var b = new hl.Bytes(cap * 8);
		b.blit(0, pts, 0, np * 8);
		pts = b;
		ptsCap = cap;
	}
	#end

	public static function segments(x0:Float, y0:Float, qx:Float, qy:Float, x1:Float, y1:Float, tolerance:Float):Int {
		var ax = x0 - 2 * qx + x1, ay = y0 - 2 * qy + y1;
		var dev = Math.sqrt(ax * ax + ay * ay) / 4;
		return Std.int(Math.max(1, Math.min(64, Math.ceil(Math.sqrt(dev / tolerance)))));
	}

	inline function point(x:Float, y:Float):Void {
		#if hl
		if (np + 2 > ptsCap) growPoints();
		pts.setF64(np << 3, x);
		pts.setF64((np + 1) << 3, y);
		#else
		points[np] = x;
		points[np + 1] = y;
		#end
		np += 2;
		if (x < x0) x0 = x;
		if (y < y0) y0 = y;
		if (x > x1) x1 = x;
		if (y > y1) y1 = y;
	}
}
