package flash.net;

import port.runtime.net.NetGuard;
import flash.events.Event;
import flash.events.EventDispatcher;
import flash.events.IOErrorEvent;
import flash.events.ProgressEvent;
import flash.utils.ByteArray;
import flash.utils.Endian;
import port.runtime.services.ByteArrayBridge;
import port.runtime.services.DataBuffer;
import port.runtime.services.Pump;
import port.runtime.services.TcpStream;

class Socket extends EventDispatcher {
    public var bytesAvailable(get, never):UInt;
    public var bytesPending(get, never):UInt;
    public var connected(get, never):Bool;
    public var endian(get, set):Endian;
    public var objectEncoding(get, set):UInt;
    public var timeout(get, set):UInt;

    var tcp:TcpStream = new TcpStream();
    var littleEndian:Bool = false;
    var encoding:UInt = 3;
    var pumping:Bool = false;

    public function new(host:String = null, port:Int = 0) {
        super();
        if (host != null && port != 0) connect(host, port);
    }

    public function connect(host:String, port:Int):Void {
        if (!NetGuard.allowHost(host, port)) {
            NetGuard.refuse("TCP " + host + ":" + port);
            haxe.Timer.delay(function() {
                dispatchEvent(new IOErrorEvent(IOErrorEvent.IO_ERROR, false, false,
                    "Error #2031: refused by the port's network guard", 2031));
            }, 0);
            return;
        }
        tcp.connect(host, port);
        tcp.input.bigEndian = tcp.output.bigEndian = !littleEndian;
        if (!pumping) {
            pumping = true;
            Pump.add(pump);
        }
    }

    function pump():Bool {
        for (event in tcp.poll()) {
            switch (event) {
                case Connected:
                    dispatchEvent(new Event(Event.CONNECT));
                case Data(bytes):
                    dispatchEvent(new ProgressEvent(ProgressEvent.SOCKET_DATA, false, false, bytes, 0));
                case Closed:
                    dispatchEvent(new Event(Event.CLOSE));
                case IoError(text):
                    dispatchEvent(new IOErrorEvent(IOErrorEvent.IO_ERROR, false, false, text, 2031));
            }
        }
        pumping = tcp.connected || tcp.connecting;
        return pumping;
    }

    public function close():Void {
        tcp.close();
    }

    public function flush():Void {
        tcp.flush();
    }

    function get_bytesAvailable():UInt return tcp.input.bytesAvailable;

    function get_bytesPending():UInt return tcp.output.length;

    function get_connected():Bool return tcp.connected;

    function get_endian():Endian return littleEndian ? Endian.LITTLE_ENDIAN : Endian.BIG_ENDIAN;

    function set_endian(value:Endian):Endian {
        littleEndian = value == Endian.LITTLE_ENDIAN;
        tcp.input.bigEndian = tcp.output.bigEndian = !littleEndian;
        return value;
    }

    function get_objectEncoding():UInt return encoding;

    function set_objectEncoding(value:UInt):UInt return encoding = value;

    function get_timeout():UInt return tcp.timeout;

    function set_timeout(value:UInt):UInt {
        tcp.timeout = value;
        return value;
    }

    function input():DataBuffer return tcp.input;

    public function readBoolean():Bool {
        return input().readBoolean();
    }

    public function readByte():Int {
        return input().readByte();
    }

    public function readBytes(bytes:ByteArray, offset:UInt = 0, length:UInt = 0):Void {
        ByteArrayBridge.readInto(input(), bytes, offset, length);
    }

    public function readDouble():Float {
        return input().readDouble();
    }

    public function readFloat():Float {
        return input().readFloat();
    }

    public function readInt():Int {
        return input().readInt();
    }

    public function readMultiByte(length:UInt, charSet:String):String {
        return input().readUTFBytes(length);
    }

    public function readShort():Int {
        return input().readShort();
    }

    public function readUTF():String {
        return input().readUTF();
    }

    public function readUTFBytes(length:UInt):String {
        return input().readUTFBytes(length);
    }

    public function readUnsignedByte():UInt {
        return input().readUnsignedByte();
    }

    public function readUnsignedInt():UInt {
        return Std.int(input().readUnsignedInt());
    }

    public function readUnsignedShort():UInt {
        return input().readUnsignedShort();
    }

    public function writeBoolean(value:Bool):Void {
        tcp.output.writeBoolean(value);
    }

    public function writeByte(value:Int):Void {
        tcp.output.writeByte(value);
    }

    public function writeBytes(bytes:ByteArray, offset:UInt = 0, length:UInt = 0):Void {
        ByteArrayBridge.writeFrom(tcp.output, bytes, offset, length);
    }

    public function writeDouble(value:Float):Void {
        tcp.output.writeDouble(value);
    }

    public function writeFloat(value:Float):Void {
        tcp.output.writeFloat(value);
    }

    public function writeInt(value:Int):Void {
        tcp.output.writeInt(value);
    }

    public function writeMultiByte(value:String, charSet:String):Void {
        tcp.output.writeUTFBytes(value);
    }

    public function writeShort(value:Int):Void {
        tcp.output.writeShort(value);
    }

    public function writeUTF(value:String):Void {
        tcp.output.writeUTF(value);
    }

    public function writeUTFBytes(value:String):Void {
        tcp.output.writeUTFBytes(value);
    }

    public function writeUnsignedInt(value:UInt):Void {
        tcp.output.writeUnsignedInt((value : Float));
    }
}
