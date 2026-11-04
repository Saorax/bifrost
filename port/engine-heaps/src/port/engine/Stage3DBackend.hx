package port.engine;

interface Stage3DBackend {
	function clear(context:flash.display3D.Context3D, red:Float, green:Float, blue:Float, alpha:Float, depth:Float,
		stencil:Int):Void;
	function drawTriangles(context:flash.display3D.Context3D, indexBuffer:flash.display3D.IndexBuffer3D,
		firstIndex:Int, numTriangles:Int):Void;
	function present(context:flash.display3D.Context3D):Void;
	function capture(context:flash.display3D.Context3D, destination:flash.display.BitmapData):Void;
}
