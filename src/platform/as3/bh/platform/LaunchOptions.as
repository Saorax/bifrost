package bh.platform
{
   import flash.Lib;
   import flash.display.StageDisplayState;

   public final class LaunchOptions
   {
      public static const ALL:Array = [
         ["-noskulls","No skulls","Art without skulls: the maps' skull-free versions and decorations (HasSkulls, am_NoSkulls) and the bouncy bomb's safe look.","toggle",null,"Maps from the next match; the bouncy bomb from the next start."],
         ["-broadcaster","Broadcaster mode","The game's broadcaster mode (for casting matches).","toggle",null,"Applies now (some screens from the next time they open)."],
         ["-spectatedelay","Spectate delay","Delay when spectating, in milliseconds (Off: the game's own setting).","number",[0,500,1000,2000,3000,5000,10000,30000,60000],"Applies from the next spectated match."],
         ["-showversion","Show version","Shows the game's version at the bottom left of the menus.","toggle",null,"Applies now."],
         ["-steamdeck","Steam Deck mode","The Steam Deck layout and settings.","toggle",null,"Applies from the next start."]];

      private static const DROPPED:Array = ["-controllertest","-nonetworknext","-fodabot","-forceoffline","-diagnosticlog",
         "-multikeyboard","-nvidiareflex","-writestats","-tinywindow"];

      public function LaunchOptions()
      {
      }

      public static function init() : void
      {
         var all:Object = saved();
         var delay:* = all["-spectatedelay"];
         if(delay is Number && delay > 0 && delay <= 120)
         {
            all["-spectatedelay"] = int(delay) * 1000;
            ModSettings.setValue("launchOptions",all);
         }
         if(ModSettings.value("showVersionDefaulted") !== true)
         {
            all["-showversion"] = true;
            ModSettings.setValue("launchOptions",all);
            ModSettings.setValue("showVersionDefaulted",true);
         }
         Hooks.launchArgs.add(addSaved);
      }

      public static function saved() : Object
      {
         var v:* = ModSettings.value("launchOptions");
         return v != null && typeof v == "object" ? v : {};
      }

      public static function set(flag:String, value:*) : void
      {
         var all:Object = saved();
         if(value == null || value === false || value === 0)
         {
            delete all[flag];
         }
         else
         {
            all[flag] = value;
         }
         ModSettings.setValue("launchOptions",all);
         apply(flag,value);
      }

      public static function option(flag:String) : Array
      {
         for each(var opt:Array in ALL)
         {
            if(opt[0] == flag)
            {
               return opt;
            }
         }
         return null;
      }

      public static function apply(flag:String, value:*) : void
      {
         var on:Boolean = value != null && value !== false && value !== 0;
         try
         {
            switch(flag)
            {
               case "-noskulls":
                  GameApp.var_2797 = on;
                  break;
               case "-broadcaster":
                  GameApp.var_5356 = on;
                  break;
               case "-writestats":
                  GameApp.var_7504 = on;
                  break;
               case "-showversion":
                  GameApp.var_12250 = on;
                  break;
               case "-nvidiareflex":
                  Main.var_12796 = on;
                  var core:GameCore = ScreenManager.owner;
                  if(!on && core != null && core.var_9592 != null)
                  {
                     core.var_9592.isActive = false;
                  }
                  break;
               case "-spectatedelay":
                  if(on)
                  {
                     class_51.var_14536 = true;
                     class_540.var_11626 = 2;
                     class_51.var_6543 = class_51.var_4540 = int(value);
                     class_51.var_10215 = class_51.var_36 = int(value);
                  }
                  else
                  {
                     class_51.var_14536 = false;
                     class_51.var_36 = GameApp.var_7605 ? 3000 : 1000;
                     class_51.var_4540 = GameApp.var_7605 ? 3000 : 1000;
                     class_540.var_11626 = GameApp.var_7605 ? 0 : 1;
                  }
                  break;
               case "-tinywindow":
                  if(on && Lib.current.stage.displayState == StageDisplayState.NORMAL)
                  {
                     GameApp.method_2919(960,540);
                  }
                  break;
            }
         }
         catch(e:Error)
         {
            Platform.log("launch option " + flag + " not applied now: " + e.message);
         }
      }

      public static function frameRate() : int
      {
         var all:Object = saved();
         return all["-unlockfps"] ? -1 : int(all["-setfps"] || 0);
      }

      public static function setFrameRate(fps:int) : void
      {
         var all:Object = saved();
         delete all["-unlockfps"];
         delete all["-setfps"];
         if(fps < 0)
         {
            all["-unlockfps"] = true;
         }
         else if(fps > 0)
         {
            all["-setfps"] = fps;
         }
         ModSettings.setValue("launchOptions",all);
      }

      private static function addSaved(args:*) : Array
      {
         var list:Array = args is Array ? (args as Array).concat() : [];
         var all:Object = saved();
         var added:Array = [];
         for(var flag:String in all)
         {
            var value:* = all[flag];
            if(DROPPED.indexOf(flag) >= 0)
            {
               continue;
            }
            if(list.indexOf(flag) >= 0 || value == null || value === false)
            {
               continue;
            }
            list.push(flag);
            if(!(value is Boolean))
            {
               list.push(String(value));
            }
            added.push(flag + (value is Boolean ? "" : " " + value));
         }
         if(added.length > 0)
         {
            Platform.log("launch options from the Options window: " + added.join(" "));
         }
         return list;
      }
   }
}
