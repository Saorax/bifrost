package flash.filesystem;

import flash.events.EventDispatcher;
import flash.utils.ByteArray;
import flash.utils.Endian;
import port.runtime.services.ByteArrayBridge;
import port.runtime.services.FileBuffer;
import port.runtime.services.ServiceError;

class FileStream extends EventDispatcher {
    public var bytesAvailable(get, never):UInt;
    public var endian(get, set):Endian;
    public var objectEncoding(get, set):UInt;
    public var position(get, set):Float;
    public var readAhead(get, set):Float;

    var buffer:Null<FileBuffer> = null;
    var littleEndian:Bool = false;
    var encoding:UInt = 3;
    var ahead:Float = 0;

    public function new() {
        super();
    }

    public static var ioSeconds:Float = 0;

    public function open(file:File, fileMode:String):Void {
        var started = haxe.Timer.stamp();
        if (buffer != null) buffer.close();
        buffer = null;
        var opened = new FileBuffer(file.nativePath, fileMode);
        opened.bigEndian = !littleEndian;
        buffer = opened;
        ioSeconds += haxe.Timer.stamp() - started;
    }

    public function openAsync(file:File, fileMode:String):Void {
        open(file, fileMode);
    }

    public function close():Void {
        var started = haxe.Timer.stamp();
        if (buffer != null) buffer.close();
        buffer = null;
        ioSeconds += haxe.Timer.stamp() - started;
    }

    public function truncate():Void {
        stream().truncate();
    }

    function stream():FileBuffer {
        if (buffer == null) throw new ServiceError(2029, "This URLStream object does not have a stream opened.");
        return buffer;
    }

    function get_bytesAvailable():UInt return buffer == null ? 0 : buffer.bytesAvailable;

    function get_endian():Endian return littleEndian ? Endian.LITTLE_ENDIAN : Endian.BIG_ENDIAN;

    function set_endian(value:Endian):Endian {
        littleEndian = value == Endian.LITTLE_ENDIAN;
        if (buffer != null) buffer.bigEndian = !littleEndian;
        return value;
    }

    function get_objectEncoding():UInt return encoding;

    function set_objectEncoding(value:UInt):UInt return encoding = value;

    function get_position():Float return buffer == null ? 0 : buffer.position;

    function set_position(value:Float):Float {
        stream().position = Std.int(value);
        return value;
    }

    function get_readAhead():Float return ahead;

    function set_readAhead(value:Float):Float return ahead = value;

    public function readBoolean():Bool {
        return stream().readBoolean();
    }

    public function readByte():Int {
        return stream().readByte();
    }

    public function readBytes(bytes:ByteArray, offset:UInt = 0, length:UInt = 0):Void {
        ByteArrayBridge.readInto(stream(), bytes, offset, length);
    }

    public function readDouble():Float {
        return stream().readDouble();
    }

    public function readFloat():Float {
        return stream().readFloat();
    }

    public function readInt():Int {
        return stream().readInt();
    }

    public function readMultiByte(length:UInt, charSet:String):String {
        return stream().readUTFBytes(length);
    }

    public function readObject():Dynamic {
        throw new ServiceError(2004, "readObject is not supported by the native FileStream.");
    }

    public function readShort():Int {
        return stream().readShort();
    }

    public function readUTF():String {
        return stream().readUTF();
    }

    public function readUTFBytes(length:UInt):String {
        return stream().readUTFBytes(length);
    }

    public function readUnsignedByte():UInt {
        return stream().readUnsignedByte();
    }

    public function readUnsignedInt():UInt {
        return Std.int(stream().readUnsignedInt());
    }

    public function readUnsignedShort():UInt {
        return stream().readUnsignedShort();
    }

    public function writeBoolean(value:Bool):Void {
        stream().writeBoolean(value);
    }

    public function writeByte(value:Int):Void {
        stream().writeByte(value);
    }

    public function writeBytes(bytes:ByteArray, offset:UInt = 0, length:UInt = 0):Void {
        ByteArrayBridge.writeFrom(stream(), bytes, offset, length);
    }

    public function writeDouble(value:Float):Void {
        stream().writeDouble(value);
    }

    public function writeFloat(value:Float):Void {
        stream().writeFloat(value);
    }

    public function writeInt(value:Int):Void {
        stream().writeInt(value);
    }

    public function writeMultiByte(value:String, charSet:String):Void {
        stream().writeUTFBytes(value);
    }

    public function writeObject(object:Dynamic):Void {
        throw new ServiceError(2004, "writeObject is not supported by the native FileStream.");
    }

    public function writeShort(value:Int):Void {
        stream().writeShort(value);
    }

    public function writeUTF(value:String):Void {
        stream().writeUTF(value);
    }

    public function writeUTFBytes(value:String):Void {
        stream().writeUTFBytes(value);
    }

    public function writeUnsignedInt(value:UInt):Void {
        stream().writeUnsignedInt((value : Float));
    }
}
