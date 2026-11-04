package;

class JSON {
   public static function parse(text:String):Dynamic {
      try {
         return haxe.Json.parse(text);
      } catch (e:Dynamic) {
         throw "SyntaxError: Error #1132: Invalid JSON parse input. (" + Std.string(e) + ")";
      }
   }

   public static function stringify(value:Dynamic, replacer:Dynamic = null, space:Dynamic = null):String {
      return haxe.Json.stringify(value);
   }
}
