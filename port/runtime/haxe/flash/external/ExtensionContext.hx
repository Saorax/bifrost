package flash.external;

import flash.events.EventDispatcher;
import flash.events.StatusEvent;
import port.runtime.services.Extensions;

class ExtensionContext extends EventDispatcher {
    public var actionScriptData:Dynamic = null;

    var impl:Null<ExtensionImpl> = null;

    public static function createExtensionContext(extensionID:String, contextType:String):ExtensionContext {
        var impl = Extensions.create(extensionID, contextType == null ? "" : contextType);
        return impl == null ? null : new ExtensionContext(impl);
    }

    public function new(impl:ExtensionImpl = null) {
        super();
        this.impl = impl;
        if (impl != null) impl.onStatus = (code, level) -> dispatchEvent(new StatusEvent(StatusEvent.STATUS, false, false, code, level));
    }

    public function call(functionName:String, ...args:Dynamic):Dynamic {
        if (impl == null) return null;
        return impl.call(functionName, args.toArray());
    }

    public function dispose():Void {
        if (impl != null) impl.dispose();
        impl = null;
    }
}
