package port.runtime.swf;

abstract FastIntMap<T>(hl.types.IntMap) {
    public inline function new() {
        this = new hl.types.IntMap();
    }

    public inline function get(key:Int):Null<T> {
        return this.get(key);
    }

    public inline function set(key:Int, value:T):Void {
        this.set(key, value);
    }

    public inline function exists(key:Int):Bool {
        return this.exists(key);
    }

    public inline function remove(key:Int):Bool {
        return this.remove(key);
    }

    public inline function keys():Iterator<Int> {
        return new hl.NativeArray.NativeArrayIterator<Int>(this.keysArray());
    }

    public inline function iterator():Iterator<T> {
        return new hl.NativeArray.NativeArrayIterator<T>(cast this.valuesArray());
    }
}
