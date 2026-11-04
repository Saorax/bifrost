package bh.platform
{
   public final class NoStore
   {
      private static var watching:Boolean = false;

      public static function init() : void
      {
         if(watching)
         {
            return;
         }
         watching = true;
         Hooks.frameRendering.add(function():void
         {
            try
            {
               var page:Object = ScreenManager.var_4066;
               if(page == null || !page.isActive)
               {
                  return;
               }
               if(page.var_9234 != null && page.var_9234.clip.visible)
               {
                  page.var_9234.clip.visible = false;
               }
               if(page.var_7277 != null && page.var_7277.clip.visible)
               {
                  page.var_7277.clip.visible = false;
               }
            }
            catch(e:Error)
            {
            }
         });
      }

      public static function storeCreated(screen:Object) : void
      {
         try
         {
            if(screen.var_4260 != null)
            {
               screen.var_4260.clip.visible = false;
            }
         }
         catch(e:Error)
         {
            Platform.log("nostore: " + e.message);
         }
      }

      public static function storeHighlight(screen:Object, target:Object) : Boolean
      {
         return target == class_478.BUY_BUTTON;
      }

      public static function buyCoins(game:Object) : Boolean
      {
         Platform.log("nostore: the buy-coins popup is not opened (no store)");
         return true;
      }
   }
}
