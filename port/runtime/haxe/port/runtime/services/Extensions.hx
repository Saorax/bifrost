package port.runtime.services;

class Extensions {
    static var factories:Map<String, (type:String) -> Null<ExtensionImpl>> = new Map();

    public static function register(id:String, factory:(type:String) -> Null<ExtensionImpl>):Void {
        factories.set(id, factory);
    }

    public static function unregister(id:String):Void {
        factories.remove(id);
    }

    public static function create(id:String, type:String = ""):Null<ExtensionImpl> {
        var factory = factories.get(id);
        return factory == null ? null : factory(type);
    }

    public static function registered():Array<String> {
        var ids = [for (k in factories.keys()) k];
        ids.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
        return ids;
    }
}

class ExtensionImpl {
    var functions:Map<String, Array<Dynamic> -> Dynamic> = new Map();

    public var onStatus:Null<(code:String, level:String) -> Void> = null;

    public function new() {}

    public function define(name:String, fn:Array<Dynamic> -> Dynamic):ExtensionImpl {
        functions.set(name, fn);
        return this;
    }

    public static var callSeconds:Float = 0;
    public static var slowestSeconds:Float = 0;
    public static var slowestName:String = "";

    public static function takeSlowest():String {
        var text = slowestSeconds > 0 ? slowestName + " " + Math.round(slowestSeconds * 10000) / 10 + " ms" : "";
        slowestSeconds = 0;
        slowestName = "";
        return text;
    }

    public function call(name:String, args:Array<Dynamic>):Dynamic {
        var fn = functions.get(name);
        if (fn == null) throw new ServiceError(3500, "The extension context does not have a method with the name " + name + ".");
        var started = haxe.Timer.stamp();
        var result = fn(args);
        var took = haxe.Timer.stamp() - started;
        callSeconds += took;
        if (took > slowestSeconds) {
            slowestSeconds = took;
            slowestName = name;
        }
        return result;
    }

    public function status(code:String, level:String):Void {
        if (onStatus != null) onStatus(code, level);
    }

    public function dispose():Void {
        functions = new Map();
        onStatus = null;
    }
}
