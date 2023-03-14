####################################################################
#
# ECSCM::Git::Driver  Object to represent interactions with
#        Git.
#
####################################################################
package ECSCM::Git::Driver;
@ISA = (ECSCM::Base::Driver);

# use strict;
# no strict qw/subs/;
# use warnings;

use ElectricCommander;
use Time::Local;
use File::Spec;
use File::Temp;
use File::Path;
use File::Basename;
use Sys::Hostname;
use Cwd;
use Getopt::Long;
use HTTP::Date qw(str2time time2str time2iso time2isoz);
use Digest::MD5 qw(md5 md5_hex md5_base64);
use Data::Dumper;
use URI;
use JSON qw(encode_json);

if (!defined ECSCM::Base::Driver) {
    require ECSCM::Base::Driver;
}

if (!defined ECSCM::Git::Cfg) {
    require ECSCM::Git::Cfg;
}

# Turn off stdout buffering; needed so that "live updates" show up in the UI
# when watching running steps.
$|=1;


####################################################################
# Object constructor for ECSCM::Git::Driver
#
# Inputs
#    cmdr          previously initialized ElectricCommander handle
#    name          name of this configuration
#
####################################################################
sub new {
    my ($this, $cmdr, $name) = @_;
    my $class = ref($this) || $this;

    my $cfg = new ECSCM::Git::Cfg($cmdr, $name);
    if (!isEmpty($name)) {
        my $sys = $cfg->getSCMPluginName();
        if ($sys ne "ECSCM-Git") {
            die "SCM config $name is not type ECSCM-Git\n";
        }
    }
    my ($self) = new ECSCM::Base::Driver($cmdr, $cfg);

    $self->{jobId} = $ENV{COMMANDER_JOBID};
    $self->{pluginName} = $cfg->getSCMPluginName();

    # Disable server SSL certificate verification
    $ENV{'GIT_SSL_NO_VERIFY'} = "true";

    my $logLevel = 0;
    eval {
        $logLevel = $self->{ec}->getProperty(
            '/projects/@PLUGIN_KEY@-@PLUGIN_VERSION@/debugLevel'
        )->findvalue('//value')->string_value();
        $logLevel = 0 unless defined $logLevel;
    };
    # FIXME: not working
    #$self->{logger} = EC::Plugin::Logger->new($logLevel);
    $self->{logger} = EC::Plugin::Logger->new(1);
    if ($logLevel) {
        $self->{logger}->info("Debug level set to: ", $logLevel);
    }

    bless ($self, $class);
    return $self;
}

####################################################################
# isImplemented
####################################################################
sub isImplemented {
    my ($self, $method) = @_;

    return ($method eq 'getSCMTag' ||
            $method eq 'apf_driver' ||
            $method eq 'cpf_driver' ||
            $method eq 'checkoutCode');
}


###############################################################################
# ElectricSentry (continuous integration) routines
###############################################################################




####################################################################
# getSCMTag
#
# Get the latest changeId on this branch
# Used for CI
#
# Args:
#   opts  - options passed in from caller
# Return:
#    changeNumber - a string representing the last change sequence #
#    changeTime   - a time stamp representing the time of last change
####################################################################
sub getSCMTag {
    my ( $self, $opts ) = @_;

    # add configuration that is stored for this config
    my $name = $self->getCfg()->getName();
    my %row  = $self->getCfg()->getRow($name);
    foreach my $k ( keys %row ) {
        $self->debug("Reading $k=$row{$k} from config");
        $opts->{$k} = $row{$k};
    }

    my $changesetNumber = undef;
    my $changeTimeStamp = undef;

     # Detects new versions using the git ls-remote command without a full pull
     if (!isEmpty($opts->{lsRemote}) && $opts->{lsRemote} eq "1") {
         my $last = undef;
         ($changesetNumber, $changeTimeStamp) =
             $self->getLastSnapshotFromRemoteRepo($opts);

         $last = $opts->{LASTATTEMPTED} || "";

        # Check if the current version is different from the last/stored
        # version (which is empty-string if there was no last version).
        if ( ( defined $last && $last ne $changesetNumber ) || $last eq "" ) {

            print join( "\n",
                "-----------------------",
                "New changes were found!!",
                "Previous change id: $last",
                "New change id:      $changesetNumber",
                "-----------------------"
            ) . "\n";

            # Since it's not possible to get the timestamp with
            # the ls-remote command we need to create a timestamp
            if ( defined $opts->{QuietTimeMinutes}
                && $opts->{QuietTimeMinutes} ne "" )
            {
                $changeTimeStamp = time() - $opts->{QuietTimeMinutes} * 1000;
            }
            else {
                $changeTimeStamp = time() - 5000;
            }
        }
    }
    # Detects new versions using the git log command
    # A full pull will be required
    else {
        ( $changesetNumber, $changeTimeStamp ) =
            $self->getLastSnapshotFromLog($opts);
    }
    return ( $changesetNumber, $changeTimeStamp );
}

##########################################################################
# getLastSnapshotFromLog
#
# Get the last snapshot SHA number and timestamp using the git log command
#
# Args:
#   opts hash
#
# Return:
#    $changeNumber       - snapshot SHA number
#    $changeTime         - timestamp
##########################################################################
sub getLastSnapshotFromLog {
    my ($self, $opts) = @_;
    my $cmdReturn = "";

    # Execute the checkout command if desired.
    if ($opts->{GitRepo} ne "") {
        print "Checking out code...\n";
        $self->checkoutCode($opts);
    }

    my $curDir = getcwd();

    # If there was no destination defined, follow convention and
    # construct it from the repository
    if(!(defined $opts->{dest}) || ($opts->{dest} eq '')){
      $opts->{dest} = getDefaultRepo($opts->{GitRepo});
    }

    if (!isEmpty($opts->{dest}) && $opts->{dest} ne ".") {
        $opts->{dest} = File::Spec->rel2abs($opts->{dest});
        print "Changing to directory $opts->{dest}\n";
        mkpath($opts->{dest});
        if (!chdir $opts->{dest}) {
            die("Could not change to directory $opts->{dest}\n");
        }
    }

    # Now form and execute the log command itself:
    $cmdReturn = $self->RunCommand(
        "git log -1 --pretty=format:%H@%ct%n --",
        {LogCommand => 1, LogResult => 1});

    chdir $curDir;
    chomp $cmdReturn;

    print "git log output=$cmdReturn\n";

    # Extract the changeset number and the date and time components.
    # This is what the format string we provided does:
    #
    #   017f1463c68694fcf22c2eab5fe8e7179073a255@1233463856
    $cmdReturn =~ m/^(.+)@(\d+)$/;
    my $changeNumber = $1;
    my $changeTime = $2;
    return ($changeNumber, $changeTime);
}

##################################################################
# getLastSnapshotFromRemoteRepo
#
# Get the last snapshot SHA number using the git ls-remote command
#
# Args:
#   opts hash
#
# Return:
#    $changeNumber       - snapshot SHA number
#    $changeTime         - always 0
##################################################################
sub getLastSnapshotFromRemoteRepo {
    my ($self, $opts) = @_;

    my $cmdReturn = "";
    if(!$self->validateBranch($opts->{GitBranch})){
        die("Invalid branch name: $opts->{GitBranch}\n");
    }

    # Load userName and password from the credential
    ($opts->{gitUserName}, $opts->{gitPassword}) =
        $self->getCredentials($opts, $opts->{gitUserName}, $opts->{gitPassword});

    my $user_pass = constructUserPass($opts);
    my %replacements = ();
    populateReplacements($opts,$user_pass,\%replacements);

    my ($repo, $using_http) = $self->fixRepoUrl($opts->{GitRepo}, $user_pass);

    # Command to execute
    my $cmd = "git ls-remote -h \"$repo\" $opts->{GitBranch}";

    $cmdReturn = $self->RunCommand($cmd,
        {LogCommand => 1, LogResult => 1, Replacements => \%replacements});
    $self->cleanupCredentials($opts);

    # The changeNumber is the first 40 characters of the result.
    my $changeNumber = substr($cmdReturn, 0, 40);

    my $changeTime = 0;

    # if monitorTag is checked, checks the tags
    if (exists($opts->{monitorTags}) && $opts->{monitorTags} eq "1") {
        my $tagChecksum = $self->checkTagsFromRemoteRepo($opts, $changeNumber);
        $changeNumber = $changeNumber . $tagChecksum;
    }

    return ($changeNumber, $changeTime);
}

##################################################################
# checkTagsFromRemoteRepo
#
# Check the tags on a commit
#
# Args:
#   opts hash
#   commit  the commit to be checked
#
# Return:
#    $tagMd5       - md5 checksum of the tags
##################################################################
sub checkTagsFromRemoteRepo {
    my ($self, $opts, $commit) = @_;

    my $cmdReturn = "";
    if(!$self->validateBranch($opts->{GitBranch})){
        die("Invalid branch name: $opts->{GitBranch}\n");
    }

    # Load userName and password from the credential
    ($opts->{gitUserName}, $opts->{gitPassword}) =
        $self->getCredentials($opts, $opts->{gitUserName}, $opts->{gitPassword});

    my $user_pass = constructUserPass($opts);
    my %replacements = ();
    populateReplacements($opts,$user_pass,\%replacements);


    my ($repo, $using_http) = $self->fixRepoUrl($opts->{GitRepo}, $user_pass);

    # Command to execute
    my $cmd = "git ls-remote --tags \"$repo\"";

    my $tagCmdReturn = $self->RunCommand($cmd,
        {LogCommand => 1, LogResult => 0, Replacements => \%replacements});
    $self->cleanupCredentials($opts);

    # filter out the tags that are not on $commit
    my @lines = split /\n/, $tagCmdReturn;
    my $tagMd5 = "";
    foreach my $line (@lines) {
        if ($line =~ /$commit/) {
            my ($a, $tag) = split /\t/, $line;
            $tagMd5 .= $tag;
        }
    }
    if ($tagMd5 ne "") {
        $tagMd5 = md5_hex($tagMd5);
    }

    return $tagMd5;
}

###############################################################################
# code checkout routines
###############################################################################

