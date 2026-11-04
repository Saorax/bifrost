package port.engine;

class ShaderDiskCache extends h3d.impl.ShaderCache {
	static var instance:ShaderDiskCache = null;

	public static var hits(default, null) = 0;
	public static var compiled(default, null) = 0;

	var dirty = false;

	public static function install(storageDirectory:String):Void {
		#if hldx
		if (Sys.getEnv("BH_PORT_SHADER_CACHE") == "0") return;
		var dir = haxe.io.Path.join([storageDirectory, "BhPort", "Cache"]);
		try sys.FileSystem.createDirectory(dir) catch (e:Dynamic) return;
		instance = new ShaderDiskCache(haxe.io.Path.join([dir, "shaders-" + #if dx12 "dx12" #else "dx11" #end + ".cache"]));
		h3d.impl.Driver.setShaderCache(instance);
		#end
	}

	override public function resolveShaderBinary(source:String, ?configurationKey = "") {
		var bytes = super.resolveShaderBinary(source, "");
		if (bytes != null) hits++;
		return bytes;
	}

	override public function saveCompiledShader(source:String, bytes:haxe.io.Bytes, ?configurationKey = "", ?saveToFile = true) {
		if (data != null && data.get(haxe.crypto.Md5.encode(source)) == bytes) return;
		compiled++;
		super.saveCompiledShader(source, bytes, "", false);
		dirty = true;
	}

	public static function flush():Void {
		if (instance == null || !instance.dirty) return;
		instance.dirty = false;
		instance.save();
	}
}
