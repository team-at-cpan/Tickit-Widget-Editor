use strict;
use warnings;

use Test::More;
use Tickit::Test;
use ;

my $win = mk_window;

my $widget = $name->new(
);

$widget->set_window( $win );

flush_tickit;

is_display( [ "" ] );

done_testing;

