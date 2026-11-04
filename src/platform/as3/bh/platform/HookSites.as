package bh.platform
{
   import flash.events.KeyboardEvent;

   public class HookSites
   {
      public function HookSites()
      {
         super();
      }

      public static function keyDown(e:KeyboardEvent) : Boolean
      {
         if(e.keyCode == 27)
         {
            e.preventDefault();
         }
         return Hooks.keyDown.fireUntilHandled1(e);
      }

      public static function precacheCollecting(param1:Boolean, param2:GameCore) : Boolean
      {
         if(!param1 && class_266.var_2356 == 1 && Hooks.precacheCollecting.fireUntilHandled1(param2))
         {
            class_266.var_2356 = 2;
            return true;
         }
         return false;
      }
   }
}
