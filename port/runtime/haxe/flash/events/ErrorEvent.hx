package flash.events;

class ErrorEvent extends TextEvent {
    public static var ERROR:String = "error";

    public var errorID(default, null):Int;

    public function new(type:String, bubbles:Bool = false, cancelable:Bool = false, text:String = "", id:Int = 0) {
        super(type, bubbles, cancelable, text);
        this.errorID = id;
    }
}
