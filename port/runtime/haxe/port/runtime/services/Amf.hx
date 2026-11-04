package port.runtime.services;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;

class Amf {
    public static function readSol(bytes:Bytes):{name:String, data:Dynamic} {
        var r = new Amf3Reader(bytes);
        if (r.u8() != 0x00 || r.u8() != 0xBF) throw new ServiceError(2004, "not a shared object file");
        r.u32();
        if (r.raw(4) != "TCSO") throw new ServiceError(2004, "not a shared object file");
        r.skip(6);
        var name = r.raw(r.u16());
        var version = r.u32();
        if (version != 3) throw new ServiceError(2004, "AMF" + version + " shared object files are not supported");
        var data:Dynamic = {};
        while (!r.done()) {
            var key = r.string();
            var value = r.value();
            Reflect.setField(data, key, value);
            if (!r.done()) r.u8();
        }
        return {name: name, data: data};
    }

    public static function writeSol(name:String, data:Dynamic):Bytes {
        var body = new Amf3Writer();
        var nameBytes = Bytes.ofString(name);
        body.raw(Bytes.ofString("TCSO"));
        for (b in [0x00, 0x04, 0x00, 0x00, 0x00, 0x00]) body.u8(b);
        body.u16(nameBytes.length);
        body.raw(nameBytes);
        body.u32(3);
        if (data != null) {
            for (key in Reflect.fields(data)) {
                body.string(key);
                body.value(Reflect.field(data, key));
                body.u8(0);
            }
        }
        var content = body.bytes();
        var out = new Amf3Writer();
        out.u8(0x00);
        out.u8(0xBF);
        out.u32(content.length);
        out.raw(content);
        return out.bytes();
    }
}

class Amf3Reader {
    var b:Bytes;
    var p:Int = 0;
    var strings:Array<String> = [];
    var objects:Array<Dynamic> = [];
    var traits:Array<{className:String, open:Bool, sealed:Array<String>}> = [];

    public function new(bytes:Bytes) {
        b = bytes;
    }

    public function done():Bool return p >= b.length;

    public function u8():Int {
        if (p >= b.length) throw new ServiceError(2030, "End of file was encountered.");
        return b.get(p++);
    }

    public function u16():Int return (u8() << 8) | u8();

    public function u32():Int return (u8() << 24) | (u8() << 16) | (u8() << 8) | u8();

    public function skip(n:Int):Void {
        for (i in 0...n) u8();
    }

    public function raw(n:Int):String {
        if (p + n > b.length) throw new ServiceError(2030, "End of file was encountered.");
        var s = b.getString(p, n);
        p += n;
        return s;
    }

    function double():Float {
        var t = Bytes.alloc(8);
        for (i in 0...8) t.set(7 - i, u8());
        return t.getDouble(0);
    }

    function u29():Int {
        var v = 0;
        for (i in 0...3) {
            var c = u8();
            if (c & 0x80 == 0) return (v << 7) | c;
            v = (v << 7) | (c & 0x7F);
        }
        return (v << 8) | u8();
    }

    public function string():String {
        var h = u29();
        if (h & 1 == 0) return strings[h >> 1];
        var len = h >> 1;
        if (len == 0) return "";
        var s = raw(len);
        strings.push(s);
        return s;
    }

    public function value():Dynamic {
        var marker = u8();
        switch (marker) {
            case 0x00, 0x01:
                return null;
            case 0x02:
                return false;
            case 0x03:
                return true;
            case 0x04:
                var v = u29();
                return (v & 0x10000000) != 0 ? v - 0x20000000 : v;
            case 0x05:
                return double();
            case 0x06:
                return string();
            case 0x07, 0x0B:
                var h = u29();
                if (h & 1 == 0) return objects[h >> 1];
                var text = raw(h >> 1);
                objects.push(text);
                return text;
            case 0x08:
                var h = u29();
                if (h & 1 == 0) return objects[h >> 1];
                var d = Date.fromTime(double());
                objects.push(d);
                return d;
            case 0x09:
                return array();
            case 0x0A:
                return object();
            case 0x0C:
                var h = u29();
                if (h & 1 == 0) return objects[h >> 1];
                var len = h >> 1;
                if (p + len > b.length) throw new ServiceError(2030, "End of file was encountered.");
                var bytes = b.sub(p, len);
                p += len;
                objects.push(bytes);
                return bytes;
            case 0x0D, 0x0E, 0x0F, 0x10:
                var h = u29();
                if (h & 1 == 0) return objects[h >> 1];
                var len = h >> 1;
                u8();
                var out:Array<Dynamic> = [];
                objects.push(out);
                if (marker == 0x10) string();
                for (i in 0...len) {
                    out.push(switch (marker) {
                        case 0x0D: u32() | 0;
                        case 0x0E: {
                                var v = u32();
                                v < 0 ? v + 4294967296.0 : (v : Float);
                            }
                        case 0x0F: double();
                        default: value();
                    });
                }
                return out;
            case 0x11:
                var h = u29();
                if (h & 1 == 0) return objects[h >> 1];
                var len = h >> 1;
                u8();
                var out:Dynamic = {};
                objects.push(out);
                for (i in 0...len) {
                    var key = value();
                    Reflect.setField(out, Std.string(key), value());
                }
                return out;
            default:
                throw new ServiceError(2004, "unknown AMF3 marker " + marker);
        }
    }

