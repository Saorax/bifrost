package flash.display3D;

class Program3D {
	public var vertexAgal(default, null):haxe.io.Bytes;
	public var fragmentAgal(default, null):haxe.io.Bytes;
	public var disposed(default, null) = false;

	var context3D:flash.display3D.Context3D;

	public function dispose():Void {
		disposed = true;
		vertexAgal = fragmentAgal = null;
	}

	public function getAttributeIndex(name:String):Int {
		return -1;
	}

	public function getConstantIndex(name:String):Int {
		return -1;
	}

	public function upload(vertexProgram:flash.utils.ByteArray, fragmentProgram:flash.utils.ByteArray):Void {
		vertexAgal = agal(vertexProgram, 0);
		fragmentAgal = agal(fragmentProgram, 1);
	}

	public function uploadSources(vertexSource:String, fragmentSource:String):Void {}

	static function agal(program:flash.utils.ByteArray, type:Int):haxe.io.Bytes {
		if (program == null) throw new flash.errors.Error("Error #2007: Parameter program must be non-null.", 2007);
		if (program.length < 7 || program[0] != 0xA0 || program[5] != 0xA1 || program[6] != type)
			throw new flash.errors.Error("Error #3680: AGAL validation failed: Bad AGAL header.", 3680);
		var copy = haxe.io.Bytes.alloc(program.length);
		for (i in 0...program.length) copy.set(i, program[i]);
		return copy;
	}

	public function new(context3D:flash.display3D.Context3D, format:flash.display3D.Context3DProgramFormat) {
		this.context3D = context3D;
	}
}
