package bh.platform
{
   import flash.display.Bitmap;
   import flash.display.DisplayObject;
   import flash.display.MovieClip;
   import flash.display.Sprite;
   import flash.events.MouseEvent;

   public class SkinEffectsWindow extends BigWindow
   {
      private static var window:SkinEffectsWindow;
      private static const COLS:int = 4;
      private static const TILE_H:Number = 80;
      private static const PIC:Number = 64;
      private static const BADGE:Number = 30;

      private var firstTile:int = 0;

      public function SkinEffectsWindow(core:GameCore)
      {
         super(core);
      }

      public static function open() : void
      {
         if(window == null || ScreenManager.allScreens.indexOf(window) < 0)
         {
            window = new SkinEffectsWindow(ScreenManager.owner);
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

      public static function get shown() : SkinEffectsWindow
      {
         return window != null && window.isActive ? window : null;
      }

      override protected function get title() : String
      {
         return "SKIN EFFECTS";
      }

      override protected function get tabNames() : Array
      {
         return ["SKINS","WEAPONS"];
      }

      override protected function get confirmLabel() : String
      {
         return "DONE";
      }

      private static function all(weapons:Boolean) : Array
      {
         var out:Array = [];
         for each(var g:Array in ClassicEffects.groups(weapons) || [])
         {
            for each(var e:Array in g[1])
            {
               out.push([e,g,skinId(e)]);
            }
         }
         out.sort(byId);
         return out;
      }

      private static function skinId(e:Array) : uint
      {
         try
         {
            return e[0] == "c" ? uint(e[3].var_14823) : uint(e[3].var_11095);
         }
         catch(err:Error)
         {
         }
         return 0;
      }

      private static function byId(a:Array, b:Array) : int
      {
         return uint(a[2]) < uint(b[2]) ? -1 : (uint(a[2]) > uint(b[2]) ? 1 : 0);
      }

      override protected function statusText() : String
      {
         var list:Array = all(tab == 1);
         var kept:int = 0;
         for each(var t:Array in list)
         {
            if(ClassicEffects.swapped(t[0][0],t[0][1]))
            {
               kept++;
            }
         }
         return kept + " UNCHANGED, " + (list.length - kept) + " PARENT EFFECTS";
      }

      override protected function buildTab(i:int) : void
      {
         var p:Sprite = panel(area.x,area.y,area.width,area.height);
         var list:Array = all(i == 1);
         if(list.length == 0)
         {
            UiKit.text(p,"No " + (i == 1 ? "weapon skins" : "skins") + " change their effects.",20,20,15,UiKit.LIGHT,UiKit.BOLD);
            return;
         }
         var w:Number = area.width - 40;
         var kind:String = i == 1 ? "w" : "c";
         var names:Array = [];
         for each(var t:Array in list)
         {
            names.push(t[0][1]);
         }
         var bw:Number = 220;
         var unchanged:Function = function():void
         {
            ClassicEffects.setSwapped(kind,names,true);
            build();
         };
         var parents:Function = function():void
         {
            ClassicEffects.setSwapped(kind,names,false);
            build();
         };
         items.push({"sprite":button(p,"ALL UNCHANGED",20,16,bw,unchanged),"width":bw,"height":30,"parent":p,"use":unchanged});
         items.push({"sprite":button(p,"ALL PARENT EFFECTS",20 + bw + 12,16,bw,parents),"width":bw,"height":30,"parent":p,
            "use":parents});
         UiKit.fit(UiKit.text(p,i == 1 ? "Unchanged keeps the weapon skin's original effects and sounds. Parent Effects use the effects of the base weapon." :
            "Unchanged keeps the skin's original effects and sounds. Parent Effects use the effects of the base legend.",20 + bw * 2 + 30,22,13,
            UiKit.GREY,UiKit.MEDIUM),w - bw * 2 - 30);
         var content:Sprite = scroller(p,20,60,w,area.height - 72);
         firstTile = items.length;
         var tw:Number = (w - 20 - (COLS - 1) * 8) / COLS;
         for(var n:int = 0; n < list.length; n++)
         {
            tile(content,list[n][0],list[n][1],(n % COLS) * (tw + 8),int(n / COLS) * (TILE_H + 6),tw);
         }
      }

      private function tile(parent:Sprite, skin:Array, group:Array, x:Number, y:Number, w:Number) : void
      {
         var c:Sprite = new Sprite();
         c.x = x;
         c.y = y;
         c.buttonMode = true;
         parent.addChild(c);
         var keep:Boolean = ClassicEffects.swapped(skin[0],skin[1]);
         UiKit.rect(c,0,0,w,TILE_H,keep ? UiKit.ROW_SELECTED : UiKit.BODY,6);
         UiKit.icon(c,picture(skin),6,(TILE_H - PIC) / 2,PIC);
         var badge:DisplayObject = skin[0] == "c" ? legendIcon(group[2] as HeroType) : weaponIcon(String(skin[3].var_12803));
         if(badge != null)
         {
            UiKit.icon(c,badge,PIC - BADGE + 9,TILE_H - BADGE - 3,BADGE);
         }
         var tx:Number = PIC + 18;
         UiKit.fit(UiKit.text(c,String(skin[2]).toUpperCase(),tx,12,14,UiKit.WHITE,UiKit.XBOLD),w - tx - 10);
         UiKit.fit(UiKit.text(c,String(group[0]).toUpperCase(),tx,32,11,UiKit.GREY,UiKit.BOLD),w - tx - 10);
         UiKit.text(c,keep ? "UNCHANGED" : "PARENT EFFECTS",tx,50,12,keep ? UiKit.WHITE : UiKit.TEAL,UiKit.XBOLD);
         var flip:Function = function():void
         {
            ClassicEffects.setSwapped(skin[0],[skin[1]],!ClassicEffects.swapped(skin[0],skin[1]));
            build();
         };
         var index:int = items.length;
         c.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
         {
            focus = index;
            flip();
         });
         items.push({"sprite":c,"width":w,"height":TILE_H,"parent":parent,"use":flip});
      }

      private static function still(clip:MovieClip) : MovieClip
      {
         if(clip != null)
         {
            clip.gotoAndStop(1);
            clip.stopAllMovieClips();
         }
         return clip;
      }

      private static function legendIcon(hero:HeroType) : DisplayObject
      {
         try
         {
            return hero != null && hero.var_12260 ? still(class_687.method_1714(hero.var_12260 + "M",hero.var_6330)) : null;
         }
         catch(e:Error)
         {
         }
         return null;
      }

      private static function weaponIcon(base:String) : DisplayObject
      {
         try
         {
            var clip:MovieClip = base ? class_687.method_1714("a_WeaponIcon_" + base,"UI_Icons") : null;
            if(clip != null)
            {
               clip.stopAllMovieClips();
            }
            return clip;
         }
         catch(e:Error)
         {
         }
         return null;
      }

      private static function picture(skin:Array) : DisplayObject
      {
         try
         {
            if(skin[0] == "c")
            {
               var c:CostumeType = skin[3] as CostumeType;
               if(c == null)
               {
                  return null;
               }
               if(c.var_753 != null && c.var_556 != null)
               {
                  var cross:MovieClip = still(class_687.method_1714(c.var_753 + "M",c.var_556));
                  if(cross != null)
                  {
                     return cross;
                  }
               }
               return c.var_12178 ? still(class_687.method_1714(c.var_12178,c.var_4697)) : null;
            }
            var w:class_725 = skin[3] as class_725;
            var bmp:Bitmap = class_51.method_7309(ScreenManager.owner,w,null,PIC).method_7455();
            if(bmp != null && bmp.bitmapData != null)
            {
               var copy:Bitmap = new Bitmap(bmp.bitmapData.clone());
               copy.smoothing = true;
               return copy;
            }
            var icon:MovieClip = class_687.method_1714(w.var_2697 ? w.var_2697 : "a_WeaponIcon_" + w.var_12803,"UI_Icons");
            if(icon != null)
            {
               icon.stopAllMovieClips();
            }
            return icon;
         }
         catch(e:Error)
         {
         }
         return null;
      }

      override protected function useItem(it:Object, dir:int) : void
      {
         if(dir != 0)
         {
            var to:int = focus + dir;
            if(focus >= firstTile ? to >= firstTile && to < items.length : to >= 0 && to < firstTile)
            {
               focus = to;
               paintFocus();
            }
            return;
         }
         super.useItem(it,dir);
      }

      override protected function moveIn(it:Object, dir:int) : Boolean
      {
         if(focus < firstTile)
         {
            if(dir > 0 && firstTile < items.length)
            {
               focus = firstTile;
               paintFocus();
               return true;
            }
            return false;
         }
         var to:int = focus + dir * COLS;
         if(to >= firstTile && to < items.length)
         {
            focus = to;
         }
         else if(to < firstTile)
         {
            focus = 0;
         }
         else
         {
            focus = items.length - 1;
         }
         paintFocus();
         return true;
      }
   }
}
