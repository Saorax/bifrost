package port.runtime.services;

import haxe.io.Bytes;

class SwzArchive {
    var data:Bytes;
    var offset:Int = 0;
    var rand:SwzRandom;

    public function new(data:Bytes, key:Int) {
        this.data = data;
        if (data.length < 8) throw "SWZ archive too short";
        var checksum = readU32(0);
        var seed = readU32(4);
        offset = 8;
        rand = new SwzRandom(seed ^ key);
        var expected = 0x2DF4A1CD;
        var rounds = unsignedMod(key, 31) + 5;
        for (_ in 0...rounds) expected ^= rand.next();
        if (expected != checksum) throw "SWZ key checksum mismatch";
    }

    public function hasNext():Bool {
        return offset < data.length;
    }

    public function next():String {
        var compressedSize = readU32(offset) ^ rand.next();
        var decompressedSize = readU32(offset + 4) ^ rand.next();
        offset += 12;
        var buffer = data.sub(offset, compressedSize);
        offset += compressedSize;
        rand.next();
        for (i in 0...buffer.length) {
            var word = rand.next() >>> (i % 16);
            buffer.set(i, buffer.get(i) ^ (word & 0xFF));
        }
        var text = haxe.zip.Uncompress.run(buffer, decompressedSize > 0 ? decompressedSize : null);
        return text.getString(0, text.length, UTF8);
    }

    inline function readU32(at:Int):Int {
        return (data.get(at) << 24) | (data.get(at + 1) << 16) | (data.get(at + 2) << 8) | data.get(at + 3);
    }

    static function unsignedMod(value:Int, by:Int):Int {
        var high = (value >>> 16) % by;
        return ((high * 65536) % by + (value & 0xFFFF)) % by;
    }

    static var key:Int = 0;
    static var current:Null<SwzArchive> = null;

    public static function extension():Extensions.ExtensionImpl {
        return new Extensions.ExtensionImpl()
            .define("RawData_Init", (args) -> {
                key = Std.int(args[0]);
                return true;
            })
            .define("RawData_SetData", (args) -> {
                try {
                    current = new SwzArchive(toBytes(args[0]), key);
                    return true;
                } catch (_:Dynamic) {
                    current = null;
                    return false;
                }
            })
            .define("RawData_GetData", (_) -> {
                #if sys
                if (traceTimes) traceFile();
                #end
                if (current == null || !current.hasNext()) {
                    current = null;
                    return null;
                }
                var text = current.next();
                #if sys
                if (traceTimes) lastText = text;
                #end
                return text;
            });
    }

    #if sys
    static var traceTimes:Bool = Sys.getEnv("BH_PORT_TRACE_SWZ") == "1";
    static var lastText:String = null;
    static var lastStamp:Float = 0;
    static var lastAllocs:Float = 0;

    static function traceFile():Void {
        var now = haxe.Timer.stamp();
        #if hl
        var gc = hl.Gc.stats();
        var allocs = gc.allocationCount;
        #else
        var allocs = 0.0;
        #end
        if (lastText != null) {
            var head = lastText.substr(0, 60).split("\n").join(" ").split("\r").join("");
            Sys.println('swz: ${Std.int((now - lastStamp) * 1000)} ms, ${Std.int((allocs - lastAllocs) / 1000)}k allocations for ${lastText.length} chars: $head');
        }
        lastText = null;
        lastStamp = now;
        lastAllocs = allocs;
    }
    #end

    static function toBytes(value:Dynamic):Bytes {
        #if openfl
        var array:openfl.utils.ByteArray = value;
        var bytes:Bytes = (cast array : openfl.utils.ByteArray.ByteArrayData);
        return bytes.sub(0, array.length);
        #else
        return (value : Bytes);
        #end
    }
}

class SwzRandom {
    var index:Int = 0;
    var state:Array<Int>;

    public function new(seed:Int) {
        state = [for (_ in 0...16) 0];
        state[0] = seed;
        for (i in 1...16) {
            var prev = state[i - 1];
            state[i] = 0x6C078965 * (prev ^ (prev >>> 30)) + i;
        }
    }

    public function next():Int {
        var idx = index;
        var a = state[idx];
        var b = state[(idx + 13) % 16];
        var c = a ^ (a << 16) ^ b ^ (b << 15);
        b = state[(idx + 9) % 16];
        b ^= b >>> 11;
        state[idx] = b ^ c;
        a = state[idx];
        var d = a ^ ((a << 5) & 0xDA442D24);
        index = (idx + 15) % 16;
        a = state[index];
        state[index] = a ^ (a << 2) ^ (b << 28) ^ c ^ (c << 18) ^ d;
        return state[index];
    }
}
