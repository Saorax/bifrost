package port.engine;

class GpuAdapter {
	public static var result(default, null):Null<Int> = null;

	#if (hldx && !dx12)
	@:hlNative("bhsound", "gpu_choose_adapter") static function chooseNative():Int return 0;

	@:hlNative("bhsound", "gpu_adapter_name") static function nameNative():hl.Bytes return null;
	#end

	public static function choose():Void {
		#if (hldx && !dx12)
		if (result != null) return;
		result = chooseNative();
		if (result != 0) Sys.println("[port] BH_PORT_ADAPTER=" + Sys.getEnv("BH_PORT_ADAPTER") + ": " + describe());
		#end
	}

	public static function describe():String {
		#if (hldx && !dx12)
		return switch (result) {
			case 1: @:privateAccess String.fromUCS2(nameNative());
			case -1: "no adapter matched (default adapter)";
			case -2: "the import hook failed (default adapter)";
			default: "default adapter";
		}
		#else
		return "default adapter";
		#end
	}
}
