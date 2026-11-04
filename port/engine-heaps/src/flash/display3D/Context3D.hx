package flash.display3D;

class Context3D extends flash.events.EventDispatcher {
	public static var supportsVideoTexture:Bool = false;
	public var backBufferHeight:Int = 0;
	public var backBufferWidth:Int = 0;
	public var driverInfo:String = "Heaps engine (no GPU backend yet)";
	public var enableErrorChecking:Bool = false;
	public var maxBackBufferHeight:Int = 2048;
	public var maxBackBufferWidth:Int = 2048;
	public var profile:flash.display3D.Context3DProfile;
	public var totalGPUMemory:Int = 0;

	public var stats(default, null) = {presents: 0, clears: 0, draws: 0, triangles: 0};

	public var program(default, null):flash.display3D.Program3D;
	public var vertexConstants(default, null) = new haxe.ds.Vector<Float>(128 * 4);
	public var fragmentConstants(default, null) = new haxe.ds.Vector<Float>(28 * 4);
	public var streams(default, null):Array<{buffer:VertexBuffer3D, offset:Int, format:Context3DVertexBufferFormat}> = [for (_ in 0...8) null];
	public var textures(default, null):Array<flash.display3D.textures.TextureBase> = [for (_ in 0...8) null];
	public var blend(default, null) = {source: Context3DBlendFactor.ONE, destination: Context3DBlendFactor.ZERO};
	public var depth(default, null) = {mask: true, compare: Context3DCompareMode.LESS};
	public var culling(default, null):Context3DTriangleFace = Context3DTriangleFace.NONE;
	public var scissor(default, null):flash.geom.Rectangle;
	public var renderTarget(default, null):flash.display3D.textures.TextureBase;

	var stage3D:flash.display.Stage3D;

	public static var backend:port.engine.Stage3DBackend;

	public function clear(red:Float = 0, green:Float = 0, blue:Float = 0, alpha:Float = 1, depth:Float = 1, stencil:UInt = 0, ?mask:UInt):Void {
		stats.clears++;
		if (backend != null) backend.clear(this, red, green, blue, alpha, depth, stencil);
	}

	public function configureBackBuffer(width:Int, height:Int, antiAlias:Int, enableDepthAndStencil:Bool = true, wantsBestResolution:Bool = false, wantsBestResolutionOnBrowserZoom:Bool = false):Void {
		if (width < 32 || height < 32 || width > maxBackBufferWidth || height > maxBackBufferHeight)
			throw new flash.errors.ArgumentError("Error #3683: The back buffer size is out of range.");
		backBufferWidth = width;
		backBufferHeight = height;
	}

	public function createCubeTexture(size:Int, format:flash.display3D.Context3DTextureFormat, optimizeForRenderToTexture:Bool, streamingLevels:Int = 0):flash.display3D.textures.CubeTexture {
		return new flash.display3D.textures.CubeTexture(this, size, format, optimizeForRenderToTexture, streamingLevels);
	}

	public function createIndexBuffer(numIndices:Int, ?bufferUsage:flash.display3D.Context3DBufferUsage):flash.display3D.IndexBuffer3D {
		return new IndexBuffer3D(this, numIndices, bufferUsage);
	}

	public function createProgram(?format:flash.display3D.Context3DProgramFormat):flash.display3D.Program3D {
		return new Program3D(this, format);
	}

	public function createRectangleTexture(width:Int, height:Int, format:flash.display3D.Context3DTextureFormat, optimizeForRenderToTexture:Bool):flash.display3D.textures.RectangleTexture {
		return new flash.display3D.textures.RectangleTexture(this, width, height, format, optimizeForRenderToTexture);
	}

	public function createTexture(width:Int, height:Int, format:flash.display3D.Context3DTextureFormat, optimizeForRenderToTexture:Bool, streamingLevels:Int = 0):flash.display3D.textures.Texture {
		return new flash.display3D.textures.Texture(this, width, height, format, optimizeForRenderToTexture, streamingLevels);
	}

	public function createVertexBuffer(numVertices:Int, data32PerVertex:Int, ?bufferUsage:flash.display3D.Context3DBufferUsage):flash.display3D.VertexBuffer3D {
		return new VertexBuffer3D(this, numVertices, data32PerVertex, bufferUsage != null ? (bufferUsage : String) : "staticDraw");
	}

	public function createVideoTexture():flash.display3D.textures.VideoTexture {
		return null;
	}

	public function dispose(recreate:Bool = true):Void {
		driverInfo = "Disposed";
		disposes++;
		program = null;
		for (i in 0...streams.length) streams[i] = null;
		for (i in 0...textures.length) textures[i] = null;
	}

	public function drawToBitmapData(destination:flash.display.BitmapData, ?srcRect:flash.geom.Rectangle, ?destPoint:flash.geom.Point):Void {
		if (destination == null) throw new flash.errors.Error("Error #2007: Parameter destination must be non-null.", 2007);
		if (backend != null) backend.capture(this, destination);
	}

	public function drawTriangles(indexBuffer:flash.display3D.IndexBuffer3D, firstIndex:Int = 0, numTriangles:Int = -1):Void {
		if (indexBuffer == null) throw new flash.errors.Error("Error #2007: Parameter indexBuffer must be non-null.", 2007);
		if (numTriangles < 0) numTriangles = Std.int((indexBuffer.numIndices - firstIndex) / 3);
		stats.draws++;
		stats.triangles += numTriangles;
		if (backend != null) backend.drawTriangles(this, indexBuffer, firstIndex, numTriangles);
	}

