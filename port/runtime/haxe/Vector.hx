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

@:forward(iterator, keyValueIterator, join, reverse, filter, map, indexOf, lastIndexOf, remove, contains, slice, splice, push, pop, shift, unshift, insert)
abstract Vector<T>(flash.Vector<T>) from flash.Vector<T> to flash.Vector<T> {
   public inline function new(?length:Dynamic = 0, ?fixed:Bool = false) {
      this = new flash.Vector<T>(Std.int(length), fixed);
   }

#if flash
   public static inline function create<T>():Vector<T> {
      return new flash.Vector<T>();
   }
#else
   public static macro function create():haxe.macro.Expr {
      return port.runtime.VectorMacro.construct([]);
   }
#end

#if flash
   public static inline function sized<T>(length:Dynamic):Vector<T> {
      return new flash.Vector<T>(length);
   }

   public static inline function sizedFixed<T>(length:Dynamic, fixed:Bool):Vector<T> {
      return new flash.Vector<T>(length, fixed);
   }
#else
   public static macro function sized(length:haxe.macro.Expr):haxe.macro.Expr {
      return port.runtime.VectorMacro.construct([macro Std.int($length)]);
   }

   public static macro function sizedFixed(length:haxe.macro.Expr, fixed:haxe.macro.Expr):haxe.macro.Expr {
      return port.runtime.VectorMacro.construct([macro Std.int($length), fixed]);
   }
#end

   public var length(get,set):Int;
   public var fixed(get,set):Bool;

   @:arrayAccess public inline function get(index:Int):T {
      return this[index];
   }

   @:arrayAccess public inline function set(index:Int, value:T):T {
      return this[index] = value;
   }

   public inline function sort(compare:Dynamic):Vector<T> {
      this.sort(cast compare);
      return cast this;
   }

#if flash
   public inline function copy():Vector<T> {
      return cast this.concat();
   }

   public static inline function ofArray<T>(values:Array<T>):Vector<T> {
      return flash.Vector.ofArray(values);
   }

   @:from public static inline function fromArray<T>(values:Array<T>):Vector<T> {
      return flash.Vector.ofArray(values);
   }

   public inline function concat(?values:Dynamic):Vector<T> {
      return cast this.concat(cast values);
   }
#else
   public function copy():Vector<T> {
      var out = new Vector<T>();
      for(item in this) {
         out.push(item);
      }
      return out;
   }

   public inline function concat(?values:Dynamic):Vector<T> {
      var out = copy();
      if(values != null) {
         var iterable:Iterable<T> = cast values;
         for(item in iterable) {
            out.push(item);
         }
      }
      return out;
   }

   public static function ofArray<T>(values:Array<T>):Vector<T> {
      var out = new Vector<T>();
      if(values != null) {
         for(item in values) {
            out.push(item);
         }
      }
      return out;
   }

   @:from public static function fromArray<T>(values:Array<T>):Vector<T> {
      return ofArray(values);
   }
#end

   @:to public function toArray():Array<T> {
      var out:Array<T> = [];
      for(item in this) {
         out.push(item);
      }
      return out;
   }

   inline function get_length():Int {
      return this.length;
   }

   inline function set_length(value:Int):Int {
      this.length = value;
      return value;
   }

   inline function get_fixed():Bool {
#if flash
      return this.fixed;
#else
      return false;
#end
   }

   inline function set_fixed(value:Bool):Bool {
#if flash
      this.fixed = value;
#end
      return value;
   }
}
#end
