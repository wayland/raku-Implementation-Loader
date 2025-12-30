use	v6.d;

use	Glob::Grammar;
use	Glob::ToRegexActions;

role	Implementation::Loader {
	has	Lock	%!load-locks;
	has	Lock	%!library-locks;

	=begin pod

	=head1 method load-library

	method	load-library(
		Str :$type,		     # The type to load, as a string
		Str :$module-name,   # The module to load, as a string; defaults to $type
		Str :$does,          # When the type is loaded, check if it does this role
		Bool :$return-type = False, # Return the type object instead of an instance
		*%parameters            # Additional parameters to pass to the type's .new() method
	)

	Loads the library in question, and makes an object of the named type.
	Supports separating module name from type name, role verification, and returning type objects.
	=end pod
	method	load-library(
		Str :$type,
		Str :$module-name,
		Str :$does,
		Bool :$return-type = False,
		*%parameters
	) {
		# Determine which module to load
		my $module-to-load = $module-name // $type;
		
		# Ensure we have a type name (for backward compatibility)
		my $type-name = $type // $module-to-load;
		
		# Backward compatibility: if neither is provided, error
		unless $module-to-load.defined {
			die "Error: Either :module-name or :type must be provided";
		}
		
		%!library-locks{$module-to-load}:exists or %!library-locks{$module-to-load} = Lock.new();
		
		my $result = %!library-locks{$module-to-load}.protect: {
			# Load the module
			my \M = (require ::($module-to-load));
			
			# If type name differs from module name, resolve it
			my \Type = $type-name eq $module-to-load ?? M !! ::($type-name);
			
			# Verify role composition if specified
			if $does.defined {
				my \Role = ::($does);
				unless Type.^does(Role) {
					die "Type {Type.^name} does not do role {$does}";
				}
			}
			
			# Return type object or instance
			if $return-type {
				return Type;
			} else {
				return Type.new(|%parameters);
			}
		}
		
		without $result { .throw }
		return $result;
	}

	=begin pod

	=head1 method available-modules

	method available-modules(@lib-paths = [])

	Scans the specified library paths and installed modules to discover all available Raku modules.

	Returns a sorted list of unique module names found in both the provided library paths and the
	installed module repositories.

	=head2 Parameters

	=item @lib-paths - An array of paths to search for .rakumod files. If empty, only installed modules are returned.

	=head2 Why use this?

	Use this method when you need to:
	=item Discover what modules are available in your system or custom library paths
	=item Build dynamic module selection interfaces
	=item Validate that a module exists before attempting to load it
	=item Generate lists of available implementations for plugin systems

	The method recursively searches directories for .rakumod files and also queries the Raku
	module repository chain for installed modules, giving you a comprehensive view of what's
	available.

	Note that, if you plan on filtering the modules you may be better off with find-module-pattern instead.

	=end pod
	method available-modules(@lib-paths = []) {
		my @lib-mods;
		for @lib-paths.flat>>.IO -> $root {
			my @stack = @($root);
			my @lib-these = gather while @stack {
				with @stack.pop {
					when :d { @stack.append: .dir }
					when .extension.lc eq 'rakumod' {
						take .relative($root).Str.subst('.rakumod', '').subst(/\//, '::', :g)
					}
				}
			}
			@lib-mods.push(|@lib-these);
		}

		my @installed = $*REPO.repo-chain
			.grep(*.^can('installed'))
			.map(*.installed)
			.flat.map(*.meta<name>)
			.grep(*.^name eq 'Str');

		my @all-mods = (@lib-mods, @installed).flat.unique.sort;
		return @all-mods;
	}

	=begin pod

	=head1 method find-module-pattern

	method find-module-pattern(:@paths = [], :@regexes = [], :@globs = [])

	Finds module names that match specified patterns using either regular expressions or glob patterns.

	This method first calls C<available-modules> to get all available modules, then filters them
	based on the provided patterns.

	=head2 Parameters

	=item :@paths - Library paths to search (passed to C<available-modules>)
	=item :@regexes - Array of regular expressions to match against module names
	=item :@globs - Array of glob patterns (e.g., "Foo::Bar::*") to match against module names

	=head2 Why use this?

	Use this method when you need to:
	=item Find all modules matching a specific naming pattern (e.g., all "Implementation::*" modules)
	=item Discover plugins or implementations that follow a naming convention
	=item Filter available modules before loading them
	=item Build dynamic module discovery based on patterns rather than exact names

	This is particularly useful for plugin systems where modules follow a naming convention, allowing
	you to discover and work with multiple implementations without hardcoding their names. The glob
	pattern support makes it easy to use shell-like wildcards (e.g., "MyApp::*::Handler") which are
	more intuitive than writing regular expressions.

	=head2 Example

	=begin code
	# Find all modules matching the glob pattern
	my @found = $loader.find-module-pattern(globs => ['Implementation::*::Backend']);
	
	# Find modules using regex
	my @found = $loader.find-module-pattern(regexes => [/^ Implementation \:\: \w+ \:\: Backend $/]);
	=end code

	=end pod
	method find-module-pattern(:@paths = [], :@regexes = [], :@globs = []) {
		# Get the regex to use with .available-modules()
		my @use-regexes;
		given True {
			when @regexes.Bool {
				@use-regexes.push: |@regexes;
				proceed;
			}
			when @globs.Bool {
				for @globs -> $glob {
					my $match = Glob::Grammar.parse($glob, actions => Glob::ToRegexActions.new());
					my Str $pattern = $match.made;
					@use-regexes.push: qq|rx/$pattern/|.EVAL;
				}
				proceed;
			}
			when ! @globs and !@regexes {
				die "Error: Please pass either globs or regexen";
				# This next line would load every possible module, which probably isn't the greatest idea
				#@use-regexes.push: /./;
			}
		}

		# Call .available-modules()
		my @all-mods = self.available-modules(@paths);
		my @module-names;
		for @use-regexes -> $regex {
			@module-names.push: |@all-mods.grep($regex);
		}
		return @module-names;
	}

	=begin pod

	=head1 method load-module-pattern

	method load-module-pattern(
		:@paths = [], :@regexes = [], :@globs = [], :@modules = [] is copy,
		Str :$does
	)

	Loads multiple modules matching specified patterns and returns a hash of successful and failed loads.

	This method combines pattern matching (via C<find-module-pattern>) with module loading (via
	C<load-library>), making it easy to bulk-load modules that match certain criteria.

	=head2 Parameters

	=item :@paths - Library paths to search for modules
	=item :@regexes - Regular expressions to match module names
	=item :@globs - Glob patterns to match module names
	=item :@modules - Optional pre-specified list of module hashes to load (skips pattern matching)
	=item :$does - Optional role name that loaded types must implement

	=head2 Returns

	Returns a list of two hashes: C<(%passes, %fails)>
	=item C<%passes> - Hash mapping module names to successfully loaded instances
	=item C<%fails> - Hash mapping module names to exception objects for failed loads

	=head2 Why use this?

	Use this method when you need to:
	=item Load multiple plugin modules that follow a naming pattern
	=item Implement a plugin system where you want to discover and load all available implementations
	=item Bulk-load modules with error handling (some may fail, others succeed)
	=item Load modules conditionally based on patterns while verifying they implement a specific role

	This is the high-level method that combines discovery and loading, making it ideal for plugin
	systems where you want to find all matching modules and load them in one operation. The method
	gracefully handles failures, allowing you to see which modules loaded successfully and which
	failed, rather than stopping on the first error.

	=head2 Example

	=begin code
	# Load all backend implementations
	my (%passes, %fails) = $loader.load-module-pattern(
		globs => ['MyApp::Backend::*'],
		does => 'MyApp::Backend'
	);
	
	# Use the successfully loaded backends
	for %passes.kv -> $name, $backend {
		say "Loaded backend: $name";
		$backend.process();
	}
	
	# Report failures
	if %fails {
		warn "Failed to load: " ~ %fails.keys.join(', ');
	}
	=end code

	=end pod
	method load-module-pattern(
		:@paths = [], :@regexes = [], :@globs = [], :@modules is copy = [],
		Str :$does
	) {
		if ! @modules.Bool {
			my @module-names = self.find-module-pattern(:@paths, :@regexes, :@globs);
			for @module-names -> $module-name {
				@modules.push: {
					module-name => $module-name,
					type => $module-name,
					does => $does,
				};
			}
		}

		my %passes;
		my %fails;
		for @modules -> $module {
			my $module-name = $module<module-name>;
			my $object = try self.load-library(|%$module);
			if $! {
				%fails{$module-name} = $!;
			} else {
				%passes{$module-name} = $object;
			}
		}

		return %passes, %fails;
	}
} # End Loader

