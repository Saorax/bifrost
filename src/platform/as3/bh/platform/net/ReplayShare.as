package bh.platform.net
{
   import bh.platform.BackTrail;
   import bh.platform.Busy;
   import bh.platform.DummyDrift;
   import bh.platform.Hooks;
   import bh.platform.Modal;
   import bh.platform.ModSettings;
   import bh.platform.ReplayIndex;
   import flash.filesystem.File;
   import flash.filesystem.FileMode;
   import flash.filesystem.FileStream;
   import flash.utils.ByteArray;
   import flash.utils.getTimer;

   public final class ReplayShare
   {
      public static const PART:int = 11060;
      public static const STORED:int = 11061;
      public static const GET:int = 11062;
      public static const DATA:int = 11063;
      public static const MODS:int = 11064;
      public static const SHARE:int = 11065;
      public static const SHARED:int = 11066;
      public static const GET_CODE:int = 11067;
      public static const VERSION:uint = 2;
      public static const MAX_MODS:int = 60;
      public static const PART_SIZE:int = 48 * 1024;
      public static const MAX_REPLAY:uint = 8 * 1024 * 1024;
      private static const SAFE_NAME:RegExp = new RegExp("^\\[[0-9.]+\\] [A-Za-z0-9 _.()-]+\\.replay$");
      private static const WAIT_MS:int = 10 * 60 * 1000;

      private static var registered:Boolean = false;

      private static var room:uint = 0;
      private static var seed:uint = 0;
      private static var watching:Boolean = false;
      private static var watchUntil:int = 0;
      private static var recorder:Object = null;

      private static var incoming:Object = null;
      private static var modsOffer:Object = null;

      public static var last:String = "";

      public function ReplayShare()
      {
      }

      public static function register() : void
      {
         if(registered)
         {
            return;
         }
         registered = true;
         Hooks.frameStarting.add(onFrame);
         Hooks.packetReceived.add(onPacket);
         ReplayIndex.sharing = {"share":shareFile,"fetch":fetchCode};
      }

      public static function matchEnded(roomNumber:uint, matchSeed:uint) : void
      {
         if(!ModSettings.flag("shareReplays",true))
         {
            PrivateServer.log("replay share: off (shareReplays false)");
            return;
         }
         try
         {
            recorder = Object(GameApp.mainInstance).var_13259.var_7524;
         }
         catch(e:Error)
         {
            recorder = null;
         }
         if(recorder == null)
         {
            PrivateServer.log("replay share: the match has no recorder");
            return;
         }
         room = roomNumber;
         seed = matchSeed;
         watching = true;
         watchUntil = getTimer() + WAIT_MS;
         onFrame();
      }

      private static function onFrame() : void
      {
         if(!watching)
         {
            return;
         }
         var current:Object = null;
         try
         {
            current = Object(GameApp.mainInstance).var_13259.var_7524;
         }
         catch(e:Error)
         {
         }
         if(recorder.var_8217)
         {
            watching = false;
            upload(recorder.var_12162.var_15327 as ByteArray);
            recorder = null;
         }
         else if(current !== recorder || getTimer() > watchUntil)
         {
            watching = false;
            recorder = null;
            PrivateServer.log("replay share: the replay of room " + room + " wasn't saved (" +
               (getTimer() > watchUntil ? "timed out" : "the next match started") + ")");
         }
      }

      private static function upload(bytes:ByteArray) : void
      {
         if(bytes == null || bytes.length == 0 || bytes.length > MAX_REPLAY)
         {
            PrivateServer.log("replay share: nothing to send (" + (bytes == null ? "no bytes" : bytes.length + " bytes") + ")");
            return;
         }
         try
         {
            var core:Object = Object(GameApp.mainInstance).var_13259;
            var total:uint = bytes.length;
            var parts:int = 0;
            ModCheck.refresh();
            var mods:Array = ModCheck.list();
            for(var off:uint = 0; off < total; off += PART_SIZE)
            {
               var n:uint = Math.min(PART_SIZE,total - off);
               var packet:NetPacket = new NetPacket(PART);
               packet.writeUint(VERSION);
               packet.writeUint(room);
               packet.writeUint(seed);
               packet.writeUint(total);
               packet.writeUint(off);
               packet.writeUint(n);
               for(var i:uint = 0; i < n; i++)
               {
                  packet.method_7572(bytes[off + i]);
               }
               writeMods(packet,off == 0 ? mods : []);
               if(!core.sendToServer(packet))
               {
                  packet.method_839();
                  PrivateServer.log("replay share: not connected, the replay of room " + room + " wasn't sent");
                  return;
               }
               packet.method_839();
               parts++;
            }
            last = "sent " + total + " bytes for room " + room + " seed " + seed + " in " + parts + " parts";
            PrivateServer.log("replay share: " + last);
         }
         catch(e:Error)
         {
            PrivateServer.log("replay share: could not send (" + e.message + ")");
         }
      }

      private static var sharing:Object = null;
      private static var codeFetch:Object = null;

      public static function shareFile(f:File, done:Function) : void
      {
         var stream:FileStream = new FileStream();
         try
         {
            var bytes:ByteArray = new ByteArray();
            stream.open(f,FileMode.READ);
            stream.readBytes(bytes);
            stream.close();
            if(bytes.length == 0 || bytes.length > MAX_REPLAY)
            {
               done(null,"the file is empty or too large");
               return;
            }
            var core:Object = Object(GameApp.mainInstance).var_13259;
            var nonce:uint = uint(Math.random() * 0x7FFFFFFF);
            ModCheck.refresh();
            var mods:Array = ModCheck.list();
            for(var off:uint = 0; off < bytes.length; off += PART_SIZE)
            {
               var n:uint = Math.min(PART_SIZE,bytes.length - off);
               var packet:NetPacket = new NetPacket(SHARE);
               packet.writeUint(VERSION);
               packet.writeUint(nonce);
               packet.writeUint(bytes.length);
               packet.writeUint(off);
               packet.writeUint(n);
               for(var i:uint = 0; i < n; i++)
               {
                  packet.method_7572(bytes[off + i]);
               }
               writeMods(packet,off == 0 ? mods : []);
               packet.writeString(f.name);
               var sent:Boolean = core.sendToServer(packet);
               packet.method_839();
               if(!sent)
               {
                  done(null,"not connected to the server");
                  return;
               }
            }
            sharing = {"name":f.name,"done":done};
            Busy.start(BUSY,"SHARING THE REPLAY",30000);
            last = "sharing " + f.name + " (" + bytes.length + " bytes)";
            PrivateServer.log("replay share: " + last);
         }
         catch(e:Error)
         {
            try
            {
               stream.close();
            }
            catch(e2:Error)
            {
            }
            PrivateServer.log("replay share: could not share " + f.name + " (" + e.message + ")");
            done(null,e.message);
         }
      }

      public static function fetchCode(code:String, done:Function) : void
      {
         try
         {
            var core:Object = Object(GameApp.mainInstance).var_13259;
            var packet:NetPacket = new NetPacket(GET_CODE);
            packet.writeString(code);
            var sent:Boolean = core.sendToServer(packet);
            packet.method_839();
            if(!sent)
            {
               done(null,"not connected to the server");
               return;
            }
            codeFetch = {"code":code,"done":done};
            incoming = null;
            modsOffer = null;
            playWhenSaved = null;
            Busy.start(BUSY,"GETTING THE REPLAY",30000);
            last = "asked for code " + code;
            PrivateServer.log("replay share: " + last);
         }
         catch(e:Error)
         {
            done(null,e.message);
         }
      }

      private static function codeDone(name:String, error:String) : Boolean
      {
         if(codeFetch == null)
         {
            return false;
         }
         var done:Function = codeFetch.done;
         codeFetch = null;
         done(name,error);
         return true;
      }

      private static const BUSY:String = "replay";

      private static var playWhenSaved:String = null;

      public static function fetch(roomNumber:uint, matchSeed:uint, play:Boolean = false) : void
      {
         playWhenSaved = play ? roomNumber + "-" + matchSeed : null;
         try
         {
            var core:Object = Object(GameApp.mainInstance).var_13259;
            var packet:NetPacket = new NetPacket(GET);
            packet.writeUint(roomNumber);
            packet.writeUint(matchSeed);
            var sent:Boolean = core.sendToServer(packet);
            packet.method_839();
            incoming = null;
            modsOffer = null;
            last = sent ? "asked for " + roomNumber + "-" + matchSeed : "not connected";
            PrivateServer.log("replay share: " + last);
            if(sent)
            {
               Busy.start(BUSY,"GETTING THE REPLAY",30000);
            }
            else
            {
               DummyDrift.show("Not connected to the server: no replay.",2500);
               BackTrail.stayed("not connected");
            }
         }
         catch(e:Error)
         {
            PrivateServer.log("replay share: could not ask (" + e.message + ")");
            BackTrail.stayed("could not ask for the replay");
         }
      }

      private static function onPacket(packet:Object) : Boolean
      {
         if(packet == null || (packet.type != STORED && packet.type != DATA && packet.type != MODS && packet.type != SHARED))
         {
            return false;
         }
         try
         {
            if(packet.type == SHARED)
            {
               var code:String = packet.readString();
               var said:String = packet.readString();
               Busy.done(BUSY);
               last = code ? "shared as " + code : "share refused: " + said;
               PrivateServer.log("replay share: " + last);
               var asked:Object = sharing;
               sharing = null;
               if(asked != null)
               {
                  asked.done(code || null,code ? null : said);
               }
               return true;
            }
            if(packet.type == STORED)
            {
               var kept:Boolean = packet.method_5885();
               var message:String = packet.readString();
               last = (kept ? "kept: " : "refused: ") + message;
               PrivateServer.log("replay share: the server says " + last);
               return true;
            }
            if(packet.type == MODS)
            {
               modsOffer = {"room":packet.readUint(),"seed":packet.readUint(),"web":packet.readUint(),"ticket":packet.readString()};
               modsOffer.mods = readMods(packet);
               PrivateServer.log("replay share: the server holds " + modsOffer.mods.length + " of the recording's mods");
               return true;
            }
            onData(packet);
         }
         catch(e:Error)
         {
            PrivateServer.log("replay share: bad packet " + packet.type + " (" + e.message + ")");
            incoming = null;
            Busy.done(BUSY);
            BackTrail.stayed("the replay didn't arrive");
         }
         return true;
      }

      private static function onData(packet:Object) : void
      {
         var r:uint = packet.readUint();
         var s:uint = packet.readUint();
         var total:uint = packet.readUint();
         var off:uint = packet.readUint();
         var n:uint = packet.readUint();
         if(total == 0)
         {
            last = "the server keeps no replay of " + r + "-" + s;
            PrivateServer.log("replay share: " + last);
            Busy.done(BUSY);
            if(r == 0 && s == 0 && codeDone(null,"no replay has that code"))
            {
               return;
            }
            DummyDrift.show("No replay: the server keeps none of that match.",3000);
            BackTrail.stayed("no replay on the server");
            return;
         }
         if(total > MAX_REPLAY || n > PART_SIZE)
         {
            throw new Error("too large");
         }
         if(off == 0)
         {
            incoming = {"room":r,"seed":s,"total":total,"bytes":new ByteArray()};
         }
         if(incoming == null || incoming.room != r || incoming.seed != s || incoming.total != total || incoming.bytes.length != off)
         {
            incoming = null;
            throw new Error("part out of order");
         }
         var bytes:ByteArray = incoming.bytes;
         for(var i:uint = 0; i < n; i++)
         {
            bytes.writeByte(packet.method_7061());
         }
         var name:String = packet.readString();
         var mods:Array = readMods(packet);
         if(bytes.length < total)
         {
            if(Busy.waiting(BUSY))
            {
               Busy.start(BUSY,"GETTING THE REPLAY " + Math.floor(bytes.length * 100 / total) + "%",30000);
            }
            return;
         }
         incoming = null;
         Busy.done(BUSY);
         if(save(name,bytes))
         {
            if(r == 0 && s == 0)
            {
               codeDone(name,null);
            }
            ModCheck.refresh();
            var differ:String = differences(mods,ModCheck.list());
            if(differ == null)
            {
               if(playWhenSaved == r + "-" + s)
               {
                  playWhenSaved = null;
                  play(name);
                  return;
               }
               PrivateServer.log("replay share: saved " + name + " (in the Replays list)");
            }
            else
            {
               PrivateServer.log("replay share: recorded with other content mods (" + differ + ")");
               var held:Object = modsOffer != null && modsOffer.room == r && modsOffer.seed == s ? modsOffer : null;
               modsOffer = null;
               var watch:Function = null;
               if(playWhenSaved == r + "-" + s)
               {
                  playWhenSaved = null;
                  watch = function():void
                  {
                     play(name);
                  };
               }
               if(ModShare.offerReplay(held ? held.web : 0,held ? held.ticket : null,held ? held.mods : [],mods,differ,watch))
               {
                  return;
               }
               Modal.show("Replay saved","It's in the Replays list. It was recorded with other content mods than yours, and " +
                  "replays play back with the mods you have on, so it may play out differently.\n\n" + differ.split("; ").join("\n"),
                  watch != null ? [{"label":"Watch anyway","action":watch},{"label":"Close"}] : null,true);
            }
         }
      }

      private static function writeMods(packet:NetPacket, mods:Array) : void
      {
         var m:int = Math.min(mods.length,MAX_MODS);
         packet.writeUint(m);
         for(var i:int = 0; i < m; i++)
         {
            packet.writeString(String(mods[i]));
         }
      }

      private static function readMods(packet:Object) : Array
      {
         var m:uint = packet.readUint();
         if(m > MAX_MODS)
         {
            throw new Error(m + " mods");
         }
         var out:Array = [];
         for(var i:uint = 0; i < m; i++)
         {
            out.push(packet.readString());
         }
         return out;
      }

      public static function differences(recorded:Array, here:Array) : String
      {
         var a:Object = {};
         var b:Object = {};
         var e:String;
         for each(e in recorded)
         {
            a[e.split("#")[0]] = e;
         }
         for each(e in here)
         {
            b[e.split("#")[0]] = e;
         }
         var onlyThere:Array = [];
         var onlyHere:Array = [];
         var changed:Array = [];
         var k:String;
         for(k in a)
         {
            if(b[k] == null)
            {
               onlyThere.push(k);
            }
            else if(b[k] != a[k])
            {
               changed.push(k);
            }
         }
         for(k in b)
         {
            if(a[k] == null)
            {
               onlyHere.push(k);
            }
         }
         var parts:Array = [];
         if(onlyThere.length > 0)
         {
            parts.push("missing here: " + onlyThere.sort().join(", "));
         }
         if(onlyHere.length > 0)
         {
            parts.push("not in the recording: " + onlyHere.sort().join(", "));
         }
         if(changed.length > 0)
         {
            parts.push("other contents: " + changed.sort().join(", "));
         }
         return parts.length > 0 ? parts.join("; ") : null;
      }

      public static function play(name:String) : Boolean
      {
         if(ReplayIndex.play(class_51.method_3608().resolvePath(name)))
         {
            PrivateServer.log("replay share: playing " + name);
            return true;
         }
         PrivateServer.log("replay share: could not play " + name);
         DummyDrift.show("Replay saved: it's in the Replays list.",4000);
         BackTrail.stayed("the replay didn't play");
         return false;
      }

      private static function save(name:String, bytes:ByteArray) : Boolean
      {
         if(!SAFE_NAME.test(name) || name.indexOf("..") >= 0)
         {
            last = "refused the file name " + name;
            PrivateServer.log("replay share: " + last);
            return false;
         }
         var dir:File = class_51.method_3608();
         dir.createDirectory();
         var file:File = dir.resolvePath(name);
         if(!file.exists)
         {
            var out:FileStream = new FileStream();
            out.open(file,FileMode.WRITE);
            out.writeBytes(bytes);
            out.close();
         }
         last = "saved " + bytes.length + " bytes as " + file.nativePath;
         PrivateServer.log("replay share: " + last);
         return true;
      }
   }
}
