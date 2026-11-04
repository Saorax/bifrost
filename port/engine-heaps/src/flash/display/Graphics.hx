package flash.display;

@:access(flash.geom.Rectangle)
class Graphics {
	public var __portAdditive:Bool;
	public var __portGroups:Array<Int>;

	@:noCompletion public var __version(default, null):Int = 0;
	@:noCompletion public var fills(default, null):Array<port.engine.art.VectorRecord.FillRecord> = [];
	@:noCompletion public var strokes(default, null):Array<port.engine.art.VectorRecord.StrokeRecord> = [];

	var fill:port.engine.art.VectorRecord.FillRecord;
	var stroke:port.engine.art.VectorRecord.StrokeRecord;

	@:noCompletion public var bounds(default, null):flash.geom.Rectangle;

	var padding = 0.0;
	var penX = 0.0;
	var penY = 0.0;

	public function beginBitmapFill(bitmap:flash.display.BitmapData, ?matrix:flash.geom.Matrix, repeat:Bool = true, smooth:Bool = false):Void {
		__version++;
		var paint = new port.engine.art.VectorRecord.Paint(port.engine.art.VectorRecord.Paint.BITMAP);
		paint.bitmap = bitmap;
		paint.matrix = matrixData(matrix);
		paint.repeat = repeat;
		paint.smooth = smooth;
		startFill(paint);
	}

	public function beginFill(color:Int = 0, alpha:Float = 1):Void {
		__version++;
		startFill(port.engine.art.VectorRecord.Paint.solid(color, alpha));
	}

	public function beginGradientFill(type:flash.display.GradientType, colors:Array<Int>, alphas:Array<Float>, ratios:Array<Int>, ?matrix:flash.geom.Matrix, ?spreadMethod:flash.display.SpreadMethod, ?interpolationMethod:flash.display.InterpolationMethod, focalPointRatio:Float = 0):Void {
		__version++;
		startFill(gradient(type, colors, alphas, ratios, matrix, spreadMethod, interpolationMethod, focalPointRatio));
	}

	public function beginShaderFill(shader:flash.display.Shader, ?matrix:flash.geom.Matrix):Void {}

	public function clear():Void {
		__version++;
		bounds = null;
		padding = 0;
		penX = penY = 0;
		fills = [];
		strokes = [];
		fill = null;
		stroke = null;
	}

	public function copyFrom(sourceGraphics:flash.display.Graphics):Void {
		__version++;
		bounds = sourceGraphics.bounds != null ? sourceGraphics.bounds.clone() : null;
		padding = sourceGraphics.padding;
		penX = sourceGraphics.penX;
		penY = sourceGraphics.penY;
		__portAdditive = sourceGraphics.__portAdditive;
		__portGroups = sourceGraphics.__portGroups;
		var openFill = sourceGraphics.fill, openStroke = sourceGraphics.stroke;
		fills = [for (f in sourceGraphics.fills) f == openFill ? f.copy() : f];
		strokes = [for (s in sourceGraphics.strokes) s == openStroke ? s.copy() : s];
		fill = null;
		stroke = null;
		var source = sourceGraphics.__shared();
		__template = source != null ? source : sourceGraphics;
		__templateVersion = __template.__version;
		__copiedVersion = __version;
	}

	@:noCompletion var __template:flash.display.Graphics;
	@:noCompletion var __templateVersion = 0;
	@:noCompletion var __copiedVersion = -1;

	@:noCompletion public function __shared():flash.display.Graphics {
		return __template != null && __version == __copiedVersion && __template.__version == __templateVersion
			? __template : null;
	}

	public function cubicCurveTo(controlX1:Float, controlY1:Float, controlX2:Float, controlY2:Float, anchorX:Float, anchorY:Float):Void {
		__version++;
		var x0 = penX, y0 = penY;
		segment(6, 6, controlX1, controlY1, controlX2, controlY2, anchorX, anchorY);
		for (i in 1...17) {
			var t = i / 16, u = 1 - t;
			point(u * u * u * x0 + 3 * u * u * t * controlX1 + 3 * u * t * t * controlX2 + t * t * t * anchorX,
				u * u * u * y0 + 3 * u * u * t * controlY1 + 3 * u * t * t * controlY2 + t * t * t * anchorY);
		}
		penX = anchorX;
		penY = anchorY;
	}

