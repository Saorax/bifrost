package bh.platform
{
   internal final class PacedNode
   {
      public static const CAMERA:int = 0;
      public static const LEGEND:int = 1;
      public static const OBJECT:int = 2;

      public var node:Object;
      public var kind:int;
      public var cx:Number;
      public var cy:Number;
      public var csx:Number;
      public var csy:Number;
      public var px:Number = 0;
      public var py:Number = 0;
      public var psx:Number = 0;
      public var psy:Number = 0;
      public var hasPrev:Boolean = false;
      public var drawn:Boolean = false;
      public var seen:uint = 0;
      public var legend:uint = 0;
   }
}
