package flash.errors;

class IOError extends flash.errors.Error {
	public function new(message:String = "") {
		super(message);
		name = "IOError";
	}
}
