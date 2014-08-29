#!/usr/bin/env perl
use strict;
use warnings;
use Tickit::DSL;

use Tickit::Widget::Editor;

Tickit::Style->load_style(<<'EOF');
Breadcrumb { powerline: 1; }
EOF

sub app_menu {
	menubar {
		menuitem 'File' => { };
		menuitem 'Edit' => { };
		menuitem 'Debug' => { };
		menuitem 'Refactor' => { };
		menuspacer;
		menuitem 'Help' => { };
	};
}

my %widget;
vbox {
	floatbox {
		vbox {
			app_menu();
			$widget{desktop} = desktop {
				vbox {
					my $bc = breadcrumb {
					} data => [];
					$bc->adapter->push([qw(test.pl Functions code)]);
					tree {

					} data => [
						'test.pl' => [
							Imports   => [qw(Tickit Tickit::Widget::Editor)],
							Functions => [qw(code)],
						]
					], 'parent:expand' => 1; 
				}, 'parent:expand' => 1;
				customwidget {
					Tickit::Widget::Editor->new(
						file => 'test.pl'
					);
				} 'expand' => 3;
			} 'parent:expand' => 1;
		}
	} 'parent:expand' => 1;
	my $status = statusbar { };
	$status->update_status('test.pl loaded');
};
tickit->run;

