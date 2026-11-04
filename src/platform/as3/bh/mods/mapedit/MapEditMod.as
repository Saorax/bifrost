package bh.mods.mapedit
{
   import bh.platform.ContentMods;
   import bh.platform.Hooks;
   import bh.platform.Platform;
   import flash.display.Shape;
   import flash.display.Sprite;
   import flash.display.Stage;
   import flash.events.Event;
   import flash.events.MouseEvent;
   import flash.filesystem.File;
   import flash.filesystem.FileMode;
   import flash.filesystem.FileStream;
   import flash.filters.GlowFilter;
   import flash.geom.Point;
   import flash.text.TextField;
   import flash.text.TextFormat;
   import flash.ui.Mouse;

   public final class MapEditMod
   {
      public static const KEY:uint = 115;
      private static const HANDLE:Number = 12;
      private static const COLLISIONS:Object = {"HardCollision":0xFF4040,"SoftCollision":0xFFD030};

      private static var stage:Stage;
      private static var layer:Sprite;
      private static var shape:Shape;
      private static var text:TextField;
      private static var on:Boolean = false;

      private static var levelName:String = null;
      private static var source:Object = null;
      private static var doc:XML = null;
      private static var undo:Array = [];
      private static var dirty:Boolean = false;
      private static var snap:Boolean = true;
      private static var message:String = "";
      private static var crlf:Boolean = false;

      private static var handles:Array = [];
      private static var hover:Object = null;
      private static var drag:Object = null;

      public function MapEditMod()
      {
      }

      public static function register() : void
      {
         Hooks.gameCreated.add(function(main:Object):void
         {
            stage = main.stage;
         });
         Hooks.keyDown.add(onKey);
      }

      private static function core() : Object
      {
         return Object(GameApp.mainInstance).var_13259;
      }

      private static function onKey(event:Object) : Boolean
      {
         if(event == null)
         {
            return false;
         }
         var code:uint = uint(event.keyCode);
         if(code == KEY && !event.ctrlKey && !event.altKey && !event.shiftKey)
         {
            if(on)
            {
               hide();
            }
            else if(Platform.matchRunning)
            {
               show();
            }
            return true;
         }
         if(!on || doc == null)
         {
            return false;
         }
         if(event.ctrlKey && code == 83)
         {
            save();
            return true;
         }
         if(event.ctrlKey && code == 90)
         {
            if(undo.length > 0)
            {
               doc = new XML(undo.pop());
               dirty = true;
               message = "undone";
            }
            return true;
         }
         if(source == null)
         {
            return false;
         }
         var at:Point = mouseWorld();
         switch(code)
         {
            case 49:
               add(<HardCollision X1={r(at.x - 150)} X2={r(at.x + 150)} Y={r(at.y)}/>,"hard collision");
               return true;
            case 50:
               add(<SoftCollision X1={r(at.x - 150)} X2={r(at.x + 150)} Y={r(at.y)}/>,"soft collision");
               return true;
            case 51:
               add(<Respawn X={r(at.x)} Y={r(at.y)}/>,"respawn");
               return true;
            case 52:
               add(<ItemSpawn X={r(at.x - 200)} Y={r(at.y - 75)} W="400" H="150"/>,"item spawn");
               return true;
            case 46:
            case 8:
               if(hover != null)
               {
                  remember();
                  var node:XML = hover.node;
                  delete node.parent().children()[node.childIndex()];
                  message = "removed " + node.name();
                  hover = null;
               }
               return true;
            case 71:
               snap = !snap;
               message = "snap " + (snap ? "on" : "off");
               return true;
         }
         return false;
      }

      private static function r(v:Number) : Number
      {
         return snap ? Math.round(v / 10) * 10 : Math.round(v);
      }

      private static function add(node:XML, what:String) : void
      {
         remember();
         var same:XMLList = doc.child(node.name());
         if(same.length() > 0)
         {
            doc.insertChildAfter(same[same.length() - 1],node);
         }
         else
         {
            doc.appendChild(node);
         }
         message = "added " + what;
      }

      private static function remember() : void
      {
         undo.push(doc.toXMLString());
         if(undo.length > 50)
         {
            undo.shift();
         }
         dirty = true;
      }

      private static function show() : void
      {
         try
         {
            levelName = String(core().var_14641.var_256.var_5173);
         }
         catch(e:Error)
         {
            Platform.log("map editor: no map in this match");
            return;
         }
         source = ContentMods.levelFile(levelName);
         doc = null;
         undo = [];
         dirty = false;
         try
         {
            var xml:Object = source != null ? readFile(source.file as File) : gameLevel(levelName);
            doc = xml is XML ? xml as XML : new XML(String(xml));
         }
         catch(e:Error)
         {
            Platform.log("map editor: could not read " + levelName + ": " + e.message);
            return;
         }
         on = true;
         message = source != null ? "editing " + source.mod.id + "/" + source.path : "a game map: view only";
         if(layer == null)
         {
            layer = new Sprite();
            shape = new Shape();
            layer.addChild(shape);
            text = new TextField();
            text.defaultTextFormat = new TextFormat("_sans",15,0xFFFFFF,true);
            text.selectable = false;
            text.mouseEnabled = false;
            text.multiline = true;
            text.width = 1100;
            text.height = 90;
            text.filters = [new GlowFilter(0,1,3,3,6)];
            layer.addChild(text);
         }
         stage.addChild(layer);
         stage.addEventListener(Event.ENTER_FRAME,onFrame,false,-900);
         stage.addEventListener(MouseEvent.MOUSE_DOWN,onDown,false,1000);
         stage.addEventListener(MouseEvent.MOUSE_UP,onUp,false,1000);
         Mouse.show();
         Platform.log("map editor on: " + levelName + " (" + (source != null ? source.file.nativePath : "game map") + ")");
      }

      private static function hide() : void
      {
         on = false;
         drag = null;
         hover = null;
         if(layer != null && layer.parent != null)
         {
            layer.parent.removeChild(layer);
         }
         if(stage != null)
         {
            stage.removeEventListener(Event.ENTER_FRAME,onFrame);
            stage.removeEventListener(MouseEvent.MOUSE_DOWN,onDown);
            stage.removeEventListener(MouseEvent.MOUSE_UP,onUp);
         }
         if(dirty)
         {
            Platform.log("map editor closed with unsaved changes to " + levelName + " (kept until the next F4 on another map)");
         }
      }

      private static function gameLevel(name:String) : String
      {
         var map:Object = class_250.var_4065;
         var xml:Object = map.h[name] != null ? map.h[name] : map.getReserved(name);
         return xml.toString();
      }

      private static function readFile(file:File) : XML
      {
         var s:FileStream = new FileStream();
         s.open(file,FileMode.READ);
         var t:String = s.readUTFBytes(s.bytesAvailable);
         s.close();
         crlf = t.indexOf("\r\n") >= 0;
         var old:Object = XML.settings();
         XML.ignoreComments = false;
         XML.ignoreProcessingInstructions = false;
         try
         {
            return new XML(t);
         }
         finally
         {
            XML.setSettings(old);
         }
         return null;
      }

      private static function save() : void
      {
         if(source == null)
         {
            message = "a game map can't be saved (view only)";
            return;
         }
         var old:Object = XML.settings();
         try
         {
            XML.prettyPrinting = true;
            XML.prettyIndent = 2;
            var out:String = doc.toXMLString() + "\n";
            if(crlf)
            {
               out = out.split("\n").join("\r\n");
            }
            var s:FileStream = new FileStream();
            s.open(new File((source.file as File).nativePath),FileMode.WRITE);
            s.writeUTFBytes(out);
            s.close();
            dirty = false;
            ContentMods.reloadFiles();
            message = "saved " + source.path + ": it plays from the next match on this map (Leave, then Training)";
            Platform.log("map editor saved " + (source.file as File).nativePath);
         }
         catch(e:Error)
         {
            message = "not saved: " + e.message;
         }
         finally
         {
            XML.setSettings(old);
         }
      }

      private static function world() : Object
      {
         var c:Object = core();
         try
         {
            var players:Object = c.var_7050;
            for(var i:int = 0; i < int(players.length); i++)
            {
               var body:Object = players[i].var_11807 != null ? players[i].var_11807.mTheDO3D : null;
               if(body != null && body.parent != null)
               {
                  return body.parent;
               }
            }
         }
         catch(e:Error)
         {
         }
         return c.var_479;
      }

      private static function toStage(w:Object, x:Number, y:Number) : Point
      {
         return w.localToGlobal(new Point(x,y));
      }

      private static function mouseWorld() : Point
      {
         return world().globalToLocal(mouse());
      }

      private static function mouse() : Point
      {
         return testMouse != null ? testMouse : new Point(stage.mouseX,stage.mouseY);
      }

      private static var testMouse:Point = null;

      public static function test(args:Array) : String
      {
         if(!on)
         {
            return "map editor not shown";
         }
         var w:Object = world();
         if(args[0] == "gamexml")
         {
            var parsed:XML = new XML(gameLevel(levelName));
            return parsed.child(String(args[1])).toXMLString().split("\n").join(" ");
         }
         if(args[0] == "real")
         {
            testMouse = null;
            return "real mouse";
         }
         testMouse = w.localToGlobal(new Point(Number(args[1]),Number(args[2])));
         draw();
         if(args[0] == "drag")
         {
            if(hover == null)
            {
               return "no handle at " + args[1] + "," + args[2];
            }
            var what:String = String(hover.node.name());
            remember();
            drag = hover;
            testMouse = w.localToGlobal(new Point(Number(args[3]),Number(args[4])));
            draw();
            drag = null;
            message = "moved " + what;
            draw();
            return "dragged " + what + " to " + args[3] + "," + args[4] + ": " + text.text.split("\r").join(" | ");
         }
         return "mouse at stage " + Math.round(testMouse.x) + "," + Math.round(testMouse.y) + (hover != null ? ", over " + hover.node.name() : "");
      }

      private static function num(node:XML, a:String, other:String = null) : Number
      {
         var v:String = String(node.attribute(a));
         if(v == "" && other != null)
         {
            v = String(node.attribute(other));
         }
         return Number(v);
      }

      private static function onFrame(e:Event) : void
      {
         if(!Platform.matchRunning)
         {
            hide();
            return;
         }
         try
         {
            draw();
         }
         catch(err:Error)
         {
            message = "drawing failed: " + err.message;
         }
      }

      private static function draw() : void
      {
         var w:Object = world();
         if(drag != null)
         {
            moveDragged(w);
         }
         var g:Object = shape.graphics;
         g.clear();
         handles = [];
         for each(var bounds:String in ["CameraBounds","SpawnBotBounds"])
         {
            for each(var b:XML in doc.child(bounds))
            {
               box(w,g,num(b,"X"),num(b,"Y"),num(b,"W"),num(b,"H"),0xB0B0B0,0.6,null);
            }
         }
         for each(var node:XML in doc.children())
         {
            var kind:String = String(node.name());
            if(kind.indexOf("Collision") > 0 && kind != "DynamicCollision")
            {
               var colour:uint = COLLISIONS[kind] != null ? uint(COLLISIONS[kind]) : 0xFF9030;
               var a:Point = toStage(w,num(node,"X1","X"),num(node,"Y1","Y"));
               var c:Point = toStage(w,num(node,"X2","X"),num(node,"Y2","Y"));
               g.lineStyle(4,colour,0.9);
               g.moveTo(a.x,a.y);
               g.lineTo(c.x,c.y);
               dot(g,a,colour,node,"1");
               dot(g,c,colour,node,"2");
            }
            else if(kind == "Respawn")
            {
               dot(g,toStage(w,num(node,"X"),num(node,"Y")),String(node.@ExpandedInit) == "true" ? 0x40C060 : 0x40FF60,node,"p",8);
            }
            else if(kind == "ItemInitSpawn" || kind == "TeamItemInitSpawn")
            {
               dot(g,toStage(w,num(node,"X"),num(node,"Y")),0x40A0FF,node,"p",6);
            }
            else if(kind == "ItemSpawn")
            {
               box(w,g,num(node,"X"),num(node,"Y"),num(node,"W"),num(node,"H"),0x40A0FF,0.9,node);
            }
         }
         pick();
         if(hover != null)
         {
            g.lineStyle(2,0xFFFFFF,1);
            g.drawCircle(hover.x,hover.y,11);
         }
         var at:Point = mouseWorld();
         text.text = "MAP EDITOR  " + levelName + (dirty ? "  (unsaved)" : "") + "   x " + Math.round(at.x) + "  y " + Math.round(at.y) +
            (hover != null ? "   " + hover.node.name() : "") + "\n" +
            (source != null ? "drag  move    1 hard  2 soft  3 respawn  4 item spawn    Del remove    Ctrl+Z undo    G snap " +
            (snap ? "on" : "off") + "    Ctrl+S save    F4 hide" : "view only (a game map)    F4 hide") + "\n" + message;
         text.x = (stage.stageWidth - text.textWidth) / 2;
         text.y = stage.stageHeight - 100;
      }

      private static function box(w:Object, g:Object, x:Number, y:Number, wd:Number, ht:Number, colour:uint, alpha:Number, node:XML) : void
      {
         var a:Point = toStage(w,x,y);
         var c:Point = toStage(w,x + wd,y + ht);
         g.lineStyle(2,colour,alpha);
         g.drawRect(a.x,a.y,c.x - a.x,c.y - a.y);
         if(node != null)
         {
            dot(g,new Point((a.x + c.x) / 2,(a.y + c.y) / 2),colour,node,"p",5);
            dot(g,c,colour,node,"size",5);
         }
      }

      private static function dot(g:Object, p:Point, colour:uint, node:XML, part:String, size:Number = 6) : void
      {
         g.lineStyle(1,0,0.8);
         g.beginFill(colour,0.95);
         g.drawCircle(p.x,p.y,size);
         g.endFill();
         if(source != null)
         {
            handles.push({"x":p.x,"y":p.y,"node":node,"part":part});
         }
      }

      private static function pick() : void
      {
         if(drag != null)
         {
            hover = drag;
            return;
         }
         hover = null;
         var best:Number = HANDLE * HANDLE;
         for each(var h:Object in handles)
         {
            var dx:Number = h.x - mouse().x;
            var dy:Number = h.y - mouse().y;
            if(dx * dx + dy * dy <= best)
            {
               best = dx * dx + dy * dy;
               hover = h;
            }
         }
      }

      private static function onDown(e:MouseEvent) : void
      {
         if(hover != null && source != null)
         {
            remember();
            drag = hover;
            e.stopImmediatePropagation();
         }
      }

      private static function onUp(e:MouseEvent) : void
      {
         if(drag != null)
         {
            message = "moved " + drag.node.name();
            drag = null;
            e.stopImmediatePropagation();
         }
      }

      private static function moveDragged(w:Object) : void
      {
         var at:Point = mouseWorld();
         var x:Number = r(at.x);
         var y:Number = r(at.y);
         var node:XML = drag.node;
         var part:String = drag.part;
         if(part == "1" || part == "2")
         {
            var x1:Number = num(node,"X1","X"), y1:Number = num(node,"Y1","Y");
            var x2:Number = num(node,"X2","X"), y2:Number = num(node,"Y2","Y");
            if(part == "1")
            {
               x1 = x;
               y1 = y;
            }
            else
            {
               x2 = x;
               y2 = y;
            }
            setPair(node,"X",x1,x2);
            setPair(node,"Y",y1,y2);
         }
         else if(part == "p" && String(node.name()) == "ItemSpawn")
         {
            node.@X = r(x - num(node,"W") / 2);
            node.@Y = r(y - num(node,"H") / 2);
         }
         else if(part == "p")
         {
            node.@X = x;
            node.@Y = y;
         }
         else if(part == "size")
         {
            node.@W = Math.max(10,x - num(node,"X"));
            node.@H = Math.max(10,y - num(node,"Y"));
         }
      }

      private static function setPair(node:XML, a:String, v1:Number, v2:Number) : void
      {
         delete node.@[a];
         delete node.@[a + "1"];
         delete node.@[a + "2"];
         if(v1 == v2)
         {
            node.@[a] = v1;
         }
         else
         {
            node.@[a + "1"] = v1;
            node.@[a + "2"] = v2;
         }
      }
   }
}
