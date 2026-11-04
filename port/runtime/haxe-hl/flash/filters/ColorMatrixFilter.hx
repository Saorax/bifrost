package flash.filters;

@:forward
abstract ColorMatrixFilter(openfl.filters.ColorMatrixFilter) from openfl.filters.ColorMatrixFilter
      to openfl.filters.ColorMatrixFilter to openfl.filters.BitmapFilter {
   public var matrix(get, set):Dynamic;

   public inline function new(?matrix:Dynamic) {
      this = new openfl.filters.ColorMatrixFilter(floats(matrix));
   }

   static function floats(values:Dynamic):Array<Float> {
      if (values == null) {
         return null;
      }
      var source:Array<Dynamic> = values;
      return [for (value in source) (value : Float)];
   }

   inline function get_matrix():Dynamic return this.matrix;
   inline function set_matrix(value:Dynamic):Dynamic {
      this.matrix = floats(value);
      return value;
   }
}
