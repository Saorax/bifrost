package port.runtime;

#if !macro
import port.runtime.E4X;
#end

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

class As3 {
#if !macro
    public static var ARRAY_CASEINSENSITIVE:Dynamic = 1;
    public static var ARRAY_DESCENDING:Dynamic = 2;
    public static var ARRAY_NUMERIC:Dynamic = 16;
    public static var FLOAT_MAX_VALUE:Float = 1.7976931348623157e308;
    public static var INT_MAX_VALUE:Int = 2147483647;
    public static var UINT_MAX_VALUE:UInt = 0xFFFFFFFF;
    public static var INT_MIN_VALUE:Int = 0x80000000;
    public static var UINT_MIN_VALUE:UInt = 0;
    public static var FLOAT_MIN_VALUE:Float = 4.9e-324;

    public static function asTypeValue<T>(value:Dynamic, type:Dynamic):Null<T> {
        if (value == null) {
            return null;
        }
        return isType(value, type) ? cast value : null;
    }

    public static function isType(value:Dynamic, type:Dynamic):Bool {
        if (value == null) {
            return false;
        }
        if (Std.isOfType(type, String)) {
            return isNamedType(value, cast type);
        }
        return Std.isOfType(value, type);
    }

#if flash
    public static extern inline function dyn(value:Dynamic):Dynamic {
        return value;
    }
#else
    static var expandos:haxe.ds.ObjectMap<Dynamic, Dynamic>;

    public static function dyn(value:Dynamic):Dynamic {
        if (value == null || Type.getClass(value) == null) {
            return value;
        }
        #if (hl && (openfl || heaps))
        if (Std.isOfType(value, openfl.display.DisplayObject)) {
            var object:openfl.display.DisplayObject = value;
            if (object.__portFields == null) object.__portFields = {};
            return object.__portFields;
        }
        #end
        if (expandos == null) {
            expandos = new haxe.ds.ObjectMap();
        }
        var fields = expandos.get(value);
        if (fields == null) {
            fields = {};
            expandos.set(value, fields);
        }
        return fields;
    }
#end

#if hl
    public static extern inline function sin(x:Float):Float return AirMath.math1(0, x);
    public static extern inline function cos(x:Float):Float return AirMath.math1(1, x);
    public static extern inline function tan(x:Float):Float return AirMath.math1(2, x);
    public static extern inline function asin(x:Float):Float return AirMath.math1(3, x);
    public static extern inline function acos(x:Float):Float return AirMath.math1(4, x);
    public static extern inline function atan(x:Float):Float return AirMath.math1(5, x);
    public static extern inline function exp(x:Float):Float return AirMath.math1(6, x);
    public static extern inline function log(x:Float):Float return AirMath.math1(7, x);
    public static extern inline function atan2(y:Float, x:Float):Float return AirMath.math2(0, y, x);
    public static extern inline function pow(x:Float, y:Float):Float return AirMath.pow(x, y);

    #if (openfl || heaps)
    public static function setRawData(matrix:flash.geom.Matrix3D, values:AS3Vector):Void {
        var own = matrix.rawData, n = values.getLength();
        if (own != null && own.length == n) {
            for (i in 0...n) own[i] = values.floatAt(i);
            return;
        }
        matrix.rawData = (values : Vector<Float>);
    }
    #end
#end

    public static function boxed(value:Dynamic):Dynamic {
        return value;
    }

    public static function re(pattern:String, flags:String = ""):Dynamic {
        return new RegExp(pattern, flags);
    }

    public static function splitRe(text:String, pattern:Dynamic):Array<Dynamic> {
        #if flash
        return untyped text.split(pattern);
        #else
        if (Std.isOfType(pattern, RegExp)) return (pattern : RegExp).splitText(text);
        return cast text.split(Std.string(pattern));
        #end
    }

    public static function replace(text:String, pattern:Dynamic, by:String):String {
        return pattern.replace(text, by);
    }

    public static function toIntValue(value:Dynamic):Int {
        #if flash
        return Std.int(value);
        #else
        #if hl
        if (value != null && hl.Type.getDynamic(value).kind == HI32) return (value : Int);
        #end
        return toInt32(toNumber(value));
        #end
    }

    #if !flash
    public static function toNumber(value:Dynamic):Float {
        if (value == null) {
            return 0;
        }
        #if hl
        switch (hl.Type.getDynamic(value).kind) {
            case HI32: return (value : Int);
            case HF64: return (value : Float);
            case HBool: return (value : Bool) ? 1 : 0;
            default:
        }
        #end
        if (Std.isOfType(value, Float)) {
            return (value : Float);
        }
        if (Std.isOfType(value, Bool)) {
            return (value : Bool) ? 1 : 0;
        }
        if (Std.isOfType(value, String)) {
            var text = StringTools.trim((value : String));
            if (text == "") {
                return 0;
            }
            var lower = text.toLowerCase();
            if (StringTools.startsWith(lower, "0x")) {
                var hex = text.substr(2);
                if (!~/^[0-9a-fA-F]+$/.match(hex)) {
                    return Math.NaN;
                }
                var n = 0.0;
                for (i in 0...hex.length) {
                    n = n * 16 + Std.parseInt("0x" + hex.charAt(i));
                }
                return n;
            }
            if (~/^[+-]?(Infinity|(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?)$/.match(text)) {
                return StringTools.endsWith(text, "Infinity")
                    ? (StringTools.startsWith(text, "-") ? Math.NEGATIVE_INFINITY : Math.POSITIVE_INFINITY)
                    : Std.parseFloat(text);
            }
            return Math.NaN;
        }
        #if !flash
        if (Std.isOfType(value, XML) || Std.isOfType(value, E4X.XMLListData)) {
            return toNumber(Std.string(value));
        }
        #end
        return Math.NaN;
    }

    public static inline function codeAtInt(s:String, i:Int):Int {
        return (i : UInt) < (s.length : UInt) ? StringTools.fastCodeAt(s, i) : 0;
    }

    public static inline function toInt32(n:Float):Int {
        return (n > -2147483649.0 && n < 2147483648.0) ? Std.int(n) : toInt32Wide(n);
    }

    public static function toInt32Wide(n:Float):Int {
        if (n > -2147483649.0 && n < 2147483648.0) {
            return Std.int(n);
        }
        if (Math.isNaN(n) || !Math.isFinite(n)) {
            return 0;
        }
        var t = n < 0 ? Math.fceil(n) : Math.ffloor(n);
        if (t >= -2147483648.0 && t <= 2147483647.0) {
            return Std.int(t);
        }
        var m = t % 4294967296.0;
        if (m < 0) {
            m += 4294967296.0;
        }
        return m >= 2147483648.0 ? Std.int(m - 4294967296.0) : Std.int(m);
    }
    #end

    public static function coerceStringValue(value:Dynamic):String {
        return value == null ? null : str(value);
    }

    public static #if flash inline #end function str(value:Dynamic):String {
        #if flash
        return Std.string(value);
        #else
        return Std.isOfType(value, String) ? (value : String) : Std.string(value);
        #end
    }

    public static extern inline function coerceUIntString(value:UInt):String {
        #if flash
        return cast value;
        #else
        return haxe.Int64.toStr(haxe.Int64.make(0, cast value));
        #end
    }

    public static extern inline function newDate():Dynamic {
        #if flash
        return untyped __new__(Date);
        #else
        return Date.now();
        #end
    }

    public static function toUIntValue(value:Dynamic):UInt {
        #if flash
        return cast Std.int(value);
        #else
        #if hl
        if (value != null && hl.Type.getDynamic(value).kind == HI32) return cast (value : Int);
        #end
        return cast toInt32(toNumber(value));
        #end
    }

    public static function imapExists(m:Dynamic, key:Dynamic):Bool {
        if (Std.isOfType(m, haxe.ds.StringMap)) return (cast m : haxe.ds.StringMap<Dynamic>).exists(key);
        if (Std.isOfType(m, haxe.ds.IntMap)) return (cast m : haxe.ds.IntMap<Dynamic>).exists(key);
        return m.exists(key);
    }

    public static function imapGet(m:Dynamic, key:Dynamic):Dynamic {
        if (Std.isOfType(m, haxe.ds.StringMap)) return (cast m : haxe.ds.StringMap<Dynamic>).method_4935(key);
        if (Std.isOfType(m, haxe.ds.IntMap)) return (cast m : haxe.ds.IntMap<Dynamic>).method_4935(key);
        return m.method_4935(key);
    }

    public static function imapHasNext(m:Dynamic):Bool {
        if (Std.isOfType(m, haxe.ds.StringMap)) return (cast m : haxe.ds.StringMap<Dynamic>).hasValues();
        if (Std.isOfType(m, haxe.ds.IntMap)) return (cast m : haxe.ds.IntMap<Dynamic>).hasValues();
        return m.iterator().hasNext();
    }

    public static inline function uintToFloat(value:UInt):Float {
        var bits:Int = cast value;
        return bits >= 0 ? (bits : Float) : (bits : Float) + 4294967296.0;
    }

    public static function uintDynamic(value:UInt):Dynamic {
        var bits:Int = cast value;
        return bits >= 0 ? (bits : Dynamic) : ((bits : Float) + 4294967296.0 : Dynamic);
    }

    public static function toFloatValue(value:Dynamic):Float {
        #if flash
        return value;
        #else
        return toNumber(value);
        #end
    }

    public static function negDynamicToFloat(value:Dynamic):Float {
        #if hl
        if (value != null) switch (hl.Type.getDynamic(value).kind) {
            case HI32: return (((value : Int) * -1 : Int) : Float);
            case HF64: return (value : Float) * -1.0;
            default:
        }
        #end
        return toFloatValue(value * -1);
    }

    public static function looseEquals(a:Dynamic, b:Dynamic):Bool {
        #if flash
        return untyped a == b;
        #else
        if (a == null || b == null) {
            return a == null && b == null;
        }
        var aText = Std.isOfType(a, String);
        var bText = Std.isOfType(b, String);
        if (aText && bText) {
            return (a : String) == (b : String);
        }
        var aNum = !aText && (Std.isOfType(a, Float) || Std.isOfType(a, Bool));
        var bNum = !bText && (Std.isOfType(b, Float) || Std.isOfType(b, Bool));
        if ((aNum && (bNum || bText)) || (bNum && aText)) {
            return toNumber(a) == toNumber(b);
        }
        return a == b;
        #end
    }

    public static function toBoolValue(value:Dynamic):Bool {
        if (value == null) {
            return false;
        }
        #if hl
        var type = hl.Type.getDynamic(value);
        switch (type.kind) {
            case HBool:
                return cast value;
            case HUI8, HUI16, HI32, HF64:
                return value != 0 && !Math.isNaN(value);
            case HObj:
                return Std.isOfType(value, String) ? str(value).length > 0 : true;
            case HDynObj, HFun:
                return true;
            default:
        }
        #end
        if (Std.isOfType(value, Bool)) {
            return cast value;
        }
        if (Std.isOfType(value, Int) || Std.isOfType(value, Float)) {
            return value != 0 && !Math.isNaN(value);
        }
        if (Std.isOfType(value, String)) {
            return str(value).length > 0;
        }
        return true;
    }

    public static function logicalOrValue(left:Dynamic, right:Dynamic):Dynamic {
        return toBool(left) ? left : right;
    }

    public static function logicalAndValue(left:Dynamic, right:Dynamic):Dynamic {
        return toBool(left) ? right : left;
    }

    public static function compareValue(left:Dynamic, op:String, right:Dynamic):Bool {
        return switch (op) {
            case ">": left > right;
            case "<": left < right;
            case ">=": left >= right;
            case "<=": left <= right;
            case "==": left == right;
            case "!=": left != right;
            default: false;
        };
    }

    public static function numericValue(op:String, left:Dynamic, right:Dynamic):Dynamic {
        return switch (op) {
            case "+": toFloat(left) + toFloat(right);
            case "-": toFloat(left) - toFloat(right);
            case "*": toFloat(left) * toFloat(right);
            case "/": toFloat(left) / toFloat(right);
            case "%": toFloat(left) % toFloat(right);
            default: Math.NaN;
        };
    }

    public static inline function typeOf(value:Dynamic):String {
        #if flash
        return untyped __typeof__(value);
        #else
        if (value == null) {
            return "object";
        }
        if (Reflect.isFunction(value)) {
            return "function";
        }
        if (Std.isOfType(value, String)) {
            return "string";
        }
        if (Std.isOfType(value, Bool)) {
            return "boolean";
        }
        if (Std.isOfType(value, Int) || Std.isOfType(value, Float)) {
            return "number";
        }
        return "object";
        #end
    }

    public static inline function intMap(value:Dynamic):haxe.ds.IntMap<Dynamic> {
        return cast value;
    }

    public static inline function stringMap(value:Dynamic):haxe.ds.StringMap<Dynamic> {
        return cast value;
    }

    public static function asObject(value:Dynamic):Dynamic {
        return value;
    }

    public static function comma<T>(first:Dynamic, second:T):T {
        return second;
    }

    public static inline function getTimer():Int {
        #if flash
        return flash.Lib.getTimer();
        #elseif port_smoke
        return SmokeClock.now();
        #elseif heaps
        return Std.int((haxe.Timer.stamp() - timerBase) * 1000);
        #else
        return Std.int(haxe.Timer.stamp() * 1000);
        #end
    }

    #if (heaps && !flash && !port_smoke)
    static var timerBase:Float = haxe.Timer.stamp();
    #end

