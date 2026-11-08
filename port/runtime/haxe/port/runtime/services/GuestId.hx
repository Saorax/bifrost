package port.runtime.services;

class GuestId {
    public static inline var FILE = "guest-id.txt";

    #if bifrost
    static var cached:Null<String> = null;

    public static function forInstall():String {
        if (cached == null) {
            cached = #if sys read(flash.filesystem.File.documentsDirectory.resolvePath("Bifrost/" + FILE).nativePath)
                #else make() #end;
        }
        return cached;
    }
    #end

    public static function usable(id:String):Bool {
        return id != null && ~/^[0-9a-f]{32}$/.match(id) && ~/[1-9a-f]/.match(id);
    }

    #if sys
    public static function read(path:String):String {
        try {
            if (sys.FileSystem.exists(path)) {
                var kept = StringTools.trim(sys.io.File.getContent(path)).toLowerCase();
                if (usable(kept)) return kept;
            }
        } catch (_:Dynamic) {}
        var made = make();
        try {
            var dir = haxe.io.Path.directory(path);
            if (dir != "" && !sys.FileSystem.exists(dir)) sys.FileSystem.createDirectory(dir);
            sys.io.File.saveContent(path, made);
        } catch (_:Dynamic) {}
        return made;
    }
    #end

    public static function make():String {
        var seed = new StringBuf();
        seed.add(Date.now().getTime());
        seed.add(haxe.Timer.stamp());
        #if sys
        seed.add(Sys.time());
        seed.add(Sys.cpuTime());
        for (name in ["COMPUTERNAME", "USERNAME", "USERPROFILE", "PROCESSOR_IDENTIFIER"]) seed.add(Sys.getEnv(name));
        try seed.add(Sys.programPath()) catch (_:Dynamic) {}
        #end
        for (_ in 0...16) {
            seed.add(Std.random(0x7fffffff));
            seed.add(Math.random());
        }
        seed.add(haxe.Timer.stamp());
        return haxe.crypto.Sha256.encode(seed.toString()).substr(0, 32);
    }
}
