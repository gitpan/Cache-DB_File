# (c) 2002 ask@unixmonks.net
package Cache::DB_File;
use strict;
use Carp;
use FileHandle;
use DB_File;
our $VERSION = '0.2';

my(%memcache, %memcache_idx);
my $m = get_days_in_month();
my %valid_options = (
	FILENAME	=> 1,
	EXPIRE 		=> 1,
	MAX_SIZE 	=> 1,
	DB_TYPE		=> 1,
	DB_FLAGS	=> 1,
	DB_MODE		=> 1,
	HIGHLOW		=> 1,
);

# Preloaded methods go here.

use constant DISK   => 100;
use constant MEMORY => 200;
use constant T_SEC  => 1;	 	# 1*1
use constant T_MIN  => 60;	 	# 1*60
use constant T_HOUR	=> 3600; 	# 60*60
use constant T_DAY  => 86400; 	# 60*60*24
use constant T_WEEK => 604800;	# 60*60*60*7
use constant T_YEAR => 31536000;# 60*60*24*3600
sub T_MON {T_DAY*$m};

# ---- CONSTRUCTOR --------------------------------------- #

sub new
{
	my($pkg, %argv) = @_;
	$pkg = ref $pkg || $pkg;
	my $self = {
		EXPIRE		=>	'30m',
		MAX_SIZE	=>	500,
		DB_TYPE		=>  $DB_HASH,
		DB_FLAGS	=>  O_CREAT|O_RDWR,
		DB_MODE		=>	0640,
		HIGHLOW		=>  '10m',
	};
	bless $self, $pkg;

	while(my($opt, $val) = each %argv) {
		$self->setopt($opt, $val);
	}

	$self->setopt('highlow',
		calc_time_expr($self->getopt('highlow'))
	);

	$self->initialize;
	
	return $self;
}

# ---- ACCESSORS --------------------------------------- #

sub setopt
{
	my($self, $opt, $val) = @_;
	$opt = uc $opt;
	if($valid_options{$opt}) {
		$self->{$opt} = $val
	} else {
		carp "Unknown option to Cache::DB_File: $opt"
	}
}

sub getopt {
	$_[0]->{uc $_[1]}
}

sub cache
{
	my($self, $cache) = @_;
	if(ref $cache) {
		$self->{CACHE} = $cache;
	} else {
		return $self->{CACHE};
	}
}
sub index
{
	my($self, $index) = @_;
	if(ref $index) {
		$self->{INDEX} = $index;
	} else {
		return $self->{INDEX};
	}
}
sub dbf
{
	my($self, $dbf) = @_;
	if($dbf) {
		$self->{DBF} = $dbf;
	} else {
		return $self->{DBF};
	}
}
sub dbf_index
{
	my($self, $dbf) = @_;
	if($dbf) {
		$self->{DBF_INDEX} = $dbf;
	} else {
		return $self->{DBF_INDEX};
	}
}

# ---- MAIN METHODS --------------------------------------- #

sub fetch
{
	my($self, $key) = @_;
	my($in, $ret, @pass);
	if($memcache_idx{$key}) {
		$in  = MEMORY;
		@pass = split(' ', $memcache_idx{$key}, 3);
	}
	elsif($self->index->{$key}) {
		$in = DISK;
		@pass = split(' ', $self->index->{$key}, 3);
	}
	else {
		return undef;
	}

	$self->update($in, $key, @pass);
	if(scalar keys %memcache_idx >= $self->getopt('max_size')) {
		$self->maintain($key, $in, @pass);
	}
	return $in == MEMORY ? $memcache{$key} : $self->cache->{$key};
}

sub store
{
	my($self, $key, $value, $expire) = @_;
	$self->collect_garbage;
	$expire ||= $self->getopt('expire');
	$expire = calc_time_expr($expire);

	$memcache_idx{$key} = join(' ',
		time, (time + $expire), 0
	);
	$memcache{$key} = $value;
}

