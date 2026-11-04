package flash.display3D;

class VertexBuffer3D {
	public var numVertices(default, null):Int;
	public var data32PerVertex(default, null):Int;
	public var data(default, null):haxe.ds.Vector<Float>;
	public var version(default, null) = 0;

	var context3D:flash.display3D.Context3D;

	public static var onDispose:VertexBuffer3D -> Void;

	public function dispose():Void {
		if (data == null) return;
		data = null;
		if (onDispose != null) onDispose(this);
	}

	public function uploadFromByteArray(data:flash.utils.ByteArray, byteArrayOffset:Int, startVertex:Int, numVertices:Int):Void {
		check(startVertex, numVertices);
		var at = data.position;
		data.position = byteArrayOffset;
		for (i in 0...numVertices * data32PerVertex) this.data[startVertex * data32PerVertex + i] = data.readFloat();
		data.position = at;
		version++;
	}

	public function uploadFromTypedArray(data:Dynamic, byteLength:Int = -1):Void {}

	public function uploadFromVector(data:openfl.Vector<Float>, startVertex:Int, numVertices:Int):Void {
		check(startVertex, numVertices);
		var vector:port.runtime.AS3Vector = Std.isOfType(data, port.runtime.AS3Vector) ? cast data : null;
		var count = numVertices * data32PerVertex;
		for (i in 0...count) this.data[startVertex * data32PerVertex + i] = vector != null ? vector.getNumber(i) : (cast data : Array<Float>)[i];
		version++;
	}

	function check(start:Int, count:Int):Void {
		if (start < 0 || count < 0 || start + count > numVertices)
			throw new flash.errors.RangeError("Error #3669: Bad input size.");
	}

	public function new(context3D:flash.display3D.Context3D, numVertices:Int, dataPerVertex:Int, bufferUsage:String) {
		this.context3D = context3D;
		this.numVertices = numVertices;
		this.data32PerVertex = dataPerVertex;
		data = new haxe.ds.Vector<Float>(numVertices * dataPerVertex);
	}
}
