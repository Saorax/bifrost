package bh.platform
{
   import flash.display.MovieClip;
   import flash.display.Shape;
   import flash.display.Sprite;
   import flash.text.TextField;

   public class PostMatchStatsWindow extends BigWindow
   {
      private static const TABS:Array = ["SUMMARY","DAMAGE","ATTACKS"];
      override protected function get fullPage() : Boolean
      {
         return true;
      }

      private function get WIDTH() : Number
      {
         return area.width;
      }

      public var stats:Object;
      public var focusBefore:ScreenBase;

      public function PostMatchStatsWindow(core:GameCore)
      {
         super(core);
      }

      override protected function get title() : String
      {
         return "MATCH STATS";
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
         if(stats == null)
         {
            return "";
         }
         return (stats.mode != "" ? String(stats.mode).toUpperCase() + "   " : "") + clock(stats.length);
      }

      override protected function back() : void
      {
         Hide();
         try
         {
            if(focusBefore != null && focusBefore !== this && focusBefore.isActive)
            {
               ScreenBase.setFocus(focusBefore);
            }
         }
         catch(e:Error)
         {
         }
         focusBefore = null;
      }

      override protected function buildTab(i:int) : void
      {
         if(stats == null)
         {
            return;
         }
         switch(i)
         {
            case 0:
               buildSummary();
               break;
            case 1:
               buildDamage();
               break;
            case 2:
               buildAttacks();
         }
      }

      private function get players() : Array
      {
         return stats.players;
      }

      private function buildSummary() : void
      {
         var p:Sprite = panel(area.x,area.y,WIDTH,area.height);
         var labelW:Number = 230;
         var colW:Number = (WIDTH - labelW - 20) / players.length;
         var size:int = players.length > 4 ? 13 : 15;
         var x:Number;
         for(var c:int = 0; c < players.length; c++)
         {
            x = labelW + c * colW;
            var head:TextField = UiKit.fit(UiKit.text(p,String(players[c].name).toUpperCase(),x + colW / 2 + 15,10,size + 1,
               players[c].color,UiKit.XBOLD,0,true),colW - 44);
            head.x = x + colW / 2 + 15 - head.width / 2;
            UiKit.icon(p,portrait(players[c].hero),head.x - 32,6,28);
         }
         var rows:Array = [
            ["LEGEND",function(pl:Object):* { return pl.legend; },0],
            ["DAMAGE DEALT",function(pl:Object):* { return Math.floor(pl.dealt); },1],
            ["DAMAGE TAKEN",function(pl:Object):* { return Math.floor(pl.taken); },-1],
            ["KOS",function(pl:Object):* { return pl.kos; },1],
            ["FALLS",function(pl:Object):* { return pl.falls; },-1],
            ["SELF-KOS",function(pl:Object):* { return pl.sds; },-1],
            ["DODGES (IN THE AIR)",function(pl:Object):* { return pl.dodges + " (" + pl.airDodges + ")"; },0],
            ["DASHES",function(pl:Object):* { return pl.dashes; },0],
            ["JUMPS",function(pl:Object):* { return pl.jumps; },0],
            ["TIME IN THE AIR (ON WALLS)",function(pl:Object):* { return percent(pl.air,pl.air + pl.ground + pl.wall) + " (" +
               percent(pl.wall,pl.air + pl.ground + pl.wall) + ")"; },0],
            ["CLASHES",function(pl:Object):* { return pl.clashes; },0],
            ["COMBOS (2+ HITS)",function(pl:Object):* { return pl.combos; },1],
            ["BEST COMBO",function(pl:Object):* { return pl.best != null ? pl.best.hits + " hits, " +
               Math.floor(pl.best.damage) : "-"; },0]];
         var y:Number = 46;
         for(var r:int = 0; r < rows.length; r++)
         {
            if(r % 2 == 0)
            {
               UiKit.rect(p,10,y - 3,WIDTH - 20,26,UiKit.BODY);
            }
            UiKit.text(p,rows[r][0],22,y,14,UiKit.GREY,UiKit.XBOLD);
            var values:Array = [];
            for(c = 0; c < players.length; c++)
            {
               values.push(rows[r][1](players[c]));
            }
            var best:Number = NaN;
            if(rows[r][2] != 0 && players.length > 1)
            {
               for each(var v:* in values)
               {
                  best = isNaN(best) ? v : (rows[r][2] > 0 ? Math.max(best,v) : Math.min(best,v));
               }
               var ties:int = 0;
               for each(v in values)
               {
                  ties += v == best ? 1 : 0;
               }
               if(ties == values.length)
               {
                  best = NaN;
               }
            }
            for(c = 0; c < players.length; c++)
            {
               x = labelW + c * colW;
               UiKit.fit(UiKit.text(p,String(values[c]),x + colW / 2,y,size,values[c] === best ? UiKit.TEAL : UiKit.WHITE,
                  UiKit.BOLD,0,true),colW - 8);
            }
            y += 27;
         }
         y += 10;
         var cell:Number = Math.floor(Math.min(56,(colW - 24) / 3,(area.height - y - 34) / 3));
         if(cell < 14)
         {
            return;
         }
         UiKit.text(p,"DODGE DIRECTIONS",22,y + cell * 1.5 - 9,14,UiKit.GREY,UiKit.XBOLD);
         for(c = 0; c < players.length; c++)
         {
            x = labelW + c * colW;
            dodgeGrid(p,players[c],x + colW / 2 - cell * 1.5,y,cell);
         }
      }

      private static function dodgeGrid(p:Sprite, pl:Object, gx:Number, gy:Number, cell:Number) : void
      {
         var grid:Array = pl.dodgeGrid != null ? pl.dodgeGrid : [0,0,0,0,0,0,0,0,0];
         var most:int = 0;
         for each(var v:int in grid)
         {
            most = Math.max(most,v);
         }
         for(var k:int = 0; k < 9; k++)
         {
            var x:Number = gx + (k % 3) * cell;
            var y:Number = gy + int(k / 3) * cell;
            UiKit.rect(p,x + 1,y + 1,cell - 2,cell - 2,heat(most > 0 ? grid[k] / most : 0,uint(pl.color)));
            var t:TextField = UiKit.text(p,String(grid[k]),x + cell / 2,y + cell / 2 - cell * 0.2,Math.max(11,int(cell * 0.3)),
               UiKit.WHITE,UiKit.XBOLD,0,true);
            t.x = x + cell / 2 - t.width / 2;
         }
      }

      private static function portrait(hero:String) : MovieClip
      {
         try
         {
            var clip:MovieClip = hero ? class_687.method_1714("a_PortraitIconAnimations","UI_Icons") : null;
            for each(var l:Object in clip != null ? clip.currentLabels : [])
            {
               if(l.name == hero)
               {
                  clip.gotoAndStop(hero);
                  clip.stopAllMovieClips();
                  return clip;
               }
            }
         }
         catch(e:Error)
         {
         }
         return null;
      }

      private static function weaponIcon(weapon:String) : MovieClip
      {
         try
         {
            var clip:MovieClip = weapon ? class_687.method_1714("a_WeaponIcon_" + weapon,"UI_Icons") : null;
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

      private static function words(s:String) : String
      {
         return s.replace(/([a-z])([A-Z])/g,"$1 $2");
      }

      private static function moveName(s:String) : String
      {
         var dirs:Object = {"n":"Neutral ","s":"Side ","d":"Down "};
         if(s.length > 1 && dirs[s.charAt(0)] != null && s.charAt(1) >= "A" && s.charAt(1) <= "Z")
         {
            s = dirs[s.charAt(0)] + s.substr(1);
         }
         return words(s);
      }

      private static function percent(part:Number, all:Number) : String
      {
         return all > 0 ? Math.round(part * 100 / all) + "%" : "-";
      }

      private static function clock(ms:Number) : String
      {
         var s:int = int(ms / 1000);
         var sec:int = s % 60;
         return int(s / 60) + ":" + (sec < 10 ? "0" : "") + sec;
      }

      private function buildDamage() : void
      {
         var p:Sprite = panel(area.x,area.y,WIDTH,area.height);
         var gx:Number = 70;
         var gy:Number = 48;
         var gw:Number = WIDTH - gx - 30;
         var gh:Number = area.height - gy - 44;
         var points:int = Math.max(2,stats.points);
         var top:Number = 100;
         for each(var pl:Object in players)
         {
            for each(var d:Number in pl.damage)
            {
               top = Math.max(top,d);
            }
         }
         top = Math.ceil(top / 50) * 50;
         var kx:Number = gx;
         for each(pl in players)
         {
            UiKit.rect(p,kx,16,14,14,pl.color,3);
            UiKit.icon(p,portrait(pl.hero),kx + 20,8,28);
            var name:TextField = UiKit.text(p,String(pl.name).toUpperCase(),kx + 54,13,14,UiKit.WHITE,UiKit.BOLD);
            kx += name.width + 84;
         }
         UiKit.text(p,"DAMAGE",gx + gw,13,13,UiKit.GREY,UiKit.XBOLD).x = gx + gw - 60;
         var grid:Shape = new Shape();
         p.addChild(grid);
         grid.graphics.lineStyle(1,UiKit.LINE);
         var step:Number = top > 300 ? 100 : 50;
         for(var v:Number = 0; v <= top; v += step)
         {
            var ly:Number = gy + gh - v / top * gh;
            grid.graphics.moveTo(gx,ly);
            grid.graphics.lineTo(gx + gw,ly);
            UiKit.text(p,String(v),gx - 10,ly - 9,12,UiKit.GREY,UiKit.BOLD).x = gx - 12 - String(v).length * 7;
         }
         var bucket:Number = stats.bucket;
         var span:Number = points * bucket;
         var tick:Number = span > 360000 ? 60000 : 30000;
         for(var t:Number = 0; t <= span; t += tick)
         {
            var lx:Number = gx + t / span * gw;
            grid.graphics.moveTo(lx,gy);
            grid.graphics.lineTo(lx,gy + gh);
            UiKit.text(p,clock(t),lx,gy + gh + 6,12,UiKit.GREY,UiKit.BOLD,0,true);
         }
         for each(pl in players)
         {
            var line:Shape = new Shape();
            p.addChild(line);
            line.graphics.lineStyle(2.5,pl.color);
            var dots:Array = [];
            var prev:Number = 0;
            for(var k:int = 0; k < pl.damage.length; k++)
            {
               var x:Number = gx + (k + 1) * bucket / span * gw;
               var y:Number = gy + gh - Number(pl.damage[k]) / top * gh;
               if(k == 0)
               {
                  line.graphics.moveTo(gx,gy + gh);
               }
               if(prev > 0 && pl.damage[k] == 0)
               {
                  dots.push([x,gy + gh - prev / top * gh]);
               }
               line.graphics.lineTo(x,y);
               prev = pl.damage[k];
            }
            for each(var dot:Array in dots)
            {
               line.graphics.lineStyle(2,UiKit.WHITE);
               line.graphics.beginFill(pl.color);
               line.graphics.drawCircle(dot[0],dot[1],5);
               line.graphics.endFill();
            }
         }
      }

      private var columns:Array = [];

      private function buildAttacks() : void
      {
         var n:int = players.length;
         var colW:Number = WIDTH / n;
         var size:int = n > 4 ? 12 : 14;
         var rowH:Number = size * 2 + 10;
         columns = [];
         for(var c:int = 0; c < n; c++)
         {
            var pl:Object = players[c];
            var p:Sprite = panel(area.x + c * colW,area.y,colW - 10,area.height);
            UiKit.icon(p,portrait(pl.hero),10,5,28);
            UiKit.fit(UiKit.text(p,String(pl.name).toUpperCase(),44,8,15,pl.color,UiKit.XBOLD),colW - 62);
            var content:Sprite = scroller(p,0,38,colW - 10,area.height - 44);
            var first:int = items.length;
            var y:Number = 0;
            for each(var a:Object in pl.attacks)
            {
               if(a.damage <= 0 && a.hits == 0)
               {
                  continue;
               }
               var row:Sprite = new Sprite();
               row.y = y;
               content.addChild(row);
               var label:String = (a.weapon != "" ? words(a.weapon) + " " : "") + moveName(a.name);
               UiKit.icon(row,weaponIcon(a.weapon),10,2,size * 2);
               UiKit.fit(UiKit.text(row,label,size * 2 + 16,0,size,UiKit.WHITE,UiKit.BOLD),colW - size * 2 - 44);
               UiKit.text(row,Math.floor(a.damage) + " damage, " + a.hits + (a.hits == 1 ? " hit" : " hits") +
                  (a.kos > 0 ? ", " + a.kos + " KO" : "") + (a.uses > 0 ? "  (used " + a.uses + "x)" : ""),size * 2 + 16,size + 3,size - 2,
                  UiKit.GREY,UiKit.MEDIUM);
               items.push({"sprite":row,"width":colW - 22,"height":rowH - 2,"parent":content});
               y += rowH;
            }
            columns.push([first,items.length - first]);
            if(items.length == first)
            {
               UiKit.text(content,"No hits.",12,0,size,UiKit.GREY,UiKit.BOLD);
            }
         }
      }

      override protected function useItem(it:Object, dir:int) : void
      {
         if(tab == 2 && dir != 0)
         {
            for(var c:int = 0; c < columns.length; c++)
            {
               if(focus >= columns[c][0] && focus < columns[c][0] + columns[c][1])
               {
                  for(var to:int = c + dir; to >= 0 && to < columns.length; to += dir)
                  {
                     if(columns[to][1] > 0)
                     {
                        focus = columns[to][0] + Math.min(focus - columns[c][0],columns[to][1] - 1);
                        paintFocus();
                        return;
                     }
                  }
                  return;
               }
            }
            return;
         }
         super.useItem(it,dir);
      }

      private static function heat(f:Number, color:uint) : uint
      {
         var lo:Array = [0x10,0x1E,0x2C];
         var hi:Array = [color >> 16 & 0xFF,color >> 8 & 0xFF,color & 0xFF];
         var r:int = lo[0] + (hi[0] - lo[0]) * f;
         var g:int = lo[1] + (hi[1] - lo[1]) * f;
         var b:int = lo[2] + (hi[2] - lo[2]) * f;
         return r << 16 | g << 8 | b;
      }
   }
}
