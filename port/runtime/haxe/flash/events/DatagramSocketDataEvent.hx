package flash.events;

import flash.utils.ByteArray;

#if flash
@:native("flash.events.DatagramSocketDataEvent") extern class DatagramSocketDataEvent extends Event {
    public static var DATA(default, never):String;

    public var data:ByteArray;
    public var srcAddress:String;
    public var srcPort:Int;

    public function new(type:String, bubbles:Bool = false, cancelable:Bool = false, data:ByteArray = null,
            srcAddress:String = "", srcPort:Int = 0):Void;
}
#else
class DatagramSocketDataEvent extends Event {
    public static inline var DATA:String = "data";

    public var data:ByteArray;
    public var srcAddress:String;
    public var srcPort:Int;

    public function new(type:String, bubbles:Bool = false, cancelable:Bool = false, data:ByteArray = null,
            srcAddress:String = "", srcPort:Int = 0) {
        super(type, bubbles, cancelable);
        this.data = data;
        this.srcAddress = srcAddress;
        this.srcPort = srcPort;
    }
}
#end
