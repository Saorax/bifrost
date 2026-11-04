package port.runtime.net;

class NetGuard {
    static final OFFICIAL = ["brawlhalla", "bmgstudios", "bluemammoth", "ubi.com", "ubisoft", "brawltools",
        "steampowered", "steamcommunity", "epicgames", "deltadna", "playfab"];

    public static var log:String->Void = null;
    public static var refusals:Int = 0;

    #if bifrost
    public static inline var CONFIG_NAME = "bh-server.json";
    public static inline var LIST_NAME = "bh-mod-settings.json";
    #else
    public static inline var CONFIG_NAME = "bh-port-server.json";
    #end

    static var loaded = false;
    static var loadedStamp:String = null;
    static var host:String = null;
    static var endpointPort:Int = 0;
    static var listed:Array<String> = [];
    static var peers:Array<String> = [];

    public static function hasEndpoint():Bool {
        load();
        return host != null;
    }

    public static function official(name:String):Bool {
        var h = name.toLowerCase();
        for (o in OFFICIAL) if (h.indexOf(o) >= 0) return true;
        return false;
    }

    public static function allowHost(name:String, remotePort:Int):Bool {
        if (name == null || name == "" || official(name)) return false;
        load();
        var lower = name.toLowerCase();
        if (peers.indexOf(lower + ":" + remotePort) >= 0) return true;
        if (listed.indexOf(lower) >= 0) return true;
        return host != null && lower == host && (endpointPort == 0 || remotePort == endpointPort);
    }

    public static function allowPeer(name:String, remotePort:Int):Bool {
        if (name == null || name == "" || official(name)) return false;
        var key = name.toLowerCase() + ":" + remotePort;
        if (peers.indexOf(key) < 0) peers.push(key);
        return true;
    }

    public static function allowUrl(url:String):Bool {
        if (url == null) return true;
        var u = StringTools.trim(url).toLowerCase();
        var colon = u.indexOf(":");
        var slash = u.indexOf("/");
        var scheme = colon > 1 && (slash < 0 || colon < slash) ? u.substr(0, colon) : "";
        if (scheme == "" || scheme == "app" || scheme == "app-storage" || scheme == "file") return true;
        if (u.indexOf("://") != colon) return false;
        var rest = u.substr(colon + 3);
        var end = rest.length;
        for (c in ["/", "?", "#"]) {
            var at = rest.indexOf(c);
            if (at >= 0 && at < end) end = at;
        }
        var authority = rest.substr(0, end);
        var at = authority.lastIndexOf("@");
        if (at >= 0) authority = authority.substr(at + 1);
        var hostPart = authority;
        var portNum = scheme == "https" ? 443 : 80;
        var pc = authority.lastIndexOf(":");
        if (pc > 0 && authority.indexOf("]") < pc) {
            hostPart = authority.substr(0, pc);
            var parsed = Std.parseInt(authority.substr(pc + 1));
            if (parsed != null) portNum = parsed;
        }
        return allowHost(hostPart, portNum);
    }

    public static function refuse(what:String):Void {
        refusals++;
        if (log != null && refusals <= 50) log("network guard: refused " + what);
    }

    public static function useEndpoint(name:String, remotePort:Int):Void {
        loaded = true;
        #if (sys && !flash)
        loadedStamp = stamp();
        #end
        host = name == null || official(name) ? null : name.toLowerCase();
        endpointPort = remotePort;
    }

    public static function reload():Void {
        loaded = false;
        loadedStamp = null;
        host = null;
        endpointPort = 0;
        listed = [];
        peers = [];
    }

    static function load():Void {
        #if (sys && !flash)
        var now = stamp();
        if (loaded && now == loadedStamp) return;
        loadedStamp = now;
        #else
        if (loaded) return;
        #end
        loaded = true;
        host = null;
        endpointPort = 0;
        listed = [];
        try {
            var config:Dynamic = readJson(CONFIG_NAME);
            if (config == null) return;
            var h:String = config.host;
            if (h != null && h != "" && !official(h)) {
                host = h.toLowerCase();
                #if bifrost
                endpointPort = 0;
                #else
                endpointPort = config.port != null ? Std.int(config.port) : 0;
                #end
            }
        } catch (_:Dynamic) {
            host = null;
        }
        #if bifrost
        try {
            var settings:Dynamic = readJson(LIST_NAME);
            if (settings == null) return;
            var servers:Array<Dynamic> = settings.servers;
            var all:Array<Dynamic> = servers != null ? servers.copy() : [];
            if (settings.mainServer != null) all.push(settings.mainServer);
            for (s in all) {
                var h:String = s == null ? null : s.host;
                if (h != null && h != "" && !official(h) && listed.indexOf(h.toLowerCase()) < 0) listed.push(h.toLowerCase());
            }
        } catch (_:Dynamic) {
            listed = [];
        }
        #end
    }

    static function readJson(name:String):Dynamic {
        var text:String = null;
        #if flash
        var file = flash.filesystem.File.documentsDirectory.resolvePath("Bifrost/" + name);
        if (file.exists) {
            var s = new flash.filesystem.FileStream();
            s.open(file, flash.filesystem.FileMode.READ);
            text = s.readUTFBytes(Std.int(s.bytesAvailable));
            s.close();
        }
        #elseif sys
        var path = pathOf(name);
        if (sys.FileSystem.exists(path)) text = sys.io.File.getContent(path);
        #end
        return text == null ? null : haxe.Json.parse(text);
    }

    #if (sys && !flash)
    static function pathOf(name:String):String {
        #if bifrost
        return flash.filesystem.File.documentsDirectory.resolvePath("Bifrost/" + name).nativePath;
        #else
        return port.runtime.services.Launch.documentsDirectory() + "\\Bifrost\\" + name;
        #end
    }

    static function stamp():String {
        var parts = [];
        for (name in #if bifrost [CONFIG_NAME, LIST_NAME] #else [CONFIG_NAME] #end) {
            try {
                var path = pathOf(name);
                if (!sys.FileSystem.exists(path)) {
                    parts.push("-");
                    continue;
                }
                var st = sys.FileSystem.stat(path);
                parts.push(st.mtime.getTime() + ":" + st.size);
            } catch (_:Dynamic) {
                parts.push("?");
            }
        }
        return parts.join("|");
    }
    #end
}
