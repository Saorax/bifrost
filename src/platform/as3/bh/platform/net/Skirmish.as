package bh.platform.net
{
   import bh.platform.Hooks;

   public final class Skirmish
   {
      private static var registered:Boolean = false;

      public function Skirmish()
      {
      }

      public static function register() : void
      {
         if(registered)
         {
            return;
         }
         registered = true;
         Hooks.skirmishFactionRewards.add(function(panel:Object, gold:uint):void
         {
            try
            {
               var rows:Object = panel.var_11375;
               var shift:int = gold == 0 ? 1 : 0;
               for(var i:int = 0; rows != null && i < int(rows.length); i++)
               {
                  var clip:Object = rows[i].var_5063;
                  if(i < shift)
                  {
                     clip.visible = false;
                     continue;
                  }
                  clip.x = (i - shift) * -8.35;
                  clip.y = (i - shift) * 70;
               }
            }
            catch(e:Error)
            {
               PrivateServer.log("skirmish: reward rows not moved (" + e.message + ")");
            }
         });
      }
   }
}
