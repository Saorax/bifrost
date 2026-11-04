package flash.filesystem;
extern class File extends flash.net.FileReference {
    static var applicationDirectory(default, never):File;
    static var documentsDirectory(default, never):File;
    function new(?path:String):Void;
    var exists(default, never):Bool;
    function resolvePath(path:String):File;
}
