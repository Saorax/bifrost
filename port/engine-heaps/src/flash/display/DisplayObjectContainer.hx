package flash.display;

class DisplayObjectContainer extends flash.display.InteractiveObject {
	public var mouseChildren:Bool = true;
	public var numChildren(get, never):Int;
	public var tabChildren:Bool = true;

	@:noCompletion var __children:Array<flash.display.DisplayObject> = [];

	public function new() {
		super();
	}

	function get_numChildren():Int {
		return __children.length;
	}

	public function addChild(child:flash.display.DisplayObject):flash.display.DisplayObject {
		return addChildAt(child, child != null && child.parent == this ? __children.length - 1 : __children.length);
	}

	public function addChildAt(child:flash.display.DisplayObject, index:Int):flash.display.DisplayObject {
		if (child == null) throw new flash.errors.Error("Error #2007: Parameter child must be non-null.");
		var up:flash.display.DisplayObject = this;
		while (up != null) {
			if (up == child) throw new flash.errors.ArgumentError("Error #2150: An object cannot be added as a child to one of it's children (or children's children, etc.).");
			up = up.parent;
		}
		if (child.parent == this) {
			if (index < 0 || index >= __children.length) throw new flash.errors.RangeError("Error #2006: The supplied index is out of bounds.");
			if (__children[index] == child) return child;
			__children.remove(child);
			__children.insert(index, child);
			return child;
		}
		if (index < 0 || index > __children.length) throw new flash.errors.RangeError("Error #2006: The supplied index is out of bounds.");
		if (child.parent != null) child.parent.removeChild(child);
		__children.insert(index, child);
		child.parent = this;
		child.dispatchEvent(new flash.events.Event(flash.events.Event.ADDED, true));
		if (stage != null) linkStage(child, stage, onStageRoot(child));
		return child;
	}

	function onStageRoot(child:flash.display.DisplayObject):flash.display.DisplayObject {
		return Std.isOfType(this, flash.display.Stage) ? child : root;
	}

	static function linkStage(object:flash.display.DisplayObject, stage:flash.display.Stage, root:flash.display.DisplayObject):Void {
		object.stage = stage;
		object.root = root;
		object.dispatchEvent(new flash.events.Event(flash.events.Event.ADDED_TO_STAGE));
		if (Std.isOfType(object, DisplayObjectContainer)) {
			var container:DisplayObjectContainer = cast object;
			for (c in container.__children.copy()) if (c.parent == container) linkStage(c, stage, root);
		}
	}

	static function unlinkStage(object:flash.display.DisplayObject):Void {
		object.dispatchEvent(new flash.events.Event(flash.events.Event.REMOVED_FROM_STAGE));
		if (Std.isOfType(object, DisplayObjectContainer)) {
			var container:DisplayObjectContainer = cast object;
			for (c in container.__children.copy()) if (c.parent == container) unlinkStage(c);
		}
		object.stage = null;
		object.root = null;
	}

	public function areInaccessibleObjectsUnderPoint(point:flash.geom.Point):Bool {
		return false;
	}

	public function contains(child:flash.display.DisplayObject):Bool {
		var up = child;
		while (up != null) {
			if (up == this) return true;
			up = up.parent;
		}
		return false;
	}

	public function getChildAt(index:Int):flash.display.DisplayObject {
		if (index < 0 || index >= __children.length) throw new flash.errors.RangeError("Error #2006: The supplied index is out of bounds.");
		return __children[index];
	}

	public function getChildByName(name:String):flash.display.DisplayObject {
		for (c in __children) if (c.name == name) return c;
		return null;
	}

	public function getChildIndex(child:flash.display.DisplayObject):Int {
		var at = __children.indexOf(child);
		if (at < 0) throw new flash.errors.ArgumentError("Error #2025: The supplied DisplayObject must be a child of the caller.");
		return at;
	}

	public function getObjectsUnderPoint(point:flash.geom.Point):Array<flash.display.DisplayObject> {
		var stack:Array<flash.display.DisplayObject> = [];
		if (__toLocal(point.x, point.y)) __hitTest(point.x, point.y, DisplayObject.__hx, DisplayObject.__hy, false, stack, false, this);
		stack.reverse();
		return stack;
	}

	@:noCompletion public function __mouseStack(x:Float, y:Float):Array<flash.display.DisplayObject> {
		var stack:Array<flash.display.DisplayObject> = [];
		if (__toLocal(x, y) && __hitTest(x, y, DisplayObject.__hx, DisplayObject.__hy, true, stack, true, this)) return stack;
		return [];
	}

