package bh.mods.lazygfx
{
   import bh.platform.Platform;
   import bh.platform.Hooks;
   import flash.filesystem.File;
   import flash.filesystem.FileMode;
   import flash.filesystem.FileStream;
   import flash.events.TimerEvent;
   import flash.system.System;
   import flash.utils.Timer;
   import flash.utils.getTimer;

   public final class LazyGfxMod
   {
      public static const LOG:String = "bh-lazygfx.txt";
      public static const DEFERRED:Object = {"DeferredGFX":true,"Deferred":true};

      private static var counts:Object = {};
      private static var started:Boolean = false;
      private static var inMatch:Boolean = false;
      private static var later:int = 0;

      public static const BATCH:int = 8;
      private static var backlog:Array = null;
      private static var waiting:Object = {};
      private static var outstanding:int = 0;
      private static var askedAt:int = 0;
      private static var streamStart:int = 0;
      private static var streamed:int = 0;
      private static var timer:Timer;

      public function LazyGfxMod()
      {
      }

      public static function register() : void
      {
         var file:File = Platform.dataFile(LOG);
         try
         {
            if(file.exists)
            {
               file.deleteFile();
            }
         }
         catch(e:Error)
         {
         }
         Hooks.fileDeferring.add(function(load:String):Boolean
         {
            if(load != null && DEFERRED[load])
            {
               counts[load] = int(counts[load]) + 1;
               return true;
            }
            return false;
         });
         Hooks.mainMenuButtonsBuilt.add(function(menu:Object):void
         {
            if(!started)
            {
               started = true;
               var parts:Array = [];
               for(var k:String in counts)
               {
                  parts.push(counts[k] + " " + k);
               }
               write("deferred at startup: " + (parts.length ? parts.join(", ") : "nothing (the file list had no deferred rows)") +
                  "; main menu after " + (getTimer() / 1000).toFixed(1) + " s, memory " + (System.totalMemoryNumber / 1048576).toFixed(0) +
                  " MB, process " + (System.privateMemory / 1048576).toFixed(0) + " MB");
               startStream();
            }
         });
         Hooks.matchStarted.add(function():void
         {
            inMatch = true;
         });
         Hooks.matchEnded.add(function(to:uint):void
         {
            inMatch = false;
         });
         Hooks.fileLoaded.add(function(f:Object):void
         {
            var name:String = String(f.fileName);
            if(waiting[name])
            {
               delete waiting[name];
               outstanding--;
               streamed++;
               return;
            }
            if(started && (name.indexOf("Gfx_") == 0 || name.indexOf("bones/") == 0))
            {
               later++;
               write("asked for by the game before the stream reached it" + (inMatch ? " (DURING A MATCH)" : "") + ": " + name +
                  " at " + (getTimer() / 1000).toFixed(1) + " s (" + later + " so far)");
            }
         });
      }

      private static function deferredFiles() : Array
      {
         var out:Array = [];
         try
         {
            var states:Object = Object(ArchiveLoader.var_13644).h;
            for(var name:String in states)
            {
               if(int(states[name]) == 1)
               {
                  out.push(name);
               }
            }
         }
         catch(e:Error)
         {
            write("could not list the deferred files: " + e.message);
         }
         return out.sort(function(a:String, b:String):int
         {
            var ka:int = a.indexOf("bones/") == 0 ? 0 : 1;
            var kb:int = b.indexOf("bones/") == 0 ? 0 : 1;
            return ka != kb ? ka - kb : (a < b ? -1 : (a > b ? 1 : 0));
         });
      }

      private static function startStream() : void
      {
         backlog = deferredFiles();
         streamStart = getTimer();
         write("streaming " + backlog.length + " deferred files in the background while in the menus");
         timer = new Timer(200);
         timer.addEventListener(TimerEvent.TIMER,onTick);
         timer.start();
      }

      private static function onTick(e:TimerEvent) : void
      {
         var now:int = getTimer();
         if(outstanding > 0 && now - askedAt < 15000)
         {
            return;
         }
         if(outstanding > 0)
         {
            write("gave up waiting for " + outstanding + " file(s) of a batch; going on");
            waiting = {};
            outstanding = 0;
         }
         if(backlog.length == 0)
         {
            timer.stop();
            write("stream done: " + streamed + " files in " + ((now - streamStart) / 1000).toFixed(1) + " s of menus, memory " +
               (System.totalMemoryNumber / 1048576).toFixed(0) + " MB, process " + (System.privateMemory / 1048576).toFixed(0) + " MB");
            return;
         }
         try
         {
            var core:Object = GameApp.mainInstance != null ? Object(GameApp.mainInstance).var_13259 : null;
            var state:uint = core != null ? uint(core.gameState) : 0;
            if(core == null || inMatch || state == 3 || state == 5 || state == 6)
            {
               return;
            }
            var states:Object = Object(ArchiveLoader.var_13644).h;
            var asked:int = 0;
            while(asked < BATCH && backlog.length > 0)
            {
               var name:String = backlog.shift();
               if(int(states[name]) != 1)
               {
                  continue;
               }
               waiting[name] = true;
               outstanding++;
               asked++;
               ArchiveLoader.method_264(name);
            }
            askedAt = now;
         }
         catch(err:Error)
         {
            write("stream stopped: " + err.message);
            timer.stop();
         }
      }

      private static function write(line:String) : void
      {
         try
         {
            var stream:FileStream = new FileStream();
            stream.open(Platform.dataFile(LOG),FileMode.APPEND);
            stream.writeUTFBytes(line + "\r\n");
            stream.close();
         }
         catch(e:Error)
         {
         }
      }
   }
}
