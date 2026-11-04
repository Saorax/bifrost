package haxe.ds;

@:native("haxe.ds._IntMap.IntMapKeysIterator")
class IntMapKeysIterator {
   var keys:Array<Int>;
   var index:Int = 0;

   public function new(h:Dynamic) {
      #if hl
      if (Std.isOfType(h, port.runtime.HashTable.IntTable)) {
         keys = (cast h : port.runtime.HashTable.IntTable).iterKeys();
         return;
      }
      #end
      keys = [for (k in Reflect.fields(h)) Std.parseInt(k)];
   }

   public function hasNext():Bool {
      return index < keys.length;
   }

   public function next():Int {
      return keys[index++];
   }
}
