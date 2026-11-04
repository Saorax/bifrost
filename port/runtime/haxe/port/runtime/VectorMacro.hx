package port.runtime;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.TypeTools;
import haxe.macro.ComplexTypeTools;

class VectorMacro {
   public static function construct(args:Array<Expr>):Expr {
      var element = elementType(Context.getExpectedType());
      if (Context.defined("hl")) {
         var length = args.length > 0 ? args[0] : macro 0;
         var fixed = args.length > 1 ? args[1] : macro false;
         var fill = defaultValue(element);
         return macro (Vector.native($length, $fixed, $fill) : Vector<$element>);
      }
      return macro (new openfl.Vector<$element>($a{args}) : Vector<$element>);
   }

   static function defaultValue(element:ComplexType):Expr {
      var type = Context.followWithAbstracts(ComplexTypeTools.toType(element));
      return switch (type) {
         case TAbstract(_.get() => {name: "Int" | "UInt"}, []): macro 0;
         case TAbstract(_.get() => {name: "Float"}, []): macro 0.0;
         case TAbstract(_.get() => {name: "Bool"}, []): macro false;
         default: macro null;
      };
   }

   static function elementType(expected:Null<Type>):ComplexType {
      if (expected != null) {
         switch (expected) {
            case TAbstract(_.get() => {name: "Vector"}, [element]) | TType(_.get() => {name: "Vector"}, [element]):
               return TypeTools.toComplexType(element);
            case TLazy(f):
               return elementType(f());
            default:
         }
      }
      Context.error("Vector construction off Flash needs its element type from the expected type, found "
         + (expected == null ? "none" : TypeTools.toString(expected)), Context.currentPos());
      return null;
   }
}
#end
