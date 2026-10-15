=head1 peer-usage-lib.pl

Read-only traffic usage calculations from samples recorded by the collector.
Samples are cumulative wg RX/TX counters. Only monotonic positive changes
between adjacent recorded measurements contribute to a period's totals.

=cut

sub peer_usage_summary
{
    my ($history, $from, $to, $expected_interval) = @_;
    $expected_interval ||= 5;
    my @samples = sort { $a->{'timestamp'} <=> $b->{'timestamp'} } grep {
        ref($_) eq 'HASH' &&
        defined($_->{'timestamp'}) && $_->{'timestamp'} =~ /^\d+(?:\.\d+)?$/ &&
        $_->{'timestamp'} >= $from && $_->{'timestamp'} <= $to &&
        defined($_->{'rx'}) && $_->{'rx'} =~ /^\d+$/ &&
        defined($_->{'tx'}) && $_->{'tx'} =~ /^\d+$/
    } @{ $history || [] };
    my ($rx, $tx, $resets, $intervals, $gaps) = (0, 0, 0, 0, 0);
    my $prior;
    foreach my $sample (@samples) {
        if ($prior && $sample->{'timestamp'} > $prior->{'timestamp'}) {
            my $reset = 0;
            $gaps++ if ($sample->{'timestamp'} - $prior->{'timestamp'} > 3 * $expected_interval);
            if ($sample->{'rx'} >= $prior->{'rx'}) {
                $rx += $sample->{'rx'} - $prior->{'rx'};
            }
            else { $reset = 1; }
            if ($sample->{'tx'} >= $prior->{'tx'}) {
                $tx += $sample->{'tx'} - $prior->{'tx'};
            }
            else { $reset = 1; }
            $resets++ if ($reset);
            $intervals++;
        }
        $prior = $sample;
    }
    return {
        rx => 0 + $rx, tx => 0 + $tx,
        samples => scalar(@samples), intervals => $intervals,
        resets => $resets, gaps => $gaps,
        first => @samples ? 0 + $samples[0]->{'timestamp'} : undef,
        last => @samples ? 0 + $samples[-1]->{'timestamp'} : undef,
    };
}

1;
