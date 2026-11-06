package port.engine;

class WindowInput {
	var stage:flash.display.Stage;
	var mouse = new MouseMap<flash.events.EventDispatcher>();
	var buttonsDown = 0;
	var repeatOf = -1;

	public static var logInput(default, null) = Sys.getEnv("BH_PORT_INPUT_LOG") == "1";
	static var functionKeysLogged = 0;

	static function name(o:Dynamic):String {
		if (o == null) return "nothing";
		var d = Std.downcast(o, flash.display.DisplayObject);
		var cls = Type.getClassName(Type.getClass(o));
		return d != null && d.name != null && d.name != "" ? cls + ":" + d.name : cls;
	}

	static function log(line:String):Void {
		BootLog.log("input: " + line);
	}

	public function new(stage:flash.display.Stage) {
		this.stage = stage;
		active(try hxd.Window.getInstance().isFocused catch (_:Dynamic) true);
		stage.__onMouse = function(type:String, x:Float, y:Float, button:Int) {
			var e = new hxd.Event(type == "mouseDown" ? EPush : type == "mouseUp" ? ERelease : EMove, x, y);
			e.button = button;
			onEvent(e);
		};
	}

	function under(x:Float, y:Float):Array<flash.display.DisplayObject> {
		var stack = stage.__mouseStack(x, y);
		return stack.length > 0 ? stack : [stage];
	}

	function target(x:Float, y:Float):flash.events.EventDispatcher {
		var chain = under(x, y);
		return chain[chain.length - 1];
	}

	function mouseFocus(target:flash.display.InteractiveObject):Void {
		if (stage.focus == target) return;
		if (stage.focus != null) {
			var event = new flash.events.FocusEvent(flash.events.FocusEvent.MOUSE_FOCUS_CHANGE, true, true, target);
			stage.focus.dispatchEvent(event);
			if (event.isDefaultPrevented()) return;
		}
		stage.focus = target != null && target.__allowMouseFocus() ? target : null;
	}

	var pendingBare:hxd.Event = null;

	var held = 0;

	function modifierBit(code:Int):Int {
		return switch (code & 0xFF) {
			case hxd.Key.CTRL: 1;
			case hxd.Key.ALT: 2;
			case hxd.Key.SHIFT: 4;
			default: 0;
		}
	}

	public function onEvent(e:hxd.Event):Void {
		if (e.kind == EFocusLost) held = 0;
		if (e.kind == EKeyDown || e.kind == EKeyUp) {
			var code = e.keyCode;
			var bit = modifierBit(code);
			if (bit != 0) held = e.kind == EKeyDown ? held | bit : held & ~bit;
			if (code == hxd.Key.SHIFT || code == hxd.Key.CTRL || code == hxd.Key.ALT) {
				flush();
				pendingBare = e;
				return;
			}
			if (pendingBare != null && pendingBare.kind == e.kind && pendingBare.keyCode == code & 0xFF
				&& code & (hxd.Key.LOC_LEFT | hxd.Key.LOC_RIGHT) != 0)
				pendingBare = null;
		}
		flush();
		handle(e);
	}

	public function flush():Void {
		if (pendingBare == null) return;
		var held = pendingBare;
		pendingBare = null;
		handle(held);
	}

	function handle(e:hxd.Event):Void {
		if (e.kind == EKeyDown && repeatOf != e.keyCode) InputTiming.keyDown(haxe.Timer.stamp());
		try {
			dispatch(e);
		} catch (error:Dynamic) {
			if (FrameLoop.onError == null) throw error;
			FrameLoop.onError(error, haxe.CallStack.toString(haxe.CallStack.exceptionStack()), "window input");
		}
	}

