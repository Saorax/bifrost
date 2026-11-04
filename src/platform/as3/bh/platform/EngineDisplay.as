package bh.platform
{
   import flash.utils.getDefinitionByName;

   public final class EngineDisplay
   {
      public static const RENDERERS:Array = ["dx11","dx12","vulkan"];
      public static const RENDERER_NAMES:Array = ["DirectX 11","DirectX 12","Vulkan"];
      public static const MODES:Array = ["game","windowed","borderless","fullscreen"];
      public static const MODE_NAMES:Array = ["Game's setting","Windowed","Borderless","Exclusive fullscreen"];

      private static var looked:Boolean = false;
      private static var api:Object = null;

      public function EngineDisplay()
      {
      }

      private static function get engine() : Object
      {
         if(!looked)
         {
            looked = true;
            try
            {
               api = getDefinitionByName("port.engine.Display");
            }
            catch(e:Error)
            {
               api = null;
            }
         }
         return api;
      }

      public static function get available() : Boolean
      {
         return engine != null;
      }

      private static function setting(name:String, fallback:*) : *
      {
         try
         {
            var value:* = engine.settings[name];
            return value === undefined || value === null ? fallback : value;
         }
         catch(e:Error)
         {
         }
         return fallback;
      }

      public static function get running() : String
      {
         try
         {
            return String(engine.renderer);
         }
         catch(e:Error)
         {
         }
         return "";
      }

      public static function get renderer() : String
      {
         return String(setting("renderer",running));
      }

      public static function get mode() : String
      {
         return String(setting("displayMode","game"));
      }

      public static function get vsync() : Boolean
      {
         return Boolean(setting("vsync",true));
      }

      public static function get monitor() : int
      {
         return int(setting("monitor",-1));
      }

      public static function nameOf(list:Array, names:Array, value:String) : String
      {
         var at:int = list.indexOf(value);
         return at < 0 ? value : String(names[at]);
      }

      public static function step(list:Array, value:*, dir:int) : *
      {
         var at:int = list.indexOf(value);
         return list[(Math.max(0,at) + dir + list.length) % list.length];
      }

      public static function setRenderer(name:String) : void
      {
         call("setRenderer",name);
      }

      public static function setMode(name:String) : void
      {
         call("setDisplayMode",name);
      }

      public static function setVsync(on:Boolean) : void
      {
         call("setVsync",on);
      }

      public static function setMonitor(index:int) : void
      {
         call("setMonitor",index);
      }

      private static function call(method:String, value:*) : void
      {
         try
         {
            var ok:* = engine[method](value,true);
            Platform.log("engine display: " + method + " " + value + (ok === false ? " refused" : ""));
         }
         catch(e:Error)
         {
            Platform.log("engine display: " + method + " failed: " + e.message);
         }
      }
   }
}
