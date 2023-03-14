####################################################################
#
# ECSCM::Git::Cfg: Object definition of a perforce SCM configuration.
#
####################################################################
package ECSCM::Git::Cfg;
@ISA = (ECSCM::Base::Cfg);
if (!defined ECSCM::Base::Cfg) {
    require ECSCM::Base::Cfg;
}

####################################################################
# Object constructor for ECSCM::Git::Cfg
#
# Inputs
#   cmdr  = a previously initialized ElectricCommander handle
#   name  = a name for this configuration
####################################################################
sub new {
    my $class = shift;

    my $cmdr = shift;
    my $name = shift;

    my($self) = ECSCM::Base::Cfg->new($cmdr,"$name");
    bless ($self, $class);
    return $self;
}


####################################################################
# gitRepo
####################################################################
sub getGitRepo {
    my ($self) = @_;
    return $self->get("GitRepo");
}
sub setGitRepo {
    my ($self, $name) = @_;
    print "Setting GitRepo to $name\n";
    return $self->set("GitRepo", "$name");
}



####################################################################
# Credential
####################################################################
sub getCredential {
    my ($self) = @_;
    return $self->get("Credential");
}
sub setCredential {
    my ($self, $name) = @_;
    print "Setting Credential to $name\n";
    return $self->set("Credential", "$name");
}


1;
