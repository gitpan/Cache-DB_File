# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl 1.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 15;
BEGIN { use_ok('Cache::DB_File', 'use Cache::DB_File') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

my $cache = Cache::DB_File->new(
	expire		=> '1h 2 min 3seconds',
	max_size	=> 10,
	filename	=> 't/testcache.db'
);
ok($cache, 'Create new cache instance');
ok(-f 't/testcache.db', 'db was created');
ok(-f 't/testcache.db.idx', 'index db was created');

my $testfile = 'Makefile.PL';
ok(open(T, "<$testfile"), 'can open Makefile for testing');
my @filecontent = <T>;

for(my $x=0; $x<=$#filecontent; $x++) {
	unless($cache->fetch($x+1)) {
		$cache->store($x+1, $filecontent[$x]);
		$cache->fetch($x+1);
	}
}

ok($cache->fetch(1), "Fetch first element");
ok(not($cache->fetch(scalar@filecontent+1)), 'Fetch nonexistant element');
is($cache->fetch(4), $filecontent[3], 'Cache and original is the same');
my $middle = int(scalar @filecount / 2);
is($cache->fetch($middle+1), $filecontent[$middle], 'Middle and original middle is the same');
is(Cache::DB_File::calc_time_expr('1second'), 1, 'Is 1second, 1 second?');
is(Cache::DB_File::calc_time_expr('1 second'), 1, 'Is 1 second, 1 second?');
is(Cache::DB_File::calc_time_expr('1s'), 1, 'Is 1s 1 second?');
is(Cache::DB_File::calc_time_expr('1minute'), 60, 'Is 1minute, 60 seconds?');
is(Cache::DB_File::calc_time_expr('1h 3minutes 4 sec'), 3784, 'Is 1h 3minutes 4 sec, 3784 seconds?');

ok($cache->close, 'Cache::DB_File->close');
