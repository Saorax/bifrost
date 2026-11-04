package bh.platform
{
   import flash.display.MovieClip;
   import flash.display.Shape;
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.events.MouseEvent;
   import flash.geom.Point;
   import flash.text.TextField;
   import flash.utils.getTimer;

   public final class HitboxView extends Sprite
   {
      private static const COLORS:Array = [13369548,52224,13421568];
      private static const HURT:uint = 8947712;

      private var w:Number;
      private var h:Number;
      private var scale:Number = 1;
      private var ox:Number = 0;
      private var oy:Number = 0;
      private var picked:Object = null;
      private var dragging:String = null;
      private var grabbed:Point = null;
      private var start:Object = null;
      private var art:Shape = new Shape();
      private var handles:Shape = new Shape();
      private var strip:Shape = new Shape();
      private var label:TextField;
      private var shown:Array = [];
      private var shownPart:int = -1;
      private var shownShape:int = -1;
      private var line:Object = null;
      private var frame:int = -1;
      private var playing:Boolean = false;
      private var lastStep:int = 0;
      public var legend:Object = null;
      private var doll:LegendDoll = null;
      private var legendLayer:MovieClip = new MovieClip();
      public var onDrag:Function = null;
      public var onFrame:Function = null;
      public static const STRIP_H:Number = 56;
      private static const PLAY_MS:int = 80;

      public function HitboxView(width:Number, height:Number)
      {
         super();
         w = width;
         h = height;
         legendLayer.mouseEnabled = false;
         legendLayer.mouseChildren = false;
         addChild(legendLayer);
         var clip:Shape = new Shape();
         clip.graphics.beginFill(0);
         clip.graphics.drawRect(0,0,w,h - STRIP_H);
         clip.graphics.endFill();
         addChild(clip);
         legendLayer.mask = clip;
         addChild(art);
         addChild(handles);
         addChild(strip);
         label = UiKit.text(this,"",12,8,12,UiKit.WHITE,UiKit.MEDIUM,w - 24);
         graphics.beginFill(0,0);
         graphics.drawRect(0,0,w,h);
         graphics.endFill();
         addEventListener(MouseEvent.MOUSE_DOWN,down);
         addEventListener(Event.REMOVED_FROM_STAGE,function(e:Event):void
         {
            dispose();
         });
      }

      public static function timeline(p:PowerType) : Object
      {
         var casts:Array = [];
         var f:int = 0;
         if(p != null && p.var_13330 != null)
         {
            for(var i:int = 0; i < int(p.var_13330.length); i++)
            {
               var c:int = int(p.var_13330[i]);
               f = i == 0 ? c : f + Math.max(1,c);
               casts.push({"frame":f,"cast":i,"entry":p.var_6679 != null && i < int(p.var_6679.length) ? int(p.var_6679[i]) : i});
            }
         }
         var recover:Number = p != null ? Number(p.var_6131) + Number(p.var_13412) : 0;
         var end:int = f + (isNaN(recover) ? 0 : int(Math.floor(Math.max(0,recover))));
         return {"casts":casts,"end":Math.max(casts.length != 0 ? f + 1 : 1,end)};
      }

      public static function castAt(tl:Object, f:int) : Object
      {
         if(tl != null)
         {
            for each(var c:Object in tl.casts)
            {
               if(int(c.frame) == f)
               {
                  return c;
               }
            }
         }
         return null;
      }

      public static function phase(tl:Object, f:int) : String
      {
         if(castAt(tl,f) != null)
         {
            return "ACTIVE";
         }
         return tl == null || tl.casts.length == 0 || f < int(tl.casts[0].frame) ? "STARTUP" :
            (f > int(tl.casts[tl.casts.length - 1].frame) ? "RECOVERY" : "BETWEEN HITS");
      }

      public function play(on:Boolean) : void
      {
         if(on == playing)
         {
            return;
         }
         playing = on;
         if(on)
         {
            lastStep = getTimer();
            addEventListener(Event.ENTER_FRAME,tick);
         }
         else
         {
            removeEventListener(Event.ENTER_FRAME,tick);
         }
      }

      private function tick(e:Event) : void
      {
         if(line == null || getTimer() - lastStep < PLAY_MS)
         {
            return;
         }
         lastStep = getTimer();
         frame = frame < 0 || frame >= int(line.end) - 1 ? 0 : frame + 1;
         paint();
         if(onFrame != null)
         {
            onFrame(frame);
         }
      }

      public static function parts(p:PowerType) : Array
      {
         var out:Array = [];
         if(p == null || p.var_13330 == null)
         {
            return out;
         }
         var seen:Object = {};
         var method:int = int(p.var_8335);
         for(var i:int = 0; i < int(p.var_13330.length); i++)
         {
            var entry:int = p.var_6679 != null && i < int(p.var_6679.length) ? int(p.var_6679[i]) : i;
            if(seen[entry])
            {
               continue;
            }
            var first:uint = p.method_1416(i);
            var count:uint = p.method_6801(i);
            var shapes:Array = [];
            for(var s:uint = first; s < first + count; s++)
            {
               if(p.var_6883 == null || s >= uint(p.var_6883.length))
               {
                  break;
               }
               var sx:Number = method == 3 ? 0 : Number(p.var_7762[s]);
               var sy:Number = method == 3 ? 0 : Number(p.var_9003[s]);
               if(method == 13)
               {
                  sx -= Number(p.var_7762[first]);
                  sy -= Number(p.var_9003[first]);
               }
               shapes.push({"x":sx,"y":sy,"rx":Number(p.var_6883[s]),"ry":Number(p.var_12276[s])});
            }
            if(shapes.length != 0)
            {
               seen[entry] = true;
               out.push({"entry":entry,"cast":i,"shapes":shapes});
            }
         }
         return out;
      }

      public static function hurtbox() : Object
      {
         try
         {
            var d:Object = Object(class_123).var_3204;
            if(d != null)
            {
               var hh:Number = Number(d.var_2831) * 0.5;
               var off:Point = drawnOffset();
               return {"x":Number(d.var_15379) + off.x,"y":Number(d.var_34) - hh + off.y,"rx":Number(d.var_7160) * 0.5,"ry":hh};
            }
         }
         catch(e:Error)
         {
         }
         return null;
      }

      public static function drawnOffset() : Point
      {
         var legend:Object = player();
         if(legend != null)
         {
            try
            {
               var at:Object = legend.var_10228;
               var dx:Number = Number(at.method_113(legend.var_5109)) - Number(at.method_113(legend.var_6005));
               var dy:Number = Number(at.method_113(legend.var_1217)) - Number(at.method_113(legend.var_4126));
               if(!isNaN(dx) && !isNaN(dy) && Math.abs(dx) <= 400 && Math.abs(dy) <= 400)
               {
                  return new Point(dx,dy);
               }
            }
            catch(e:Error)
            {
            }
         }
         return new Point(0,0);
      }

      private function animFrame(f:int) : int
      {
         if(f < 0)
         {
            f = line != null && line.casts.length != 0 ? int(line.casts[0].frame) : 0;
         }
         if(legend != null && legend.frames != null && f < legend.frames.length)
         {
            return int(legend.frames[f]);
         }
         return int(f * Number(class_51.var_12355));
      }

      public static function gameFrames(p:PowerType, who:Object) : Array
      {
         if(p == null || who == null)
         {
            return null;
         }
         try
         {
            var end:int = int(timeline(p).end);
            var cast:class_5 = new class_5(ScreenManager.owner,p,who as class_123,1);
            cast.var_13001 = 1;
            cast.var_402 = uint(1 + end);
            cast.method_6427();
            var map:Array = cast.var_6191;
            var out:Array = [];
            var at:Number = 0;
            for(var s:int = 0; s < end; s++)
            {
               if(map != null && Number(map[s]) > 0)
               {
                  at = Number(map[s]);
               }
               out.push(int(Math.floor(at)));
            }
            return out;
         }
         catch(e:Error)
         {
            ErrorLog.write("move editor: no frame map for the legend: " + e);
         }
         return null;
      }

      private static function player() : Object
      {
         try
         {
            var players:* = ScreenManager.owner.var_7050;
            return players != null && players.length > 0 ? players[0] : null;
         }
         catch(e:Error)
         {
         }
         return null;
      }

      public function draw(all:Array, part:int, shape:int, tl:Object = null, at:int = -1) : void
      {
         shown = all;
         shownPart = part;
         shownShape = shape;
         line = tl;
         frame = at;
         var hurt:Object = hurtbox();
         var boxes:Array = hurt != null ? [hurt] : [{"x":0,"y":-50,"rx":20,"ry":50}];
         for each(var pt:Object in all)
         {
            boxes = boxes.concat(pt.shapes);
         }
         var minX:Number = 0;
         var maxX:Number = 0;
         var minY:Number = 0;
         var maxY:Number = 0;
         for each(var b:Object in boxes)
         {
            minX = Math.min(minX,b.x - b.rx);
            maxX = Math.max(maxX,b.x + b.rx);
            minY = Math.min(minY,b.y - b.ry);
            maxY = Math.max(maxY,b.y + b.ry);
         }
         var pad:Number = 40;
         var drawH:Number = h - STRIP_H;
         scale = Math.min(2,Math.min((w - pad * 2) / Math.max(1,maxX - minX),(drawH - pad * 2) / Math.max(1,maxY - minY)));
         ox = w / 2 - (minX + maxX) / 2 * scale;
         oy = drawH / 2 - (minY + maxY) / 2 * scale;
         if(doll != null)
         {
            doll.clear();
            doll = null;
         }
         if(legend != null && legend.anim != null)
         {
            var off:Point = drawnOffset();
            doll = LegendDoll.build(legendLayer,legend.costume,legend.scheme,legend.anim,[legend.anim],legend.item,
               ox + off.x * scale,oy + off.y * scale,scale,"move editor");
         }
         paint();
      }

      private function paint() : void
      {
         var all:Array = shown;
         var part:int = shownPart;
         var shape:int = shownShape;
         var hurt:Object = hurtbox();
         var firing:Object = frame >= 0 ? castAt(line,frame) : null;
         var g:* = art.graphics;
         g.clear();
         g.lineStyle(1,UiKit.LINE);
         g.moveTo(8,oy);
         g.lineTo(w - 8,oy);
         g.moveTo(ox,8);
         g.lineTo(ox,h - STRIP_H - 8);
         g.lineStyle();
         if(hurt != null)
         {
            fill(g,hurt,HURT,0.5);
         }
         picked = null;
         for(var i:int = 0; i < all.length; i++)
         {
            if(frame >= 0 && (firing == null || int(firing.entry) != int(all[i].entry)))
            {
               continue;
            }
            var c:uint = COLORS[uint(firing != null ? firing.cast : all[i].cast) % 3];
            for(var s:int = 0; s < all[i].shapes.length; s++)
            {
               fill(g,all[i].shapes[s],c,i == part || frame >= 0 ? 0.55 : 0.14);
               if(i == part && s == shape)
               {
                  picked = all[i].shapes[s];
               }
            }
         }
         drawHandles(picked);
         paintStrip(firing);
         if(doll != null)
         {
            doll.pose(animFrame(frame));
         }
      }

      public function legendState() : String
      {
         return legend == null || legend.anim == null ? "none" : legend.anim + (doll == null ? " (no doll)" : doll.anim != null ?
            " frame " + animFrame(frame) + (legend.frames != null ? "" : " (no game frame map)") : " (not on this skin)");
      }

      private function paintStrip(firing:Object) : void
      {
         var g:* = strip.graphics;
         g.clear();
         if(line == null)
         {
            label.text = "";
            return;
         }
         var end:int = int(line.end);
         var x0:Number = 12;
         var y0:Number = h - STRIP_H;
         var cw:Number = (w - 24) / Math.max(1,end);
         var gap:Number = cw > 4 ? 1 : 0;
         var partEntry:int = shownPart >= 0 && shownPart < shown.length ? int(shown[shownPart].entry) : -1;
         for(var f:int = 0; f < end; f++)
         {
            var c:Object = castAt(line,f);
            var color:uint = c != null ? COLORS[uint(c.cast) % 3] : (phase(line,f) == "RECOVERY" ? 3158080 : 6974072);
            g.beginFill(color,c != null && frame < 0 && int(c.entry) != partEntry ? 0.45 : 1);
            g.drawRect(x0 + f * cw + gap,y0,Math.max(1,cw - gap * 2),14);
            g.endFill();
         }
         if(frame >= 0)
         {
            g.lineStyle(2,UiKit.WHITE);
            g.drawRect(x0 + frame * cw,y0 - 2,Math.max(2,cw),18);
            g.lineStyle();
         }
         var startup:int = line.casts.length != 0 ? int(line.casts[0].frame) : 0;
         label.text = (frame < 0 ? "ALL PARTS" : "FRAME " + (frame + 1) + " OF " + end + "   " + phase(line,frame) +
            (firing != null ? " (PART " + (partOf(firing) + 1) + ")" : "")) + "      FIRST ACTIVE FRAME " + (startup + 1) + ", " +
            end + " FRAMES";
      }

      private function partOf(c:Object) : int
      {
         for(var i:int = 0; i < shown.length; i++)
         {
            if(int(shown[i].entry) == int(c.entry))
            {
               return i;
            }
         }
         return -1;
      }

      private function fill(g:*, b:Object, color:uint, alpha:Number) : void
      {
         var rx:Number = b.rx * scale;
         var ry:Number = b.ry * scale;
         g.beginFill(color,alpha);
         g.drawRoundRect(ox + b.x * scale - rx,oy + b.y * scale - ry,rx * 2,ry * 2,Math.min(rx,ry) * 2);
         g.endFill();
      }

      private function drawHandles(b:Object) : void
      {
         var g:* = handles.graphics;
         g.clear();
         if(b == null)
         {
            return;
         }
         var cx:Number = ox + b.x * scale;
         var cy:Number = oy + b.y * scale;
         g.lineStyle(2,UiKit.WHITE);
         g.drawRoundRect(cx - b.rx * scale,cy - b.ry * scale,b.rx * scale * 2,b.ry * scale * 2,Math.min(b.rx,b.ry) * scale * 2);
         g.lineStyle();
         g.beginFill(UiKit.WHITE);
         g.drawCircle(cx,cy,6);
         g.drawRect(cx + b.rx * scale - 6,cy + b.ry * scale - 6,12,12);
         g.endFill();
      }

      private function down(e:MouseEvent) : void
      {
         if(picked == null || stage == null)
         {
            return;
         }
         var cx:Number = ox + picked.x * scale;
         var cy:Number = oy + picked.y * scale;
         var corner:Point = new Point(cx + picked.rx * scale,cy + picked.ry * scale);
         if(Point.distance(new Point(mouseX,mouseY),corner) <= 14)
         {
            dragging = "size";
         }
         else if(Math.abs(mouseX - cx) <= picked.rx * scale + 6 && Math.abs(mouseY - cy) <= picked.ry * scale + 6)
         {
            dragging = "move";
         }
         else
         {
            return;
         }
         grabbed = new Point(mouseX,mouseY);
         start = {"x":picked.x,"y":picked.y,"rx":picked.rx,"ry":picked.ry};
         stage.addEventListener(MouseEvent.MOUSE_MOVE,moved);
         stage.addEventListener(MouseEvent.MOUSE_UP,up);
         e.stopPropagation();
      }

      private function moved(e:MouseEvent) : void
      {
         if(dragging == null || picked == null)
         {
            return;
         }
         var dx:Number = Math.round((mouseX - grabbed.x) / scale);
         var dy:Number = Math.round((mouseY - grabbed.y) / scale);
         if(dragging == "move")
         {
            picked.x = start.x + dx;
            picked.y = start.y + dy;
         }
         else
         {
            picked.rx = Math.max(1,start.rx + dx);
            picked.ry = Math.max(1,start.ry + dy);
         }
         drawHandles(picked);
      }

      private function up(e:MouseEvent) : void
      {
         if(stage != null)
         {
            stage.removeEventListener(MouseEvent.MOUSE_MOVE,moved);
            stage.removeEventListener(MouseEvent.MOUSE_UP,up);
         }
         var was:String = dragging;
         dragging = null;
         if(was != null && picked != null && onDrag != null &&
            (picked.x != start.x || picked.y != start.y || picked.rx != start.rx || picked.ry != start.ry))
         {
            onDrag(picked.x,picked.y,picked.rx,picked.ry);
         }
      }

      public function dispose() : void
      {
         play(false);
         if(stage != null)
         {
            stage.removeEventListener(MouseEvent.MOUSE_MOVE,moved);
            stage.removeEventListener(MouseEvent.MOUSE_UP,up);
         }
         dragging = null;
         if(doll != null)
         {
            doll.clear();
            doll = null;
         }
      }
   }
}
