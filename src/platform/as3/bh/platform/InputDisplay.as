package bh.platform
{
   import flash.display.DisplayObject;
   import flash.display.Shape;
   import flash.display.Sprite;
   import flash.display.Stage;
   import flash.text.TextField;
   import flash.geom.Point;
   import flash.geom.Rectangle;
   import flash.utils.Dictionary;

   public final class InputDisplay
   {
      public static const POSITIONS:Array = ["Off","Bottom left","Bottom middle","Bottom right","Bottom, by side"];
      public static const SIZES:Array = [75,100,125,150];
      private static const SPLIT:int = 4;
      private static const DIM:Number = 0.3;
      private static var dimTick:int = 0;

      private static const KEYS:Array = [
         [1,4,"UP",1,0,1],
         [4,1,"LEFT",0,1,1],
         [2,5,"DOWN",1,1,1],
         [8,2,"RIGHT",2,1,1],
         [128,6,"LIGHT",3.4,0,1.3],
         [64,9,"HEAVY",4.7,0,1.3],
         [256,7,"DODGE",3.4,1,1.3],
         [512,8,"THROW",4.7,1,1.3],
         [16,3,"JUMP",0,2,6]];
      private static const PS_NAMES:Object = {"A":"CROSS","B":"CIRCLE","X":"SQUARE","Y":"TRIANGLE","LB":"L1","RB":"R1",
         "LT":"L2","RT":"R2","BACK":"SHARE","START":"OPTIONS"};
      private static const CELL:int = 34;
      private static const GAP:int = 3;
      private static const PAD:int = 6;
      private static const TITLE:int = 16;
      private static const MAX_OTHERS:int = 3;
      private static const LOCAL:uint = 8;
      private static const BOT:uint = 32;
      private static const OFF_COLOR:uint = 0x1A2B3A;
      private static const ON_COLOR:uint = UiKit.TEAL;

      private static var stage:Stage;
      private static var root:Sprite;
      private static var listening:Boolean = false;
      private static var panels:Dictionary = new Dictionary(true);
      private static var order:Array = [];
      private static var logged:int = 0;

      public function InputDisplay()
      {
      }

      public static function init() : void
      {
         Hooks.gameCreated.add(function(main:Object):void
         {
            stage = main.stage;
         });
         Hooks.matchStarted.add(start);
         Hooks.matchEnded.add(function(state:uint):void
         {
            stop();
         });
      }

      public static function get position() : int
      {
         var v:* = ModSettings.value("inputDisplay");
         return v == null ? 0 : Math.max(0,Math.min(POSITIONS.length - 1,int(v)));
      }

      public static function set position(p:int) : void
      {
         ModSettings.setValue("inputDisplay",p);
         if(position == 0)
         {
            stop();
         }
         else if(Platform.matchRunning)
         {
            start();
            layout();
         }
      }

      public static function get size() : int
      {
         var v:* = ModSettings.value("inputDisplaySize");
         return v != null && SIZES.indexOf(int(v)) >= 0 ? int(v) : 100;
      }

      public static function set size(percent:int) : void
      {
         ModSettings.setValue("inputDisplaySize",percent);
         layout();
      }

      public static const OTHERS:Array = ["Off","Your Teammate(s)","All"];

      public static function get others() : int
      {
         var v:* = ModSettings.value("inputDisplayOthers");
         if(v == null)
         {
            return ModSettings.flag("inputDisplayOpponents",false) ? 2 : 0;
         }
         return Math.max(0,Math.min(2,int(v)));
      }

      public static function set others(mode:int) : void
      {
         ModSettings.setValue("inputDisplayOthers",mode);
         for(var i:int = order.length - 1; i >= 0; i--)
         {
            if(order[i].other)
            {
               removePanel(order[i].state,order[i]);
            }
         }
         layout();
      }

      private static function start() : void
      {
         if(position == 0 || stage == null || listening)
         {
            return;
         }
         if(root == null)
         {
            root = new Sprite();
            root.mouseEnabled = root.mouseChildren = false;
         }
         Layers.put(root,Layers.screens(),stage,true);
         Hooks.inputSampled.add(onSample);
         Hooks.simulationFrame.add(onFrame);
         listening = true;
      }

      private static function stop() : void
      {
         if(listening)
         {
            Hooks.inputSampled.remove(onSample);
            Hooks.simulationFrame.remove(onFrame);
            listening = false;
         }
         if(root != null)
         {
            if(root.parent != null)
            {
               root.parent.removeChild(root);
            }
            root.removeChildren();
         }
         panels = new Dictionary(true);
         order.length = 0;
         logged = 0;
      }

      private static function onSample(state:Object, time:uint, bits:uint) : void
      {
         var device:uint = uint(state.var_8184);
         var p:Object = panels[state];
         if(p != null && device != 0 && p.device != device && (p.device == 2) != (device == 2))
         {
            removePanel(state,p);
            p = null;
         }
         if(p == null)
         {
            if(device == 0)
            {
               return;
            }
            p = device == 2 ? makePad(state) : makePanel(state,device);
         }
         else if(p.device != device && device != 0)
         {
            relabel(p,state,device);
         }
         if(p.pad != null)
         {
            try
            {
               (p.pad as PadDisplay).poll(state.var_2223.var_12619,shown(p,uint(state.var_13063)));
            }
            catch(e:Error)
            {
            }
         }
      }

      private static function onFrame(core:Object) : void
      {
         if(root != null)
         {
            root.visible = !BigWindow.anyOpen() && !LoadingBackground.showing;
         }
         if(others > 0)
         {
            addOthers(core,others == 1);
         }
         for(var i:int = 0; i < order.length; i++)
         {
            var p:Object = order[i];
            if(p.pad == null)
            {
               paintBits(p,shown(p,uint(p.state.var_13063)));
            }
         }
         if(++dimTick % 4 == 0)
         {
            dim(core);
         }
      }

      public static var bodiesSeen:Array = [];

      private static function dim(core:Object) : void
      {
         if(root == null || !root.visible || stage == null || order.length == 0)
         {
            return;
         }
         var bodies:Array = [];
         try
         {
            var players:Object = core.var_7050;
            for(var i:int = 0; i < int(players.length); i++)
            {
               var body:Sprite3D = players[i] != null && players[i].var_11807 != null ? players[i].var_11807.mTheDO3D : null;
               if(body != null && body.var_10860 && body.parent != null)
               {
                  var feet:Point = body.localToGlobal(new Point(0,0));
                  var head:Point = body.localToGlobal(new Point(0,-160));
                  var side:Point = body.localToGlobal(new Point(55,0));
                  var half:Number = Math.abs(side.x - feet.x);
                  if(feet.y > head.y && half > 0)
                  {
                     bodies.push(new Rectangle(feet.x - half,head.y,half * 2,feet.y - head.y));
                  }
               }
            }
         }
         catch(e:Error)
         {
         }
         bodiesSeen = bodies;
         for(var j:int = 0; j < order.length; j++)
         {
            var box:Sprite = order[j].box;
            var area:Rectangle = box.getBounds(stage);
            var covered:Boolean = false;
            for(var k:int = 0; k < bodies.length && !covered; k++)
            {
               covered = area.intersects(bodies[k]);
            }
            box.alpha = covered ? DIM : 1;
         }
      }

      private static function sideOf(p:Object) : int
      {
         try
         {
            var n:int = int(p.state.var_594.var_11355);
            var count:int = int(p.state.owner.var_7050.length);
            return n > Math.max(1,int(count / 2)) ? 1 : 0;
         }
         catch(e:Error)
         {
         }
         return p.other ? 1 : 0;
      }

      private static function addOthers(core:Object, mates:Boolean) : void
      {
         var others:int = 0;
         var i:int;
         for(i = 0; i < order.length; i++)
         {
            if(order[i].other)
            {
               others++;
            }
         }
         var players:* = core != null ? core.var_7050 : null;
         if(players == null || others >= MAX_OTHERS)
         {
            return;
         }
         var team:uint = 0;
         if(mates)
         {
            try
            {
               if((uint(core.var_8999.var_2458) & 1) != 0)
               {
                  for(i = 0; i < players.length; i++)
                  {
                     if(players[i] != null && (uint(players[i].var_1249) & LOCAL) != 0 && (uint(players[i].var_1249) & BOT) == 0)
                     {
                        team = uint(players[i].var_3540);
                        break;
                     }
                  }
               }
            }
            catch(e:Error)
            {
            }
            if(team == 0)
            {
               return;
            }
         }
         for(i = 0; i < players.length && others < MAX_OTHERS; i++)
         {
            var legend:Object = players[i];
            var state:Object = legend != null ? legend.var_10012 : null;
            if(state == null || panels[state] != null)
            {
               continue;
            }
            var flags:uint = uint(legend.var_1249);
            if((flags & LOCAL) != 0 && (flags & BOT) == 0 || mates && uint(legend.var_3540) != team)
            {
               continue;
            }
            var p:Object = makePanel(state,0);
            p.other = true;
            others++;
            Platform.log("input display: " + p.title.text + " panel (" + (mates ? "teammate" : "other player") + "'s inputs)");
         }
      }

      private static function shown(p:Object, bits:uint) : uint
      {
         if((bits & (128 | 512)) != (128 | 512))
         {
            return bits;
         }
         var lightOnly:Boolean = false;
         try
         {
            var state:Object = p.state;
            if(p.device == 1)
            {
               lightOnly = Boolean(state.owner.var_7206.var_7262);
            }
            else if(p.device == 2)
            {
               lightOnly = Boolean(state.var_2223.var_12619.var_10840.var_7262);
            }
            else if(p.device == 3)
            {
               lightOnly = Boolean(state.var_2313.var_7206.var_7262);
            }
         }
         catch(e:Error)
         {
         }
         return lightOnly ? bits : uint(bits & ~512);
      }

      private static function paintBits(p:Object, bits:uint) : void
      {
         var changed:uint = (p.bits ^ bits) & 0x3DF;
         if(changed == 0)
         {
            return;
         }
         p.bits = bits;
         if(logged < 40)
         {
            logged++;
            Platform.log("input display: " + p.title.text + " shows 0x" + bits.toString(16));
         }
         var caps:Array = p.caps;
         for(var i:int = 0; i < KEYS.length; i++)
         {
            if((changed & KEYS[i][0]) != 0)
            {
               paint(caps[i],(bits & KEYS[i][0]) != 0);
            }
         }
      }

      private static function makePanel(state:Object, device:uint) : Object
      {
         var box:Sprite = new Sprite();
         var w:Number = 6 * (CELL + GAP) - GAP + PAD * 2;
         var h:Number = 3 * (CELL + GAP) - GAP + PAD * 2 + TITLE;
         box.graphics.beginFill(0x000000,0.55);
         box.graphics.drawRoundRect(0,0,w,h,10,10);
         box.graphics.endFill();
         var title:TextField = UiKit.text(box,"",PAD,2,11,UiKit.LIGHT,UiKit.BOLD);
         var caps:Array = [];
         for(var i:int = 0; i < KEYS.length; i++)
         {
            var k:Array = KEYS[i];
            var cap:Sprite = new Sprite();
            cap.x = PAD + k[3] * (CELL + GAP);
            cap.y = PAD + TITLE + k[4] * (CELL + GAP);
            var bg:Shape = new Shape();
            cap.addChild(bg);
            var cw:Number = k[5] * CELL + (k[5] - 1) * GAP;
            var label:TextField = UiKit.text(cap,"",0,0,12,UiKit.WHITE,UiKit.BOLD);
            var action:TextField = UiKit.text(cap,k[2],0,0,8,UiKit.GREY,UiKit.BOLD);
            caps.push({"sprite":cap,"bg":bg,"w":cw,"label":label,"action":action});
            paint(caps[i],false);
            box.addChild(cap);
         }
         var p:Object = {"box":box,"title":title,"caps":caps,"bits":0,"device":0,"state":state,"other":false};
         panels[state] = p;
         order.push(p);
         root.addChild(box);
         relabel(p,state,device);
         layout();
         return p;
      }

      private static function makePad(state:Object) : Object
      {
         var pad:PadDisplay = new PadDisplay(state);
         var p:Object = {"box":pad.box,"title":pad.title,"pad":pad,"bits":0,"device":2,"state":state,"other":false};
         var name:String = "CONTROLLER";
         try
         {
            var type:Object = state.var_2223.method_7757();
            if(type != null && type.mDisplayName)
            {
               name = String(type.mDisplayName).toUpperCase();
            }
         }
         catch(e:Error)
         {
         }
         pad.title.text = slotOf(state) + name;
         panels[state] = p;
         order.push(p);
         root.addChild(pad.box);
         layout();
         return p;
      }

      private static function removePanel(state:Object, p:Object) : void
      {
         delete panels[state];
         var i:int = order.indexOf(p);
         if(i >= 0)
         {
            order.splice(i,1);
         }
         if(p.box.parent != null)
         {
            p.box.parent.removeChild(p.box);
         }
      }

      private static function slotOf(state:Object) : String
      {
         try
         {
            return "P" + int(state.var_594.var_11355) + "  ";
         }
         catch(e:Error)
         {
         }
         return "";
      }

      private static function relabel(p:Object, state:Object, device:uint) : void
      {
         p.device = device;
         if(device != 0)
         {
            p.other = false;
         }
         var slot:String = slotOf(state);
         var map:Object = null;
         var pad:Object = null;
         var playStation:Boolean = false;
         var profile:int = 0;
         var name:String = "KEYBOARD";
         try
         {
            profile = int(state.owner.var_12133);
            if(device == 1)
            {
               map = state.owner.var_7206;
            }
            else if(device == 3)
            {
               map = state.var_2313.var_7206;
               name = "KEYBOARD 2";
            }
            else if(device == 0)
            {
               name = (uint(state.var_594.var_1249) & BOT) != 0 ? "BOT" : "PLAYER";
            }
            else
            {
               name = "CONTROLLER";
               var type:Object = state.var_2223.method_7757();
               if(type != null && type.mDisplayName)
               {
                  name = String(type.mDisplayName).toUpperCase();
               }
               pad = state.var_2223.var_12619.var_10840;
               playStation = type != null && String(type.var_15259).indexOf("PS") == 0;
            }
         }
         catch(e:Error)
         {
         }
         p.title.text = slot + name;
         for(var i:int = 0; i < KEYS.length; i++)
         {
            var cap:Object = p.caps[i];
            var key:String = "";
            if(map != null)
            {
               var names:Array = [];
               for(var second:int = 0; second < 2; second++)
               {
                  try
                  {
                     var code:int = int(map.method_932(KEYS[i][1],profile,false,second == 1,false));
                     var name1:String = code != 255 ? String(map.method_7962(code)) : "";
                     if(name1.length > 0 && name1 != "null" && names.indexOf(name1) < 0)
                     {
                        names.push(name1);
                     }
                  }
                  catch(e:Error)
                  {
                  }
               }
               key = names.join(" ");
            }
            else if(pad != null && KEYS[i][0] >= 16)
            {
               try
               {
                  var buttons:Array = pad.method_5841(false,KEYS[i][0]);
                  if(buttons != null && buttons.length > 0)
                  {
                     key = buttons.slice(0,playStation ? 1 : 2).map(function(b:String, ...rest):String
                     {
                        return playStation && PS_NAMES[b] != null ? PS_NAMES[b] : b;
                     }).join(" ");
                  }
               }
               catch(e:Error)
               {
               }
            }
            var label:TextField = cap.label;
            var action:TextField = cap.action;
            var actionOnly:Boolean = device == 0;
            if(actionOnly)
            {
               label.text = "";
               action.visible = true;
            }
            else if(key.length == 0 || key == "null")
            {
               label.text = map != null || pad != null && KEYS[i][0] >= 16 ? "-" : KEYS[i][2];
               action.visible = label.text == "-";
            }
            else
            {
               label.text = key.toUpperCase();
               action.visible = true;
            }
            UiKit.fit(label,cap.w - 4);
            label.x = Math.round((cap.w - label.width) / 2);
            label.y = action.visible ? 3 : Math.round((CELL - label.height) / 2);
            action.x = Math.round((cap.w - action.width) / 2);
            action.y = actionOnly ? Math.round((CELL - action.height) / 2) : CELL - action.height - 1;
            paint(cap,(p.bits & KEYS[i][0]) != 0);
         }
      }

      private static function paint(cap:Object, on:Boolean) : void
      {
         var bg:Shape = cap.bg;
         bg.graphics.clear();
         bg.graphics.beginFill(on ? ON_COLOR : OFF_COLOR,on ? 1 : 0.9);
         bg.graphics.drawRoundRect(0,0,cap.w,CELL,6,6);
         bg.graphics.endFill();
         (cap.label as TextField).textColor = on ? UiKit.NAVY_TEXT : UiKit.WHITE;
         (cap.action as TextField).textColor = on ? UiKit.NAVY_TEXT : UiKit.GREY;
      }

      private static function layout() : void
      {
         if(root == null || stage == null || order.length == 0)
         {
            return;
         }
         var scale:Number = size / 100;
         var i:int;
         for(i = 0; i < order.length; i++)
         {
            var scaled:Sprite = order[i].box as Sprite;
            scaled.scaleX = scale;
            scaled.scaleY = scale;
         }
         var pos:int = position;
         if(pos == SPLIT)
         {
            var left:Number = 12;
            var right:Number = stage.stageWidth - 12;
            for(i = 0; i < order.length; i++)
            {
               var sideBox:Sprite = order[i].box;
               sideBox.y = stage.stageHeight - sideBox.height - 12;
               if(sideOf(order[i]) == 0)
               {
                  sideBox.x = left;
                  left += sideBox.width + 8;
               }
            }
            for(i = order.length - 1; i >= 0; i--)
            {
               if(sideOf(order[i]) == 1)
               {
                  right -= order[i].box.width;
                  order[i].box.x = right;
                  right -= 8;
               }
            }
         }
         else
         {
            var total:Number = -8;
            for(i = 0; i < order.length; i++)
            {
               total += (order[i].box as Sprite).width + 8;
            }
            var x:Number = pos == 1 ? 12 : (pos == 2 ? Math.round((stage.stageWidth - total) / 2) : stage.stageWidth - total - 12);
            for(i = 0; i < order.length; i++)
            {
               var box:Sprite = order[i].box;
               box.x = x;
               box.y = stage.stageHeight - box.height - 12;
               x += box.width + 8;
            }
         }
         if(root.parent != null && root.parent.getChildIndex(root) != root.parent.numChildren - 1)
         {
            root.parent.setChildIndex(root,root.parent.numChildren - 1);
         }
      }
   }
}
