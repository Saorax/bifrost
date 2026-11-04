package port.runtime.services;

class Settings {
    static var stores:Map<String, Settings> = new Map();

    public var name(default, null):String;
    public var data(default, null):Dynamic;

    public static function getLocal(name:String, localPath:String = "/"):Settings {
        var key = folder(localPath) + "|" + name;
        var store = stores.get(key);
        if (store == null) {
            store = new Settings(name, file(name, localPath));
            stores.set(key, store);
        }
        return store;
    }

    public static function reset():Void {
        stores = new Map();
    }

    public static function file(name:String, localPath:String = "/"):String {
        return Paths.resolve(folder(localPath), name + ".sol");
    }

    static function folder(localPath:String):String {
        var game = port.runtime.PortStorage.gameFolder;
        var base = Paths.resolve(game != null ? game : Launch.storageDirectory(), "#SharedObjects");
        var sub = localPath == null ? "" : StringTools.replace(localPath, "/", "\\");
        while (StringTools.startsWith(sub, "\\")) sub = sub.substr(1);
        return sub == "" ? base : Paths.resolve(base, sub);
    }

    var path:String;

    function new(name:String, path:String) {
        this.name = name;
        this.path = path;
        data = {};
        if (Files.exists(path)) {
            try {
                var parsed:Dynamic = Amf.readSol(Files.readBytes(path)).data;
                if (parsed != null && Reflect.isObject(parsed)) data = parsed;
            } catch (e:Dynamic) {
            }
        }
    }

    public function flush(minDiskSpace:Int = 0):String {
        Files.writeBytes(path, Amf.writeSol(name, data));
        return "flushed";
    }

    public function clear():Void {
        data = {};
        if (Files.exists(path)) Files.deleteFile(path);
    }

    public var size(get, never):Int;

    function get_size():Int {
        return Amf.writeSol(name, data).length;
    }
}
