# -*- Perl -*-

# ElectricCommander.pm --
#
# Stubbed Perl interface to the ElectricCommander server for Testing purposes.
#
# Copyright (c) 2005-2012 Electric Cloud, Inc.
# All rights reserved.

package ElectricCommander;

use Test::MockObject;
use Data::Dumper;

my $connectValue;
my $authValue;
my $authOKValue;

my @resourcesToPing = ();

sub clearState {
    @resourcesToPing = ();
}

sub resourcesToPing{
    return @resourcesToPing;
}

sub new {
    my ( $class, $config ) = @_;
    $config = {} unless defined($config);
    my $self = $config;
    bless $self;
    return $self;
}

sub setAbortDefault() {

}

sub newBatch {
    my $mock = Test::MockObject->new();

    $mock->mock(
        'createResource' => sub {
            my ($mock) = @_;
            return "";
        }
    );
    $mock->mock(
        'pingResource' => sub {
            my ($mock,$resource) = @_;
			push (@resourcesToPing,$resource);
            return "";
        }
    );
    $mock->mock(
        'submit' => sub {
            my ($mock) = @_;
            return "";
        }
    );	
}

sub getProperty {
    my ( $self, $input ) = @_;

    if ( $input eq '/myJob/info/hosts/host-ip/platform' ) {
        return XML::XPath->new("<value>Windows</value>");
    }
    elsif ( $input eq '/myJob/info/hosts/host-ip/hostname' ) {
        return XML::XPath->new("<value>center-world</value>");
    } elsif ( $input eq '/myJob/info/hosts/center-world/runInstall_exitCode' ) {
        return XML::XPath->new("<value>0</value>");
    }
    elsif ( $input eq '/myJob/info/hosts/center-world/runInstall_exitCode' ) {
        return XML::XPath->new("<value>0</value>");
    }
    else {
        return XML::XPath->new("<value>5</value>");
    }
}

1;
