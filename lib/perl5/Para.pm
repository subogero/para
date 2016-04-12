package Para;
use strict;
use warnings;
use Socket;

sub new {
    my $class = shift;
    my %p = @_;
    die "job not a sub" if ref $p{job} ne 'CODE';
    die "callback not a sub" if $p{callback} && ref $p{callback} ne 'CODE';
    $p{jobs} //= 1;
    die "jobs negative or no integer" unless $p{jobs} =~ /^\d+$/;
    $p{queue} = [];
    $p{results} = [] unless $p{callback};
    $p{kids} = {};
    $p{size} ||= 4096;
    die "size not positive integer" unless $p{size} =~ /^[1-9]\d*$/;
    socketpair $p{fd_child}, $p{fd_parent}, AF_UNIX, SOCK_SEQPACKET, 0
        or die "failed to create socketpair: $!";
    bless \%p, $class;
}

sub to_queue {
    my $p = shift;
    $p->debug("to_queue @_");
    push @{$p->{queue}}, @_;
    $p->start_jobs;
}

sub run {
    my $p = shift;
    while (1) {
        my $result;
        recv $p->{fd_parent}, $result, $p->{size}, 0;
        $p->debug("run read: $result");
        if ($p->{callback}) {
            $p->{callback}->($result);
        } else {
            push @{$p->{results}}, $result;
        }
        my $pid = wait;
        delete $p->{kids}{$pid} if $pid > 0;
        $p->start_jobs;
        last unless keys %{$p->{kids}};
    }
}

sub results {
    my $p = shift;
    my $n = shift;
    my $size = @{$p->{results}};
    $n = $size if !$n || $n > $size || $n < 0;
    my @res = splice @{$p->{results}}, 0, $n;
    return @res;
}

sub start_jobs {
    my $p = shift;
    while (@{$p->{queue}} && keys $p->{kids} < $p->{jobs}) {
        my $payload = shift @{$p->{queue}};
        $p->debug("start_jobs payload $payload");
        my $pid = fork;
        die "fork failed" if $pid < 0;
        if ($pid) {
            $p->debug("parent forked $pid");
            $p->{kids}{$pid} = 1;
        } else {
            select $p->{fd_child};
            exit $p->{job}->($payload);
        }
    }
}

sub debug {
    my $p = shift;
    return unless $p->{debug};
    my $msg = shift or return;
    $msg =~ s/^(.+?)\s*$/DEBUG: $1\n/;
    print STDERR $msg;
}

1;
