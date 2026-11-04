package flash.display;

class DisplayObject extends flash.events.EventDispatcher implements flash.display.IBitmapDrawable {
	static var instanceCount = 0;

	public var alpha(get, set):Float;
	public var blendMode:flash.display.BlendMode = flash.display.BlendMode.NORMAL;
	public var cacheAsBitmap:Bool = false;
	public var cacheAsBitmapMatrix:flash.geom.Matrix;
	public var filters(get, set):Array<flash.filters.BitmapFilter>;
	public var height(get, set):Float;
	public var loaderInfo(get, never):flash.display.LoaderInfo;
	public var mask(default, set):flash.display.DisplayObject;
	public var metaData:Dynamic;
	public var mouseX(get, never):Float;
	public var mouseY(get, never):Float;
	public var name:String;
	public var opaqueBackground:Null<Int>;
	public var parent:flash.display.DisplayObjectContainer;
	public var root:flash.display.DisplayObject;
	public var rotation(get, set):Float;
	public var scale9Grid:flash.geom.Rectangle;
	public var scaleX(get, set):Float;
	public var scaleY(get, set):Float;
	public var scrollRect:flash.geom.Rectangle;
	public var shader:flash.display.Shader;
	public var stage:flash.display.Stage;
	public var transform(get, set):flash.geom.Transform;
	public var visible:Bool = true;
	public var width(get, set):Float;
	public var x(get, set):Float;
	public var y(get, set):Float;
	public var __portFields:Dynamic;
	public var __portTimelineNames:Dynamic;

	@:noCompletion var __transform:flash.geom.Matrix = new flash.geom.Matrix();
	@:noCompletion var __scaleX:Float = 1;
	@:noCompletion var __scaleY:Float = 1;
	@:noCompletion var __rotation:Float = 0;
	@:noCompletion var __rotationSine:Float = 0;
	@:noCompletion var __rotationCosine:Float = 1;
	@:noCompletion var __alpha:Float = 1;
	@:noCompletion var __objectTransform:flash.geom.Transform;
	@:noCompletion var __filters:Array<flash.filters.BitmapFilter>;
	@:noCompletion public var __isMask:Bool = false;

	@:noCompletion public static var __pointerX:Float = 0;
	@:noCompletion public static var __pointerY:Float = 0;
	@:noCompletion static var __hx:Float = 0;
	@:noCompletion static var __hy:Float = 0;

	function set_mask(value:flash.display.DisplayObject):flash.display.DisplayObject {
		if (mask != null) mask.__isMask = false;
		if (value != null) value.__isMask = true;
		return mask = value;
	}

	function get_mouseX():Float {
		return __toLocal(__pointerX, __pointerY) ? __hx : 0;
	}

	function get_mouseY():Float {
		return __toLocal(__pointerX, __pointerY) ? __hy : 0;
	}

	@:noCompletion static inline function __inverse(m:flash.geom.Matrix, x:Float, y:Float):Bool {
		var det = m.a * m.d - m.b * m.c;
		if (det == 0) return false;
		var px = x - m.tx, py = y - m.ty;
		__hx = (m.d * px - m.c * py) / det;
		__hy = (m.a * py - m.b * px) / det;
		return true;
	}

	@:noCompletion public function __toLocal(x:Float, y:Float):Bool {
		var chain = [];
		var o = this;
		while (o != null) {
			chain.push(o);
			o = o.parent;
		}
		var i = chain.length;
		while (i-- > 0) {
			var c = chain[i];
			if (!__inverse(c.__transform, x, y)) return false;
			x = __hx;
			y = __hy;
			if (i > 0 && c.scrollRect != null) {
				x += c.scrollRect.x;
				y += c.scrollRect.y;
			}
		}
		__hx = x;
		__hy = y;
		return true;
	}