####################################################################
# checkoutCode
#
# Checkout code
#   cleanupCredentials moved to afterRunMethod hook
#
# Args:
#   expected in the %args hash
#
#   dest
#
# Return:
#    1      = success
#    0      = failure
####################################################################
sub checkoutCode {
    my ($self, $opts) = @_;

    # print 'opts: ', Dumper $self->opts();
    $self->{_opts} = $opts;
    # TODO: This is a pretty big function. It would be worthwhile to
    # break it up into a few pieces.

    # Get configuration that is stored for this config
    my $name = $self->getCfg()->getName();
    my %row = $self->getCfg()->getRow($name);
    foreach my $k (keys %row) {
        $opts->{$k}=$row{$k};
    }

    # use Data::Dumper;
    # print Dumper $self->retrieveUserCredential($name . '_webhookSecret');
    # die;

    # Validate branch
    if (!$self->validateBranch($opts->{GitBranch})){
        die("Invalid branch name: $opts->{GitBranch}\n");
    }

    # Checkout master branch, if not specified
    if(isEmpty($opts->{GitBranch})) {
        $opts->{GitBranch} = "master";
    }

    my $gitRepos = $opts->{GitRepo};

    # Validate > 1 git repositories specified
    if (isEmpty($gitRepos)) {
        die("Error: At least one Git repository is required\n");
    }

    # Split and look for multiple repositories
    my @repos = split(m/[\r\n|]+/, $gitRepos);
    my $size = @repos;

    # Are we checking out multiple repositories
    my $multipleRepositories = ($size > 1);

    # Are we trying to get code from a tag?
    my $tagSpecified = !isEmpty($opts->{tag});

    if ($tagSpecified && $multipleRepositories) {
        die("Error: impossible to perform checkout using TAG with multiple repositories\n");
    }

    if(!isEmpty($opts->{commit}) && $multipleRepositories) {
          die("Error: impossible to perform checkout using Commit Hash with multiple repositories\n");
    }

    # Load userName and password from the credential
    ($opts->{gitUserName}, $opts->{gitPassword}) =
        $self->getCredentials($opts, $opts->{gitUserName}, $opts->{gitPassword});

    # Get the current working directory
    my $curDir = getcwd();

    my $user_pass = constructUserPass($opts);
    my %replacements = ();
    populateReplacements($opts,$user_pass,\%replacements);

    my $using_http = 0;

    my $clone = $opts->{clone} = ($opts->{clone} || '') eq '1' ? 1 : 0;
    my $overwrite = $opts->{overwrite} = ($opts->{overwrite} || '') eq '1' ? 1 : 0;

    my $destdir = $opts->{dest};

    if (defined $destdir) {
        # Trim trailing garbage.
        $destdir =~ s/[\s\/\\]+$//s;

        # Trim leading spaces.
        $destdir =~ s/^\s+//s;
    }
    else {
        $destdir = '';
    }

    # Set if the destination directory was specified
    my $destinationDirectorySpecified = ($destdir ne '');

    # Iterate and checkout each git repository provided
    my $ids = {};
    foreach my $git_repo (@repos) {
        #fix git urls
        my ($current_repo, $using_http) = $self->fixRepoUrl($git_repo, $user_pass);

        my $subdir = $destdir;

        # If there was no destination defined, follow convention and
        # construct it from the repository
        if (isEmpty($subdir)) {
          $subdir = getDefaultRepo($current_repo);
        }

        # If there are multiple repositories and a directory has been specified
        # then construct the destDir/repoDir
        if($multipleRepositories && $destinationDirectorySpecified){
            my $repoDir = getDefaultRepo($current_repo);
            $subdir = $subdir . '/' . $repoDir;
        }

        $subdir = File::Spec->rel2abs($subdir);

        if (-d $subdir && $overwrite) {
            print "Remove existing directory '$subdir'\n";
            rmtree($subdir);
        }

        if($destinationDirectorySpecified) {
          # Make the destination directory
          print "Creating directory '$subdir'\n";
          mkdirp($subdir);
        }
        else {
            print "Use directory: '$subdir'\n";
        }

        my ($cmd, $ret);

        if ($clone) {
            $ret = $self->performClone($opts, $current_repo, $subdir, $tagSpecified, \%replacements);
        } else {
            $ret = $self->performPull($opts, $current_repo, $subdir, $tagSpecified, \%replacements);
        }

        # Check exit code for last command
        # If there was an error, propagate it
        return 0 unless defined($ret);

        # Run reset if Commit Hash specified
        if(!isEmpty($opts->{commit})){
            $cmd = "git reset --hard $opts->{commit}";
            return 0 unless defined($self->RunCommand($cmd, {LogCommand => 1}));
        }

        # If a tag is specified and we've cloned, perform a checkout to the tag
        if ($clone && $tagSpecified) {
            $cmd = "git checkout tags/$opts->{tag}";

            if (! defined($self->RunCommand($cmd, {LogCommand => 1}))) {
                return 0;
            }
        }

        my $items = $self->generateChangelog($opts, $current_repo);
        $ids->{$git_repo} = [map { $_->{commit} } @{$items}];


        # Change back to the working directory in case we are doing another git
        # operation
        chdir $curDir;
    }


    $self->saveCheckoutResult($ids);

    return 1;
}


#*****************************************************************************

=head2 saveCheckoutResult

Saves the results under the specified property sheet.

=cut

#-----------------------------------------------------------------------------
sub saveCheckoutResult {
    my ($self, $result) = @_;

    my $sheet = $self->{_opts}->{resultPropertySheet};

    my $json         = encode_json($result);
    my $jsonProperty = "$sheet/json";

    local $@ = undef;
    eval {
        $self->getCmdr()->setProperty($jsonProperty, $json);
        $self->logger->info(qq{Set property "$jsonProperty" to result "$json"});
    };

    if ($@) {
        die qq{Set property "$jsonProperty" failed: $@\n};
    }

    my $headSheet = "$sheet/head";

    for my $repo (keys %{$result}) {
        my $hash = join(';', @{$result->{$repo}});

        $repo =~ s#[\[\]\/]+#-#g;

        my $headProperty = "$headSheet/$repo";

        local $@ = undef;
        eval {
            $self->getCmdr()->setProperty($headProperty, $hash);
            $self->logger->info(qq{Set property "$headProperty" to result "$hash"});
        };

        if ($@) {
            die qq{Set property "$headProperty" failed: $@\n};
        }
    }

    return;
} ## end sub saveCheckoutResult

###################################################################
# CollectReportingData
####################################################################
sub CollectReportingData {
    my ($self, $opts) = @_;

    for my $k (keys %$opts) {
        $opts->{$k} .= '';
    }
    # FIXME Is this really necessary?
    $self->{_opts} = $opts;

    $self->{logger}->info("Procedure parameters: ", $opts);
    if ($opts->{debug} && $self->{logger}->{level} < 1) {
        $self->{logger}->{level} = 1;
        $self->{logger}->debug("Debug is enabled");
    }

    my $payloads_sent = {
        codeCommit => 0,
        codeCommitFile => 0
    };

    $self->{ec} = ElectricCommander->new();

    my $payloads_to_send = [];
    # 0. Create reporting object
    my $reporting = EC::ReportingCore->new(
        $self->{ec}, {
            pluginName => 'ECSCM-Git',
            source => 'Git',
            pluginConfiguration => $opts->{config},
            transform => $opts->{transformScript},
            mappings  => $opts->{fieldMapping}
        }
    );
    if (!$opts->{previewMode} && !$opts->{debug}) {
        $reporting->{silent_reporting} = 1;
        # Disabling debug if it is not preview mode
        $self->{logger}->{level} = 0;
    }
    # Validate branch
    if (!$self->validateBranch($opts->{GitBranch})){
        die("Invalid branch name: $opts->{GitBranch}\n");
    }

    # Checkout master branch, if not specified
    if (isEmpty($opts->{GitBranch})) {
        $opts->{GitBranch} = "master";
    }

    my $git_repo = $opts->{GitRepo};

    if (isEmpty($git_repo)) {
        die("Error: Git repository is required\n");
    }

    # Load userName and password from the credential
    ($opts->{gitUserName}, $opts->{gitPassword}) =
        $self->getCredentials($opts, $opts->{gitUserName}, $opts->{gitPassword});

     # Get the current working directory
    my $curDir = getcwd();

    my $user_pass = constructUserPass($opts);
    my %replacements = ();
    populateReplacements($opts,$user_pass, \%replacements);

    my ($current_repo, $using_http) = $self->fixRepoUrl($git_repo, $user_pass);
    my $subdir = getDefaultRepo($current_repo);
    $self->debug("Subdir: " . Dumper $subdir);
    my $repo_name = $subdir;
    $subdir = File::Spec->rel2abs($subdir);
    $self->debug("Subdir changed to: '$subdir'");

    ### Metadata block

    # If metadata property path is not provided, default one will be used.
    # metadata property path defaults to plugin project, or schedule, depending on context.
    my $metadataPath = $reporting->buildMetadataLocation($repo_name, "code_commit");

    my $metadata = undef;
    if (!$self->{previewMode}) {
        $metadata = $reporting->getMetadata($metadataPath);
    }

    # Get remote metadata
    my ($lastSnapshot) = $self->getLastSnapshotFromRemoteRepo($opts);
    $self->logger()->debug("Remote metadata: ", $lastSnapshot);

    my $last_id = '';
    if ($metadata) {
        $self->logger()->debug("Metadata found:", Dumper $metadata);

        if ($metadata->{lastSnapshot} eq $lastSnapshot) {
            # TODO: Add summary setting here.
            $self->set_reporting_summary($payloads_sent, 1);
            exit 0;
        }
        # metadata is present, now limitation for depth and starting commit should be cancelled.
        $opts->{depth} = '';
        $opts->{commit} = '';
        $last_id = $metadata->{lastSnapshot};
    }
    else {
        $self->logger()->debug("Metadata not found.");
    }
    $metadata = { lastSnapshot => $lastSnapshot };
    ### end metadata block

    # Get metrics.
    # if we here, there is no metadata, or we have new data, and we can get metrics to be submitted.
    my $pull_result = $self->performPull($opts, $current_repo, $subdir, 0, \%replacements);
    unless ($pull_result) {
        $self->set_summary("Error occured during pull.");
        exit 1;
    }

    my @metrics = $self->get_metrics({
            last_id => $last_id,
            file_prefix => $opts->{filePrefix},
            opts => $opts,
        });

    # TODO
    #my $mappings = $reporting->buildMappings($metrics);
    #if (!$mappings->{codeCommit}) {
    #    $mappings->{codeCommit} = {};
    #}
    #if (!$mappings->{codeCommitFile}) {
    #    $mappings->{codeCommitFile} = {};
    #}
    #print Dumper($mappings);

    for my $commit (@metrics) {
        #print Dumper $commit->{commitId};

        my $commit_payload = {
            pluginConfiguration => '',
            pluginName => 'ECSCM-Git',
            source => 'Git',
            sourceUrl => '',
            baseDrilldownUrl => '',
            commitDate => '',
            scmUrl => '',
            scmRepoBranch => '',
            commitId => '',
            commitAuthor => '',
            commitAuthorId => '',
            commitMessage => '',
            codeLinesAdded => 0,
            codeLinesUpdated => 0,
            codeLinesRemoved => 0,
            filesAdded => 0,
            filesUpdated => 0,
            filesRemoved => 0,
            timestamp => '',
        };

        $commit_payload->{pluginConfiguration} .= $opts->{config};
        $commit_payload->{sourceUrl} .= $opts->{commitURLTemplate};
        $commit_payload->{sourceUrl} =~ s/\${repoUrl}/$opts->{GitRepo}/g;
        $commit_payload->{sourceUrl} =~ s/\${commitId}/$commit->{commitId}/g;
        $commit_payload->{sourceUrl} =~ s/\${branch}/$opts->{GitBranch}/g;
        #baseDrilldownUrl
        $commit_payload->{commitDate} = $commit->{commitDate};
        $commit_payload->{scmUrl} .= $opts->{GitRepo};
        $commit_payload->{scmRepoBranch} .= $opts->{GitBranch};
        $commit_payload->{commitId} = $commit->{commitId};
        $commit_payload->{commitAuthor} = $commit->{commitAuthor};
        $commit_payload->{commitAuthorId} = $commit->{commitAuthorId};
        $commit_payload->{commitMessage} = $commit->{commitMessage};
        $commit_payload->{codeLinesAdded} = $commit->{codeLinesAdded};
        $commit_payload->{codeLinesUpdated} = $commit->{codeLinesAdded} + $commit->{codeLinesRemoved};
        $commit_payload->{codeLinesRemoved} = $commit->{codeLinesRemoved};
        $commit_payload->{filesAdded} = $commit->{filesAdded};
        $commit_payload->{filesUpdated} = $commit->{filesUpdated};
        $commit_payload->{filesRemoved} = $commit->{filesRemoved};
        $commit_payload->{timestamp} = $commit->{commitDate};
        my $mappings = $reporting->buildMappings({
            commit => $commit
        });
        $self->logger()->debug("Commit object: ", Dumper $commit);
        $self->logger()->debug("Commit mappings: ", Dumper $mappings->{codeCommit});
        $commit_payload = {
            %{$commit_payload},
            %{$mappings->{codeCommit}}
        };

        $self->logger()->debug("Commit payload: ", Dumper $commit_payload);
        $reporting->validateAndConvert('code_commit', $commit_payload);

        my $temp_payloads = {
            codeCommit => {},
            codeCommitFile => [],
        };
        $temp_payloads->{codeCommit} = $commit_payload;
        ### Start code_commit_file reports
        #print Dumper ($commit->{files});
        if ($opts->{fileDetails} eq "1") {
            for my $commit_file ( @{ $commit->{files} }) {
                 #print Dumper $file;

                my $commit_file_payload = {
                    scmUrl => '',
                    scmRepoBranch => '',
                    commitId => '',
                    sourceUrl => '',
                    filePath => '',
                    fileClassification => '',
                    fileChangeType => '',
                    codeLinesAdded => '',
                    codeLinesUpdated => 'n/a',
                    codeLinesRemoved => ''
                };

                $commit_file_payload->{scmUrl} .= $opts->{GitRepo};
                $commit_file_payload->{scmRepoBranch} .= $opts->{GitBranch};
                $commit_file_payload->{commitId} = $commit->{commitId};

                $commit_file_payload->{sourceUrl} .= $opts->{fileURLTemplate};
                $commit_file_payload->{sourceUrl} =~ s/\${repoUrl}/$opts->{GitRepo}/g;
                $commit_file_payload->{sourceUrl} =~ s/\${commitId}/$commit->{commitId}/g;
                $commit_file_payload->{sourceUrl} =~ s/\${branch}/$opts->{GitBranch}/g;
                $commit_file_payload->{sourceUrl} =~ s/\${fileName}/$commit_file->{filePath}/g;

                $commit_file_payload->{filePath} = $commit_file->{filePath};
                # fileClassification
                # fileChangeType
                $commit_file_payload->{codeLinesAdded} = $commit_file->{codeLinesAdded};
                $commit_file_payload->{codeLinesUpdated} = $commit_file->{codeLinesAdded} + $commit_file->{codeLinesRemoved};
                $commit_file_payload->{codeLinesRemoved} = $commit_file->{codeLinesRemoved};

                $reporting->validateAndConvert('code_commit_file', $commit_file_payload);
                $self->logger()->debug("File object: ", Dumper $commit_file);
                my $mappings = $reporting->buildMappings({commit => $commit, commitFile => $commit_file});
                if (!$mappings) {
                    $mappings = {codeCommitFile => {}};
                }
                $self->logger()->debug("CodeCommitFile Mappings: ", Dumper $mappings->{codeCommitFile});
                $commit_file_payload = {
                    %{$commit_file_payload},
                    %{$mappings->{codeCommitFile}}
                };
                $self->logger()->debug("CodeCommitFile Payload: ", Dumper $commit_file_payload);
                push @{$temp_payloads->{codeCommitFile}}, $commit_file_payload;
            }
        }
        push @{$payloads_to_send}, $temp_payloads;
    }
    print "Transforming payloads:\n";
    @$payloads_to_send = map {
        $self->logger()->debug("Payload before transform: ", Dumper $_);
        $_ = $reporting->doTransform($_);
        $self->logger()->debug("Payload after transform: ", Dumper $_);
        $_;
    } @$payloads_to_send;

    unless ($opts->{previewMode}) {
        $self->logger()->debug("Sending payloads");
        for my $p (@{$payloads_to_send}) {
            $self->logger()->debug("CodeCommit Payload: ". Dumper $p->{codeCommit});
            my $commit_result = $reporting->sendReportToEF('code_commit', $p->{codeCommit});
            unless ($commit_result->{ok}) {
                $self->set_summary("Can't send report: $commit_result->{message}");
                die "Can't sent code_commit report: $commit_result->{message}\n";
            }
            $payloads_sent->{codeCommit}++;
            for my $fp (@{$p->{codeCommitFile}}) {
                $self->logger()->debug("CodeCommitFile Payload: ". Dumper $fp);
                my $file_commit_result = $reporting->sendReportToEF('code_commit_file', $fp);
                unless ($file_commit_result->{ok}) {
                    $self->set_summary("Can't send report: $file_commit_result->{message}");
                    die "Can't sent code_commit_file report: $file_commit_result->{message}\n";
                }
                $payloads_sent->{codeCommitFile}++;
            }
        }
        $reporting->setMetadata($metadataPath, $metadata);
        $self->set_reporting_summary($payloads_sent);
    }
}

