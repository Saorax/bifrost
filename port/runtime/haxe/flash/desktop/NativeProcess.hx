package flash.desktop;

import flash.events.EventDispatcher;
import flash.events.IOErrorEvent;
import flash.events.NativeProcessExitEvent;
import flash.events.ProgressEvent;
import flash.utils.ByteArray;
import port.runtime.services.ByteArrayBridge;
import port.runtime.services.Pump;

class NativeProcess extends EventDispatcher {
    public static var isSupported:Bool = #if sys true #else false #end;

    public var running:Bool = false;
    public var standardInput:ByteArray = new ByteArray();
    public var standardOutput:ByteArray = new ByteArray();
    public var standardError:ByteArray = new ByteArray();

    #if sys
    var process:sys.io.Process;
    var chunks = new sys.thread.Deque<{error:Bool, data:haxe.io.Bytes}>();
    var readersDone = 0;
    var inputClosed = false;
    #end

    public function new() {
        super();
    }

    public static function argumentsFor(given:Dynamic, extra:String):Array<String> {
        var out = new Array<String>();
        if (given != null) {
            var count:Int = given.length;
            for (i in 0...count) out.push(Std.string(port.runtime.As3.indexValue(given, i)));
        }
        if (extra != null && extra != "") for (arg in extra.split("\t")) out.push(arg);
        return out;
    }

    public function start(info:NativeProcessStartupInfo):Void {
        #if sys
        if (running) throw new port.runtime.services.ServiceError(3214, "Error #3214: the process is already running");
        var path = info.executable.nativePath;
        process = new sys.io.Process(path, argumentsFor(info.arguments, Sys.getEnv("BH_PORT_NATIVEPROCESS_ARGS")));
        running = true;
        readersDone = 0;
        reader(process.stdout, false);
        reader(process.stderr, true);
        Pump.add(pump);
        #else
        throw new port.runtime.services.ServiceError(3212, "NativeProcess is not supported");
        #end
    }

    #if sys
    function reader(input:haxe.io.Input, error:Bool):Void {
        var queue = chunks;
        sys.thread.Thread.create(function() {
            var buffer = haxe.io.Bytes.alloc(4096);
            try {
                while (true) {
                    var n = input.readBytes(buffer, 0, buffer.length);
                    if (n <= 0) break;
                    queue.add({error: error, data: buffer.sub(0, n)});
                }
            } catch (e:Dynamic) {}
            queue.add({error: error, data: null});
        });
    }

    static function append(target:ByteArray, data:haxe.io.Bytes):Void {
        var at = target.position;
        target.position = target.length;
        for (i in 0...data.length) target.writeByte(data.get(i));
        target.position = at;
    }

    function pump():Bool {
        flushInput();
        var chunk;
        while ((chunk = chunks.pop(false)) != null) {
            if (chunk.data == null) {
                readersDone++;
                continue;
            }
            var target = chunk.error ? standardError : standardOutput;
            append(target, chunk.data);
            dispatchEvent(new ProgressEvent(chunk.error ? ProgressEvent.STANDARD_ERROR_DATA : ProgressEvent.STANDARD_OUTPUT_DATA,
                false, false, chunk.data.length, 0));
        }
        if (readersDone < 2) return true;
        var code:Null<Int> = #if eval process.exitCode(true) #else process.exitCode(false) #end;
        if (code == null) return true;
        running = false;
        process.close();
        dispatchEvent(new NativeProcessExitEvent(NativeProcessExitEvent.EXIT, false, false, code));
        return false;
    }

    function flushInput():Void {
        if (inputClosed || standardInput.length == 0) return;
        try {
            var bytes = ByteArrayBridge.slice(standardInput, 0, standardInput.length);
            process.stdin.writeBytes(bytes, 0, bytes.length);
            process.stdin.flush();
        } catch (e:Dynamic) {
            dispatchEvent(new IOErrorEvent("standardInputIoError", false, false, Std.string(e)));
        }
        standardInput.clear();
    }
    #end

    public function exit(force:Bool = false):Void {
        #if sys
        if (process == null || !running) return;
        flushInput();
        if (force) process.kill() else closeInput();
        #end
    }

    public function closeInput():Void {
        #if sys
        if (process == null || inputClosed) return;
        flushInput();
        inputClosed = true;
        try process.stdin.close() catch (e:Dynamic) {}
        #end
    }
}
