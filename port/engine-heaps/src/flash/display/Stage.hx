package flash.display;

class Stage extends flash.display.DisplayObjectContainer {
	public static var supportsOrientationChange:Bool;
	public var autoOrients:Bool;
	public var align:flash.display.StageAlign;
	public var allowsFullScreen:Bool = true;
	public var allowsFullScreenInteractive:Bool = true;
	public var application:Dynamic;
	public var color:Null<Int>;
	public var contentsScaleFactor:Float = 1;
	public var context3D:flash.display3D.Context3D;
	public var deviceOrientation:flash.display.StageOrientation;
	public var displayState(default, set):flash.display.StageDisplayState = NORMAL;
	public var focus(get, set):flash.display.InteractiveObject;
	@:noCompletion var __focus:flash.display.InteractiveObject;
	public var frameRate(default, set):Float = 60;
	public var fullScreenHeight:UInt;
	public var fullScreenSourceRect:flash.geom.Rectangle;
	public var fullScreenWidth:UInt;
	public var orientation:flash.display.StageOrientation;
	public var quality:flash.display.StageQuality;
	public var scaleMode:flash.display.StageScaleMode;
	public var showDefaultContextMenu:Bool = true;
	public var softKeyboardRect:flash.geom.Rectangle;
	public var stage3Ds:openfl.Vector<flash.display.Stage3D>;
	public var stageFocusRect:Bool = true;
	public var stageHeight(default, null):Int = 0;
	public var stageWidth(default, null):Int = 0;
	public var supportedOrientations:openfl.Vector<flash.display.StageOrientation>;
	public var window:Dynamic;
	public var nativeWindow:flash.display.NativeWindow;

	@:noCompletion public dynamic function __onMouse(type:String, x:Float, y:Float, button:Int):Void {}

	@:noCompletion public var __mouseOverTarget:flash.display.DisplayObject;

	public dynamic function onDisplayState(state:flash.display.StageDisplayState):Void {}

	public function setOrientation(newOrientation:flash.display.StageOrientation):Void {}

	public function new(window:Dynamic, ?color:Int) {
		super();
		this.window = window;
		this.color = color;
		this.stage = this;
		name = null;
		stage3Ds = [for (_ in 0...4) new flash.display.Stage3D(this)];
	}

	public function resized(width:Int, height:Int):Void {
		if (width == stageWidth && height == stageHeight) return;
		stageWidth = width;
		stageHeight = height;
		if (scaleMode == NO_SCALE) dispatchEvent(new flash.events.Event(flash.events.Event.RESIZE));
	}

	override public function invalidate():Void {
		port.engine.FrameLoop.invalidate();
	}

	function get_focus():flash.display.InteractiveObject {
		if (__focus != null && __focus.stage == null) __focus = null;
		return __focus;
	}

	function set_focus(value:flash.display.InteractiveObject):flash.display.InteractiveObject {
		if (value != __focus) {
			var old = __focus;
			__focus = value;
			if (old != null) old.dispatchEvent(new flash.events.FocusEvent(flash.events.FocusEvent.FOCUS_OUT, true, false, value));
			if (value != null) value.dispatchEvent(new flash.events.FocusEvent(flash.events.FocusEvent.FOCUS_IN, true, false, old));
		}
		return value;
	}

	function set_frameRate(value:Float):Float {
		if (Math.isNaN(value)) return frameRate;
		return frameRate = value < 0.01 ? 0.01 : value > 1000 ? 1000 : value;
	}

	function set_displayState(value:flash.display.StageDisplayState):flash.display.StageDisplayState {
		if (value == null) value = NORMAL;
		if (value != displayState) {
			displayState = value;
			onDisplayState(value);
		}
		return value;
	}
}
