class AgalSpike extends hxd.App {
	static var exp = {
		var v = Sys.getEnv("BH_AGAL_SPIKE_EXP");
		v == null ? "" : v;
	};

	var frames = 0;
	var probe:port.engine.GpuProbe;

	override function init() {
		probe = new port.engine.GpuProbe();
		Sys.println('driver ${Type.getClassName(Type.getClass(engine.driver))}, exp "$exp"');
	}

	override function render(e:h3d.Engine) {
		frames++;
		var window = hxd.Window.getInstance();
		if (frames == 1 && exp.indexOf("borderless") >= 0) window.displayMode = Borderless;
		if (frames == 1 && exp.indexOf("vsync") >= 0) window.vsync = true;
		if (frames == 1 && exp.indexOf("resize") >= 0) window.resize(1280, 720);
		probe.draw(e);
		if (frames == 120) {
			Sys.println("120 frames drawn");
			hxd.System.exit();
		}
	}

	static function main() {
		new AgalSpike();
	}
}
