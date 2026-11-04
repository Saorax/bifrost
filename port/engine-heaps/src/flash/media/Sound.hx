package flash.media;

class Sound extends flash.events.EventDispatcher {
	public var bytesLoaded(default, null):Int = 0;
	public var bytesTotal(default, null):Int = 0;
	public var isBuffering(default, null):Bool = false;
	public var length(get, never):Float;
	public var url(default, null):String;

	var res:hxd.res.Sound;

	public function new(?stream:flash.net.URLRequest, ?context:Dynamic) {
		super();
		if (stream != null) load(stream, context);
	}

	static function pathOf(url:String):String {
		return StringTools.startsWith(url, "file:///") ? StringTools.urlDecode(url.substr(8)) : url;
	}

	public function load(stream:flash.net.URLRequest, ?context:Dynamic):Void {
		url = stream.url;
		var error:String = null;
		try {
			var bytes = sys.io.File.getBytes(pathOf(url));
			bytesLoaded = bytesTotal = bytes.length;
			res = hxd.res.Any.fromBytes(pathOf(url), bytes).toSound();
			res.getData();
		} catch (e:Dynamic) {
			res = null;
			error = "Error #2032: Stream Error. URL: " + url + " (" + Std.string(e) + ")";
		}
		port.runtime.services.Pump.add(function() {
			if (error != null) {
				var event = new flash.events.IOErrorEvent(flash.events.IOErrorEvent.IO_ERROR);
				event.text = error;
				dispatchEvent(event);
			} else {
				dispatchEvent(new flash.events.Event(flash.events.Event.COMPLETE));
			}
			return false;
		});
	}

	function get_length():Float {
		return res == null ? 0 : res.getData().duration * 1000;
	}

	public function close():Void {}

	public function play(startTime:Float = 0, loops:Int = 0, ?sndTransform:SoundTransform):SoundChannel {
		if (traced()) port.engine.BootLog.log("sound: play " + url + (res == null ? " (not loaded: silent)"
			: " (" + Math.round(length) + " ms, loops " + loops + ", volume "
				+ (sndTransform != null ? sndTransform.volume : 1) + ")"));
		return new SoundChannel(res, startTime, loops, sndTransform);
	}

	static var traceState = -1;

	static function traced():Bool {
		if (traceState < 0) traceState = Sys.getEnv("BH_PORT_TRACE_SOUND") == "1" ? 1 : 0;
		return traceState == 1;
	}
}
