package flash.errors;

class ArgumentError extends flash.errors.Error {
	public function new(message:String = "") {
		super(message);
		name = "ArgumentError";
	}
}
