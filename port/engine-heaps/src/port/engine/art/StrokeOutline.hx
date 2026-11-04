package port.engine.art;

class StrokeOutline {
	public var triangles(default, null):Array<Float> = [];
	public var x0(default, null) = Math.POSITIVE_INFINITY;
	public var y0(default, null) = Math.POSITIVE_INFINITY;
	public var x1(default, null) = Math.NEGATIVE_INFINITY;
	public var y1(default, null) = Math.NEGATIVE_INFINITY;

	var half:Float;
	var caps:String;
	var joints:String;
	var miterLimit:Float;
	var tolerance:Float;
	var points:Array<Float> = [];

	public function new(width:Float, caps:String, joints:String, miterLimit:Float, tolerance:Float = 0.05) {
		half = width / 2;
		this.caps = caps == null ? "round" : caps;
		this.joints = joints == null ? "round" : joints;
		this.miterLimit = miterLimit >= 1 ? miterLimit : 3;
		this.tolerance = tolerance;
	}

	public var count(get, never):Int;

	function get_count():Int {
		return Std.int(triangles.length / 6);
	}

	public function add(commands:VectorRecord.PathCommands, data:Array<Float>):Void {
		var d = 0;
		var cx = 0.0, cy = 0.0;
		for (c in commands) {
			switch ((c:Int)) {
				case 1:
					flush();
					cx = data[d++];
					cy = data[d++];
					point(cx, cy);
				case 2:
					cx = data[d++];
					cy = data[d++];
					point(cx, cy);
				case 3:
					var qx = data[d++], qy = data[d++], ex = data[d++], ey = data[d++];
					var n = PathFans.segments(cx, cy, qx, qy, ex, ey, tolerance);
					for (k in 1...n + 1) {
						var t = k / n, u = 1 - t;
						point(u * u * cx + 2 * u * t * qx + t * t * ex, u * u * cy + 2 * u * t * qy + t * t * ey);
					}
					cx = ex;
					cy = ey;
				case 6:
					var ax = data[d++], ay = data[d++], bx = data[d++], by = data[d++], ex = data[d++], ey = data[d++];
					var n = Std.int(Math.max(PathFans.segments(cx, cy, ax, ay, bx, by, tolerance),
						PathFans.segments(ax, ay, bx, by, ex, ey, tolerance)) * 2);
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
		var p:Array<Float> = [];
		var i = 0;
		while (i + 1 < points.length) {
			var x = points[i], y = points[i + 1];
			if (p.length == 0 || Math.abs(x - p[p.length - 2]) > 1e-6 || Math.abs(y - p[p.length - 1]) > 1e-6) {
				p.push(x);
				p.push(y);
			}
			i += 2;
		}
		points.resize(0);
		var n = p.length >> 1;
		if (n == 0 || half <= 0) return;
		if (n == 1) {
			if (caps == "round") disc(p[0], p[1]);
			else if (caps == "square") box(p[0] - half, p[1] - half, p[0] + half, p[1] + half);
			return;
		}
		var closed = n > 2 && Math.abs(p[0] - p[(n - 1) * 2]) < 1e-6 && Math.abs(p[1] - p[(n - 1) * 2 + 1]) < 1e-6;
		for (k in 0...n - 1) segment(p[k * 2], p[k * 2 + 1], p[k * 2 + 2], p[k * 2 + 3]);
		for (k in 1...n - 1) joint(p[k * 2 - 2], p[k * 2 - 1], p[k * 2], p[k * 2 + 1], p[k * 2 + 2], p[k * 2 + 3]);
		if (closed) {
			joint(p[(n - 2) * 2], p[(n - 2) * 2 + 1], p[0], p[1], p[2], p[3]);
		} else {
			cap(p[2], p[3], p[0], p[1]);
			cap(p[(n - 2) * 2], p[(n - 2) * 2 + 1], p[(n - 1) * 2], p[(n - 1) * 2 + 1]);
		}
	}

	function segment(ax:Float, ay:Float, bx:Float, by:Float):Void {
		var dx = bx - ax, dy = by - ay;
		var len = Math.sqrt(dx * dx + dy * dy);
		var nx = -dy / len * half, ny = dx / len * half;
		tri(ax + nx, ay + ny, bx + nx, by + ny, bx - nx, by - ny);
		tri(ax + nx, ay + ny, bx - nx, by - ny, ax - nx, ay - ny);
	}

	function joint(ax:Float, ay:Float, bx:Float, by:Float, cx:Float, cy:Float):Void {
		if (joints == "round") {
			disc(bx, by);
			return;
		}
		var d1x = bx - ax, d1y = by - ay, d2x = cx - bx, d2y = cy - by;
		var l1 = Math.sqrt(d1x * d1x + d1y * d1y), l2 = Math.sqrt(d2x * d2x + d2y * d2y);
		d1x /= l1;
		d1y /= l1;
		d2x /= l2;
		d2y /= l2;
		var cross = d1x * d2y - d1y * d2x;
		if (Math.abs(cross) < 1e-9 && d1x * d2x + d1y * d2y > 0) return;
		var s = cross < 0 ? 1 : -1;
		var n1x = -d1y * half * s, n1y = d1x * half * s, n2x = -d2y * half * s, n2y = d2x * half * s;
		var p1x = bx + n1x, p1y = by + n1y, p2x = bx + n2x, p2y = by + n2y;
		tri(bx, by, p1x, p1y, p2x, p2y);
		if (joints == "miter") {
			var cosTheta = -(d1x * d2x + d1y * d2y);
			var ratio = Math.sqrt(2 / (1 - cosTheta + 1e-12));
			if (ratio <= miterLimit) {
				var mx = n1x + n2x, my = n1y + n2y;
				var ml = Math.sqrt(mx * mx + my * my);
				if (ml > 1e-9) {
					var tipX = bx + mx / ml * half * ratio, tipY = by + my / ml * half * ratio;
					tri(p1x, p1y, tipX, tipY, p2x, p2y);
				}
			}
		}
	}

	function cap(ax:Float, ay:Float, bx:Float, by:Float):Void {
		if (caps == "round") {
			disc(bx, by);
		} else if (caps == "square") {
			var dx = bx - ax, dy = by - ay;
			var len = Math.sqrt(dx * dx + dy * dy);
			dx = dx / len * half;
			dy = dy / len * half;
			var nx = -dy, ny = dx;
			tri(bx + nx, by + ny, bx + nx + dx, by + ny + dy, bx - nx + dx, by - ny + dy);
			tri(bx + nx, by + ny, bx - nx + dx, by - ny + dy, bx - nx, by - ny);
		}
	}

	function disc(x:Float, y:Float):Void {
		var step = half > tolerance ? 2 * Math.acos(1 - tolerance / half) : Math.PI;
		var n = Std.int(Math.max(8, Math.min(64, Math.ceil(2 * Math.PI / step))));
		var px = x + half, py = y;
		for (k in 1...n + 1) {
			var a = 2 * Math.PI * k / n;
			var qx = x + Math.cos(a) * half, qy = y + Math.sin(a) * half;
			tri(x, y, px, py, qx, qy);
			px = qx;
			py = qy;
		}
	}

	function box(ax:Float, ay:Float, bx:Float, by:Float):Void {
		tri(ax, ay, bx, ay, bx, by);
		tri(ax, ay, bx, by, ax, by);
	}

	function tri(ax:Float, ay:Float, bx:Float, by:Float, cx:Float, cy:Float):Void {
		for (v in [ax, ay, bx, by, cx, cy]) triangles.push(v);
		bound(ax, ay);
		bound(bx, by);
		bound(cx, cy);
	}

	inline function bound(x:Float, y:Float):Void {
		if (x < x0) x0 = x;
		if (y < y0) y0 = y;
		if (x > x1) x1 = x;
		if (y > y1) y1 = y;
	}

	function point(x:Float, y:Float):Void {
		points.push(x);
		points.push(y);
	}
}