####################################################################
sub property_exists {
    my ($self, $prop) = @_;

    my $ec = $self->getCmdr();


    my $no_error_transaction = sub {
        my ($code) = @_;
        my $old_abort_on_error = $ec->abortOnError();
        $ec->abortOnError(0);
        eval {$code->();};
        my $err = $@;
        $ec->abortOnError($old_abort_on_error);
        if ($err) {
            die $err;
        }
    };

    my $exists = 1;
    my $error_message;

    $no_error_transaction->(
        sub {
            my $xpath = $ec->getProperty($prop);
            my $code  = $xpath->findvalue('//code')->string_value;
            $self->logger->info(qq{Trying to get "$prop": $code});
            if ($code) {
                $exists        = 0;
                $error_message = qq{Cannot get property "$prop": $code};
            }
        }
    );
    return ($exists, $error_message);
} ## end sub property_exists

####################################################################
sub getArtifactsDirectory {
    my ($self, $create) = @_;

    my $ec = $self->getCmdr();


    my $property = '/myJob/artifactsDirectory';
    my ($property_exists) = $self->property_exists($property);
    if (!$property_exists) {
        my ($projectName) = $self->getProjectAndScheduleNames();

        $property = "/projects/$projectName/artifactsDirectory";
        ($property_exists) = $self->property_exists($property);
        if (!$property_exists) {
            $property = '/myProject/artifactsDirectory';
            ($property_exists) = $self->property_exists($property);
            if (!$property_exists) {
                $property = '/server/artifactsDirectory';
                ($property_exists) = $self->property_exists($property);
            }
        }
    }

    my $art_dir;
    if ($property_exists) {
        $art_dir = $ec->getProperty($property)->findvalue('//value')->string_value();

        if (!defined($art_dir) || ($art_dir eq '')) {
            $self->{logger}->info("Artifacts directory: is empty");
            return $ENV{COMMANDER_WORKSPACE};
        }
    }
    else {
        $art_dir = 'artifacts';
    }

    $self->{logger}->info("Artifacts directory: ", $art_dir);

    $art_dir = File::Spec->catdir($ENV{COMMANDER_WORKSPACE}, $art_dir);

    if (!-d $art_dir && $create) {
        mkpath($art_dir);
    }

    return $art_dir;
} ## end sub getArtifactsDirectory

####################################################################
sub createChangelogReport {
    my ($self, $name, $items) = @_;

    my $ec = $self->getCmdr();

    my $pluginProjectName = $ec->getPlugin({pluginName => $self->{pluginName}})->findvalue('//projectName')->string_value;
    my ($success, $xpath, $msg)
        = $self->InvokeCommander({SuppressLog => 1, IgnoreError => 1}, "getProperty", "/projects/$pluginProjectName/templates/changeLogs");
    if (!$success) {
        die "Error getting template 'changeLogs': $msg\n";
    }

    my $template = $xpath->findvalue('//value')->string_value;
    unless ($template) {
        die "Template 'changeLogs' is empty\n";
    }

    # get class code
    my $property = "/plugins/$pluginProjectName/project/scm_driver/Text::MicroTemplate";
    my $result = ElectricCommander::PropMod::loadPerlCodeFromProperty($ec, $property);
    if (!$result) {
        die "Could not load Text::MicroTemplate module\n";
    }


    # require Text::MicroTemplate;

    my $renderer = Text::MicroTemplate::build_mt($template);

    local $@ = undef;
    my $report = eval {$renderer->({name => $name, items => $items})->as_string};
    if ($@) {
        die "Render failed: $@\n";
    }


    my $art_dir = $self->getArtifactsDirectory(1);

    my $filename = sprintf('changeLogDetails_%06d.html', int(rand(1_000_000)));
    my $filepath = File::Spec->catfile($art_dir, $filename);

    open(FILE, '>', $filepath) or die "Cannot create $filepath: $!\n";
    print(FILE $report);
    close(FILE);


    my $job_step_id = $ENV{COMMANDER_JOBSTEPID};
    my $link        = "/commander/jobSteps/$job_step_id/$filename";

    eval {$ec->setProperty("/myJob/report-urls/$name", $link);};

    my $summary = qq{<html><a href="$link" target="_blank">Download Report</a></html>};

    eval {$ec->setProperty('/myPipelineStageRuntime/ec_summary/' . $name, $summary);};

    return 1;
} ## end sub createChangelogReport

####################################################################
# generateChangelog
#
#
# Arguments:
#   opts          -              Hash containing all options
#   current_repo  -              The repository to pull from
#
# Returns: void
#
####################################################################
sub generateChangelog
{
    my ($self, $opts, $current_repo) = @_;

    my $ec = $self->getCmdr();

    # Get the scm key to allow us to later generate the revision and
    # changelog properties
    my $scmKey = $self->getKeyFromUrl($current_repo)."-".$opts->{GitBranch};

    # Get last checked out revision
    my $fromRevision = $self->getStartForChangeLog($scmKey) || "";

    # If there is no last checked revision, show only last comment
    # Otherwise, show from $fromRevision to HEAD
    my $commitRange = $fromRevision ? "$fromRevision.." : "-1";

    # Create the log command to retrieve the last change description
    #TODO: add option to choose format output or remove completely commented git log command
    #my $cmd = qq{git log $commitRange --pretty=format:"%H|%an
    my $cmd = qq{git log $commitRange --name-status};
    print "Retrieveing changelog using following command:\n$cmd\n";
    my $log = $self->RunCommand($cmd, {LogCommand=>0});

    my @items;
    if ($log) {
        my $snapshot = $self->RunCommand("git log -1 --pretty='format:%H'", {LogCommand=>0});
        if(!$snapshot) {
            die "Can't get last commit hash!";
        }

        @items = parseGitLog($log);
        #print 'PARSED LOG: ' . Dumper @items;

        $self->setPropertiesOnJob($scmKey, $snapshot, $log);

        my ($projectName, $scheduleName, $procedureName) =
        $self->getProjectAndScheduleNames();

        if (!isEmpty($scheduleName)) {
            my $prop = "/projects[$projectName]/schedules[$scheduleName]/" .
                "ecscm_changelogs/$scmKey";
            $ec->setProperty($prop, $log);
        }

        my $changelogReportName = $current_repo;
        $changelogReportName =~ s#^.*/##;
        $changelogReportName =~ s#\.git$##;
        $changelogReportName = sprintf("Changelog report: %s - %s", $changelogReportName, $opts->{GitBranch});
        $self->createChangelogReport($changelogReportName, \@items);
    }

    return \@items;
}

