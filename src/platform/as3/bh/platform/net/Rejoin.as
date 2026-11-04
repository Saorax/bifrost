package bh.platform.net
{
   import bh.platform.Hooks;
   import flash.utils.getTimer;

   public final class Rejoin
   {
      public static const INPUTS:int = 11083;
      public static const FLAG:uint = 2;

      private static const JUMP:uint = 4000;
      private static const GAP:uint = 300;
      private static const HOLD:int = 500;

      public static var active:Boolean = false;
      public static var through:Number = -1;
      public static var caughtUpAt:Number = -1;

      public static var handedBackAt:Number = -1;

      private static var registered:Boolean = false;
      private static var pending:Array = [];
      private static var rows:uint = 0;
      private static var batches:uint = 0;
      private static var startedAt:int = 0;
      private static var nearSince:int = -1;
      private static var jumps:uint = 0;
      private static var jumpedMs:Number = 0;
      private static var slowest:int = 0;
      private static var lastLog:int = 0;
      private static var unknown:Object = {};

      public function Rejoin()
      {
      }

      public static function register() : void
      {
         if(registered)
         {
            return;
         }
         registered = true;
         Hooks.packetReceived.add(onPacket);
      }

      public static function begin(on:Boolean, room:uint) : void
      {
         active = on;
         through = -1;
         caughtUpAt = -1;
         handedBackAt = -1;
         if(on)
         {
            startedAt = lastLog = getTimer();
         }
         nearSince = -1;
         jumps = 0;
         jumpedMs = 0;
         slowest = 0;
         unknown = {};
         if(!on)
         {
            pending = [];
            rows = batches = 0;
         }
         else
         {
            PrivateServer.log("rejoin: rebuilding room " + room + "'s match from its start; " + pending.length +
               " streamed rows already here");
         }
      }

      public static function handBack(at:Number) : void
      {
         if(!active)
         {
            return;
         }
         PrivateServer.log("rejoin: handing the legend back at " + uint(at) + " ms (stream through " + uint(through) + " ms, " +
            batches + " batches, " + rows + " rows, " + jumps + " catch-up frames, slowest " + slowest + " ms, " +
            ((getTimer() - startedAt) / 1000).toFixed(1) + " s after the start)");
         active = false;
         handedBackAt = at;
         pending = [];
         rows = batches = 0;
      }

      public static function end(why:String) : void
      {
         if(!active)
         {
            return;
         }
         PrivateServer.log("rejoin: rebuilt match over (" + why + "): " + batches + " batches, " + rows + " rows, stream through " +
            through + " ms, " + (caughtUpAt >= 0 ? "caught up at " + uint(caughtUpAt) + " ms" : "never caught up") + ", " +
            jumps + " catch-up frames for " + uint(jumpedMs) + " ms of match, slowest frame " + slowest + " ms");
         active = false;
         pending = [];
         rows = batches = 0;
      }

      private static function onPacket(packet:Object) : Boolean
      {
         if(packet == null || packet.type != INPUTS)
         {
            return false;
         }
         if(handedBackAt >= 0)
         {
            return true;
         }
         try
         {
            var n:uint = packet.readUint();
            for(var i:uint = 0; i < n; i++)
            {
               var ent:uint = packet.method_8473(4);
               var t:uint = packet.readUint();
               var bits:uint = packet.method_8473(14);
               pending.push([t,ent,bits]);
            }
            batches++;
            rows += n;
         }
         catch(e:Error)
         {
            PrivateServer.log("rejoin: could not read 11083 (" + e.message + ")");
         }
         return true;
      }

      public static function frame(core:Object, start:Number) : uint
      {
         var late:uint = uint.MAX_VALUE;
         var now:int = getTimer();
         if(pending.length > 0)
         {
            var states:Object = {};
            for each(var p:Object in core.var_7050)
            {
               if(p.var_10012 != null)
               {
                  states[uint(p.var_11355)] = p.var_10012;
               }
            }
            var simulated:uint = uint(core.var_13849);
            for each(var row:Array in pending)
            {
               var state:Object = states[uint(row[1])];
               if(state == null)
               {
                  if(unknown[row[1]] == null)
                  {
                     unknown[row[1]] = true;
                     PrivateServer.log("rejoin: stream rows for entity " + row[1] + ", which this match doesn't have");
                  }
                  continue;
               }
               var at:uint = uint(Number(row[0]) + start - 16);
               RemoteInput.feed(state,at,uint(row[2]));
               if(at <= simulated && at < late)
               {
                  late = at;
               }
               through = Math.max(through,Number(row[0]) - 16);
            }
            pending = [];
         }
         if(through < 0)
         {
            return late;
         }
         var goal:Number = start + through;
         var time:Number = Number(uint(core.var_12659));
         if(time + 16 < goal)
         {
            var to:Number = Math.min(goal,time + JUMP);
            core.var_12659 = uint(to);
            jumps++;
            jumpedMs += to - time;
            Smoothing.jumped();
         }
         if(caughtUpAt < 0)
         {
            var gap:Number = goal - Number(uint(core.var_13849));
            if(jumps > 0 && lastFrameAt > 0)
            {
               slowest = Math.max(slowest,now - lastFrameAt);
            }
            if(gap <= GAP)
            {
               if(nearSince < 0)
               {
                  nearSince = now;
               }
               else if(now - nearSince >= HOLD)
               {
                  caughtUpAt = Number(uint(core.var_13849)) - start;
                  PrivateServer.log("rejoin: rebuilt match caught up at " + uint(caughtUpAt) + " ms (stream " + uint(through) +
                     " ms), " + ((now - startedAt) / 1000).toFixed(1) + " s after the start; " + jumps + " catch-up frames, " +
                     "slowest " + slowest + " ms");
               }
            }
            else
            {
               nearSince = -1;
               if(now - lastLog >= 1000)
               {
                  lastLog = now;
                  PrivateServer.log("rejoin: simulated " + uint(Number(uint(core.var_13849)) - start) + " ms, stream " +
                     uint(through) + " ms, gap " + int(gap) + " ms");
               }
            }
         }
         lastFrameAt = now;
         return late;
      }

      private static var lastFrameAt:int = 0;
   }
}
