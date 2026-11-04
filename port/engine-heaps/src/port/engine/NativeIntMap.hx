package port.engine;

class NativeIntMap<T> {
	var h:hl.types.IntMap;

	public function new() {
		h = new hl.types.IntMap();
	}

	public inline function get(key:Int):Null<T> {
		return h.get(key);
	}

	public inline function set(key:Int, value:T):Void {
		h.set(key, value);
	}

	public inline function exists(key:Int):Bool {
		return h.exists(key);
	}

	public inline function remove(key:Int):Bool {
		return h.remove(key);
	}

	public function iterator():Iterator<T> {
		var values = h.valuesArray();
		var i = 0;
		return {
			hasNext: () -> i < values.length,
			next: () -> (values[i++] : T)
		};
	}
}
