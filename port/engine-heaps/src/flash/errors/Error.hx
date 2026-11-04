package flash.errors;

class Error extends haxe.Exception {
	public var errorID(default, null):Int;
	public var name:String;

	public function new(message:String = "", id:Int = 0) {
		super(message);
		this.errorID = id;
		name = "Error";
		if (traceAll) port.engine.BootLog.log("error made: " + Type.getClassName(Type.getClass(this)) + " " + message
			+ haxe.CallStack.toString(haxe.CallStack.callStack()));
	}

	static var traceAll = Sys.getEnv("BH_PORT_TRACE_ERRORS") == "1";

	public function getStackTrace():String {
		return name + (message != null && message != "" ? ": " + message : "")
			+ haxe.CallStack.toString(haxe.CallStack.exceptionStack());
	}

	override public function toString():String {
		return message != null ? message : "Error";
	}
}
