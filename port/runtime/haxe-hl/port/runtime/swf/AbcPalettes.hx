package port.runtime.swf;

import haxe.io.Bytes;

class AbcPalettes {
    public static var classesRead(default, null):Int = 0;
    public static var unreadBodies(default, null):Int = 0;

    var bytes:Bytes;
    var pos:Int;
    var ints:Array<Int> = [0];
    var uints:Array<Float> = [0];
    var doubles:Array<Float> = [Math.NaN];
    var strings:Array<String> = [""];
    var namespaces:Array<Int> = [0];
    var multinames:Array<{ns:Int, name:Int}> = [{ns: 0, name: 0}];

    var frameScripts:FastStringMap<Int> = new FastStringMap();
    var bodies:FastIntMap<Int> = new FastIntMap();

    function new(bytes:Bytes, start:Int) {
        this.bytes = bytes;
        this.pos = start;
    }

    public static function read(bytes:Bytes, start:Int, into:FastStringMap<Array<Dynamic>>):Void {
        var abc = new AbcPalettes(bytes, start);
        abc.parse();
        for (name in abc.frameScripts.keys()) {
            var body = abc.bodies.get(abc.frameScripts.get(name));
            if (body == null) continue;
            var palette = abc.palette(body);
            if (palette != null) {
                into.set(name, palette);
                classesRead++;
            }
        }
    }

    inline function u8():Int return bytes.get(pos++);

    function u30():Int {
        var result = 0, shift = 0;
        while (true) {
            var b = bytes.get(pos++);
            result |= (b & 0x7f) << shift;
            if (b & 0x80 == 0 || shift >= 28) break;
            shift += 7;
        }
        return result;
    }

    function qualified(index:Int):String {
        if (index <= 0 || index >= multinames.length) return null;
        var m = multinames[index];
        var name = strings[m.name];
        var ns = m.ns > 0 && m.ns < namespaces.length ? strings[namespaces[m.ns]] : "";
        return ns == null || ns == "" ? name : ns + "." + name;
    }

    function plainName(index:Int):String {
        return index > 0 && index < multinames.length ? strings[multinames[index].name] : null;
    }

    function parse() {
        pos += 4;
        var n = u30();
        for (i in 1...n) {
            var v = u30();
            ints.push(v | 0);
        }
        n = u30();
        for (i in 1...n) {
            var v = u30();
            uints.push(v < 0 ? v + 4294967296.0 : v);
        }
        n = u30();
        for (i in 1...n) {
            doubles.push(bytes.getDouble(pos));
            pos += 8;
        }
        n = u30();
        for (i in 1...n) {
            var len = u30();
            strings.push(bytes.getString(pos, len));
            pos += len;
        }
        n = u30();
        for (i in 1...n) {
            u8();
            namespaces.push(u30());
        }
        n = u30();
        for (i in 1...n) {
            var count = u30();
            for (j in 0...count) u30();
        }
        n = u30();
        for (i in 1...n) {
            switch (u8()) {
                case 0x07 | 0x0D:
                    var ns = u30();
                    multinames.push({ns: ns, name: u30()});
                case 0x0F | 0x10:
                    multinames.push({ns: 0, name: u30()});
                case 0x11 | 0x12:
                    multinames.push({ns: 0, name: 0});
                case 0x09 | 0x0E:
                    var name = u30();
                    u30();
                    multinames.push({ns: 0, name: name});
                case 0x1B | 0x1C:
                    u30();
                    multinames.push({ns: 0, name: 0});
                case 0x1D:
                    var base = u30();
                    var count = u30();
                    for (j in 0...count) u30();
                    multinames.push({ns: 0, name: base < multinames.length ? multinames[base].name : 0});
                case kind:
                    throw "unknown ABC multiname kind " + kind;
            }
        }
        n = u30();
        for (i in 0...n) {
            var params = u30();
            u30();
            for (j in 0...params) u30();
            u30();
            var flags = u8();
            if (flags & 0x08 != 0) {
                var options = u30();
                for (j in 0...options) {
                    u30();
                    u8();
                }
            }
            if (flags & 0x80 != 0) for (j in 0...params) u30();
        }
        n = u30();
        for (i in 0...n) {
            u30();
            var items = u30();
            for (j in 0...items * 2) u30();
        }
        var classCount = u30();
        for (i in 0...classCount) {
            var name = qualified(u30());
            u30();
            var flags = u8();
            if (flags & 0x08 != 0) u30();
            var interfaces = u30();
            for (j in 0...interfaces) u30();
            u30();
            traits(name);
        }
        for (i in 0...classCount) {
            u30();
            traits(null);
        }
        n = u30();
        for (i in 0...n) {
            u30();
            traits(null);
        }
        n = u30();
        for (i in 0...n) {
            var method = u30();
            for (j in 0...4) u30();
            var length = u30();
            bodies.set(method, pos);
            pos += length;
            var exceptions = u30();
            for (j in 0...exceptions * 5) u30();
            traits(null);
        }
    }

