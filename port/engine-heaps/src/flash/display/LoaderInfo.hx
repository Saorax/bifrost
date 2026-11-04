package flash.display;

class LoaderInfo extends flash.events.EventDispatcher {
	public static function create(loader:flash.display.Loader):flash.display.LoaderInfo {
		var info = new LoaderInfo();
		info.loader = loader;
		info.uncaughtErrorEvents = new flash.events.UncaughtErrorEvents();
		return info;
	}

	public var applicationDomain:flash.system.ApplicationDomain;
	public var assetLibrary:flash.utils.AssetLibrary;
	public var bytes:flash.utils.ByteArray;
	public var bytesLoaded:Int = 0;
	public var bytesTotal:Int = 0;
	public var childAllowsParent:Bool = true;
	public var content:flash.display.DisplayObject;
	public var contentType:String;
	public var frameRate:Float = 0;
	public var height:Int = -1;
	public var loader:flash.display.Loader;
	public var loaderURL:String;
	public var parameters:Dynamic = {};
	public var parentAllowsChild:Bool = true;
	public var sameDomain:Bool = true;
	public var sharedEvents:flash.events.EventDispatcher = new flash.events.EventDispatcher();
	public var uncaughtErrorEvents:flash.events.UncaughtErrorEvents;
	public var url:String;
	public var width:Int = -1;

	public function new() {
		super();
	}
}
