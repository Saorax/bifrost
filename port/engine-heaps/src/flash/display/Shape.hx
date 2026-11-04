package flash.display;

class Shape extends flash.display.DisplayObject {
	public var graphics:flash.display.Graphics;

	@:noCompletion override function __getBounds(rect:flash.geom.Rectangle, matrix:flash.geom.Matrix):Void {
		super.__getBounds(rect, matrix);
		if (graphics != null) graphics.__addBounds(rect, matrix);
	}

	@:noCompletion override public function __hitTest(x:Float, y:Float, lx:Float, ly:Float, shapeFlag:Bool, stack:Array<flash.display.DisplayObject>, interactiveOnly:Bool, hitObject:flash.display.DisplayObject):Bool {
		if (graphics == null) return false;
		if (!hitObject.visible || __isMask) return false;
		if (!__inMask(x, y)) return false;
		if (graphics.__hitTest(lx, ly, shapeFlag)) {
			if (stack != null && !interactiveOnly) stack.push(hitObject);
			return true;
		}
		return false;
	}

	@:noCompletion override public function __hitTestMask(x:Float, y:Float, lx:Float, ly:Float):Bool {
		return graphics != null && graphics.__hitTest(lx, ly, true);
	}

	public function new() {
		super();
		graphics = new flash.display.Graphics(this);
	}
}
