package bh.platform
{
   import flash.display.DisplayObject;
   import flash.display.DisplayObjectContainer;
   import flash.display.Sprite;
   import flash.display.Stage;
   import flash.geom.Rectangle;
   import flash.text.TextField;
   import flash.utils.Dictionary;

   public final class RatingTags
   {
      public static var before:Object = {};
      public static var cards:Object = {};
      public static var after:Object = {};

      private static var layer:Sprite = null;
      private static var registered:Boolean = false;
      private static var previewCards:Array = null;

      public function RatingTags()
      {
      }

      public static function init() : void
      {
         if(registered)
         {
            return;
         }
         registered = true;
         Hooks.frameRendering.add(onFrame);
      }

      public static function preview(cards:Array) : void
      {
         previewCards = cards;
      }

      public static function previewGone() : void
      {
         previewCards = null;
      }

      public static function reset() : void
      {
         before = {};
         after = {};
         cards = {};
         previewCards = null;
      }

      public static function rankLabel(stars:uint) : String
      {
         if(stars == 0)
         {
            return "UNRANKED";
         }
         if(stars == 50)
         {
            return "VALHALLAN";
         }
         try
         {
            return String(class_189.method_7376(stars)).toUpperCase() + " " + (6 - int(class_189.method_1542(stars)));
         }
         catch(e:Error)
         {
         }
         return "";
      }

      private static function stage() : Stage
      {
         try
         {
            return Object(GameApp.mainInstance).stage as Stage;
         }
         catch(e:Error)
         {
         }
         return null;
      }

      private static function clear() : void
      {
         if(layer != null)
         {
            if(layer.parent != null)
            {
               layer.parent.removeChild(layer);
            }
            layer = null;
         }
      }

      private static function tierOf(stars:uint) : String
      {
         if(stars == 0)
         {
            return "Unranked";
         }
         if(stars == 50)
         {
            return "Valhallan";
         }
         try
         {
            return String(class_189.method_7376(stars));
         }
         catch(e:Error)
         {
         }
         return "Unranked";
      }

      private static function onFrame() : void
      {
         if(!RatingExtras.on)
         {
            clear();
            drawnKey = "";
            return;
         }
         try
         {
            var tags:Array = TAGS;
            tags.length = 0;
            if(previewCards != null && previewCards.length == 2)
            {
               drawSides();
               return;
            }
            if(previewCards != null)
            {
               for each(var c:Array in previewCards)
               {
                  var b:Object = before[uint(c[1])];
                  if(b != null && c[0] != null)
                  {
                     var placing:Boolean = uint(b.games) < 10;
                     tags.push({"at":c[0],"podium":false,"top":placing ? "PLACEMENT " + (uint(b.games) + 1) + "/10" :
                        rankLabel(uint(b.stars)),"bottom":String(b.rating),"colour":0xFFFFFF,
                        "tier":placing ? "Unranked" : tierOf(uint(b.stars)),"rating":int(b.rating)});
                  }
               }
            }
            else if(ScreenManager.var_6219 != null && ScreenManager.var_6219.isActive && !ScreenManager.var_14957.isActive &&
               !ScreenManager.var_4066.isActive && !(ScreenManager.var_4776 != null && ScreenManager.var_4776.isActive) &&
               !(ScreenManager.var_4268 != null && ScreenManager.var_4268.isActive) &&
               !(ScreenManager.var_11413 != null && ScreenManager.var_11413.isActive) &&
               !(ScreenManager.var_12129 != null && ScreenManager.var_12129.isActive))
            {
               var cards:Object = ScreenManager.var_6219.var_3126;
               for(var i:int = 0; cards != null && int(cards.length) <= 2 && i < int(cards.length); i++)
               {
                  var card:Object = cards[i];
                  if(card == null || card.var_1496 == null || card.var_4483 == null || !card.var_4483.visible ||
                     card.var_4483.stage == null)
                  {
                     continue;
                  }
                  var slot:DisplayObject = card.var_7350 != null && card.var_7350.clip != null ? card.var_7350.clip : null;
                  var at:DisplayObject = slot != null && slot.stage != null ? slot : card.var_4483;
                  var emoji:DisplayObject = card.var_2145 != null && card.var_2145.isActive && card.var_2145.clip != null &&
                     card.var_2145.clip.visible && card.var_2145.clip.stage != null ? card.var_2145.clip : null;
                  var menuOpen:Boolean = false;
                  try
                  {
                     menuOpen = card.var_12747 != null && card.var_12747.var_2793 != null &&
                        card.var_12747.var_2793.var_5063 != null && card.var_12747.var_2793.var_5063.visible;
                  }
                  catch(eMenu:Error)
                  {
                  }
                  var pid:uint = uint(card.var_1496.var_14656);
                  var a:Array = after[pid];
                  var g:int = before[pid] != null ? int(before[pid].games) : 10;
                  var inPlacement:Boolean = a != null ? g + 1 < 10 : g < 10;
                  var label:String = inPlacement ? "PLACEMENT " + (g + 1) + "/10" : "";
                  if(a != null)
                  {
                     var d:int = int(a[1]) - int(a[0]);
                     tags.push({"at":at,"below":emoji,"hidden":menuOpen,"podium":at === slot,"top":label != "" ? label : rankLabel(uint(a[2])),
                        "bottom":a[0] + "  >  " + a[1] + "  (" + (d >= 0 ? "+" : "") + d + ")","colour":d >= 0 ? 0x5BD67A : 0xF0646A,
                        "tier":inPlacement ? "Unranked" : tierOf(uint(a[2])),"rating":int(a[1])});
                  }
                  else if(before[pid] != null)
                  {
                     tags.push({"at":at,"below":emoji,"hidden":menuOpen,"podium":at === slot,"top":label != "" ? label : rankLabel(uint(before[pid].stars)),
                        "bottom":String(before[pid].rating),"colour":0xFFFFFF,
                        "tier":inPlacement ? "Unranked" : tierOf(uint(before[pid].stars)),"rating":int(before[pid].rating)});
                  }
               }
            }
            draw(tags);
         }
         catch(e:Error)
         {
            clear();
         }
      }

      private static var drawnKey:String = "";
      private static var incomplete:Boolean = false;
      private static var sidesDrawn:Array = [];
      private static const TAGS:Array = [];

      private static function drawSides() : void
      {
         var s:Stage = stage();
         var me:Object = before[uint(previewCards[0][1])];
         var them:Object = before[uint(previewCards[1][1])];
         if(s == null || me == null || them == null)
         {
            clear();
            drawnKey = "";
            return;
         }
         var key:String = "sides:" + s.stageWidth + "x" + s.stageHeight;
         var holder:DisplayObjectContainer = Layers.screenOf(previewCards[0][0] as DisplayObject);
         if(key == drawnKey && me === sidesDrawn[0] && them === sidesDrawn[1] && cards === sidesDrawn[2] && layer != null &&
            layer.parent != null && !incomplete)
         {
            Layers.put(layer,holder,s);
            return;
         }
         sidesDrawn = [me,them,cards];
         clear();
         drawnKey = key;
         layer = new Sprite();
         layer.mouseEnabled = layer.mouseChildren = false;
         var sc:Number = s.stageHeight / 1080;
         var w:Number = 330 * sc;
         var y:Number = 150 * sc;
         var ok1:Boolean = RatingExtras.sidePanel(layer,me,cards[String(previewCards[0][1])],24 * sc,y,w,sc,
            accountName(previewCards[0][0],"YOU"),true);
         var ok2:Boolean = RatingExtras.sidePanel(layer,them,cards[String(previewCards[1][1])],s.stageWidth - 24 * sc - w,y,w,sc,
            accountName(previewCards[1][0],"OPPONENT"),true);
         incomplete = !ok1 || !ok2;
         Layers.put(layer,holder,s);
      }

      private static function accountName(card:Object, fallback:String) : String
      {
         var t:TextField = findText(card as DisplayObjectContainer,"am_AccountName");
         var name:String = t != null ? t.text.replace(/^\s+|\s+$/g,"") : "";
         return name != "" ? name.toUpperCase() : fallback;
      }

      private static function findText(c:DisplayObjectContainer, name:String) : TextField
      {
         if(c == null)
         {
            return null;
         }
         for(var i:int = 0; i < c.numChildren; i++)
         {
            var ch:DisplayObject = c.getChildAt(i);
            if(ch is TextField && ch.name == name)
            {
               return TextField(ch);
            }
            var deeper:TextField = ch is DisplayObjectContainer ? findText(DisplayObjectContainer(ch),name) : null;
            if(deeper != null)
            {
               return deeper;
            }
         }
         return null;
      }

      private static function draw(tags:Array) : void
      {
         var s:Stage = stage();
         if(s == null || tags.length == 0)
         {
            clear();
            drawnKey = "";
            return;
         }
         var key:String = s.stageWidth + "x" + s.stageHeight + ":";
         var boxes:Array = [];
         for each(var t:Object in tags)
         {
            boxes.push(t.podium ? DisplayObject(t.at).getBounds(s) : anchor(DisplayObject(t.at),s));
            var under:Rectangle = t.below != null ? DisplayObject(t.below).getBounds(s) : null;
            t.underY = under != null ? under.bottom : NaN;
            key += t.top + "|" + t.bottom + "|" + t.colour + "|" + t.tier + "|" + t.rating + "|" + t.gain + "|" + t.loss +
               (t.podium ? "p" : "") + ";";
         }
         var holder:DisplayObjectContainer = Layers.screenOf(DisplayObject(tags[0].at));
         var sc:Number = s.stageHeight / 1080;
         var row:Number = 0;
         for(var j:int = 0; j < tags.length; j++)
         {
            if(!tags[j].podium)
            {
               row = Math.max(row,Rectangle(boxes[j]).bottom);
            }
         }
         if(key == drawnKey && layer != null && layer.parent != null && !incomplete && layer.numChildren == tags.length)
         {
            for(var k:int = 0; k < tags.length; k++)
            {
               place(layer.getChildAt(k),tags[k],boxes[k],row,sc,s);
            }
            Layers.put(layer,holder,s);
            return;
         }
         clear();
         drawnKey = key;
         incomplete = false;
         layer = new Sprite();
         layer.mouseEnabled = layer.mouseChildren = false;
         for(var i:int = 0; i < tags.length; i++)
         {
            var tag:Object = tags[i];
            var card:Sprite = new Sprite();
            var icon:Number = 52 * sc;
            var top:TextField = UiKit.text(card,String(tag.top),icon + 14 * sc,8 * sc,16 * sc,0xFFFFFF,UiKit.XBOLD);
            var bottom:TextField = UiKit.text(card,String(tag.bottom),icon + 14 * sc,30 * sc,19 * sc,uint(tag.colour),UiKit.XBOLD);
            var w:Number = icon + 28 * sc + Math.max(top.width,bottom.width);
            var h:Number = 60 * sc;
            if(tag.gain != null)
            {
               var gain:TextField = UiKit.text(card,"+" + tag.gain,icon + 14 * sc,54 * sc,16 * sc,0x5BD67A,UiKit.XBOLD);
               var loss:TextField = UiKit.text(card,"-" + tag.loss,gain.x + gain.width + 10 * sc,54 * sc,16 * sc,0xF0646A,UiKit.XBOLD);
               w = Math.max(w,loss.x + loss.width + 14 * sc);
               h = 80 * sc;
            }
            UiKit.rect(card,-2 * sc,-2 * sc,w + 4 * sc,h + 4 * sc,0x2C5A80,12 * sc);
            UiKit.rect(card,0,0,w,h,0x07142A,10 * sc);
            for(var c:int = card.numChildren - 1; c >= 0; c--)
            {
               if(card.getChildAt(c) is TextField)
               {
                  card.setChildIndex(card.getChildAt(c),card.numChildren - 1);
               }
            }
            var badge:Sprite = RatingExtras.rankIcon(int(tag.rating),String(tag.tier) == "Unranked",icon - 8 * sc);
            if(badge != null)
            {
               badge.x = 6 * sc + (icon - badge.width) / 2;
               badge.y = (h - badge.height) / 2;
               card.addChild(badge);
            }
            card.name = w + "x" + h;
            place(card,tag,boxes[i],row,sc,s);
            layer.addChild(card);
         }
         Layers.put(layer,holder,s);
      }

      private static var anchors:Dictionary = new Dictionary(true);

      private static function anchor(at:DisplayObject, s:Stage) : Rectangle
      {
         var field:DisplayObject = anchors[at] as DisplayObject;
         if(field == null || field.stage == null)
         {
            field = findText(at as DisplayObjectContainer,"am_AccountName");
            if(field != null)
            {
               anchors[at] = field;
            }
         }
         var target:DisplayObject = field != null && field.stage != null ? field : at;
         return target.getBounds(s);
      }

      private static function place(card:DisplayObject, tag:Object, box:Rectangle, row:Number, sc:Number, s:Stage) : void
      {
         var size:Array = card.name.split("x");
         var w:Number = Number(size[0]);
         var h:Number = Number(size[1]);
         var x:Number = Math.round(box.x + box.width / 2 - w / 2);
         var y:Number = tag.podium ? Math.round(Math.min(Math.max(box.bottom,isNaN(tag.underY) ? box.bottom : tag.underY) + 6 * sc,
            s.stageHeight - h - 4 * sc)) : Math.round(s.stageHeight - h - 24 * sc);
         var settle:Number = 12 * sc;
         if(card.parent == null || Math.abs(card.x - x) > settle || Math.abs(card.y - y) > settle)
         {
            card.x = x;
            card.y = y;
         }
         card.visible = !tag.hidden;
      }
   }
}
