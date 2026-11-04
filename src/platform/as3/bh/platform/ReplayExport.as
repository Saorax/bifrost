package bh.platform
{
   import flash.display.BitmapData;
   import flash.display.JPEGEncoderOptions;
   import flash.display3D.Context3D;
   import flash.filesystem.File;
   import flash.utils.ByteArray;
   import flash.utils.getTimer;

   public final class ReplayExport
   {
      public static const KEY:uint = 120;
      public static const FOLDER:String = "Videos";
      public static const TAIL_MS:uint = 1500;

      private static var pending:Boolean = false;
      private static var stopping:Boolean = false;
      private static var running:Boolean = false;
      private static var base:uint = 0;
      private static var virtualNow:uint = 0;
      private static var drawn:uint = 0;
      private static var writer:AviWriter;
      private static var part:int = 1;
      private static var stem:String;
      private static var startedMs:int = 0;
      private static var encodeMs:Number = 0;
      private static var startReplayMs:uint = 0;
      private static var musicMuted:Boolean = false;
      private static var skipped:int = 0;
      private static var seenReplayMs:uint = 0;
      private static var nextStem:String = null;

      public static var fps:int = 60;
      public static var quality:int = 90;
      public static var last:String = "";
      public static var lastFiles:Array = [];

      public function ReplayExport()
      {
      }

      public static function init() : void
      {
         var f:* = ModSettings.value("replayExportFps");
         if(f === 30 || f === 50 || f === 60)
         {
            fps = int(f);
         }
         var q:* = ModSettings.value("replayExportQuality");
         if(q is Number && q >= 50 && q <= 100)
         {
            quality = int(q);
         }
         Hooks.keyDown.add(onKey);
         Hooks.matchEnded.add(function(... rest):void
         {
            if(running)
            {
               stop("the replay ended");
            }
            pending = false;
         });
      }

      public static function get active() : Boolean
      {
         return running;
      }

      public static function get time() : uint
      {
         return virtualNow;
      }

      private static function onKey(event:Object) : Boolean
      {
         if(event == null || uint(event.keyCode) != KEY || !event.ctrlKey || event.shiftKey || event.altKey)
         {
            return false;
         }
         if(running || pending)
         {
            if(pending)
            {
               pending = false;
            }
            else
            {
               stopping = true;
            }
            return true;
         }
         start();
         return true;
      }

      private static function game() : GameCore
      {
         return GameApp.mainInstance != null ? GameApp.mainInstance.game : null;
      }

      public static function replayPlaying() : Boolean
      {
         var g:GameCore = game();
         return g != null && (g.var_3595 & 1024) != 0 && g.var_5368 != null;
      }

      public static function start() : Boolean
      {
         if(!replayPlaying())
         {
            DummyDrift.show("Replay export: open a replay first (Ctrl+F9 while it plays)",2500);
            return false;
         }
         pending = true;
         seenReplayMs = 0;
         nextStem = null;
         return true;
      }

      public static function startWithNext(replayName:String) : void
      {
         pending = true;
         seenReplayMs = 0;
         nextStem = replayName;
         Platform.log("replay export: armed for " + replayName);
      }

      public static function requestStop() : void
      {
         if(pending)
         {
            pending = false;
         }
         else if(running)
         {
            stopping = true;
         }
      }

      public static function clock(g:GameCore, now:uint) : uint
      {
         if(!running)
         {
            if(!pending)
            {
               return now;
            }
            var t:uint = g != null && (g.var_3595 & 1024) != 0 ? g.var_12659 : 0;
            if(t == 0 || t < seenReplayMs)
            {
               seenReplayMs = t;
            }
            if(t == 0 || t < uint(seenReplayMs + 160))
            {
               return now;
            }
            pending = false;
            if(!begin(g,now))
            {
               return now;
            }
         }
         virtualNow = uint(base + Math.floor(drawn * 1000 / fps));
         g.var_12269 = uint(virtualNow - 16);
         return virtualNow;
      }

      private static function begin(g:GameCore, now:uint) : Boolean
      {
         if(g == null || (g.var_3595 & 1024) == 0)
         {
            return false;
         }
         var d:Date = new Date();
         stem = (nextStem != null ? nextStem : "Replay") + " " + d.fullYear + "-" + two(d.month + 1) + "-" + two(d.date) +
            " " + two(d.hours) + "." + two(d.minutes) + "." + two(d.seconds);
         nextStem = null;
         part = 1;
         lastFiles = [];
         writer = null;
         base = now;
         drawn = 0;
         skipped = 0;
         encodeMs = 0;
         startedMs = getTimer();
         startReplayMs = g.var_12659;
         running = true;
         stopping = false;
         musicMuted = true;
         class_727.method_6088(true);
         Platform.log("replay export: started at replay time " + startReplayMs + " ms, " + fps + " fps");
         DummyDrift.show("Exporting the replay to video... (Ctrl+F9 stops)",2000);
         return true;
      }

      private static function nextFile() : File
      {
         var name:String = stem + (part > 1 ? " (part " + part + ")" : "") + ".avi";
         var file:File = Platform.dataFile(FOLDER + "/" + name);
         file.parent.createDirectory();
         lastFiles.push(file.nativePath);
         return file;
      }

      public static function presenting(context:Context3D) : void
      {
         if(!running)
         {
            return;
         }
         var g:GameCore = game();
         try
         {
            var t:int = getTimer();
            if(writer == null)
            {
               writer = new AviWriter(nextFile(),context.backBufferWidth,context.backBufferHeight,fps);
            }
            var shot:BitmapData = new BitmapData(context.backBufferWidth,context.backBufferHeight,false,0);
            context.drawToBitmapData(shot);
            if(drawn == 0 && skipped < 30 && black(shot))
            {
               skipped++;
               shot.dispose();
               return;
            }
            var jpeg:ByteArray = new ByteArray();
            shot.encode(shot.rect,new JPEGEncoderOptions(quality),jpeg);
            shot.dispose();
            writer.add(jpeg);
            jpeg.clear();
            encodeMs += getTimer() - t;
            drawn++;
            if(writer.full)
            {
               writer.close();
               part++;
               writer = new AviWriter(nextFile(),context.backBufferWidth,context.backBufferHeight,fps);
            }
         }
         catch(e:Error)
         {
            Platform.log("replay export: frame " + drawn + " failed: " + e.message);
            stop("an error: " + e.message);
            return;
         }
         if(drawn % fps == 0)
         {
            DummyDrift.show("Exporting the replay: " + int(drawn / fps) + " s of video (Ctrl+F9 stops)",1500);
         }
         if(stopping)
         {
            stop("stopped (Ctrl+F9)");
         }
         else if(g == null || (g.var_3595 & 1024) == 0)
         {
            stop("the replay ended");
         }
         else if(g.var_5368.var_12978 != 0 && g.var_12659 > uint(g.var_5368.var_12978 + TAIL_MS))
         {
            stop("the replay ended");
         }
      }

      private static function stop(why:String) : void
      {
         if(!running)
         {
            return;
         }
         running = false;
         stopping = false;
         var g:GameCore = game();
         var real:uint = uint(getTimer());
         if(g != null && real > virtualNow)
         {
            g.var_171 = uint(g.var_171 + (real - virtualNow));
            g.var_12269 = uint(real - 16);
         }
         var frames:uint = 0;
         var seconds:Number = 0;
         try
         {
            frames = drawn;
            if(writer != null)
            {
               writer.close();
            }
         }
         catch(e:Error)
         {
            Platform.log("replay export: closing the file failed: " + e.message);
         }
         writer = null;
         if(musicMuted)
         {
            class_727.method_6088(false);
            musicMuted = false;
         }
         seconds = frames / fps;
         var took:Number = (getTimer() - startedMs) / 1000;
         var replayMs:uint = g != null ? uint(g.var_12659 - startReplayMs) : 0;
         last = frames + " frames (" + seconds.toFixed(2) + " s at " + fps + " fps), replay time " + replayMs +
            " ms, " + lastFiles.length + " file(s), took " + took.toFixed(1) + " s, encode " +
            (frames > 0 ? (encodeMs / frames).toFixed(1) : "0") + " ms/frame; " + why;
         Platform.log("replay export: " + last + ": " + lastFiles.join(", "));
         DummyDrift.show("Replay exported: " + seconds.toFixed(1) + " s to Documents\\Bifrost\\" + FOLDER,3500);
      }

      private static function black(b:BitmapData) : Boolean
      {
         for(var y:int = 0; y < 9; y++)
         {
            for(var x:int = 0; x < 16; x++)
            {
               if(b.getPixel(int((x + 0.5) * b.width / 16),int((y + 0.5) * b.height / 9)) != 0)
               {
                  return false;
               }
            }
         }
         return true;
      }

      private static function two(n:int) : String
      {
         return n < 10 ? "0" + n : String(n);
      }
   }
}
