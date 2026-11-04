package haxe.ds;

#if macro
extern class ObjectMap<K:{}, V> implements haxe.Constraints.IMap<K, V> {
	function new():Void;
	function set(key:K, value:V):Void;
	function get(key:K):Null<V>;
	function exists(key:K):Bool;
	function remove(key:K):Bool;
	function keys():Iterator<K>;
	function iterator():Iterator<V>;
	#if eval
	@:runtime inline function keyValueIterator():KeyValueIterator<K, V> {
		return new haxe.iterators.MapKeyValueIterator(this);
	}
	#else
	function keyValueIterator():KeyValueIterator<K, V>;
	#end
	function copy():ObjectMap<K, V>;
	function toString():String;
	function clear():Void;
}
#else
class ObjectMap<K:{}, V> extends flash.utils.Dictionary implements haxe.Constraints.IMap<K, V> {
	public function new() {
		super(false);
	}

	public function get(key:K):Null<V> {
		return untyped this[key];
	}

	public function set(key:K, value:V):Void {
		untyped this[key] = value;
	}

	public function method_4935(key:Dynamic):Null<V> {
		return untyped this[key];
	}

	public function method_65(key:Dynamic, value:V):Void {
		untyped this[key] = value;
	}

	public function exists(key:K):Bool {
		return untyped this[key] != null;
	}

	public function remove(key:K):Bool {
		var has = exists(key);
		untyped __delete__(this, key);
		return has;
	}

	public function keys():Iterator<K> {
		return NativePropertyIterator.iterator(this);
	}

	public function iterator():Iterator<V> {
		return NativeValueIterator.iterator(this);
	}

	public inline function keyValueIterator():KeyValueIterator<K, V> {
		return new haxe.iterators.MapKeyValueIterator(this);
	}

	public function copy():ObjectMap<K, V> {
		var copied = new ObjectMap();
		for (key in keys())
			copied.set(key, get(key));
		return copied;
	}

	public function toString():String {
		var s = "[";
		var it = keys();
		for (i in it) {
			s += (s == "[" ? "" : ", ") + Std.string(i) + " => " + Std.string(get(i));
		}
		return s + "]";
	}

	public function clear():Void {
		for (i in keys())
			untyped __delete__(this, i);
	}
}

private class NativePropertyIterator {
	var collection:Dynamic;
	var index:Int = 0;

	public static inline function iterator(collection:Dynamic):NativePropertyIterator {
		var result = new NativePropertyIterator();
		result.collection = collection;
		return result;
	}

	function new() {}

	public inline function hasNext():Bool {
		var c = collection;
		var i = index;
		var result = untyped __has_next__(c, i);
		collection = c;
		index = i;
		return result;
	}

	public inline function next():Dynamic {
		var i = index;
		var result = untyped __forin__(collection, i);
		index = i;
		return result;
	}
}

private class NativeValueIterator {
	var collection:Dynamic;
	var index:Int = 0;

	public static inline function iterator(collection:Dynamic):NativeValueIterator {
		var result = new NativeValueIterator();
		result.collection = collection;
		return result;
	}

	function new() {}

	public inline function hasNext():Bool {
		var c = collection;
		var i = index;
		var result = untyped __has_next__(c, i);
		collection = c;
		index = i;
		return result;
	}

	public inline function next():Dynamic {
		var i = index;
		var result = untyped __foreach__(collection, i);
		index = i;
		return result;
	}
}
#end
