package flash.net;

import flash.events.EventDispatcher;
import port.runtime.services.Settings;

class SharedObject extends EventDispatcher {
    public var data(get, never):Dynamic;
    public var size(get, never):UInt;

    var store:Settings;

    function new(store:Settings) {
        super();
        this.store = store;
    }

    static var opened:Map<Settings, SharedObject> = new Map();

    public static function getLocal(name:String, localPath:String = null, secure:Bool = false):SharedObject {
        var stored = port.runtime.PortStorage.gameFolder != null ? name : port.runtime.PortStorage.PREFIX + name;
        var store = Settings.getLocal(stored, localPath == null ? "/" : localPath);
        var shared = opened.get(store);
        if (shared == null) opened.set(store, shared = new SharedObject(store));
        return shared;
    }

    function get_data():Dynamic return store.data;

    function get_size():UInt return store.size;

    public function flush(minDiskSpace:Int = 0):String {
        var started = haxe.Timer.stamp();
        var result = store.flush(minDiskSpace);
        flash.filesystem.FileStream.ioSeconds += haxe.Timer.stamp() - started;
        return result;
    }

    public function clear():Void {
        store.clear();
    }

    public function close():Void {}
}
