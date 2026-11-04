package flash.display;

class Bitmap extends flash.display.DisplayObject {
	public var bitmapData:flash.display.BitmapData;
	public var pixelSnapping:flash.display.PixelSnapping;
	public var smoothing:Bool;

	@:access(flash.geom.Rectangle)
	@:noCompletion override function __getBounds(rect:flash.geom.Rectangle, matrix:flash.geom.Matrix):Void {
		super.__getBounds(rect, matrix);
		if (bitmapData == null) return;
		var own = new flash.geom.Rectangle(0, 0, bitmapData.width, bitmapData.height);
		var out = new flash.geom.Rectangle();
		own.__transform(out, matrix);
		rect.__expand(out.x, out.y, out.width, out.height);
	}

	@:noCompletion override public function __hitTest(x:Float, y:Float, lx:Float, ly:Float, shapeFlag:Bool, stack:Array<flash.display.DisplayObject>, interactiveOnly:Bool, hitObject:flash.display.DisplayObject):Bool {
		if (!hitObject.visible || __isMask || bitmapData == null) return false;
		if (!__inMask(x, y)) return false;
		if (lx > 0 && ly > 0 && lx <= bitmapData.width && ly <= bitmapData.height) {
			if (scrollRect != null && !scrollRect.contains(lx, ly)) return false;
			if (stack != null && !interactiveOnly) stack.push(hitObject);
			return true;
		}
		return false;
	}

	@:noCompletion override public function __hitTestMask(x:Float, y:Float, lx:Float, ly:Float):Bool {
		return bitmapData != null && lx > 0 && ly > 0 && lx <= bitmapData.width && ly <= bitmapData.height;
	}

	public function new(?bitmapData:flash.display.BitmapData, ?pixelSnapping:flash.display.PixelSnapping, smoothing:Bool = false) {
		super();
		this.bitmapData = bitmapData;
		this.pixelSnapping = pixelSnapping == null ? flash.display.PixelSnapping.AUTO : pixelSnapping;
		this.smoothing = smoothing;
	}
}
