package port.runtime;

import openfl.display.DisplayObject;
import openfl.display.IDisplayObjectLoader;
import openfl.display.LoaderInfo;
import openfl.display.MovieClip;
import openfl.net.URLRequest;
import openfl.system.LoaderContext;
import openfl.utils.ByteArray;
import openfl.utils.Future;
import openfl.utils.Promise;

@:access(openfl.display.LoaderInfo)
class SwfLoader implements IDisplayObjectLoader {
    public static var loaded(default, null):Int = 0;

    public function new() {}

    public static function isSwf(bytes:ByteArray):Bool {
        if (bytes == null || bytes.length < 8) return false;
        var a = bytes[0], b = bytes[1], c = bytes[2];
        return (a == "F".code || a == "C".code || a == "Z".code) && b == "W".code && c == "S".code;
    }

    public function load(request:URLRequest, context:LoaderContext, contentLoaderInfo:LoaderInfo):Future<DisplayObject> {
        return null;
    }

    public function loadBytes(buffer:ByteArray, context:LoaderContext, contentLoaderInfo:LoaderInfo):Future<DisplayObject> {
        if (!isSwf(buffer)) return null;
        contentLoaderInfo.contentType = "application/x-shockwave-flash";
        var domain = context != null && context.applicationDomain != null ? context.applicationDomain
            : new openfl.system.ApplicationDomain(openfl.system.ApplicationDomain.currentDomain);
        contentLoaderInfo.applicationDomain = domain;
        var library = new port.runtime.swf.SwfLibrary(buffer, buffer.length);
        port.runtime.swf.SwfSymbols.register(domain, library);
        contentLoaderInfo.bytesLoaded = buffer.length;
        contentLoaderInfo.bytesTotal = buffer.length;
        var promise = new Promise<DisplayObject>();
        port.runtime.services.Pump.add(function() {
            loaded++;
            promise.complete(new MovieClip());
            return false;
        });
        return promise.future;
    }
}
