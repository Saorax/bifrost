package flash.utils;

class Dictionary {
   var objects:haxe.ds.ObjectMap<Dynamic, Dynamic>;
   var primitives:Map<String, Dynamic>;
   var primitiveKeys:Map<String, Dynamic>;
   var order:Array<Dynamic>;

   public function new(?weakKeys:Bool = false) {
      objects = new haxe.ds.ObjectMap();
      primitives = new Map();
      primitiveKeys = new Map();
      order = [];
   }

   static function primitiveTag(key:Dynamic):Null<String> {
      if (key == null) return "null";
      if (Std.isOfType(key, String)) return "s" + key;
      if (Std.isOfType(key, Bool)) return "b" + key;
      if (Std.isOfType(key, Int) || Std.isOfType(key, Float)) {
         var n:Float = key;
         return "n" + (n == Std.int(n) ? Std.string(Std.int(n)) : Std.string(n));
      }
      return null;
   }

   public function getValue(key:Dynamic):Dynamic {
      var tag = primitiveTag(key);
      return tag != null ? primitives.get(tag) : objects.get(key);
   }

   public function setValue(key:Dynamic, value:Dynamic):Dynamic {
      var tag = primitiveTag(key);
      if (tag != null) {
         if (!primitives.exists(tag)) {
            primitiveKeys.set(tag, key);
            order.push(key);
         }
         primitives.set(tag, value);
      } else {
         if (!objects.exists(key)) order.push(key);
         objects.set(key, value);
      }
      return value;
   }

   public function exists(key:Dynamic):Bool {
      var tag = primitiveTag(key);
      return tag != null ? primitives.exists(tag) : objects.exists(key);
   }

   public function remove(key:Dynamic):Bool {
      var tag = primitiveTag(key);
      var removed = tag != null ? (primitiveKeys.remove(tag) && primitives.remove(tag)) : objects.remove(key);
      if (removed) {
         for (i in 0...order.length) {
            var k = order[i];
            if (tag != null ? primitiveTag(k) == tag : k == key) {
               order.splice(i, 1);
               break;
            }
         }
      }
      return true;
   }

   public function keys():Iterator<Dynamic> {
      return order.copy().iterator();
   }

   public function iterator():Iterator<Dynamic> {
      return [for (k in order) getValue(k)].iterator();
   }
}
