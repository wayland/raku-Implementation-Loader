# Abstract::Factory::Helper

Will dynamically create classes with the same name as the modules.  Modules can be specified with the glob language.

# Primary use: .load-module-pattern()

```
use	Abstract::Factory::Helper;

class Foo does Abstract::Factory::Helper {}

my $loader = Foo.new();
my ($passes, $fails) = $loader.load-module-pattern(
	:paths(['lib', 't']),
	:globs(["Lo?derTest*"]),
);
$passing-class = $passes<LoaderTestPassing>
$passing-class.the-method()
```
The above code will try to load eg. `LoaderTestPassing` and `LoaderTestFailing`, and even `LoZderTestZZZZZ`,
but will ignore `IgnoreLoaderTest`.  

It will also call `.the-method` on the new object that's a `LoaderTestPassing`.

.load-module-pattern can also take a `:regexes` key that contains an array of regexes.
If a module matches any of the regexes or globs, then this will try to load the
class.  

See `.available-modules` for info on the `:paths` option.  

# .available-modules(@lib-paths)

Returns a list of all modules that could be loaded.  The @lib-paths are the library
paths to search (eg. anything you declare with `use lib 'path'` will need to be
repeated here).  

# .load-library(Str :$type, *%parameters)

Loads the class specified in the `$type` string from the module of the same name.  
%parameters are passed to the .new() method on the class.  
