package bh.platform
{
   import flash.utils.getTimer;

   public final class BackTrail
   {
      private static const WAIT_MS:int = 30000;
      private static const SETTLE_MS:int = 400;

      private static var registered:Boolean = false;
      private static var trail:Array = null;
      private static var why:String = "";
      private static var since:int = 0;
      private static var started:Boolean = false;
      private static var ended:Boolean = false;
      private static var menuSince:int = -1;
      private static var queue:Array = [];
      private static var queueAt:int = 0;
      private static const STEP_MS:int = 150;

      public static var last:String = "";

      public static function init() : void
      {
         if(registered)
         {
            return;
         }
         registered = true;
         Hooks.gameStateChanging.add(function(from:uint, to:uint):void
         {
            if(trail == null || playing(from) == playing(to))
            {
               return;
            }
            if(playing(to) && ended)
            {
               last = "dropped " + names(trail) + ": another match started before the menus came back";
               Platform.log("back trail: " + last);
               trail = null;
            }
            else if(playing(to))
            {
               started = true;
            }
            else if(started)
            {
               ended = true;
               since = getTimer();
               menuSince = -1;
            }
         });
         Hooks.frameStarting.add(onFrame);
      }

      public static function leaving(reason:String) : void
      {
         var open:Array = BigWindow.openWindows();
         if(open.length == 0)
         {
            return;
         }
         trail = open;
         for each(var w:BigWindow in open)
         {
            try
            {
               w.Hide();
            }
            catch(e:Error)
            {
               ErrorLog.write("back trail: " + w + " not hidden: " + e);
            }
         }
         why = reason;
         since = getTimer();
         started = false;
         ended = false;
         menuSince = -1;
         last = "kept " + names(open) + " for " + reason;
         Platform.log("back trail: " + last);
      }

      public static function stayed(reason:String) : void
      {
         if(trail != null && !started)
         {
            restore(reason);
         }
      }

      private static function onFrame() : void
      {
         var now:int = getTimer();
         if(queue.length > 0 && now >= queueAt)
         {
            var w:BigWindow = queue.shift();
            try
            {
               w.returnTo();
            }
            catch(e:Error)
            {
               ErrorLog.write("back trail: " + w + " not shown again: " + e);
            }
            queueAt = now + STEP_MS;
         }
         if(trail == null)
         {
            return;
         }
         if(!started)
         {
            if(now - since > WAIT_MS && menusBack())
            {
               restore("no match followed the " + why);
            }
            return;
         }
         if(!ended)
         {
            return;
         }
         if(menusBack())
         {
            if(menuSince < 0)
            {
               menuSince = now;
            }
            else if(now - menuSince >= SETTLE_MS)
            {
               restore("the " + why + " ended");
            }
         }
         else
         {
            menuSince = -1;
         }
      }

      private static const REPLAY_PLAYING:uint = 5;

      private static function playing(state:uint) : Boolean
      {
         return state == REPLAY_PLAYING || state == Platform.MATCH_RUNNING;
      }

      private static function menusBack() : Boolean
      {
         try
         {
            return !Platform.matchRunning && ScreenManager.var_10617 != null && ScreenManager.var_10617.isActive;
         }
         catch(e:Error)
         {
         }
         return false;
      }

      private static function restore(reason:String) : void
      {
         var shown:Array = trail;
         trail = null;
         queue = shown.concat();
         queueAt = 0;
         last = "showed " + names(shown) + " again (" + reason + ")";
         Platform.log("back trail: " + last);
      }

      public static function order() : String
      {
         var out:Array = [];
         for each(var w:BigWindow in BigWindow.openWindows())
         {
            out.push(w.trailName + "@" + ScreenManager.activeScreens.indexOf(w));
         }
         return out.join(", ");
      }

      private static function names(windows:Array) : String
      {
         var out:Array = [];
         for each(var w:BigWindow in windows)
         {
            out.push(w.trailName);
         }
         return out.join(" > ");
      }
   }
}