sub update
{
	my($self, $in, $key, $time_s, $time_e, $hits) = @_;
	my $href = ($in == MEMORY) ? \%memcache_idx : $self->index;

	$href->{$key} = join(' ', time, $time_e, ++$hits);
}

sub initialize
{
	my($self) = @_;
	croak "Missing filename option to Cache::DB_File"
		unless $self->getopt('filename');
	
	my $X = tie my %cache, 'DB_File',
		$self->getopt('filename'),
		$self->getopt('db_flags'),
		$self->getopt('db_mode'),
		$self->getopt('db_type')
	;
	$self->cache(\%cache);
	$self->dbf($X);
	my $Y = tie my %index, 'DB_File',
		$self->getopt('filename').'.idx',
		$self->getopt('db_flags'),
		$self->getopt('db_mode'),
		$self->getopt('db_type')
	;
	$self->index(\%index);
	$self->dbf_index($Y);
}

sub close
{
	my($self) = @_;	
	my $cache = $self->cache;
	my $index = $self->index;
	$self->all_mem_to_disk;
	$self->dbf->sync() if ref $self->dbf;
	$self->dbf_index->sync() if ref $self->dbf_index;
	untie $cache if ref $cache;
	untie $index if ref $index;
}

sub collect_garbage
{
	my($self) = @_;
	my $db_changed = 0;

	foreach my $in ((MEMORY, DISK)) {
		my $cache = $in == MEMORY ? \%memcache : $self->cache;
		my $index = $in == MEMORY ? \%memcache_idx : $self->index;
		my $index_size = scalar keys %$index;
		my @sorted_by_hits = ();
		while(my($key, $value) = each %$index)
		{
			my($t_start, $t_expire, $hits)
				= split(' ', $value, 3);
			if($t_expire && time >= $t_expire) {
				delete $cache->{$key};
				delete $index->{$key};
				++$db_changed, $index_size--;
			}
			else {
				push(@sorted_by_hits, "$hits:$key") if $in == MEMORY;
			}
		}

		if($in == MEMORY) {
			if($index_size >= $self->getopt('max_size'))
			{
				@sorted_by_hits = sort{
					($a) = split ':', $a, 1;
					($b) = split ':', $b, 1;
					$a <=> $b;
				} @sorted_by_hits;
			
				until($index_size <= $self->getopt('max_size'))
				{
					print "HERE I AM\n";
					my($hits, $key) = split(':', shift @sorted_by_hits, 1);
					$self->move_to_disk($key, 0, 0);
					++$db_changed, $index_size--;
				}
			}
		}
	}

	if($db_changed) {
		$self->sync;
	}
}

sub sync
{
	my($self) = @_;
	$self->dbf->sync();
	$self->dbf_index->sync();
	return 1;
}
			
sub maintain
{
	my($self, $key, $in, $time_s, $time_e, $hits) = @_;
	if($in == MEMORY) {
		if(time >= ($time_s + $self->getopt('highlow'))) {
			if($self->is_low(MEMORY, $hits)) {
				move_to_disk($key, $hits, $time_e);
			}
		}
		return;
	}
	if($in == DISK) {
		if(time <= ($time_s + $self->getopt('highlow'))) {
			if($self->is_high(DISK, $hits)) {
				move_to_mem($key, $hits, $time_e);
			}
		}
		return;
	}
	$self->sync();
}

sub move_to_disk
{
	my($self, $key, $hits, $time_e) = @_;
	$self->index->{$key} = delete $memcache_idx{$key};
	$self->cache->{$key} = delete $memcache{$key};
}
sub move_to_mem
{
	my($self, $key, $hits, $time_e) = @_;
	$memcache{$key} = delete $self->cache->{$key};
	$memcache_idx{$key} = delete $self->index->{$key};
}

sub all_mem_to_disk
{
	my($self) = @_;
	while(my($key, $val) = each %memcache_idx) {
		my($time_s, $time_e, $hits)
			= split(' ', $val, 3);
		$self->move_to_disk($key, $hits, $time_e);
	}
}
		
