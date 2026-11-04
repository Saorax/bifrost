package flash.display;

class Stage3D extends flash.events.EventDispatcher {
	public var context3D:flash.display3D.Context3D;
	public var visible:Bool = true;
	public var x:Float = 0;
	public var y:Float = 0;

	var stage:flash.display.Stage;
	var pending = false;

	public function requestContext3D(?context3DRenderMode:flash.display3D.Context3DRenderMode, ?profile:flash.display3D.Context3DProfile):Void {
		if (pending || (context3D != null && context3D.driverInfo != "Disposed")) return;
		pending = true;
		var chosen:flash.display3D.Context3DProfile = profile != null ? profile : flash.display3D.Context3DProfile.BASELINE;
		var wait = contextDelay;
		port.runtime.services.Pump.add(function() {
			if (wait-- > 0) return true;
			pending = false;
			context3D = new flash.display3D.Context3D(stage, null, this);
			context3D.profile = chosen;
			context3D.maxBackBufferWidth = context3D.maxBackBufferHeight = maxBackBuffer(chosen);
			dispatchEvent(new flash.events.Event(flash.events.Event.CONTEXT3D_CREATE));
			return false;
		});
	}

	public function requestContext3DMatchingProfiles(profiles:openfl.Vector<flash.display3D.Context3DProfile>):Void {
		requestContext3D(null, profiles != null && profiles.length > 0 ? profiles[0] : null);
	}

	static var contextDelay:Int = {
		var v = Std.parseInt(Sys.getEnv("BH_PORT_CONTEXT_DELAY"));
		v == null ? 0 : v;
	};

	static function maxBackBuffer(profile:flash.display3D.Context3DProfile):Int {
		return switch (profile) {
			case BASELINE | BASELINE_CONSTRAINED | BASELINE_EXTENDED: 2048;
			default: 4096;
		}
	}

	public function new(stage:flash.display.Stage) {
		super();
		this.stage = stage;
	}
}