	public function curveTo(controlX:Float, controlY:Float, anchorX:Float, anchorY:Float):Void {
		__version++;
		var x0 = penX, y0 = penY;
		segment(3, 4, controlX, controlY, anchorX, anchorY);
		point(anchorX, anchorY);
		inline function extreme(p0:Float, c:Float, p2:Float):Float {
			var d = p0 - 2 * c + p2;
			return d == 0 ? -1 : (p0 - c) / d;
		}
		var tx = extreme(x0, controlX, anchorX), ty = extreme(y0, controlY, anchorY);
		if (tx > 0 && tx < 1) {
			var u = 1 - tx;
			point(u * u * x0 + 2 * u * tx * controlX + tx * tx * anchorX, u * u * y0 + 2 * u * tx * controlY + tx * tx * anchorY);
		}
		if (ty > 0 && ty < 1) {
			var u = 1 - ty;
			point(u * u * x0 + 2 * u * ty * controlX + ty * ty * anchorX, u * u * y0 + 2 * u * ty * controlY + ty * ty * anchorY);
		}
		penX = anchorX;
		penY = anchorY;
	}

	public function drawCircle(x:Float, y:Float, radius:Float):Void {
		__version++;
		if (radius <= 0) return;
		box(x - radius, y - radius, radius * 2, radius * 2);
		ellipsePath(x, y, radius, radius);
	}

	public function drawEllipse(x:Float, y:Float, width:Float, height:Float):Void {
		__version++;
		if (width <= 0 || height <= 0) return;
		box(x, y, width, height);
		ellipsePath(x + width / 2, y + height / 2, width / 2, height / 2);
	}

	public function drawGraphicsData(graphicsData:openfl.Vector<flash.display.IGraphicsData>):Void {
		if (graphicsData == null) return;
		for (graphics in graphicsData) {
			if (graphics == null) continue;
			if (Std.isOfType(graphics, flash.display.GraphicsSolidFill)) {
				var fill:flash.display.GraphicsSolidFill = cast graphics;
				beginFill(fill.color, fill.alpha);
			} else if (Std.isOfType(graphics, flash.display.GraphicsBitmapFill)) {
				var bitmapFill:flash.display.GraphicsBitmapFill = cast graphics;
				beginBitmapFill(bitmapFill.bitmapData, bitmapFill.matrix, bitmapFill.repeat, bitmapFill.smooth);
			} else if (Std.isOfType(graphics, flash.display.GraphicsGradientFill)) {
				var g:flash.display.GraphicsGradientFill = cast graphics;
				beginGradientFill(g.type, g.colors, g.alphas, g.ratios, g.matrix, g.spreadMethod, g.interpolationMethod, g.focalPointRatio);
			} else if (Std.isOfType(graphics, flash.display.GraphicsStroke)) {
				var stroke:flash.display.GraphicsStroke = cast graphics;
				if (stroke.fill != null) {
					var thickness:Null<Float> = stroke.thickness;
					if (Math.isNaN(thickness)) thickness = null;
					if (Std.isOfType(stroke.fill, flash.display.GraphicsSolidFill)) {
						var fill:flash.display.GraphicsSolidFill = cast stroke.fill;
						lineStyle(thickness, fill.color, fill.alpha, stroke.pixelHinting, stroke.scaleMode, stroke.caps, stroke.joints,
							stroke.miterLimit);
					} else if (Std.isOfType(stroke.fill, flash.display.GraphicsBitmapFill)) {
						var bitmapFill:flash.display.GraphicsBitmapFill = cast stroke.fill;
						lineStyle(thickness, 0, 1, stroke.pixelHinting, stroke.scaleMode, stroke.caps, stroke.joints, stroke.miterLimit);
						lineBitmapStyle(bitmapFill.bitmapData, bitmapFill.matrix, bitmapFill.repeat, bitmapFill.smooth);
					} else if (Std.isOfType(stroke.fill, flash.display.GraphicsGradientFill)) {
						var g:flash.display.GraphicsGradientFill = cast stroke.fill;
						lineStyle(thickness, 0, 1, stroke.pixelHinting, stroke.scaleMode, stroke.caps, stroke.joints, stroke.miterLimit);
						lineGradientStyle(g.type, g.colors, g.alphas, g.ratios, g.matrix, g.spreadMethod, g.interpolationMethod,
							g.focalPointRatio);
					}
				} else {
					lineStyle();
				}
			} else if (Std.isOfType(graphics, flash.display.GraphicsPath)) {
				var path:flash.display.GraphicsPath = cast graphics;
				drawPath(path.commands, path.data, path.winding);
			} else if (Std.isOfType(graphics, flash.display.GraphicsEndFill)) {
				endFill();
			}
		}
	}
	public function drawPath(commands:openfl.Vector<Int>, data:openfl.Vector<Float>, ?winding:flash.display.GraphicsPathWinding):Void {
		__version++;
		if (commands == null || data == null) return;
		if (fill != null) reserve(fill.commands, fill.data, commands.length + 1, data.length + 2);
		if (stroke != null) reserve(stroke.commands, stroke.data, commands.length + 1, data.length + 2);
		var d = 0;
		for (i in 0...commands.length) {
			switch (commands[i]) {
				case 1: moveTo(data[d], data[d + 1]); d += 2;
				case 2: lineTo(data[d], data[d + 1]); d += 2;
				case 3: curveTo(data[d], data[d + 1], data[d + 2], data[d + 3]); d += 4;
				case 4: moveTo(data[d + 2], data[d + 3]); d += 4;
				case 5: lineTo(data[d + 2], data[d + 3]); d += 4;
				case 6: cubicCurveTo(data[d], data[d + 1], data[d + 2], data[d + 3], data[d + 4], data[d + 5]); d += 6;
				default:
			}
		}
	}
	public function drawQuads(rects:openfl.Vector<Float>, ?indices:openfl.Vector<Int>, ?transforms:openfl.Vector<Float>):Void {}

