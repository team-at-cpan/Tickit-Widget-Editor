#!/usr/bin/env perl
use strict;
use warnings;

use Tickit;
use Tickit::Widget::Editor;
Tickit->new(root => Tickit::Widget::Editor->new(
	file => 'test.pl'
))->run;

