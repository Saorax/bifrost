package port.runtime.services;

import haxe.io.Bytes;

class Files {
    public static function exists(path:String):Bool {
        #if sys
        return path != "" && sys.FileSystem.exists(path);
        #else
        return false;
        #end
    }

    public static function isDirectory(path:String):Bool {
        #if sys
        return exists(path) && sys.FileSystem.isDirectory(path);
        #else
        return false;
        #end
    }

    public static function size(path:String):Float {
        #if sys
        return exists(path) && !isDirectory(path) ? sys.FileSystem.stat(path).size : 0;
        #else
        return 0;
        #end
    }

    public static function modificationDate(path:String):Null<Date> {
        #if sys
        return exists(path) ? sys.FileSystem.stat(path).mtime : null;
        #else
        return null;
        #end
    }

    public static function list(path:String):Array<String> {
        #if sys
        if (!isDirectory(path)) throw new ServiceError(3003, "File or directory does not exist: " + path);
        var names = sys.FileSystem.readDirectory(path);
        names.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
        return [for (n in names) Paths.resolve(path, n)];
        #else
        return [];
        #end
    }

    public static function createDirectory(path:String):Void {
        #if sys
        sys.FileSystem.createDirectory(path);
        #end
    }

    public static function deleteFile(path:String):Void {
        #if sys
        if (!exists(path) || isDirectory(path)) throw new ServiceError(3003, "File does not exist: " + path);
        sys.FileSystem.deleteFile(path);
        #end
    }

    public static function deleteDirectory(path:String, contents:Bool = false):Void {
        #if sys
        if (!isDirectory(path)) throw new ServiceError(3003, "Directory does not exist: " + path);
        if (contents) {
            for (entry in list(path)) {
                if (isDirectory(entry)) deleteDirectory(entry, true) else sys.FileSystem.deleteFile(entry);
            }
        } else if (sys.FileSystem.readDirectory(path).length > 0) {
            throw new ServiceError(3011, "Directory is not empty: " + path);
        }
        sys.FileSystem.deleteDirectory(path);
        #end
    }

    public static function copy(from:String, to:String, overwrite:Bool = false):Void {
        #if sys
        if (!exists(from)) throw new ServiceError(3003, "File or directory does not exist: " + from);
        if (exists(to)) {
            if (!overwrite) throw new ServiceError(3002, "File or directory exists: " + to);
            if (isDirectory(to)) deleteDirectory(to, true) else sys.FileSystem.deleteFile(to);
        }
        if (isDirectory(from)) {
            createDirectory(to);
            for (entry in list(from)) copy(entry, Paths.resolve(to, Paths.name(entry)), false);
        } else {
            var parent = Paths.parent(to);
            if (parent != null) createDirectory(parent);
            sys.io.File.copy(from, to);
        }
        #end
    }

    public static function move(from:String, to:String, overwrite:Bool = false):Void {
        #if sys
        if (!exists(from)) throw new ServiceError(3003, "File or directory does not exist: " + from);
        if (exists(to)) {
            if (!overwrite) throw new ServiceError(3002, "File or directory exists: " + to);
            if (isDirectory(to)) deleteDirectory(to, true) else sys.FileSystem.deleteFile(to);
        }
        sys.FileSystem.rename(from, to);
        #end
    }

    public static function readBytes(path:String):Bytes {
        #if sys
        if (!exists(path) || isDirectory(path)) throw new ServiceError(3003, "File does not exist: " + path);
        return sys.io.File.getBytes(path);
        #else
        throw new ServiceError(3003, "File does not exist: " + path);
        #end
    }

    public static function writeBytes(path:String, bytes:Bytes):Void {
        #if sys
        var parent = Paths.parent(path);
        if (parent != null && !exists(parent)) createDirectory(parent);
        sys.io.File.saveBytes(path, bytes);
        #end
    }
}
