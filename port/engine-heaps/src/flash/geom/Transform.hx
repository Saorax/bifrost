package flash.geom;

@:access(flash.display.DisplayObject)
class Transform {
	public var colorTransform(get, set):flash.geom.ColorTransform;
	public var concatenatedColorTransform(get, never):flash.geom.ColorTransform;
	public var concatenatedMatrix(get, never):flash.geom.Matrix;
	public var matrix(get, set):flash.geom.Matrix;
	public var matrix3D:flash.geom.Matrix3D;
	public var pixelBounds:flash.geom.Rectangle;

	var displayObject:flash.display.DisplayObject;
	var color = new flash.geom.ColorTransform();

	function get_colorTransform():flash.geom.ColorTransform {
		return new ColorTransform(color.redMultiplier, color.greenMultiplier, color.blueMultiplier, color.alphaMultiplier,
			color.redOffset, color.greenOffset, color.blueOffset, color.alphaOffset);
	}

	function set_colorTransform(value:flash.geom.ColorTransform):flash.geom.ColorTransform {
		if (value == null) return color;
		color.redMultiplier = value.redMultiplier;
		color.greenMultiplier = value.greenMultiplier;
		color.blueMultiplier = value.blueMultiplier;
		color.alphaMultiplier = value.alphaMultiplier;
		color.redOffset = value.redOffset;
		color.greenOffset = value.greenOffset;
		color.blueOffset = value.blueOffset;
		color.alphaOffset = value.alphaOffset;
		if (displayObject != null) displayObject.alpha = value.alphaMultiplier;
		return color;
	}

	function get_concatenatedColorTransform():flash.geom.ColorTransform {
		var out = get_colorTransform();
		var up = displayObject != null ? displayObject.parent : null;
		while (up != null) {
			out.concat(up.transform.color);
			up = up.parent;
		}
		return out;
	}

	function get_concatenatedMatrix():flash.geom.Matrix {
		return displayObject != null ? displayObject.concatenatedMatrix() : new Matrix();
	}

	function get_matrix():flash.geom.Matrix {
		return displayObject != null ? displayObject.__transform.clone() : null;
	}

	function set_matrix(value:flash.geom.Matrix):flash.geom.Matrix {
		if (value != null && displayObject != null) displayObject.__setMatrix(value.a, value.b, value.c, value.d, value.tx, value.ty);
		return value;
	}

	public function new(displayObject:flash.display.DisplayObject) {
		this.displayObject = displayObject;
	}
}
