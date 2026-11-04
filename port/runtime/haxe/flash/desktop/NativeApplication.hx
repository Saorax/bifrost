package flash.desktop;

import flash.events.EventDispatcher;
import flash.events.InvokeEvent;
import flash.filesystem.File;
import port.runtime.services.Launch;
import port.runtime.services.Pump;

class NativeApplication extends EventDispatcher {
    public static var nativeApplication(get, never):NativeApplication;
    public static var supportsDockIcon:Bool = false;

    public var activeWindow:Dynamic = null;
    public var applicationID(get, never):String;
    public var icon:Dynamic = null;

    static var instance:Null<NativeApplication> = null;

    var invoked:Bool = false;

    public function new() {
        super();
        Pump.add(deliverInvoke);
    }

    static function get_nativeApplication():NativeApplication {
        if (instance == null) instance = new NativeApplication();
        return instance;
    }

    function get_applicationID():String return Launch.APP_ID;

    function deliverInvoke():Bool {
        if (invoked) return false;
        if (!hasEventListener(InvokeEvent.INVOKE)) return true;
        invoked = true;
        var args:Array<Dynamic> = [for (a in Launch.arguments()) a];
        dispatchEvent(new InvokeEvent(InvokeEvent.INVOKE, false, false, args, new File(Launch.applicationDirectory())));
        return false;
    }

    public function exit(errorCode:Int = 0):Void {
        #if sys
        Sys.exit(errorCode);
        #end
    }
}
