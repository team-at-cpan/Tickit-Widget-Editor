package Tickit::Widget::Editor;
# ABSTRACT: 
use strict;
use warnings;

use parent qw(Tickit::Widget);

our $VERSION = '0.001';

=head1 NAME

Tickit::Widget::Editor -

=head1 SYNOPSIS

 use Tickit;
 use Tickit::Widget::Editor;
 Tickit->new(root_widget => Tickit::Widget::Editor->new(
 ))->run;

=head1 DESCRIPTION

Provides a widget for doing stuff.

=cut

use Tickit::Utils qw(substrwidth textwidth);
use List::Util qw(min max);
use Text::Tabs ();

use Tickit::Debug;
use Tickit::Style;

use constant CAN_FOCUS => 1;

BEGIN {
	style_definition base =>
		highlight_row_bg => 236,
		highlight_col_bg => 236,
		highlight_pos_bg => 244,
		highlight_pos_fg => 'hi-yellow',
		line_fg => 6;
}

=head1 METHODS

=cut

=head2 lines

Returns the number of lines this widget would like.

=cut

sub lines { 1 }

=head2 cols

Returns the number of columns this widget would like.

=cut

sub cols { 1 }

=head2 new

Instantiate a new fileviewer widget. Passes any given
named parameters to L</configure>.

=cut

sub new {
	my $self = shift->SUPER::new;
	my %args = @_;
	$self->{top_line} = 0;
	$self->{cursor_line} = 0;
	$self->{cursor_col} = 0;
	$self->{requested_col} = 0;
	$self->{mode} = 'normal';
	$self->{pending_input} = [ ];
	$self->configure(%args);
	$self
}

=head2 configure

Takes the following named parameters:

=over 4

=item * file - the file to load

=back

=cut

sub configure {
	my $self = shift;
	my %args = @_;
	if(my $file = delete $args{file}) {
		$self->load_file($file);
	}
	$self;
}

=head2 load_file

Loads the given file into memory.

=cut

sub load_file {
	my $self = shift;
	my $file = shift;
	$self->{filename} = $file;
	open my $fh, '<:encoding(utf-8)', $file or die "$file - $!";
	chomp(my @line_data = <$fh>);
	$self->{file_content} = \@line_data;
	$fh->close or die $!;
	$self;
}

=head2 line_attributes

Given a zero-based line number and line text, returns the attributes
to apply for this line.

This method is intended for line-level highlights such as current cursor
position or selected text - For syntax highlighting, overriding the
L</render_line_data> method may be more appropriate.

=cut

sub line_attributes {
	my $self = shift;
	my ($line, $txt) = @_;
	my %attr = (fg => 7);
	%attr = (fg => 6, bg => 4, b => 1) if $line == $self->cursor_line;
	return %attr;
}

=head2 render_to_rb

Render this widget. Will call L</render_line_data> and L</render_line_number>
to do the actual drawing.

=cut

