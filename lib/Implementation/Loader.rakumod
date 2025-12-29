use	v6.d;

use	Glob::Grammar;
use	Glob::ToRegexActions;

role	Implementation::Loader {
	has	Lock	%!library-locks;

	=begin pod

	=head1 method load-library

	method	load-library(Str :$type = 'Database::Storage::Memory', *%parameters)

	Loads the library in question, and makes an object of the named type
	=end pod
	method	load-library(Str :$type, *%parameters) {
		%!library-locks{$type}:exists or %!library-locks{$type} = Lock.new();
		my $library-object = %!library-locks{$type}.protect: {
			# Load the relevant module
			my \M = (require ::($type));

			# Create the object
			M.new(|%parameters);
		}

		without $library-object { .throw }

		return $library-object;
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

	method load-module-pattern(:@paths = [], :@regexes = [], :@globs = []) {
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
		my %passes;
		my %fails;
		for @module-names -> $module-name {
			my $object = try self.load-library(type => $module-name);
			if $! {
				%fails{$module-name} = $!;
			} else {
				%passes{$module-name} = $object;
			}
		}

		return %passes, %fails;
	}
} # End Loader