	public function drawRect(x:Float, y:Float, width:Float, height:Float):Void {
		__version++;
		if (width == 0 && height == 0) return;
		box(x, y, width, height);
		var x0 = penX, y0 = penY;
		moveTo(x, y);
		lineTo(x + width, y);
		lineTo(x + width, y + height);
		lineTo(x, y + height);
		lineTo(x, y);
		penX = x0;
		penY = y0;
	}

	public function drawRoundRect(x:Float, y:Float, width:Float, height:Float, ellipseWidth:Float, ?ellipseHeight:Float):Void {
		__version++;
		if (width == 0 && height == 0) return;
		box(x, y, width, height);
		var rx = ellipseWidth / 2, ry = (ellipseHeight == null ? ellipseWidth : ellipseHeight) / 2;
		roundRectPath(x, y, width, height, rx, ry, rx, ry, rx, ry, rx, ry);
	}

	public function drawRoundRectComplex(x:Float, y:Float, width:Float, height:Float, topLeftRadius:Float, topRightRadius:Float, bottomLeftRadius:Float, bottomRightRadius:Float):Void {
		__version++;
		if (width <= 0 || height <= 0) return;
		box(x, y, width, height);
		roundRectPath(x, y, width, height, topLeftRadius, topLeftRadius, topRightRadius, topRightRadius,
			bottomRightRadius, bottomRightRadius, bottomLeftRadius, bottomLeftRadius);
	}

	public function drawTriangles(vertices:openfl.Vector<Float>, ?indices:openfl.Vector<Int>, ?uvtData:openfl.Vector<Float>, ?culling:flash.display.TriangleCulling):Void {
		__version++;
		if (vertices == null) return;
		var i = 0;
		while (i + 1 < vertices.length) {
			point(vertices[i], vertices[i + 1]);
			i += 2;
		}
		if (fill == null) return;
		inline function corner(k:Int, move:Bool) {
			fill.commands.push(move ? 1 : 2);
			fill.data.push(vertices[k * 2]);
			fill.data.push(vertices[k * 2 + 1]);
		}
		var count = indices != null ? indices.length : Std.int(vertices.length / 2);
		var t = 0;
		while (t + 2 < count) {
			for (j in 0...3) corner(indices != null ? indices[t + j] : t + j, j == 0);
			t += 3;
		}
	}

	public function endFill():Void {
		__version++;
		fill = null;
	}

	public function lineBitmapStyle(bitmap:flash.display.BitmapData, ?matrix:flash.geom.Matrix, repeat:Bool = true, smooth:Bool = false):Void {
		__version++;
		if (stroke == null) return;
		var paint = new port.engine.art.VectorRecord.Paint(port.engine.art.VectorRecord.Paint.BITMAP);
		paint.bitmap = bitmap;
		paint.matrix = matrixData(matrix);
		paint.repeat = repeat;
		paint.smooth = smooth;
		stroke.paint = paint;
	}

