package port.engine;

class Tls {
	public static inline var VERIFY_NAME = "localhost";

	static var anchors:Map<String, sys.ssl.Certificate> = new Map();
	static var lock = new sys.thread.Mutex();

	public static function pin(host:String, pem:String):Bool {
		if (host == null || host == "" || pem == null) return false;
		var cert = try sys.ssl.Certificate.fromString(pem) catch (e:Dynamic) null;
		if (cert == null) return false;
		lock.acquire();
		anchors.set(host.toLowerCase(), cert);
		lock.release();
		return true;
	}

	public static function unpin(host:String):Void {
		if (host == null) return;
		lock.acquire();
		anchors.remove(host.toLowerCase());
		lock.release();
	}

	public static function pinned(host:String):Bool {
		return anchor(host) != null;
	}

	static function anchor(host:String):Null<sys.ssl.Certificate> {
		if (host == null) return null;
		lock.acquire();
		var found = anchors.get(host.toLowerCase());
		lock.release();
		return found;
	}

	public static function httpsHost(url:String):Null<String> {
		if (url == null || !StringTools.startsWith(url.toLowerCase(), "https://")) return null;
		var rest = url.substr("https://".length);
		var end = rest.length;
		for (c in ["/", "?", "#"]) {
			var at = rest.indexOf(c);
			if (at >= 0 && at < end) end = at;
		}
		var hostPort = rest.substr(0, end);
		var at = hostPort.lastIndexOf("@");
		if (at >= 0) hostPort = hostPort.substr(at + 1);
		var colon = hostPort.indexOf(":");
		return colon >= 0 ? hostPort.substr(0, colon) : hostPort;
	}

	public static function socketFor(url:String):Null<sys.ssl.Socket> {
		var cert = anchor(httpsHost(url));
		if (cert == null) return null;
		var sock = new sys.ssl.Socket();
		sock.verifyCert = true;
		sock.setCA(cert);
		sock.setHostname(VERIFY_NAME);
		return sock;
	}
}
