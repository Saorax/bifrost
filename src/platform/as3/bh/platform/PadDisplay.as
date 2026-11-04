package bh.platform
{
   import flash.display.CapsStyle;
   import flash.display.DisplayObject;
   import flash.display.GradientType;
   import flash.display.Graphics;
   import flash.display.JointStyle;
   import flash.display.LineScaleMode;
   import flash.display.Shape;
   import flash.display.Sprite;
   import flash.geom.Matrix;
   import flash.text.TextField;

   public final class PadDisplay
   {
      public static const W:int = 231;
      public static const H:int = 136;
      private static const PAD:int = 6;
      private static const TITLE:int = 16;
      private static const CANVAS_W:Number = 400;
      private static const CANVAS_H:Number = 340;
      private static const SCALE:Number = (H - TITLE - 4) / CANVAS_H;

      private static const OFF:uint = 0x1A2B3A;
      private static const ON:uint = UiKit.TEAL;
      private static const BUTTONS:Array = ["A","B","X","Y","LB","RB","BACK","START","LS","RS"];
      private static const COMMANDS:Array = [[[1,-90],[2,90],[4,180],[8,0]],[[16,"JUMP"]],[[128,"LIGHT"],[64,"HEAVY"]],
         [[256,"DODGE"],[512,"THROW"]]];
      private static const STICK_TRAVEL:Number = 9;

      public var box:Sprite;
      public var title:TextField;

      private var ids:Object = {};
      private var values:Object = {};
      private var lit:Object = {};
      private var knobs:Object = {};
      private var padKind:String = "xbox";
      private var invertY:Boolean;
      private var bits:uint = 0;
      private var commandCaps:Array = [];

      public function PadDisplay(state:Object)
      {
         box = new Sprite();
         box.graphics.beginFill(0x000000,0.55);
         box.graphics.drawRoundRect(0,0,W,H,10,10);
         box.graphics.endFill();
         var type:Object = null;
         try
         {
            type = state.var_2223.method_7757();
            padKind = kindOf(type);
            invertY = type != null && Boolean(type.var_1470);
            for each(var n:String in BUTTONS.concat(["LT","RT","UP","DOWN","LEFT","RIGHT","LSX","LSY","RSX","RSY","DPAD"]))
            {
               var id:* = type.buttons.h[n];
               if(id != null && String(id).length > 0)
               {
                  ids[n] = String(id);
               }
            }
         }
         catch(e:Error)
         {
         }
         var pad:Sprite = new Sprite();
         pad.scaleX = pad.scaleY = SCALE;
         pad.x = 2;
         pad.y = TITLE + 2;
         box.addChild(pad);
         draw(pad,PadLooks.LOOKS[padKind].layers);
         title = UiKit.text(box,"",PAD,2,11,UiKit.LIGHT,UiKit.BOLD);
         var left:Number = pad.x + Math.ceil(CANVAS_W * SCALE) + 4;
         var rows:Number = COMMANDS.length * 12 + (COMMANDS.length - 1) * 4;
         var y:Number = Math.round(TITLE + (H - TITLE - rows) / 2);
         for each(var row:Array in COMMANDS)
         {
            var x:Number = left;
            for each(var c:Array in row)
            {
               var cap:Sprite = new Sprite();
               var t:TextField = c[1] is String ? UiKit.text(cap,c[1],2,0,8,UiKit.GREY,UiKit.BOLD) : null;
               var bg:Shape = new Shape();
               cap.addChildAt(bg,0);
               var cw:Number = t != null ? Math.ceil(t.width) + 4 : 14;
               cap.x = x;
               cap.y = y;
               x += cw + 2;
               box.addChild(cap);
               commandCaps.push({"bit":c[0],"bg":bg,"t":t,"w":cw,"angle":t == null ? Number(c[1]) : NaN});
               paintCommand(commandCaps[commandCaps.length - 1],false);
            }
            y += 16;
         }
         poll(state.var_2223.var_12619,0);
      }

      private static function kindOf(type:Object) : String
      {
         if(type == null)
         {
            return "xbox";
         }
         var name:String = String(type.mDisplayName).toLowerCase();
         var style:String = String(type.var_15259);
         if(name.indexOf("ps5") >= 0 || name.indexOf("dualsense") >= 0)
         {
            return "dualsense";
         }
         if(style.indexOf("PS") == 0)
         {
            return "dualshock";
         }
         if(style == "SwitchPro")
         {
            return "switch";
         }
         return "xbox";
      }

      private function draw(pad:Sprite, layers:Array) : void
      {
         var key:String = null;
         var g:Graphics = null;
         for each(var layer:Object in layers)
         {
            var on:Boolean = layer.state == "on";
            var k:String = (layer.knob != null ? layer.knob : "") + "|" + (on ? layer.part : "");
            if(k != key)
            {
               key = k;
               var s:Shape = new Shape();
               var parent:Sprite = pad;
               if(layer.knob != null)
               {
                  if(knobs[layer.knob] == null)
                  {
                     knobs[layer.knob] = new Sprite();
                     pad.addChild(knobs[layer.knob]);
                  }
                  parent = knobs[layer.knob];
               }
               parent.addChild(s);
               if(on)
               {
                  s.visible = false;
                  if(lit[layer.part] == null)
                  {
                     lit[layer.part] = [];
                  }
                  lit[layer.part].push(s);
               }
               g = s.graphics;
            }
            paint(g,layer);
         }
         for each(var n:String in BUTTONS.concat(["LT","RT","D0","D1","D2","D3"]))
         {
            values[n] = 0;
         }
      }

      private static function paint(g:Graphics, layer:Object) : void
      {
         var path:Object = parse(String(layer.d));
         var cmds:Array = path.cmds;
         var dx:Number = layer.shadow ? 3 : 0;
         var dy:Number = layer.shadow ? 4 : 0;
         if(layer.stroke != null)
         {
            g.lineStyle(Number(layer.lw),uint(layer.stroke),1,false,LineScaleMode.NORMAL,CapsStyle.ROUND,JointStyle.ROUND);
         }
         else
         {
            g.lineStyle();
         }
         var filled:Boolean = true;
         if(layer.grad != null)
         {
            var b:Array = path.bounds;
            var m:Matrix = new Matrix();
            m.createGradientBox(Math.max(1,b[2] - b[0]),Math.max(1,b[3] - b[1]),Math.PI / 2,b[0] + dx,b[1] + dy);
            g.beginGradientFill(GradientType.LINEAR,[uint(layer.grad[0]),uint(layer.grad[1])],[1,1],[0,255],m);
         }
         else if(layer.fill != null)
         {
            g.beginFill(uint(layer.fill),layer.alpha != null ? Number(layer.alpha) : 1);
         }
         else
         {
            filled = false;
         }
         for each(var c:Array in cmds)
         {
            if(c[0] == "M")
            {
               g.moveTo(c[1] + dx,c[2] + dy);
            }
            else if(c[0] == "L")
            {
               g.lineTo(c[1] + dx,c[2] + dy);
            }
            else if(c[0] == "C")
            {
               g.cubicCurveTo(c[1] + dx,c[2] + dy,c[3] + dx,c[4] + dy,c[5] + dx,c[6] + dy);
            }
            else if(c[0] == "Z")
            {
               g.lineTo(c[1] + dx,c[2] + dy);
            }
         }
         if(filled)
         {
            g.endFill();
         }
         g.lineStyle();
      }

      private static function parse(d:String) : Object
      {
         var tokens:Array = [];
         var word:String = "";
         for(var ci:int = 0; ci <= d.length; ci++)
         {
            var ch:String = ci < d.length ? d.charAt(ci) : " ";
            if(ch == " " || ch == "," || ch == "M" || ch == "L" || ch == "C" || ch == "Z")
            {
               if(word.length > 0)
               {
                  tokens.push(word);
               }
               word = "";
               if(ch != " " && ch != ",")
               {
                  tokens.push(ch);
               }
            }
            else
            {
               word += ch;
            }
         }
         var out:Array = [];
         var b:Array = [Infinity,Infinity,-Infinity,-Infinity];
         var start:Array = [0,0];
         var i:int = 0;
         while(i < tokens.length)
         {
            var t:String = tokens[i++];
            var n:int = t == "M" || t == "L" ? 2 : (t == "C" ? 6 : 0);
            var c:Array = [t];
            for(var j:int = 0; j < n; j++)
            {
               var v:Number = Number(tokens[i++]);
               c.push(v);
               if((j & 1) == 0)
               {
                  b[0] = Math.min(b[0],v);
                  b[2] = Math.max(b[2],v);
               }
               else
               {
                  b[1] = Math.min(b[1],v);
                  b[3] = Math.max(b[3],v);
               }
            }
            if(t == "M")
            {
               start = [c[1],c[2]];
            }
            else if(t == "Z")
            {
               c.push(start[0],start[1]);
            }
            out.push(c);
         }
         return {"cmds":out,"bounds":b};
      }

      public function poll(controller:Object, commands:uint) : void
      {
         var map:Object = null;
         try
         {
            map = controller.var_12051.h;
         }
         catch(e:Error)
         {
            return;
         }
         for each(var n:String in BUTTONS)
         {
            set(n,num(map,n) > 0.3 ? 1 : 0);
         }
         set("LT",Math.round(Math.max(0,Math.min(1,num(map,"LT"))) * 20) / 20);
         set("RT",Math.round(Math.max(0,Math.min(1,num(map,"RT"))) * 20) / 20);
         var d:uint = 0;
         if(num(map,"UP") >= 0.1) d |= 1;
         if(num(map,"DOWN") >= 0.1) d |= 2;
         if(num(map,"LEFT") >= 0.1) d |= 4;
         if(num(map,"RIGHT") >= 0.1) d |= 8;
         if(ids.DPAD != null)
         {
            var h:Number = num(map,"DPAD");
            d |= h == 0.714 ? 4 : (h == -0.429 ? 8 : (h == -1 ? 1 : (h == 0.143 ? 2 : (h == -0.714 ? 1 | 8 : (h == 0.429 ? 4 | 2 : (h == 1 ? 1 | 4 : (h == -0.143 ? 2 | 8 : 0)))))));
         }
         for(var i:int = 0; i < 4; i++)
         {
            set("D" + i,(d & 1 << i) != 0 ? 1 : 0);
         }
         stickTo("L",num(map,"LSX"),num(map,"LSY"));
         stickTo("R",num(map,"RSX"),num(map,"RSY"));
         var changed:uint = (bits ^ commands) & 0x3DF;
         if(changed != 0)
         {
            bits = commands;
            for each(var c:Object in commandCaps)
            {
               if((changed & c.bit) != 0)
               {
                  paintCommand(c,(commands & c.bit) != 0);
               }
            }
         }
      }

      private function num(map:Object, name:String) : Number
      {
         var id:String = ids[name];
         if(id == null)
         {
            return 0;
         }
         var v:Number = Number(map[id]);
         return isNaN(v) ? 0 : v;
      }

      private function set(name:String, v:Number) : void
      {
         if(values[name] === v)
         {
            return;
         }
         values[name] = v;
         for each(var s:DisplayObject in lit[name])
         {
            s.visible = v > 0.02;
            s.alpha = v;
         }
      }

      private function stickTo(side:String, x:Number, y:Number) : void
      {
         if(invertY)
         {
            y = -y;
         }
         var knob:Sprite = knobs[side];
         if(knob == null)
         {
            return;
         }
         var r:Number = Math.sqrt(x * x + y * y);
         if(r > 1)
         {
            x /= r;
            y /= r;
         }
         knob.x = Math.round(x * STICK_TRAVEL);
         knob.y = Math.round(-y * STICK_TRAVEL);
      }

      private static function paintCommand(c:Object, on:Boolean) : void
      {
         var bg:Shape = c.bg;
         bg.graphics.clear();
         bg.graphics.beginFill(on ? ON : OFF,on ? 1 : 0.9);
         bg.graphics.drawRoundRect(0,0,c.w,12,4,4);
         bg.graphics.endFill();
         if(c.t == null)
         {
            var a:Number = c.angle * Math.PI / 180;
            var cx:Number = c.w / 2;
            bg.graphics.beginFill(on ? UiKit.NAVY_TEXT : UiKit.GREY);
            bg.graphics.moveTo(cx + Math.cos(a) * 4,6 + Math.sin(a) * 4);
            bg.graphics.lineTo(cx + Math.cos(a + 2.4) * 4,6 + Math.sin(a + 2.4) * 4);
            bg.graphics.lineTo(cx + Math.cos(a - 2.4) * 4,6 + Math.sin(a - 2.4) * 4);
            bg.graphics.endFill();
            return;
         }
         (c.t as TextField).textColor = on ? UiKit.NAVY_TEXT : UiKit.GREY;
      }
   }
}
