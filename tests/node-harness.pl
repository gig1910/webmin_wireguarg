# Shared Node fixture runner for generated UI scripts.
use strict;
use warnings;
use File::Temp qw(tempfile);

sub wg_test_node_check {
    my ($script,$label)=@_;
    my $node=qx(command -v node 2>/dev/null);
    $node =~ s/[\r\n]+\z//;
    return 0 unless $node;
    my ($fh,$path)=tempfile(SUFFIX=>'.js',UNLINK=>1);
    print {$fh} $script;
    close($fh) or die "Cannot close $label JavaScript fixture: $!\n";
    system($node,'--check',$path)==0
        or die "$label generated JavaScript is invalid\n";
    return 1;
}

sub wg_test_node_script {
    my ($script,$label)=@_;
    my $node=qx(command -v node 2>/dev/null);
    $node =~ s/[\r\n]+\z//;
    return 0 unless $node;
    my ($fh,$path)=tempfile(SUFFIX=>'.js',UNLINK=>1);
    print {$fh} $script;
    close($fh) or die "Cannot close $label JavaScript fixture: $!\n";
    system($node,'--check',$path)==0
        or die "$label generated JavaScript is invalid\n";
    system($node,$path)==0
        or die "$label behavior test failed\n";
    return 1;
}
1;
