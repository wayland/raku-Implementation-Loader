use	v6.d;

class	TestModule::WithParams {
	has	Str	$.name;
	has	Int	$.value;
	
	submethod	BUILD(:$!name = "default", :$!value = 0) {}
	
	method	get-info() {
		return "Name: $!name, Value: $!value";
	}
}

