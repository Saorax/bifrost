package flash.events;

class FileListEvent extends Event {
    public static var DIRECTORY_LISTING:String = "directoryListing";

    public var files:Array<Dynamic>;

    public function new(type:String, bubbles:Bool = false, cancelable:Bool = false, files:Array<Dynamic> = null) {
        super(type, bubbles, cancelable);
        this.files = files == null ? [] : files;
    }
}
