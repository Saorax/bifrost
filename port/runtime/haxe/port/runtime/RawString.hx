package port.runtime;

#if flash
@:native("String") extern class RawString extends flash.errors.Error {}
#else
typedef RawString = String;
#end
