package port.runtime;

class SlowListeners {
    static inline var LIMIT_MS = 300;
    static var depth = 0;

    public static function call(callback:Dynamic->Void, event:openfl.events.Event):Void {
        var started = Sys.time();
        depth++;
        try {
            callback(event);
        } catch (error:Dynamic) {
            depth--;
            report(started, event);
            throw error;
        }
        depth--;
        report(started, event);
    }

    static function report(started:Float, event:openfl.events.Event):Void {
        var ms = Std.int((Sys.time() - started) * 1000);
        if (ms < LIMIT_MS) return;
        var target = event.currentTarget != null ? Type.getClassName(Type.getClass(event.currentTarget)) : "null";
        NativeMain.log("slow listener: " + ms + " ms, " + event.type + " on " + target + " (depth " + depth + ")");
    }
}