####################################################################
# createLinkToChangelogReport
#
# Side Effects:
#   If /myJob/ecscm_changelogs exists, create a report-urls link
#
# Arguments:
#   self -              the object reference
#   reportName -        the name of the report
#
# Returns:
#   Nothing.
####################################################################
sub createLinkToChangelogReport {
    my ($self, $reportName) = @_;

    my $name = $self->getCfg()->getSCMPluginName();

    my ($success, $xpath, $msg) = $self->InvokeCommander({SuppressLog=>1,IgnoreError=>1}, "getProperty", "/plugins/$name/pluginName");
    if (!$success) {
        print "Error getting promoted plugin name for $name: $msg\n";
        return;
    }

    my $root = $xpath->findvalue('//value')->string_value;

    my $prop = "/myJob/report-urls/$reportName";
    my $target = "/commander/pages/$root/reports?jobId=".$self->{jobId};

    # e.g. /commander/pages/EC-DefectTracking-JIRA-1.0/reports?debug=1?jobId=510
    print "Creating link $target\n";

    ($success, $xpath, $msg) = $self->InvokeCommander({SuppressLog=>1,IgnoreError=>1}, "setProperty", "$prop", "$target");

    if (!$success) {
        print "Error trying to set property $prop: $msg\n";
    }
}

####################################################################
# performPull
#
#
# Arguments:
#   opts          -              Hash containing all options
#   current_repo  -              The repository to pull from
#   subdir        -              The directory where the code pulled from
#                                the git server will reside
#   tagSpecified  -              0/1 if a tag was specified by the user
#   replacements  -              The hash containing passwords to censor
#
# Side Effects: working directory is changed to subdir
# Returns: void
#
####################################################################
sub performPull
{
    my ($self, $opts, $current_repo, $subdir, $tagSpecified, $replacements) = @_;

    # Only create and CD to the directory if we aren't cloning.  This is
    # because for git versions before 1.6.2, cloning fails even for an
    # empty directory:
    # https://github.com/git/git/commit/55892d23981917aefdb387ad7d0429f90cbd446a
    print "Creating and changing to directory $subdir\n";
    mkpath($subdir);
    if (!chdir $subdir) {
        die("Could not change to directory $subdir\n");
    }
    my $cmdReturn = $self->RunCommand("git init", {LogCommand => 0});


    my $cmd = "";

    # Create pull command
    if($tagSpecified) {
        $cmd = "git pull $current_repo -t $opts->{tag}";
    } else {
        $cmd = "git pull $current_repo $opts->{GitBranch}";
    }

     # Run pull commmand
    $cmdReturn = $self->RunCommand($cmd, {LogCommand => 1, LogResult => 0, Replacements => $replacements});

    print "Pull: $cmdReturn\n";

    return $cmdReturn;
}