	public function lineGradientStyle(type:flash.display.GradientType, colors:Array<Int>, alphas:Array<Float>, ratios:Array<Int>, ?matrix:flash.geom.Matrix, ?spreadMethod:flash.display.SpreadMethod, ?interpolationMethod:flash.display.InterpolationMethod, focalPointRatio:Float = 0):Void {
		__version++;
		if (stroke == null) return;
		stroke.paint = gradient(type, colors, alphas, ratios, matrix, spreadMethod, interpolationMethod, focalPointRatio);
	}

	public function lineStyle(?thickness:Float, color:Int = 0, alpha:Float = 1, pixelHinting:Bool = false, ?scaleMode:flash.display.LineScaleMode, ?caps:flash.display.CapsStyle, ?joints:flash.display.JointStyle, miterLimit:Float = 3):Void {
		__version++;
		padding = thickness != null && thickness > 0 ? thickness / 2 : 0;
		if (thickness == null || Math.isNaN(thickness)) {
			stroke = null;
			return;
		}
		stroke = new port.engine.art.VectorRecord.StrokeRecord(thickness < 0 ? 0 : thickness > 255 ? 255 : thickness,
			port.engine.art.VectorRecord.Paint.solid(color, alpha));
		stroke.pixelHinting = pixelHinting;
		stroke.scaleMode = scaleMode != null ? (scaleMode : String) : "normal";
		stroke.caps = caps != null ? (caps : String) : "round";
		stroke.joints = joints != null ? (joints : String) : "round";
		stroke.miterLimit = miterLimit;
		strokes.push(stroke);
	}

	public function lineTo(x:Float, y:Float):Void {
		__version++;
		segment(2, 2, x, y);
		point(penX, penY);
		point(x, y);
		penX = x;
		penY = y;
	}

	public function moveTo(x:Float, y:Float):Void {
		__version++;
		penX = x;
		penY = y;
		if (fill != null) {
			fill.commands.push(1);
			fill.data.push(x);
			fill.data.push(y);
		}
		if (stroke != null) {
			stroke.commands.push(1);
			stroke.data.push(x);
			stroke.data.push(y);
		}
	}

	public function overrideBlendMode(blendMode:flash.display.BlendMode):Void {}
	public function readGraphicsData(recurse:Bool = true):openfl.Vector<flash.display.IGraphicsData> {
		var out = new openfl.Vector<flash.display.IGraphicsData>();
		__readInto(out, __owner, recurse, null);
		return out;
	}

	static function __readInto(out:openfl.Vector<flash.display.IGraphicsData>, o:flash.display.DisplayObject, recurse:Bool,
			space:flash.geom.Matrix):Void {
		if (o == null) return;
		var g:flash.display.Graphics = Std.isOfType(o, flash.display.Shape) ? (cast o : flash.display.Shape).graphics
			: Std.isOfType(o, flash.display.Sprite) ? (cast o : flash.display.Sprite).graphics : null;
		if (g != null) g.__readOwn(out, space);
		if (recurse && Std.isOfType(o, flash.display.DisplayObjectContainer)) {
			var c:flash.display.DisplayObjectContainer = cast o;
			for (i in 0...c.numChildren) {
				var child = c.getChildAt(i);
				if (child == null) continue;
				var m = child.transform.matrix;
				if (space != null) m.concat(space);
				__readInto(out, child, recurse, m);
			}
		}
	}

	function __readOwn(out:openfl.Vector<flash.display.IGraphicsData>, space:flash.geom.Matrix):Void {
		for (f in fills) {
			out.push(paintData(f.paint, space));
			out.push(pathData(f.commands, f.data, space));
			out.push(new flash.display.GraphicsEndFill());
		}
		for (st in strokes) {
			var scaleMode:flash.display.LineScaleMode = st.scaleMode;
			var caps:flash.display.CapsStyle = st.caps;
			var joints:flash.display.JointStyle = st.joints;
			var stroke = new flash.display.GraphicsStroke(st.thickness, st.pixelHinting, scaleMode, caps, joints, st.miterLimit,
				cast paintData(st.paint, space));
			out.push(stroke);
			out.push(pathData(st.commands, st.data, space));
		}
	}

