package haxe.ds;

import haxe.ds._StringMap.StringMapKeysIterator;
import haxe.ds._StringMap.StringMapValuesIterator;

class StringMap<T> implements haxe.Constraints.IMap<String, T> {
   public static var reserved:Dynamic = #if hl new port.runtime.HashTable.StringTable() #else {} #end;

   static inline function isReserved(text:String):Bool {
      #if hl
      return reserved != null && (cast reserved : port.runtime.HashTable.KeyTable).hasText(text);
      #else
      return Reflect.hasField(reserved, text);
      #end
   }

   public var h:Dynamic;
   public var rh:Dynamic;
   #if hl
   var t:port.runtime.HashTable.StringTable;
   #end

   static inline function keyText(key:Dynamic):String {
      #if hl
      return Std.isOfType(key, String) ? (cast key : String) : Std.string(key);
      #else
      return Std.string(key);
      #end
   }

   public function new() {
      #if hl
      h = t = new port.runtime.HashTable.StringTable();
      #else
      h = {};
      #end
      rh = null;
   }

   public function setReserved(key:String, value:T):Void {
      if (rh == null) {
         rh = {};
      }
      Reflect.setField(rh, "$" + key, value);
   }

   public function method_65(key:Dynamic, value:T):Void {
      var text = keyText(key);
      if (isReserved(text)) {
         setReserved(text, value);
      } else {
         #if hl
         t.set(text, value);
         #else
         Reflect.setField(h, text, value);
         #end
      }
   }

   public function set(key:String, value:T):Void {
      #if hl
      var text = key == null ? "null" : key;
      if (isReserved(text)) setReserved(text, value) else t.set(text, value);
      #else
      method_65(key, value);
      #end
   }

   public function remove(key:Dynamic):Bool {
      var text = keyText(key);
      if (isReserved(text)) {
         var reservedKey = "$" + text;
         return rh != null && Reflect.deleteField(rh, reservedKey);
      }
      #if hl
      return t.remove(text);
      #else
      return Reflect.deleteField(h, text);
      #end
   }

   public function keys():Iterator<String> {
      return new StringMapKeysIterator(h, rh);
   }

   public function iterator():Iterator<T> {
      return new StringMapValuesIterator<T>(h, rh);
   }

   public function hasValues():Bool {
      #if hl
      if (rh == null && h == t) return !t.isEmpty();
      #end
      return iterator().hasNext();
   }

   public function getReserved(key:String):Null<T> {
      return rh == null ? null : Reflect.field(rh, "$" + key);
   }

   public function method_4935(key:Dynamic):Null<T> {
      var text = keyText(key);
      #if hl
      return isReserved(text) ? getReserved(text) : t.get(text);
      #else
      return isReserved(text) ? getReserved(text) : Reflect.field(h, text);
      #end
   }

   public function get(key:String):Null<T> {
      #if hl
      var text = key == null ? "null" : key;
      return isReserved(text) ? getReserved(text) : t.get(text);
      #else
      return method_4935(key);
      #end
   }

   public function existsReserved(key:String):Bool {
      return rh != null && Reflect.hasField(rh, "$" + key);
   }

   public function exists(key:Dynamic):Bool {
      var text = keyText(key);
      #if hl
      return isReserved(text) ? existsReserved(text) : t.exists(text);
      #else
      return isReserved(text) ? existsReserved(text) : Reflect.hasField(h, text);
      #end
   }

   public function keyValueIterator():KeyValueIterator<String, T> {
      return new haxe.iterators.MapKeyValueIterator(this);
   }

   public function copy():StringMap<T> {
      var copied = new StringMap<T>();
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
      h = t = new port.runtime.HashTable.StringTable();
      #else
      h = {};
      #end
      rh = null;
   }
}
