package port.runtime;

class LoadTrace {
    static var lastSets:Int = 0;
    static var lastFailed:Dynamic = null;
    static var replayed = false;

    public static function poll(log:String->Void, describe:Dynamic->String):Void {
        var count:Int = Std.int(ArchiveLoader.loadedSetCount);
        if (count > lastSets) {
            lastSets = count;
            var files:Array<String> = [];
            var list = ArchiveLoader.var_5359;
            if (list != null)
                for (i in 0...Std.int(list.length)) {
                    var f:Dynamic = list[i];
                    files.push(f.fileName + "@" + f.loadSet + ":" + f.var_6640);
                }
            var sets = ArchiveLoader.loadSets;
            log("load: set " + count + " done (of " + (sets != null ? Std.string(sets.length) : "?") + "); files "
                + files.join(" "));
        }
        var failed:Dynamic = ArchiveLoader.var_10918;
        if (failed != null && failed != lastFailed) {
            lastFailed = failed;
            log("load: failed file " + failed.fileName);
            if (!replayed) {
                replayed = true;
                try {
                    ArchiveLoader.handleLoadedFile(failed);
                    log("load: replaying " + failed.fileName + " did not throw");
                } catch (error:Dynamic) {
                    log("load: " + failed.fileName + " handler throws: " + describe(error));
                }
            }
        }
    }
}
