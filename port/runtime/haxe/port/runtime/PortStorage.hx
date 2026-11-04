package port.runtime;

class PortStorage {
    public static inline var PREFIX = "bhport_";
    public static inline var FOLDER = "BhPort";

    public static var gameFolder:Null<String> = null;

    public static function storageDirectory():flash.filesystem.File {
        #if flash
        return flash.filesystem.File.applicationStorageDirectory.resolvePath(FOLDER);
        #else
        return flash.filesystem.File.applicationStorageDirectory;
        #end
    }

    public static function userDirectory():flash.filesystem.File {
        #if !flash
        if (gameFolder != null) return new flash.filesystem.File(port.runtime.services.Launch.userDirectory());
        #end
        return ensure(storageDirectory().resolvePath("User"));
    }

    public static function documentsDirectory():flash.filesystem.File {
        #if !flash
        if (gameFolder != null) return new flash.filesystem.File(port.runtime.services.Launch.documentsDirectory());
        #end
        return ensure(storageDirectory().resolvePath("Documents"));
    }

    static function ensure(dir:flash.filesystem.File):flash.filesystem.File {
        try {
            if (!dir.exists) dir.createDirectory();
        } catch (_:Dynamic) {}
        return dir;
    }

    public static function getLocal(name:String, ?localPath:String, secure:Bool = false):flash.net.SharedObject {
        #if flash
        return flash.net.SharedObject.getLocal(PREFIX + name, localPath, secure);
        #else
        return flash.net.SharedObject.getLocal(name, localPath, secure);
        #end
    }
}
