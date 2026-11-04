package bh.platform
{
   import flash.display.MovieClip;
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.filesystem.File;
   import flash.filesystem.FileMode;
   import flash.filesystem.FileStream;
   import flash.events.MouseEvent;
   import flash.net.FileFilter;
   import flash.text.TextField;
   import flash.utils.getTimer;

   public class ColorEditor extends BigWindow
   {
      public static const MOD_ID:String = "my-colors";
      private static const TABS:Array = ["COLOURS","SHADES","MY SCHEMES"];
      private static const GROUPS:Array = [
         ["HAIR",["HairLt","Hair","HairDk"]],
         ["MAIN",["Body1VL","Body1Lt","Body1","Body1Dk","Body1VD","Body1Acc"]],
         ["SECOND",["Body2VL","Body2Lt","Body2","Body2Dk","Body2VD","Body2Acc"]],
         ["SPECIAL",["SpecialVL","SpecialLt","Special","SpecialDk","SpecialVD","SpecialAcc"]],
         ["CLOTH",["ClothVL","ClothLt","Cloth","ClothDk"]],
         ["WEAPON",["WeaponVL","WeaponLt","Weapon","WeaponDk","WeaponAcc"]],
         ["HANDS",["HandsLt","HandsDk","HandsSkinLt","HandsSkinDk"]]];
      private static const SHADE_NAMES:Object = {"VL":"very light","Lt":"light","Dk":"dark","VD":"very dark","Acc":"accent",
         "SkinLt":"skin light","SkinDk":"skin dark"};

      override protected function get fullPage() : Boolean
      {
         return true;
      }

      private function get PREVIEW_W() : Number
      {
         return Math.max(380,Math.round(area.width * 0.3));
      }

      private function get ROWS_X() : Number
      {
         return area.x + PREVIEW_W + 10;
      }

      private function get ROWS_W() : Number
      {
         return area.right - ROWS_X;
      }

      private function get COL_W() : Number
      {
         return Math.floor((ROWS_W - 10) / 2);
      }
      private static const BAR_H:Number = 46;

      private static var window:ColorEditor;
      private static var afterClose:Function;

      private var doc:Object;
      private var previewScheme:class_76;
      private var heroIndex:int = 0;
      private var skinIndex:int = 0;
      private var previewHolder:MovieClip;
      private var previewInfo:TextField;
      private var doll:LegendDoll;
      private var dirty:Boolean = true;
      private var lastDraw:int = 0;
      private var deleteArmed:String = null;
      private var note:String = "";
      private var describe:TextField;
      private var describeLabel:TextField;
      private var colW:Number = 0;

      public function ColorEditor(core:GameCore)
      {
         super(core);
         doc = fresh("Blue");
      }

      public static function open(closed:Function = null) : void
      {
         afterClose = closed;
         if(window == null || ScreenManager.allScreens.indexOf(window) < 0)
         {
            window = new ColorEditor(ScreenManager.owner);
            ScreenManager.registerScreen(window);
            if(ScreenManager.var_14744 != null)
            {
               window.registrationIndex = ScreenManager.var_14744.registrationIndex;
            }
         }
         if(!window.isActive)
         {
            window.dirty = true;
            window.Display();
         }
      }

      public static function get shown() : ColorEditor
      {
         return window != null && window.isActive ? window : null;
      }

      override protected function get title() : String
      {
         return "COLOUR EDITOR";
      }

      override protected function get tabNames() : Array
      {
         return TABS;
      }

      override protected function get confirmLabel() : String
      {
         return "DONE";
      }

      override protected function statusText() : String
      {
         return note;
      }

      override protected function hintText() : String
      {
         var n:Object = Prompts.KEYS;
         return n.tabs + " TABS     " + n.select + " SELECT     " + n.option + (tab == 2 ? " DELETE" : " RESET") + "     " +
            n.back + " BACK";
      }

      override protected function back() : void
      {
         clearDoll();
         Hide();
         var then:Function = afterClose;
         afterClose = null;
         if(then != null)
         {
            try
            {
               then();
            }
            catch(e:Error)
            {
               ErrorLog.write("colour editor: reopening the mods window failed: " + e);
            }
         }
      }

      private static function fresh(base:String) : Object
      {
         return {"key":null,"name":"My colours","base":base,"adjust":{},"shades":{}};
      }

      private static function bases() : Array
      {
         var out:Array = [];
         try
         {
            for each(var s:class_76 in class_76.var_3762)
            {
               if(s != null && s.var_3938 == 0 && s != class_76.NO_COLOR_SCHEME && s.var_10427 != null && s.var_10427.length > 0)
               {
                  out.push(s);
               }
            }
            out.sortOn("var_14291",Array.NUMERIC);
         }
         catch(e:Error)
         {
         }
         return out;
      }

      private static function slot(name:String) : int
      {
         try
         {
            return class_76.method_1421(name);
         }
         catch(e:Error)
         {
         }
         return -1;
      }

      private static function baseScheme(name:String) : class_76
      {
         var s:class_76 = class_76.method_4680(name);
         return s != null ? s : class_76.method_4680("Blue");
      }

      private function colors() : Array
      {
         var base:class_76 = baseScheme(doc.base);
         var out:Array = base != null && base.var_10427 != null ? base.var_10427.concat() : [];
         for each(var g:Array in GROUPS)
         {
            var adj:Array = doc.adjust[g[0]];
            for each(var name:String in g[1])
            {
               var i:int = slot(name);
               if(i < 0)
               {
                  continue;
               }
               if(doc.shades[name] != null)
               {
                  out[i] = uint(doc.shades[name]);
               }
               else if(adj != null && uint(out[i]) != 0)
               {
                  out[i] = shift(uint(out[i]),adj[0],adj[1],adj[2]);
               }
            }
         }
         return out;
      }

      private function colorOf(name:String) : uint
      {
         var i:int = slot(name);
         return i >= 0 ? uint(colors()[i]) : 0;
      }

      public static function shift(rgb:uint, h:Number, s:Number, v:Number) : uint
      {
         var hsv:Array = toHsv(rgb);
         var hue:Number = (hsv[0] + h + 360) % 360;
         var sat:Number = clamp(hsv[1] + s / 100);
         var val:Number = clamp(hsv[2] + v / 100);
         return fromHsv(hue,sat,val);
      }

      private static function clamp(x:Number) : Number
      {
         return Math.max(0,Math.min(1,x));
      }

      public static function toHsv(rgb:uint) : Array
      {
         var r:Number = (rgb >> 16 & 255) / 255;
         var g:Number = (rgb >> 8 & 255) / 255;
         var b:Number = (rgb & 255) / 255;
         var max:Number = Math.max(r,g,b);
         var min:Number = Math.min(r,g,b);
         var d:Number = max - min;
         var h:Number = 0;
         if(d > 0)
         {
            if(max == r)
            {
               h = 60 * (((g - b) / d) % 6);
            }
            else if(max == g)
            {
               h = 60 * ((b - r) / d + 2);
            }
            else
            {
               h = 60 * ((r - g) / d + 4);
            }
         }
         return [(h + 360) % 360,max > 0 ? d / max : 0,max];
      }

      public static function fromHsv(h:Number, s:Number, v:Number) : uint
      {
         var c:Number = v * s;
         var x:Number = c * (1 - Math.abs(h / 60 % 2 - 1));
         var m:Number = v - c;
         var rgb:Array = h < 60 ? [c,x,0] : h < 120 ? [x,c,0] : h < 180 ? [0,c,x] : h < 240 ? [0,x,c] : h < 300 ? [x,0,c] : [c,0,x];
         var out:uint = 0;
         for(var k:int = 0; k < 3; k++)
         {
            out = out << 8 | Math.round((rgb[k] + m) * 255);
         }
         return out;
      }

      public static function hex(rgb:uint) : String
      {
         var s:String = rgb.toString(16).toUpperCase();
         while(s.length < 6)
         {
            s = "0" + s;
         }
         return s;
      }

      override public function OnCreateScreen() : void
      {
         super.OnCreateScreen();
         var box:Sprite = new Sprite();
         box.x = area.x;
         box.y = area.y;
         body.addChild(box);
         UiKit.rect(box,0,0,PREVIEW_W,area.height,UiKit.PANEL);
         UiKit.rect(box,10,10,PREVIEW_W - 20,area.height - 70,UiKit.BODY);
         previewHolder = new MovieClip();
         previewHolder.mouseEnabled = false;
         previewHolder.mouseChildren = false;
         box.addChild(previewHolder);
         previewHolder.mask = UiKit.rect(box,10,10,PREVIEW_W - 20,area.height - 70,0);
         previewInfo = UiKit.text(box,"",14,area.height - 54,13,UiKit.LIGHT,UiKit.MEDIUM,PREVIEW_W - 28);
         dirty = true;
      }

      private function heroes() : Array
      {
         var out:Array = [];
         try
         {
            for each(var h:HeroType in HeroType.var_12147)
            {
               if(h != null && h.var_10527 != null)
               {
                  out.push(h);
               }
            }
         }
         catch(e:Error)
         {
         }
         return out;
      }

      private function skinsOf(hero:HeroType) : Array
      {
         var out:Array = [];
         if(hero == null)
         {
            return out;
         }
         out.push(hero.var_10527);
         try
         {
            for each(var c:CostumeType in CostumeType.var_12012)
            {
               if(c != null && c.var_7289 == hero && c != hero.var_10527 && c.var_3789 != null && c.var_3789.length > 0)
               {
                  out.push(c);
               }
            }
         }
         catch(e:Error)
         {
         }
         return out;
      }

      private function previewCostume() : CostumeType
      {
         var hs:Array = heroes();
         if(hs.length == 0)
         {
            return null;
         }
         heroIndex = (heroIndex % hs.length + hs.length) % hs.length;
         var skins:Array = skinsOf(hs[heroIndex]);
         skinIndex = (skinIndex % skins.length + skins.length) % skins.length;
         return skins[skinIndex];
      }

      private static function gameText(key:String, fallback:String) : String
      {
         try
         {
            var s:String = class_256.method_1351(key);
            if(s != null && s != "" && s != key)
            {
               return s;
            }
         }
         catch(e:Error)
         {
         }
         return fallback;
      }

      private static const ANIM_KINDS:Array = ["SELECTED","IDLE","EMOTE","ATTACK","MOVEMENT"];
      private static const ATTACK_SLOTS:Array = [11,7,8,1,2,3,4,5,6,9,10];
      private static const SLOT_KEYS:Object = {
         "1":["NLIGHT",null], "2":["SLIGHT",null], "3":["DLIGHT",null], "4":["NAIR",null], "5":["SAIR",null],
         "6":["DAIR",null], "7":["SSIG","SHEAVY"], "8":["DSIG","DHEAVY"], "9":["RECOVERY",null], "10":["GP",null],
         "11":["NSIG","NHEAVY"]};
      private var animKind:int = 0;
      private var animPick:int = 0;
      private var animPlays:Boolean = true;

      private static function movements() : Object
      {
         return class_454.var_11922 != null ? class_454.var_11922 : [];
      }

      private function animCount() : int
      {
         switch(animKind)
         {
            case 2:
               return class_629.var_4365 != null ? int(class_629.var_4365.length) : 0;
            case 3:
               return 3 * ATTACK_SLOTS.length;
            case 4:
               return 3 * int(movements().length);
         }
         return 0;
      }

      private function pickIndex() : int
      {
         var n:int = animCount();
         return n > 0 ? (animPick % n + n) % n : 0;
      }

      private static function weaponItem(hero:HeroType, w:int) : ItemType
      {
         return w == 2 ? ItemType.var_6395 : ItemType.method_8638(w == 0 ? hero.mBaseWeapon1 : hero.mBaseWeapon2);
      }

      private static function weaponLabel(hero:HeroType, w:int) : String
      {
         if(w == 2)
         {
            return "UNARMED";
         }
         var item:ItemType = weaponItem(hero,w);
         return item != null ? gameText(item.mDisplayNameKey,w == 0 ? hero.mBaseWeapon1 : hero.mBaseWeapon2).toUpperCase() : "-";
      }

      private static function attackPower(hero:HeroType, w:int, slot:int) : PowerType
      {
         var name:String = null;
         if(w < 2 && (slot == 7 || slot == 8 || slot == 11))
         {
            name = slot == 7 ? (w == 0 ? hero.mSpecialPower1_Forward : hero.mSpecialPower2_Forward) : slot == 8 ?
               (w == 0 ? hero.mSpecialPower1_Down : hero.mSpecialPower2_Down) : (w == 0 ? hero.mSpecialPower1 : hero.mSpecialPower2);
         }
         else
         {
            var item:ItemType = weaponItem(hero,w);
            name = item != null ? item.var_13621[slot] : null;
         }
         return name != null ? PowerType.method_6087(name) : null;
      }

      private function animLabel(costume:CostumeType) : String
      {
         var hero:HeroType = costume != null ? costume.var_7289 : null;
         var i:int = pickIndex();
         try
         {
            switch(animKind)
            {
               case 2:
                  var taunt:class_629 = class_629.var_4365[i];
                  return gameText(taunt.mDisplayNameKey,taunt.mTauntName).toUpperCase();
               case 3:
                  var w:int = int(i / ATTACK_SLOTS.length);
                  var keys:Array = SLOT_KEYS[String(ATTACK_SLOTS[i % ATTACK_SLOTS.length])];
                  return (hero != null ? weaponLabel(hero,w) : "-") + "  " + (w == 2 && keys[1] != null ? keys[1] : keys[0]);
               case 4:
                  var moves:Object = movements();
                  return (hero != null ? weaponLabel(hero,int(i / moves.length)) : "-") + "  " +
                     String(moves[i % moves.length]).toUpperCase();
            }
         }
         catch(e:Error)
         {
         }
         return ANIM_KINDS[animKind];
      }

      private function animSpec(costume:CostumeType) : Array
      {
         var hero:HeroType = costume.var_7289;
         var selected:String = PaperDoll.method_637(hero,costume);
         var i:int = pickIndex();
         try
         {
            switch(animKind)
            {
               case 1:
                  var idle:String = PaperDoll.method_4400(hero,costume);
                  return [idle,idle,null];
               case 2:
                  var taunt:class_629 = class_629.var_4365[i];
                  return [taunt.var_5358,taunt.method_1674(costume,null,false,false,0),null];
               case 3:
                  var power:PowerType = attackPower(hero,int(i / ATTACK_SLOTS.length),int(ATTACK_SLOTS[i % ATTACK_SLOTS.length]));
                  if(power != null)
                  {
                     var attack:String = power.method_3298(costume,null).var_10352;
                     return [attack,attack,ItemType.method_8638(power.var_13984)];
                  }
                  break;
               case 4:
                  var moves:Object = movements();
                  var item:ItemType = weaponItem(hero,int(i / moves.length));
                  var move:String = String(moves[i % moves.length]);
                  if(item != null)
                  {
                     return [move,[move + costume.mCostumeName + item.var_12885,move + hero.mHeroName + item.var_12885,
                        move + item.var_12885,move],item];
                  }
            }
         }
         catch(e:Error)
         {
            ErrorLog.write("colour editor: animation " + animLabel(costume) + " not found: " + e);
         }
         return [selected,selected,null];
      }

      private function clearDoll() : void
      {
         if(doll != null)
         {
            doll.clear();
            doll = null;
         }
      }

      private function drawPreview() : void
      {
         dirty = false;
         lastDraw = getTimer();
         clearDoll();
         if(previewScheme == null)
         {
            previewScheme = new class_76();
            previewScheme.mColorSchemeName = "BHColorEditorPreview";
            previewScheme.var_9268 = "M";
         }
         previewScheme.var_10427 = colors();
         var costume:CostumeType = previewCostume();
         if(costume == null || previewHolder == null)
         {
            return;
         }
         var spec:Array = animSpec(costume);
         var names:Array = spec[1] is Array ? spec[1] as Array : [spec[1]];
         doll = LegendDoll.build(previewHolder,costume,previewScheme,spec[0],names,spec[2],10 + (PREVIEW_W - 20) / 2,
            area.height - 84,0.95,"colour editor");
         animPlays = doll != null && doll.anim != null;
         if(doll != null)
         {
            doll.play(names[0]);
         }
         if(previewInfo != null)
         {
            previewInfo.text = String(costume.var_7289.mDisplayName).toUpperCase() + ": " +
               gameText(costume.mDisplayNameKey,costume.mCostumeName) + (animPlays ? "" : "   (" + animLabel(costume) +
               ": not on this skin)") + "\n" + (doc.key != null ? "Saved as \"" + doc.name + "\"" : "Not saved yet");
         }
      }

      override protected function everyFrame() : void
      {
         if(dirty && getTimer() - lastDraw > 120)
         {
            drawPreview();
         }
      }

      private function changed() : void
      {
         dirty = true;
         deleteArmed = null;
         note = doc.key != null ? "Changed: SAVE to keep it." : "";
      }

      private function rowsPanel(caption:String) : Sprite
      {
         colW = 0;
         describeLabel = null;
         var p:Sprite = panel(ROWS_X,area.y,ROWS_W,area.height);
         describe = UiKit.text(p,caption,14,area.height - 42,13,UiKit.GREY,UiKit.MEDIUM,ROWS_W - 28);
         return scroller(p,0,8,ROWS_W,area.height - 52);
      }

      private function columnsPanel() : Array
      {
         var listH:Number = area.height - BAR_H - 6;
         var cols:Array = [];
         for(var k:int = 0; k < 2; k++)
         {
            var p:Sprite = panel(ROWS_X + k * (COL_W + 10),area.y,COL_W,listH);
            cols.push(scroller(p,0,4,COL_W,listH - 8));
         }
         var bar:Sprite = panel(ROWS_X,area.y + area.height - BAR_H,ROWS_W,BAR_H);
         describeLabel = UiKit.text(bar,"",14,4,14,UiKit.WHITE,UiKit.XBOLD);
         describe = UiKit.text(bar,"",14,22,12,UiKit.LIGHT,UiKit.MEDIUM,ROWS_W - 28);
         colW = COL_W;
         return cols;
      }

      private static function splitAt(heights:Array, before:Number, after:Number) : int
      {
         var total:Number = before + after;
         for each(var h:Number in heights)
         {
            total += h;
         }
         var left:Number = before;
         for(var i:int = 0; i < heights.length; i++)
         {
            if(left + heights[i] / 2 > total / 2)
            {
               return i;
            }
            left += heights[i];
         }
         return heights.length;
      }

      private function row(parent:Sprite, label:String, value:String, about:String, change:Function, pick:Function = null,
                           option:Function = null, swatches:Array = null, shown:String = null) : Sprite
      {
         var compact:Boolean = colW > 0;
         var w:Number = compact ? colW - 20 : ROWS_W - 24;
         var h:Number = compact ? 26 : 30;
         var line:Sprite = new Sprite();
         line.x = 10;
         line.y = lastBottom(parent);
         parent.addChild(line);
         UiKit.rect(line,0,0,w,h,UiKit.BODY,6);
         var nameField:TextField = UiKit.fit(UiKit.text(line,compact && shown != null ? shown : label,compact ? 10 : 14,compact ? 4 : 5,
            compact ? 13 : 14,UiKit.WHITE,UiKit.BOLD),w * (compact ? 0.3 : 0.36));
         var leftArrow:Number = compact ? w * 0.5 : w * 0.66;
         var sx:Number = compact ? nameField.x + nameField.width + 8 : w * 0.37;
         var ss:Number = compact ? 14 : 18;
         for each(var c:* in swatches)
         {
            if(compact && sx + ss > leftArrow - 4)
            {
               break;
            }
            UiKit.rect(line,sx,(h - ss) / 2,ss,ss,uint(c),3);
            sx += ss + 3;
         }
         var vx:Number = compact ? (leftArrow + 22 + w - 28) / 2 : w * 0.8;
         var v:TextField = UiKit.text(line,value,vx,compact ? 4 : 5,compact ? 13 : 14,UiKit.TEAL,UiKit.BOLD,0,true);
         UiKit.fit(v,compact ? w - 28 - leftArrow - 30 : w * 0.25);
         v.x = vx - v.width / 2;
         if(change != null)
         {
            UiKit.arrow(line,leftArrow,(h - 22) / 2,-1,function():void
            {
               change(-1);
               build();
            });
            UiKit.arrow(line,w - (compact ? 28 : 30),(h - 22) / 2,1,function():void
            {
               change(1);
               build();
            });
         }
         var index:int = items.length;
         line.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
         {
            focus = index;
            paintFocus();
         });
         items.push({"sprite":line,"parent":parent,"width":w,"height":h,"change":change,"use":pick,"option":option,
            "about":about,"label":label});
         return line;
      }

      private function buttonRow(parent:Sprite, label:String, about:String, act:Function) : void
      {
         var y:Number = lastBottom(parent);
         var holder:Sprite = new Sprite();
         holder.y = y;
         parent.addChild(holder);
         button(holder,label,10,2,220,act,30,14);
         items.push({"sprite":holder,"parent":parent,"width":230,"height":34,"use":act,"about":about,"focusBox":[2,2,4,30],
            "label":label});
      }

      private function heading(parent:Sprite, s:String) : void
      {
         var y:Number = lastBottom(parent);
         var t:TextField = UiKit.text(parent,s,colW > 0 ? 12 : 16,y + (colW > 0 ? 4 : 6),colW > 0 ? 12 : 13,UiKit.GREY,UiKit.XBOLD);
         t.name = "heading";
      }

      private function lastBottom(parent:Sprite) : Number
      {
         var bottom:Number = 0;
         for(var i:int = 0; i < parent.numChildren; i++)
         {
            var c:Object = parent.getChildAt(i);
            bottom = Math.max(bottom,c.y + (c is TextField ? (colW > 0 ? 24 : 28) : (colW > 0 && c.height < 28 ? 29 : 34)));
         }
         return bottom;
      }

      override protected function focused(it:Object) : void
      {
         if(describeLabel != null)
         {
            describeLabel.text = it.label ? String(it.label) : "";
         }
         if(describe != null)
         {
            describeText(describe,it.about ? String(it.about) : "");
         }
      }

      override protected function useItem(it:Object, dir:int) : void
      {
         if(dir == 0 && it.use != null)
         {
            it.use();
         }
         else if(it.change != null)
         {
            it.change(dir == 0 ? 1 : dir);
            build();
         }
      }

      override protected function buildTab(i:int) : void
      {
         switch(i)
         {
            case 0:
               buildColours();
               break;
            case 1:
               buildShades();
               break;
            case 2:
               buildMine();
         }
      }

      private function buildColours() : void
      {
         var cols:Array = columnsPanel();
         var list:Sprite = cols[0];
         heading(list,"SCHEME");
         row(list,"NAME",doc.name,"The name in the colour picker. " + Prompts.KEYS.select + " to type it.",null,function():void
         {
            typeText("SCHEME NAME",doc.name,24,function(text:String):void
            {
               text = text.replace(/^\s+|\s+$/g,"");
               if(text != "")
               {
                  doc.name = text;
                  changed();
               }
               build();
            });
         });
         var bs:Array = bases();
         var base:class_76 = baseScheme(doc.base);
         row(list,"START FROM",base != null ? gameText(base.mDisplayNameKey,base.mColorSchemeName) : doc.base,
            "The game's colour scheme the changes start from (your changes are kept when you switch).",function(dir:int):void
         {
            var at:int = Math.max(0,bs.indexOf(base));
            var next:class_76 = bs[(at + dir + bs.length) % bs.length];
            doc.base = next.mColorSchemeName;
            changed();
         },null,null,base != null ? swatchesOf(base.var_10427,["Hair","Body1","Body2","Special","Cloth","Weapon"]) : null);
         var cost:CostumeType = previewCostume();
         heading(list,"PREVIEW");
         row(list,"PREVIEW LEGEND",cost != null ? String(cost.var_7289.mDisplayName).toUpperCase() : "-",
            "The legend on the left (only the preview: a scheme works with every legend and skin).",function(dir:int):void
         {
            heroIndex += dir;
            skinIndex = 0;
            dirty = true;
         },null,null,null,"LEGEND");
         row(list,"PREVIEW SKIN",cost != null ? gameText(cost.mDisplayNameKey,cost.mCostumeName) : "-",
            "The skin on the left.",function(dir:int):void
         {
            skinIndex += dir;
            dirty = true;
         },null,null,null,"SKIN");
         row(list,"PREVIEW ANIMATION",ANIM_KINDS[animKind],"What the legend on the left does, as the game's Image Render " +
            "Tool shows it: the character select pose, idle, an emote, an attack or a movement.",function(dir:int):void
         {
            animKind = (animKind + dir + ANIM_KINDS.length) % ANIM_KINDS.length;
            animPick = 0;
            dirty = true;
         },null,null,null,"ANIMATION");
         row(list,"PREVIEW PLAYS",animCount() > 0 ? animLabel(cost) : "-","Which emote, attack or movement (with which " +
            "weapon) the legend plays.",function(dir:int):void
         {
            if(animCount() > 0)
            {
               animPick = pickIndex() + dir;
               dirty = true;
            }
         },null,null,null,"PLAYS");
         var all:Array = colors();
         var groups:Array = [];
         for each(var g:Array in GROUPS)
         {
            var present:Boolean = false;
            for each(var nm:String in g[1])
            {
               present = present || slot(nm) >= 0 && uint(all[slot(nm)]) != 0;
            }
            if(present)
            {
               groups.push(g);
            }
         }
         var heights:Array = groups.map(function(... rest):Number
         {
            return 24 + 3 * 29;
         });
         var left:int = splitAt(heights,2 * 24 + 6 * 29,24 + 2 * 34);
         for(var gi:int = 0; gi < groups.length; gi++)
         {
            g = groups[gi];
            list = cols[gi < left ? 0 : 1];
            var label:String = g[0];
            heading(list,label);
            var adj:Array = doc.adjust[label] != null ? doc.adjust[label] : [0,0,0];
            var sw:Array = swatchesOf(all,g[1]);
            var parts:Array = [["HUE",0,10,"Turns every shade of " + label.toLowerCase() + " round the colour wheel."],
               ["SATURATION",1,5,"More or less colourful."],["BRIGHTNESS",2,5,"Lighter or darker."]];
            for each(var part:Array in parts)
            {
               row(list,label + " " + part[0],(adj[part[1]] > 0 ? "+" : "") + adj[part[1]] + (part[1] == 0 ? "" : "%"),
                  part[3] + " " + Prompts.KEYS.option + " resets the group.",adjuster(label,part[1],part[2]),null,
                  groupResetter(label),part[1] == 0 ? sw : null,part[0]);
            }
         }
         list = cols[1];
         heading(list,"");
         buttonRow(list,doc.key != null ? "SAVE CHANGES" : "SAVE",
            "Saves into the mod \"" + MOD_ID + "\" in the game's mods folder; the scheme is in the colour picker at once.",save);
         buttonRow(list,"NEW SCHEME","Starts a new scheme (from the same START FROM).",function():void
         {
            doc = fresh(doc.base);
            note = "New scheme.";
            dirty = true;
            build();
         });
      }

      private static function swatchesOf(cols:Array, names:Array) : Array
      {
         var out:Array = [];
         for each(var n:String in names)
         {
            var i:int = slot(n);
            if(i >= 0 && cols != null && uint(cols[i]) != 0)
            {
               out.push(uint(cols[i]));
            }
         }
         return out;
      }

      private function adjuster(group:String, part:int, step:Number) : Function
      {
         return function(dir:int):void
         {
            var adj:Array = doc.adjust[group] != null ? doc.adjust[group] : [0,0,0];
            var limit:Number = part == 0 ? 180 : 100;
            var v:Number = adj[part] + dir * step;
            if(part == 0)
            {
               v = v > 180 ? v - 360 : (v <= -180 ? v + 360 : v);
            }
            adj[part] = Math.max(-limit,Math.min(limit,v));
            doc.adjust[group] = adj;
            changed();
         };
      }

      private function groupResetter(group:String) : Function
      {
         return function():void
         {
            delete doc.adjust[group];
            changed();
            build();
         };
      }

      private function buildShades() : void
      {
         var cols:Array = columnsPanel();
         var all:Array = colors();
         var base:class_76 = baseScheme(doc.base);
         var groups:Array = [];
         var heights:Array = [];
         for each(var g:Array in GROUPS)
         {
            var names:Array = [];
            for each(var n:String in g[1])
            {
               if(slot(n) >= 0 && (uint(all[slot(n)]) != 0 || doc.shades[n] != null))
               {
                  names.push(n);
               }
            }
            if(names.length > 0)
            {
               groups.push([g[0],names]);
               heights.push(24 + names.length * 29);
            }
         }
         var left:int = splitAt(heights,0,0);
         for(var gi:int = 0; gi < groups.length; gi++)
         {
            g = groups[gi];
            var list:Sprite = cols[gi < left ? 0 : 1];
            heading(list,g[0]);
            for each(var name:String in g[1])
            {
               var i:int = slot(name);
               var own:Boolean = doc.shades[name] != null;
               var shade:String = name.replace(/^(Hair|Body1|Body2|Special|Cloth|Weapon|Hands)/,"");
               var label:String = g[0] + " " + (shade == "" ? "" : (SHADE_NAMES[shade] != null ? SHADE_NAMES[shade] : shade).toUpperCase());
               row(list,label.replace(/\s+$/,""),"#" + hex(uint(all[i])) + (own ? " *" : ""),
                  "Left/right: lighter or darker. " + Prompts.KEYS.select + ": type the colour (RRGGBB). " +
                  Prompts.KEYS.option + ": back to the group's colour." + (own ? " (* set here)" : ""),
                  shadeChanger(name),shadeTyper(name),shadeResetter(name),
                  [base != null && base.var_10427 != null ? uint(base.var_10427[i]) : 0,uint(all[i])],
                  shade == "" ? "BASE" : (SHADE_NAMES[shade] != null ? SHADE_NAMES[shade] : shade).toUpperCase());
            }
         }
      }

      private function shadeChanger(name:String) : Function
      {
         return function(dir:int):void
         {
            doc.shades[name] = shift(colorOf(name),0,0,dir * 4);
            changed();
         };
      }

      private function shadeTyper(name:String) : Function
      {
         return function():void
         {
            typeText(name.toUpperCase() + " (RRGGBB)",hex(colorOf(name)),6,function(text:String):void
            {
               text = text.replace(/^#/,"").toUpperCase();
               if(/^[0-9A-F]{6}$/.test(text))
               {
                  doc.shades[name] = parseInt(text,16);
                  changed();
               }
               else
               {
                  note = "\"" + text + "\" isn't a colour: 6 characters of 0-9 and A-F, like 37BEAE.";
               }
               build();
            });
         };
      }

      private function shadeResetter(name:String) : Function
      {
         return function():void
         {
            delete doc.shades[name];
            changed();
            build();
         };
      }

      private function buildMine() : void
      {
         var list:Sprite = rowsPanel("");
         row(list,"IMPORT XML","",Prompts.KEYS.select + ": pick an .xml file with one ColorSchemeType or a whole " +
            "ColorSchemeTypes list. Each scheme in it is added as a new one of yours (the game's own stay as they are).",
            null,importPicker);
         var saved:Array = readEditorFile().schemes;
         if(saved.length == 0)
         {
            UiKit.text(list,"Nothing saved yet. Make a scheme in COLOURS and SAVE it, or IMPORT XML.",16,48,14,UiKit.GREY,
               UiKit.BOLD);
            return;
         }
         for each(var s:Object in saved)
         {
            var live:class_76 = class_76.method_4680(s.key);
            row(list,String(s.name).toUpperCase(),s.key == doc.key ? "EDITING" : (deleteArmed == s.key ? "DELETE?" : ""),
               Prompts.KEYS.select + ": edit it. " + Prompts.KEYS.option + " twice: delete it.",null,
               opener(s),deleter(s),live != null ? swatchesOf(live.var_10427,["Hair","Body1","Body2","Special","Cloth","Weapon"]) : null);
         }
      }

      private function opener(s:Object) : Function
      {
         return function():void
         {
            doc = {"key":s.key,"name":s.name,"base":s.base,"adjust":copy(s.adjust),"shades":copy(s.shades)};
            note = "Editing \"" + s.name + "\".";
            dirty = true;
            showTab(0);
         };
      }

      private function deleter(s:Object) : Function
      {
         return function():void
         {
            if(deleteArmed != s.key)
            {
               deleteArmed = s.key;
               note = "Press again to delete \"" + s.name + "\".";
               build();
               return;
            }
            deleteArmed = null;
            remove(s.key);
            build();
         };
      }

      private function importPicker() : void
      {
         try
         {
            var f:File = File.documentsDirectory;
            f.addEventListener(Event.SELECT,function(e:Event):void
            {
               try
               {
                  var st:FileStream = new FileStream();
                  st.open(f,FileMode.READ);
                  var text:String = st.readUTFBytes(st.bytesAvailable);
                  st.close();
                  note = importXml(text,f.name);
               }
               catch(err:Error)
               {
                  note = "Couldn't read " + f.name + ": " + err.message;
               }
               dirty = true;
               build();
            });
            f.browseForOpen("A colour scheme (ColorSchemeType XML)",[new FileFilter("Colour schemes (*.xml)","*.xml"),
               new FileFilter("All files","*.*")]);
         }
         catch(e:Error)
         {
            note = "Couldn't open the file dialog: " + e.message;
            build();
         }
      }

      public function importXml(text:String, from:String) : String
      {
         var rows:Array = [];
         var root:XML;
         try
         {
            root = new XML("<import>" + text.replace(/<\?xml[^>]*\?>/g,"") + "</import>");
         }
         catch(e:Error)
         {
            return from + " isn't XML this can read: " + e.message;
         }
         for each(var x:XML in root..ColorSchemeType)
         {
            rows.push(x);
         }
         if(rows.length == 0)
         {
            return "No ColorSchemeType in " + from + ".";
         }
         var known:Object = {};
         for each(var g:Array in GROUPS)
         {
            for each(var n:String in g[1])
            {
               known[n] = true;
            }
         }
         var data:Object = readEditorFile();
         var keys:Array = [];
         var seen:Object = {};
         for each(var old:Object in data.schemes)
         {
            keys.push(old.key);
            seen[old.name + "|" + colorsKey(old.colors)] = true;
         }
         var added:Array = [];
         var skipped:int = 0;
         var full:Boolean = false;
         for each(x in rows)
         {
            var cols:Object = {};
            var count:int = 0;
            for each(var child:XML in x.children())
            {
               var m:Object = /^(\w+)_Swap$/.exec(String(child.localName()));
               var hexText:Object = /^\s*(?:0x|#)?([0-9A-Fa-f]{6})\s*$/.exec(String(child.text()));
               if(m != null && known[m[1]] && hexText != null)
               {
                  cols[m[1]] = parseInt(hexText[1],16);
                  count++;
               }
            }
            var label:String = String(x.DisplayNameKey).replace(/^\s+|\s+$/g,"");
            if(label == "" || label.indexOf(" ") < 0 && /_DisplayName$|^Must be/.test(label))
            {
               label = String(x.@ColorSchemeName);
            }
            label = label.replace(/[<>&"]/g,"").substr(0,30);
            var same:String = label + "|" + colorsKey(cols);
            if(count == 0 || label == "" || seen[same])
            {
               skipped++;
               continue;
            }
            if(nextId() < 0)
            {
               full = true;
               break;
            }
            var entry:Object = {"key":newKey(label,keys),"name":label,"base":"Blue","adjust":{},"shades":copy(cols),
               "colors":cols};
            keys.push(entry.key);
            data.schemes.push(entry);
            writeMod(data);
            register(entry);
            seen[same] = true;
            added.push(label);
         }
         Platform.log("colour editor: imported " + added.length + " scheme(s) from " + from + " (" + skipped + " skipped)");
         var out:String = added.length == 0 ? "Nothing new in " + from :
            "Imported " + (added.length == 1 ? "\"" + added[0] + "\"" : added.length + " schemes") + ": in the colour picker now";
         if(skipped > 0)
         {
            out += " (" + skipped + " skipped: no colours, or already yours)";
         }
         if(full)
         {
            out += ". No colour IDs left (the game allows IDs below 160): delete a scheme first";
         }
         return out + ".";
      }

      private static function colorsKey(colors:Object) : String
      {
         var parts:Array = [];
         for(var k:String in colors)
         {
            parts.push(k + "=" + uint(colors[k]));
         }
         parts.sort();
         return parts.join(",");
      }

      private static function copy(o:Object) : Object
      {
         return o != null ? JSON.parse(JSON.stringify(o)) : {};
      }

      override protected function optionItem(it:Object) : void
      {
         if(it.option != null)
         {
            it.option();
         }
      }

      private static function modFolder() : File
      {
         return new File(File.applicationDirectory.resolvePath(ContentMods.FOLDER).nativePath).resolvePath(MOD_ID);
      }

      private static function readEditorFile() : Object
      {
         try
         {
            var f:File = modFolder().resolvePath("editor.json");
            if(f.exists)
            {
               var st:FileStream = new FileStream();
               st.open(f,FileMode.READ);
               var text:String = st.readUTFBytes(st.bytesAvailable);
               st.close();
               var data:Object = JSON.parse(text);
               if(data != null && data.schemes is Array)
               {
                  return data;
               }
            }
         }
         catch(e:Error)
         {
            ErrorLog.write("colour editor: editor.json unreadable: " + e);
         }
         return {"schemes":[]};
      }

      private static function writeText(f:File, text:String) : void
      {
         var st:FileStream = new FileStream();
         st.open(f,FileMode.WRITE);
         st.writeUTFBytes(text);
         st.close();
      }

      private static function writeMod(data:Object) : void
      {
         var dir:File = modFolder();
         if(data.schemes.length == 0)
         {
            if(dir.exists)
            {
               dir.deleteDirectory(true);
            }
            return;
         }
         if(!dir.exists)
         {
            dir.createDirectory();
         }
         writeText(dir.resolvePath("editor.json"),JSON.stringify(data,null,2));
         var rows:Array = [];
         var names:Object = {};
         for each(var s:Object in data.schemes)
         {
            rows.push(rowXml(s,"@id","@id"));
            names[nameKey(s.key)] = s.name;
         }
         var strings:Object = {"English":names};
         try
         {
            var lang:String = Localization.var_14676.var_14508;
            if(lang != null && lang != "English")
            {
               strings[lang] = names;
            }
         }
         catch(e:Error)
         {
         }
         var mod:Object = {"id":MOD_ID,"name":"My colour schemes","version":"1.0","author":"Colour editor",
            "description":"Colour schemes made in the game's colour editor (Mods > COLOUR EDITOR).","strings":strings,
            "tables":{"ColorSchemeTypes":rows}};
         writeText(dir.resolvePath("mod.json"),JSON.stringify(mod,null,2));
      }

      private static function nameKey(key:String) : String
      {
         return "BH_MyColors_" + key;
      }

      private static function rowXml(s:Object, id:String, order:String) : String
      {
         var base:class_76 = baseScheme(s.base);
         var x:String = "<ColorSchemeType ColorSchemeName=\"" + s.key + "\"><ColorSchemeID>" + id + "</ColorSchemeID>" +
            "<DefaultUnlocked>FALSE</DefaultUnlocked><DisplayNameKey>" + nameKey(s.key) + "</DisplayNameKey>" +
            "<IconName>" + (base != null && base.var_2697 != null ? base.var_2697 : "a_ColorIcon_Blue") + "</IconName>" +
            "<IconFileName>" + (base != null && base.var_11984 != null ? base.var_11984 : "UI_Icons") + "</IconFileName>" +
            "<OrderID>" + order + "</OrderID><Rarity>M</Rarity><TeamColor>0</TeamColor><BroadcasterEnabled>false</BroadcasterEnabled>";
         var team:Array = teamLinks(uint(s.colors["Body1"] != null ? s.colors["Body1"] : 0));
         if(team[0] != null)
         {
            x += "<ExcludeOpponentTeamColor>" + team[0] + "</ExcludeOpponentTeamColor>";
         }
         x += "<FallbackOpponentTeamColor>" + team[1] + "</FallbackOpponentTeamColor>";
         x += "<IndicatorColor>0x" + hex(uint(s.colors["Body1"] != null ? s.colors["Body1"] : 0xFFFFFF)) + "</IndicatorColor>";
         for(var name:String in s.colors)
         {
            x += "<" + name + "_Swap>0x" + hex(uint(s.colors[name])) + "</" + name + "_Swap>";
         }
         return x + "</ColorSchemeType>";
      }

      public static function teamLinks(body:uint) : Array
      {
         var hsv:Array = toHsv(body);
         if(hsv[1] < 0.25 || hsv[2] < 0.2)
         {
            return [null,"TeamRed1"];
         }
         if(hsv[0] < 25 || hsv[0] >= 330)
         {
            return ["TeamRed1","TeamBlue1"];
         }
         if(hsv[0] >= 170 && hsv[0] < 250)
         {
            return ["TeamBlue1","TeamRed1"];
         }
         return [null,"TeamRed1"];
      }

      private function namedColors() : Object
      {
         var all:Array = colors();
         var out:Object = {};
         for each(var g:Array in GROUPS)
         {
            for each(var name:String in g[1])
            {
               var i:int = slot(name);
               if(i >= 0 && uint(all[i]) != 0)
               {
                  out[name] = uint(all[i]);
               }
            }
         }
         return out;
      }

      private static function newKey(name:String, taken:Array) : String
      {
         var stem:String = "BHMyColor_" + name.replace(/[^A-Za-z0-9]/g,"");
         var key:String = stem;
         for(var n:int = 2; taken.indexOf(key) >= 0 || class_76.method_4680(key) != null; n++)
         {
            key = stem + n;
         }
         return key;
      }

      private function save() : void
      {
         try
         {
            var data:Object = readEditorFile();
            var keys:Array = [];
            var entry:Object = null;
            for each(var s:Object in data.schemes)
            {
               keys.push(s.key);
               if(s.key == doc.key)
               {
                  entry = s;
               }
            }
            if(entry == null)
            {
               var free:int = nextId();
               if(free < 0)
               {
                  note = "No colour IDs left (the game allows IDs below 160): delete a scheme first.";
                  build();
                  return;
               }
               entry = {"key":newKey(doc.name,keys)};
               data.schemes.push(entry);
            }
            doc.key = entry.key;
            entry.name = doc.name;
            entry.base = doc.base;
            entry.adjust = copy(doc.adjust);
            entry.shades = copy(doc.shades);
            entry.colors = namedColors();
            writeMod(data);
            register(entry);
            note = "Saved \"" + doc.name + "\": in the colour picker now.";
            Platform.log("colour editor: saved " + entry.key + " (" + doc.name + ")");
         }
         catch(e:Error)
         {
            note = "Not saved: " + e.message;
            ErrorLog.write("colour editor: save failed: " + e + " " + e.getStackTrace());
         }
         dirty = true;
         build();
      }

      private static function nextId() : int
      {
         var top:int = 0;
         for each(var s:class_76 in class_76.var_3762)
         {
            top = Math.max(top,s.var_9518);
         }
         return top + 1 < 160 ? top + 1 : -1;
      }

      private static function register(entry:Object) : void
      {
         var lang:Object = Localization.var_14676;
         if(lang != null)
         {
            lang.var_15061.method_65(nameKey(entry.key),entry.name);
         }
         var live:class_76 = class_76.method_4680(entry.key);
         if(live == null)
         {
            var order:int = 0;
            for each(var s:class_76 in class_76.var_3762)
            {
               order = Math.max(order,s.var_14291);
            }
            class_76.method_8601(Xml.parse(rowXml(entry,String(nextId()),String(order + 1))).method_7292());
            live = class_76.method_4680(entry.key);
            if(live == null)
            {
               throw new Error("the game refused the row");
            }
            live.var_6656 = class_76.method_4680(live.var_10292);
            if(live.var_6656 == null)
            {
               live.var_6656 = class_76.var_11546;
            }
            if(live.var_3898 != null)
            {
               live.var_8795 = [];
               for each(var other:String in live.var_3898.split(","))
               {
                  var o:class_76 = class_76.method_4680(other);
                  if(o != null)
                  {
                     class_50.method_5679(live.var_8795,o.var_9518);
                  }
               }
            }
            class_76.var_1809.sort(class_76.method_4693);
            if(ContentMods.added["ColorSchemeTypes"] == null)
            {
               ContentMods.added["ColorSchemeTypes"] = {};
            }
            ContentMods.added["ColorSchemeTypes"][entry.key] = MOD_ID;
         }
         else
         {
            var cols:Array = [];
            for(var name:String in entry.colors)
            {
               var i:int = slot(name);
               if(i >= 0)
               {
                  cols[i] = uint(entry.colors[name]);
               }
            }
            live.var_10427 = cols;
            live.var_14932 = uint(entry.colors["Body1"] != null ? entry.colors["Body1"] : 0xFFFFFF);
            if(class_76.var_1809.indexOf(live) < 0)
            {
               class_76.var_1809.push(live);
               class_76.var_1809.sort(class_76.method_4693);
            }
         }
      }

      private function remove(key:String) : void
      {
         try
         {
            var data:Object = readEditorFile();
            var kept:Array = [];
            var name:String = key;
            for each(var s:Object in data.schemes)
            {
               if(s.key != key)
               {
                  kept.push(s);
               }
               else
               {
                  name = s.name;
               }
            }
            data.schemes = kept;
            writeMod(data);
            var live:class_76 = class_76.method_4680(key);
            if(live != null && class_76.var_1809.indexOf(live) >= 0)
            {
               class_76.var_1809.splice(class_76.var_1809.indexOf(live),1);
            }
            if(doc.key == key)
            {
               doc.key = null;
            }
            note = "Deleted \"" + name + "\" (gone from the picker; the mod drops it at the next start).";
         }
         catch(e:Error)
         {
            note = "Not deleted: " + e.message;
         }
      }

      override public function OnDestroyScreen() : void
      {
         clearDoll();
         super.OnDestroyScreen();
      }
   }
}
