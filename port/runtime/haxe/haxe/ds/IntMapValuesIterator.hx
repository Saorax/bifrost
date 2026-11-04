package haxe.ds;

@:native("haxe.ds._IntMap.IntMapValuesIterator")
class IntMapValuesIterator<T> {
   var h:Dynamic;
   var keys:Array<String>;
   var index:Int = 0;
   #if hl
   var table:port.runtime.HashTable.IntTable;
   var intKeys:Array<Int>;
   #end

   public function new(h:Dynamic) {
      this.h = h;
      #if hl
      if (Std.isOfType(h, port.runtime.HashTable.IntTable)) {
         table = cast h;
         intKeys = table.intKeys();
         keys = table.otherKeys();
         return;
      }
      #end
      keys = Reflect.fields(h);
   }

   public function hasNext():Bool {
      #if hl
      if (table != null) return index < intKeys.length + keys.length;
      #end
      return index < keys.length;
   }

   public function next():T {
      #if hl
      if (table != null) {
         var i = index++;
         return i < intKeys.length ? table.get(intKeys[i]) : table.getValue(keys[i - intKeys.length]);
      }
      #end
      return Reflect.field(h, keys[index++]);
   }
}
