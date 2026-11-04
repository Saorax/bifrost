package bh.mods.matchload
{
   import bh.platform.Hooks;
   import bh.platform.ModSettings;
   import bh.platform.Platform;
   import bh.platform.net.P2PSession;
   import flash.filesystem.FileMode;
   import flash.filesystem.FileStream;
   import flash.system.System;
   import flash.utils.getTimer;

   public final class MatchLoadMod
   {
      public static const LOG:String = "bh-matchload.txt";
      public static const DEFERRED:Object = {"DeferredGFX":true,"Deferred":true};
      public static const MAX_HOLD:int = 15000;

      private static var deferredCount:int = 0;
      private static var inMatch:Boolean = false;
      private static var holding:Boolean = false;
      private static var holdFrom:int = -1;
      private static var matchAt:int = 0;
      private static var used:Object = {};
      private static var usedCount:int = 0;
      private static var introLoads:int = 0;
      private static var playLoads:Array = [];
      private static var late:Object = {};
      private static var lines:Array = [];
      private static var playResolves:int = 0;
      private static var playBySymbol:Object = {};
      private static var loadingNow:int = 0;
      private static var frames:int = 0;

      public function MatchLoadMod()
      {
      }

      public static function register() : void
      {
         Hooks.fileDeferring.add(function(load:String):Boolean
         {
            if(load != null && DEFERRED[load])
            {
               deferredCount++;
               return true;
            }
            return false;
         });
         Hooks.mainMenuButtonsBuilt.add(function(menu:Object):void
         {
            if(deferredCount > 0)
            {
               write("startup: " + deferredCount + " deferred files left out; main menu after " + (getTimer() / 1000).toFixed(1) +
                  " s, memory " + mb(System.totalMemoryNumber) + " MB");
               deferredCount = 0;
               flush();
            }
         });
         Hooks.matchStarted.add(onMatchStarted);
         Hooks.matchEnded.add(function(to:uint):void
         {
            if(!inMatch)
            {
               return;
            }
            inMatch = false;
            stopRecording();
            var lateText:Array = [];
            for(var lf:String in late)
            {
               lateText.push(lf + " (" + late[lf] + ")");
            }
            write("match ended: " + playLoads.length + " deferred file(s) loaded during play" +
               (playLoads.length ? " (" + playLoads.slice(0,12).join(", ") + (playLoads.length > 12 ? ", ..." : "") + ")" : "") +
               "; needed during play before loaded: " + (lateText.length ? lateText.join(", ") : "none") +
               ", memory " + mb(System.totalMemoryNumber) + " MB");
            var top:Array = [];
            for(var s:String in playBySymbol)
            {
               top.push({"s":s,"n":int(playBySymbol[s])});
            }
            top.sortOn("n",Array.NUMERIC | Array.DESCENDING);
            write("  sprite lookups during play: " + playResolves + "; most: " +
               top.slice(0,10).map(function(o:Object, i:int, a:Array):String { return o.s + " " + o.n; }).join(", "));
            flush();
         });
         Hooks.fileLoaded.add(function(f:Object):void
         {
            if(!inMatch || !isDeferred(String(f.fileName)))
            {
               return;
            }
            if(holding || holdFrom < 0)
            {
               introLoads++;
            }
            else
            {
               playLoads.push(String(f.fileName) + " at " + ((getTimer() - matchAt) / 1000).toFixed(1) + " s");
            }
         });
         Hooks.simulationFrame.add(onSimulation);
         Hooks.artPendingChecking.add(function():Boolean
         {
            return inMatch && !holding && loadingNow == 0;
         });
      }

      private static function onMatchStarted() : void
      {
         inMatch = true;
         matchAt = getTimer();
         holding = true;
         holdFrom = -1;
         used = {};
         usedCount = 0;
         introLoads = 0;
         playLoads = [];
         late = {};
         playResolves = 0;
         playBySymbol = {};
         Hooks.gfxResolving.add(onResolving);
      }

      private static function onResolving(symbol:String, defaultFile:String) : void
      {
         var file:String = null;
         try
         {
            file = class_170.var_5202 != null ? String(Object(class_170.var_5202).h[symbol] || "") : "";
         }
         catch(e:Error)
         {
         }
         if(!file)
         {
            file = defaultFile;
         }
         if(!file)
         {
            return;
         }
         if(holding || holdFrom < 0)
         {
            if(!used[file])
            {
               used[file] = true;
               usedCount++;
            }
         }
         else
         {
            playResolves++;
            var key:String = symbol + " @" + file + ":" + Object(ArchiveLoader.var_13644).h[file] +
               (ArchiveLoader.method_5947(file) != null ? "+" : "");
            playBySymbol[key] = int(playBySymbol[key]) + 1;
         }
         if(!(holding || holdFrom < 0) && late[file] === undefined)
         {
            var state:* = Object(ArchiveLoader.var_13644).h[file];
            if(state !== undefined && int(state) != 3)
            {
               late[file] = symbol;
            }
         }
      }

      private static function stopRecording() : void
      {
         Hooks.gfxResolving.remove(onResolving);
      }

      private static function onSimulation(core:Object) : void
      {
         if(!holding)
         {
            if(inMatch && ++frames % 15 == 0)
            {
               loadingNow = queuedCount();
            }
            return;
         }
         var now:int = getTimer();
         if(holdFrom < 0)
         {
            holdFrom = now;
         }
         var queued:int = queuedCount();
         var precacheDone:Boolean = uint(class_266.var_2356) == 3;
         if((queued == 0 && precacheDone) || now - holdFrom > MAX_HOLD)
         {
            release(core,now,queued);
            return;
         }
         if(P2PSession.active)
         {
            return;
         }
         var target:uint = uint(core.var_11938);
         var from:uint = uint(core.var_1171);
         if(target > from)
         {
            core.var_11938 = from;
            core.var_171 = uint(core.var_171) + (target - from);
         }
      }

      private static function release(core:Object, now:int, queued:int) : void
      {
         holding = false;
         loadingNow = queued;
         if(!ModSettings.flag("matchloadTrackPlay",false))
         {
            stopRecording();
         }
         var unloaded:int = 0;
         var states:Object = Object(ArchiveLoader.var_13644).h;
         var unload:Boolean = ModSettings.flag("matchloadUnload",true);
         for(var name:String in states)
         {
            if(unload && int(states[name]) == 3 && !used[name])
            {
               try
               {
                  ArchiveLoader.method_3649(name);
                  delete Object(ArchiveLoader.var_5266).h[name];
                  states[name] = 1;
                  unloaded++;
               }
               catch(e:Error)
               {
               }
            }
         }
         write("match " + ((holdFrom - matchAt) / 1000).toFixed(1) + " s: held " + (now - holdFrom) + " ms" +
            (queued > 0 ? " (gave up with " + queued + " still loading)" : "") + (P2PSession.active ? " (P2P: not held)" : "") +
            "; " + usedCount + " files used, " + introLoads + " deferred loaded in the intro, " + unloaded +
            " unused deferred unloaded" + (unload ? "" : " (matchloadUnload off)") + "; memory " + mb(System.totalMemoryNumber) + " MB");
      }

      private static function queuedCount() : int
      {
         var n:int = 0;
         try
         {
            var states:Object = Object(ArchiveLoader.var_13644).h;
            for(var name:String in states)
            {
               if(int(states[name]) == 2)
               {
                  n++;
               }
            }
         }
         catch(e:Error)
         {
         }
         return n;
      }

      private static function isDeferred(name:String) : Boolean
      {
         try
         {
            return Object(ArchiveLoader.var_13644).h[name] !== undefined;
         }
         catch(e:Error)
         {
         }
         return false;
      }

      private static function mb(bytes:Number) : int
      {
         return int(bytes / 1048576);
      }

      private static function write(line:String) : void
      {
         lines.push(new Date().toLocaleTimeString() + " " + line);
      }

      private static function flush() : void
      {
         if(lines.length == 0)
         {
            return;
         }
         try
         {
            var stream:FileStream = new FileStream();
            stream.open(Platform.dataFile(LOG),FileMode.APPEND);
            stream.writeUTFBytes(lines.join("\r\n") + "\r\n");
            stream.close();
         }
         catch(e:Error)
         {
         }
         lines.length = 0;
      }
   }
}
