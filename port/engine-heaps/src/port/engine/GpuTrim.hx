package port.engine;

class GpuTrim {
	static var enabled = Sys.getEnv("BH_PORT_GPU_TRIM") == "1";
	static var pending = false;

	public static var trims(default, null) = 0;
	public static var trimMs(default, null) = 0.0;

	public static function request():Void {
		if (enabled) pending = true;
	}

	public static function run(e:h3d.Engine):Void {
		if (!pending) return;
		pending = false;
		#if (hldx && !dx12)
		var driver = Std.downcast(e.driver, h3d.impl.DirectXDriver);
		if (driver == null) return;
		var t0 = haxe.Timer.stamp();
		if (@:privateAccess driver.portTrim() > 0) trims++;
		trimMs += (haxe.Timer.stamp() - t0) * 1000;
		#end
	}
}
