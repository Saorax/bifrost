package flash.display;

class InteractiveObject extends flash.display.DisplayObject {
	public var doubleClickEnabled:Bool = false;
	public var focusRect:Null<Bool>;
	public var mouseEnabled:Bool = true;
	public var needsSoftKeyboard:Bool = false;
	public var softKeyboardInputAreaOfInterest:flash.geom.Rectangle;
	public var tabEnabled(get, set):Bool;
	@:noCompletion var __tabEnabled:Null<Bool>;
	public var tabIndex:Int = -1;

	public function requestSoftKeyboard():Bool {
		return false;
	}

	function get_tabEnabled():Bool {
		return __tabEnabled != null ? __tabEnabled : __tabDefault();
	}

	function set_tabEnabled(value:Bool):Bool {
		__tabEnabled = value;
		return value;
	}

	@:noCompletion function __tabDefault():Bool {
		return false;
	}

	@:noCompletion public function __allowMouseFocus():Bool {
		return mouseEnabled && tabEnabled;
	}

	@:noCompletion override public function __interactive():Bool {
		return true;
	}

	public function new() {
		super();
	}
}
