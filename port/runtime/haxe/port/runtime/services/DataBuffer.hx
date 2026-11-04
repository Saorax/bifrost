package port.runtime.services;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;

class DataBuffer {
    public var position(get, set):Int;
    public var bytesAvailable(get, never):Int;
    public var length(get, never):Int;
    public var bigEndian:Bool = true;

    var data:Bytes;
    var len:Int = 0;
    var pos:Int = 0;

    public function new() {
        data = Bytes.alloc(256);
    }

    function get_position():Int return pos;

    function set_position(v:Int):Int {
        pos = v < 0 ? 0 : v;
        return pos;
    }

    function get_bytesAvailable():Int return len > pos ? len - pos : 0;

    function get_length():Int return len;

    function need(n:Int):Void {
        if (pos + n > len) throw new ServiceError(2030, "End of file was encountered.");
    }

    function room(n:Int):Void {
        if (pos + n > data.length) {
            var size = data.length * 2;
            while (size < pos + n) size *= 2;
            var grown = Bytes.alloc(size);
            grown.blit(0, data, 0, len);
            data = grown;
        }
    }

    function wrote(n:Int):Void {
        pos += n;
        if (pos > len) len = pos;
    }

    public function compact():Void {
        if (pos == 0) return;
        var keep = len > pos ? len - pos : 0;
        if (keep > 0) data.blit(0, data, pos, keep);
        len = keep;
        pos = 0;
    }

    public function append(b:Bytes, offset:Int, length:Int):Void {
        var at = pos;
        pos = len;
        room(length);
        data.blit(pos, b, offset, length);
        len += length;
        pos = at;
    }

    public function contents():Bytes {
        return data.sub(0, len);
    }

    public function clear():Void {
        len = 0;
        pos = 0;
    }

    public function readByte():Int {
        need(1);
        var v = data.get(pos++);
        return v > 127 ? v - 256 : v;
    }

    public function readUnsignedByte():Int {
        need(1);
        return data.get(pos++);
    }

    public function readBoolean():Bool return readUnsignedByte() != 0;

    public function readShort():Int {
        var v = readUnsignedShort();
        return v > 32767 ? v - 65536 : v;
    }

    public function readUnsignedShort():Int {
        need(2);
        var a = data.get(pos), b = data.get(pos + 1);
        pos += 2;
        return bigEndian ? (a << 8) | b : (b << 8) | a;
    }

    public function readInt():Int {
        need(4);
        var v = bigEndian ? (data.get(pos) << 24) | (data.get(pos + 1) << 16) | (data.get(pos + 2) << 8) | data.get(pos + 3)
            : data.getInt32(pos);
        pos += 4;
        return v;
    }

    public function readUnsignedInt():Float {
        var v = readInt();
        return v < 0 ? v + 4294967296.0 : v;
    }

    public function readDouble():Float {
        need(8);
        var v = bigEndian ? swapped(8).getDouble(0) : data.getDouble(pos);
        pos += 8;
        return v;
    }

    public function readFloat():Float {
        need(4);
        var v = bigEndian ? swapped(4).getFloat(0) : data.getFloat(pos);
        pos += 4;
        return v;
    }

    function swapped(n:Int):Bytes {
        var b = Bytes.alloc(n);
        for (i in 0...n) b.set(i, data.get(pos + n - 1 - i));
        return b;
    }

    public function readUTFBytes(n:Int):String {
        need(n);
        var end = pos;
        while (end < pos + n && data.get(end) != 0) end++;
        var s = data.getString(pos, end - pos);
        pos += n;
        return s;
    }

    public function readUTF():String {
        var n = readUnsignedShort();
        return readUTFBytes(n);
    }

    public function readBytes(target:BytesBuffer, length:Int = 0):Void {
        if (length == 0) length = bytesAvailable;
        need(length);
        target.addBytes(data, pos, length);
        pos += length;
    }

    public function readChunk(length:Int):Bytes {
        need(length);
        var out = data.sub(pos, length);
        pos += length;
        return out;
    }

    public function readAll():Bytes {
        var n = bytesAvailable;
        need(n);
        var out = data.sub(pos, n);
        pos += n;
        return out;
    }

    public function writeByte(v:Int):Void {
        room(1);
        data.set(pos, v & 0xFF);
        wrote(1);
    }

    public function writeBoolean(v:Bool):Void writeByte(v ? 1 : 0);

    public function writeShort(v:Int):Void {
        room(2);
        if (bigEndian) {
            data.set(pos, (v >> 8) & 0xFF);
            data.set(pos + 1, v & 0xFF);
        } else {
            data.set(pos, v & 0xFF);
            data.set(pos + 1, (v >> 8) & 0xFF);
        }
        wrote(2);
    }

    public function writeInt(v:Int):Void {
        room(4);
        if (bigEndian) {
            data.set(pos, (v >>> 24) & 0xFF);
            data.set(pos + 1, (v >> 16) & 0xFF);
            data.set(pos + 2, (v >> 8) & 0xFF);
            data.set(pos + 3, v & 0xFF);
        } else {
            data.setInt32(pos, v);
        }
        wrote(4);
    }

    public function writeUnsignedInt(v:Float):Void writeInt(Std.int(v >= 2147483648.0 ? v - 4294967296.0 : v));

    public function writeDouble(v:Float):Void {
        var b = Bytes.alloc(8);
        b.setDouble(0, v);
        writeRaw(b, bigEndian);
    }

    public function writeFloat(v:Float):Void {
        var b = Bytes.alloc(4);
        b.setFloat(0, v);
        writeRaw(b, bigEndian);
    }

    function writeRaw(b:Bytes, reverse:Bool):Void {
        room(b.length);
        for (i in 0...b.length) data.set(pos + i, b.get(reverse ? b.length - 1 - i : i));
        wrote(b.length);
    }

    public function writeUTFBytes(s:String):Void writeBytes(Bytes.ofString(s));

    public function writeUTF(s:String):Void {
        var b = Bytes.ofString(s);
        if (b.length > 65535) throw new ServiceError(2006, "The supplied index is out of bounds.");
        writeShort(b.length);
        writeBytes(b);
    }

    public function writeBytes(b:Bytes, offset:Int = 0, length:Int = 0):Void {
        if (length == 0) length = b.length - offset;
        room(length);
        data.blit(pos, b, offset, length);
        wrote(length);
    }

}
