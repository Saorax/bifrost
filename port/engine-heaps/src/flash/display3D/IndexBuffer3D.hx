package flash.display3D;

class IndexBuffer3D {
	public var numIndices(default, null):Int;
	public var data(default, null):haxe.ds.Vector<Int>;
	public var version(default, null) = 0;

	var context3D:flash.display3D.Context3D;

	public static var onDispose:IndexBuffer3D -> Void;

	public function dispose():Void {
		if (data == null) return;
		data = null;
		if (onDispose != null) onDispose(this);
	}

	public function uploadFromByteArray(data:flash.utils.ByteArray, byteArrayOffset:Int, startOffset:Int, count:Int):Void {
		check(startOffset, count);
		var at = data.position;
		data.position = byteArrayOffset;
		for (i in 0...count) this.data[startOffset + i] = data.readUnsignedShort();
		data.position = at;
		version++;
	}

	public function uploadFromTypedArray(data:Dynamic, byteLength:Int = -1):Void {}

	public function uploadFromVector(data:openfl.Vector<UInt>, startOffset:Int, count:Int):Void {
		check(startOffset, count);
		var vector:port.runtime.AS3Vector = Std.isOfType(data, port.runtime.AS3Vector) ? cast data : null;
		for (i in 0...count) this.data[startOffset + i] = (vector != null ? vector.getInt(i) : (cast data : Array<Int>)[i]) & 0xFFFF;
		version++;
	}

	function check(start:Int, count:Int):Void {
		if (start < 0 || count < 0 || start + count > numIndices)
			throw new flash.errors.RangeError("Error #3669: Bad input size.");
	}

	public function new(context3D:flash.display3D.Context3D, numIndices:Int, bufferUsage:flash.display3D.Context3DBufferUsage) {
		this.context3D = context3D;
		this.numIndices = numIndices;
		data = new haxe.ds.Vector<Int>(numIndices);
	}
}
