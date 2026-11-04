package port.runtime.swf;

abstract FastStringMap<T>(hl.types.BytesMap) {
    public inline function new() {
        this = new hl.types.BytesMap();
    }

    public inline function get(key:String):Null<T> {
        return key == null ? null : @:privateAccess this.get(key.bytes);
    }

    public inline function set(key:String, value:T):Void {
        @:privateAccess this.set(key.bytes, value);
    }

    public inline function exists(key:String):Bool {
        return key != null && @:privateAccess this.exists(key.bytes);
    }

    public inline function remove(key:String):Bool {
        return key != null && @:privateAccess this.remove(key.bytes);
    }

    public function keys():Iterator<String> {
        var bytes = this.keysArray();
        return [for (i in 0...bytes.length) @:privateAccess String.fromUCS2(bytes[i])].iterator();
    }

    public function keyValueIterator():KeyValueIterator<String, T> {
        return [for (key in keys()) {key: key, value: (get(key) : T)}].iterator();
    }
}
