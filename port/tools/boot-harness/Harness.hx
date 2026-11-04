import flash.display.Loader;
import flash.display.Sprite;
import flash.events.Event;
import flash.events.IOErrorEvent;
import flash.events.UncaughtErrorEvent;
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;
import flash.system.ApplicationDomain;
import flash.system.LoaderContext;
import flash.utils.ByteArray;

class Harness extends Sprite {
    static function log(text:String):Void {
        try {
            var file = File.documentsDirectory.resolvePath("Bifrost/bh-port-boot.txt");
            var stream = new FileStream();
            stream.open(file, FileMode.APPEND);
            stream.writeUTFBytes(Date.now().toString() + " " + text + "\n");
            stream.close();
        } catch (e:Dynamic) {}
    }

    static function describe(error:Dynamic):String {
        if (Std.isOfType(error, flash.errors.Error)) {
            var e:flash.errors.Error = cast error;
            var stack = e.getStackTrace();
            return e.name + " #" + e.errorID + ": " + e.message + (stack != null ? "\n" + stack : "");
        }
        return Std.string(error);
    }

    static function main() {
        flash.Lib.current.addChild(new Harness());
    }

    function new() {
        super();
        log("harness: start");
        var bytes = new ByteArray();
        var stream = new FileStream();
        stream.open(File.applicationDirectory.resolvePath("BrawlhallaAir.game.swf"), FileMode.READ);
        stream.readBytes(bytes);
        stream.close();
        log("harness: read " + bytes.length + " bytes");
        var same = File.applicationDirectory.resolvePath("harness-same-domain.txt").exists;
        log("harness: " + (same ? "same domain" : "own domain"));
        var context = new LoaderContext(false, same ? ApplicationDomain.currentDomain : new ApplicationDomain(null));
        context.allowCodeImport = true;
        var loader = new Loader();
        loader.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, function(e:UncaughtErrorEvent) {
            log("uncaught: " + describe(e.error));
        });
        loader.contentLoaderInfo.addEventListener(Event.INIT, function(_) log("harness: game init"));
        loader.contentLoaderInfo.addEventListener(Event.COMPLETE, function(_) log("harness: game loaded"));
        loader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, function(e:IOErrorEvent) log("harness: io error " + e.text));
        addChild(loader);
        try {
            loader.loadBytes(bytes, context);
        } catch (e:Dynamic) {
            log("harness: loadBytes threw " + describe(e));
        }
    }
}
