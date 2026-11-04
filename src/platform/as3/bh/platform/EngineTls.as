package bh.platform
{
   import flash.filesystem.File;
   import flash.filesystem.FileMode;
   import flash.filesystem.FileStream;
   import flash.utils.getDefinitionByName;

   public final class EngineTls
   {
      public static const FOLDER:String = "tls";

      private static var looked:Boolean = false;

      private static var api:Object = null;

      public function EngineTls()
      {
      }

      private static function get engine() : Object
      {
         if(!looked)
         {
            looked = true;
            try
            {
               api = getDefinitionByName("port.engine.Tls");
            }
            catch(e:Error)
            {
               api = null;
            }
         }
         return api;
      }

      public static function fileName(host:String) : String
      {
         return FOLDER + "/" + host.replace(/[^A-Za-z0-9.\-]/g,"_") + ".pem";
      }

      public static function twinPem(host:String) : String
      {
         if(!host)
         {
            return null;
         }
         try
         {
            var f:File = Platform.dataFile(fileName(host));
            if(!f.exists)
            {
               return null;
            }
            var s:FileStream = new FileStream();
            s.open(f,FileMode.READ);
            var pem:String = s.readUTFBytes(s.bytesAvailable);
            s.close();
            return pem.indexOf("-----BEGIN CERTIFICATE-----") >= 0 ? pem : null;
         }
         catch(e:Error)
         {
            Platform.log("engine tls: reading " + fileName(host) + " failed: " + e.message);
         }
         return null;
      }

      public static function pinServer(host:String) : Boolean
      {
         if(engine == null || !host)
         {
            return false;
         }
         try
         {
            var pem:String = twinPem(host);
            if(pem == null)
            {
               return false;
            }
            var ok:* = engine["pin"](host,pem);
            Platform.log("engine tls: " + host + "'s https " + (ok === true ? "pinned to its own authority" : "not pinned: the engine refused " + fileName(host)));
            return ok === true;
         }
         catch(e:Error)
         {
            Platform.log("engine tls: pinning " + host + " failed: " + e.message);
         }
         return false;
      }
   }
}
