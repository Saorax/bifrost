package port.runtime.net;

class GuardedSocket extends flash.net.Socket {
    public function new() {
        super();
    }

    override public function connect(host:String, port:Int):Void {
        if (NetGuard.allowHost(host, port)) {
            super.connect(host, port);
            return;
        }
        NetGuard.refuse("TCP " + host + ":" + port);
        haxe.Timer.delay(function() {
            dispatchEvent(new flash.events.IOErrorEvent("ioError", false, false,
                "Error #2031: refused by the port's network guard", 2031));
        }, 0);
    }
}
