package flash.utils;

class Dictionary {
   final values:Dynamic;

   public function new(?weakKeys:Bool = false) {
      values = {};
   }

   public inline function getValue(key:Dynamic):Dynamic {
      return Reflect.field(values, Std.string(key));
   }

   public inline function setValue(key:Dynamic, value:Dynamic):Dynamic {
      Reflect.setField(values, Std.string(key), value);
      return value;
   }
}