	@:noCompletion public function __hitTest(x:Float, y:Float, lx:Float, ly:Float, shapeFlag:Bool, stack:Array<DisplayObject>,
			interactiveOnly:Bool, hitObject:DisplayObject):Bool {
		return false;
	}

	@:noCompletion public function __hitTestMask(x:Float, y:Float, lx:Float, ly:Float):Bool {
		return false;
	}

	@:noCompletion function __inMask(x:Float, y:Float):Bool {
		if (mask == null) return true;
		return mask.__toLocal(x, y) && mask.__hitTestMask(x, y, __hx, __hy);
	}

	@:noCompletion public function __interactive():Bool {
		return false;
	}

	function get_filters():Array<flash.filters.BitmapFilter> {
		return __filters == null ? [] : __filters.copy();
	}

	function set_filters(value:Array<flash.filters.BitmapFilter>):Array<flash.filters.BitmapFilter> {
		if (value != null && value.length > 0) {
			__filters = [for (filter in value) {
				var copy = filter != null ? filter.clone() : null;
				copy != null ? copy : filter;
			}];
		} else {
			__filters = null;
		}
		return value;
	}

	public function getBounds(targetCoordinateSpace:flash.display.DisplayObject):flash.geom.Rectangle {
		var matrix = new flash.geom.Matrix();
		if (targetCoordinateSpace != null && targetCoordinateSpace != this) {
			matrix = concatenatedMatrix();
			var target = targetCoordinateSpace.concatenatedMatrix();
			target.invert();
			matrix.concat(target);
		}
		var bounds = new flash.geom.Rectangle();
		__getBounds(bounds, matrix);
		port.runtime.Twips.snap(bounds);
		return bounds;
	}

	public function getRect(targetCoordinateSpace:flash.display.DisplayObject):flash.geom.Rectangle {
		return getBounds(targetCoordinateSpace);
	}

	@:noCompletion function __getBounds(rect:flash.geom.Rectangle, matrix:flash.geom.Matrix):Void {}

	@:noCompletion function __localBounds():flash.geom.Rectangle {
		var rect = new flash.geom.Rectangle();
		__getBounds(rect, __transform);
		rect.x -= __transform.tx;
		rect.y -= __transform.ty;
		return port.runtime.Twips.snap(rect);
	}

	@:noCompletion function __ownBounds():flash.geom.Rectangle {
		var rect = new flash.geom.Rectangle();
		__getBounds(rect, new flash.geom.Matrix());
		return port.runtime.Twips.snap(rect);
	}

	function get_width():Float return __localBounds().width;

	function set_width(value:Float):Float {
		var own = __ownBounds().width;
		scaleX = value != own ? value / own : 1;
		return value;
	}

	function get_height():Float return __localBounds().height;

	function set_height(value:Float):Float {
		var own = __ownBounds().height;
		scaleY = value != own ? value / own : 1;
		return value;
	}

	public function globalToLocal(pos:flash.geom.Point):flash.geom.Point {
		var m = concatenatedMatrix();
		m.invert();
		return m.transformPoint(pos);
	}

	public function hitTestObject(obj:flash.display.DisplayObject):Bool {
		if (obj != null && obj.parent != null && parent != null) {
			return getBounds(this).intersects(obj.getBounds(this));
		}
		return false;
	}

	public function hitTestPoint(x:Float, y:Float, shapeFlag:Bool = false):Bool {
		if (stage == null || !__toLocal(x, y)) return false;
		return __hitTest(x, y, __hx, __hy, shapeFlag, null, false, this);
	}
	public function invalidate():Void {}

	public function localToGlobal(point:flash.geom.Point):flash.geom.Point {
		return concatenatedMatrix().transformPoint(point);
	}

	@:noCompletion public function concatenatedMatrix():flash.geom.Matrix {
		var m = __transform.clone();
		var up = parent;
		while (up != null) {
			m.concat(up.__transform);
			up = up.parent;
		}
		return m;
	}

	@:noCompletion function __advance(deltaTime:Int):Void {}

