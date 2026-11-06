package port.engine;

class RendererStart {
	static inline var FAILED = 0x0BAD3D11;

	public static function failed(error:String):Bool {
		if (error.indexOf("DirectX") < 0 && error.indexOf("DXError") < 0) return false;
		if (Sys.getEnv("BH_PORT_MARKER") == null) return false;
		BootLog.log("renderer failed: " + error);
		if (Sys.getEnv("BIFROST_RENDERER_RETRY") != "1") {
			var flags = new haxe.EnumFlags<hl.UI.DialogFlags>();
			flags.set(IsError);
			hl.UI.dialog("Brawlhalla",
				"Brawlhalla could not start its graphics on this PC.\n\nUpdating your graphics driver usually fixes this. "
				+ "You can also pick another renderer in the Bifrost app.\n\n" + error, flags);
		}
		Sys.exit(FAILED);
		return true;
	}
}
