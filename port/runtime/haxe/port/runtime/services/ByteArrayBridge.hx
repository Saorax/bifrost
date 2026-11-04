package port.runtime.services;

import flash.utils.ByteArray;

class ByteArrayBridge {
    public static function readInto(source:DataBuffer, bytes:ByteArray, offset:Int, length:Int):Void {
        if (length == 0) length = source.bytesAvailable;
        if (length > source.bytesAvailable) throw new ServiceError(2030, "End of file was encountered.");
        var keep = bytes.position;
        bytes.position = offset;
        #if ((openfl || heaps) && !flash)
        if (length > 0) bytes.writeBytes(ByteArray.fromBytes(source.readChunk(length)), 0, length);
        #else
        for (i in 0...length) bytes.writeByte(source.readUnsignedByte());
        #end
        bytes.position = keep;
    }

    public static function writeFrom(target:DataBuffer, bytes:ByteArray, offset:Int, length:Int):Void {
        var chunk = slice(bytes, offset, length);
        if (chunk.length > 0) target.writeBytes(chunk, 0, chunk.length);
    }

    public static function slice(bytes:ByteArray, offset:Int, length:Int):haxe.io.Bytes {
        var total:Int = cast bytes.length;
        if (length == 0) length = total - offset;
        if (offset < 0 || length < 0 || offset + length > total)
            throw new ServiceError(2006, "The supplied index is out of bounds.");
        var keep = bytes.position;
        bytes.position = offset;
        var chunk = haxe.io.Bytes.alloc(length);
        for (i in 0...length) chunk.set(i, bytes.readUnsignedByte());
        bytes.position = keep;
        return chunk;
    }

    public static function wrap(data:haxe.io.Bytes):ByteArray {
        var out = new ByteArray();
        for (i in 0...data.length) out.writeByte(data.get(i));
        out.position = 0;
        return out;
    }
}
