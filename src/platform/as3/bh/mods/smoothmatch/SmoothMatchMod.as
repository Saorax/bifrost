package bh.mods.smoothmatch
{
   import bh.platform.Platform;
   import bh.platform.Hooks;
   import bh.platform.ModSettings;
   import bh.platform.net.P2PSession;
   import flash.filesystem.FileMode;
   import flash.filesystem.FileStream;
   import flash.system.System;
   import flash.utils.Dictionary;
   import flash.utils.getTimer;

   public final class SmoothMatchMod
   {
      public static const LOG:String = "bh-smooth.txt";
      public static const MAX_GAP:int = 50;
      public static const ONLINE_MODES:uint = 4 | 2 | 4194304 | 1024 | 2048 | 8192 | 262144 | 524288;

      private static var lastFrame:int = 0;
      private static var skipped:int = 0;
      private static var skippedMs:int = 0;

      public static const KO_IMMINENCE:Number = -1;
      private static var states:Dictionary = new Dictionary(true);
      private static var kos:int = 0;
      private static var inMatch:Boolean = false;
      private static var pending:Array = [];
      private static var koCollections:int = 0;

      public function SmoothMatchMod()
      {
      }

      public static function register() : void
      {
         Hooks.matchStarted.add(function():void
         {
            lastFrame = 0;
            skipped = skippedMs = 0;
            states = new Dictionary(true);
            kos = koCollections = 0;
            inMatch = true;
         });
         Hooks.matchEnded.add(function(to:uint):void
         {
            inMatch = false;
            if(skipped > 0 || kos > 0)
            {
               write("match ended: " + skipped + " catch-up jump(s) skipped, " + skippedMs + " ms in all; " + kos + " KOs, " +
                  koCollections + " collection(s) at a KO");
            }
         });
         Hooks.simulationFrame.add(onSimulation);
         Hooks.matchStartCollecting.add(function(core:Object):Boolean
         {
            return !ModSettings.flag("matchStartCollection",false);
         });
         Hooks.precacheCollecting.add(function(core:Object):Boolean
         {
            return ModSettings.flag("skipPrecacheCollection",false);
         });
      }

      private static function onSimulation(core:Object) : void
      {
         collectAtKo(core);
         var now:int = getTimer();
         var local:Boolean = (uint(core.var_3595) & ONLINE_MODES) == 0;
         var first:Boolean = lastFrame == 0 && !P2PSession.active;
         if(local && (first || (lastFrame > 0 && now - lastFrame > MAX_GAP && uint(core.var_5300) != 0)))
         {
            var target:uint = uint(core.var_11938);
            var from:uint = uint(core.var_1171);
            if(target > from + 16)
            {
               var excess:uint = target - (from + 16);
               core.var_11938 = target - excess;
               core.var_171 = uint(core.var_171) + excess;
               skipped++;
               skippedMs += int(excess);
               if(skipped <= 20)
               {
                  write((first ? "the match's first update" : "frame of " + (now - lastFrame) + " ms") + ": skipped a catch-up of " +
                     int(excess / 16) + " steps");
               }
            }
         }
         lastFrame = now;
      }

      private static function collectAtKo(core:Object) : void
      {
         var ko:Boolean = false;
         try
         {
            var players:Object = core.var_7050;
            for(var i:int = 0; players != null && i < int(players.length); i++)
            {
               var player:Object = players[i];
               var state:int = int(player.var_661);
               if(state == 7 && states[player] !== undefined && states[player] != 7)
               {
                  ko = true;
               }
               states[player] = state;
            }
         }
         catch(e:Error)
         {
            return;
         }
         if(!ko)
         {
            return;
         }
         kos++;
         var setting:* = ModSettings.value("koCollection");
         var imminence:Number = setting is Number ? Number(setting) : KO_IMMINENCE;
         if(imminence < 0)
         {
            write("KO (collection at KOs off)");
            return;
         }
         var before:Number = System.totalMemoryNumber;
         var start:int = getTimer();
         System.pauseForGCIfCollectionImminent(imminence);
         var took:int = getTimer() - start;
         var freed:Number = before - System.totalMemoryNumber;
         if(freed > 1048576)
         {
            koCollections++;
         }
         write("KO: pauseForGCIfCollectionImminent(" + imminence + ") took " + took + " ms, freed " +
            (freed / 1048576).toFixed(1) + " MB");
      }

      private static function write(line:String) : void
      {
         pending.push(new Date().toLocaleTimeString() + " " + line);
         if(inMatch)
         {
            return;
         }
         try
         {
            var stream:FileStream = new FileStream();
            stream.open(Platform.dataFile(LOG),FileMode.APPEND);
            stream.writeUTFBytes(pending.join("\r\n") + "\r\n");
            stream.close();
            pending.length = 0;
         }
         catch(e:Error)
         {
         }
      }
   }
}
