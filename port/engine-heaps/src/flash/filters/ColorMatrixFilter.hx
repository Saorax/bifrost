package flash.filters;

class ColorMatrixFilter extends flash.filters.BitmapFilter {
	public var matrix(get, set):Dynamic;

	var values:Array<Float>;

	public function new(?matrix:Dynamic) {
		super();
		this.matrix = matrix;
	}

	static function floats(source:Dynamic):Array<Float> {
		var out = [1.0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0];
		if (source != null) {
			var given:Array<Dynamic> = source;
			for (i in 0...Std.int(Math.min(20, given.length))) {
				var v:Null<Float> = given[i];
				out[i] = v == null || Math.isNaN(v) ? 0 : v;
			}
		}
		return out;
	}

	function get_matrix():Dynamic return values.copy();

	function set_matrix(value:Dynamic):Dynamic {
		values = floats(value);
		return value;
	}

	@:noCompletion public function __values():Array<Float> return values;

	override public function clone():flash.filters.BitmapFilter {
		return new ColorMatrixFilter(values.copy());
	}
}