    function traits(owner:String) {
        var n = u30();
        for (i in 0...n) {
            var name = u30();
            var kind = u8();
            switch (kind & 0x0f) {
                case 0 | 6:
                    u30();
                    u30();
                    if (u30() != 0) u8();
                case 1 | 2 | 3:
                    u30();
                    var method = u30();
                    if (owner != null && (kind & 0x0f) == 1 && plainName(name) == "frame1") frameScripts.set(owner, method);
                case 4 | 5:
                    u30();
                    u30();
                default:
                    throw "unknown ABC trait kind " + kind;
            }
            if (kind & 0x40 != 0) {
                var count = u30();
                for (j in 0...count) u30();
            }
        }
    }

    function palette(body:Int):Array<Dynamic> {
        pos = body;
        var length = u30();
        var end = pos + length;
        var stack:Array<Dynamic> = [];
        while (pos < end) {
            var op = u8();
            switch (op) {
                case 0xD0 | 0xD1 | 0xD2 | 0xD3:
                    stack.push(null);
                case 0x30:
                    stack.pop();
                case 0x24:
                    var v = u8();
                    stack.push(v >= 0x80 ? v - 0x100 : v);
                case 0x25:
                    var v = u30();
                    stack.push(v >= 0x8000 && v < 0x10000 ? v - 0x10000 : v);
                case 0x2D:
                    stack.push(ints[u30()]);
                case 0x2E:
                    var v = uints[u30()];
                    stack.push(v <= 0x7fffffff ? Std.int(v) : v);
                case 0x2F:
                    stack.push(doubles[u30()]);
                case 0x56:
                    var count = u30();
                    if (count > stack.length) break;
                    stack.push(stack.splice(stack.length - count, count));
                case 0x68 | 0x61:
                    var name = plainName(u30());
                    var value = stack.pop();
                    stack.pop();
                    if (name == "a" && Std.isOfType(value, Array)) return value;
                case 0x47:
                    break;
                case 0x5D | 0x5E | 0x60:
                    u30();
                    stack.push(null);
                case 0x66:
                    u30();
                    stack.pop();
                    stack.push(null);
                case 0x46 | 0x4F:
                    u30();
                    var count = u30();
                    if (count + 1 > stack.length) break;
                    stack.splice(stack.length - count - 1, count + 1);
                    if (op == 0x46) stack.push(null);
                case 0x20 | 0x21 | 0x26 | 0x27 | 0x28:
                    stack.push(op == 0x26 ? true : op == 0x27 ? false : op == 0x28 ? Math.NaN : null);
                case 0x2C:
                    stack.push(strings[u30()]);
                case 0xF0 | 0xF1 | 0xEF:
                    if (op == 0xEF) {
                        u8();
                        u30();
                        u8();
                        u30();
                    } else {
                        u30();
                    }
                case 0x80:
                    u30();
                case 0x82 | 0x85 | 0x73 | 0x74 | 0x75 | 0x88 | 0x89:
                case 0x29:
                    stack.pop();
                case 0x2A:
                    stack.push(stack[stack.length - 1]);
                case 0x02 | 0x09:
                default:
                    break;
            }
        }
        unreadBodies++;
        return null;
    }
}