	static function paintData(p:port.engine.art.VectorRecord.Paint, space:flash.geom.Matrix):flash.display.IGraphicsData {
		var m = p.matrix == null ? null : new flash.geom.Matrix(p.matrix[0], p.matrix[1], p.matrix[2], p.matrix[3], p.matrix[4], p.matrix[5]);
		if (m != null && space != null) m.concat(space);
		return switch (p.kind) {
			case port.engine.art.VectorRecord.Paint.BITMAP: new flash.display.GraphicsBitmapFill(p.bitmap, m, p.repeat, p.smooth);
			case port.engine.art.VectorRecord.Paint.LINEAR | port.engine.art.VectorRecord.Paint.RADIAL:
				var type:flash.display.GradientType = p.kind == port.engine.art.VectorRecord.Paint.RADIAL ? "radial" : "linear";
				var spread:flash.display.SpreadMethod = p.spread;
				var interpolation:flash.display.InterpolationMethod = p.interpolation;
				new flash.display.GraphicsGradientFill(type, p.colors.copy(), p.alphas.copy(), p.ratios.copy(), m, spread,
					interpolation, p.focal);
			default: new flash.display.GraphicsSolidFill(p.color, p.alpha);
		}
	}

	static function pathData(commands:port.engine.art.VectorRecord.PathCommands, data:port.engine.art.VectorRecord.PathNumbers,
			space:flash.geom.Matrix):flash.display.GraphicsPath {
		var n = commands.length;
		var ca = new Array<Int>();
		if (n > 0) ca[n - 1] = 0;
		for (i in 0...n) ca[i] = commands[i];
		var m = data.length;
		var da = new Array<Float>();
		if (m > 0) da[m - 1] = 0;
		if (space == null) {
			for (i in 0...m) da[i] = data[i];
		} else {
			var i = 0;
			while (i + 1 < m) {
				var x = data[i], y = data[i + 1];
				da[i] = space.a * x + space.c * y + space.tx;
				da[i + 1] = space.b * x + space.d * y + space.ty;
				i += 2;
			}
			if (i < m) da[i] = data[i];
		}
		return new flash.display.GraphicsPath(openfl.Vector.ofArray(ca), openfl.Vector.ofArray(da));
	}

	@:noCompletion public function __portTrim():Void {
		for (f in fills) {
			f.commands = f.commands.copy();
			f.data = f.data.copy();
		}
		for (s in strokes) {
			s.commands = s.commands.copy();
			s.data = s.data.copy();
		}
		fill = null;
		stroke = null;
	}

	@:noCompletion public function __portRecordBytes():Float {
		var n = 0.0;
		for (f in fills) n += 64 + f.commands.length * 4.0 + f.data.length * 8.0;
		for (s in strokes) n += 64 + s.commands.length * 4.0 + s.data.length * 8.0;
		return n;
	}

	@:noCompletion public function __portSetBounds(x:Float, y:Float, width:Float, height:Float):Void {
		if (bounds == null) bounds = new flash.geom.Rectangle();
		bounds.setTo(x, y, width, height);
	}

	@:noCompletion public function __addBounds(rect:flash.geom.Rectangle, matrix:flash.geom.Matrix):Void {
		if (bounds == null) return;
		var out = new flash.geom.Rectangle();
		bounds.__transform(out, matrix);
		rect.__expand(out.x, out.y, out.width, out.height);
	}

	@:noCompletion public function __hitTest(px:Float, py:Float, shapeFlag:Bool):Bool {
		if (bounds == null) return false;
		if (!(px > bounds.x && py > bounds.y && bounds.contains(px, py))) return false;
		if (!shapeFlag) return true;
		if (bounds.width == 0 || bounds.height == 0) return false;
		for (f in fills) if (insideFill(f.commands, f.data, px, py)) return true;
		for (s in strokes) {
			var half = Math.max(s.thickness, 1) / 2;
			if (nearStroke(s.commands, s.data, px, py, half * half)) return true;
		}
		return false;
	}

