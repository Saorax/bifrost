package bh.platform
{
   import flash.filesystem.File;
   import flash.utils.getTimer;

   public final class ReplayPlayer
   {
      private static const WAIT_MS:int = 30000;
      private static const LEAD_MS:Number = 3000;
      private static const MOVING_MS:uint = 160;
      private static const BUSY:String = "replay-stats";

      private static var registered:Boolean = false;
      private static var pending:Object = null;

      public static var last:String = "";

      public function ReplayPlayer()
      {
      }

      public static function watch(f:File, at:Number = -1, analyse:Boolean = false) : Boolean
      {
         if(!registered)
         {
            registered = true;
            Hooks.frameStarting.add(onFrame);
         }
         pending = at >= 0 || analyse ? {"name":f.name,"at":at,"analyse":analyse,"t0":getTimer(),"stage":0} : null;
         PostMatchStats.armNext = analyse;
         BackTrail.leaving(analyse ? "replay stats" : "replay");
         if(ReplayIndex.play(f))
         {
            last = (analyse ? "getting the stats of " : "watching ") + f.name + (at >= 0 ? " from " + Math.round(at) : "");
            return true;
         }
         pending = null;
         PostMatchStats.armNext = false;
         BackTrail.stayed("the replay didn't play");
         last = "could not play " + f.name;
         return false;
      }

      public static function get busy() : Boolean
      {
         return pending != null;
      }

      private static function onFrame() : void
      {
         if(pending == null)
         {
            return;
         }
         if(getTimer() - pending.t0 > WAIT_MS * (pending.analyse ? 10 : 1))
         {
            Busy.done(BUSY);
            last = "gave up on " + pending.name + " at stage " + pending.stage;
            Platform.log("replays: " + last);
            pending = null;
            return;
         }
         if(!PostMatchStats.replaying)
         {
            if(pending.stage == 1)
            {
               Busy.done(BUSY);
               last = "the replay closed while getting its stats";
               Platform.log("replays: " + last);
               pending = null;
            }
            return;
         }
         try
         {
            var game:Object = ScreenManager.owner;
            var hud:Object = ScreenManager.var_945;
            if(game == null || hud == null || hud.var_5368 == null)
            {
               return;
            }
            var now:uint = uint(game.var_13849);
            if(pending.stage == 0)
            {
               if(pending.seen == null || now < uint(pending.seen))
               {
                  pending.seen = now;
                  return;
               }
               if(now < uint(pending.seen) + MOVING_MS)
               {
                  return;
               }
               var end:uint = uint(hud.var_5368.var_12978);
               var start:Number = Number(game.var_5300);
               var to:Number = pending.analyse ? end : Math.max(start,Number(pending.at) - LEAD_MS);
               hud.method_5306(uint(to));
               pending.stage = 1;
               pending.end = end;
               last = (pending.analyse ? "getting stats: seeking to " : "jumped to ") + uint(to) + " in " + pending.name;
               Platform.log("replays: " + last);
               if(!pending.analyse)
               {
                  pending = null;
               }
               else
               {
                  Busy.start(BUSY,"GETTING MATCH STATS",20000);
               }
               return;
            }
            if(now + 50 < uint(pending.end) && (uint(game.var_3595) & 2048) == 0)
            {
               return;
            }
            Busy.done(BUSY);
            var name:String = pending.name;
            pending = null;
            var stats:Object = PostMatchStats.replaySnapshot();
            if(stats == null)
            {
               last = "no stats from " + name;
               Platform.log("replays: " + last);
               DummyDrift.show("This replay gave no match stats.",3000);
               return;
            }
            ReplayStore.saveStats(name,stats,"from the replay");
            last = "stats of " + name + " saved";
            PostMatchStats.openWith(stats);
         }
         catch(e:Error)
         {
            Busy.done(BUSY);
            last = "failed: " + e.message;
            Platform.log("replays: " + last);
            pending = null;
         }
      }
   }
}
