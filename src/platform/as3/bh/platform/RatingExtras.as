package bh.platform
{
   import bh.platform.net.ServerStats;
   import flash.display.Bitmap;
   import flash.display.BitmapData;
   import flash.display.DisplayObject;
   import flash.display.DisplayObjectContainer;
   import flash.display.MovieClip;
   import flash.display.PixelSnapping;
   import flash.display.Shape;
   import flash.display.Sprite;
   import flash.display.Stage;
   import flash.geom.Rectangle;
   import flash.text.TextField;
   import flash.utils.Dictionary;
   import flash.utils.getTimer;

   public final class RatingExtras
   {
      private static const RANKS:Array = ["TIN","BRONZE","SILVER","GOLD","PLATINUM","DIAMOND"];
      private static const BANNERS:Array = ["Tin","Bronze","Silver","Gold","Platinum","Diamond"];
      private static const RANK_SPAN:int = 500;
      private static const STEP:int = 100;
      private static const VALHALLAN:int = 3000;

      private static const EDGE:uint = 0x2C5A80;
      private static const FILL:uint = 0x07142A;
      private static const FILL_TOP:uint = 0x0D2240;
      private static const ACCENT:uint = 0x4FE3D0;
      private static const LABEL:uint = 0x7F9AB3;
      private static const TRACK:uint = 0x1A2B45;
      private static const WIN:uint = 0x5BD67A;
      private static const LOSS:uint = 0xF0646A;
      private static const GOLD:uint = 0xFFD45C;

      public static var change:Object = null;
      public static var seriesBefore:Object = null;

      private static var layer:Sprite = null;
      private static var drawnKey:String = "";

      private static var drawnSig:String = "";

      private static var retries:int = 0;
      private static var registered:Boolean = false;
      private static var hidden:Array = [];
      private static var boxClips:Dictionary = new Dictionary(true);
      private static var incomplete:Boolean = false;

      private static var lobbyCard:Object = null;
      private static var lobbyLegends:Array = null;
      private static var lobbyMates:Array = null;
      private static var lobbyName:String = null;

      public function RatingExtras()
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

      private static var previewUntil:int = 0;

      public static function preview(c:Object, ms:int) : void
      {
         change = c;
         previewUntil = getTimer() + ms;
      }

      public static function reset() : void
      {
         change = null;
         seriesBefore = null;
      }

      public static function series(q:Object, me:uint, them:uint) : void
      {
         seriesBefore = {"mine":uint(q.series != null ? q.series[me] || 0 : 0),"theirs":uint(q.series != null ? q.series[them] || 0 : 0)};
      }

      public static function tierName(rating:int) : String
      {
         if(rating >= VALHALLAN)
         {
            return "VALHALLAN";
         }
         var r:int = Math.max(0,rating);
         return RANKS[int(r / RANK_SPAN)] + " " + (5 - int((r % RANK_SPAN) / STEP));
      }

      private static function bannerTier(rating:int, placing:Boolean) : String
      {
         if(placing)
         {
            return "Unranked";
         }
         return rating >= VALHALLAN ? "Valhallan" : BANNERS[int(Math.max(0,rating) / RANK_SPAN)];
      }

      private static function toNext(rating:int) : String
      {
         if(rating >= VALHALLAN)
         {
            return "TOP RANK";
         }
         var next:int = (int(Math.max(0,rating) / STEP) + 1) * STEP;
         return (next - rating) + " TO " + tierName(next);
      }

      private static function winRate(wins:int, games:int) : String
      {
         return games > 0 ? Math.round(wins * 100 / games) + "%" : "-";
      }

      private static function signed(n:int) : String
      {
         return (n >= 0 ? "+" : "") + n;
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
         if(layer == null && hidden.length == 0 && drawnKey == "")
         {
            return;
         }
         if(layer != null && layer.parent != null)
         {
            layer.parent.removeChild(layer);
         }
         layer = null;
         drawnKey = "";
         fx = null;
         for each(var d:DisplayObject in hidden)
         {
            restore(d);
         }
         hidden = [];
      }

      private static function restore(d:DisplayObject) : void
      {
         var ui:Object = boxClips[d];
         d.visible = ui == null || ui.isActive;
         d.alpha = 1;
      }

      private static function hide(parts:Array) : void
      {
         for each(var d:DisplayObject in hidden)
         {
            if(parts.indexOf(d) < 0)
            {
               restore(d);
            }
         }
         hidden = [];
         for each(var p:DisplayObject in parts)
         {
            if(p != null)
            {
               p.visible = false;
               p.alpha = 0;
               hidden.push(p);
            }
         }
      }

      public static function get on() : Boolean
      {
         return ModSettings.flag("rankedOverlays",true);
      }

      public static function set on(v:Boolean) : void
      {
         ModSettings.setFlag("rankedOverlays",v);
      }

      private static function onFrame() : void
      {
         if(!on)
         {
            clear();
            return;
         }
         try
         {
            var s:Stage = stage();
            if(s == null)
            {
               return;
            }
            var elo:Object = ScreenManager.var_14957;
            var previewing:Boolean = previewUntil > 0 && getTimer() < previewUntil && change != null;
            if(previewing || elo != null && elo.isActive && change != null && change.after != null && elo.panelClip != null &&
               DisplayObject(elo.panelClip).stage != null)
            {
               if(!previewing)
               {
                  hide([DisplayObject(elo.panelClip)]);
               }
               draw(s,"elo",drawElo,elo != null && elo.panelClip != null ? Layers.screenOf(DisplayObject(elo.panelClip)) : null);
               animate();
               return;
            }
            var cs:Object = ScreenManager.var_4257;
            if(cs != null && cs.isActive && cs.var_13266 != null && cs.var_13266.var_9693 && cs.var_13266.var_4483 != null &&
               cs.var_13266.var_4483.stage != null)
            {
               var ladder:String = lobbyLadder(cs);
               var card:Object = ladder != null ? ServerStats.get("ranked:" + ladder) : null;
               var team:Object = ladder == "2v2" ? teamCard(cs) : null;
               if(team != null && team.rating != null)
               {
                  card = team;
               }
               if(card != null && card.rating != null)
               {
                  lobbyCard = card;
                  lobbyLegends = ladder == "1v1" ? legends(cs) : null;
                  lobbyMates = ladder == "2v2" && !card.team ? mates(cs,s) : null;
                  lobbyName = ladder;
                  var covers:Array = [DisplayObject(cs.var_13266.var_4483),cs.var_13266.var_7696 != null ? cs.var_13266.var_7696.clip : null];
                  var summaries:Array = [cs.mSeasonalSummary2v2_A,cs.mSeasonalSummary2v2_B];
                  for(var bi:int = 0; bi < 2; bi++)
                  {
                     if(ladder == "1v1" || card.team || mateKnown(bi))
                     {
                        covers.push(shownBox(summaries[bi]));
                     }
                  }
                  hide(covers);
                  draw(s,"lobby",drawLobby,Layers.screenOf(DisplayObject(cs.var_13266.var_4483)));
                  return;
               }
            }
            clear();
         }
         catch(e:Error)
         {
            clear();
         }
      }

      private static function mateKnown(i:int) : Boolean
      {
         var m:Object = lobbyMates != null ? lobbyMates[i] : null;
         return m != null && m.card != null && m.card.rating != null;
      }

      private static function shownBox(box:Object) : DisplayObject
      {
         if(box == null || box.var_4483 == null || box.var_6052 == null)
         {
            return null;
         }
         boxClips[box.var_4483] = box.var_6052;
         return box.var_6052.isActive ? DisplayObject(box.var_4483) : null;
      }

      private static function mates(cs:Object, s:Stage) : Array
      {
         var members:Object = cs.owner.var_6244.var_1751;
         if(members == null || members.length < 1)
         {
            return null;
         }
         var out:Array = [];
         var boxes:Array = [cs.mSeasonalSummary2v2_A,cs.mSeasonalSummary2v2_B];
         for(var i:int = 0; i < Math.min(2,members.length); i++)
         {
            var m:Object = members[i];
            var box:Object = boxes[i];
            var r:Rectangle = box != null && box.var_4483 != null && box.var_4483.stage != null ?
               DisplayObject(box.var_4483).getBounds(s) : null;
            var shown:String = m.var_6307 != null && m.var_6307.var_14792 ? String(m.var_6307.var_14792) : String(m.var_7572 || "");
            out.push({"name":shown,"card":ServerStats.get("ranked:2v2:" + uint(m.var_14656)),
               "rect":r != null ? [Math.round(r.x),Math.round(r.y),Math.round(r.width),Math.round(r.height)] : null});
         }
         return out;
      }

      private static function teamCard(cs:Object) : Object
      {
         var members:Object = cs.owner.var_6244.var_1751;
         if(members == null || members.length != 2)
         {
            return null;
         }
         for(var i:int = 0; i < 2; i++)
         {
            var id:uint = uint(members[i].var_14656);
            if(id != 0 && id != uint(cs.owner.var_14656))
            {
               return ServerStats.get("ranked:team:" + id);
            }
         }
         return null;
      }

      private static function lobbyLadder(cs:Object) : String
      {
         var pl:Object = cs.owner.var_6244.var_2390;
         if(pl == null || !pl.var_9135)
         {
            return null;
         }
         if(pl == class_301.PLAYLIST_RANKED1V1)
         {
            return "1v1";
         }
         if(pl == class_301.PLAYLIST_RANKED2V2)
         {
            return "2v2";
         }
         return null;
      }

      private static function legends(cs:Object) : Array
      {
         var core:Object = cs.owner;
         var best:Array = null;
         var picked:Array = null;
         try
         {
            var rows:Array = core.var_12691 as Array;
            for(var id:int = 0; rows != null && id < rows.length; id++)
            {
               var r:Object = rows[id];
               if(r != null && uint(r.var_4699) > 0 && (best == null || int(r.var_12895) > int(best[1])))
               {
                  best = [id,int(r.var_12895),int(r.var_14952),int(r.var_4699)];
               }
            }
            for(var slot:int = 0; slot < 4; slot++)
            {
               var p:Object = core.var_6244.method_8549(slot);
               if(p == null || p.var_5540 == null || p.var_5540.var_13881 == null)
               {
                  continue;
               }
               if(p.hasOwnProperty("var_14656") && uint(p.var_14656) != 0 && uint(p.var_14656) != uint(core.var_14656))
               {
                  continue;
               }
               var hero:Object = p.var_5540.var_13881;
               if(String(hero.mHeroName).toLowerCase() != "random")
               {
                  var hid:int = int(hero.var_12172);
                  var row:Object = rows != null && hid < rows.length ? rows[hid] : null;
                  picked = row != null && uint(row.var_4699) > 0 ? [hid,int(row.var_12895),int(row.var_14952),int(row.var_4699)] :
                     [hid,-1,0,0];
               }
               break;
            }
         }
         catch(e:Error)
         {
         }
         return [best,picked];
      }

      private static function covered() : Boolean
      {
         return BigWindow.anyOpen() || ScreenManager.var_638 != null && ScreenManager.var_638.isActive ||
            ScreenManager.var_13854 != null && ScreenManager.var_13854.isActive ||
            ScreenManager.var_10749 != null && ScreenManager.var_10749.isActive;
      }

      private static function draw(s:Stage, kind:String, painter:Function, holder:DisplayObjectContainer) : void
      {
         var objs:Array = kind == "elo" ? [change] : [lobbyCard];
         var small:String = "";
         if(kind == "elo")
         {
            small = seriesBefore == null ? "-" : seriesBefore.mine + "/" + seriesBefore.theirs;
         }
         else
         {
            small = lobbyName + ":" + JSON.stringify(lobbyLegends);
            for(var mi:int = 0; lobbyMates != null && mi < lobbyMates.length; mi++)
            {
               var m:Object = lobbyMates[mi];
               objs.push(m.card);
               small += "|" + m.name + ":" + m.rect;
            }
         }
         var key:String = kind + "@" + s.stageWidth + "x" + s.stageHeight + ":" + small;
         var sig:String = "";
         try
         {
            sig = JSON.stringify(objs);
         }
         catch(e:Error)
         {
            sig = String(Math.random());
         }
         var same:Boolean = key == drawnKey && sig == drawnSig;
         drawnSig = sig;
         retries = same ? retries + 1 : 0;
         if(same && layer != null && layer.parent != null && (!incomplete || retries % 10 != 0))
         {
            layer.visible = !covered();
            Layers.put(layer,holder,s);
            return;
         }
         if(layer != null && layer.parent != null)
         {
            layer.parent.removeChild(layer);
         }
         drawnKey = key;
         incomplete = false;
         layer = new Sprite();
         layer.mouseEnabled = layer.mouseChildren = false;
         painter(layer,s);
         layer.visible = !covered();
         Layers.put(layer,holder,s);
      }

      private static function panel(g:Sprite, x:Number, y:Number, w:Number, h:Number, sc:Number) : void
      {
         UiKit.rect(g,x - 2 * sc,y - 2 * sc,w + 4 * sc,h + 4 * sc,EDGE,16 * sc);
         UiKit.rect(g,x,y,w,h,FILL,14 * sc);
         UiKit.rect(g,x,y,w,46 * sc,FILL_TOP,14 * sc);
         UiKit.rect(g,x,y + 32 * sc,w,14 * sc,FILL_TOP);
         UiKit.rect(g,x,y + 46 * sc,w,2 * sc,EDGE);
      }

      private static function banner(g:Sprite, tier:String, rating:int, label:String, x:Number, y:Number, w:Number,
                                     sc:Number) : void
      {
         var size:int = int(w * 0.92);
         var b:Bitmap = LeaderboardWindow.tierBanner(tier,size,rating);
         if(b != null)
         {
            b.x = x + (w - b.width) / 2;
            b.y = y;
            g.addChild(b);
         }
         else
         {
            incomplete = true;
         }
         UiKit.text(g,label,x + w / 2,y + size + 4 * sc,15 * sc,0xFFFFFF,UiKit.XBOLD,0,true);
      }

      private static var fx:Object = null;

      private static var fxChange:Object = null;

      private static var fxStart:int = 0;

      private static const FX_MS:int = 1400;

      private static const RAYS:int = 12;

      private static function rankChange(g:Sprite, before:int, after:int, rank:Boolean, ru:TextField, x:Number, y:Number,
                                         w:Number, sc:Number) : void
      {
         var size:int = int(w * 0.92);
         var rising:Boolean = after > before;
         if(fxChange !== change)
         {
            fxChange = change;
            fxStart = getTimer();
            if(rank && rising)
            {
               try
               {
                  class_727.PostEvent("UI_Scoreboard_PvPRankUp_Play");
               }
               catch(e:Error)
               {
               }
            }
         }
         var cx:Number = x + w / 2;
         var cy:Number = y + size / 2;
         var rays:Shape = null;
         if(rank && rising)
         {
            rays = new Shape();
            var reach:Number = size * 0.55;
            for(var i:int = 0; i < RAYS; i++)
            {
               var a0:Number = (i - 0.18) * Math.PI * 2 / RAYS;
               var a1:Number = (i + 0.18) * Math.PI * 2 / RAYS;
               rays.graphics.beginFill(i % 2 == 0 ? GOLD : ACCENT,0.8);
               rays.graphics.moveTo(0,0);
               rays.graphics.lineTo(Math.cos(a0) * reach,Math.sin(a0) * reach);
               rays.graphics.lineTo(Math.cos(a1) * reach,Math.sin(a1) * reach);
               rays.graphics.endFill();
            }
            rays.x = cx;
            rays.y = cy;
            g.addChild(rays);
         }
         var old:Sprite = centred(g,LeaderboardWindow.tierBanner(bannerTier(before,false),size,before),cx,cy);
         var now:Sprite = centred(g,LeaderboardWindow.tierBanner(bannerTier(after,false),size,after),cx,cy);
         if(old == null || now == null)
         {
            incomplete = true;
         }
         UiKit.text(g,tierName(after),cx,y + size + 4 * sc,15 * sc,0xFFFFFF,UiKit.XBOLD,0,true);
         fx = {"rays":rays,"old":old,"now":now,"label":ru,"rising":rising,"cy":cy,"sink":20 * sc};
         animate();
      }

      private static function centred(g:Sprite, b:Bitmap, cx:Number, cy:Number) : Sprite
      {
         if(b == null)
         {
            return null;
         }
         var holder:Sprite = new Sprite();
         b.x = -b.width / 2;
         b.y = -b.height / 2;
         holder.addChild(b);
         holder.x = cx;
         holder.y = cy;
         g.addChild(holder);
         return holder;
      }

      private static function clamp01(v:Number) : Number
      {
         return v < 0 ? 0 : (v > 1 ? 1 : v);
      }

      private static function animate() : void
      {
         if(fx == null)
         {
            return;
         }
         var ms:int = getTimer() - fxStart;
         var t:Number = ms / FX_MS;
         var old:Sprite = fx.old as Sprite;
         var now:Sprite = fx.now as Sprite;
         var out:Number = clamp01(t / 0.35);
         if(old != null)
         {
            old.alpha = 1 - out;
            old.visible = out < 1;
            old.scaleX = old.scaleY = fx.rising ? 1 - 0.3 * out : 1 - 0.1 * out;
            old.y = fx.rising ? fx.cy : fx.cy + fx.sink * out;
         }
         var p:Number = clamp01((t - 0.3) / 0.4);
         if(now != null)
         {
            now.alpha = clamp01(p * 2);
            if(fx.rising)
            {
               var q:Number = p - 1;
               var back:Number = 1 + 2.70158 * q * q * q + 1.70158 * q * q;
               now.scaleX = now.scaleY = 0.4 + 0.6 * back;
            }
            else
            {
               now.scaleX = now.scaleY = 1;
            }
         }
         var label:TextField = fx.label as TextField;
         if(label != null)
         {
            label.alpha = clamp01((t - 0.55) / 0.15);
         }
         var rays:Shape = fx.rays as Shape;
         if(rays != null)
         {
            rays.rotation = (ms / 40) % 360;
            rays.alpha = t < 1 ? 0.55 * clamp01((t - 0.3) / 0.3) : 0.35 + 0.12 * Math.sin(ms / 300);
         }
      }

      private static function tierBar(g:Sprite, x:Number, y:Number, w:Number, rating:int, sc:Number) : void
      {
         var h:Number = 10 * sc;
         UiKit.rect(g,x,y,w,h,TRACK,h / 2);
         var part:Number = rating >= VALHALLAN ? 1 : (Math.max(0,rating) % RANK_SPAN) / RANK_SPAN;
         if(part > 0)
         {
            UiKit.rect(g,x,y,Math.max(h,w * part),h,ACCENT,h / 2);
         }
         for(var i:int = 1; i < 5; i++)
         {
            UiKit.rect(g,x + w * i / 5 - sc,y - sc,2 * sc,h + 2 * sc,FILL);
         }
      }

      public static function placementPips(g:Sprite, x:Number, y:Number, size:Number, games:int, total:int,
                                           results:Array) : Number
      {
         return pips(g,x,y,size,games,total,ACCENT,results);
      }

      private static function pips(g:Sprite, x:Number, y:Number, size:Number, on:int, total:int, color:uint,
                                   results:Object = null) : Number
      {
         var known:Array = results is Array ? results as Array : [];
         for(var i:int = 0; i < total; i++)
         {
            var fill:uint = TRACK;
            if(i < on)
            {
               var r:String = on - 1 - i < known.length ? String(known[on - 1 - i]) : "";
               fill = r == "win" ? WIN : (r == "loss" ? LOSS : color);
            }
            UiKit.rect(g,x + i * size * 1.45,y,size,size,fill,size / 2);
         }
         return x + total * size * 1.45;
      }

      private static function stat(g:Sprite, label:String, value:String, x:Number, y:Number, sc:Number,
                                   color:uint = 0xFFFFFF) : Number
      {
         var l:TextField = UiKit.text(g,label,x,y,12 * sc,LABEL,UiKit.XBOLD);
         var v:TextField = UiKit.text(g,value,x,y + 15 * sc,20 * sc,color,UiKit.XBOLD);
         return x + Math.max(l.width,v.width);
      }

      private static function part(g:Sprite, value:int, label:String, x:Number, y:Number, size:Number) : Number
      {
         var v:TextField = UiKit.text(g,signed(value),x,y,size,value >= 0 ? WIN : LOSS,UiKit.XBOLD);
         var l:TextField = UiKit.text(g,label,v.x + v.width + 3,y,size,LABEL,UiKit.XBOLD);
         return l.x + l.width + size;
      }

      private static function ratingLine(g:Sprite, legendId:int, name:String, before:int, after:int, x:Number, y:Number,
                                         right:Number, sc:Number, rankIcon:Boolean = false) : void
      {
         var nx:Number = x;
         if(legendId > 0)
         {
            var icon:Bitmap = LeaderboardWindow.legendIcon(legendId,int(30 * sc));
            if(icon != null)
            {
               icon.x = x;
               icon.y = y - 4 * sc;
               g.addChild(icon);
            }
            nx = x + 36 * sc;
         }
         if(rankIcon)
         {
            nx = placeIcon(g,RatingExtras.rankIcon(after,false,30 * sc),nx,y - 4 * sc) + 6 * sc;
         }
         UiKit.text(g,name,nx,y,16 * sc,0xFFFFFF,UiKit.XBOLD);
         var d:int = after - before;
         var t:TextField = UiKit.text(g,before + "  >  " + after + "   (" + signed(d) + ")",0,y,16 * sc,
            d >= 0 ? WIN : LOSS,UiKit.XBOLD);
         t.x = right - t.width;
      }

      private static function drawElo(g:Sprite, s:Stage) : void
      {
         var sc:Number = s.stageHeight / 1080;
         var w:Number = 780 * sc;
         var h:Number = 330 * sc;
         var x:Number = (s.stageWidth - w) / 2;
         var y:Number = 222 * sc;
         panel(g,x,y,w,h,sc);
         var before:int = int(change.before);
         var after:int = int(change.after);
         var games:int = int(change.games);
         var placement:int = change.placement != null ? int(change.placement) : 10;
         var placing:Boolean = games > 0 && games < placement;
         var ladder:String = String(change.ladder || "1v1").toUpperCase();
         var col:Number = 236 * sc;
         UiKit.text(g,"RANKED " + ladder,x + 22 * sc,y + 12 * sc,18 * sc,0xFFFFFF,UiKit.XBOLD);
         var up:Boolean = !placing && tierName(after).split(" ")[0] != tierName(before).split(" ")[0];
         var step:Boolean = !placing && !up && tierName(after) != tierName(before);
         var ru:TextField = null;
         if(up || step)
         {
            ru = UiKit.text(g,(up ? "RANK " : "TIER ") + (after > before ? (up ? "UP!" : "UP") : "DOWN"),0,y + 10 * sc,
               20 * sc,after > before ? ACCENT : LOSS,UiKit.XBOLD);
            ru.x = x + w - 22 * sc - ru.width;
         }
         if(up || step)
         {
            rankChange(g,before,after,up,ru,x + 8 * sc,y + 54 * sc,col - 8 * sc,sc);
         }
         else
         {
            fx = null;
            banner(g,bannerTier(after,placing),after,placing ? "PLACEMENT " + games + "/" + placement : tierName(after),
               x + 8 * sc,y + 54 * sc,col - 8 * sc,sc);
         }
         var cx:Number = x + col + 10 * sc;
         var right:Number = x + w - 24 * sc;
         UiKit.text(g,"ELO RATING",cx,y + 62 * sc,13 * sc,LABEL,UiKit.XBOLD);
         var old:TextField = UiKit.text(g,before + "  >",cx,y + 86 * sc,24 * sc,LABEL,UiKit.XBOLD);
         var now:TextField = UiKit.text(g,String(after),old.x + old.width + 10 * sc,y + 76 * sc,38 * sc,0xFFFFFF,UiKit.XBOLD);
         var d:int = after - before;
         UiKit.text(g,"(" + signed(d) + ")",now.x + now.width + 10 * sc,y + 88 * sc,24 * sc,d >= 0 ? WIN : LOSS,UiKit.XBOLD);
         var px:Number = cx;
         var py:Number = y + 130 * sc;
         if(change.base != null)
         {
            px = part(g,int(change.base),"BASE",px,py,14 * sc);
            if(int(change.streak_bonus) != 0)
            {
               var n:int = Math.abs(int(change.streak));
               px = part(g,int(change.streak_bonus),"STREAK (" + n + (int(change.streak) > 0 ? " WINS)" : " LOSSES)"),px,py,14 * sc);
            }
         }
         if(change["protected"] == true)
         {
            UiKit.text(g,"PROTECTED: NEXT LOSS DERANKS",px,py,14 * sc,GOLD,UiKit.XBOLD);
         }
         var by:Number = y + 162 * sc;
         if(placing)
         {
            UiKit.text(g,"PLACEMENT MATCHES",cx,by,13 * sc,LABEL,UiKit.XBOLD);
            pips(g,cx + 170 * sc,by + 2 * sc,11 * sc,games,placement,ACCENT,change.last);
         }
         else
         {
            var next:TextField = UiKit.text(g,toNext(after),0,by - 2 * sc,13 * sc,LABEL,UiKit.XBOLD);
            next.x = right - next.width;
            tierBar(g,cx,by + 2 * sc,next.x - 14 * sc - cx,after,sc);
         }
         UiKit.rect(g,cx,y + 192 * sc,right - cx,sc,EDGE);
         var ly:Number = y + 206 * sc;
         if(change.legend != null)
         {
            var lid:int = int(change.legend.id);
            ratingLine(g,lid,LeaderboardWindow.legendName(lid).toUpperCase(),int(change.legend.before),int(change.legend.after),
               cx,ly,right,sc,true);
         }
         else if(change.team != null)
         {
            ratingLine(g,0,"TEAM RATING",int(change.team.before),int(change.team.after),cx,ly,right,sc);
         }
         UiKit.rect(g,cx,y + 246 * sc,right - cx,sc,EDGE);
         var sy:Number = y + 258 * sc;
         var sx:Number = stat(g,"BEST ELO",String(change.peak != null ? change.peak : after),cx,sy,sc) + 28 * sc;
         sx = stat(g,"WINS",String(change.wins != null ? change.wins : "-"),sx,sy,sc) + 28 * sc;
         if(change.wins != null)
         {
            sx = stat(g,"WIN %",winRate(int(change.wins),games),sx,sy,sc) + 28 * sc;
         }
         if(int(change.rank) > 0)
         {
            stat(g,"RANK",String("#" + change.rank),sx,sy,sc);
         }
         if(seriesBefore != null && ladder == "1V1")
         {
            var won:Boolean = after > before;
            var mine:int = int(seriesBefore.mine) + (won ? 1 : 0);
            var theirs:int = int(seriesBefore.theirs) + (won ? 0 : 1);
            var label:TextField = UiKit.text(g,"SERIES (BEST OF 5)",0,sy,12 * sc,LABEL,UiKit.XBOLD);
            label.x = right - label.width;
            var score:TextField = UiKit.text(g,mine + " - " + theirs,0,sy + 14 * sc,22 * sc,
               mine > theirs ? WIN : (mine < theirs ? LOSS : 0xFFFFFF),UiKit.XBOLD);
            score.x = right - score.width;
         }
      }

      public static function sidePanel(g:Sprite, base:Object, card:Object, x:Number, y:Number, w:Number, sc:Number,
                                       label:String, centred:Boolean = false) : Boolean
      {
         incomplete = false;
         card = card || {};
         var rating:int = int(base.rating);
         var games:int = int(base.games);
         var placement:int = card.placement != null ? int(card.placement) : 10;
         var placing:Boolean = games < placement;
         var legend:Object = card.legend;
         var last:Array = card.last is Array ? (card.last as Array).slice(0,12) : [];
         var showLast:Boolean = last.length > 0 || games == 0;
         var h:Number = (showLast ? 650 : 594) * sc;
         panel(g,x,y,w,h,sc);
         var mid:Number = x + w / 2;
         var pad:Number = 20 * sc;
         if(centred)
         {
            var title:TextField = UiKit.fit(UiKit.text(g,label,0,y + 12 * sc,18 * sc,0xFFFFFF,UiKit.XBOLD),w - 2 * pad);
            title.x = mid - title.width / 2;
         }
         else
         {
            UiKit.text(g,label,x + pad,y + 12 * sc,18 * sc,0xFFFFFF,UiKit.XBOLD);
         }
         banner(g,bannerTier(rating,placing),rating,placing ? "PLACEMENT " + (games + 1) + "/" + placement :
            tierName(rating),mid - 85 * sc,y + 58 * sc,170 * sc,sc);
         var ry:Number = y + 270 * sc;
         var r:TextField = UiKit.text(g,String(rating),mid,ry,40 * sc,0xFFFFFF,UiKit.XBOLD,0,true);
         UiKit.text(g,"ELO RATING",mid,ry + r.height - 4 * sc,12 * sc,LABEL,UiKit.XBOLD,0,true);
         ry += 74 * sc;
         if(placing)
         {
            var pw:Number = placement * 11 * sc * 1.45;
            pips(g,mid - pw / 2,ry + 2 * sc,11 * sc,games,placement,ACCENT,card.last);
         }
         else
         {
            tierBar(g,x + pad,ry,w - 2 * pad,rating,sc);
            UiKit.text(g,toNext(rating),mid,ry + 14 * sc,12 * sc,LABEL,UiKit.XBOLD,0,true);
         }
         ry += 44 * sc;
         UiKit.rect(g,x + pad,ry - 8 * sc,w - 2 * pad,sc,EDGE);
         var colW:Number = (w - 2 * pad) / 4;
         var wins:int = card.wins != null ? int(card.wins) : 0;
         var cells:Array = [["BEST",card.peak != null ? String(card.peak) : String(rating)],["WINS",String(wins)],
            ["WIN %",winRate(wins,games)],["RANK",int(card.rank) > 0 ? "#" + card.rank : "-"]];
         for(var i:int = 0; i < cells.length; i++)
         {
            var cxm:Number = x + pad + colW * i + colW / 2;
            UiKit.text(g,cells[i][0],cxm,ry,11 * sc,LABEL,UiKit.XBOLD,0,true);
            UiKit.text(g,cells[i][1],cxm,ry + 14 * sc,18 * sc,0xFFFFFF,UiKit.XBOLD,0,true);
         }
         if(showLast)
         {
            ry += 56 * sc;
            UiKit.rect(g,x + pad,ry - 8 * sc,w - 2 * pad,sc,EDGE);
            UiKit.text(g,last.length > 0 ? "LAST " + last.length : "NO RANKED MATCHES YET",mid,ry,12 * sc,LABEL,UiKit.XBOLD,0,true);
            var bw:Number = 20 * sc;
            var gap:Number = 3 * sc;
            var lx:Number = mid - (last.length * (bw + gap) - gap) / 2;
            for(var k:int = 0; k < last.length; k++)
            {
               var win:Boolean = String(last[last.length - 1 - k]) == "win";
               UiKit.rect(g,lx + k * (bw + gap),ry + 18 * sc,bw,20 * sc,win ? 0x1E5A35 : 0x5A1E25,5 * sc);
               UiKit.text(g,win ? "W" : "L",lx + k * (bw + gap) + bw / 2,ry + 20 * sc,12 * sc,win ? WIN : LOSS,UiKit.XBOLD,0,true);
            }
         }
         if(legend != null)
         {
            ry += 52 * sc;
            UiKit.rect(g,x + pad,ry - 8 * sc,w - 2 * pad,sc,EDGE);
            var lr:int = legend.rating != null ? int(legend.rating) : -1;
            var lid:int = int(legend.id);
            var portrait:Bitmap = LeaderboardWindow.legendIcon(lid,int(40 * sc));
            if(portrait != null)
            {
               portrait.x = x + pad;
               portrait.y = ry;
               g.addChild(portrait);
            }
            var lx2:Number = x + pad + 46 * sc;
            if(lr >= 0)
            {
               lx2 = placeIcon(g,rankIcon(lr,false,40 * sc),lx2,ry) + 6 * sc;
            }
            UiKit.text(g,LeaderboardWindow.legendName(lid).toUpperCase(),lx2,ry,16 * sc,0xFFFFFF,UiKit.XBOLD);
            UiKit.text(g,lr >= 0 ? int(legend.wins) + " WINS   " + winRate(int(legend.wins),int(legend.games)) : "NOT PLAYED RANKED",
               lx2,ry + 20 * sc,12 * sc,LABEL,UiKit.XBOLD);
            if(lr >= 0)
            {
               var lv:TextField = UiKit.text(g,String(lr),0,ry + 4 * sc,24 * sc,0xFFFFFF,UiKit.XBOLD);
               lv.x = x + w - pad - lv.width;
            }
         }
         return !incomplete;
      }

      private static function drawLobby(g:Sprite, s:Stage) : void
      {
         var sc:Number = s.stageHeight / 1080;
         var c:Object = lobbyCard;
         var w:Number = 640 * sc;
         var legendRows:int = lobbyLegends == null ? 1 : (lobbyLegends[0] != null ? 1 : 0) + (lobbyLegends[1] != null ? 1 : 0);
         var last:Array = c.last is Array ? (c.last as Array).slice(0,12) : [];
         var showLast:Boolean = last.length > 0 || int(c.games) == 0;
         var h:Number = Math.max(248,(showLast ? 222 : 176) + 44 * Math.max(1,legendRows)) * sc;
         var x:Number = s.stageWidth / 2 - 316 * sc;
         var y:Number = 532 * sc;
         panel(g,x,y,w,h,sc);
         var rating:int = int(c.rating);
         var games:int = int(c.games);
         var placement:int = c.placement != null ? int(c.placement) : 10;
         var placing:Boolean = games < placement;
         var ladder:String = String(lobbyName || c.ladder || "1v1").toUpperCase();
         var col:Number = 180 * sc;
         UiKit.text(g,"RANKED " + ladder + (c.team ? " TEAM" : ""),x + 22 * sc,y + 12 * sc,18 * sc,0xFFFFFF,UiKit.XBOLD);
         var season:TextField = UiKit.text(g,"SEASON " + (c.season != null ? c.season : 1),0,y + 12 * sc,18 * sc,ACCENT,UiKit.XBOLD);
         season.x = x + w - 22 * sc - season.width;
         banner(g,bannerTier(rating,placing),rating,placing ? "PLACEMENT " + games + "/" + placement : tierName(rating),
            x + 12 * sc,y + 58 * sc,col - 16 * sc,sc);
         var cx:Number = x + col + 8 * sc;
         var right:Number = x + w - 22 * sc;
         UiKit.text(g,"ELO RATING",cx,y + 60 * sc,13 * sc,LABEL,UiKit.XBOLD);
         UiKit.text(g,String(rating),cx,y + 74 * sc,38 * sc,0xFFFFFF,UiKit.XBOLD);
         var sx:Number = cx + 128 * sc;
         sx = stat(g,"BEST ELO",String(c.peak),sx,y + 62 * sc,sc) + 22 * sc;
         sx = stat(g,"WINS",String(c.wins),sx,y + 62 * sc,sc) + 22 * sc;
         sx = stat(g,"WIN %",winRate(int(c.wins),games),sx,y + 62 * sc,sc) + 22 * sc;
         if(int(c.rank) > 0)
         {
            stat(g,"RANK","#" + c.rank,sx,y + 62 * sc,sc);
         }
         var by:Number = y + 128 * sc;
         if(placing)
         {
            UiKit.text(g,"PLACEMENT MATCHES",cx,by,13 * sc,LABEL,UiKit.XBOLD);
            pips(g,cx + 170 * sc,by + 2 * sc,11 * sc,games,placement,ACCENT,c.last);
         }
         else
         {
            var next:TextField = UiKit.text(g,toNext(rating),0,by - 2 * sc,13 * sc,LABEL,UiKit.XBOLD);
            next.x = right - next.width;
            tierBar(g,cx,by + 2 * sc,next.x - 14 * sc - cx,rating,sc);
         }
         UiKit.rect(g,cx,y + 156 * sc,right - cx,sc,EDGE);
         if(showLast)
         {
            var ly:Number = y + 168 * sc;
            UiKit.text(g,"LAST " + (last.length > 0 ? last.length : 12),cx,ly + 3 * sc,13 * sc,LABEL,UiKit.XBOLD);
            if(last.length == 0)
            {
               UiKit.text(g,"NO RANKED MATCHES YET",cx + 90 * sc,ly,15 * sc,0xFFFFFF,UiKit.XBOLD);
            }
            for(var k:int = 0; k < last.length; k++)
            {
               var win:Boolean = String(last[last.length - 1 - k]) == "win";
               var bx:Number = cx + 80 * sc + k * 28 * sc;
               UiKit.rect(g,bx,ly,25 * sc,22 * sc,win ? 0x1E5A35 : 0x5A1E25,6 * sc);
               UiKit.text(g,win ? "W" : "L",bx + 12.5 * sc,ly + 2 * sc,14 * sc,win ? WIN : LOSS,UiKit.XBOLD,0,true);
            }
            UiKit.rect(g,cx,y + 202 * sc,right - cx,sc,EDGE);
         }
         var ry:Number = y + (showLast ? 216 : 170) * sc;
         if(lobbyLegends == null)
         {
            if(c.team)
            {
               membersLine(g,c.members as Array,cx,ry,right,sc);
               return;
            }
            teammateLine(g,c.teammate,cx,ry,right,sc);
            for(var mi:int = 0; lobbyMates != null && mi < lobbyMates.length; mi++)
            {
               if(mateKnown(mi))
               {
                  mateCard(g,lobbyMates[mi],sc);
               }
            }
            return;
         }
         var best:Array = lobbyLegends[0];
         var picked:Array = lobbyLegends[1];
         if(best != null)
         {
            legendLine(g,"BEST LEGEND",best,cx,ry,right,sc);
            ry += 44 * sc;
         }
         if(picked != null)
         {
            legendLine(g,"PICKED",picked,cx,ry,right,sc);
         }
         else if(best == null)
         {
            UiKit.text(g,"PICK A LEGEND TO SEE ITS RATING",cx,ry + 6 * sc,14 * sc,LABEL,UiKit.XBOLD);
         }
      }

      private static function legendLine(g:Sprite, label:String, l:Array, x:Number, y:Number, right:Number,
                                         sc:Number) : void
      {
         var id:int = int(l[0]);
         var rating:int = int(l[1]);
         var icon:Bitmap = LeaderboardWindow.legendIcon(id,int(34 * sc));
         if(icon != null)
         {
            icon.x = x;
            icon.y = y;
            g.addChild(icon);
         }
         var tx:Number = x + 40 * sc;
         if(rating >= 0)
         {
            tx = placeIcon(g,rankIcon(rating,false,34 * sc),tx,y) + 6 * sc;
         }
         UiKit.text(g,label,tx,y - 1 * sc,12 * sc,LABEL,UiKit.XBOLD);
         var n:TextField = UiKit.text(g,LeaderboardWindow.legendName(id).toUpperCase(),tx,y + 13 * sc,16 * sc,0xFFFFFF,UiKit.XBOLD);
         if(rating >= 0)
         {
            UiKit.text(g,int(l[2]) + " WINS   " + winRate(int(l[2]),int(l[3])),n.x + n.width + 12 * sc,y + 16 * sc,13 * sc,LABEL,
               UiKit.XBOLD);
         }
         var v:TextField = UiKit.text(g,rating >= 0 ? String(rating) : "NOT PLAYED RANKED",0,y + 6 * sc,
            rating >= 0 ? 22 * sc : 14 * sc,rating >= 0 ? 0xFFFFFF : LABEL,UiKit.XBOLD);
         v.x = right - v.width;
      }

      private static function placeIcon(g:Sprite, icon:Sprite, x:Number, y:Number) : Number
      {
         if(icon == null)
         {
            return x;
         }
         icon.x = x;
         icon.y = y;
         g.addChild(icon);
         return x + icon.width;
      }

      public static function rankIcon(rating:int, placing:Boolean, size:Number) : Sprite
      {
         var star:uint = 0;
         var notch:int = 0;
         if(!placing && rating >= VALHALLAN)
         {
            star = 50;
         }
         else if(!placing)
         {
            var r:int = Math.max(0,rating);
            star = 1 + int(r / RANK_SPAN) * 6 + 1;
            notch = int((r % RANK_SPAN) / STEP) + 1;
         }
         var cacheKey:String = star + ":" + notch + ":" + Math.round(size);
         var bd:BitmapData = iconCache[cacheKey] as BitmapData;
         if(bd == null)
         {
            var drawn:Sprite = makeRankIcon(star,notch,Math.round(size));
            if(drawn == null)
            {
               return null;
            }
            try
            {
               bd = new BitmapData(Math.max(1,Math.ceil(drawn.width)),Math.max(1,Math.ceil(drawn.height)),true,0);
               bd.draw(drawn,null,null,null,null,true);
               iconCache[cacheKey] = bd;
            }
            catch(e:Error)
            {
               Platform.log("rank icon: can't draw to a bitmap: " + e.message);
               return drawn;
            }
         }
         var out:Sprite = new Sprite();
         out.mouseEnabled = out.mouseChildren = false;
         out.addChild(new Bitmap(bd,PixelSnapping.AUTO,true));
         return out;
      }

      private static var iconCache:Object = {};

      private static function makeRankIcon(star:uint, notch:int, size:Number) : Sprite
      {
         try
         {
            var whole:MovieClip = class_687.method_1714("a_UISeasonal2v2","UI_1") as MovieClip;
            var clip:MovieClip = whole != null ? class_51.method_3081(whole,"am_PanelInternal") : null;
            var icon:MovieClip = clip != null ? class_51.method_3081(clip,"am_BannerIcon") : null;
            if(icon == null)
            {
               Platform.log("rank icon: no am_BannerIcon in a_UISeasonal2v2 (" + whole + ")");
               return null;
            }
            clip.parent.removeChild(clip);
            var notches:MovieClip = class_51.method_3081(clip,"am_BannerNotches");
            for(var i:int = clip.numChildren - 1; i >= 0; i--)
            {
               var ch:DisplayObject = clip.getChildAt(i);
               if(!(ch === icon || ch === notches && notch > 0))
               {
                  clip.removeChildAt(i);
               }
            }
            UiKit.gotoLabel(icon,class_189.method_7376(star));
            if(notches != null && notch > 0)
            {
               UiKit.gotoLabel(notches,"Notch" + notch);
            }
            clip.stopAllMovieClips();
            var b:Rectangle = icon.getBounds(clip);
            if(notches != null && notch > 0)
            {
               b = b.union(notches.getBounds(clip));
            }
            if(b.height <= 0)
            {
               return null;
            }
            var k:Number = size / b.height;
            clip.scaleX = clip.scaleY = k;
            clip.x = -b.x * k;
            clip.y = -b.y * k;
            var out:Sprite = new Sprite();
            out.mouseEnabled = out.mouseChildren = false;
            out.addChild(clip);
            return out;
         }
         catch(e:Error)
         {
            Platform.log("rank icon: " + e.message);
         }
         return null;
      }

      private static function membersLine(g:Sprite, members:Array, x:Number, y:Number, right:Number, sc:Number) : void
      {
         var half:Number = (right - x) / 2;
         for(var i:int = 0; members != null && i < Math.min(2,members.length); i++)
         {
            var m:Object = members[i];
            var left:Number = x + i * half;
            var rating:int = int(m.rating);
            var tx:Number = placeIcon(g,rankIcon(rating,int(m.games) < 10,34 * sc),left,y) + 6 * sc;
            UiKit.text(g,"OWN 2V2",tx,y - 1 * sc,12 * sc,LABEL,UiKit.XBOLD);
            var v:TextField = UiKit.text(g,String(rating),0,y + 2 * sc,22 * sc,0xFFFFFF,UiKit.XBOLD);
            v.x = left + half - 16 * sc - v.width;
            UiKit.fit(UiKit.text(g,String(m.name).toUpperCase(),tx,y + 13 * sc,16 * sc,0xFFFFFF,UiKit.XBOLD),
               v.x - 10 * sc - tx);
         }
      }

      private static function teammateLine(g:Sprite, t:Object, x:Number, y:Number, right:Number, sc:Number) : void
      {
         if(t == null)
         {
            UiKit.text(g,"BEST TEAMMATE",x,y - 1 * sc,12 * sc,LABEL,UiKit.XBOLD);
            UiKit.text(g,"NO RANKED TEAM MATCHES YET",x,y + 13 * sc,16 * sc,0xFFFFFF,UiKit.XBOLD);
            return;
         }
         var rating:int = int(t.rating);
         var games:int = int(t.games);
         var tx:Number = placeIcon(g,rankIcon(rating,games < 10,34 * sc),x,y) + 6 * sc;
         UiKit.text(g,"BEST TEAMMATE",tx,y - 1 * sc,12 * sc,LABEL,UiKit.XBOLD);
         var n:TextField = UiKit.fit(UiKit.text(g,String(t.name).toUpperCase(),tx,y + 13 * sc,16 * sc,0xFFFFFF,UiKit.XBOLD),
            200 * sc);
         UiKit.text(g,int(t.wins) + " WINS   " + winRate(int(t.wins),games) + (int(t.rank) > 0 ? "   #" + t.rank : ""),
            n.x + n.width + 12 * sc,y + 16 * sc,13 * sc,LABEL,UiKit.XBOLD);
         var v:TextField = UiKit.text(g,String(rating),0,y + 2 * sc,22 * sc,0xFFFFFF,UiKit.XBOLD);
         v.x = right - v.width;
         UiKit.text(g,"TEAM",right - v.width / 2,y + 26 * sc,10 * sc,LABEL,UiKit.XBOLD,0,true);
      }

      private static function mateCard(g:Sprite, m:Object, sc:Number) : void
      {
         if(m == null || m.rect == null)
         {
            return;
         }
         var c:Object = m.card;
         var last:Array = c != null && c.last is Array ? (c.last as Array).slice(0,5) : [];
         var w:Number = 350 * sc;
         var h:Number = (last.length > 0 || c != null && int(c.rank) > 0 ? 162 : 124) * sc;
         var x:Number = m.rect[0] + m.rect[2] / 2 - w / 2;
         var y:Number = m.rect[1] + m.rect[3] / 2 - h / 2;
         panel(g,x,y,w,h,sc);
         var pad:Number = 14 * sc;
         UiKit.fit(UiKit.text(g,String(m.name).toUpperCase(),x + pad,y + 8 * sc,15 * sc,0xFFFFFF,UiKit.XBOLD),w - 120 * sc);
         var tag:TextField = UiKit.text(g,"INDIVIDUAL 2V2",0,y + 10 * sc,11 * sc,ACCENT,UiKit.XBOLD);
         tag.x = x + w - pad - tag.width;
         if(c == null || c.rating == null)
         {
            UiKit.text(g,c != null && c.error != null ? "NO RANKED 2V2 YET" : "LOADING...",x + pad,y + 56 * sc,14 * sc,LABEL,
               UiKit.XBOLD);
            return;
         }
         var rating:int = int(c.rating);
         var games:int = int(c.games);
         var placement:int = c.placement != null ? int(c.placement) : 10;
         var placing:Boolean = games < placement;
         var tx:Number = placeIcon(g,rankIcon(rating,placing,56 * sc),x + pad,y + 56 * sc) + 10 * sc;
         var lab:TextField = UiKit.text(g,placing ? "PLACEMENT " + games + "/" + placement : tierName(rating),tx,y + 56 * sc,
            12 * sc,LABEL,UiKit.XBOLD);
         UiKit.text(g,String(rating),tx,y + 69 * sc,30 * sc,0xFFFFFF,UiKit.XBOLD);
         var sx:Number = Math.max(tx + 92 * sc,lab.x + lab.width + 12 * sc);
         sx = stat(g,"BEST",String(c.peak),sx,y + 58 * sc,sc) + 12 * sc;
         sx = stat(g,"WINS",String(c.wins),sx,y + 58 * sc,sc) + 12 * sc;
         stat(g,"WIN %",winRate(int(c.wins),games),sx,y + 58 * sc,sc);
         if(last.length == 0 && int(c.rank) <= 0)
         {
            return;
         }
         var ly:Number = y + 128 * sc;
         UiKit.rect(g,x + pad,ly - 6 * sc,w - 2 * pad,sc,EDGE);
         if(last.length > 0)
         {
            UiKit.text(g,"LAST " + last.length,x + pad,ly + 4 * sc,11 * sc,LABEL,UiKit.XBOLD);
         }
         for(var k:int = 0; k < last.length; k++)
         {
            var win:Boolean = String(last[last.length - 1 - k]) == "win";
            var bx:Number = x + pad + 58 * sc + k * 24 * sc;
            UiKit.rect(g,bx,ly + 2 * sc,21 * sc,19 * sc,win ? 0x1E5A35 : 0x5A1E25,5 * sc);
            UiKit.text(g,win ? "W" : "L",bx + 10.5 * sc,ly + 3 * sc,12 * sc,win ? WIN : LOSS,UiKit.XBOLD,0,true);
         }
         if(int(c.rank) > 0)
         {
            var rk:TextField = UiKit.text(g,"#" + c.rank,0,ly + 1 * sc,16 * sc,0xFFFFFF,UiKit.XBOLD);
            rk.x = x + w - pad - rk.width;
         }
      }
   }
}
