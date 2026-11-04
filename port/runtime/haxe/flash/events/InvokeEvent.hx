package flash.events;

import flash.filesystem.File;

class InvokeEvent extends Event {
    public static var INVOKE:String = "invoke";

    public var arguments:Array<Dynamic>;
    public var currentDirectory:File;

    public function new(type:String, bubbles:Bool = false, cancelable:Bool = false,
            arguments:Array<Dynamic> = null, currentDirectory:File = null) {
        super(type, bubbles, cancelable);
        this.arguments = arguments == null ? [] : arguments;
        this.currentDirectory = currentDirectory;
    }
}
