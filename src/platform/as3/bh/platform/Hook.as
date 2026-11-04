package bh.platform
{
   import flash.utils.getTimer;

   public final class Hook
   {
      private static const SLOW:int = 250;

      public var name:String;

      private var handlers:Vector.<Function> = new Vector.<Function>();

      public function Hook(name:String)
      {
         this.name = name;
      }

      public function add(handler:Function) : void
      {
         if(handlers.indexOf(handler) < 0)
         {
            var list:Vector.<Function> = handlers.concat();
            list.push(handler);
            handlers = list;
         }
      }

      public function remove(handler:Function) : void
      {
         var i:int = handlers.indexOf(handler);
         if(i >= 0)
         {
            var list:Vector.<Function> = handlers.concat();
            list.splice(i,1);
            handlers = list;
         }
      }

      public function get count() : int
      {
         return handlers.length;
      }

      public function fire0() : void
      {
         run(0,null,null,null,false);
      }

      public function fire1(a:*) : void
      {
         run(1,a,null,null,false);
      }

      public function fire2(a:*, b:*) : void
      {
         run(2,a,b,null,false);
      }

      public function fire3(a:*, b:*, c:*) : void
      {
         run(3,a,b,c,false);
      }

      public function fireUntilHandled0() : Boolean
      {
         return run(0,null,null,null,true);
      }

      public function fireUntilHandled1(a:*) : Boolean
      {
         return run(1,a,null,null,true);
      }

      public function fireUntilHandled2(a:*, b:*) : Boolean
      {
         return run(2,a,b,null,true);
      }

      public function fireUntilHandled3(a:*, b:*, c:*) : Boolean
      {
         return run(3,a,b,c,true);
      }

      private function run(n:int, a:*, b:*, c:*, until:Boolean) : Boolean
      {
         var list:Vector.<Function> = handlers;
         var count:int = list.length;
         for(var i:int = 0; i < count; i++)
         {
            var handler:Function = list[i];
            var started:int = getTimer();
            try
            {
               var result:* = n == 0 ? handler() : (n == 1 ? handler(a) : (n == 2 ? handler(a,b) : handler(a,b,c)));
               if(getTimer() - started > SLOW)
               {
                  Platform.log("hook " + name + " handler " + i + " took " + (getTimer() - started) + " ms");
               }
               if(until && result === true)
               {
                  return true;
               }
            }
            catch(e:Error)
            {
               Platform.log("hook " + name + " handler failed: " + e);
            }
         }
         return false;
      }

      public function fire(... args) : void
      {
         var list:Vector.<Function> = handlers;
         var count:int = list.length;
         for(var i:int = 0; i < count; i++)
         {
            var handler:Function = list[i];
            var started:int = getTimer();
            try
            {
               handler.apply(null,args);
               if(getTimer() - started > SLOW)
               {
                  Platform.log("hook " + name + " handler " + i + " took " + (getTimer() - started) + " ms");
               }
            }
            catch(e:Error)
            {
               Platform.log("hook " + name + " handler failed: " + e);
            }
         }
      }

      public function filter(value:*, ... args) : *
      {
         var list:Vector.<Function> = handlers;
         var count:int = list.length;
         for(var i:int = 0; i < count; i++)
         {
            var handler:Function = list[i];
            try
            {
               var result:* = handler.apply(null,[value].concat(args));
               if(result != null)
               {
                  value = result;
               }
            }
            catch(e:Error)
            {
               Platform.log("hook " + name + " handler failed: " + e);
            }
         }
         return value;
      }

      public function fireUntilHandled(... args) : Boolean
      {
         var list:Vector.<Function> = handlers;
         var count:int = list.length;
         for(var i:int = 0; i < count; i++)
         {
            var handler:Function = list[i];
            try
            {
               if(handler.apply(null,args) === true)
               {
                  return true;
               }
            }
            catch(e:Error)
            {
               Platform.log("hook " + name + " handler failed: " + e);
            }
         }
         return false;
      }
   }
}
