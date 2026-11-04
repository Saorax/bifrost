package port.runtime;

#if hl
class KeyTable {
   public function new() {}

   public function getValue(key:Dynamic):Dynamic return null;
   public function setValue(key:Dynamic, value:Dynamic):Dynamic return value;
   public function has(key:Dynamic):Bool return false;
   public function hasText(key:String):Bool return has(key);
   public function delete(key:Dynamic):Bool return false;
   public function keys():Array<String> return [];
   public function values():Array<Dynamic> return [];
   public function isEmpty():Bool return values().length == 0;
   public function valuesNative():hl.NativeArray<Dynamic> {
      var all = values();
      var out = new hl.NativeArray<Dynamic>(all.length);
      for (i in 0...all.length) out[i] = all[i];
      return out;
   }
}

class StringTable extends KeyTable {
   var m:hl.types.BytesMap;

   public function new() {
      super();
      m = new hl.types.BytesMap();
   }

   public static inline function text(key:Dynamic):String {
      return Std.isOfType(key, String) ? (cast key : String) : Std.string(key);
   }

   public inline function get(key:String):Dynamic {
      return m.get(@:privateAccess key.bytes);
   }

   public inline function set(key:String, value:Dynamic):Void {
      m.set(@:privateAccess key.bytes, value);
   }

   public inline function exists(key:String):Bool {
      return m.exists(@:privateAccess key.bytes);
   }

   public inline function remove(key:String):Bool {
      return m.remove(@:privateAccess key.bytes);
   }

   override public function getValue(key:Dynamic):Dynamic return get(text(key));
   override public function setValue(key:Dynamic, value:Dynamic):Dynamic {
      set(text(key), value);
      return value;
   }
   override public function has(key:Dynamic):Bool return exists(text(key));
   override public function hasText(key:String):Bool return exists(key == null ? "null" : key);
   override public function delete(key:Dynamic):Bool return remove(text(key));

   override public function keys():Array<String> {
      var a = m.keysArray();
      return [for (i in 0...a.length) @:privateAccess String.fromUCS2(a[i])];
   }

   override public function values():Array<Dynamic> {
      return cast hl.types.ArrayObj.alloc(m.valuesArray());
   }

   override public function valuesNative():hl.NativeArray<Dynamic> return m.valuesArray();

   @:hlNative("std", "hbsize") static function size(m:hl.types.BytesMap.BytesMapData):Int return 0;

   override public function isEmpty():Bool return size(cast m) == 0;
}

class IntTable extends KeyTable {
   var m:hl.types.IntMap;
   var other:StringTable;

   public function new() {
      super();
   }

   static function intKey(key:Dynamic):Null<Int> {
      if (Std.isOfType(key, Int)) return (cast key : Int);
      if (Std.isOfType(key, Float)) {
         var f:Float = key;
         var i = Std.int(f);
         return i == f && Std.string(i) == Std.string(f) ? i : null;
      }
      if (Std.isOfType(key, String)) {
         var s:String = key;
         var i = Std.parseInt(s);
         return i != null && Std.string(i) == s ? i : null;
      }
      return null;
   }

   public inline function get(key:Int):Dynamic {
      return m == null ? null : m.get(key);
   }

   public inline function set(key:Int, value:Dynamic):Void {
      if (m == null) m = new hl.types.IntMap();
      m.set(key, value);
   }

   public inline function exists(key:Int):Bool {
      return m != null && m.exists(key);
   }

   override public function getValue(key:Dynamic):Dynamic {
      if (Std.isOfType(key, Int)) return get((cast key : Int));
      var i = intKey(key);
      return i != null ? get(i) : other == null ? null : other.getValue(key);
   }

   override public function setValue(key:Dynamic, value:Dynamic):Dynamic {
      if (Std.isOfType(key, Int)) {
         set((cast key : Int), value);
         return value;
      }
      var i = intKey(key);
      if (i != null) {
         set(i, value);
      } else {
         if (other == null) other = new StringTable();
         other.setValue(key, value);
      }
      return value;
   }

   override public function has(key:Dynamic):Bool {
      if (Std.isOfType(key, Int)) return exists((cast key : Int));
      var i = intKey(key);
      return i != null ? exists(i) : other != null && other.has(key);
   }

   override public function delete(key:Dynamic):Bool {
      var i = intKey(key);
      return i != null ? m != null && m.remove(i) : other != null && other.delete(key);
   }

   public function intKeys():Array<Int> {
      if (m == null) return [];
      var a = m.keysArray();
      return [for (i in 0...a.length) a[i]];
   }

   public function otherKeys():Array<String> {
      return other == null ? [] : other.keys();
   }

   public function iterKeys():Array<Int> {
      var out = intKeys();
      if (other != null) for (k in other.keys()) out.push(Std.parseInt(k));
      return out;
   }

   @:hlNative("std", "hisize") static function size(m:hl.types.IntMap.IntMapData):Int return 0;

   override public function isEmpty():Bool return (m == null || size(cast m) == 0) && (other == null || other.isEmpty());

   override public function keys():Array<String> {
      var out = [for (k in intKeys()) Std.string(k)];
      if (other != null) for (k in other.keys()) out.push(k);
      return out;
   }

   override public function values():Array<Dynamic> {
      var out:Array<Dynamic> = [];
      if (m != null) {
         var a = m.valuesArray();
         for (i in 0...a.length) out.push(a[i]);
      }
      if (other != null) for (v in other.values()) out.push(v);
      return out;
   }
}
#end
