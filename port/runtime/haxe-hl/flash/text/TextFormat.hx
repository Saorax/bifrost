package flash.text;

@:forward
@:forward.new
abstract TextFormat(openfl.text.TextFormat) from openfl.text.TextFormat to openfl.text.TextFormat {
   public var size(get, set):Dynamic;

   public inline function new(?font:String, ?size:Dynamic, ?color:Dynamic, ?bold:Dynamic, ?italic:Dynamic,
         ?underline:Dynamic, ?url:String, ?target:String, ?align:Dynamic, ?leftMargin:Dynamic, ?rightMargin:Dynamic,
         ?indent:Dynamic, ?leading:Dynamic) {
      this = new openfl.text.TextFormat(font, toInt(size), toInt(color), bold, italic, underline, url, target, align,
         toInt(leftMargin), toInt(rightMargin), toInt(indent), toInt(leading));
   }

   static function toInt(value:Dynamic):Null<Int> {
      return value == null ? null : Std.int(value);
   }

   inline function get_size():Dynamic return this.size;
   inline function set_size(value:Dynamic):Dynamic {
      this.size = toInt(value);
      return value;
   }
}
