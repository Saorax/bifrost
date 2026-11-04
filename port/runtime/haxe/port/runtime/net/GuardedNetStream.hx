package port.runtime.net;

#if flash
class GuardedNetStream extends flash.net.NetStream {
    public function new(connection:flash.net.NetConnection, ?peerID:String) {
        super(connection, peerID == null ? "connectToFMS" : peerID);
    }

    override public function play(restArgs:haxe.extern.Rest<Dynamic>):Void {
        var url:Dynamic = restArgs.length > 0 ? restArgs[0] : null;
        if (Std.isOfType(url, String) && !NetGuard.allowUrl(url)) {
            NetGuard.refuse("video " + url);
            return;
        }
        super.play(...restArgs);
    }
}
#end
