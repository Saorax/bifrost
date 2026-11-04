package openfl.net;

class NetConnection extends flash.events.EventDispatcher {
	public static var CONNECT_SUCCESS:String = "NetConnection.Connect.Success";

	public function connect(command:String, ?p1:Dynamic, ?p2:Dynamic, ?p3:Dynamic, ?p4:Dynamic, ?p5:Dynamic):Void {
		if (command != null) throw "Error: Can only connect in \"HTTP streaming\" mode";
		dispatchEvent(new flash.events.NetStatusEvent(flash.events.NetStatusEvent.NET_STATUS, false, true,
			{code: CONNECT_SUCCESS, level: "status"}));
	}

	public function new() {
		super();
	}
}
