package port.runtime.services;

class Pump {
    static var tasks:Array<() -> Bool> = [];

    public static function add(task:() -> Bool):Void {
        tasks.push(task);
    }

    public static function tick():Void {
        if (tasks.length == 0) return;
        var current = tasks;
        tasks = [];
        var keep:Array<() -> Bool> = [];
        var failure:Null<haxe.Exception> = null;
        for (task in current) {
            try {
                if (task()) keep.push(task);
            } catch (e:haxe.Exception) {
                keep.push(task);
                if (failure == null) failure = e;
            }
        }
        for (task in tasks) keep.push(task);
        tasks = keep;
        if (failure != null) throw failure;
    }

    public static var size(get, never):Int;

    static function get_size():Int return tasks.length;
}
