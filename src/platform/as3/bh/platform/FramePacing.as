package bh.platform
{
   import bh.platform.net.P2PSession;
   import bh.platform.net.Smoothing;
   import flash.utils.Dictionary;

   public final class FramePacing
   {
      public static const KEY:uint = 122;
      public static const MAX_MOVE:Number = 260;
      public static const MAX_CAMERA:Number = 500;
      public static const MAX_ZOOM:Number = 1.3;

      private static var core:Object = null;
      private static var entries:Dictionary = new Dictionary();
      private static var active:Vector.<PacedNode> = new Vector.<PacedNode>();
      private static var spare:Vector.<PacedNode> = new Vector.<PacedNode>();
      private static var stamp:uint = 0;
      private static var stepped:Boolean = false;
      private static var alpha:Number = 0;
      private static var rollback:Boolean = false;
      private static var modified:Boolean = false;
      private static var frames:uint = 0;
      private static var steps:uint = 0;
      private static var offStep:uint = 0;
      public static var on:Boolean = false;

      public function FramePacing()
      {
      }

      public static function init() : void
      {
         on = ModSettings.flag("framePacing",true);
         Hooks.frameStarting.add(restore);
         Hooks.frameRendering.add(onRender);
         Hooks.keyDown.add(onKey);
      }

      private static function onKey(event:Object) : Boolean
      {
         if(event == null || uint(event.keyCode) != KEY || event.ctrlKey || event.altKey || event.shiftKey)
         {
            return false;
         }
         on = !on;
         ModSettings.setFlag("framePacing",on);
         restore();
         clear();
         report();
         Platform.log("frame pacing " + (on ? "on" : "off") + " (F11)");
         return true;
      }

      private static function game() : Object
      {
         if(core == null)
         {
            try
            {
               core = ScreenManager.owner;
            }
            catch(e:Error)
            {
            }
         }
         return core;
      }

      private static function clear() : void
      {
         entries = new Dictionary();
         active.length = 0;
         spare.length = 0;
      }

      private static function restore() : void
      {
         if(!modified)
         {
            return;
         }
         modified = false;
         for(var i:int = 0; i < active.length; i++)
         {
            var n:PacedNode = active[i];
            if(n.drawn)
            {
               n.node.x = n.cx;
               n.node.y = n.cy;
               if(n.kind == PacedNode.CAMERA)
               {
                  n.node.scaleX = n.csx;
                  n.node.scaleY = n.csy;
               }
               n.drawn = false;
            }
         }
      }

      private static function onRender() : void
      {
         if(!on)
         {
            return;
         }
         var g:Object = game();
         if(g == null || !paced(g))
         {
            if(active.length > 0)
            {
               restore();
               clear();
               report();
            }
            return;
         }
         try
         {
            var matchTime:Boolean = Boolean(g.var_10934);
            var now:Number = matchTime ? Number(g.var_12659) : Number(g.var_11938);
            var before:Number = matchTime ? Number(g.var_13849) : Number(g.var_1171);
            stepped = Math.floor(now / 16) != Math.floor(before / 16);
            alpha = (now % 16) / 16;
            frames++;
            if(stepped)
            {
               steps++;
            }
            rollback = P2PSession.rollbackOn;
            if(rollback)
            {
               Smoothing.prepare();
            }
            stamp++;
            var t:Vector.<PacedNode> = spare;
            spare = active;
            active = t;
            active.length = 0;
            pace(g.levelLayer3D,PacedNode.CAMERA);
            var players:Object = g.var_7050;
            for(var i:int = 0; i < int(players.length); i++)
            {
               var body:Object = players[i].var_11807 != null ? players[i].var_11807.mTheDO3D : null;
               if(body != null)
               {
                  entry(body).legend = stamp;
               }
            }
            layer(g.var_580);
            layer(g.var_479);
            layer(g.var_6167);
            layer(g.var_11193);
            layer(g.worldUILayer3D);
            for(i = 0; i < spare.length; i++)
            {
               var old:PacedNode = spare[i];
               if(old.seen != stamp && old.node != null)
               {
                  delete entries[old.node];
                  old.node = null;
               }
            }
            spare.length = 0;
         }
         catch(e:Error)
         {
            Platform.log("frame pacing stopped: " + e.getStackTrace());
            on = false;
            restore();
            clear();
         }
      }

      private static function paced(g:Object) : Boolean
      {
         var state:uint = uint(g.gameState);
         var flags:uint = uint(g.var_3595);
         return state == 6 || state == 5 && (flags & 1024) != 0 || state == 3 && (flags & 32) != 0;
      }

      private static function report() : void
      {
         if(frames > 0)
         {
            Platform.log("frame pacing: " + frames + " frames, " + steps + " with steps, " + offStep +
               " moves between steps");
         }
         frames = 0;
         steps = 0;
         offStep = 0;
      }

      private static function entry(node:Object) : PacedNode
      {
         var n:PacedNode = entries[node];
         if(n == null)
         {
            n = new PacedNode();
            n.node = node;
            n.cx = Number(node.x);
            n.cy = Number(node.y);
            n.csx = Number(node.scaleX);
            n.csy = Number(node.scaleY);
            entries[node] = n;
            spare.push(n);
         }
         return n;
      }

      private static function layer(l:Object) : void
      {
         var children:Object = l != null ? l.var_12216 : null;
         for(var c:int = 0; children != null && c < int(children.length); c++)
         {
            var child:Object = children[c];
            var n:PacedNode = entries[child];
            var legend:Boolean = n != null && n.legend == stamp;
            pace(child,legend ? PacedNode.LEGEND : PacedNode.OBJECT);
         }
      }

      private static function pace(node:Object, kind:int) : void
      {
         var n:PacedNode = entry(node);
         if(n.seen == stamp)
         {
            return;
         }
         n.seen = stamp;
         n.kind = kind;
         active.push(n);
         var x:Number = Number(node.x);
         var y:Number = Number(node.y);
         var sx:Number = Number(node.scaleX);
         var sy:Number = Number(node.scaleY);
         if(stepped)
         {
            n.px = n.cx;
            n.py = n.cy;
            n.psx = n.csx;
            n.psy = n.csy;
            n.hasPrev = true;
         }
         else if(x != n.cx || y != n.cy || sx != n.csx || sy != n.csy)
         {
            n.hasPrev = false;
            offStep++;
         }
         n.cx = x;
         n.cy = y;
         n.csx = sx;
         n.csy = sy;
         var ox:Number = 0;
         var oy:Number = 0;
         if(rollback && kind == PacedNode.LEGEND)
         {
            ox = Smoothing.offsetX(node);
            oy = Smoothing.offsetY(node);
         }
         if(!n.hasPrev || jumped(n))
         {
            if(ox == 0 && oy == 0)
            {
               return;
            }
            node.x = x + ox;
            node.y = y + oy;
         }
         else
         {
            node.x = n.px + (x - n.px) * alpha + ox;
            node.y = n.py + (y - n.py) * alpha + oy;
            if(kind == PacedNode.CAMERA)
            {
               node.scaleX = n.psx + (sx - n.psx) * alpha;
               node.scaleY = n.psy + (sy - n.psy) * alpha;
            }
         }
         n.drawn = true;
         modified = true;
      }

      private static function jumped(n:PacedNode) : Boolean
      {
         var dx:Number = n.cx - n.px;
         var dy:Number = n.cy - n.py;
         if(n.kind == PacedNode.CAMERA)
         {
            var zoom:Number = n.psx > 0 ? n.csx / n.psx : 1;
            return dx * dx + dy * dy > MAX_CAMERA * MAX_CAMERA || zoom > MAX_ZOOM || zoom < 1 / MAX_ZOOM;
         }
         return dx * dx + dy * dy > MAX_MOVE * MAX_MOVE;
      }
   }
}
