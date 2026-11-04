package flash.events;

class NativeProcessExitEvent extends Event {
    public static var EXIT:String = "exit";

    public var exitCode:Int;

    public function new(type:String, bubbles:Bool = false, cancelable:Bool = false, exitCode:Int = 0) {
        super(type, bubbles, cancelable);
        this.exitCode = exitCode;
    }
}
