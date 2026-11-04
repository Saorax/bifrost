package port.runtime;

class AS3Vector {
   var items:Array<Dynamic>;
   var floats:Array<Float>;
   var ints:Array<Int>;
   public static var intDemotions = 0;
   public var data(get, set):Array<Dynamic>;
   public var fixed:Bool;
   public var fill:Dynamic;

   static inline var BOX_MIN = -128;
   static inline var BOX_COUNT = 4224;
   static var boxes:hl.NativeArray<Dynamic>;

   static function makeBoxes():hl.NativeArray<Dynamic> {
      var out = new hl.NativeArray<Dynamic>(BOX_COUNT);
      for (i in 0...BOX_COUNT) out[i] = (i + BOX_MIN : Dynamic);
      return boxes = out;
   }

   public static inline function box(value:Dynamic):Dynamic {
      return value != null && hl.Type.getDynamic(value).kind == hl.Type.TypeKind.HI32 ? shared(value) : value;
   }

   static function shared(value:Dynamic):Dynamic {
      var i:Int = value;
      var at = i - BOX_MIN;
      return at >= 0 && at < BOX_COUNT ? (boxes == null ? makeBoxes() : boxes)[at] : value;
   }

   static function boxInt(value:Int):Dynamic {
      var at = value - BOX_MIN;
      return at >= 0 && at < BOX_COUNT ? (boxes == null ? makeBoxes() : boxes)[at] : (value : Dynamic);
   }

   static inline function isInt(value:Dynamic):Bool {
      return value != null && hl.Type.getDynamic(value).kind == hl.Type.TypeKind.HI32;
   }

   public function new(length:Int = 0, fixed:Bool = false, ?fill:Dynamic) {
      fill = box(fill);
      this.fill = fill;
      if (fill != null && hl.Type.getDynamic(fill).kind == hl.Type.TypeKind.HF64) {
         floats = [];
         var zero:Float = fill;
         for (i in 0...length) {
            floats.push(zero);
         }
      #if !as3_boxed_int_vectors
      } else if (isInt(fill)) {
         ints = [];
         var zero:Int = fill;
         for (i in 0...length) {
            ints.push(zero);
         }
      #end
      } else {
         items = [];
         for (i in 0...length) {
            items.push(fill);
         }
      }
      this.fixed = fixed;
   }

   public static function wrap(values:Array<Dynamic>, ?fill:Dynamic):AS3Vector {
      var out = new AS3Vector(0, false, fill);
      if (out.floats != null) {
         for (i in 0...values.length) out.floats.push(number(values[i]));
         return out;
      }
      if (out.ints != null) {
         var all = true;
         for (i in 0...values.length) {
            if (!isInt(values[i])) {
               all = false;
               break;
            }
         }
         if (all) {
            for (i in 0...values.length) out.ints.push(values[i]);
            return out;
         }
         out.ints = null;
      }
      for (i in 0...values.length) values[i] = box(values[i]);
      out.items = values;
      return out;
   }

   static inline function number(value:Dynamic):Float {
      return value != null && hl.Type.getDynamic(value).kind == hl.Type.TypeKind.HF64 ? (value : Float)
         : As3.toFloatValue(value);
   }

   public inline function isFloatStore():Bool {
      return floats != null;
   }

   public inline function isIntStore():Bool {
      return ints != null;
   }

   inline function get_data():Array<Dynamic> {
      if (floats != null) demote();
      if (ints != null) demoteInts();
      return items;
   }

   function set_data(values:Array<Dynamic>):Array<Dynamic> {
      floats = null;
      ints = null;
      return items = values;
   }

   function demoteInts():Void {
      var values:Array<Dynamic> = [];
      for (i in 0...ints.length) values.push(boxInt(ints[i]));
      items = values;
      ints = null;
      intDemotions++;
   }

   public function getInt(index:Int):Int {
      if (ints != null) {
         if (index < 0 || index >= ints.length) {
            throw outOfRange(index);
         }
         return ints[index];
      }
      return As3.toIntValue(get(index));
   }

   public function getNumber(index:Int):Float {
      if (floats != null) {
         return getFloat(index);
      }
      if (ints != null) {
         if (index < 0 || index >= ints.length) {
            throw outOfRange(index);
         }
         return ints[index];
      }
      return As3.toFloatValue(get(index));
   }

   public function setInt(index:Int, value:Int):Int {
      if (ints != null) {
         if (index < 0 || index > ints.length || (index == ints.length && fixed)) {
            throw outOfRange(index);
         }
         ints[index] = value;
         return value;
      }
      set(index, value);
      return value;
   }

