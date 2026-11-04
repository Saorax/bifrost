package port.runtime;

abstract SparseArray(haxe.ds.IntMap<Dynamic>) {
    public inline function new() this = new haxe.ds.IntMap<Dynamic>();

    @:arrayAccess public inline function get(index:Int):Dynamic return this.get(index);

    @:arrayAccess public inline function set(index:Int, value:Dynamic):Dynamic {
        this.set(index, value);
        return value;
    }
}
