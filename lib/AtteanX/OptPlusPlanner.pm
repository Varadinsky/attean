use v5.14;
use warnings;

=head1 NAME

AtteanX::OptPlusPlanner - Query planner adding support for new OPTPLUS joins

=head1 VERSION

This document describes AtteanX::OptPlusPlanner version 0.005

=head1 SYNOPSIS

  use v5.14;
  use Attean;
  my $planner = AtteanX::OptPlusPlanner->new();
  my $default_graphs = [ Attean::IRI->new('http://example.org/') ];
  my $plan = $planner->plan_for_algebra( $algebra, $model, $default_graphs );
  my $iter = $plan->evaluate($model);
  my $iter = $e->evaluate( $model );

=head1 DESCRIPTION

=head1 ATTRIBUTES

=over 4

=cut

use Attean::Algebra;
use Attean::Plan;
use Attean::Expression;

package AtteanX::OptPlusPlanner 0.005 {
	use Moo;
	use namespace::clean;
	extends 'Attean::IDPQueryPlanner';

	sub plans_for_algebra {
		my $self			= shift;
		my $algebra			= shift;
		my $model			= shift;
		my $active_graphs	= shift;
		my $default_graphs	= shift;
		my %args			= @_;
		
		if ($model->does('Attean::API::CostPlanner')) {
			my @plans	= $model->plans_for_algebra($algebra, $model, $active_graphs, $default_graphs, @_);
			if (@plans) {
				return @plans; # trust that the model knows better than us what plans are best
			}
		}
		
		if ($algebra->isa('Attean::Algebra::OptPlus')) {
			my @children	= @{ $algebra->children };
			my @vars		= keys %{ { map { map { $_ => 1 } $_->in_scope_variables } @children } };
			my @plansets	= map { [$self->plans_for_algebra($_, $model, $active_graphs, $default_graphs, @_)] } @children;
			my $l	= [$self->plans_for_algebra($children[0], $model, $active_graphs, $default_graphs, @_)];
			my $r	= [$self->plans_for_algebra($children[1], $model, $active_graphs, $default_graphs, @_)];
			return $self->join_plans($model, $active_graphs, $default_graphs, $l, $r, 'optplus');
		} else {
			return $self->SUPER::plans_for_algebra($algebra, $model, $active_graphs, $default_graphs, %args);
		}
	}
	
	sub join_plans {
		my $self			= shift;
		my $model			= shift;
		my $active_graphs	= shift;
		my $default_graphs	= shift;
		my $lplans			= shift;
		my $rplans			= shift;
		my $type			= shift;
		if ($type eq 'optplus') {
			my @plans;
			foreach my $lhs (@{ $lplans }) {
				foreach my $rhs (@{ $rplans }) {
					my @vars	= (@{ $lhs->in_scope_variables }, @{ $rhs->in_scope_variables });
					my %vars;
					my %join_vars;
					foreach my $v (@vars) {
						if ($vars{$v}++) {
							$join_vars{$v}++;
						}
					}
					my @join_vars	= keys %join_vars;
					push(@plans, AtteanX::OptPlusPlanner::NestedLoopJoin->new(children => [$lhs, $rhs], left => 1, join_variables => \@join_vars, distinct => 0, in_scope_variables => [keys %vars], ordered => []));
					if (scalar(@join_vars) > 0) {
						push(@plans, AtteanX::OptPlusPlanner::HashJoin->new(children => [$lhs, $rhs], join_variables => \@join_vars, distinct => 0, in_scope_variables => [keys %vars], ordered => []));
					}
					
				}
			}
			return @plans;
		} else {
			return $self->SUPER::join_plans($model, $active_graphs, $default_graphs, $lplans, $rplans, $type, @_);
		}
	}
}

package AtteanX::OptPlusPlanner::NestedLoopJoin 0.005 {
	use Moo;
	use Types::Standard qw(ArrayRef Str Bool ConsumerOf);
	with 'Attean::API::Plan', 'Attean::API::BinaryQueryTree';
	has 'join_variables' => (is => 'ro', isa => ArrayRef[Str], required => 1);
	sub plan_as_string { return 'NestedLoop OptPlusJoin' }
	sub impl {
		my $self	= shift;
		my $model	= shift;
		my @children	= map { $_->impl($model) } @{ $self->children };
		return sub {
			my ($lhs, $rhs)	= map { $_->() } @children;
			my @right	= $rhs->elements;
			my @results;
			while (my $l = $lhs->next) {
				push(@results, $l);
				foreach my $r (@right) {
					if (my $j = $l->join($r)) {
						push(@results, $j);
					}
				}
			}
			return Attean::ListIterator->new(
				item_type => 'Attean::API::Result',
				values => \@results
			);
		}
	}
}

=item * L<Attean::Plan::HashJoin>

Evaluates a join (natural-, anti-, or left-) using a hash join.

=cut

package AtteanX::OptPlusPlanner::HashJoin 0.005 {
	use Moo;
	use Types::Standard qw(ArrayRef Str ConsumerOf Bool);
	with 'Attean::API::Plan', 'Attean::API::BinaryQueryTree';
	has 'join_variables' => (is => 'ro', isa => ArrayRef[Str], required => 1);
	sub plan_as_string {
		my $self	= shift;
		return sprintf('NestedLoop OptPlusJoin { %s }', join(', ', @{$self->join_variables}));
	}

	sub impl {
		my $self	= shift;
		my $model	= shift;
		my @children	= map { $_->impl($model) } @{ $self->children };
		return sub {
			my %hash;
			my @vars	= @{ $self->join_variables };
			my $rhs		= $children[1]->();
			while (my $r = $rhs->next()) {
				my $key	= join(',', map { ref($_) ? $_->as_string : '' } map { $r->value($_) } @vars);
				push(@{ $hash{$key} }, $r);
			}
			
			my @results;
			my $lhs		= $children[0]->();
			while (my $l = $lhs->next()) {
				push(@results, $l);
				my $key		= join(',', map { ref($_) ? $_->as_string : '' } map { $l->value($_) } @vars);
				if (my $rows = $hash{$key}) {
					foreach my $r (@$rows) {
						if (my $j = $l->join($r)) {
							push(@results, $j);
						}
					}
				}
			}
			return Attean::ListIterator->new(
				item_type => 'Attean::API::Result',
				values => \@results
			);
		}
	}
}

1;

__END__

=back

=head1 BUGS

Please report any bugs or feature requests to through the GitHub web interface
at L<https://github.com/kasei/attean/issues>.

=head1 REFERENCES

The seminal reference for Iterative Dynamic Programming is "Iterative
dynamic programming: a new class of query optimization algorithms" by
D. Kossmann and K. Stocker, ACM Transactions on Database Systems
(2000).

The heuristics to order triple patterns in this module is
influenced by L<The ICS-FORTH Heuristics-based SPARQL Planner
(HSP)|http://www.ics.forth.gr/isl/index_main.php?l=e&c=645>.


=head1 SEE ALSO

L<http://www.perlrdf.org/>

=head1 AUTHOR

Gregory Todd Williams  C<< <gwilliams@cpan.org> >>

=head1 COPYRIGHT

Copyright (c) 2014 Gregory Todd Williams.
This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
