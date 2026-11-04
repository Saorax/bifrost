package haxe.ds;

@:native("haxe.ds._StringMap.StringMapKeysIterator")
class StringMapKeysIterator {
   var keys:Array<String>;
   var index:Int = 0;

   public function new(h:Dynamic, rh:Dynamic) {
      #if hl
      keys = Std.isOfType(h, port.runtime.HashTable.KeyTable) ? (cast h : port.runtime.HashTable.KeyTable).keys() : Reflect.fields(h);
      #else
      keys = Reflect.fields(h);
      #end
      if (rh != null) {
         for (key in Reflect.fields(rh)) {
            keys.push(key.charAt(0) == "$" ? key.substr(1) : key);
         }
      }
   }

   public function hasNext():Bool {
      return index < keys.length;
   }

   public function next():String {
      return keys[index++];
   }
}

@:native("haxe.ds._StringMap.StringMapValuesIterator")
class StringMapValuesIterator<T> {
   var values:Array<Dynamic>;
   #if hl
   var native:hl.NativeArray<Dynamic>;
   #end
   var index:Int = 0;

   public function new(h:Dynamic, rh:Dynamic) {
      #if hl
      if (Std.isOfType(h, port.runtime.HashTable.KeyTable) && rh == null) {
         var table:port.runtime.HashTable.KeyTable = cast h;
         native = table.valuesNative();
         return;
      }
      #end
      values = [];
      #if hl
      if (Std.isOfType(h, port.runtime.HashTable.KeyTable)) {
         for (v in (cast h : port.runtime.HashTable.KeyTable).values()) values.push(v);
      } else
      #end
      for (key in Reflect.fields(h)) {
         values.push(Reflect.field(h, key));
      }
      if (rh != null) {
         for (key in Reflect.fields(rh)) {
            values.push(Reflect.field(rh, key));
         }
      }
   }

   public function hasNext():Bool {
      #if hl
      if (native != null) return index < native.length;
      #end
      return index < values.length;
   }

   public function next():T {
      #if hl
      if (native != null) return cast native[index++];
      #end
      return cast values[index++];
   }
}
