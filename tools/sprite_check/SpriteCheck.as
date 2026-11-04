package
{
   import flash.desktop.NativeApplication;
   import flash.display.BitmapData;
   import flash.display.IGraphicsData;
   import flash.display.GraphicsGradientFill;
   import flash.display.GraphicsSolidFill;
   import flash.display.Loader;
   import flash.display.MovieClip;
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.events.IOErrorEvent;
   import flash.filesystem.File;
   import flash.filesystem.FileMode;
   import flash.filesystem.FileStream;
   import flash.geom.Matrix;
   import flash.geom.Rectangle;
   import flash.system.ApplicationDomain;
   import flash.system.LoaderContext;
   import flash.utils.ByteArray;
   import flash.utils.setTimeout;

   public class SpriteCheck extends Sprite
   {
      private var logPath:String;
      private var classes:Array;
      private var mode:String = "full";
      private var loader:Loader;
      private var index:int = 0;
      private var canvas:Sprite = new Sprite();
      private var redraw:Sprite = new Sprite();

      public function SpriteCheck()
      {
         super();
         var cfg:Object;
         try
         {
            cfg = JSON.parse(read(File.applicationDirectory.resolvePath("spritecheck.json")));
         }
         catch(e:Error)
         {
            finish();
            return;
         }
         logPath = cfg.log;
         classes = cfg.classes;
         if(cfg.mode)
         {
            mode = cfg.mode;
         }
         log("start " + cfg.swf + " (" + classes.length + " classes)");
         addChild(canvas);
         var bytes:ByteArray = new ByteArray();
         var s:FileStream = new FileStream();
         s.open(new File(cfg.swf),FileMode.READ);
         s.readBytes(bytes);
         s.close();
         var ctx:LoaderContext = new LoaderContext(false,new ApplicationDomain(ApplicationDomain.currentDomain));
         ctx.allowCodeImport = true;
         loader = new Loader();
         loader.contentLoaderInfo.addEventListener(Event.COMPLETE,loaded);
         loader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR,function(e:Event):void
         {
            log("load failed: " + e);
            finish();
         });
         loader.loadBytes(bytes,ctx);
      }

      private function loaded(e:Event) : void
      {
         log("loaded");
         setTimeout(next,1);
      }

      private function next() : void
      {
         if(index >= classes.length)
         {
            log("done: all " + classes.length + " classes passed");
            finish();
            return;
         }
         var name:String = classes[index++];
         try
         {
            check(name);
         }
         catch(err:Error)
         {
            log("error " + name + ": " + err.name + " #" + err.errorID + " " + err.message);
         }
         setTimeout(next,1);
      }

      private function check(name:String) : void
      {
         log("class " + name);
         var cls:Class = loader.contentLoaderInfo.applicationDomain.getDefinition(name) as Class;
         log("  " + name + ": new");
         var mc:MovieClip = new cls() as MovieClip;
         log("  " + name + ": gotoAndStop(1)");
         mc.gotoAndStop(1);
         log("  " + name + ": stopAllMovieClips, a = " + mc["a"]);
         try
         {
            mc["stopAllMovieClips"]();
         }
         catch(stopErr:Error)
         {
         }
         canvas.addChild(mc);
         var frames:int = mc.totalFrames;
         for(var f:int = 1; f <= frames; f++)
         {
            log("  " + name + " frame " + f + "/" + frames + ": bounds");
            mc.gotoAndStop(f);
            var b:Rectangle = mc.getBounds(canvas);
            if(b.width < 1 || b.height < 1)
            {
               continue;
            }
            log("  " + name + " frame " + f + ": readGraphicsData");
            var data:Vector.<IGraphicsData> = mc.graphics.readGraphicsData(true);
            log("  " + name + " frame " + f + ": " + data.length + " entries; recolour");
            if(mode == "read")
            {
               continue;
            }
            for(var i:int = 0; i < int(data.length / 3); i++)
            {
               var d:IGraphicsData = data[i * 3];
               if(d is GraphicsSolidFill)
               {
                  GraphicsSolidFill(d).color = 0x336699;
               }
               else if(d is GraphicsGradientFill)
               {
                  GraphicsGradientFill(d).colors[0] = 0xFF336699;
                  GraphicsGradientFill(d).colors[1] = 0xFF996633;
               }
            }
            log("  " + name + " frame " + f + ": drawGraphicsData");
            redraw.graphics.clear();
            redraw.graphics.drawGraphicsData(data);
            if(mode == "draw")
            {
               continue;
            }
            log("  " + name + " frame " + f + ": rasterize");
            var bmp:BitmapData = new BitmapData(Math.min(4096,int(b.width) + 4),Math.min(4096,int(b.height) + 4),true,0);
            var m:Matrix = new Matrix(1,0,0,1,-b.x,-b.y);
            bmp.draw(redraw,m,null,null,null,true);
            bmp.draw(mc,m,null,null,null,true);
            bmp.dispose();
         }
         canvas.removeChild(mc);
         log("  " + name + " ok");
      }

      private function read(f:File) : String
      {
         var s:FileStream = new FileStream();
         s.open(f,FileMode.READ);
         var t:String = s.readUTFBytes(s.bytesAvailable);
         s.close();
         return t;
      }

      private function log(line:String) : void
      {
         try
         {
            var s:FileStream = new FileStream();
            s.open(new File(logPath),FileMode.APPEND);
            s.writeUTFBytes(line + "\r\n");
            s.close();
         }
         catch(e:Error)
         {
         }
      }

      private function finish() : void
      {
         NativeApplication.nativeApplication.exit();
      }
   }
}
