package flash.media;

class SoundChannel extends flash.events.EventDispatcher {
	public var leftPeak(default, null):Float = 0;
	public var rightPeak(default, null):Float = 0;
	public var soundTransform(get, set):SoundTransform;
	public var position(get, never):Float;

	var transform:SoundTransform;
	var channel:hxd.snd.Channel;
	var res:hxd.res.Sound;
	var loopsLeft:Int;
	var started:Float;
	var startTime:Float;
	var stopped:Float = -1;

	public function new(?res:hxd.res.Sound, startTime:Float = 0, loops:Int = 0, ?transform:SoundTransform) {
		super();
		this.res = res;
		this.startTime = startTime;
		this.transform = transform != null ? transform : new SoundTransform();
		started = haxe.Timer.stamp();
		loopsLeft = loops;
		if (res != null) start(startTime);
	}

	function start(at:Float):Void {
		channel = hxd.snd.Manager.get().play(res);
		channel.loop = loopsLeft >= 1000;
		channel.volume = transform.volume;
		if (at > 0) channel.position = at / 1000;
		channel.onEnd = ended;
	}

	function ended():Void {
		if (stopped >= 0) return;
		if (loopsLeft > 0 && !channel.loop) {
			loopsLeft--;
			start(0);
			return;
		}
		channel = null;
		stopped = haxe.Timer.stamp();
		dispatchEvent(new flash.events.Event(flash.events.Event.SOUND_COMPLETE));
	}

	function get_position():Float {
		if (channel != null) return channel.position * 1000;
		var end = stopped >= 0 ? stopped : haxe.Timer.stamp();
		return startTime + (end - started) * 1000;
	}

	function get_soundTransform():SoundTransform {
		return transform;
	}

	function set_soundTransform(t:SoundTransform):SoundTransform {
		transform = t != null ? t : new SoundTransform();
		if (channel != null) channel.volume = transform.volume;
		return transform;
	}

	public function stop():Void {
		if (stopped < 0) stopped = haxe.Timer.stamp();
		if (channel != null) {
			channel.stop();
			channel = null;
		}
	}
}
