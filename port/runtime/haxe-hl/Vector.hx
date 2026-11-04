package;

#if macro
abstract Vector<T>(Dynamic) {
   public static macro function create():haxe.macro.Expr {
      return port.runtime.VectorMacro.construct([]);
   }

   public static macro function sized(length:haxe.macro.Expr):haxe.macro.Expr {
      return port.runtime.VectorMacro.construct([macro Std.int($length)]);
   }

   public static macro function sizedFixed(length:haxe.macro.Expr, fixed:haxe.macro.Expr):haxe.macro.Expr {
      return port.runtime.VectorMacro.construct([macro Std.int($length), fixed]);
   }
}
#else
import port.runtime.AS3Vector;

abstract Vector<T>(AS3Vector) from AS3Vector to AS3Vector {
   public inline function new(?length:Dynamic = 0, ?fixed:Bool = false) {
      this = new AS3Vector(Std.int(length), fixed);
   }

   public static inline function native<T>(length:Int, fixed:Bool, fill:Dynamic):Vector<T> {
      return new AS3Vector(length, fixed, fill);
   }

   public static macro function create():haxe.macro.Expr {
      return port.runtime.VectorMacro.construct([]);
   }

   public static macro function sized(length:haxe.macro.Expr):haxe.macro.Expr {
      return port.runtime.VectorMacro.construct([macro Std.int($length)]);
   }

   public static macro function sizedFixed(length:haxe.macro.Expr, fixed:haxe.macro.Expr):haxe.macro.Expr {
      return port.runtime.VectorMacro.construct([macro Std.int($length), fixed]);
   }

   public var length(get,set):Int;
   public var fixed(get,set):Bool;

   @:arrayAccess public inline function get(index:Int):T {
      return this.get(index);
   }

   @:arrayAccess public inline function set(index:Int, value:T):T {
      this.set(index, value);
      return value;
   }

   public inline function push(value:T):Int {
      return this.push(value);
   }

   public inline function pop():T {
      return this.pop();
   }

   public inline function shift():T {
      return this.shift();
   }

   public inline function unshift(value:T):Int {
      return this.unshift(value);
   }

   public inline function insertAt(index:Int, value:T):Void {
      this.insertAt(index, value);
   }

   public inline function removeAt(index:Int):T {
      return this.removeAt(index);
   }

   public inline function insert(index:Int, value:T):Void {
      this.insertAt(index, value);
   }

   public function remove(value:T):Bool {
      var at = this.indexOf(value);
      if (at < 0) {
         return false;
      }
      this.removeAt(at);
      return true;
   }

   public inline function contains(value:T):Bool {
      return this.indexOf(value) >= 0;
   }

   public inline function splice(start:Dynamic, ?deleteCount:Dynamic, ?items:Array<T>):Vector<T> {
      return this.splice(Std.int(start), deleteCount == null ? 0x7fffffff : Std.int(deleteCount),
         items == null ? [] : cast items);
   }

   public inline function slice(?start:Dynamic = 0, ?end:Dynamic = 0x7fffffff):Vector<T> {
      return this.slice(Std.int(start), Std.int(end));
   }

   public inline function indexOf(value:T, ?from:Int = 0):Int {
      return this.indexOf(value, from);
   }

   public inline function lastIndexOf(value:T, ?from:Int = 0x7fffffff):Int {
      return this.lastIndexOf(value, from);
   }

   public inline function join(?separator:String = ","):String {
      return this.join(separator);
   }

   public inline function reverse():Vector<T> {
      return this.reverse();
   }

   public inline function sort(compare:Dynamic):Vector<T> {
      return this.sort(compare);
   }

   public inline function filter(callback:Dynamic, ?thisObject:Dynamic):Vector<T> {
      return this.filter(callback, thisObject);
   }

   public inline function map(callback:Dynamic, ?thisObject:Dynamic):Vector<T> {
      return this.map(callback, thisObject);
   }

   public inline function forEach(callback:Dynamic, ?thisObject:Dynamic):Void {
      this.forEach(callback, thisObject);
   }

   public inline function some(callback:Dynamic, ?thisObject:Dynamic):Bool {
      return this.some(callback, thisObject);
   }

   public inline function every(callback:Dynamic, ?thisObject:Dynamic):Bool {
      return this.every(callback, thisObject);
   }

   public inline function iterator():Iterator<T> {
      return cast this.data.iterator();
   }

   public inline function keyValueIterator():KeyValueIterator<Int, T> {
      return cast this.data.keyValueIterator();
   }

   public inline function copy():Vector<T> {
      return this.concat(null);
   }

   public inline function concat(?values:Dynamic):Vector<T> {
      return this.concat(values);
   }

   public inline function toString():String {
      return this.toString();
   }

   public static function ofArray<T>(values:Array<T>):Vector<T> {
      var raw = unwrap(values);
      if (raw != null) {
         if (arrayKinds == null) {
            arrayKinds = [hl.Type.getDynamic(unwrap(([] : Array<Float>))), hl.Type.getDynamic(unwrap(([] : Array<Int>)))];
         }
         var kind = hl.Type.getDynamic(raw);
         if (kind == arrayKinds[0]) {
            var floats:Array<Float> = cast raw;
            var out = new AS3Vector(0, false, 0.0);
            for (i in 0...floats.length) out.setFloat(i, floats[i]);
            return out;
         }
         if (kind == arrayKinds[1]) {
            var ints:Array<Int> = cast raw;
            return AS3Vector.wrap([for (i in 0...ints.length) (ints[i] : Dynamic)], 0);
         }
      }
      return AS3Vector.wrap(values == null ? [] : [for (item in values) (item : Dynamic)]);
   }

   static var arrayKinds:Array<hl.Type>;

   @:access(hl.types.ArrayDyn)
   static function unwrap(values:Dynamic):Dynamic {
      if (values == null) return null;
      return Std.isOfType(values, hl.types.ArrayDyn) ? (values : hl.types.ArrayDyn).array : values;
   }

   @:from public static function fromArray<T>(values:Array<T>):Vector<T> {
      return ofArray(values);
   }

   @:to public function toArray():Array<T> {
      return [for (item in this.data) (item : T)];
   }

   @:from static function fromOpenflInts(values:openfl.Vector<Int>):Vector<Int> {
      return AS3Vector.wrap([for (i in 0...values.length) (values[i] : Dynamic)], 0);
   }

   @:from static function fromOpenflUInts(values:openfl.Vector<UInt>):Vector<UInt> {
      return AS3Vector.wrap([for (i in 0...values.length) (values[i] : Dynamic)], 0);
   }

   @:from static function fromOpenflFloats(values:openfl.Vector<Float>):Vector<Float> {
      return AS3Vector.wrap([for (i in 0...values.length) (values[i] : Dynamic)], 0.0);
   }

   @:from static function fromOpenflObjects<T:{}>(values:openfl.Vector<T>):Vector<T> {
      return AS3Vector.wrap([for (i in 0...values.length) (values[i] : Dynamic)]);
   }

   static var scratchFloats:Array<openfl.Vector<Float>> = [];

   @:to static function toOpenflFloats(store:AS3Vector):openfl.Vector<Float> {
      var n = store.getLength();
      var out = n < 64 ? scratchFloats[n] : null;
      if (out == null) {
         out = new openfl.Vector<Float>(n);
         if (n < 64) scratchFloats[n] = out;
      }
      for (i in 0...n) out[i] = store.floatAt(i);
      return out.copy();
   }

   static var scratchInts:Array<openfl.Vector<Int>> = [];

   @:to static function toOpenflInts(store:AS3Vector):openfl.Vector<Int> {
      var n = store.getLength();
      var out = n < 64 ? scratchInts[n] : null;
      if (out == null) {
         out = new openfl.Vector<Int>(n);
         if (n < 64) scratchInts[n] = out;
      }
      for (i in 0...n) out[i] = store.intAt(i);
      return out.copy();
   }

   @:to static function toOpenflUInts(store:AS3Vector):openfl.Vector<UInt> {
      var out = new openfl.Vector<UInt>();
      for (i in 0...store.getLength()) {
         out.push(store.intAt(i));
      }
      return out;
   }

   @:to static function toOpenflStrings(store:AS3Vector):openfl.Vector<String> {
      var out = new openfl.Vector<String>();
      for (item in store.data) {
         out.push(item);
      }
      return out;
   }

   @:to static function toOpenflGraphicsData(store:AS3Vector):openfl.Vector<openfl.display.IGraphicsData> {
      var out = new openfl.Vector<openfl.display.IGraphicsData>();
      for (item in store.data) {
         out.push(item);
      }
      return out;
   }

   inline function get_length():Int {
      return this.getLength();
   }

   inline function set_length(value:Int):Int {
      return this.setLength(value);
   }

   inline function get_fixed():Bool {
      return this.fixed;
   }

   inline function set_fixed(value:Bool):Bool {
      return this.fixed = value;
   }
}
#end