sub render_to_rb {
	my ($self, $rb, $rect) = @_;
	my $win = $self->window or return;

	my $line = $rect->top + $self->top_line;
	my @line_data = @{$self->{file_content}}[$line .. min($line + $rect->lines, $#{$self->{file_content}})];

	my $w = $win->cols - $self->horizontal_offset;
	for my $row ($rect->linerange) {
		if(@line_data) {
			# FIXME is this unicode-safe? probably not
			local $Text::Tabs::tabstop = 4;
			my $txt = substrwidth(Text::Tabs::expand(shift @line_data), 0, $w);
			$self->render_line_number($rb, $rect, $row, $line);
			$self->render_line_data($rb, $rect, $row, $line, $txt);
		} else {
			$rb->erase_at($row, $rect->left, $rect->cols, $self->get_style_pen);
		}
		++$line;
	}
}

=head2 render_line_number

Renders the given (zero-based) line number at the current
cursor position.

Subclasses should override this to provide styling as required.

=cut

sub render_line_number {
	my ($self, $rb, $rect, $row, $line) = @_;
	my $win = $self->window or return;
	$rb->text_at($row, 0, sprintf("%6d ", $line + 1), $self->get_style_pen('line'));
}

=head2 render_line_data

Renders the given line text at the current cursor position.

Subclasses should override this to provide styling as required.

=cut

sub render_line_data {
	my ($self, $rb, $rect, $row, $line, $txt) = @_;
	my $win = $self->window or return;
	my $pen = Tickit::Pen->new($self->line_attributes($line, $txt));
	if(1) {
		$rb->goto($row, $self->horizontal_offset);
		my $pen = $self->get_style_pen($self->cursor_line == $line ? 'highlight_row' : '');
		if($self->cursor_col < textwidth($txt)) {
			$rb->text(substrwidth($txt, 0, $self->cursor_col), $pen);
			$rb->text(substrwidth($txt, $self->cursor_col, 1), $self->get_style_pen($line == $self->cursor_line ? 'highlight_pos' : 'highlight_col'));
			$rb->text(substrwidth($txt, 1 + $self->cursor_col), $pen);
		} else {
			$rb->text($txt, $pen);
			$rb->erase_to($self->cursor_col + $self->horizontal_offset, $pen);
			$rb->text(' ', $self->get_style_pen($line == $self->cursor_line ? 'highlight_pos' : 'highlight_col'));
		}
		$rb->erase_to($rect->right, $pen);
	} else {
		$rb->text_at($row, $self->horizontal_offset, $txt, $pen);
	}
}

=head2 on_key

Handle a keypress event. Passes the event on to L</handle_key> or
L</handle_text> as appropriate.

=cut

sub on_key {
	my ($self, $ev) = @_;
	return $self->handle_key($ev->str) if $ev->type eq 'key';
	return $self->handle_text($ev->str) if $ev->type eq 'text';
	die "wtf is @_ ?\n";
}

=head2 cursor_line

Accessor for the current cursor line. Will trigger a redraw if
we have a window and the cursor line has changed.

=cut

sub cursor_line {
	my $self = shift;
	if(@_) {
		my $line = shift;
		return $self if $self->{cursor_line} == $line;
		$self->{cursor_line} = $line;
		$self->{cursor_col} = min($self->{requested_col}, $self->line_width($line));
		if(my $win = $self->window) {
			if($line < $self->top_line) {
				$self->top_line($line);
			} elsif($line >= $self->top_line + $win->lines) {
				$self->top_line($line - ($win->lines - 1));
			}
			$win->cursor_at($self->cursor_line, $self->cursor_col + $self->horizontal_offset);
			$self->redraw;
		}
		return $self;
	}
	return $self->{cursor_line};
}

sub horizontal_offset { 7 }

=head2 cursor_col

Accessor for the current cursor col. Will trigger a redraw if
we have a window and the cursor col has changed.

=cut

sub cursor_col {
	my $self = shift;
	if(@_) {
		my $col = shift;
		$col = 0 if $col < 0;
		return $self if $self->{cursor_col} == $col;
		my $line = $self->cursor_line;
		$self->{requested_col} = $self->{cursor_col} = min($col, $self->line_width($line));
		if(my $win = $self->window) {
			$win->cursor_at($line, $self->{cursor_col} + $self->horizontal_offset);
			$self->redraw;
		}
		return $self;
	}
	return $self->{cursor_col};
}

=head2 handle_key

Handle a keypress event. Currently hard-coded to accept
up, down, pageup and pagedown events.

=cut

sub handle_key {
	my ($self, $key) = @_;
	return unless defined $key;
	if($key eq 'Down') {
		$self->cursor_line($self->cursor_line + 1);
	} elsif($key eq 'Up') {
		$self->cursor_line($self->cursor_line - 1);
	} elsif($key eq 'PageDown') {
		if($self->cursor_line < $#{$self->{file_content}}) {
			$self->cursor_line(min($self->cursor_line + 10, $#{$self->{file_content}}));
		}
	} elsif($key eq 'PageUp') {
		if($self->cursor_line > 0) {
			$self->cursor_line(max($self->cursor_line - 10, 0));
		}
	} elsif($key eq 'Left') {
		$self->cursor_col($self->cursor_col - 1);
	} elsif($key eq 'Right') {
		$self->cursor_col($self->cursor_col + 1);
	} elsif($key eq 'Esc') {
		$self->mode('normal');
	} elsif($key eq 'Backspace') {
		substr $self->{file_content}[$self->cursor_line], $self->cursor_col - 1, 1, '';
		$self->cursor_col($self->cursor_col - 1);
	}
}

sub mode {
	my $self = shift;
	if(@_) {
		$self->{mode} = shift;
		return $self;
	}
	return $self->{mode};
}

=head2 handle_text

Stub method for dealing with text events.

=cut

sub handle_text {
	my ($self, $txt) = @_;
	if($self->mode eq 'insert') {
		substr $self->{file_content}[$self->cursor_line], $self->cursor_col, 0, $txt;
		$self->cursor_col($self->cursor_col + 1);
	} elsif($self->mode eq 'visual') {
	} else {
		push @{$self->{pending_input}}, $txt;
		$self->handle_input;
	}
}

sub open_line_after {
	my ($self) = @_;
	$self->mode('insert');
	splice @{$self->{file_content}}, $self->cursor_line + 1, 0, '';
	$self->cursor_line($self->cursor_line + 1);
	$self->redraw if $self->window;
}
sub delete_line {
	my ($self) = @_;
	splice @{$self->{file_content}}, $self->cursor_line, 1;
	$self->redraw if $self->window;
}
sub delete_to_eol {
	my ($self) = @_;
	substr($self->{file_content}[$self->cursor_line], $self->cursor_col) = '';
	$self->redraw if $self->window;
}

sub move_left {
	my ($self) = @_;
	$self->cursor_col($self->cursor_col - 1);
}
sub move_right {
	my ($self) = @_;
	$self->cursor_col($self->cursor_col + 1);
}
sub move_up {
	my ($self) = @_;
	$self->cursor_line($self->cursor_line - 1);
}
sub move_down {
	my ($self) = @_;
	$self->cursor_line($self->cursor_line + 1);
}
sub first_line { $_[0]->cursor_line(0) }
sub last_line { $_[0]->cursor_line($#{$_[0]{file_content}}) }

{
my %normal_map = (
	'h'  => 'move_left',
	'l'  => 'move_right',
	'j'  => 'move_down',
	'k'  => 'move_up',
	'a'  => 'append_text',
	'A'  => 'append_eol',
	'i'  => 'insert_text',
	'I'  => 'insert_bol',
	'R'  => 'replace_text',
	'o'  => 'open_line_after',
	'O'  => 'open_line_before',
	'yy' => 'yank_line',
	'p'  => 'put_after',
	'P'  => 'put_before',
	'dd' => 'delete_line',
	'D'  => 'delete_to_eol',
	'gg' => 'first_line',
	'G'  => 'last_line',
);
sub handle_input {
	my ($self) = @_;
	if($self->mode eq 'normal') {
		my $data = join '', @{$self->{pending_input}};
		while(length $data) {
			if(my $method = $normal_map{$data}) {
				$self->$method if $self->can($method);
				splice @{$self->{pending_input}}, 0, length($data);
				$data = join '', @{$self->{pending_input}};
			} else {
				substr $data, -1, 1, '';
			}
		}
	}
}
}

=head2 top_line

First line shown in the window.

=cut

sub top_line {
	my $self = shift;
	if(@_) {
		my $line = shift;
		return $self if $line == $self->{top_line};
		my $prev = $self->{top_line};
		$self->{top_line} = $line;
		if(my $win = $self->window) {
			$self->redraw unless $win->scroll($line - $prev, 0);
		}
		return $self;
	}
	return $self->{top_line};
}

sub line_width {
	my ($self, $line) = @_;
	local $Text::Tabs::tabstop = 4;
	textwidth(Text::Tabs::expand($self->{file_content}[$line]));
}

1;

__END__

=head1 SEE ALSO

=over 4

=item * L<Tickit::Widgets> - the standard Tickit widgetset.

=item * L<Tickit>

=back

=head1 AUTHOR

Tom Molesworth <cpan@perlsite.co.uk>

=head1 LICENSE

Copyright Tom Molesworth 2014. Licensed under the same terms as Perl itself.

