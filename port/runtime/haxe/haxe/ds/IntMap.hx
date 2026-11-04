package haxe.ds;

class IntMap<T> implements haxe.Constraints.IMap<Int, T> {
   public var h:Dynamic;
   #if hl
   var t:port.runtime.HashTable.IntTable;
   #end

   public function new() {
      #if hl
      h = t = new port.runtime.HashTable.IntTable();
      #else
      h = {};
      #end
   }

   public function method_65(key:Dynamic, value:T):Void {
      #if hl
      t.setValue(key, value);
      #else
      Reflect.setField(h, Std.string(key), value);
      #end
   }

   public function set(key:Int, value:T):Void {
      #if hl
      t.set(key, value);
      #else
      method_65(key, value);
      #end
   }

   public function method_4935(key:Dynamic):Null<T> {
      #if hl
      return t.getValue(key);
      #else
      return Reflect.field(h, Std.string(key));
      #end
   }

   public function get(key:Int):Null<T> {
      #if hl
      return t.get(key);
      #else
      return method_4935(key);
      #end
   }

   public function exists(key:Dynamic):Bool {
      #if hl
      return t.has(key);
      #else
      return Reflect.hasField(h, Std.string(key));
      #end
   }

   public function remove(key:Dynamic):Bool {
      #if hl
      return t.delete(key);
      #else
      if (!exists(key)) {
         return false;
      }
      Reflect.deleteField(h, Std.string(key));
      return true;
      #end
   }

   public function keys():Iterator<Int> {
      return new IntMapKeysIterator(h);
   }

   public function iterator():Iterator<T> {
      return new IntMapValuesIterator<T>(h);
   }

   public function hasValues():Bool {
      #if hl
      if (h == t) return !t.isEmpty();
      #end
      return iterator().hasNext();
   }

   public function keyValueIterator():KeyValueIterator<Int, T> {
      return new haxe.iterators.MapKeyValueIterator(this);
   }

   public function copy():IntMap<T> {
      var copied = new IntMap<T>();
      for (key in keys()) {
         copied.method_65(key, method_4935(key));
      }
      return copied;
   }

   public function toString():String {
      var parts = [];
      for (key in keys()) {
         parts.push(key + " => " + Std.string(method_4935(key)));
      }
      return "{" + parts.join(", ") + "}";
   }

   public function clear():Void {
      #if hl
      h = t = new port.runtime.HashTable.IntTable();
      #else
      h = {};
      #end
   }
}
