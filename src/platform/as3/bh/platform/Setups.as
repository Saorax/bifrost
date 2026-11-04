package bh.platform
{
   import flash.display.DisplayObject;
   import flash.display.Sprite;
   import flash.events.MouseEvent;
   import flash.geom.Point;
   import flash.geom.Rectangle;
   import flash.text.TextField;
   import flash.utils.ByteArray;
   import flash.utils.getDefinitionByName;

   public final class Setups
   {
      public static const KEY:String = "legendSetups";

      private static const ROW:Number = 30;
      private static const WIDTH:Number = 170;
      private static const VISIBLE:int = 8;

      private static var screen:Object = null;
      private static var slots:Object = {};
      private static var panels:Object = {};
      private static var started:Boolean = false;
      private static var inputDevice:int = -1;

      public static function get charSelect() : Object
      {
         return screen;
      }

      public static function init() : void
      {
         if(started)
         {
            return;
         }
         started = true;
         Hooks.frameStarting.add(tick);
      }

      private static function all() : Object
      {
         var v:* = ModSettings.value(KEY);
         return v != null && typeof v == "object" ? v : {};
      }

      public static function forLegend(legend:String) : Array
      {
         var list:* = legend != null ? all()[legend] : null;
         return list is Array ? list as Array : [];
      }

      public static function storeList(legend:String, list:Array) : void
      {
         var data:Object = all();
         if(list.length == 0)
         {
            delete data[legend];
         }
         else
         {
            data[legend] = list;
         }
         ModSettings.setValue(KEY,data);
      }

      private static function legendName(player:Object) : String
      {
         var hero:Object = player != null && player.var_5540 != null ? player.var_5540.var_13881 : null;
         return hero != null ? String(hero.mHeroName) : null;
      }

      public static function capture(player:Object) : Object
      {
         var w1:Object = player.method_5489(true);
         var w2:Object = player.method_5489(false);
         var sidekick:Object = getClass("class_574").var_14155[player.var_12740];
         var companion:Object = player.var_5378 == 0 ? null : getClass("CompanionType").var_9851.method_4935(player.var_5378);
         var emitter:Object = getClass("class_118").var_13975[player.var_12121];
         return {
            "skin":player.var_2483 != null ? player.var_2483.mCostumeName : null,
            "colour":player.var_13724 != null ? player.var_13724.mColorSchemeName : null,
            "weapon1":w1 != null ? w1.mWeaponSkinName : null,
            "weapon2":w2 != null ? w2.mWeaponSkinName : null,
            "sidekick":sidekick != null ? sidekick.mSpawnBotName : null,
            "companion":companion != null ? companion.var_3857 : "",
            "emitter":emitter != null ? emitter.var_2065 : null,
            "stance":uint(player.var_5158)
         };
      }

      public static function delta(from:int, to:int, n:int) : int
      {
         if(from < 0 || to < 0 || n <= 0 || from == to)
         {
            return 0;
         }
         var fwd:int = (to - from + n) % n;
         return fwd <= n - fwd ? fwd : fwd - n;
      }

      public static function indexBy(list:Object, test:Function) : int
      {
         for(var i:int = 0; list != null && i < int(list.length); i++)
         {
            if(test(list[i]))
            {
               return i;
            }
         }
         return -1;
      }

      public static function step(podium:Object, slot:uint, player:Object, category:int, k:int) : void
      {
         if(k == 0)
         {
            return;
         }
         podium.var_7434 = category;
         podium.var_14899 = 0;
         podium.method_7373(player,slot,k,true);
      }

      public static function apply(podium:Object, slot:uint, player:Object, s:Object) : void
      {
         var owner:Object = podium.owner;
         var data:Object = owner.var_8329;
         if(s.skin != null)
         {
            var skins:Object = data.method_6632(player.var_5540,owner.var_6244.var_2390);
            step(podium,slot,player,0,delta(indexBy(skins,function(c:Object):Boolean { return c == player.var_2483; }),
               indexBy(skins,function(c:Object):Boolean { return c.mCostumeName == s.skin; }),int(skins.length)));
         }
         if(s.colour != null && player.var_13724 != null && player.var_13724.mColorSchemeName != s.colour)
         {
            var c0:Object = player.var_13724;
            var c:Object = c0;
            for(var n:int = 1; n <= 400; n++)
            {
               c = owner.var_6244.method_1771(slot,player.var_2483,c,1,podium.var_5670);
               if(c == null || c == c0)
               {
                  break;
               }
               if(c.mColorSchemeName == s.colour)
               {
                  step(podium,slot,player,1,n);
                  break;
               }
            }
         }
         if(!podium.var_12638)
         {
            weapon(podium,slot,player,true,s.weapon1);
            weapon(podium,slot,player,false,s.weapon2);
         }
         if(s.sidekick != null)
         {
            var bots:Object = data.method_7796();
            var botType:Object = getClass("class_574").var_14155;
            step(podium,slot,player,4,delta(indexBy(bots,function(id:uint):Boolean { return id == player.var_12740; }),
               indexBy(bots,function(id:uint):Boolean { return botType[id] != null && botType[id].mSpawnBotName == s.sidekick; }),
               int(bots.length)));
         }
         if(s.companion != null)
         {
            var comps:Object = data.method_225(player.var_2483,player);
            var compType:Object = getClass("CompanionType").var_9851;
            var count:int = int(comps.length) + 1;
            var cur:int = player.var_5378 == 0 ? count - 1 : indexBy(comps,function(id:uint):Boolean { return id == player.var_5378; });
            var want:int = s.companion == "" ? count - 1 : indexBy(comps,function(id:uint):Boolean
            {
               var t:Object = compType.method_4935(id);
               return t != null && t.var_3857 == s.companion;
            });
            step(podium,slot,player,5,delta(cur,want,count));
         }
         if(s.emitter != null)
         {
            var ems:Object = data.method_6850();
            var emType:Object = getClass("class_118").var_13975;
            step(podium,slot,player,6,delta(indexBy(ems,function(id:uint):Boolean { return id == player.var_12121; }),
               indexBy(ems,function(id:uint):Boolean { return emType[id] != null && emType[id].var_2065 == s.emitter; }),
               int(ems.length)));
         }
         for(var i:int = 0; s.stance != null && i < 12 && uint(player.var_5158) != uint(s.stance); i++)
         {
            step(podium,slot,player,7,1);
         }
         podium.var_7434 = 0;
         podium.method_853(player,slot,false);
      }

      private static function weapon(podium:Object, slot:uint, player:Object, first:Boolean, name:String) : void
      {
         var list:Object = first ? podium.mUsableWeapon1Skins : podium.mUsableWeapon2Skins;
         if(name == null || list == null)
         {
            return;
         }
         var cur:Object = player.method_5489(first);
         step(podium,slot,player,first ? 2 : 3,delta(indexBy(list,function(w:Object):Boolean { return w == cur; }),
            indexBy(list,function(w:Object):Boolean { return w != null && w.mWeaponSkinName == name; }),int(list.length)));
      }

      private static const CODE_PREFIX:String = "BHSETUP1:";
      private static const B64:String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

      public static function code(player:Object, name:String) : String
      {
         var s:Object = capture(player);
         s.legend = legendName(player);
         s.name = name;
         var bytes:ByteArray = new ByteArray();
         bytes.writeUTFBytes(JSON.stringify(s));
         var size:int = int(bytes.length);
         var out:String = "";
         for(var i:int = 0; i < size; i += 3)
         {
            var a:int = int(bytes[i]);
            var b:int = i + 1 < size ? int(bytes[i + 1]) : 0;
            var c:int = i + 2 < size ? int(bytes[i + 2]) : 0;
            var n:int = a << 16 | b << 8 | c;
            out += B64.charAt(n >> 18 & 63) + B64.charAt(n >> 12 & 63);
            if(i + 1 < size)
            {
               out += B64.charAt(n >> 6 & 63);
            }
            if(i + 2 < size)
            {
               out += B64.charAt(n & 63);
            }
         }
         return CODE_PREFIX + out;
      }

      public static function decode(text:String) : Object
      {
         if(text == null)
         {
            return null;
         }
         text = text.replace(/\s+/g,"");
         var at:int = text.indexOf(CODE_PREFIX);
         if(at < 0)
         {
            return null;
         }
         text = text.substr(at + CODE_PREFIX.length);
         var bytes:ByteArray = new ByteArray();
         var bits:int = 0;
         var held:int = 0;
         for(var i:int = 0; i < text.length; i++)
         {
            var v:int = B64.indexOf(text.charAt(i));
            if(v < 0)
            {
               return null;
            }
            held = (held << 6 | v) & 0xFFFF;
            bits += 6;
            if(bits >= 8)
            {
               bits -= 8;
               bytes.writeByte(held >> bits & 255);
            }
         }
         try
         {
            bytes.position = 0;
            var s:Object = JSON.parse(bytes.readUTFBytes(int(bytes.length)));
            return s != null && s.legend is String ? s : null;
         }
         catch(e:Error)
         {
         }
         return null;
      }

      public static function importCode(text:String) : Object
      {
         var s:Object = decode(text);
         if(s == null)
         {
            return null;
         }
         var legend:String = String(s.legend);
         delete s.legend;
         var list:Array = forLegend(legend);
         s.name = s.name is String && String(s.name) != "" ? String(s.name).substr(0,24) : "SETUP " + (list.length + 1);
         list.push(s);
         storeList(legend,list);
         return {"legend":legend,"name":s.name};
      }

      public static function saveNew(player:Object) : void
      {
         var legend:String = legendName(player);
         var list:Array = forLegend(legend);
         var s:Object = capture(player);
         s.name = "SETUP " + (list.length + 1);
         list.push(s);
         storeList(legend,list);
      }

      private static function state(slot:int) : Object
      {
         if(slots[slot] == null)
         {
            slots[slot] = {"focus":false,"pick":0,"last":-1,"legend":null};
         }
         return slots[slot];
      }

      private static function entries(st:Object, list:Array) : Array
      {
         var out:Array = [{"kind":"window"}];
         for(var i:int = 0; i < list.length; i++)
         {
            out.push({"kind":"setup","i":i});
         }
         out.push({"kind":"save"});
         if(st.last >= 0 && st.last < list.length)
         {
            out.push({"kind":"delete","i":st.last});
         }
         return out;
      }

      private static function topCategory(podium:Object, slot:int) : int
      {
         var was:uint = podium.var_7434;
         var top:int = 0;
         try
         {
            for(var c:int = 0; c < 8; c++)
            {
               podium.var_7434 = c;
               if(!podium.method_7977(slot))
               {
                  top = c;
                  break;
               }
            }
         }
         finally
         {
            podium.var_7434 = was;
         }
         return top;
      }

      private static function deviceOf(player:Object) : Object
      {
         var at:int = player.method_5111() ? int(player.var_4125) : -1;
         var devs:Array = class_112.var_5048;
         return at >= 0 && devs != null && at < devs.length ? devs[at] : null;
      }

      private static function context(slot:int) : Object
      {
         if(screen == null || slot < 0)
         {
            return null;
         }
         var owner:Object = screen.owner;
         var podium:Object = screen.method_8904(slot);
         var player:Object = podium != null ? owner.var_6244.method_8549(slot) : null;
         if(player == null || !podium.var_5326)
         {
            return null;
         }
         var st:Object = state(slot);
         var legend:String = legendName(player);
         if(st.legend != legend)
         {
            st.legend = legend;
            st.last = -1;
            st.pick = 0;
            st.focus = false;
            st.main = null;
         }
         return {"podium":podium,"player":player,"legend":legend,"st":st,"list":forLegend(legend),"device":deviceOf(player)};
      }

      private static function act(slot:int, x:Object, index:int, confirm:Boolean) : void
      {
         var st:Object = x.st;
         var list:Array = x.list;
         var es:Array = entries(st,list);
         if(index < 0 || index >= es.length)
         {
            return;
         }
         st.pick = index;
         var e:Object = es[index];
         if(e.kind == "setup")
         {
            if(st.last < 0)
            {
               st.main = capture(x.player);
            }
            apply(x.podium,slot,x.player,list[e.i]);
            screen.method_3789();
            st.last = e.i;
         }
         else if(e.kind == "window" && confirm)
         {
            st.focus = false;
            LoadoutWindow.open(screen,slot,inputDevice);
         }
         else if(e.kind == "save" && confirm)
         {
            saveNew(x.player);
            st.last = forLegend(x.legend).length - 1;
            st.pick = st.last + 1;
         }
         else if(e.kind == "delete" && confirm)
         {
            list.splice(e.i,1);
            storeList(x.legend,list);
            st.last = -1;
            st.pick = Math.min(e.i + 1,list.length + 1);
         }
      }

      private static function cycle(slot:int, x:Object, dir:int) : void
      {
         var st:Object = x.st;
         var list:Array = x.list;
         if(list.length == 0)
         {
            return;
         }
         var at:int = st.last >= 0 && st.last < list.length ? st.last : -1;
         var to:int = (at + 1 + dir + list.length + 1) % (list.length + 1) - 1;
         if(to < 0)
         {
            if(st.main != null)
            {
               apply(x.podium,slot,x.player,st.main);
               screen.method_3789();
            }
            st.last = -1;
            st.pick = 0;
            return;
         }
         act(slot,x,to + 1,false);
      }

      public static function input(cs:Object, input:int, device:uint) : Boolean
      {
         init();
         screen = cs;
         inputDevice = int(device);
         try
         {
            var owner:Object = cs.owner;
            var slot:int = owner.var_6244.method_4034(owner.var_14656,device,true);
            var x:Object = context(slot);
            if(x == null)
            {
               if(slot >= 0)
               {
                  state(slot).focus = false;
               }
               return false;
            }
            var st:Object = x.st;
            if((input == 26 || input == 27) && x.legend != null)
            {
               cycle(slot,x,input == 27 ? 1 : -1);
               return true;
            }
            if(!st.focus)
            {
               if(input == 4 && int(x.podium.var_7434) == topCategory(x.podium,slot) && x.legend != null)
               {
                  st.focus = true;
                  st.pick = st.last >= 0 ? st.last + 1 : 0;
                  return true;
               }
               return false;
            }
            var es:Array = entries(st,x.list);
            switch(input)
            {
               case 4:
               case 5:
                  var to:int = st.pick + (input == 4 ? -1 : 1);
                  if(to >= 0 && to < es.length)
                  {
                     act(slot,x,to,false);
                  }
                  return true;
               case 1:
                  return true;
               case 2:
                  st.focus = false;
                  return true;
               case 17:
               case 23:
                  var e:Object = es[Math.min(st.pick,es.length - 1)];
                  if(e.kind == "setup")
                  {
                     st.focus = false;
                  }
                  else
                  {
                     act(slot,x,st.pick,true);
                  }
                  return true;
               case 18:
                  st.focus = false;
                  return true;
            }
            return false;
         }
         catch(err:Error)
         {
            ErrorLog.write("setups: " + err + " " + err.getStackTrace());
         }
         return false;
      }

      private static function tick() : void
      {
         if(screen == null)
         {
            return;
         }
         try
         {
            var slot:int;
            var parent:Object = screen.panelClip;
            if(parent == null || parent.stage == null)
            {
               if(!idle)
               {
                  for(slot = 0; slot < 4; slot++)
                  {
                     state(slot).focus = false;
                     hide(slot);
                  }
                  idle = true;
               }
               return;
            }
            idle = false;
            for(slot = 0; slot < 4; slot++)
            {
               draw(slot);
            }
         }
         catch(err:Error)
         {
            ErrorLog.write("setups draw: " + err);
            screen = null;
         }
      }

      private static var idle:Boolean = false;

      private static function hide(slot:int) : void
      {
         var p:Object = panels[slot];
         if(p != null && p.sprite.parent != null)
         {
            p.sprite.parent.removeChild(p.sprite);
         }
         if(p != null && p.tag != null)
         {
            Prompts.clear(ScreenBase(screen),p.tag);
            p.tag = null;
            p.key = null;
         }
      }

      private static function podiumLeftOf(slot:int, x:Number, parent:Sprite) : Boolean
      {
         for(var i:int = 0; i < 8; i++)
         {
            if(i == slot)
            {
               continue;
            }
            var other:Object = screen.method_8904(i);
            var wheel:Object = other != null && other.var_5326 ? other.var_11917 : null;
            if(wheel == null || wheel.var_11879 == null || wheel.var_11879[0] == null)
            {
               continue;
            }
            var clip:DisplayObject = wheel.var_11879[0].clip as DisplayObject;
            if(clip != null && clip.stage != null && clip.getBounds(parent).x < x - 20)
            {
               return true;
            }
         }
         return false;
      }

      private static function draw(slot:int) : void
      {
         var x:Object = context(slot);
         var wheel:Object = x != null ? x.podium.var_11917 : null;
         var parent:Sprite = screen.panelClip as Sprite;
         if(x == null || wheel == null || wheel.var_11879 == null || wheel.var_11879[0] == null || parent == null ||
            parent.stage == null || x.legend == null)
         {
            if(slot >= 0)
            {
               state(slot).focus = false;
            }
            hide(slot);
            return;
         }
         var st:Object = x.st;
         if(int(x.podium.var_7434) != topCategory(x.podium,slot))
         {
            st.focus = false;
         }
         var list:Array = x.list;
         var es:Array = entries(st,list);
         var p:Object = panels[slot];
         if(p == null)
         {
            p = panels[slot] = {"sprite":new Sprite(),"key":null};
         }
         if(p.sprite.parent != parent || parent.getChildIndex(p.sprite) != parent.numChildren - 1)
         {
            parent.addChild(p.sprite);
         }
         var top:Rectangle = DisplayObject(wheel.var_11879[0].clip).getBounds(parent);
         var minX:Number = parent.globalToLocal(new Point(6,0)).x;
         var shown:int = Math.min(VISIBLE,es.length);
         var left:Boolean = podiumLeftOf(slot,top.x,parent);
         var w:Number = left ? WIDTH : Math.floor(Math.max(110,Math.min(WIDTH,top.x - 12 - minX)));
         var tagLine:Boolean = list.length > 0 && w < 230;
         var head:Number = tagLine ? 50 : 30;
         var h:Number = head + shown * ROW + 8;
         if(left)
         {
            p.sprite.x = top.x - 6;
            p.sprite.y = top.y - 34 - h;
         }
         else
         {
            p.sprite.x = top.x - w - 12;
            p.sprite.y = top.y - 4;
         }
         var names:Array = [];
         for each(var s:Object in list)
         {
            names.push(s.name);
         }
         var tabs:String = list.length > 0 ? BigWindow.buttonNames().tabs : "";
         var key:String = w + "|" + st.focus + "|" + st.pick + "|" + st.last + "|" + names.join(",") + "|" + tabs;
         if(p.key == key)
         {
            return;
         }
         p.key = key;
         var sp:Sprite = p.sprite;
         if(p.tag != null)
         {
            Prompts.clear(ScreenBase(screen),p.tag);
            p.tag = null;
         }
         sp.removeChildren();
         var first:int = Math.max(0,Math.min(st.pick - VISIBLE + 2,es.length - VISIBLE));
         UiKit.rect(sp,0,0,w,h,st.focus ? UiKit.TEAL : UiKit.LINE,8);
         UiKit.rect(sp,2,2,w - 4,h - 4,UiKit.BODY,8);
         UiKit.text(sp,"SETUPS" + (st.focus ? "" : "  ▲"),12,6,13,st.focus ? UiKit.TEAL : UiKit.GREY,UiKit.XBOLD);
         if(tabs != "")
         {
            var on0:String = st.last >= 0 && st.last < list.length ? String(list[st.last].name) : "MAIN";
            var name0:TextField = UiKit.text(sp,on0,w - 10,tagLine ? 29 : 8,10,UiKit.GREY,UiKit.BOLD);
            UiKit.fit(name0,tagLine ? w - 70 : w - 130);
            name0.x = w - 10 - name0.width;
            p.tag = new Sprite();
            p.tag.y = tagLine ? 26 : 5;
            sp.addChild(p.tag);
            Prompts.fill(ScreenBase(screen),p.tag,"{PageLeft2}{PageRight2}",16,10,UiKit.GREY,name0.x - 6,0,x.device);
         }
         for(var r:int = 0; r < shown; r++)
         {
            var index:int = first + r;
            var e:Object = es[index];
            var cell:Sprite = new Sprite();
            cell.x = 6;
            cell.y = head + r * ROW;
            cell.buttonMode = true;
            sp.addChild(cell);
            var on:Boolean = st.focus && index == st.pick;
            var current:Boolean = e.kind == "setup" && e.i == st.last;
            UiKit.rect(cell,0,0,w - 12,ROW - 4,on ? UiKit.ROW_SELECTED : (current ? UiKit.PANEL : UiKit.BODY),5);
            if(on)
            {
               UiKit.rect(cell,0,0,3,ROW - 4,UiKit.TEAL);
            }
            {
               var label:String = e.kind == "window" ? "ALL PICKS" : e.kind == "save" ? "+ SAVE AS NEW" : (e.kind == "delete" ?
                  "DELETE " + list[e.i].name : list[e.i].name);
               var t:TextField = UiKit.text(cell,label,10,4,12,e.kind == "delete" ? 0xFF8A80 : (on || current ? UiKit.WHITE :
                  UiKit.LIGHT),UiKit.BOLD);
               UiKit.fit(t,w - 24);
            }
            cell.addEventListener(MouseEvent.CLICK,clicker(slot,index));
         }
      }

      private static function clicker(slot:int, index:int) : Function
      {
         return function(e:MouseEvent):void
         {
            try
            {
               var x:Object = context(slot);
               if(x != null)
               {
                  x.st.focus = true;
                  inputDevice = -1;
                  act(slot,x,index,true);
                  panels[slot].key = null;
               }
            }
            catch(err:Error)
            {
               ErrorLog.write("setups click: " + err + " " + err.getStackTrace());
            }
         };
      }

      private static function getClass(name:String) : Object
      {
         return Object(getDefinitionByName(name));
      }
   }
}
