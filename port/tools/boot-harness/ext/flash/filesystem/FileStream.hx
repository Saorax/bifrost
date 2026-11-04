package flash.filesystem;
extern class FileStream extends flash.events.EventDispatcher {
    function new():Void;
    function open(file:File, fileMode:String):Void;
    function readBytes(bytes:flash.utils.ByteArray, offset:UInt = 0, length:UInt = 0):Void;
    function writeUTFBytes(value:String):Void;
    function close():Void;
}