	function dispatch(e:hxd.Event):Void {
		flash.display.DisplayObject.__pointerX = e.relX;
		flash.display.DisplayObject.__pointerY = e.relY;
		var ctrl = held & 1 != 0 || hxd.Key.isDown(hxd.Key.CTRL);
		var alt = held & 2 != 0 || hxd.Key.isDown(hxd.Key.ALT);
		var shift = held & 4 != 0 || hxd.Key.isDown(hxd.Key.SHIFT);
		switch (e.kind) {
			case EKeyDown | EKeyUp:
				var type = e.kind == EKeyDown ? flash.events.KeyboardEvent.KEY_DOWN : flash.events.KeyboardEvent.KEY_UP;
				var event = new flash.events.KeyboardEvent(type, true, false, KeyMap.charCode(e.keyCode, shift),
					KeyMap.keyCode(e.keyCode), cast KeyMap.keyLocation(e.keyCode), ctrl, alt, shift, ctrl, false);
				var target:flash.events.EventDispatcher = stage.focus != null ? stage.focus : stage;
				var fn = KeyMap.keyCode(e.keyCode);
				if (!logInput && e.kind == EKeyDown && repeatOf != e.keyCode && fn >= 112 && fn <= 123 && functionKeysLogged++ < 60)
					log("F" + (fn - 111) + (ctrl ? " ctrl" : "") + (alt ? " alt" : "") + (shift ? " shift" : "") + " (heaps " + e.keyCode + ")");
				if (logInput && !(e.kind == EKeyDown && repeatOf == e.keyCode))
					log(type + " keyCode " + KeyMap.keyCode(e.keyCode) + " (heaps " + e.keyCode + ")"
						+ (ctrl ? " ctrl" : "") + (alt ? " alt" : "") + (shift ? " shift" : "") + " at " + name(target));
				repeatOf = e.kind == EKeyDown ? e.keyCode : -1;
				target.dispatchEvent(event);
				var field = Std.downcast(stage.focus, flash.text.TextField);
				if (field != null && e.kind == EKeyDown) field.__portKeyDown(KeyMap.keyCode(e.keyCode), ctrl, shift);
			case ETextInput:
				var field = Std.downcast(stage.focus, flash.text.TextField);
				if (field != null && !(ctrl && !alt)) field.__portTextInput(String.fromCharCode(e.charCode));
			case EPush:
				if (e.button >= 0 && e.button < 3) {
					buttonsDown |= 1 << e.button;
					var at = target(e.relX, e.relY);
					if (logInput) log("mouseDown button " + e.button + " at " + Math.round(e.relX) + "," + Math.round(e.relY)
						+ " on " + name(at));
					if (e.button == 0) mouseFocus(cast at);
					send(mouse.press(e.button, at), e, 0, ctrl, alt, shift);
					var field = Std.downcast(at, flash.text.TextField);
					if (e.button == 0 && field != null && stage.focus == field && field.__toLocal(e.relX, e.relY))
						field.__portMouseDown(@:privateAccess flash.display.DisplayObject.__hx, @:privateAccess flash.display.DisplayObject.__hy);
				}
			case ERelease | EReleaseOutside:
				if (e.button >= 0 && e.button < 3) {
					buttonsDown &= ~(1 << e.button);
					if (logInput) log("mouseUp button " + e.button + (e.kind == ERelease ? "" : " outside the window"));
					send(mouse.release(e.button, e.kind == ERelease ? target(e.relX, e.relY) : null), e, 0, ctrl, alt, shift);
				}
			case EMove:
				var chain = under(e.relX, e.relY);
				stage.__mouseOverTarget = chain[chain.length - 1];
				var targets:Array<flash.events.EventDispatcher> = cast chain;
				send(mouse.move(targets[targets.length - 1], targets), e, 0, ctrl, alt, shift);
			case EWheel:
				var at = target(e.relX, e.relY);
				var delta = Math.round(-e.wheelDelta * 3);
				if (logInput) log("wheel delta " + delta + " on " + name(at));
				send(mouse.wheel(at), e, delta, ctrl, alt, shift);
				var field = Std.downcast(at, flash.text.TextField);
				if (field != null) field.__portWheel(delta);
			case EFocus:
				active(true);
			case EFocusLost:
				active(false);
			default:
		}
	}

	public function active(on:Bool):Void {
		var window:Dynamic = stage.nativeWindow != null ? stage.nativeWindow : stage;
		flash.desktop.NativeApplication.nativeApplication.activeWindow = on ? window : null;
	}

	function send(events:Array<{type:String, target:flash.events.EventDispatcher}>, e:hxd.Event, delta:Int, ctrl:Bool,
			alt:Bool, shift:Bool):Void {
		for (item in events) {
			var lx = e.relX, ly = e.relY;
			var o = Std.downcast(item.target, flash.display.DisplayObject);
			if (o != null && o.__toLocal(e.relX, e.relY)) {
				lx = @:privateAccess flash.display.DisplayObject.__hx;
				ly = @:privateAccess flash.display.DisplayObject.__hy;
			}
			var event = new flash.events.MouseEvent(item.type, item.type != "rollOver" && item.type != "rollOut", false,
				lx, ly, null, ctrl, alt, shift, buttonsDown & 1 != 0, delta);
			event.stageX = e.relX;
			event.stageY = e.relY;
			item.target.dispatchEvent(event);
		}
	}
}
