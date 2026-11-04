package bh.platform
{
   import flash.display.Screen;
   import flash.display.Stage;
   import flash.events.ThrottleEvent;
   import flash.utils.getTimer;

   public final class FrameRateWatch
   {
      private static const WINDOW_MS:int = 2000;
      private static const LOW:Number = 0.8;
      private static const WINDOWS_LOW:int = 3;

      private static var stage:Stage;
      private static var start:int = 0;
      private static var last:int = 0;
      private static var frames:int = 0;
      private static var longest:int = 0;
      private static var lowWindows:int = 0;
      private static var refresh:Number = 0;
      private static var throttle:String = "none";
      private static var kicked:int = 0;
      private static var kicks:int = 0;
      private static var menuReached:Boolean = false;

      public static var testTarget:Number = 0;
      public static var lastFps:Number = 0;
      public static var lastTarget:Number = 0;
      public static var reports:int = 0;
      public static var lastLongest:int = 0;
      public static var lastInFront:Boolean = false;

      public function FrameRateWatch()
      {
      }

      public static function init() : void
      {
         Hooks.gameCreated.add(function(main:Object):void
         {
            stage = main.stage;
            try
            {
               stage.addEventListener(ThrottleEvent.THROTTLE,function(e:ThrottleEvent):void
               {
                  throttle = e.state + " " + e.targetFrameRate;
                  ErrorLog.write("frame rate: runtime throttle " + throttle);
               });
            }
            catch(e:Error)
            {
            }
         });
         Hooks.mainMenuButtonsBuilt.add(function(menu:Object):void
         {
            menuReached = true;
         });
         Hooks.frameStarting.add(onFrame);
      }

      private static function onFrame() : void
      {
         var now:int = getTimer();
         if(stage == null)
         {
            return;
         }
         if(start == 0)
         {
            start = last = now;
            return;
         }
         frames++;
         if(now - last > longest)
         {
            longest = now - last;
         }
         last = now;
         if(now - start < WINDOW_MS)
         {
            return;
         }
         var fps:Number = frames * 1000 / (now - start);
         var target:Number = stage.frameRate;
         if(refresh <= 0)
         {
            refresh = readRefresh();
         }
         if(refresh > 0 && refresh < target)
         {
            target = refresh;
         }
         var realTarget:Number = target;
         if(testTarget > 0)
         {
            target = testTarget;
         }
         lastFps = fps;
         lastTarget = target;
         var inFront:Boolean = false;
         try
         {
            inFront = stage.nativeWindow.active && !stage.nativeWindow.closed;
         }
         catch(e:Error)
         {
         }
         var shortFrames:Boolean = longest < 3 * 1000 / Math.max(25,realTarget);
         lastLongest = longest;
         lastInFront = inFront;
         if(kicked > 0)
         {
            ErrorLog.write("frame rate: " + fps.toFixed(1) + " fps " + (kicked * 2) + " s after re-applying " + stage.frameRate +
               (fps >= LOW * target ? " (back)" : " (still low)"));
            kicked = fps >= LOW * target || kicked >= 2 ? 0 : kicked + 1;
         }
         else if(inFront && shortFrames && fps < LOW * target && !loading() && kicks < 5)
         {
            if(++lowWindows == WINDOWS_LOW)
            {
               refresh = readRefresh();
               ErrorLog.write("frame rate: stuck low, " + fps.toFixed(1) + " fps for " + (WINDOWS_LOW * 2) + " s against " +
                  stage.frameRate + " set" + (testTarget > 0 ? " (test target " + testTarget + ")" : "") + ", display " + refresh + " Hz; longest frame " + longest + " ms; " + context());
               kicks++;
               reports++;
               var rate:Number = stage.frameRate;
               stage.frameRate = rate == 1000 ? 999 : rate + 1;
               stage.frameRate = rate;
               kicked = 1;
               lowWindows = 0;
            }
         }
         else
         {
            lowWindows = 0;
         }
         start = now;
         frames = 0;
         longest = 0;
      }

      private static function loading() : Boolean
      {
         return !menuReached;
      }

      private static function readRefresh() : Number
      {
         try
         {
            return Number(GameApp.windowsExtension.ASGetRefreshRate());
         }
         catch(e:Error)
         {
         }
         return 0;
      }

      private static function context() : String
      {
         var s:String = "";
         try
         {
            s += "display state " + stage.displayState + ", window " + stage.nativeWindow.bounds + ", stage " +
               stage.stageWidth + "x" + stage.stageHeight + ", throttle " + throttle + ", match " + Platform.matchRunning +
               ", frame pacing " + FramePacing.on + ", screens:";
            for each(var sc:Screen in Screen.screens)
            {
               s += " " + sc.bounds + (sc == Screen.mainScreen ? " (main)" : "");
            }
         }
         catch(e:Error)
         {
            s += " (" + e.message + ")";
         }
         return s;
      }
   }
}
