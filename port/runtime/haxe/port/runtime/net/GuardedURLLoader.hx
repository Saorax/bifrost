package port.runtime.net;

#if flash
typedef GuardedRequest = flash.net.URLRequest;
#else
typedef GuardedRequest = openfl.net.URLRequest;
#end

class GuardedURLLoader extends #if flash flash.net.URLLoader #else openfl.net.URLLoader #end {
    public function new() {
        super();
    }

    override public function load(request:GuardedRequest):Void {
        if (request == null || NetGuard.allowUrl(request.url)) {
            #if (hl && port_trace_net)
            var url = request == null ? "null" : request.url;
            if (NetGuard.log != null) {
                NetGuard.log("HTTP local load " + url);
                addEventListener("complete", function(_) NetGuard.log("HTTP local complete " + url));
                addEventListener("ioError", function(e) NetGuard.log("HTTP local ioError " + url + ": " + e));
            }
            #end
            super.load(request);
            return;
        }
        NetGuard.refuse("HTTP " + request.url);
        haxe.Timer.delay(function() {
            dispatchEvent(new #if flash flash.events.IOErrorEvent #else openfl.events.IOErrorEvent #end(
                "ioError", false, false, "Error #2032: refused by the port's network guard", 2032));
        }, 0);
    }
}
