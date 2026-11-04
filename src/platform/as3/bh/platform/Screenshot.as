package bh.platform
{
   import flash.display.BitmapData;
   import flash.display.PNGEncoderOptions;
   import flash.display3D.Context3D;
   import flash.filesystem.File;
   import flash.filesystem.FileMode;
   import flash.filesystem.FileStream;
   import flash.utils.ByteArray;
   import flash.utils.getTimer;

   public final class Screenshot
   {
      public static const KEY:uint = 123;
      public static const FOLDER:String = "Screenshots";

      private static var wanted:Boolean = false;
      private static var hudShown:Boolean = true;

      public static var last:File;
      public static var lastMs:int;

      public function Screenshot()
      {
      }

      public static function init() : void
      {
         Hooks.keyDown.add(onKey);
         Hooks.matchEnded.add(function(... rest):void
         {
            hudShown = true;
         });
      }

      private static function onKey(event:Object) : Boolean
      {
         if(event == null || uint(event.keyCode) != KEY || event.altKey || event.ctrlKey == event.shiftKey)
         {
            return false;
         }
         if(event.shiftKey)
         {
            hud = !hud;
            DummyDrift.show(hud ? "HUD shown" : "HUD hidden (Shift+F12 shows it)",1500);
         }
         else
         {
            take();
         }
         return true;
      }

      public static function get hud() : Boolean
      {
         return hudShown;
      }

      public static function set hud(on:Boolean) : void
      {
         hudShown = on;
         showHud(on);
      }

      private static function showHud(on:Boolean) : void
      {
         var game:GameCore = GameApp.mainInstance != null ? GameApp.mainInstance.game : null;
         if(game == null)
         {
            return;
         }
         if(game.worldUILayer3D != null)
         {
            game.worldUILayer3D.isActive = on;
         }
         if(game.var_14987 != null)
         {
            game.var_14987.isActive = on;
         }
         if(game.var_8248 != null)
         {
            game.var_8248.isActive = on;
         }
      }

      public static function take() : void
      {
         wanted = true;
      }

      public static function presenting(context:Context3D) : void
      {
         if(ReplayExport.active)
         {
            ReplayExport.presenting(context);
         }
         if(!wanted)
         {
            return;
         }
         wanted = false;
         var started:int = getTimer();
         try
         {
            var shot:BitmapData = new BitmapData(context.backBufferWidth,context.backBufferHeight,false,0);
            context.drawToBitmapData(shot);
            var png:ByteArray = shot.encode(shot.rect,new PNGEncoderOptions(true));
            var size:String = shot.width + "x" + shot.height;
            shot.dispose();
            var file:File = Platform.dataFile(FOLDER + "/" + name());
            var out:FileStream = new FileStream();
            out.open(file,FileMode.WRITE);
            out.writeBytes(png);
            out.close();
            last = file;
            lastMs = getTimer() - started;
            Platform.log("screenshot: " + file.nativePath + " (" + size + ", " + png.length +
               " bytes, " + lastMs + " ms)");
            DummyDrift.show("Screenshot saved: Documents\\Bifrost\\" + FOLDER + "\\" + file.name,2500);
         }
         catch(e:Error)
         {
            Platform.log("screenshot failed: " + e.message);
            DummyDrift.show("Screenshot failed: " + e.message,2500);
         }
      }

      private static function name() : String
      {
         var d:Date = new Date();
         return "Brawlhalla " + d.fullYear + "-" + two(d.month + 1) + "-" + two(d.date) + " " + two(d.hours) + "." +
            two(d.minutes) + "." + two(d.seconds) + "." + ("00" + d.milliseconds).substr(-3) + ".png";
      }

      private static function two(n:int) : String
      {
         return n < 10 ? "0" + n : String(n);
      }
   }
}
