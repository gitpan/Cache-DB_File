use 5.6.1;
use ExtUtils::MakeMaker;

$PACKAGE = 'Cache::DB_File';
($PACKAGE_FILE = $PACKAGE) =~ s#::#/#g;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
	NAME			=> $PACKAGE,
	VERSION_FROM	=> "lib/$PACKAGE_FILE.pm", # finds $VERSION
	PREREQ_PM		=> {
						'DB_File' => 1
	},
	ABSTRACT_FROM	=> "lib/$PACKAGE_FILE.pm",
	AUTHOR			=> 'Ask Solem Hoel <ask@unixmonks.net>',
	clean 			=> {
						FILES => 't/testcache.db t/testcache.db.idx',
	},
	dist			=> {
						COMPRESS 	=> 'gzip -9',
						SUFFIX		=> '.gz',
						DIST_DEFAULT=> 'all tardist'
	}
);

