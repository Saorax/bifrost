package bh.platform
{
   import flash.display.DisplayObject;
   import flash.display.DisplayObjectContainer;
   import flash.display.Shape;
   import flash.display.Sprite;
   import flash.display.Stage;
   import flash.filesystem.File;
   import flash.geom.Point;
   import flash.geom.Rectangle;
   import flash.utils.getTimer;

   public final class LoadingBackground
   {
      private static var level:Object = null;
      private static var layer:Sprite = null;
      private static var attachedTo:DisplayObjectContainer = null;
      private static var attachedLevel:Object = null;
      private static var musicUntil:int = 0;

      public static function init() : void
      {
         Hooks.matchPreviewShown.add(onShown);
         Hooks.frameRendering.add(onFrame);
      }

      private static function onShown(core:Object, info:Object) : void
      {
         try
         {
            level = info != null ? LevelType.var_3683[info.var_11528] : null;
         }
         catch(e:Error)
         {
            level = null;
         }
      }

      public static function get showing() : Boolean
      {
         try
         {
            return preview() != null;
         }
         catch(e:Error)
         {
         }
         return false;
      }

      private static function preview() : Object
      {
         return shownOf(ScreenManager.sScreenMatchPreviewRanked1v1) || shownOf(ScreenManager.sScreenMatchPreviewRanked2v2) ||
            shownOf(ScreenManager.var_12737);
      }

      private static function shownOf(sc:Object) : Object
      {
         return sc != null && sc.isActive && sc.panelClip != null && sc.panelClip.stage != null ? sc : null;
      }

      private static function onFrame() : void
      {
         try
         {
            if(level == null)
            {
               return;
            }
            var sc:Object = preview();
            if(sc == null)
            {
               if(attachedTo != null)
               {
                  level = null;
                  attachedTo = null;
                  if(layer != null && layer.parent != null)
                  {
                     layer.parent.removeChild(layer);
                  }
                  layer = null;
                  UiKit.forgetPictures();
               }
               return;
            }
            music();
            var clip:DisplayObjectContainer = sc.panelClip as DisplayObjectContainer;
            if(clip === attachedTo && level === attachedLevel && layer != null && layer.parent === clip)
            {
               return;
            }
            attach(clip);
         }
         catch(e:Error)
         {
            Platform.log("loading background: " + e.message);
            level = null;
         }
      }

      private static function music() : void
      {
         if(musicUntil == 0 || getTimer() > musicUntil)
         {
            return;
         }
         var type:Object = level.var_7718;
         if(type == null)
         {
            musicUntil = 0;
            return;
         }
         level.method_3576();
         if(class_727.var_2141 == type.var_4366)
         {
            musicUntil = 0;
            Platform.log("loading background: the map's music (" + level.var_1145 + ")");
         }
      }

      private static function attach(clip:DisplayObjectContainer) : void
      {
         if(layer != null && layer.parent != null)
         {
            layer.parent.removeChild(layer);
         }
         layer = null;
         attachedTo = clip;
         attachedLevel = level;
         var desc:Object = class_250.method_3445(LevelType(level));
         if(desc == null)
         {
            return;
         }
         try
         {
            level.method_410();
            musicUntil = getTimer() + 15000;
         }
         catch(eMusic:Error)
         {
         }
         var s:Stage = clip.stage;
         var tl:Point = clip.globalToLocal(new Point(0,0));
         var br:Point = clip.globalToLocal(new Point(s.stageWidth,s.stageHeight));
         var w:Number = br.x - tl.x;
         var h:Number = br.y - tl.y;
         layer = new Sprite();
         layer.mouseEnabled = layer.mouseChildren = false;
         layer.x = tl.x;
         layer.y = tl.y;
         var levelName:String = String(desc.method_4935("LevelName"));
         var dir:String = desc.exists("AssetDir") ? String(desc.method_4935("AssetDir")) : "";
         var drawn:int = 0;
         var it:* = desc.method_5430();
         var back:Sprite = new Sprite();
         layer.addChild(back);
         var hasBack:Boolean = false;
         var world:Sprite = new Sprite();
         while(it.hasNext())
         {
            var el:Object = it.next();
            if(el.var_4402 == "Background" && !hasBack && el.exists("AssetName"))
            {
               var bg:File = file(levelName,"mapArt/Backgrounds/" + el.method_4935("AssetName"));
               if(bg != null)
               {
                  UiKit.picture(back,bg,w,h,true);
                  hasBack = true;
               }
            }
            else if(el.var_4402 == "Platform" || el.var_4402 == "MovingPlatform")
            {
               drawn += piece(world,el,levelName,dir);
            }
         }
         var b:Rectangle = world.getBounds(world);
         if(drawn > 0 && b.width > 0 && b.height > 0)
         {
            var k:Number = Math.min(w * 0.92 / b.width,h * 0.8 / b.height);
            world.scaleX = world.scaleY = k;
            world.x = w / 2 - (b.x + b.width / 2) * k;
            world.y = h * 0.56 - (b.y + b.height / 2) * k;
            layer.addChild(world);
         }
         var dim:Shape = new Shape();
         dim.graphics.beginFill(0x000814,0.3);
         dim.graphics.drawRect(0,0,w,h);
         dim.graphics.endFill();
         layer.addChild(dim);
         clip.addChildAt(layer,backdropIndex(clip) + 1);
         Platform.log("loading background: " + levelName + " (" + drawn + " pieces)");
      }

      private static function file(levelName:String, path:String) : File
      {
         var modded:File = MapArt.pictureFor(levelName,path);
         if(modded != null)
         {
            return modded;
         }
         var f:File = File.applicationDirectory.resolvePath(path);
         return f.exists ? f : null;
      }

      private static function num(el:Object, name:String, def:Number) : Number
      {
         if(!el.exists(name))
         {
            return def;
         }
         var v:Number = Number(el.method_4935(name));
         return isNaN(v) ? def : v;
      }

      private static function assetPath(dir:String, name:String) : String
      {
         return name.indexOf("../") == 0 ? "mapArt/" + name.substr(3) : "mapArt/" + (dir != "" ? dir + "/" : "") + name;
      }

      private static function piece(parent:Sprite, el:Object, levelName:String, dir:String) : int
      {
         if(el.exists("Theme") || el.exists("ScoringType"))
         {
            return 0;
         }
         var node:Sprite = new Sprite();
         node.x = num(el,"X",0);
         node.y = num(el,"Y",0);
         var sized:Boolean = el.exists("AssetName") && el.exists("W") && el.exists("H");
         node.scaleX = sized ? 1 : (el.exists("Scale") ? num(el,"Scale",1) : num(el,"ScaleX",1));
         node.scaleY = sized ? 1 : (el.exists("Scale") ? num(el,"Scale",1) : num(el,"ScaleY",1));
         node.rotation = num(el,"Rotation",0);
         parent.addChild(node);
         var n:int = 0;
         if(el.exists("AssetName") && el.exists("W") && el.exists("H"))
         {
            var name:String = String(el.method_4935("AssetName"));
            var f:File = name.indexOf(".png") != 0 ? file(levelName,assetPath(dir,name)) : null;
            if(f != null)
            {
               var pw:Number = num(el,"W",0);
               var ph:Number = num(el,"H",0);
               var holder:Sprite = new Sprite();
               holder.graphics.beginFill(0,0);
               holder.graphics.drawRect(0,0,pw,ph);
               holder.graphics.endFill();
               UiKit.picture(holder,f,pw,ph,false);
               node.addChild(holder);
               n++;
            }
         }
         var kids:* = el.method_5430();
         while(kids.hasNext())
         {
            var kid:Object = kids.next();
            if(kid.var_4402 == "Platform" || kid.var_4402 == "Asset" || kid.var_4402 == "MovingPlatform")
            {
               n += piece(node,kid,levelName,dir);
            }
         }
         return n;
      }

      private static function backdropIndex(clip:DisplayObjectContainer) : int
      {
         var s:Stage = clip.stage;
         var screen:Number = s.stageWidth * s.stageHeight;
         var found:int = -1;
         for(var i:int = 0; i < clip.numChildren; i++)
         {
            var ch:DisplayObject = clip.getChildAt(i);
            if(!ch.visible)
            {
               continue;
            }
            var b:Rectangle = ch.getBounds(s).intersection(new Rectangle(0,0,s.stageWidth,s.stageHeight));
            if(b.width * b.height >= screen * 0.9)
            {
               found = i;
            }
            else
            {
               break;
            }
         }
         return found;
      }
   }
}
