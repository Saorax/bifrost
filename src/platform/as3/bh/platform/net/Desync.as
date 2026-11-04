package bh.platform.net
{
   import flash.utils.ByteArray;
   import flash.utils.getTimer;

   public final class Desync
   {
      public static const EVERY:int = 4;
      public static const SEND:int = 6;
      public static const LOG_LIMIT:int = 5;
      public static const LOG_HASH_EVERY:int = 10;
      public static const LOG_HASH_LIMIT:int = 400;
      private static var hashLines:int = 0;
      private static var missing:int = 0;

      private static var mine:Object = {};
      private static var order:Array = [];
      private static var details:Object = {};
      private static var theirs:Object = {};
      private static var hashedThrough:Number = -1;

      public static var compared:uint = 0;
      public static var mismatches:uint = 0;
      public static var firstAt:int = -1;
      public static var unknownLayout:uint = 0;
      private static var logged:int = 0;
      private static var hashes:uint = 0;
      private static var hashMs:int = 0;
      private static var hashSlowest:int = 0;

      public function Desync()
      {
      }

      public static function reset() : void
      {
         mine = {};
         order = [];
         details = {};
         theirs = {};
         hashedThrough = -1;
         dumped = false;
         hashes = 0;
         hashMs = 0;
         hashSlowest = 0;
         compared = 0;
         mismatches = 0;
         firstAt = -1;
         unknownLayout = 0;
         logged = 0;
         hashLines = 0;
         missing = 0;
      }

      public static function collect(core:Object, start:Number, final:Number) : void
      {
         if(final <= hashedThrough)
         {
            return;
         }
         var t:Number = Math.max(Math.floor(hashedThrough) + 1,Number(start));
         t = Math.ceil(t / 16) * 16;
         while((t / 16) % 5 != 1)
         {
            t += 16;
         }
         for(; t <= final; t += 80)
         {
            if(int(t / 80) % EVERY != 0)
            {
               continue;
            }
            var began:int = getTimer();
            var h:Object = playersHash(core,uint(t));
            var took:int = getTimer() - began;
            hashes++;
            hashMs += took;
            hashSlowest = Math.max(hashSlowest,took);
            if(h == null)
            {
               missing++;
               continue;
            }
            var rel:int = int(t - start);
            mine[rel] = h.all;
            details[rel] = h;
            if(int(t / 80) % (EVERY * LOG_HASH_EVERY) == 0 && hashLines < LOG_HASH_LIMIT)
            {
               hashLines++;
               PrivateServer.log("P2P hash at " + rel + " ms: " + uint(h.all).toString(16) + (missing > 0 ? " (" + missing +
                  " times without checkpoints so far)" : ""));
            }
            if(!dumped)
            {
               dumped = true;
               dump(core,rel,h);
            }
            order.push(rel);
            for(var peerName:String in theirs)
            {
               if(theirs[peerName][rel] != null)
               {
                  check(peerName,rel,uint(theirs[peerName][rel]));
               }
            }
         }
         hashedThrough = final;
         while(order.length > 64)
         {
            var old:int = order.shift();
            delete mine[old];
            delete details[old];
            for each(var peerHashes:Object in theirs)
            {
               delete peerHashes[old];
            }
         }
      }

      public static function shifted(by:Number) : void
      {
         if(hashedThrough >= 0)
         {
            hashedThrough = Math.max(-1,hashedThrough - by);
         }
      }

      public static function playersHash(core:Object, t:uint) : Object
      {
         var players:Object = core.var_7050;
         var all:uint = 2166136261;
         var parts:Array = [];
         var states:Array = [];
         for(var i:int = 0; i < int(players.length); i++)
         {
            var keeper:Object = players[i].var_7944;
            var cp:Object = keeper != null ? keeper.method_3072(t) : null;
            var bytes:ByteArray = cp != null ? cp.var_5133 as ByteArray : null;
            if(bytes == null)
            {
               return null;
            }
            var h:uint = playerHash(players[i],bytes);
            for(var k:int = 0; k < 4; k++)
            {
               all = uint((all ^ ((h >>> (k * 8)) & 255)) * 16777619);
            }
            parts.push(h);
            states.push(bytes);
         }
         return {"all":all,"parts":parts,"states":states};
      }

      private static const FIXED:int = 438;

      private static const FLAGS_AT:int = 144;

      private static const GFX_AT:int = 434;

      private static function sidekickSize(bytes:ByteArray) : int
      {
         var at:uint = bytes.position;
         var size:int = 0;
         try
         {
            bytes.position = FIXED + 125;
            var n:int = bytes.readInt();
            bytes.position += Math.max(n,0) * 4;
            var m:int = bytes.readInt();
            size = 125 + 4 + Math.max(n,0) * 4 + 4 + Math.max(m,0) * 24;
         }
         catch(e:Error)
         {
            size = 0;
         }
         bytes.position = at;
         return size;
      }

      private static function playerHash(player:Object, bytes:ByteArray) : uint
      {
         var len:int = int(bytes.length);
         var bot:int = player.var_7753 != null ? sidekickSize(bytes) : 0;
         var powersAt:int = FIXED + bot;
         var statsAt:int = -1;
         var statsEnd:int = len - TAIL - TRAIL;
         var at:uint = bytes.position;
         try
         {
            bytes.position = powersAt + 88;
            var n:int = bytes.readInt();
            statsAt = powersAt + 92 + Math.max(n,0) * 4 + (player.var_10012 != null ? 28 : 0) + 64;
         }
         catch(e:Error)
         {
            statsAt = -1;
         }
         bytes.position = at;
         var h:uint = fnv(2166136261,bytes,0,FLAGS_AT);
         var flags:uint = 0;
         try
         {
            bytes.position = FLAGS_AT;
            flags = bytes.readUnsignedInt() & ~uint(4 | 8);
         }
         catch(e:Error)
         {
         }
         bytes.position = at;
         for(var k:int = 3; k >= 0; k--)
         {
            h = uint((h ^ ((flags >>> (k * 8)) & 255)) * 16777619);
         }
         h = fnv(h,bytes,FLAGS_AT + 4,GFX_AT);
         h = fnv(h,bytes,GFX_AT + 4,FIXED);
         if(statsAt >= 0 && statsAt + STATS_FIXED == statsEnd)
         {
            h = fnv(h,bytes,powersAt,statsEnd);
            return fnv(h,bytes,len - TAIL,len);
         }
         var maps:uint = statsAt >= 0 && statsAt + STATS_FIXED + 16 <= statsEnd ? mapsHash(bytes,statsAt + STATS_FIXED,statsEnd) : 0;
         if(maps == 0)
         {
            unknownLayout++;
            if(statsEnd <= powersAt)
            {
               return fnv(h,bytes,powersAt,len);
            }
            h = fnv(h,bytes,powersAt,statsEnd);
            return fnv(h,bytes,len - TAIL,len);
         }
         h = fnv(h,bytes,powersAt,statsAt + STATS_FIXED + 16);
         h = uint((h ^ maps) * 16777619);
         return fnv(h,bytes,len - TAIL,len);
      }

      private static const STATS_FIXED:int = 172;
      private static const TRAIL:int = 67;
      private static const TAIL:int = 15;

      private static function mapsHash(bytes:ByteArray, from:int, end:int) : uint
      {
         var sizes:Array = [16,12,8];
         var p:int = from + 16;
         var total:uint = 0;
         for(var m:int = 0; m < 3; m++)
         {
            var sum:uint = 0;
            var count:uint = 0;
            while(true)
            {
               if(p >= end)
               {
                  return 0;
               }
               var flag:int = bytes[p];
               p++;
               if(flag == 0)
               {
                  break;
               }
               if(flag != 1 || p + int(sizes[m]) > end)
               {
                  return 0;
               }
               sum = uint(sum + fnv(2166136261,bytes,p,p + int(sizes[m])));
               count++;
               p += int(sizes[m]);
            }
            total = uint((total ^ uint(sum + count * 31 + m)) * 16777619);
         }
         return p == end ? (total == 0 ? 1 : total) : 0;
      }

      private static function fnv(h:uint, bytes:ByteArray, from:int, to:int) : uint
      {
         for(var k:int = from; k < to; k++)
         {
            h = uint((h ^ bytes[k]) * 16777619);
         }
         return h;
      }

      public static function write(body:ByteArray) : void
      {
         var n:int = Math.min(SEND,order.length);
         body.writeByte(n);
         for(var i:int = order.length - n; i < order.length; i++)
         {
            body.writeUnsignedInt(uint(order[i]));
            body.writeUnsignedInt(uint(mine[order[i]]));
         }
      }

      public static function read(peerName:String, b:ByteArray) : void
      {
         if(b.bytesAvailable < 1)
         {
            return;
         }
         var n:int = b.readUnsignedByte();
         if(theirs[peerName] == null)
         {
            theirs[peerName] = {};
         }
         for(var i:int = 0; i < n && b.bytesAvailable >= 8; i++)
         {
            var rel:int = int(b.readUnsignedInt());
            var hash:uint = b.readUnsignedInt();
            if(theirs[peerName][rel] != null || (order.length > 0 && rel < int(order[0])))
            {
               continue;
            }
            theirs[peerName][rel] = hash;
            if(mine[rel] != null)
            {
               check(peerName,rel,hash);
            }
         }
      }

      private static var dumped:Boolean = false;

      private static function dump(core:Object, rel:int, h:Object) : void
      {
         try
         {
            for(var i:int = 0; i < h.states.length; i++)
            {
               var b:ByteArray = h.states[i];
               var hex:Array = [];
               for(var k:int = 0; k < int(b.length); k++)
               {
                  var v:uint = b[k];
                  hex.push((v < 16 ? "0" : "") + v.toString(16));
               }
               var p:Object = core.var_7050[i];
               PrivateServer.log("P2P checkpoint at " + rel + " ms, player " + i + " (ID " + uint(p.var_14656) + ", flags " +
                  uint(p.var_1249) + ", " + b.length + " bytes): " + hex.join(""));
            }
         }
         catch(e:Error)
         {
         }
      }

      private static function check(peerName:String, rel:int, theirHash:uint) : void
      {
         compared++;
         if(uint(mine[rel]) == theirHash)
         {
            return;
         }
         mismatches++;
         if(firstAt < 0)
         {
            firstAt = rel;
         }
         if(logged >= LOG_LIMIT)
         {
            return;
         }
         logged++;
         var d:Object = details[rel];
         var lines:Array = [];
         if(d != null)
         {
            for(var i:int = 0; i < d.parts.length; i++)
            {
               lines.push("player " + i + " " + uint(d.parts[i]).toString(16) + " " + describe(d.states[i]));
            }
         }
         PrivateServer.log("P2P DESYNC at " + rel + " ms with " + peerName + ": ours " + uint(mine[rel]).toString(16) +
            ", theirs " + theirHash.toString(16) + (lines.length ? "; " + lines.join("; ") : ""));
         if(logged == 1 && d != null)
         {
            for(var j:int = 0; j < d.states.length; j++)
            {
               PrivateServer.log("P2P desync checkpoint at " + rel + " ms, player " + j + ": " + hex(d.states[j]));
            }
         }
      }

      private static function hex(b:ByteArray) : String
      {
         var out:Array = [];
         for(var k:int = 0; k < int(b.length); k++)
         {
            var v:uint = b[k];
            out.push((v < 16 ? "0" : "") + v.toString(16));
         }
         return out.join("");
      }

      public static function describe(bytes:ByteArray) : String
      {
         var at:uint = bytes.position;
         var out:Array = [];
         try
         {
            bytes.position = 0;
            out.push(bytes.readUnsignedInt(),bytes.readUnsignedInt());
            for(var i:int = 0; i < 13 && bytes.bytesAvailable >= 8; i++)
            {
               out.push(int(bytes.readDouble() * 100) / 100);
            }
         }
         catch(e:Error)
         {
         }
         bytes.position = at;
         return "[" + out.join(" ") + "]";
      }

      public static function cost() : String
      {
         return hashes + " checkpoints hashed in " + hashMs + " ms (slowest " + hashSlowest + " ms)";
      }

      public static function summary() : String
      {
         return compared == 0 ? "no desync checks (the other side sent no hashes)" :
            compared + " desync checks, " + (mismatches == 0 ? "all matched" : mismatches + " DIFFERED (first at " + firstAt + " ms)");
      }
   }
}
