package port.runtime;

#if flash
import flash.events.UncaughtErrorEvent;
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;

class FlashBoot {
    public static var initStage:String = "";

    static function log(text:String):Void {
        try {
            var stream = new FileStream();
            stream.open(File.documentsDirectory.resolvePath("Bifrost/bh-port-boot.txt"), FileMode.APPEND);
            stream.writeUTFBytes(Date.now().toString() + " " + text + "\n");
            stream.close();
        } catch (_:Dynamic) {}
    }

    static function describe(error:Dynamic):String {
        if (Std.isOfType(error, flash.errors.Error)) {
            var e:flash.errors.Error = cast error;
            var stack = e.getStackTrace();
            return e.name + " #" + e.errorID + ": " + e.message + (stack != null ? "\n" + stack : "");
        }
        return Std.string(error);
    }

    static var seen:Map<String, Int> = new Map();

    static function logUncaught(error:Dynamic):Void {
        var text = describe(error);
        var count = (seen.exists(text) ? seen.get(text) : 0) + 1;
        seen.set(text, count);
        if (count <= 3)
            log("uncaught: " + text);
        else if (Math.pow(10, Math.round(Math.log(count) / Math.log(10))) == count)
            log("uncaught (seen " + count + " times): " + text.split("\n")[0]);
    }

    static function main():Void {
        log("boot: start");
        flash.Lib.current.loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR,
            function(event:UncaughtErrorEvent) logUncaught(event.error));
        flash.Lib.current.addEventListener(flash.events.Event.ENTER_FRAME, function(_) LoadTrace.poll(log, describe));
        port.runtime.net.NetGuard.log = log;
        SmokeDriver.start(flash.Lib.current.stage);
        try {
            BootDocument.staticInit();
            GameApp.forceOffline = true;
            DnaTelemetry.dnaDisabled = true;
            GameApp.main();
        } catch (error:Dynamic) {
            log("uncaught in GameApp.main (static init stage: " + initStage + "): " + describe(error));
            throw error;
        }
        log("boot: GameApp.main returned");
    }
}
#else
class FlashBoot {
    public static var initStage:String = "";
}
#end
