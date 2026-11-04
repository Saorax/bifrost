package bh.platform
{
   import flash.display.Sprite;
   import flash.events.MouseEvent;

   public class AchievementsWindow extends BigWindow
   {
      private static const TABS:Array = ["ACCOUNT","WEAPONS","LEGENDS","MATCHES","KOS","OTHER"];
      private static const COLS:int = 3;
      private static const CARD_H:Number = 44;

      private static var window:AchievementsWindow;

      private var asked:Object = {};

      public function AchievementsWindow(core:GameCore)
      {
         super(core);
      }

      public static function open() : void
      {
         if(window == null || ScreenManager.allScreens.indexOf(window) < 0)
         {
            window = new AchievementsWindow(ScreenManager.owner);
            ScreenManager.registerScreen(window);
            if(ScreenManager.var_14744 != null)
            {
               window.registrationIndex = ScreenManager.var_14744.registrationIndex;
            }
         }
         if(!window.isActive)
         {
            window.Display();
         }
      }

      public static function get shown() : AchievementsWindow
      {
         return window != null && window.isActive ? window : null;
      }

      private function get CARD_W() : Number
      {
         return Math.floor((area.width - 20 - 10 * (COLS - 1)) / COLS);
      }

      override protected function get fullPage() : Boolean
      {
         return true;
      }

      override protected function get title() : String
      {
         return "ACHIEVEMENTS";
      }

      override protected function get tabNames() : Array
      {
         return TABS;
      }

      override protected function get tabLayout() : Array
      {
         return [-500,170,0.8];
      }

      override protected function get confirmLabel() : String
      {
         return "DONE";
      }

      override protected function statusText() : String
      {
         if(steam == null)
         {
            return "STEAM NOT AVAILABLE";
         }
         var all:Array = list();
         var have:int = 0;
         for each(var a:Object in all)
         {
            have += unlocked(a) ? 1 : 0;
         }
         return have + " / " + all.length + " UNLOCKED";
      }

      override protected function hintText() : String
      {
         return defaultHint() + "     {Y} UNLOCK TAB";
      }

      private static function get steam() : Object
      {
         try
         {
            return ScreenManager.owner.var_7918;
         }
         catch(e:Error)
         {
         }
         return null;
      }

      private static function list() : Array
      {
         var out:Array = [];
         try
         {
            for each(var a:class_276 in class_276.var_8931)
            {
               if(a != null && a.var_13601 != null)
               {
                  out.push(a);
               }
            }
         }
         catch(e:Error)
         {
         }
         return out;
      }

      private static function events(a:Object) : Array
      {
         var out:Array = [];
         for each(var e:String in a.var_15185)
         {
            out.push(e);
         }
         return out;
      }

      private static function tabOf(a:Object) : int
      {
         var ev:Array = events(a);
         var e:String = ev.length > 0 ? ev[0] : "";
         var kind:String = e.split(".")[0];
         if(kind == "accountLevel" || kind == "goldEarned" || kind == "buy")
         {
            return 0;
         }
         if(kind == "heroLevel")
         {
            var parts:Array = e.split(".");
            return parts.length == 3 && !a.var_13199 ? 1 : 2;
         }
         if(kind == "play" || kind.indexOf("playlist") == 0 || kind == "place" || kind == "rematch")
         {
            return 3;
         }
         if(kind == "kill" || kind == "multiKill" || kind == "tripleHit" || kind == "singleMatch")
         {
            return 4;
         }
         return 5;
      }

      private function unlocked(a:Object) : Boolean
      {
         try
         {
            return steam != null && Boolean(steam.GetAchievement(a.var_13601));
         }
         catch(e:Error)
         {
         }
         return false;
      }

      private static function nameOf(a:Object) : String
      {
         var s:String = String(a.var_3794 || a.var_13601);
         return s.replace(/([a-z])([A-Z0-9])/g,"$1 $2").replace(/([0-9])([A-Z])/g,"$1 $2").toUpperCase();
      }

      private static function weapon(tag:String) : String
      {
         var w:String = tag.replace(/User$/,"");
         return w == "Katar" ? "Katars" : (w == "Fists" ? "Gauntlets" : (w == "Boots" ? "Battle Boots" : w));
      }

      private static function describe(a:Object) : String
      {
         var n:int = int(a.var_11932);
         var ev:Array = events(a);
         if(ev.length == 0)
         {
            return a.var_3794 == "HordeSilver" ? "Reach wave 26 in Horde (counted by the game)." :
               (a.var_3794 == "CatchBombsBronze" ? "Catch " + n + " bombs in a row (counted by the game)." : "");
         }
         var p:Array = String(ev[0]).split(".");
         switch(p[0])
         {
            case "goldEarned":
               return "Earn " + p[1] + " gold.";
            case "accountLevel":
               return "Reach account level " + p[1] + ".";
            case "heroLevel":
               if(a.var_13199)
               {
                  return "Reach level " + p[p.length - 1] + " with legends of " + n + " different weapons.";
               }
               return p.length == 3 ? "Reach level " + p[2] + " with a legend that uses " + weapon(p[1]) + "." :
                  "Reach level " + p[1] + " with " + (n == 1 ? "a legend." : n + " legends.");
            case "play":
               return "Play " + n + (n == 1 ? " online match." : " online matches.");
            case "place":
               return "Win " + n + " matches.";
            case "playlistPlay":
               return "Play " + n + " " + p[1] + " matches.";
            case "playlistPerfect":
               return "Win " + n + " " + p[1] + " matches without losing a stock.";
            case "playlist":
               return "Get " + p[2] + " KOs in a team match.";
            case "kill":
               return n + " KOs" + (p.length > 1 ? " (" + ev.join(", ").replace(/kill\./g,"") + ")." : ".");
            case "multiKill":
               return n + " " + String(p[1]).toLowerCase() + " KOs.";
            case "buy":
               return "Own a " + p[1] + " skin.";
         }
         return n + " x " + ev.join(", ");
      }

      override protected function buildTab(i:int) : void
      {
         var p:Sprite = panel(area.x,area.y,area.width,area.height);
         if(steam == null)
         {
            UiKit.text(p,"Steam isn't running, so achievements can't be read or unlocked.",20,20,15,UiKit.LIGHT,UiKit.BOLD);
            return;
         }
         var content:Sprite = scroller(p,10,10,area.width - 20,area.height - 20);
         var at:int = 0;
         for each(var a:class_276 in list())
         {
            if(tabOf(a) != i)
            {
               continue;
            }
            card(content,a,(at % COLS) * (CARD_W + 10),int(at / COLS) * (CARD_H + 6));
            at++;
         }
      }

      private function card(parent:Sprite, a:class_276, x:Number, y:Number) : void
      {
         var c:Sprite = new Sprite();
         c.x = x;
         c.y = y;
         c.buttonMode = true;
         parent.addChild(c);
         var have:Boolean = unlocked(a);
         var pending:Boolean = !have && asked[a.var_1741];
         UiKit.rect(c,0,0,CARD_W,CARD_H,have ? UiKit.ROW_SELECTED : UiKit.BODY,6);
         UiKit.fit(UiKit.text(c,nameOf(a),14,4,13,have ? UiKit.WHITE : UiKit.LIGHT,UiKit.XBOLD),CARD_W - 130);
         UiKit.fit(UiKit.text(c,describe(a),14,23,11,UiKit.GREY,UiKit.BOLD),CARD_W - 130);
         var mark:String = have ? "UNLOCKED" : (pending ? "UNLOCKING..." : "LOCKED");
         var t:* = UiKit.text(c,mark,CARD_W - 12,13,12,have ? UiKit.TEAL : UiKit.GREY,UiKit.XBOLD);
         t.x = CARD_W - 12 - t.width;
         var index:int = items.length;
         var self:AchievementsWindow = this;
         c.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
         {
            focus = index;
            paintFocus();
            self.ask([a]);
         });
         items.push({"sprite":c,"width":CARD_W,"height":CARD_H,"parent":parent,"achievement":a});
      }

      override protected function moveIn(it:Object, dir:int) : Boolean
      {
         var to:int = focus + dir * COLS;
         if(to >= 0 && to < items.length)
         {
            focus = to;
            paintFocus();
         }
         return true;
      }

      override protected function useItem(it:Object, dir:int) : void
      {
         if(dir != 0)
         {
            var to:int = focus + dir;
            if(to >= 0 && to < items.length)
            {
               focus = to;
               paintFocus();
            }
            return;
         }
         if(it.achievement != null)
         {
            ask([it.achievement]);
         }
      }

      override protected function optionItem(it:Object) : void
      {
         var locked:Array = [];
         for each(var x:Object in items)
         {
            if(x.achievement != null && !unlocked(x.achievement))
            {
               locked.push(x.achievement);
            }
         }
         ask(locked);
      }

      private function ask(which:Array) : void
      {
         var locked:Array = [];
         for each(var a:Object in which)
         {
            if(!unlocked(a))
            {
               locked.push(a);
            }
         }
         if(steam == null || locked.length == 0)
         {
            return;
         }
         var what:String = locked.length == 1 ? nameOf(locked[0]) : locked.length + " achievements";
         Modal.show("Unlock achievements","Unlock " + what + " on your Steam account? Steam can't lock it again.",
            [{"label":"Unlock","action":function():void
            {
               unlock(locked);
            }},{"label":"Cancel"}]);
      }

      private function unlock(which:Array) : void
      {
         for each(var a:Object in which)
         {
            try
            {
               class_4.method_9121(a.var_1741);
               asked[a.var_1741] = true;
               Platform.log("achievements: unlock asked for " + a.var_13601);
            }
            catch(e:Error)
            {
               Platform.log("achievements: unlock of " + a.var_13601 + " failed: " + e.message);
            }
         }
         refreshIn = 60;
         build();
      }

      private var refreshIn:int = 0;

      override protected function everyFrame() : void
      {
         if(refreshIn > 0 && --refreshIn == 0)
         {
            build();
         }
      }
   }
}
