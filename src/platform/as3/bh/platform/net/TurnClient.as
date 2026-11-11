package bh.platform.net
{
   import flash.utils.ByteArray;
   import flash.utils.Endian;

   public final class TurnClient
   {
      public static const COOKIE:uint = 0x2112A442;
      private static const ALLOCATE:uint = 0x0003;
      private static const REFRESH:uint = 0x0004;
      private static const CHANNEL_BIND:uint = 0x0009;
      private static const DATA_INDICATION:uint = 0x0017;
      private static const SUCCESS:uint = 0x0100;
      private static const ERROR:uint = 0x0110;

      private static const USERNAME:uint = 0x0006;
      private static const MESSAGE_INTEGRITY:uint = 0x0008;
      private static const ERROR_CODE:uint = 0x0009;
      private static const CHANNEL_NUMBER:uint = 0x000C;
      private static const LIFETIME:uint = 0x000D;
      private static const XOR_PEER_ADDRESS:uint = 0x0012;
      private static const DATA:uint = 0x0013;
      private static const REALM:uint = 0x0014;
      private static const NONCE:uint = 0x0015;
      private static const XOR_RELAYED_ADDRESS:uint = 0x0016;
      private static const REQUESTED_TRANSPORT:uint = 0x0019;
      private static const XOR_MAPPED_ADDRESS:uint = 0x0020;

      public static const RTO:int = 500;
      public static const PORT_WAIT:int = 2500;
      public static const GIVE_UP:int = 10000;
      public static const BIND_EVERY:int = 240000;
      public static const FIRST_CHANNEL:uint = 0x4000;
      public static const LAST_CHANNEL:uint = 0x4FFF;


      public var host:String;
      public var ports:Array;
      public var username:String;
      public var password:String;
      public var expires:uint;

      public var state:String = "idle";
      public var why:String = "";
      public var serverIp:String = null;
      public var serverPort:int = 0;
      public var relayedIp:String = null;
      public var relayedPort:int = 0;
      public var mappedIp:String = null;
      public var mappedPort:int = 0;
      public var lifetime:int = 600;

      public var onReady:Function = null;
      public var onFailed:Function = null;
      public var onData:Function = null;
      public var onBound:Function = null;
      public var log:Function = null;

      private var sendBytes:Function;
      private var portIndex:int = 0;
      private var portStarted:int = 0;
      private var realm:String = null;
      private var nonce:String = null;
      private var key:ByteArray = null;
      private var pending:Object = {};
      private var refreshAt:int = 0;
      private var peers:Object = {};
      private var byChannel:Object = {};
      private var nextChannel:uint = FIRST_CHANNEL;
      private var out:ByteArray = new ByteArray();
      private var sendFailed:Boolean = false;

      public function TurnClient(send:Function, host:String, ports:Array, username:String, password:String, expires:uint = 0)
      {
         this.sendBytes = send;
         this.host = host;
         this.ports = ports.length > 0 ? ports : [3478];
         this.username = username;
         this.password = password;
         this.expires = expires;
      }

      public function sameLogin(host:String, ports:Array, username:String, password:String) : Boolean
      {
         return this.host == host && this.username == username && this.password == password &&
            this.ports.join(",") == (ports.length > 0 ? ports : [3478]).join(",");
      }

      public function get ready() : Boolean
      {
         return state == "ready";
      }

      public function start(now:int) : void
      {
         if(state != "idle")
         {
            return;
         }
         state = "allocating";
         portIndex = 0;
         serverPort = int(ports[0]);
         portStarted = now;
         serverIp = /^\d{1,3}(\.\d{1,3}){3}$/.test(host) ? host : null;
         request(ALLOCATE,"allocate",null,now);
      }

      public function owns(address:String, port:int) : Boolean
      {
         return state != "idle" && state != "closed" && port == serverPort && (serverIp == null || address == serverIp);
      }

      public function addPeer(ip:String, port:int, now:int) : void
      {
         var id:String = ip + ":" + port;
         var peer:Object = peers[id];
         if(peer != null)
         {
            if(peer.retired)
            {
               peer.retired = false;
               if(ready && !peer.binding)
               {
                  bind(peer,now);
               }
            }
            return;
         }
         if(nextChannel > LAST_CHANNEL)
         {
            say("TURN: no channel left for " + id);
            return;
         }
         peer = {"ip":ip,"port":port,"channel":nextChannel++,"bound":false,"nextBind":0,"binding":false,"retired":false};
         peers[id] = peer;
         byChannel[peer.channel] = peer;
         if(ready)
         {
            bind(peer,now);
         }
      }

      public function retirePeer(ip:String, port:int) : void
      {
         var peer:Object = peers[ip + ":" + port];
         if(peer != null)
         {
            peer.retired = true;
            peer.bound = false;
         }
      }

      public function retirePeers() : void
      {
         for each(var peer:Object in peers)
         {
            peer.retired = true;
            peer.bound = false;
         }
      }

      public function isBound(ip:String, port:int) : Boolean
      {
         var peer:Object = peers[ip + ":" + port];
         return ready && peer != null && peer.bound;
      }

      public function send(ip:String, port:int, payload:ByteArray) : Boolean
      {
         var peer:Object = peers[ip + ":" + port];
         if(!ready || peer == null || !peer.bound)
         {
            return false;
         }
         out.length = 0;
         out.endian = Endian.BIG_ENDIAN;
         out.writeShort(peer.channel);
         out.writeShort(payload.length);
         out.writeBytes(payload,0,payload.length);
         transmit(out);
         return true;
      }

      public function close(now:int) : void
      {
         if(state == "ready")
         {
            var lifetimeZero:ByteArray = new ByteArray();
            lifetimeZero.writeUnsignedInt(0);
            transmit(build(REFRESH,newTransaction(),[LIFETIME,lifetimeZero],true));
         }
         state = "closed";
         pending = {};
      }

      public function tick(now:int) : void
      {
         if(state == "idle" || state == "closed" || state == "failed")
         {
            return;
         }
         for(var tx:String in pending)
         {
            var req:Object = pending[tx];
            if(req.kind == "allocate" && now - portStarted >= PORT_WAIT)
            {
               delete pending[tx];
               nextPort(now);
               return;
            }
            if(now < req.next)
            {
               continue;
            }
            if(now - req.first >= GIVE_UP)
            {
               delete pending[tx];
               timedOut(req,now);
               if(state != "ready" && state != "allocating")
               {
                  return;
               }
               continue;
            }
            transmit(req.bytes);
            req.rto *= 2;
            req.next = now + req.rto;
         }
         if(state != "ready")
         {
            return;
         }
         if(now >= refreshAt && !hasPending("refresh"))
         {
            var life:ByteArray = new ByteArray();
            life.writeUnsignedInt(600);
            request(REFRESH,"refresh",null,now,[LIFETIME,life]);
            refreshAt = now + 60000;
         }
         for each(var peer:Object in peers)
         {
            if(!peer.retired && !peer.binding && now >= int(peer.nextBind))
            {
               bind(peer,now);
            }
         }
      }

      public function received(b:ByteArray, address:String, port:int, now:int) : Boolean
      {
         if(!owns(address,port) || b.length < 4)
         {
            return false;
         }
         b.position = 0;
         b.endian = Endian.BIG_ENDIAN;
         var first:uint = b[0];
         if((first & 0xC0) == 0x40)
         {
            if(serverIp == null)
            {
               return false;
            }
            var channel:uint = b.readUnsignedShort();
            var length:uint = b.readUnsignedShort();
            var peer:Object = byChannel[channel];
            if(peer != null && length <= b.bytesAvailable && onData != null)
            {
               var payload:ByteArray = new ByteArray();
               if(length > 0)
               {
                  b.readBytes(payload,0,length);
               }
               onData(peer.ip,peer.port,payload);
            }
            return true;
         }
         if((first & 0xC0) != 0 || b.length < 20)
         {
            return false;
         }
         var type:uint = b.readUnsignedShort();
         var size:uint = b.readUnsignedShort();
         if(b.readUnsignedInt() != COOKIE || 20 + size > b.length)
         {
            return false;
         }
         var txBytes:ByteArray = new ByteArray();
         b.readBytes(txBytes,0,12);
         var tx:String = TurnCrypto.hex(txBytes);
         var attrs:Object = readAttributes(b,size);
         if(type == DATA_INDICATION)
         {
            if(serverIp == null)
            {
               return false;
            }
            var from:Object = xorAddress(attrs[XOR_PEER_ADDRESS]);
            var data:ByteArray = attrs[DATA];
            if(from != null && data != null && onData != null && peers[from.ip + ":" + from.port] != null)
            {
               onData(from.ip,from.port,data);
            }
            return true;
         }
         var req:Object = pending[tx];
         if(req == null)
         {
            return serverIp != null;
         }
         delete pending[tx];
         if(serverIp == null)
         {
            serverIp = address;
         }
         if((type & 0x0110) == SUCCESS)
         {
            succeeded(req,attrs,now);
         }
         else if((type & 0x0110) == ERROR)
         {
            refused(req,attrs,now);
         }
         return true;
      }

      private function succeeded(req:Object, attrs:Object, now:int) : void
      {
         if(attrs[LIFETIME] != null)
         {
            attrs[LIFETIME].position = 0;
            lifetime = int(attrs[LIFETIME].readUnsignedInt());
         }
         if(req.kind == "allocate")
         {
            var relayed:Object = xorAddress(attrs[XOR_RELAYED_ADDRESS]);
            if(relayed == null)
            {
               fail("TURN allocated no IPv4 relayed address",now);
               return;
            }
            relayedIp = relayed.ip;
            relayedPort = relayed.port;
            var mapped:Object = xorAddress(attrs[XOR_MAPPED_ADDRESS]);
            if(mapped != null)
            {
               mappedIp = mapped.ip;
               mappedPort = mapped.port;
            }
            state = "ready";
            scheduleRefresh(now);
            say("TURN: relayed address " + relayedIp + ":" + relayedPort + " on " + host + " UDP " + serverPort +
               " (" + lifetime + " s)");
            for each(var peer:Object in peers)
            {
               if(!peer.retired)
               {
                  bind(peer,now);
               }
            }
            if(onReady != null)
            {
               onReady(this);
            }
         }
         else if(req.kind == "refresh")
         {
            scheduleRefresh(now);
         }
         else if(req.kind == "bind")
         {
            var p:Object = req.peer;
            p.binding = false;
            if(byChannel[p.channel] !== p || p.retired)
            {
               return;
            }
            var first:Boolean = !p.bound;
            p.bound = true;
            p.nextBind = now + BIND_EVERY;
            if(first)
            {
               say("TURN: channel " + p.channel.toString(16) + " to " + p.ip + ":" + p.port);
               if(onBound != null)
               {
                  onBound(p.ip,p.port);
               }
            }
         }
      }

      private function refused(req:Object, attrs:Object, now:int) : void
      {
         var code:int = errorCode(attrs[ERROR_CODE]);
         if((code == 401 || code == 438) && attrs[NONCE] != null && int(req.retries) < 2)
         {
            var firstLogin:Boolean = key == null;
            if(code == 401 && !firstLogin && req.authed)
            {
               failOrLog(req,"TURN refused the login (401)",now);
               return;
            }
            nonce = text(attrs[NONCE]);
            if(attrs[REALM] != null)
            {
               realm = text(attrs[REALM]);
            }
            key = TurnCrypto.longTermKey(username,realm || "",password);
            request(req.method,req.kind,req.peer,now,req.extra,int(req.retries) + 1);
            return;
         }
         failOrLog(req,"TURN error " + code + " on " + req.kind,now);
      }

      private function failOrLog(req:Object, reason:String, now:int) : void
      {
         if(req.kind == "allocate" || req.kind == "refresh")
         {
            fail(reason,now);
         }
         else
         {
            if(req.peer != null)
            {
               req.peer.binding = false;
               req.peer.nextBind = now + 5000;
            }
            say(reason + (req.peer != null ? " for " + req.peer.ip + ":" + req.peer.port : ""));
         }
      }

      private function timedOut(req:Object, now:int) : void
      {
         failOrLog(req,"TURN: no answer to " + req.kind,now);
      }

      private function nextPort(now:int) : void
      {
         portIndex++;
         if(portIndex >= ports.length)
         {
            fail("no answer from " + host + " on UDP " + ports.join(", "),now);
            return;
         }
         say("TURN: no answer on UDP " + serverPort + ", trying " + ports[portIndex]);
         serverPort = int(ports[portIndex]);
         portStarted = now;
         request(ALLOCATE,"allocate",null,now);
      }

      private function fail(reason:String, now:int) : void
      {
         if(state == "failed" || state == "closed")
         {
            return;
         }
         var wasReady:Boolean = state == "ready";
         state = "failed";
         why = reason;
         pending = {};
         for each(var peer:Object in peers)
         {
            peer.bound = false;
         }
         say("TURN: " + reason + (wasReady ? " (the allocation is gone)" : ""));
         if(onFailed != null)
         {
            onFailed(reason);
         }
      }

      private function scheduleRefresh(now:int) : void
      {
         refreshAt = now + int(Math.max(30,Math.min(300,lifetime / 2)) * 1000);
      }

      private function bind(peer:Object, now:int) : void
      {
         peer.binding = true;
         var number:ByteArray = new ByteArray();
         number.writeShort(peer.channel);
         number.writeShort(0);
         request(CHANNEL_BIND,"bind",peer,now,[CHANNEL_NUMBER,number,XOR_PEER_ADDRESS,xorBytes(peer.ip,peer.port)]);
      }

      private function hasPending(kind:String) : Boolean
      {
         for each(var req:Object in pending)
         {
            if(req.kind == kind)
            {
               return true;
            }
         }
         return false;
      }

      private function request(method:uint, kind:String, peer:Object, now:int, extra:Array = null, retries:int = 0) : void
      {
         var attrs:Array = (extra || []).concat();
         if(method == ALLOCATE)
         {
            var transport:ByteArray = new ByteArray();
            transport.writeUnsignedInt(17 << 24);
            attrs.push(REQUESTED_TRANSPORT,transport);
         }
         var txBytes:ByteArray = newTransaction();
         var bytes:ByteArray = build(method,txBytes,attrs,key != null);
         pending[TurnCrypto.hex(txBytes)] = {"method":method,"kind":kind,"peer":peer,"extra":extra,"bytes":bytes,
            "first":now,"next":now + RTO,"rto":RTO,"retries":retries,"authed":key != null};
         transmit(bytes);
      }

      private function newTransaction() : ByteArray
      {
         var b:ByteArray = new ByteArray();
         for(var i:int = 0; i < 12; i++)
         {
            b.writeByte(int(Math.random() * 256));
         }
         return b;
      }

      private function build(method:uint, tx:ByteArray, attrs:Array, authed:Boolean) : ByteArray
      {
         var body:ByteArray = new ByteArray();
         var i:int;
         for(i = 0; i < attrs.length; i += 2)
         {
            writeAttribute(body,uint(attrs[i]),attrs[i + 1]);
         }
         if(authed && key != null)
         {
            writeAttribute(body,USERNAME,TurnCrypto.utf8(username));
            writeAttribute(body,REALM,TurnCrypto.utf8(realm || ""));
            writeAttribute(body,NONCE,TurnCrypto.utf8(nonce || ""));
         }
         var m:ByteArray = new ByteArray();
         m.writeShort(method);
         m.writeShort(body.length + (authed && key != null ? 24 : 0));
         m.writeUnsignedInt(COOKIE);
         m.writeBytes(tx,0,12);
         if(body.length > 0)
         {
            m.writeBytes(body,0,body.length);
         }
         if(authed && key != null)
         {
            var mac:ByteArray = TurnCrypto.hmacSha1(key,m);
            writeAttribute(m,MESSAGE_INTEGRITY,mac);
         }
         m.position = 0;
         return m;
      }

      private static function writeAttribute(b:ByteArray, type:uint, value:ByteArray) : void
      {
         b.writeShort(type);
         b.writeShort(value.length);
         if(value.length > 0)
         {
            b.writeBytes(value,0,value.length);
         }
         while(b.length % 4 != 0)
         {
            b.writeByte(0);
         }
      }

      private static function readAttributes(b:ByteArray, size:uint) : Object
      {
         var attrs:Object = {};
         var end:uint = 20 + size;
         b.position = 20;
         while(b.position + 4 <= end)
         {
            var type:uint = b.readUnsignedShort();
            var length:uint = b.readUnsignedShort();
            if(b.position + length > end)
            {
               break;
            }
            var value:ByteArray = new ByteArray();
            if(length > 0)
            {
               b.readBytes(value,0,length);
            }
            value.position = 0;
            if(attrs[type] == null)
            {
               attrs[type] = value;
            }
            b.position = Math.min(end,b.position + (4 - length % 4) % 4);
         }
         return attrs;
      }

      private static function xorAddress(value:ByteArray) : Object
      {
         if(value == null || value.length < 8)
         {
            return null;
         }
         value.position = 0;
         value.readUnsignedByte();
         if(value.readUnsignedByte() != 1)
         {
            return null;
         }
         var port:int = value.readUnsignedShort() ^ COOKIE >>> 16;
         var ip:uint = value.readUnsignedInt() ^ COOKIE;
         return {"ip":(ip >>> 24) + "." + (ip >>> 16 & 0xFF) + "." + (ip >>> 8 & 0xFF) + "." + (ip & 0xFF),"port":port};
      }

      private static function xorBytes(ip:String, port:int) : ByteArray
      {
         var parts:Array = ip.split(".");
         var v:uint = uint(parts[0]) << 24 | uint(parts[1]) << 16 | uint(parts[2]) << 8 | uint(parts[3]);
         var b:ByteArray = new ByteArray();
         b.writeByte(0);
         b.writeByte(1);
         b.writeShort(port ^ COOKIE >>> 16);
         b.writeUnsignedInt(v ^ COOKIE);
         return b;
      }

      private static function errorCode(value:ByteArray) : int
      {
         if(value == null || value.length < 4)
         {
            return 0;
         }
         value.position = 2;
         var cls:int = value.readUnsignedByte() & 7;
         return cls * 100 + value.readUnsignedByte();
      }

      private static function text(value:ByteArray) : String
      {
         value.position = 0;
         return value.readUTFBytes(value.length);
      }

      private function transmit(bytes:ByteArray) : void
      {
         var to:String = serverIp != null ? serverIp : host;
         try
         {
            sendBytes(bytes,to,serverPort);
         }
         catch(e:Error)
         {
            if(!sendFailed)
            {
               sendFailed = true;
               say("TURN: sending to " + to + " UDP " + serverPort + " failed: " + e.message);
            }
         }
      }

      private function say(line:String) : void
      {
         if(log != null)
         {
            log(line);
         }
      }
   }
}
