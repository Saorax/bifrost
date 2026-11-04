package flash.display;

class Sprite extends flash.display.DisplayObjectContainer {
	public static function fromTimeline(timeline:flash.display.Timeline):flash.display.Sprite {
		var sprite = new Sprite();
		if (timeline != null) timeline.initializeSprite(sprite);
		return sprite;
	}

	public var buttonMode:Bool = false;
	public var dropTarget:flash.display.DisplayObject;
	public var graphics:flash.display.Graphics;
	public var hitArea:flash.display.Sprite;
	public var useHandCursor:Bool = true;

	@:noCompletion override function __tabDefault():Bool {
		return buttonMode;
	}

	public function startDrag(lockCenter:Bool = false, ?bounds:flash.geom.Rectangle):Void {}

	public function stopDrag():Void {}

	@:noCompletion override function __getBounds(rect:flash.geom.Rectangle, matrix:flash.geom.Matrix):Void {
		super.__getBounds(rect, matrix);
		if (graphics != null) graphics.__addBounds(rect, matrix);
	}

	@:noCompletion override public function __hitTest(x:Float, y:Float, lx:Float, ly:Float, shapeFlag:Bool, stack:Array<flash.display.DisplayObject>, interactiveOnly:Bool, hitObject:flash.display.DisplayObject):Bool {
		if (interactiveOnly && !mouseEnabled && !mouseChildren) return false;
		if (!hitObject.visible || __isMask) return hitTestHitArea(x, y, shapeFlag, stack, interactiveOnly, hitObject);
		if (!__inMask(x, y)) return hitTestHitArea(x, y, shapeFlag, stack, interactiveOnly, hitObject);
		if (scrollRect != null && !scrollRect.contains(lx + scrollRect.x, ly + scrollRect.y)) {
			return hitTestHitArea(x, y, shapeFlag, stack, true, hitObject);
		}
		if (super.__hitTest(x, y, lx, ly, shapeFlag, stack, interactiveOnly, hitObject)) {
			return stack == null || interactiveOnly;
		} else if (hitArea == null && graphics != null) {
			var gx = lx, gy = ly;
			if (scrollRect != null) {
				gx += scrollRect.x;
				gy += scrollRect.y;
			}
			if (graphics.__hitTest(gx, gy, shapeFlag)) {
				if (stack != null && (!interactiveOnly || mouseEnabled)) stack.push(hitObject);
				return true;
			}
		}
		return hitTestHitArea(x, y, shapeFlag, stack, interactiveOnly, hitObject);
	}

	function hitTestHitArea(x:Float, y:Float, shapeFlag:Bool, stack:Array<flash.display.DisplayObject>, interactiveOnly:Bool,
			hitObject:flash.display.DisplayObject):Bool {
		if (hitArea != null && !hitArea.mouseEnabled) {
			hitArea.mouseEnabled = true;
			var hit = hitArea.__toLocal(x, y) && hitArea.__hitTest(x, y, @:privateAccess flash.display.DisplayObject.__hx,
				@:privateAccess flash.display.DisplayObject.__hy, shapeFlag, null, true, hitObject);
			hitArea.mouseEnabled = false;
			if (stack != null && hit) stack.push(hitObject);
			return hit;
		}
		return false;
	}

	@:noCompletion override public function __hitTestMask(x:Float, y:Float, lx:Float, ly:Float):Bool {
		if (super.__hitTestMask(x, y, lx, ly)) return true;
		return graphics != null && graphics.__hitTest(lx, ly, true);
	}

	public function new() {
		super();
		graphics = new flash.display.Graphics(this);
	}
}
