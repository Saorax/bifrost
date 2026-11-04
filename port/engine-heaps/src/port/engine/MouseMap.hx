package port.engine;

class MouseMap<T> {
	static var DOWN = ["mouseDown", "rightMouseDown", "middleMouseDown"];
	static var UP = ["mouseUp", "rightMouseUp", "middleMouseUp"];
	static var CLICK = ["click", "rightClick", "middleClick"];

	var pressed:Array<Null<T>> = [null, null, null];
	var over:Null<T> = null;
	var overChain:Array<T> = [];

	public function new() {}

	public function press(button:Int, target:Null<T>):Array<{type:String, target:T}> {
		pressed[button] = target;
		return target == null ? [] : [{type: DOWN[button], target: target}];
	}

	public function release(button:Int, target:Null<T>):Array<{type:String, target:T}> {
		var out = target == null ? [] : [{type: UP[button], target: target}];
		if (target != null && pressed[button] == target) out.push({type: CLICK[button], target: target});
		pressed[button] = null;
		return out;
	}

	public function move(target:Null<T>, chain:Array<T>):Array<{type:String, target:T}> {
		var out:Array<{type:String, target:T}> = [];
		if (target != over) {
			if (over != null) out.push({type: "mouseOut", target: over});
			var i = overChain.length;
			while (i-- > 0) if (chain.indexOf(overChain[i]) < 0) out.push({type: "rollOut", target: overChain[i]});
			for (o in chain) if (overChain.indexOf(o) < 0) out.push({type: "rollOver", target: o});
			if (target != null) out.push({type: "mouseOver", target: target});
			over = target;
			overChain = chain.copy();
		}
		if (target != null) out.push({type: "mouseMove", target: target});
		return out;
	}

	public function wheel(target:Null<T>):Array<{type:String, target:T}> {
		return target == null ? [] : [{type: "mouseWheel", target: target}];
	}
}
