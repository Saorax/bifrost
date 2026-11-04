package bh.platform
{
   import flash.display.DisplayObject;
   import flash.display.DisplayObjectContainer;
   import flash.display.Stage;
   import flash.geom.Matrix;

   public final class Layers
   {
      public function Layers()
      {
      }

      public static function screens() : DisplayObjectContainer
      {
         return class_687.var_15207;
      }

      public static function screenOf(d:DisplayObject) : DisplayObjectContainer
      {
         var top:DisplayObjectContainer = class_687.var_15207;
         var low:DisplayObjectContainer = class_687.var_8390;
         while(d != null && d.parent != null)
         {
            if(d.parent === top || d.parent === low)
            {
               return d as DisplayObjectContainer;
            }
            d = d.parent;
         }
         return null;
      }

      public static function put(layer:DisplayObject, holder:DisplayObjectContainer, s:Stage, bottom:Boolean = false) : void
      {
         if(layer == null)
         {
            return;
         }
         if(holder == null || holder.stage == null)
         {
            holder = s;
         }
         if(holder == null)
         {
            return;
         }
         if(layer.parent !== holder)
         {
            holder.addChildAt(layer,bottom ? 0 : holder.numChildren);
         }
         else
         {
            var at:int = bottom ? 0 : holder.numChildren - 1;
            if(holder.getChildIndex(layer) != at)
            {
               holder.setChildIndex(layer,at);
            }
         }
         var m:Matrix = holder === s ? new Matrix() : holder.transform.concatenatedMatrix;
         m.invert();
         var now:Matrix = layer.transform.matrix;
         if(now.a != m.a || now.b != m.b || now.c != m.c || now.d != m.d || now.tx != m.tx || now.ty != m.ty)
         {
            layer.transform.matrix = m;
         }
      }
   }
}
