package bh.platform.net
{
   import flash.events.Event;
   import flash.filesystem.File;
   import flash.filesystem.FileMode;
   import flash.filesystem.FileStream;
   import flash.utils.ByteArray;
   import flash.utils.getTimer;
   import bh.platform.Hooks;
   import bh.platform.Platform;

   public final class SpectateFeed
   {
      public static const START:int = 10104;
      public static const INPUTS:int = 10106;
      public static const BEGIN:int = 10107;

      public static var last:String = "idle";

      public static var lead:int = 0;

      private static var rows:Array = null;
      private static var next:int = 0;
      private static var t0:int = 0;
      private static var endAt:uint = 0;
      private static var ended:Boolean = false;
      private static var batches:int = 0;
      private static var stage:Object = null;

      public function SpectateFeed()
      {
      }

      public static function play(name:String, holdPort:int = 0) : String
      {
         stop();
         var core:Object = Object(GameApp.mainInstance).var_13259;
         if(holdPort > 0 && !(core.var_9913 != null && core.var_9913.isConnected()))
         {
            core.var_9913 = new TcpConnection(null,null);
            core.var_9913.Connect("127.0.0.1",holdPort);
         }
         var r:Object = readReplay(name);
         if(r.error != null)
         {
            return last = r.error;
         }
         var replay:class_320 = r.replay;
         var heroes:uint = r.heroes;
         var start:NetPacket = r.start;
         rows = r.rows;
         endAt = replay.var_12978;
         next = 0;
         batches = 0;
         ended = false;
         if(!Net.deliver(start))
         {
            rows = null;
            return last = "no link updater";
         }
         var begin:NetPacket = new NetPacket(BEGIN);
         begin.method_5184(true);
         Net.deliver(readable(begin));
         t0 = getTimer();
         stage = GameApp.mainInstance.stage;
         stage.addEventListener(Event.ENTER_FRAME,onFrame);
         last = "playing " + r.file + ": seed " + replay.var_10040 + ", level " + replay.var_12531.var_8543 + ", " +
            replay.var_4813.length + " players, " + heroes + " legends each, " + rows.length + " inputs, end " + endAt +
            ", game mode now " + core.var_3595;
         return last;
      }

      private static function readReplay(name:String, startType:int = START) : Object
      {
         var file:File = class_51.method_3608().resolvePath(name);
         if(!file.exists)
         {
            return {"error":"no replay " + name};
         }
         var bytes:ByteArray = new ByteArray();
         var s:FileStream = new FileStream();
         s.open(file,FileMode.READ);
         s.readBytes(bytes);
         s.close();
         ScreenManager.var_9407.method_834(bytes,file.name);
         var bits:BitStream = new BitStream(bytes);
         var replay:class_320 = new class_320();
         var ok:Boolean = replay.method_2646(file.name,bits);
         bits.method_6958();
         if(!ok)
         {
            return {"error":"replay not readable: " + file.name};
         }
         var heroes:uint = replay.var_8999.method_327();
         var start:NetPacket = startPacket(replay.var_10040,replay.var_12531.var_8543,0,replay.var_8999,heroes,
            replay.var_4813,replay.var_14656,replay.var_13290,replay.var_7185,startType);
         var out:Array = [];
         for each(var ent:uint in replay.var_4813)
         {
            var times:Vector.<uint> = Object(replay.var_4180).h[ent];
            var inputs:Vector.<uint> = Object(replay.var_6776).h[ent];
            if(times == null || inputs == null)
            {
               continue;
            }
            for(var i:int = 0; i < times.length; i++)
            {
               out.push([times[i],ent,inputs[i]]);
            }
         }
         out.sortOn([0,1],[Array.NUMERIC,Array.NUMERIC]);
         var lastOf:Object = {};
         for each(var row:Array in out)
         {
            lastOf[row[1]] = row[2];
         }
         for(var who:String in lastOf)
         {
            out.push([uint(replay.var_12978 + 2500),uint(who),uint(lastOf[who])]);
         }
         return {"replay":replay,"heroes":heroes,"start":start,"rows":out,"file":file.name};
      }

      public static function record(name:String, out:String, batchMs:int = 50) : String
      {
         var r:Object = readReplay(name,UP_START);
         if(r.error != null)
         {
            return r.error;
         }
         var lines:Array = [JSON.stringify({"t":0,"type":START,"hex":hexOf(NetPacket(r.start).method_7070())})];
         var all:Array = r.rows;
         var batchCount:int = 0;
         var i:int = 0;
         while(i < all.length)
         {
            var until:uint = uint(all[i][0]) + uint(batchMs);
            var j:int = i;
            while(j < all.length && uint(all[j][0]) < until)
            {
               j++;
            }
            var p:NetPacket = inputsPacket(all.slice(i,j),UP_INPUTS);
            lines.push(JSON.stringify({"t":Number(all[j - 1][0]) / 1000,"type":INPUTS,"hex":hexOf(p.method_7070())}));
            batchCount++;
            i = j;
         }
         var file:File = Platform.dataFile(out);
         var fs:FileStream = new FileStream();
         fs.open(file,FileMode.WRITE);
         fs.writeUTFBytes(lines.join("\n") + "\n");
         fs.close();
         return "recorded " + r.file + " as " + file.nativePath + ": " + all.length + " rows in " + batchCount +
            " batches, end " + class_320(r.replay).var_12978;
      }

      private static function hexOf(b:ByteArray) : String
      {
         var out:String = "";
         for(var i:int = 0; i < b.length; i++)
         {
            var v:int = b[i];
            out += (v < 16 ? "0" : "") + v.toString(16);
         }
         return out;
      }

      public static function state() : String
      {
         if(rows == null)
         {
            return last;
         }
         return last + "; sent " + next + "/" + rows.length + " in " + batches + " batches, next at " +
            (next < rows.length ? rows[next][0] : "-") + ", feed time " + (getTimer() - t0 + lead);
      }

      public static function stop() : void
      {
         if(stage != null)
         {
            stage.removeEventListener(Event.ENTER_FRAME,onFrame);
            stage = null;
         }
         rows = null;
      }

      private static function onFrame(e:Event) : void
      {
         try
         {
            var now:uint = uint(getTimer() - t0 + lead);
            var upTo:int = next;
            while(upTo < rows.length && uint(rows[upTo][0]) <= now)
            {
               upTo++;
            }
            var core:Object = Object(GameApp.mainInstance).var_13259;
            if(next == 0 && core.var_9913 != null && !core.var_9913.isConnected())
            {
               last = last.split("; waiting")[0] + "; waiting for the spectate connection";
               t0 = getTimer();
               return;
            }
            if(upTo > next)
            {
               Net.deliver(inputsPacket(rows.slice(next,upTo)));
               next = upTo;
               batches++;
            }
            if(next >= rows.length && !ended)
            {
               ended = true;
               last = "all sent: " + rows.length + " inputs in " + batches + " batches, " + (getTimer() - t0) + " ms";
               stop();
            }
         }
         catch(err:Error)
         {
            last = "feed error: " + err.getStackTrace();
            stop();
         }
      }

      private static function readable(packet:NetPacket) : NetPacket
      {
         var body:ByteArray = new ByteArray();
         var written:ByteArray = packet.method_7070();
         body.writeBytes(written,0,written.length);
         body.position = 0;
         var type:int = int(packet.type);
         packet.method_839();
         return new NetPacket(type,body);
      }

      public static function startPacket(seed:uint, level:uint, teamMode:uint, settings:class_166, heroes:uint,
         entities:Object, playerIds:Object, names:Object, data:Object, type:int = START) : NetPacket
      {
         var p:NetPacket = new NetPacket(type);
         var extras:Boolean = false;
         for each(var e:uint in entities)
         {
            if(data[e] != null && class_294(data[e]).var_9478 != null)
            {
               extras = true;
            }
         }
         p.writeUint(seed);
         p.writeUint(level);
         p.writeUint(teamMode);
         p.writeUint(0);
         p.writeUint(0);
         p.writeUint(heroes);
         p.method_5184(extras);
         settings.method_4231(p);
         var count:uint = 0;
         for each(e in entities)
         {
            if(data[e] != null)
            {
               count++;
            }
         }
         p.writeUint(count);
         for each(e in entities)
         {
            var d:class_294 = data[e];
            if(d == null)
            {
               continue;
            }
            p.writeUint(e);
            p.writeUint(uint(playerIds[e]));
            p.writeUint(d.var_9352);
            p.writeString(names[e] != null ? String(names[e]) : "");
            p.writeString(d.var_2901);
            p.writeUint(d.var_2826);
            p.writeUint(d.var_12895);
            p.writeUint(d.var_3243);
            p.writeUint(d.var_7774);
            p.writeUint(d.var_7685);
            p.writeUint(d.var_12935);
            p.writeUint(d.var_8902);
            p.writeUint(d.var_2464);
            p.writeUint(d.var_11804);
            for(var k:int = 0; k < 8; k++)
            {
               p.writeUint(d.var_7882[k]);
            }
            p.method_6483(d.var_2379);
            p.method_6483(d.var_15112);
            var flags:Array = d.var_2165.var_3813;
            for(k = 0; k < flags.length; k += 2)
            {
               p.method_5184(true);
               p.writeUint(uint(flags[k]));
               p.writeUint(k + 1 < flags.length ? uint(flags[k + 1]) : 0);
            }
            p.method_5184(false);
            p.method_6483(d.var_4349);
            p.writeUint(d.var_6454);
            p.writeUint(d.var_3540);
            p.writeUint(d.var_6607);
            p.method_6483(d.var_6061);
            for(k = 0; k < int(heroes); k++)
            {
               var h:class_188 = d.var_12798[k];
               p.writeUint(h.var_11835 & 0xFFFF);
               p.writeUint(h.var_14823);
               p.writeUint(h.var_3173);
               p.writeUint(h.var_15258);
               p.writeUint(h.var_9049);
            }
            if(extras)
            {
               var x:class_183 = d.var_9478;
               p.method_5184(x != null);
               if(x != null)
               {
                  p.method_6483(x.var_13360);
                  p.writeUint(x.var_11025);
                  p.writeUint(x.var_4371);
               }
            }
         }
         if(type == UP_START)
         {
            p.writeUint(ITEMS_MARK);
            p.writeUint(uint(Object(GameApp.mainInstance).var_13259.var_14656));
         }
         return type == START ? readable(p) : p;
      }

      public static const ITEMS_MARK:uint = 0x4D4F4449;

      private static var mapped:int = 0;

      private static function remapStart(packet:NetPacket) : Boolean
      {
         try
         {
            var bits:Object = packet.var_5085;
            if(bits == null || uint(bits.var_11198) % 8 != 0)
            {
               return false;
            }
            var at:uint = uint(uint(bits.var_11198) / 8);
            var host:uint = copyStart(new NetPacket(START,bits.var_15327,at),new NetPacket(START),0);
            var me:uint = uint(Object(GameApp.mainInstance).var_13259.var_14656);
            if(host == 0 || host == me || !ModItems.knows(host))
            {
               if(host != 0 && host != me)
               {
                  PrivateServer.log("spectate: no mod item list from the host " + host + "; its item ids are used as they are");
               }
               return false;
            }
            mapped = 0;
            var w:NetPacket = new NetPacket(START);
            copyStart(new NetPacket(START,bits.var_15327,at),w,host);
            var r:NetPacket = readable(w);
            PrivateServer.log("spectate: match set-up with the host " + host + "'s mod item ids turned into this PC's (" + mapped +
               " changed)");
            Object(GameApp.mainInstance).var_13259.linkUpdater.method_7460(r);
            r.method_839();
            return true;
         }
         catch(e:Error)
         {
            PrivateServer.log("spectate: match set-up ids not mapped (" + e.message + ")");
         }
         return false;
      }

      private static function itemOf(table:String, host:uint, v:uint) : uint
      {
         if(host == 0)
         {
            return v;
         }
         var out:uint = ModItems.id(table,host,v);
         if(out != v)
         {
            mapped++;
         }
         return out;
      }

      private static function copyStart(r:NetPacket, w:NetPacket, host:uint) : uint
      {
         var k:int;
         for(k = 0; k < 5; k++)
         {
            w.writeUint(r.readUint());
         }
         var heroes:uint = r.readUint();
         w.writeUint(heroes);
         var extras:Boolean = r.method_5885();
         w.method_5184(extras);
         var settings:class_166 = new class_166();
         settings.method_1570(r);
         settings.method_4231(w);
         var count:uint = r.readUint();
         w.writeUint(count);
         for(var n:uint = 0; n < count; n++)
         {
            w.writeUint(r.readUint());
            w.writeUint(r.readUint());
            w.writeUint(r.readUint());
            w.writeString(r.readString());
            w.writeString(r.readString());
            for(k = 0; k < 3; k++)
            {
               w.writeUint(r.readUint());
            }
            w.writeUint(itemOf("ColorSchemeTypes",host,r.readUint()));
            w.writeUint(itemOf("SpawnBotTypes",host,r.readUint()));
            w.writeUint(itemOf("CompanionTypes",host,r.readUint()));
            w.writeUint(r.readUint());
            w.writeUint(itemOf("TrailEffectTypes",host,r.readUint()));
            w.writeUint(itemOf("PlayerThemeTypes",host,r.readUint()));
            for(k = 0; k < 8; k++)
            {
               w.writeUint(itemOf("TauntTypes",host,r.readUint()));
            }
            w.method_6483(itemOf("TauntTypes",host,r.method_2544()));
            w.method_6483(itemOf("TauntTypes",host,r.method_2544()));
            while(r.method_5885())
            {
               w.method_5184(true);
               w.writeUint(r.readUint());
               w.writeUint(r.readUint());
            }
            w.method_5184(false);
            w.method_6483(itemOf("avatarTypes",host,r.method_2544()));
            for(k = 0; k < 3; k++)
            {
               w.writeUint(r.readUint());
            }
            w.method_6483(itemOf("MonikerTypes",host,r.method_2544()));
            for(k = 0; k < int(heroes); k++)
            {
               w.writeUint(r.readUint());
               w.writeUint(itemOf("costumeTypes",host,r.readUint()));
               w.writeUint(r.readUint());
               var weapons:uint = r.readUint();
               var both:uint = host != 0 ? ModItems.weapons(host,weapons) : weapons;
               if(both != weapons)
               {
                  mapped++;
               }
               w.writeUint(both);
               w.writeUint(r.readUint());
            }
            if(extras)
            {
               var has:Boolean = r.method_5885();
               w.method_5184(has);
               if(has)
               {
                  w.method_6483(r.method_2544());
                  w.writeUint(r.readUint());
                  w.writeUint(r.readUint());
               }
            }
         }
         var rest:int = int(r.var_5085.var_15327.length) * 8 - int(r.var_5085.var_11198);
         if(rest >= 8 && r.readUint() == ITEMS_MARK)
         {
            return r.readUint();
         }
         return 0;
      }

      public static function inputsPacket(batch:Array, type:int = INPUTS) : NetPacket
      {
         var p:NetPacket = new NetPacket(type);
         p.writeUint(batch.length);
         for each(var r:Array in batch)
         {
            p.method_2167(4,uint(r[1]));
            p.writeUint(uint(r[0]));
            p.method_2167(14,uint(r[2]));
         }
         return type == INPUTS ? readable(p) : p;
      }

      public static const TICKET:int = 2420;
      public static const UP_START:int = 11080;
      public static const UP_INPUTS:int = 11081;
      public static const UP_END:int = 11082;
      public static const ROOM:int = 2445;
      public static const LEFT_ROOM:int = 2412;
      public static const SPECTATING:uint = 262144;

      private static var registered:Boolean = false;
      private static var hosting:Boolean = false;
      private static var offered:Boolean = false;
      private static var sentAt:Object = {};
      private static var lastIn:Object = {};
      private static var lastUp:Number = 0;
      public static const HEARTBEAT:int = 250;
      public static var uploaded:uint = 0;
      public static var uploadedRows:uint = 0;

      public static function register() : void
      {
         if(registered)
         {
            return;
         }
         registered = true;
         Hooks.packetReceived.add(onPacket);
      }

      private static function onPacket(packet:Object) : Boolean
      {
         if(int(packet.type) == START)
         {
            return remapStart(NetPacket(packet));
         }
         if(int(packet.type) == ROOM || int(packet.type) == LEFT_ROOM)
         {
            earlyEnd = -1;
            leaveSpectatedMatch();
            return false;
         }
         if(int(packet.type) == ABRUPT && spectating())
         {
            earlyEnd = Number(NetPacket(packet).readUint());
            if(!watchingEnd)
            {
               watchingEnd = true;
               Hooks.frameStarting.add(checkEnd);
            }
            PrivateServer.log("spectate: the host left the match early; watching up to " + uint(earlyEnd) + " ms, then the room");
            return true;
         }
         if(int(packet.type) != TICKET || PrivateServer.host == null)
         {
            return false;
         }
         var n:NetPacket = NetPacket(packet);
         var player:uint = n.readUint();
         var host:String = n.readString();
         var port:uint = n.method_2544();
         var ticket:String = n.readString();
         var extra:uint = n.readUint();
         var w:NetPacket = new NetPacket(TICKET);
         w.writeUint(player);
         w.writeString(host != "" ? host : PrivateServer.host);
         w.method_6483(port != 0 ? port : PrivateServer.port);
         w.writeString(ticket);
         w.writeUint(extra);
         var r:NetPacket = readable(w);
         startRejoin(ticket.indexOf(REJOIN_PREFIX) == 0);
         PrivateServer.log("spectate: 2420 for room " + extra + ", connecting to " + (host != "" ? host : PrivateServer.host) +
            ":" + (port != 0 ? port : PrivateServer.port) + (rejoining ? " (rejoining this PC's own match)" : ""));
         Object(GameApp.mainInstance).var_13259.linkUpdater.method_7046(r);
         r.method_839();
         return true;
      }

      public static const REJOIN_PREFIX:String = "rejoin-";
      public static const CAUGHT_UP_GAP:int = HEARTBEAT + 50;
      public static const CAUGHT_UP_FOR:int = 500;
      public static var rejoining:Boolean = false;
      public static var caughtUpAt:Number = -1;
      private static var rejoinSince:int = 0;
      private static var closeSince:int = -1;
      private static var rejoinLogAt:int = 0;
      private static var rejoinSeen:Boolean = false;
      private static var lastStepped:Number = 0;
      private static var rejoinHooked:Boolean = false;
      private static var savedDelay:int = -1;

      private static function startRejoin(on:Boolean) : void
      {
         restoreDelay();
         if(on)
         {
            savedDelay = int(class_51.var_4540);
            class_51.var_4540 = 0;
         }
         rejoining = on;
         caughtUpAt = -1;
         closeSince = -1;
         rejoinSeen = false;
         lastStepped = 0;
         rejoinSince = rejoinLogAt = getTimer();
         if(on && !rejoinHooked)
         {
            rejoinHooked = true;
            Hooks.frameStarting.add(checkRejoin);
         }
      }

      private static function restoreDelay() : void
      {
         if(savedDelay >= 0)
         {
            class_51.var_4540 = uint(savedDelay);
            savedDelay = -1;
         }
      }

      private static function stopRejoin(why:String) : void
      {
         restoreDelay();
         if(rejoinHooked)
         {
            rejoinHooked = false;
            Hooks.frameStarting.remove(checkRejoin);
         }
         if(why != null)
         {
            PrivateServer.log("rejoin: " + why);
         }
      }

      private static function checkRejoin() : void
      {
         try
         {
            var now:int = getTimer();
            if(!spectating())
            {
               if(rejoinSeen)
               {
                  rejoining = false;
                  stopRejoin("the spectated match ended before it caught up");
               }
               else if(now - rejoinSince > 30000)
               {
                  rejoining = false;
                  stopRejoin("the spectated match never started");
               }
               return;
            }
            var core:Object = Object(GameApp.mainInstance).var_13259;
            var stepped:Number = Number(core.var_12659);
            var newest:Number = Number(core.var_13969);
            var gap:Number = newest - stepped;
            if(uint(core.gameState) == 2 || stepped + 1000 < lastStepped)
            {
               rejoining = false;
               stopRejoin("the spectated match ended (state " + uint(core.gameState) + ", stream " + uint(newest) +
                  " ms) before it caught up");
               return;
            }
            lastStepped = stepped;
            if(!rejoinSeen)
            {
               rejoinSeen = true;
               PrivateServer.log("rejoin: catching up from " + uint(stepped) + " ms, stream at " + uint(newest) + " ms");
            }
            if(now - rejoinLogAt >= 1000)
            {
               rejoinLogAt = now;
               PrivateServer.log("rejoin: stepped " + uint(stepped) + " ms, stream " + uint(newest) + " ms, gap " + int(gap) + " ms");
            }
            if(gap > CAUGHT_UP_GAP)
            {
               closeSince = -1;
               return;
            }
            if(closeSince < 0)
            {
               closeSince = now;
            }
            else if(now - closeSince >= CAUGHT_UP_FOR)
            {
               caughtUpAt = stepped;
               stopRejoin("caught up at " + uint(stepped) + " ms (stream " + uint(newest) + " ms), " +
                  ((now - rejoinSince) / 1000).toFixed(1) + " s after the ticket");
            }
         }
         catch(e:Error)
         {
            rejoining = false;
            stopRejoin("catch-up check failed (" + e.message + ")");
         }
      }

      public static const ABRUPT:int = 10102;
      private static var earlyEnd:Number = -1;
      private static var watchingEnd:Boolean = false;

      private static function spectating() : Boolean
      {
         try
         {
            var mode:uint = uint(Object(GameApp.mainInstance).var_13259.var_3595);
            return mode == SPECTATING || mode == 524288;
         }
         catch(e:Error)
         {
         }
         return false;
      }

      private static function checkEnd() : void
      {
         if(earlyEnd < 0)
         {
            return;
         }
         try
         {
            if(!spectating())
            {
               earlyEnd = -1;
               return;
            }
            var core:Object = Object(GameApp.mainInstance).var_13259;
            var now:uint = uint(core.var_12659);
            now -= now % 16;
            if(now > earlyEnd)
            {
               PrivateServer.log("spectate: reached the early end at " + now + " ms; back to the room");
               earlyEnd = -1;
               core.method_4351();
            }
         }
         catch(e:Error)
         {
            earlyEnd = -1;
            PrivateServer.log("spectate: the early end failed (" + e.message + ")");
         }
      }

      private static function leaveSpectatedMatch() : void
      {
         try
         {
            var core:Object = Object(GameApp.mainInstance).var_13259;
            var mode:uint = uint(core.var_3595);
            if(mode != SPECTATING && mode != 524288 && mode != 2097152)
            {
               return;
            }
            core.method_1002();
            core.var_3595 = 8;
            core.setGameState(0);
            core.method_862();
            PrivateServer.log("spectate: the room again; the spectated match (mode " + mode + ") ended");
         }
         catch(err:Error)
         {
            PrivateServer.log("spectate: ending the spectated match failed (" + err.message + ")");
         }
      }

      public static function hostFrame(core:Object, start:Number, through:Number) : void
      {
         try
         {
            if(!offered)
            {
               offered = true;
               sentAt = {};
               lastIn = {};
               lastUp = 0;
               uploaded = uploadedRows = 0;
               hosting = offerStart(core);
            }
            if(!hosting || through < 0)
            {
               return;
            }
            var limit:Number = Math.min(start + through,Number(core.var_13849));
            var base:Number = start - 16;
            var batch:Array = [];
            for each(var p:Object in core.var_7050)
            {
               var hist:Object = p.var_10012 != null ? p.var_10012.var_11813 : null;
               if(hist == null)
               {
                  continue;
               }
               var ent:uint = uint(p.var_11355);
               var after:Number = sentAt[ent] != null ? Number(sentAt[ent]) : -1;
               var i:int = int(hist.length) - 1;
               while(i >= 0 && Number(hist[i].var_5941) > after)
               {
                  i--;
               }
               var newest:Number = after;
               for(i++; i < int(hist.length); i++)
               {
                  var t:Number = Number(hist[i].var_5941);
                  if(t > limit)
                  {
                     break;
                  }
                  batch.push([t <= base ? 0 : uint(t - base),ent,uint(hist[i].var_1212)]);
                  lastIn[ent] = uint(hist[i].var_1212);
                  newest = t;
               }
               sentAt[ent] = newest;
            }
            var now:Number = limit - base;
            if(batch.length == 0)
            {
               if(now - lastUp < HEARTBEAT)
               {
                  return;
               }
               for each(p in core.var_7050)
               {
                  ent = uint(p.var_11355);
                  batch.push([uint(now),ent,lastIn[ent] != null ? uint(lastIn[ent]) : 0]);
               }
               if(batch.length == 0)
               {
                  return;
               }
            }
            for each(var row:Array in batch)
            {
               lastUp = Math.max(lastUp,Number(row[0]));
            }
            batch.sortOn([0,1],[Array.NUMERIC,Array.NUMERIC]);
            var up:NetPacket = inputsPacket(batch,UP_INPUTS);
            core.sendToServer(up);
            up.method_839();
            uploaded++;
            uploadedRows += batch.length;
         }
         catch(err:Error)
         {
            hosting = false;
            PrivateServer.log("spectate: upload stopped (" + err.message + ")");
         }
      }

      private static function offerStart(core:Object) : Boolean
      {
         var recorder:Object = core.var_7524;
         var stream:Object = recorder != null ? recorder.var_12162 : null;
         if(stream == null || stream.var_15327 == null || stream.var_15327.length == 0)
         {
            PrivateServer.log("spectate: no replay recorder in this match; nothing offered");
            return false;
         }
         var bytes:ByteArray = new ByteArray();
         bytes.writeBytes(stream.var_15327,0,stream.var_15327.length);
         bytes.position = 0;
         var bits:BitStream = new BitStream(bytes);
         var header:class_320 = new class_320();
         header.method_2646("[sdr]spectate",bits,false);
         bits.method_6958();
         if(header.var_12531 == null || header.var_4813.length == 0)
         {
            PrivateServer.log("spectate: the recorder's header didn't read back; nothing offered");
            return false;
         }
         var up:NetPacket = startPacket(header.var_10040,header.var_12531.var_8543,0,header.var_8999,header.var_8999.method_327(),
            header.var_4813,header.var_14656,header.var_13290,header.var_7185,UP_START);
         core.sendToServer(up);
         up.method_839();
         PrivateServer.log("spectate: match set-up offered (seed " + header.var_10040 + ", level " + header.var_12531.var_8543 +
            ", " + header.var_4813.length + " players)");
         return true;
      }

      public static function resumeAt(core:Object, start:Number, at:Number) : void
      {
         offered = true;
         sentAt = {};
         lastIn = {};
         for each(var p:Object in core.var_7050)
         {
            var ent:uint = uint(p.var_11355);
            sentAt[ent] = at;
            if(p.var_10012 != null)
            {
               lastIn[ent] = RemoteInput.bitsAt(p.var_10012,uint(at));
            }
         }
         lastUp = at - (start - 16);
         uploaded = uploadedRows = 0;
         hosting = offerStart(core);
      }

      public static function hostEnd(abrupt:Boolean = false) : void
      {
         if(hosting)
         {
            try
            {
               var core:Object = Object(GameApp.mainInstance).var_13259;
               var up:NetPacket = new NetPacket(UP_END);
               up.method_5184(abrupt);
               up.writeUint(uint(lastUp));
               core.sendToServer(up);
               up.method_839();
            }
            catch(err:Error)
            {
            }
            PrivateServer.log("spectate: " + uploaded + " input batches (" + uploadedRows + " rows) uploaded this match" +
               (abrupt ? "; it ended early, spectators stop at " + uint(lastUp) + " ms" : ""));
         }
         hosting = offered = false;
      }
   }
}
