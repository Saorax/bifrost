package port.runtime.services;

import port.runtime.services.Extensions.ExtensionImpl;

class NativeExtension extends ExtensionImpl {
    public static var log:String->Void = null;
    public static var calls(default, null):Int = 0;
    public static var posted(default, null):Int = 0;
    public static var playing(default, null):Int = 0;
    static var seenEvents:Map<String, Bool> = new Map();

    static inline var UNLOAD_BUDGET = 0.004;
    static var deferUnloads = Sys.getEnv("BH_PORT_SYNC_UNLOAD") != "1";
    static var pendingUnloads:Array<String> = [];
    static var updateHooked = false;

    var loaded = false;

    function new() {
        super();
    }

    public static function open(appDir:String, id:String, initializer:String, finalizer:String):NativeExtension {
        var dll = appDir + "/META-INF/AIR/extensions/" + id + "/META-INF/ANE/Windows-x86-64/" + id + ".dll";
        if (!sys.FileSystem.exists(dll)) {
            if (log != null) log("extension " + id + ": no DLL at " + dll);
            return null;
        }
        var step = Native.load(@:privateAccess dll.toUtf8(), @:privateAccess initializer.toUtf8(),
            @:privateAccess finalizer.toUtf8());
        if (step != 0) {
            if (log != null) log("extension " + id + ": load failed at step " + step);
            return null;
        }
        if (log != null) log("extension " + id + ": loaded, " + Native.function_count() + " functions");
        var ext = new NativeExtension();
        ext.loaded = true;
        return ext;
    }

    override public function call(name:String, args:Array<Dynamic>):Dynamic {
        if (!loaded) return null;
        if (deferUnloads && name == "UnloadBank" && args.length == 1 && Std.isOfType(args[0], String)) {
            pendingUnloads.push(args[0]);
            if (!updateHooked) {
                updateHooked = true;
                Pump.add(() -> {
                    runPendingUnloads(UNLOAD_BUDGET);
                    return true;
                });
            }
            return 1;
        }
        if (name == "LoadBank" || name == "SetBasePath" || name == "Init") runPendingUnloads(-1);
        return invoke(name, args);
    }

    function runPendingUnloads(budget:Float):Void {
        if (pendingUnloads.length == 0 || !loaded) return;
        var started = Sys.time();
        do {
            invoke("UnloadBank", [pendingUnloads.shift()]);
        } while (pendingUnloads.length > 0 && (budget < 0 || Sys.time() - started < budget));
    }

    function invoke(name:String, args:Array<Dynamic>):Dynamic {
        var out = new haxe.io.BytesOutput();
        for (arg in args) write(out, arg);
        var bytes = out.getBytes();
        var started = Sys.time();
        var result = Native.call(@:privateAccess name.toUtf8(), bytes.getData().bytes, bytes.length);
        var took = Sys.time() - started;
        calls++;
        if (name == "PostEvent") {
            posted++;
            var event = Std.string(args[0]);
            if (log != null && !seenEvents.exists(event)) {
                seenEvents.set(event, true);
                log("sound event " + event + " = " + result);
            }
            if (!Math.isNaN(result) && result != 0) playing++;
        }
        if (log != null && (name == "Init" || name == "LoadBank" || name == "UnloadBank"))
            log("extension call " + name + "(" + args.join(", ") + ") = " + result + " (" + Math.round(took * 10000) / 10
                + " ms)");
        if (Math.isNaN(result)) return null;
        if (result >= 0 && result <= 2147483647 && result == Math.ffloor(result)) return Std.int(result);
        return result;
    }

    static function write(out:haxe.io.BytesOutput, value:Dynamic) {
        if (value == null) {
            out.writeByte(4);
        } else if (Std.isOfType(value, String)) {
            var bytes = haxe.io.Bytes.ofString(value);
            out.writeByte(2);
            out.writeInt32(bytes.length);
            out.write(bytes);
        } else if (Std.isOfType(value, Int)) {
            var i:Int = value;
            if (i >= 0) {
                out.writeByte(0);
                out.writeInt32(i);
            } else {
                out.writeByte(1);
                out.writeDouble(i);
            }
        } else if (Std.isOfType(value, Float)) {
            out.writeByte(1);
            out.writeDouble(value);
        } else if (Std.isOfType(value, Bool)) {
            out.writeByte(0);
            out.writeInt32(value ? 1 : 0);
        } else if (Std.isOfType(value, Array)) {
            var items:Array<Dynamic> = value;
            out.writeByte(3);
            out.writeInt32(items.length);
            for (item in items) write(out, item);
        } else {
            out.writeByte(4);
        }
    }

    override public function dispose():Void {
        runPendingUnloads(-1);
        if (loaded) Native.dispose();
        loaded = false;
        super.dispose();
    }
}

@:hlNative("bhsound")
private extern class Native {
    static function load(dll:hl.Bytes, initializer:hl.Bytes, finalizer:hl.Bytes):Int;
    static function function_count():Int;
    static function call(name:hl.Bytes, args:hl.Bytes, length:Int):Float;
    static function dispose():Void;
}
