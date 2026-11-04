package bh.platform.net
{
   import bh.platform.Hooks;
   import flash.utils.getTimer;

   public final class Smoothing
   {
      public static const DEFAULT_MS:Number = 100;
      public static const MAX_JUMP:Number = 400;
      public static const MIN_ERROR:Number = 2;

      private static var registered:Boolean = false;
      private static var on:Boolean = false;
      private static var core:Object = null;
      private static var players:Object = {};
      private static var startTime:uint = 0;
      private static var rolledBack:Boolean = false;
      private static var lastDraw:int = 0;
      private static var preparedFrame:Boolean = false;

      private static var tau:Number = DEFAULT_MS / 2.3;

      public static var corrections:uint = 0;
      public static var largest:Number = 0;
      public static var tooLarge:uint = 0;

      public function Smoothing()
      {
      }

      public static function setMs(ms:Number) : void
      {
         tau = Math.max(1,ms) / 2.3;
      }

      public static function start(enabled:Boolean, ms:Number) : void
      {
         if(!registered)
         {
            registered = true;
            Hooks.frameStarting.add(function():void
            {
               preparedFrame = false;
               restore();
            });
            Hooks.frameRendering.add(onRender);
         }
         stop();
         on = enabled;
         tau = Math.max(1,ms) / 2.3;
      }

      public static function stop() : void
      {
         restore();
         on = false;
         core = null;
         players = {};
         rolledBack = false;
         corrections = 0;
         largest = 0;
         tooLarge = 0;
         lastDraw = 0;
      }

      public static function beforeSteps(game:Object) : void
      {
         if(!on)
         {
            return;
         }
         core = game;
         restore();
         startTime = uint(game.var_13849);
         startTime -= startTime % 16;
         try
         {
            var list:Object = game.var_7050;
            for(var i:int = 0; i < int(list.length); i++)
            {
               var player:Object = list[i];
               var sprite:Object = spriteOf(player);
               var p:Object = entry(player);
               p.hasStart = sprite != null;
               if(sprite != null)
               {
                  p.startX = Number(sprite.x);
                  p.startY = Number(sprite.y);
               }
            }
         }
         catch(e:Error)
         {
         }
      }

      public static function jumped() : void
      {
         rolledBack = true;
         for each(var p:Object in players)
         {
            p.offX = p.offY = 0;
            p.hasVelocity = false;
         }
      }

      public static function rollingBack() : void
      {
         rolledBack = true;
      }

      public static function prepare() : void
      {
         if(!on || core == null || preparedFrame)
         {
            return;
         }
         update(false);
         preparedFrame = true;
      }

      public static function offsetX(sprite:Object) : Number
      {
         var p:Object = shifted(sprite);
         return p != null ? Number(p.offX) : 0;
      }

      public static function offsetY(sprite:Object) : Number
      {
         var p:Object = shifted(sprite);
         return p != null ? Number(p.offY) : 0;
      }

      private static function shifted(sprite:Object) : Object
      {
         if(!preparedFrame)
         {
            return null;
         }
         for each(var p:Object in players)
         {
            if(p.drawSprite == sprite)
            {
               return p;
            }
         }
         return null;
      }

      private static function onRender() : void
      {
         if(!on || core == null || preparedFrame)
         {
            return;
         }
         update(true);
      }

      private static function update(move:Boolean) : void
      {
         restore();
         var now:int = getTimer();
         var fade:Number = lastDraw > 0 ? Math.exp(-(now - lastDraw) / tau) : 0;
         lastDraw = now;
         try
         {
            var endTime:uint = uint(core.var_12659);
            endTime -= endTime % 16;
            var steps:Number = endTime > startTime ? (endTime - startTime) / 16 : 0;
            var list:Object = core.var_7050;
            for(var i:int = 0; i < int(list.length); i++)
            {
               var player:Object = list[i];
               var sprite:Object = spriteOf(player);
               var p:Object = entry(player);
               if(sprite == null || !p.hasStart)
               {
                  p.offX = p.offY = 0;
                  p.hasVelocity = false;
                  continue;
               }
               var x:Number = Number(sprite.x);
               var y:Number = Number(sprite.y);
               p.offX *= fade;
               p.offY *= fade;
               if(rolledBack && p.hasVelocity)
               {
                  var errX:Number = x - (p.startX + p.vx * steps);
                  var errY:Number = y - (p.startY + p.vy * steps);
                  var err:Number = Math.sqrt(errX * errX + errY * errY);
                  if(err > MAX_JUMP)
                  {
                     p.offX = p.offY = 0;
                     tooLarge++;
                  }
                  else if(err > MIN_ERROR)
                  {
                     p.offX -= errX;
                     p.offY -= errY;
                     corrections++;
                     largest = Math.max(largest,err);
                  }
               }
               else if(!rolledBack && steps > 0)
               {
                  p.vx = (x - p.startX) / steps;
                  p.vy = (y - p.startY) / steps;
                  p.hasVelocity = true;
               }
               p.drawSprite = null;
               if(Math.abs(p.offX) < 0.5 && Math.abs(p.offY) < 0.5)
               {
                  p.offX = p.offY = 0;
                  continue;
               }
               p.drawSprite = sprite;
               if(!move)
               {
                  continue;
               }
               sprite.x = x + p.offX;
               sprite.y = y + p.offY;
               p.sprite = sprite;
               p.trueX = x;
               p.trueY = y;
               p.shownX = Number(sprite.x);
               p.shownY = Number(sprite.y);
               p.applied = true;
            }
         }
         catch(e:Error)
         {
         }
         rolledBack = false;
      }

      private static function restore() : void
      {
         for each(var p:Object in players)
         {
            if(p.applied)
            {
               p.applied = false;
               try
               {
                  if(Math.abs(Number(p.sprite.x) - p.shownX) < 0.01 && Math.abs(Number(p.sprite.y) - p.shownY) < 0.01)
                  {
                     p.sprite.x = p.trueX;
                     p.sprite.y = p.trueY;
                  }
               }
               catch(e:Error)
               {
               }
            }
         }
      }

      private static function spriteOf(player:Object) : Object
      {
         var anim:Object = player.var_11807;
         return anim != null ? anim.mTheDO3D : null;
      }

      private static function entry(player:Object) : Object
      {
         var id:uint = uint(player.var_14656);
         var p:Object = players[id];
         if(p == null)
         {
            p = players[id] = {"offX":0,"offY":0,"vx":0,"vy":0,"hasVelocity":false,"hasStart":false,"applied":false,"drawSprite":null};
         }
         return p;
      }
   }
}
