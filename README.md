NAME
====

Implementation::Loader - dynamically load implementation modules by name or pattern

DESCRIPTION
===========

This role is for an interface or factory class to compose when that interface has multiple implementations and the program must choose and load one at runtime. The composing class gains methods to find candidate implementation modules, load them, and instantiate the appropriate class.

By convention, each implementation module defines a class with the same name as the module. Candidate modules can be selected by exact name or by glob patterns.

Primary use
-----------

[load-module-pattern](#method load-module-pattern) is the usual entry point: pass `:globs` or `:regexes` to find matching module names, then load each one and collect successes and failures in two hashes.

METHODS
=======

The methods below are documented in the order they are defined in this role.

method load-library
===================

    method load-library(
        Str :$type,
        Str :$module-name,
        Str :$does,
        Bool :$return-type = False,
        *%parameters
    )

Parameters
----------

  * `:$type` - The type to load, as a string

  * `:$module-name` - The module to load, as a string; defaults to `:$type`

  * `:$does` - When the type is loaded, check if it does this role

  * `:$return-type` - Return the type object instead of an instance (default `False`)

  * `*%parameters` - Additional parameters passed to the type's `.new` method

Loads the library in question, and makes an object of the named type. When `:$type` names a module whose main class has the same name, that class is loaded and instantiated. Any additional arguments are passed to the type's `.new` method.

Supports separating module name from type name, role verification, and returning type objects instead of instances.

method available-modules
========================

    method available-modules(@lib-paths = [])

Scans the specified library paths and installed modules to discover all available Raku modules.

Returns a sorted list of unique module names found in both the provided library paths and the installed module repositories.

Parameters
----------

  * @lib-paths - An array of paths to search for .rakumod files. If empty, only installed modules are returned. Anything you declare with `use lib 'path'` will need to be repeated here.

Why use this?
-------------

Use this method when you need to:

  * Discover what modules are available in your system or custom library paths

  * Build dynamic module selection interfaces

  * Validate that a module exists before attempting to load it

  * Generate lists of available implementations for plugin systems

The method recursively searches directories for .rakumod files and also queries the Raku module repository chain for installed distributions, using each distribution's `provides` metadata so plugin modules are listed by their loadable module names.

Note that, if you plan on filtering the modules you may be better off with [find-module-pattern](#method find-module-pattern) instead.

method find-module-pattern
==========================

    method find-module-pattern(:@paths = [], :@regexes = [], :@globs = [])

Finds module names that match specified patterns using either regular expressions or glob patterns.

This method first calls `available-modules` to get all available modules, then filters them based on the provided patterns.

Parameters
----------

  * :@paths - Library paths to search (passed to `available-modules`)

  * :@regexes - Array of regular expressions to match against module names

  * :@globs - Array of glob patterns (e.g., "Foo::Bar::*") to match against module names

Why use this?
-------------

Use this method when you need to:

  * Find all modules matching a specific naming pattern (e.g., all "Implementation::*" modules)

  * Discover plugins or implementations that follow a naming convention

  * Filter available modules before loading them

  * Build dynamic module discovery based on patterns rather than exact names

This is particularly useful for plugin systems where modules follow a naming convention, allowing you to discover and work with multiple implementations without hardcoding their names. The glob pattern support makes it easy to use shell-like wildcards (e.g., "MyApp::*::Handler") which are more intuitive than writing regular expressions.

Example
-------

    # Find all modules matching the glob pattern
    my @found = $loader.find-module-pattern(globs => ['Implementation::*::Backend']);

    # Find modules using regex
    my @found = $loader.find-module-pattern(regexes => [/^ Implementation \:\: \w+ \:\: Backend $/]);

method load-module-pattern
==========================

    method load-module-pattern(
        :@paths = [], :@regexes = [], :@globs = [], :@modules = [] is copy,
        Str :$does
    )

Loads multiple modules matching specified patterns and returns a hash of successful and failed loads.

This method combines pattern matching (via `find-module-pattern`) with module loading (via `load-library`), making it easy to bulk-load modules that match certain criteria.

Parameters
----------

  * :@paths - Library paths to search for modules

  * :@regexes - Regular expressions to match module names

  * :@globs - Glob patterns to match module names

  * :@modules - Optional pre-specified list of module hashes to load (skips pattern matching)

  * :$does - Optional role name that loaded types must implement

Returns
-------

Returns a list of two hashes: `(%passes, %fails)`

  * `%passes` - Hash mapping module names to successfully loaded instances

  * `%fails` - Hash mapping module names to exception objects for failed loads

Why use this?
-------------

Use this method when you need to:

  * Load multiple plugin modules that follow a naming pattern

  * Implement a plugin system where you want to discover and load all available implementations

  * Bulk-load modules with error handling (some may fail, others succeed)

  * Load modules conditionally based on patterns while verifying they implement a specific role

This is the high-level method that combines discovery and loading, making it ideal for plugin systems where you want to find all matching modules and load them in one operation. The method gracefully handles failures, allowing you to see which modules loaded successfully and which failed, rather than stopping on the first error.

If a module matches any of the regexes or globs, this method will try to load the corresponding class. See [available-modules](#method available-modules) for how the `:@paths` option controls which directories are searched.

Example
-------

    use Implementation::Loader;
    class Foo does Implementation::Loader {}
    my $loader = Foo.new;
    my ($passes, $fails) = $loader.load-module-pattern(
	    :paths(['lib', 't']),
	    :globs(['Lo?derTest*']),
    );
    my $passing-class = $passes<LoaderTestPassing>;
    $passing-class.the-method;

The glob above will try to load modules such as `LoaderTestPassing` and `LoaderTestFailing`, and even `LoZderTestZZZZZ`, but will ignore `IgnoredLoaderTest`. Successfully loaded objects can be used immediately, as with `LoaderTestPassing` above.

`load-module-pattern` also accepts `:regexes` with an array of regular expressions; a module is loaded when its name matches any glob or regex.

    # Load all backend implementations, verifying a role
    my (%passes, %fails) = $loader.load-module-pattern(
	    globs => ['MyApp::Backend::*'],
	    does => 'MyApp::Backend'
    );
    for %passes.kv -> $name, $backend {
	    say "Loaded backend: $name";
	    $backend.process;
    }
    if %fails {
	    warn "Failed to load: " ~ %fails.keys.join(', ');
    }

