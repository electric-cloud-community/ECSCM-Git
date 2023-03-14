#!/usr/bin/env perl
# line 3 "preamble.pl"

use strict;
use warnings;

BEGIN {
    use Carp;
    use ElectricCommander;
    $|=1;

    # TODO This should be in EC core
    # Make 'use Foo;' search in properties as well
    # If property exists, wrap it into a "file" and present to Perl CORE
    # Also makes errors/warnings show correct filename and line
    # The local versions of modules are preferred, load from prop as a last
    #     resort.
    my $ec = ElectricCommander->new;
    my $prefix = '/projects/';
    my $get_version = sub {
        my ($ec) = @_;

        my $plugins = $ec->getPlugin('ECSCM');

        my $nodeset = $plugins->find('//plugin'); # find all paragraphs

        my $version = '';
        foreach my $node ($nodeset->get_nodelist) {
            my $promoted = $node->findvalue('//promoted')->string_value();
            if ($promoted && $promoted eq '1') {
                $version = $node->findvalue('//pluginVersion')->string_value();
            }
        }

        $version = 'ECSCM-' . $version;

        return $version;
    };
    my $ecscm_plugin_version = $get_version->($ec);
    $prefix .= $ecscm_plugin_version . '/scm_driver/';
    my $load_ecscm = sub {
        my ($self, $target) = @_;

        # Undo perl'd require transformation
        my $prop = $target;
        $prop =~ s#/#::#g;
        $prop =~ s#\.pm$##;
        my $display = $prop;
        $prop = "$prefix$prop";

        my $code = eval {
            $ec->getProperty("$prop")->findvalue('//value')->string_value;
        };
        return unless $code; # let other module paths try ;)

        # Prepend comment for correct error attribution
        $code = qq{# line 1 "$display"\n$code};

        # We must return a file in perl < 5.10, in 5.10+ just return \$code
        #    would suffice.
        open my $fd, "<", \$code
            or die "Redirect failed when loading $target from $display";

        return $fd;
    };
    my $load_git_modules = sub {
        my ($self, $target) = @_;

        # Undo perl'd require transformation
        my $prop = $target;
        $prop =~ s#/#::#g;
        $prop =~ s#\.pm$##;
        my $display = $prop;
        $prop = "/myProject/scm_driver/$prop";
        print "Prop: $prop\n";
        my $code = eval {
            $ec->getProperty("$prop")->findvalue('//value')->string_value;
        };
        return unless $code; # let other module paths try ;)

        # Prepend comment for correct error attribution
        $code = qq{# line 1 "$display"\n$code};

        # We must return a file in perl < 5.10, in 5.10+ just return \$code
        #    would suffice.
        open my $fd, "<", \$code
            or die "Redirect failed when loading $target from $display";

        return $fd;
    };
    push @INC, $load_ecscm;
    push @INC, $load_git_modules;
};

use ECSCM::Base::Driver;
use ECSCM::Base::Cfg;
use ECSCM::Git::Driver;
use ECSCM::Git::Cfg;

use Data::Dumper;


my $opts = {
    config               => '$[config]',
    GitRepo              => '$[GitRepo]',
    GitBranch            => '$[GitBranch]',
    commit               => '$[commit]',
    depth                => '$[depth]',
    fieldMapping         => '$[fieldMapping]',
    metadataPropertyPath => '$[metadataPropertyPath]',
    transformScript      => '$[transformScript]',
    previewMode          => '$[previewMode]',
    debug                => '$[debug]',
};

my $ec = ElectricCommander->new();
my $git = ECSCM::Git::Driver->new(
    $ec,
    $opts->{config},
);

$git->CollectReportingData($opts);