    public static function parseInt(value:Dynamic, radix:Dynamic = null):Float {
        var text = str(value);
        var base = radix == null ? 10 : toInt(radix);
        var parsed = Std.parseInt(base == 16 ? "0x" + text : text);
        return parsed == null ? Math.NaN : parsed;
    }

    public static function encodeURIComponent(value:Dynamic):String {
        return StringTools.urlEncode(str(value));
    }

    public static function getDefinitionByName(name:String):Dynamic {
        var found:Dynamic = resolveDefinition(name);
        if (found == null && StringTools.startsWith(name, "class_")) {
            found = resolveDefinition("Class_" + name.substr(6));
        }
        #if flash
        if (found == null) {
            throw new flash.errors.ReferenceError("Error #1065: Variable " + name + " is not defined.");
        }
        #end
        return found;
    }

    static function resolveDefinition(name:String):Dynamic {
        #if flash
        try {
            return untyped __global__["flash.utils.getDefinitionByName"](name);
        } catch (e:Dynamic) {
            return null;
        }
        #else
        return Type.resolveClass(name);
        #end
    }

    public static inline function getQualifiedClassName(value:Dynamic):String {
        #if flash
        return untyped __global__["flash.utils.getQualifiedClassName"](value);
        #else
        var cls = Type.getClass(value);
        if (cls == null) {
            return str(value);
        }
        return Type.getClassName(cls);
        #end
    }

    public static function describeType(value:Dynamic):Dynamic {
        #if flash
        return untyped __global__["flash.utils.describeType"](value);
        #else
        if (value == null) {
            return new XML('<type name="null"/>');
        }
        var isClass = Std.isOfType(value, Class);
        var cls:Class<Dynamic> = isClass ? cast value : Type.getClass(value);
        var name = cls == null ? str(typeOf(value)) : Type.getClassName(cls);
        var type = new XML("<type/>");
        type.setAttributeValue("name", name);
        if (cls == null) {
            return type;
        }
        var names = isClass ? Type.getClassFields(cls) : Type.getInstanceFields(cls);
        for (field in names) {
            if (StringTools.startsWith(field, "get_") || StringTools.startsWith(field, "set_") || StringTools.startsWith(field, "__")) {
                continue;
            }
            var fieldValue:Dynamic = try Reflect.getProperty(value, field) catch (_:Dynamic) null;
            var node = new XML(Reflect.isFunction(fieldValue) ? "<method/>" : "<variable/>");
            node.setAttributeValue("name", field);
            if (!Reflect.isFunction(fieldValue)) {
                var valueClass = fieldValue == null ? null : Type.getClass(fieldValue);
                node.setAttributeValue("type", valueClass == null ? "*" : Type.getClassName(valueClass));
            }
            type.appendChild(node);
        }
        return type;
        #end
    }

    public static function navigateToURL(request:Dynamic, target:String = null):Void {
        #if flash
        flash.Lib.getURL(request, target);
        #elseif openfl
        openfl.Lib.navigateToURL(request, target);
        #elseif sys
        port.runtime.services.Browser.open(request);
        #end
    }

    public static function newInstance(cls:Dynamic):Dynamic {
        return createInstance(cls, []);
    }

    public static function finallyRun(body:Void->Void, cleanup:Void->Void):Void {
        try {
            body();
        } catch (e:Dynamic) {
            cleanup();
            throw e;
        }
        cleanup();
    }

    public static function finallyValue<T>(body:Void->T, cleanup:Void->Void):T {
        try {
            var value = body();
            cleanup();
            return value;
        } catch (e:Dynamic) {
            cleanup();
            throw e;
        }
    }

    public static function setTimeout(fn:Dynamic, delay:Int, ...args:Dynamic):haxe.Timer {
        return delayCall(fn, delay, args.toArray());
    }

    public static function setInterval(fn:Dynamic, delay:Int, ...args:Dynamic):haxe.Timer {
        return intervalCall(fn, delay, args.toArray());
    }

    static function delayCall(fn:Dynamic, delay:Int, list:Array<Dynamic>):haxe.Timer {
        return haxe.Timer.delay(function():Void {
            Reflect.callMethod(null, fn, list);
        }, delay);
    }

    static function intervalCall(fn:Dynamic, delay:Int, list:Array<Dynamic>):haxe.Timer {
        var timer = new haxe.Timer(delay);
        timer.run = function():Void {
            Reflect.callMethod(null, fn, list);
        };
        return timer;
    }

    public static function clearInterval(timer:haxe.Timer):Void {
        if (timer != null) {
            timer.stop();
        }
    }

    public static function hasKeyValue(target:Dynamic, key:Dynamic):Bool {
        #if hl
        if (Std.isOfType(target, port.runtime.HashTable.KeyTable)) {
            return (cast target:port.runtime.HashTable.KeyTable).has(key);
        }
        #end
        #if (hl && (openfl || heaps))
        if (Std.isOfType(target, flash.utils.Dictionary)) {
            return (cast target:flash.utils.Dictionary).exists(key);
        }
        #end
        return target != null && Reflect.hasField(target, str(key));
    }

    public static function hasOwnPropertyValue(target:Dynamic, key:Dynamic):Bool {
        if (target == null) {
            throw "TypeError: Error #1009: Cannot access a property or method of a null object reference.";
        }
        var name = str(key);
        if (Reflect.hasField(target, name)) {
            return true;
        }
        var cls = Type.getClass(target);
        return cls != null && Type.getInstanceFields(cls).indexOf(name) >= 0;
    }

    public static function field(target:Dynamic, key:String):Dynamic {
        #if !flash
        if (arrayProps != null && Std.isOfType(target, Array)) {
            var props = arrayProps.get(target);
            if (props != null && props.exists(key)) {
                return props.get(key);
            }
        }
        #end
        return target == null ? null : Reflect.field(target, key);
    }

    public static function setField(target:Dynamic, key:String, value:Dynamic):Dynamic {
        #if !flash
        if (Std.isOfType(target, Array) && Std.parseInt(key) == null) {
            if (arrayProps == null) {
                arrayProps = new haxe.ds.ObjectMap();
            }
            var props = arrayProps.get(target);
            if (props == null) {
                arrayProps.set(target, props = new Map());
            }
            props.set(key, value);
            return value;
        }
        #end
        if (target != null) {
            Reflect.setField(target, key, value);
        }
        return value;
    }

    #if !flash
    static var arrayProps:haxe.ds.ObjectMap<Dynamic, Map<String, Dynamic>>;
    #end

    public static function keys(target:Dynamic):Iterator<String> {
        if (target == null) {
            return ([]:Array<String>).iterator();
        }
        #if hl
        if (Std.isOfType(target, port.runtime.HashTable.KeyTable)) {
            return (cast target:port.runtime.HashTable.KeyTable).keys().iterator();
        }
        #end
        if (hasMember(target, "keys")) {
            return Reflect.callMethod(target, Reflect.field(target, "keys"), []);
        }
        return Reflect.fields(target).iterator();
    }

    public static function dynamicKeys(target:Dynamic):Iterator<Dynamic> {
        #if (hl && (openfl || heaps))
        if (Std.isOfType(target, flash.utils.Dictionary)) {
            return (cast target:flash.utils.Dictionary).keys();
        }
        #end
        return cast keys(target);
    }

    public static function values(target:Dynamic):Iterator<Dynamic> {
        if (target == null) {
            return [].iterator();
        }
        if (Std.isOfType(target, Array)) {
            var array:Array<Dynamic> = cast target;
            return [for (i in 0...array.length) array[i]].iterator();
        }
        #if hl
        if (Std.isOfType(target, port.runtime.HashTable.KeyTable)) {
            return (cast target:port.runtime.HashTable.KeyTable).values().iterator();
        }
        var cls = Type.getClass(target);
        if (cls != null && Type.getClassName(cls) == "port.runtime.AS3Vector") {
            var length:Int = Reflect.getProperty(target, "length");
            var get = Reflect.field(target, "get");
            return [for (i in 0...length) Reflect.callMethod(target, get, [i])].iterator();
        }
        #end
        if (hasMember(target, "iterator")) {
            return Reflect.callMethod(target, Reflect.field(target, "iterator"), []);
        }
        var fields = Reflect.fields(target);
        var values:Array<Dynamic> = [];
        for (field in fields) {
            values.push(Reflect.field(target, field));
        }
        return values.iterator();
    }

    static inline function hasMember(target:Dynamic, name:String):Bool {
        #if flash
        return Reflect.hasField(target, name);
        #else
        return Reflect.field(target, name) != null;
        #end
    }

    #if port_trace_index
    public static var indexTrail:Array<String> = [];
    #end

    public static function indexValue(target:Dynamic, key:Dynamic):Dynamic {
        if (target == null) {
            return null;
        }
        #if port_trace_index
        if (indexTrail.length >= 12) indexTrail.shift();
        indexTrail.push(Std.string(Type.typeof(target)) + "[" + Std.string(Type.typeof(key)) + "]");
        #end
        #if hl
        if (Std.isOfType(target, port.runtime.HashTable.KeyTable)) {
            return (cast target:port.runtime.HashTable.KeyTable).getValue(key);
        }
        #end
        #if (hl && (openfl || heaps))
        if (Std.isOfType(target, AS3Vector)) {
            return (cast target:AS3Vector).get(toInt(key));
        }
        if (Std.isOfType(target, flash.utils.Dictionary)) {
            return (cast target:flash.utils.Dictionary).getValue(key);
        }
        if (Std.isOfType(target, openfl.utils.ByteArray.ByteArrayData) && (Std.isOfType(key, Int) || Std.isOfType(key, Float))) {
            var bytes:openfl.utils.ByteArray = cast target;
            var i = toNumber(key);
            if (!(i >= 0 && i < bytes.length) || i != Math.ffloor(i)) {
                return null;
            }
            return bytes[Std.int(i)];
        }
        #end
        if (Std.isOfType(target, String)) {
            return (cast target:String).charAt(toInt(key));
        }
        if (Std.isOfType(target, Array)) {
            #if (hl && (openfl || heaps))
            var array:Array<Dynamic> = cast target;
            var i = toNumber(key);
            if (!(i >= 0 && i < array.length) || i != Math.ffloor(i)) {
                return null;
            }
            return array[Std.int(i)];
            #else
            return (cast target:Array<Dynamic>)[toInt(key)];
            #end
        }
        #if !flash
        if (Std.isOfType(target, E4X.XMLListData)) {
            var items = (cast target:E4X.XMLListData).items;
            var i = toNumber(key);
            return i >= 0 && i < items.length && i == Math.ffloor(i) ? items[Std.int(i)] : null;
        }
        #end
        if (hasMember(target, "method_4935")) {
            return Reflect.callMethod(target, Reflect.field(target, "method_4935"), [key]);
        }
        if (hasMember(target, "get")) {
            return Reflect.callMethod(target, Reflect.field(target, "get"), [key]);
        }
        #if (hl && (openfl || heaps))
        if (Std.isOfType(target, openfl.display.DisplayObjectContainer)) {
            var name = str(key);
            var value:Dynamic = Reflect.field(target, name);
            if (value == null) {
                var fields:Dynamic = (cast target:openfl.display.DisplayObject).__portFields;
                if (fields != null) value = Reflect.field(fields, name);
            }
            var names:Dynamic = value == null ? (cast target:openfl.display.DisplayObject).__portTimelineNames : null;
            if (names != null) {
                var placed:Dynamic = Reflect.field(names, name);
                if (placed != null && (cast placed:openfl.display.DisplayObject).parent == target) value = placed;
            }
            if (value == null) value = (cast target:openfl.display.DisplayObjectContainer).getChildByName(name);
            if (value == null && names != null) value = Reflect.field(names, name);
            return value;
        }
        #end
        return Reflect.field(target, str(key));
    }

    public static function callMember(target:Dynamic, name:String, args:Array<Dynamic>):Dynamic {
        var method:Dynamic = Reflect.field(target, name);
        if (method == null) {
            throw "TypeError: Error #1006: " + name + " is not a function.";
        }
        return Reflect.callMethod(target, method, args);
    }

    public static function callIndexed(target:Dynamic, key:Dynamic, args:Array<Dynamic>):Dynamic {
        var fn:Dynamic = indexValue(target, key);
        if (fn == null || !Reflect.isFunction(fn)) {
            throw "TypeError: Error #1006: " + Std.string(key) + " is not a function.";
        }
        return Reflect.callMethod(null, fn, args);
    }

    public static function getProp(target:Dynamic, name:String):Dynamic {
        if (target == null) {
            throw "TypeError: Error #1009: Cannot access a property or method of a null object reference.";
        }
        var value:Dynamic = Reflect.getProperty(target, name);
        #if (hl && (openfl || heaps))
        if (value == null && Std.isOfType(target, openfl.display.DisplayObject)) {
            var object:openfl.display.DisplayObject = target;
            if (object.__portFields != null) value = Reflect.field(object.__portFields, name);
        }
        #end
        return value;
    }

