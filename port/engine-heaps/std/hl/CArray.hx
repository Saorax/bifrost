package hl;

abstract CArray<T>(Abstract<"hl_carray">) {
	public var length(get, never):Int;

	inline function get_length() return getLen(cast this);

	@:arrayAccess inline function get(index:Int):T {
		var slot = new hl.NativeArray<hl.Bytes>(1);
		slot[0] = elementBytes(cast this, index);
		var typed:hl.NativeArray<T> = cast slot;
		return typed[0];
	}

	static var strides:hl.types.IntMap;
	static var lengths:hl.types.IntMap;
	static var lock = new sys.thread.Mutex();

	static inline function bytesOf<V>(v:V):hl.Bytes {
		var slot = new hl.NativeArray<V>(1);
		slot[0] = v;
		var bytes:hl.NativeArray<hl.Bytes> = cast slot;
		return bytes[0];
	}

	public static function alloc<T>(cl:Class<T>, size:Int):CArray<T> {
		var t = (cast cl : BaseType).__type__;
		var arr = alloc_carray(t, size);
		var tb = bytesOf(t);
		var obj = hl.Bytes.fromAddress(haxe.Int64.make(tb.getI32(12), tb.getI32(8)));
		var rt = hl.Bytes.fromAddress(haxe.Int64.make(obj.getI32(76), obj.getI32(72)));
		var stride = rt.getI32(16);
		var key = keyOf(arr);
		lock.acquire();
		if (strides == null) {
			strides = new hl.types.IntMap();
			lengths = new hl.types.IntMap();
		}
		strides.set(key, stride);
		lengths.set(key, size);
		lock.release();
		return cast arr;
	}

	static inline function keyOf(arr:CArray<Dynamic>):Int {
		return bytesOf(arr).address().low;
	}

	static function elementBytes(arr:CArray<Dynamic>, index:Int):hl.Bytes {
		var b = bytesOf(arr);
		if (index == 0) return b;
		lock.acquire();
		var stride:Int = strides.get(keyOf(arr));
		lock.release();
		return b.offset(index * stride);
	}

	static function getLen(arr:CArray<Dynamic>):Int {
		lock.acquire();
		var n:Int = lengths == null ? 0 : lengths.get(keyOf(arr));
		lock.release();
		return n;
	}

	@:hlNative("?std", "alloc_carray")
	static function alloc_carray(t:hl.Type, size:Int):CArray<Dynamic> {
		return null;
	}
}
