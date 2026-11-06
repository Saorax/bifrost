package flash.display;

@:access(flash.display.Timeline)
class MovieClip extends flash.display.Sprite {
	public static function fromTimeline(timeline:flash.display.Timeline):flash.display.MovieClip {
		var movieClip = new MovieClip();
		movieClip.attachTimeline(timeline);
		return movieClip;
	}

	public var currentFrame(get, never):Int;
	public var currentFrameLabel(get, never):String;
	public var currentLabel(get, never):String;
	public var currentLabels(get, never):Array<flash.display.FrameLabel>;
	public var currentScene(get, never):flash.display.Scene;
	public var enabled:Bool = true;
	public var framesLoaded(get, never):Int;
	public var isPlaying(get, never):Bool;
	public var scenes(get, never):Array<flash.display.Scene>;
	public var totalFrames(get, never):Int;

	@:noCompletion var __timeline:flash.display.Timeline;
	@:noCompletion var __scene:flash.display.Scene;

	public function addFrameScript(index:Int, method:() -> Void):Void {
		if (__timeline != null) __timeline.__addFrameScript(index, method);
	}

	public function attachTimeline(timeline:flash.display.Timeline):Void {
		__timeline = timeline;
		if (timeline != null) {
			timeline.__attachMovieClip(this);
			play();
		}
	}

	public function gotoAndPlay(frame:Any, ?scene:String):Void {
		if (__timeline != null) __timeline.__gotoAndPlay(__frameReference(frame), scene);
	}

	public function gotoAndStop(frame:Any, ?scene:String):Void {
		if (__timeline != null) __timeline.__gotoAndStop(__frameReference(frame), scene);
	}

	@:noCompletion function __frameReference(frame:Any):Any {
		if (!(frame is String)) return frame;
		var label:String = cast frame;
		for (known in __timeline.__currentLabels) if (known.name == label) return frame;
		var number = Std.parseInt(label);
		return number != null && Std.string(number) == label ? number : frame;
	}

	public function nextFrame():Void {
		if (__timeline != null) __timeline.__nextFrame();
	}

	public function nextScene():Void {
		if (__timeline != null) __timeline.__nextScene();
	}

	public function play():Void {
		if (__timeline != null) __timeline.__play();
	}

	public function prevFrame():Void {
		if (__timeline != null) __timeline.__prevFrame();
	}

	public function prevScene():Void {
		if (__timeline != null) __timeline.__prevScene();
	}

	public function stop():Void {
		if (__timeline != null) __timeline.__stop();
	}

	override public function stopAllMovieClips():Void {
		super.stopAllMovieClips();
		stop();
	}

	@:noCompletion override function __advance(deltaTime:Int):Void {
		if (__timeline != null) __timeline.__enterFrame(deltaTime);
		super.__advance(deltaTime);
	}

	function get_currentFrame():Int return __timeline != null ? __timeline.__currentFrame : 1;

	function get_currentFrameLabel():String return __timeline != null ? __timeline.__currentFrameLabel : null;

	function get_currentLabel():String return __timeline != null ? __timeline.__currentLabel : null;

	function get_currentLabels():Array<flash.display.FrameLabel> return __timeline != null ? __timeline.__currentLabels.copy() : [];

	function get_currentScene():flash.display.Scene {
		if (__timeline != null) return __timeline.__currentScene;
		if (__scene == null) __scene = new flash.display.Scene("", [], 1);
		return __scene;
	}

	function get_framesLoaded():Int return __timeline != null ? __timeline.__framesLoaded : 1;

	function get_isPlaying():Bool return __timeline != null ? __timeline.__isPlaying : false;

	function get_scenes():Array<flash.display.Scene> return __timeline != null ? __timeline.scenes.copy() : [currentScene];

	function get_totalFrames():Int return __timeline != null ? __timeline.__totalFrames : 1;

	public function new() {
		super();
	}
}
