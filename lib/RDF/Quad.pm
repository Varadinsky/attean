use v5.14;
use warnings;

package RDF::Quad 0.001 {
	use Moose;
	use RDF::API::Binding;
	
	has 'subject'	=> (is => 'ro', isa => 'RDF::BlankOrIRI', required => 1);
	has 'predicate'	=> (is => 'ro', isa => 'RDF::IRI', required => 1);
	has 'object'	=> (is => 'ro', isa => 'RDF::API::Term', required => 1);
	has 'graph'		=> (is => 'ro', isa => 'RDF::IRI', required => 1);
	
	with 'RDF::API::Quad';
	
	around BUILDARGS => sub {
		my $orig 	= shift;
		my $class	= shift;
		if (scalar(@_) == 4) {
			my %args;
			@args{qw(subject predicate object graph)}	= @_;
			return $class->$orig(%args);
		}
		return $class->$orig(@_);
	};
}

1;