package flash.system;

class ApplicationDomain {
	public static var currentDomain:flash.system.ApplicationDomain = new ApplicationDomain(null);
	public var parentDomain:flash.system.ApplicationDomain;

	public function getDefinition(name:String):Class<Dynamic> {
		return port.runtime.swf.SwfSymbols.resolve(this, name);
	}

	public function hasDefinition(name:String):Bool {
		return port.runtime.swf.SwfSymbols.resolve(this, name) != null;
	}

	public function new(?parentDomain:flash.system.ApplicationDomain) {
		this.parentDomain = parentDomain != null ? parentDomain : currentDomain;
	}
}
