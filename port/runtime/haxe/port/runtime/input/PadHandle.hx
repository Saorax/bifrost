package port.runtime.input;

class PadHandle {
	public var id(default, null):Int;
	public var name(default, null):String;

	public dynamic function onButton(button:String, down:Bool):Void {}

	public dynamic function onAxis(axis:String, value:Float):Void {}

	public dynamic function onDisconnect():Void {}

	public function new(id:Int, name:String) {
		this.id = id;
		this.name = name;
	}
}
