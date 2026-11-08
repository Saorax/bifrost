package port.runtime.services;

import haxe.io.Bytes;

class TcpStream {
    public var connected(default, null):Bool = false;
    public var connecting(get, never):Bool;
    public var timeout:Int = 20000;
    public var input(default, null):DataBuffer;
    public var output(default, null):DataBuffer;

    public var tls:Bool = false;
    public var tlsName:Null<String> = null;
    public var tlsStatus(default, null):String = "unknown";

    #if sys
    var socket:Null<sys.net.Socket> = null;
    var job:Null<ConnectJob> = null;
    #end
    #if (sys && hl)
    public var tlsCa:Null<sys.ssl.Certificate> = null;
    var secure:Bool = false;
    #end
    var events:Array<SocketEvent> = [];
    var chunk:Bytes = Bytes.alloc(65536);

    public function new() {
        input = new DataBuffer();
        output = new GuardedBuffer(this);
    }

    function get_connecting():Bool {
        #if sys
        return job != null;
        #else
        return false;
        #end
    }

    public function connect(host:String, port:Int):Void {
        shut();
        input.clear();
        output.clear();
        if (port <= 0 || port > 65535) throw new ServiceError(2003, "Invalid socket port number specified.");
        #if sys
        var j = new ConnectJob(host, port, timeout);
        #if hl
        if (tls) {
            j.tls = true;
            j.tlsName = tlsName != null ? tlsName : host;
            j.tlsCa = tlsCa;
        }
        #end
        job = j;
        sys.thread.Thread.create(j.run);
        #else
        events.push(IoError("Error #2031: Socket Error. URL: " + host));
        #end
    }

    #if sys
    function settle():Void {
        var j = job;
        if (j == null) return;
        var ready = j.finished();
        if (!ready && haxe.Timer.stamp() < j.deadline) return;
        job = null;
        var s = ready ? j.socket : null;
        if (!ready) j.cancel();
        if (s != null) {
            socket = s;
            connected = true;
            #if hl
            if (j.tls) {
                secure = true;
                tlsStatus = "valid";
            }
            #end
            events.push(Connected);
        } else {
            #if hl
            if (j.tls) tlsStatus = "invalid";
            #end
            events.push(IoError("Error #2031: Socket Error. URL: " + j.host));
        }
    }
    #end

    #if (sys && hl)
    function readTls():Int {
        var received = 0;
        while (true) {
            var n = try socket.input.readBytes(chunk, 0, chunk.length) catch (e:haxe.io.Eof) {
                tlsEof = true;
                0;
            } catch (e:haxe.io.Error) {
                if (e != haxe.io.Error.Blocked) throw e;
                0;
            }
            if (n <= 0) return received;
            input.append(chunk, 0, n);
            received += n;
        }
    }

    var tlsEof:Bool = false;
    #end

    public function poll():Array<SocketEvent> {
        #if sys
        settle();
        if (connected && socket != null) {
            input.compact();
            var received = 0;
            try {
                #if hl
                if (secure) {
                    received = readTls();
                    if (tlsEof) throw new haxe.io.Eof();
                } else
                #end
                while (sys.net.Socket.select([socket], null, null, 0).read.length > 0) {
                    var n = socket.input.readBytes(chunk, 0, chunk.length);
                    if (n <= 0) break;
                    input.append(chunk, 0, n);
                    received += n;
                }
            } catch (e:Dynamic) {
                if (received > 0) events.push(Data(received));
                received = 0;
                shut();
                events.push(Closed);
            }
            if (received > 0) events.push(Data(received));
        }
        #end
        var out = events;
        events = [];
        return out;
    }

    public function flush():Void {
        if (!connected) throw new ServiceError(2002, "Operation attempted on invalid socket.");
        if (output.length == 0) return;
        #if sys
        try {
            #if hl
            if (secure) socket.setBlocking(true);
            #end
            socket.output.writeFullBytes(output.contents(), 0, output.length);
            socket.output.flush();
            #if hl
            if (secure) socket.setBlocking(false);
            #end
        } catch (e:Dynamic) {
            output.clear();
            shut();
            events.push(Closed);
            return;
        }
        #end
        output.clear();
    }

    public function close():Void {
        if (!connected && !connecting) throw new ServiceError(2002, "Operation attempted on invalid socket.");
        shut();
    }

    function shut():Void {
        connected = false;
        #if (sys && hl)
        secure = false;
        tlsEof = false;
        #end
        #if sys
        if (job != null) {
            job.cancel();
            job = null;
        }
        if (socket != null) {
            try socket.close() catch (_:Dynamic) {}
            socket = null;
        }
        #end
    }
}

enum SocketEvent {
    Connected;
    Data(bytes:Int);
    Closed;
    IoError(text:String);
}

private class GuardedBuffer extends DataBuffer {
    var owner:TcpStream;

    public function new(owner:TcpStream) {
        super();
        this.owner = owner;
    }

    override function room(n:Int):Void {
        if (!owner.connected) throw new ServiceError(2002, "Operation attempted on invalid socket.");
        super.room(n);
    }
}

#if sys
private class ConnectJob {
    public var host(default, null):String;
    public var deadline(default, null):Float;
    public var socket(default, null):Null<sys.net.Socket> = null;
    public var tls:Bool = false;
    #if hl
    public var tlsName:Null<String> = null;
    public var tlsCa:Null<sys.ssl.Certificate> = null;
    #end
    var port:Int;
    var timeout:Int;
    var lock:sys.thread.Mutex = new sys.thread.Mutex();
    var done:Bool = false;
    var cancelled:Bool = false;

    public function new(host:String, port:Int, timeout:Int) {
        this.host = host;
        this.port = port;
        this.timeout = timeout > 250 ? timeout : 250;
        deadline = haxe.Timer.stamp() + this.timeout / 1000;
    }

    public function run():Void {
        var s:Null<sys.net.Socket> = null;
        try {
            s = open();
        } catch (e:Dynamic) {
            s = null;
        }
        lock.acquire();
        var drop = cancelled;
        if (!drop) {
            socket = s;
            done = true;
        }
        lock.release();
        if (drop && s != null) try s.close() catch (_:Dynamic) {}
    }

    function open():sys.net.Socket {
        #if hl
        if (tls) {
            var t = new sys.ssl.Socket();
            try {
                t.verifyCert = true;
                if (tlsCa != null) t.setCA(tlsCa);
                t.setHostname(tlsName);
                t.setTimeout(timeout / 1000);
                t.connect(new sys.net.Host(host), port);
                t.setFastSend(true);
                t.setBlocking(false);
            } catch (e:Dynamic) {
                try t.close() catch (_:Dynamic) {}
                throw e;
            }
            return t;
        }
        #end
        var s = new sys.net.Socket();
        try {
            s.setTimeout(timeout / 1000);
            s.connect(new sys.net.Host(host), port);
            s.setFastSend(true);
        } catch (e:Dynamic) {
            try s.close() catch (_:Dynamic) {}
            throw e;
        }
        return s;
    }

    public function finished():Bool {
        lock.acquire();
        var d = done;
        lock.release();
        return d;
    }

    public function cancel():Void {
        lock.acquire();
        cancelled = true;
        var s = done ? socket : null;
        socket = null;
        lock.release();
        if (s != null) try s.close() catch (_:Dynamic) {}
    }
}
#end