	static function edges(commands:port.engine.art.VectorRecord.PathCommands, data:port.engine.art.VectorRecord.PathNumbers, close:Bool, edge:Float->Float->Float->Float->Void):Void {
		var d = 0, x = 0.0, y = 0.0, sx = 0.0, sy = 0.0, open = false;
		for (c in commands) {
			switch ((c:Int)) {
				case 1:
					if (close && open && (x != sx || y != sy)) edge(x, y, sx, sy);
					x = sx = data[d++];
					y = sy = data[d++];
					open = true;
				case 2:
					var nx = data[d++], ny = data[d++];
					edge(x, y, nx, ny);
					x = nx;
					y = ny;
				case 3:
					var cx = data[d++], cy = data[d++], ax = data[d++], ay = data[d++];
					var lx = x, ly = y;
					for (i in 1...9) {
						var t = i / 8, u = 1 - t;
						var nx = u * u * x + 2 * u * t * cx + t * t * ax, ny = u * u * y + 2 * u * t * cy + t * t * ay;
						edge(lx, ly, nx, ny);
						lx = nx;
						ly = ny;
					}
					x = ax;
					y = ay;
				case 6:
					var c1x = data[d++], c1y = data[d++], c2x = data[d++], c2y = data[d++], ax = data[d++], ay = data[d++];
					var lx = x, ly = y;
					for (i in 1...17) {
						var t = i / 16, u = 1 - t;
						var nx = u * u * u * x + 3 * u * u * t * c1x + 3 * u * t * t * c2x + t * t * t * ax;
						var ny = u * u * u * y + 3 * u * u * t * c1y + 3 * u * t * t * c2y + t * t * t * ay;
						edge(lx, ly, nx, ny);
						lx = nx;
						ly = ny;
					}
					x = ax;
					y = ay;
				default:
			}
		}
		if (close && open && (x != sx || y != sy)) edge(x, y, sx, sy);
	}

	static function insideFill(commands:port.engine.art.VectorRecord.PathCommands, data:port.engine.art.VectorRecord.PathNumbers, px:Float, py:Float):Bool {
		var crossings = 0;
		edges(commands, data, true, function(x0, y0, x1, y1) {
			if ((y0 > py) != (y1 > py) && px < x0 + (py - y0) * (x1 - x0) / (y1 - y0)) crossings++;
		});
		return crossings & 1 == 1;
	}

	static function nearStroke(commands:port.engine.art.VectorRecord.PathCommands, data:port.engine.art.VectorRecord.PathNumbers, px:Float, py:Float, limit:Float):Bool {
		var near = false;
		edges(commands, data, false, function(x0, y0, x1, y1) {
			if (near) return;
			var dx = x1 - x0, dy = y1 - y0, len = dx * dx + dy * dy;
			var t = len == 0 ? 0 : ((px - x0) * dx + (py - y0) * dy) / len;
			if (t < 0) t = 0 else if (t > 1) t = 1;
			var ex = x0 + t * dx - px, ey = y0 + t * dy - py;
			if (ex * ex + ey * ey <= limit) near = true;
		});
		return near;
	}

	function box(x:Float, y:Float, width:Float, height:Float):Void {
		point(x, y);
		point(x + width, y + height);
	}

	function point(x:Float, y:Float):Void {
		var left = x - padding, top = y - padding, right = x + padding, bottom = y + padding;
		if (bounds == null) {
			bounds = new flash.geom.Rectangle(left, top, right - left, bottom - top);
			return;
		}
		var r = bounds.x + bounds.width, b = bounds.y + bounds.height;
		if (left < bounds.x) bounds.x = left;
		if (top < bounds.y) bounds.y = top;
		if (right > r) r = right;
		if (bottom > b) b = bottom;
		bounds.width = r - bounds.x;
		bounds.height = b - bounds.y;
	}

	function startFill(paint:port.engine.art.VectorRecord.Paint):Void {
		fill = new port.engine.art.VectorRecord.FillRecord(paint);
		fills.push(fill);
	}

	function segment(command:Int, count:Int, a:Float, b:Float, c = 0., d = 0., e = 0., f = 0.):Void {
		if (fill != null) addSegment(fill.commands, fill.data, command, count, a, b, c, d, e, f);
		if (stroke != null) addSegment(stroke.commands, stroke.data, command, count, a, b, c, d, e, f);
	}

	static function reserve(commands:port.engine.art.VectorRecord.PathCommands, data:port.engine.art.VectorRecord.PathNumbers,
			moreCommands:Int, moreNumbers:Int):Void {
		var n = commands.length;
		commands[n + moreCommands - 1] = 0;
		commands.resize(n);
		var m = data.length;
		data[m + moreNumbers - 1] = 0;
		data.resize(m);
	}