	@:noCompletion override public function __hitTest(x:Float, y:Float, lx:Float, ly:Float, shapeFlag:Bool, stack:Array<flash.display.DisplayObject>, interactiveOnly:Bool, hitObject:flash.display.DisplayObject):Bool {
		if (!hitObject.visible || __isMask || (interactiveOnly && !mouseEnabled && !mouseChildren)) return false;
		if (!__inMask(x, y)) return false;
		if (scrollRect != null) {
			lx += scrollRect.x;
			ly += scrollRect.y;
			if (!scrollRect.contains(lx, ly)) return false;
		}
		var i = __children.length;
		if (interactiveOnly) {
			if (stack == null || !mouseChildren) {
				while (--i >= 0) {
					var child = __children[i];
					if (!DisplayObject.__inverse(child.__transform, lx, ly)) continue;
					if (child.__hitTest(x, y, DisplayObject.__hx, DisplayObject.__hy, shapeFlag, null, mouseChildren, child)) {
						if (stack != null) stack.push(hitObject);
						return true;
					}
				}
			} else {
				var length = stack.length;
				var hit = false;
				while (--i >= 0) {
					var child = __children[i];
					var interactive = child.__interactive();
					if (interactive || (mouseEnabled && !hit)) {
						if (!DisplayObject.__inverse(child.__transform, lx, ly)) continue;
						if (child.__hitTest(x, y, DisplayObject.__hx, DisplayObject.__hy, shapeFlag, stack, true, child)) {
							hit = true;
							if (interactive && stack.length > length) break;
						}
					}
				}
				if (hit) {
					stack.insert(length, hitObject);
					return true;
				}
			}
		} else {
			var hit = false;
			while (--i >= 0) {
				var child = __children[i];
				if (!DisplayObject.__inverse(child.__transform, lx, ly)) continue;
				if (child.__hitTest(x, y, DisplayObject.__hx, DisplayObject.__hy, shapeFlag, stack, false, child)) {
					hit = true;
					if (stack == null) break;
				}
			}
			return hit;
		}
		return false;
	}

	@:noCompletion override public function __hitTestMask(x:Float, y:Float, lx:Float, ly:Float):Bool {
		if (scrollRect != null) {
			lx += scrollRect.x;
			ly += scrollRect.y;
		}
		var i = __children.length;
		while (--i >= 0) {
			var child = __children[i];
			if (DisplayObject.__inverse(child.__transform, lx, ly) && child.__hitTestMask(x, y, DisplayObject.__hx, DisplayObject.__hy)) return true;
		}
		return false;
	}

	public function removeChild(child:flash.display.DisplayObject):flash.display.DisplayObject {
		if (child == null || child.parent != this) throw new flash.errors.ArgumentError("Error #2025: The supplied DisplayObject must be a child of the caller.");
		child.dispatchEvent(new flash.events.Event(flash.events.Event.REMOVED, true));
		if (child.stage != null) unlinkStage(child);
		if (child.parent == this) {
			__children.remove(child);
			child.parent = null;
		}
		return child;
	}

	public function removeChildAt(index:Int):flash.display.DisplayObject {
		return removeChild(getChildAt(index));
	}

	public function removeChildren(beginIndex:Int = 0, endIndex:Int = 0x7FFFFFFF):Void {
		if (endIndex == 0x7FFFFFFF) endIndex = __children.length - 1;
		if (__children.length == 0 && beginIndex == 0) return;
		if (beginIndex < 0 || endIndex < beginIndex || endIndex >= __children.length) throw new flash.errors.RangeError("Error #2006: The supplied index is out of bounds.");
		for (_ in beginIndex...endIndex + 1) removeChild(__children[beginIndex]);
	}

	public function setChildIndex(child:flash.display.DisplayObject, index:Int):Void {
		var at = getChildIndex(child);
		if (index < 0 || index >= __children.length) throw new flash.errors.RangeError("Error #2006: The supplied index is out of bounds.");
		__children.splice(at, 1);
		__children.insert(index, child);
	}

	public function stopAllMovieClips():Void {
		for (child in __children) {
			if (Std.isOfType(child, DisplayObjectContainer)) (cast child : DisplayObjectContainer).stopAllMovieClips();
		}
	}

	@:noCompletion override function __getBounds(rect:flash.geom.Rectangle, matrix:flash.geom.Matrix):Void {
		super.__getBounds(rect, matrix);
		for (child in __children) {
			if (child.__scaleX == 0 && child.__scaleY == 0) continue;
			var world = child.__transform.clone();
			world.concat(matrix);
			child.__getBounds(rect, world);
		}
	}

	@:noCompletion override function __advance(deltaTime:Int):Void {
		for (child in __children) child.__advance(deltaTime);
	}

	public function swapChildren(child1:flash.display.DisplayObject, child2:flash.display.DisplayObject):Void {
		swapChildrenAt(getChildIndex(child1), getChildIndex(child2));
	}

	public function swapChildrenAt(index1:Int, index2:Int):Void {
		var a = getChildAt(index1), b = getChildAt(index2);
		__children[index1] = b;
		__children[index2] = a;
	}
}
