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

	method load-module-pattern(
		:@paths = [], :@regexes = [], :@globs = [], :@modules = [] is copy,
		Str :$does
	) {
		if ! @modules.Bool {
			@module-names = self.find-module-pattern(:@paths, :@regexes, :@globs);
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

