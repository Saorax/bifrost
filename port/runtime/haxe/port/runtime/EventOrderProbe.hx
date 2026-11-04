package port.runtime;

private typedef PxSprite = #if (flash || !openfl) flash.display.Sprite #else openfl.display.Sprite #end;
private typedef PxEvent = #if (flash || !openfl) flash.events.Event #else openfl.events.Event #end;
private typedef PxDispatcher = #if (flash || !openfl) flash.events.EventDispatcher #else openfl.events.EventDispatcher #end;

class EventOrderProbe {
	public var lines(default, null):Array<String> = [];

	var stage:PxDispatcher;
	var root:PxSprite;
	var a:PxSprite;
	var b:PxSprite;
	var off:PxSprite;
	var frame = 0;

	public function new(stage:Dynamic) {
		this.stage = stage;
		root = named("root");
		a = named("a");
		b = named("b");
		off = named("off");
		(stage : Dynamic).addChild(root);
		root.addChild(a);
		a.addChild(b);
	}

	static function named(name:String):PxSprite {
		var s = new PxSprite();
		s.name = name;
		return s;
	}

	function nameOf(target:Dynamic):String {
		if (target == null) return "null";
		if (target == stage) return "stage";
		return Std.string(Reflect.getProperty(target, "name"));
	}

	function note(text:String):Void {
		lines.push(text);
	}

	function listener(tag:String, ?then:PxEvent->Void):Dynamic {
		return function(e:PxEvent) {
			note(tag + " phase=" + e.eventPhase + " current=" + nameOf(e.currentTarget) + " target=" + nameOf(e.target));
			if (then != null) then(e);
		};
	}

	function clear(type:String, added:Array<{node:Dynamic, f:Dynamic, capture:Bool}>):Void {
		for (item in added) (item.node : PxDispatcher).removeEventListener(type, item.f, item.capture);
	}

	public function dispatchCases():Void {
		var added:Array<{node:Dynamic, f:Dynamic, capture:Bool}> = [];
		function on(node:Dynamic, type:String, f:Dynamic, capture:Bool = false, priority:Int = 0) {
			(node : PxDispatcher).addEventListener(type, f, capture, priority, false);
			added.push({node: node, f: f, capture: capture});
		}

		note("case 1: phases and priorities");
		on(stage, "probe", listener("stage capture"), true);
		on(root, "probe", listener("root capture"), true);
		on(a, "probe", listener("a capture p0"), true, 0);
		on(a, "probe", listener("a capture p5"), true, 5);
		on(b, "probe", listener("b capture-on-target"), true);
		on(b, "probe", listener("b target first p0"));
		on(b, "probe", listener("b target second p0"));
		on(b, "probe", listener("b target p10"), false, 10);
		on(a, "probe", listener("a bubble"));
		on(root, "probe", listener("root bubble"));
		on(stage, "probe", listener("stage bubble"));
		note("returned " + b.dispatchEvent(new PxEvent("probe", true, false)));
		clear("probe", added);
		added = [];

		note("case 2: stopPropagation at a's capture");
		on(a, "probe", listener("a capture p5 stops", e -> e.stopPropagation()), true, 5);
		on(a, "probe", listener("a capture p0 (same node)"), true, 0);
		on(b, "probe", listener("b target"));
		on(root, "probe", listener("root bubble"));
		b.dispatchEvent(new PxEvent("probe", true, false));
		clear("probe", added);
		added = [];

		note("case 3: stopImmediatePropagation at b's first target listener");
		on(b, "probe", listener("b first stops immediately", e -> e.stopImmediatePropagation()));
		on(b, "probe", listener("b second"));
		on(a, "probe", listener("a bubble"));
		b.dispatchEvent(new PxEvent("probe", true, false));
		clear("probe", added);
		added = [];

		note("case 4: listeners added and removed during the dispatch");
		var late = listener("b added during dispatch");
		var lateUp = listener("root bubble added during dispatch");
		var removed = listener("b removed before its turn");
		on(b, "probe", listener("b first adds and removes", function(_) {
			(b : PxDispatcher).addEventListener("probe", late, false, 0, false);
			(root : PxDispatcher).addEventListener("probe", lateUp, false, 0, false);
			(b : PxDispatcher).removeEventListener("probe", removed, false);
		}));
		on(b, "probe", removed);
		b.dispatchEvent(new PxEvent("probe", true, false));
		note("again");
		b.dispatchEvent(new PxEvent("probe", true, false));
		(b : PxDispatcher).removeEventListener("probe", late, false);
		(root : PxDispatcher).removeEventListener("probe", lateUp, false);
		clear("probe", added);
		added = [];

		note("case 5: a non-bubbling event");
		on(root, "probe", listener("root capture"), true);
		on(b, "probe", listener("b target"));
		on(a, "probe", listener("a bubble"));
		b.dispatchEvent(new PxEvent("probe", false, false));
		clear("probe", added);
		added = [];

		note("case 6: the same event dispatched again from a listener");
		var outer:PxEvent = new PxEvent("probe", true, false);
		var inner = false;
		on(a, "probe", listener("a bubble", function(e) {
			if (inner) return;
			inner = true;
			note("redispatch returns " + root.dispatchEvent(e) + ", same object " + (e == outer));
		}));
		on(root, "probe", listener("root bubble"));
		b.dispatchEvent(outer);
		clear("probe", added);
		added = [];

		note("case 7: added/addedToStage and removed/removedFromStage over a subtree (x > y), seen at x, y and root");
		var x = named("x"), y = named("y");
		x.addChild(y);
		for (node in ([x, y, root] : Array<Dynamic>))
			for (type in ["added", "addedToStage", "removed", "removedFromStage"])
				on(node, type, listener(nameOf(node) + " " + type));
		a.addChild(x);
		note("removing");
		a.removeChild(x);
		for (type in ["added", "addedToStage", "removed", "removedFromStage"]) clear(type, added);
	}

	var frameListeners:Array<{node:Dynamic, type:String, f:Dynamic}> = [];

	public function frameStep():Bool {
		frame++;
		if (frame == 1) {
			note("frames: enterFrame and exitFrame across objects (registered b, off, root, stage, a)");
			for (node in ([b, off, root, stage, a] : Array<Dynamic>)) {
				for (type in ["enterFrame", "exitFrame"]) {
					var tag = nameOf(node) + " " + type;
					var f:Dynamic = null;
					f = function(e:PxEvent) {
						note("frame " + frame + ": " + tag + " phase=" + e.eventPhase + " target=" + nameOf(e.target));
						if (type == "enterFrame" && node == root && frame == 2) {
							var extra:Dynamic = function(_) note("frame " + frame + ": a enterFrame added during enterFrame");
							(a : PxDispatcher).addEventListener("enterFrame", extra, false, 0, false);
							frameListeners.push({node: a, type: "enterFrame", f: extra});
						}
					};
					(node : PxDispatcher).addEventListener(type, f, false, 0, false);
					frameListeners.push({node: node, type: type, f: f});
				}
			}
			return false;
		}
		if (frame < 4) return false;
		for (item in frameListeners) (item.node : PxDispatcher).removeEventListener(item.type, item.f, false);
		(stage : Dynamic).removeChild(root);
		return true;
	}
}
