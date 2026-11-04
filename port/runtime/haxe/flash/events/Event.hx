package flash.events;

class Event {
    public static var ADDED_TO_STAGE:String = "addedToStage";
    public static var CLOSE:String = "close";
    public static var COMPLETE:String = "complete";
    public static var CONNECT:String = "connect";
    public static var CHANGE:String = "change";
    public static var ACTIVATE:String = "activate";
    public static var CONTEXT3D_CREATE:String = "context3DCreate";
    public static var CLOSING:String = "closing";
    public static var DEACTIVATE:String = "deactivate";
    public static var ENTER_FRAME:String = "enterFrame";
    public static var EXIT_FRAME:String = "exitFrame";
    public static var EXITING:String = "exiting";
    public static var RESIZE:String = "resize";
    public static var SELECT:String = "select";

    public var type:String;
    public var bubbles:Bool;
    public var cancelable:Bool;
    public var currentTarget:Dynamic;
    public var target:Dynamic;

    public function new(type:String, bubbles:Bool = false, cancelable:Bool = false) {
        this.type = type;
        this.bubbles = bubbles;
        this.cancelable = cancelable;
        this.currentTarget = null;
        this.target = null;
    }

    public function stopPropagation():Void {}

    public function stopImmediatePropagation():Void {}

    public function preventDefault():Void {}

    public function clone():Event {
        return new Event(type, bubbles, cancelable);
    }
}
