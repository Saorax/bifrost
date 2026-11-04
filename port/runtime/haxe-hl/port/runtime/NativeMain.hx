package port.runtime;

import port.runtime.services.Launch;

@:access(openfl.display.Stage)
class NativeMain {
    public static function log(text:String):Void {
        try {
            var path = Sys.getEnv("BH_PORT_LOG");
            if (path == null || path == "") {
                var dir = Launch.documentsDirectory() + "\\Bifrost";
                if (!sys.FileSystem.exists(dir)) sys.FileSystem.createDirectory(dir);
                path = dir + "\\bh-port-boot.txt";
            }
            var out = sys.io.File.append(path, false);
            out.writeString(Date.now().toString() + " " + text + "\n");
            out.close();
        } catch (_:Dynamic) {}
    }

    static var probeCounts:Map<Int, Int> = new Map();

    public static function probe(id:Int, limit:Int, text:() -> String):Void {
        var count = probeCounts.exists(id) ? probeCounts.get(id) : 0;
        if (count < limit) {
            var line = try text() catch (e:Dynamic) "(probe failed: " + Std.string(e) + ")";
            if (line == null) return;
            probeCounts.set(id, count + 1);
            log("probe " + id + ": " + line);
        }
    }

    static function describe(error:Dynamic):String {
        var stack = haxe.CallStack.toString(haxe.CallStack.exceptionStack());
        var text = Std.isOfType(error, haxe.Exception) ? (error : haxe.Exception).details() : Std.string(error);
        return text + (stack != "" ? "\n" + stack : "");
    }

    static var seen:Map<String, Int> = new Map();

    static function logUncaught(error:Dynamic):Void {
        var text = describe(error);
        var count = (seen.exists(text) ? seen.get(text) : 0) + 1;
        seen.set(text, count);
        if (count <= 3)
            log("uncaught: " + text #if port_trace_index + "\nindex trail: " + port.runtime.As3.indexTrail.join(" ") #end);
        else if (Math.pow(10, Math.round(Math.log(count) / Math.log(10))) == count)
            log("uncaught (seen " + count + " times): " + text.split("\n")[0]);
    }

    static function main():Void {
        openfl.utils.ByteArray.defaultEndian = openfl.utils.Endian.BIG_ENDIAN;
        var appDir = Sys.getEnv("BH_PORT_APP_DIR");
        if (appDir != null && appDir != "") Launch.configure("application", appDir);
        var storageDir = Sys.getEnv("BH_PORT_STORAGE_DIR");
        if (storageDir != null && storageDir != "") Launch.configure("storage", storageDir);
        log("boot: start (native, application " + Launch.applicationDirectory() + ")");
        var started = Sys.time();

        var app = new openfl.display.Application();
        app.meta["name"] = "Brawlhalla";
        app.meta["file"] = "BrawlhallaPort";
        var attributes:lime.ui.WindowAttributes = {
            allowHighDPI: false,
            frameRate: 60,
            height: 720,
            resizable: true,
            title: "Brawlhalla (native port)",
            width: 1280,
        };
        attributes.context = {
            antialiasing: 0,
            background: 0x000000,
            depth: true,
            hardware: true,
            stencil: true,
            vsync: false,
        };
        if (Sys.getEnv("SDL_OPENGL_ES_DRIVER") == null && Sys.getEnv("BH_PORT_GLES_DRIVER") != "0")
            Sys.putEnv("SDL_OPENGL_ES_DRIVER", "1");
        app.createWindow(attributes);
        var stage:openfl.display.Stage = (cast app.window : openfl.display.Window).stage;
        var context = app.window.context;
        if (context != null && context.gl != null)
            log("window context: " + context.type + " " + context.version + ", " + context.gl.getString(context.gl.VERSION)
                + ", " + context.gl.getString(context.gl.RENDERER));
        else
            log("window context: " + (context == null ? "none" : Std.string(context.type)) + " (no GL)");
        stage.__uncaughtErrorEvents.addEventListener(openfl.events.UncaughtErrorEvent.UNCAUGHT_ERROR,
            function(event:openfl.events.UncaughtErrorEvent) {
                logUncaught(event.error);
                event.preventDefault();
            });
        stage.addEventListener(openfl.events.Event.ENTER_FRAME, function(_) {
            try {
                port.runtime.services.Pump.tick();
                LoadTrace.poll(log, describe);
            } catch (error:Dynamic) {
                logUncaught(error);
            }
        }, false, 1000);

        port.runtime.services.BuiltinExtensions.registerAll();
        port.runtime.input.Pads.source = port.runtime.input.LimePads.start;
        if (Sys.getEnv("BH_PORT_NO_SOUND") != "1") {
            port.runtime.services.NativeExtension.log = log;
            port.runtime.services.Extensions.register("SoundEngineExtension", (_) -> port.runtime.services.NativeExtension.open(
                Launch.applicationDirectory(), "SoundEngineExtension", "SoundEngineExtInitializer", "SoundEngineExtFinalizer"));
        }
        openfl.display.Loader.registerLoader(new SwfLoader());
        port.runtime.net.NetGuard.log = log;
        SmokeDriver.start(stage);
        flash.Lib.current = openfl.Lib.current;
        try {
            BootDocument.staticInit();
            GameApp.forceOffline = true;
            DnaTelemetry.dnaDisabled = true;
            GameApp.main();
        } catch (error:Dynamic) {
            log("uncaught in GameApp.main (static init stage: " + FlashBoot.initStage + "): " + describe(error));
        }
        log("boot: GameApp.main returned after " + Std.int((Sys.time() - started) * 1000) + " ms");

        var result = app.exec();
        lime.system.System.exit(result);
    }
}
