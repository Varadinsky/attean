use v5.14;
use autodie;
use utf8;
use Test::More;
use Test::Exception;
use FindBin qw($Bin);
use File::Glob qw(bsd_glob);
use File::Spec;

use Attean;

my $p	= RDF->get_parser('Turtle');
is($p, 'Attean::X::Parser::Turtle');

done_testing();
