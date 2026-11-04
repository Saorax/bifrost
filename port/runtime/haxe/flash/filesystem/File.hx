package flash.filesystem;

import flash.events.EventDispatcher;
import port.runtime.services.Files;
import port.runtime.services.Launch;
import port.runtime.services.Paths;

class File extends EventDispatcher {
    public static var applicationDirectory(get, never):File;
    public static var applicationStorageDirectory(get, never):File;
    public static var documentsDirectory(get, never):File;
    public static var userDirectory(get, never):File;
    public static var desktopDirectory(get, never):File;

    public var exists(get, never):Bool;
    public var isDirectory(get, never):Bool;
    public var name(get, never):String;
    public var extension(get, never):String;
    public var nativePath(get, set):String;
    public var size(get, never):Float;
    public var url(get, never):String;
    public var parent(get, never):File;
    public var modificationDate(get, never):Date;

    var path:String;

    public function new(path:String = "") {
        super();
        this.path = Paths.normalize(StringTools.startsWith(path, "file:///") ? StringTools.urlDecode(path.substr(8)) : path);
    }

    static function get_applicationDirectory():File return new File(Launch.applicationDirectory());

    static function get_applicationStorageDirectory():File
        return new File(port.runtime.PortStorage.gameFolder != null ? port.runtime.PortStorage.gameFolder
            : Paths.resolve(Launch.storageDirectory(), port.runtime.PortStorage.FOLDER));

    static function get_documentsDirectory():File return port.runtime.PortStorage.documentsDirectory();

    static function get_userDirectory():File return port.runtime.PortStorage.userDirectory();

    static function get_desktopDirectory():File return new File(Launch.desktopDirectory());

    function get_exists():Bool return Files.exists(path);

    function get_isDirectory():Bool return Files.isDirectory(path);

    function get_name():String return Paths.name(path);

    function get_extension():String return Paths.extension(path);

    function get_nativePath():String return path;

    function set_nativePath(value:String):String {
        path = Paths.normalize(value);
        return path;
    }

    function get_size():Float return Files.size(path);

    function get_url():String return Paths.url(path);

    function get_parent():File {
        var up = Paths.parent(path);
        return up == null ? null : new File(up);
    }

    function get_modificationDate():Date return Files.modificationDate(path);

    public function resolvePath(path:String):File {
        var resolved = Paths.resolve(this.path, path);
        #if sys
        if (path == LAUNCHER_MARKER) {
            var marker = Sys.getEnv("BH_PORT_MARKER");
            if (marker != null && marker != "" && resolved == Paths.resolve(Launch.applicationDirectory(), path))
                return new File(marker);
        }
        #end
        return new File(resolved);
    }

    static inline var LAUNCHER_MARKER = "bifrost-engine.json";

    public function createDirectory():Void {
        Files.createDirectory(path);
    }

    public function deleteFile():Void {
        Files.deleteFile(path);
    }

    public function deleteDirectory(deleteDirectoryContents:Bool = false):Void {
        Files.deleteDirectory(path, deleteDirectoryContents);
    }

    public function getDirectoryListing():Array<File> {
        return [for (entry in Files.list(path)) new File(entry)];
    }

    public function getDirectoryListingAsync():Void {
        var files:Array<Dynamic> = try cast getDirectoryListing() catch (e:Dynamic) [];
        haxe.Timer.delay(function() {
            dispatchEvent(new flash.events.FileListEvent(flash.events.FileListEvent.DIRECTORY_LISTING, false, false, files));
        }, 0);
    }

    public function copyTo(target:File, overwrite:Bool = false):Void {
        Files.copy(path, target.nativePath, overwrite);
    }

    public function moveTo(target:File, overwrite:Bool = false):Void {
        Files.move(path, target.nativePath, overwrite);
    }

    static final RUNNABLE = ["exe", "bat", "cmd", "com", "msi", "ps1", "vbs", "js", "jse", "wsf", "lnk", "scr", "pif", "reg"];

    public function openWithDefaultApplication():Void {
        if (!exists) throw new port.runtime.services.ServiceError(3003, "File or directory does not exist.");
        if (!isDirectory && RUNNABLE.indexOf(extension == null ? "" : extension.toLowerCase()) >= 0)
            throw new port.runtime.services.ServiceError(3214, "Executables can't be opened this way.");
        #if sys
        var mode = Sys.getEnv("BH_PORT_BROWSER");
        if (mode == "off") return;
        if (mode != null && mode != "") {
            try {
                var out = sys.io.File.append(mode, false);
                out.writeString("open " + path + "\n");
                out.close();
            } catch (e:Dynamic) {}
            return;
        }
        if (Sys.systemName() == "Windows") {
            var windowsPath = StringTools.replace(path, "/", "\\");
            #if hl
            if (shellOpen(@:privateAccess windowsPath.bytes) > 32) return;
            #end
            new sys.io.Process("explorer.exe", [windowsPath]);
        }
        else new sys.io.Process(Sys.systemName() == "Mac" ? "open" : "xdg-open", [path]);
        #end
    }

    #if hl
    @:hlNative("bhsound", "shell_open") static function shellOpen(path:hl.Bytes):Int return 0;
    #end

    #if bifrost
    public function browseForOpen(title:String, ?typeFilter:Array<Dynamic>):Void {
        browse(false, title, typeFilter);
    }

    public function browseForSave(title:String):Void {
        browse(true, title, null);
    }

    function browse(save:Bool, title:String, typeFilter:Array<Dynamic>):Void {
        var chosen:String = null;
        #if hl
        var filters = typeFilter == null ? null : [for (f in typeFilter) {
            name: Std.string(f.description),
            exts: [for (e in Std.string(f.extension).split(";")) StringTools.replace(StringTools.trim(e), "*.", "")]
        }];
        var options:hl.UI.FileOptions = {title: title, filters: filters};
        if (path != null && path != "")
            options.fileName = path;
        chosen = save ? hl.UI.saveFile(options) : hl.UI.loadFile(options);
        #end
        if (chosen == null) {
            dispatchEvent(new flash.events.Event(flash.events.Event.CANCEL));
            return;
        }
        nativePath = chosen;
        dispatchEvent(new flash.events.Event(flash.events.Event.SELECT));
    }
    #end
}