	@:noCompletion function __setMatrix(a:Float, b:Float, c:Float, d:Float, tx:Float, ty:Float):Void {
		var t = __transform;
		if (t.a == a && t.b == b && t.c == c && t.d == d && t.tx == tx && t.ty == ty) return;
		__scaleX = b == 0 ? a : Math.sqrt(a * a + b * b);
		__scaleY = c == 0 ? d : Math.sqrt(c * c + d * d);
		var rotation = (180 / Math.PI) * Math.atan2(d, c) - 90;
		if (rotation != __rotation) {
			__rotation = rotation;
			var radians = rotation * (Math.PI / 180);
			__rotationSine = Math.sin(radians);
			__rotationCosine = Math.cos(radians);
		}
		t.a = a;
		t.b = b;
		t.c = c;
		t.d = d;
		t.tx = tx;
		t.ty = ty;
	}

	@:noCompletion public static var rootLoaderInfo(get, null):flash.display.LoaderInfo;

	static function get_rootLoaderInfo():flash.display.LoaderInfo {
		if (rootLoaderInfo == null) rootLoaderInfo = flash.display.LoaderInfo.create(null);
		return rootLoaderInfo;
	}

	function get_loaderInfo():flash.display.LoaderInfo return stage != null ? get_rootLoaderInfo() : null;

	function get_alpha():Float return __alpha;

	function set_alpha(value:Float):Float {
		if (value != value) value = 0.0;
		else if (value > 1.0) value = 1.0;
		else if (value < 0.0) value = 0.0;
		return __alpha = value;
	}

	function get_rotation():Float return __rotation;

	function set_rotation(value:Float):Float {
		if (value != __rotation) {
			value = value % 360.0;
			if (value > 180.0) value -= 360.0;
			else if (value < -180.0) value += 360.0;
			__rotation = value;
			var radians = __rotation * (Math.PI / 180);
			__rotationSine = Math.sin(radians);
			__rotationCosine = Math.cos(radians);
			__transform.a = __rotationCosine * __scaleX;
			__transform.b = __rotationSine * __scaleX;
			__transform.c = -__rotationSine * __scaleY;
			__transform.d = __rotationCosine * __scaleY;
		}
		return value;
	}

	function get_scaleX():Float return __scaleX;

	function set_scaleX(value:Float):Float {
		if (value != __scaleX) {
			__scaleX = value;
			if (__rotation == 0) {
				__transform.a = value;
			} else {
				__transform.a = __rotationCosine * value;
				__transform.b = __rotationSine * value;
			}
		}
		return value;
	}

	function get_scaleY():Float return __scaleY;

	function set_scaleY(value:Float):Float {
		if (value != __scaleY) {
			__scaleY = value;
			if (__rotation == 0) {
				__transform.d = value;
			} else {
				__transform.c = -__rotationSine * value;
				__transform.d = __rotationCosine * value;
			}
		}
		return value;
	}

	function get_x():Float return __transform.tx;

	function set_x(value:Float):Float {
		if (value != value) value = 0.0;
		return __transform.tx = value;
	}

	function get_y():Float return __transform.ty;

	function set_y(value:Float):Float {
		if (value != value) value = 0.0;
		return __transform.ty = value;
	}

	function get_transform():flash.geom.Transform {
		if (__objectTransform == null) __objectTransform = new flash.geom.Transform(this);
		return __objectTransform;
	}

	function set_transform(value:flash.geom.Transform):flash.geom.Transform {
		if (value == null) throw new flash.errors.Error("Parameter transform must be non-null.", 2007);
		var own = get_transform();
		var m = value.matrix;
		if (m != null) __setMatrix(m.a, m.b, m.c, m.d, m.tx, m.ty);
		own.colorTransform = value.colorTransform;
		return own;
	}

	public function new() {
		super();
		name = "instance" + (++instanceCount);
	}
}
