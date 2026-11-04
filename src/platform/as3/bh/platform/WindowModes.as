package bh.platform
{
   public final class WindowModes
   {
      public static const EXCLUSIVE_KEY:String = "UI_WINDOWMODE_EXCLUSIVE";

      private static const STEPS:Array = [[0,"game"],[0,"fullscreen"],[1,"game"],[2,"game"]];

      private static var pending:String = null;

      public function WindowModes()
      {
      }

      public static function init() : void
      {
         if(!EngineDisplay.available)
         {
            return;
         }
         Hooks.stringsLoaded.add(function(language:Object):void
         {
            language.var_15061.method_65(EXCLUSIVE_KEY,"Exclusive Fullscreen");
         });
         Hooks.windowModeStepping.add(function(forward:Boolean):Boolean
         {
            var at:int = index();
            var next:Array = STEPS[(at + (forward ? 1 : -1) + STEPS.length) % STEPS.length];
            GameApp.var_14131 = uint(next[0]);
            pending = String(next[1]);
            return true;
         });
         Hooks.windowModeApplying.add(function(stage:Object):Boolean
         {
            if(pending == null)
            {
               return false;
            }
            var mode:String = pending;
            pending = null;
            if(mode == "fullscreen")
            {
               EngineDisplay.setMode("fullscreen");
               return true;
            }
            if(EngineDisplay.mode != "game")
            {
               EngineDisplay.setMode("game");
            }
            return false;
         });
      }

      private static function index() : int
      {
         var value:uint = GameApp.var_14131;
         var mode:String = pending != null ? pending : EngineDisplay.mode;
         if(value == 0)
         {
            return mode == "fullscreen" ? 1 : 0;
         }
         return value == 1 ? 2 : 3;
      }

      public static function label() : String
      {
         if(!EngineDisplay.available)
         {
            return null;
         }
         return index() == 1 ? EXCLUSIVE_KEY : null;
      }
   }
}