   function demote():Void {
      var values:Array<Dynamic> = [];
      for (i in 0...floats.length) values.push((floats[i] : Dynamic));
      items = values;
      floats = null;
   }

   public function getFloat(index:Int):Float {
      if (floats != null) {
         if (index < 0 || index >= floats.length) {
            throw outOfRange(index);
         }
         return floats[index];
      }
      return get(index);
   }

   public function setFloat(index:Int, value:Float):Float {
      if (floats != null) {
         if (index < 0 || index > floats.length || (index == floats.length && fixed)) {
            throw outOfRange(index);
         }
         floats[index] = value;
         return value;
      }
      set(index, value);
      return value;
   }

   public inline function floatAt(index:Int):Float {
      return floats != null ? floats[index] : ints != null ? ints[index] : (items[index] : Float);
   }

   public inline function intAt(index:Int):Int {
      return ints != null ? ints[index] : (items[index] : Int);
   }

   public var length(get, set):Int;

   @:keep function get_length():Int {
      return getLength();
   }

   @:keep function set_length(value:Int):Int {
      return setLength(value);
   }

   @:keep function __get_field(fid:Int):Dynamic {
      if (fid == untyped $hash("length")) {
         return getLength();
      }
      return null;
   }

   public inline function getLength():Int {
      return floats != null ? floats.length : ints != null ? ints.length : items.length;
   }

   public function setLength(value:Int):Int {
      checkFixed();
      if (ints != null) {
         if (value < ints.length) {
            ints.resize(value);
         } else {
            var zero:Int = fill;
            while (ints.length < value) {
               ints.push(zero);
            }
         }
         return value;
      }
      if (floats != null) {
         if (value < floats.length) {
            floats.resize(value);
         } else {
            var zero:Float = fill;
            while (floats.length < value) {
               floats.push(zero);
            }
         }
         return value;
      }
      if (value < data.length) {
         data.splice(value, data.length - value);
      } else {
         while (data.length < value) {
            data.push(fill);
         }
      }
      return value;
   }

   public function get(index:Int):Dynamic {
      if (floats != null) {
         return getFloat(index);
      }
      if (ints != null) {
         if (index < 0 || index >= ints.length) {
            throw outOfRange(index);
         }
         return boxInt(ints[index]);
      }
      if (index < 0 || index >= items.length) {
         throw outOfRange(index);
      }
      return items[index];
   }

   public function set(index:Int, value:Dynamic):Dynamic {
      if (floats != null) {
         setFloat(index, number(value));
         return value;
      }
      if (ints != null) {
         if (isInt(value)) {
            setInt(index, value);
            return value;
         }
         demoteInts();
      }
      if (index < 0 || index > items.length || (index == items.length && fixed)) {
         throw outOfRange(index);
      }
      items[index] = box(value);
      return value;
   }

   public function push(value:Dynamic):Int {
      checkFixed();
      if (floats != null) {
         return floats.push(number(value));
      }
      if (ints != null) {
         if (isInt(value)) {
            return ints.push(value);
         }
         demoteInts();
      }
      return items.push(box(value));
   }

   public function pushFloat(value:Float):Int {
      if (floats != null) {
         checkFixed();
         return floats.push(value);
      }
      return push(value);
   }

   public function pushInt(value:Int):Int {
      if (ints != null) {
         checkFixed();
         return ints.push(value);
      }
      return push(value);
   }

   public function pop():Dynamic {
      checkFixed();
      if (floats != null) {
         return floats.length == 0 ? fill : (floats.pop() : Dynamic);
      }
      if (ints != null) {
         return ints.length == 0 ? fill : boxInt(ints.pop());
      }
      return items.length == 0 ? fill : items.pop();
   }

   public function shift():Dynamic {
      checkFixed();
      if (ints != null) {
         return ints.length == 0 ? fill : boxInt(ints.shift());
      }
      return data.length == 0 ? fill : data.shift();
   }

   public function unshift(value:Dynamic):Int {
      checkFixed();
      if (ints != null && isInt(value)) {
         ints.unshift(value);
         return ints.length;
      }
      data.unshift(box(value));
      return data.length;
   }

   public function insertAt(index:Int, value:Dynamic):Void {
      checkFixed();
      data.insert(clampIndex(index), box(value));
   }

   public function removeAt(index:Int):Dynamic {
      checkFixed();
      var at = index < 0 ? index + data.length : index;
      if (at < 0 || at >= data.length) {
         throw outOfRange(index);
      }
      return data.splice(at, 1)[0];
   }

