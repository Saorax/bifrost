package flash.net;

@:forward
@:forward.new
abstract NetConnection(openfl.net.NetConnection) from openfl.net.NetConnection to openfl.net.NetConnection
      to openfl.events.EventDispatcher {
   public inline function close():Void {}
}
