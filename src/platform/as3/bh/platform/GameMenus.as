package bh.platform
{
   import flash.display.MovieClip;
   import flash.display.Shape;
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.geom.Point;

   public final class GameMenus
   {
      public static const LOBBY:String = "lobby";
      public static const TRAINING:String = "training";
      public static const REPLAYS:String = "replays";

      private static const BUTTON:String = "bifrostMenuButton";

      public static var reshow:Function = null;

      public function GameMenus()
      {
      }

      public static function own(page:String) : Boolean
      {
         return ModSettings.flag(key(page),false);
      }

      public static function setOwn(page:String, on:Boolean) : void
      {
         ModSettings.setFlag(key(page),on);
      }

      public static function label(page:String) : String
      {
         return own(page) ? "The game's" : "Bifrost's";
      }

      private static function key(page:String) : String
      {
         return page == TRAINING ? "gameTrainingMenu" : page == REPLAYS ? "gameReplayList" : "gameLobbyMenu";
      }

      private static var ticker:Shape = null;
      private static var waiting:Object = null;
      private static var shownOn:Object = null;
      private static var holder:Sprite = null;
      private static var tries:int = 0;

      public static function offered(screen:Object) : Boolean
      {
         return screen != null && (shownOn === screen || waiting != null && waiting.screen === screen);
      }

      public static function offer(screen:Object, page:String, again:Function = null) : void
      {
         withdraw(screen);
         waiting = {"screen":screen,"page":page,"again":again};
         tries = 0;
         if(ticker == null)
         {
            ticker = new Shape();
            ticker.addEventListener(Event.ENTER_FRAME,onFrame);
         }
      }

      private static function onFrame(e:Event) : void
      {
         if(waiting != null)
         {
            if(place(waiting.screen,waiting.page,waiting.again))
            {
               waiting = null;
            }
            else if(++tries > 120)
            {
               Platform.log("game menus: the game's " + waiting.page + " page never showed; no Bifrost menu button");
               waiting = null;
            }
         }
         if(shownOn != null && (!shownOn.isActive || holder == null || holder.parent == null))
         {
            withdraw(shownOn);
         }
      }

      private static function place(screen:Object, page:String, again:Function) : Boolean
      {
         try
         {
            var clip:MovieClip = screen.panelClip;
            if(clip == null || clip.stage == null || !screen.isActive)
            {
               return false;
            }
            var host:Object = clip.parent != null ? clip.parent : clip;
            holder = new Sprite();
            holder.name = BUTTON;
            var at:Point = host.globalToLocal(new Point(clip.stage.stageWidth,0));
            UiKit.tabButton(holder,page == REPLAYS ? "BIFROST LIST" : "BIFROST MENU",at.x - 220,at.y + 18,0.85,function():void
            {
               withdraw(screen);
               setOwn(page,false);
               if(again != null)
               {
                  again(screen);
               }
               else if(reshow != null)
               {
                  reshow(screen);
               }
            });
            host.addChild(holder);
            shownOn = screen;
            Platform.log("game menus: Bifrost menu button on the game's " + page + " page at " + int(at.x - 220) + "," + int(at.y + 18));
         }
         catch(e:Error)
         {
            Platform.log("game menus: no Bifrost menu button on the game's page: " + e);
         }
         return true;
      }

      public static function withdraw(screen:Object) : void
      {
         if(waiting != null && waiting.screen === screen)
         {
            waiting = null;
         }
         try
         {
            if(holder != null && holder.parent != null)
            {
               holder.parent.removeChild(holder);
            }
         }
         catch(e:Error)
         {
         }
         holder = null;
         shownOn = null;
      }
   }
}