   public function splice(start:Int, deleteCount:Int, items:Array<Dynamic>):AS3Vector {
      var at = clampIndex(start);
      var count = deleteCount < 0 ? 0 : deleteCount;
      if (count > data.length - at) {
         count = data.length - at;
      }
      if (fixed && count != items.length) {
         throw notFixed();
      }
      var removed = data.splice(at, count);
      for (i in 0...items.length) {
         data.insert(at + i, box(items[i]));
      }
      return wrap(removed, fill);
   }

   public function slice(start:Int = 0, end:Int = 0x7fffffff):AS3Vector {
      return wrap(data.slice(clampIndex(start), clampIndex(end)), fill);
   }

   public function concat(other:Dynamic):AS3Vector {
      var out = wrap(data.copy(), fill);
      if (other != null) {
         if (Std.isOfType(other, AS3Vector)) {
            for (item in (other : AS3Vector).data) {
               out.data.push(box(item));
            }
         } else {
            var values:Array<Dynamic> = other;
            for (item in values) {
               out.data.push(box(item));
            }
         }
      }
      return out;
   }

   public function indexOf(value:Dynamic, from:Int = 0):Int {
      if (ints != null && isInt(value)) {
         var wanted:Int = value;
         var i = from < 0 ? Std.int(Math.max(0, ints.length + from)) : from;
         while (i < ints.length) {
            if (ints[i] == wanted) {
               return i;
            }
            i++;
         }
         return -1;
      }
      var i = from < 0 ? Std.int(Math.max(0, data.length + from)) : from;
      while (i < data.length) {
         if (data[i] == value) {
            return i;
         }
         i++;
      }
      return -1;
   }

   public function lastIndexOf(value:Dynamic, from:Int = 0x7fffffff):Int {
      var i = from < 0 ? data.length + from : (from >= data.length ? data.length - 1 : from);
      while (i >= 0) {
         if (data[i] == value) {
            return i;
         }
         i--;
      }
      return -1;
   }

   public function join(separator:String = ","):String {
      var parts = [for (item in data) item == null ? "null" : Std.string(item)];
      return parts.join(separator);
   }

   public function reverse():AS3Vector {
      data.reverse();
      return this;
   }

   public function sort(compare:Dynamic):AS3Vector {
      if (Reflect.isFunction(compare)) {
         data.sort(function(a, b) {
            var r:Float = compare(a, b);
            return r < 0 ? -1 : (r > 0 ? 1 : 0);
         });
      } else {
         var options:Int = compare == null ? 0 : Std.int(compare);
         var numeric = options & 16 != 0;
         var caseless = options & 1 != 0;
         var descending = options & 2 != 0;
         data.sort(function(a, b) {
            var r = 0;
            if (numeric) {
               var x:Float = a;
               var y:Float = b;
               r = x < y ? -1 : (x > y ? 1 : 0);
            } else {
               var x = Std.string(a);
               var y = Std.string(b);
               if (caseless) {
                  x = x.toLowerCase();
                  y = y.toLowerCase();
               }
               r = x < y ? -1 : (x > y ? 1 : 0);
            }
            return descending ? -r : r;
         });
      }
      return this;
   }

   public function filter(callback:Dynamic, ?thisObject:Dynamic):AS3Vector {
      var out = wrap([], fill);
      for (i in 0...data.length) {
         var item = data[i];
         if (As3.toBoolValue(callback(item, i, this))) {
            out.data.push(item);
         }
      }
      return out;
   }

   public function map(callback:Dynamic, ?thisObject:Dynamic):AS3Vector {
      return wrap([for (i in 0...data.length) callback(data[i], i, this)], fill);
   }

   public function forEach(callback:Dynamic, ?thisObject:Dynamic):Void {
      for (i in 0...data.length) {
         callback(data[i], i, this);
      }
   }

   public function some(callback:Dynamic, ?thisObject:Dynamic):Bool {
      for (i in 0...data.length) {
         if (As3.toBoolValue(callback(data[i], i, this))) {
            return true;
         }
      }
      return false;
   }

   public function every(callback:Dynamic, ?thisObject:Dynamic):Bool {
      for (i in 0...data.length) {
         if (!As3.toBoolValue(callback(data[i], i, this))) {
            return false;
         }
      }
      return true;
   }

   public function toString():String {
      return join(",");
   }

   inline function clampIndex(index:Int):Int {
      return index < 0 ? Std.int(Math.max(0, data.length + index)) : (index > data.length ? data.length : index);
   }

   inline function checkFixed():Void {
      if (fixed) {
         throw notFixed();
      }
   }

   function outOfRange(index:Int):Dynamic {
      return new openfl.errors.RangeError("Error #1125: The index " + index + " is out of range " + getLength()
         + ".");
   }

   function notFixed():Dynamic {
      return new openfl.errors.RangeError("Error #1126: Cannot change the length of a fixed Vector.");
   }
}