sub get_highest
{
	my($self, $hashref) = @_;
	return [reverse sort{
		($a) = split ':', $a, 1;
		($b) = split ':', $b, 1;
		$a <=> $b;
	} keys %$hashref]->[0];
}

sub get_lowest
{
	my($self, $hashref) = @_;
	return [sort{
		($a) = split ':', $a, 1;
		($b) = split ':', $b, 1;
		$a <=> $b;
	} keys %$hashref]->[0];
}

sub is_low
{
	my($self, $in, $h) = @_;
	my $e = ($in == MEMORY)
		? get_highest(\%memcache_idx)
		: get_highest($self->index)
	;
	return 0 unless $h;
	return ($h * $e / 4 <= $e / $h);
}

sub is_high
{
	my($self, $in, $h) = @_;
	my $e = ($in == MEMORY)
		? get_lowest(\%memcache_idx)
		: get_lowest($self->index)
	;
	return 0 unless $e;
	return ($h * $e / 4 >= $e / $h);
}	

# ---- TIME FUNCTIONS --------------------------------------- #


sub get_days_in_month
{
	my($sec, $min, $hour, $mday, $mon, $year)
		=  localtime(time);
	$mday++, $year+=1900;

	return 28 if(not($year % 4));
	return 31 if($mday == 8);
	return ($mday % 2) ? 31 : 30;
}

sub calc_time_expr
{
	my($time_expr) = @_;
	my @expr = split /\s+/, $time_expr;
	my $time = 0;
	while(my $this = shift @expr) {
		my($int, $type);
		if($this =~ /(\d+)(\w+)/) {
			($int, $type) = ($1, $2);
		} else {
			($int = $this) =~ s/[^\d]//g;
			$type = shift @expr;
			croak "Strange number of elements in time pattern: $time_expr"
			  unless($type =~ /\w/);
		}
		$time += $int * get_time_type($type);
	}
	return $time;
}			
				
	
sub get_time_type
{
	my $time = lc shift @_;
	my $c = substr($time, 0, 1);
	return T_MON  if $time =~ /^mo/;
	return T_SEC  if $c eq 's';
	return T_MIN  if $c eq 'm';
	return T_HOUR if $c eq 'h';
	return T_DAY  if $c eq 'd';
	return T_WEEK if $c eq 'w';
	return T_YEAR if $c eq 'y';
	return 0;
}

1;
__END__
=head1 NAME

Cache::DB_File - Memory cache which, when full, swaps to DB_File database.

=head1 SYNOPSIS

  use Cache::DB_File ();

  my $cache = Cache::DB_File->new(
    max_size => 50,         # Maximum elements in hash before swapping to disk.
    expire   => '1h 2m 1s', # Default expiry time for elements.
    db_mode	 => 06400,      # file mode for database.
    highlow  => '10m',      # Time before a rarely accessed hit element in memory
                            # is moved to disk, or frequently accessed element in
                            # disk is moved to memory.
  );

  $cache->store('key', 'data');
  $cache->store('key2', 'this data expires in 10 seconds', '10seconds');
  my $in_cache = $cache->fetch('key');

  $cache->sync(); # sync to disk.

  $cache->close(); # NOTE: will also write elements in memory to disk.
  

=head1 ABSTRACT

  Cache::DB_File is a cache system that has a optional limit on the number of elements,
  and optional time limits on elements. When the memory cache reaches its limit,
  it will swap infrequently used elements to disk.

=head1 DESCRIPTION
  
  Cache::DB_File is a cache system that has a optional limit on the number of elements,
  and optional time limits on elements. When the memory cache reaches its limit,
  it will swap infrequently used elements to disk.

=head1 EXPORT

Cache::DB_File does not export anything.

=head1 SEE ALSO

L<perl>, L<Cache::Cache>, L<DB_File>, L<Tie::Cache::LRU>

=head1 AUTHOR

Ask Solem Hoel, E<lt>ask@unixmonks.net<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2002 by Ask Solem Hoel

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