    public static function setProp(target:Dynamic, name:String, value:Dynamic):Dynamic {
        if (target == null) {
            throw "TypeError: Error #1009: Cannot access a property or method of a null object reference.";
        }
        #if !flash
        if (name == "length" && (Std.isOfType(target, Array) #if (hl && (openfl || heaps)) || Std.isOfType(target, AS3Vector)
            || Std.isOfType(target, openfl.utils.ByteArray.ByteArrayData) #end)) {
            setLength(target, value);
            return value;
        }
        #end
        Reflect.setProperty(target, name, value);
        return value;
    }

    public static function createInstance(cls:Dynamic, args:Array<Dynamic>):Dynamic {
        #if (hl && (openfl || heaps))
        if (Std.isOfType(cls, port.runtime.swf.SwfSymbols.SymbolClass)) {
            return (cast cls:port.runtime.swf.SwfSymbols.SymbolClass).create();
        }
        #end
        return Type.createInstance(cls, args);
    }

    public static function setIndexValue(target:Dynamic, key:Dynamic, value:Dynamic):Dynamic {
        if (target == null) {
            return value;
        }
        #if hl
        if (Std.isOfType(target, port.runtime.HashTable.KeyTable)) {
            return (cast target:port.runtime.HashTable.KeyTable).setValue(key, value);
        }
        #end
        #if (hl && (openfl || heaps))
        if (Std.isOfType(target, AS3Vector)) {
            return (cast target:AS3Vector).set(toInt(key), value);
        }
        if (Std.isOfType(target, flash.utils.Dictionary)) {
            return (cast target:flash.utils.Dictionary).setValue(key, value);
        }
        if (Std.isOfType(target, openfl.utils.ByteArray.ByteArrayData)) {
            var bytes:openfl.utils.ByteArray = cast target;
            bytes[toInt(key)] = toInt(value);
            return value;
        }
        #end
        if (Std.isOfType(target, Array)) {
            (cast target:Array<Dynamic>)[toInt(key)] = value;
            return value;
        }
        if (hasMember(target, "method_65")) {
            Reflect.callMethod(target, Reflect.field(target, "method_65"), [key, value]);
            return value;
        }
        if (hasMember(target, "set")) {
            Reflect.callMethod(target, Reflect.field(target, "set"), [key, value]);
            return value;
        }
        Reflect.setField(target, str(key), value);
        return value;
    }

    public static inline function setLength(target:Dynamic, value:Dynamic):Int {
        #if flash
        return untyped target.length = value;
        #else
        var length = toInt(value);
        if (target == null) {
            return length;
        }
        if (Std.isOfType(target, Array)) {
            var array:Array<Dynamic> = cast target;
            array.resize(length);
            return length;
        }
        #if (hl && (openfl || heaps))
        if (Std.isOfType(target, AS3Vector)) {
            return (cast target:AS3Vector).setLength(length);
        }
        if (Std.isOfType(target, openfl.utils.ByteArray.ByteArrayData)) {
            var bytes:openfl.utils.ByteArray = cast target;
            bytes.length = length;
            return length;
        }
        #end
        Reflect.setProperty(target, "length", length);
        return length;
        #end
    }

    public static function stringReplaceValue(text:Dynamic, pattern:Dynamic, by:Dynamic, extra:Dynamic = null):String {
        if (extra != null) {
            text = pattern;
            pattern = by;
            by = extra;
        }
        #if !flash
        if (extra == null && text != null && !Std.isOfType(text, String) && hasMember(text, "replace")) {
            return Reflect.callMethod(text, Reflect.field(text, "replace"), [pattern, by]);
        }
        #end
        var value = str(text);
        #if flash
        return untyped value.replace(pattern, by);
        #else
        if (pattern != null && hasMember(pattern, "replace")) {
            return Reflect.callMethod(pattern, Reflect.field(pattern, "replace"), [value, str(by)]);
        }
        var find = str(pattern);
        var at = value.indexOf(find);
        return at < 0 ? value : value.substr(0, at) + str(by) + value.substr(at + find.length);
        #end
    }

    public static inline function nativeTrace(value:Dynamic):Void {
        #if flash
        untyped __global__["trace"](value);
        #end
    }

    public static function stringSearch(text:Dynamic, pattern:Dynamic):Int {
        var value = str(text);
        #if flash
        return untyped value.search(pattern);
        #else
        if (pattern != null && hasMember(pattern, "exec")) {
            var match = Reflect.callMethod(pattern, Reflect.field(pattern, "exec"), [value]);
            if (match == null) {
                return -1;
            }
            return value.indexOf(str(index(match, 0)));
        }
        return value.indexOf(str(pattern));
        #end
    }

    #if (hl && (openfl || heaps))
    static var vectorElementSearch:Bool = Sys.getEnv("BH_PORT_VECTOR_INDEXOF") != "text";
    #end

    public static function valueIndexOfValue(value:Dynamic, needle:Dynamic, start:Dynamic = null):Int {
        #if flash
        return start == null ? untyped value.indexOf(needle) : untyped value.indexOf(needle, start);
        #else
        var offset = start == null ? 0 : toInt(start);
        if (Std.isOfType(value, Array)) {
            var array:Array<Dynamic> = cast value;
            for (i in offset...array.length) {
                if (array[i] == needle) {
                    return i;
                }
            }
            return -1;
        }
        #if (hl && (openfl || heaps))
        if (vectorElementSearch && Std.isOfType(value, port.runtime.AS3Vector)) {
            var vector:port.runtime.AS3Vector = cast value;
            return vector.indexOf(needle, offset);
        }
        #end
        return str(value).indexOf(str(needle), offset);
        #end
    }

    public static function stringSlice(text:Dynamic, start:Dynamic = 0, end:Dynamic = null):Dynamic {
        var first = toInt(start);
        if (Std.isOfType(text, Array)) {
            var array:Array<Dynamic> = cast text;
            return end == null ? array.slice(first) : array.slice(first, toInt(end));
        }
        var value = str(text);
        return end == null ? value.substr(first) : value.substring(first, toInt(end));
    }

    public static function stringSubstrValue(text:Dynamic, start:Dynamic = 0, len:Dynamic = null):String {
        var value = str(text);
        var first = toInt(start);
        return len == null ? value.substr(first) : value.substr(first, toInt(len));
    }

    public static inline function mathMin2Value(a:Dynamic, b:Dynamic):Dynamic {
        #if flash
        return Math.min(a, b);
        #else
        return mathMin(a, b);
        #end
    }

    public static function mathMin(a:Dynamic, b:Dynamic, ...rest:Dynamic):Dynamic {
        var value = Math.min(toFloat(a), toFloat(b));
        for (item in rest) {
            value = Math.min(value, toFloat(item));
        }
        return value;
    }

    public static inline function mathMax2Value(a:Dynamic, b:Dynamic):Dynamic {
        #if flash
        return Math.max(a, b);
        #else
        return mathMax(a, b);
        #end
    }

    public static function mathMax(a:Dynamic, b:Dynamic, ...rest:Dynamic):Dynamic {
        var value = Math.max(toFloat(a), toFloat(b));
        for (item in rest) {
            value = Math.max(value, toFloat(item));
        }
        return value;
    }

    public static function mathApply(max:Bool, values:Dynamic):Float {
        var value = max ? Math.NEGATIVE_INFINITY : Math.POSITIVE_INFINITY;
        if (values == null)
            return value;
        var list:Array<Dynamic> = values;
        for (item in list) {
            var n = toFloat(item);
            if (Math.isNaN(n))
                return Math.NaN;
            value = max ? Math.max(value, n) : Math.min(value, n);
        }
        return value;
    }

    #if (flash || openfl || heaps)
    public static function isByteArray(value:Dynamic):Bool {
        #if flash
        return Std.isOfType(value, flash.utils.ByteArray);
        #elseif heaps
        return Std.isOfType(value, flash.utils.ByteArray.ByteArrayData);
        #else
        return Std.isOfType(value, openfl.utils.ByteArray.ByteArrayData);
        #end
    }

    public static function asByteArray(value:Dynamic):flash.utils.ByteArray {
        return isByteArray(value) ? cast value : null;
    }
    #end

    public static function isUInt(value:Dynamic):Bool {
        if (value == null || !(Std.isOfType(value, Int) || Std.isOfType(value, Float)))
            return false;
        var n:Float = value;
        return n >= 0 && n <= 4294967295.0 && Math.ffloor(n) == n;
    }

    public static function newArray(...args:Dynamic):Array<Dynamic> {
        if (args.length == 1 && (Std.isOfType(args[0], Int) || Std.isOfType(args[0], Float))) {
            var list:Array<Dynamic> = [];
            var n = Std.int(toFloat(args[0]));
            if (n > 0)
                list[n - 1] = null;
            return list;
        }
        return [for (item in args) item];
    }

    public static function stringMatchValue(text:Dynamic, pattern:Dynamic):Array<Dynamic> {
        var value = str(text);
        #if flash
        return untyped value.match(pattern);
        #else
        if (Std.isOfType(pattern, RegExp)) {
            var re:RegExp = cast pattern;
            if (re.global) return re.matchAll(value);
            return re.exec(value);
        }
        if (pattern != null && hasMember(pattern, "exec")) {
            return Reflect.callMethod(pattern, Reflect.field(pattern, "exec"), [value]);
        }
        var found = value.indexOf(str(pattern));
        return found < 0 ? null : [str(pattern)];
        #end
    }

    public static function numberToFixed(value:Dynamic, digits:Int = 0):String {
        var n:Float = toFloat(value);
        var scale:Float = Math.pow(10, digits);
        var rounded:Float = Math.round(n * scale) / scale;
        var text = str(rounded);
        if (digits <= 0) {
            return text.split(".")[0];
        }
        if (text.indexOf(".") < 0) {
            text += ".";
        }
        while (text.length - text.indexOf(".") - 1 < digits) {
            text += "0";
        }
        return text;
    }

    public static function valueToStringValue(value:Dynamic, radix:Dynamic = null):String {
        if (radix != null) {
            var base = toInt(radix);
            var number = toInt(value);
            if (base == 16) {
                return StringTools.hex(number).toLowerCase();
            }
        }
        return str(value);
    }

    public static function errorName(value:Dynamic):String {
        if (value == null) {
            return "Error";
        }
        var cls = Type.getClass(value);
        var name = cls == null ? null : Type.getClassName(cls);
        return name == null ? "Error" : name.split(".").pop();
    }

    #if (flash || openfl || heaps)
    static var VM_ERROR = ~/^(TypeError|RangeError|ReferenceError|ArgumentError|SyntaxError): /;

    public static function catchError(value:Dynamic):flash.errors.Error {
        if (Std.isOfType(value, flash.errors.Error)) {
            return value;
        }
        if (Std.isOfType(value, String)) {
            var text:String = value;
            if (!VM_ERROR.match(text)) {
                throw value;
            }
            text = VM_ERROR.matchedRight() + thrownAt();
            return switch (VM_ERROR.matched(1)) {
                case "RangeError": new flash.errors.RangeError(text);
                case "ArgumentError": new flash.errors.ArgumentError(text);
                case "SyntaxError": syntaxError(text);
                default: new flash.errors.TypeError(text);
            }
        }
        var text = Std.isOfType(value, haxe.Exception) ? (cast value:haxe.Exception).message : Std.string(value);
        if (text == null || text == "" || text == "Null access") {
            text = "Error #1009: Cannot access a property or method of a null object reference.";
        }
        return new flash.errors.TypeError(text + thrownAt());
    }

    static function syntaxError(text:String):flash.errors.Error {
        var error = new flash.errors.Error(text, 1132);
        error.name = "SyntaxError";
        return error;
    }

    static function thrownAt():String {
        #if sys
        if (Sys.getEnv("BH_PORT_TRACE_ERRORS") == "1") {
            return " (thrown at" + haxe.CallStack.toString(haxe.CallStack.exceptionStack()) + ")";
        }
        #end
        return "";
    }
    #end

    public static function arrayFilter(value:Dynamic, fn:Dynamic):Dynamic {
        #if (hl && (openfl || heaps))
        if (Std.isOfType(value, AS3Vector)) {
            return (cast value:AS3Vector).filter(fn);
        }
        #end
        var array:Array<Dynamic> = cast value;
        var out:Array<Dynamic> = [];
        if (array == null) {
            return out;
        }
        for (i in 0...array.length) {
            var item = array[i];
            if (toBool(Reflect.callMethod(null, fn, [item, i, array]))) {
                out.push(item);
            }
        }
        return out;
    }

    public static function arrayMap(value:Dynamic, fn:Dynamic):Dynamic {
        #if (hl && (openfl || heaps))
        if (Std.isOfType(value, AS3Vector)) {
            return (cast value:AS3Vector).map(fn);
        }
        #end
        var array:Array<Dynamic> = cast value;
        var out:Array<Dynamic> = [];
        if (array == null) {
            return out;
        }
        for (i in 0...array.length) {
            out.push(Reflect.callMethod(null, fn, [array[i], i, array]));
        }
        return out;
    }

    public static function arrayConcatValue(value:Dynamic, other:Dynamic = null):Dynamic {
        #if (hl && (openfl || heaps))
        if (Std.isOfType(value, AS3Vector)) {
            return (cast value:AS3Vector).concat(other);
        }
        #end
        var array:Array<Dynamic> = cast value;
        if (array == null) {
            return [];
        }
        if (other == null) {
            return #if flash (array : Dynamic).concat() #else array.copy() #end;
        }
        if (Std.isOfType(other, Array)) {
            return array.concat(cast other);
        }
        var out:Array<Dynamic> = #if flash (array : Dynamic).concat() #else array.copy() #end;
        out.push(other);
        return out;
    }

    public static function arraySplice(value:Dynamic, start:Dynamic, deleteCount:Dynamic, ...items:Dynamic):Dynamic {
        #if (hl && (openfl || heaps))
        if (Std.isOfType(value, AS3Vector)) {
            return (cast value:AS3Vector).splice(toInt(start), toInt(deleteCount), items.toArray());
        }
        #end
        var array:Array<Dynamic> = cast value;
        if (array == null) {
            return [];
        }
        var removed = array.splice(toInt(start), toInt(deleteCount));
        var at = toInt(start);
        for (i in 0...items.length) {
            #if flash (array : Dynamic).splice(at + i, 0, items[i]) #else array.insert(at + i, items[i]) #end;
        }
        return removed;
    }

    public static function arrayPush(value:Dynamic, ...items:Dynamic):UInt {
        #if (hl && (openfl || heaps))
        if (Std.isOfType(value, AS3Vector)) {
            var vector:AS3Vector = cast value;
            for (item in items) vector.push(item);
            return vector.length;
        }
        #end
        var array:Array<Dynamic> = cast value;
        if (array == null) {
            return 0;
        }
        for (item in items) {
            array.push(item);
        }
        return array.length;
    }

    public static function arraySortValue(value:Dynamic, optionsOrCompare:Dynamic = null):Dynamic {
        #if (hl && (openfl || heaps))
        if (Std.isOfType(value, AS3Vector)) {
            return (cast value:AS3Vector).sort(optionsOrCompare);
        }
        #end
        var array:Array<Dynamic> = cast value;
        if (array == null) {
            return value;
        }
        if (Reflect.isFunction(optionsOrCompare)) {
            array.sort(function(a:Dynamic, b:Dynamic):Int {
                return toInt(Reflect.callMethod(null, optionsOrCompare, [a, b]));
            });
            return value;
        }
        var options = toInt(optionsOrCompare);
        array.sort(function(a:Dynamic, b:Dynamic):Int {
            var result = (options & toInt(ARRAY_NUMERIC)) != 0
                ? Reflect.compare(toFloat(a), toFloat(b))
                : (options & toInt(ARRAY_CASEINSENSITIVE)) != 0
                ? Reflect.compare(str(a).toLowerCase(), str(b).toLowerCase())
                : Reflect.compare(str(a), str(b));
            return (options & toInt(ARRAY_DESCENDING)) != 0 ? -result : result;
        });
        return value;
    }

    public static function arraySortOn(value:Dynamic, fields:Dynamic, options:Dynamic = null):Dynamic {
        var array:Array<Dynamic> = cast value;
        if (array == null) {
            return value;
        }
        var fieldList:Array<Dynamic> = Std.isOfType(fields, Array) ? cast fields : [fields];
        var optionList:Array<Dynamic> = Std.isOfType(options, Array) ? cast options : [options];
        array.sort(function(a:Dynamic, b:Dynamic):Int {
            for (i in 0...fieldList.length) {
                var field = str(fieldList[i]);
                var opts = i < optionList.length ? toInt(optionList[i]) : toInt(options);
                var av = Std.isOfType(a, Array) ? indexValue(a, fieldList[i]) : a == null ? null : getProp(a, field);
                var bv = Std.isOfType(b, Array) ? indexValue(b, fieldList[i]) : b == null ? null : getProp(b, field);
                var result = (opts & toInt(ARRAY_NUMERIC)) != 0
                    ? Reflect.compare(toFloat(av), toFloat(bv))
                    : (opts & toInt(ARRAY_CASEINSENSITIVE)) != 0
                    ? Reflect.compare(str(av).toLowerCase(), str(bv).toLowerCase())
                    : Reflect.compare(str(av), str(bv));
                if (result != 0) {
                    return (opts & toInt(ARRAY_DESCENDING)) != 0 ? -result : result;
                }
            }
            return 0;
        });
        return value;
    }

    public static function xmlConcat(a:Dynamic, b:Dynamic):Dynamic {
        #if flash
        return untyped a + b;
        #else
        inline function items(v:Dynamic):Array<XML> {
            return v == null ? [] : Std.isOfType(v, XML) ? [cast v] : (cast v:E4X.XMLListData).items;
        }
        return new E4X.XMLListData(items(a).concat(items(b)));
        #end
    }

    public static function xmlDescendants(target:Dynamic, key:Dynamic):Dynamic {
        if (target == null) {
            return new XMLList();
        }
        #if !flash
        if (Std.isOfType(target, XML)) {
            return (cast target:XML).descendants(key);
        }
        if (Std.isOfType(target, E4X.XMLListData)) {
            return (cast target:E4X.XMLListData).descendants(key);
        }
        #end
        return Reflect.callMethod(target, Reflect.field(target, "descendants"), [key]);
    }

    public static function xmlNode(name:String, attrs:Array<Dynamic> = null):Dynamic {
        var b = new StringBuf();
        b.add("<" + name);
        var i = 0;
        while (attrs != null && i + 1 < attrs.length) {
            var v = coerceString(attrs[i + 1]);
            v = StringTools.replace(StringTools.replace(StringTools.replace(v, "&", "&amp;"), "<", "&lt;"), "\"", "&quot;");
            b.add(" " + attrs[i] + "=\"" + v + "\"");
            i += 2;
        }
        b.add("/>");
        return new XML(b.toString());
    }

    public static function xmlAttribute(target:Dynamic, key:Dynamic):Dynamic {
        if (target == null) {
            return null;
        }
        #if !flash
        if (Std.isOfType(target, XML) || Std.isOfType(target, E4X.XMLListData)) {
            return target.attribute(str(key));
        }
        #end
        var attrs:Dynamic = Reflect.field(target, "__as3XmlAttrs");
        if (attrs != null) {
            return Reflect.field(attrs, str(key));
        }
        return Reflect.field(target, str(key));
    }

    public static function xmlChild(target:Dynamic, key:Dynamic):Dynamic {
        if (target == null) {
            return new XMLList();
        }
        #if !flash
        if (Std.isOfType(target, XML)) {
            return (cast target:XML).child(key);
        }
        if (Std.isOfType(target, E4X.XMLListData)) {
            return (cast target:E4X.XMLListData).child(key);
        }
        #end
        if (hasMember(target, "child")) {
            return Reflect.callMethod(target, Reflect.field(target, "child"), [key]);
        }
        return Reflect.field(target, str(key));
    }

    public static inline function removeChild(parent:Dynamic, child:Dynamic):Dynamic {
        #if flash
        return untyped parent.removeChild(child);
        #else
        if (parent == null || child == null) {
            return child;
        }
        if (hasMember(parent, "removeChild")) {
            return Reflect.callMethod(parent, Reflect.field(parent, "removeChild"), [child]);
        }
        return child;
        #end
    }

    public static function nativeWindow(stage:Dynamic):Dynamic {
        #if flash
        return untyped stage.nativeWindow;
        #else
        return {
            width: 0,
            height: 0,
            addEventListener: function(type:Dynamic, listener:Dynamic):Void {},
            maximize: function():Void {},
            restore: function():Void {},
            notifyUser: function(type:Dynamic):Void {}
        };
        #end
    }

    public static function setXmlAttribute(target:Dynamic, key:Dynamic, value:Dynamic):Dynamic {
        if (target == null) {
            return value;
        }
        #if !flash
        if (Std.isOfType(target, XML)) {
            (cast target:XML).setAttributeValue(str(key), value);
            return value;
        }
        #end
        var attrs:Dynamic = Reflect.field(target, "__as3XmlAttrs");
        if (attrs == null) {
            attrs = {};
            Reflect.setField(target, "__as3XmlAttrs", attrs);
        }
        Reflect.setField(attrs, str(key), value);
        return value;
    }

    public static function deleteFieldValue(target:Dynamic, key:Dynamic):Bool {
        if (target == null) {
            return true;
        }
        #if hl
        if (Std.isOfType(target, port.runtime.HashTable.KeyTable)) {
            (cast target:port.runtime.HashTable.KeyTable).delete(key);
            return true;
        }
        #end
        #if (hl && (openfl || heaps))
        if (Std.isOfType(target, flash.utils.Dictionary)) {
            return (cast target:flash.utils.Dictionary).remove(key);
        }
        #end
        return Reflect.deleteField(target, str(key));
    }

    public static function deleteXmlAttribute(target:Dynamic, key:Dynamic):Bool {
        if (target == null) {
            return true;
        }
        #if !flash
        if (Std.isOfType(target, XML)) {
            return (cast target:XML).deleteAttribute(str(key));
        }
        #end
        var attrs:Dynamic = Reflect.field(target, "__as3XmlAttrs");
        if (attrs != null) {
            return Reflect.deleteField(attrs, str(key));
        }
        return Reflect.deleteField(target, str(key));
    }

    static function isNamedType(value:Dynamic, name:String):Bool {
        return switch (name) {
            case "Array<Dynamic>", "Array":
                Std.isOfType(value, Array) || (Reflect.isObject(value) && Reflect.hasField(value, "length"));
            case "Class<Dynamic>", "Class":
                #if hl Std.isOfType(value, hl.BaseType.Class) #else Type.getClassName(value) != null #end;
            case "UInt":
                (Std.isOfType(value, Int) || Std.isOfType(value, Float)) && {
                    var number:Float = value;
                    number >= 0 && number <= 4294967295.0 && Math.ffloor(number) == number;
                };
            #if (hl && (openfl || heaps))
            case _ if (StringTools.startsWith(name, "Vector<") || name == "Vector"):
                Std.isOfType(value, AS3Vector);
            #end
            case _:
                false;
        };
    }
#end

#if macro
    static function atCall(e:Expr):Expr {
        if (!Context.defined("hl")) return e;
        var pos = Context.currentPos();
        function at(x:Expr):Expr {
            return x == null ? null : {expr: haxe.macro.ExprTools.map(x, at).expr, pos: pos};
        }
        return at(e);
    }
#end

    public static macro function toInt(value:Expr):Expr {
        return atCall(toInt__at(value));
    }

#if macro
    static function toInt__at(value:Expr):Expr {
        var read = nativeIntVectorRead(value);
        if (read != null) return intVectorRead(read, "getInt");
        var wrapped = Context.defined("hl") ? nativeIntegerSum(value) : null;
        if (wrapped != null) return wrapped;
        return Context.defined("flash")
            ? (hasBasicType(value, "Int") ? value : macro ((untyped __int__)(($value : Dynamic)) : Int))
            : switch (nativePrimitive(value)) {
                case "Int": value;
                case "UInt": macro (cast $value : Int);
                case "Float": macro port.runtime.As3.toInt32($value);
                default: macro port.runtime.As3.toIntValue($value);
            };
    }
#end

    public static macro function toUInt(value:Expr):Expr {
        return atCall(toUInt__at(value));
    }

#if macro
    static function toUInt__at(value:Expr):Expr {
        if (!Context.defined("flash") && expectsDynamic()) {
            var typed = toUIntTyped(value);
            return macro port.runtime.As3.uintDynamic($typed);
        }
        return toUIntTyped(value);
    }
#end

    #if macro
    static function expectsDynamic():Bool {
        var expected = try Context.getExpectedType() catch (_:Dynamic) null;
        if (expected == null) return false;
        return switch (Context.follow(expected)) {
            case TDynamic(_): true;
            case TAbstract(_.get() => abs, _): abs.pack.length == 0 && abs.name == "Any";
            default: false;
        };
    }

    static function toUIntTyped(value:Expr):Expr {
        var read = nativeIntVectorRead(value);
        if (read != null) {
            var unboxed = intVectorRead(read, "getInt");
            return macro (cast $unboxed : UInt);
        }
        var wrapped = Context.defined("hl") ? nativeIntegerSum(value) : null;
        if (wrapped != null) return macro (cast $wrapped : UInt);
        return Context.defined("flash")
            ? (hasBasicType(value, "UInt") ? value : macro (($value : Dynamic) : UInt))
            : switch (nativePrimitive(value)) {
                case "UInt": value;
                case "Int": macro (cast $value : UInt);
                case "Float": macro (cast port.runtime.As3.toInt32($value) : UInt);
                default: macro port.runtime.As3.toUIntValue($value);
            };
    }
    #end

    public static macro function mathMin2(a:Expr, b:Expr):Expr {
        return atCall(minMax2__at(true, a, b));
    }

    public static macro function mathMax2(a:Expr, b:Expr):Expr {
        return atCall(minMax2__at(false, a, b));
    }

#if macro
    static function minMax2__at(min:Bool, a:Expr, b:Expr):Expr {
        if (Context.defined("hl") && !Context.defined("as3_dynamic_float_conversions")) {
            var expected = Context.getExpectedType();
            if (expected == null || isBasicAbstract(expected, "Float")) {
                var l = nativeFloatOperand(a), r = nativeFloatOperand(b);
                if (l != null && r != null) return min ? macro Math.min($l, $r) : macro Math.max($l, $r);
            }
        }
        return min ? macro port.runtime.As3.mathMin2Value($a, $b) : macro port.runtime.As3.mathMax2Value($a, $b);
    }
#end

    public static macro function toFloat(value:Expr):Expr {
        return atCall(toFloat__at(value));
    }

#if macro
    static function toFloat__at(value:Expr):Expr {
        if (Context.defined("hl")) {
            var read = nativeIntVectorRead(value);
            if (read != null) return intVectorRead(read, "getNumber");
            var inner = unparen(value);
            switch (inner.expr) {
                case ECall({expr: EField(owner, "numeric")}, [{expr: EConst(CString(op, _))}, left, right]) if (isAs3Path(owner)):
                    var nativeOp = arithBinop(op);
                    var l = numericFloatOperand(left), r = numericFloatOperand(right);
                    if (nativeOp != null && l != null && r != null)
                        return {expr: EBinop(nativeOp, l, r), pos: Context.currentPos()};
                case ECall({expr: EField(owner, "neg")}, [operand]) if (isAs3Path(owner) && typeableOperand(operand, 0)
                    && negatesDynamic(operand)):
                    return macro port.runtime.As3.negDynamicToFloat($operand);
                default:
                    var typed = nativeFloatOperand(value);
                    if (typed != null) return typed;
                    if (!Context.defined("as3_dynamic_float_conversions") && typeableOperand(value, 0)
                        && floatArithmetic(value)) {
                        var type = try Context.typeof(value) catch (_:Dynamic) null;
                        if (type != null && isBasicAbstract(type, "Float")) return value;
                        if (type != null && isBasicAbstract(type, "Int")) return macro (($value : Int) : Float);
                    }
            }
        }
        return Context.defined("flash")
            ? (hasBasicType(value, "Float") ? value : macro (($value : Dynamic) : Float))
            : macro port.runtime.As3.toFloatValue($value);
    }
#end

    public static macro function toBool(value:Expr):Expr {
        return atCall(toBool__at(value));
    }

#if macro
    static function toBool__at(value:Expr):Expr {
        if (!Context.defined("flash")) {
            var typed = nativeTypedBool(value);
            return typed != null ? typed : macro port.runtime.As3.toBoolValue($value);
        }
        var logical = nativeBoolLogical(value);
        if (logical != null)
            return logical;
        return hasBasicType(value, "Bool") ? value : macro (($value : Dynamic) : Bool);
    }
#end

    public static macro function neg(value:Expr):Expr {
        var type = try Context.followWithAbstracts(Context.typeof(value)) catch (_:Dynamic) null;
        var isFloat = type != null && switch (type) {
            case TAbstract(t, _): t.get().name == "Float" && t.get().pack.length == 0;
            default: false;
        };
        var isDynamic = type != null && switch (type) {
            case TDynamic(_) | TMono(_): true;
            default: false;
        };
        return isFloat ? macro ($value * -1.0) : isDynamic ? macro ($value * -1) : macro -($value);
    }

    public static macro function floor(value:Expr):Expr {
        return roundingResult(macro Math.ffloor($value));
    }

    public static macro function ceil(value:Expr):Expr {
        return roundingResult(macro Math.fceil($value));
    }

    public static macro function round(value:Expr):Expr {
        return roundingResult(macro Math.fround($value));
    }

    public static macro function index(target:Expr, key:Expr):Expr {
        return atCall(index__at(target, key));
    }

#if macro
    static function index__at(target:Expr, key:Expr):Expr {
        if (Context.defined("flash") && typedArrayRead(target, key))
            return macro $target[$key];
        if (Context.defined("flash")) {
            var element = typedArrayElement(target);
            if (element != null && dynamicKey(key)) {
                var ct = Context.toComplexType(element);
                if (ct != null)
                    return macro (cast (untyped ($target)[$key]) : $ct);
            }
        }
        if (Context.defined("flash") && typedVectorIndex(target, key)) {
            if (!Context.defined("as3_dynamic_string_vector_reads") && isStringType(vectorElement(target)))
                return macro (cast (untyped ($target)[$key]) : String);
            return macro (untyped ($target)[$key] : Dynamic);
        }
        if (Context.defined("hl") && arrayIndex(target, key))
            return macro ({
                var __portArr = $target;
                var __portKey:Int = cast $key;
                __portArr == null || __portKey < 0 || __portKey >= __portArr.length ? null : (__portArr[__portKey] : Dynamic);
            } : Dynamic);
        if (Context.defined("hl") && nativeFloatVectorIndex(target, key))
            return macro ({
                var __portVec:port.runtime.AS3Vector = cast $target;
                var __portKey:Int = port.runtime.As3.toInt($key);
                __portVec == null ? port.runtime.As3.toFloatValue(null) : __portVec.getFloat(__portKey);
            } : Float);
        if (Context.defined("hl") && nativeVectorIndex(target, key)) {
            var element = nativeClassElement(target);
            if (element != null)
                return macro ({
                    var __portVec:port.runtime.AS3Vector = cast $target;
                    var __portKey:Int = port.runtime.As3.toInt($key);
                    __portVec == null ? null : (cast __portVec.get(__portKey) : $element);
                } : $element);
        }
        if (Context.defined("hl") && nativeVectorIndex(target, key))
            return macro ({
                var __portVec:port.runtime.AS3Vector = cast $target;
                var __portKey:Int = port.runtime.As3.toInt($key);
                __portVec == null ? null : __portVec.get(__portKey);
            } : Dynamic);
        if (Context.defined("hl") && intMapTable(target) && simpleOperand(key)
            && ["Int", "UInt"].indexOf(nativePrimitive(key)) >= 0)
            return macro ({
                var __portTable:Dynamic = $target;
                var __portKey:Int = cast $key;
                Std.isOfType(__portTable, port.runtime.HashTable.IntTable)
                    ? (cast __portTable : port.runtime.HashTable.IntTable).get(__portKey)
                    : port.runtime.As3.indexValue(__portTable, __portKey);
            } : Dynamic);
        if (Context.defined("hl") && byteArrayIndex(target, key))
            return macro ({
                var __portBytes:openfl.utils.ByteArray = $target;
                var __portKey:Int = cast $key;
                __portBytes == null || __portKey < 0 || __portKey >= __portBytes.length ? null : (__portBytes[__portKey] : Dynamic);
            } : Dynamic);
        return Context.defined("flash") && nativeIndexTarget(target, key)
            ? macro (untyped ($target)[$key] : Dynamic)
            : macro port.runtime.As3.indexValue($target, $key);
    }
#end

    public static macro function setIndex(target:Expr, key:Expr, value:Expr):Expr {
        return atCall(setIndex__at(target, key, value));
    }

    public static macro function vectorPush(target:Expr, value:Expr):Expr {
        return atCall(vectorPush__at(target, value));
    }

#if macro
    static function vectorPush__at(target:Expr, value:Expr):Expr {
        if (Context.defined("hl")) {
            var element = vectorElement(target);
            if (element != null && !Context.defined("as3_dynamic_float_vector_reads") && isFloatType(element)
                    && isNumberTyped(value))
                return macro (cast $target : port.runtime.AS3Vector).pushFloat($value);
            if (element != null && !Context.defined("as3_boxed_int_vectors")
                    && (isBasicAbstract(element, "Int") || isBasicAbstract(element, "UInt"))) {
                var valueType = try Context.follow(Context.typeof(value)) catch (_:Dynamic) null;
                if (valueType != null && (isBasicAbstract(valueType, "Int") || isBasicAbstract(valueType, "UInt")))
                    return macro (cast $target : port.runtime.AS3Vector).pushInt(cast $value);
            }
        }
        return macro $target.push($value);
    }

    static function setIndex__at(target:Expr, key:Expr, value:Expr):Expr {
        if (Context.defined("flash") && typedVectorIndex(target, key)) {
            var element = Context.toComplexType(vectorElement(target));
            return macro (cast $target : flash.Vector<$element>)[$key] = $value;
        }
        if (Context.defined("hl") && nativeFloatVectorIndex(target, key) && isNumberTyped(value))
            return macro ({
                var __portVec:port.runtime.AS3Vector = cast $target;
                var __portKey:Int = port.runtime.As3.toInt($key);
                var __portValue:Float = $value;
                __portVec == null ? __portValue : __portVec.setFloat(__portKey, __portValue);
            } : Float);
        if (Context.defined("hl") && nativeIntVectorIndex(target, key)) {
            var valueType = try Context.follow(Context.typeof(value)) catch (_:Dynamic) null;
            var unsigned = valueType != null && isBasicAbstract(valueType, "UInt");
            if (valueType != null && (unsigned || isBasicAbstract(valueType, "Int"))) {
                var stored = macro ({
                    var __portVec:port.runtime.AS3Vector = cast $target;
                    var __portKey:Int = port.runtime.As3.toInt($key);
                    var __portValue:Int = cast $value;
                    __portVec == null ? __portValue : __portVec.setInt(__portKey, __portValue);
                } : Int);
                return unsigned ? macro (cast $stored : UInt) : stored;
            }
        }
        if (Context.defined("hl") && nativeVectorIndex(target, key))
            return macro ({
                var __portVec:port.runtime.AS3Vector = cast $target;
                var __portKey:Int = port.runtime.As3.toInt($key);
                var __portValue:Dynamic = $value;
                __portVec == null ? __portValue : __portVec.set(__portKey, __portValue);
            } : Dynamic);
        if (Context.defined("hl") && byteArrayIndex(target, key))
            return macro ({
                var __portBytes:openfl.utils.ByteArray = $target;
                var __portKey:Int = cast $key;
                var __portValue:Dynamic = $value;
                if (__portBytes != null) __portBytes[__portKey] = port.runtime.As3.toInt(__portValue);
                __portValue;
            } : Dynamic);
        return Context.defined("flash") && nativeIndexTarget(target, key)
            ? macro (untyped ($target)[$key] = $value : Dynamic)
            : macro port.runtime.As3.setIndexValue($target, $key, $value);
    }
#end

    public static macro function valueToString(value:Expr, ?radix:Expr):Expr {
        var hasRadix = radix != null && switch (radix.expr) {
            case EConst(CIdent("null")): false;
            default: true;
        };
        if (!Context.defined("flash"))
            return hasRadix ? macro port.runtime.As3.valueToStringValue($value, $radix)
                : macro port.runtime.As3.valueToStringValue($value);
        var args = hasRadix ? [radix] : [];
        var typed = macro $value.toString($a{args});
        if (isStringType(try Context.typeof(typed) catch (_:Dynamic) null))
            return typed;
        return macro (cast (untyped ($value).toString($a{args})) : String);
    }

    public static macro function logicalOr(left:Expr, right:Expr):Expr {
        return atCall(logicalOr__at(left, right));
    }

#if macro
    static function logicalOr__at(left:Expr, right:Expr):Expr {
        if (Context.defined("flash"))
            return logicalOperator(OpBoolOr, left, right,
                macro { var __as3_l:Dynamic = $left; port.runtime.As3.toBool(__as3_l) ? __as3_l : ($right : Dynamic); });
        return logicalOperator(OpBoolOr, left, right,
            macro { var __as3_l:Dynamic = $left; var __as3_v:Dynamic = port.runtime.As3.toBool(__as3_l) ? __as3_l : ($right : Dynamic); __as3_v; });
    }
#end

    public static macro function logicalAnd(left:Expr, right:Expr):Expr {
        return atCall(logicalAnd__at(left, right));
    }

#if macro
    static function logicalAnd__at(left:Expr, right:Expr):Expr {
        if (Context.defined("flash"))
            return logicalOperator(OpBoolAnd, left, right,
                macro { var __as3_l:Dynamic = $left; port.runtime.As3.toBool(__as3_l) ? ($right : Dynamic) : __as3_l; });
        return logicalOperator(OpBoolAnd, left, right,
            macro { var __as3_l:Dynamic = $left; var __as3_v:Dynamic = port.runtime.As3.toBool(__as3_l) ? ($right : Dynamic) : __as3_l; __as3_v; });
    }
#end

    public static macro function compare(left:Expr, op:Expr, right:Expr):Expr {
        return atCall(compare__at(left, op, right));
    }

#if macro
    static function compare__at(left:Expr, op:Expr, right:Expr):Expr {
        var fallback = macro port.runtime.As3.compareValue($left, $op, $right);
        if (!Context.defined("flash") || Context.defined("as3_compare_helper")) {
            return fallback;
        }
        var binop = switch (op.expr) {
            case EConst(CString(">")): OpGt;
            case EConst(CString("<")): OpLt;
            case EConst(CString(">=")): OpGte;
            case EConst(CString("<=")): OpLte;
            case EConst(CString("==")): OpEq;
            case EConst(CString("!=")): OpNotEq;
            default: null;
        };
        if (binop == null) {
            return fallback;
        }
        var pos = Context.currentPos();
        var lt = scalarName(left);
        var rt = scalarName(right);
        if (lt == "Int" && rt == "UInt") {
            left = isNonNegativeIntLiteral(left) ? macro ($left : UInt) : macro ($left : Dynamic);
        } else if (lt == "UInt" && rt == "Int") {
            right = isNonNegativeIntLiteral(right) ? macro ($right : UInt) : macro ($right : Dynamic);
        }
        var dl = macro ($left : Dynamic);
        var dr = macro ($right : Dynamic);
        for (pair in [[left, right], [left, dr], [dl, right], [dl, dr]]) {
            var native = {expr: EParenthesis({expr: EBinop(binop, pair[0], pair[1]), pos: pos}), pos: pos};
            try {
                Context.typeExpr(native);
                return native;
            } catch (e:Dynamic) {}
        }
        return fallback;
    }
#end

    public static macro function arraySort(value:Expr, ?optionsOrCompare:Expr):Expr {
        var hasArg = optionsOrCompare != null && switch (optionsOrCompare.expr) {
            case EConst(CIdent("null")): false;
            default: true;
        };
        var fallback = hasArg
            ? macro port.runtime.As3.arraySortValue($value, $optionsOrCompare)
            : macro port.runtime.As3.arraySortValue($value);
        if (!Context.defined("flash") || !hasArg || Context.getExpectedType() != null) {
            return fallback;
        }
        var isArray = switch (try Context.follow(Context.typeof(value)) catch (_:Dynamic) null) {
            case TInst(_.get() => cls, _): cls.pack.length == 0 && cls.name == "Array";
            default: false;
        };
        if (!isArray && !Context.defined("as3_no_identity_conversions"))
            isArray = vectorElement(value) != null;
        var isFunction = switch (try Context.follow(Context.typeof(optionsOrCompare)) catch (_:Dynamic) null) {
            case TFun(_, _): true;
            default: false;
        };
        if (!isArray || !isFunction) {
            return fallback;
        }
        var native = macro $value.sort($optionsOrCompare);
        try {
            Context.typeExpr(native);
        } catch (_:Dynamic) {
            return fallback;
        }
        return native;
    }

    public static macro function stringReplace(text:Expr, rest:Array<Expr>):Expr {
        var pos = Context.currentPos();
        var fallback = {expr: ECall(macro port.runtime.As3.stringReplaceValue, [text].concat(rest)), pos: pos};
        if (!Context.defined("flash")) {
            return fallback;
        }
        var owner = switch (try Context.follow(Context.typeof(text)) catch (_:Dynamic) null) {
            case TInst(_.get() => cls, _): !(cls.pack.length == 0 && cls.name == "String");
            case TAnonymous(_.get() => anon): switch (anon.status) {
                    case AClassStatics(_): true;
                    default: false;
                };
            default: false;
        };
        if (!owner) {
            return fallback;
        }
        var native = {expr: ECall({expr: EField(text, "replace"), pos: pos}, rest), pos: pos};
        try {
            Context.typeExpr(native);
        } catch (_:Dynamic) {
            return fallback;
        }
        return native;
    }

    public static macro function stringMatch(text:Expr, pattern:Expr):Expr {
        var owner = switch (try Context.follow(Context.typeof(text)) catch (_:Dynamic) null) {
            case TInst(_.get() => cls, _): !(cls.pack.length == 0 && cls.name == "String");
            default: false;
        };
        return owner ? macro $text.match($pattern) : macro port.runtime.As3.stringMatchValue($text, $pattern);
    }

    public static macro function hasKey(target:Expr, key:Expr):Expr {
        return Context.defined("flash") && nativeInTarget(target)
            ? macro (untyped __in__($key, $target) : Bool)
            : macro port.runtime.As3.hasKeyValue($target, $key);
    }

    public static macro function deleteField(target:Expr, key:Expr):Expr {
        return Context.defined("flash") && nativeIndexTarget(target, key)
            ? macro (untyped __delete__($target, $key) : Bool)
            : macro port.runtime.As3.deleteFieldValue($target, $key);
    }

    public static macro function asType(value:Expr, type:Expr):Expr {
        return atCall(asType__at(value, type));
    }

#if macro
    static function asType__at(value:Expr, type:Expr):Expr {
        var isNull = switch (value.expr) { case EConst(CIdent("null")): true; default: false; };
        if (Context.defined("flash") && !isNull) {
            var cls = nativeAsClass(type);
            if (cls != null) {
                return macro (untyped __as__($value, $cls) : Dynamic);
            }
        }
        switch (type.expr) {
            case EConst(CIdent("UInt")) if (!Context.defined("flash")):
                return macro port.runtime.As3.asTypeValue($value, "UInt");
            default:
        }
        if (!Context.defined("flash")) {
            var typed = layerClassType(type);
            type = runtimeClassOf(type);
            if (typed != null) {
                return macro (port.runtime.As3.asTypeValue($value, $type) : $typed);
            }
            if (layerStringType(type))
                return macro (port.runtime.As3.asTypeValue($value, $type) : Dynamic);
        }
        return macro port.runtime.As3.asTypeValue($value, $type);
    }

    static function layerStringType(type:Expr):Bool {
        if (!Context.defined("bifrost")) return false;
        var local = Context.getLocalClass();
        if (local == null || local.get().pack[0] != "bh") return false;
        return switch (type.expr) {
            case EConst(CString(_)): true;
            default: false;
        };
    }

    static function layerClassType(type:Expr):Null<ComplexType> {
        if (!Context.defined("bifrost")) return null;
        var local = Context.getLocalClass();
        if (local == null || local.get().pack[0] != "bh") return null;
        switch (type.expr) {
            case EConst(CIdent(_)), EField(_, _):
            default:
                return null;
        }
        var path = haxe.macro.ExprTools.toString(type);
        var resolved = try Context.getType(path) catch (_:Dynamic) return null;
        return switch (resolved) {
            case TInst(c, params) if (params.length == 0 && !c.get().isInterface): Context.toComplexType(resolved);
            default: null;
        };
    }

    static function runtimeClassOf(type:Expr):Expr {
        switch (type.expr) {
            case EConst(CIdent(_)), EField(_, _):
            default:
                return type;
        }
        var path = haxe.macro.ExprTools.toString(type);
        var resolved = try Context.getType(path) catch (_:Dynamic) return type;
        while (true) {
            switch (resolved) {
                case TType(t, params):
                    resolved = Context.follow(resolved, true);
                    if (resolved == null) return type;
                    switch (resolved) { case TType(_, _): return type; default: }
                case TAbstract(a, _):
                    var under = a.get().type;
                    switch (Context.follow(under)) {
                        case TInst(c, _):
                            var cls = c.get();
                            var module = cls.module.split(".").pop();
                            var parts = cls.pack.concat(module == cls.name ? [cls.name] : [module, cls.name]);
                            return macro $p{parts};
                        default:
                            return type;
                    }
                default:
                    return type;
            }
        }
    }
#end

    public static macro function numeric(op:Expr, left:Expr, right:Expr):Expr {
        return atCall(numeric__at(op, left, right));
    }

#if macro
    static function numeric__at(op:Expr, left:Expr, right:Expr):Expr {
        var helper = macro port.runtime.As3.numericValue($op, $left, $right);
        var binop = switch (op.expr) {
            case EConst(CString(s, _)): arithBinop(s);
            default: null;
        };
        if (!Context.defined("flash")) {
            if (Context.defined("hl") && expectsFloat()) {
                var l = nativeFloatOperand(left), r = nativeFloatOperand(right);
                if (binop != null && l != null && r != null)
                    return {expr: EBinop(binop, l, r), pos: Context.currentPos()};
            }
            return helper;
        }
        if (binop == null)
            return helper;
        left = numericVectorRead(left);
        right = numericVectorRead(right);
        var leftKind = numericKind(left);
        var rightKind = numericKind(right);
        if (leftKind == null || rightKind == null) {
            return helper;
        }
        if (leftKind == "dynamic" || rightKind == "dynamic") {
            if (binop == OpAdd && Context.defined("as3_numeric_add_helper")) {
                return helper;
            }
            var native = {expr: EBinop(binop, macro ($left : Dynamic), macro ($right : Dynamic)), pos: Context.currentPos()};
            return macro (untyped $native : Dynamic);
        }
        var typed = {expr: EBinop(binop, left, right), pos: Context.currentPos()};
        var floatResult = binop == OpDiv || leftKind == "float" || rightKind == "float";
        return floatResult && expectsInteger() ? macro ($typed : Dynamic) : typed;
    }
#end

#if macro
    static function arithBinop(op:String):Null<Binop> {
        return switch (op) {
            case "+": OpAdd;
            case "-": OpSub;
            case "*": OpMult;
            case "/": OpDiv;
            case "%": OpMod;
            default: null;
        };
    }

    static function unparen(e:Expr):Expr {
        return switch (e.expr) {
            case EParenthesis(inner): unparen(inner);
            default: e;
        };
    }

    static function plainType(type:haxe.macro.Type):Null<haxe.macro.Type> {
        for (_ in 0...16) switch (type) {
            case TMono(ref):
                type = ref.get();
                if (type == null) return null;
            case TType(_, _) | TLazy(_):
                type = Context.follow(type, true);
            default: break;
        }
        return type;
    }

    static function nativeAsClass(type:Expr):Null<Expr> {
        switch (type.expr) {
            case EConst(CString("Array<Dynamic>", _)):
                return macro Array;
            case EConst(CString("Class<Dynamic>", _)):
                return macro (untyped __global__["Class"]);
            case EConst(CIdent(_)), EField(_, _):
            default:
                return null;
        }
        return switch (try Context.follow(Context.typeof(type)) catch (_:Dynamic) return null) {
            case TAnonymous(_.get() => {status: AClassStatics(_.get() => cls)}):
                switch (cls.kind) { case KAbstractImpl(_): null; default: type; }
            default: null;
        };
    }

    static function numericVectorRead(value:Expr):Expr {
        var inner = unparen(value);
        return switch (inner.expr) {
            case ECall({expr: EField(owner, "index")}, [target, key]) if (isAs3Path(owner) && typedVectorIndex(target, key)):
                var element = vectorElement(target);
                switch (Context.follow(element)) {
                    case TAbstract(_.get() => abs, []) if (abs.pack.length == 0 && (abs.name == "Int" || abs.name == "UInt" || abs.name == "Float")):
                        macro $target[$key];
                    default: value;
                }
            default: value;
        };
    }

    static function isAs3Path(owner:Expr):Bool {
        return switch (owner.expr) {
            case EConst(CIdent("As3")): true;
            case EField({expr: EField({expr: EConst(CIdent("port"))}, "runtime")}, "As3"): true;
            default: false;
        };
    }

    static function numericKind(value:Expr):Null<String> {
        return switch (try Context.follow(Context.typeof(value)) catch (_:Dynamic) return null) {
            case TAbstract(_.get() => abs, _) if (abs.pack.length == 0):
                switch (abs.name) {
                    case "Int", "UInt": "int";
                    case "Float": "float";
                    case "Dynamic", "Any": "dynamic";
                    default: null;
                }
            case TDynamic(_): "dynamic";
            default: null;
        };
    }

    static function isNonNegativeIntLiteral(value:Expr):Bool {
        return switch (value.expr) {
            case EParenthesis(e): isNonNegativeIntLiteral(e);
            case EConst(CInt(_)): true;
            default: false;
        };
    }

    static function scalarName(value:Expr):Null<String> {
        var t = try Context.follow(Context.typeof(value)) catch (e:Dynamic) null;
        while (t != null) switch (t) {
            case TAbstract(_.get() => abs, [inner]) if (abs.pack.length == 0 && abs.name == "Null"):
                t = Context.follow(inner);
            case TAbstract(_.get() => abs, []) if (abs.pack.length == 0 && (abs.name == "Int" || abs.name == "UInt")):
                return abs.name;
            default:
                return null;
        }
        return null;
    }

    static function nativeTypedBool(value:Expr):Null<Expr> {
        var type = try Context.typeof(value) catch (_:Dynamic) null;
        if (type == null)
            return null;
        var unwrapping = true;
        while (unwrapping) switch (type) {
            case TMono(_.get() => bound):
                if (bound == null) return null;
                type = bound;
            case TLazy(f):
                type = f();
            case TType(_.get() => t, params):
                type = haxe.macro.TypeTools.applyTypeParameters(t.type, t.params, params);
            default:
                unwrapping = false;
        }
        return switch (type) {
            case TAbstract(_.get() => t, []) if (t.pack.length == 0 && t.name == "Bool"):
                macro ($value : Bool);
            case TAbstract(_.get() => t, []) if (t.pack.length == 0 && (t.name == "Int" || t.name == "UInt")):
                macro ($value != 0);
            case TAbstract(_.get() => t, []) if (t.pack.length == 0 && t.name == "Float"):
                macro { var __asBool:Float = $value; __asBool != 0 && !Math.isNaN(__asBool); };
            case TInst(_.get() => c, _) if (c.pack.length == 0 && c.name == "String"):
                macro { var __asBool:String = $value; __asBool != null && __asBool.length > 0; };
            case TInst(_.get() => c, _):
                switch (c.kind) {
                    case KTypeParameter(_) | KExpr(_) | KAbstractImpl(_): null;
                    default: macro ($value != null);
                }
            case TFun(_, _) | TEnum(_, _):
                macro ($value != null);
            default: null;
        };
    }

    static function nativeBoolLogical(value:Expr):Null<Expr> {
        var inner = unparen(value);
        return switch (inner.expr) {
            case ECall(callee, [a, b]):
                var op = switch (haxe.macro.ExprTools.toString(callee)) {
                    case "port.runtime.As3.logicalOr": OpBoolOr;
                    case "port.runtime.As3.logicalAnd": OpBoolAnd;
                    default: null;
                };
                if (op == null) return null;
                var l = boolOperand(a);
                var r = l == null ? null : boolOperand(b);
                r == null ? null : {expr: EBinop(op, l, r), pos: inner.pos};
            default: null;
        };
    }

    static function boolOperand(value:Expr):Null<Expr> {
        var logical = nativeBoolLogical(value);
        return logical != null ? logical : isBool(value) ? value : null;
    }

    static function logicalOperator(op:Binop, left:Expr, right:Expr, helper:Expr):Expr {
        var leftNative = nativeBoolLogical(left);
        if (leftNative != null)
            left = leftNative;
        var rightNative = nativeBoolLogical(right);
        if (rightNative != null)
            right = rightNative;
        var leftBool = leftNative != null || isBool(left);
        var rightBool = rightNative != null || isBool(right);
        var expected = Context.getExpectedType();
        var wantsBool = expected != null && switch (Context.follow(expected)) {
            case TAbstract(_.get() => abs, _): abs.pack.length == 0 && abs.name == "Bool";
            default: false;
        };
        if (!(leftBool && rightBool) && !wantsBool) {
            return helper;
        }
        var l = leftBool ? left : macro port.runtime.As3.toBool($left);
        var r = rightBool ? right : macro port.runtime.As3.toBool($right);
        var native = {expr: EBinop(op, l, r), pos: Context.currentPos()};
        return wantsBool ? native : macro ($native : Dynamic);
    }

    static function hasBasicType(value:Expr, name:String):Bool {
        if (Context.defined("as3_no_identity_conversions")) {
            return false;
        }
        var inner = value;
        while (true) switch (inner.expr) {
            case EParenthesis(e): inner = e;
            case EUnop(OpIncrement | OpDecrement, _, _): return false;
            case ETernary(_, a, b) | EIf(_, a, b) if (b != null): return hasBasicType(a, name) && hasBasicType(b, name);
            case EBinop(OpAdd | OpSub | OpMult | OpDiv | OpMod, a, b) if (name == "Int" || name == "UInt"):
                if (!isIntegral(a) || !isIntegral(b)) return false;
                break;
            case EField(receiver, "index"):
                var enumReceiver = switch (try Context.follow(Context.typeof(receiver)) catch (_:Dynamic) null) {
                    case TEnum(_, _): true;
                    case TInst(_.get() => cls, _): Lambda.exists(cls.statics.get(), f -> f.name == "__isenum");
                    default: false;
                };
                if (enumReceiver) return false;
                break;
            default: break;
        }
        var type = try Context.typeof(value) catch (_:Dynamic) return false;
        while (true) switch (type) {
            case TAbstract(_.get() => abs, _) if (abs.pack.length == 0 && abs.name == "Null"): return false;
            case TType(_, _) | TLazy(_): type = Context.follow(type, true);
            case TMono(_.get() => t) if (t != null): type = t;
            default: break;
        }
        return switch (Context.follow(type)) {
            case TAbstract(_.get() => abs, _): abs.pack.length == 0 && abs.name == name;
            default: false;
        };
    }

    static function roundingResult(number:Expr):Expr {
        var expected = try Context.getExpectedType() catch (_:Dynamic) null;
        var wantsFloat = expected != null && switch (Context.followWithAbstracts(expected)) {
            case TAbstract(t, _): t.get().name == "Float" && t.get().pack.length == 0;
            default: false;
        };
        return wantsFloat ? number : macro port.runtime.As3.toInt32($number);
    }

    static function nativePrimitive(value:Expr):Null<String> {
        var t = try Context.typeof(value) catch (_:Dynamic) return null;
        while (true) {
            switch (t) {
                case TAbstract(_.get() => abs, _) if (abs.pack.length == 0 && abs.name == "Null"):
                    return null;
                case TAbstract(_.get() => abs, []):
                    return abs.pack.length == 0 && ["Int", "UInt", "Float"].indexOf(abs.name) >= 0 ? abs.name : null;
                case TType(_, _) | TLazy(_):
                    t = Context.follow(t, true);
                case TMono(_.get() => m) if (m != null):
                    t = m;
                default:
                    return null;
            }
        }
    }

    static function isPlainPrimitive(value:Expr):Bool {
        var t = try Context.typeof(value) catch (_:Dynamic) return false;
        while (true) {
            switch (t) {
                case TAbstract(_.get() => abs, _) if (abs.pack.length == 0 && abs.name == "Null"):
                    return false;
                case TAbstract(_.get() => abs, []):
                    return abs.pack.length == 0 && ["Int", "UInt", "Float", "Bool"].indexOf(abs.name) >= 0;
                case TType(_, _) | TLazy(_):
                    t = Context.follow(t, true);
                default:
                    return false;
            }
        }
    }

    static function isString(value:Expr):Bool {
        if (Context.defined("as3_no_identity_conversions")) {
            return false;
        }
        return switch (try Context.follow(Context.typeof(value)) catch (_:Dynamic) return false) {
            case TInst(_.get() => cls, _): cls.pack.length == 0 && cls.name == "String";
            case TDynamic(_): true;
            default: false;
        };
    }

    static function nativeIndexOfTarget(value:Expr):Bool {
        if (Context.defined("as3_no_identity_conversions"))
            return false;
        if (vectorElement(value) != null)
            return true;
        return switch (try Context.follow(Context.typeof(value)) catch (_:Dynamic) return false) {
            case TInst(_.get() => cls, _): cls.pack.length == 0 && (cls.name == "String" || cls.name == "Array");
            default: false;
        };
    }

    static function isNullExpr(value:Expr):Bool {
        return switch (value.expr) { case EConst(CIdent("null")): true; default: false; };
    }

    static function isStringTyped(value:Expr):Bool {
        if (Context.defined("as3_no_identity_conversions"))
            return false;
        return switch (try Context.follow(Context.typeof(value)) catch (_:Dynamic) return false) {
            case TInst(_.get() => cls, _): cls.pack.length == 0 && cls.name == "String";
            default: false;
        };
    }

    static function typedArray(value:Expr):Bool {
        return switch (try Context.follow(Context.typeof(value)) catch (_:Dynamic) return false) {
            case TInst(_.get() => cls, [_]): cls.pack.length == 0 && cls.name == "Array";
            default: false;
        };
    }

    static function isIntegral(value:Expr):Bool {
        return switch (try Context.follow(Context.typeof(value)) catch (_:Dynamic) return false) {
            case TAbstract(_.get() => abs, _): abs.pack.length == 0 && (abs.name == "Int" || abs.name == "UInt");
            default: false;
        };
    }

    static function isBool(value:Expr):Bool {
        return switch (try Context.follow(Context.typeof(value)) catch (_:Dynamic) return false) {
            case TAbstract(_.get() => abs, _): abs.pack.length == 0 && abs.name == "Bool";
            default: false;
        };
    }

    static function expectsFloat():Bool {
        var expected = Context.getExpectedType();
        if (expected == null) {
            return false;
        }
        return switch (Context.follow(expected)) {
            case TAbstract(_.get() => abs, _): abs.pack.length == 0 && abs.name == "Float";
            default: false;
        };
    }

    static function nativeIntegerSum(value:Expr):Null<Expr> {
        var code = nativeCharCode(value);
        if (code != null) return code;
        var inner = unparen(value);
        switch (inner.expr) {
            case ECall({expr: EField(owner, "numeric")}, [{expr: EConst(CString(op, _))}, left, right])
                if (isAs3Path(owner) && (op == "+" || op == "-")):
                var l = nativeIntOperand(left), r = nativeIntOperand(right);
                if (l == null || r == null) return null;
                return {expr: EBinop(op == "+" ? OpAdd : OpSub, l, r), pos: Context.currentPos()};
            default:
                return null;
        }
    }

    static function nativeCharCode(value:Expr):Null<Expr> {
        var inner = unparen(value);
        switch (inner.expr) {
            case ECall({expr: EField(receiver, "charCodeAt")}, [index]):
                var isString = switch (try Context.follow(Context.typeof(receiver)) catch (_:Dynamic) null) {
                    case TInst(_.get() => cls, _): cls.pack.length == 0 && cls.name == "String";
                    default: false;
                };
                if (!isString) return null;
                var key = switch (nativePrimitive(index)) {
                    case "Int": index;
                    case "UInt": macro (cast $index : Int);
                    default: return null;
                };
                return macro port.runtime.As3.codeAtInt($receiver, $key);
            default:
                return null;
        }
    }

    static function nativeIntOperand(value:Expr):Null<Expr> {
        switch (value.expr) {
            case ECall({expr: EField(owner, "index")}, [target, key]) if (isAs3Path(owner) && nativeVectorIndex(target, key)):
                var integer = switch (Context.follow(vectorElement(target))) {
                    case TAbstract(_.get() => abs, []) if (abs.pack.length == 0 && (abs.name == "Int" || abs.name == "UInt")): true;
                    default: false;
                };
                if (!integer) return null;
                return macro ({
                    var __portVec:port.runtime.AS3Vector = cast $target;
                    var __portKey:Int = port.runtime.As3.toInt($key);
                    __portVec == null ? 0 : (__portVec.get(__portKey) : Int);
                } : Int);
            case ECall({expr: EField(owner, "toInt")}, [_]) if (isAs3Path(owner)):
                return macro ($value : Int);
            case ECall({expr: EField(owner, "toUInt")}, [_]) if (isAs3Path(owner)):
                return macro (cast $value : Int);
            default:
        }
        if (!simpleOperand(value)) return null;
        var type = plainType(try Context.typeof(value) catch (_:Dynamic) return null);
        if (type == null) return null;
        return switch (type) {
            case TAbstract(_.get() => abs, _) if (abs.pack.length == 0 && abs.name == "Int"): macro ($value : Int);
            case TAbstract(_.get() => abs, _) if (abs.pack.length == 0 && abs.name == "UInt"): macro (cast $value : Int);
            default: null;
        };
    }

    static function nativeFloatOperand(value:Expr):Null<Expr> {
        if (!simpleOperand(value)) return null;
        var type = plainType(try Context.typeof(value) catch (_:Dynamic) return null);
        if (type == null) return null;
        return switch (type) {
            case TAbstract(_.get() => abs, _) if (abs.pack.length == 0 && abs.name == "Float"): value;
            case TAbstract(_.get() => abs, _) if (abs.pack.length == 0 && abs.name == "Int"): macro (($value : Int) : Float);
            case TAbstract(_.get() => abs, _) if (abs.pack.length == 0 && abs.name == "UInt"):
                macro port.runtime.As3.uintToFloat($value);
            default: null;
        };
    }

    static function typeableOperand(value:Expr, depth:Int):Bool {
        if (depth > 6) return false;
        return switch (value.expr) {
            case EConst(CIdent(_) | CInt(_) | CFloat(_)): true;
            case EField(owner, _): simpleOperand(owner);
            case EParenthesis(e): typeableOperand(e, depth + 1);
            case EBinop(OpAdd | OpSub | OpMult | OpDiv, a, b): typeableOperand(a, depth + 1) && typeableOperand(b, depth + 1);
            case EUnop(OpNeg, false, e): typeableOperand(e, depth + 1);
            case ETernary(c, a, b): plainCondition(c, depth + 1) && typeableOperand(a, depth + 1)
                && typeableOperand(b, depth + 1);
            case ECall({expr: EField(owner, _)}, args) if (isAs3Path(owner)):
                Lambda.foreach(args, simpleOperand);
            case ECall({expr: EField(owner, _)}, args):
                simpleOperand(owner) && Lambda.foreach(args, plainArgument);
            default: false;
        };
    }

    static function plainCondition(value:Expr, depth:Int):Bool {
        if (depth > 6) return false;
        return switch (value.expr) {
            case EParenthesis(e): plainCondition(e, depth + 1);
            case EBinop(OpEq | OpNotEq | OpLt | OpLte | OpGt | OpGte, a, b): plainArithmetic(a) && plainArithmetic(b);
            case EBinop(OpBoolAnd | OpBoolOr, a, b): plainCondition(a, depth + 1) && plainCondition(b, depth + 1);
            case EUnop(OpNot, false, e): plainCondition(e, depth + 1);
            default: false;
        };
    }

    static function plainArgument(value:Expr):Bool {
        return switch (value.expr) {
            case EUnop(OpNot, false, e): simpleOperand(e);
            case ECall({expr: EField(owner, "index")}, [target, key]) if (isAs3Path(owner)):
                simpleOperand(target) && simpleOperand(key);
            default: plainArithmetic(value);
        };
    }

    static function plainArithmetic(value:Expr):Bool {
        return switch (value.expr) {
            case EParenthesis(e): plainArithmetic(e);
            case EBinop(OpAdd | OpSub | OpMult | OpDiv, a, b): plainArithmetic(a) && plainArithmetic(b);
            case EUnop(OpNeg, false, e): plainArithmetic(e);
            default: simpleOperand(value);
        };
    }

    static function intMapTable(target:Expr):Bool {
        return switch (target.expr) {
            case EParenthesis(e): intMapTable(e);
            case EField({expr: ECall({expr: EField(owner, "intMap")}, [_])}, "h"): isAs3Path(owner);
            default: false;
        };
    }

    static function negatesDynamic(value:Expr):Bool {
        var type = try Context.followWithAbstracts(Context.typeof(value)) catch (_:Dynamic) null;
        return type != null && switch (type) {
            case TDynamic(_) | TMono(_): true;
            default: false;
        };
    }

    static function numericFloatOperand(value:Expr):Null<Expr> {
        var simple = nativeFloatOperand(value);
        if (simple != null || Context.defined("as3_dynamic_float_conversions")) return simple;
        if (!typeableOperand(value, 0) || !floatArithmetic(value)) return null;
        var type = try Context.typeof(value) catch (_:Dynamic) return null;
        if (isBasicAbstract(type, "Float")) return value;
        if (isBasicAbstract(type, "Int")) return macro (($value : Int) : Float);
        return null;
    }

    static function floatArithmetic(value:Expr):Bool {
        return switch (value.expr) {
            case EParenthesis(e): floatArithmetic(e);
            case EBinop(_, a, b): typedFloat(value) && floatArithmetic(a) && floatArithmetic(b);
            case EUnop(_, _, e): typedFloat(value) && floatArithmetic(e);
            case ETernary(_, a, b): floatArithmetic(a) && floatArithmetic(b);
            default: true;
        };
    }

    static function typedFloat(value:Expr):Bool {
        var type = try Context.typeof(value) catch (_:Dynamic) return false;
        return isBasicAbstract(type, "Float");
    }

    static function isBasicAbstract(type:haxe.macro.Type, name:String):Bool {
        type = plainType(type);
        if (type == null) return false;
        return switch (type) {
            case TAbstract(_.get() => abs, _): abs.pack.length == 0 && abs.name == name;
            default: false;
        };
    }

    static function simpleOperand(value:Expr):Bool {
        return switch (value.expr) {
            case EConst(CIdent(_) | CInt(_) | CFloat(_)): true;
            case EField(owner, _): simpleOperand(owner);
            case EParenthesis(e): simpleOperand(e);
            default: false;
        };
    }

    static function expectsInteger():Bool {
        var expected = Context.getExpectedType();
        if (expected == null) {
            return false;
        }
        return switch (Context.follow(expected)) {
            case TAbstract(_.get() => abs, _): abs.pack.length == 0 && (abs.name == "Int" || abs.name == "UInt");
            default: false;
        };
    }

    static function nativeIndexTarget(target:Expr, key:Expr):Bool {
        switch (try Context.follow(Context.typeof(key)) catch (_:Dynamic) return false) {
            case TMono(_): return false;
            default:
        }
        return nativeInTarget(target);
    }

    static function typedArrayElement(target:Expr):Null<haxe.macro.Type> {
        return switch (try Context.follow(Context.typeof(target)) catch (_:Dynamic) return null) {
            case TInst(_.get() => cls, [element]) if (cls.pack.length == 0 && cls.name == "Array"):
                switch (Context.follow(element)) {
                    case TInst(_.get() => ec, _) if (!(ec.pack.length == 0 && ec.name == "String")
                        && !ec.kind.match(KTypeParameter(_))):
                        element;
                    default: null;
                }
            default: null;
        };
    }

    static function dynamicKey(key:Expr):Bool {
        return switch (try Context.follow(Context.typeof(key)) catch (_:Dynamic) return false) {
            case TDynamic(_): true;
            case TAbstract(_.get() => abs, _): abs.pack.length == 0 && (abs.name == "Dynamic" || abs.name == "Any");
            default: false;
        };
    }

    static function arrayIndex(target:Expr, key:Expr):Bool {
        switch (try Context.follow(Context.typeof(target)) catch (_:Dynamic) return false) {
            case TInst(_.get() => cls, [_]) if (cls.pack.length == 0 && cls.name == "Array"):
            default:
                return false;
        }
        return switch (try Context.follow(Context.typeof(key)) catch (_:Dynamic) return false) {
            case TAbstract(_.get() => abs, _): abs.pack.length == 0 && (abs.name == "Int" || abs.name == "UInt");
            default: false;
        };
    }

    static function byteArrayIndex(target:Expr, key:Expr):Bool {
        inline function bytesPack(pack:Array<String>):Bool {
            var p = pack.join("/");
            return p == "openfl/utils" || p == "flash/utils";
        }
        switch (try Context.follow(Context.typeof(target)) catch (_:Dynamic) return false) {
            case TAbstract(_.get() => abs, _) if (abs.name == "ByteArray" && bytesPack(abs.pack)):
            case TInst(_.get() => cls, _) if (cls.name == "ByteArrayData" && bytesPack(cls.pack)):
            default:
                return false;
        }
        return switch (try Context.follow(Context.typeof(key)) catch (_:Dynamic) return false) {
            case TAbstract(_.get() => abs, _): abs.pack.length == 0 && (abs.name == "Int" || abs.name == "UInt");
            default: false;
        };
    }

    static function typedArrayRead(target:Expr, key:Expr):Bool {
        switch (try Context.follow(Context.typeof(target)) catch (_:Dynamic) return false) {
            case TInst(_.get() => cls, [element]) if (cls.pack.length == 0 && cls.name == "Array"):
                switch (Context.follow(element)) {
                    case TDynamic(_), TMono(_): return false;
                    case TAbstract(_.get() => abs, _) if (abs.pack.length == 0 && (abs.name == "Dynamic" || abs.name == "Any")):
                        return false;
                    default:
                }
            default:
                return false;
        }
        return switch (try Context.follow(Context.typeof(key)) catch (_:Dynamic) return false) {
            case TAbstract(_.get() => abs, _): abs.pack.length == 0 && (abs.name == "Int" || abs.name == "UInt");
            default: false;
        };
    }

    static function nativeVectorIndex(target:Expr, key:Expr):Bool {
        switch (try Context.follow(Context.typeof(target)) catch (_:Dynamic) return false) {
            case TAbstract(_.get() => abs, [_]) if (abs.pack.length == 0 && abs.name == "Vector"):
            default:
                return false;
        }
        return switch (try Context.follow(Context.typeof(key)) catch (_:Dynamic) return false) {
            case TAbstract(_.get() => abs, _): abs.pack.length == 0 && (abs.name == "Int" || abs.name == "UInt");
            default: false;
        };
    }

    static function typedVectorIndex(target:Expr, key:Expr):Bool {
        if (vectorElement(target) == null)
            return false;
        return switch (try Context.follow(Context.typeof(key)) catch (_:Dynamic) return false) {
            case TAbstract(_.get() => abs, _): abs.pack.length == 0 && abs.name == "Int";
            default: false;
        };
    }

    static function dynamicCheckInner(e:Expr):Null<Expr> {
        return switch (e.expr) {
            case EParenthesis(inner): dynamicCheckInner(inner);
            case ECheckType(inner, TPath({pack: [], name: "Dynamic", params: [] | null, sub: null})): inner;
            default: null;
        };
    }

    static function nativeFloatVectorIndex(target:Expr, key:Expr):Bool {
        if (Context.defined("as3_dynamic_float_vector_reads") || !nativeVectorIndex(target, key))
            return false;
        return isFloatType(vectorElement(target));
    }

    static function nativeIntVectorIndex(target:Expr, key:Expr):Bool {
        if (Context.defined("as3_boxed_int_vectors") || !nativeVectorIndex(target, key))
            return false;
        var element = vectorElement(target);
        return element != null && (isBasicAbstract(element, "Int") || isBasicAbstract(element, "UInt"));
    }

    static function nativeIntVectorRead(value:Expr):Null<Array<Expr>> {
        if (!Context.defined("hl"))
            return null;
        var inner = unparen(value);
        return switch (inner.expr) {
            case ECall({expr: EField(owner, "index")}, [target, key]) if (isAs3Path(owner) && nativeIntVectorIndex(target, key)):
                [target, key];
            default: null;
        };
    }

    static function intVectorRead(read:Array<Expr>, getter:String):Expr {
        var target = read[0], key = read[1];
        return getter == "getInt"
            ? macro ({
                var __portVec:port.runtime.AS3Vector = cast $target;
                var __portKey:Int = port.runtime.As3.toInt($key);
                __portVec == null ? 0 : __portVec.getInt(__portKey);
            } : Int)
            : macro ({
                var __portVec:port.runtime.AS3Vector = cast $target;
                var __portKey:Int = port.runtime.As3.toInt($key);
                __portVec == null ? 0.0 : __portVec.getNumber(__portKey);
            } : Float);
    }

    static function isFloatType(type:Null<haxe.macro.Type>):Bool {
        return type != null && switch (Context.follow(type)) {
            case TAbstract(_.get() => abs, []): abs.pack.length == 0 && abs.name == "Float";
            default: false;
        };
    }

    static function isNumberTyped(value:Expr):Bool {
        return switch (try Context.follow(Context.typeof(value)) catch (_:Dynamic) return false) {
            case TAbstract(_.get() => abs, []): abs.pack.length == 0
                && (abs.name == "Float" || abs.name == "Int" || abs.name == "UInt");
            default: false;
        };
    }

    static function isStringType(type:Null<haxe.macro.Type>):Bool {
        return type != null && switch (Context.follow(type)) {
            case TInst(_.get() => cls, _): cls.pack.length == 0 && cls.name == "String";
            default: false;
        };
    }

    static function vectorElement(target:Expr):Null<haxe.macro.Type> {
        return switch (try Context.follow(Context.typeof(target)) catch (_:Dynamic) return null) {
            case TAbstract(_.get() => abs, [element]) if (abs.pack.length == 0 && abs.name == "Vector"): element;
            case TInst(_.get() => cls, [element]) if (cls.pack.join(".") == "flash" && cls.name == "Vector"): element;
            default: null;
        };
    }

    static function nativeClassElement(target:Expr):Null<ComplexType> {
        var element = vectorElement(target);
        if (element == null) return null;
        return switch (Context.follow(element)) {
            case TInst(_.get() => cls, _) if (!(cls.pack.length == 0 && cls.name == "String") && cls.kind.match(KNormal)):
                Context.toComplexType(element);
            default: null;
        };
    }

    static function nativeInTarget(target:Expr):Bool {
        var type = try Context.follow(Context.typeof(target)) catch (_:Dynamic) return false;
        return switch (type) {
            case TInst(_.get() => cls, _):
                cls.isExtern || cls.pack.length == 0 && (cls.name == "Array" || cls.name == "String");
            case TDynamic(_), TAnonymous(_):
                true;
            case TAbstract(_.get() => abs, _):
                abs.pack.length == 0 && (abs.name == "Dynamic" || abs.name == "Any");
            default:
                false;
        };
    }
#end

    public static macro function vectorLength(value:Expr):Expr {
        var literal = switch (value.expr) { case EConst(CInt(_)): true; default: false; };
        return numericKind(value) == "int" && !literal ? value : macro port.runtime.As3.toUInt($value);
    }

    public static macro function valueIndexOf(value:Expr, needle:Expr, ?start:Expr):Expr {
        var hasStart = start != null && !switch (start.expr) { case EConst(CIdent("null")): true; default: false; };
        if (nativeIndexOfTarget(value))
            return hasStart ? macro $value.indexOf($needle, $start) : macro $value.indexOf($needle);
        return hasStart ? macro port.runtime.As3.valueIndexOfValue($value, $needle, $start)
            : macro port.runtime.As3.valueIndexOfValue($value, $needle);
    }

    public static macro function stringSubstr(text:Expr, ?start:Expr, ?len:Expr):Expr {
        var hasStart = start != null && !isNullExpr(start);
        var hasLen = len != null && !isNullExpr(len);
        if (hasStart && isStringTyped(text) && isIntegral(start) && (!hasLen || isIntegral(len)))
            return hasLen ? macro $text.substr($start, $len) : macro $text.substr($start);
        if (!hasStart)
            return macro port.runtime.As3.stringSubstrValue($text);
        return hasLen ? macro port.runtime.As3.stringSubstrValue($text, $start, $len)
            : macro port.runtime.As3.stringSubstrValue($text, $start);
    }

    public static macro function arrayConcat(value:Expr, ?other:Expr):Expr {
        var hasOther = other != null && !isNullExpr(other);
        var element = Context.defined("as3_no_identity_conversions") ? null : vectorElement(value);
        if (element == null && !Context.defined("as3_no_identity_conversions")) {
            var inner = dynamicCheckInner(value);
            if (inner != null && (element = vectorElement(inner)) != null)
                value = inner;
        }
        if (element != null) {
            var e = Context.toComplexType(element);
            if (!Context.defined("flash"))
                return hasOther ? macro @:pos(Context.currentPos()) port.runtime.As3.boxed((cast $value : flash.Vector<$e>).concat($other))
                    : macro @:pos(Context.currentPos()) port.runtime.As3.boxed((cast $value : flash.Vector<$e>).concat());
            return hasOther ? macro ((cast $value : flash.Vector<$e>).concat($other) : Dynamic)
                : macro ((cast $value : flash.Vector<$e>).concat() : Dynamic);
        }
        if (hasOther && typedArray(value) && typedArray(other)
                && (try Context.unify(Context.typeof(other), Context.typeof(value)) catch (_:Dynamic) false))
            return macro ($value.concat($other) : Dynamic);
        var ownConcat = switch (try Context.follow(Context.typeof(value)) catch (_:Dynamic) null) {
            case TInst(_.get() => cls, _): !(cls.pack.length == 0 && cls.name == "Array");
            default: false;
        };
        if (ownConcat)
            return hasOther ? macro $value.concat($other) : macro $value.concat();
        return hasOther ? macro port.runtime.As3.arrayConcatValue($value, $other)
            : macro port.runtime.As3.arrayConcatValue($value);
    }

    public static macro function stringArg(value:Expr):Expr {
        return atCall(stringArg__at(value));
    }

#if macro
    static function stringArg__at(value:Expr):Expr {
        if (isString(value))
            return value;
        if (Context.defined("flash"))
            return isPlainPrimitive(value) ? macro (($value : Dynamic) : String) : macro Std.string($value);
        return macro port.runtime.As3.str($value);
    }
#end

    public static macro function stringParam(value:Expr):Expr {
        return atCall(stringParam__at(value));
    }

#if macro
    static function stringParam__at(value:Expr):Expr {
        if (isStringTyped(value))
            return value;
        var untypedValue = switch (try Context.follow(Context.typeof(value)) catch (_:Dynamic) null) {
            case TDynamic(_): true;
            case TMono(_): true;
            default: false;
        };
        if (Context.defined("flash"))
            return untypedValue || isPlainPrimitive(value) ? macro (($value : Dynamic) : String) : value;
        if (untypedValue)
            return macro port.runtime.As3.coerceStringValue($value);
        return isPlainPrimitive(value) ? macro Std.string($value) : value;
    }
#end

    public static macro function uintConst(value:Expr):Expr {
        if (!Context.defined("flash"))
            return macro ($value : UInt);
        var digits = switch (value.expr) {
            case EConst(CInt(v)): v;
            case _: Context.error("uintConst takes an integer literal", value.pos);
        }
        var name = "UIntConst_" + digits;
        try {
            Context.getType("port.runtime." + name);
        } catch (_:Dynamic) {
            var cls = macro class $name {
                public static inline var V:UInt = $value;
            };
            cls.pack = ["port", "runtime"];
            Context.defineType(cls);
        }
        return macro port.runtime.$name.V;
    }

    public static macro function coerceString(value:Expr):Expr {
        return atCall(coerceString__at(value));
    }

#if macro
    static function coerceString__at(value:Expr):Expr {
        return Context.defined("flash")
            ? macro (($value : Dynamic) : String)
            : macro port.runtime.As3.coerceStringValue($value);
    }
#end
}

#if !macro
typedef As3Reg = RegExp;

typedef As3Object = #if flash flash.utils.Object #else Dynamic #end;
#end