	public static var presents(default, null) = 0;
	public static var disposes(default, null) = 0;

	public function present():Void {
		stats.presents++;
		presents++;
		if (backend != null) backend.present(this);
	}

	public function setBlendFactors(sourceFactor:flash.display3D.Context3DBlendFactor, destinationFactor:flash.display3D.Context3DBlendFactor):Void {
		blend.source = sourceFactor;
		blend.destination = destinationFactor;
	}

	public function setColorMask(red:Bool, green:Bool, blue:Bool, alpha:Bool):Void {}

	public function setCulling(triangleFaceToCull:flash.display3D.Context3DTriangleFace):Void {
		culling = triangleFaceToCull;
	}

	public function setDepthTest(depthMask:Bool, passCompareMode:flash.display3D.Context3DCompareMode):Void {
		depth.mask = depthMask;
		depth.compare = passCompareMode;
	}

	public function setProgram(program:flash.display3D.Program3D):Void {
		this.program = program;
	}

	public function setProgramConstantsFromByteArray(programType:flash.display3D.Context3DProgramType, firstRegister:Int, numRegisters:Int, data:flash.utils.ByteArray, byteArrayOffset:UInt):Void {
		var target = constants(programType);
		var at = data.position;
		data.position = byteArrayOffset;
		for (i in 0...numRegisters * 4) {
			var slot = firstRegister * 4 + i;
			var value = data.readFloat();
			if (slot < target.length) target[slot] = value;
		}
		data.position = at;
	}

	public function setProgramConstantsFromMatrix(programType:flash.display3D.Context3DProgramType, firstRegister:Int, matrix:flash.geom.Matrix3D, transposedMatrix:Bool = false):Void {
		var target = constants(programType);
		var raw = matrix.rawData;
		for (row in 0...4) for (column in 0...4) {
			var slot = (firstRegister + row) * 4 + column;
			if (slot < target.length) target[slot] = transposedMatrix ? raw[column * 4 + row] : raw[row * 4 + column];
		}
	}

	public function setProgramConstantsFromVector(programType:flash.display3D.Context3DProgramType, firstRegister:Int, data:Dynamic, numRegisters:Int = -1):Void {
		var target = constants(programType);
		var vector:port.runtime.AS3Vector = Std.isOfType(data, port.runtime.AS3Vector) ? data : null;
		var array:Array<Float> = vector == null ? data : null;
		var length = vector != null ? vector.length : array.length;
		var count = numRegisters < 0 ? Std.int(length / 4) : numRegisters;
		for (i in 0...count * 4) {
			var slot = firstRegister * 4 + i;
			if (slot < target.length && i < length) target[slot] = vector != null ? vector.getNumber(i) : array[i];
		}
	}

	public function setRenderToBackBuffer():Void {
		renderTarget = null;
	}

	public function setRenderToTexture(texture:flash.display3D.textures.TextureBase, enableDepthAndStencil:Bool = false, antiAlias:Int = 0, surfaceSelector:Int = 0):Void {
		renderTarget = texture;
	}

	public function setSamplerStateAt(sampler:Int, wrap:flash.display3D.Context3DWrapMode, filter:flash.display3D.Context3DTextureFilter, mipfilter:flash.display3D.Context3DMipFilter):Void {}

	public function setScissorRectangle(rectangle:flash.geom.Rectangle):Void {
		scissor = rectangle != null ? rectangle.clone() : null;
	}

	public function setStencilActions(?triangleFace:flash.display3D.Context3DTriangleFace, ?compareMode:flash.display3D.Context3DCompareMode, ?actionOnBothPass:flash.display3D.Context3DStencilAction, ?actionOnDepthFail:flash.display3D.Context3DStencilAction, ?actionOnDepthPassStencilFail:flash.display3D.Context3DStencilAction):Void {}

	public function setStencilReferenceValue(referenceValue:UInt, readMask:UInt = 0xFF, writeMask:UInt = 0xFF):Void {}

	public function setTextureAt(sampler:Int, texture:flash.display3D.textures.TextureBase):Void {
		textures[sampler] = texture;
	}

	public function setVertexBufferAt(index:Int, buffer:flash.display3D.VertexBuffer3D, bufferOffset:Int = 0, ?format:flash.display3D.Context3DVertexBufferFormat):Void {
		if (buffer == null) {
			streams[index] = null;
			return;
		}
		var s = kept[index];
		if (s == null) kept[index] = s = {buffer: buffer, offset: bufferOffset, format: null};
		s.buffer = buffer;
		s.offset = bufferOffset;
		s.format = format != null ? format : Context3DVertexBufferFormat.FLOAT_4;
		streams[index] = s;
	}

	var kept:Array<{buffer:VertexBuffer3D, offset:Int, format:Context3DVertexBufferFormat}> = [for (_ in 0...8) null];

	static var VERTEX:Context3DProgramType = Context3DProgramType.VERTEX;

	function constants(type:Context3DProgramType):haxe.ds.Vector<Float> {
		return type == VERTEX ? vertexConstants : fragmentConstants;
	}

	public function new(stage:flash.display.Stage, ?contextState:Dynamic, ?stage3D:flash.display.Stage3D) {
		super();
		this.stage3D = stage3D;
	}
}