	function addSegment(commands:port.engine.art.VectorRecord.PathCommands, data:port.engine.art.VectorRecord.PathNumbers, command:Int, count:Int, a:Float, b:Float, c:Float,
			d:Float, e:Float, f:Float):Void {
		if (commands.length == 0) {
			commands.push(1);
			data.push(penX);
			data.push(penY);
		}
		commands.push(command);
		data.push(a);
		data.push(b);
		if (count > 2) {
			data.push(c);
			data.push(d);
			if (count > 4) {
				data.push(e);
				data.push(f);
			}
		}
	}

	function ellipsePath(cx:Float, cy:Float, rx:Float, ry:Float):Void {
		var x0 = penX, y0 = penY, b = bounds == null ? null : bounds.clone();
		moveTo(cx + rx, cy);
		var k = 1 / Math.cos(Math.PI / 8);
		for (i in 0...8) {
			var mid = (i + 0.5) * Math.PI / 4, end = (i + 1) * Math.PI / 4;
			curveTo(cx + Math.cos(mid) * rx * k, cy + Math.sin(mid) * ry * k, cx + Math.cos(end) * rx, cy + Math.sin(end) * ry);
		}
		bounds = b;
		if (b == null) box(cx - rx, cy - ry, rx * 2, ry * 2);
		penX = x0;
		penY = y0;
	}

	function roundRectPath(x:Float, y:Float, w:Float, h:Float, tlx:Float, tly:Float, trx:Float, try_:Float, brx:Float,
			bry:Float, blx:Float, bly:Float):Void {
		var b = bounds == null ? null : bounds.clone(), x0 = penX, y0 = penY;
		inline function clampX(r:Float) return Math.max(0, Math.min(r, w / 2));
		inline function clampY(r:Float) return Math.max(0, Math.min(r, h / 2));
		tlx = clampX(tlx); trx = clampX(trx); brx = clampX(brx); blx = clampX(blx);
		tly = clampY(tly); try_ = clampY(try_); bry = clampY(bry); bly = clampY(bly);
		var k = 1 / Math.cos(Math.PI / 8);
		function corner(cx:Float, cy:Float, rx:Float, ry:Float, a0:Float) {
			if (rx <= 0 || ry <= 0) return;
			for (i in 0...2) {
				var mid = a0 + (i + 0.5) * Math.PI / 4, end = a0 + (i + 1) * Math.PI / 4;
				curveTo(cx + Math.cos(mid) * rx * k, cy + Math.sin(mid) * ry * k, cx + Math.cos(end) * rx, cy + Math.sin(end) * ry);
			}
		}
		moveTo(x + w, y + h - bry);
		corner(x + w - brx, y + h - bry, brx, bry, 0);
		lineTo(x + blx, y + h);
		corner(x + blx, y + h - bly, blx, bly, Math.PI / 2);
		lineTo(x, y + tly);
		corner(x + tlx, y + tly, tlx, tly, Math.PI);
		lineTo(x + w - trx, y);
		corner(x + w - trx, y + try_, trx, try_, Math.PI * 1.5);
		lineTo(x + w, y + h - bry);
		bounds = b;
		penX = x0;
		penY = y0;
	}

	static function gradient(type:flash.display.GradientType, colors:Array<Int>, alphas:Array<Float>, ratios:Array<Int>,
			matrix:flash.geom.Matrix, spreadMethod:flash.display.SpreadMethod, interpolationMethod:flash.display.InterpolationMethod,
			focalPointRatio:Float):port.engine.art.VectorRecord.Paint {
		var paint = new port.engine.art.VectorRecord.Paint((type : String) == "radial" ? port.engine.art.VectorRecord.Paint.RADIAL
			: port.engine.art.VectorRecord.Paint.LINEAR);
		paint.colors = colors != null ? colors.copy() : [];
		paint.alphas = alphas != null ? alphas.copy() : [];
		paint.ratios = ratios != null ? ratios.copy() : [];
		paint.matrix = matrixData(matrix);
		paint.spread = spreadMethod != null ? (spreadMethod : String) : "pad";
		paint.interpolation = interpolationMethod != null ? (interpolationMethod : String) : "rgb";
		paint.focal = focalPointRatio;
		return paint;
	}

	static function matrixData(m:flash.geom.Matrix):Array<Float> {
		return m == null ? null : [m.a, m.b, m.c, m.d, m.tx, m.ty];
	}

	@:noCompletion var __owner:flash.display.DisplayObject;

	public function new(owner:flash.display.DisplayObject) {
		__owner = owner;
	}
}
