package flash.events;

class IOErrorEvent extends ErrorEvent {
    public static var IO_ERROR:String = "ioError";

    public function new(type:String, bubbles:Bool = false, cancelable:Bool = false, text:String = "", id:Int = 0) {
        super(type, bubbles, cancelable, text, id);
    }
}