####################################################################
# performClone
#
#
# Arguments:
#   opts          -              Hash containing all options
#   current_repo  -              The repository to pull from
#   subdir        -              The directory where the code pulled from
#                                the git server will reside
#   tagSpecified  -              0/1 if a tag was specified by the user
#   replacements  -              The hash containing passwords to censor
#
# Side Effects: working directory is changed to subdir
# Returns: void
#
####################################################################
sub performClone
{
    my ($self, $opts, $current_repo, $subdir, $tagSpecified, $replacements) = @_;

    my $cmd = "git clone";

    # For clone command --depth option should come before <directory>
    if(!isEmpty($opts->{depth})) {
        $cmd .= " --depth $opts->{depth}";
    }

    # Create clone command with destination folder
    if(!isEmpty($opts->{GitBranch})) {
        $cmd .= qq{ "$current_repo" -b $opts->{GitBranch} \"$subdir\"};
    } else {
        $cmd .= qq{ "$current_repo" \"$subdir\"};
    }

    # Run clone commmand
    my $cmdReturn = $self->RunCommand($cmd,
        {LogCommand => 1, LogResult => 0, Replacements => $replacements});

    print "Clone: $cmdReturn\n";

    # After we have run clone, it's safe to cd into the directory
    # so subsequent git commands run as expected.

    print "Changing to directory $subdir\n";
    if (!chdir $subdir) {
        die("Could not change to directory $subdir\n");
    }

    return $cmdReturn;
}

####################################################################
# getKeyFromUrl
#
# Side Effects:
#
# Arguments:
#   url  -              the Git url
#
# Returns:
#   "Git" plus the last part of a git reposirory
####################################################################
sub getKeyFromUrl
{
    my ($self, $url) = @_;
    $url =~ s/.*\///g;
    return "Git-$url";
}

#-------------------------------------------------------------------------
#
#  Fix the git repo url by injecting credentials in the url
#
#  Params
#       repo => url to the git repository.
#            supported formats:
#               SSH         => git@github.com:ecplugin/ectest.git
#               HTTP:       => https://user@github.com/ecplugin/ectest.git
#               HTTP:       => https://github.com/ecplugin/ectest
#               Git:        => git://github.com/ecplugin/ectest.git
#               Bitbucket:  => https://user@bitbucket.org/user/ec-test.git
#       user_pass => user credentials with the following format: user:password@
#  Returns
#       repo  - fixed url
#       using_http - 0/1
#
#-------------------------------------------------------------------------
sub fixRepoUrl {
    my ($self, $repo, $user_pass) = @_;

    my $using_http = 0;
    my $new_url = '';
    my $proto = '';

    $using_http = 1 if $repo =~ m|^https?://|is;

    if ($repo =~ m/@/) {
        $repo =~ s|://.+@|://$user_pass|is;
    }
    else {
        $repo =~ s|://|://$user_pass|is;
    }


    return ($repo, $using_http);
}


sub fixRepoUrl_old {
    my ($self, $repo, $user_pass) = @_;

    #removing users in the url to avoid git ask for a password
    my $using_http = 0;
    $repo =~ s/([https:|http:]\/\/)(.*@)(.*)/$1$user_pass$3/ixms;
    #if the name doesnt contain the user name and password and inject the user credentials in the url
    if ($repo !~ m/(.+):(.+)@(.+)/i) {
        #http or https
        if ($repo =~ m/https:/i) {
            substr $repo, length ('https://'), 0, $user_pass;
        }
        elsif ($repo =~ m/http:/i) {
            substr $repo, length ('http://'), 0, $user_pass;
        }
        $using_http = 1;
    } elsif ($repo =~ m/http/i) {
        $using_http = 1;
    }
    return ($repo, $using_http);
}

#-------------------------------------------------------------------------
#
#  Find the name of the project of the current job and the schedule that was
#  used to launch it.
#
#  Params
#       None
#
#  Returns
#       projectName  - the Project name of the running job
#       scheduleName - the Schedule name of the running job
#
#  Notes
#       scheduleName will be an empty string if the current job was not
#       launched from a Schedule
#
#-------------------------------------------------------------------------

sub getProjectAndScheduleNames
{
    my $self = shift;

    my $scheduleName = "";
    my $projectName = "";
    my $procedureName = "";



    # Call CloudBees CD to get info about the current job
    my ($success, $xPath) = $self->InvokeCommander({SuppressLog=>1},
                                                   "getJobInfo",
                                                   $self->{jobId});

    # Find the schedule name in the properties
    $scheduleName = $xPath->findvalue('//scheduleName');
    $projectName = $xPath->findvalue('//projectName');
    $procedureName = $xPath->findvalue('//procedureName');


    return ($projectName, $scheduleName, $procedureName);
}

###############################################################################
# agentPreflight routines  (apf_xxxx)
###############################################################################

#------------------------------------------------------------------------------
# apf_getScmInfo
#
#       If the client script passed some SCM-specific information, then it is
#       collected here.
#------------------------------------------------------------------------------

sub apf_getScmInfo
{
    my ($self,$opts) = @_;

    my $cwd = getcwd();
    my $scm_info_path = $cwd . '/' . 'ecpreflight_data/scmInfo';
    my $scmInfo = $self->pf_readFile($scm_info_path);
    $scmInfo =~ m/(.*)\n/;
    $opts->{GitBranch} = $1;
    print("Git information received from client:\n"
            . "GitBranch: $opts->{GitBranch}\n");
}

#------------------------------------------------------------------------------
# apf_createSnapshot
#
#       Create the basic source snapshot before overlaying the deltas passed
#       from the client.
#------------------------------------------------------------------------------
sub apf_createSnapshot
{
    my ($self,$opts) = @_;

    my $result = $self->checkoutCode($opts);
    if (defined $result) {
        print "checked out $result\n";
    }
}

#------------------------------------------------------------------------------
# apf_driver
#
# agent preflight driver for git
#------------------------------------------------------------------------------
sub apf_driver()
{
    my $self = shift;
    my $opts = shift;

    if ($opts->{test}) { $self->setTestMode(1); }
    $opts->{delta} = "ecpreflight_files";

    $self->apf_downloadFiles($opts);
    $self->apf_transmitTargetInfo($opts);
    $self->apf_getScmInfo($opts);
    $self->apf_createSnapshot($opts);
    $self->apf_deleteFiles($opts);
    $self->apf_overlayDeltas($opts);
}

###############################################################################
# clientPreflight routines  (cpf_xxxx)
###############################################################################

#------------------------------------------------------------------------------
# copyDeltas
#
#       Finds all new and modified files and either copies them directly to
#       the job's workspace or transfers them via the server using putFiles.
#       The job is kicked off once the sources are ready to upload.
#
#   methods:
#       local_all     - get tracked and untracked changes between working
#                       tree and local repo
#       local_tracked - get tracked changes between working tree and local repo
#       remote        - get changes between local repo and it's remote
#
#
#------------------------------------------------------------------------------
sub cpf_copyDeltas
{
    my ($self, $opts) = @_;
    $self->cpf_display("Collecting delta information");

    # change to the git dir
    if (!defined($opts->{scm_gitdir}) ||  "$opts->{scm_gitdir}" eq "") {
        $self->cpf_error("Could not change to directory $opts->{scm_gitdir}");
    }

    chdir ($opts->{scm_gitdir}) || $self->cpf_error("Could not change to directory $opts->{scm_gitdir}");

    # legacy flag
    if (!defined($opts->{scm_method}) && defined($opts->{scm_copyUncommitted}) &&
       "$opts->{scm_copyUncommitted}" eq "yes" ) {
       $opts->{scm_method} = "local_all";
    }
    if (!defined($opts->{scm_method}) ||
        ("$opts->{scm_method}" ne "local_tracked" &&
         "$opts->{scm_method}" ne "local_all" &&
         "$opts->{scm_method}" ne "remote" )
         ) {
        # default method if not provided is local_commit
        $self->cpf_error("method $opts->{scm_method} not recognized. must be \"local_all\","
            . "\"local_tracked\", or \"remote\".");
    }

    $self->cpf_findTargetDirectory($opts);
    $self->cpf_createManifestFiles($opts);

    my $files = ();
    if ($opts->{scm_method} ne "remote") {
        # get files that are different between the working directory
        # and the local repostitory
        $files = $self->cpf_localDelta($opts);
    } else {
        $files = $self->cpf_remoteDelta($opts);
    }

    # based on method of finding deltas, pick a result set
    my @changetypes ;
    push @changetypes, "commit";
    if ($opts->{scm_method} eq "local_all" ){
        push @changetypes, "changed";
        push @changetypes, "untracked";
    }
    my $top = getcwd();

    # now for all the changetypes of interest, move the files
    # files are relative to the current directory
    foreach my $type (@changetypes) {
        foreach my $f ( @{ $files->{$type}{deltafile} } ) {
            my $fpath = $top . "/$f";
            $fpath = File::Spec->rel2abs($fpath);
            $self->cpf_addDelta($opts,$fpath, "$f");
        }
        foreach my $d ( @{ $files->{$type}{delfiles} } ) {
            $self->cpf_addDelete("$d");
        }
    }

    $self->cpf_closeManifestFiles($opts);
    # agent checkout will use refspec refs/for/branch  where branch was extracted
    # from git status
    $self->cpf_saveScmInfo($opts,"refs/heads/$opts->{scm_branch}\n");
    $self->cpf_uploadFiles($opts);
}

#------------------------------------------------------------------------------
# cpf_localDelta
#
#   use git status to find deltas between working dir and local repo
#   retrieves both tracked and untracked files
#   caller can choose which to consider
#
#
#------------------------------------------------------------------------------
sub cpf_localDelta
{
    my ($self, $opts) = @_;
    $self->cpf_display("Collecting deltas from local repo");

    # Get current branch
    my $output  = $self->RunCommand( "git branch", {LogCommand => 1});
    $self->cpf_debug("$output");
    $opts->{scm_branch} = (split(" ", $output))[1];

    # Collect a list of opened files.
    # this assumes the current dir is the top of the
    # working tree
    # since git returns 1 for situations we consider non-error, we
    # ignore the error status and rely on the content returned.
    # Use --porcelain options, which have format compatible across all git versions.
    my $output  = $self->RunCommand( "git status --porcelain", {LogCommand => 1});
    $self->cpf_debug("$output");

    # Parse the output from git status and figure out the file name and what
    # type of change is being made.

    ##### OUTPUT SAMPLE
    # A   zero
    # M   one
    # D   two
    # ??  three
    #   M four
    #   D five
    ######################
    my $files = ();

    for my $line (split('\n', $output)) {
        my ($tm, $file) = $line =~ /^(.{2})\s(.*)$/;
        my ($type, $mode) = ('commit', 'deltafile');

        # Deleted files marked by ' D' or ' D' type
        if ($tm =~ /(D | D)/) {
            $mode = 'delfiles';
        }

        # Uncomitted changes marked with starting space in type
        if ($tm =~ / ./) {
            $type = 'changed';
        } elsif ($tm eq '??') {
            # File added, but not marked for commit
            $type = 'untracked';
        }

        push @{$files->{$type}{$mode}} , $file;
    }

    return $files;
}

#------------------------------------------------------------------------------
# cpf_remoteDelta
#
#       use git diff to find deltas between local repo and remote repo
#------------------------------------------------------------------------------
sub cpf_remoteDelta
{
    my ($self, $opts) = @_;
    $self->cpf_display("Collecting deltas between local and remote");

    # if specific branch not specified, get current checkout branch
    if (!defined($opts->{scm_branch}) ||"$opts->{scm_branch}" eq "") {
        # find the current branch
        my $branches  = $self->RunCommand( "git branch -a", {LogCommand => 1});
        $self->cpf_debug("$branches");

        foreach(split(/\n/, $branches)) {
            my $line = $_;
            if (! ($line =~ /^\*/)) { next;}
            chomp $line;
            $line =~ /^\* (.*)/;
            $opts->{scm_branch} = $1;
            last;
        }
    }

    if ("$opts->{scm_branch}" eq "") {
        $self->cpf_error("No branch specified and could not"
            . " detect current branch with \"git branch -a\" command.");
    }

    # if specific remote not specified, get from config
    if (!defined($opts->{scm_remote}) ||"$opts->{scm_remote}" eq "") {
        # get the remote for this branch
        my $remote  = $self->RunCommand(
            "git config"
            . " --get branch."
            . $opts->{scm_branch}
            . ".remote",
            {LogCommand => 1});
        chomp $remote;
        $opts->{scm_remote} = $remote;
        $self->cpf_debug("remote:$opts->{scm_remote}");
    }

    if (!defined($opts->{scm_remote}) ||"$opts->{scm_remote}" eq "") {
        $self->cpf_error("Remote not specified and could not detect using"
            ." \"git config --get branch.$opts->{scm_branch}.remote\" command.");
    }

    # get list of deltas between local and remote
    my $deltas  = $self->RunCommand(
        "git diff --name-status "
        . $opts->{scm_remote}
        . "/"
        . $opts->{scm_branch}
        . "..."
        . $opts->{scm_branch},
        {LogCommand => 1});

    $self->cpf_debug("deltas:$deltas");

    # Parse the output

    ##### OUTPUT SAMPLE
    #D       tools/zipalign/README.txt
    #M       tools/zipalign/ZipFile.h
    #A       twelve
    ######################
    my $files = ();
    my $type = "commit";
    foreach(split(/\n/, $deltas)) {
        my $line = $_;
        if ($line =~ "^M[ \t]*(.*)") {
            # modified files
            push @ { $files->{$type}{deltafile} } , $1;
            $self->cpf_debug("modified file $1");
        }
        if ($line =~ "^A[ \t]*(.*)") {
            # added files
            push @ { $files->{$type}{deltafile} } , $1;
            $self->cpf_debug("added file $1");
        }
        if ($line =~ "^D[ \t]*(.*)") {
            # deleted files
            push @ { $files->{$type}{delfiles} } , $1;
            $self->cpf_debug("deleted file $1");
        }
    }
    return $files;
}

#------------------------------------------------------------------------------
# autoCommit
#
#       Automatically commit changes
#
### TODO
#  Error out if:
#       - A check-in has occurred since the preflight was started, and the
#         policy is set to die on any check-in.
#       - A check-in has occurred and opened files are out of sync with the
#         head of the branch.
#       - A check-in has occurred and non-opened files are out of sync with
#         the head of the branch, and the policy is set to die on any changes
#         within the client workspace.
#------------------------------------------------------------------------------
sub cpf_autoCommit()
{
    my ($self, $opts) = @_;

    $self->cpf_display("Committing changes");
    $self->RunCommand("git commit -m \"$opts->{scm_commitComment}\"", {LogCommand =>1});

    # todo check that commit succeeded
    $self->cpf_display("Changes have been successfully submitted");
}

#------------------------------------------------------------------------------
# driver
#
#       Main program for the application.
#------------------------------------------------------------------------------
sub cpf_driver
{
    my ($self, $opts) = @_;

    $self->cpf_display("Executing Git actions for ecpreflight");
    $::gHelpMessage .= "
Git Options:

--gitdir=dir          The Git directory to process
--method= local_all get tracked and untracked changes between working tree and local repo  | local_tracked = get tracked changes between working tree and local repo | remote
";

    ## override config file with command line options
    my %ScmOptions = (
    "gitdir=s"            => \$opts->{scm_gitdir},
    "method=s"            => \$opts->{scm_method},

    );

    Getopt::Long::Configure("default");
    if (!GetOptions(%ScmOptions)) {
        error($::gHelpMessage);
    }

    if ($::gHelp eq "1") {
        $self->cpf_display($::gHelpMessage);
        return;
    }

    # Collect SCM-specific information from the configuration
    $self->extractOption($opts, "scm_gitdir");

    $self->cpf_debug("gitdir=$opts->{scm_gitdir}");

    # if auto-commit, then require a commit comment.
    if ($opts->{scm_autoCommit} && !defined($opts->{scm_commitComment}) ) {
        $self->cpf_error("Required element \"scm_commitComment\" is empty or absent in "
                . "the provided options.  May also be passed on the command "
                . "line using --commitComment");
    }

    # Copy the deltas to a specific location.
    $self->cpf_copyDeltas($opts);

    # Auto commit if the user has chosen to do so.

    if ($opts->{scm_autoCommit}) {
        if (!$opts->{opt_Testing}) {
            $self->cpf_waitForJob($opts);
        }
        $self->cpf_autoCommit($opts);
    }
}

#------------------------------------------------------------------------------
# validateBranch
#    Verify that a branch name doesn't:
#        - Have a path component that begins with "."
#        - Have a double dot ".."
#        - Have an ASCII control character, "~", "^", ":" or SP, anywhere
#        - End with a "/"
#        - End with ".lock"
#        - Contain a "\" (backslash
#------------------------------------------------------------------------------
sub validateBranch {
    my ($self, $branch) = @_;
    if($branch && $branch ne ""){
        if($branch =~ m/^\.|\/$|\.lock|\\|(\.\.)|[~^:\s]/gi){
            return 0;
        }
    }
    return 1;
}

#------------------------------------------------------------------------------
# getDefaultRepo
#     follow git convention and attempt to determine the directory
#     a git clone populates when no directory was specified.
#
#     Also refered to as "humanish" part of source repo
#
#
# https://www.kernel.org/pub/software/scm/git/docs/git-clone.html
# How git does it:
# https://github.com/git/git/blob/master/contrib/examples/git-clone.sh#L232
#------------------------------------------------------------------------------
sub getDefaultRepo {

  my ($repo) = @_;


  $repo =~ s|/\$||;
  # Strip off .git
  $repo =~ s|:*/*\.git$||;

  $repo =~ s|.*[/:]||;

  return $repo;
}

#------------------------------------------------------------------------------
# mkdirp
# Emulate mkdir -p
#------------------------------------------------------------------------------
sub mkdirp {
    my $dir = shift;
    return if (-d $dir);
    mkdirp(dirname($dir));
    mkdir $dir;
}

#------------------------------------------------------------------------------
# isEmpty
#
# Helper function that returns true if the given scalar
# is empty or undefined.
#------------------------------------------------------------------------------
sub isEmpty($) {
    my ($str) = @_;

    return !defined($str) || length($str) == 0;
}

#------------------------------------------------------------------------------
# constructUserPass
#
# Returns a concatentation of username:password, with a ':' in between
# Args:
#   opts hash
#------------------------------------------------------------------------------

sub constructUserPass($) {

    my ($opts) = @_;

    my $user_pass = $opts->{gitUserName};

    if (!isEmpty($opts->{gitPassword})) {
        # Construct the string to use in the actual git command
        $user_pass .= ":$opts->{gitPassword}";
    }

    # Add '@' only if the user name has been specified
    if (!isEmpty($user_pass)) {
        $user_pass .= "@";
    }

    return $user_pass;
}

#------------------------------------------------------------------------------
# populateReplacements
#
# We construct a username-password string to embed in the url to Git.
# However, in some error cases, Git emits the full url in error messages.
# Fortunately, we capture the output, so we can tweak it before emitting
# to *our* stdout (which ultimately goes to the step log file).
#
# We do so by creating a "replacements" hash that maps patterns to
# target values in RunCommand.
# Args:
#   opts hash
#   user_pass  string in the form username:password@
#   replacements hash
# Side Effect: Replacements hash is populated with value to print out
#              instead of the real password
#------------------------------------------------------------------------------
sub populateReplacements($$) {

    my ($opts, $user_pass, $replacements) = @_;

    # Get the git user name
    my $user = $opts->{gitUserName};

    if (!isEmpty($opts->{gitPassword})) {

        # Create a string to emit in the log messages
        my $safe_user_pass = $user . ':****@';

        # Add the sanitized string to the hash for future retrieval
        $replacements->{$user_pass} = $safe_user_pass;
    }
}

#------------------------------------------------------------------------------
# Wrapper for ECSCM's retrieveUserCredential, with support for ssh keys
# Depending of credentialType config property, we treat userPassword content
# as private ssh key or password
# Args:
#   opts hash
#   user username
#   password password or private key
# Returns:
#   array containing username and password, or undef's ff there are no
#   credentials assigned or credentials contain public ssh key
#------------------------------------------------------------------------------
sub getCredentials {
    my ($self, $opts, $user, $password) = @_;

    # Load userName and password from the credential
    ($opts->{gitUserName}, $opts->{gitPassword}) =
        $self->retrieveUserCredential($opts->{credential}, $user, $password);

    # Get the git user name and password
    $user = $opts->{gitUserName};
    $password = $opts->{gitPassword};

    if($self->getCfg()->get("credentialType") eq "key") {
        $self->createKeyWrapper($user, $password);
        $password = undef;
    }
    else {
        my $version = $self->getGitVersion;
        # Email, slashes and other stuff should be escaped
        # From version 1.7.3.4 the escape logic changes
        if ($self->compareVersions($version, '1.7.3.4') >= 0) {
            print "Git is later than 1.7.3.4, applying escape logic\n";
            $user = escape($user);
            $password = escape($password);
        }
    }

    return ($user, $password);
}

#------------------------------------------------------------------------------
# Cleanup step's directory from ssh wrapper script and private key file
# in case we are using ssh private key authentication
# Args:
#   opts hash
# Returns:
#   None
#------------------------------------------------------------------------------
sub cleanupCredentials {
    my ($self, $opts) = @_;

    if($self->getCfg()->get("credentialType") ne "key") {
        return;
    }

    # try new cool cleanup
    if (exists $self->{_idRsaFileName}) {
        File::Temp::cleanup();
        return;
    }

    # old cleanup also supported
    my $workspace = $ENV{COMMANDER_WORKSPACE};
    my $jobStepId = $ENV{COMMANDER_JOBSTEPID};
    my @files = ("$workspace/id_rsa.".$jobStepId, "$workspace/git_ssh.".$jobStepId);

    print "Removing private key ssh wrapper in $workspace\n";
    unlink(@files) or warn "Could not remove ssh credentials from $workspace.";
}

#------------------------------------------------------------------------------
# Setup wrapper script for git ssh key handling
# Args:
#   opts hash
#------------------------------------------------------------------------------
sub createKeyWrapper {
    my ($self, $user, $key) = @_;

    my $idRsaKeyFile = $self->{_idRsaFileName};
    my $gitSSHClientFile = $self->{_gitSSHClientFile};

    if ($idRsaKeyFile && -e $idRsaKeyFile->filename() && -e $gitSSHClientFile) {
        print "Files already exists\n";
        return 0;
    }

    my $workspace = $ENV{COMMANDER_WORKSPACE};

    # let's deal with id_rsa file
    my $idRsaKeyFile = File::Temp->new("id_rsa.XXXXXX",
        DIR =>  $workspace,
    );

    print "Creating private key ssh wrapper in $workspace\n";

    my $privateKeyFile = $idRsaKeyFile->filename();
    # write the private key to a file
    print $idRsaKeyFile $key;
    # change the access right for security reason
    # Otherwise the git command fails for security warning when running in commander
    chmod 0600, $privateKeyFile;

    # let's deal with script file

    my $scriptFile = $workspace . '/' . 'git_ssh';

    # create the script
    my $scriptContent = join "\n", (
        '#!/bin/sh',
        qq|/usr/bin/ssh -T -o "BatchMode=yes" -o "StrictHostKeyChecking=no" -l "$user" -i "$privateKeyFile" "\$@"|,
    );

    local *SCRIPTFILE;
    open SCRIPTFILE, '>', $scriptFile;
    print SCRIPTFILE $scriptContent or do {
        $self->error("Can't write git client script: $!");
    };
    close SCRIPTFILE;

    chmod 0700, $scriptFile;

    $self->{_idRsaFileName} = $idRsaKeyFile;
    $self->{_gitSSHClientFile} = $scriptContent;
    print "Files created: ID_RSA: ", $idRsaKeyFile->filename(), " SCRIPT: ", $scriptFile, "\n";

    $ENV{GIT_SSH} = $scriptFile;
    return;
}


#------------------------------------------------------------------------------
# Hook, if exists ECSCM will call it directly after runMethod.
# Args:
#   It will called with invoker method name as param
#------------------------------------------------------------------------------
sub afterRunMethod {
    my ($self, $method) = @_;

    $self->cleanupCredentials();
}


#------------------------------------------------------------------------------
# Hook, it performs cleanup
# Args:
#   It will called with invoker method name as param
#------------------------------------------------------------------------------
sub cleanupHandler {
    my ($self, $subroutine) = @_;

    $self->cleanupCredentials();
}

# Our wrapper for uri_escape. Does a little bit more - we've got an old version of the module
sub escape {
    my ($string) = @_;

    if (!string) {
        return '';
    }
    require URI::Escape;
    $string = URI::Escape::uri_escape($string);
    $string =~ s/@/\%40/;
    $string =~ s/\\/\%5C/;
    $string =~ s/!/\%21/g;
    # TODO : symbol?
    return $string;
}

sub getGitVersion {
    my ($self) = @_;

    my $cmdReturn = $self->RunCommand('git --version');
    my ($version) = $cmdReturn =~ m/git\sversion\s(.+)/;
    return $version;
}


sub compareVersions {
    my ($self, $first_str, $second_str) = @_;

    my $first = $self->parseVersion($first_str);
    my $second = $self->parseVersion($second_str);

    return
        $first->{major} <=> $second->{major}
        || $first->{minor} <=> $second->{minor}
        || $first->{revision} <=> $second->{revision}
        || $first->{build} <=> $second->{build};
}


sub parseGitLog {
    my ($logs) = @_;

    my @commits = ();
    my %commit = ();

    for my $line (split "\n", $logs) {
        # Get commit SHA1 (40 hex digits)
        if (my ($commit_hash) = $line =~ /^commit\s+(([a-f0-9]{40}))/) {
            # push previous commit to array
            if (%commit) {
                # Remove extra new line symbols at the start and at the end
                $commit{commitMessage} =~ s/^\n+//;
                $commit{commitMessage} =~ s/\n+$//;

                push(@commits, { %commit });
                %commit = ();
            }

            %commit = (
                commit => $commit_hash,
                files => {},
                files_list => [], # for keeping order
            );

            next;
        }

        # Get commit date
        if (my ($commit_date) = $line =~ /^Date:\s+(.*)/) {
            $commit{date} = $commit_date;
            next;
        }

        # Get author
        #TODO: make more robust
        if ($line =~ /^Author:\s+((.*) <(\S+@\S+)>)$/) {
            $commit{author} = $1;
            $commit{authorName} = $2;
            $commit{authorId} = $3;
            next;
        }

        # Skip merge lines
        if ($line =~ /^Merge:/) {
            next;
        }

        # Get commit message lines and summary
        if (!$line || $line =~ /^\ {4}/) {
            $commit{commitMessage} .= $line;
            $commit{commitMessage} .="\n";

            if (!$commit{summary}) {
                $commit{summary} = $line;
            }
            next;
        }

        # Get files info
        # JFI ((?:A|D|M|T|U|X|B)|(?:C|R)\d*)
        if ($line =~ /^(\S\d*)\s+(.*)/) {
            my $action   = $1;
            my $filePath = $2;
            $commit{'files'}->{$filePath} = {
                action => $action,
            };
            push(@{$commit{'files_list'}}, $filePath);
            next;
        }

        # Find unexpected lines
        print "WARNING: Unexpected line in git-log: \"$line\"";
    }

    # Remove extra new line symbols at the start and at the end
    $commit{commitMessage} =~ s/^\n+//;
    $commit{commitMessage} =~ s/\n+$//;

    # Push last commit
    push(@commits, { %commit });
    %commit = ();

    return @commits;
}


sub parseVersion {
    my ($self, $str) = @_;

    my ($major, $minor, $revision, $build) = $str =~ m/(\d+)\.(\d+)\.(\d+)(?:\.(\d))?/;

    return {
        major => $major + 0,
        minor => $minor + 0,
        revision => $revision + 0,
        build => $build ? $build + 0 :  0,
    }
}

sub logger {
    my ($self) = @_;

    return $self->{logger};
}

sub debug {
    my ($self, @params) = @_;

    return $self->logger->debug(@params);
}

sub set_summary {
    my ($self, @msg) = @_;

    my $path = '/myCall/summary';
    ElectricCommander->new()->setProperty($path => join('', @msg));
}


sub set_reporting_summary {
    my ($self, $reporting_result, $up_to_date) = @_;

    my $msg = '';
    if ($up_to_date) {
        $msg = "Up to date, nothing to sync.\n";
    }
    $msg .= "CodeCommit Payloads sent: " . $reporting_result->{codeCommit} . "\n";
    $msg .= "CodeCommitFile  Payloads sent: " . $reporting_result->{codeCommitFile} . "\n";
    $self->logger()->info($msg);
    $self->set_summary($msg);
}


sub get_metrics {
    my ($self, $params) = @_;

    my $last_id = '';
    my $file_prefix = '';
    my $opts = {};
    my $commits_count;
    if ($params->{opts}) {
        $opts = $params->{opts};
    }
    if ($opts->{commit}) {
        $params->{last_id} = $opts->{commit};
    }
    if ($params->{last_id}) {
        $last_id = "HEAD^..$params->{last_id}";
    }
    if ($params->{file_prefix}) {
        $file_prefix = $params->{file_prefix};
    }
    if ($opts->{depth}) {
        $commits_count = " --max-count=$opts->{depth} ";
    }
    my @commits = ();
    my %commit = ();

    # TODO add timezone
    # my $cmd = qq{git log $last_id $commits_count  --numstat --date=format:%FT%T.000Z --summary --shortstat };
    my $cmd = qq{git log $last_id $commits_count --numstat --date=iso8601 --summary --shortstat};
    print "Retrieving metrics using following command:\n$cmd\n";
    my $replacements = {};
    my @logResult = split /\n/, $self->RunCommand($cmd, {LogCommand=>0, Replacements => $replacements});
    if ($? ne '0') {
        $self->logger()->info("Error occured during git log.");
        exit 1;
    }
    for my $line (@logResult) {
        # Get commit SHA1 (40 hex digits)
        if (my ($commit_hash) = $line =~ /^commit\s+(([a-f0-9]{40}))/) {
            # push previous commit to array
            if (%commit) {
                # Remove extra new line symbols at the start and at the end
                $commit{commitMessage} =~ s/^\n+//;
                $commit{commitMessage} =~ s/\n+$//;
                # Copy contents of hash
                if ($opts->{GitBranch}) {
                    $commit{scmRepoBranch} = $opts->{GitBranch};
                }
                if ($opts->{GitRepo}) {
                    $commit{scmUrl} = $opts->{GitRepo};
                    $commit{sourceUrl} = $opts->{GitRepo};
                }
                $commit{codeLinesUpdated} = $commit{codeLinesAdded} + $commit{codeLinesUpdated};
                push(@commits, { %commit });
                %commit = ();
            }

            %commit = (
                codeLinesAdded => 0,
                codeLinesRemoved => 0,
                codeLinesUpdated => 0,
                commitId => $commit_hash,
                files => [],
                filesAdded => 0,
                filesRemoved => 0,
                filesUpdated => 0,
            );

            next;
        }

        # Get commit date
        if (my ($commit_date) = $line =~ /^Date:\s+(.*)/) {
            $commit{commitDate} = $commit_date;
            next;
        }

        # Get author
        #TODO: make more robust
        if (my ($author, $authorId) = $line =~ /^Author:\s+(.*) (<\S+@\S+>)$/) {
            $commit{commitAuthor} = $author;
            $commit{commitAuthorId} = $authorId;
            next;
        }

        # Get commit message lines
        if (!$line || $line =~ /^\ {4}/) {
            $commit{commitMessage} .= $line;
            $commit{commitMessage} .="\n";
            next;
        }

        # Get files info
        # example line for regular text files:
        # 3       0       dsl/procedures/GetLastSonarMetrics/form.xml
        # example line for binary files:
        # -       -       share/logo.png
        # TODO in Perl 5.10+ rewrite with pattern reset grouping (?|...)
        if (my ($added, $removed, $binary1, $binary2, $filePath) = $line =~ /^(?:(\d+)\s+(\d+)|(?:(-)\s+(-)))\s+(.*)/) {
            if ($file_prefix) {
                my $reg = quotemeta($file_prefix);
                $reg = '^' . $reg;
                $filePath =~ s/$reg//s;
            }
            my $t = {
                codeLinesAdded => $added ? $added : 0,
                codeLinesRemoved => $removed ? $removed : 0,
                filePath => $filePath
            };
            $t->{codeLinesUpdated} = $t->{codeLinesAdded} + $t->{codeLinesRemoved};
            push(@{$commit{files}}, $t);
            next;
        }

        # Get summary stats
        # Examples:
        # 28 files changed, 887 insertions(+)
        # 1 file changed, 5 deletions(-)
        # 9 files changed, 13069 insertions(+), 34 deletions(-)
        if (my ($changed, $insertion, $deletion) = $line =~ /^ (\d+) files? changed(?:, (\d+) insertions?\(\+\))?(?:, (\d+) deletions?\(-\))?/) {
            $commit{filesUpdated} = $changed ? $changed : 0;
            $commit{codeLinesAdded} = $insertion ? $insertion : 0;
            $commit{codeLinesRemoved} = $deletion ? $deletion : 0;
            next;
        }

        # Get creation/deletion actions

        if (my ($action) = $line =~ /^ (create|delete) mode \d+ /) {
            if ($action eq "create") {
                $commit{filesAdded} += 1;
            }
            elsif ($action eq "delete") {
                $commit{filesRemoved} += 1;
            }
            next;
        }

        # Skip mode change
        if ($line =~ /^ mode change \d+ /) {
            next;
        }

        # Skip merge lines
        if ($line =~ /^Merge:/) {
            next;
        }

        # Find unexpected lines
        $self->logger()->warning("Unexpected line in git-log: \"$line\"");
    }

    ### TODO this is duplicate code
    # Remove extra new line symbols at the start and at the end
    $commit{commitMessage} =~ s/^\n+//;
    $commit{commitMessage} =~ s/\n+$//;

    # Push last commit
    push(@commits, { %commit });
    %commit = ();

    @commits = map {
        if ($opts->{GitBranch}) {
            $_->{scmRepoBranch} = $opts->{GitBranch};
        }
        if ($opts->{GitRepo}) {
            $_->{scmUrl} = $opts->{GitRepo};
            $_->{sourceUrl} = $opts->{GitRepo};
        }
        $_;
    } @commits;
    return @commits;
}


#*****************************************************************************

=item B<set_pipeline_summary>

Sets pipeline summary (only if the job step runs in a pipeline)

=cut

#-----------------------------------------------------------------------------
sub set_pipeline_summary {
    my ($self, $name, $message) = @_;

    if ($self->inPipeline) {
        eval { $self->ec->setProperty("/myPipelineStageRuntime/ec_summary/$name", $message);};
    }

    return;
}

1;

package EC::Plugin::Exception;

use strict;
use warnings;
use Data::Dumper;

sub new {
    my ($class, %params) = @_;

    my $self = {};

    for my $k (keys %params) {
        $self->{$k} = $params{$k};
    }
    # if ($params{message}) {
    #     $self->{message} = $params{message};
    # }
    bless $self, $class;
    return $self;
}


sub throw {
    my ($self, $message) = @_;
    die $self;
}


sub toString {
    my ($self) = @_;

    my $retval;
    for my $k (keys %$self) {
        $retval .= "$k: $self->{$k}\n";
    }
    return $retval;
}


sub message {
    my ($self, @msg) = @_;

    if (@msg) {
        $self->{message} = join '', @msg;
    }
    return $self->{message};
}

package EC::Plugin::Logger;

use strict;
use warnings;
use Data::Dumper;

use constant {
    ERROR => -1,
    INFO => 0,
    DEBUG => 1,
    TRACE => 2,
};

sub new {
    my ($class, $level) = @_;
    $level ||= 0;
    my $self = {level => $level};
    return bless $self,$class;
}

sub warning {
    my ($self, @messages) = @_;

    $self->log(INFO, 'WARNING: ', @messages);
}

sub info {
    my ($self, @messages) = @_;
    $self->log(INFO, @messages);
}

sub debug {
    my ($self, @messages) = @_;
    $self->log(DEBUG, '[DEBUG]', @messages);
}

sub error {
    my ($self, @messages) = @_;
    $self->log(ERROR, '[ERROR]', @messages);
}

sub trace {
    my ($self, @messages) = @_;
    $self->log(TRACE, '[TRACE]', @messages);
}

sub log {
    my ($self, $level, @messages) = @_;

    binmode STDOUT, ':encoding(UTF-8)';

    return if $level > $self->{level};
    my @lines = ();
    for my $message (@messages) {
        unless(defined $message) {
            $message = 'undef';
        }
        if (ref $message) {
            print Dumper($message);
        }
        else {
            print "$message";
        }
    }
    print "\n";
    return 1;
}

1;


package EC::Mapper;

use strict;
use warnings;
use Carp;
use Data::Dumper;


sub new {
    my ($class, %params) = @_;

    my $self = {};
    bless $self, $class;
    if ($params{transform}) {
        $self->{_transform} = $params{transform};
        my $error = $self->_load_transform();
        if ($error) {
            croak "Can't load transform script:\n$error";
        }
    }
    if ($params{mappings}) {
        $self->{_mappings} = $params{mappings};
    }

    return $self;
}


sub _load_transform {
    my ($self) = @_;
    no warnings 'redefine';
    $self->{_transform} = "package EC::Mapper::Transformer;\n" .
        q|sub transform {my ($payload) = @_; return $payload}| . "\n" .
        q|no warnings 'redefine';| .
        $self->{_transform} .
        "1;\n";


    eval $self->{_transform};
    if ($@) {
        return $@;
    }
    my $transformer = {};
    $self->{transformer} = bless $transformer, "EC::Mapper::Transformer";
    return '';
}

sub transform {
    my ($self, $payload) = @_;

    return $self->{transformer}->transform($payload);
}
sub parse_mapping {
    my ($self, $struct) = @_;

    # remove last comma to make it working.
    $struct =~ s/,\s*$//s;
    my $map = $self->{_mappings};
    return {} unless $map;
    my $retval;

    # remove comments
    $map =~ s/^\s*#.*?$//gms;
    my @map = map {s/\s+$//gs;s/^\s+//gs;$_} split ',', $map;

    # remove empty records
    @map = grep {$_} @map;

    for my $m (@map) {
        my ($request, $response) = split ':', $m;

        # trim records to allow records with spaces around colon (one : two)
        $request =~ s/^\s+//gs;
        $request =~ s/\s+$//gs;
        $response =~ s/^\s+//gs;
        $response =~ s/\s+$//gs;

        my @response = split '\.', $response;

        if ($request =~ m/"(.*?)"/) {
            if (scalar @response > 1) {
                $retval->{$response[0]}->{$response[1]} = $1;
            }
            else {
                $retval->{$response} = $1;
            }
            next;
        }
        my $accessor = [];
        my @path = split '\.', $request;
        for my $p (@path) {
            if ($p !~ m/\[/s) {
                push @$accessor, {'HASH', $p};
            }
            else {
                $p =~ m/(.*?)\[(.*?)\]/s;
                push @$accessor, {'HASH', $1};
                push @$accessor, {'ARRAY', $2};
            }
        }
        my $value = '';

        my $t = $struct;
        for my $acc (@$accessor) {
            if (!$t) {
                $t = undef;
                last;
            }
            if ($acc->{HASH}) {
                $t = $t->{$acc->{HASH}};
            }
            else {
                $t = $t->[$acc->{ARRAY}];
            }
        }
        if (defined $t) {
            if (scalar @response > 1) {
                $retval->{$response[0]}->{$response[1]} = $t;
            }
            else {
                $retval->{$response} = $t;
            }
        }
    }
    return $retval;
}

1;


package EC::Reporting::Payloads;
use strict;
use warnings;
use Carp;

our $VERSION = 0.02;
our $ALLOWED_REPORT_OBJECT_TYPES =[
    'quality',
    'build',
    'incident',
    'feature',
    'code_quality',
    'code_quality_file'
];

sub new {
    my ($class, $params) = @_;

    my $self = {
        config => {},
    };
    for my $p (qw/source pluginName pluginConfiguration/) {
        if (!$params->{$p}) {
            croak "Missing param $p\n";
        }
        $self->{config}->{$p} = $params->{$p};
    }
    bless $self, $class;
    return $self;
}


sub getStructure {
    my ($self, $type) = @_;

    my $structure = {
        # common fields for reporting.
        source              => $self->{config}->{source},
        pluginName          => $self->{config}->{pluginName},
        pluginConfiguration => $self->{config}->{pluginConfiguration},
    };

    if ($type eq 'incident') {
        my @list = qw/reportType sourceUrl incidentId category subCategory configurationItem priority status reportedBy createdOn modifiedOn timestamp/;
        for my $field (@list) {
            $structure->{$field} = '';
        }
        $structure->{reportType} = 'incident';
    }
    elsif ($type eq 'code_quality') {
        my @list = (
            'pluginConfiguration',
            'pluginName',
            'source',
            'sourceUrl',
            'buildNumber',
            'commitId',
            'duration',
            'runId',
            'applicationName',
            'applicationProjectName',
            'pipelineName',
            'pipelineProjectName',
            'flowRuntimeName',
            'pipelineStageName',
            'baseDrilldownUrl',
            'bugs',
            'classComplexity',
            'classes',
            'codeSmells',
            'functionComplexity',
            'violations',
            'vulnerabilities',
        );
        for my $field (@list) {
            $structure->{$field} = '';
        }
        $structure->{reportType} = 'code_quality';
    }
    elsif ($type eq 'code_quality_file') {
        my @list = (
            'pluginConfiguration',
            'pluginName',
            'source',
            'sourceUrl',
            'buildNumber',
            'commitId',
            'runId',
            'filePath',
            'linesOfCode',

            # for sonarqube
            'bugs',
            'complexity',
            'codeSmells',
            'violations',
            'vulnerabilities'
        );
        for my $field (@list) {
            $structure->{$field} = '';
        }
        $structure->{reportType} = 'code_quality_file';
    }
    else {
        croak "Unknown report type: $type\n";
    }
    return $structure;
}


# params
# allowNewFields => 1|0
# allowEmptyFields => 1|0
sub buildPayload {
    my ($self, $type, $hash, $params) = @_;

    my $structure = $self->getStructure($type);
    # now we have a structure.

    for my $key (keys %$hash) {
        # need to check do we allow new fields in payload
        if (!$params->{allowNewFields} && !defined $structure->{$key}) {
            croak "No field $key in payload found while no new fields are allowed.";
        }
        $structure->{$key} = $hash->{$key};
    }
    # check for empty fields. If empty fields are not allowed, these fields should be removed.
    unless ($params->{allowEmptyFields}) {
        for my $field (keys %$structure) {
            if ($structure->{$field} eq '') {
                delete $structure->{$field};
            }
        }
    }

    return $structure;
}


# Return DateTime object with original timezone
sub dateToTimestamp {
    my ($self, $date) = @_;
    my ($year, $month, $day, $hour, $min, $sec, $tz) = $date =~ /(\d{4})-(\d{2})-(\d{2}).(\d{2}):(\d{2}):(\d{2})\s([\+\-\d:]+)/;
    return DateTime->new(
        year => $year,
        month => $month,
        day => $day,
        hour => $hour,
        minute => $min,
        second => $sec,
        time_zone => $tz,
    );
}

1;


package EC::ReportingCore;
use strict;
use warnings;
use Carp;
use Data::Dumper;
use JSON;
use DateTime;


sub sr {
    my ($self) = @_;

    return $self->{silent_reporting};
}


sub new {
    my ($class, $ec, $params) = @_;

    if (!$params->{pluginName}) {
        croak "Missing pluginName parameter.";
    }
    if (!$params->{source}) {
        croak "Missing source parameter.";
    }
    if (!$params->{pluginConfiguration}) {
        croak "Missing pluginConfiguration parameter.";
    }
    my $self = {
        ec => $ec,
        silent_reporting => 0
    };
    $self->{pluginName} = $params->{pluginName};
    $self->{source} = $params->{source};
    $self->{pluginConfiguration} = $params->{source};

    if ($params->{transform} || $params->{mappings}) {
        # ($self->{mappings}, $self->{transform}) = ($params->{mappings}, $params->{transform});
        $self->{mappings} = $params->{mappings} || '';
        $self->{transform} = $params->{transform} || '';
        $self->{mapper} = EC::Mapper->new(
            mappings => $self->{mappings},
            transform => $self->{transform},
        );
    }

    bless $self, $class;
    return $self;
}

sub sendReportToEF {
    my ($self, $reportObjectType, $payload) = @_;

    for my $key (keys %$payload) {
        if (!defined $payload->{$key}) {
            # $payload->{$key} = '';
            delete $payload->{$key};
        }
        if (ref $payload->{$key} && ref $payload->{$key} !~ m/^(?:ARRAY|HASH$)/s) {
            $payload->{$key} .= '';
        }
    }
    my $retval = {
        ok => 1,
        message => '',
    };
    my $ec = $self->{ec};
    my $json = encode_json($payload);
    unless ($self->sr()) {
        print "Sending JSON payload: $json\n";
    }
    # silent mode.
    else {
        print "Sending $reportObjectType json payload in Silent Mode.\n";
    }
    my $xpath = $ec->sendReportingData({
        payload => $json,
        reportObjectTypeName => $reportObjectType
    });

    my $error_code = $xpath->findvalue('//error/code')->string_value();
    if ($error_code) {
        $retval->{ok} = 0;
        $retval->{message} = $error_code;
    }
    return $retval;
}

sub buildMappings {
    my ($self, $struct) = @_;

    my $mapping = {};
    if ($self->{mapper} && $self->{mappings}) {
        $mapping = $self->{mapper}->parse_mapping($struct);
    }
    return $mapping;
}


sub doTransform {
    my ($self, $struct) = @_;

    if ($self->{mapper} && $self->{transform}) {
        $struct = $self->{mapper}->transform($struct);
    }
    return $struct;
}


sub getPayload {
    my ($self, $reportType, $data, $params) = @_;

    my $payloads = $self->getPayloadsEngine;
    my $payload = $payloads->buildPayload(
        $reportType, $data, $params
    );
    return $payload;
}


sub getPayloadsEngine {
    my ($self) = @_;

    unless($self->{payloads}) {
        my $payloads = EC::Reporting::Payloads->new({
            source => $self->{source},
            pluginName => $self->{pluginName},
            pluginConfiguration => $self->{pluginConfiguration}
        });
        $self->{payloads} = $payloads;
    }
    return $self->{payloads};
}


sub setMetadata {
    my ($self, $metadataPath, $value) = @_;
    print "Setting metadata: ($metadataPath)", Dumper $value;
    $self->{ec}->setProperty($metadataPath, encode_json($value));
}


sub getMetadata {
    my ($self, $metadata_property_path) = @_;

    my $metadata = undef;

    eval {
        $metadata = $self->{ec}->getProperty($metadata_property_path)->findvalue('//value')->string_value();
        if ($metadata) {
            $metadata = decode_json($metadata);
        }
        1;
    };
    return $metadata;
}

sub getRunContext {
    my ($self) = @_;

    my $ec = $self->{ec};
    my $context = 'pipeline';
    my $flowRuntimeId = '';

    eval {
        $flowRuntimeId = $ec->getProperty('/myFlowRuntimeState/id')->findvalue('//value')->string_value;
    };
    return $context if $flowRuntimeId;

    eval {
        $flowRuntimeId = $ec->getProperty('/myFlowRuntime/id')->findvalue('/value')->string_value();
    };
    return $context if $flowRuntimeId;

    eval {
        $flowRuntimeId = $ec->getProperty('/myPipelineStageRuntime/id')->findvalue('/value')->string_value();
    };
    return $context if $flowRuntimeId;

    $context = 'schedule';
    my $scheduleName = '';
    eval {
        $scheduleName = $self->getScheduleName();
        1;
    } or do {
        print "error occured: $@\n";
    };

    if ($scheduleName) {
        return $context;
    }
    $context = 'procedure';
    return $context;
}

# OLD
sub getRunContext2 {
    my ($self) = @_;

    my $ec = $self->{ec};
    my $context = 'pipeline';

    eval {
        my $flowRuntimeId = $ec->getProperty('/flowRuntime/id')->findvalue('/value')->string_value();
        return $context if $flowRuntimeId;
    };

    $context = 'schedule';
    my $scheduleName = '';
    eval {
        $scheduleName = $self->getScheduleName();
        1;
    } or do {
        print "error occured: $@\n";
    };

    if ($scheduleName) {
        return $context;
    }
    $context = 'procedure';
    return $context;
}


sub getProjectName {
    my ($self, $jobId) = @_;

    $jobId ||= $ENV{COMMANDER_JOBID};

    my $projectName = '';
    eval {
        my $result = $self->{ec}->getJobDetails($jobId);
        $projectName = $result->findvalue('//job/projectName')->string_value();
        1;
    } or do {
        print "error occured: $@\n";
    };

    return $projectName;
}


sub getScheduleName {
    my ($self, $jobId) = @_;

    $jobId ||= $ENV{COMMANDER_JOBID};

    my $scheduleName = '';
    eval {
        my $result = $self->{ec}->getJobDetails($jobId);
        $scheduleName = $result->findvalue('//scheduleName')->string_value();
        print "Schedule found: $scheduleName\n";
        1;
    } or do {
        print "error occured: $@\n";
    };

    return $scheduleName;
}


sub buildMetadataLocation {
    my ($self, $jobName, $reportingType) = @_;

    my $context = $self->getRunContext();
    print "Context found: $context\n";
    my $location = '';
    my $projectName = $self->getProjectName();

    if ($context eq 'schedule') {
        my $scheduleName = $self->getScheduleName();
        $location = "/projects/$projectName/schedules/$scheduleName/ecreport_data_tracker";
    }
    else {
        $location = "/projects/$projectName/ecreport_data_tracker";
    }

    my $propertyName = $self->{pluginName} . '-' . $jobName . '-' . $reportingType;
    $location .= '/' . $propertyName;
    return $location;
}



sub validateAndConvert {
    my ($self, $report_object_type, $payload) = @_;

    my $types = $self->get_report_payload_types($report_object_type);
    my $retval = {};

    for my $field_name (keys %$types) {
        my $type = $types->{$field_name}->{type};
        my $required = $types->{$field_name}->{required};

        if  ($required && !defined $payload->{$field_name}) {
            print "Payload does not contain required field $field_name, skipping: " . JSON->new->pretty->encode($payload);
            $retval->{skip} = 1;
        }

        next if $retval->{skip};
        my $value = $payload->{$field_name};
        next unless defined $value;
        if ($type =~ /number|duration|percent/i ) {
            unless($value =~ /^\d+(\.\d+)?$/) {
                die "Non-numeric value $value found for field $field_name in payload " . Dumper($payload);
            }
            $payload->{$field_name} += 0;
        }
        elsif ($type eq 'BOOLEAN') {
            $payload->{$field_name} = $value ? \1 : \0;
        }
        elsif ($type =~ /^(DATE|DATETIME)$/) {
            #TODO: review this checks, add unit-tests
            #TODO: when Git 2.7+ will be minimal supported version
            # In Git 2.7 we can convert date to UTC with introduced "-local" date format
            # and env variables TZ or LC_TIME
            # like "TZ=UTC git log --date=format-local:%FT%T.000Z"
            my $date = $self->getPayloadsEngine->dateToTimestamp($value);
            $date = $date->set_time_zone('UTC');
            $payload->{$field_name} = $date->datetime() . 'Z';
        }
        elsif ($type eq 'STRING') {
            if ($value eq '') {
                #TODO: use logger instead
                print "Skip empty parameter $field_name\n";
                delete $payload->{$field_name};
            }
        }
        else {
            die "Unknown type: $type for $field_name";
        }
    }
    return $retval;

}


sub get_report_payload_types {
    my ($self, $report_object_type) = @_;

    unless($self->{types}->{$report_object_type}) {
        my $xpath = $self->{ec}->getReportObjectAttributes($report_object_type);
        for my $node ($xpath->findnodes('//reportObjectAttribute')) {
            my $attribute_name = $node->findvalue('reportObjectAttributeName')->string_value;
            my $data_type = $node->findvalue('type')->string_value;
            my $required = $node->findvalue('required')->string_value + 0;

            $self->{types}->{$report_object_type}->{$attribute_name}->{type} = $data_type;
            $self->{types}->{$report_object_type}->{$attribute_name}->{required} = $required;
        }
    }
    return $self->{types}->{$report_object_type};
}


1;