    function array():Dynamic {
        var h = u29();
        if (h & 1 == 0) return objects[h >> 1];
        var count = h >> 1;
        var key = string();
        if (key == "") {
            var out:Array<Dynamic> = [];
            objects.push(out);
            for (i in 0...count) out.push(value());
            return out;
        }
        var slot = objects.length;
        objects.push(null);
        var keys:Array<String> = [];
        var values:Array<Dynamic> = [];
        while (key != "") {
            keys.push(key);
            values.push(value());
            key = string();
        }
        var dense:Array<Dynamic> = [for (i in 0...count) value()];
        var indexes = [for (k in keys) INDEX.match(k) && k.length < 7 ? Std.parseInt(k) : -1];
        if (indexes.indexOf(-1) < 0) {
            var list:Array<Dynamic> = dense;
            for (i in 0...keys.length) list[indexes[i]] = values[i];
            objects[slot] = list;
            return list;
        }
        var out:Dynamic = {};
        objects[slot] = out;
        for (i in 0...keys.length) Reflect.setField(out, keys[i], values[i]);
        for (i in 0...count) Reflect.setField(out, Std.string(i), dense[i]);
        return out;
    }

    static final INDEX = ~/^(0|[1-9][0-9]*)$/;

    function object():Dynamic {
        var h = u29();
        if (h & 1 == 0) return objects[h >> 1];
        var t;
        if (h & 2 == 0) {
            t = traits[h >> 2];
        } else {
            if (h & 4 != 0) throw new ServiceError(2004, "externalizable AMF3 objects are not supported");
            var className = string();
            var sealed = [for (i in 0...(h >> 4)) string()];
            t = {className: className, open: h & 8 != 0, sealed: sealed};
            traits.push(t);
        }
        var out:Dynamic = {};
        objects.push(out);
        for (name in t.sealed) Reflect.setField(out, name, value());
        if (t.open) {
            var key = string();
            while (key != "") {
                Reflect.setField(out, key, value());
                key = string();
            }
        }
        return out;
    }
}

class Amf3Writer {
    var buf = new BytesBuffer();
    var strings:Map<String, Int> = new Map();
    var stringCount:Int = 0;

    public function new() {}

    public function bytes():Bytes return buf.getBytes();

    public function u8(v:Int):Void buf.addByte(v & 0xFF);

    public function u16(v:Int):Void {
        u8(v >> 8);
        u8(v);
    }

    public function u32(v:Int):Void {
        u8(v >>> 24);
        u8(v >> 16);
        u8(v >> 8);
        u8(v);
    }

    public function raw(b:Bytes):Void buf.add(b);

    function u29(v:Int):Void {
        v &= 0x1FFFFFFF;
        if (v < 0x80) {
            u8(v);
        } else if (v < 0x4000) {
            u8((v >> 7) | 0x80);
            u8(v & 0x7F);
        } else if (v < 0x200000) {
            u8((v >> 14) | 0x80);
            u8((v >> 7) | 0x80);
            u8(v & 0x7F);
        } else {
            u8((v >> 22) | 0x80);
            u8((v >> 15) | 0x80);
            u8((v >> 8) | 0x80);
            u8(v);
        }
    }

    function double(v:Float):Void {
        var t = Bytes.alloc(8);
        t.setDouble(0, v);
        for (i in 0...8) u8(t.get(7 - i));
    }

    public function string(s:String):Void {
        if (s != "") {
            var ref = strings.get(s);
            if (ref != null) {
                u29(ref << 1);
                return;
            }
            strings.set(s, stringCount++);
        }
        var b = Bytes.ofString(s);
        u29((b.length << 1) | 1);
        raw(b);
    }

    public function value(v:Dynamic):Void {
        if (v == null) {
            u8(0x01);
        } else if (Std.isOfType(v, Bool)) {
            u8(v ? 0x03 : 0x02);
        } else if (Std.isOfType(v, Int) || Std.isOfType(v, Float)) {
            var f:Float = v;
            if (Math.isFinite(f) && Math.ffloor(f) == f && f >= -268435456 && f <= 268435455 && !(f == 0 && 1 / f < 0)) {
                u8(0x04);
                u29(Std.int(f));
            } else {
                u8(0x05);
                double(f);
            }
        } else if (Std.isOfType(v, String)) {
            u8(0x06);
            string(v);
        } else if (Std.isOfType(v, Date)) {
            u8(0x08);
            u29(1);
            double((v : Date).getTime());
        } else if (Std.isOfType(v, Bytes)) {
            var bytes:Bytes = v;
            u8(0x0C);
            u29((bytes.length << 1) | 1);
            raw(bytes);
        } else if (Std.isOfType(v, Array)) {
            var a:Array<Dynamic> = v;
            u8(0x09);
            if (a.length > 0 && a[a.length - 1] != null && a.indexOf(null) >= 0) {
                u29(1);
                for (i in 0...a.length) {
                    if (a[i] == null) continue;
                    string(Std.string(i));
                    value(a[i]);
                }
                u29(1);
            } else {
                u29((a.length << 1) | 1);
                u29(1);
                for (item in a) value(item);
            }
        } else {
            u8(0x0A);
            u29(0x0B);
            u29(1);
            for (key in Reflect.fields(v)) {
                if (key == "") continue;
                string(key);
                value(Reflect.field(v, key));
            }
            u29(1);
        }
    }
}
